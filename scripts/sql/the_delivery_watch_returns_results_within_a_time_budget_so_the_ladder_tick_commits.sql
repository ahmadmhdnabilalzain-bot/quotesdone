-- THE DELIVERY WATCH RETURNS ITS RESULTS WITHIN A TIME BUDGET, SO THE LADDER TICK COMMITS AGAIN (27 Oct 2026).
-- apply-window: any (CREATE OR REPLACE of one routine; no table lock)
--
-- Assigned: customer_support (the delivery loop: every delivery.request gets its delivery.result back to whoever
-- asked). The routine's previous file was the it_engineer's timeout fix of 19 Oct; the loop itself is this seat's.
--
-- ══ MEASURED, 27 Oct 2026 18:30-18:50 UTC, htdblwldjkcgjvmqkbeh, read-only and rolled-back transactions ══════════
--   * The last delivery.request handoff that carries a loop verdict was written 19 Oct 14:01 UTC. delivery.result
--     handoffs per day: 16 Oct 2, 17 Oct 4, 19 Oct 870, then 0 every day since. 771 done/failed delivery.request
--     rows wait for their result (the watch's own candidate query).
--   * fn_customer_support_delivery_watch(null), the call resilience_ping makes through fn_refund_ladder_sweep over
--     PostgREST (statement_timeout 8 s): 15,464 ms for its batch of 50 (results_returned 50), about 300 ms a result.
--     So every `ladder` tick since 19 Oct has been cancelled at 8 s and ROLLED BACK whole: no result ever commits,
--     the same shape the 19 Oct file (the_backup_prune_and_the_delivery_watch_finish_under_the_api_timeout.sql)
--     fixed with LIMIT 50 when a result was cheap. fn_ceo_refund_loop_sweep, the sweep's other call, takes 9 ms.
--   * Downstream, measured the same hour: fn_it_duties (DELIVERY CONFIRMATION) raises a finding for every request
--     older than 2 h with no loop verdict: 176 duty:delivery:request:* findings opened in the last 20 h (118 of the
--     requests are the 27 Oct invite_m365_seed sends), each an it.finding handoff to customer_support. 178 of those
--     sit past their 4 h reply window unescalated, which is the red it_engineer_loop_is_closed test; see the PR.
--
-- ══ WHAT THIS CHANGES ═══════════════════════════════════════════════════════════════════════════════════════════
--   The walk (p_request_id null) stops 3 s after it began, by its own clock, and counts the rest as
--   left_for_next_tick; what it returned within the budget commits with the tick. 3 s leaves the rest of the
--   8 s for fn_refund_ladder_sweep's ladder steps and the CEO loop sweep. At ~300 ms a result that is ~10 results a
--   tick, and the backlog drains a tick at a time instead of never. A call for one request (p_request_id given) is
--   not budgeted: it is one row. Nothing else in the body changes; LIMIT 50 stays as the upper bound.
--
-- WHAT IT DOES NOT DO. It does not make a result cheaper (ponytail: if results arrive faster than the budget
-- returns them, make fn_seat_handoff / the delivery.result trigger cheaper rather than raising the budget), and it
-- does not touch fn_it_duties or the reverify escalation budget.
--
-- Body: the MANIFEST-last one (the_backup_prune_and_the_delivery_watch_finish_under_the_api_timeout.sql, line 2048;
-- the canonical engine reads 0 drift, so it is production's) with the budget only. CREATE OR REPLACE keeps the live
-- ACL (revoked from public, anon, authenticated in that file), so no revoke here.
-- Prevented by: scripts/checks/backup_prune_and_delivery_watch_stay_under_the_api_timeout.test.mjs ('the delivery
-- watch walk stops on a clock budget').
-- Pending: scripts/sql/pending/the_delivery_watch_returns_results_within_a_time_budget_so_the_ladder_tick_commits.txt

create or replace function public.fn_customer_support_delivery_watch(p_request_id bigint default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  q record; n public.notifications; tx public.transactions; sup record; v_since timestamptz;
  v_reply jsonb; v_result text; v_evidence jsonb; v_retries int; v_nid bigint; v_done int := 0; v_waiting int := 0; v_retried int := 0;
  v_overdue int := 0; v_rep jsonb; v_failed int := 0;
  -- 27 Oct 2026: the walk (p_request_id null) stops 3 s after it began; the rest waits for the next tick (header).
  v_until timestamptz := clock_timestamp() + interval '3 seconds'; v_left int := 0;
begin
  for q in
    select a.* from public.agent_actions a
     where a.kind = 'handoff' and a.agent = 'customer_support' and a.status in ('done', 'failed')
       and a.detail->>'type' = 'delivery.request'
       and (a.detail->>'result_handoff_id') is null
       and (p_request_id is null or a.id = p_request_id)
     order by a.id
     limit case when p_request_id is null then 50 else 1 end
  loop
    if p_request_id is null and clock_timestamp() > v_until then v_left := v_left + 1; continue; end if;
    v_nid := coalesce((q.detail->>'retry_notification_id')::bigint, (q.evidence->>'notification_id')::bigint);
    n := null;
    select * into n from public.notifications where id = v_nid;

    -- NOT TERMINAL IN TIME IS A FINDING, whatever else is true of the request.
    if n.id is not null and n.status in ('pending', 'queued') and n.created_at < now() - interval '24 hours'
       and (q.detail->>'overdue_report_id') is null then
      v_rep := public.fn_support_report_to_ceo(
        'delivery_overdue:' || q.id, 'elevated',
        'A ' || coalesce(q.detail->>'msg_type', 'notice') || ' for the ' || coalesce(n.to_role, 'recipient') || ' has not left the outbox in 24 hours',
        jsonb_build_object('request_id', q.id, 'asked_by', q.detail->>'from', 'notification_id', n.id, 'status', n.status,
                           'queued_at', n.created_at, 'attempts', n.attempts, 'last_error', n.last_error),
        jsonb_build_array('queued by customer_support', 'watched every heartbeat since'),
        'Find why the outbox is not draining this row (dispatcher down, sending disabled, cap) and get it out, or tell the asking seat it will not go.',
        'agent_actions#' || q.id);
      update public.agent_actions set detail = detail || jsonb_build_object('overdue_report_id', v_rep->'report_id') where id = q.id;
      v_overdue := v_overdue + 1;
    end if;

    if q.status = 'done' and (q.detail->>'watch_until') is not null then
      -- ── the watched path, carried over unchanged ──
      select * into tx from public.transactions where id = (q.detail->>'transaction_id')::uuid;
      select l.id, lower(coalesce(l.claimed_by, l.email)) as email,
             regexp_replace(coalesce(nullif(btrim(l.whatsapp), ''), l.phone_e164, l.phone, ''), '[^0-9]', '', 'g') as phone
        into sup from public.leads l where l.id = (q.detail->>'supplier_id')::bigint;
      v_since := coalesce(tx.revealed_at, q.created_at);
      v_retries := coalesce((q.detail->>'retries')::int, 0);

      -- ANY CHANNEL, EVERY TIME. The first thing that came back wins.
      select jsonb_build_object('channel', ch, 'at', at, 'ref', ref) into v_reply from (
        select 'portal' ch, m.created_at at, 'messages#' || m.id ref from public.messages m
         where tx.id is not null and m.inquiry_id = tx.inquiry_id and m.supplier_id = tx.supplier_id
           and m.sender = 'supplier' and coalesce(m.blocked, false) = false and m.created_at > v_since
        union all
        select 'supplier_ack', tx.supplier_ack_at, 'transactions.supplier_ack_at' where tx.supplier_ack_at > v_since
        union all
        select coalesce(w.response_channel, 'recorded'), w.first_response_at, coalesce(w.response_ref, 'supplier_response_watch#' || w.id)
          from public.supplier_response_watch w where tx.id is not null and w.transaction_id = tx.id and w.first_response_at > v_since
        union all
        select 'email', im.created_at, 'inbound_messages#' || im.id from public.inbound_messages im
         where sup.email is not null and lower(im.from_email) = sup.email and im.created_at > v_since
        union all
        select 'whatsapp', wm.created_at, 'wa_messages#' || wm.id from public.wa_messages wm
         where length(coalesce(sup.phone, '')) >= 8 and regexp_replace(coalesce(wm.wa_from, ''), '[^0-9]', '', 'g') = sup.phone
           and wm.created_at > v_since
        order by 2 limit 1) z;

      if v_reply is not null and q.detail->>'recipient_role' = 'supplier' then
        v_result := 'proof_of_response';
        v_evidence := jsonb_build_object('reply', v_reply);
      elsif n.id is null or n.status in ('failed', 'bounced', 'error') then
        if v_retries < 1 and n.id is not null then
          perform set_config('app.qd_delivery_tracked', 'on', true);   -- the retry is tracked by this request (retry_notification_id)
          insert into public.notifications (type, kind, to_email, cc_emails, to_role, lead_id, inquiry_id, quote_id, channel, subject, body, status, requested_by)
          values (n.type, n.kind, n.to_email, n.cc_emails, n.to_role, n.lead_id, n.inquiry_id, n.quote_id, 'email', n.subject, n.body, 'queued', n.requested_by)
          returning id into v_nid;
          perform set_config('app.qd_delivery_tracked', 'off', true);
          update public.agent_actions
             set detail = detail || jsonb_build_object('retries', v_retries + 1, 'retry_notification_id', v_nid,
                                                       'first_failure', jsonb_build_object('notification_id', n.id, 'status', n.status, 'error', n.last_error))
           where id = q.id;
          perform public.fn_seat_handoff_event(q.id, 'retried');
          v_retried := v_retried + 1;
          continue;
        end if;
        v_result := 'no_response_confirmation';
        v_evidence := jsonb_build_object('delivered', false, 'retries', v_retries,
          'delivery', jsonb_build_object('notification_id', n.id, 'status', n.status, 'error', n.last_error),
          'first_failure', q.detail->'first_failure');
      elsif now() >= (q.detail->>'watch_until')::timestamptz then
        v_result := 'no_response_confirmation';
        v_evidence := jsonb_build_object('delivered', n.status = 'sent' or n.sent_at is not null,
          'delivery', jsonb_build_object('notification_id', n.id, 'status', n.status, 'sent_at', n.sent_at,
                                         'provider_message_id', n.provider_message_id, 'attempts', n.attempts),
          'whatsapp', (select coalesce(jsonb_agg(jsonb_build_object('notification_id', w.id, 'status', w.status, 'sent_at', w.sent_at,
                                                                    'provider_message_id', w.provider_message_id)), '[]'::jsonb)
                         from public.notifications w
                        where w.id in (select (x)::bigint from jsonb_array_elements_text(coalesce(q.evidence->'whatsapp_ids', '[]'::jsonb)) x)),
          'window_closed_at', q.detail->'watch_until',
          'channels_checked', jsonb_build_array('portal', 'supplier_ack', 'recorded_reply', 'email', 'whatsapp'));
      else
        v_waiting := v_waiting + 1;
        continue;
      end if;
    else
      -- ── every other request: one result when the send is terminal ──
      v_evidence := jsonb_build_object('notification', case when n.id is null then null else jsonb_build_object(
                      'id', n.id, 'status', n.status, 'channel', n.channel, 'to_role', n.to_role, 'sent_at', n.sent_at,
                      'provider_message_id', n.provider_message_id, 'attempts', n.attempts, 'last_error', n.last_error,
                      -- what Twilio reported, and its error in plain words (null for email)
                      'provider_status', n.provider_status, 'provider_error_code', n.provider_error_code,
                      'provider_error_explained', public.fn_twilio_error_in_plain_words(n.provider_error_code)) end,
                    'whatsapp', (select coalesce(jsonb_agg(jsonb_build_object('notification_id', w.id, 'status', w.status,
                                                   'provider_message_id', w.provider_message_id, 'provider_status', w.provider_status,
                                                   'provider_error_code', w.provider_error_code)), '[]'::jsonb)
                                   from public.notifications w
                                  where w.id in (select (x)::bigint from jsonb_array_elements_text(coalesce(q.evidence->'whatsapp_ids', '[]'::jsonb)) x)));
      if q.status = 'failed' then
        v_result := 'not_queued';
        v_evidence := v_evidence || jsonb_build_object('error', q.detail->>'error');
      elsif coalesce((q.evidence->>'stubbed')::boolean, false) then
        v_result := 'stubbed';
      elsif n.id is null and q.evidence ? 'notify' then
        v_result := 'routed';
        v_evidence := v_evidence || jsonb_build_object('notify', q.evidence->'notify');
      -- 22 SEP 2026 (it_engineer, UNSOLVED-06) — "NOTHING WAS QUEUED" WAS THREE DIFFERENT THINGS.
      -- MEASURED: support_ceo_report 3075, 3076, 3084 and 3085 each read 'A supplier_invite for the supplier
      -- did not arrive (not_sent)' with reason 'nothing was queued'. Their requests (agent_actions 42578,
      -- 42579, 42595, 42596) each carry evidence.queued = true and evidence.notification_id 36988/36989/
      -- 37002/37003, and NONE of those notification rows exists any more: every one addressed a
      -- zz-demo-supplier-invite-…@example.invalid fixture and the demo hygiene sweep deleted them between
      -- being queued at 19:11-19:15Z and the watch tick at 19:30Z on 21 Sep. So support DID queue the
      -- message; its record was removed afterwards. (The 22 Sep audit read these as invitations held by
      -- app_secrets.supplier_outreach_golive=false. They are not: the hold path
      -- (the_invitations_warm_up_on_measured_health_and_leave_across_the_working_day.sql) writes an
      -- invite_schedule row with status 'pending' and a supplier_invites agent_run, and asks for no
      -- delivery at all — so a held invitation never reaches this watch.)
      -- The three cases now answer differently, and only the first is a fault:
      --   nothing was ever queued and nothing explains it  -> 'not_sent'  (escalates, as before)
      --   the campaign is held by the founder's own switch  -> 'held'     (recorded, never escalated)
      --   the row it queued has since been deleted         -> 'record_removed'
      elsif n.id is null and coalesce(q.detail->>'msg_type', '') like '%invite%'
            and not public.fn_supplier_outreach_golive() then
        v_result := 'held';
        v_evidence := v_evidence || jsonb_build_object('reason',
          'the supplier campaign is held: app_secrets.supplier_outreach_golive is false, so no invitation is sent. This is the founder''s switch, not a delivery failure.');
      elsif n.id is null and coalesce((q.evidence->>'notification_id'), '') <> '' then
        v_result := 'record_removed';
        v_evidence := v_evidence || jsonb_build_object('reason',
          'the notification this request queued (id ' || (q.evidence->>'notification_id')
          || ') no longer exists, so its delivery cannot be read. A queued message whose row was deleted afterwards - the demo hygiene sweep does this to fixture rows - is not a message that was never sent.');
      elsif n.id is null then
        v_result := 'not_sent';
        v_evidence := v_evidence || jsonb_build_object('reason', coalesce(q.evidence->>'reason', 'nothing was queued'));
      elsif n.status = 'sent' and n.channel in ('whatsapp', 'sms') and coalesce(btrim(n.provider_message_id), '') <> '' then
        -- 22 SEP 2026: a Twilio SID proves only that Twilio ACCEPTED the message. Meta or the carrier can
        -- still refuse it, and that arrives later as a status report (wa_status). So a WhatsApp or SMS
        -- waits for delivered/read; a failure has already turned the row 'failed' (below); and a message
        -- with no final report 24 hours on is returned as unconfirmed rather than claimed as delivered.
        if n.provider_status in ('delivered', 'read') then
          v_result := 'delivered';
        elsif n.sent_at < now() - interval '24 hours' then
          v_result := 'sent_unconfirmed';
          v_evidence := v_evidence || jsonb_build_object('reason',
            'Twilio accepted it but reported no delivery within 24 hours: neither its status callback nor the backstop poll gave a final status');
        else
          v_waiting := v_waiting + 1;
          continue;
        end if;
      elsif n.status = 'sent' then
        v_result := case when coalesce(btrim(n.provider_message_id), '') <> '' then 'delivered' else 'sent_unconfirmed' end;
      elsif n.status in ('failed', 'bounced', 'error') then v_result := 'failed';
      elsif n.status in ('held', 'suppressed', 'skipped', 'cancelled') then v_result := n.status;
      elsif n.status = 'digest' then v_result := 'digested';
      else
        v_waiting := v_waiting + 1;
        continue;
      end if;
    end if;

    -- ONE RESULT, TO WHOEVER ASKED. A result the handoff register refuses must not stop the rest of the
    -- queue: it is recorded on the request and in the stream, and counted.
    -- The result is acted on at once, and the asking seat's close writes THIS request row (its loop,
    -- closed_by, the retry). So the handoff is sent first and its id written after, in a statement of
    -- its own: calling fn_seat_handoff inside the UPDATE of the same row failed with "tuple to be updated
    -- was already modified by an operation triggered by the current command" (measured 14 Sep 2026).
    begin
      update public.agent_actions set detail = detail || jsonb_build_object('result', v_result) where id = q.id;
      v_nid := public.fn_seat_handoff('customer_support', q.detail->>'from', 'delivery.result', 'agent_actions', q.id::text,
                 jsonb_build_object('request_id', q.id, 'result', v_result, 'evidence', v_evidence,
                                    'msg_type', q.detail->>'msg_type', 'recipient_role', q.detail->>'recipient_role',
                                    'retry_of', q.detail->'retry_of',
                                    'step', q.detail->>'step', 'refund_id', q.detail->>'refund_id',
                                    'transaction_id', q.detail->>'transaction_id', 'supplier_id', q.detail->>'supplier_id',
                                    'remediation_id', q.detail->>'remediation_id'));
      update public.agent_actions set detail = detail || jsonb_build_object('result_handoff_id', v_nid) where id = q.id;
      v_done := v_done + 1;
    exception when others then
      update public.agent_actions set detail = detail || jsonb_build_object('result_error', left(sqlerrm, 500)) where id = q.id;
      perform public.fn_seat_handoff_event(q.id, 'result_failed');
      v_failed := v_failed + 1;
    end;
  end loop;
  return jsonb_build_object('results_returned', v_done, 'still_watching', v_waiting, 'retried', v_retried,
                            'overdue_raised', v_overdue, 'results_failed', v_failed, 'left_for_next_tick', v_left);
end $fn$;
