-- F19 - a deliberately malformed capability fixture, so case 3 tests the schema and not the lookup
--
-- The founder's section C case 3 is "malformed fixture result -> refused". The first run of
-- scripts/phase_d/prove_capability_boundary.mjs submitted a CONTEXT_KEY row as if it were a
-- capability result and got pd_capability_fixture_unknown -- a refusal, and the WRONG one: it
-- proves the lookup refuses an id that is not a CAPABILITY_RESULT row, and says nothing about
-- whether the output-schema validation fn_phase_d_capability_result_accept performs would catch a
-- result that IS a capability result and is malformed.
--
-- A guard you cannot make fail is a guard nobody has tested, so the catalogue gains a row whose
-- whole purpose is to fail: it is scoped CAPABILITY_RESULT, so the lookup finds it, and its object
-- is missing three of the five contract keys and types a fourth wrongly. The acceptance service
-- must name both failures.
--
-- It is safe to commit because it can only ever be reached by a caller that asks for PDF-1099 by
-- name, and the only caller that does is the proof harness.

INSERT INTO public.phase_d_fixture_catalogue
 (fixture_id, fixture_version, workflow_id, step_id, scope, field_key, value, value_kind, currency,
  expected_schema, expected_result, prohibited_external_use, marker_exemption)
VALUES
('PDF-1099',1,null,null,'CAPABILITY_RESULT','malformed_capability_result',
 '{"finding":"PHASE_D_FIXTURE_DO_NOT_PUBLISH — a deliberately malformed capability result: rationale, assumptions and provider_mode are missing and confidence is a string where the contract says number.","confidence":"high"}',
 'object', null,
 'DELIBERATELY INVALID against public.phase_d_capability_contract: missing rationale, assumptions and provider_mode; confidence typed string where the contract declares number',
 'fn_phase_d_capability_result_accept refuses with pd_capability_result_malformed and names the three missing keys and the one wrongly typed key',
 'This fixture exists to be refused. It must never be accepted, recorded or acted on, and nothing may be published from it.',
 null)
ON CONFLICT (fixture_id) DO NOTHING;
