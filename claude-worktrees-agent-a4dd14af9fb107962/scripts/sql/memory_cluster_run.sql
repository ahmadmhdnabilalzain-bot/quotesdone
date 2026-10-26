-- First execution of the three memory-cluster writers, applied to staging and production.
-- Separate from the DDL file on purpose: a function's effects must be READ BACK in a statement of
-- their own. A single statement shares one snapshot, so calling a function and counting its rows in
-- the same UNION returns the pre-call state.
--   node scripts/apply_sql.mjs scripts/sql/memory_cluster_run.sql --promote --ddl
select public.fn_sop_update();
select public.fn_promote_memory_sweep(20);
select public.fn_improvement_plan_refresh();
