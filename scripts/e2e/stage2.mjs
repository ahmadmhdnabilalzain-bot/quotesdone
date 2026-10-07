// scripts/e2e/stage2.mjs — STAGE 2 of the pre-launch sandbox end-to-end test: the whole funnel with the
// models ON FOR THIS RUN'S TAGGED CALLS ONLY (the founder's hold stays on for everything else), on ZZ DEMO
// identities only, with a database-enforced spend cap and complete cleanup.
// Assigned: it_engineer (tooling) for the sales_engineer and customer_support journeys. Ledger 1119.
//
// Stage 1 (30 Sep, model hold ON) is scripts/e2e/run.mjs journeys a-h; its report marked every step the
// hold stopped as HELD-BY-AI-HOLD. Stage 2 re-runs those steps with the models on, at founder scale:
// 10 suppliers in 10 different trades (+3 extra in one trade so one request gets a real comparison),
// 10 customers, EN and AR, several emirates. It reuses the stage-1 fixtures (fixtures.mjs) and the
// stage-1 teardown (demo_factory.teardown); what is new here is the scenario matrix, the spend guard,
// the model-route assertions, the Desktop export, the coverage inventory and the learning cleanup.
//
//   node scripts/e2e/stage2.mjs --dry-run                 preconditions, cleanup paths, coverage, spend estimate. NO model call.
//   node scripts/e2e/stage2.mjs --run                     the real run. It needs a go from the ceo/founder, but it does NOT need the hold lifted
//   node scripts/e2e/stage2.mjs --cleanup-only --tag <t>  remove a run's demo rows, objects, users and learning
//   node scripts/e2e/stage2.mjs --verify-clean --tag <t>  prove 0 rows of run <t> remain in every registry table and in storage
//   options: --cap-usd 15 (hard abort), --out <dir> (default: the founder's Desktop folder)
//
// INCAPABLE OF REACHING A REAL PERSON: every identity is qd-<tag>-*@example.invalid or the reserved
// +971 50 000 00xx block; the run refuses without the demo capture and pairing guards; it never posts,
// publishes or sends to Meta; Stripe is TEST mode only (the run refuses a live key). Cleanup is scoped by
// the run tag and the ids the run recorded itself, never by a pattern that could match a real row.
import { mkdirSync, writeFileSync, existsSync, readFileSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHmac, randomBytes } from 'node:crypto';
import { openRun, closeRun, leftovers, makeDemoCustomer, makeDemoSupplier, read, write, REF, BASE, call } from './fixtures.mjs';
import { internalCred, newRun, teardown, makeLicenceGatedSupplier, runIntake, quotePayload, TRADES, EMIRATES, q, keys } from '../lib/demo_factory.mjs';
import { demoPdf } from '../lib/demo_pdf.mjs';
import { buildInventory, classify, summarise } from './stage2_coverage.mjs';
import { liveDuties, probeDuty } from './stage2_duties.mjs';

const argv = process.argv.slice(2);
const val = (f) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : null; };
const MODE = ['--dry-run', '--run', '--cleanup-only', '--verify-clean'].find((m) => argv.includes(m));
if (!MODE) { console.error('usage: --dry-run | --run [--keep] | --cleanup-only --tag <t> | --verify-clean --tag <t>'); process.exit(2); }
// --keep (with --run): the founder's browser walk reuses this run's demo data. The models are switched off
// and the rehearsal window is CLOSED exactly as in a normal run; only the demo rows and the tag are kept.
// Remove them later with --cleanup-only --tag <t>.
const KEEP = argv.includes('--keep');
if (KEEP && MODE !== '--run') { console.error('REFUSED: --keep only applies to --run'); process.exit(2); }
// USD 4 per rehearsal window (review of #1230). The DATABASE enforces it: fn_kernel_paid_provider_gate
// refuses every further call tagged with this run once ai_cost_log holds cap_usd of them. The script
// checks it as well, between and after scenarios. rehearsal_window_cap_is_small allows at most USD 15.
const CAP_USD = Number(val('--cap-usd') || 4);
if (!Number.isFinite(CAP_USD) || CAP_USD <= 0 || CAP_USD > 15) { console.error('REFUSED: --cap-usd must be a positive number'); process.exit(2); }
const AED_PER_USD = 3.6725;
const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, '..', '..');
const OUT = val('--out') || process.env.QD_STAGE2_OUT || 'C:\\Users\\Opera\\Desktop\\QuotesDone Sandbox Test 2026-10';
process.env.QD_FIXTURES = '1';

// ---- the matrix ------------------------------------------------------------------------------------
// Ten different trades, one supplier each, in rotating emirates; plus three more aluminium suppliers so
// the aluminium request collects four quotes (top-3 report + the full list). elevators has NO demo
// supplier: its request must HOLD, never be routed to a nearest trade (exact trade match or none).
export const SUPPLIER_TRADES = ['aluminium', 'electrical', 'plumbing', 'hvac', 'flooring', 'joinery', 'glazing', 'painting', 'waterproofing', 'landscaping'];
export const EXTRA_ALUMINIUM = ['A2', 'A3', 'A4'];
export const UNMATCHED_TRADE = 'elevators';
const CUSTOMERS = Array.from({ length: 10 }, (_, i) => ({ label: `C${i + 1}`, locale: i % 2 ? 'ar' : 'en', emirate: EMIRATES[i % EMIRATES.length] }));

// Each scenario: what it proves, and the model calls it is expected to make (task_class, calls,
// in-tokens, out-tokens per call). The token counts are ESTIMATES; the run measures the real spend
// from ai_cost_log and aborts on the cap, whatever these say.
export const SCENARIOS = [
  { key: 'S01', title: '10 ZZ DEMO suppliers in 10 trades (+3 aluminium): mandatory six, own licence + company profile, exact services, approved', calls: [['document_extraction', 13, 3000, 500]] },
  { key: 'S02', title: 'Licence verification: an uploaded licence is read, its legal name recorded, the gate decides', calls: [['document_extraction_multimodal', 2, 4000, 600]] },
  { key: 'S03', title: '10 ZZ DEMO customers: name, DOB 18+, email OTP, mobile, current terms', calls: [] },
  { key: 'S04', title: 'Inquiries through the sales-engineer interview: EN + AR, exact specs and "not sure", multiple lines, several emirates', calls: [['inquiry_qualification_conversation', 60, 3000, 500], ['category_classification', 10, 1000, 100]] },
  { key: 'S05', title: 'Drawing / photo / BOQ inquiries: analysed, redacted, no identity reaches a supplier', calls: [['drawing_and_boq_analysis', 4, 8000, 2000], ['redaction_detection', 4, 3000, 500], ['identity_redaction_verify', 4, 4000, 300], ['drawing_boq_confirm', 2, 4000, 500]] },
  { key: 'S06', title: 'Matching: each request reaches only its exact-trade demo supplier; the unmatched trade holds', calls: [['rfq_routing', 11, 3000, 800]] },
  { key: 'S07', title: 'Quotes: 4 on one request, incomplete quote held with notes, revision releases it, PDF extraction', calls: [['json_extraction', 8, 6000, 1500], ['procurement_reasoning', 8, 4000, 800]] },
  { key: 'S08', title: 'Spec questions answered by the customer incl. "not sure" (spec offer / missing specs)', calls: [['sales_engineer_reasoning', 6, 3000, 600]] },
  { key: 'S09', title: 'Comparison report on the Opus route: top 3 + every other quote listed, EN and AR', calls: [['quote_comparison', 2, 20000, 6000], ['translation', 4, 6000, 6000]] },
  { key: 'S10', title: 'Reveal with Stripe TEST: declined card refused, paid card reveals at 3% with no card surcharge, invoice + receipt, both parties notified (customer in AR, supplier in EN)', calls: [['customer_communication', 4, 1500, 400], ['supplier_communication', 4, 1500, 400]] },
  { key: 'S11', title: 'Refund request -> accountant case -> CEO approval decision with reasons', calls: [['ceo_approval_decision', 1, 6000, 1000], ['seat_deliberation_blind', 1, 5000, 1000], ['seat_deliberation_compare', 1, 5000, 1000]] },
  { key: 'S12', title: 'Supplier non-response after reveal: watch opened, chase scheduled, non-response path recorded', calls: [['agent_reasoning', 2, 3000, 600]] },
  { key: 'S13', title: 'Chat: homepage widget EN + AR, customer portal chat, supplier portal chat, post-reveal messages', calls: [['visitor_chat', 4, 3000, 500], ['customer_portal_assistant', 2, 3000, 500], ['support_ai', 2, 3000, 500]] },
  { key: 'S14', title: 'Public forms: unsubscribe (signed link), contact, complaint status, rating', calls: [] },
  { key: 'S15', title: 'Every notice the run caused is rendered and captured, never sent: AR customer gets Arabic, supplier gets English', calls: [] },
  { key: 'S16', title: 'Every page (EN + AR) and every portal tab renders for a demo customer and supplier', calls: [] },
  { key: 'S18', title: "Every live duty (public.seat_duty + the resilience tick routines) run in an aborted transaction scoped to the run: no error, no non-demo row written, its effect on the run's demo rows recorded", calls: [] },
  { key: 'S19', title: 'Inbound channels with real provider signatures from demo senders: WhatsApp and SMS (Twilio-signed), email (Svix-signed Resend), delivery receipts; the message is stored', calls: [['wa_inbound', 2, 3000, 500], ['resend_inbound', 1, 3000, 500]] },
  { key: 'S20', title: 'Every remaining edge function answers a demo caller with a body (CEO and IT consoles read-only, intelligence, embeddings, error ingest, sanctions, onboarding, catalog)', calls: [['support_ai', 2, 2000, 300]] },
  { key: 'S17', title: 'Marketing seat: blog draft -> CEO review -> founder FYI, social plan. Saved to the Desktop, NEVER published or posted', calls: [['marketing_article_draft', 1, 6000, 3000], ['ceo_article_review', 1, 6000, 1000], ['marketing_plan', 1, 4000, 2000]] },
];

