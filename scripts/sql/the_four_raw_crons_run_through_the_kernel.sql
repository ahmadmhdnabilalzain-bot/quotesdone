-- THE FOUR RAW CRONS RUN THROUGH THE KERNEL (3 Sep 2026).
--
-- every_live_entry_point_is_a_component.sql declared the four active jobs no component owned. The
-- kernel boards then said the true thing about them: they are state-changing cron components that
-- do not run through fn_kernel_cron_exec, so their ticks leave no trace
-- (fn_kernel_system_trace_state.active_state_changing_cron_components_not_wrapped 4 of 96). Twenty-two
-- of the twenty-three other active jobs were wrapped in August; these four were missed because
-- nothing owned them. They are wrapped here with the owners the declaration gave them, and their
-- next tick is traced like every other job's.
--
--   node scripts/apply_sql.mjs scripts/sql/the_four_raw_crons_run_through_the_kernel.sql --apply --ddl
begin;
do $wrap$
declare r record; v jsonb;
begin
  for r in select * from (values
      (278::bigint, 'it_operations_engineer', 'product_eng'),
      (292::bigint, 'knowledge_director',     'data_intel'),
      (303::bigint, 'cybersecurity_engineer', 'product_eng'),
      (315::bigint, 'knowledge_director',     'data_intel')
    ) t(jobid, role_id, dept) loop
    v := public.fn_kernel_wrap_and_enable_cron(r.jobid, r.role_id, r.dept, 'routine_operational_decision');
    if coalesce((v->>'ok')::boolean, false) is not true then
      raise exception 'wrap of cron % failed: %', r.jobid, v;
    end if;
    raise notice 'cron %: %', r.jobid, v->>'action';
  end loop;
end $wrap$;

-- The wrap stamps its own boilerplate on the component; the owner and the reason the declaration
-- carried are kept.
update public.phase_c_component c
   set accountable_role_id = o.role_id, department_id = o.dept, authority_class = 'routine_operational_decision',
       activation_state = 'active',
       repair_or_keep_action = 'declared and wrapped 3 Sep 2026: an active job no component owned; now traced through fn_kernel_cron_exec like every other active job'
  from (values
      ('cron:phase_c_outbox_deliver_1min',       'it_operations_engineer', 'product_eng'),
      ('cron:company_self_knowledge_sync_15min', 'knowledge_director',     'data_intel'),
      ('cron:it_security_live_posture_hourly',   'cybersecurity_engineer', 'product_eng'),
      ('cron:kb_embed_ops_knowledge',            'knowledge_director',     'data_intel')
    ) o(component_id, role_id, dept)
 where c.component_id = o.component_id;

do $proof$
declare v_raw int; v_board text;
begin
  select count(*) into v_raw from cron.job where jobid in (278, 292, 303, 315) and (not active or command not ilike '%fn_kernel_cron_exec%');
  select actual into v_board from public.fn_kernel_system_trace_state() where check_name = 'active_state_changing_cron_components_not_wrapped';
  if v_raw > 0 then raise exception '% of the four jobs are still raw or inactive', v_raw; end if;
  if v_board is distinct from '0' and v_board not like '0 %' then raise exception 'board still reports unwrapped state-changing cron components: %', v_board; end if;
  raise notice 'proof: all four jobs run through fn_kernel_cron_exec; board active_state_changing_cron_components_not_wrapped = %', v_board;
end $proof$;
commit;
