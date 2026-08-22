import { writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';

const get = async (sig) => (await sql(`select pg_get_functiondef('${sig}'::regprocedure) as def`))[0].def;

// ---------- 1. the scenario record stores the envelope -----------------------------------------
let rec = await get('public.fn_phase_d_scenario_record_write(jsonb)');
const REC_COLS_OLD = `     contributes_ref, contributed_value, contributes_kind, trace_id, provenance, expected_effect)`;
const REC_COLS_NEW = `     contributes_ref, contributed_value, contributes_kind, trace_id, provenance, expected_effect,
     canonical_ref)`;
const REC_VALS_OLD = `          nullif(p_input->>'expected_effect',''))`;
const REC_VALS_NEW = `          nullif(p_input->>'expected_effect',''),
          -- F44/F45. The canonical reference the write service returned. The scenario row's own
          -- scenario_record_id is never the business object identity.
          p_input->'canonical_ref')`;
for (const [n, o, x] of [['record columns', REC_COLS_OLD, REC_COLS_NEW], ['record values', REC_VALS_OLD, REC_VALS_NEW]]) {
  const c = rec.split(o).length - 1;
  if (c !== 1) { console.error(`anchor "${n}" matched ${c}`); process.exit(1); }
  rec = rec.replace(o, x);
}

// ---------- 2. the factory passes it, and contributes the canonical identity --------------------
let fac = await get('public.fn_phase_d_fixture_scenario(jsonb)');

const FAC_VALUE_OLD = `        'contributed_value', case when st.stage_key = 'inquiry_route_set' then 'confirmed'`;
const FAC_VALUE_NEW = `        'canonical_ref',     v_w->'canonical_ref',
        'contributed_value', case when st.stage_key = 'inquiry_route_set' then 'confirmed'`;
{
  const c = fac.split(FAC_VALUE_OLD).length - 1;
  if (c !== 1) { console.error(`anchor "factory canonical_ref" matched ${c}`); process.exit(1); }
  fac = fac.replace(FAC_VALUE_OLD, FAC_VALUE_NEW);
}

// Both identity arms collapse into one: the canonical reference decides, per the frozen map.
const FAC_ID_OLD = `                                  when st.contributes_kind = 'OBJECT_KEY'
                                    then v_w->>'business_key'`;
const FAC_ID_NEW = `                                  -- F45. OBJECT_KEY AND RESULT_KEY WERE THE SAME QUESTION ASKED TWICE.
                                  -- Which identity an object is known by is a property of the
                                  -- object, recorded once in phase_d_object_reference_strategy and
                                  -- derived from the frozen map -- not something a stage decides.
                                  -- Both arms are now the canonical reference the writer returned.
                                  when st.contributes_kind in ('OBJECT_KEY','RESULT_KEY')
                                    then v_w->'canonical_ref'->'physical_ref'->>'pk_value'`;
{
  const c = fac.split(FAC_ID_OLD).length - 1;
  if (c !== 1) { console.error(`anchor "factory identity arm" matched ${c}`); process.exit(1); }
  fac = fac.replace(FAC_ID_OLD, FAC_ID_NEW);
}

const FAC_REFS_OLD = `               when st.contributes_kind = 'OBJECT_KEY' then v_w->>'business_key'`;
const FAC_REFS_NEW = `               when st.contributes_kind in ('OBJECT_KEY','RESULT_KEY')
                 then v_w->'canonical_ref'->'physical_ref'->>'pk_value'`;
{
  const c = fac.split(FAC_REFS_OLD).length - 1;
  if (c !== 1) { console.error(`anchor "factory parent_refs arm" matched ${c}`); process.exit(1); }
  fac = fac.replace(FAC_REFS_OLD, FAC_REFS_NEW);
}

// The trailing `else split_part(...)` arms are now unreachable for identity kinds; they remain for
// a stage with no contributes_kind at all, which the CHECK does not permit. Left in place rather
// than deleted so the diff is exactly the two arms this file is about.

// ---------- 3. the resolver reads the envelope --------------------------------------------------
let inp = await get('public.fn_phase_d_fixture_input(bigint,text,text)');
const INP_OLD = `    select case when sc.contributes_kind = 'RESULT_KEY'
                then coalesce(sc.contributed_value, sc.business_key)
                else sc.contributed_value end v,`;
const INP_NEW = `    -- F45. THE CANONICAL REFERENCE, OR NOTHING. There is no coalesce chain here on purpose: a
    -- fallback among the scenario row id, the object-record key, the business key and the relation
    -- primary key is precisely the guessing the founder's ruling of 23 Aug 2026 removes. An identity
    -- stage answers from the reference the write service returned; a PAYLOAD_VALUE or STATE stage
    -- answers with the value it settled; anything else contributes nothing and the key falls through
    -- to the object payload, then to the committed catalogue, then to an explicit refusal.
    select case when sc.contributes_kind in ('PAYLOAD_VALUE','STATE') then sc.contributed_value
                when sc.canonical_ref is not null
                  then sc.canonical_ref->'physical_ref'->>'pk_value'
                else null end v,`;
{
  const c = inp.split(INP_OLD).length - 1;
  if (c !== 1) { console.error(`anchor "fixture_input branch 1" matched ${c}`); process.exit(1); }
  inp = inp.replace(INP_OLD, INP_NEW);
}

const HEADER = `-- F45 - every Phase D path takes the reference instead of choosing a key
--
-- F43 recorded which identity is canonical for each of the 56 objects; F44 made the write services
-- return it. This migrates the three paths that were choosing for themselves:
--
--   fn_phase_d_scenario_record_write   stores the envelope beside the row it created
--   fn_phase_d_fixture_scenario        contributes the canonical identity, not a row id
--   fn_phase_d_fixture_input           answers a context key from the envelope, or not at all
--
-- OBJECT_KEY AND RESULT_KEY WERE THE SAME QUESTION ASKED TWICE. F42 added OBJECT_KEY because two
-- stages needed the object-store key while the rest needed a relation primary key, and classified
-- them by hand. That list was correct and could not stay correct: which identity an object is known
-- by is a property of the OBJECT, and the frozen map has always said so. Both arms now read the
-- reference, and the classification is no longer a per-stage decision anyone can get wrong.
--
-- THERE IS NO FALLBACK CHAIN IN THE RESOLVER, and that is deliberate. The previous body was
-- coalesce(contributed_value, business_key), which is a guess between two keys, and it is how
-- artifact_sha256 came to resolve to 44208. An identity stage now answers from the envelope or
-- contributes nothing at all, so the key falls through to the object payload, then to the committed
-- catalogue, then to an explicit refusal -- each of which is a stated source rather than a guess.
--
-- THE REST OF ALL THREE ROUTINES IS BYTE-IDENTICAL. Five anchors, each required to match once.

`;

writeFileSync('scripts/sql/phase_d_f45_every_path_takes_the_reference_instead_of_choosing_a_key.sql',
  HEADER + rec + ';\n\n' + fac + ';\n\n' + inp + ';\n');
console.log('written');
