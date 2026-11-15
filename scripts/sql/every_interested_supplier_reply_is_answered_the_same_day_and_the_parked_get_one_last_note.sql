-- EVERY INTERESTED SUPPLIER REPLY IS ANSWERED THE SAME WORKING DAY, AND THE PARKED GET ONE LAST NOTE. Seat: sales_engineer.
-- 15 Nov 2026. Founder rulings 1696/1701/1705/1706 (enough registered suppliers first; bring solutions, not issues).
--
-- WHAT WAS THERE (READ from origin/main 06881a2d6; SELECT 15 Nov 2026):
--   * A supplier's mail to supplier@ is read first (email_triage/supplier_mailbox_reading.ts, ruling 1633) and, when the reading
--     allows, answered by the model in its thread with the claim link (fn_inbox_send; ruling 1339: never a code reply). When the
--     answer failed twice, fn_customer_support_rescues_dead_answers handed it to the sales engineer ("answer it in its thread"),
--     whose handler (fn_sales_engineer_acts_on_supplier_reply) never writes a reply: it waits 24 hours, then sets needs_review
--     for a person. "Reading not recorded within the hour" ends the same way. Nothing answers it the same day.
--   * supplier_reply_followup, lifetime: 7 rows, 2 sent, 5 dropped. Three of the five went to Microsoft and Azure system senders
--     (inbound 1874, 1994, 2069; the memory note the-supplier-mailbox-is-read-before-it-is-answered): dropping those was right.
--     Two (1872, 1873, no lead) were first answered by the retired template path, so no reading exists and the follow-up rule
--     refuses them. This file does not reopen any of the five.
--   * 162 leads in lifecycle_stage 'no_response' after the day-3/7/14 nudges: never contacted again by any channel. Their
--     mailbox class (SELECT): google 30, microsoft 51, other 81; none suppressed.
-- WHAT THIS DOES:
--   1. fn_supplier_reply_kind: decline / subsidiary / later / question / interested (fn_supplier_reply_intent, plus a question
--      when the person asks one).
--   2. fn_sales_engineer_answers_supplier_replies_same_day (seat duty sales_engineer.supplier_replies_same_day, every 15 minutes):
--      every unanswered supplier mail of kind interested or question from the last 7 days, whose reading allows an answer or
--      has not been made, is OWED an answer by its due time: 17:00 Dubai the same working day when it arrived on a working day
--      before 15:00, else 12:00 the next working day (fn_supplier_reply_due_by). The sales engineer puts it back to the model's
--      answerer (the same retry fn_customer_support_rescues_dead_answers makes: triaged_at, ai_category and owner_role cleared,
--      needs_review set), so email_triage reads it (if no reading exists) and the model writes the answer with the claim link,
--      through fn_inbox_send and the outbox. At most 3 requests, 30 minutes apart, after a first 30 minutes of customer_support's
--      own pass. Past the due time unanswered: escalated to the CEO seat (review.requested) with the reason. A mail the reading
--      refuses, a decline, a suppressed or fixture sender: recorded as not owed, with why. Nothing leaves this table unrecorded.
--   3. fn_sales_engineer_final_touch_parked_suppliers (seat duty sales_engineer.final_touch_parked, hourly): each lead parked as
--      no_response gets ONE last e-mail (English, never WhatsApp itself: a "chat with us on WhatsApp" click-to-chat link to the
--      company's public WhatsApp number, src/content/company.json phone.tel, held in app_secrets.supplier_whatsapp_click_to_chat),
--      then stays parked (public.supplier_final_touch keeps it from a second). Same gates as a nudge: invite_enabled and the
--      founder's supplier_outreach_golive, a UAE working day 09:00-17:00 Dubai, the mailbox class open on the placement gate and
--      not held by the bounce judgement, fn_supplier_outreach_reachable (suppressed, bounced, banned, screened, registered
--      elsewhere), never a lead that replied or registered. At most supplier_final_touch_daily (5) a day: these addresses took
--      four e-mails without a bounce, so they add little bounce risk, but they never replied, so they are kept off the warm
--      invitation cap and small enough not to weigh on engagement.
-- Not the model's to write: the final touch is campaign mail (like the nudges and registration reminders), not a reply.
-- prevented by: scripts/checks/the_supplier_funnel_runs_itself.test.mjs (text) and
-- every_interested_supplier_reply_is_answered_the_same_day_and_the_parked_get_one_last_note_probe.sql (LOCAL).
-- APPLY ORDER: after the_bounce_brake_judges_each_bounce_by_kind_provider_and_sample_and_the_ceo_restarts_within_a_limit.sql
-- (the final touch reads the judgement).
-- LOCKS: two new tables, one seat_handoff_kind row and new routines; inbound_messages rows are updated one at a time by the duty, as the rescue does.
set local lock_timeout = '1500ms';

create table if not exists public.supplier_reply_same_day (
  inbound_message_id bigint primary key,
  lead_id bigint,
  kind text not null check (kind in ('interested', 'question')),
  received_at timestamptz not null,
  due_by timestamptz not null,
  state text not null default 'owed' check (state in ('owed', 'answered', 'escalated', 'not_owed')),
  attempts integer not null default 0,
  last_requested_at timestamptz,
  answered_at timestamptz,
  escalated_at timestamptz,
  handoff_id bigint,
  reason text,
  created_at timestamptz not null default now());
comment on table public.supplier_reply_same_day is 'Every supplier reply of kind interested or question and what became of it: answered by the model the same working day, escalated to the CEO past its due time, or not owed (with why). Never dropped silently (rulings 1705/1706). every_interested_supplier_reply_is_answered_the_same_day_and_the_parked_get_one_last_note.sql';
create index if not exists supplier_reply_same_day_owed on public.supplier_reply_same_day (due_by) where state = 'owed';

create table if not exists public.supplier_final_touch (
  lead_id bigint primary key,
  to_email text not null,
  provider_class text,
  notification_id bigint,
  queued_at timestamptz not null default now());
comment on table public.supplier_final_touch is 'The one last e-mail (with a WhatsApp click-to-chat link) each lead parked as no_response received; a lead here is never touched again. every_interested_supplier_reply_is_answered_the_same_day_and_the_parked_get_one_last_note.sql';

do $guard$
begin
  if not (select relrowsecurity from pg_class where oid = 'public.supplier_reply_same_day'::regclass) then
    alter table public.supplier_reply_same_day enable row level security;
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'supplier_reply_same_day' and policyname = 'supplier_reply_same_day_service_role_only') then
    create policy supplier_reply_same_day_service_role_only on public.supplier_reply_same_day as permissive for all to public using (false) with check (false);
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.supplier_final_touch'::regclass) then
    alter table public.supplier_final_touch enable row level security;
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'supplier_final_touch' and policyname = 'supplier_final_touch_service_role_only') then
    create policy supplier_final_touch_service_role_only on public.supplier_final_touch as permissive for all to public using (false) with check (false);
  end if;
