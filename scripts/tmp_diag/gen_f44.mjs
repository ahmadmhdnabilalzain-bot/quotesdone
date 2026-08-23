import { writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';

const [{ def }] = await sql(
  `select pg_get_functiondef('public.fn_phase_d_object_write(jsonb)'::regprocedure) as def`);

// --- the EXISTING_TABLE return -----------------------------------------------------------------
const EXT_OLD = `      'result_reference', format('%s:%s=%s', wm.target_relation, wm.key_column, v_result_ref),
      'business_key', v_key, 'state', v_state,`;
const EXT_NEW = `      'result_reference', format('%s:%s=%s', wm.target_relation, wm.key_column, v_result_ref),
      -- F44. THE CANONICAL REFERENCE, RETURNED BY THE WRITER ITSELF.
      -- Which identity is canonical for this object is a property of the object, recorded once in
      -- public.phase_d_object_reference_strategy and derived from the frozen 56-object map. For an
      -- EXISTING_TABLE object it is the relation's own primary key -- the value this write just
      -- produced -- and every caller downstream now takes it from here rather than choosing.
      'canonical_ref', public.fn_phase_d_ref(jsonb_build_object(
                         'object_id', v_object, 'identity', v_result_ref,
                         'owner_ref', v_owner_ref)),
      'business_key', v_key, 'state', v_state,`;

// --- the PHASE_D_STORE return ------------------------------------------------------------------
const STO_OLD = `    'result_reference', format('public.phase_d_object_record:record_id=%s', v_id),
    'version', v_version, 'state', v_readback.state,`;
const STO_NEW = `    'result_reference', format('public.phase_d_object_record:record_id=%s', v_id),
    -- F44. For a PHASE_D_STORE object the canonical identity is object_id + business_key + version.
    -- record_id stays in the envelope as the physical detail it is, never as the identity.
    'canonical_ref', public.fn_phase_d_ref(jsonb_build_object(
                       'object_id', v_object, 'identity', v_key,
                       'version', v_version::text, 'owner_ref', v_owner_ref)),
    'version', v_version, 'state', v_readback.state,`;

let body = def;
for (const [name, o, n2] of [['EXISTING_TABLE return', EXT_OLD, EXT_NEW], ['PHASE_D store return', STO_OLD, STO_NEW]]) {
  const c = body.split(o).length - 1;
  if (c !== 1) { console.error(`anchor "${name}" matched ${c}`); process.exit(1); }
  body = body.replace(o, n2);
}

const PRELUDE = `-- The scenario record stores the canonical reference the writer returned, not its own row id.
ALTER TABLE public.phase_d_scenario_record
  ADD COLUMN IF NOT EXISTS canonical_ref jsonb;

COMMENT ON COLUMN public.phase_d_scenario_record.canonical_ref IS
  'The canonical reference envelope returned by the write service for the object this stage created. '
  'The scenario row''s own scenario_record_id is NEVER the business object identity -- that confusion '
  'is the defect F43 and F44 exist to remove. F44.';
`;

const HEADER = `-- F44 - the writer returns the reference, so nothing downstream has to choose one
--
-- F43 recorded, once, which identity is canonical for each of the 56 frozen business objects. This
-- makes the write services hand that reference back, so every caller downstream takes it rather
-- than picking among the four keys that were previously all in circulation.
--
-- WHY THIS IS THE WHOLE FIX AND NOT A PER-RULE ONE. The frozen map already encodes which identity
-- each object is known by, and every business rule was written against that same map. Checked
-- against the six rules that were refusing:
--
--   inquiry                    EXISTING_TABLE  public.inquiries      -> relation pk   BR-013 reads public.inquiries
--   supplier_account           EXISTING_TABLE  public.leads          -> relation pk   BR-015 reads public.leads
--   payment_transaction        EXISTING_TABLE  public.transactions   -> relation pk   BR-020 reads transactions
--   supplier_safe_package      PHASE_D_STORE                         -> business key  BR-012 reads the object store
--   customer_terms_acceptance  PHASE_D_STORE                         -> business key  BR-026 reads the object store
--   quotation_revision         PHASE_D_STORE                         -> business key  BR-035 reads the object store
--
-- Six for six, mechanically, with no per-key list. The rules were never inconsistent with each
-- other -- they were all consistent with the frozen map, and the fixture factory was the one thing
-- that was not. That is why F42's two-stage reclassification was the right shape at the wrong
-- scale, and why the founder's instruction was to do this once for every path.
--
-- THE REST OF THE ROUTINE IS BYTE-IDENTICAL. Two anchors, each required to match exactly once.

`;

writeFileSync('scripts/sql/phase_d_f44_the_writer_returns_the_reference_so_nothing_downstream_chooses.sql',
  HEADER + PRELUDE + '\n' + body + ';\n');
console.log('written');
