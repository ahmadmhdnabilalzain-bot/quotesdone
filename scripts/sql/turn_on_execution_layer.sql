-- TURN ON THE AUTONOMOUS EXECUTION LAYER (deterministic only; OpenRouter stays OFF).
--
-- Founder confirmed 2 Sep 2026 ("turn it on now"; "lift all previous limits or frozen gates; the only
-- thing that remains blocked is OpenRouter"). The stand-down had all 9 pipeline crons inactive. This
-- re-enables the DETERMINISTIC executor dispatch and adds the deterministic in-department head-approval
-- driver, so authorized actions execute without the founder. It deliberately leaves the INFERENCE-BOUND
-- producers OFF (agent_action_work_sweep, and the consequential sweep whose targets call the LLM) while
-- OpenRouter is held, so no path attempts paid inference. GATE-032 was lifted separately
-- (lift_automation_hold_gate032.sql).
--
--   node scripts/apply_sql.mjs scripts/sql/turn_on_execution_layer.sql --apply --ddl

begin;

-- 1. Quarantine any inference-bound queued work (action_worker calls the LLM; OpenRouter held). Idempotent.
update public.action_execution
   set status = 'cancelled', finished_at = now(),
       response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
         'quarantined_by','launch_safe_unblock','at',now(),
         'reason','executor requires live LLM inference (OpenRouter held OFF); deterministic-only launch.')
 where status = 'queued' and action_class = 'agent_action_work';

-- 2. The deterministic in-department head-approval driver: pure rules, no inference. The entitled in-dept
--    head auto-approves parked medium-risk, reversible/compensatable, single-authority consequential
--    actions authored by a DIFFERENT agent. Never touches spend/contract dual-authority, high-risk, or
--    founder-reserved actions. It only calls fn_action_head_approve; the dispatcher then executes.
create or replace function public.fn_action_head_drive(p_limit integer default 20)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $fn$
declare r record; v_res jsonb; v_head text; v_reason text; v_ok int := 0; v_skip int := 0;
begin
  for r in
    select a.id, a.action_class, e.department, a.risk_tier,
           coalesce(a.author, a.request->>'actor', a.request->>'requested_by', a.request->>'author') as author,
           e.second_authority, e.required_authority, e.reversible, e.compensation_action_class
      from public.action_execution a
      join public.org_action_executor e on e.action_class = a.action_class
      join public.action_approval ap on ap.action_execution_id = a.id
     where a.status = 'queued'
       and a.response->>'invoker' = 'awaiting_head_approval'
       and ap.approval_decision = 'requested'
       and ap.consumed_at is null
       and a.risk_tier = 'medium'
       and e.second_authority is null
       and coalesce(e.required_authority,'') <> 'founder'
       and (e.reversible or e.compensation_action_class is not null)
     order by a.created_at
     limit greatest(coalesce(p_limit,20),1)
  loop
    begin
      v_res := public.fn_action_resolve_approver(r.department, r.risk_tier);
      v_head := v_res->>'approver';
      if v_head is null or (v_res->>'basis') not like 'department head of %' then
        v_skip := v_skip + 1; continue;
      end if;
      if r.author is null or coalesce(public.fn_org_agent_resolve(r.author), r.author) = v_head then
        v_skip := v_skip + 1; continue;
      end if;
      v_reason := format('auto-approved by in-department head %s under the medium-risk in-department policy: reversible/compensatable, author %s is independent. Deterministic driver, no inference.', v_head, r.author);
      perform public.fn_action_head_approve(r.id, 'approved', v_reason, v_head);
      v_ok := v_ok + 1;
    exception when others then
      v_skip := v_skip + 1;
      update public.action_execution
         set response = coalesce(response,'{}'::jsonb) || jsonb_build_object('head_drive_skipped', left(SQLERRM,300), 'at', now())
       where id = r.id;
    end;
  end loop;

  insert into public.agent_runs(agent,started_at,finished_at,status,counts,note)
  values ('action_head_drive', now(), now(), 'ok',
          jsonb_build_object('approved', v_ok, 'skipped', v_skip),
          format('In-dept heads auto-approved %s medium-risk action(s); %s skipped.', v_ok, v_skip));
  return jsonb_build_object('ok', true, 'approved', v_ok, 'skipped', v_skip, 'ran_at', now());
end $fn$;
revoke execute on function public.fn_action_head_drive(integer) from public;
grant execute on function public.fn_action_head_drive(integer) to service_role;

-- 3. Re-enable the deterministic executor dispatch pair (dispatch + collect). Idempotent.
select cron.alter_job((select jobid from cron.job where jobname='action_invoke_dispatch_5min'), active := true);
select cron.alter_job((select jobid from cron.job where jobname='action_invoke_collect_5min'),  active := true);

-- 4. Schedule the head-approval driver between dispatch runs (:03,:08,...). It self-gates on the parked
--    queue (does nothing when nothing is parked), so it is safe to leave running.
select cron.schedule('action_head_drive_5min','3,8,13,18,23,28,33,38,43,48,53,58 * * * *',
                     $$select public.fn_action_head_drive(20);$$);

-- 5. Register the two re-enabled/new crons that reach a watched relation (collect touches action_execution;
--    the head driver writes an agent_runs heartbeat), so fn_phase_d_committed_scenario_guards passes.
insert into public.phase_d_committed_scenario_cron(jobid, jobname, reaches, quarantine)
select j.jobid, j.jobname,
  case j.jobname
    when 'action_invoke_collect_5min' then 'public.action_execution (resolves dispatcher-set running rows to succeeded/failed) + public.dead_letter. Acts ONLY on rows the dispatcher already set to running; a committed fixture scenario dispatches nothing, so collect resolves nothing.'
    else 'public.agent_runs (a one-row-per-run heartbeat log) plus public.action_approval / action_execution ONLY when an action is parked awaiting_head_approval. A committed fixture scenario parks no action, so it writes only its own agent_runs heartbeat.'
  end,
  case j.jobname
    when 'action_invoke_collect_5min' then 'none required — no running rows exist in a fixture scenario, so a scenario open() has nothing of this cron to remove.'
    else 'the scenario open() removes the action_head_drive agent_runs heartbeat rows it produced; approvals/executions are never produced in a fixture scenario.'
  end
from cron.job j where j.jobname in ('action_invoke_collect_5min','action_head_drive_5min')
on conflict (jobid) do update set jobname=excluded.jobname, reaches=excluded.reaches, quarantine=excluded.quarantine;

-- 6. RPC executors (the bulk of the department capability) dispatch through the rpc invoker, which does
--    NOT call inference. Of the active rpc executors only one target called the LLM — deactivate it so
--    the deterministic-only bar holds — then enable the rpc dispatch cron. Verified end-to-end: a queued
--    org_scorecard action ran to 'succeeded' through fn_action_invoke_rpc (aborted-tx probe).
update public.org_action_executor
   set active = false, note = coalesce(note,'') || ' | deactivated 2 Sep 2026: target calls inference, held while OpenRouter is off'
 where kind = 'rpc' and active
   and exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                where n.nspname='public' and p.proname = org_action_executor.target
                  and pg_get_functiondef(p.oid) ~* 'ai_gateway|openrouter|llm\(');
select cron.alter_job((select jobid from cron.job where jobname='action_invoke_rpc_5min'), active := true);

commit;
