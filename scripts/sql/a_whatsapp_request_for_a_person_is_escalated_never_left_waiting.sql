-- A WHATSAPP REQUEST FOR A PERSON IS ESCALATED, NEVER LEFT WAITING.
--
-- Seats: customer_support (the WhatsApp seat owns support.human_requested), it_engineer (author). 7 Oct 2026.
-- Wiring audit (PR #1278), item 2: one support.human_requested handoff pending since 22 Sep 14:41Z.
--
-- MEASURED, read-only, 7 Oct 2026 01:40Z. Handoff 58191: the number is the founder's own mobile (the number
-- in app_secrets.admin_mfa_phone; fn_identify_contact answers audience = 'founder'), event "WhatsApp: Ahmad
-- Alzain asks to talk to a person" -- the founder trying the menu's "Talk to a person" on 22 Sep. Not a customer,
-- not a supplier, nobody waiting. It stayed open 15 days for three reasons, all in the_whatsapp_menu_answers_
-- like_a_senior_member_of_staff.sql:
--   1. wa_inbound passes p_hold = false for the founder, and fn_wa_human_request_tick only ever looked at
--      held = 'true' rows -- so the 23-hour follow-up never ran for it.
--   2. Even a held request was only followed up: the tick set followed_up_at and never closed the handoff and
--      never told anyone but the founder. Nobody but the founder (by typing DONE) could ever close it.
--   3. There was no escalation past the founder: no CEO report, no owner after the 24-hour clock.
--   (fn_it_handoff_sla_items did list it, inside the IT duty's handoff_sla finding, which reaches the founder's
--    digest -- the same person who was not answering.)
--
-- WHAT THIS CHANGES.
--   A. fn_wa_human_request: the founder's own number opens NO handoff (he cannot be waiting on himself); his
--      alert still goes out, so trying the menu still shows him what a customer's request looks like.
--   B. fn_wa_human_request_tick, every request, held or not:
--        23 h  customer_support follows up with the contact inside the WhatsApp window (held only, unchanged),
--              hands the chat back to the automatic replies and alerts the founder again (unchanged);
--        24 h  (seat_handoff_kind.reply_within) customer_support reports it to the CEO --
--              support_ceo_report 'wa_human:<handoff id>', severity serious -- once, recorded on the handoff;
--        then  the handoff closes only when BOTH have happened: the contact was followed up (or the founder sent
--              DONE, the existing close) AND the CEO's report is completed. The verdict names both.
--   C. Handoff 58191 is closed by its exact id with the reason above.
--
-- Prevented by: scripts/checks/a_whatsapp_request_for_a_person_is_escalated_never_left_waiting.test.mjs
-- Probe: the verdict row at the end, rolled-back ZZ DEMO request on +971500000099 (the demo range; never sent:
-- its conversation has no open WhatsApp window, so no follow-up is queued).
--   node scripts/apply_sql.mjs scripts/sql/a_whatsapp_request_for_a_person_is_escalated_never_left_waiting.sql --apply --ddl

