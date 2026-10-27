// verify_prod_readiness.mjs — the §8 production deployment sequence, as a measurement.
//
// READ-ONLY AGAINST PRODUCTION, BY CONSTRUCTION. Every database read goes through
// qd_guard's mgmtRead(), which refuses anything matching a write verb; every Edge Function
// read is a GET. This script cannot deploy and cannot apply. It answers one question —
// "which of §8 is still outstanding in production right now?" — and prints the exact
// statement for each item that is. Re-run it after applying to prove each item landed.
//
// WHY THIS EXISTS. §8 was a hand-maintained list in a markdown brief, and two of its
// claims were already wrong when measured on 5 Aug 2026:
//
//   - "fn_task_class mapping for quote_compare (absent in production)" — it is PRESENT,
//     mapped to quote_comparison. Deploying against that line would have been a no-op
//     dressed up as a fix.
//   - "model_policy.quote_comparison.max_tokens 3000 -> 10000" — production is at
//     **1500**, not 3000. That is the original haiku/1500 ceiling §5 records as the first
//     of four intermittent truncations. The gap is twice what the brief claimed.
//
// §2.3's lesson generalises: any hand-maintained list rots. So the code half is DERIVED —
// every function whose newest commit is later than its deployed bundle is outstanding —
// rather than transcribed from the brief. The three highest-priority fixes additionally
// carry a signature pinned against the deployed bundle itself, because "the directory
// changed" and "the defect is gone" are different claims and only the second one matters.
//
//   node scripts/verify_prod_readiness.mjs
import { supabaseAccessToken } from './lib/supabase_token.mjs';
import { execSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { mgmtRead, PROD_REF } from './lib/qd_guard.mjs';

const token = supabaseAccessToken();
const H = { Authorization: 'Bearer ' + token };

const out = [];
const item = (area, name, ok, detail, fix) => {
  out.push({ area, name, ok, detail, fix });
  console.log(`${ok ? 'APPLIED   ' : 'OUTSTANDING'} ${area.padEnd(7)} ${name.padEnd(46)} ${detail}`);
};

// ---- CODE: what is deployed vs what is committed ------------------------------------------------
// The deployed bundle is the transpiled artifact, not the source, so it is not byte-comparable
// with the repo. Two independent signals instead: a timestamp comparison that covers every
// function without a maintained list, and a literal-string assertion for the three defects whose
// exact shipped form was measured on 5 Aug 2026.
console.log(`\n=== CODE (production ${PROD_REF}) ===`);

// THE DEPLOY LIST IS THE BRANCH DIFF, NOT A COMMIT-TIMESTAMP COMPARISON.
// The first cut of this script compared each function's newest commit against its deployed
// updated_at and reported 118 functions "behind the repo" — including _shared, home and faq.
// That number is an artefact: this repo was built by PULLING FROM production, so mass-import
// and internal-auth-migration commits touched every directory at once and mark all of them as
// newer than anything deployed. A 118-function production deploy list derived that way is a
// confident wrong answer of exactly the shape §5 warns about.
//
// What actually needs deploying is what THIS BRANCH changed relative to main. That is derived,
// not transcribed, so it cannot rot the way §8's hand-maintained list did — and it already
// caught four functions §8 never named: dispatch_inquiry, match_eval, route_inquiry,
// stripe_setup_page.
const changed = execSync('git diff --name-only main...HEAD -- supabase/functions/')
  .toString().split('\n')
  .map(l => (l.match(/^supabase\/functions\/([^/]+)\//) || [])[1])
  .filter(Boolean);
const slugs = [...new Set(changed)].filter(s => s !== '_shared').sort();

// A WHOLE-FILE SUBSTRING CHECK WAS TRIED HERE AND IT NEVER WORKED. It asked whether the repo's
// index.ts appears verbatim inside the deployed bundle, on the evidence that some source lines do.
// They do — but only the ones that survive transpilation. The bundle is transpiled JavaScript, not
// TypeScript: measured 5 Aug 2026, the longest matching prefix of doc_extract was 432 chars of
// 17,317 and of customer_api 211 of 81,594, both diverging at the import statements, and a mid-file
// 300-char slice was absent from both. String literals and comments survive; type annotations,
// non-null assertions and rewritten imports do not.
//
// So that check reported "differs" for all 16 functions BOTH BEFORE AND AFTER a clean 16/16
// deploy. It happened to give the right answer before the deploy, by coincidence, which is the
// most dangerous kind of wrong. A gate that can only ever fail is worse than no gate.
//
// What is left is honest: git tells us WHAT needs deploying, the deployed version number shows
// movement, and the per-defect signatures below are the real assertion that a fix landed.
const deployedVer = new Map();
for (const slug of slugs) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROD_REF}/functions/${slug}`, { headers: H });
  deployedVer.set(slug, r.ok ? `v${(await r.json()).version}` : 'NOT DEPLOYED');
}
const missing = slugs.filter(s => deployedVer.get(s) === 'NOT DEPLOYED');
item('code', 'every function this branch changed exists in production', missing.length === 0,
  missing.length ? `${missing.length} never deployed: ${missing.join(' ')}`
                 : `${slugs.length} function(s), deployed versions: ` +
                   slugs.map(s => `${s} ${deployedVer.get(s)}`).join(', '),
  `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\\deploy_functions.ps1 \`\n` +
  `           -ProjectRef ${PROD_REF} -IMeanProduction ${slugs.join(' ')}\n` +
  `-- Version numbers only prove SOMETHING was deployed. The signature checks below are what\n` +
  `-- prove the FIX landed; treat those as the gate.`);

// The three §8 priority fixes, asserted against the shipped bundle rather than the directory.
// Each `bad` string was read out of production's own /functions/<slug>/body on 5 Aug 2026.
const SIGNATURES = [
  ['customer_api',    /transactions'\)\.select\('id,quote_id,revealed_at,created_at'\)/,
   'my_inquiries selects transactions.created_at, a column that exists in neither project. PostgREST 400s, `|| []` swallows it, and NO QUOTE IS EVER MARKED REVEALED — the customer pays and the portal never changes.'],
  ['doc_extract',     /max\s*:\s*2000/,
   'caller-side max:2000 under an 8000 task class. Measured natural output 1,996 / 2,170 / 2,051 tokens across three runs — the document queue fails on roughly one page in three with extraction_null.'],
  ['license_extract', /max\s*:\s*1500/,
   'caller-side max:1500 under an 8000 task class. A realistic 15-activity licence uses 1,116–1,171 tokens (74–78%), and a truncated licence returns HTTP 200 with every field blank — byte-identical to an unreadable scan.'],
];
// COMMENTS ARE STRIPPED BEFORE MATCHING, and forgetting that produced a false alarm on the very
// first run after deploying. doc_extract's fix is explained by a comment that quotes the defect it
// removed ("...can only ever LOWER the policy ceiling, never raise it. `max:2000`"), and the
// signature matched that comment: 2 hits in the raw bundle, 0 with comment lines removed. A
// detector that trips on its own explanation would have sent the next session to re-fix something
// already fixed.
const codeOnly = (s) => s.split('\n').filter((l) => !/^\s*\/\//.test(l)).join('\n');
for (const [slug, bad, why] of SIGNATURES) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROD_REF}/functions/${slug}/body`, { headers: H });
  const txt = r.ok ? codeOnly(await r.text()) : '';
  const hit = bad.test(txt);
  item('code', `${slug}: the defect is gone from the deployed bundle`, !hit,
    hit ? `STILL LIVE — ${why}` : `signature ${bad} absent from ${txt.length} chars of deployed bundle`,
    hit ? `deploy ${slug} (covered by the command above)` : null);
}

// ---- CONFIG: applied DIRECTLY, never as a migration ---------------------------------------------
// verify_phase1.mjs asserts the migration ledger matches production at 712 @ 20260804182051.
// A migration file for any of these breaks that parity, which is why every statement below is a
// direct one. They are all idempotent.
console.log(`\n=== CONFIG (direct statements — a migration breaks the 712-vs-712 ledger parity) ===`);

const one = async (sql) => (await mgmtRead(PROD_REF, sql))[0];

// 1. model_rate vs model_registry — the Phase 6 root defect.
const rate = await one(`
  select coalesce(string_agg(r.model_id, ' ' order by r.model_id), '') as missing
    from public.model_registry r
    left join public.model_rate m on m.model = r.model_id
   where coalesce(r.active,true) and r.in_per_mtok_usd is not null
     and r.out_per_mtok_usd is not null and m.model is null`);
const zero = await one(`
  select count(*) filter (where coalesce(cost_aed,0)=0 and not coalesce(cached,false)
                            and coalesce(model_used,'none')<>'none')::text as n,
         count(*)::text as total from public.ai_cost_log`);
item('config', 'every active registry model has an AED rate', !rate.missing,
  rate.missing ? `unpriced: ${rate.missing} — ${zero.n} of ${zero.total} ai_cost_log rows bill at zero, and fn_llm_log only moves department_budget when cost > 0, so the budget halt cannot fire for that traffic at all`
               : `every active model priced; ${zero.n} of ${zero.total} rows at zero cost`,
  rate.missing ? `-- derive rates from the registry rather than hand-writing them: the two tables\n` +
    `-- disagreeing IS the defect, and a hand-written model_rate is how production lost every\n` +
    `-- google/* row in the first place.\n` +
    `insert into public.model_rate (model, tier, in_aed_per_mtok, out_aed_per_mtok,\n` +
    `       usd_per_m_prompt, usd_per_m_output, id_verified, source_url, verified_at, note)\n` +
    `select r.model_id, r.tier, round(r.in_per_mtok_usd * 3.6725, 4), round(r.out_per_mtok_usd * 3.6725, 4),\n` +
    `       r.in_per_mtok_usd, r.out_per_mtok_usd, false, 'derived from public.model_registry',\n` +
    `       current_date, 'Derived from model_registry at 3.6725 AED/USD.'\n` +
    `  from public.model_registry r\n` +
    ` where coalesce(r.active,true) and r.in_per_mtok_usd is not null and r.out_per_mtok_usd is not null\n` +
    `   on conflict (model) do update set in_aed_per_mtok = excluded.in_aed_per_mtok,\n` +
    `        out_aed_per_mtok = excluded.out_aed_per_mtok, tier = excluded.tier;` : null);

// 2. the missing task class.
const drv = await one(`select coalesce((select task_class from public.fn_task_class
                                         where fn='drawing_redact_verify'),'ABSENT') as tc`);
// THIS ASSERTED EXISTENCE AND PASSED ON THE ONE VALUE ITS OWN REMEDIATION FORBIDS (9 Aug 2026).
// The gate read `drv.tc !== 'ABSENT'`, so ANY mapping satisfied it. Measured on production today:
// the row exists and says **document_extraction**, which model_policy resolves to
// google/gemini-3.5-flash — and the fix text printed a dozen lines below says, from a measurement
// on staging that took the journey 37/37 -> 35/37, that this function cannot parse that model's
// output, fails closed, and publishes NO redacted page. So the gate reported APPLIED over exactly
// the configuration it exists to prevent, and would have gone on doing so forever.
//
// A check that passes by accident is worse than one that fails. It now asserts the VALUE.
// Currently latent rather than firing: 2 drawings on file and 0 inquiries carrying a
// drawing_redacted_paths, so no redaction has been attempted on real work yet. Redaction is the
// supplier-anonymity mechanism this marketplace is built on, so it should be right before traffic
// arrives, not after.
const drvBad = drv.tc === 'document_extraction';
item('config', 'drawing_redact_verify routes to a model it can parse', drv.tc !== 'ABSENT' && !drvBad,
  drv.tc === 'ABSENT' ? `ABSENT — fn_ai_route reports UNMAPPED and falls through to general_drafting. It happens to work there, but nobody chose it`
    : drvBad ? `document_extraction — resolves to google/gemini-3.5-flash, whose output this function cannot parse. It fails closed and publishes NO redacted page`
                      : `${drv.tc}`,
  (drv.tc === 'ABSENT' || drvBad) ? `-- general_drafting, NOT document_extraction. Mapping it to document_extraction to match\n` +
    `-- its siblings drawing_redact/drawing_boq was applied in staging and took the journey from\n` +
    `-- 37/37 to 35/37: that class resolves to google/gemini-3.5-flash, whose output this function\n` +
    `-- cannot parse. It then fails closed and publishes NO redacted page. Until the parser is\n` +
    `-- fixed this function must not be routed to a google model.\n` +
    `insert into public.fn_task_class (fn, task_class, note, active, updated_at)\n` +
    `values ('drawing_redact_verify','general_drafting',\n` +
    `        'Vision check that a redaction landed. Was UNMAPPED. NOT document_extraction: that is '\n` +
    `        || 'google/gemini-3.5-flash, whose output this function cannot parse (measured 5 Aug 2026).',\n` +
    `        true, now())\n` +
    `   on conflict (fn) do update set task_class = excluded.task_class, active = true;` : null);

// 3. the policy ceilings. Each target is the measured natural maximum with headroom, per §5:
//    "measure the natural output with the ceiling lifted, then set the budget above the maximum".
for (const [tc, target, why] of [
  ['quote_comparison',   10000, 'measured natural range 2,618–7,266 tokens. Production is at the ORIGINAL haiku/1500 — the first of the four truncations in §5, and the brief\'s "3000 -> 10000" understates the gap by half'],
  ['document_extraction', 8000, 'drawing_boq asks for 8000; measured doc_extract output 1,996–2,170'],
  ['rfq_routing',         2500, 'truncated at 300 in §5'],
]) {
  const p = await one(`select coalesce(max_tokens::text,'null') as m, coalesce(tier,'?') as t,
                              coalesce(model_primary,'none') as mp
                         from public.model_policy where task_class='${tc}'`);
  const ok = p && Number(p.m) >= target;
  item('config', `model_policy.${tc}.max_tokens >= ${target}`, ok,
    `${p ? `${p.t} / ${p.mp} / max ${p.m}` : 'ABSENT'}${ok ? '' : ` — ${why}`}`,
    ok ? null : `update public.model_policy set max_tokens = ${target} where task_class = '${tc}';`);
}

// 4. task classes that are switched off entirely.
const off = await one(`
  select coalesce(string_agg(distinct t.fn || ' -> ' || p.task_class, ', '), '') as fns
    from public.fn_task_class t
    join public.model_policy p on p.task_class = t.task_class
   where coalesce(t.active,true) and coalesce(p.active,true)
     and (coalesce(p.tier,'none')='none' or coalesce(p.max_tokens,0)=0)`);
item('config', 'no live function maps to a switched-off task class', !off.fns,
  off.fns ? `${off.fns} — tier=none/max_tokens=0. The function is dead at the model layer, not merely unwired` : 'none',
  off.fns ? `-- Decide per function whether it should route to a real class or be retired. Do NOT\n` +
    `-- bulk-enable: supplier_matching being off is why capability_agent's ANALYZE path is dead,\n` +
    `-- but its CONFIRM path makes no model call at all and works today.\n` +
    `-- e.g. update public.fn_task_class set task_class='missing_fields' where fn='inquiry_intake';` : null);

// 5. the CAD bucket.
const mime = await one(`select coalesce(array_to_string(allowed_mime_types,', '),'(null)') as m
                          from storage.buckets where id='drawing-files'`);
const hasCad = /dwg/.test(mime.m) && /dxf/.test(mime.m);
item('config', 'drawing-files accepts CAD uploads', hasCad, mime.m,
  hasCad ? null : `-- Note a SECOND gate sits behind this one: customer_api still passes SAFE_UPLOAD, and\n` +
    `-- create_inquiry records drawing_file_path for the raster upload only — so once the bucket\n` +
    `-- accepts a .dxf, the stored original is still referenced by no row and the supplier asked\n` +
    `-- to quote from it has no path to it. Fixing only this line changes nothing visible.\n` +
    `update storage.buckets\n` +
    `   set allowed_mime_types = allowed_mime_types || array['image/vnd.dwg','image/vnd.dxf']\n` +
    ` where id = 'drawing-files';`);

// 6. monitoring views on the dead table.
const views = await one(`select coalesce(string_agg(viewname,' '),'') as v from pg_views
                          where schemaname='public' and definition ~* '\\mllm_calls\\M'`);
item('config', 'no monitoring view reads the dead llm_calls table', !views.v,
  views.v ? `${views.v} — llm_calls has one writer left (site_assistant) and returns nothing, so these read as "no problem found"` : 'all read ai_cost_log',
  views.v ? `-- DROP + CREATE, not CREATE OR REPLACE: the views change shape. Dropping a view drops\n` +
    `-- its grants, so reapply them (postgres and service_role hold the full set on all three).\n` +
    `-- Keep the COLUMN COUNT identical — verify_phase1 asserts 5,237 columns, and the first cut\n` +
    `-- of this change added three and turned that gate red.\n` +
    `-- The full statements are in scripts/staging/seed_cost_config.mjs, section 4.` : null);

// 7. the credential that makes capability_agent reachable.
const cred = await one(`select count(*)::text as n from public.internal_credential
                         where coalesce(active,true) and 'capability_agent' = any(scope)`);
item('config', 'an internal_credential scopes capability_agent', cred.n !== '0',
  cred.n === '0' ? `none — confirm is the ONLY writer of a confirmed supplier_capabilities row and its ledger entry, and it makes no model call. supplier_capabilities has 0 rows, so capability-gated dispatch cannot ever have run`
                 : `${cred.n} credential(s)`,
  cred.n === '0' ? `update public.internal_credential\n` +
    `   set scope = scope || array['capability_agent']\n` +
    ` where context = 'db.internal' and coalesce(active,true)\n` +
    `   and not ('capability_agent' = any(scope));` : null);

// ---- the sequence -------------------------------------------------------------------------------
const todo = out.filter(x => !x.ok);
console.log(`\n${'='.repeat(96)}`);
console.log(`PROD READINESS ${out.length - todo.length}/${out.length} applied on ${PROD_REF}`);
if (!todo.length) { console.log('\nEverything in §8 is live in production.'); process.exit(0); }

console.log(`\n${todo.length} item(s) outstanding. Apply in this order — code first, because the\n` +
  `configuration raises ceilings that the OLD deployed code would still override downward\n` +
  `(ai_gateway takes min(caller, policy), so a caller-side max is the binding constraint):\n`);
let n = 0;
for (const t of todo.filter(x => x.area === 'code')) if (t.fix) console.log(`--- ${++n}. [${t.area}] ${t.name}\n${t.fix}\n`);
for (const t of todo.filter(x => x.area === 'config')) if (t.fix) console.log(`--- ${++n}. [${t.area}] ${t.name}\n${t.fix}\n`);
console.log(`Re-run this script after applying. It is the gate, not the changelog.`);
process.exit(1);
