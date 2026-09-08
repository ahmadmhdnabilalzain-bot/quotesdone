import { writeFileSync } from 'node:fs';
import { sql } from '../lib/db.mjs';

const [{ def }] = await sql(
  `select pg_get_functiondef('public.fn_phase_d_fixture_scenario(jsonb)'::regprocedure) as def`);

const VALUE_EXPR = `case when st.stage_key = 'inquiry_route_set' then 'confirmed'
                                  else split_part(v_w->>'result_reference', '=', 2) end`;

const VALUE_NEW = `case when st.stage_key = 'inquiry_route_set' then 'confirmed'
                                  -- F41. A PAYLOAD_VALUE STAGE CONTRIBUTES A VALUE, NOT ITS ROW ID.
                                  -- artifact_revision declares it contributes artifact_sha256, and
                                  -- this expression handed over split_part(result_reference,'=',2)
                                  -- -- the primary key of the row it had just written. BR-036 read
                                  -- 44208 and refused it as "not a SHA-256 digest", correctly.
                                  -- The digest is in the record's own payload, written by F08 over
                                  -- the committed artifact body, so it is read from there.
                                  when st.contributes_kind = 'PAYLOAD_VALUE' then
                                    (select o.payload #>> array[st.contributes_ref]
                                       from public.phase_d_object_record o
                                      where o.object_id = st.object_id
                                        and o.business_key = split_part(v_w->>'result_reference', '=', 2)
                                      limit 1)
                                  else split_part(v_w->>'result_reference', '=', 2) end`;

const REFS_EXPR = `          case when st.stage_key = 'inquiry_route_set' then 'confirmed'
               else split_part(v_w->>'result_reference', '=', 2) end);`;

const REFS_NEW = `          case when st.stage_key = 'inquiry_route_set' then 'confirmed'
               when st.contributes_kind = 'PAYLOAD_VALUE' then
                 (select o.payload #>> array[st.contributes_ref]
                    from public.phase_d_object_record o
                   where o.object_id = st.object_id
                     and o.business_key = split_part(v_w->>'result_reference', '=', 2)
                   limit 1)
               else split_part(v_w->>'result_reference', '=', 2) end);`;

let body = def;
for (const [name, o, n2] of [['manifest value', VALUE_EXPR, VALUE_NEW], ['parent_refs value', REFS_EXPR, REFS_NEW]]) {
  const c = body.split(o).length - 1;
  if (c !== 1) { console.error(`anchor "${name}" matched ${c}`); process.exit(1); }
  body = body.replace(o, n2);
}

const HEADER = `-- F41 - the factory recorded a row id as the value the stage said it contributed
--
-- F40 reclassified the artifact_revision stage as PAYLOAD_VALUE and taught fn_phase_d_fixture_input
-- to stop falling back to a business key for a stage that contributes a value. It changed nothing,
-- and the measurement said so: artifact_sha256 still resolved to 44278.
--
-- The reason is here. fn_phase_d_fixture_scenario writes contributed_value for EVERY stage as
--
--     split_part(v_w->>'result_reference', '=', 2)
--
-- which is the primary key of the row the stage just created. contributed_value was therefore
-- never null, so F40's "a stage that supplied no value contributes nothing" branch could not fire.
-- The value was not missing; it was wrong, and confidently so.
--
-- A PAYLOAD_VALUE stage now contributes the value from the record's own payload under the key it
-- declares it contributes. For artifact_revision that is artifact_sha256, which F08 already
-- computes as sha256 over the committed artifact body and writes into the payload -- so the digest
-- BR-036 judges is a digest of something, and can be recomputed from the fixture.
--
-- RESULT_KEY and STATE stages are untouched: the identity of what was created is genuinely the
-- right answer for the first, and inquiry_route_set's literal 'confirmed' for the second.
--
-- THE REST OF THE ROUTINE IS BYTE-IDENTICAL. Two anchors, each required to match exactly once.

`;

writeFileSync('scripts/sql/phase_d_f41_the_factory_recorded_a_row_id_as_the_value_it_contributed.sql',
  HEADER + body + ';\n');
console.log('written');
