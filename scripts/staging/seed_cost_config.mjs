// seed_cost_config.mjs — make the AI cost meter actually meter.
//
// Applied DIRECTLY, never as a migration: verify_phase1.mjs asserts the migration ledger matches
// production at 712 @ 20260804182051, and adding a migration file breaks that parity.
//
// What this fixes, all of it measured by verify_cost.mjs before and after:
//
//   1. model_rate is EMPTY in staging (0 rows). fn_llm_log prices from model_rate, so every one of
//      the 645 ai_cost_log rows recorded cost_aed = 0.00 - and because fn_llm_log only updates the
//      budget `if p_dept is not null and v_cost > 0`, department_budget never moved either. The
//      whole cost and budget subsystem was silently inert, reporting zero rather than failing.
//      Rates are DERIVED from model_registry so the two tables cannot drift apart again: that
//      divergence is the root defect (production's model_rate has no google/* rows at all, which
//      is why 216 of its Gemini calls bill at zero).
//
//   2. department_budget is EMPTY in staging (production has 13 rows). Nothing to spend against,
//      so the halt and degrade paths in fn_ai_route were unreachable.
//
//   3. fn_task_class has no row for `drawing_redact_verify`, so fn_ai_route falls through to
//      'UNMAPPED function' -> general_drafting (medium tier, 900 max_tokens). The function that
//      VERIFIES a drawing redaction - the check the journey asserts privacy on - was running on a
//      task class it was never sized for. PRODUCTION IS MISSING THIS ROW TOO.
//
//   4. v_llm_model_mix and v_llm_calls_without_task_class read `llm_calls`, a dead legacy table
//      with one writer left in the repo. They return nothing and read as "no problem found".
//      v_llm_offpolicy reads v_llm_model_mix and is blind transitively.
//
//     node scripts/staging/seed_cost_config.mjs
//     node scripts/staging/seed_cost_config.mjs --reset-telemetry
import { resolveStagingRef, mgmtRead, mgmtWrite } from '../lib/qd_guard.mjs';

// 15 AUG 2026: this tool's whole job is standing a SECOND project up from this one, and there is
// no second project — pglpqrhvozwepymcuunn was deleted. It is kept rather than retired because it
// works unchanged the day a new staging project exists; it now REFUSES instead of defaulting to a
// ref that 404s, because a sync reporting success against nothing is the worst outcome available.
const REF = resolveStagingRef(process.env.QD_STAGING_REF);
const RESET = process.argv.includes('--reset-telemetry');

// The rate production already prices at. Kept as one constant so a revaluation is one edit.
const AED_PER_USD = Number(process.env.QD_AED_PER_USD || 3.6725);

const say = (label, detail) => console.log(`  ${label.padEnd(34)} ${detail}`);

// ---- 1. model_rate, derived from model_registry ------------------------------------------------
const rates = await mgmtWrite(REF, `
  insert into public.model_rate
    (model, tier, in_aed_per_mtok, out_aed_per_mtok,
     usd_per_m_prompt, usd_per_m_output, id_verified, source_url, verified_at, note)
  select r.model_id, r.tier,
         round(r.in_per_mtok_usd  * ${AED_PER_USD}, 4),
         round(r.out_per_mtok_usd * ${AED_PER_USD}, 4),
         r.in_per_mtok_usd, r.out_per_mtok_usd,
         false, 'derived from public.model_registry', current_date,
         'Derived from model_registry at ${AED_PER_USD} AED/USD by seed_cost_config.mjs. ' ||
         'model_rate and model_registry disagreeing is the Phase 6 defect; deriving one from the ' ||
         'other is what stops them drifting again.'
    from public.model_registry r
   where coalesce(r.active,true) and r.in_per_mtok_usd is not null and r.out_per_mtok_usd is not null
     on conflict (model) do update
        set tier             = excluded.tier,
            in_aed_per_mtok  = excluded.in_aed_per_mtok,
            out_aed_per_mtok = excluded.out_aed_per_mtok,
            usd_per_m_prompt = excluded.usd_per_m_prompt,
            usd_per_m_output = excluded.usd_per_m_output,
            source_url       = excluded.source_url,
            verified_at      = excluded.verified_at,
            note             = excluded.note
  returning model, in_aed_per_mtok, out_aed_per_mtok`, 'seed model_rate');
say('model_rate', `${rates.length} model(s) priced at ${AED_PER_USD} AED/USD`);
for (const r of rates) say('', `  ${r.model.padEnd(30)} in ${r.in_aed_per_mtok} / out ${r.out_aed_per_mtok} AED/Mtok`);