end $guard$;
revoke all on public.supplier_reply_same_day from anon, authenticated;
revoke all on public.supplier_final_touch from anon, authenticated;

insert into public.app_secrets (key, value) values
  ('supplier_whatsapp_click_to_chat', '12183166814'),   -- src/content/company.json phone.tel, the WhatsApp number the site publishes
  ('supplier_final_touch_daily', '5')
on conflict (key) do nothing;

-- ── 1. WHAT KIND OF REPLY IT IS ───────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_supplier_reply_kind(p_text text)
returns text language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select case
    when i <> 'interested' then i
    -- a question: a question mark, or a line that opens like one ("how do we", "what is", "can you", "is there")
    when coalesce(p_text, '') ~ '\?' or coalesce(p_text, '') ~* '(^|\n)\s*(how|what|which|when|where|who|why|is|are|do|does|can|could|would|will|should)\M'
      then 'question'
    else 'interested' end
    from (select public.fn_supplier_reply_intent(p_text) as i) x
$fn$;
revoke execute on function public.fn_supplier_reply_kind(text) from public, anon, authenticated;

-- The working-day promise: 17:00 Dubai the same working day if it arrived on one before 15:00, else 12:00 the next working day.
create or replace function public.fn_supplier_reply_due_by(p_received timestamptz)
returns timestamptz language plpgsql stable set search_path to 'public', 'pg_temp' as $fn$
declare v timestamp := p_received at time zone 'Asia/Dubai'; d date := v::date;
begin
  if public.fn_is_working_day(d) and extract(hour from v) < 15 then
    return (d + time '17:00') at time zone 'Asia/Dubai';
  end if;
  d := d + 1;
  while not public.fn_is_working_day(d) loop d := d + 1; end loop;
  return (d + time '12:00') at time zone 'Asia/Dubai';
