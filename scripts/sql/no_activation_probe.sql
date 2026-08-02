-- Nothing customer-visible may have been switched on by this session.
select 'mep_trade_route rows: ' || count(*)::text as line from public.mep_trade_route
union all
select 'inquiry_workstream rows (live): ' || count(*)::text from public.inquiry_workstream
union all
select 'inquiry_workstream_group rows (live): ' || count(*)::text from public.inquiry_workstream_group
union all
select 'inquiry_scope_disposition rows: ' || count(*)::text from public.inquiry_scope_disposition
union all
select 'holdout cases: ' || count(*)::text from public.p2c1_holdout_case
union all
select 'holdout result of record rows: ' || count(*)::text || ' (must be 1, immutable)'
  from public.p2c1_holdout_result_of_record
union all
select 'holdout seal intact: ' || (fn_p2c1_holdout_verify_seal() ->> 'intact')
union all
select 'inquiry_state_audit rows: ' || count(*)::text from public.inquiry_state_audit
union all
select 'rollback functions present: ' || string_agg(p.proname, ', ' order by p.proname)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname in ('fn_p2c1_rollback_stage_b','fn_p2c1_rollback_stage_b6');
