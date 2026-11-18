-- A PROMPT THAT TIMED OUT TWICE AT THE MODEL GATEWAY IS NOT SENT AGAIN AT THE SAME SIZE AND EFFORT.
-- Seat: it_engineer (the reasoning queue). 18 Nov 2026. NOT APPLIED: see scripts/sql/pending/<this name>.txt.
--
-- MEASURED (production, read-only, ai_cost_log fn resilience_ping, 48 h to 18 Nov 2026 10:20Z, e2e_run_tag null):
--   * 53 of the 55 billed failed calls ended at the wall with 0 output tokens: the plan (routine_employee_reasoning, 26
--     calls) at 51.1-51.4 s of the 51.5-51.8 s the caller declared, the answer (internal_judgement) at 39.3-41.4 s on the CEO's
--     Opus (AED 0.22-0.24 a call) and at 89.6 s for it_engineer;
--   * the same prompt_hash failed again on the next tick (each failure logs a billed row and a 0-cost "ALL MODELS
--     FAILED" row): ceo 25 billed failures over 19 hashes, marketing 12 over 12, it_engineer 9 over 9 (0 ever
--     answered), sales_engineer 7 over 7, accountant 2 over 2;
--   * the rows (reasoning_held_question, 3 days) read result.reason 'model_failed: no reply' with the failed step
--     'gateway_http_502:gateway_deadline': 40 seat_duty and 6 order_conversation rows 'failed' at 3 tries, each try the
--     same request at the same high effort.
--
-- WHAT THIS CHANGES: fn_reason_held_due only, and in it only the claim's RETURNING list (diffed against the live
-- pg_get_functiondef of 18 Nov 2026: one comment and the returning line). The claim now also returns
--   attempts          the try this claim counted (after the increment);
--   gateway_timeouts  how many earlier tries ended at the model's wall: the count the replay writes on the row's result
--                     (result.gateway_timeouts, _shared/think/replay.ts), or, for a row whose last result was written
--                     before that count existed, 1 when that result was a timeout (a failed model step - decompose,
--                     synthesise or verify - whose detail names gateway_deadline, gateway_wall or a timeout; a
--                     turn_deadline is a call never started) and 0 if not.
-- The edge half (_shared/think/replay.ts replayShape) reads it: after two timeouts an internal row is sent once lighter
-- (medium effort; a decision skips the planner for the one-step plan) and a customer's, supplier's or visitor's row is
-- not sent again; either close files a finding for the owning seat. The 3-try bound, the order, the 10-minute retry
-- wait, the 14-day clock, the hold gate, the re-ask exclusion and the fan-out are unchanged. Apply order is free: the
-- edge reads an absent field as 0 (today's behaviour), and today's edge ignores the two new fields.
--
-- CREATE OR REPLACE keeps the routine's ACL; the revoke below names its one signature (fn_reason_held_due(integer),
-- the only overload on production, 18 Nov 2026). search_path stays pinned.
-- Prevented by: supabase/functions/_shared/a_prompt_that_timed_out_twice_is_not_resent.test.ts

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
       and not (surface = any(public.fn_reask_surfaces()))   -- 27 Oct 2026: asked again by fn_reask_due, every minute
     order by surface, coalesce(qhash, id::text), attempts desc, id
  ), due as (
    select h.id from public.reasoning_held_question h
     where h.id in (select id from lead where last_attempt_at is null or last_attempt_at < now() - interval '10 minutes')
     -- 27 Oct: the OLDEST due question first (was: untried first, then newest, 6 Oct). A retry still waits its 10
     -- minutes; after that its age alone decides. The three-try bound keeps one failing row from holding the head.
     order by h.created_at, h.id
     limit greatest(1, least(coalesce(p_limit, 3), 10))
     for update skip locked
  ), claimed as (
    -- 6 Oct: the first claim starts the 14-day clock (a question waits out the hold without ageing)
    update public.reasoning_held_question h set attempts = h.attempts + 1, last_attempt_at = now(),
           expires_at = case when h.attempts = 0 and h.surface not like 'site_assistant.%'
                             then now() + interval '14 days' else h.expires_at end
      from due where h.id = due.id
    -- 18 Nov: the try counted, and the earlier tries that timed out at the model's wall (the replay sends no third at the same size)
    returning h.id, h.seat, h.surface, h.request, h.subject, h.created_at, h.attempts,
              greatest(case when h.result->>'gateway_timeouts' ~ '^[0-9]+$' then (h.result->>'gateway_timeouts')::int else 0 end,
                       case when h.result->>'status' is distinct from 'answered' and jsonb_typeof(h.result->'steps') = 'array'
                             and exists (select 1 from jsonb_array_elements(h.result->'steps') s
                                          where s->>'status' = 'failed' and s->>'kind' in ('decompose', 'synthesise', 'verify')
                                            and coalesce(s->>'detail', '') ~* 'gateway_deadline|gateway_wall|timed? ?out|timeout'
                                            and coalesce(s->>'detail', '') !~* '^turn_deadline')
                            then 1 else 0 end) as gateway_timeouts
  )
  select coalesce(jsonb_agg(to_jsonb(claimed)), '[]'::jsonb) into v from claimed;
  return v;
end $function$;
revoke execute on function public.fn_reason_held_due(integer) from public, anon, authenticated;