end $fn$;
revoke execute on function public.fn_supplier_reply_due_by(timestamptz) from public, anon, authenticated;

-- THE CEO'S CONVERSATION FOR AN OVERDUE REPLY: registered here (an unregistered kind is filed 'failed' by fn_seat_handoff). The
-- handler leaves it waiting on the CEO; the sales engineer closes it once the supplier has been answered (originator_closes).
create or replace function public.fn_ceo_holds_an_overdue_supplier_reply(p_id bigint)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object('waiting', 'the CEO has the supplier answered in the thread today (inbound '
                            || coalesce(a.detail->>'inbound_message_id', '?') || '); the sales engineer closes this once the answer has gone')
    from public.agent_actions a where a.id = p_id
$fn$;
revoke execute on function public.fn_ceo_holds_an_overdue_supplier_reply(bigint) from public, anon, authenticated;
insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file) values
  ('supplier.reply_overdue', 'sales_engineer', 'ceo',
   'A supplier who wrote back (interested or a question) was not answered by the model by its working-day due time after three requests: the CEO has it answered in the thread today. The sales engineer closes it when the answer has gone.',
   'fn_ceo_holds_an_overdue_supplier_reply', interval '4 hours', true,
   'scripts/sql/every_interested_supplier_reply_is_answered_the_same_day_and_the_parked_get_one_last_note.sql')
on conflict do nothing;