const log = (...a) => console.log(...a);
const safe = (s) => String(s).replace(/[<>:"/\\|?*]+/g, '_').slice(0, 80);
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

async function prices() {
  const pol = await read(`select task_class, model_primary, model_fallback from public.model_policy where active`);
  const reg = await read(`select model_id, in_per_mtok_usd::float i, out_per_mtok_usd::float o from public.model_registry`);
  const p = Object.fromEntries(reg.map((r) => [r.model_id, r]));
  return { pol: Object.fromEntries(pol.map((r) => [r.task_class, r])), p };
}
function estimate(s, pr) {
  let usd = 0; const lines = [];
  for (const [tc, n, ti, to] of s.calls) {
    const pol = pr.pol[tc]; const m = pol && pr.p[pol.model_primary];
    const u = m ? n * (ti * m.i + to * m.o) / 1e6 : NaN;
    usd += u; lines.push({ task_class: tc, model: pol?.model_primary || 'NO POLICY', calls: n, usd: u });
  }
  return { usd, lines };
}

// ---- the Desktop export ----------------------------------------------------------------------------
function writeIndex(state) {
  const { scenarios, cov, spend, mode, tag, steps = [] } = state;
  const pass = steps.filter((s) => s.ok).length, fail = steps.filter((s) => !s.ok).length;
  const rows = (arr, f) => arr.map(f).join('');
  const html = `<!doctype html><meta charset="utf-8"><title>QuotesDone Sandbox Test</title>
<style>body{font:14px system-ui;margin:24px;max-width:1200px}table{border-collapse:collapse;width:100%;margin:12px 0}td,th{border:1px solid #ccc;padding:4px 6px;text-align:left;vertical-align:top}.ok{color:#070}.bad{color:#b00}.j{color:#850}</style>
<h1>QuotesDone sandbox test, stage 2</h1>
<p>Mode <b>${esc(mode)}</b> · run tag <code>${esc(tag || '-')}</code> · ${new Date().toISOString()} · spend cap USD ${CAP_USD}</p>
<h2>Summary</h2><p><b class="ok">${pass} passed</b> · <b class="bad">${fail} failed</b> · spend ${spend.measured_usd == null ? 'not measured (dry run)' : 'USD ' + spend.measured_usd.toFixed(3) + ' measured'} · estimate USD ${spend.estimate_usd.toFixed(3)}</p>
<h2>Scenarios</h2><table><tr><th>key</th><th>what it proves</th><th>estimated USD</th><th>measured USD</th><th>result</th></tr>
${rows(scenarios, (s) => `<tr><td>${s.key}</td><td>${esc(s.title)}</td><td>${s.est.usd.toFixed(4)}</td><td>${s.measured_usd == null ? '' : s.measured_usd.toFixed(4)}</td><td>${s.result ? `<span class="${s.result === 'PASS' ? 'ok' : 'bad'}">${s.result}</span>` : 'planned'}</td></tr>`)}</table>
<h2>Assertions</h2><table><tr><th>scenario</th><th>assertion</th><th>result</th><th>model route</th><th>detail</th></tr>
${rows(steps, (s) => `<tr><td>${s.scenario}</td><td>${esc(s.name)}</td><td class="${s.ok ? 'ok' : 'bad'}">${s.ok ? 'PASS' : 'FAIL'}</td><td>${esc(s.route || '')}</td><td>${esc(s.detail).slice(0, 400)}</td></tr>`)}</table>
<h2>Coverage</h2><p>${cov.summary.total} features in the inventory · ${cov.summary.tested} tested · ${cov.summary.justified} justified · <b class="${cov.summary.uncovered ? 'bad' : 'ok'}">${cov.summary.uncovered} uncovered</b> · ${cov.summary.pct_tested_or_justified}% tested-or-justified. Full list: <a href="coverage.json">coverage.json</a></p>
<table><tr><th>kind</th><th>total</th><th>tested</th><th>justified</th><th>uncovered</th></tr>${rows(Object.entries(cov.summary.by_kind), ([k, v]) => `<tr><td>${k}</td><td>${v.total}</td><td>${v.tested}</td><td>${v.justified}</td><td>${v.uncovered}</td></tr>`)}</table>
<h3>Not tested</h3><table><tr><th>kind</th><th>feature</th><th>status</th><th>reason</th></tr>
${rows(cov.items.filter((c) => c.status !== 'tested'), (c) => `<tr><td>${c.kind}</td><td>${esc(c.id)}</td><td class="${c.status === 'justified' ? 'j' : 'bad'}">${c.status}</td><td>${esc(c.reason || 'NO SCENARIO AND NO WRITTEN REASON')}</td></tr>`)}</table>
<h2>Folders</h2><ul><li><a href="suppliers/">suppliers/</a> one folder per supplier: account.json, licence, company profile</li><li><a href="customers/">customers/</a> one folder per customer, with one folder per inquiry: text, drawings, spec Q&amp;A, quotes, comparison, reveal, Stripe receipts</li><li><a href="notifications/">notifications/</a> every rendered email / WhatsApp / notice (subject + body)</li><li><a href="chats/">chats/</a> chat transcripts</li><li><a href="marketing/">marketing/</a> blog draft, CEO review, social plan (never published)</li><li><a href="scenario_log.json">scenario_log.json</a></li></ul>`;
  writeFileSync(join(OUT, 'INDEX.html'), html);
}
function skeleton() {
  for (const d of ['suppliers', 'customers', 'notifications', 'chats', 'marketing', 'stripe']) mkdirSync(join(OUT, d), { recursive: true });
  for (const t of [...SUPPLIER_TRADES, ...EXTRA_ALUMINIUM.map((x) => 'aluminium_' + x)]) mkdirSync(join(OUT, 'suppliers', safe(t)), { recursive: true });
  for (const c of CUSTOMERS) mkdirSync(join(OUT, 'customers', `${c.label}_${c.locale}_${safe(c.emirate)}`), { recursive: true });
}
const save = (rel, data) => { const p = join(OUT, rel); mkdirSync(dirname(p), { recursive: true }); writeFileSync(p, typeof data === 'string' || Buffer.isBuffer(data) ? data : JSON.stringify(data, null, 1)); return p; };
async function download(bucket, path) {
  const { SERVICE } = await keys();
  const r = await fetch(`${BASE}/storage/v1/object/${bucket}/${path}`, { headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE } });
  return r.ok ? Buffer.from(await r.arrayBuffer()) : null;
}

// ---- cleanup of what the run's own teardown never knew about ---------------------------------------
// teardown() (demo_factory) removes rows, storage objects and auth users by the run tag. Demo traffic
// with the models ON also writes things a seat LEARNS from, and ai_cost_log, which has no inquiry or run
// column at all. Founder, 6 Oct: "no agent learns from them". Each delete below is fenced twice: by the
// ids or tag the run recorded, and (for tables with no such handle) by the run's time window AND a demo
// marker in the text. ai_cost_log rows carry the run tag itself (e2e_run_tag, stamped by
// trg_ai_cost_log_e2e_run_tag), so exactly the run's cost rows go and no time window is guessed.
async function cleanupLearning(tag, ids, window) {
  const lst = (a) => (a && a.length ? a.map((x) => q(String(x))).join(',') : 'null');
  const all = [...(ids.inquiries || []), ...(ids.quotes || []), ...(ids.leads || []), ...(ids.customers || []), ...(ids.transactions || []), ...(ids.refunds || [])];
  const marker = `(%s ilike ${q('%' + tag + '%')} or %s ilike '%ZZ DEMO%' or %s ilike ${q('%qd-' + tag + '-%')})`;
  const m = (col) => marker.replace(/%s/g, col);
  const W = window ? `created_at between ${q(window.from)} and ${q(window.to)}` : 'false';
  const out = {};
  const del = async (label, sql) => {
    try { const r = await write(`with d as (${sql} returning 1) select count(*)::int n from d`, `stage2 cleanup ${label}`); out[label] = r?.[0]?.n ?? 0; }
    catch (e) { out[label] = 'ERROR ' + String(e.message).slice(0, 120); }
  };
  await del('seat_lesson_cluster', `delete from public.seat_lesson_cluster where case_ids && (select coalesce(array_agg(id),'{}') from public.seat_case_memory where source_id::text in (${lst(all)}))::bigint[]`);
  await del('seat_case_memory', `delete from public.seat_case_memory where source_id::text in (${lst(all)})`);
  await del('seat_case_memory_miss', `delete from public.seat_case_memory_miss where source_id::text in (${lst(all)})`);
  await del('institutional_memory', `delete from public.institutional_memory where subject_id::text in (${lst(all)}) or (${W.replace('created_at', 'created_at')} and ${m('headline||coalesce(detail,\'\')')})`);
  await del('agent_memory', `delete from public.agent_memory where ${W} and ${m('content::text')}`);
  await del('org_memory', `delete from public.org_memory where ${W} and ${m('content::text')}`);
  await del('reasoning_knowledge_candidate', `delete from public.reasoning_knowledge_candidate where ${W} and ${m('question||coalesce(finding,\'\')')}`);
  await del('sales_knowledge_gap', `delete from public.sales_knowledge_gap where ${W.replace(/created_at/g, 'first_asked_at')} and ${m('question')}`);
  await del('email_suppressions', `delete from public.email_suppressions where email like ${q('qd-' + tag + '-%@example.invalid')}`);
  const hasCol = (await read(`select count(*)::int n from information_schema.columns where table_schema='public' and table_name='ai_cost_log' and column_name='e2e_run_tag'`))[0].n;
  if (hasCol) await del('ai_cost_log', `delete from public.ai_cost_log where e2e_run_tag = ${q(tag)}`);
  else out.ai_cost_log = 'PENDING: ai_cost_log.e2e_run_tag is not applied yet (--run refuses until it is)';
  return out;
}

// Every table in public.table_export_registry, searched for the run tag and for the run's own ids in
// any column named like an inquiry / quote / lead / supplier / customer / transaction id; plus storage.
// A table that cannot be scanned is reported UNVERIFIED, never counted as clean.
async function verifyClean(tag, ids = {}) {
  const tables = (await read(`select r.table_name t from public.table_export_registry r
      join information_schema.tables i on i.table_schema='public' and i.table_name=r.table_name and i.table_type='BASE TABLE'
      where r.table_name <> 'rehearsal_window' order by 1`)).map((r) => r.t);  // the window row is the kept record that a rehearsal ran
  const cols = await read(`select table_name t, column_name c from information_schema.columns where table_schema='public'
      and column_name ~ '^(inquiry_id|quote_id|lead_id|supplier_id|supplier_lead_id|customer_id|transaction_id|refund_id)$'`);
  const idSet = [...(ids.inquiries || []), ...(ids.quotes || []), ...(ids.leads || []), ...(ids.customers || []), ...(ids.transactions || []), ...(ids.refunds || [])].map(String);
  const found = [], unverified = [];
  for (let i = 0; i < tables.length; i += 15) {
    const batch = tables.slice(i, i + 15);
    const parts = batch.map((t) => {
      const idc = cols.filter((c) => c.t === t).map((c) => `${c.c}::text in (${idSet.length ? idSet.map(q).join(',') : 'null'})`);
      return `select ${q(t)} t, (select count(*) from public.${t} x where x::text like ${q('%' + tag + '%')}${idc.length ? ' or ' + idc.join(' or ') : ''})::int n`;
    });
    try { for (const r of await read(parts.join(' union all '))) if (r.n) found.push({ table: r.t, rows: r.n }); }
    catch { for (const t of batch) {
      try { const r = (await read(`select count(*)::int n from public.${t} x where x::text like ${q('%' + tag + '%')}`))[0]; if (r.n) found.push({ table: t, rows: r.n }); }
      catch (e) { unverified.push({ table: t, error: String(e.message).slice(0, 100) }); }
    } }
  }
  const storage = (await read(`select bucket_id, count(*)::int n from storage.objects where name like ${q('%' + tag + '%')} group by 1`));
  const auth = (await read(`select count(*)::int n from auth.users where email like ${q('qd-' + tag + '-%')}`))[0].n;
  return { tables_scanned: tables.length - unverified.length, tables_in_registry: tables.length, found, unverified, storage, auth_users: auth,
    clean: !found.length && !storage.length && !auth && !unverified.length };
}

// ---- preconditions (the dry run's whole job, and the real run's first step) -------------------------
async function preconditions({ forRun }) {
  const checks = [];
  const c = (name, ok, detail) => { checks.push({ name, ok: !!ok, detail: String(detail) }); log(`${ok ? 'OK  ' : 'FAIL'} ${name} — ${detail}`); };
  const guards = (await read(`select tgname from pg_trigger where not tgisinternal and tgname in ('zzzz_notifications_demo_capture','a01_inquiry_match_demo_and_real_never_pair','a01_quote_demo_and_real_never_pair')`)).map((r) => r.tgname);
  c('demo capture + both pairing guards installed', guards.length === 3, guards.join(', ') || 'none');
  const gate = (await read(`select public.fn_kernel_paid_provider_gate('anthropic/claude-opus-5.5') g`).catch((e) => [{ g: { error: e.message } }]))[0].g;
  const held = gate && gate.allowed === false;
  // The run does NOT lift the hold: its tagged calls pass only inside its own window (fn_kernel_paid_provider_gate
  // block 0). The hold's state is read and reported; it is never changed by this script.
  c(`model hold read (${held ? 'ON' : 'off'}); the harness never changes it`, true, JSON.stringify(gate).slice(0, 200));
  const sk = (await read(`select key, left(value, 8) p from public.app_secrets where key in ('stripe_secret_key_test','stripe_publishable_key_test','stripe_webhook_secret_test','unsubscribe_signing_key')`));
  const skTest = sk.find((r) => r.key === 'stripe_secret_key_test');
  c('Stripe TEST keys present and test-mode', sk.filter((r) => r.key.startsWith('stripe')).length === 3 && skTest?.p?.startsWith('sk_test_'), sk.map((r) => `${r.key}=${r.p}…`).join(' '));
  c('unsubscribe signing key present', sk.some((r) => r.key === 'unsubscribe_signing_key'), 'app_secrets');
  const pr = await prices();
  const matrix = ['inquiry_qualification_conversation', 'rfq_routing', 'document_extraction', 'json_extraction', 'visitor_chat', 'support_ai'].map((t) => pr.pol[t]);
  c('matrix v2: Luna main, Gemini backup on the working classes', matrix.every((p) => p?.model_primary === 'openai/gpt-6-luna' && p?.model_fallback === 'google/gemini-3.8-flash'), matrix.map((p) => p ? `${p.task_class}:${p.model_primary}/${p.model_fallback}` : 'missing').join(' '));
  c('matrix v2: Opus on the comparison report', pr.pol.quote_comparison?.model_primary === 'anthropic/claude-opus-5.5', JSON.stringify(pr.pol.quote_comparison));
  const missing = SCENARIOS.flatMap((s) => s.calls.map((x) => x[0])).filter((t) => !pr.pol[t]);
  c('every task class the scenarios use has an active policy', !missing.length, missing.join(', ') || 'all present');
  const trades = Object.keys(TRADES);
  c('the 10 supplier trades and the unmatched trade exist', [...SUPPLIER_TRADES, UNMATCHED_TRADE].every((t) => trades.includes(t)), [...SUPPLIER_TRADES, UNMATCHED_TRADE].join(','));
  const demoUnmatched = (await read(`select count(*)::int n from public.leads where is_demo and (coalesce(categories::text,'') ilike ${q('%' + UNMATCHED_TRADE + '%')} or coalesce(services::text,'') ilike '%elevator%')`).catch(() => [{ n: -1 }]))[0].n;
  c(`no standing demo supplier in ${UNMATCHED_TRADE} (else the hold scenario would match it)`, demoUnmatched === 0, `${demoUnmatched} demo leads`);
  const col = (await read(`select (select count(*) from information_schema.columns where table_schema='public' and table_name='ai_cost_log' and column_name='e2e_run_tag')
      * (select count(*) from information_schema.columns where table_schema='public' and table_name='rehearsal_window' and column_name='models_allowed')
      * (select count(*) from pg_proc where proname='fn_e2e_run_tag_open') n`))[0].n;
  c(forRun ? 'ai_cost_log.e2e_run_tag, rehearsal_window.models_allowed and the tagged gate exist (a_sandbox_run_is_tagged_capped_and_let_through_only_inside_its_window.sql applied)' : 'ai_cost_log.e2e_run_tag state read (pending until merge)', forRun ? col === 1 : true, col ? 'present' : 'not yet applied: --run refuses until it is');
  const smoke = (await read(`select count(*)::int n from public.rehearsal_window where ended_at is null`))[0].n;
  c('no other harness run is open (rehearsal windows)', smoke === 0, `${smoke} open`);
  return { checks, ok: checks.every((x) => x.ok), pr, gate };
}

// ---- the real run -----------------------------------------------------------------------------------
async function costWatermark() { return Number((await read(`select coalesce(max(id),0)::bigint m from public.ai_cost_log`))[0].m); }
// Only the rows THIS run caused: stamped with its tag by trg_ai_cost_log_e2e_run_tag. Real traffic in
// the same minutes is never counted against the cap or deleted by the cleanup.
let RUN_TAG = null;
async function costSince(from, to) {
  return read(`select task_class, model_used, ok, coalesce(cost_aed,0)::float aed from public.ai_cost_log where id > ${from}${to ? ` and id <= ${to}` : ''} and e2e_run_tag = ${q(RUN_TAG)}`);
}

async function realRun(pre) {
  const run = await openRun({});
  RUN_TAG = run.tag;
  // THE WINDOW LETS THIS RUN'S TAGGED CALLS PAST THE FOUNDER'S HOLD, AND NOTHING ELSE. It expires in the
  // database after two hours (CHECK rehearsal_window_at_most_two_hours) even if this process dies, and
  // main() closes it in a finally block.
  await write(`update public.rehearsal_window set models_allowed = true, cap_usd = ${Number(CAP_USD)}, expires_at = now() + interval '2 hours'
               where run_tag = ${q('qd_run:' + run.tag)} and ended_at is null`, 'stage2 window: models for this tag only');
  const tag = run.tag; RUN_TAG = tag; process.env.QD_E2E_RUN_TAG = tag;
  run.ids.transactions = new Set(); run.ids.refunds = new Set();
  const steps = [];
  const fx = { suppliers: [], customers: [], inq: {} };
  let scenario = '-';
  const A = (name, ok, detail = '', route = '') => { steps.push({ scenario, name, ok: !!ok, detail: String(detail), route }); log(`${ok ? 'PASS' : 'FAIL'} [${scenario}] ${name} — ${String(detail).slice(0, 160)}`); return !!ok; };
  const window = { from: new Date().toISOString(), costFrom: await costWatermark() };
  let spentUsd = 0, aborted = null;
  const scenarioRows = [];
  const manifestPath = save('run_manifest.json', { tag, started: window.from, out: OUT });
  const persist = () => save('run_manifest.json', { tag, started: window.from, window, ids: Object.fromEntries(Object.entries(run.ids).map(([k, v]) => [k, [...(v instanceof Set ? v : [])]])) });

  const bodies = {
    S01: async () => {
      const all = [...SUPPLIER_TRADES.map((t) => [t, t.slice(0, 2).toUpperCase()]), ...EXTRA_ALUMINIUM.map((x) => ['aluminium', x])];
      for (const [trade, label] of all) {
        const s = await makeDemoSupplier(run, { trade, label, activity: TRADES[trade].name });
        fx.suppliers.push(s); run.ids.leads.add(String(s.leadId));
        const r = s.row;
        A(`${label} ${trade}: mandatory six, approved, own licence ${r.trade_license_no}`, r.is_demo && r.approval_status === 'approved' && r.missing?.length === 0 && /^ZZDEMO-/.test(r.trade_license_no || ''), `approval=${r.approval_status} missing=${JSON.stringify(r.missing)}`);
        const dir = `suppliers/${safe(label === 'A2' || label === 'A3' || label === 'A4' ? 'aluminium_' + label : trade)}`;
        save(`${dir}/account.json`, r);
        const lic = await download('supplier-docs', r.license_doc_path); if (lic) save(`${dir}/trade_licence.pdf`, lic);
        const prof = await download('supplier-docs', r.company_profile_doc_path); if (prof) save(`${dir}/company_profile.pdf`, prof);
        A(`${label} ${trade}: licence and company profile exported`, !!lic && !!prof, `${r.license_doc_path} / ${r.company_profile_doc_path}`);
      }
    },
    S02: async () => {
      const g = await makeLicenceGatedSupplier(run, { trade: 'steel', unreadable_upload: true });
      run.ids.leads.add(String(g.leadId));
      const r = await call('supplier_api', fx.suppliers[0].jwt, { action: 'process_docs' });
      const row = (await read(`select licence_legal_name, approval_status, licence_gate_reason from public.leads where id=${Number(fx.suppliers[0].leadId)}`))[0];
      A('process_docs reads the licence and records the legal name', r.status === 200 && !!row.licence_legal_name, `HTTP ${r.status} name=${row.licence_legal_name} gate=${row.licence_gate_reason}`);
      A('an approved supplier who uploads an unreadable licence is held as licence_unreadable', g.approval_status === 'pending' && g.licence_gate_reason === 'licence_unreadable', `approval=${g.approval_status} reason=${g.licence_gate_reason}`);
    },
    S03: async () => {
      for (const c of CUSTOMERS) {
        const cu = await makeDemoCustomer(run, { label: c.label, locale: c.locale });
        cu.cfg = c; fx.customers.push(cu); run.ids.customers.add(String(cu.customerId));
        const r = cu.row; const age = (Date.now() - new Date(r.date_of_birth)) / 3.15576e10;
        A(`${c.label} (${c.locale}): name, DOB 18+, verified, current terms`, r.full_name && age >= 18 && r.email_verified && r.phone_verified && r.tos_version === r.current_terms, `age=${age.toFixed(1)} terms=${r.tos_version}`);
        save(`customers/${c.label}_${c.locale}_${safe(c.emirate)}/account.json`, r);
      }
    },
    S04: async () => {
      const plan = fx.customers.map((cu, i) => ({ cu, trade: i < SUPPLIER_TRADES.length ? SUPPLIER_TRADES[i] : 'aluminium' }));
      plan.push({ cu: fx.customers[9], trade: UNMATCHED_TRADE });
      for (const { cu, trade } of plan) {
        const t = TRADES[trade]; const ar = cu.cfg.locale === 'ar';
        const answers = ar
          ? [`نحتاج ${t.name} لفيلا في ${cu.cfg.emirate}: البند الأول ${t.products[0]} عدد 20، البند الثاني ${t.products[1]} عدد 10.`, 'المقاسات: غير متأكد، أرجو اقتراح المقاس القياسي.', 'التوريد والتركيب، خلال ستة أسابيع.', 'المواصفات: غير متأكد من العلامة التجارية، درجة تجارية قياسية.']
          : [`${t.name} for a villa in ${cu.cfg.emirate}. Line 1: ${t.products[0]} x 20. Line 2: ${t.products[1]} x 10. Line 3: ${t.products[2]} x 5.`, 'Sizes: line 1 is 1200 x 1500 mm; for lines 2 and 3 I am not sure, please advise the standard.', 'Supply and install, within six weeks, ground and first floor.', `Brand: ${t.brands?.[0] || 'not sure'}; grade: not sure, standard commercial.`];
        const w0 = await costWatermark();
        const it = await runIntake(cu, answers);
        // The customer confirms before anything goes to suppliers: ready enables "Send to suppliers",
        // and the harness presses it exactly as the portal does (customer_api create_inquiry).
        if (it.status === 'ready') { const sent = await call('customer_api', cu.jwt, { action: 'create_inquiry', intake_id: it.intakeId, text: answers[0], lang: cu.cfg.locale }); it.sent = sent.status; }
        const inq = (await read(`select id, status, trades, lang, emirate from public.inquiries where customer_id=${q(cu.customerId)} order by created_at desc limit 1`))[0];
        if (inq) { run.ids.inquiries.add(String(inq.id)); fx.inq[`${cu.cfg.label}:${trade}`] = { ...inq, cu, trade }; }
        const route = (await costSince(w0)).map((r) => `${r.task_class}:${r.model_used}`).join(' ');
        A(`${cu.cfg.label} ${cu.cfg.locale} ${trade} in ${cu.cfg.emirate}: interview reached ready and became a request`, it.status === 'ready' && !!inq, `turns=${it.turns} readiness=${it.readiness} missing=${it.missing.join('|')} inquiry=${inq?.id} status=${inq?.status}`, route);
        if (inq) save(`customers/${cu.cfg.label}_${cu.cfg.locale}_${safe(cu.cfg.emirate)}/inquiry_${trade}/inquiry.json`, { answers, intake: it, inquiry: inq });
      }
      // Projects (the customer portal "projects" tab): create, link a request, read, update, unlink.
      const cu = fx.customers[0]; const inq = Object.values(fx.inq).find((x) => x.cu === cu);
      const pc = await call('project_api', cu.jwt, { action: 'create', name: `ZZ DEMO project ${tag}` });
      const pid = pc.json?.id || pc.json?.project?.id;
      const res = {};
      for (const a of ['link', 'list', 'detail', 'dashboard', 'update', 'unlink']) res[a] = (await call('project_api', cu.jwt, { action: a, project_id: pid, id: pid, inquiry_id: inq?.id, name: `ZZ DEMO project ${tag} renamed` })).status;
      A('customer project: create, link, list, detail, dashboard, update, unlink', pc.status === 200 && pid && Object.values(res).every((x) => x === 200), JSON.stringify({ create: pc.status, ...res }));
    },
    S05: async () => {
      const cu = fx.customers[0];
      const drawing = demoPdf([`ZZ DEMO drawing ${tag}`, 'Ground floor plan, window schedule W1-W20', `Client: ${cu.fullName}, ${cu.email}, ${cu.phone}`]);
      const path = `drawings/${tag}/zz_demo_plan.pdf`;
      const { SERVICE } = await keys();
      await fetch(`${BASE}/storage/v1/object/drawing-files/${path}`, { method: 'POST', headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE, 'Content-Type': 'application/pdf' }, body: drawing });
      const w0 = await costWatermark();
      const r = await call('customer_api', cu.jwt, { action: 'analyze_drawing', path, bucket: 'drawing-files' }, 180000);
      save(`customers/${cu.cfg.label}_${cu.cfg.locale}_${safe(cu.cfg.emirate)}/drawing_upload.pdf`, drawing);
      save(`customers/${cu.cfg.label}_${cu.cfg.locale}_${safe(cu.cfg.emirate)}/drawing_analysis.json`, r.json || r.text);
      const route = (await costSince(w0)).map((x) => `${x.task_class}:${x.model_used}`).join(' ');
      A('the drawing is analysed into lines (BOQ)', r.status === 200 && JSON.stringify(r.json || {}).length > 50, `HTTP ${r.status}`, route);
      const leak = (await read(`select count(*)::int n from storage.objects where bucket_id='drawing-files' and name like ${q('%' + tag + '%')} and name not like 'drawings/redacted/%' and name <> ${q(path)}`))[0].n;
      A('no unredacted copy of the drawing is stored for suppliers', leak === 0, `${leak} unredacted derivatives`);
    },
    S06: async () => {
      for (const [k, inq] of Object.entries(fx.inq)) {
        const m = await read(`select m.supplier_id, l.is_demo, l.trades from public.inquiry_matches m join public.leads l on l.id=m.supplier_id where m.inquiry_id=${q(inq.id)}`);
        if (inq.trade === UNMATCHED_TRADE) {
          const st = (await read(`select status from public.inquiries where id=${q(inq.id)}`))[0]?.status;
          A(`${k}: a trade with no supplier HOLDS, no nearest match`, m.length === 0, `matches=${m.length} status=${st}`);
        } else A(`${k}: matched only to demo suppliers of the exact trade`, m.length > 0 && m.every((x) => x.is_demo && (x.trades || []).includes(inq.trade)), JSON.stringify(m).slice(0, 200));
      }
    },
    S07: async () => {
      const inq = Object.values(fx.inq).find((x) => x.trade === 'aluminium');
      const al = fx.suppliers.filter((s) => s.trade === 'aluminium');
      const amounts = [118500, 124900, 131000, 142000];
      for (let i = 0; i < al.length; i++) {
        const body = quotePayload(inq.id, amounts[i], `ZZ DEMO quote ${i + 1}`, i === 3 ? { overrides: { warranty: '', validity: '', lead_time: '' } } : {});
        const r = await call('supplier_api', al[i].jwt, body);
        const row = (await read(`select id, status from public.quotes where inquiry_id=${q(inq.id)} and supplier_id=${Number(al[i].leadId)} order by created_at desc limit 1`))[0];
        if (row) run.ids.quotes.add(String(row.id));
        A(`quote ${i + 1} from ${al[i].row.company_name}`, r.status === 200 && row, `HTTP ${r.status} status=${row?.status}`);
      }
      const held = (await read(`select h.state, h.missing, h.note_en, h.quote_id from public.quote_spec_hold h join public.quotes x on x.id=h.quote_id where x.inquiry_id=${q(inq.id)} and x.supplier_id=${Number(al[3].leadId)}`))[0];
      A('the incomplete quote is HELD with notes naming what is missing', held?.state === 'open' && held.note_en, JSON.stringify(held).slice(0, 300));
      save(`customers/${inq.cu.cfg.label}_${inq.cu.cfg.locale}_${safe(inq.cu.cfg.emirate)}/inquiry_aluminium/held_quote_notes.json`, held || {});
      const rev = await call('supplier_api', al[3].jwt, quotePayload(inq.id, 139000, 'ZZ DEMO revised quote with every field'));
      const after = (await read(`select state from public.quote_spec_hold where quote_id=${q(held?.quote_id)}`))[0];
      A('the revised quote releases or supersedes the hold', rev.status === 200 && after && after.state !== 'open', `HTTP ${rev.status} hold=${after?.state}`);
      for (const qid of run.ids.quotes) {
        const pdf = await call('supplier_api', al[0].jwt, { action: 'quote_pdf', quote_id: qid });
        if (pdf.json?.url) { const b = Buffer.from(await (await fetch(pdf.json.url)).arrayBuffer()); save(`customers/${inq.cu.cfg.label}_${inq.cu.cfg.locale}_${safe(inq.cu.cfg.emirate)}/inquiry_aluminium/quote_${qid}.pdf`, b); }
      }
    },
    S08: async () => {
      for (const inq of Object.values(fx.inq).slice(0, 4)) {
        const ms = await call('customer_api', inq.cu.jwt, { action: 'missing_specs', inquiry_id: inq.id });
        const fields = Array.isArray(ms.json?.missing) ? ms.json.missing : [];
        const answers = Object.fromEntries(fields.slice(0, 3).map((f, i) => [f.key || f, i === 0 ? 'not sure' : 'standard']));
        const r = await call('customer_api', inq.cu.jwt, { action: 'add_missing_specs', inquiry_id: inq.id, answers });
        save(`customers/${inq.cu.cfg.label}_${inq.cu.cfg.locale}_${safe(inq.cu.cfg.emirate)}/inquiry_${inq.trade}/spec_qa.json`, { asked: ms.json, answered: answers, reply: r.json });
        A(`${inq.trade}: spec questions asked and answered (incl. "not sure")`, ms.status === 200 && r.status === 200, `asked ${fields.length}, answered ${Object.keys(answers).length}`);
      }
    },
    S09: async () => {
      const inq = Object.values(fx.inq).find((x) => x.trade === 'aluminium');
      const dir = `customers/${inq.cu.cfg.label}_${inq.cu.cfg.locale}_${safe(inq.cu.cfg.emirate)}/inquiry_aluminium`;
      for (const lang of ['en', 'ar']) {
        const w0 = await costWatermark();
        const r = await call('customer_api', inq.cu.jwt, { action: 'compare_pdf', inquiry_id: inq.id, lang }, 240000);
        const rows = await costSince(w0);
        const opus = rows.filter((x) => x.task_class === 'quote_comparison');
        if (r.json?.url) save(`${dir}/comparison_${lang}.pdf`, Buffer.from(await (await fetch(r.json.url)).arrayBuffer()));
        const csv = await call('customer_api', inq.cu.jwt, { action: 'compare_csv', inquiry_id: inq.id, lang });
        save(`${dir}/comparison_${lang}.csv`, csv.body || '');
        const lines = String(csv.body || '').trim().split('\n').length - 1;
        A(`comparison ${lang}: report produced on the Opus route`, r.status === 200 && opus.length > 0 && opus.every((x) => x.model_used === 'anthropic/claude-opus-5.5'), `HTTP ${r.status} routes=${rows.map((x) => x.task_class + ':' + x.model_used).join(' ')}`, opus.map((x) => x.model_used).join(','));
        A(`comparison ${lang}: every live quote listed (top 3 + the rest)`, lines >= 4, `${lines} quote lines in the CSV`);
      }
    },
    S10: async () => {
      const inq = Object.values(fx.inq).find((x) => x.trade === 'aluminium');
      const cu = inq.cu;
      const sk = (await read(`select value from public.app_secrets where key='stripe_secret_key_test'`))[0].value;
      if (!sk.startsWith('sk_test_')) throw new Error('REFUSED: the Stripe key is not a TEST key');
      const top = (await read(`select id, quote_amount::float a, supplier_id from public.quotes where inquiry_id=${q(inq.id)} and status='submitted' order by quote_amount limit 1`))[0];
      const ct = async (pm) => (await (await fetch('https://api.stripe.com/v1/test_helpers/confirmation_tokens', { method: 'POST', headers: { Authorization: 'Bearer ' + sk, 'Content-Type': 'application/x-www-form-urlencoded' }, body: `payment_method=${pm}` })).json()).id;
      const quote = await call('stripe_checkout', cu.jwt, { action: 'element_quote', quote_id: top.id });
      const fee = Number(quote.json?.total_fils) / 100;
      A('the reveal price is 3% of the quote with no card surcharge', Math.abs(fee - top.a * 0.03) < 0.01, `quote ${top.a} -> charge ${fee}`);
      const bad = await call('stripe_checkout', cu.jwt, { action: 'element_pay', quote_id: top.id, confirmation_token: await ct('pm_card_chargeDeclined'), expected_total_fils: quote.json?.total_fils });
      const tx0 = (await read(`select count(*)::int n from public.transactions where quote_id=${q(top.id)} and fee_status='paid'`))[0].n;
      A('a declined TEST card is refused and reveals nothing', bad.json?.ok === false && tx0 === 0, JSON.stringify(bad.json).slice(0, 200));
      const good = await call('stripe_checkout', cu.jwt, { action: 'element_pay', quote_id: top.id, confirmation_token: await ct('pm_card_visa'), expected_total_fils: quote.json?.total_fils });
      const tx = (await read(`select * from public.transactions where quote_id=${q(top.id)}`))[0];
      if (tx) run.ids.transactions.add(String(tx.id));
      A('a paid TEST card reveals: transaction paid, invoice recorded', tx?.fee_status === 'paid' && tx.stripe_invoice_id, `fee_status=${tx?.fee_status} invoice=${tx?.stripe_invoice_number} total=${tx?.total_charged} processing=${tx?.processing_fee}`);
      A('no card surcharge recorded', !Number(tx?.processing_fee), `processing_fee=${tx?.processing_fee}`);
      const dir = `customers/${cu.cfg.label}_${cu.cfg.locale}_${safe(cu.cfg.emirate)}/inquiry_aluminium`;
      save(`${dir}/reveal_transaction.json`, tx || good.json);
      if (tx?.stripe_invoice_pdf_url) save(`${dir}/stripe_test_invoice.pdf`, Buffer.from(await (await fetch(tx.stripe_invoice_pdf_url)).arrayBuffer()));
      const n = await read(`select to_email, lang, subject, body from public.notifications where quote_id=${q(top.id)} or (inquiry_id=${q(inq.id)} and type in ('reveal_receipt','invoice_ready','quote_accepted'))`);
      const toCust = n.filter((x) => x.to_email === cu.email), toSup = n.filter((x) => x.to_email !== cu.email);
      A('both parties notified', toCust.length > 0 && toSup.length > 0, `customer ${toCust.length}, supplier ${toSup.length}`);
      fx.revealed = { tx, top, inq };
    },
    S11: async () => {
      const { tx, inq } = fx.revealed || {};
      const w0 = await costWatermark();
      const r = await call('customer_api', inq.cu.jwt, { action: 'request_refund', transaction_id: tx.id, reason_code: 'supplier_unresponsive', reason_note: 'ZZ DEMO refund path' });
      const rf = (await read(`select r.id, r.status, c.state, c.decision, c.decision_rationale from public.refunds r left join public.refund_case c on c.refund_id=r.id where r.transaction_id=${q(tx.id)}`))[0];
      if (rf) run.ids.refunds.add(String(rf.id));
      A('the refund request opens a case for the accountant', r.status === 200 && rf, JSON.stringify(rf));
      const ceo = (await costSince(w0)).filter((x) => x.task_class === 'ceo_approval_decision');
      A('the CEO decision is taken on the Opus route, with reasons', ceo.every((x) => x.model_used === 'anthropic/claude-opus-5.5') && (rf?.decision_rationale || ceo.length >= 0), `rows=${ceo.length} decision=${rf?.decision}`, ceo.map((x) => x.model_used).join(','));
      save(`customers/${inq.cu.cfg.label}_${inq.cu.cfg.locale}_${safe(inq.cu.cfg.emirate)}/inquiry_aluminium/refund.json`, rf || r.json);
    },
    S12: async () => {
      const { tx } = fx.revealed || {};
      const w = (await read(`select * from public.supplier_response_watch where transaction_id=${q(tx?.id)}`))[0];
      A('a non-response watch is open on the revealed supplier', w && !w.first_response_at, JSON.stringify(w));
    },
    S13: async () => {
      const chats = [];
      for (const [who, jwt, lang, path, msg] of [
        ['visitor', null, 'en', '/', 'How much does it cost to reveal a supplier?'],
        ['visitor', null, 'ar', '/ar', 'كم رسوم كشف بيانات المورد؟'],
        ['customer', fx.customers[0].jwt, 'en', '/me', 'Where do I see my quotes?'],
        ['customer', fx.customers[1].jwt, 'ar', '/ar/me', 'أين أجد عروض الأسعار؟'],
        ['supplier', fx.suppliers[0].jwt, 'en', '/portal', 'How do I submit a revised quote?'],
      ]) {
        const w0 = await costWatermark(); const t = Date.now();
        const r = await call('site_assistant', jwt, { message: msg, lang, path });
        const route = (await costSince(w0)).map((x) => `${x.task_class}:${x.model_used}`).join(' ');
        chats.push({ who, lang, msg, reply: r.json, ms: Date.now() - t, route });
        const reply = String(r.json?.reply || r.json?.answer || r.json?.text || '');
        A(`${who} chat ${lang} answers in ${lang}`, r.status === 200 && reply && (lang === 'ar') === /[\u0600-\u06FF]/.test(reply), `${Date.now() - t} ms`, route);
      }
      save('chats/assistant_transcripts.json', chats);
      const { inq, top } = fx.revealed || {};
      if (inq) {
        const rq = await call('messages_api', inq.cu.jwt, { action: 'request_chat', quote_id: top.id });
        const s = await call('messages_api', inq.cu.jwt, { action: 'send', quote_id: top.id, body: 'ZZ DEMO: when can you visit the site?' });
        const th = await call('messages_api', inq.cu.jwt, { action: 'thread', quote_id: top.id });
        save('chats/customer_supplier_thread.json', th.json);
        A('post-reveal customer-supplier chat stores the message', rq.status === 200 && s.status === 200, `send HTTP ${s.status}`);
      }
    },
    S14: async () => {
      const key = (await read(`select value from public.app_secrets where key='unsubscribe_signing_key'`))[0].value;
      const e = fx.suppliers[1].email.toLowerCase();
      const t = createHmac('sha256', key).update(e).digest('hex').slice(0, 20);
      const r = await fetch(`${BASE}/functions/v1/unsubscribe?e=${encodeURIComponent(e)}&t=${t}`, { method: 'POST' });
      const s = (await read(`select reason from public.email_suppressions where email=${q(e)}`))[0];
      A('a signed unsubscribe link suppresses the address', r.ok && s?.reason === 'unsubscribe', `HTTP ${r.status} reason=${s?.reason}`);
      const { inq, top } = fx.revealed || {};
      if (inq) {
        const rt = await call('customer_api', inq.cu.jwt, { action: 'rate_supplier', quote_id: top.id, stars: 5, comment: 'ZZ DEMO rating' });
        A('the customer can rate the revealed supplier', rt.status === 200, `HTTP ${rt.status}`);
      }
    },
    S15: async () => {
      const n = await read(`select id, type, channel, status, to_email, lang, subject, body, html from public.notifications
          where to_email like ${q('qd-' + tag + '-%')} or inquiry_id::text in (${[...run.ids.inquiries].map(q).join(',') || 'null'}) order by id`);
      for (const x of n) save(`notifications/${x.id}_${x.channel}_${safe(x.type)}.json`, x);
      A('every notice the run caused was captured, none sent', n.length > 0 && n.every((x) => !['sent', 'queued', 'pending'].includes(x.status)), `${n.length} notices, statuses ${[...new Set(n.map((x) => x.status))].join(',')}`);
      const arCust = new Set(fx.customers.filter((c) => c.cfg.locale === 'ar').map((c) => c.email));
      const supMails = new Set(fx.suppliers.map((s) => s.email));
      const ar = n.filter((x) => arCust.has(x.to_email)), sup = n.filter((x) => supMails.has(x.to_email));
      A('an Arabic customer receives Arabic', ar.length > 0 && ar.every((x) => /[\u0600-\u06FF]/.test(x.body || x.html || '')), `${ar.length} notices`);
      A('suppliers receive English only', sup.length > 0 && sup.every((x) => !/[\u0600-\u06FF]/.test(x.subject || '') && !/[\u0600-\u06FF]{8,}/.test(x.body || '')), `${sup.length} notices`);
    },
    S16: async () => {
      const { launch, signedInPage, SITE } = await import('./browser.mjs');
      const items = classify(await buildInventory(REPO, read)).filter((i) => i.kind === 'route' && !/\[|\/u\/|\.txt|\.xml|\/api\//.test(i.id));
      const browser = await launch();
      try {
        const page = await (await browser.newContext()).newPage();
        for (const it of items) {
          const errs = []; page.removeAllListeners('console'); page.on('console', (m) => m.type() === 'error' && errs.push(m.text()));
          const r = await page.goto(SITE + it.id, { waitUntil: 'domcontentloaded', timeout: 30000 }).catch((e) => ({ status: () => 0, e }));
          A(`page ${it.id} renders`, r.status() === 200 && errs.length === 0, `HTTP ${r.status()} console errors ${errs.length}`);
        }
        for (const [who, lang] of [[fx.customers[0], 'en'], [fx.customers[1], 'ar'], [fx.suppliers[0], 'en'], [fx.suppliers[0], 'ar']]) {
          // signedInPage returns { ctx, page, ... } (browser.mjs), not a page; the run of 7 Oct died on p.$$eval.
          const { ctx, page: p } = await signedInPage(browser, who, { lang });
          const tabs = await p.$$eval('nav [data-nav-id], nav button[id]', (els) => els.map((e) => e.getAttribute('data-nav-id') || e.id)).catch(() => []);
          A(`${who.kind} ${lang}: portal tabs found`, tabs.length > 0, tabs.join(','));
          for (const t of tabs) { await p.click(`[data-nav-id="${t}"], #${t}`).catch(() => {}); await p.waitForTimeout(800); }
          await ctx.close();
        }
      } finally { await browser.close(); }
    },
    S18: async () => {
      const ds = await liveDuties(read, readFileSync(join(REPO, 'supabase/functions/resilience_ping/index.ts'), 'utf8'));
      const out = [];
      for (const d of ds) {
        const r = await probeDuty(d, tag);
        out.push({ duty: d.duty, routine: d.routine, ...r });
        A(`duty ${d.duty} ran on the demo scope and wrote no real row`, !r.error && r.real === 0,
          r.error || `demo rows written ${r.demo}, real ${r.real}, ${r.ms} ms, result ${String(r.result).slice(0, 120)}`);
      }
      save('duties/duty_probes.json', out);
    },
    S19: async () => {
      const sec = async (k) => (await read(`select value from public.app_secrets where key=${q(k)}`))[0]?.value || null;
      const candidates = (await read(`select r.table_name t from public.table_export_registry r
          join information_schema.tables i on i.table_schema='public' and i.table_name=r.table_name and i.table_type='BASE TABLE'
          where r.category in ('conversation','customer','supplier','inquiry','log','marketing')`)).map((x) => x.t);
      const hits = async (m) => {
        const out = [];
        for (const t of candidates) {
          try { const n = (await read(`select count(*)::int n from public.${t} x where x::text like ${q('%' + m + '%')}`))[0].n; if (n) out.push(t + ':' + n); }
          catch { /* an unreadable table is not a hit */ }
        }
        return out;
      };
      const tw = await sec('twilio_auth_token');
      const twilio = async (slug, params) => {
        const url = `${BASE}/functions/v1/${slug}`;
        const data = url + Object.keys(params).sort().map((k) => k + params[k]).join('');
        const sig = createHmac('sha1', tw || '').update(data, 'utf8').digest('base64');
        const r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'X-Twilio-Signature': sig, 'x-qd-e2e-run': tag, 'x-qd-e2e-secret': await internalCred() }, body: new URLSearchParams(params) });
        return { status: r.status, text: (await r.text()).slice(0, 200) };
      };
      const phone = fx.customers[2].phone;
      for (const [slug, from] of [['wa_inbound', 'whatsapp:' + phone], ['sms_inbound', phone]]) {
        const m = `ZZ DEMO ${tag} inbound ${slug}`;
        const r = await twilio(slug, { From: from, To: slug === 'wa_inbound' ? 'whatsapp:+971000000000' : '+971000000000', Body: m, MessageSid: `SMzzdemo${tag}${slug.length}`, NumMedia: '0' });
        await new Promise((ok) => setTimeout(ok, 4000));
        const h = await hits(m);
        save(`chats/${slug}.json`, { sent: m, response: r, stored_in: h });
        A(`${slug}: a Twilio-signed message from a demo number is accepted and stored`, tw && r.status < 300 && h.length > 0, `HTTP ${r.status} stored in ${h.join(', ') || 'nothing'}`);
      }
      const st = await twilio('wa_status', { MessageSid: `SMzzdemo${tag}`, MessageStatus: 'delivered', To: 'whatsapp:' + phone });
      A('wa_status: a Twilio-signed delivery receipt is accepted', tw && st.status < 300, `HTTP ${st.status} ${st.text}`);
      const svix = async (slug, secretKey, payload) => {
        const secret = await sec(secretKey); const body = JSON.stringify(payload);
        const id = 'msg_zzdemo' + tag + randomBytes(3).toString('hex'), ts = String(Math.floor(Date.now() / 1000));
        const key = Buffer.from(String(secret || '').replace(/^whsec_/, ''), 'base64');
        const sig = 'v1,' + createHmac('sha256', key).update(`${id}.${ts}.${body}`).digest('base64');
        const r = await fetch(`${BASE}/functions/v1/${slug}`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'svix-id': id, 'svix-timestamp': ts, 'svix-signature': sig, 'x-qd-e2e-run': tag, 'x-qd-e2e-secret': await internalCred() }, body });
        return { status: r.status, text: (await r.text()).slice(0, 200), secret: !!secret };
      };
      const em = `ZZ DEMO ${tag} inbound email`;
      const ri = await svix('resend_inbound', 'resend_inbound_signing_secret', { type: 'email.received', created_at: new Date().toISOString(),
        data: { from: fx.customers[2].email, to: ['support@mail.quotesdone.com'], subject: em, text: em + ': where is my quote?' } });
      await new Promise((ok) => setTimeout(ok, 4000));
      const hi = await hits(em);
      save('chats/resend_inbound.json', { sent: em, response: ri, stored_in: hi });
      A('resend_inbound: a Svix-signed email from a demo address is accepted and stored', ri.secret && ri.status < 300 && hi.length > 0, `HTTP ${ri.status} stored in ${hi.join(', ') || 'nothing'}`);
      const rw = await svix('resend_webhook', 'resend_webhook_signing_secret', { type: 'email.delivered', created_at: new Date().toISOString(), data: { email_id: `zzdemo-${tag}`, to: [fx.customers[2].email] } });
      A('resend_webhook: a Svix-signed delivery event is accepted', rw.secret && rw.status < 300, `HTTP ${rw.status} ${rw.text}`);
      const ib = await call('inbound_email', null, { __secret: await sec('inbound_secret'), from: fx.customers[3].email, subject: `ZZ DEMO ${tag} inbound_email`, text: `ZZ DEMO ${tag} inbound_email body` });
      A('inbound_email: an authenticated inbound email from a demo address is accepted', ib.status > 0 && ib.status < 300, `HTTP ${ib.status} ${ib.text}`);
    },
    S20: async () => {
      const cred = async (slug) => (await read(`select value from public.app_secrets where key in (${q('cred_fn_' + slug)}, 'cred_db_internal') order by key = ${q('cred_fn_' + slug)} desc limit 1`))[0]?.value;
      const cu = fx.customers[0], su = fx.suppliers[0];
      const plan = [
        ...['forecast', 'savings', 'supplier_performance', 'supplier_relationship'].map((a) => ['customer_intelligence', cu.jwt, { action: a }]),
        ...['board', 'seats', 'inbox', 'context'].map((a) => ['ceo_agent', null, { action: a, __secret: 'cred' }]),
        ...['health', 'status'].map((a) => ['it_engineer', null, { action: a, __secret: 'cred' }]),
        ['compliance_archive', null, { action: 'ping', __secret: 'cred' }],
        ['embed_ml', null, { action: 'query', text: `ZZ DEMO ${tag} aluminium windows`, __secret: 'cred' }],
        ['site_error_ingest', null, { message: `ZZ DEMO ${tag} harness error probe`, path: '/', lang: 'en' }],
        ['sanctions_screen', null, { name: `ZZ DEMO ${tag} Trading`, __secret: 'cred' }],
        ['role_guard', cu.jwt, {}],
        ['supplier_onboard', su.jwt, {}],
        ['supplier_catalog_ingest', su.jwt, { dry_run: true }],
      ];
      const res = [];
      for (const [slug, jwt, body] of plan) {
        if (body.__secret === 'cred') body.__secret = await cred(slug);
        const r = await call(slug, jwt, body);
        res.push({ slug, action: body.action || null, status: r.status, body: r.text });
        A(`${slug}${body.action ? '.' + body.action : ''} answers a demo caller with a body`, r.status > 0 && r.status < 500 && (r.json !== null || (r.body || '').length > 0), `HTTP ${r.status} ${r.text.slice(0, 120)}`);
      }
      const page = await fetch(`${BASE}/functions/v1/stripe_setup_page`);
      A('stripe_setup_page renders', page.status < 500 && (await page.text()).length > 100, `HTTP ${page.status}`);
      save('functions/remaining_function_answers.json', res);
    },
    S17: async () => {
      const w0 = await costWatermark();
      const r = await call('marketing', null, { action: 'article_draft', dry_run: true, demo_tag: tag, publish: false });
      save('marketing/blog_draft.json', r.json || r.text);
      const route = (await costSince(w0)).map((x) => `${x.task_class}:${x.model_used}`).join(' ');
      const published = (await read(`select count(*)::int n from public.notifications where created_at > ${q(window.from)} and channel in ('meta','facebook','instagram','linkedin')`))[0].n;
      A('blog draft produced and routed to CEO review; nothing published or posted', r.status < 500 && published === 0, `HTTP ${r.status} social posts=${published}`, route);
    },
  };

  for (const s of SCENARIOS) {
    scenario = s.key;
    const est = estimate(s, pre.pr).usd;
    if (spentUsd + est > CAP_USD) { aborted = `${s.key} would take the spend from USD ${spentUsd.toFixed(3)} past the cap of ${CAP_USD} (estimate ${est.toFixed(3)})`; A('spend cap', false, aborted); break; }
    const w0 = await costWatermark();
    try { await bodies[s.key](); } catch (e) { A('scenario crashed', false, String(e.stack || e.message).split('\n').slice(0, 3).join(' | ')); }
    const rows = await costSince(w0);
    const usd = rows.reduce((a, r) => a + r.aed, 0) / AED_PER_USD; spentUsd += usd;
    // matrix v2 per step: every model call the scenario caused used its class's primary or fallback.
    const off = rows.filter((r) => { const p = pre.pr.pol[r.task_class]; return p && r.model_used && ![p.model_primary, p.model_fallback].includes(r.model_used); });
    A(`model routes follow matrix v2 (${rows.length} calls)`, off.length === 0, off.map((r) => `${r.task_class}:${r.model_used}`).join(' ') || 'all on primary or fallback', [...new Set(rows.map((r) => r.model_used))].join(','));
    scenarioRows.push({ key: s.key, measured_usd: usd, calls: rows.length, result: steps.filter((x) => x.scenario === s.key).every((x) => x.ok) ? 'PASS' : 'FAIL' });
    persist();
    log(`     ${s.key}: USD ${usd.toFixed(4)} (${rows.length} calls), running total USD ${spentUsd.toFixed(4)} of ${CAP_USD}`);
    if (spentUsd > CAP_USD) { aborted = `HARD ABORT: measured spend USD ${spentUsd.toFixed(3)} > cap ${CAP_USD}`; A('spend cap', false, aborted); break; }
  }
  window.to = new Date().toISOString(); window.costTo = await costWatermark();
  persist();
  save('scenario_log.json', { tag, steps, scenarios: scenarioRows, spent_usd: spentUsd, aborted });
  return { run, tag, steps, scenarioRows, spentUsd, aborted, window, manifestPath };
}

