-- EVERY WHATSAPP SAYS WHETHER IT ARRIVED (customer_support, 22 Sep 2026).
--
-- Seat: customer_support, which owns every send. The founder, 14 Sep 2026 (#207): "nothing literally
-- should ever be a one way communication" — and a send that nobody hears back from is exactly that.
--
-- MEASURED 22 Sep 2026 (Twilio API, read-only SQL on production):
--   * The WhatsApp sender whatsapp:+12183166814 has its incoming webhook on functions/v1/wa_inbound and
--     NO status callback. No Messages.json POST in supabase/functions set StatusCallback, and nothing
--     polled a message's status.
--   * public.notifications, channel whatsapp: 36 'sent' (3 with a Twilio SID), 80 skipped, 39 suppressed,
--     6 held. send_sms stored no SID at all on the rows it marked 'sent'.
--   * fn_customer_support_delivery_watch returned 'delivered' for any 'sent' row with a SID, and
--     fn_originator_checks_delivery closed it 'confirmed' on the same evidence. So a WhatsApp Twilio
--     accepted and Meta then refused (63016 outside the 24-hour window, 63024 not a WhatsApp user, a
--     template not approved) was reported to the asking seat as delivered, for ever.
--   * The IT engineer's sender duty reads email bounce and complaint rates; nothing read WhatsApp or SMS
--     delivery at all. app_secrets.twilio_auth_token exists (32 characters), so signatures can be checked.
--
-- WHAT THIS CHANGES:
--   1. notifications gains provider_status / provider_status_at / provider_error_code /
--      provider_status_checked_at — Twilio's own word, written ONLY by fn_twilio_status_arrived.
--   2. fn_twilio_status_arrived(sid, status, error_code, source): the one recorder, called by
--      supabase/functions/wa_status for a signed status callback and for the backstop poll. Matched by
--      MessageSid, idempotent, and never moves a status backwards (queued < sending < sent < delivered |
--      undelivered | failed < read). failed/undelivered turns the row 'failed' with Twilio's error in
--      plain words (fn_twilio_error_in_plain_words).
--   3. fn_customer_support_delivery_watch: a WhatsApp/SMS waits for delivered/read before it is
--      'delivered'; a failure comes back as 'failed' carrying the code and its explanation, to the seat
--      that asked; no final report within 24 hours comes back as 'sent_unconfirmed'.
--      fn_originator_checks_delivery confirms a WhatsApp/SMS only on delivered/read, and
--      fn_ceo_delivery_undelivered_decide writes "the provider confirmed" only on the same evidence.
--   4. fn_twilio_status_poll_claim(limit): the backstop — messages sent 30 min to 7 days ago with no
--      final status, each at most once per 30 minutes, at most 50 per call (wa_status asks Twilio).
--   5. fn_it_whatsapp_delivery_health(), duty 'whatsapp_delivery' (hourly): failure rate from
--      delivered/failed reports per channel, and any message with no final report 24 hours on.
--
-- WHAT THIS DOES NOT CHANGE: the email path (Resend's webhook already reports bounces); the watched
-- refund-ladder branch of the watch; wa_inbound's in-session replies (recorded in wa_messages, which
-- holds no SID — the callback answers matched=false for them); send_whatsapp's caps and templates.
-- Every other line of the three redefined routines is byte-identical to their live bodies of 22 Sep
-- (every_send_comes_back_to_whoever_asked.sql, the_whatsapp_number_is_confirmed_and_only_a_confirmed_one_is_used.sql,
-- the_ceo_answers_every_overdue_it_report_even_one_the_founder_was_already_told_about.sql).
--
-- PREVENTED BY: scripts/checks/every_twilio_send_reports_its_status.test.mjs (every Messages.json POST
-- carries StatusCallback; wa_status keeps verify_jwt=false and fails closed), _shared/twilio_status.test.ts
-- (signature valid/invalid/missing), and every_whatsapp_says_whether_it_arrived_probe.sql (ordering,
-- idempotency, failure handoff, the 24-hour unconfirmed, the backstop claim, the IT duty).
--
--   node scripts/apply_sql.mjs scripts/sql/every_whatsapp_says_whether_it_arrived.sql --apply --ddl

-- ── 1. TWILIO'S WORD, ON THE ROW IT IS ABOUT ─────────────────────────────────────────────────────
alter table public.notifications
  add column if not exists provider_status text,
  add column if not exists provider_status_at timestamptz,
  add column if not exists provider_error_code text,
  add column if not exists provider_status_checked_at timestamptz;
alter table public.notifications drop constraint if exists notifications_provider_status_known;
alter table public.notifications add constraint notifications_provider_status_known check (
  provider_status is null or provider_status in ('accepted', 'scheduled', 'queued', 'sending', 'sent',
                                                 'delivered', 'undelivered', 'failed', 'read'));
comment on column public.notifications.provider_status is
  'Twilio''s last reported status for a WhatsApp/SMS (never moves backwards). Written only by fn_twilio_status_arrived.';

-- ── 2. THE ORDER A STATUS MAY MOVE IN ────────────────────────────────────────────────────────────
-- 0 = not a status we record. delivered, undelivered and failed are all final (4); read (5) is later
-- than delivered. An equal rank is never applied, so the first final report wins and a repeat is a no-op.
create or replace function public.fn_twilio_status_rank(p_status text)
returns int language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select case lower(coalesce(p_status, ''))
    when 'accepted' then 1 when 'scheduled' then 1 when 'queued' then 1
    when 'sending' then 2 when 'sent' then 3
    when 'delivered' then 4 when 'undelivered' then 4 when 'failed' then 4
    when 'read' then 5 else 0 end
$fn$;
revoke execute on function public.fn_twilio_status_rank(text) from public, anon, authenticated;

-- ── 3. TWILIO'S ERROR, IN WORDS A SEAT CAN ACT ON ────────────────────────────────────────────────
-- From twilio.com/docs/api/errors (read 22 Sep 2026). Anything not listed names its code and the page.
create or replace function public.fn_twilio_error_in_plain_words(p_code text)
returns text language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select case nullif(btrim(coalesce(p_code, '')), '')
    when '63016' then 'outside the 24-hour window: the recipient has not messaged us in the last 24 hours, so WhatsApp accepts only an approved template, not free text'
    when '63024' then 'not a usable WhatsApp account: the number is not on WhatsApp, has not accepted WhatsApp''s terms, or runs an outdated app'
    when '63003' then 'the number could not be found on WhatsApp: wrong, inactive or not registered'
    when '63032' then 'WhatsApp will not deliver to this user because of a WhatsApp restriction on the recipient'
    when '63033' then 'the recipient has opted out of receiving these messages'
    when '63049' then 'Meta chose not to deliver it (its per-user limit on marketing messages)'
    when '63050' then 'the recipient has opted out of marketing messages on WhatsApp'
    when '63013' then 'WhatsApp refused it as a policy violation'
    when '63018' then 'our WhatsApp sender hit its rate limit, so the message was not delivered'
    when '63027' then 'the template does not exist at Meta in this language'
    when '63028' then 'the template was sent with the wrong number of variables'
    when '63040' then 'Meta rejected the template'
    when '63041' then 'Meta paused the template (low quality)'
    when '63042' then 'Meta disabled the template'
    when '63051' then 'Meta has locked our WhatsApp sender or account'
    when '63112' then 'Meta has disabled the WhatsApp Business Account behind our sender'
    when '30003' then 'the phone is unreachable (switched off or out of coverage)'
    when '30005' then 'the number does not exist or is not assigned to anyone'
    when '30006' then 'the number is a landline or cannot receive SMS'
    when '30007' then 'the carrier filtered it as unwanted'
    when '30008' then 'the carrier reported an unknown delivery error'
    else case when p_code is null or btrim(p_code) = '' then null
              else 'Twilio error ' || btrim(p_code) || ' (twilio.com/docs/api/errors/' || btrim(p_code) || ')' end
  end
$fn$;
revoke execute on function public.fn_twilio_error_in_plain_words(text) from public, anon, authenticated;

-- ── 4. THE ONE RECORDER ──────────────────────────────────────────────────────────────────────────
-- Matched by the SID send_whatsapp / send_sms stored. The row lock orders two reports for one message.
-- A report that ranks no higher than what is stored is acknowledged and ignored: that is both the
-- idempotency (a repeat) and the ordering (a 'sent' arriving after 'delivered').
create or replace function public.fn_twilio_status_arrived(p_sid text, p_status text, p_error_code text default null,
                                                          p_source text default 'callback')
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  n public.notifications; v_status text := lower(btrim(coalesce(p_status, ''))); v_code text := nullif(btrim(coalesce(p_error_code, '')), '');
  v_final_fail boolean;
begin
  if coalesce(btrim(p_sid), '') = '' then return jsonb_build_object('matched', false, 'applied', false, 'reason', 'no MessageSid'); end if;
  if public.fn_twilio_status_rank(v_status) = 0 then
    return jsonb_build_object('matched', null, 'applied', false, 'reason', 'not a status this estate records: ' || left(v_status, 40));
  end if;
  select * into n from public.notifications
   where provider_message_id = btrim(p_sid) and channel in ('whatsapp', 'sms')
   order by id limit 1 for update;
  if n.id is null then return jsonb_build_object('matched', false, 'applied', false); end if;
  if public.fn_twilio_status_rank(v_status) <= public.fn_twilio_status_rank(n.provider_status) then
    return jsonb_build_object('matched', true, 'applied', false, 'notification_id', n.id, 'kept', n.provider_status, 'ignored', v_status);
  end if;
  v_final_fail := v_status in ('failed', 'undelivered');
  update public.notifications
     set provider_status = v_status, provider_status_at = now(),
         provider_error_code = coalesce(v_code, provider_error_code),
         status = case when v_final_fail and status = 'sent' then 'failed' else status end,
         last_error = case when v_final_fail
                           then left('Twilio reported ' || v_status || coalesce(' (error ' || v_code || ')', '') || ': '
                                     || coalesce(public.fn_twilio_error_in_plain_words(v_code), 'no error code was given'), 500)
                           else last_error end
   where id = n.id;
  return jsonb_build_object('matched', true, 'applied', true, 'notification_id', n.id, 'from', n.provider_status, 'to', v_status,
                            'failed', v_final_fail, 'error_code', v_code, 'source', left(coalesce(p_source, ''), 20));
end $fn$;
revoke execute on function public.fn_twilio_status_arrived(text, text, text, text) from public, anon, authenticated;

-- ── 5. THE BACKSTOP: WHICH MESSAGES TO ASK TWILIO ABOUT ──────────────────────────────────────────
-- Callbacks can be lost. Claimed rows are stamped before they are returned, so the next call walks the
-- REMAINING set, never its own last answers, and two overlapping calls never ask twice (skip locked).
create or replace function public.fn_twilio_status_poll_claim(p_limit int default 20)
returns table (notification_id bigint, sid text)
language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  return query
  update public.notifications u set provider_status_checked_at = now()
   where u.id in (select c.id from public.notifications c
                   where c.channel in ('whatsapp', 'sms') and coalesce(btrim(c.provider_message_id), '') <> ''
                     and c.sent_at < now() - interval '30 minutes' and c.sent_at > now() - interval '7 days'
                     and public.fn_twilio_status_rank(c.provider_status) < 4
                     and (c.provider_status_checked_at is null or c.provider_status_checked_at < now() - interval '30 minutes')
                   order by coalesce(c.provider_status_checked_at, c.sent_at)
                   limit least(greatest(coalesce(p_limit, 20), 1), 50)
                   for update skip locked)
  returning u.id, u.provider_message_id;
end $fn$;
revoke execute on function public.fn_twilio_status_poll_claim(int) from public, anon, authenticated;

-- ── 6. THE WATCH: A WHATSAPP IS DELIVERED WHEN TWILIO SAYS SO ────────────────────────────────────
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
                            'overdue_raised', v_overdue, 'results_failed', v_failed);