-- ── 2. THE SAME-DAY ANSWER ────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_sales_engineer_answers_supplier_replies_same_day(p_now timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_dxb timestamp := p_now at time zone 'Asia/Dubai';
  v_work boolean := public.fn_is_working_day((p_now at time zone 'Asia/Dubai')::date)
                    and extract(hour from v_dxb) >= 8 and extract(hour from v_dxb) < 18;
  r record; v_new int := 0; v_answered int := 0; v_not int := 0; v_requested int := 0; v_escalated int := 0; v_from text; v_why text; v_hid bigint;
begin
  -- a. the mail that is owed an answer: a person's reply to the supplier mailbox (owner sales_engineer, or customer_support's
  --    retry), of kind interested or question, unanswered, from the last 7 days
  insert into public.supplier_reply_same_day (inbound_message_id, lead_id, kind, received_at, due_by)
  select m.id, m.lead_id, public.fn_supplier_reply_kind(m.body), m.created_at, public.fn_supplier_reply_due_by(m.created_at)
    from public.inbound_messages m
    left join public.leads l on l.id = m.lead_id
   where m.created_at > p_now - interval '7 days' and m.created_at <= p_now and m.replied_at is null
     and (m.owner_role = 'sales_engineer' or (m.owner_role is null and m.lead_id is not null))
     and public.fn_supplier_reply_kind(m.body) in ('interested', 'question')
     and not public.fn_inbound_is_bounce(m.from_email, m.subject, m.raw)
     and (public.fn_is_demo_email(lower(substring(coalesce(m.from_email, '') from '([^<>[:space:]"]+@[^<>[:space:]"]+)'))) or coalesce(l.is_demo, false)) = v_fx
  on conflict (inbound_message_id) do nothing;
  get diagnostics v_new = row_count;

  for r in select s.*, m.replied_at, m.from_email, m.replied_by, d.may_reply, d.reading, d.hard_rule
             from public.supplier_reply_same_day s join public.inbound_messages m on m.id = s.inbound_message_id
             left join public.mailbox_reply_decision d on d.inbound_message_id = s.inbound_message_id
            where s.state in ('owed', 'escalated') order by s.due_by limit 50 for update of s skip locked loop
    v_from := lower(substring(coalesce(r.from_email, '') from '([^<>[:space:]"]+@[^<>[:space:]"]+)'));
    -- b. answered (by the model through fn_inbox_send, or by a person from the Inbox)
    if r.replied_at is not null then
      update public.supplier_reply_same_day set state = 'answered', answered_at = r.replied_at,
             reason = 'answered by ' || coalesce(r.replied_by, 'the inbox') || case when r.replied_at <= r.due_by then ' on time' else ' after its due time' end
       where inbound_message_id = r.inbound_message_id;
      -- the CEO's overdue conversation, if there was one, is closed by the seat that opened it
      if r.handoff_id is not null and exists (select 1 from public.agent_actions a where a.id = r.handoff_id and a.status = 'pending') then
        -- the originator names itself, as trg_handoff_only_originator_closes asks, only for this close
        perform set_config('qd.handoff_closer', 'sales_engineer', true);
        perform public.fn_seat_handoff_complete(r.handoff_id, jsonb_build_object('answered_at', r.replied_at, 'replied_by', r.replied_by,
                                                'closed_by', 'sales_engineer', 'inbound_message_id', r.inbound_message_id));
        perform set_config('qd.handoff_closer', '', true);
      end if;
      v_answered := v_answered + 1; continue;
    end if;
    continue when r.state = 'escalated';   -- already with the CEO; closed above once answered
    -- c. not owed, and why: the reading refused it (ruling 1633), the sender is a machine, the founder, a fixture or suppressed
    v_why := case
      when r.reading is not null and not r.may_reply then 'the reading refused an answer: ' || r.reading || coalesce(' (' || r.hard_rule || ')', '')
      when v_from is null then 'no sender address'
      when public.fn_is_machine_sender(v_from) then 'a machine sender'
      when public.fn_is_founder_own_inbox(v_from) then 'the founder''s own inbox'
      when not v_fx and public.fn_is_demo_email(v_from) then 'a fixture address'
      when exists (select 1 from public.email_suppressions x where lower(x.email) = v_from) then 'the address is suppressed (an opt-out or a bounce)'
      end;
    if v_why is not null then
      update public.supplier_reply_same_day set state = 'not_owed', reason = v_why where inbound_message_id = r.inbound_message_id;
      v_not := v_not + 1; continue;
    end if;
    -- d. past its due time: the CEO seat holds it, with the reason (never a silent drop)
    if p_now >= r.due_by then
      v_hid := public.fn_seat_handoff('sales_engineer', 'ceo', 'supplier.reply_overdue', 'inbound_messages', r.inbound_message_id::text,
        jsonb_build_object('inbound_message_id', r.inbound_message_id, 'lead_id', r.lead_id, 'from_email', v_from, 'kind', r.kind,
          'ask', 'A supplier who wrote back (' || r.kind || ') has not been answered by ' || to_char(r.due_by at time zone 'Asia/Dubai', 'DD Mon HH24:MI')
                 || ' Dubai after ' || r.attempts || ' request(s) to the model''s answerer. Decide the answer and have it sent in the thread today.',
          'reading', r.reading));
      update public.supplier_reply_same_day set state = 'escalated', escalated_at = p_now, handoff_id = v_hid,
             reason = 'unanswered at its due time after ' || r.attempts || ' request(s): handed to the CEO seat' where inbound_message_id = r.inbound_message_id;
      v_escalated := v_escalated + 1; continue;
    end if;
    -- e. inside working hours, after customer_support's own first 30 minutes: back to the model's answerer (the rescue's retry)
    if v_work and r.received_at <= p_now - interval '30 minutes' and r.attempts < 3
       and (r.last_requested_at is null or r.last_requested_at <= p_now - interval '30 minutes') then
      update public.inbound_messages
         set triaged_at = null, ai_category = null, owner_role = null, needs_review = true,
             raw = coalesce(raw, '{}'::jsonb) || jsonb_build_object('same_day_answer_requested_at', p_now)
       where id = r.inbound_message_id and replied_at is null;
      update public.supplier_reply_same_day set attempts = attempts + 1, last_requested_at = p_now,
             reason = 'request ' || (r.attempts + 1) || ' to the model''s answerer (email_triage reads and answers it with the claim link)'
       where inbound_message_id = r.inbound_message_id;
      v_requested := v_requested + 1;
    end if;
  end loop;
  return jsonb_build_object('new', v_new, 'answered', v_answered, 'not_owed', v_not, 'requested', v_requested, 'escalated', v_escalated,
                            'owed_now', (select count(*) from public.supplier_reply_same_day where state = 'owed'), 'working_hours', v_work, 'fixture', v_fx);
end $fn$;
revoke execute on function public.fn_sales_engineer_answers_supplier_replies_same_day(timestamptz) from public, anon, authenticated;

-- ── 3. THE ONE LAST NOTE TO A PARKED LEAD ─────────────────────────────────────────────────────────────────────────
create or replace function public.fn_supplier_final_touch_text(p_company text, p_link text, p_wa_digits text)
returns jsonb language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object(
    'subject', 'One last note from QuotesDone',
    'body', coalesce('Dear ' || nullif(btrim(case when p_company ~ '[؀-ۿ]' then '' else p_company end), '') || ',', 'Dear Sir or Madam,') || E'\n\n'
      || 'We wrote to you in the past few weeks about QuotesDone, the Dubai platform where companies in the UAE post requests for quotation '
      || 'and each request goes only to suppliers who work in that exact trade.' || E'\n\n'
      || 'This is the last e-mail we will send about it. If a conversation suits you better than a form, you can chat with us on WhatsApp: '
      || 'https://wa.me/' || regexp_replace(coalesce(p_wa_digits, ''), '[^0-9]', '', 'g') || E'\n\n'
      || 'If you would like to register your company, it takes a few minutes: ' || p_link || E'\n\n'
      || 'If you would rather not hear from us, reply to this e-mail and we will remove your address.')
$fn$;
revoke execute on function public.fn_supplier_final_touch_text(text, text, text) from public, anon, authenticated;

create or replace function public.fn_sales_engineer_final_touch_parked_suppliers(p_now timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_dxb timestamp := p_now at time zone 'Asia/Dubai';
  v_cap int := coalesce((select nullif(btrim(value), '')::int from public.app_secrets where key = 'supplier_final_touch_daily'), 5);
  v_wa text := (select nullif(btrim(value), '') from public.app_secrets where key = 'supplier_whatsapp_click_to_chat');
  v_site text := coalesce((select nullif(btrim(value), '') from public.app_secrets where key = 'public_site_url'), 'https://quotesdone.com');
  v_open text[]; v_j jsonb; v_held text[]; v_used int; v_left int; v_queued int := 0; r public.leads; m jsonb; v_res jsonb; v_cls text; v_link text;
begin
  if not public.fn_is_working_day(v_dxb::date) or extract(hour from v_dxb) < 9 or extract(hour from v_dxb) >= 17 then
    return jsonb_build_object('held', 'outside a UAE working day 09:00-17:00 Dubai', 'queued', 0);
  end if;
  if not (coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false)
          and public.fn_supplier_outreach_golive()) then
    return jsonb_build_object('held', 'the supplier campaign is not open (invite_enabled / supplier_outreach_golive)', 'queued', 0);
  end if;
  if v_wa is null then return jsonb_build_object('held', 'app_secrets.supplier_whatsapp_click_to_chat is not set', 'queued', 0); end if;
  v_open := public.fn_invite_placement_open_providers(v_dxb::date, p_now);
  v_j := public.fn_invite_bounce_judgement(p_now);
  if coalesce((v_j->>'company_brake')::boolean, false) then
    return jsonb_build_object('held', 'bounce judgement: ' || coalesce(v_j->>'why', 'brake'), 'queued', 0);
  end if;
  v_held := coalesce((select array_agg(x) from jsonb_array_elements_text(v_j->'held_classes') x), '{}'::text[]);
  v_open := array(select p from unnest(v_open) p where not (p = any (v_held)));
  if cardinality(v_open) = 0 and not v_fx then return jsonb_build_object('held', 'no mailbox class open', 'queued', 0); end if;
  select count(*) into v_used from public.supplier_final_touch t
   where (t.queued_at at time zone 'Asia/Dubai')::date = v_dxb::date and public.fn_is_demo_email(t.to_email) = v_fx;
  v_left := greatest(0, v_cap - v_used);
  for r in select l.* from public.leads l
            where l.lifecycle_stage = 'no_response'
              and (coalesce(l.is_demo, false) or public.fn_is_demo_email(l.email)) = v_fx
              and not exists (select 1 from public.supplier_final_touch t where t.lead_id = l.id)
              and not coalesce(l.claimed, false) and l.registration_submitted_at is null
              and not exists (select 1 from public.inbound_messages m where m.lead_id = l.id)
            order by l.invite_last_followup_at nulls last, l.id
            limit 200 loop
    exit when v_queued >= v_left;
    if not v_fx then
      continue when not public.fn_supplier_outreach_reachable(r, r.email);
      v_cls := public.fn_mail_provider_of_email(r.email);
      continue when not (v_cls = any (v_open));
    end if;
    v_link := coalesce(public.fn_supplier_invite_link(v_site, r.claim_token, r.id), v_site || '/en/portal');
    m := public.fn_supplier_final_touch_text(r.company_name, v_link, v_wa);
    v_res := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'supplier_registration_reminder', 'requested_by', 'sales_engineer', 'channel', 'email',
      'to_email', lower(btrim(r.email)), 'to_role', 'supplier', 'lead_id', r.id, 'lang', 'en',
      'subject', m->>'subject', 'body', m->>'body', 'dedupe_key', 'supplier_final_touch:' || r.id)));
    insert into public.supplier_final_touch (lead_id, to_email, provider_class, notification_id)
    values (r.id, lower(btrim(r.email)), v_cls, nullif(v_res->0->>'notification_id', '')::bigint)
    on conflict (lead_id) do nothing;
    v_queued := v_queued + 1;
  end loop;
  return jsonb_build_object('held', null, 'queued', v_queued, 'cap', v_cap, 'used_before', v_used, 'open_providers', to_jsonb(v_open),
                            'left_parked', (select count(*) from public.leads l where l.lifecycle_stage = 'no_response' and not coalesce(l.is_demo, false)
                                              and not exists (select 1 from public.supplier_final_touch t where t.lead_id = l.id)),
                            'fixture', v_fx);