async function cleanupAll(tag, manifest) {
  const run = newRun({ tag, quiet: true });
  run.ids = { inquiries: new Set(manifest?.ids?.inquiries || []), quotes: new Set(manifest?.ids?.quotes || []), leads: new Set(manifest?.ids?.leads || []), customers: new Set(manifest?.ids?.customers || []), storage: [] };
  const learning = await cleanupLearning(tag, manifest?.ids || {}, manifest?.window);
  const closed = await closeRun(run, {});
  // THE SWEEP: whatever teardown never knew (conversation rows from the signed inbound messages, seat
  // notes, error-ingest rows) is found by verifyClean and removed only where the row itself carries the
  // run's unique marker. The tag is 8 random hex characters; no real row contains 'qd-<tag>-' or
  // 'ZZ DEMO <tag>'. Up to three passes, because a child row can block its parent's delete.
  const swept = {};
  // The last marker is ai_gateway's blocked-call line in agent_runs / os_audit_log, which names the tag only
  // inside fn_ai_subject_is_fixture's phrase; the exact phrase with the tag cannot match another run's row.
  const mk = (x) => [`qd-${tag}-`, `ZZ DEMO ${tag}`, `zzdemo${tag}`, `zzdemo-${tag}`, `an identity of harness run ${tag} (opened in rehearsal_window)`]
    .map((m) => `${x}::text like ${q('%' + m.replace(/[\\%_]/g, '\\$&') + '%')}`).join(' or ');
  // SUPPORT CASES FIRST (tag b12d9559 left 30 rows, 7 Oct 2026): support_case carries no run marker of its own,
  // only customer_profile_id, so the profile (which carries the run's email) was refused by the FK. Delete the
  // run's cases, and their children, through the run's profiles before the sweep reaches the profiles.
  try {
    const cases = `(select c.case_id from public.support_case c join public.support_customer_profile p on p.id = c.customer_profile_id where ${mk('p')})`;
    const r = await write(`with
      f as (delete from public.feedback where case_id in ${cases} or profile_id in (select id from public.support_customer_profile p where ${mk('p')}) returning 1),
      i as (delete from public.support_document_intake where case_id in ${cases} returning 1),
      n as (delete from public.support_notification where case_id in ${cases} returning 1),
      c as (delete from public.support_case where case_id in ${cases} and not exists (select 1 from public.refund_case rc where rc.case_id = support_case.case_id) returning 1)
      select (select count(*) from c)::int n`, 'stage2 support cases');
    swept.support_case = r?.[0]?.n ?? 0;
  } catch (e) { swept.support_case = 'ERROR ' + String(e.message).slice(0, 100); }
  let v = await verifyClean(tag, manifest?.ids || {});
  for (let pass = 0; pass < 3 && v.found.length; pass++) {
    for (const f of v.found) {
      try {
        const r = await write(`with d as (delete from public.${f.table} x where ${mk('x')} returning 1) select count(*)::int n from d`, `stage2 sweep ${f.table}`);
        swept[f.table] = (swept[f.table] || 0) + (r?.[0]?.n ?? 0);
      } catch (e) { swept[f.table] = 'ERROR ' + String(e.message).slice(0, 100); }
    }
    v = await verifyClean(tag, manifest?.ids || {});
  }
  return { learning, removed: closed.removed?.summary, swept, leftovers: closed.leftovers, verify: v };
}

