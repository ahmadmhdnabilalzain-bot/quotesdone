import { writeFileSync } from 'node:fs';
import { sql } from '../phase_b/lib/db.mjs';

const [{ prosrc }] = await sql(
  `select prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='fn_phase_d_step_context'`);
let body = prosrc;
const rep = (o, n) => { const c = body.split(o).length - 1; if (c !== 1) throw new Error(`anchor ${c}: ${o.slice(0, 70)}`); body = body.replace(o, n); };

// ---- 1. the run's own party, kept even when the step is about something else -------------------
rep(`  v_boid := nullif(btrim(coalesce(r.business_object_id,'')),'');`,
`  v_boid := nullif(btrim(coalesce(r.business_object_id,'')),'');
  -- THE RUN'S OWN PARTY, KEPT SEPARATELY. v_boid below is consumed by the STEP's object: where the
  -- step writes something other than what the run is about, the prefix does not match, the lookup
  -- fails and v_found is false. That is correct for the step's own subject and wrong for anything
  -- that belongs to the run as a whole. Measured 23 Aug 2026 on W09-S03: the run's
  -- business_object_id is 'supplier_account:37085' and the step's business object is
  -- supplier_capability on public.supplier_capabilities with row_found false, so the terms branch
  -- below had no anchor and fell through to the catalogue.
  v_run_key := case when v_boid like '%:%' then substr(v_boid, position(':' in v_boid) + 1) else null end;`);

// ---- 2. declare it ----------------------------------------------------------------------------
rep('  v_boid   text;', '  v_boid   text;\n  v_run_key text;');

// ---- 3. the terms branch: try the step's subject, then the run's party ------------------------
rep(`      if v_found and v_row_id is not null then
        select o.payload ->> v_k into v_val_txt
          from public.phase_d_object_record o
         where o.superseded_by is null
           and o.payload ? 'terms_version' and o.payload ? 'terms_hash'
           and o.owner_ref = v_row_id
         order by o.record_id desc limit 1;`,
`      -- J05. AND THE ACCEPTANCE BELONGS TO THE RUN'S PARTY, NOT TO THE STEP'S SUBJECT. The block
      -- above anchored on v_row_id, which is the row the STEP is about. Measured on W09-S03, S05
      -- and S06: the run is about supplier_account 37085 and the step is about a
      -- supplier_capability that does not exist yet, so v_found was false, this branch never ran,
      -- and BR-025 was answered from catalogue fixtures PDF-3104/PDF-3105 --
      -- "acceptance names version phase-d-fixture-terms-v1 at digest 5d31c13d1f0f, which matches 0
      -- row(s) in public.legal_documents". The acceptance the scenario actually wrote names
      -- supplier-agreement v5, owned by 37085, and it was one join away the whole time.
      --
      -- A terms acceptance is a fact about the PARTY the run concerns; no step in a workflow makes
      -- it a fact about that step's own subject. So the step's subject is tried first, and the
      -- run's own party second. A run whose party owns no acceptance still resolves nothing and
      -- BR-025 still matches 0 rows and still refuses: the rule keeps its ability to fail.
      if coalesce(v_row_id, v_run_key) is not null then
        select o.payload ->> v_k into v_val_txt
          from public.phase_d_object_record o
         where o.superseded_by is null
           and o.payload ? 'terms_version' and o.payload ? 'terms_hash'
           and o.owner_ref in (v_row_id, v_run_key)
         order by (o.owner_ref = v_row_id) desc, o.record_id desc limit 1;`);

const header = `-- J05 — the terms acceptance was looked for under the step's subject, and it belongs to the run's
-- party
--
-- MEASURED 23 Aug 2026 on htdblwldjkcgjvmqkbeh. The 257-step coverage matrix left seven steps with
-- no effect; three of them -- W09-S03, W09-S05, W09-S06 -- were refused by BR-025 with
--
--   acceptance names version phase-d-fixture-terms-v1 at digest 5d31c13d1f0f, which matches
--   0 row(s) in public.legal_documents whose displayed body hashes to exactly that digest
--
-- and that is the committed catalogue answering, fixtures PDF-3104 and PDF-3105. The scenario had
-- already written the real acceptance: object supplier_terms_acceptance, owner_ref 37085, version
-- v5 -- the published public.legal_documents supplier-agreement. Probed rather than reasoned about,
-- the step context for W09-S03 came back
--
--   business_object = {"relation": "public.supplier_capabilities", "object_id":
--                      "supplier_capability", "row_found": false, ...}
--
-- while the run's business_object_id is 'supplier_account:37085'. G02 fixed this key once, by
-- anchoring the acceptance lookup on "this run's own business object". What it actually anchored on
-- is the row the STEP is about, and W09-S03 is about a supplier_capability that does not exist yet.
--
-- A terms acceptance is a fact about the party the run concerns. The step's subject is tried first
-- and the run's own party second, and where neither owns an acceptance nothing is resolved and
-- BR-025 still refuses -- the rule keeps its ability to fail, which is the only thing that makes
-- its passing worth anything.
--
-- ROLLBACK: re-apply the previous body of fn_phase_d_step_context. No DDL, no grants.
--
-- GENERATED from the live body by scripts/tmp_diag/gen_j05.mjs.
CREATE OR REPLACE FUNCTION public.fn_phase_d_step_context(p_step_run_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$`;

writeFileSync('scripts/sql/phase_d_j05_the_acceptance_belongs_to_the_runs_party_not_the_steps_subject.sql',
  header + body + '$function$;\n');
console.log('written');
