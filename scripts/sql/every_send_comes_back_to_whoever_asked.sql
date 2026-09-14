-- EVERY SEND COMES BACK TO WHOEVER ASKED FOR IT.
--
-- Assigned: customer_support (the door, the carrying, the watch, the result). The originator's close
-- (fn_originator_checks_delivery) is each asking seat's own act: sales_engineer, accountant, ceo,
-- it_engineer, and customer_support for its own notices. 14 Sep 2026.
--
-- The founder, 14 Sep 2026 (public.founder_instruction #207, verbatim): "always make sure things are
-- in loop. nothing literally should ever be a one way communication".
--
-- MEASURED BEFORE WRITING (14 Sep 2026, production):
--   * fn_customer_support_delivery_watch picked up a delivery.request ONLY when detail->>'watch_until'
--     was set, and only those ever got a delivery.result back. Every other sales-engineer send was
--     one-way: reveal_receipt, quote_accepted, reveal_payment_incomplete, dues/registration paid,
--     refund_request_received, refund_issued, refund_declined, refund_in_progress, nonresponse_charge,
--     nonresponse_charge_correction, subscription_due, billing_answer, charge_dispute_answer
--     (fn_sales_engineer_acts_on_handoff) and refund_proof_request (fn_sales_engineer_ladder_step).
--   * A delivery.request whose handler RAISED was marked 'failed' and nothing ever looked at it again.
--   * fn_seat_handoff_act had handlers for sales_engineer, accountant and customer_support only, so a
--     result could not even be addressed to the ceo or the it_engineer.
--   * Edge functions wrote public.notifications directly, with no handoff at all: supplier_api
--     (new_quote, supplier_registered), customer_api (new_inquiry, job_awarded_other, rfq_addendum,
--     rfq_no_supplier), messages_api (new_message, clarification_requested, notifyMatched),
--     resend_inbound (expense_logged, supplier_doc_applied, doc_received), contact_submit
--     (contact_message), supplier_ack (supplier_ack), wa_templates_watch (wa_templates_ready) and
--     _shared/line_specs/workflow.ts (the spec-hold notices).
--   * 0 handoffs of any kind exist yet (pre-launch). The structure is the evidence, not a count.
--
-- WHAT THIS CHANGES:
--   door    fn_customer_support_takes_delivery(rows): the ONE way an edge function asks for a send.
--           Each row becomes a tracked delivery.request from the seat fn_channel_requester names for
--           its type, carried by customer_support. supabase/functions/_shared/deliver.ts calls it;
--           scripts/checks/every_send_comes_back_to_whoever_asked.test.mjs fails on any other insert.
--   watch   every delivery.request -- watched or not, queued or refused -- gets exactly one
--           delivery.result back to the seat that asked, once its notification is terminal. A
--           notification still not terminal 24 hours after it was queued is raised to the CEO.
--   close   the asking seat re-reads the notification itself (it does not take support's word), and
--           closes on proof: sent WITH a provider message id. Anything else makes it act: one retry on
--           the other channel, then an escalation to the CEO with the evidence.
--
-- DEFINED ELSEWHERE, ONCE: fn_seat_handoff_types (the delivery.request rows for it_engineer and
-- customer_support, a delivery.result row back to every asking seat) and fn_seat_handoff_act (every
-- delivery.result goes to fn_originator_checks_delivery in the seat addressed; the sales engineer still
-- attaches a ladder result first) are defined by scripts/sql/the_it_engineer_closes_every_loop_it_opens.sql
-- (PR #634), exactly as live on 14 Sep 2026, together with that build's it.finding conversations. Two
-- files redefining one routine means whichever applies last wipes the other's rows; one file owns each.
-- The TypeScript mirror (supabase/functions/_shared/payment_handoffs.ts) follows that file.
--
-- WHAT THIS DELIBERATELY DOES NOT CHANGE:
--   * fn_sales_engineer_acts_on_handoff, fn_sales_engineer_writes and fn_sales_engineer_ladder_step
--     (their live bodies belong to PR #628 and PR #629). None needs a line: the watch now covers what
--     they queue.
--   * The watched path (the refund ladder: proof_of_response / no_response_confirmation, the one email
--     retry) is carried over unchanged, and fn_sales_engineer_attaches_delivery_result still receives
--     exactly those results and no others.
--   * SQL routines that insert into public.notifications themselves (fn_notify_founder,
--     fn_supplier_notice, fn_wa_fanout and others; 24 at the time of writing) are NOT rerouted here.
--
--   node scripts/apply_sql.mjs scripts/sql/every_send_comes_back_to_whoever_asked.sql --apply --ddl

-- ── 2. SUPPORT CARRIES A REQUEST ─────────────────────────────────────────────────────────────────
-- Unchanged for the founder and for the sales engineer's composed words (the body of
-- customer_support_names_the_kind_when_it_reaches_the_founder.sql). Two additions:
--   * a PREPARED row (the edge door) is queued as written, under the seat that asked;
--   * the founder path records which founder_alert rows fn_notify_founder queued, so the watch can
--     report on them. Rows this transaction wrote carry created_at = now() (the transaction's own
--     timestamp); no other transaction's row can.
create or replace function public.fn_customer_support_acts_on_handoff(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  a public.agent_actions; d jsonb; v_ar boolean; v_subject text; v_body text; v_nid bigint; v_fan jsonb; v_cc text[]; v_res jsonb;
  p public.notifications; v_before bigint; v_from text;
begin
  select * into a from public.agent_actions where id = p_id;
  d := a.detail; v_from := d->>'from';
  if d->>'type' <> 'delivery.request' then raise exception 'customer_support has no handler for %', d->>'type'; end if;

  if d ? 'prepared' then
    p := jsonb_populate_record(null::public.notifications, d->'prepared');
    if p.to_role in ('customer', 'supplier') and v_from not in ('sales_engineer', 'customer_support') then
      raise exception 'only the sales engineer and support address customers and suppliers; % may address the founder only', v_from;
    end if;
    -- The caller chooses the words and the address. It never chooses the status, the sender or the
    -- requester: those are support's record of what it was asked and what it did.
    insert into public.notifications (type, kind, to_email, cc_emails, to_role, to_phone, lead_id, inquiry_id, quote_id,
                                      channel, subject, body, html, attachments, lang, status, requested_by)
    values (p.type, p.kind, p.to_email, coalesce(p.cc_emails, '{}'), p.to_role, p.to_phone, p.lead_id, p.inquiry_id, p.quote_id,
            coalesce(p.channel, 'email'), p.subject, p.body, p.html, p.attachments, p.lang, 'queued', v_from)
    returning id into v_nid;
    select coalesce(jsonb_agg(n.id), '[]'::jsonb) into v_fan from public.notifications n
     where n.channel = 'whatsapp' and n.id > v_nid and n.created_at = now() and n.type = p.type
       and n.to_email is not distinct from p.to_email;
    return jsonb_build_object('delivered', true, 'queued_at', now(), 'notification_id', v_nid, 'whatsapp_ids', v_fan,
                              'channel', coalesce(p.channel, 'email'), 'prepared', true);
  end if;

  if d->>'recipient_role' = 'founder' then
    -- A TEST NEVER REACHES HIM. The fixture ladder sets app.qd_stub_founder_notify; the probe also
    -- aborts its transaction, so even the queued rows are never committed.
    if coalesce(current_setting('app.qd_stub_founder_notify', true), '') = 'on' then
      return jsonb_build_object('channel', 'founder', 'stubbed', true, 'event', d->>'event');
    end if;
    select coalesce(max(id), 0) into v_before from public.notifications;
    v_res := public.fn_notify_founder(p_event => d->>'event', p_detail => d->>'detail', p_level => coalesce(d->>'level', 'high'),
                                      p_kind => d->>'kind', p_dedupe_key => d->>'dedupe_key', p_owner_agent => 'customer_support');
    select coalesce(jsonb_agg(n.id order by n.id), '[]'::jsonb) into v_fan from public.notifications n
     where n.id > v_before and n.type = 'founder_alert' and n.created_at = now();
    return jsonb_build_object('channel', 'founder', 'notify', v_res, 'notification_ids', v_fan,
                              'notification_id', v_fan->0);
  end if;

  if v_from <> 'sales_engineer' then
    raise exception 'only the sales engineer addresses customers and suppliers; % may address the founder only', v_from;
  end if;
  if coalesce(d->>'to_email', '') !~ '@' then
    return jsonb_build_object('delivered', false, 'reason', 'no email address on file for the ' || coalesce(d->>'recipient_role', 'recipient'));
  end if;

  v_ar := d->>'locale' = 'ar' and d->>'body_ar' is not null;
  v_subject := case when v_ar then coalesce(d->>'subject_ar', d->>'subject_en') else d->>'subject_en' end;
  v_body    := case when v_ar then d->>'body_ar' else d->>'body_en' end;
  select coalesce(array_agg(x), '{}') into v_cc from jsonb_array_elements_text(coalesce(d->'cc', '[]'::jsonb)) x;

  -- requested_by names the seat that asked (customer_support_is_the_only_sender_on_email_and_whatsapp.sql);
  -- sender stays customer_support by that file's default and check.
  insert into public.notifications (type, kind, to_email, cc_emails, to_role, lead_id, inquiry_id, quote_id, channel, subject, body, status, requested_by)
  values (d->>'msg_type', d->>'msg_type', d->>'to_email', v_cc, d->>'recipient_role',
          (d->>'supplier_id')::bigint, (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid, 'email', v_subject, v_body, 'queued',
          v_from)
  returning id into v_nid;
  select coalesce(jsonb_agg(n.id), '[]'::jsonb) into v_fan from public.notifications n
   where n.channel = 'whatsapp' and n.type = d->>'msg_type' and n.id > v_nid
     and n.to_email = d->>'to_email' and n.created_at >= now() - interval '1 minute';

  return jsonb_build_object('delivered', true, 'queued_at', now(), 'notification_id', v_nid, 'whatsapp_ids', v_fan,
                            'language', case when v_ar then 'ar' else 'en' end,
                            'watch_until', d->'watch_until', 'watching', (d->>'watch_until') is not null);
end $fn$;
revoke execute on function public.fn_customer_support_acts_on_handoff(bigint) from public, anon, authenticated;

-- ── 3. THE ONE DOOR FOR EDGE FUNCTIONS ───────────────────────────────────────────────────────────
-- Each row is a public.notifications row as the caller used to insert it. The asking seat is the row's
-- requested_by when given, otherwise the seat fn_channel_requester already names for that type (the
-- register the sender-of-record trigger reads), so no caller has to know the organisation chart.
-- A row may carry dedupe_key: a retry of the same request then returns the original handoff.
-- Returns one element per row: {handoff_id, seat, status, notification_id, error}.
create or replace function public.fn_customer_support_takes_delivery(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r jsonb; v_seat text; v_id bigint; h public.agent_actions; v_out jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(p_rows) is distinct from 'array' then
    raise exception 'fn_customer_support_takes_delivery takes an array of notification rows';
  end if;
  for r in select x from jsonb_array_elements(p_rows) x loop
    if coalesce(btrim(r->>'type'), '') = '' then raise exception 'a delivery request must name its type'; end if;
    v_seat := coalesce(nullif(btrim(r->>'requested_by'), ''), public.fn_channel_requester(r->>'type', r->>'kind'));
    if v_seat = 'platform' then
      raise exception 'a sign-in code (%) is sent by the platform OTP service, never queued through support', r->>'type';
    end if;
    v_id := public.fn_seat_handoff(v_seat, 'customer_support', 'delivery.request', 'notifications',
      coalesce(nullif(btrim(r->>'dedupe_key'), ''),
               (r->>'type') || ':' || coalesce(r->>'to_email', r->>'to_phone', r->>'to_role', 'nobody') || ':' || gen_random_uuid()::text),
      jsonb_build_object('prepared', r - 'dedupe_key' - 'requested_by' - 'status' - 'sender',
                         'msg_type', r->>'type', 'recipient_role', r->>'to_role', 'to_email', r->>'to_email',
                         'supplier_id', r->'lead_id', 'inquiry_id', r->'inquiry_id', 'quote_id', r->'quote_id'));
    select * into h from public.agent_actions where id = v_id;
    v_out := v_out || jsonb_build_array(jsonb_build_object('handoff_id', v_id, 'seat', v_seat, 'status', h.status,
      'notification_id', h.evidence->'notification_id', 'error', h.detail->>'error'));
  end loop;
  return v_out;
end $fn$;
revoke execute on function public.fn_customer_support_takes_delivery(jsonb) from public, anon, authenticated;

-- ── 4. THE WATCH: EVERY REQUEST COMES BACK ───────────────────────────────────────────────────────
-- A WATCHED delivery (the refund ladder) keeps its contract exactly: proof of response on any channel,
-- or the no-response confirmation when the window closes, with one email retry of a failed send.
-- EVERY OTHER delivery gets one result as soon as its notification is terminal:
--   delivered         sent, and the provider gave a message id
--   sent_unconfirmed  marked sent with no provider message id: nothing proves it left
--   failed | held | suppressed | skipped | cancelled | digested   the outbox's own word for it
--   not_sent          support queued nothing (no address on file)
--   not_queued        support's handler refused the request (the error is carried)
--   routed | stubbed  a founder notice founder_mail_policy routed elsewhere, or a test's stub
-- A notification still pending or queued 24 hours after it was queued is not a result; it is a finding,
-- raised to the CEO once. 24 hours is past send_outbox's own staleness hold and its daily-cap carry-over,
-- so only a queue nobody is draining reaches it.
create or replace function public.fn_customer_support_delivery_watch(p_request_id bigint default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  q record; n public.notifications; tx public.transactions; sup record; v_since timestamptz;
  v_reply jsonb; v_result text; v_evidence jsonb; v_retries int; v_nid bigint; v_done int := 0; v_waiting int := 0; v_retried int := 0;
  v_overdue int := 0; v_rep jsonb; v_failed int := 0;
begin
  for q in
    select a.* from public.agent_actions a
     where a.kind = 'handoff' and a.agent = 'customer_support' and a.status in ('done', 'failed')
       and a.detail->>'type' = 'delivery.request'
       and (a.detail->>'result_handoff_id') is null
       and (p_request_id is null or a.id = p_request_id)
     order by a.id
  loop
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
          insert into public.notifications (type, kind, to_email, cc_emails, to_role, lead_id, inquiry_id, quote_id, channel, subject, body, status, requested_by)
          values (n.type, n.kind, n.to_email, n.cc_emails, n.to_role, n.lead_id, n.inquiry_id, n.quote_id, 'email', n.subject, n.body, 'queued', n.requested_by)
          returning id into v_nid;
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
                      'provider_message_id', n.provider_message_id, 'attempts', n.attempts, 'last_error', n.last_error) end,
                    'whatsapp', (select coalesce(jsonb_agg(jsonb_build_object('notification_id', w.id, 'status', w.status,
                                                   'provider_message_id', w.provider_message_id)), '[]'::jsonb)
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
      elsif n.id is null then
        v_result := 'not_sent';
        v_evidence := v_evidence || jsonb_build_object('reason', coalesce(q.evidence->>'reason', 'nothing was queued'));
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
                            'overdue_raised', v_overdue, 'results_failed', v_failed);
end $fn$;
revoke execute on function public.fn_customer_support_delivery_watch(bigint) from public, anon, authenticated;

-- ── 5. THE ASKING SEAT CHECKS, THEN CLOSES OR ACTS ───────────────────────────────────────────────
-- Called by fn_seat_handoff_act for every delivery.result, in the seat it is addressed to. The seat
-- re-reads the notification itself rather than taking support's result on trust, and records what it
-- saw on the request (detail.loop / closed_by / closed_at / close_check).
--   proof of delivery (sent + provider id)          -> closed 'confirmed'
--   a ladder result (proof / no-response)           -> closed 'handled_by_the_ladder' (the CEO's loop owns it)
--   routed / stubbed / digested / cancelled         -> closed with that verdict
--   anything else, first time                       -> ONE retry on the other channel, when there is one
--   anything else after the retry, or no other way  -> escalated to the CEO with the evidence
create or replace function public.fn_originator_checks_delivery(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  a public.agent_actions; req public.agent_actions; n public.notifications; v_seat text; v_result text; v_seen jsonb;
  v_verdict text; v_phone text; v_email text; v_channel text; v_retry bigint; v_rep jsonb; v_origin bigint;
begin
  select * into a from public.agent_actions where id = p_id;
  v_seat := a.agent; v_result := a.detail->>'result';
  select * into req from public.agent_actions where id = (a.detail->>'request_id')::bigint;
  if req.id is null then return jsonb_build_object('closed', false, 'reason', 'the request this result answers is gone'); end if;

  select * into n from public.notifications
   where id = coalesce((req.detail->>'retry_notification_id')::bigint, (req.evidence->>'notification_id')::bigint);
  v_seen := jsonb_build_object('notification_id', n.id, 'status', n.status, 'channel', n.channel,
                               'provider_message_id', n.provider_message_id, 'sent_at', n.sent_at, 'checked_at', now());

  if v_result in ('proof_of_response', 'no_response_confirmation') then
    v_verdict := 'handled_by_the_ladder';
  elsif v_result = 'delivered' and n.status = 'sent' and coalesce(btrim(n.provider_message_id), '') <> '' then
    v_verdict := 'confirmed';
  elsif v_result in ('routed', 'stubbed', 'digested', 'cancelled') then
    v_verdict := v_result;
  end if;

  if v_verdict is null and v_result not in ('not_queued', 'sent_unconfirmed') and req.detail->'retry_of' is null
     and coalesce(req.detail->>'recipient_role', n.to_role) in ('customer', 'supplier') then
    -- THE OTHER CHANNEL, ONCE. Email that did not arrive goes to the number on file; WhatsApp that did
    -- not arrive goes to the address. A refused request (not_queued) is a defect, not a channel
    -- problem, and a send that may have left (sent_unconfirmed) is never sent twice: both escalate.
    v_email := coalesce(n.to_email, req.detail->>'to_email');
    if coalesce(n.channel, req.detail->'prepared'->>'channel', 'email') = 'whatsapp' then
      if coalesce(v_email, '') ~ '@' then v_channel := 'email'; end if;
    else
      select coalesce(nullif(btrim(l.whatsapp), ''), l.phone_e164, l.phone) into v_phone
        from public.leads l where l.id = coalesce((req.detail->>'supplier_id')::bigint, n.lead_id);
      if v_phone is null and coalesce(req.detail->>'recipient_role', n.to_role) = 'customer' and v_email is not null then
        select c.phone into v_phone from public.customers c where lower(c.email) = lower(v_email) limit 1;
      end if;
      if length(regexp_replace(coalesce(v_phone, ''), '[^0-9]', '', 'g')) >= 8 then v_channel := 'whatsapp'; end if;
    end if;
    if v_channel is not null and n.id is not null then
      v_retry := public.fn_seat_handoff(v_seat, 'customer_support', 'delivery.request', 'notifications', 'retry:' || req.id,
        jsonb_build_object('retry_of', req.id, 'msg_type', n.type, 'recipient_role', coalesce(n.to_role, req.detail->>'recipient_role'),
                           'to_email', v_email, 'supplier_id', coalesce(req.detail->'supplier_id', to_jsonb(n.lead_id)),
                           'inquiry_id', n.inquiry_id, 'quote_id', n.quote_id,
                           'prepared', jsonb_build_object('type', n.type, 'kind', n.kind, 'to_role', n.to_role, 'lead_id', n.lead_id,
                                                          'inquiry_id', n.inquiry_id, 'quote_id', n.quote_id, 'subject', n.subject,
                                                          'body', n.body, 'lang', n.lang, 'channel', v_channel,
                                                          'to_email', case when v_channel = 'email' then v_email else n.to_email end,
                                                          'to_phone', case when v_channel = 'whatsapp' then v_phone end)));
      v_verdict := 'retried_on_' || v_channel;
    end if;
  end if;

  if v_verdict is null then
    v_rep := public.fn_support_report_to_ceo(
      'delivery_undelivered:' || req.id, 'elevated',
      'A ' || coalesce(req.detail->>'msg_type', 'notice') || ' for the ' || coalesce(req.detail->>'recipient_role', n.to_role, 'recipient')
        || ' did not arrive (' || v_result || ')',
      jsonb_build_object('request_id', req.id, 'result', v_result, 'support_evidence', a.detail->'evidence', 'rechecked', v_seen,
                         'retry_of', req.detail->'retry_of'),
      jsonb_build_array(v_seat || ' asked customer_support to send it',
                        case when req.detail->'retry_of' is not null then 'it was already a retry on the other channel'
                             else 'no other channel was on file' end),
      'Decide how this reaches them: correct the address or number, reach them another way, or record that it need not go.',
      'agent_actions#' || req.id, p_source_agent => v_seat);
    v_verdict := case when coalesce((v_rep->>'ok')::boolean, false) then 'escalated' else 'escalation_refused' end;
  end if;

  update public.agent_actions
     set detail = detail || jsonb_build_object('loop', v_verdict, 'closed_by', v_seat, 'closed_at', now(), 'close_check', v_seen,
                                               'retry_request_id', v_retry, 'escalation', v_rep)
   where id = req.id;
  -- A retry's outcome is the original's outcome too: whoever reads the first request sees how it ended.
  v_origin := (req.detail->>'retry_of')::bigint;
  if v_origin is not null then
    update public.agent_actions set detail = detail || jsonb_build_object('loop', 'retry_' || v_verdict) where id = v_origin;
  end if;
  return jsonb_build_object('checked_by', v_seat, 'result', v_result, 'verdict', v_verdict, 'rechecked', v_seen,
                            'retry_request_id', v_retry, 'escalation', v_rep);
end $fn$;
revoke execute on function public.fn_originator_checks_delivery(bigint) from public, anon, authenticated;
