-- =================================================================================================
-- Phase D — D56. The ownership ledger still named the file the routine used to live in.
--
-- application_source_of_truth.test.mjs check 6 — "ledger claims the repository denies" — reports 2
-- of 1225, and both are this increment's:
--
--     fn_kernel_workflow_start(p_input jsonb)  ledger: kernel_k14_start_does_not_pre_hand_off.sql
--                                              manifest order: phase_d_d36_…
--     fn_os_portals_gates()                    ledger: fn_os_portals_gates.sql
--                                              manifest order: phase_d_d55_…
--
-- public.kernel_routine_ownership records which file each live routine comes from. D36 and D55
-- replaced one routine each with a new file, and the manifest was appended correctly — the ledger
-- was not. Nothing is wrong with the routines; the record of where they come from went stale, which
-- is precisely what that check exists to catch.
--
-- THE STATEMENTS BELOW WERE NOT TYPED. They are the output of
--     node scripts/checks/application_source_of_truth.test.mjs --emit-ledger-sync
-- which the test provides for this purpose, so the ledger is reconciled to what the manifest says
-- rather than to what somebody believed it said.
--
-- WORTH RECORDING: the check found these 2 only because the same commit fixed its CSV reader. It
-- parsed the emitted manifest with a split on ',', so every QUOTED multi-argument signature was
-- truncated at its first argument and silently skipped — 403 of 1195 rows, 33.7%, including every
-- multi-argument Phase D routine. Check 7 had been reading 0 against a denominator a third short of
-- the estate.
-- =================================================================================================

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/phase_d_d55_the_evidence_stated_the_predicates_own_premise.sql',
       evidence = 'records source_file scripts/sql/fn_os_portals_gates.sql, manifest order says scripts/sql/phase_d_d55_the_evidence_stated_the_predicates_own_premise.sql — reconciled mechanically 17 Aug 2026 (kernel_s0c).'
 where schema_name = 'public' and routine_name = 'fn_os_portals_gates'
   and coalesce(identity_args,'') = '';

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/phase_d_d36_the_kernel_opens_the_step_and_now_runs_it.sql',
       evidence = 'records source_file scripts/sql/kernel_k14_start_does_not_pre_hand_off.sql, manifest order says scripts/sql/phase_d_d36_the_kernel_opens_the_step_and_now_runs_it.sql — reconciled mechanically 17 Aug 2026 (kernel_s0c).'
 where schema_name = 'public' and routine_name = 'fn_kernel_workflow_start'
   and coalesce(identity_args,'') = 'p_input jsonb';

-- ---- CONTROL ------------------------------------------------------------------------------------
do $ctl$
declare r record; v_bad text := '';
begin
  for r in select o.routine_name, coalesce(o.identity_args,'') ia, o.source_file
             from public.kernel_routine_ownership o
            where o.schema_name = 'public'
              and o.routine_name in ('fn_kernel_workflow_start','fn_os_portals_gates') loop
    if r.source_file not like 'scripts/sql/phase_d_d%' then
      v_bad := v_bad || format(' [%s(%s) still records %s]', r.routine_name, r.ia, r.source_file);
    end if;
  end loop;
  if v_bad <> '' then
    raise exception 'D56: the ledger was not reconciled:%', v_bad;
  end if;

  -- and the update must not have painted the whole table, which an unbounded where would do
  if (select count(*) from public.kernel_routine_ownership
       where source_file like 'scripts/sql/phase_d_d36%'
          or source_file like 'scripts/sql/phase_d_d55%') <> 2 then
    raise exception 'D56: % row(s) now point at d36 or d55; exactly 2 should.',
      (select count(*) from public.kernel_routine_ownership
        where source_file like 'scripts/sql/phase_d_d36%'
           or source_file like 'scripts/sql/phase_d_d55%');
  end if;

  raise notice 'D56: both ownership rows reconciled to the manifest, and no other row moved.';
end
$ctl$;
