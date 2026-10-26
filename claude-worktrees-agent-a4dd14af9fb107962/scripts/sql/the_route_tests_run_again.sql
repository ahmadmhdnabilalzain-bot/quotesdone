-- THE 86-CATEGORY ROUTE TESTS RUN AGAIN (4 Sep 2026).
--
-- The pack scorecard was run for the first time today (it needs the founder's knowledge packs
-- extracted; they were four unopened zips in Downloads, and the path is now recorded in the
-- session memory so the next session can run it). It reported 99.8% ingested across 37 of 37
-- artefacts and 36 of 37 IN USE, with exactly one artefact NOT READ BY ANY PRODUCTION ROUTINE:
--
--   1 - 86_CATEGORIES (routing) - route tests - probe returned 0 against fn_kb_route_test_run
--
-- The cause is the plainest kind: public.kb_operational_route_test holds 344 cases that assert how
-- a customer's words resolve to one of the 86 trade categories -- the front of the money loop -- and
-- cron 222 kb_route_tests_hourly, the only thing that runs them, has been inactive since the
-- stand-down. The capability was finished and had no entry point.
--
-- MEASURED BEFORE ENABLING, not after: driven by hand at 09:22 UTC, fn_kb_route_test_run(400) ran
-- all 344 in 8 seconds and returned passed 344, failed 0, regressions 0 (258 route_or_ask_scope_details
-- + 86 ask_clarifying_question, each matching its expected action). So this switch does not turn on a
-- red; it turns on a guard over something that is currently correct, which is the only honest moment
-- to turn one on.
--
-- WHAT IT WRITES, read before enabling: kb_operational_route_test.last_result / last_run_at, and on a
-- REGRESSION (a case that used to pass and now fails, not merely a failure) one agent_actions row for
-- knowledge_eng. It reaches no watched relation, sends nothing, calls no model, and does not page the
-- founder -- trg_page_high_agent_action pages only agents matching ^(finance|security|operations).
--
-- The component cron:kb_route_tests_hourly already exists, active, accountable to knowledge_director
-- in data_intel, so this wraps the job through the kernel and switches it on.
--
--   node scripts/apply_sql.mjs scripts/sql/the_route_tests_run_again.sql --apply --ddl
begin;

select public.fn_kernel_wrap_and_enable_cron(222, 'knowledge_director', 'data_intel');

insert into public.cron_registry (jobname, purpose)
select 'kb_route_tests_hourly',
       'Runs the 344 operational route tests of the 86-category catalogue against fn_kb_route_decide '
    || 'and records each result; raises an agent_actions incident for knowledge_eng only when a case '
    || 'that used to pass regresses. Deterministic, no model, no outbound, no watched relation.'
 where not exists (select 1 from public.cron_registry where jobname = 'kb_route_tests_hourly');

do $proof$
declare v_active boolean; v_cmd text; v_role text; v_wrapped int;
begin
  select j.active, j.command into v_active, v_cmd from cron.job j where j.jobid = 222;
  select count(*) into v_wrapped from public.phase_c_system_execution_wrapper w where w.jobid = 222;
  select c.accountable_role_id into v_role from public.phase_c_component c
   where c.component_id = 'cron:kb_route_tests_hourly';
  if not coalesce(v_active, false) then raise exception 'cron 222 is still inactive'; end if;
  if v_cmd not like '%fn_kernel_cron_exec(222)%' then raise exception 'cron 222 does not run through the kernel: %', v_cmd; end if;
  if v_wrapped <> 1 then raise exception 'cron 222 has % wrapper row(s), expected 1', v_wrapped; end if;
  if not exists (select 1 from public.org_role r where r.role_id = v_role and r.status = 'active') then
    raise exception 'cron 222 is accountable to %, which does not resolve to an active role', v_role;
  end if;
  raise notice 'proof: cron 222 active, wrapped, owned by % (an active role)', v_role;
end $proof$;
commit;
