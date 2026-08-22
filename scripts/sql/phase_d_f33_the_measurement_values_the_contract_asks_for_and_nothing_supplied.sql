-- F33 - the measurement values the output contract asks for, and the catalogue rows nothing read
--
-- The founder's ruling of 22 Aug 2026, section 8A: "Move numerator, denominator, formula, window to
-- the typed handler output object where the schema expects them. Do not hide them only in an effect
-- payload."
--
-- MEASURED FIRST. Eight steps bind MEASUREMENT_HANDLER, and each of their output schemas requires
-- metric, numerator, denominator, formula and window on top of the four universal keys. The handler
-- built them like this:
--
--     when 'MEASUREMENT_HANDLER' then jsonb_strip_nulls(jsonb_build_object(
--       'metric', coalesce(s.required_output,''),
--       'denominator', p_input->'denominator',
--       'numerator',   p_input->'numerator',
--       'formula',     nullif(btrim(coalesce(p_input->>'formula','')),''),
--       'window',      nullif(btrim(coalesce(p_input->>'window','')),'')))
--
-- Four of the five come from p_input. E32 stopped the harness supplying inputs -- deliberately, and
-- correctly, because a deliverable that hands the rules their own answers measures nothing -- and
-- the kernel dispatch passes no such keys. So all four are null, jsonb_strip_nulls removes them,
-- and fn_phase_d_schema_validate refuses the output the handler just built. Measured on the
-- 30-workflow drive: W11-S01 refuses with pd_output_schema_invalid even AFTER its capability
-- fixture is accepted and F32 let the provenance through.
--
-- WHERE THE VALUES BELONG. Section 6: "The fixture catalogue supplies explicit content for the
-- content-dependent objects... Handlers validate, persist, version and route these values. Handlers
-- do not generate them." A measurement handler that invented its own numerator would be the worst
-- version of this: a number about the real business, produced from nothing, carried into a business
-- object. So the values come from committed catalogue rows, one set per step, each with a fixture
-- id, a version, a computed checksum and an explicit prohibition on external use.
--
-- A ROW NOTHING READS IS NOT A FIXTURE. public.phase_d_fixture_catalogue already held two
-- HANDLER_OUTPUT rows -- PDF-0055 (rationale) and PDF-0056 (recommendation) -- and grep over
-- scripts/sql finds exactly two references to the string HANDLER_OUTPUT: the CHECK constraint that
-- allows the value, and the INSERT that wrote those rows. Nothing has ever read that scope. This
-- file adds the reader, so the two existing rows become live at the same time as the new ones.
--
-- THE DENOMINATOR GUARD KEEPS ITS TEETH. fn_phase_d_handler_execute refuses a denominator of 0 with
-- pd_output_schema_invalid, and that stays exactly as it is. None of the fixtures below is 0, and a
-- step with no committed fixture still produces a null and is still refused by its own contract --
-- which is what makes this a supply of values rather than a way past the check.

begin;

