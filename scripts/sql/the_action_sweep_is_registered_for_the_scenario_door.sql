-- THE ACTION SWEEP IS REGISTERED FOR THE SCENARIO DOOR (6 Sep 2026).
--
-- held-rows-go-to-their-owners taught fn_agent_action_work_sweep to settle auto/notify/officer kinds
-- itself, which means cron 243 agent_action_work_sweep_hourly now reaches org_tasks (a watched
-- relation) through fn_agent_action_hand_to_owner. fn_phase_d_committed_scenario_guards reads
-- every_active_cron_that_reaches_a_watched_relation_is_registered and went red with
-- "1 unregistered: 243 agent_action_work_sweep_hourly"; the scenario door then refused to open and
-- kernel_positive_controls failed on fn_phase_d_committed_scenario_close. The register catches up
-- with the mechanism: what the sweep reaches and why a scenario's rows are not its finding.
--
--   node scripts/apply_sql.mjs scripts/sql/the_action_sweep_is_registered_for_the_scenario_door.sql --apply --ddl
begin;

do $reg$
declare v_job bigint;
begin
  select jobid into v_job from cron.job where jobname = 'agent_action_work_sweep_hourly';
  if v_job is null then raise exception 'agent_action_work_sweep_hourly is not scheduled'; end if;

  insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine) values
    (v_job, 'agent_action_work_sweep_hourly',
     'UPDATEs public.agent_actions (status auto_done / notified / superseded / cancelled with detail.settled_reason); INSERTs public.org_tasks through fn_agent_action_hand_to_owner (fn_org_task_* lane) and public.notifications for the accountable role. Reads agent_action_kind_policy, org_agents, org_departments.',
     'Hourly in its own transaction. It settles agent_actions by KIND POLICY; a committed scenario''s ZZ DEMO fixture rows are cancelled as fixtures (settled_reason=fixture), never worked, and close() asserts scenario rows by id/marker. It creates no outbound HTTP request.')
  on conflict (jobid) do update set jobname = excluded.jobname, reaches = excluded.reaches, quarantine = excluded.quarantine;
end $reg$;

do $proof$
declare v_bad text;
begin
  select string_agg(g.check_name || ': ' || g.detail, ' | ') filter (where not g.ok) into v_bad
    from public.fn_phase_d_committed_scenario_guards() g;
  if v_bad is not null then raise exception 'a scenario-door guard is still red: %', v_bad; end if;
  raise notice 'proof: every scenario-door guard is green; agent_action_work_sweep_hourly registered';
end $proof$;

commit;
