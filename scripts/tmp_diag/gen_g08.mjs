import { writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';

const HEAD = `-- G08 — seven keys, one answer, and the answer was the run's own row id
--
-- fn_phase_d_step_context answered inquiry_id, supplier_id, quote_id, transaction_id, document_id,
-- comparison_id and refund_id from a single branch:
--
--     v_val := to_jsonb(v_row_id);   -- the primary key of the run's OWN business object
--
-- which is right for exactly one of the seven on any given run and wrong for the other six. It does
-- not fail loudly: it hands a rule a real identifier of the wrong kind, and the rule then refuses
-- with a sentence about a row that was never the subject.
--
-- MEASURED, by driving each workflow and reading the dispatch ledger:
--
--   W14  primary object quotation -> public.quotes.id (uuid)
--        BR-015: "supplier 9b7619c4-7491-8db1-4239-1f381a591dfe is not an approved, verified
--        supplier" — that uuid is the QUOTE. The scenario's supplier is public.leads.id 34894, an
--        approved and verified one, and BR-015 never saw it.
--   W15  primary object quotation_comparison -> public.quote_comparisons.id (bigint)
--        BR-020: "no transaction 4478" — 4478 is the COMPARISON.
--   W07  primary object inquiry_document -> public.documents.id (bigint)
--        BR-013: "inquiry 4507 is not quote-ready" — 4507 is the DOCUMENT.
--
-- Three workflows producing no business effect at all, three rules each refusing correctly about
-- the wrong object. This is the estate's recurring shape stated once more: an instrument reporting
-- on a subject other than the one it names.
--
-- TWO CHANGES, AND THE FIRST IS THE CORRECTNESS FIX.
--
-- 1. The branch now answers only where it has grounds to. public.phase_d_context_key_object already
--    records which object each of these keys names. If the key names the run's own object, the row
--    id is the answer. If not, the run's relation is searched for a column that is a declared
--    FOREIGN KEY to that object's canonical relation, and failing that for a column named exactly
--    like the key — both derived from the catalog, neither listed here. Where neither exists the key
--    is left UNRESOLVED, which is a truthful "this run does not name one" rather than a confident
--    wrong number. That alone fixes W14, whose quotes.supplier_id is a declared foreign key to
--    public.leads.
--
-- 2. A SCENARIO-REFERENCE DOOR, for the two the schema cannot reach. public.quote_comparisons
--    carries no transaction column and public.documents relates to its inquiry through a
--    polymorphic (ref_table, ref_id) pair, so no derivation from the schema can answer W15's
--    transaction_id or W07's inquiry_id. The scenario, however, created both objects and recorded
--    the canonical reference of each in public.phase_d_scenario_record.
--
--    That door sits exactly where F11 put the fixture door: AFTER every real source and BEFORE the
--    catalogue, and it returns nothing at all unless fn_phase_d_fixture_context() verifies an hmac
--    over the current txid keyed by a secret no role can read. In production it resolves nothing.
--    It is strictly better than the catalogue door it sits in front of, because it answers with the
--    canonical reference of a row the scenario actually created rather than with a committed
--    constant — which is the whole of what G02, G06 and D9g were each about.
--
-- NOTHING IS HANDED TO A RULE BY A CALLER. E32's property is intact: the driver still passes no
-- context, and both new paths read rows.
--
-- Four anchors, each required to match exactly once. The rest of the routine is byte-identical.`;

const r = await sql(`select pg_get_functiondef(p.oid) as def from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_step_context'`);
let def = r[0].def;
const splice = (anchor, repl, what) => {
  const n = def.split(anchor).length - 1;
  if (n !== 1) throw new Error(`${what}: anchor matched ${n} time(s)`);
  def = def.replace(anchor, repl);
};

splice(`  v_val_txt text;  -- G02: the acceptance value read back before it becomes jsonb`,
`  v_val_txt text;  -- G02: the acceptance value read back before it becomes jsonb
  v_key_obj text;  -- G08: the object a context key names, from phase_d_context_key_object
  v_link    text;  -- G08: the column on this run's relation that reaches that object
  v_link_v  text;  -- G08: what that column holds
  v_scn_ref jsonb; -- G08: the canonical reference the scenario recorded for that object`,
  'G08 declaration');

splice(`    elsif v_k in ('inquiry_id','supplier_id','quote_id','transaction_id','document_id',
                  'comparison_id','refund_id') then
      if v_found then
        v_val := to_jsonb(v_row_id);
        v_src := format('%s.%s, looked up by the run''s business_object_id', v_rel, v_keycol);
      end if;`,
`    elsif v_k in ('inquiry_id','supplier_id','quote_id','transaction_id','document_id',
                  'comparison_id','refund_id') then
      -- G08. THIS ANSWERED ALL SEVEN WITH THE RUN'S OWN ROW ID. See the file header: BR-015 was told
      -- a quote was a supplier, BR-020 that a comparison was a transaction, BR-013 that a document
      -- was an inquiry. Each key names an object, that object is recorded, and the answer must come
      -- from the object it names or not at all.
      select cko.object_id into v_key_obj
        from public.phase_d_context_key_object cko where cko.context_key = v_k;

      if v_found and v_key_obj is not null and v_key_obj = v_obj then
        -- The key names the object this run is about. The row id is the answer.
        v_val := to_jsonb(v_row_id);
        v_src := format('%s.%s, looked up by the run''s business_object_id', v_rel, v_keycol);

      elsif v_found and v_key_obj is not null then
        -- The key names a DIFFERENT object. Reach it from this run's own row, through a declared
        -- foreign key to that object's canonical relation where one exists, and otherwise through a
        -- column named exactly like the key. Both are read from the catalog; neither is listed here.
        select a.attname into v_link
          from pg_constraint con
          join lateral unnest(con.conkey) k(attnum) on true
          join pg_attribute a on a.attrelid = con.conrelid and a.attnum = k.attnum
         where con.contype = 'f'
           and con.conrelid = to_regclass(v_rel)
           and con.confrelid = (select to_regclass(bb.canonical_relation)
                                  from public.phase_d_business_object_binding bb
                                 where bb.object_id = v_key_obj)
         order by a.attname limit 1;
        if v_link is null then
          select a.attname into v_link from pg_attribute a
           where a.attrelid = to_regclass(v_rel) and a.attnum > 0 and not a.attisdropped
             and a.attname = v_k;
        end if;
        if v_link is not null then
          begin
            execute format('select %I::text from %s where %I::text = $1',
                           v_link, to_regclass(v_rel)::text, v_keycol)
              into v_link_v using v_row_id;
          exception when others then v_link_v := null; end;
          if coalesce(btrim(v_link_v),'') <> '' then
            v_val := to_jsonb(v_link_v);
            v_src := format('%s.%s of the run''s own row, which reaches %s', v_rel, v_link, v_key_obj);
          end if;
          v_link := null; v_link_v := null;
        end if;
      end if;`,
  'G08 object-key branch');

// The scenario-reference door, immediately before the F11 fixture door.
splice(`    -- F11. THE FIXTURE DOOR, AND ONLY AFTER EVERY REAL SOURCE HAS BEEN TRIED.`,
`    -- G08. THE SCENARIO-REFERENCE DOOR, in front of the catalogue and behind every real source.
    --
    -- public.quote_comparisons carries no transaction column and public.documents relates to its
    -- inquiry through a polymorphic (ref_table, ref_id) pair, so no derivation from the schema can
    -- reach W15's transaction_id or W07's inquiry_id from the run's own row. The scenario created
    -- both objects and recorded the canonical reference of each. This answers from THAT -- a row the
    -- scenario actually wrote through fn_phase_d_object_write -- rather than from the committed
    -- constant the fixture door below would otherwise supply.
    --
    -- It returns nothing unless fn_phase_d_fixture_context() verifies an hmac over the current txid
    -- keyed by a secret no role can SELECT. In production this block resolves nothing at all.
    if (v_val is null or v_val = 'null'::jsonb
        or (jsonb_typeof(v_val) = 'string' and btrim(coalesce(v_val #>> '{}','')) = ''))
       and public.fn_phase_d_fixture_context() is not null then
      select cko.object_id into v_key_obj
        from public.phase_d_context_key_object cko where cko.context_key = v_k;
      if v_key_obj is not null then
        select sc.canonical_ref into v_scn_ref
          from public.phase_d_scenario_record sc
         where sc.fixture_run_id = public.fn_phase_d_fixture_context()
           and sc.object_id = v_key_obj
         order by sc.scenario_record_id desc limit 1;
        if v_scn_ref is not null
           and coalesce(btrim(v_scn_ref->>'canonical_identity'),'') <> '' then
          v_ctx  := v_ctx  || jsonb_build_object(v_k, to_jsonb(v_scn_ref->>'canonical_identity'));
          v_prov := v_prov || jsonb_build_object(v_k,
            format('the canonical reference the scenario recorded for %s in '
                || 'public.phase_d_scenario_record -- a row this scenario created through '
                || 'fn_phase_d_object_write, not a committed constant', v_key_obj));
          v_scn_ref := null; v_key_obj := null;
          continue;
        end if;
        v_scn_ref := null;
      end if;
      v_key_obj := null;
    end if;

    -- F11. THE FIXTURE DOOR, AND ONLY AFTER EVERY REAL SOURCE HAS BEEN TRIED.`,
  'G08 scenario door');

writeFileSync('scripts/sql/phase_d_g08_seven_keys_one_answer_and_it_was_the_runs_own_row_id.sql',
  HEAD + '\n' + def + '\n');
console.log('G08 written');
