-- Rollback for K14. Restores fn_kernel_workflow_start block (e), the pre-emptive handoff run.
--
-- This deliberately reinstates the defect K14 removed: every workflow whose entry step carries an
-- outgoing edge (16 of 30) will again end up with TWO open handoff runs on that edge as soon as
-- the entry step completes, and the successor step can never be opened. Run it only to restore the
-- pre-2026-08-17 behaviour, never as a fix.
--
-- Restoring means re-applying the K2 file, which is the source of the block:
--
--   node scripts/apply_sql.mjs scripts/sql/kernel_k2_workflow_start.sql --apply --ddl
--
-- That file still contains block (e) verbatim, so no reconstruction is needed here and none is
-- attempted. Re-applying it replaces the K14 definition with the original one. Nothing else in
-- K14 changed: no table, no grant, no trigger, no data.
--
-- Check afterwards that the old behaviour is back, and that you meant it:
--
--   select public.fn_kernel_workflow_start(jsonb_build_object(
--     'workflow_id','W14','business_object_id','ZZ-ROLLBACK-PROBE','source_kind','autonomous',
--     'source_ref','rollback:k14','requested_by','probe'))->'created'->>'handoff';
--   -- '1' means block (e) is back. '0' means K14 is still deployed.
--
-- Run the probe inside a transaction you abort, or it leaves a real workflow run behind.

select 'K14 rollback is a re-apply of scripts/sql/kernel_k2_workflow_start.sql, not a script. '
       'See the comment block above.' as instruction;