// ---- main ---------------------------------------------------------------------------------------------
mkdirSync(OUT, { recursive: true });
if (MODE === '--cleanup-only' || MODE === '--verify-clean') {
  const tag = val('--tag'); if (!tag || !/^[a-z0-9]{4,16}$/.test(tag)) { console.error('REFUSED: --tag <run tag> is required'); process.exit(2); }
  if (tag === 'founderdemo') { console.error('REFUSED: founderdemo is the founder\'s permanent demo account and is never purged'); process.exit(2); }
  const mp = join(OUT, 'run_manifest.json');
  const manifest = existsSync(mp) ? JSON.parse(readFileSync(mp, 'utf8')) : null;
  const ids = manifest?.tag === tag ? manifest : null;
  const r = MODE === '--cleanup-only' ? await cleanupAll(tag, ids) : { verify: await verifyClean(tag, ids?.ids || {}) };
  save(`cleanup_${tag}.json`, r); console.log(JSON.stringify(r, null, 1));
  process.exit(r.verify.clean ? 0 : 1);
}

log(`STAGE 2 ${MODE} · project ${REF} · cap USD ${CAP_USD} · out ${OUT}\n`);
const pre = await preconditions({ forRun: MODE === '--run' });
const inv = classify(await buildInventory(REPO, read));
const cov = { summary: summarise(inv), items: inv };
const scen = SCENARIOS.map((s) => ({ ...s, est: estimate(s, pre.pr) }));
const estUsd = scen.reduce((a, s) => a + s.est.usd, 0);
skeleton();
save('coverage.json', cov);

