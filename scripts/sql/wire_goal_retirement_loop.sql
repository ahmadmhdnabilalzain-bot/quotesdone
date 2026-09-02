-- Wire the goal_retirement_replan loop end-to-end. Two deterministic connectivity gaps, both
-- surfaced by the estate's OWN instruments (not an LLM audit), both in the same loop:
--
--   EXEC-01  public.v_workflow_side_effects_without_executor returns exactly one row:
--            goal_retirement_replan step 1, action_class 'verify', has no active org_action_executor.
--            The step ("Confirm the objectives serving the retired goal are superseded") can never
--            execute because no executor backs the 'verify' class.
--
--   OA-01    public.company_event carries no live subscriber for 'goal.retired', yet trg_goal_cascade
--            emits it (verified: pg_get_functiondef(trg_goal_cascade) contains 'goal.retired'). The
--            dispatcher public.fn_event_dispatch delivers ONLY through public.event_subscription, so a
--            retired goal reaches no agent. Its mirror, 'goal.at_risk', is subscribed by ceo; the
--            re-plan is corporate-performance work, owned by corporate_performance_director -> cpo,
--            who owns all three steps of goal_retirement_replan.
--
-- Neither table is a frozen Phase A/B/C subject (org_action_executor, event_subscription are runtime
-- wiring), so no freeze amendment is required. Both are plain, reversible inserts.
--
--   node scripts/apply_sql.mjs scripts/sql/wire_goal_retirement_loop.sql --apply --ddl

begin;

-- EXEC-01 target. Deterministic, read-only verification: for every RETIRED company goal
-- (company_goals.active = false), confirm the department_objective rows that serve it
-- (goal_key = the goal) are superseded (status = 'superseded'). A real check — it returns ok=false
-- when an objective still serves a retired goal, and currently returns ok=true only because no goal
-- is retired yet. Argless + returns jsonb: the exact contract public.fn_action_invoke_rpc requires.
create or replace function public.fn_verify_objectives_superseded()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_retired int; v_pending int; v_details jsonb;
begin
  select count(*) into v_retired from public.company_goals where active = false;

  select count(*),
         coalesce(jsonb_agg(jsonb_build_object(
           'objective_id', o.id, 'dept', o.dept_key, 'goal_key', o.goal_key, 'status', o.status)
           order by o.id), '[]'::jsonb)
    into v_pending, v_details
  from public.department_objective o
  where o.goal_key is not null
    and exists (select 1 from public.company_goals g where g.key = o.goal_key and g.active = false)
    and coalesce(o.status, '') <> 'superseded'
    and coalesce(o.active, true) = true;

  return jsonb_build_object(
    'ok', v_pending = 0,
    'verified_at', now(),
    'retired_goals', v_retired,
    'objectives_pending_supersession', v_pending,
    'pending', v_details,
    'note', case when v_pending = 0
                 then 'Every objective serving a retired goal is superseded'
                 else format('%s objective(s) still serve a retired goal and are not superseded', v_pending)
            end);
end
$function$;

-- CREATE grants EXECUTE to PUBLIC for a SECURITY DEFINER function; revoke it (skill §5).
revoke execute on function public.fn_verify_objectives_superseded() from public;

-- rpc executors run as service-role, so fn_org_action_executor_guard refuses any target not
-- deliberately allow-listed. This target is read-only (no writes, no money, no external HTTP, no
-- model call) — it only reads company_goals + department_objective and returns a jsonb verdict.
insert into public.org_action_executor_rpc_allowed (target, note)
values ('fn_verify_objectives_superseded',
        'exec verify executor for goal_retirement_replan step 1; read-only, deterministic, zero-arg (2026-09-02 expert-staff standard)')
on conflict (target) do nothing;

-- EXEC-01 executor. Metadata mirrors the working fn_self_review executor exactly (low / advisory_safe
-- / reversible, compensation declared so v_executor_registry_gaps does not flag it, notifies_human
-- false so the rpc invoker's human-notification gate passes). owner exec / leadership, matching the
-- workflow's os_key and the cpo owner of the step.
insert into public.org_action_executor
  (action_class, kind, target, params, active, note, advisory_safe, department, owner_os,
   risk_tier, reversible, idempotency_strategy, timeout_seconds, max_attempts,
   required_authority, compensation_action_class, notifies_human, unattended_ok)
values
  ('verify', 'rpc', 'fn_verify_objectives_superseded', '{}'::jsonb, true,
   'Confirms the objectives serving a retired company goal are superseded (goal_retirement_replan step 1).',
   true, 'exec', 'leadership', 'low', true, 'natural_key', 60, 1,
   null, 'manual_reversal', false, false)
on conflict (action_class) do update
  set active = excluded.active, kind = excluded.kind, target = excluded.target,
      department = excluded.department, owner_os = excluded.owner_os, risk_tier = excluded.risk_tier,
      advisory_safe = excluded.advisory_safe, reversible = excluded.reversible,
      idempotency_strategy = excluded.idempotency_strategy,
      compensation_action_class = excluded.compensation_action_class,
      notifies_human = excluded.notifies_human, note = excluded.note;

-- OA-01 subscription. Mirrors goal.at_risk -> ceo; goal.retired -> cpo (owns goal_retirement_replan).
insert into public.event_subscription (agent_key, event_type, reason, active)
values ('cpo', 'goal.retired',
        'Re-plan department objectives after a company goal is retired (goal_retirement_replan)', true)
on conflict (agent_key, event_type) do update set active = true, reason = excluded.reason;

commit;