end $fn$;
revoke execute on function public.fn_sales_engineer_final_touch_parked_suppliers(timestamptz) from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('sales_engineer.supplier_replies_same_day', 'sales_engineer', interval '15 minutes', 'fn_sales_engineer_answers_supplier_replies_same_day',
   'Every supplier reply of kind interested or question is answered by the model the same working day (17:00 Dubai, or noon the next working day): put back to the model''s answerer up to 3 times, escalated to the CEO past its due time, recorded as not owed with why. Rulings 1339/1633/1705.',
   'scripts/sql/every_interested_supplier_reply_is_answered_the_same_day_and_the_parked_get_one_last_note.sql'),
  ('sales_engineer.final_touch_parked', 'sales_engineer', interval '1 hour', 'fn_sales_engineer_final_touch_parked_suppliers',
   'Each lead parked as no_response gets one last e-mail with a WhatsApp click-to-chat link (never a WhatsApp message), at most supplier_final_touch_daily a working day, under the invitation gates; then stays parked. Ruling 1705.',
   'scripts/sql/every_interested_supplier_reply_is_answered_the_same_day_and_the_parked_get_one_last_note.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('supplier_reply_same_day', true, 'sales_engineer', 'Every interested or question supplier reply and what became of it (answered, escalated, not owed with why).', 'sales_engineer'),
  ('supplier_final_touch', true, 'sales_engineer', 'The one last e-mail each lead parked as no_response received.', 'sales_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category, reason = excluded.reason, added_by = excluded.added_by;