-- ---- 1. THE READER --------------------------------------------------------------------------
-- Step-scoped first, generic second. Neither is invented: both are committed rows with a checksum.
-- Returns jsonb so a number stays a number and a string stays a string; the output schema types
-- both, and passing everything back as text would have made numerator fail its declared type.
CREATE OR REPLACE FUNCTION public.fn_phase_d_fixture_output(p_step_id text, p_field_key text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'pg_temp'
AS $function$
  select c.value
    from public.phase_d_fixture_catalogue c
   where c.scope = 'HANDLER_OUTPUT'
     and c.field_key = p_field_key
     and (c.step_id = p_step_id or c.step_id is null)
   order by (c.step_id is null), c.fixture_version desc, c.fixture_id
   limit 1;
$function$;

REVOKE EXECUTE ON FUNCTION public.fn_phase_d_fixture_output(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_phase_d_fixture_output(text, text) TO service_role;

COMMENT ON FUNCTION public.fn_phase_d_fixture_output(text, text) IS
  'The committed HANDLER_OUTPUT value for one step and one output key. Step-scoped rows win over '
  'generic ones. Returns NULL when the catalogue holds nothing, so the step''s own output contract '
  'refuses it rather than this function inventing a value. F33.';

-- ---- 2. THE VALUES --------------------------------------------------------------------------
-- One set per MEASUREMENT_HANDLER step. The numbers are small, distinct per step and never zero, so
-- a wrong-step resolution is visible in the output rather than plausible. Every numeric row carries
-- a marker_exemption, because a JSON number cannot contain PHASE_D_FIXTURE_DO_NOT_PUBLISH and the
-- catalogue's marker CHECK requires one or the other.
INSERT INTO public.phase_d_fixture_catalogue
 (fixture_id, fixture_version, workflow_id, step_id, scope, field_key, value, value_kind, currency,
  expected_schema, expected_result, prohibited_external_use, marker_exemption)
VALUES
-- generic formula and window, in the scope the handler reads. PDF-0015 and PDF-0016 carry the same
-- text under CONTEXT_KEY; they are the step's INPUT vocabulary and are left exactly where they are.
('PDF-3001',1,null,null,'HANDLER_OUTPUT','formula',
 '"PHASE_D_FIXTURE_DO_NOT_PUBLISH numerator divided by denominator over the stated window, computed over the fixture scenario only"','text',null,
 'free text naming how the ratio was formed; the output schema types it string',
 'the MEASUREMENT_HANDLER output validates against its own contract',
 'Never quote as a company metric definition. It describes a fixture scenario.',null),
('PDF-3002',1,null,null,'HANDLER_OUTPUT','window',
 '"PHASE_D_FIXTURE_DO_NOT_PUBLISH fixture window 2026-08-01T00:00:00Z..2026-08-21T00:00:00Z"','text',null,
 'free text naming the measurement window; the output schema types it string',
 'the MEASUREMENT_HANDLER output validates against its own contract',
 'Never quote as a reporting period. No real period was measured.',null),

('PDF-3003',1,'W02','W02-S08','HANDLER_OUTPUT','numerator','3','number',null,
 'a JSON number; the output schema types numerator number',
 'W02-S08 produces a typed measurement its contract accepts',
 'Never report. It counts nothing in the real business.',
 'A JSON number cannot carry the text marker. This row is a fixture measurement over the Phase D scenario and is prohibited from external use by the column beside it.'),
('PDF-3004',1,'W02','W02-S08','HANDLER_OUTPUT','denominator','7','number',null,
 'a JSON number greater than zero; the handler refuses a denominator of 0',
 'W02-S08 produces a typed measurement its contract accepts',
 'Never report. It counts nothing in the real business.',
 'A JSON number cannot carry the text marker. This row is a fixture measurement over the Phase D scenario and is prohibited from external use by the column beside it.'),
('PDF-3005',1,'W03','W03-S08','HANDLER_OUTPUT','numerator','5','number',null,
 'a JSON number; the output schema types numerator number',
 'W03-S08 produces a typed measurement its contract accepts',
 'Never report. It counts nothing in the real business.',
 'A JSON number cannot carry the text marker. This row is a fixture measurement over the Phase D scenario and is prohibited from external use by the column beside it.'),
('PDF-3006',1,'W03','W03-S08','HANDLER_OUTPUT','denominator','11','number',null,
 'a JSON number greater than zero; the handler refuses a denominator of 0',
 'W03-S08 produces a typed measurement its contract accepts',
 'Never report. It counts nothing in the real business.',
 'A JSON number cannot carry the text marker. This row is a fixture measurement over the Phase D scenario and is prohibited from external use by the column beside it.'),
('PDF-3007',1,'W11','W11-S01','HANDLER_OUTPUT','numerator','4','number',null,
 'a JSON number; the output schema types numerator number',
 'W11-S01 produces a typed measurement its contract accepts',
 'Never report. It counts nothing in the real business.',
 'A JSON number cannot carry the text marker. This row is a fixture measurement over the Phase D scenario and is prohibited from external use by the column beside it.'),
('PDF-3008',1,'W11','W11-S01','HANDLER_OUTPUT','denominator','9','number',null,
 'a JSON number greater than zero; the handler refuses a denominator of 0',
 'W11-S01 produces a typed measurement its contract accepts',
 'Never report. It counts nothing in the real business.',
 'A JSON number cannot carry the text marker. This row is a fixture measurement over the Phase D scenario and is prohibited from external use by the column beside it.'),
('PDF-3009',1,'W11','W11-S02','HANDLER_OUTPUT','numerator','6','number',null,
 'a JSON number; the output schema types numerator number',
 'W11-S02 produces a typed measurement its contract accepts',
 'Never report. It counts nothing in the real business.',
 'A JSON number cannot carry the text marker. This row is a fixture measurement over the Phase D scenario and is prohibited from external use by the column beside it.'),
('PDF-3010',1,'W11','W11-S02','HANDLER_OUTPUT','denominator','13','number',null,
 'a JSON number greater than zero; the handler refuses a denominator of 0',
 'W11-S02 produces a typed measurement its contract accepts',
 'Never report. It counts nothing in the real business.',
 'A JSON number cannot carry the text marker. This row is a fixture measurement over the Phase D scenario and is prohibited from external use by the column beside it.'),
('PDF-3011',1,'W11','W11-S06','HANDLER_OUTPUT','numerator','2','number',null,
 'a JSON number; the output schema types numerator number',
 'W11-S06 produces a typed measurement its contract accepts',
 'Never report. It counts nothing in the real business.',
 'A JSON number cannot carry the text marker. This row is a fixture measurement over the Phase D scenario and is prohibited from external use by the column beside it.'),
('PDF-3012',1,'W11','W11-S06','HANDLER_OUTPUT','denominator','8','number',null,
 'a JSON number greater than zero; the handler refuses a denominator of 0',
 'W11-S06 produces a typed measurement its contract accepts',
 'Never report. It counts nothing in the real business.',
 'A JSON number cannot carry the text marker. This row is a fixture measurement over the Phase D scenario and is prohibited from external use by the column beside it.'),
('PDF-3013',1,'W20','W20-S07','HANDLER_OUTPUT','numerator','7','number',null,
 'a JSON number; the output schema types numerator number',
 'W20-S07 produces a typed measurement its contract accepts',
 'Never report. It counts nothing in the real business.',
 'A JSON number cannot carry the text marker. This row is a fixture measurement over the Phase D scenario and is prohibited from external use by the column beside it.'),
('PDF-3014',1,'W20','W20-S07','HANDLER_OUTPUT','denominator','15','number',null,
 'a JSON number greater than zero; the handler refuses a denominator of 0',
 'W20-S07 produces a typed measurement its contract accepts',
 'Never report. It counts nothing in the real business.',
 'A JSON number cannot carry the text marker. This row is a fixture measurement over the Phase D scenario and is prohibited from external use by the column beside it.'),
('PDF-3015',1,'W21','W21-S07','HANDLER_OUTPUT','numerator','1','number',null,
 'a JSON number; the output schema types numerator number',
 'W21-S07 produces a typed measurement its contract accepts',
 'Never report. It counts nothing in the real business.',
 'A JSON number cannot carry the text marker. This row is a fixture measurement over the Phase D scenario and is prohibited from external use by the column beside it.'),
('PDF-3016',1,'W21','W21-S07','HANDLER_OUTPUT','denominator','4','number',null,
 'a JSON number greater than zero; the handler refuses a denominator of 0',
 'W21-S07 produces a typed measurement its contract accepts',
 'Never report. It counts nothing in the real business.',
 'A JSON number cannot carry the text marker. This row is a fixture measurement over the Phase D scenario and is prohibited from external use by the column beside it.'),
('PDF-3017',1,'W28','W28-S08','HANDLER_OUTPUT','numerator','9','number',null,
 'a JSON number; the output schema types numerator number',
 'W28-S08 produces a typed measurement its contract accepts',
 'Never report. It counts nothing in the real business.',
 'A JSON number cannot carry the text marker. This row is a fixture measurement over the Phase D scenario and is prohibited from external use by the column beside it.'),
('PDF-3018',1,'W28','W28-S08','HANDLER_OUTPUT','denominator','12','number',null,
 'a JSON number greater than zero; the handler refuses a denominator of 0',
 'W28-S08 produces a typed measurement its contract accepts',
 'Never report. It counts nothing in the real business.',
 'A JSON number cannot carry the text marker. This row is a fixture measurement over the Phase D scenario and is prohibited from external use by the column beside it.')
ON CONFLICT (fixture_id) DO NOTHING;

commit;
