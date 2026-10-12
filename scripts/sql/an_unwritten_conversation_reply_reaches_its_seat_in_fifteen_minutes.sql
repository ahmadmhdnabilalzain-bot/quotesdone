-- an_unwritten_conversation_reply_reaches_its_seat_in_fifteen_minutes — customer_support + sales_engineer, 12 Oct 2026.
-- Rulings 1195/1196/1197 and the review of #1335: when no model could write a conversation reply (or the guard
-- refused what it wrote), the person gets the fixed HELD NOTICE and the turn is filed in the reasoning queue
-- (wa_inbound.unwritten_reply, supplier_api.quote_review_unwritten). resilience_ping replays it through the model.
--   1. fn_reason_held_escalate: such a turn still held after 15 MINUTES (not 48 hours) goes to its seat
--      (customer_support / sales_engineer) as a held_question action; the WhatsApp customer is then told a person has
--      it (the existing holding notice). Every other surface keeps its 48 hours.
--   2. fn_reason_apply_supplier_api__quote_review_unwritten: the replayed answer is posted into the supplier's
--      quotation thread (WhatsApp answers are delivered by reasoned_delivery.ts already). A thread that has since been
--      submitted or closed is never written to.
-- CREATE OR REPLACE keeps fn_reason_held_escalate's ACL. The apply routine is NEW: revoked in this file.
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

create or replace function public.fn_reason_apply_supplier_api__quote_review_unwritten(p_id bigint, p_result jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_review uuid; v_answer text := btrim(coalesce(p_result ->> 'answer', '')); v_msg uuid;
begin
  select (h.subject ->> 'review_id')::uuid into v_review
    from public.reasoning_held_question h
   where h.id = p_id and h.subject ->> 'review_id' ~ '^[0-9a-fA-F-]{36}$';
  if v_review is null or v_answer = '' then
    return jsonb_build_object('posted', false, 'why', case when v_review is null then 'no review on the held turn' else 'empty answer' end);
  end if;
  insert into public.quote_review_messages (review_id, role, kind, body, body_ar, attachments, issues)
  select r.id, 'sales_engineer', 'text', left(v_answer, 4000), null, '[]'::jsonb, null
    from public.quote_reviews r
   where r.id = v_review and r.status not in ('submitted', 'closed')
  returning id into v_msg;
  return jsonb_build_object('posted', v_msg is not null, 'message_id', v_msg, 'review_id', v_review);
end $function$;

revoke execute on function public.fn_reason_apply_supplier_api__quote_review_unwritten(bigint, jsonb) from public, anon, authenticated;

-- Verdict row (the file defines routines, so it never raises): both routines are live and say what they must.
select case
  when position('wa_inbound.unwritten_reply' in pg_get_functiondef('public.fn_reason_held_escalate(integer)'::regprocedure)) = 0
    then 'PROBE FAILED: fn_reason_held_escalate does not carry the 15-minute rule'
  when to_regprocedure('public.fn_reason_apply_supplier_api__quote_review_unwritten(bigint,jsonb)') is null
    then 'PROBE FAILED: the quotation-thread apply routine is missing'
  when has_function_privilege('anon', 'public.fn_reason_apply_supplier_api__quote_review_unwritten(bigint,jsonb)', 'execute')
    then 'PROBE FAILED: anon can execute the apply routine'
  else 'PROBE OK' end as verdict;
