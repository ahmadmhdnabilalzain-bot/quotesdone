import { writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';

let fac = (await sql(
  `select pg_get_functiondef('public.fn_phase_d_fixture_scenario(jsonb)'::regprocedure) as def`))[0].def;

// The stage writes 'artifact_sha256', v_art_sha into the payload. v_art_sha is declared and never
// assigned, so the payload has carried a null there since F08.
const NEEDLE = `        'artifact_sha256', v_art_sha,`;
if (fac.split(NEEDLE).length - 1 !== 1) { console.error('the artifact payload anchor did not match once'); process.exit(1); }

const ANCHOR = `      v_pay := v_pay || jsonb_build_object(
        'artifact_ref', (select c.value #>> '{}' from public.phase_d_fixture_catalogue c
                          where c.scope='CONTEXT_KEY' and c.field_key='artifact_ref'),
        'artifact_sha256', v_art_sha,`;
const REPLACEMENT = `      -- F48. v_art_sha WAS DECLARED AND NEVER ASSIGNED, SO THIS PAYLOAD CARRIED A NULL.
      --
      -- F08 added the variable with the comment "the digest BR-036 resolves" and the stage below
      -- writes it into the artifact record's payload. Nothing ever assigned it. Measured: BR-036
      -- refuses W08, W20, W22 and W24 with "review names artifact <id> at digest 5be99093ba73,
      -- which resolves to 0 artifact_review row(s) and 0 business object record(s) carrying exactly
      -- that digest" -- and the reason no record carries it is that this line wrote null.
      --
      -- The digest is the committed one F39 computed over the committed artifact body, read here
      -- rather than recomputed, so the value in the record is the same value the context resolver
      -- hands the rule and anyone can recompute both from the catalogue.
      v_art_sha := (select c.value #>> '{}' from public.phase_d_fixture_catalogue c
                     where c.scope='CONTEXT_KEY' and c.field_key='artifact_sha256');
      if v_art_sha is null then
        raise exception 'fn_phase_d_fixture_scenario: no committed artifact_sha256 fixture, so the artifact record would carry no digest and BR-036 could never pass or fail for a real reason (pd_fixture_artifact_digest_missing)'
          using errcode = '23502';
      end if;

      v_pay := v_pay || jsonb_build_object(
        'artifact_ref', (select c.value #>> '{}' from public.phase_d_fixture_catalogue c
                          where c.scope='CONTEXT_KEY' and c.field_key='artifact_ref'),
        'artifact_sha256', v_art_sha,`;

if (fac.split(ANCHOR).length - 1 !== 1) { console.error('the artifact stage anchor did not match once'); process.exit(1); }
fac = fac.replace(ANCHOR, REPLACEMENT);

const HEADER = `-- F48 - a variable declared with a comment saying what it is for, and never assigned
--
--     v_art_sha  text;   -- F08: the digest BR-036 resolves
--
-- It is written into the artifact record's payload by the artifact_revision stage and it was never
-- assigned anywhere, so that payload has carried a null since F08. grep for "v_art_sha :=" over the
-- live definition returns nothing.
--
-- MEASURED. BR-036 refuses W08, W20, W22 and W24 -- four of the thirteen workflows that still
-- execute nothing -- with:
--
--   "review names artifact 6803a863-... at digest 5be99093ba73, which resolves to 0 artifact_review
--    row(s) and 0 business object record(s) carrying exactly that digest"
--
-- The digest in that sentence is correct: F39 computed it over the committed artifact body and F47
-- now hands it to the rule. What is missing is a RECORD carrying it, and the line that was supposed
-- to put it there wrote a null.
--
-- The value is read from the committed catalogue rather than recomputed here, so the record and the
-- rule are given the same value from the same row, and both are recomputable from the fixture body
-- committed beside it. A missing catalogue digest now refuses outright rather than writing a null
-- again -- a stage that silently records nothing is what this file is fixing.
--
-- The rest of the routine is byte-identical. One anchor, required to match exactly once.

`;

writeFileSync('scripts/sql/phase_d_f48_a_variable_declared_for_a_purpose_and_never_assigned.sql',
  HEADER + fac + ';\n');
console.log('written');
