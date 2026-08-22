import { writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';

const [{ def }] = await sql(
  `select pg_get_functiondef('public.fn_phase_d_fixture_input(bigint,text,text)'::regprocedure) as def`);

const OLD = `    select coalesce(sc.contributed_value, sc.business_key) v, sc.object_id o,
           sc.canonical_relation cr, sc.fixture_id fi, sc.fixture_version fv, sc.source_checksum ck
      into r
      from public.phase_d_scenario_record sc
     where sc.fixture_run_id = v_run and sc.contributes_ref = p_key
     order by sc.scenario_record_id limit 1;`;

const NEW = `    -- F40. A STAGE THAT CONTRIBUTED NOTHING STILL ANSWERED, WITH ITS OWN ROW ID.
    --
    -- coalesce(contributed_value, business_key) means a stage whose contributed_value was never set
    -- answers the key with the primary key of the row it created. Measured: the artifact_revision
    -- stage declares contributes_ref = 'artifact_sha256', sets no contributed_value, and so
    -- resolved artifact_sha256 to 44208 -- a row id. BR-036 then refused with "artifact_sha256
    -- 44208 is not a SHA-256 digest (64 hexadecimal characters), so it was not computed over any
    -- artifact", which was true, and which no fixture could correct: a non-null wrong value blocks
    -- the catalogue fallback below, because that fallback exists only for a key NOTHING answered.
    --
    -- The fallback to business_key is kept where it is right -- a RESULT_KEY stage contributes the
    -- identity of what it created, and that IS its business key -- and refused where it is not.
    -- A stage that declares it contributes a value and supplies none now contributes NOTHING, so
    -- the object-payload branch below and then the committed catalogue get their turn, and a key
    -- with no answer anywhere stays unresolved and its rule refuses.
    select case when sc.contributes_kind = 'RESULT_KEY'
                then coalesce(sc.contributed_value, sc.business_key)
                else sc.contributed_value end v,
           sc.object_id o,
           sc.canonical_relation cr, sc.fixture_id fi, sc.fixture_version fv, sc.source_checksum ck
      into r
      from public.phase_d_scenario_record sc
     where sc.fixture_run_id = v_run and sc.contributes_ref = p_key
     order by sc.scenario_record_id limit 1;
    if found and r.v is null then r := null; end if;`;

const n = def.split(OLD).length - 1;
if (n !== 1) { console.error(`anchor matched ${n} times`); process.exit(1); }

let body = def.replace(OLD, NEW);

// `if found` immediately after must also require a value.
const GUARD_OLD = `    if found then
      value := to_jsonb(r.v);`;
const GUARD_NEW = `    if r.v is not null then
      value := to_jsonb(r.v);`;
if (body.split(GUARD_OLD).length - 1 !== 1) { console.error('guard anchor'); process.exit(1); }
body = body.replace(GUARD_OLD, GUARD_NEW);

const STAGE = `-- The one stage that declares a VALUE and was classified as a KEY. artifact_sha256 is a digest
-- computed over the artifact body, not the identity of the revision row, and F08 already writes it
-- into that record's payload -- where branch (1b) of fn_phase_d_fixture_input reads it from. The
-- reclassification is what lets branch (1b) get its turn.
UPDATE public.phase_d_fixture_stage
   SET contributes_kind = 'PAYLOAD_VALUE'
 WHERE stage_key = 'artifact_revision'
   AND contributes_ref = 'artifact_sha256'
   AND contributes_kind = 'RESULT_KEY';
`;

const HEADER = `-- F40 - a stage that contributed nothing still answered, with its own row id
--
-- MEASURED, on the resolved context of W08's first step inside a fixture scenario:
--
--   artifact_sha256 = 44208   <- phase_d_scenario_record: the ux_specification created by fixture run 802
--
-- 44208 is a primary key. BR-036 refused it, correctly and precisely: "artifact_sha256 44208 is not
-- a SHA-256 digest (64 hexadecimal characters), so it was not computed over any artifact." Three
-- workflows -- W08, W22, W24 -- have their FIRST handler refusal there, and W20 has it as one of
-- two.
--
-- THE MECHANISM. fn_phase_d_fixture_input branch (1) resolves a context key from the scenario
-- record whose contributes_ref names it, as coalesce(contributed_value, business_key). Every one of
-- the 32 stages is classified contributes_kind = 'RESULT_KEY', including artifact_revision, whose
-- contributed_value is never set. So the coalesce fell through to the row id and the key was
-- ANSWERED -- which matters twice over, because branch (2), the committed catalogue, runs only for
-- a key nothing else answered. A wrong non-null value does not merely fail a rule; it locks out
-- the fixture that would have been right. F39 added a computed artifact_sha256 to the catalogue
-- and it could never be reached.
--
-- TWO CHANGES, AND THE SECOND IS THE GENERAL ONE:
--
--   * artifact_revision is reclassified PAYLOAD_VALUE, because artifact_sha256 is a digest computed
--     over the artifact body and not the identity of the revision row. F08 already writes that
--     digest into the record's payload, and branch (1b) reads payloads -- it simply never got its
--     turn.
--
--   * branch (1) falls back to business_key ONLY for a RESULT_KEY stage, where the identity of what
--     was created is genuinely the answer. A stage that declares it contributes a value and
--     supplies none now contributes nothing, so the payload branch and then the catalogue get their
--     turn, and a key nothing can answer stays unresolved and its rule refuses -- which is the
--     contract working rather than a row id wearing a digest's name.

`;

writeFileSync('scripts/sql/phase_d_f40_a_stage_that_contributed_nothing_still_answered_with_its_row_id.sql',
  HEADER + STAGE + '\n' + body + ';\n');
console.log('written');
