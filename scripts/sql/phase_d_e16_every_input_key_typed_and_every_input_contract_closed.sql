-- E16 — every input key typed, and every input contract closed
--
-- MEASURED 2026-08-20. Of 2,772 declared schema keys, 2,242 were `unconstrained`, and the input side
-- accounted for all of the worst of it: **769 of 769 input keys `unconstrained`**,
-- `additional_properties = true` on **257 of 257** input schemas, and **0** input enum domains.
-- Driven against `fn_phase_d_schema_validate`, that meant:
--
--   * `{founder_instruction: 12345, current_approved_founder_policies: true, ...}` — integers and
--     booleans where the source text describes documents — validated **true**;
--   * the same payload plus `refund_amount_aed: 999999` and `__proto__: {admin:true}` also
--     validated **true**.
--
-- The output side was already right: closed contract, `status` domain, wrong types rejected. The
-- machinery in `fn_phase_d_schema_validate` was never the problem — it enforces types, enum domains
-- and closure, and it already refuses a required key with no declared type. The DATA said
-- "unconstrained" and "open", so there was nothing for it to enforce. This file is therefore data,
-- not code: no routine changes.
--
-- WHY THIS IS NOT AN INVENTION. The previous `type_source` read: "no frozen source declares a type
-- for any of them; all are recorded unconstrained, explicitly." That was honest about the frozen
-- registry and wrong about the estate, because the type of an input key is not a matter of opinion —
-- it is whatever `fn_phase_d_step_inputs` produces, and that is measurable.
--
-- THE MEASUREMENT. There are only **20 distinct input keys** across all 769 declarations (three of
-- them — `workflow_record`, `prior_accepted_outputs`, `applicable_policy` — carry 747 of the 2,307
-- declarations). Driving every workflow through the kernel in one aborted transaction and reading
-- `jsonb_typeof` of every key `fn_phase_d_step_inputs` returned gave **`object`, for every key,
-- with no exceptions and no second type anywhere**: 14 of the 20 observed directly, and the
-- remaining 6 share a resolver branch with an observed key. Every one of the 14 branches in that
-- function is a `jsonb_build_object(...)`. There is no key it can produce a scalar for.
--
-- WHY CLOSING THE CONTRACT MATTERS, AND IS NOT COSMETIC. `fn_phase_d_handler_execute` passes
-- `coalesce(p_input->'effect_payload', v_inputs)` as the payload of the business object it writes.
-- An undeclared input key therefore does not sit harmlessly beside the contract — it rides into a
-- business record. `refund_amount_aed` validating `true` against an open input schema was a route
-- from an unvalidated payload into `fn_phase_d_object_write`. The kernel path cannot produce such a
-- key (`fn_phase_d_step_inputs` returns exactly the declared set), so closing costs the real caller
-- nothing and closes the door on every other one.
--
-- `scripts/checks/phase_d_input_schemas_are_typed_and_closed.test.mjs` commits both audit payloads
-- as NEGATIVE CONTROLS, so the two that used to validate `true` now have to keep validating `false`.
--
-- No routine is created or replaced here, so there is no grant to revoke.

update public.phase_d_handler_schema s
   set field_types = (
         select jsonb_object_agg(k, 'object')
           from unnest(s.required_keys || coalesce(s.optional_keys,'{}')) k),
       additional_properties = false,
       schema_version = 2,
       type_source =
         'E16, 2026-08-20, MEASURED not asserted: every branch of public.fn_phase_d_step_inputs '
         || 'builds its value with jsonb_build_object, and driving all 30 workflows through '
         || 'fn_kernel_workflow_start / fn_kernel_step_complete / fn_kernel_handoff_accept / '
         || 'fn_kernel_review_decide in one aborted transaction and reading jsonb_typeof of every '
         || 'returned key gave object for all 14 of the 20 distinct input keys that resolved, with '
         || 'no second type observed for any key; the other 6 share a resolver branch with an '
         || 'observed key. additional_properties is false because fn_phase_d_step_inputs returns '
         || 'exactly the declared key set, so nothing the kernel path can produce is excluded, while '
         || 'fn_phase_d_handler_execute passes the input object straight through as the payload of '
         || 'the business object it writes — an undeclared key was a route into a business record. '
         || 'Prior type_source, kept here because it was the honest reading of the frozen registry '
         || 'and is now superseded by a measurement of the estate: '
         || left(coalesce(s.type_source,'(none)'), 300)
 where s.schema_kind = 'input';

-- The 20 keys the update just typed, named so that a reader can check the claim without driving
-- anything: applicable_policy, approved_company_objectives_and_department_mandates, budget_envelope,
-- complete_ownership_and_measurement_setup, current_approved_founder_policies, current_baseline,
-- current_cash_budget_and_commitments, current_company_objective, current_company_state,
-- department_mandates, external_and_internal_evidence, founder_instruction, founder_mandate,
-- issued_initiatives, kpi_tree, prior_accepted_outputs, resource_envelope, strategy_option,
-- strategy_options, workflow_record.

-- FAIL THE FILE RATHER THAN LEAVE A HALF-TYPED REGISTRY. An update that silently matched fewer rows
-- than intended is exactly the shape that puts a green number next to an unfinished job.
do $$
declare v_open int; v_unconstrained int; v_v1 int;
begin
  select count(*) into v_open from public.phase_d_handler_schema
   where schema_kind = 'input' and coalesce(additional_properties, true);
  select count(*) into v_unconstrained
    from public.phase_d_handler_schema s, lateral unnest(s.required_keys) k
   where s.schema_kind = 'input' and coalesce(s.field_types->>k, 'unconstrained') = 'unconstrained';
  select count(*) into v_v1 from public.phase_d_handler_schema
   where schema_kind = 'input' and schema_version < 2;

  if v_open > 0 or v_unconstrained > 0 or v_v1 > 0 then
    raise exception 'E16 did not finish: % input schemas still open, % required input keys still unconstrained, % still at schema_version 1',
      v_open, v_unconstrained, v_v1;
  end if;
end $$;