// ---- 2. department_budget ----------------------------------------------------------------------
// The dept_keys and ceilings are production's; spent_aed starts at 0 because staging spend is
// staging's own. This is configuration, not a copy of business records.
const DEPTS = [
  ['customer_success', 800], ['evolution', 320], ['exec', 800], ['finance', 400], ['hr', 200],
  ['intelligence', 480], ['it', 640], ['knowledge', 640], ['knowledge_eng', 640], ['legal', 400],
  ['marketing', 400], ['procurement', 1600], ['sales', 320],
];
const budgets = await mgmtWrite(REF, `
  insert into public.department_budget
    (dept_key, monthly_aed, spent_aed, period_label, degrade_at_pct, halt_at_pct, updated_at)
  values ${DEPTS.map(([k, v]) => `('${k}', ${v}, 0, to_char(now(),'YYYY-MM'), 70, 95, now())`).join(', ')}
     on conflict (dept_key) do update
        set monthly_aed = excluded.monthly_aed,
            degrade_at_pct = excluded.degrade_at_pct,
            halt_at_pct = excluded.halt_at_pct,
            period_label = excluded.period_label
  returning dept_key`, 'seed department_budget');
say('department_budget', `${budgets.length} department(s), degrade 70% / halt 95%`);

// ---- 3. the missing task class -----------------------------------------------------------------
// drawing_redact_verify reads page images to confirm a redaction actually landed. Its siblings
// drawing_redact and drawing_boq are both document_extraction (medium, 8000 max_tokens); routing it
// to general_drafting gave it 900. §5 of the brief records four separate defects caused by a token
// ceiling sitting inside the output's natural range, so a 900-token ceiling on a vision check is
// the same shape of bug waiting to happen.
// MEASURED, NOT ASSUMED. The obvious mapping is document_extraction, to match its siblings
// drawing_redact and drawing_boq. That mapping was applied, and the journey immediately dropped to
// 35/37: drawing_redaction_runs came back status=failed, pages_out=0, verify_failed=1, with
// verify_detail [{"page":0,"found":["verify_unparseable"]}].
//
// The model call itself SUCCEEDED - ok=true, 396 output tokens. document_extraction resolves to
// google/gemini-3.5-flash, and drawing_redact_verify cannot parse what that model returns, so it
// fails closed and publishes no redacted page. That is the correct refusal and the wrong routing.
//
// So it is mapped to general_drafting: the same medium tier and the same
// ~anthropic/claude-haiku-latest the UNMAPPED fallback was already giving it, and the same
// 900-token ceiling its measured 295-396 token output fits inside - but now a decision on the
// record rather than a fallback nobody chose. The parser's inability to read gemini output is a
// real defect and is filed in the brief; until it is fixed, this function must not be routed to a
// google model.
// CORRECTED 5 Aug 2026 (session 10). The note below used to say document_extraction was refused
// because "this function cannot parse google/gemini-3.5-flash output". That was a misdiagnosis, and
// the experiment that settled it changed one variable: the same image, prompt and model at the
// caller's own `max: 400` returned output_tokens 396, finish_reason 'length', truncated TRUE and 36
// characters cut off mid-JSON; with the ceiling removed it returned 724 tokens, finish_reason
// 'stop', 423 characters that parse, correctly naming the consultant, client, project and plot
// number. The verifier reads gemini fine. `max: 400` was the defect — the fifth instance of §5's
// token-ceiling pattern. Removed from drawing_redact/index.ts, which now also reports a truncation
// as `verify_truncated` instead of laundering it into `verify_unparseable`.
//
// So it now goes where its siblings drawing_redact and drawing_boq already are.
const tc = await mgmtWrite(REF, `
  insert into public.fn_task_class (fn, task_class, note, active, updated_at)
  values ('drawing_redact_verify', 'document_extraction',
          'Vision check that a redaction landed. Mapped alongside its siblings drawing_redact and '
          || 'drawing_boq. Session 9 pinned it to general_drafting believing it could not parse '
          || 'gemini output; measured 5 Aug 2026, that was the caller-side max:400 truncating it '
          || '(396 tokens, finish_reason=length). With the ceiling removed it parses at 724 tokens. '
          || 'MISSING IN PRODUCTION - and production still ships the max:400, so deploy '
          || 'drawing_redact BEFORE applying this row there.',
          true, now())
     on conflict (fn) do update set task_class = excluded.task_class, active = true,
                                    note = excluded.note, updated_at = now()
  returning fn, task_class`, 'seed fn_task_class');
say('fn_task_class', `${tc[0].fn} -> ${tc[0].task_class}`);

