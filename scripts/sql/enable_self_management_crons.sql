-- SELF-MANAGEMENT LOOP — enable the deterministic KPI / review / learning crons.
--
-- These are pure-SQL, no-model routines: they measure employee and department KPIs, review
-- objectives and outcomes, run the learning loop and promotion review, and refresh strategy — the
-- deterministic half of "every agent is measured and improves". They sat inactive after the
-- stand-down. This wraps each as a traced kernel component (command -> fn_kernel_cron_exec(jobid))
-- and activates it, exactly like reenable_the_dispatch_and_action_runtime.sql.
--
-- ACCOUNTABLE ROLE MUST RESOLVE IN org_role. fn_kernel_system_execution_trace RAISES
-- 'accountable role X does not resolve in org_role' at every tick otherwise — a scheduled execution
-- nobody owns is refused. The roles below are real org_role.role_id values (verified against the
-- live 176-role set): performance/measurement work -> corporate_performance_director (exec, owns the
-- KPI scoreboard, improvement initiatives and outcome grading); quality self-review ->
-- quality_and_release_director (assurance); objective/strategy review -> ceo (exec); the
-- agent-action work sweep -> chief_operating_officer (people_ops).
--
-- fn_kernel_wrap_and_enable_cron EARLY-RETURNS when a job is already wrapped and does NOT then update
-- the accountable role, so the reconciling UPDATE below is what corrects the role on a re-apply.
--
--   node scripts/apply_sql.mjs scripts/sql/enable_self_management_crons.sql --apply --ddl

-- Wrap + enable (first apply on a clean DB sets the correct role directly).
select public.fn_kernel_wrap_and_enable_cron(250, 'corporate_performance_director', 'exec');       -- employee_kpi_measure
select public.fn_kernel_wrap_and_enable_cron(249, 'corporate_performance_director', 'exec');       -- dept_objective_measure
select public.fn_kernel_wrap_and_enable_cron(194, 'ceo', 'exec');                                  -- os_objective_measure
select public.fn_kernel_wrap_and_enable_cron(140, 'corporate_performance_director', 'exec');       -- kpi_review
select public.fn_kernel_wrap_and_enable_cron(139, 'quality_and_release_director', 'assurance');    -- self_review
select public.fn_kernel_wrap_and_enable_cron(184, 'corporate_performance_director', 'exec');       -- improvement_plan
select public.fn_kernel_wrap_and_enable_cron(204, 'corporate_performance_director', 'exec');       -- learning_loop_sweep
select public.fn_kernel_wrap_and_enable_cron(143, 'corporate_performance_director', 'exec');       -- outcome_evaluate
select public.fn_kernel_wrap_and_enable_cron(205, 'corporate_performance_director', 'exec');       -- improvement_handover
select public.fn_kernel_wrap_and_enable_cron(285, 'ceo', 'exec');                                  -- objective_review
select public.fn_kernel_wrap_and_enable_cron(156, 'ceo', 'exec');                                  -- os_review
select public.fn_kernel_wrap_and_enable_cron(282, 'corporate_performance_director', 'exec');       -- promotion_review
select public.fn_kernel_wrap_and_enable_cron(84,  'ceo', 'exec');                                  -- strategy_ai
select public.fn_kernel_wrap_and_enable_cron(243, 'chief_operating_officer', 'people_ops');        -- agent_action_work_sweep_hourly

-- Reconcile the accountable role on the component for already-wrapped jobs (the wrap fn early-returns).
update public.phase_c_component c
   set accountable_role_id = m.role, department_id = m.dept, activation_state = 'active'
  from (values
    (250,'corporate_performance_director','exec'), (249,'corporate_performance_director','exec'),
    (194,'ceo','exec'),                            (140,'corporate_performance_director','exec'),
    (139,'quality_and_release_director','assurance'),(184,'corporate_performance_director','exec'),
    (204,'corporate_performance_director','exec'), (143,'corporate_performance_director','exec'),
    (205,'corporate_performance_director','exec'), (285,'ceo','exec'),
    (156,'ceo','exec'),                            (282,'corporate_performance_director','exec'),
    (84,'ceo','exec'),                             (243,'chief_operating_officer','people_ops')
  ) as m(jobid, role, dept)
  join public.phase_c_system_execution_wrapper w on w.jobid = m.jobid
 where c.component_id = w.component_id;

-- Guard: every wrapped self-management job's accountable role must resolve in org_role.
do $$
declare v_bad int;
begin
  select count(*) into v_bad
    from public.phase_c_system_execution_wrapper w
    join public.phase_c_component c on c.component_id = w.component_id
   where w.jobid in (250,249,194,140,139,184,204,143,205,285,156,282,84,243)
     and not exists (select 1 from public.org_role r where r.role_id = c.accountable_role_id);
  if v_bad > 0 then
    raise exception '% self-management cron component(s) still carry an unresolvable accountable role', v_bad;
  end if;
end $$;
