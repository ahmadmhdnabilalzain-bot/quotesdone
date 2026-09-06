-- AN ESCALATED REMEDIATION OPENS ONE TASK, NOT TWO (6 Sep 2026).
--
-- fn_agent_remediation_escalate_consume opened the manager's org_task and then called
-- the founder notifier with kind remediation_escalated. Since the founder-mail policy landed the same
-- night, that kind is routed instead of emailed, and fn_founder_mail_route opened a second task for
-- the same escalation; the connectivity scenario "an escalated remediation opens a manager task ->
-- exactly one, deduplicated" read 2. The consumer's own task is the routing; the notify call goes.
-- Every other line is the live definition.
--
--   node scripts/apply_sql.mjs scripts/sql/an_escalated_remediation_opens_one_task.sql --apply --ddl
CREATE OR REPLACE FUNCTION public.fn_agent_remediation_escalate_consume()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_mgr text; v_dept text; v_title text; v_handled int := 0;
begin
  for r in select * from public.agent_remediation where status='escalated' loop
    v_title := 'Remediation escalated: '||r.agent_key||' / '||coalesce(r.competency, r.failure_class);
    if exists (select 1 from public.org_tasks where title = v_title and status <> 'done') then
      continue;   -- already consumed
    end if;
    v_mgr  := coalesce(public.fn_org_agent_resolve((select manager_key from public.org_agents where agent_key=r.agent_key)),
                       (select manager_key from public.org_agents where agent_key=r.agent_key));
    v_dept := coalesce((select department from public.org_agents where agent_key=v_mgr),
                       (select department from public.org_agents where agent_key=r.agent_key), 'exec');
    insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class, assigned_agent)
    values (v_dept, v_title,
      r.agent_key||' has exhausted remediation on '||coalesce(r.competency,r.failure_class)||' ('
      ||coalesce(r.attempts::text,'?')||'/'||coalesce(r.max_attempts::text,'?')||' attempts, latest score '
      ||coalesce(r.latest_score::text,'?')||'). Autonomy is still blocked. Decide: retrain, reassign, or downgrade seniority.',
      'assigned', 'supervised', false, 'remediation', v_mgr);
    -- 6 SEP 2026: the manager task opened above IS the routing. This used to also call
    -- the founder notifier with kind remediation_escalated; under the founder-mail policy that kind is
    -- routed, not emailed, and the router opened a SECOND task for the same escalation
    -- (org_connectivity_scenarios: "exactly one, deduplicated" read 2). The escalation reaches the
    -- founder through the brief's WITH THE ORGANISATION count, which reads org_tasks.
    v_handled := v_handled + 1;
  end loop;
  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('remediation_escalate_consume', now(), now(), 'ok', jsonb_build_object('handled', v_handled),
          'Escalated-remediation consumer: '||v_handled||' manager task(s) + founder notice(s) raised.');
  return jsonb_build_object('ok', true, 'handled', v_handled);
end $function$
