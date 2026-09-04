-- DOWN for scripts/sql/phase_e_retire_the_no_caller_functions.sql (4 Sep 2026).
--
-- Nothing runs this (scripts/sql/down/README.md). DROP FUNCTION has no SQL down: the 42 routines come
-- back only by re-applying their canonical files from git (each still sits in scripts/sql; the
-- canonical engine names the file per routine), and the exposure-scope rows and ownership-ledger rows
-- come back with them through the engine's --emit-ledger-sync. What THIS file reverses is the component
-- bookkeeping, so a restored routine is not still recorded as retired: every row this drop marked
-- INTENTIONALLY_RETIRED returns to DEFERRED_RUNTIME_IMPLEMENTATION / inactive with the evidence it
-- carried before (the measured "no caller" finding).
--
-- Order: re-apply the canonical files FIRST, then run this; the component classification guard
-- refuses DEFERRED_RUNTIME_IMPLEMENTATION on a routine that has a caller, and none of these had one.
begin;

update public.phase_c_component
   set activation_state = 'inactive', classification = 'DEFERRED_RUNTIME_IMPLEMENTATION',
       gap = 'no trigger, cron, routine, edge function or frontend caller; entry=none',
       repair_or_keep_action = 'Phase D: give it a caller and an entry point, or retire it',
       evidence = 'restored by phase_e_retire_the_no_caller_functions_down.sql; previously: ' || evidence
 where classification = 'INTENTIONALLY_RETIRED'
   and evidence like 'phase_e_retire_the_no_caller_functions.sql 2026-09-04:%';

do $ctl$
declare v_left int;
begin
  select count(*) into v_left from public.phase_c_component
   where evidence like 'phase_e_retire_the_no_caller_functions.sql 2026-09-04:%' and classification = 'INTENTIONALLY_RETIRED';
  if v_left > 0 then raise exception '% component row(s) still marked retired by the Phase E drop', v_left; end if;
end $ctl$;

commit;
