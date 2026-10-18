-- a_whatsapp_message_whose_turn_crashed_reaches_customer_support_in_five_minutes — customer_support, 19 Oct 2026.
-- Since #1457 wa_inbound stores every authenticated message on arrival (wa_messages.meta.stage = 'received') and the turn
-- completes that row; a turn that finishes without a row of its own marks it 'handled'. A row still at 'received' after
-- 5 minutes is a turn that crashed or whose isolate was killed: the customer has had no answer.
-- fn_wa_arrival_sweep hands each such row to customer_support ONCE, as a held_question action, and marks the row
-- 'escalated' in the same statement. It never replays the turn: a replay could send a second reply to a turn that had in
-- fact answered before dying, so the one path is a person (never both, never twice). FOR UPDATE SKIP LOCKED means two
-- concurrent sweeps cannot take the same row. Called every resilience_ping tick next to fn_reason_held_escalate.
-- p_from limits the sweep to one number: the probe below uses it so it never touches a real row.
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
    returning w.id, w.wa_from, w.profile_name, w.inbound, w.created_at, w.meta->>'message_sid' as message_sid
  ), filed as (
    insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
    select 'customer_support', 'held_question', 'pending', 'low',
           'A WhatsApp message got no answer: its turn stopped before replying (5 minutes)',
           jsonb_build_object('wa_message_id', m.id, 'from', m.wa_from, 'profile_name', m.profile_name,
                              'message', left(coalesce(m.inbound, ''), 1000), 'received_at', m.created_at, 'message_sid', m.message_sid,
                              'waiting_for', 'customer_support to answer this person on WhatsApp; nothing was sent to them'),
           'wa_messages', m.id::text
      from marked m
    returning id
  )
  select coalesce(jsonb_agg(jsonb_build_object('wa_message_id', m.id, 'from', m.wa_from)), '[]'::jsonb)
    into v from marked m where (select count(*) from filed) >= 0;
  return v;
end $function$;

revoke execute on function public.fn_wa_arrival_sweep(integer, text) from public, anon, authenticated;

-- VERDICT PROBE (the file defines a routine, so it cleans up and returns a row instead of raising).
-- Two rows on the reserved fixture number: one stuck 10 minutes at 'received', one completed. The sweep must take the stuck
-- one exactly once (a second sweep takes nothing), file one action for it, and leave the completed row untouched.
-- meta.audience founder keeps fn_support_wire_whatsapp from opening a support case for the probe number.
with ins as (
  insert into public.wa_messages (wa_from, wa_to, profile_name, inbound, reply, lang, escalated, sent, created_at, meta)
  values ('whatsapp:+971500000099', '', 'ZZ DEMO sweep probe', 'ZZ DEMO sweep probe stuck', '', 'en', false, false, now() - interval '10 minutes', '{"stage":"received","audience":"founder"}'),
         ('whatsapp:+971500000099', '', 'ZZ DEMO sweep probe', 'ZZ DEMO sweep probe done', 'ok', 'en', false, true, now() - interval '10 minutes', '{"route":"faq","audience":"founder"}')
  returning id
) select count(*) from ins;

create temp table _sweep_probe on commit drop as
select public.fn_wa_arrival_sweep(100, 'whatsapp:+971500000099') as first_run, null::jsonb as second_run;
update _sweep_probe set second_run = public.fn_wa_arrival_sweep(100, 'whatsapp:+971500000099');

create temp table _sweep_verdict on commit drop as
select case
  when jsonb_array_length((select first_run from _sweep_probe)) <> 1 then 'PROBE FAILED: the stuck row was not taken exactly once on the first sweep'
  when jsonb_array_length((select second_run from _sweep_probe)) <> 0 then 'PROBE FAILED: a second sweep took the same row again'
  when (select count(*) from public.agent_actions where agent = 'customer_support' and target_table = 'wa_messages'
          and target_id in (select id::text from public.wa_messages where inbound like 'ZZ DEMO sweep probe%')) <> 1
    then 'PROBE FAILED: not exactly one customer_support action for the stuck row'
  when (select meta from public.wa_messages where inbound = 'ZZ DEMO sweep probe done') <> '{"route":"faq","audience":"founder"}'::jsonb
    then 'PROBE FAILED: the completed row was touched'
  else 'PROBE OK' end as verdict;

delete from public.agent_actions where target_table = 'wa_messages'
   and target_id in (select id::text from public.wa_messages where inbound like 'ZZ DEMO sweep probe%');
delete from public.wa_messages where inbound like 'ZZ DEMO sweep probe%';

select case when exists (select 1 from public.wa_messages where inbound like 'ZZ DEMO sweep probe%')
            then 'PROBE FAILED: probe rows were left behind' else verdict end as verdict
  from _sweep_verdict;
