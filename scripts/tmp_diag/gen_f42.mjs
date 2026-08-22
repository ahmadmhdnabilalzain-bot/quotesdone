import { writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';

const [{ def }] = await sql(
  `select pg_get_functiondef('public.fn_phase_d_fixture_scenario(jsonb)'::regprocedure) as def`);

// F41 left both expressions with the PAYLOAD_VALUE arm. Extend the same two with OBJECT_KEY.
const OLD_A = `                                  when st.contributes_kind = 'PAYLOAD_VALUE' then`;
const NEW_A = `                                  -- F42. AN OBJECT_KEY STAGE CONTRIBUTES THE KEY THE PHASE D
                                  -- OBJECT STORE USES, WHICH IS NOT THE RELATION'S ROW ID.
                                  when st.contributes_kind = 'OBJECT_KEY'
                                    then v_w->>'business_key'
                                  when st.contributes_kind = 'PAYLOAD_VALUE' then`;

const OLD_B = `          case when st.stage_key = 'inquiry_route_set' then 'confirmed'
               when st.contributes_kind = 'PAYLOAD_VALUE' then`;
const NEW_B = `          case when st.stage_key = 'inquiry_route_set' then 'confirmed'
               when st.contributes_kind = 'OBJECT_KEY' then v_w->>'business_key'
               when st.contributes_kind = 'PAYLOAD_VALUE' then`;

let body = def;
for (const [name, o, n2] of [['manifest arm', OLD_A, NEW_A], ['parent_refs arm', OLD_B, NEW_B]]) {
  const c = body.split(o).length - 1;
  if (c !== 1) { console.error(`anchor "${name}" matched ${c}`); process.exit(1); }
  body = body.replace(o, n2);
}

const PRELUDE = `-- The third classification, and the two stages that need it.
ALTER TABLE public.phase_d_fixture_stage
  DROP CONSTRAINT IF EXISTS phase_d_fixture_stage_contributes_kind_check;
ALTER TABLE public.phase_d_fixture_stage
  ADD CONSTRAINT phase_d_fixture_stage_contributes_kind_check
  CHECK (contributes_kind = ANY (ARRAY['RESULT_KEY'::text, 'STATE'::text,
                                       'PAYLOAD_VALUE'::text, 'OBJECT_KEY'::text]));

-- safe_package_ref and acceptance_ref are read by BR-012 and BR-026 against
-- public.phase_d_object_record. Every other stage keeps RESULT_KEY: BR-013 and BR-015 read
-- public.inquiries and public.leads and want the relation row they already get, and reclassifying
-- those would break two rules to fix two.
UPDATE public.phase_d_fixture_stage
   SET contributes_kind = 'OBJECT_KEY'
 WHERE contributes_ref IN ('safe_package_ref', 'acceptance_ref')
   AND contributes_kind = 'RESULT_KEY';
`;

const HEADER = `-- F42 - the same object, keyed one way by the scenario and another by the rules that read it
--
-- MEASURED inside one fixture scenario, comparing the two stores row by row:
--
--   object                      phase_d_scenario_record   phase_d_object_record        matching
--   customer_terms_acceptance   44779                     a0744275-4177-02ab-4a07-...  0
--   supplier_safe_package       44783                     9d4ca492-0fec-dadf-8a62-...  0
--   quotation_revision          44786                     5c99d6e1-167a-a2e1-d0ed-...  0
--   ux_specification            44789                     1213f219-4a40-5784-3186-...  0
--
-- The scenario record carries the primary key of the row in the real business relation; the Phase D
-- object store carries its own derived key. The context resolver hands the rules the first, and
-- fn_phase_d_rule_check looks it up in the second:
--
--   -- BR-012
--   select count(*) into v_n from public.phase_d_object_record o
--    where o.object_id = 'supplier_safe_package' and o.state = 'approved' and o.superseded_by is null
--      and (o.business_key = v_txt or 'supplier_safe_package:' || o.business_key = v_txt);
--
-- So a package the factory created, approved, in the right state, reads as **0 approved packages**,
-- and W12 and W13 refuse on their first step every drive. BR-026 has the same shape against
-- customer_terms_acceptance, which is W04 and W09.
--
-- WHY THIS IS NOT A COALESCE. The two shapes are both correct, for different rules. BR-013's refusal
-- names public.inquiries and BR-015's names public.leads: those rules want the RELATION row and get
-- it today. Keying the object store by the relation id would fix three rules, break two, and destroy
-- the replay determinism the derived key exists for -- a relation id is new on every drive, so a
-- replay would create a second record instead of colliding with itself.
--
-- WHAT IS DONE INSTEAD. The distinction is recorded as data on the stage, beside the two that were
-- already there. A stage says which kind of thing it contributes:
--
--   RESULT_KEY     the identity of the row it created in the canonical relation  (unchanged, 29 stages)
--   OBJECT_KEY     the key the Phase D object store uses for that object          (new, 2 stages)
--   PAYLOAD_VALUE  a value from the created record's payload                      (F40, 1 stage)
--   STATE          a literal state the stage settles                              (1 stage)
--
-- Only safe_package_ref and acceptance_ref are reclassified, because only their consuming rules read
-- the object store. This is a per-key decision and it is written where a per-key decision belongs --
-- on the row, with the reason in the migration -- rather than as a branch in a resolver that would
-- have to guess.
--
-- THE REST OF THE ROUTINE IS BYTE-IDENTICAL. Two anchors, each required to match exactly once.

`;

writeFileSync('scripts/sql/phase_d_f42_the_same_object_keyed_one_way_by_the_scenario_and_another_by_the_rules.sql',
  HEADER + PRELUDE + '\n' + body + ';\n');
console.log('written');
