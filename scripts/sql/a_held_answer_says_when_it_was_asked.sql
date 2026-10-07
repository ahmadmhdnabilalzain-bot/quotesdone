-- A HELD ANSWER SAYS WHEN IT WAS ASKED -- it_engineer, 7 Oct 2026.
--
-- Ledger 1175 lifted the founder's hold; the replay (_shared/think.ts replayHeld) now drains the backlog in about an
-- hour instead of 17. Some of those questions were asked days ago. An answer to a stale question must not reach a
-- real person unreviewed, so the replay needs the question's age: fn_reason_held_due now returns created_at with each
-- claimed row. One change to the RETURNING list; body otherwise byte-copied from production (pg_get_functiondef,
-- 7 Oct 2026). CREATE OR REPLACE keeps the ACL.
-- Prevented by: supabase/functions/_shared/think.test.ts ('a stale held answer is stored, never sent unreviewed').

CREATE OR REPLACE FUNCTION public.fn_reason_held_due(p_limit integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_gate jsonb; v jsonb;
begin
  perform public.fn_reason_held_sweep();
  v_gate := public.fn_kernel_paid_provider_gate('hold-probe/not-a-model');
  if coalesce(v_gate->>'rule', '') in ('founder_hold', 'no_paid_ai_switch', 'empty_route_state') then
    return '[]'::jsonb;
  end if;
  with lead as (
    select distinct on (surface, coalesce(qhash, id::text)) id, attempts, last_attempt_at, created_at
      from public.reasoning_held_question
     where status = 'held' and attempts < 3
     order by surface, coalesce(qhash, id::text), attempts desc, id
  ), due as (
    select h.id from public.reasoning_held_question h
     where h.id in (select id from lead where last_attempt_at is null or last_attempt_at < now() - interval '10 minutes')
     -- 6 Oct: the NEWEST due question first; a retry (last_attempt_at set) still waits its 10 minutes, then goes
     -- behind untried rows exactly as before, so it is never starved past its three tries.
     order by h.last_attempt_at nulls first, h.created_at desc
     limit greatest(1, least(coalesce(p_limit, 3), 10))
     for update skip locked
  ), claimed as (
    -- 6 Oct: the first claim starts the 14-day clock (a question waits out the hold without ageing)
    update public.reasoning_held_question h set attempts = h.attempts + 1, last_attempt_at = now(),
           expires_at = case when h.attempts = 0 and h.surface not like 'site_assistant.%'
                             then now() + interval '14 days' else h.expires_at end
      from due where h.id = due.id
    returning h.id, h.seat, h.surface, h.request, h.subject, h.created_at
  )
  select coalesce(jsonb_agg(to_jsonb(claimed)), '[]'::jsonb) into v from claimed;
  return v;
end $function$
;
