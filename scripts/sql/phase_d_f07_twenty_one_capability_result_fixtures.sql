-- F07 - twenty-one capability result fixtures, one per capability-dependent step
--
-- One committed CAPABILITY_RESULT row per step the frozen binding marks capability-dependent. Each
-- carries the five keys public.phase_d_capability_contract declares for a REASONING capability --
-- finding, rationale, confidence, assumptions, provider_mode -- and every free-text value inside
-- carries PHASE_D_FIXTURE_DO_NOT_PUBLISH.
--
-- WHY ONE PER STEP AND NOT ONE SHARED ROW. A capability result is an answer to a particular
-- question, and the founder's section C requires the fixture to be identified by id, version and
-- hash on the accepted result. A single shared row would make twenty-one different steps
-- indistinguishable in the evidence, which is the "instrument reporting on the wrong subject"
-- shape. The fixture ids are derived from the step id so a reader can go from a result row back to
-- the step without a lookup table.
--
-- confidence is 0 on every one of them, deliberately. There is no model behind these values and no
-- inference was run to produce them; a fixture that claimed 0.9 confidence would be asserting
-- something about a reasoning process that did not happen. The number is part of the contract
-- because a Phase E result must carry one; its value here says what it should say.

INSERT INTO public.phase_d_fixture_catalogue
 (fixture_id, fixture_version, workflow_id, step_id, scope, field_key, value, value_kind, currency,
  expected_schema, expected_result, prohibited_external_use, marker_exemption)
SELECT
  'PDF-1' || lpad((row_number() over (order by b.step_id))::text, 3, '0'),
  1,
  b.workflow_id,
  b.step_id,
  'CAPABILITY_RESULT',
  'capability_result',
  jsonb_build_object(
    'finding',   format('PHASE_D_FIXTURE_DO_NOT_PUBLISH — fixture %s result for %s. No judgement was made about the real business; this value exists so the capability-result interface can be exercised end to end.',
                        b.capability_dependency, b.step_id),
    'rationale', format('PHASE_D_FIXTURE_DO_NOT_PUBLISH — supplied as a pre-authored fixture through fn_phase_d_capability_result_accept with provider_mode fixture. The frozen required_action that makes %s capability-dependent is: %s. No provider was called and no paid inference was requested.',
                        b.step_id, coalesce(nullif(b.capability_evidence,''),'(none recorded)')),
    'confidence', 0,
    'assumptions', jsonb_build_array(
      'PHASE_D_FIXTURE_DO_NOT_PUBLISH — no model produced this result; confidence is 0 because there is no inference behind it',
      'PHASE_D_FIXTURE_DO_NOT_PUBLISH — the result is accepted only inside a verified Phase D fixture context and inside a transaction that is aborted'),
    'provider_mode', 'fixture'),
  'object',
  null,
  format('an object carrying exactly the keys public.phase_d_capability_contract declares for %s on %s: finding (string), rationale (string), confidence (number), assumptions (array), provider_mode (string)',
         b.capability_dependency, b.step_id),
  format('fn_phase_d_capability_result_accept validates it, records the fixture id, version and hash, and %s continues through the normal handler', b.step_id),
  'This is not an analysis, a classification, a forecast, a design or a review verdict. It must never be shown to a customer, a supplier or the founder as one, and it must never be published.',
  null
FROM public.phase_d_handler_binding b
WHERE b.capability_dependency <> 'NONE'
ON CONFLICT (fixture_id) DO NOTHING;
