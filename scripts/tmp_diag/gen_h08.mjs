// H08 generator: fn_phase_d_fixture_scenario — the F15 settling write addresses the row the first
// write returned, not the key the stage was called with.
import { writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';

const HEAD = `-- H08 — the settling write looked for the row by the key the stage was called with, and for a
--       generated-key relation that key names nothing
--
-- F15 made the factory read a created row's state column back and, where the product's own
-- triggers had moved it, write the stage's declared state again through the same canonical
-- service. That second write passed business_key = v_key, the stage's deterministic uuid. For an
-- EXISTING_TABLE object whose key column is generated and not in its write map -- supplier_account
-- on public.leads is the measured case -- fn_phase_d_object_write resolved no identity from a uuid
-- that is not the relation's key, INSERTED, and the scenario ended with two suppliers: the one the
-- stage recorded and the one it had just created. Measured 23 Aug 2026: parent_refs.supplier_id and
-- the scenario's supplier_account reference disagreed (36093 vs 36096), the quotation carried a
-- third (36089), and every W09 step that read its supplier read a different one.
--
-- F44 made the writer RETURN the canonical identity of the row it wrote, and H02 made the writer
-- find a row by that identity when the map carries no key column. So the settling write now
-- addresses the row the first write returned -- split_part(result_reference, '=', 2), already the
-- value the manifest records as business_key -- and falls back to v_key only where the writer
-- returned nothing, which it cannot do without raising. One row per stage, as the stage intends.
--
-- ROLLBACK: re-apply the previous body of fn_phase_d_fixture_scenario (phase_d_g16 is the last file
-- that defines it). No DDL.
--
-- One anchor, required to match exactly once. The rest of the routine is byte-identical.`;

const r = await sql(`select pg_get_functiondef(p.oid) as def from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_fixture_scenario'`);
let def = r[0].def;
const once = (anchor, label) => { const n = def.split(anchor).length - 1; if (n !== 1) throw new Error(`${label}: anchor matched ${n} times`); };

const a1 = `          if v_actual is distinct from v_state then
            v_w := public.fn_phase_d_object_write(jsonb_build_object(
              'object_id', st.object_id, 'business_key', v_key, 'owner_ref', v_owner,
              'created_by', v_actor, 'state', v_state, 'payload', v_pay));`;
once(a1, 'A1');
def = def.replace(a1, `          if v_actual is distinct from v_state then
            -- H08. ADDRESS THE ROW THE FIRST WRITE RETURNED. v_key is the stage's own uuid and names
            -- nothing on a generated-key relation; the returned identity is the row.
            v_w := public.fn_phase_d_object_write(jsonb_build_object(
              'object_id', st.object_id,
              'business_key', coalesce(split_part(v_w->>'result_reference','=',2), v_key),
              'owner_ref', v_owner,
              'created_by', v_actor, 'state', v_state, 'payload', v_pay));`);

writeFileSync('scripts/sql/phase_d_h08_the_settling_write_named_a_key_the_relation_did_not_have.sql', HEAD + '\n' + def + '\n');
console.log('H08 written');
