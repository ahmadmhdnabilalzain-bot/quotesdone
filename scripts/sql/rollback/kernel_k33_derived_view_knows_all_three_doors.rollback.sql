-- Rollback for kernel_k33_derived_view_knows_all_three_doors. See the file header for what it does and why.
--
-- These are MEASUREMENT corrections. Rolling one back does not change a single source's behaviour;
-- it changes what the estate reports about them, back to a number that was wrong. K33 restores a
-- predicate that reports eleven cut-over sources as bypassing; K34 removes the only check that can
-- judge an Edge Function at all; K32 replaces measured statuses with stale ones.
--
-- If a number here looks wrong, the fix is almost never this file — it is to correct the evidence
-- the source names in phase_c_source_cutover.disposition_evidence, which is a row somebody reads.

select 'Rollback for kernel_k33_derived_view_knows_all_three_doors: re-apply the file that previously defined the object named in its header. '
       'These are measurement corrections; rolling one back restores a wrong number, not a '
       'different behaviour.' as instruction;
