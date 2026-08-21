-- F04 - the board and the trigger disagreed about what a row is
--
-- F02 shipped fn_phase_d_fixture_catalogue_state() with the canonical serialisation written out by
-- hand, and F03 added a thirteenth field to the row -- marker_exemption -- and taught the TRIGGER
-- about it. The board was not taught, so it recomputed every checksum over twelve fields and
-- reported:
--
--     rows_whose_checksum_does_not_match_their_content   expected 0, got 62 of 62
--     text_fixtures_without_the_marker                   expected 0, got 10
--
-- Both reds are the board being wrong, and both are worth recording rather than quietly patching,
-- because they are the same defect twice: a check that restates a rule in its own words instead of
-- calling the routine that owns it. The first red is a serialisation typed into two places; the
-- second is the marker rule typed into two places, where F03 gave the constraint an exemption arm
-- and the board kept the constraint's original sentence.
--
-- THE FIX IS TO REMOVE THE SECOND COPY, NOT TO EDIT IT. The canonical serialisation now lives in
-- exactly one routine, fn_phase_d_fixture_row_digest, which the trigger and the board both call.
-- A field added to the catalogue in future changes one function and both readers follow.
--
-- The marker check gains the exemption arm the CHECK constraint has, and the board gains a row that
-- DISCLOSES the exemptions rather than absorbing them: `text_fixtures_marker_exempt` is reported
-- with its count and is green only while every exempt row still carries its stated reason. An
-- exemption nobody can see is the shape this estate keeps finding.

CREATE OR REPLACE FUNCTION public.fn_phase_d_fixture_row_digest(r public.phase_d_fixture_catalogue)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select encode(sha256(convert_to(concat_ws(chr(31),
    r.fixture_id, r.fixture_version::text, coalesce(r.workflow_id,''), coalesce(r.step_id,''),
    r.scope, r.field_key, r.value::text, r.value_kind, coalesce(r.currency,''),
    r.expected_schema, r.expected_result, r.prohibited_external_use,
    coalesce(r.marker_exemption,'')), 'UTF8')), 'hex');
$function$;

COMMENT ON FUNCTION public.fn_phase_d_fixture_row_digest(public.phase_d_fixture_catalogue) IS
  'THE CANONICAL SERIALISATION OF A PHASE D FIXTURE ROW, IN ONE PLACE. The checksum trigger and '
  'the catalogue board both call this, so a field added to the catalogue cannot leave one of them '
  'computing a different digest from the other -- which is exactly what happened between F02 and '
  'F03 and put 62 of 62 rows on the board as drifted (F04).';

CREATE OR REPLACE FUNCTION public.fn_phase_d_fixture_catalogue_checksum()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  -- THE CHECKSUM IS COMPUTED, NEVER ACCEPTED. A caller-supplied checksum is a claim about a row.
  new.checksum := public.fn_phase_d_fixture_row_digest(new);
  return new;
end
$function$;

DROP TRIGGER IF EXISTS a10_phase_d_fixture_catalogue_checksum ON public.phase_d_fixture_catalogue;
CREATE TRIGGER a10_phase_d_fixture_catalogue_checksum
  BEFORE INSERT OR UPDATE ON public.phase_d_fixture_catalogue
  FOR EACH ROW EXECUTE FUNCTION public.fn_phase_d_fixture_catalogue_checksum();

CREATE OR REPLACE FUNCTION public.fn_phase_d_fixture_catalogue_state()
 RETURNS TABLE(check_name text, expected text, actual text, ok boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with c as (select * from public.phase_d_fixture_catalogue),
       unmarked as (
         select * from c
          where jsonb_typeof(value) = 'string'
            and value #>> '{}' not like '%PHASE_D_FIXTURE_DO_NOT_PUBLISH%'),
       exempt as (select * from unmarked where length(btrim(coalesce(marker_exemption,''))) >= 60),
       drifted as (select * from c where checksum <> public.fn_phase_d_fixture_row_digest(c.*))
  select 'catalogue_entries'::text, 'at least 40'::text,
         (select count(*)::text from c), (select count(*) from c) >= 40
  union all
  select 'text_fixtures_without_the_marker_and_without_an_exemption', '0',
         (select count(*)::text from unmarked
           where length(btrim(coalesce(marker_exemption,''))) < 60),
         not exists (select 1 from unmarked
                      where length(btrim(coalesce(marker_exemption,''))) < 60)
  union all
  -- DISCLOSED, NOT ABSORBED. This row is green while every exempt fixture still states why it
  -- cannot carry the marker, and it prints the count so a reader sees the size of the exemption
  -- rather than a bare green.
  select 'text_fixtures_marker_exempt',
         'each one stating, in 60 characters or more, why the value cannot carry the marker',
         (select count(*)::text || ' of ' || (select count(*) from c
                                               where jsonb_typeof(value) = 'string')::text
                                || ' text fixtures: '
                                || coalesce(string_agg(field_key, ', ' order by fixture_id),'(none)')
            from exempt),
         (select count(*) from unmarked) = (select count(*) from exempt)
  union all
  select 'financial_fixtures_without_a_declared_currency', '0',
         (select count(*)::text from c where value_kind = 'number'
            and field_key ~ '(amount|fee|price|fils|aed|cost|total)' and currency is null),
         not exists (select 1 from c where value_kind = 'number'
            and field_key ~ '(amount|fee|price|fils|aed|cost|total)' and currency is null)
  union all
  select 'rows_whose_checksum_does_not_match_their_content', '0',
         (select count(*)::text from drifted), not exists (select 1 from drifted)
  union all
  select 'catalogue_rows_naming_a_step_that_is_not_frozen', '0',
         (select count(*)::text from c where step_id is not null
            and not exists (select 1 from public.phase_b_workflow_step s where s.step_id = c.step_id)),
         not exists (select 1 from c where step_id is not null
            and not exists (select 1 from public.phase_b_workflow_step s where s.step_id = c.step_id))
  union all
  select 'scenario_records_still_committed', '0',
         (select count(*)::text from public.phase_d_scenario_record),
         not exists (select 1 from public.phase_d_scenario_record)
  union all
  select 'fixture_contexts_still_committed', '0',
         (select count(*)::text from public.phase_d_test_context_grant),
         not exists (select 1 from public.phase_d_test_context_grant);
$function$;

-- Recompute every checksum through the one routine, so the stored value and the board agree.
UPDATE public.phase_d_fixture_catalogue SET fixture_version = fixture_version;
