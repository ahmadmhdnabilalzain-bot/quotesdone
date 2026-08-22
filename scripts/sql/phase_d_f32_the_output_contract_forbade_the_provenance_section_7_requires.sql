-- F32 - the output contract forbade the very provenance section 7 requires
--
-- MEASURED, not deduced. Driving W11, W21, W23, W25 and W29 through the kernel doors:
--
--   [{"step_id": "W11-S01", "fixture_id": "PDF-1004", "provider_mode": "fixture",
--     "fixture_hash": "7cf343f0ffcf...", "redispatch_outcome": "REFUSED",
--     "redispatch_refusal": "pd_output_schema_invalid"}]  capability_results_accepted = 1
--
-- The capability path WORKS. F05 made the boundary fail closed, F07 committed 21 fixture results,
-- F17 re-dispatches the step once a result is accepted, F18 marks the request answered. The request
-- opens, the committed fixture is accepted through fn_phase_d_capability_result_accept, the step is
-- dispatched again -- and then the handler's own output contract rejects the output.
--
-- WHY. fn_phase_d_handler_execute merges a `capability_result` object into the output whenever a
-- capability answer exists (F06), carrying request_id, result_id, provider_mode, fixture_id,
-- fixture_version, fixture_hash, payload_digest and evidence. That is exactly what the founder's
-- ruling of 22 Aug 2026 section 7 requires be recorded: "Record fixture ID/version/hash" and
-- "Record provenance and trace".
--
-- And no output schema declares it. Measured: of 257 output schemas, `capability_result` is in
-- required_keys on 0 and optional_keys on 0, and additional_properties is false on 257 of 257 --
-- correctly, because E16 closed those contracts so an undeclared key could not reach a business
-- object payload. So the handler adds a key the contract forbids, and fn_phase_d_schema_validate
-- refuses the output. Every one of the 21 capability-dependent steps fails this way the moment its
-- fixture is accepted, which is why 21/21 capability coverage reads 0 however many fixtures exist.
--
-- THE FIX IS ON THE CONTRACT, NOT ON THE VALIDATOR. Two wrong ways to close this were available and
-- both are refused here:
--
--   * setting additional_properties = true on those 21 schemas. That re-opens the hole E16 closed
--     for every key, not just this one, to admit one key we can name.
--   * dropping capability_result from the output. That deletes the provenance section 7 demands and
--     leaves the fixture id, version and hash recorded nowhere the output can be audited from.
--
-- What is actually wrong is that the contract does not describe the output the handler produces.
-- capability_result is declared here as an OPTIONAL key with a stated type, on exactly the 21 steps
-- that carry a capability dependency and on no others -- so a step with no capability dependency
-- that somehow emitted one is still refused, and the closed contract keeps its teeth everywhere.
--
-- NOTHING IS WEAKENED. additional_properties stays false on 257 of 257. field_types gains one entry
-- per amended schema, so scripts/checks/phase_d_input_schemas_are_typed_and_closed.test.mjs still
-- measures 0 unconstrained keys. The 236 non-capability schemas are untouched.

begin;

-- The subject is exactly the capability-dependent steps, taken from the frozen binding rather than
-- from a list typed here. A list would go stale the moment a binding changed, and this estate has
-- been bitten by an expectation typed into the check it guards.
update public.phase_d_handler_schema s
   set optional_keys = (
         select array_agg(distinct k order by k)
           from unnest(coalesce(s.optional_keys, '{}'::text[]) || array['capability_result']) k),
       field_types = coalesce(s.field_types, '{}'::jsonb)
                     || jsonb_build_object('capability_result', 'object'),
       schema_version = coalesce(s.schema_version, 1) + 1
 where s.schema_kind = 'output'
   and exists (select 1 from public.phase_d_handler_binding b
                where b.step_id = s.step_id
                  and coalesce(b.capability_dependency,'NONE') <> 'NONE')
   and not ('capability_result' = any(coalesce(s.optional_keys, '{}'::text[])));

commit;
