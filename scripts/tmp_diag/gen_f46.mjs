import { writeFileSync } from 'node:fs';
import { sql } from '../lib/db.mjs';
const get = async (sig) => (await sql(`select pg_get_functiondef('${sig}'::regprocedure) as def`))[0].def;

// ---------- fn_phase_d_ref: one field that always holds the identity ---------------------------
let ref = await get('public.fn_phase_d_ref(jsonb)');
const REF_OLD = `  return jsonb_strip_nulls(jsonb_build_object(
    'object_id',    v_obj,
    'storage_kind', s.storage_kind,
    'business_key', case when s.storage_kind = 'PHASE_D_STORE' then v_ident else v_ident end,
    'version',      coalesce(v_ver, 1),
    'physical_ref', jsonb_build_object(
                      'schema',    s.physical_schema,
                      'relation',  s.physical_relation,
                      'pk_column', case when s.storage_kind = 'PHASE_D_STORE'
                                        then 'business_key' else s.physical_pk_column end,
                      'pk_value',  v_ident),`;
const REF_NEW = `  -- F46. ONE FIELD THAT ALWAYS HOLDS THE IDENTITY, WHATEVER THE STORAGE KIND.
  --
  -- The round-trip proof of section 2 found this on its first run, which is what it is for. The
  -- envelope carried the identity in physical_ref.pk_value on the way IN and the physical row id in
  -- the same field on the way OUT, because for a PHASE_D_STORE object those are different things:
  -- the identity is object_id + business_key + version, and the physical row is
  -- phase_d_object_record.record_id, which nobody knows until the object is resolved. Three of seven
  -- round trips compared the two and reported "wrong identity" on objects that had resolved
  -- perfectly.
  --
  -- canonical_identity is now the single field every consumer reads. It is the business key for a
  -- PHASE_D_STORE object and the relation's primary key for the other two kinds, and no caller has
  -- to know which -- that is the whole point of recording the strategy once. physical_ref now
  -- describes where the object physically lives and carries pk_value only when the caller actually
  -- knows it; for the store it is filled in by fn_phase_d_ref_resolve.
  return jsonb_strip_nulls(jsonb_build_object(
    'object_id',          v_obj,
    'storage_kind',       s.storage_kind,
    'canonical_identity', v_ident,
    'business_key',       v_ident,
    'version',            coalesce(v_ver, 1),
    'physical_ref', jsonb_build_object(
                      'schema',    s.physical_schema,
                      'relation',  case when s.storage_kind = 'PHASE_D_STORE'
                                        then 'phase_d_object_record' else s.physical_relation end,
                      'pk_column', case when s.storage_kind = 'PHASE_D_STORE'
                                        then 'record_id' else s.physical_pk_column end,
                      'pk_value',  case when s.storage_kind = 'PHASE_D_STORE'
                                        then null else v_ident end),`;
{
  const c = ref.split(REF_OLD).length - 1;
  if (c !== 1) { console.error(`anchor "ref envelope" matched ${c}`); process.exit(1); }
  ref = ref.replace(REF_OLD, REF_NEW);
}

// ---------- fn_phase_d_ref_resolve: echo the identity, and read it from either field ------------
let res = await get('public.fn_phase_d_ref_resolve(jsonb)');
const RES_IN_OLD = `  v_key   text := nullif(btrim(coalesce(p_ref->'physical_ref'->>'pk_value',
                                        p_ref->>'business_key','')),'');`;
const RES_IN_NEW = `  -- F46. canonical_identity first: it is the one field that always holds the identity. The other
  -- two are read only for an envelope built before F46, and physical_ref.pk_value is deliberately
  -- LAST because for a PHASE_D_STORE object it is the physical row, not the identity.
  v_key   text := nullif(btrim(coalesce(p_ref->>'canonical_identity',
                                        p_ref->>'business_key',
                                        p_ref->'physical_ref'->>'pk_value','')),'');`;
{
  const c = res.split(RES_IN_OLD).length - 1;
  if (c !== 1) { console.error(`anchor "resolve input" matched ${c}`); process.exit(1); }
  res = res.replace(RES_IN_OLD, RES_IN_NEW);
}

const RES_STORE_OLD = `    return jsonb_build_object(
      'ok', true, 'object_id', v_obj, 'storage_kind', s.storage_kind,
      'business_key', v_rec.business_key, 'version', v_rec.version, 'state', v_rec.state,`;