end $fn$;
-- ── 7. THE ASKING SEAT CONFIRMS A WHATSAPP ONLY ON DELIVERED OR READ ───────────────────────────────
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
                               'provider_message_id', n.provider_message_id, 'sent_at', n.sent_at, 'checked_at', now(),
                               'provider_status', n.provider_status, 'provider_error_code', n.provider_error_code);

  if v_result in ('proof_of_response', 'no_response_confirmation') then
    v_verdict := 'handled_by_the_ladder';
  -- 22 Sep 2026: for WhatsApp and SMS the seat's own re-check also reads Twilio's delivery report; a SID
  -- alone is only Twilio's acceptance (every_whatsapp_says_whether_it_arrived.sql).
  elsif v_result = 'delivered' and n.status = 'sent' and coalesce(btrim(n.provider_message_id), '') <> ''
        and (coalesce(n.channel, 'email') not in ('whatsapp', 'sms') or n.provider_status in ('delivered', 'read')) then
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
      -- 14 Sep 2026 (#322): the CONFIRMED WhatsApp number, else SMS on the verified mobile. This used to
      -- take leads.whatsapp (a scraped listing number) or any phone on file.
      v_phone := public.fn_whatsapp_destination(coalesce(req.detail->>'recipient_role', n.to_role), null,
                   coalesce((req.detail->>'supplier_id')::bigint, n.lead_id), v_email);
      if v_phone is not null then v_channel := 'whatsapp';
      else
        v_phone := public.fn_verified_mobile(coalesce(req.detail->>'recipient_role', n.to_role), null,
                     coalesce((req.detail->>'supplier_id')::bigint, n.lead_id), v_email);
        if v_phone is not null then v_channel := 'sms'; end if;
      end if;
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
                                                          'to_phone', case when v_channel in ('whatsapp', 'sms') then v_phone end)));
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
-- ── 7b. THE CEO SAYS "THE PROVIDER CONFIRMED" ONLY WHEN IT DID ─────────────────────────────────────
create or replace function public.fn_ceo_delivery_undelivered_decide(p_report_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  r public.support_ceo_report; n public.notifications; twin public.notifications; v_receipt text;
  v_req public.agent_actions; v_subject bigint;
begin
  select * into r from public.support_ceo_report where id = p_report_id for update;
  if not found or r.status <> 'sent' then return jsonb_build_object('ok', false, 'reason', 'no open report ' || p_report_id); end if;
  select * into n from public.notifications
   where id = coalesce((r.verified_evidence -> 'rechecked' ->> 'notification_id')::bigint,
                       (r.verified_evidence -> 'support_evidence' -> 'notification' ->> 'id')::bigint);
  if n.id is null then
    -- The report may name the notification only through its request (18 Sep reports did: the
    -- recheck found "nothing was queued"). A subject that no longer exists cannot be re-checked.
    select * into v_req from public.agent_actions
     where id = nullif(r.verified_evidence ->> 'request_id', '')::bigint and kind = 'handoff';
    v_subject := coalesce(nullif(v_req.detail ->> 'subject_id', '')::bigint,
                          (r.verified_evidence -> 'rechecked' ->> 'notification_id')::bigint);
    if v_req.id is not null and v_req.detail ->> 'subject_table' = 'notifications' and v_subject is not null
       and not exists (select 1 from public.notifications x where x.id = v_subject) then
      v_receipt := 'ceo: the founder alert this report is about (notification ' || v_subject || ', request '
                   || v_req.id || ') no longer exists in public.notifications, so its delivery can never be '
                   || 're-checked and there is nothing left to deliver. Closed on that fact rather than left open for ever.';
      update public.support_ceo_report
         set status = 'accepted', accepted_at = now(), acceptance_receipt = v_receipt, owner_role_id = 'ceo'
       where id = r.id;
      return jsonb_build_object('ok', true, 'report_id', r.id, 'notification_id', v_subject, 'subject_present', false, 'receipt', v_receipt);
    end if;
    return jsonb_build_object('ok', false, 'report_id', r.id, 'reason', 'the report names no notification');
  end if;
  -- The email twin fn_notify_founder writes in the same statement as the WhatsApp fan-out.
  select * into twin from public.notifications t
   where t.channel = 'email' and t.type = n.type and t.created_at = n.created_at
     and t.to_role is not distinct from n.to_role and t.id <> n.id and t.status = 'sent'
   order by t.id limit 1;

  -- 22 Sep 2026 (every_whatsapp_says_whether_it_arrived.sql): for WhatsApp and SMS a SID is only Twilio's
  -- acceptance; "the provider confirmed" needs Twilio's delivered/read report.
  if n.status = 'sent' and coalesce(btrim(n.provider_message_id), '') <> ''
     and (coalesce(n.channel, 'email') not in ('whatsapp', 'sms') or n.provider_status in ('delivered', 'read')) then
    v_receipt := 'ceo: the provider confirmed notification ' || n.id || ' (' || n.channel || ', message '
                 || n.provider_message_id || ', sent ' || to_char(n.sent_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai)';
  elsif n.status = 'sent' and n.channel = 'whatsapp' and twin.id is not null then
    v_receipt := 'ceo: notification ' || n.id || ' was handed to Twilio at '
                 || to_char(n.sent_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai '
                 || case when coalesce(btrim(n.provider_message_id), '') = '' then 'without a provider id on record; '
                         else '(message ' || n.provider_message_id || ') and Twilio has not reported it delivered; ' end
                 || 'the email twin ' || twin.id || ' was sent and confirmed (' || coalesce(twin.provider_message_id, '?') || ').';
  elsif n.status in ('failed', 'skipped', 'suppressed') and twin.id is not null then
    v_receipt := 'ceo: notification ' || n.id || ' (' || n.channel || ') ended ' || n.status
                 || coalesce(' — ' || left(n.last_error, 160), '') || '; the email twin ' || twin.id
                 || ' was sent and confirmed (' || coalesce(twin.provider_message_id, '?') || '), so the alert reached the founder.';
  else
    -- A founder alert with no delivered twin, or still in the queue: not the CEO's to wave through.
    return jsonb_build_object('ok', false, 'report_id', r.id, 'notification_id', n.id, 'status', n.status,
                              'reason', 'undecided: no confirmed delivery on any channel');
  end if;
  update public.support_ceo_report
     set status = 'accepted', accepted_at = now(), acceptance_receipt = v_receipt, owner_role_id = 'ceo'
   where id = r.id;
  return jsonb_build_object('ok', true, 'report_id', r.id, 'notification_id', n.id, 'receipt', v_receipt);
end $fn$;
-- ── 8. THE IT ENGINEER READS ARRIVALS, NOT ACCEPTANCES ───────────────────────────────────────────
-- Duty 'whatsapp_delivery' (it_duty_schedule, hourly; resilience_ping's itLaterDutiesTick). Per channel,
-- over the last 7 days of messages Twilio accepted (a SID on the row):
--   failure_rate:<channel>     failed+undelivered / all with a final report, above whatsapp_failure_rate_max,
--                              once at least whatsapp_min_final_7d have a final report
--   no_final_status:<channel>  any message 24 hours past its send with no final report — the callback and
--                              the backstop poll are both not reporting, so the rate above cannot be trusted
-- Evidence carries the counts and each error code with its plain-words meaning. Owner: customer_support.
create or replace function public.fn_it_whatsapp_delivery_health()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  x record; v_items jsonb := '[]'::jsonb; v_rates jsonb := '{}'::jsonb; v_out jsonb;
  v_min numeric := coalesce(public.fn_it_threshold('whatsapp_min_final_7d'), 10);
  v_max numeric := coalesce(public.fn_it_threshold('whatsapp_failure_rate_max'), 0.05);
begin
  for x in
    select n.channel,
           count(*) filter (where n.provider_status in ('delivered', 'read')) as delivered,
           count(*) filter (where n.provider_status = 'read') as read,
           count(*) filter (where n.provider_status in ('failed', 'undelivered')) as failed,
           count(*) filter (where public.fn_twilio_status_rank(n.provider_status) < 4 and n.sent_at < now() - interval '24 hours') as unknown,
           count(*) as accepted
      from public.notifications n
     where n.channel in ('whatsapp', 'sms') and coalesce(btrim(n.provider_message_id), '') <> ''
       and n.sent_at > now() - interval '7 days'
     group by n.channel
  loop
    v_rates := v_rates || jsonb_build_object(x.channel, jsonb_build_object('accepted', x.accepted, 'delivered', x.delivered,
      'read', x.read, 'failed', x.failed, 'no_final_status_after_24h', x.unknown,
      'errors', (select coalesce(jsonb_object_agg(coalesce(e.code, 'none'),
                                   jsonb_build_object('count', e.c, 'means', public.fn_twilio_error_in_plain_words(e.code))), '{}'::jsonb)
                   from (select m.provider_error_code code, count(*) c from public.notifications m
                          where m.channel = x.channel and m.provider_status in ('failed', 'undelivered')
                            and m.sent_at > now() - interval '7 days' group by 1) e)));
    if x.delivered + x.failed >= v_min and x.failed::numeric / (x.delivered + x.failed) > v_max then
      v_items := v_items || jsonb_build_object('item', 'failure_rate:' || x.channel, 'owner_seat', 'customer_support', 'subject', 'wa_status',
        'title', round(100 * x.failed::numeric / (x.delivered + x.failed), 1) || '% of last week''s ' || x.channel
                 || ' messages were refused after Twilio accepted them',
        'blast', 'customer_facing', 'affected', x.failed,
        'evidence', (v_rates->x.channel) || jsonb_build_object('max', v_max, 'min_final', v_min));
    end if;
    if x.unknown > 0 then
      v_items := v_items || jsonb_build_object('item', 'no_final_status:' || x.channel, 'owner_seat', 'customer_support', 'subject', 'wa_status',
        'title', x.unknown || ' ' || x.channel || ' message(s) sent over 24 hours ago have no delivery report from Twilio',
        'blast', 'customer_facing', 'affected', x.unknown,
        'evidence', (v_rates->x.channel) || jsonb_build_object('why_it_matters',
          'the status callback (wa_status) and its 30-minute backstop poll are both silent, so delivery is unknown'));
    end if;
  end loop;
  v_out := jsonb_build_object('settled', public.fn_it_duty_settle('whatsapp_delivery', v_items), 'rates', v_rates);
  perform public.fn_it_duty_ran('whatsapp_delivery', v_out);
  return v_out;
end $fn$;
revoke execute on function public.fn_it_whatsapp_delivery_health() from public, anon, authenticated;

insert into public.it_duty_schedule (duty, every, note)
values ('whatsapp_delivery', interval '1 hour',
        'customer_support via it_engineer: WhatsApp/SMS failure rate from Twilio delivery reports, and messages with no final report after 24h (fn_it_whatsapp_delivery_health)')
on conflict (duty) do nothing;
insert into public.it_threshold (key, value, unit, basis) values
  ('whatsapp_min_final_7d', 10, 'messages', 'Below ten messages with a final delivery report in a week, one failure is a 10% rate; the rate is not evaluated on less.'),
  ('whatsapp_failure_rate_max', 0.05, 'ratio', 'More than 5% of accepted WhatsApp/SMS refused by Meta or the carrier means a template, window or number problem worth acting on.')
on conflict (key) do nothing;

-- resilience_ping's whatsappTick calls wa_status for the backstop poll with its own scoped credential.
update public.internal_credential set scope = array_append(scope, 'wa_status')
 where context = 'fn.resilience_ping' and active and not ('wa_status' = any (scope));

-- CREATE OR REPLACE keeps the two redefined routines' ACLs; written out so this file states them.
revoke execute on function public.fn_customer_support_delivery_watch(bigint) from public, anon, authenticated;
revoke execute on function public.fn_originator_checks_delivery(bigint) from public, anon, authenticated;
revoke execute on function public.fn_ceo_delivery_undelivered_decide(bigint) from public, anon, authenticated;

-- ══ VERDICT ═════════════════════════════════════════════════════════════════════════════════════
-- DDL above, so the verdict is a ROW and reads the live definitions. Behaviour is proved by
-- every_whatsapp_says_whether_it_arrived_probe.sql.
select case
  when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'notifications' and column_name = 'provider_status')
   and pg_get_functiondef('public.fn_customer_support_delivery_watch(bigint)'::regprocedure) like '%n.provider_status in (''delivered'', ''read'')%'
   and pg_get_functiondef('public.fn_originator_checks_delivery(bigint)'::regprocedure) like '%n.provider_status in (''delivered'', ''read'')%'
   and pg_get_functiondef('public.fn_ceo_delivery_undelivered_decide(bigint)'::regprocedure) like '%n.provider_status in (''delivered'', ''read'')%'
   and public.fn_twilio_status_rank('sent') < public.fn_twilio_status_rank('delivered')
   and public.fn_twilio_error_in_plain_words('63016') like 'outside the 24-hour window%'
   and exists (select 1 from public.it_duty_schedule where duty = 'whatsapp_delivery')
   and exists (select 1 from public.internal_credential where context = 'fn.resilience_ping' and active and 'wa_status' = any (scope))
  then 'PROBE OK: WhatsApp/SMS wait for Twilio''s delivery report, failures come back in plain words, the IT duty reads arrivals'
  else 'PROBE FAILED: every_whatsapp_says_whether_it_arrived is not what is live' end as verdict;
