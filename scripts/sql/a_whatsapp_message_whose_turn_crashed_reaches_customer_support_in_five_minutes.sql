-- a_whatsapp_message_whose_turn_crashed_reaches_customer_support_in_five_minutes — customer_support, 19 Oct 2026.
-- Since #1457 wa_inbound stores every authenticated message on arrival (wa_messages.meta.stage = 'received') and the turn
-- completes that row; a turn that finishes without a row of its own marks it 'handled'. A row still at 'received' after
-- 5 minutes is a turn that crashed or whose isolate was killed: the customer has had no answer.
--
-- fn_wa_arrival_sweep takes each such row ONCE and, in one statement:
--   1. marks it 'escalated' on wa_messages;
--   2. files it in the held-question queue (reasoning_held_question, dedupe_key 'wa_arrival:<id>', escalated_at now(),
--      subject.phone) — so the EXISTING holding-notice path (fn_reason_held_notice_due -> sendHeldNotices in resilience_ping,
--      retried every 30 minutes up to 8 times, Arabic when the message is Arabic) tells the customer a person has it.
--      status 'failed' keeps it out of the model replay: the turn is never replayed, so a reply can never go out twice;
--   3. files one customer_support held_question action (the seat's queue), only for a row step 2 really inserted.
-- RACE WITH A SLOW TURN (review of #1457): wa_inbound completes its arrival row only while it is still 'received'. If the
-- sweep got there first, the turn writes its own row and calls fn_wa_arrival_turn_finished, which closes the action
-- (auto_done) and the held row, and suppresses a holding notice not yet sent.
-- CONCURRENT SWEEPS: FOR UPDATE SKIP LOCKED skips a row another sweep holds; once that sweep commits, the row is
-- 'escalated' and fails the WHERE on re-check. The unique dedupe_key is the backstop: a second insert for the same message
-- is dropped (on conflict do nothing) and no action is filed for it. A single-transaction probe cannot open two sessions;
-- the probe below proves the backstop by sweeping a row whose held entry already exists.
-- Applied at merge (release operator), never before. Prevented by: the verdict probe at the end of this file.

create or replace function public.fn_wa_arrival_sweep(p_limit integer default 20, p_from text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v jsonb;
begin
  with stuck as (
    select id from public.wa_messages
     where meta->>'stage' = 'received'
       and created_at <= now() - interval '5 minutes'
       and (p_from is null or wa_from = p_from)
     order by created_at
     limit greatest(1, least(coalesce(p_limit, 20), 100))
     for update skip locked
  ), marked as (
    update public.wa_messages w
       set meta = w.meta || jsonb_build_object('stage', 'escalated', 'escalated_at', now())
      from stuck where w.id = stuck.id
    returning w.id, w.wa_from, w.profile_name, w.inbound, w.created_at, w.lang, w.meta->>'message_sid' as message_sid
  ), held as (
    insert into public.reasoning_held_question (seat, surface, question, request, subject, reason, status, escalated_at, dedupe_key)
    select 'customer_support', 'wa_inbound.turn_crashed',
           coalesce(nullif(btrim(m.inbound), ''), '(a WhatsApp message with no text)'),
           jsonb_build_object('wa_message_id', m.id),
           jsonb_build_object('phone', regexp_replace(m.wa_from, '^whatsapp:', '', 'i'), 'lang', m.lang, 'wa_message_id', m.id),
           'the WhatsApp turn stopped before replying (no row completed in 5 minutes)', 'failed', now(), 'wa_arrival:' || m.id
      from marked m
    on conflict (dedupe_key) do nothing
    returning id, (request->>'wa_message_id')::bigint as wa_id
  ), filed as (
    insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
    select 'customer_support', 'held_question', 'pending', 'low',
           'A WhatsApp message got no answer: its turn stopped before replying (5 minutes)',
           jsonb_build_object('wa_message_id', m.id, 'held_id', h.id, 'from', m.wa_from, 'profile_name', m.profile_name,
                              'message', left(coalesce(m.inbound, ''), 1000), 'received_at', m.created_at, 'message_sid', m.message_sid,
                              'told', 'the holding notice (a person has it) goes to them on WhatsApp from the held-question queue',
                              'waiting_for', 'customer_support to answer this person on WhatsApp'),
           'wa_messages', m.id::text
      from marked m join held h on h.wa_id = m.id
    returning id
  )
  select coalesce(jsonb_agg(jsonb_build_object('wa_message_id', h.wa_id, 'held_id', h.id)), '[]'::jsonb)
    into v from held h where (select count(*) from filed) >= 0;
  return v;
end $function$;

revoke execute on function public.fn_wa_arrival_sweep(integer, text) from public, anon, authenticated;

-- The turn finished after the sweep took its row: close what the sweep opened, and do not tell the customer a person has it
-- when the reply already went out (a notice already delivered stays delivered; the record says why it is closed).
create or replace function public.fn_wa_arrival_turn_finished(p_wa_message_id bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare n_held int; n_act int;
begin
  update public.reasoning_held_question
     set status = 'applied', applied_at = now(),
         notice_delivered_at = coalesce(notice_delivered_at, now()),
         notice_detail = coalesce(notice_detail, jsonb_build_object('suppressed', 'the turn replied after the sweep took it'))
   where dedupe_key = 'wa_arrival:' || p_wa_message_id and status <> 'applied';
  get diagnostics n_held = row_count;
  update public.agent_actions
     set status = 'auto_done', decided_at = now(), decided_by = 'wa_inbound'
   where agent = 'customer_support' and kind = 'held_question' and target_table = 'wa_messages'
     and target_id = p_wa_message_id::text and status = 'pending';
  get diagnostics n_act = row_count;
  return jsonb_build_object('held_closed', n_held, 'actions_closed', n_act);
end $function$;

revoke execute on function public.fn_wa_arrival_turn_finished(bigint) from public, anon, authenticated;

-- THE SWEPT MESSAGES STAY IN THE WEEKLY REVIEW (review of #1457). fn_ceo_management_review counted a seat's reasoning
-- queue as status = 'held' only; a swept WhatsApp message sits there as 'failed' (so the replay never takes it) and would
-- have vanished from customer_support's count. It now also counts 'failed' rows with dedupe prefix wa_arrival:.
-- Body copied from the_ceo_management_review_request_fits_the_reasoning_limit.sql (live md5 of the body matched it,
-- 19 Oct 2026); that one line is the only change. CREATE OR REPLACE keeps its ACL.
create or replace function public.fn_ceo_management_review()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_week date := public.fn_ceo_review_week(); v_facts jsonb; v_held bigint; v_cap int;
begin
  if (select held_id from public.ceo_review where kind = 'management_review' and period = v_week) is not null then
    return jsonb_build_object('week', v_week, 'already_filed', true);
  end if;
  -- BOUNDED (5 Oct 2026, ceo): 200 characters of each duty's result, then none if the facts still pass 45,000.
  foreach v_cap in array array[200, 0] loop
  select jsonb_build_object(
    'seats', (select jsonb_object_agg(r.role_id, jsonb_build_object(
        'duties', (select coalesce(jsonb_agg(jsonb_build_object('duty', d.duty, 'last_ok_at', d.last_ok_at, 'failures', d.failures,
                     'last_result', case when v_cap = 0 then null
                                         when length(d.last_result::text) <= v_cap then d.last_result
                                         else to_jsonb(left(d.last_result::text, v_cap) || '...') end)), '[]'::jsonb)
                     from public.seat_duty d where d.owner_seat = r.role_id),
        'open_findings', (select count(*) from public.it_engineer_finding f where f.closed_at is null
                            and coalesce(f.evidence->>'owner_seat', f.raised_by) = r.role_id),
        'reasoning_waiting', (select count(*) from public.reasoning_held_question h where h.seat = r.role_id
                                and (h.status = 'held' or (h.status = 'failed' and h.dedupe_key like 'wa_arrival:%'))),
        'handoffs_pending', (select count(*) from public.agent_actions a where a.agent = r.role_id and a.kind = 'handoff' and a.status = 'pending'),
        -- the seat reports against its own year-one targets and its month directive
        'targets', (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(public.fn_ceo_year_plan_status(now())->'metrics') x
                     where x->>'owner_seat' = r.role_id),
        'month_directive', (select jsonb_build_object('actions', d.actions, 'targets', d.targets, 'handoff_id', d.handoff_id, 'status', d.status)
                              from public.ceo_seat_directive d where d.seat = r.role_id and d.month = date_trunc('month', now() at time zone 'Asia/Dubai')::date),
        'improvements_open', (select count(*) from public.ceo_improvement i where i.seat = r.role_id and i.status in ('open', 'assigned'))))
      from public.org_role r where r.status = 'active'),
    'duties_unhealthy', public.fn_seat_duty_health(),
    'week_revenue_aed', (select coalesce(sum(reveal_fee), 0) from public.transactions where fee_status in ('paid', 'collected', 'succeeded') and revealed_at > now() - interval '7 days'),
    'requests_7d', (select count(*) from public.inquiries where created_at > now() - interval '7 days'),
    'customers', (select count(*) from public.customers where not coalesce(is_demo, false)),
    'suppliers_approved', (select count(*) from public.leads where approval_status = 'approved' and not coalesce(is_demo, false)),
    'forecast', (select facts from public.ceo_review where kind = 'target_forecast' and period = v_week),
    'last_review', (select jsonb_build_object('week', period, 'verdict', decision, 'fields', fields) from public.ceo_review
                     where kind = 'management_review' and period < v_week and decision is not null order by period desc limit 1))
  into v_facts;
  exit when length(v_facts::text) <= 45000;
  end loop;
  insert into public.ceo_review (kind, period, facts) values ('management_review', v_week, v_facts)
  on conflict (kind, period) do update set facts = excluded.facts;

  v_held := public.fn_seat_duty_reason('ceo', 'ceo.management_review',
    'The weekly management review. Read each seat''s week — its duties, failures, open findings, what waits in its '
      || 'reasoning queue, and its own targets and month directive on the founder''s year-one path — against last week''s review. Give the verdict and name the one '
      || 'binding constraint.',
    ('[{"id":"on_track","meaning":"the company is on its plan this week"},'
    || '{"id":"at_risk","meaning":"the plan holds but something material is slipping"},'
    || '{"id":"off_track","meaning":"the plan is not working and must change"}]')::jsonb,
    v_facts, jsonb_build_object('kind', 'management_review', 'period', v_week), 'ceo_mreview:' || v_week);
  -- ONE VERDICT LINE (24 Sep 2026, it_engineer): the per-seat week is the SQL facts above (duties, failures,
  -- findings, queue, targets, directive); the model gives only the verdict and the one binding constraint, at
  -- normal stakes, so the review is one think() call. The five per-seat direction fields it wrote before are gone.
  update public.reasoning_held_question
     set request = jsonb_set(request || '{"stakes":"normal"}'::jsonb, '{decision,fields}', jsonb_build_array(
           jsonb_build_object('key', 'binding_constraint', 'question', 'the one constraint that most limits progress this week')))
   where id = v_held;
  update public.ceo_review set held_id = v_held where kind = 'management_review' and period = v_week;
  return jsonb_build_object('week', v_week, 'filed', v_held);
end $fn$;

-- VERDICT PROBE (the file defines routines, so it cleans up and returns a row instead of raising).
-- Rows on the reserved fixture number: A stuck 10 minutes at 'received', B completed, C stuck but already holding a held
-- entry (the concurrent-sweep backstop). The sweep must take A exactly once (a second sweep takes nothing), queue one
-- holding notice and one action for A, file NOTHING for C, and leave B untouched; fn_wa_arrival_turn_finished then closes
-- A's action and suppresses its notice. meta.audience founder keeps fn_support_wire_whatsapp from opening a support case.
with ins as (
  insert into public.wa_messages (wa_from, wa_to, profile_name, inbound, reply, lang, escalated, sent, created_at, meta)
  values ('whatsapp:+971500000099', '', 'ZZ DEMO sweep probe', 'ZZ DEMO sweep probe A', '', 'en', false, false, now() - interval '10 minutes', '{"stage":"received","audience":"founder"}'),
         ('whatsapp:+971500000099', '', 'ZZ DEMO sweep probe', 'ZZ DEMO sweep probe B', 'ok', 'en', false, true, now() - interval '10 minutes', '{"route":"faq","audience":"founder"}'),
         ('whatsapp:+971500000099', '', 'ZZ DEMO sweep probe', 'ZZ DEMO sweep probe C', '', 'en', false, false, now() - interval '10 minutes', '{"stage":"received","audience":"founder"}')
  returning id
) select count(*) from ins;

insert into public.reasoning_held_question (seat, surface, question, request, subject, reason, status, escalated_at, dedupe_key)
select 'customer_support', 'wa_inbound.turn_crashed', 'ZZ DEMO sweep probe C', '{}'::jsonb, '{"phone":""}'::jsonb, 'probe: a sweep already took it', 'failed', now(), 'wa_arrival:' || id
  from public.wa_messages where inbound = 'ZZ DEMO sweep probe C';

create temp table _sweep_probe on commit drop as
select public.fn_wa_arrival_sweep(100, 'whatsapp:+971500000099') as first_run, null::jsonb as second_run, null::jsonb as finished;
update _sweep_probe set second_run = public.fn_wa_arrival_sweep(100, 'whatsapp:+971500000099');

create temp table _sweep_counts on commit drop as
select (select count(*) from public.reasoning_held_question where dedupe_key = 'wa_arrival:' || a.id and escalated_at is not null
          and notice_delivered_at is null and subject->>'phone' = '+971500000099' and status = 'failed') as a_notice_owed,
       (select count(*) from public.agent_actions where target_table = 'wa_messages' and target_id = a.id::text and status = 'pending') as a_actions,
       (select count(*) from public.agent_actions where target_table = 'wa_messages' and target_id = c.id::text) as c_actions,
       (select meta from public.wa_messages where id = b.id) as b_meta,
       a.id as a_id
  from (select id from public.wa_messages where inbound = 'ZZ DEMO sweep probe A') a,
       (select id from public.wa_messages where inbound = 'ZZ DEMO sweep probe B') b,
       (select id from public.wa_messages where inbound = 'ZZ DEMO sweep probe C') c;

update _sweep_probe set finished = public.fn_wa_arrival_turn_finished((select a_id from _sweep_counts));

create temp table _sweep_verdict on commit drop as
select case
  when jsonb_array_length((select first_run from _sweep_probe)) <> 1 then 'PROBE FAILED: the first sweep did not queue exactly one message (A)'
  when jsonb_array_length((select second_run from _sweep_probe)) <> 0 then 'PROBE FAILED: a second sweep took a row again'
  when (select a_notice_owed from _sweep_counts) <> 1 then 'PROBE FAILED: no holding notice is owed to A''s customer'
  when (select a_actions from _sweep_counts) <> 1 then 'PROBE FAILED: not exactly one customer_support action for A'
  when (select c_actions from _sweep_counts) <> 0 then 'PROBE FAILED: a message already held (C) was filed again'
  when (select b_meta from _sweep_counts) <> '{"route":"faq","audience":"founder"}'::jsonb then 'PROBE FAILED: the completed row (B) was touched'
  when (select finished from _sweep_probe) <> '{"held_closed":1,"actions_closed":1}'::jsonb then 'PROBE FAILED: a late reply did not close A''s action and notice'
  when exists (select 1 from public.reasoning_held_question h, _sweep_counts s where h.dedupe_key = 'wa_arrival:' || s.a_id
                 and (h.status <> 'applied' or (h.notice_detail->>'suppressed') is null)) then 'PROBE FAILED: A''s notice was not suppressed'
  else 'PROBE OK' end as verdict;

delete from public.agent_actions where target_table = 'wa_messages'
   and target_id in (select id::text from public.wa_messages where inbound like 'ZZ DEMO sweep probe%');
delete from public.reasoning_held_question where dedupe_key in (select 'wa_arrival:' || id from public.wa_messages where inbound like 'ZZ DEMO sweep probe%');
delete from public.wa_messages where inbound like 'ZZ DEMO sweep probe%';

select case when exists (select 1 from public.wa_messages where inbound like 'ZZ DEMO sweep probe%')
              or exists (select 1 from public.reasoning_held_question where question like 'ZZ DEMO sweep probe%')
            then 'PROBE FAILED: probe rows were left behind' else verdict end as verdict
  from _sweep_verdict;
