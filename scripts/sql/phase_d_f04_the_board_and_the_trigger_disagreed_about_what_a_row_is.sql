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

-- ROUTINE REMOVED 7 September 2026. public.fn_phase_d_fixture_row_digest was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


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

-- ROUTINE REMOVED 7 September 2026. public.fn_phase_d_fixture_catalogue_state was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- Recompute every checksum through the one routine, so the stored value and the board agree.
UPDATE public.phase_d_fixture_catalogue SET fixture_version = fixture_version;
