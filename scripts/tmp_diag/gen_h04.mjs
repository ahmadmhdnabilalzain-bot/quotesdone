// H04 generator: fn_phase_d_fixture_effect_payload — three corrections to what the committed
// catalogue and the scenario supply to an effect payload, all fixture-context only.
import { writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';

const HEAD = `-- H04 — a key that names a row was asked of a resolver that had not been told to resolve it; a
--        constant was handed to a column that must be unique; and a relation with nothing
--        mandatory was handed nothing at all
--
-- Three corrections to fn_phase_d_fixture_effect_payload. It returns an empty object outside a
-- verified Phase D fixture context, before and after this file.
--
-- 1. W15-S02/S06/S08 REFUSED: null value in column "inquiry_id" of relation "quote_comparisons".
--    G14 asks fn_phase_d_step_context for a payload key that names a row -- inquiry_id,
--    transaction_id, group_id, field_id, requested_by -- before it consults the catalogue, which is
--    right. But fn_phase_d_step_context resolves ONLY the keys the step's rules and gates declare,
--    and no rule or gate of W15-S02 declares inquiry_id, so the resolver was asked about a key it
--    never tried and answered nothing. The object a payload key names is recorded in
--    public.phase_d_context_key_object, and the scenario recorded that object's canonical reference;
--    this file asks that register directly -- the same read fn_phase_d_fixture_input makes for a
--    CONTEXT_KEY -- and only then the catalogue. Nothing is chosen: a key not in the register, or an
--    object the scenario did not create, still gets nothing.
--
-- 2. W07-S04/S05 REFUSED: duplicate key value violates unique constraint "documents_bucket_path_key".
--    inquiry_document's map INSERTs into public.documents, whose (bucket, path) is UNIQUE. The
--    catalogue value for path is one committed constant, so the second versioned extraction of the
--    same document collided with the first. A committed constant is content; it cannot also be an
--    identity. Where a catalogue value lands in a column that belongs to a UNIQUE index of the
--    target relation, the step run id is appended -- read off the kernel's row, not chosen -- so
--    each versioned artifact of one run is a distinct row and a replay of the same step run lands on
--    the same path. The provenance says so.
--
-- 3. W28-S01/S02/S07 REFUSED: legal_risk_review supplied no column the write map for
--    public.legal_reviews can use. G14's population is "the NOT NULL, no-default columns the relation
--    demands", and public.legal_reviews demands none, so the handler reached the write with title,
--    summary, doc_kind and risk_level all absent. The population now also carries every mapped
--    column for which the committed catalogue holds an EFFECT_PAYLOAD value scoped to THIS step or
--    THIS workflow -- scoped, so a global fixture for "title" does not spray into every object that
--    happens to map one. The rows for W28 are committed alongside this file (H07).
--
-- ROLLBACK: re-apply the previous body of fn_phase_d_fixture_effect_payload (phase_d_g14 is the
-- last file that defines it). No DDL.
--
-- Three anchors, each required to match exactly once. The rest of the routine is byte-identical.`;

const r = await sql(`select pg_get_functiondef(p.oid) as def from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_fixture_effect_payload'`);
let def = r[0].def;
const once = (anchor, label) => { const n = def.split(anchor).length - 1; if (n !== 1) throw new Error(`${label}: anchor matched ${n} times`); };

// ---- 3. the population: NOT NULL no-default columns UNION mapped columns with a scoped fixture ----
const a1 = `      select m.key as src
        from m
        join pg_attribute a on a.attrelid = to_regclass(v_rel) and a.attname = m.col
        left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
       where a.attnum > 0 and a.attnotnull and d.adbin is null
         and a.attidentity = '' and a.attgenerated = ''
         and m.key not in ('business_key','owner_ref','state')
    loop`;
once(a1, 'A1');
def = def.replace(a1, `      select m.key as src
        from m
        join pg_attribute a on a.attrelid = to_regclass(v_rel) and a.attname = m.col
        left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
       where a.attnum > 0 and a.attidentity = '' and a.attgenerated = ''
         and m.key not in ('business_key','owner_ref','state')
         and (   (a.attnotnull and d.adbin is null)
              -- H04 (3). A mapped column the committed catalogue speaks for, at this step or in
              -- this workflow. Scoped rows only: a global fixture fills nothing here.
              or exists (select 1 from public.phase_d_fixture_catalogue c
                          where c.scope = 'EFFECT_PAYLOAD' and c.field_key = m.key
                            and (c.step_id = sr.step_id
                                 or (c.step_id is null and c.workflow_id = e.workflow_id))))
    loop`);

// ---- 1 + 2. the per-key resolution: register first, then catalogue; unique columns get the run ----
const a2 = `      v_ctx_val := (public.fn_phase_d_step_context(p_step_run_id))->'context'->(r.src);
      if v_ctx_val is not null and v_ctx_val <> 'null'::jsonb then
        v_out := v_out || jsonb_build_object(r.src, v_ctx_val);
        continue;
      end if;
      select * into fi from public.fn_phase_d_fixture_input(p_step_run_id, 'EFFECT_PAYLOAD', r.src) fi;
      if fi.value is not null then
        v_out := v_out || jsonb_build_object(r.src, fi.value);
      end if;
    end loop;`;
once(a2, 'A2');
def = def.replace(a2, `      v_ctx_val := (public.fn_phase_d_step_context(p_step_run_id))->'context'->(r.src);
      if v_ctx_val is not null and v_ctx_val <> 'null'::jsonb then
        v_out := v_out || jsonb_build_object(r.src, v_ctx_val);
        continue;
      end if;
      -- H04 (1). A KEY THAT NAMES AN OBJECT IS ANSWERED FROM THE OBJECT THE SCENARIO CREATED, whether
      -- or not this step's rules declared the key. The register is public.phase_d_context_key_object;
      -- the identity is the canonical reference the scenario recorded for that object.
      select to_jsonb(sc.canonical_ref->>'canonical_identity') into v_ctx_val
        from public.phase_d_context_key_object cko
        join public.phase_d_scenario_record sc
          on sc.object_id = cko.object_id and sc.fixture_run_id = v_run
       where cko.context_key = r.src
         and coalesce(btrim(sc.canonical_ref->>'canonical_identity'),'') <> ''
       order by sc.scenario_record_id desc
       limit 1;
      if v_ctx_val is not null then
        v_out := v_out || jsonb_build_object(r.src, v_ctx_val);
        continue;
      end if;
      select * into fi from public.fn_phase_d_fixture_input(p_step_run_id, 'EFFECT_PAYLOAD', r.src) fi;
      if fi.value is not null then
        -- H04 (2). A CONSTANT CANNOT BE AN IDENTITY. Where this column belongs to a UNIQUE index of
        -- the target relation, the step run id is appended so each versioned row of one run is its
        -- own row and a replay of the same step run lands on the same value.
        if jsonb_typeof(fi.value) = 'string'
           and exists (select 1
                         from pg_index i
                         join pg_attribute a2 on a2.attrelid = i.indrelid and a2.attnum = any(i.indkey)
                        where i.indrelid = to_regclass(v_rel) and i.indisunique
                          and a2.attname = (select m2.col
                                              from public.phase_d_object_write_map wm2,
                                                   lateral jsonb_each_text(wm2.column_map) m2(col, key)
                                             where wm2.object_id = e.effect_object_id and m2.key = r.src
                                             limit 1)) then
          v_out := v_out || jsonb_build_object(r.src,
                     to_jsonb((fi.value #>> '{}') || '/' || sr.step_id || '/' || p_step_run_id::text));
        else
          v_out := v_out || jsonb_build_object(r.src, fi.value);
        end if;
      end if;
    end loop;`);

writeFileSync('scripts/sql/phase_d_h04_a_key_that_names_a_row_a_constant_that_must_be_unique_a_relation_that_demands_nothing.sql', HEAD + '\n' + def + '\n');
console.log('H04 written');