// ---- 3b. the four functions that were DEAD AT THE MODEL LAYER ----------------------------------
// capability_agent, category_reqs, inquiry_intake and supplier_review all resolved to task classes
// with tier='none' and max_tokens=0, so fn_ai_route returned use_llm:false BEFORE budget, cache or
// any model, and ai_gateway answered HTTP 200 with no `content`.
//
// This was NOT a founder decision, which is how the brief had it. It was a mis-labelling: the
// 20260728204939 migration filed these four by GUESSING what they do, and every guess is wrong
// against the source. Then 20260804182051 switched missing_fields_detection and supplier_matching
// off - correct for the tasks those class NAMES describe, fatal for four functions wrongly filed
// under them. The fix is to file each under the class matching what it actually asks the model for.
//
// WHY EACH, from the source rather than the old note:
//   capability_agent  reads up to 5 supplier documents as vision parts and returns a 13-key JSON
//                     -> document_extraction, with license_extract / doc_extract / quote_extract.
//   category_reqs     AUTHORS UAE supplier requirements + a compliance checklist into
//                     category_specs -> knowledge_research, with gen_category_knowledge / kb_deepen.
//   inquiry_intake    runs the entire customer conversation and writes the supplier brief
//                     -> agent_reasoning. Already applied to staging and MEASURED: 65 calls on
//                     sonnet-5, 194-1178 output tokens (max 69% of the 1700 ceiling), 0 truncations.
//   supplier_review   grades a registration against fixed format rules, small fixed JSON
//                     -> json_extraction, with canon_eval / knowledge_exam.
//
// THE WORST OF THE FOUR IS supplier_review, and it is a live production defect: with no `content`
// its parser reads '{}' and returns {ok:true, severity:'clean', issues:[], summary:''} WITHOUT the
// fallback:true flag its other failure branches set. supplier_api writes that into
// leads.ai_review_notes and emails the founder "AI check: clean". Every supplier registration ever
// made has been certified clean by a model that never ran.
//
// Recorded HERE, not only as a hand-applied row, because rebuild_staging.mjs drops schema public and
// sync_staging_reference.mjs then re-copies fn_task_class FROM PRODUCTION, which still holds the
// dead mapping. The current staging inquiry_intake remap survives a sync only because copyTable
// skips when the staging row count already matches production's (67 = 67); it would NOT survive a
// rebuild.
const dead = await mgmtWrite(REF, `
  insert into public.fn_task_class (fn, task_class, note, active, updated_at) values
   ('capability_agent','document_extraction',
    'Reads a supplier''s own trade licence, company profile and catalogues (PDF/image) as vision parts and returns the capability JSON. Filed with its siblings license_extract, doc_extract, quote_extract, drawing_boq. Was supplier_matching (tier=none) on a note describing tie-ranking it never did.', true, now()),
   ('category_reqs','knowledge_research',
    'Authors UAE supplier requirements and a compliance checklist per category into category_specs. Same job as gen_category_knowledge / gen_category_personas / kb_deepen. Was missing_fields_detection (tier=none) on a note describing a required-field comparison it never did.', true, now()),
   ('inquiry_intake','agent_reasoning',
    'Runs the whole customer conversation in a category specialist persona and writes the supplier brief. Was missing_fields_detection (tier=none): the model was off, the crude keyword fallback answered, and readiness froze at 40. Measured on staging: 65 calls, 194-1178 output tokens against a 1700 ceiling, zero truncations.', true, now()),
   ('supplier_review','json_extraction',
    'Grades a submitted registration against explicit format rules and returns a small fixed JSON. Same shape as canon_eval and knowledge_exam. Was supplier_matching (tier=none), and the refusal was LAUNDERED into severity=clean with no fallback flag - so every registration was certified clean by a model that never ran.', true, now())
  on conflict (fn) do update set task_class = excluded.task_class, active = true,
                                 note = excluded.note, updated_at = now()
  returning fn, task_class`, 'seed fn_task_class (four switched-off functions)');
for (const r of dead) say('', `  ${r.fn.padEnd(20)} -> ${r.task_class}`);

// ---- 4. repoint the monitoring views off the dead table -----------------------------------------
// ai_cost_log has no `fell_back` column, so "fallback" is derived from what the policy would have
// chosen: a call whose model is not the active policy's model_primary for its task class. That is a
// truer definition than the old boolean anyway - it catches a model substituted by fn_ai_route's
// capability override or budget degrade, which never set fell_back.
// `create or replace view` cannot rename or reorder columns, and these views change shape
// (cached_tokens has no equivalent in ai_cost_log; cost_aed is new), so they are dropped and
// rebuilt. v_llm_offpolicy is dropped first because it selects from v_llm_model_mix. Dropping a
// view also drops its grants, so they are reapplied below - sync_staging_grants.mjs exists because
// exactly this was missed once before.
await mgmtWrite(REF, `drop view if exists public.v_llm_offpolicy`, 'drop v_llm_offpolicy');
await mgmtWrite(REF, `drop view if exists public.v_llm_model_mix`, 'drop v_llm_model_mix');
await mgmtWrite(REF, `drop view if exists public.v_llm_calls_without_task_class`, 'drop v_llm_calls_without_task_class');