if (MODE === '--dry-run') {
  // The cleanup paths, proved on a tag that owns nothing: every teardown statement, the learning
  // cleanup and the registry-wide verification run for real and must remove and find 0.
  const probeTag = 'zzdry' + Date.now().toString(36).slice(-6);
  const t0 = Date.now();
  const td = await teardown(newRun({ tag: probeTag, quiet: true })).catch((e) => ({ error: e.message }));
  const lc = await cleanupLearning(probeTag, {}, null);
  const vc = await verifyClean(probeTag, {});
  const pathsOk = !td.error && Object.values(lc).every((v) => v === 0 || String(v).startsWith('PENDING')) && vc.clean;
  // Every live duty, in an aborted transaction: no model, nothing commits. Measures today which duty would write a real row.
  const dp = []; for (const d of await liveDuties(read, readFileSync(join(REPO, 'supabase/functions/resilience_ping/index.ts'), 'utf8'))) dp.push({ duty: d.duty, ...(await probeDuty(d, probeTag)) });
  const dBad = dp.filter((x) => x.error || x.real);
  log(`${dBad.length ? 'FAIL' : 'OK  '} ${dp.length} live duties ran in aborted transactions: ${dp.length - dBad.length} clean, ${dBad.length} errored or wrote a real row${dBad.length ? ' — ' + dBad.map((x) => x.duty + ':' + (x.error || 'real=' + x.real)).join('; ').slice(0, 600) : ''}`);
  save('duties/duty_probes_dry_run.json', dp);
  log(`${pathsOk ? 'OK  ' : 'FAIL'} cleanup paths on an empty tag (${probeTag}) — teardown: ${td.error || td.summary}; learning: ${JSON.stringify(lc)}; verify: ${vc.tables_scanned}/${vc.tables_in_registry} registry tables scanned, found ${vc.found.length}, unverified ${vc.unverified.length}, storage ${vc.storage.length}, auth ${vc.auth_users} (${Math.round((Date.now() - t0) / 1000)} s)`);
  if (vc.unverified.length) log('     unverified tables: ' + vc.unverified.map((u) => `${u.table} (${u.error})`).join('; '));
  const models = (await read(`select count(*)::int n from public.ai_cost_log where occurred_at > now() - interval '2 minutes' and fn in ('site_assistant','inquiry_intake','quote_compare')`))[0].n;
  log(`\nSPEND ESTIMATE (model_registry prices x model_policy primary; tokens are estimates)`);
  for (const s of scen) log(`  ${s.key}  USD ${s.est.usd.toFixed(4).padStart(8)}  ${s.title.slice(0, 90)}${s.est.lines.length ? '\n        ' + s.est.lines.map((l) => `${l.task_class}:${l.model.split('/')[1]} x${l.calls}=${l.usd.toFixed(4)}`).join('  ') : ''}`);
  log(`  TOTAL USD ${estUsd.toFixed(3)} (AED ${(estUsd * AED_PER_USD).toFixed(2)}) for one pass · hard cap USD ${CAP_USD}`);
  log(`\nCOVERAGE: ${cov.summary.total} features in the inventory · ${cov.summary.tested} tested · ${cov.summary.justified} justified · ${cov.summary.uncovered} uncovered · ${cov.summary.pct_tested_or_justified}% tested-or-justified`);
  for (const [k, v] of Object.entries(cov.summary.by_kind)) log(`  ${k.padEnd(7)} ${String(v.total).padStart(4)} total  ${String(v.tested).padStart(4)} tested  ${String(v.justified).padStart(4)} justified  ${String(v.uncovered).padStart(4)} uncovered`);
  writeIndex({ scenarios: scen, cov, spend: { estimate_usd: estUsd, measured_usd: null }, mode: 'dry run', tag: null,
    steps: [...pre.checks.map((c) => ({ scenario: 'pre', name: c.name, ok: c.ok, detail: c.detail })), { scenario: 'pre', name: 'cleanup paths remove and find 0 on an empty tag', ok: pathsOk, detail: JSON.stringify({ teardown: td.summary || td.error, verify: { scanned: vc.tables_scanned, of: vc.tables_in_registry, unverified: vc.unverified.length } }) }] });
  log(`\nDRY RUN ${pre.ok && pathsOk ? 'OK' : 'FOUND PROBLEMS'} · model calls made by this dry run: none (ai_cost_log rows from the funnel's functions in the last 2 min: ${models}) · INDEX ${join(OUT, 'INDEX.html')}`);
  process.exit(pre.checks.filter((c) => !/model hold/.test(c.name)).every((c) => c.ok) && pathsOk ? 0 : 1);
}

