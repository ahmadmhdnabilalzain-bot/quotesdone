-- =================================================================================================
-- Phase D — E6. The record still claimed the door E4 closed.
--
-- FOUND BY THE ESTATE'S OWN BOARD, not by looking for it. Minutes after E4 revoked the 57 grants,
-- `node --test scripts/checks/kernel_boards_are_green.test.mjs` went red on a board E4 never
-- mentions:
--
--     fn_kernel_component_exposure_state.external_entry_disagrees_with_derivation
--       expected 0 of 149, got 3 of 149 (recorded vocabulary no / unauthenticated_only / yes)
--
-- That check compares a RECORDED column, public.phase_c_component.external_entry, against a value
-- DERIVED from the catalogue by fn_kernel_component_reachability. E4 changed the catalogue. The
-- three rows that now disagree are exactly the three that K11 promoted on 16 Aug 2026 for one
-- reason — a PUBLIC EXECUTE grant — and they are named in docs/phase-c-kernel/K11_COMPONENT_
-- EXPOSURE.csv as the bucket "3 publicly reachable":
--
--   component                                       before K11            K11 set             now derived
--   dbfn:fn_phase_b_invariants()                    DEFERRED / inactive   ACTIVE_PUBLIC_ENTRY ACTIVE_SCRIPT_ENTRY
--   dbfn:fn_rating_due(timestamp with time zone)      / no                / active            / active / no
--   dbfn:fn_supplier_quality(bigint)                                      / unauthenticated_   DEFERRED_RUNTIME_
--                                                                           only              IMPLEMENTATION / inactive / no
--
-- Their crosswalk rows have said the repair out loud since 16 Aug: "Phase D: give it a caller and
-- an entry point, or retire it. It is deployed and unreachable." E4 did the second half. This file
-- makes the record say so.
--
-- WHY ALL THREE COLUMNS MOVE AND NOT JUST THE ONE THE BOARD CHECKS.
--   a00_phase_c_component_classification_guard REFUSES the update otherwise. Its second clause is
--   `if new.classification like 'ACTIVE\_%' and not v_reachable then raise` — and
--   fn_supplier_quality now has no reachability vector at all: no grant to anon or authenticated, no
--   internal caller, no trigger, no schedule, no view, no queue consumer, no webhook, and no caller
--   in src/** or scripts/**. Writing external_entry alone would be refused by the estate's own
--   guard, whose message is "Wire the missing leg, or record what is true; do not relabel the row."
--   Recording what is true IS the change here: the underlying fact moved when the grant went.
--
-- WHAT IS NOT TOUCHED, AND THE BOUNDARY SAID OUT LOUD.
--   21 of the 149 QuotesDone components have a recorded classification that disagrees with the
--   derivation. THREE of those 21 are these, caused by E4 minutes ago; the other EIGHTEEN are
--   pre-existing, were disagreeing before this session opened, and are not touched here. The board
--   deliberately checks external_entry and not classification, so those eighteen are not a red.
--   Fixing 3 of 21 because they are mine and leaving 18 that are not is the correct scope for a
--   remediation increment, and it is stated rather than left to be discovered.
--
-- THE FREEZE. public.phase_c_component IS a Phase C frozen subject — `component_crosswalk`. Its
-- digest covers component_type, workflow_id, step_id, accountable_role_id, canonical_system_actor,
-- authority_class, trace_policy_id, activation_state, classification and mutates_state. It does NOT
-- cover external_entry. So the external_entry write alone would have been invisible to
-- fn_phase_c_freeze_drift(), and the classification and activation_state writes are not. An
-- amendment is recorded below, pinned to the exact prior digest
-- 3e50290d1791567e652a5fb17be6ee3b399e4c6ebcbbd55533ecd564b0636b4d, which was read off production
-- immediately before this file and equals the live digest. phase_c_frozen_subject.digest is NOT
-- overwritten — that is the rubber stamp the amendment table exists to prevent.
--
-- docs/phase-c/PHASE_C_RUNTIME_COMPONENT_CROSSWALK.csv carries the same three rows and is compared
-- to the live table column by column by scripts/checks/phase_c_component_crosswalk.test.mjs. It is
-- updated in the same commit. docs/phase-c-kernel/K11_COMPONENT_EXPOSURE.csv is a dated measurement
-- of what was true on 16 Aug and is deliberately left alone: rewriting it would erase the evidence
-- that these three were ever publicly reachable.
-- =================================================================================================

update public.phase_c_component
   set external_entry = 'no',
       classification = 'ACTIVE_SCRIPT_ENTRY'
 where component_id in ('dbfn:fn_phase_b_invariants()',
                        'dbfn:fn_rating_due(p_now timestamp with time zone)')
   and external_entry = 'unauthenticated_only';

update public.phase_c_component
   set external_entry  = 'no',
       classification  = 'DEFERRED_RUNTIME_IMPLEMENTATION',
       activation_state = 'inactive'
 where component_id = 'dbfn:fn_supplier_quality(p_lead_id bigint)'
   and external_entry = 'unauthenticated_only';

-- The amendment is written from the LIVE digest computed after the updates, in this same
-- transaction, so it cannot record a digest that never existed.
-- amendment_id is GENERATED ALWAYS AS IDENTITY. It is not supplied and it is not overridden:
-- OVERRIDING SYSTEM VALUE on an identity column is how a sequence and its table stop agreeing.
insert into public.phase_c_freeze_amendment
  (subject, object_identity, prior_digest, new_digest, reason, evidence)
select 'component_crosswalk',
       'public.phase_c_component',
       '3e50290d1791567e652a5fb17be6ee3b399e4c6ebcbbd55533ecd564b0636b4d',
       (select encode(sha256(convert_to(string_agg(
          c.component_id || '|' || coalesce(c.component_type,'') || '|' || coalesce(c.workflow_id,'')
            || '|' || coalesce(c.step_id,'') || '|' || coalesce(c.accountable_role_id,'')
            || '|' || coalesce(c.canonical_system_actor,'') || '|' || coalesce(c.authority_class,'')
            || '|' || coalesce(c.trace_policy_id,'') || '|' || coalesce(c.activation_state,'')
            || '|' || coalesce(c.classification,'') || '|' || coalesce(c.mutates_state::text,''),
          chr(10) order by c.component_id),'UTF8')),'hex') from public.phase_c_component c),
       'E6 records what E4 made true. Three components were classified ACTIVE_PUBLIC_ENTRY with '
       || 'external_entry unauthenticated_only for exactly one reason — EXECUTE held through PUBLIC — '
       || 'and E4 revoked it after measuring that no caller anywhere in the repository invokes them '
       || 'with an anon or authenticated client. Their own crosswalk rows have said since 16 Aug '
       || '2026: "Phase D: give it a caller and an entry point, or retire it. It is deployed and '
       || 'unreachable." No workflow ownership, order, state, transition, gate, business rule, '
       || 'handoff accountability, category-overlay authority or founder boundary is changed. '
       || 'a00_phase_c_component_classification_guard would have REFUSED the external_entry write on '
       || 'fn_supplier_quality while classification still read ACTIVE_PUBLIC_ENTRY, so the '
       || 'classification move is the guard''s own instruction carried out, not a relabel.',
       'fn_kernel_component_exposure_state().external_entry_disagrees_with_derivation went 0 -> 3 of '
       || '149 the moment E4 applied, and returns to 0 of 149 with this file. Each new value is the '
       || 'value fn_kernel_component_reachability derives, read from the catalogue: '
       || 'fn_phase_b_invariants and fn_rating_due are ACTIVE_SCRIPT_ENTRY, still reachable through '
       || 'scripts/checks/phase_b_invariants.test.mjs, scripts/phase_b/rehearse.mjs and '
       || 'scripts/staging/prove_rating_schedule.mjs; fn_supplier_quality is '
       || 'DEFERRED_RUNTIME_IMPLEMENTATION with no reachability vector of any kind.';

-- NO EXCEPTION HANDLER IN EITHER BLOCK. A `when others` here would swallow the very assertions the
-- blocks exist to make, and a file that cannot fail is not a check.
do $e6$
declare
  v_disagree int;
  v_rows     int;
begin
  select count(*) into v_rows from public.phase_c_component
   where component_id in ('dbfn:fn_phase_b_invariants()',
                          'dbfn:fn_rating_due(p_now timestamp with time zone)',
                          'dbfn:fn_supplier_quality(p_lead_id bigint)')
     and external_entry = 'no';
  if v_rows <> 3 then
    raise exception 'E6: expected 3 components on external_entry=no, found %. '
      'A WHERE clause that matched nothing is not an idempotent re-apply — check the component_ids.', v_rows;
  end if;

  select count(*) into v_disagree
    from public.phase_c_component_exposure_scope s
    join public.phase_c_component c using (component_id),
         lateral public.fn_kernel_component_reachability(c.component_id) r(d)
   where r.d->>'derived_classification' <> 'EXTENSION_OWNED_EXCLUDED'
     and c.external_entry is distinct from r.d->>'derived_external_entry';
  if v_disagree <> 0 then
    raise exception 'E6: % component(s) still record an external_entry the derivation does not agree with.', v_disagree;
  end if;
end
$e6$;

-- The freeze reading is done in its own block so a cast failure in the first cannot mask it. Both
-- are read-only; neither writes anything.
do $e6b$
declare v_row record;
begin
  select * into v_row from public.fn_phase_c_freeze_drift() where check_name = 'frozen_subjects_drifted';
  if not v_row.ok then
    raise exception 'E6: fn_phase_c_freeze_drift() reports % — the amendment did not cover this edit. '
      'Its prior_digest must equal the frozen baseline AND its new_digest must equal the live digest.',
      v_row.actual;
  end if;
  select * into v_row from public.fn_phase_c_freeze_drift()
   where check_name = 'frozen_subjects_changed_under_a_recorded_amendment';
  raise notice 'E6: frozen subjects changed under a recorded amendment: %', v_row.actual;
end
$e6b$;