const RES_STORE_NEW = `    return jsonb_build_object(
      'ok', true, 'object_id', v_obj, 'storage_kind', s.storage_kind,
      'canonical_identity', v_rec.business_key,
      'business_key', v_rec.business_key, 'version', v_rec.version, 'state', v_rec.state,`;
{
  const c = res.split(RES_STORE_OLD).length - 1;
  if (c !== 1) { console.error(`anchor "resolve store return" matched ${c}`); process.exit(1); }
  res = res.replace(RES_STORE_OLD, RES_STORE_NEW);
}

const RES_TBL_OLD = `  return jsonb_build_object(
    'ok', true, 'object_id', v_obj, 'storage_kind', s.storage_kind,
    'business_key', v_key, 'version', coalesce(v_ver, 1),`;
const RES_TBL_NEW = `  return jsonb_build_object(
    'ok', true, 'object_id', v_obj, 'storage_kind', s.storage_kind,
    'canonical_identity', v_key,
    'business_key', v_key, 'version', coalesce(v_ver, 1),`;
{
  const c = res.split(RES_TBL_OLD).length - 1;
  if (c !== 1) { console.error(`anchor "resolve table return" matched ${c}`); process.exit(1); }
  res = res.replace(RES_TBL_OLD, RES_TBL_NEW);
}

// ---------- the three consumers read canonical_identity ----------------------------------------
let fac = await get('public.fn_phase_d_fixture_scenario(jsonb)');
const F1_OLD = `                                  when st.contributes_kind in ('OBJECT_KEY','RESULT_KEY')
                                    then v_w->'canonical_ref'->'physical_ref'->>'pk_value'`;
const F1_NEW = `                                  when st.contributes_kind in ('OBJECT_KEY','RESULT_KEY')
                                    then v_w->'canonical_ref'->>'canonical_identity'`;
const F2_OLD = `               when st.contributes_kind in ('OBJECT_KEY','RESULT_KEY')
                 then v_w->'canonical_ref'->'physical_ref'->>'pk_value'`;
const F2_NEW = `               when st.contributes_kind in ('OBJECT_KEY','RESULT_KEY')
                 then v_w->'canonical_ref'->>'canonical_identity'`;
for (const [n, o, x] of [['factory manifest arm', F1_OLD, F1_NEW], ['factory refs arm', F2_OLD, F2_NEW]]) {
  const c = fac.split(o).length - 1;
  if (c !== 1) { console.error(`anchor "${n}" matched ${c}`); process.exit(1); }
  fac = fac.replace(o, x);
}

let inp = await get('public.fn_phase_d_fixture_input(bigint,text,text)');
const I_OLD = `                when sc.canonical_ref is not null
                  then sc.canonical_ref->'physical_ref'->>'pk_value'`;
const I_NEW = `                when sc.canonical_ref is not null
                  then sc.canonical_ref->>'canonical_identity'`;
{
  const c = inp.split(I_OLD).length - 1;
  if (c !== 1) { console.error(`anchor "fixture_input identity" matched ${c}`); process.exit(1); }
  inp = inp.replace(I_OLD, I_NEW);
}

const HEADER = `-- F46 - one field that always holds the identity, found by the round trip that was written to find it
--
-- Section 2 of the founder's ruling of 23 Aug 2026 asked for a create/resolve round trip on all 56
-- objects. Its first run reported three of seven resolutions as "wrong identity", and they were not.
--
-- The envelope carried the identity in physical_ref.pk_value on the way IN and the physical row id
-- in the same field on the way OUT. For an EXISTING_TABLE object those are the same value, so the
-- ambiguity was invisible. For a PHASE_D_STORE object they are different things by design: the
-- identity is object_id + business_key + version, and the physical row is
-- phase_d_object_record.record_id, which nobody knows until the object has been resolved.
--
-- That is the same defect this whole contract exists to remove, reappearing inside the contract
-- itself: one field meaning two things depending on who is holding it.
--
-- canonical_identity is now the single field every consumer reads -- the business key for a
-- PHASE_D_STORE object, the relation primary key for the other two kinds -- and no caller has to
-- know which. physical_ref goes back to describing only where the object physically lives, and
-- carries pk_value only when it is actually known.
--
-- Five routines, seven anchors, each required to match exactly once. Everything else is byte-identical.

`;

writeFileSync('scripts/sql/phase_d_f46_one_field_that_always_holds_the_identity.sql',
  HEADER + ref + ';\n\n' + res + ';\n\n' + fac + ';\n\n' + inp + ';\n');
console.log('written');