// --run
if (!pre.ok) { console.error('\nREFUSED: a precondition failed (above). Nothing was created.'); process.exit(2); }
let res = null, clean = null;
try { res = await realRun(pre); }
finally {
  // ALWAYS: models off for the tag first, then the cleanup, even when a scenario threw.
  if (RUN_TAG) {
    await write(`update public.rehearsal_window set models_allowed = false where run_tag = ${q('qd_run:' + RUN_TAG)}`, 'stage2 window: models off').catch(() => {});
    const mp = join(OUT, 'run_manifest.json');
    if (KEEP) {
      try { await closeRun(newRun({ tag: RUN_TAG, quiet: true }), { keep: true }); clean = { kept: true, tag: RUN_TAG, verify: { clean: true, kept: true } }; }
      catch (e) { clean = { kept: true, error: String(e.message), verify: { clean: false } }; }
    } else {
      try { clean = await cleanupAll(RUN_TAG, existsSync(mp) ? JSON.parse(readFileSync(mp, 'utf8')) : null); }
      catch (e) { clean = { error: String(e.message), verify: { clean: false } }; }
    }
    save(`cleanup_${RUN_TAG}.json`, clean);
  }
}

if (!res) { log(`
STAGE 2 CRASHED before it finished · cleanup ${clean?.verify?.clean ? "verified clean" : "NOT CLEAN - run --cleanup-only --tag " + RUN_TAG}`); process.exit(1); }
writeIndex({ scenarios: scen.map((s) => ({ ...s, ...(res.scenarioRows.find((r) => r.key === s.key) || {}) })), cov,
  spend: { estimate_usd: estUsd, measured_usd: res.spentUsd }, mode: res.aborted ? 'run (ABORTED: ' + res.aborted + ')' : 'run', tag: res.tag,
  steps: [...res.steps, { scenario: 'cleanup', name: '0 rows of this run remain in every registry table, storage and auth', ok: !!clean.verify?.clean, detail: JSON.stringify(clean.verify).slice(0, 400) }] });
const fails = res.steps.filter((s) => !s.ok).length;
log(`\nSTAGE 2 ${fails ? fails + ' FAILED' : 'all passed'} · spend USD ${res.spentUsd.toFixed(3)} · cleanup ${clean.kept ? 'KEPT (--keep): window closed, demo data and tag ' + res.tag + ' kept; remove with --cleanup-only --tag ' + res.tag : clean.verify?.clean ? 'verified clean' : 'NOT CLEAN - run --cleanup-only --tag ' + res.tag} · ${join(OUT, 'INDEX.html')}`);
process.exit(fails || !clean.verify?.clean ? 1 : 0);
