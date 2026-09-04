-- DOWN for scripts/sql/phase_e_retire_the_frozen_baseline_boards.sql (4 Sep 2026).
--
-- Nothing runs this (scripts/sql/down/README.md). It reverses the DATA edits that file made: the
-- GATE-001 rows in phase_b_gate / phase_c_gate_binding / phase_d_gate_contract and the two
-- phase_c_component rows. It does NOT restore the two dropped routines or the three re-defined
-- bodies — DROP FUNCTION and CREATE OR REPLACE have no SQL down; recover those from git
-- (supabase/migrations/20260815070000_phase_a_frozen_founder_approved.sql,
-- scripts/sql/phase_b_11_baseline_functions.sql, and the last manifest file before this one that
-- defines fn_phase_c_invariants / fn_phase_b_invariants / fn_phase_d_gate_evaluate) and re-apply.
-- Restoring GATE-001's old predicate without restoring fn_phase_a_baseline_drift leaves the gate
-- pointing at a routine that does not exist, so apply the git recovery FIRST.
begin;

update public.phase_b_gate
   set gate_name = 'Phase A baseline frozen',
       pass_result = 'Proceed without changing organization.',
       fail_result = 'Stop and create formal Phase A change request.',
       required_evidence = 'Phase A founder-approved tag, fingerprints and registries exist.'
 where gate_id = 'GATE-001';

update public.phase_c_gate_binding
   set gate_name = 'Phase A baseline frozen',
       evidence = 'phase_b_gate GATE-001 scope=ALL type=hard'
 where gate_id = 'GATE-001';

update public.phase_d_gate_contract
   set refusal_code = 'gate001_phase_a_not_frozen',
       evidence_source = 'public.fn_phase_a_baseline_drift() and the Phase A row in public.org_phase_baseline'
 where gate_id = 'GATE-001';

update public.phase_c_component
   set activation_state = 'deployed', classification = 'CANONICAL_KEEP', gap = '', repair_or_keep_action = 'keep',
       evidence = 'restored by phase_e_retire_the_frozen_baseline_boards_down.sql'
 where component_id = 'dbfn:fn_phase_a_baseline_drift()';
update public.phase_c_component
   set activation_state = 'deployed', classification = 'ACTIVE_INTERNAL_CALLER', gap = '', repair_or_keep_action = 'keep',
       evidence = 'restored by phase_e_retire_the_frozen_baseline_boards_down.sql'
 where component_id = 'dbfn:fn_phase_b_baseline_drift()';

do $ctl$
begin
  if not exists (select 1 from public.phase_b_gate where gate_id = 'GATE-001' and gate_name = 'Phase A baseline frozen') then
    raise exception 'GATE-001 was not restored';
  end if;
end $ctl$;

commit;
