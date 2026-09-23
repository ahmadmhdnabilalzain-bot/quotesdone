-- A HELD QUESTION NEVER EXPIRES — AT 48 HOURS IT IS ESCALATED TO ITS SEAT, AND IT IS REPLAYED WHENEVER THE HOLD LIFTS.
-- Seat: it_engineer (shared platform). 23 Sep 2026, founder_instruction 886-903 (ledger 890), and the
-- coordinator's ruling the same day: the model hold will last a while, so a 7-day expiry would silently drop
-- the questions the hold is holding.
--
-- WHAT CHANGES (every_seat_reasons_before_it_answers.sql set expires_at = now() + 7 days on every channel
-- question and fn_reason_held_due marked it 'expired'):
--   1. fn_reason_hold files a question with NO expiry, whatever its surface.
--   2. fn_reason_held_due never expires anything; rows already given an expiry are cleared by this file, and a row
--      already marked 'expired' is put back to 'held'. After 5 failed attempts a row is still 'failed' (it stops
--      costing replays) — and it is escalated like a stale one, never dropped.
--   3. fn_reason_held_escalate (NEW) — runs every tick, under the hold too: a question held 48 hours or more, or
--      failed, becomes a human-visible pending item in the OWNING seat's queue (public.agent_actions, kind
--      'held_question', agent = the seat, target reasoning_held_question/<id>), once per row (escalated_at). It
--      returns the rows it escalated so the caller can tell a WhatsApp customer the question is being handled
--      (_shared/reasoned_delivery.ts holdingNotice). The row stays 'held' and is replayed the moment the gate opens.
--
-- Follows a_reasoned_answer_is_applied_by_its_own_surface.sql. Pending:
-- scripts/sql/pending/a_held_question_never_expires_it_is_escalated_at_48_hours.txt.
-- Proved in one aborted transaction: scripts/checks/decision_points_are_reasoned.test.mjs.

alter table public.reasoning_held_question add column if not exists escalated_at timestamptz;
update public.reasoning_held_question set expires_at = null where expires_at is not null;
update public.reasoning_held_question set status = 'held' where status = 'expired';

create or replace function public.fn_reason_hold(p_seat text, p_surface text, p_question text, p_request jsonb,
  p_plan jsonb, p_subject jsonb, p_reason text, p_dedupe_key text default null)
returns bigint
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_id bigint;
begin
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key)
  values (p_seat, p_surface, left(p_question, 8000), p_request, coalesce(p_plan, '{}'::jsonb), p_subject, p_reason, p_dedupe_key)
  on conflict (dedupe_key) do update set reason = excluded.reason, plan = excluded.plan
  returning id into v_id;
  return v_id;
end $fn$;
revoke execute on function public.fn_reason_hold(text, text, text, jsonb, jsonb, jsonb, text, text) from public, anon, authenticated;
grant execute on function public.fn_reason_hold(text, text, text, jsonb, jsonb, jsonb, text, text) to service_role;

create or replace function public.fn_reason_held_due(p_limit integer default 3)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_gate jsonb; v jsonb;
begin
  update public.reasoning_held_question set status = 'failed' where status = 'held' and attempts >= 5;
  v_gate := public.fn_kernel_paid_provider_gate('hold-probe/not-a-model');
  if coalesce(v_gate->>'rule', '') in ('founder_hold', 'no_paid_ai_switch', 'empty_route_state') then
    return '[]'::jsonb;
  end if;
  with due as (
    select id from public.reasoning_held_question
     where status = 'held' and attempts < 5
       and (last_attempt_at is null or last_attempt_at < now() - interval '10 minutes')
     order by last_attempt_at nulls first, created_at
     limit greatest(1, least(coalesce(p_limit, 3), 10))
     for update skip locked
  ), claimed as (
    update public.reasoning_held_question h set attempts = h.attempts + 1, last_attempt_at = now()
      from due where h.id = due.id
    returning h.id, h.seat, h.surface, h.request, h.subject
  )
  select coalesce(jsonb_agg(to_jsonb(claimed)), '[]'::jsonb) into v from claimed;
  return v;
end $fn$;
revoke execute on function public.fn_reason_held_due(integer) from public, anon, authenticated;
grant execute on function public.fn_reason_held_due(integer) to service_role;

create or replace function public.fn_reason_held_escalate(p_limit integer default 20)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v jsonb;
begin
  with stale as (
    select id from public.reasoning_held_question
     where escalated_at is null
       and (status = 'failed' or (status = 'held' and created_at <= now() - interval '48 hours'))
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
           left('A question held ' || case when m.status = 'failed' then 'after 5 failed reasonings' else 'for 48 hours' end
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
end $fn$;
revoke execute on function public.fn_reason_held_escalate(integer) from public, anon, authenticated;
grant execute on function public.fn_reason_held_escalate(integer) to service_role;
