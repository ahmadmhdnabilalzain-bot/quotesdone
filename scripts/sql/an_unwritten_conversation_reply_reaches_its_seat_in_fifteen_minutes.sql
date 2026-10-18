-- an_unwritten_conversation_reply_reaches_its_seat_in_fifteen_minutes — customer_support + sales_engineer, 12 Oct 2026.
-- Rulings 1195/1196/1197 and the review of #1335: when no model could write a conversation reply (or the guard
-- refused what it wrote), the person gets the fixed HELD NOTICE and the turn is filed in the reasoning queue
-- (wa_inbound.unwritten_reply, supplier_api.quote_review_unwritten). resilience_ping replays it through the model.
--   1. fn_reason_held_escalate: such a turn still held after 15 MINUTES (not 48 hours) goes to its seat
--      (customer_support / sales_engineer) as a held_question action; the WhatsApp customer is then told a person has
--      it (the existing holding notice). Every other surface keeps its 48 hours.
--   2. The replayed answer is NOT applied by a routine: reasoned_delivery.ts hands think()'s answer to aiReply as a draft
--      to check, and only aiReply's guarded text is sent on WhatsApp or posted into the quotation thread.
-- CREATE OR REPLACE keeps fn_reason_held_escalate's ACL; nothing new is created.
-- Applied at merge (release operator), never before.

create or replace function public.fn_reason_held_escalate(p_limit integer default 20)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v jsonb;
begin
  with stale as (
    select id from public.reasoning_held_question
     where escalated_at is null
       and (status = 'failed'
            or (status = 'held' and created_at <= now() - interval '48 hours')
            -- a person is waiting on a conversation reply no model could write: 15 minutes, not 48 hours
            or (status = 'held' and surface in ('wa_inbound.unwritten_reply', 'supplier_api.quote_review_unwritten')
                and created_at <= now() - interval '15 minutes'))
     order by created_at
     limit greatest(1, least(coalesce(p_limit, 20), 100))
     for update skip locked
  ), marked as (
    update public.reasoning_held_question h set escalated_at = now()
      from stale where h.id = stale.id
    returning h.id, h.seat, h.surface, h.question, h.subject, h.status, h.created_at
  ), filed as (
    insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
    select m.seat, 'held_question', 'pending', 'low',
           left('A question held ' || case when m.status = 'failed' then 'after 5 failed reasonings'
                                           when m.surface in ('wa_inbound.unwritten_reply', 'supplier_api.quote_review_unwritten')
                                             then '15 minutes with no model-written reply (the person has only the held notice)'
                                           else 'for 48 hours' end
                || ' on ' || m.surface || ' needs you', 200),
           jsonb_build_object('held_id', m.id, 'surface', m.surface, 'question', left(m.question, 1000), 'subject', m.subject,
                              'held_since', m.created_at, 'status', m.status,
                              'waiting_for', m.seat || ' to answer or act on it; it is also replayed the moment the model hold lifts'),
           'reasoning_held_question', m.id::text
      from marked m
    returning id
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'seat', m.seat, 'surface', m.surface, 'question', left(m.question, 500),
                                              'subject', m.subject, 'status', m.status)), '[]'::jsonb)
    into v from marked m where (select count(*) from filed) >= 0;
  return v;
end $function$;

-- Verdict row (the file defines a routine, so it never raises).
select case
  when position('wa_inbound.unwritten_reply' in pg_get_functiondef('public.fn_reason_held_escalate(integer)'::regprocedure)) = 0
    then 'PROBE FAILED: fn_reason_held_escalate does not carry the 15-minute rule'
  else 'PROBE OK' end as verdict;
