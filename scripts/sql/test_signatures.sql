select p.oid::regprocedure::text || '  ->  ' || pg_get_function_result(p.oid) as f
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and (p.proname like 'fn_p2c1_%test%' or p.proname like 'fn_p2c1_%suite%'
        or p.proname like 'fn_p2c1_holdout%' or p.proname like 'fn_p2c1_%regression%'
        or p.proname like 'fn_p2c1_rollback%')
 order by 1;