create or replace function public.fn_wa_human_request(p_phone text, p_hold boolean, p_event text, p_detail text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_digits text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'); v_h bigint; v_ok boolean := true; v_err text;
  v_founder boolean;
begin
  if length(v_digits) < 9 then return jsonb_build_object('ok', false, 'reason', 'no usable number'); end if;
  -- A. The founder trying "Talk to a person" from his own number is not a person waiting (handoff 58191, 22 Sep).
  v_founder := coalesce(public.fn_identify_contact(v_digits) ->> 'audience', '') = 'founder';
  if p_hold and not v_founder then
    insert into public.wa_conversation (phone_e164, party_kind, message_count, thread_state, handed_to)
    values (v_digits, 'unknown', 0, 'handed_to_human', 'customer_support')
    on conflict (phone_e164) do update set thread_state = 'handed_to_human', handed_to = 'customer_support', last_seen_at = now();
  end if;
  select id into v_h from public.agent_actions
   where kind = 'handoff' and status = 'pending' and detail ->> 'type' = 'support.human_requested' and detail ->> 'phone_digits' = v_digits
   order by id desc limit 1;
  if v_h is null and not v_founder then
    v_h := public.fn_seat_handoff('customer_support', 'customer_support', 'support.human_requested', 'wa_conversation',
      v_digits || ':' || to_char(now() at time zone 'UTC', 'YYYYMMDDHH24MISS'),
      jsonb_build_object('phone_digits', v_digits, 'held', p_hold, 'event', p_event,
                         'waiting_for', 'a person to answer +' || v_digits || ' on WhatsApp'));
  end if;
  begin
    perform public.fn_notify_founder(p_event => p_event, p_detail => p_detail, p_level => 'high', p_kind => 'whatsapp_human_request',
                                     p_dedupe_key => 'wa_human:' || v_digits || ':' || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD'),
                                     p_owner_agent => 'customer_support');
  exception when others then v_ok := false; v_err := left(sqlerrm, 300);
  end;
  return jsonb_build_object('ok', true, 'handoff_id', v_h, 'held', p_hold, 'founder_own_number', v_founder, 'notified', v_ok, 'notify_error', v_err);
end $fn$;
revoke execute on function public.fn_wa_human_request(text, boolean, text, text) from public, anon, authenticated;

create or replace function public.fn_wa_human_request_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r record; v_conv public.wa_conversation; v_ref text; v_secret text; v_req bigint; v_body text; v_lang text; n int := 0; v_sent int := 0;
  v_held boolean; v_window interval; v_rep jsonb; rep public.support_ceo_report; n_esc int := 0; n_closed int := 0;
begin
  select value into v_ref from public.app_secrets where key = 'project_ref';
  select value into v_secret from public.app_secrets where key = 'cred_fn_resilience_ping';
  for r in select a.* from public.agent_actions a
            where a.kind = 'handoff' and a.status = 'pending' and a.detail ->> 'type' = 'support.human_requested'
              and a.created_at < now() - interval '23 hours' and not (a.detail ? 'followed_up_at')
            order by a.id limit 20 loop
    n := n + 1; v_req := null;
    v_held := coalesce(r.detail ->> 'held', 'true') = 'true';
    update public.wa_conversation set thread_state = 'open', handed_to = null
     where phone_e164 = r.detail ->> 'phone_digits' and thread_state = 'handed_to_human'
    returning * into v_conv;
    if v_conv.id is null then select * into v_conv from public.wa_conversation where phone_e164 = r.detail ->> 'phone_digits'; end if;
    v_lang := case when coalesce(v_conv.language, '') = 'ar' then 'ar' else 'en' end;
    v_body := case when v_lang = 'ar'
      then 'نعتذر عن تأخر ردنا عليكم. لم يتمكن أحد أعضاء الفريق من التواصل معكم بعد، وقد أبلغناه مجددًا بطلبكم. وإلى حين ذلك عادت إليكم خدمة الردود الفورية في هذه المحادثة، فتفضلوا بإرسال كلمة «قائمة» لعرض الخيارات أو كتابة استفساركم.' || E'\n\nفريق خدمة العملاء في QuotesDone'
      else 'We are sorry you have not heard from us yet. A member of the team has not been able to reach you, and we have reminded them of your request. Meanwhile, instant answers are back on in this chat: reply MENU for the options or type your question.' || E'\n\nQuotesDone Customer Support' end;
    if v_held and v_conv.window_expires_at > now() and v_ref is not null and v_secret is not null then
      select net.http_post(
        url := 'https://' || v_ref || '.supabase.co/functions/v1/send_whatsapp',
        headers := jsonb_build_object('Content-Type', 'application/json'),
        body := jsonb_build_object('__secret', v_secret, 'to', '+' || (r.detail ->> 'phone_digits'), 'body', v_body),
        timeout_milliseconds := 15000) into v_req;
      v_sent := v_sent + 1;
    end if;
    begin
      perform public.fn_notify_founder(p_event => 'WhatsApp: +' || (r.detail ->> 'phone_digits') || ' has waited 23 hours for a person',
        p_detail => 'Nobody closed the request from +' || (r.detail ->> 'phone_digits') || ' (' || coalesce(r.detail ->> 'event', 'Talk to a person') || ').'
        || case when v_req is not null then ' They were sent a polite follow-up and automatic replies are back on.'
                else ' Their WhatsApp window has closed, so no follow-up could be sent; call them or email them.' end
        || E'\nReply now: https://wa.me/' || (r.detail ->> 'phone_digits')
        || E'\nWhen handled, send DONE +' || (r.detail ->> 'phone_digits') || ' to the QuotesDone WhatsApp number.',
        p_level => 'high', p_kind => 'whatsapp_human_request', p_dedupe_key => 'wa_human_followup:' || r.id,
        p_owner_agent => 'customer_support');
    exception when others then null;   -- the follow-up is recorded below either way
    end;
    update public.agent_actions
       set detail = detail || jsonb_build_object('followed_up_at', now(), 'followup_request_id', v_req,
                                                 'followup_skipped', case when v_req is not null then null
                                                                           when not v_held then 'not held: the automatic replies were never paused'
                                                                           else 'the 24-hour WhatsApp window had closed' end)
     where id = r.id;
  end loop;
  -- B. 24 h, the reply clock (seat_handoff_kind.reply_within): customer_support reports it to the CEO, once.
  select reply_within into v_window from public.seat_handoff_kind
   where type = 'support.human_requested' and from_seat = 'customer_support' and to_seat = 'customer_support';
  v_window := coalesce(v_window, interval '24 hours');
  for r in select a.* from public.agent_actions a
            where a.kind = 'handoff' and a.status = 'pending' and a.detail ->> 'type' = 'support.human_requested'
              and a.created_at < now() - v_window and not (a.detail ? 'escalated_report_id')
            order by a.id limit 20 loop
    v_rep := public.fn_support_report_to_ceo('wa_human:' || r.id, 'serious',
      'A WhatsApp contact asked for a person and nobody answered within ' || v_window || ' (handoff ' || r.id || ')',
      jsonb_build_object('handoff_id', r.id, 'phone_digits', r.detail ->> 'phone_digits', 'asked_at', r.created_at,
                         'event', r.detail ->> 'event', 'followed_up_at', r.detail ->> 'followed_up_at',
                         'followup_request_id', r.detail ->> 'followup_request_id', 'followup_skipped', r.detail ->> 'followup_skipped'),
      jsonb_build_array('customer_support alerted the founder at ' || to_char(r.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai',
                        coalesce('customer_support followed up with the contact at ' || (r.detail ->> 'followed_up_at'),
                                 'customer_support has not yet followed up with the contact')),
      'Decide who answers this contact today (call, email or WhatsApp from the company number) and record it. The request stays open until the contact was followed up and this report is completed.',
      p_review_in => interval '4 hours', p_source_agent => 'customer_support');
    if coalesce((v_rep ->> 'ok')::boolean, false) then
      update public.agent_actions
         set detail = detail || jsonb_build_object('escalated_report_id', (v_rep ->> 'report_id')::bigint, 'escalated_at', now())
       where id = r.id;
      n_esc := n_esc + 1;
    end if;
  end loop;

  -- The loop closes when the contact was followed up AND the CEO's report is completed; the verdict names both.
  for r in select a.* from public.agent_actions a
            where a.kind = 'handoff' and a.status = 'pending' and a.detail ->> 'type' = 'support.human_requested'
              and a.detail ? 'followed_up_at' and a.detail ? 'escalated_report_id'
            order by a.id limit 20 loop
    select * into rep from public.support_ceo_report where id = (r.detail ->> 'escalated_report_id')::bigint;
    continue when rep.id is null or rep.status <> 'completed';
    perform set_config('qd.handoff_closer', 'customer_support', true);
    perform public.fn_seat_handoff_complete(r.id, coalesce(r.evidence, '{}'::jsonb) || jsonb_build_object(
      'verified_by', 'customer_support', 'verified_at', now(),
      'verdict', 'followed up ' || (r.detail ->> 'followed_up_at')
                 || coalesce(' (' || (r.detail ->> 'followup_skipped') || ')', '')
                 || '; the CEO decided (report ' || rep.id || '): ' || left(coalesce(rep.completion_note, rep.acceptance_receipt, 'completed'), 400)));
    perform set_config('qd.handoff_closer', '', true);
    n_closed := n_closed + 1;
  end loop;
  return jsonb_build_object('ok', true, 'due', n, 'followups_queued', v_sent, 'escalated', n_esc, 'closed', n_closed);
end $fn$;
revoke execute on function public.fn_wa_human_request_tick() from public, anon, authenticated;

-- C. Handoff 58191, by exact id, only while it is still the founder's own pending request.
do $close$
declare h public.agent_actions;
begin
  select * into h from public.agent_actions where id = 58191;
  if h.status = 'pending' and h.detail ->> 'type' = 'support.human_requested'
     and coalesce(public.fn_identify_contact(h.detail ->> 'phone_digits') ->> 'audience', '') = 'founder' then
    perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
      'verified_by', 'customer_support', 'verified_at', now(),
      'verdict', 'Closed, not answered: the request came from the founder''s own number (fn_identify_contact = founder) on 22 Sep 2026 '
                 || '14:41Z -- the founder trying "Talk to a person". Nobody was waiting. It stayed open because the 23-hour tick skipped '
                 || 'unheld requests and nothing escalated past the founder; both fixed in '
                 || 'a_whatsapp_request_for_a_person_is_escalated_never_left_waiting.sql.'));
  end if;
end
$close$;

select case
  when (select status from public.agent_actions where id = 58191) <> 'done' then 'PROBE FAILED: handoff 58191 is still open'
  when (select prosrc from pg_proc where oid = 'public.fn_wa_human_request_tick()'::regprocedure) like '%detail ->> ''held'', ''true'') = ''true''%order by a.id limit 20 loop%'
       and (select prosrc from pg_proc where oid = 'public.fn_wa_human_request_tick()'::regprocedure) not like '%wa_human:%'
    then 'PROBE FAILED: the tick still skips unheld requests or never escalates'
  when (select prosrc from pg_proc where oid = 'public.fn_wa_human_request(text, boolean, text, text)'::regprocedure) not like '%v_founder%'
    then 'PROBE FAILED: the founder''s own number still opens a handoff'
  else 'PROBE OK' end as verdict;