await mgmtWrite(REF, `
  create view public.v_llm_model_mix as
  select c.fn,
         c.model_used as model,
         count(*)                                              as calls,
         count(*) filter (where p.model_primary is not null
                            and c.model_used <> p.model_primary) as fallbacks,
         count(*) filter (where not coalesce(c.ok,true))        as failures,
         round(avg(c.latency_ms))                               as avg_ms,
         sum(coalesce(c.prompt_tokens,0))                       as prompt_tokens,
         sum(coalesce(c.output_tokens,0))                       as output_tokens,
         -- Replaces the old cached_tokens, which has no equivalent in ai_cost_log: a cache hit is
         -- logged with 0 tokens. Same column COUNT as production's view, which is what
         -- verify_phase1's 5,237-column parity check measures - adding a column here turned that
         -- gate red, and a parity gate that is red for a good reason still hides the next bad one.
         round(sum(coalesce(c.cost_aed,0)), 4)                  as cost_aed,
         bool_or(coalesce(c.cached,false))                      as uses_caching,
         max(c.occurred_at)                                     as last_seen
    from public.ai_cost_log c
    left join public.model_policy p
           on p.task_class = c.task_class and coalesce(p.active,true)
   where c.occurred_at > now() - interval '30 days'
   group by c.fn, c.model_used`, 'repoint v_llm_model_mix');
say('v_llm_model_mix', 'now reads ai_cost_log (cached_tokens -> cost_aed, same column count)');

await mgmtWrite(REF, `
  create view public.v_llm_calls_without_task_class as
  select date_trunc('day', occurred_at)                            as day,
         count(*)                                                  as calls,
         -- renamed from no_purpose: ai_cost_log's column is task_class. Column count unchanged.
         count(*) filter (where task_class is null
                            or btrim(task_class) = '')              as no_task_class,
         count(distinct model_used)                                as distinct_models
    from public.ai_cost_log
   group by date_trunc('day', occurred_at)
   order by 1 desc`, 'repoint v_llm_calls_without_task_class');
say('v_llm_calls_without_task_class', 'now reads ai_cost_log (no_purpose -> no_task_class)');

// llm_policy has 3 rows in production and 0 in staging, and is not what fn_ai_route consults.
// Repointing v_llm_offpolicy at v_llm_model_mix alone would have turned a silent all-clear into a
// loud false alarm (every model "off-policy" against an empty table), so it now asks the question
// that matters: was a model used that no active policy can actually select?
await mgmtWrite(REF, `
  create view public.v_llm_offpolicy as
  select m.fn, m.model, m.calls, m.last_seen
    from public.v_llm_model_mix m
   where m.model is not null and m.model <> 'none'
     and not exists (
       select 1 from public.model_policy p
        where coalesce(p.active,true)
          and (p.model_primary = m.model or p.model_fallback = m.model))`,
  'repoint v_llm_offpolicy');
say('v_llm_offpolicy', 'now asks: used a model no active policy can select');

// Restore the privileges the DROPs removed, in production's shape (postgres + service_role hold
// the full set on all three).
for (const v of ['v_llm_model_mix', 'v_llm_calls_without_task_class', 'v_llm_offpolicy']) {
  await mgmtWrite(REF,
    `grant select, insert, update, delete, truncate, references, trigger
       on public.${v} to postgres, service_role`, `regrant ${v}`);
}
const grants = await mgmtRead(REF, `
  select count(*)::int n from information_schema.role_table_grants
   where table_schema='public'
     and table_name in ('v_llm_model_mix','v_llm_calls_without_task_class','v_llm_offpolicy')`);
say('grants', `${grants[0].n} privilege row(s) restored (expected 42: 3 views x 2 roles x 7)`);

// ---- 5. optional: clear telemetry produced while the meter was broken ---------------------------
if (RESET) {
  const n = await mgmtWrite(REF, `
    with d as (delete from public.ai_cost_log
                where coalesce(cost_aed,0) = 0
                  and not coalesce(cached,false)
                  and coalesce(model_used,'none') <> 'none'
               returning 1)
    select count(*)::int n from d`, 'reset stale telemetry');
  say('ai_cost_log', `${n[0].n} row(s) removed - all recorded 0.00 because model_rate was empty, ` +
    'so they measure a broken meter rather than a real cost');
}

const after = (await mgmtRead(REF, `
  select (select count(*) from public.model_rate)::int rates,
         (select count(*) from public.department_budget)::int depts,
         (select count(*) from public.ai_cost_log)::int logs,
         (select count(*) from pg_views where schemaname='public'
           and definition ~* '\\mllm_calls\\M')::int views_on_dead_table`))[0];
console.log(`\nmodel_rate ${after.rates} · department_budget ${after.depts} · ` +
            `ai_cost_log ${after.logs} · views still on llm_calls ${after.views_on_dead_table}`);
