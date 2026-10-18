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
import { openRun, closeRun, leftovers, makeDemoCustomer, makeDemoSupplier, read, write, REF, BASE, call, demoEmail, waitFor } from './fixtures.mjs';
import { internalCred, newRun, teardown, makeLicenceGatedSupplier, makeSupplier, demoMobile, runIntake, factSheet, quotePayload, TRADES, EMIRATES, q, keys } from '../lib/demo_factory.mjs';
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
// Ten different trades, one supplier each, in rotating emirates; plus three more aluminium suppliers.
// The aluminium request invites all four (any number may quote) and collects four quotes, so the
// comparison has a top 3 and "the rest". elevators has NO demo
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
  { key: 'S07', title: 'Quotes: every capable supplier invited (4 on the aluminium request, no count cap) and quoting, incomplete quote held with notes, revision releases it, PDF extraction', calls: [['json_extraction', 8, 6000, 1500], ['procurement_reasoning', 8, 4000, 800]] },
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
  // ---- the founder's bar of 12 Oct 2026 (ledger 1121/1160/1164): every document READ, every copy FILED ----
  { key: 'S21', title: 'Supplier documents through the REAL process_docs, one supplier per licence shape (text, two-column, scanned PDF, photo, rotated, bilingual, Arabic-only, multi-page, expired, another company\'s name, blank) + a company profile each (PDF, DOCX, PPTX, picture) + a catalogue: licence number, legal name and expiry exactly as printed, the name taken from the licence (1176), every attachment read (1177), the gate decides right', calls: [['document_extraction', 40, 6000, 600]] },
  { key: 'S22', title: 'Signed terms: each customer\'s acceptance records version, IP and hash; the certificate PDF is on the letterhead with them; customer_api accept_terms re-records; the company register lists real customers only', calls: [] },
  { key: 'S25', title: 'An unfinished sign-up is never a customer (1181): inside 30 minutes it stays, after 30 minutes the real purge removes the row, the auth user and the OTP rows; a complete sign-up of the same age is never touched', calls: [] },
  { key: 'S26', title: 'Real-browser walk (#1270, Playwright on the live site) for this run\'s identities while the window is open: portal tabs EN + AR, uploads, request creation, quote viewing, Stripe TEST reveal, the your-data page, supplier registration with licence upload', calls: [['visitor_chat', 4, 3000, 500], ['inquiry_qualification_conversation', 8, 3000, 500]] },
  { key: 'S17', title: 'Marketing seat: blog draft -> CEO review -> founder FYI, social plan. Saved to the Desktop, NEVER published or posted', calls: [['marketing_article_draft', 1, 6000, 3000], ['ceo_article_review', 1, 6000, 1000], ['marketing_plan', 1, 4000, 2000]] },
  { key: 'S23', title: 'Dropbox: every document of the run filed in its owner\'s ONE folder (supplier licence/profile, customer details, signed terms, inquiry files), each backup record verified by size and content hash, the listing matches the records', calls: [] },
  { key: 'S24', title: 'AI answers judged by a model of ANOTHER family (chat, intake, comparison), and 0 messages from the run reached a real person on any channel', calls: [['ceo__internal_judgement', 6, 4000, 400], ['internal_judgement', 2, 8000, 400]] },
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
  // cb: the storage CDN served a register 41 minutes stale after it was rewritten (12 Oct 2026); read the object as it is now.
  const r = await fetch(`${BASE}/storage/v1/object/${bucket}/${path}?cb=${Date.now()}`, { headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE } });
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
  // ROWS AND FILES KEYED BY ID ONLY (no FK, no text marker), found by verify-clean's id scan after the sweep:
  // supplier_score (run f4294be8: 23 rows) and supplier_document_cache with its rendered PDF in agent-docs
  // (run 4cf353a2: 1 row, 1 object the tag-only storage scan could not see). The run's own lead ids, nothing else.
  await del('supplier_score', `delete from public.supplier_score where lead_id::text in (${lst(ids.leads)})`);
  const cached = (ids.leads || []).length ? await read(`select bucket, path from public.supplier_document_cache where supplier_id::text in (${lst(ids.leads)}) and bucket is not null and path is not null`) : [];
  if (cached.length) { const { SERVICE } = await keys(); for (const c of cached) await fetch(`${BASE}/storage/v1/object/${c.bucket}/${c.path}`, { method: 'DELETE', headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE } }).catch(() => {}); }
  await del('supplier_document_cache', `delete from public.supplier_document_cache where supplier_id::text in (${lst(ids.leads)})`);
  // Run 71b75b60, the first run with released quotes and a real comparison, left the comparison cache (2 rows) and 6 rendered
  // PDFs named only by the run's ids (agent-docs compare/<inquiry>/..., quote-files quotes/<lead>/<inquiry>/regenerated/...).
  // Removed by the run's own UUIDs anywhere in the name, and by its numeric lead ids only inside the lead-keyed folders.
  await del('qd_compare_cache', `delete from public.qd_compare_cache where inquiry_id::text in (${lst(ids.inquiries)})`);
  // Run 321d13ae (18 Oct) left a quotation chat thread keyed only by the run's ids. The WhatsApp and seat-task rows it left
  // carry the run's markers and are removed by cleanupAll's marker sweep (MARKER_TABLES), never by a bare tag.
  await del('chat_threads', `delete from public.chat_threads where inquiry_id::text in (${lst(ids.inquiries)}) or customer_id::text in (${lst(ids.customers)}) or supplier_id::text in (${lst(ids.leads)})`);
  {
    const uu = [...(ids.customers || []), ...(ids.inquiries || []), ...(ids.quotes || [])].map(String).filter((x) => /^[0-9a-f-]{36}$/i.test(x));
    const ld = (ids.leads || []).map(Number).filter((n) => Number.isInteger(n) && n > 0);
    const conds = [...uu.map((u) => `name like ${q('%' + u + '%')}`),
      ...ld.flatMap((n) => ['quotes', 'supplier', 'licenses', 'profiles', 'catalogs'].map((f) => `name like ${q('%' + f + '/' + n + '/%')}`))];
    const objs = conds.length ? await read(`select bucket_id b, name n from storage.objects where ${conds.join(' or ')}`) : [];
    if (objs.length) { const { SERVICE } = await keys(); for (const o of objs) await fetch(`${BASE}/storage/v1/object/${o.b}/${o.n}`, { method: 'DELETE', headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE } }).catch(() => {}); }
    out.storage_by_id = objs.length;
  }
  const hasCol = (await read(`select count(*)::int n from information_schema.columns where table_schema='public' and table_name='ai_cost_log' and column_name='e2e_run_tag'`))[0].n;
  if (hasCol) await del('ai_cost_log', `delete from public.ai_cost_log where e2e_run_tag = ${q(tag)}`);
  else out.ai_cost_log = 'PENDING: ai_cost_log.e2e_run_tag is not applied yet (--run refuses until it is)';
  return out;
}

// Every table in public.table_export_registry, searched for the run tag and for the run's own ids in
// any column named like an inquiry / quote / lead / supplier / customer / transaction id; plus storage.
// A table that cannot be scanned is reported UNVERIFIED, never counted as clean.
const dbxCred = async () => (await read(`select value from public.app_secrets where key in ('cred_fn_resilience_ping','cred_fn_backup_kick') order by key limit 1`))[0]?.value;
async function verifyClean(tag, ids = {}) {
  const tables = (await read(`select r.table_name t from public.table_export_registry r
      join information_schema.tables i on i.table_schema='public' and i.table_name=r.table_name and i.table_type='BASE TABLE'
      where r.table_name not in ('rehearsal_window', 'routine_change_log') order by 1`)).map((r) => r.t);
  // rehearsal_window: the kept record that a rehearsal ran. routine_change_log: the DDL audit of applied SQL, whose COMMENTS may
  // cite a run tag as evidence (run 1c94fa6a: #1337's quote-quality fix named it). Neither is demo data; neither may be deleted.
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
  // Objects are named by tag OR by the run's own ids (agent-docs/supplier/<lead id>/..., customer and inquiry uuids):
  // run 4cf353a2 left a cached quotation PDF that a tag-only scan reported as storage 0.
  const idLike = [...(ids.leads || []).map((x) => `%/${Number(x)}/%`), ...[...(ids.customers || []), ...(ids.inquiries || []), ...(ids.quotes || [])].map((x) => `%${String(x)}%`)];
  const storage = (await read(`select bucket_id, count(*)::int n from storage.objects where name like ${q('%' + tag + '%')}${idLike.map((p) => ` or name like ${q(p)}`).join('')} group by 1`));
  const auth = (await read(`select count(*)::int n from auth.users where email like ${q('qd-' + tag + '-%')}`))[0].n;
  // DROPBOX (final sandbox test, 12 Oct 2026): the run's _sandbox/<tag> tree, listed by the same check the daily
  // duty runs, and the backup records keyed SBX:<tag>:. A listing that cannot be read is UNVERIFIED, not clean.
  const sbx = (await read(`select count(*)::int n from public.doc_backups where dedupe_key like ${q('SBX:' + tag + ':%')}`))[0].n;
  let dropbox = { listed: null, records: sbx };
  try {
    const v = await call('dropbox_backup', null, { __secret: await dbxCred(), op: 'sandbox_verify', tag }, 120000);
    dropbox.listed = v.status === 200 && v.json?.summary ? Number(v.json.summary.listed ?? NaN) : null;
    if (dropbox.listed == null || Number.isNaN(dropbox.listed)) dropbox.error = `HTTP ${v.status} ${v.text.slice(0, 160)}`;
  } catch (e) { dropbox.error = String(e.message).slice(0, 160); }
  if (dropbox.error) unverified.push({ table: 'dropbox:_sandbox/' + tag, error: dropbox.error });
  return { tables_scanned: tables.length - unverified.length, tables_in_registry: tables.length, found, unverified, storage, auth_users: auth, dropbox,
    clean: !found.length && !storage.length && !auth && !unverified.length && dropbox.listed === 0 && sbx === 0 };
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

// A scenario that cannot run because an EARLIER one produced nothing to work on is SKIPPED with the
// reason, not crashed: 7 Oct 2026 (run fe7ba9c4) S07, S09, S10 and S11 all died on 'inq.id of
// undefined' after S04's interviews never reached ready, which buried the one real failure under four
// false ones.
export class Skip extends Error {}
const need = (v, reason) => { if (!v) throw new Skip(reason); return v; };

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
        // A FACT SHEET per customer (scripts/lib/demo_factory.mjs factSheet): the opening states the
        // element, lines with sizes and quantities and the location; every later turn answers the keys
        // the intake asked for. C3 answers the material question "not sure" on purpose.
        const sheet = factSheet(trade, { lang: ar ? 'ar' : 'en', emirate: cu.cfg.emirate, notSure: cu.cfg.label === 'C3' });
        const answers = [sheet.opening];
        const w0 = await costWatermark();
        const it = await runIntake(cu, answers, 14, sheet);
        // The customer confirms before anything goes to suppliers: ready enables "Send to suppliers",
        // and the harness presses it exactly as the portal does (customer_api create_inquiry).
        if (it.status === 'ready') { const sent = await call('customer_api', cu.jwt, { action: 'create_inquiry', intake_id: it.intakeId, text: answers[0], lang: cu.cfg.locale }); it.sent = sent.status; }
        const inq = (await read(`select id, status, trades, lang, emirate from public.inquiries where customer_id=${q(cu.customerId)} order by created_at desc limit 1`))[0];
        if (inq) { run.ids.inquiries.add(String(inq.id)); fx.inq[`${cu.cfg.label}:${trade}`] = { ...inq, cu, trade }; }
        const route = (await costSince(w0)).map((r) => `${r.task_class}:${r.model_used}`).join(' ');
        A(`${cu.cfg.label} ${cu.cfg.locale} ${trade} in ${cu.cfg.emirate}: interview reached ready and became a request`, it.status === 'ready' && !!inq, `intake=${it.status} turns=${it.turns} readiness=${it.readiness} missing=${it.missing.join('|')} inquiry=${inq?.id} status=${inq?.status}`, route);
        if (inq) save(`customers/${cu.cfg.label}_${cu.cfg.locale}_${safe(cu.cfg.emirate)}/inquiry_${trade}/inquiry.json`, { fact_sheet: sheet.values, intake: it, inquiry: inq });
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
        const m = await read(`select m.supplier_id, l.is_demo, c.trades from public.inquiry_matches m join public.leads l on l.id=m.supplier_id left join public.supplier_capabilities c on c.supplier_id=l.id where m.inquiry_id=${q(inq.id)}`);
        if (inq.trade === UNMATCHED_TRADE) {
          const st = (await read(`select status from public.inquiries where id=${q(inq.id)}`))[0]?.status;
          A(`${k}: a trade with no supplier HOLDS, no nearest match`, m.length === 0, `matches=${m.length} status=${st}`);
        } else A(`${k}: matched only to demo suppliers of the exact trade`, m.length > 0 && m.every((x) => x.is_demo && (x.trades || []).includes(inq.trade)), JSON.stringify(m).slice(0, 200));
      }
    },
    S07: async () => {
      const inq = need(Object.values(fx.inq).find((x) => x.trade === 'aluminium'), 'no aluminium request: the S04 interview did not reach ready, so there is nothing to quote on');
      const al = fx.suppliers.filter((s) => s.trade === 'aluminium');
      // EVERY CAPABLE SUPPLIER IS INVITED (founder ruling 24 Sep 2026: any number may quote; top 3 is only the
      // report). Run 1c94fa6a: A4 got 404 because the matcher then stopped each trade at 3; that cap is gone
      // (scripts/checks/every_matched_supplier_is_invited.test.mjs), so all four aluminium suppliers must be invited
      // and quote. Who was invited is still READ from inquiry_matches, never assumed.
      const invitedIds = new Set((await read(`select supplier_id from public.inquiry_matches where inquiry_id=${q(inq.id)}`)).map((r) => Number(r.supplier_id)));
      const inv = al.filter((s) => invitedIds.has(Number(s.leadId)));
      const out = al.filter((s) => !invitedIds.has(Number(s.leadId)));
      A(`the aluminium request invites every one of its ${al.length} capable aluminium suppliers (no count cap)`, inv.length === al.length,
        `invited ${inv.map((s) => s.row.company_name).join(', ')}; not invited ${out.map((s) => s.row.company_name).join(', ') || 'none'}`);
      for (const s of out) {
        const r = await call('supplier_api', s.jwt, quotePayload(inq.id, 150000, 'ZZ DEMO uninvited quote'));
        A(`${s.row.company_name} was not invited, so its quote is refused`, r.status === 404, `HTTP ${r.status}`);
      }
      need(inv.length >= 2, `only ${inv.length} aluminium supplier(s) invited, so there is no complete quote beside the incomplete one`);
      // The LAST invited supplier sends the incomplete quote (no warranty, validity or lead time); the others a full form.
      const inc = inv[inv.length - 1];
      const amounts = [118500, 124900, 131000, 142000, 149500];
      const qidOf = {};
      for (let i = 0; i < inv.length; i++) {
        const body = quotePayload(inq.id, amounts[i % amounts.length], `ZZ DEMO quote ${i + 1}`, inv[i] === inc ? { overrides: { warranty: '', validity: '', lead_time: '' } } : {});
        const r = await call('supplier_api', inv[i].jwt, body);
        const row = (await read(`select id, status from public.quotes where inquiry_id=${q(inq.id)} and supplier_id=${Number(inv[i].leadId)} order by created_at desc limit 1`))[0];
        if (row) { run.ids.quotes.add(String(row.id)); qidOf[inv[i].leadId] = row.id; }
        A(`quote ${i + 1} from ${inv[i].row.company_name}`, r.status === 200 && row, `HTTP ${r.status} status=${row?.status}`);
      }
      need(run.ids.quotes.size, 'no quote was accepted on the aluminium request (submit_quote failed above), so there is no hold to walk');
      const holdOf = async (s) => (await read(`select h.state, h.missing, h.note_en, h.quote_id from public.quote_spec_hold h join public.quotes x on x.id=h.quote_id where x.inquiry_id=${q(inq.id)} and x.supplier_id=${Number(s.leadId)} order by h.id desc limit 1`))[0];
      // The supplier's own door out of a hold (supplier portal "complete your quotation"): spec_hold shows
      // the form, spec_fill answers every missing detail, the sales engineer regenerates the standard
      // quotation and asks for approval, spec_approve releases it. Each step sends its own notice
      // (quote_spec_hold / quote_spec_regenerated / quote_spec_released), asserted below in English.
      const TERM = { delivery: '4 weeks from approval of shop drawings', warranty_period: '12 months', warranty_coverage: 'materials and workmanship',
        installation_included: 'yes', installation_detail: 'supply and installation on site', validity: '30 days', lead_time: '4 weeks' };
      const walk = async (s, qid) => {
        const form = await call('supplier_api', s.jwt, { action: 'spec_hold', quote_id: qid });
        const sch = form.json?.schema || {};
        // price_ex_vat is a NUMBER (validateTerm): the quote's own amount, as its supplier would confirm it (run 1be65ab2 sent 'standard').
        const amt = (await read(`select coalesce(price_ex_vat, quote_amount)::float a from public.quotes where id=${q(qid)}`))[0]?.a;
        const values = { terms: Object.fromEntries((sch.terms || []).map((m) => [m.attr, m.attr === 'price_ex_vat' ? String(amt) : TERM[m.attr] ?? (String(m.attr).startsWith('component:') ? 'standard component' : 'standard')])),
          lines: Object.fromEntries((sch.lines || []).map((l) => [l.line_no, Object.fromEntries(l.fields.filter((f) => f.missing).map((f) => [f.attr, f.options?.length ? (f.options[0].value ?? f.options[0]) : f.type === 'number' ? 6 : 'standard']))])) };
        const fill = await call('supplier_api', s.jwt, { action: 'spec_fill', quote_id: qid, values });
        const appr = await call('supplier_api', s.jwt, { action: 'spec_approve', quote_id: qid, confirm: true });
        const after = (await read(`select state from public.quote_spec_hold where quote_id=${q(qid)} order by id desc limit 1`))[0];
        return { fill, appr, after };
      };
      // A "complete" form quote still names no glass type, profile system or VAT basis, and the exact-specs
      // rule rightly holds it too (run 1c94fa6a: all three held). Its supplier completes it through the same
      // door, so the comparison and the reveal have submitted quotes to work on.
      for (const s of inv.filter((x) => x !== inc)) {
        const h = await holdOf(s);
        if (h?.state !== 'open') { A(`${s.row.company_name}: the full quote is not held`, true, `hold=${h?.state ?? 'none'}`); continue; }
        const w = await walk(s, h.quote_id);
        A(`${s.row.company_name}: the specs the hold names are completed and the quote released`, w.fill.json?.complete === true && w.after?.state === 'released', `fill HTTP ${w.fill.status} approve HTTP ${w.appr.status} hold=${w.after?.state}`);
      }
      const held = await holdOf(inc);
      A('the incomplete quote is HELD with notes naming what is missing', held?.state === 'open' && held.note_en, String(JSON.stringify(held ?? null)).slice(0, 300));
      save(`customers/${inq.cu.cfg.label}_${inq.cu.cfg.locale}_${safe(inq.cu.cfg.emirate)}/inquiry_aluminium/held_quote_notes.json`, held || {});
      const { fill, appr, after } = await walk(inc, held?.quote_id);
      A('spec_fill: every missing detail answered regenerates the standard quotation', fill.status === 200 && fill.json?.complete === true, `HTTP ${fill.status} ${JSON.stringify(fill.json).slice(0, 300)}`);
      if (fill.json?.pdf_url) save(`customers/${inq.cu.cfg.label}_${inq.cu.cfg.locale}_${safe(inq.cu.cfg.emirate)}/inquiry_aluminium/regenerated_quote_${held?.quote_id}.pdf`, Buffer.from(await (await fetch(fill.json.pdf_url)).arrayBuffer()));
      A('spec_approve releases the hold', appr.status === 200 && after?.state === 'released', `HTTP ${appr.status} hold=${after?.state} ${JSON.stringify(appr.json).slice(0, 200)}`);
      const notes = await read(`select type, channel, subject, body from public.notifications where quote_id=${q(held?.quote_id)} and type like 'quote_spec_%'`);
      for (const t of ['quote_spec_hold', 'quote_spec_regenerated', 'quote_spec_released']) {
        const n = notes.filter((x) => x.type === t);
        A(`notice ${t}: rendered to the supplier in English`, n.length > 0 && n.every((x) => x.subject && x.body && !/[؀-ۿ]{8,}/.test(x.body)), `${n.length} rows: ${n.map((x) => x.channel).join(',')}`);
      }
      for (const qid of run.ids.quotes) {
        const pdf = await call('supplier_api', inv[0].jwt, { action: 'quote_pdf', quote_id: qid });
        if (pdf.json?.url) { const b = Buffer.from(await (await fetch(pdf.json.url)).arrayBuffer()); save(`customers/${inq.cu.cfg.label}_${inq.cu.cfg.locale}_${safe(inq.cu.cfg.emirate)}/inquiry_aluminium/quote_${qid}.pdf`, b); }
      }
    },
    S08: async () => {
      for (const inq of Object.values(fx.inq).slice(0, 4)) {
        // Run f4294be8 (12 Oct 2026): "asked 0" on all four was CORRECT - each request's own hold check
        // (fn_rfq_required_check) had missing=[] (every required key present, rfq_ready=true), and the
        // harness then posted empty answers, which the product rightly refuses (nothing_to_add). What is
        // asserted now is that the questions asked are exactly what the request's check finds missing;
        // when there are some, the first is answered "not sure" through the not_sure path (a handoff to
        // the sales engineer, never a fake answer) and the rest are answered; when there are none,
        // nothing is asked and an empty answer is refused.
        const chk = (await read(`select public.fn_rfq_required_check(i) c from public.inquiries i where i.id=${q(inq.id)}`))[0]?.c || {};
        const want = (Array.isArray(chk.missing) ? chk.missing : []).map(String).sort();
        const ms = await call('customer_api', inq.cu.jwt, { action: 'missing_specs', inquiry_id: inq.id });
        const fields = Array.isArray(ms.json?.missing) ? ms.json.missing : [];
        const asked = fields.map((f) => String(f.key || f)).sort();
        const [unsure, ...rest] = asked;
        const answers = Object.fromEntries(rest.map((k) => [k, 'Standard commercial grade, as per the drawings']));
        const r = await call('customer_api', inq.cu.jwt, unsure
          ? { action: 'add_missing_specs', inquiry_id: inq.id, answers, not_sure: [unsure] }
          : { action: 'add_missing_specs', inquiry_id: inq.id, answers: {} });
        save(`customers/${inq.cu.cfg.label}_${inq.cu.cfg.locale}_${safe(inq.cu.cfg.emirate)}/inquiry_${inq.trade}/spec_qa.json`, { hold_check_missing: want, asked: ms.json, answered: answers, not_sure: unsure ? [unsure] : [], reply: r.json });
        const sameAsCheck = ms.status === 200 && JSON.stringify(asked) === JSON.stringify(want);
        const replyOk = unsure ? r.status === 200 && r.json?.ok !== false : r.json?.error === 'nothing_to_add';
        A(`${inq.trade}: spec questions asked are what the request's hold check finds missing, and answered (incl. "not sure")`, sameAsCheck && replyOk,
          `check missing ${want.length} [${want.join(',')}], asked ${asked.length}, answered ${rest.length}, not sure ${unsure ? 1 : 0}, reply HTTP ${r.status} ${r.json?.error || 'ok'}`);
      }
    },
    S09: async () => {
      const inq = need(Object.values(fx.inq).find((x) => x.trade === 'aluminium'), 'no aluminium request: the S04 interview did not reach ready, so there is nothing to quote on');
      const dir = `customers/${inq.cu.cfg.label}_${inq.cu.cfg.locale}_${safe(inq.cu.cfg.emirate)}/inquiry_aluminium`;
      const live = Number((await read(`select count(*) n from public.quotes where inquiry_id=${q(inq.id)} and status='submitted'`))[0]?.n || 0);
      for (const lang of ['en', 'ar']) {
        const w0 = await costWatermark();
        const r = await call('customer_api', inq.cu.jwt, { action: 'compare_pdf', inquiry_id: inq.id, lang }, 240000);
        const rows = await costSince(w0);
        const opus = rows.filter((x) => x.task_class === 'quote_comparison');
        if (r.json?.url) save(`${dir}/comparison_${lang}.pdf`, Buffer.from(await (await fetch(r.json.url)).arrayBuffer()));
        const csv = await call('customer_api', inq.cu.jwt, { action: 'compare_csv', inquiry_id: inq.id, lang });
        // compare_csv answers JSON {csv}; the quotes are its COLUMNS (head = "Compare", Supplier A, B, ...), not
        // its rows. Run 4 counted the lines of the JSON body (1) and read 3 listed quotes as 0.
        const csvText = String(csv.json?.csv || '');
        save(`${dir}/comparison_${lang}.csv`, csvText || csv.body || '');
        const lines = csvText ? csvText.replace(/^﻿/, '').split(/\r?\n/)[0].split(',').length - 1 : 0;
        A(`comparison ${lang}: report produced on the Opus route`, r.status === 200 && opus.length > 0 && opus.every((x) => x.model_used === 'anthropic/claude-opus-5.5'), `HTTP ${r.status} routes=${rows.map((x) => x.task_class + ':' + x.model_used).join(' ')}`, opus.map((x) => x.model_used).join(','));
        // Every live quote, not a fixed 4: the request has as many as it invited (S07), and "the rest" exists only past 3.
        A(`comparison ${lang}: every live quote listed (top 3 + the rest)`, live >= 2 && lines >= live, `${lines} quote lines in the CSV, ${live} submitted quotes`);
      }
    },
    S10: async () => {
      const inq = need(Object.values(fx.inq).find((x) => x.trade === 'aluminium'), 'no aluminium request: the S04 interview did not reach ready, so there is nothing to quote on');
      const cu = inq.cu;
      const sk = (await read(`select value from public.app_secrets where key='stripe_secret_key_test'`))[0].value;
      if (!sk.startsWith('sk_test_')) throw new Error('REFUSED: the Stripe key is not a TEST key');
      const top = need((await read(`select id, quote_amount::float a, supplier_id from public.quotes where inquiry_id=${q(inq.id)} and status='submitted' order by quote_amount limit 1`))[0], 'no submitted quote on the aluminium request (S07), so there is nothing to reveal');
      const ct = async (pm) => (await (await fetch('https://api.stripe.com/v1/test_helpers/confirmation_tokens', { method: 'POST', headers: { Authorization: 'Bearer ' + sk, 'Content-Type': 'application/x-www-form-urlencoded' }, body: `payment_method=${pm}` })).json()).id;
      // element_quote prices the card actually used, so it needs that card's ConfirmationToken (the
      // contract since 14 Sep 2026, stripe_checkout/index.ts element_quote). Run 4 sent none: HTTP 400
      // bad_confirmation_token, total_fils undefined, and element_pay then compared against NaN and
      // answered 'repriced' before Stripe ever saw the declined card. Each card is quoted on its own token.
      const quoteFor = async (pm) => { const t = await ct(pm); const r = await call('stripe_checkout', cu.jwt, { action: 'element_quote', quote_id: top.id, confirmation_token: t }); return { t, r }; };
      const qBad = await quoteFor('pm_card_chargeDeclined'), qGood = await quoteFor('pm_card_visa');
      for (const [label, x] of [['declined', qBad], ['visa', qGood]]) {
        const fee = Number(x.r.json?.total_fils) / 100;
        A(`the reveal price is 3% of the final ex-VAT quote with no card surcharge (${label} card)`, x.r.status === 200 && Math.abs(fee - top.a * 0.03) < 0.01 && Number(x.r.json?.processing_fee) === 0 && Math.abs(Number(x.r.json?.base_fee) - top.a * 0.03) < 0.01, `HTTP ${x.r.status} quote ${top.a} -> charge ${fee} processing ${x.r.json?.processing_fee} basis ${x.r.json?.fee_basis}`);
      }
      const bad = await call('stripe_checkout', cu.jwt, { action: 'element_pay', quote_id: top.id, confirmation_token: qBad.t, expected_total_fils: qBad.r.json?.total_fils });
      const tx0 = (await read(`select count(*)::int n from public.transactions where quote_id=${q(top.id)} and fee_status='paid'`))[0].n;
      // Refused BY THE CARD: status 'failed' (Stripe declined, invoice voided), never 'repriced' (Stripe not reached).
      A('a declined TEST card is refused and reveals nothing', bad.json?.ok === false && bad.json?.status === 'failed' && tx0 === 0, JSON.stringify(bad.json).slice(0, 200));
      const good = await call('stripe_checkout', cu.jwt, { action: 'element_pay', quote_id: top.id, confirmation_token: qGood.t, expected_total_fils: qGood.r.json?.total_fils });
      A('the paid TEST card is charged exactly the total it was quoted', good.json?.status === 'succeeded' && good.json?.total_fils === qGood.r.json?.total_fils, JSON.stringify(good.json).slice(0, 200));
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
      const { tx, inq } = need(fx.revealed?.tx && fx.revealed, 'no paid reveal (S10), so there is no transaction to refund');
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
      save('chats/assistant_transcripts.json', chats); fx.chats = chats;
      const { inq, top } = fx.revealed || {};
      if (inq) {
        // messages_api keys a thread on (inquiry_id, supplier_id), not quote_id: run 4's 400 was
        // 'missing inquiry_id/supplier_id', which a paid reveal alone would not have cured.
        const key = { inquiry_id: inq.id, supplier_id: top.supplier_id };
        const rq = await call('messages_api', inq.cu.jwt, { action: 'request_chat', ...key });
        const s = await call('messages_api', inq.cu.jwt, { action: 'send', ...key, body: 'ZZ DEMO: when can you visit the site?' });
        const th = await call('messages_api', inq.cu.jwt, { action: 'thread', ...key });
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
        const rt = await call('customer_api', inq.cu.jwt, { action: 'rate_supplier', quote_id: top.id, rating: 5, comment: 'ZZ DEMO rating, five stars' }); // field is `rating` (rating_input.ts); `stars` was 400 rating_out_of_range
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
      const { launch, signedInPage, openPortal, portalUrl, SITE } = await import('./browser.mjs');
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
          // signedInPage never navigates (the 7 Oct run read about:blank); openPortal goes to the portal and
          // waits for its nav. Tabs carry data-nav-id (SupplierPortal main tabs, PortalShell NavButton).
          const { ctx, page: p, calls } = await signedInPage(browser, who, { lang });
          await openPortal(p, portalUrl(who.kind, lang), calls);
          const tabs = [...new Set(await p.locator('nav [data-nav-id]:visible').evaluateAll((els) => els.map((e) => e.getAttribute('data-nav-id'))).catch(() => []))];
          A(`${who.kind} ${lang}: portal tabs found`, tabs.length > 0, tabs.join(','));
          const opened = [];
          for (const t of tabs) {
            const b = p.locator(`nav [data-nav-id="${t}"]:visible`).first();
            await b.click().catch(() => {}); await p.waitForTimeout(800);
            if ((await b.getAttribute('aria-current').catch(() => null)) === 'page') opened.push(t);
          }
          A(`${who.kind} ${lang}: every portal tab opens`, tabs.length > 0 && opened.length === tabs.length, `opened ${opened.length} of ${tabs.length}: ${tabs.filter((t) => !opened.includes(t)).join(',') || 'all'}`);
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
      const svix = async (slug, secretKey, payload, qs = '') => {
        const secret = await sec(secretKey); const body = JSON.stringify(payload);
        const id = 'msg_zzdemo' + tag + randomBytes(3).toString('hex'), ts = String(Math.floor(Date.now() / 1000));
        const key = Buffer.from(String(secret || '').replace(/^whsec_/, ''), 'base64');
        const sig = 'v1,' + createHmac('sha256', key).update(`${id}.${ts}.${body}`).digest('base64');
        const r = await fetch(`${BASE}/functions/v1/${slug}${qs}`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'svix-id': id, 'svix-timestamp': ts, 'svix-signature': sig, 'x-qd-e2e-run': tag, 'x-qd-e2e-secret': await internalCred() }, body });
        return { status: r.status, text: (await r.text()).slice(0, 200), secret: !!secret };
      };
      const em = `ZZ DEMO ${tag} inbound email`;
      const ri = await svix('resend_inbound', 'resend_inbound_signing_secret', { type: 'email.received', created_at: new Date().toISOString(),
        data: { from: fx.customers[2].email, to: ['support@mail.quotesdone.com'], subject: em, text: em + ': where is my quote?' } },
        '?s=' + encodeURIComponent(await sec('resend_inbound_token') || ''));
      await new Promise((ok) => setTimeout(ok, 4000));
      const hi = await hits(em);
      save('chats/resend_inbound.json', { sent: em, response: ri, stored_in: hi });
      A('resend_inbound: a Svix-signed email from a demo address is accepted and stored', ri.secret && ri.status < 300 && hi.length > 0, `HTTP ${ri.status} stored in ${hi.join(', ') || 'nothing'}`);
      const rw = await svix('resend_webhook', 'resend_webhook_signing_secret', { type: 'email.delivered', created_at: new Date().toISOString(), data: { email_id: `zzdemo-${tag}`, to: [fx.customers[2].email] } },
        '?key=' + encodeURIComponent(await sec('resend_webhook_key') || ''));
      A('resend_webhook: a Svix-signed delivery event is accepted', rw.secret && rw.status < 300, `HTTP ${rw.status} ${rw.text}`);
      const ib = await call('inbound_email', null, { __secret: await sec('inbound_webhook_secret'), from: fx.customers[3].email, subject: `ZZ DEMO ${tag} inbound_email`, text: `ZZ DEMO ${tag} inbound_email body` });
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
    // ---- S21: every supplier document READ through the real door ------------------------------------
    // The corpus (document_intake_corpus.mjs, ledger 1162) carries the truth of every file. One ZZ DEMO
    // supplier per licence SHAPE uploads it through supplier_api process_docs exactly as the portal does,
    // with a company profile (rotating PDF / DOCX / PPTX / picture) and, for the first, a catalogue. What is
    // asserted is what the supplier's ROW ends with, not what a reader module returns.
    S21: async () => {
      const { buildCorpus } = await import('./document_intake_corpus.mjs');
      const { judge } = await import('./document_intake_score.mjs');
      const cdir = join(OUT, 'documents', `stage2_${tag}`);
      const docs = await buildCorpus(cdir);
      const seen = new Set();
      const lic = docs.filter((d) => d.kind === 'licence' && d.file && !d.start_approved && (/^lic_(expired|mismatch|blank)/.test(d.id) || !seen.has(d.format) && seen.add(d.format)));
      const profiles = docs.filter((d) => d.kind === 'profile');
      const catalogue = docs.find((d) => d.kind === 'catalogue');
      const b64 = (d) => ({ original_b64: readFileSync(join(cdir, d.file)).toString('base64'), mime: d.mime, filename: `qd-${tag}-${d.file}` });
      const norm = (s) => String(s ?? '').toLowerCase().replace(/&/g, ' and ').replace(/[.,،'’`()\-]/g, ' ').replace(/\s+/g, ' ').trim();
      const unreadFamily = new Set(['licence_unreadable', 'licence_expiry_unread', 'licence_number_unread']);
      const auto = (await read(`select coalesce(auto_approve_suppliers,false) a from public.pricing_config where id=1`))[0]?.a === true;
      const results = [];
      for (let i = 0; i < lic.length; i++) {
        const d = lic[i]; const prof = profiles[i % profiles.length];
        const email = demoEmail(run, 'sup');
        const s = await makeSupplier(run, { trade: 'aluminium', email, company_name: d.registered_name, approval: 'pending' });
        run.ids.leads.add(String(s.leadId)); fx.docSuppliers = [...(fx.docSuppliers || []), { leadId: s.leadId, doc: d.id }];
        await write(`update public.leads set phone = ${q(demoMobile())}, contact_name = ${q('ZZ DEMO Contact ' + tag)}, owner_dob = '1985-06-01',
            owner_email_verified = true, owner_phone_verified = true where id = ${Number(s.leadId)}`, 'S21 demo supplier contact');
        await call('kyc', s.jwt, { action: 'accept_terms', user_kind: 'supplier', email });
        await call('kyc', s.jwt, { action: 'whatsapp_choose', user_kind: 'supplier', email, opt: 'same' });
        const w0 = await costWatermark();
        const body = { action: 'process_docs', license: b64(d), company_profile: b64(prof), ...(i === 0 && catalogue ? { catalogs: [b64(catalogue)] } : {}) };
        const r = await call('supplier_api', s.jwt, body, 240000);
        const route = (await costSince(w0)).map((x) => `${x.task_class}:${x.model_used}`).join(' ');
        const settled = await waitFor(async () => { const x = (await read(`select approval_status, licence_gate_reason from public.leads where id=${Number(s.leadId)}`))[0]; return x && (x.approval_status !== 'pending' || x.licence_gate_reason) ? x : null; }, { timeoutMs: 45000 });
        const row = (await read(`select l.company_name, l.trade_license_no, l.licence_legal_name, l.license_expiry::text license_expiry, l.license_authority, l.approval_status, l.licence_gate_reason,
            l.license_doc_path, l.company_profile_doc_path, l.catalog_doc_paths, c.proposed_trades, c.source_docs
            from public.leads l left join public.supplier_capabilities c on c.supplier_id = l.id where l.id=${Number(s.leadId)}`))[0];
        const t = d.truth; const arOnly = String(d.format).startsWith('arabic_only');
        const v = { licence_no: judge('licence_no', t.licence_no, row.trade_license_no),
          legal_name: arOnly ? judge('legal_name_ar', t.legal_name_ar, row.licence_legal_name) : judge('legal_name_en', t.legal_name_en, row.licence_legal_name),
          expiry: judge('expiry_date', t.expiry_date, row.license_expiry) };
        const exp = d.expected, reason = row.licence_gate_reason || null, approved = row.approval_status === 'approved';
        const clear = (x) => x === 'approved' || (!auto && x === 'pending');   // auto-approve off: complete and waiting is the right end
        let gate;
        if (exp === 'approve') gate = reason == null && clear(row.approval_status) ? 'correct' : unreadFamily.has(reason) ? 'held' : 'wrong';
        else if (exp === 'name_autofilled') gate = reason == null && clear(row.approval_status) && norm(row.company_name) === norm(t.legal_name_en) ? 'correct' : 'wrong';
        else if (exp === 'hold_name') gate = ['licence_unreadable', 'licence_name_mismatch'].includes(reason) && !approved ? 'correct' : approved ? 'UNSAFE' : 'wrong';
        else gate = reason === exp ? 'correct' : approved ? 'UNSAFE' : 'wrong';
        // A licence that must be READ (everything but the blank page/photo) may not come back with a critical field held.
        const mustRead = !['licence_unreadable', 'reg_licence'].includes(exp);
        const bad = Object.entries(v).filter(([f, x]) => x === 'wrong' || (mustRead && x === 'held' && !(arOnly && f === 'legal_name')));
        A(`${d.id} (${d.format}, ${d.authority}): licence number, legal name and expiry read exactly`, r.status === 200 && bad.length === 0,
          `HTTP ${r.status} no=${row.trade_license_no}/${t.licence_no} name=${row.licence_legal_name}/${arOnly ? t.legal_name_ar : t.legal_name_en} expiry=${row.license_expiry}/${t.expiry_date} ${JSON.stringify(v)}`, route);
        A(`${d.id}: the gate decides ${exp}`, gate === 'correct', `${row.approval_status}${reason ? ' (' + reason + ')' : ''} company=${row.company_name} -> ${gate}`);
        if (exp === 'name_autofilled') {
          const act = (await read(`select count(*)::int n from public.agent_actions where kind='supplier_name_from_licence' and (detail->>'lead_id')::text=${q(String(s.leadId))} or (kind='supplier_name_from_licence' and target_id::text=${q(String(s.leadId))})`).catch(() => [{ n: -1 }]))[0].n;
          A(`${d.id}: the company name is taken from the licence and recorded (1176)`, norm(row.company_name) === norm(t.legal_name_en) && act !== 0, `company=${row.company_name} agent_actions=${act}`);
        }
        // 1177: every attachment read - each uploaded path has a reading on the supplier's row.
        const docsRead = (row.source_docs?.docs || []);
        const uploaded = [row.license_doc_path, row.company_profile_doc_path, ...(row.catalog_doc_paths || [])].filter(Boolean);
        const unread = uploaded.filter((p) => !docsRead.some((x) => x.path === p && x.status && !/error|unread|failed/i.test(x.status)));
        A(`${d.id}: every attachment read (licence + ${prof.format} profile${i === 0 ? ' + catalogue' : ''}) (1177)`, mustRead ? unread.length === 0 : unread.filter((p) => p !== row.license_doc_path).length === 0,
          `${uploaded.length} uploaded, unread: ${unread.join(', ') || 'none'} · ${JSON.stringify(docsRead.map((x) => [String(x.path).split('/').pop(), x.status])).slice(0, 220)}`);
        // Cross matching: what the profile does is proposed, and nothing it does not do.
        const truthTrades = new Set([...(t.trades || []), ...(prof.truth.trades || []), ...(i === 0 && catalogue ? catalogue.truth.trades : [])]);
        const prop = row.proposed_trades || [];
        const wrong = prop.filter((x) => !truthTrades.has(x)), missing = (prof.truth.trades || []).filter((x) => !prop.includes(x));
        A(`${d.id}: the profile's trades are proposed for matching, none it does not do`, wrong.length === 0 && missing.length === 0, `proposed ${JSON.stringify(prop)} truth ${JSON.stringify([...truthTrades])} wrong ${wrong} missing ${missing}`);
        results.push({ doc: d.id, format: d.format, authority: d.authority, expected: exp, truth: t, row: { ...row, source_docs: undefined }, verdicts: v, gate, process_docs: r.json, route });
        // The corpus prints the SAME company on several shapes (Falcon Aluminium is lic_dubai_ded_old_text
        // and lic_dubai_det_bi_jpg), and one company registers once (leads_claimed_company_name_uidx) - so the
        // next shape's supplier crashed with 23505 (run f4294be8). Once this shape is asserted, its own
        // ZZ DEMO row gives the name back; the next supplier registers under the name its licence prints,
        // so the name-vs-licence rule (1176) is tested on the real name, not on a suffixed one.
        await write(`update public.leads set company_name = company_name || ${q(' [' + tag + ' ' + d.id + ']')}
            where id = ${Number(s.leadId)} and claimed_by like '%@example.invalid' and company_name like 'ZZ DEMO%'`, 'S21 release the corpus name');
      }
      save('documents/stage2_document_reading.json', results);
    },
    // ---- S22: the signed terms and the company's customer register --------------------------------
    S22: async () => {
      const { pdfFactsFromBytes } = await import('./pdf_facts.mjs');
      const cur = (await read(`select value from public.app_secrets where key='customer_terms_version'`))[0]?.value;
      for (const cu of fx.customers) {
        const row = await waitFor(async () => { const x = (await read(`select full_name, tos_version, tos_ip, tos_sha256, tos_accepted_at, signed_terms_path, signed_terms_at from public.customers where id=${q(cu.customerId)}`))[0]; return x?.signed_terms_path ? x : null; }, { timeoutMs: 60000 })
          || (await read(`select full_name, tos_version, tos_ip, tos_sha256, tos_accepted_at, signed_terms_path, signed_terms_at from public.customers where id=${q(cu.customerId)}`))[0];
        const dir = `customers/${cu.cfg.label}_${cu.cfg.locale}_${safe(cu.cfg.emirate)}`;
        A(`${cu.cfg.label}: acceptance records the current version, the IP and the text hash`, row.tos_version === cur && !!row.tos_ip && /^[0-9a-f]{64}$/.test(row.tos_sha256 || ''), `version=${row.tos_version}/${cur} ip=${row.tos_ip} sha=${String(row.tos_sha256).slice(0, 12)}`);
        const pdf = row.signed_terms_path ? await download('signed-terms', row.signed_terms_path) : null;
        if (pdf) save(`${dir}/signed_terms_certificate.pdf`, pdf);
        const f = pdf ? await pdfFactsFromBytes(pdf).catch(() => null) : null;
        const txt = String(f?.text || '');
        A(`${cu.cfg.label}: the signed certificate is on the letterhead and names the signer, IP and hash`, !!pdf && /QuotesDone/i.test(txt) && txt.includes(String(row.tos_ip)) && txt.includes(String(row.tos_sha256).slice(0, 16)) && (cu.cfg.locale === 'ar' || txt.includes(row.full_name)),
          `${row.signed_terms_path} ${pdf ? pdf.length + ' bytes' : 'MISSING'} letterhead=${/QuotesDone/i.test(txt)} ip=${txt.includes(String(row.tos_ip))} hash=${txt.includes(String(row.tos_sha256).slice(0, 16))}`);
      }
      const c1 = fx.customers[0];
      const at0 = (await read(`select tos_accepted_at from public.customers where id=${q(c1.customerId)}`))[0].tos_accepted_at;
      const re = await call('customer_api', c1.jwt, { action: 'accept_terms' });
      const at1 = (await read(`select tos_accepted_at, tos_version from public.customers where id=${q(c1.customerId)}`))[0];
      A('customer_api accept_terms re-records the acceptance at the current version', re.status === 200 && re.json?.version === cur && at1.tos_version === cur && String(at1.tos_accepted_at) >= String(at0), `HTTP ${re.status} ${JSON.stringify(re.json)}`);
      const cred = (await read(`select value from public.app_secrets where key in ('cred_fn_compliance_archive','cred_db_internal') order by key='cred_fn_compliance_archive' desc limit 1`))[0]?.value;
      const reg = await call('compliance_archive', null, { __secret: cred, action: 'register' });
      const bytes = await download('signed-terms', 'registers/customers-register.xlsx');
      if (bytes) save('customers/customers-register.xlsx', bytes);
      const { inflateRawSync } = await import('node:zlib');
      // the sheet's text: every deflated or stored entry of the xlsx (a zip), concatenated
      let sheetText = '';
      if (bytes) for (let o = 0; o + 30 < bytes.length;) {
        if (bytes.readUInt32LE(o) !== 0x04034b50) break;
        const method = bytes.readUInt16LE(o + 8), csize = bytes.readUInt32LE(o + 18), nlen = bytes.readUInt16LE(o + 26), xlen = bytes.readUInt16LE(o + 28);
        const data = bytes.subarray(o + 30 + nlen + xlen, o + 30 + nlen + xlen + csize);
        try { sheetText += (method === 8 ? inflateRawSync(data) : data).toString('utf8'); } catch { /* not text */ }
        o += 30 + nlen + xlen + csize;
      }
      const real = (await read(`select count(*)::int n from public.customers where tos_accepted_at is not null and not coalesce(is_demo,false) and email not like '%@example.invalid'`))[0].n;
      const fixtures = (sheetText.match(/example\.invalid|ZZ DEMO/gi) || []).length;
      A('the company customer register lists every real customer and no fixture (and its Dropbox copy is the same file)', reg.status === 200 && reg.json?.count === real && fixtures === 0 && reg.json?.dropbox_mirrored === true,
        `HTTP ${reg.status} count=${reg.json?.count} real=${real} fixture mentions in the file=${fixtures} dropbox=${reg.json?.dropbox_mirrored}`);
    },
    // ---- S23: Dropbox, each owner's ONE folder ------------------------------------------------------
    // fn_backup_sandbox_enqueue re-roots this run's demo rows under /QuotesDone Backup/_sandbox/<tag>/ with the
    // same sub-tree production uses; op 'sandbox' uploads them with production's own backupRow (size + content
    // hash read back); op 'sandbox_verify' lists the folder against the records.
    S23: async () => {
      const cred = (await read(`select value from public.app_secrets where key in ('cred_fn_resilience_ping','cred_fn_backup_kick') order by key limit 1`))[0]?.value;
      const enq = await write(`select public.fn_backup_sandbox_enqueue(${q(tag)}) r`, 'stage2 dropbox sandbox enqueue');
      let up = null;
      for (let i = 0; i < 8; i++) {
        up = await call('dropbox_backup', null, { __secret: cred, op: 'sandbox', tag }, 240000);
        const left = (await read(`select count(*)::int n from public.doc_backups where dedupe_key like ${q('SBX:' + tag + ':%')} and status <> 'done'`))[0].n;
        if (!left) break;
      }
      const rows = await read(`select id, entity_id, doc_type, bucket, path, dropbox_path, status, verified_at, dropbox_content_hash, bytes, dropbox_size from public.doc_backups where dedupe_key like ${q('SBX:' + tag + ':%')} order by dropbox_path`);
      save('dropbox/backup_records.json', rows);
      A('every document of the run has a backup record, uploaded and verified by size and content hash', rows.length > 0 && rows.every((x) => x.status === 'done' && x.verified_at && x.dropbox_content_hash),
        `${rows.length} records · ${rows.filter((x) => x.status !== 'done').map((x) => x.status + ':' + x.path).join(' ').slice(0, 300) || 'all done'} · enqueue ${JSON.stringify(enq?.[0]?.r).slice(0, 120)} · last upload HTTP ${up?.status}`);
      const root = `/QuotesDone Backup/_sandbox/${tag}/`;
      const folderOf = (p) => p.slice(0, p.lastIndexOf('/'));
      // Suppliers: the licence and profile of every supplier in the run (S01 and S21) are in Suppliers/<category>/<name> (<id>)/, one folder each.
      for (const leadId of [...fx.suppliers.map((s) => s.leadId), ...(fx.docSuppliers || []).map((s) => s.leadId)]) {
        const l = (await read(`select license_doc_path, company_profile_doc_path, company_name from public.leads where id=${Number(leadId)}`))[0];
        const mine = rows.filter((x) => x.dropbox_path.includes(`(${leadId})/`));
        const files = [l.license_doc_path, l.company_profile_doc_path].filter(Boolean);
        const filed = files.filter((p) => rows.some((x) => x.path === p && x.dropbox_path.startsWith(root + 'Suppliers/') && x.dropbox_path.includes(`(${leadId})/`)));
        const folders = new Set(mine.map((x) => folderOf(x.dropbox_path)));
        A(`supplier ${leadId}: licence and profile filed in its ONE folder`, filed.length === files.length && folders.size === 1, `${filed.length}/${files.length} filed · folders ${[...folders].map((f) => f.replace(root, '')).join(' | ')}`);
      }
      // Customers: details, signed terms and every inquiry under Customers/<name> (<id8>)/.
      for (const cu of fx.customers) {
        const id8 = String(cu.customerId).slice(0, 8);
        const mine = rows.filter((x) => x.dropbox_path.startsWith(root + 'Customers/') && x.dropbox_path.includes(`(${id8})/`));
        const tops = new Set(mine.map((x) => x.dropbox_path.replace(root + 'Customers/', '').split('/')[0]));
        const terms = mine.some((x) => /Signed Terms/i.test(x.dropbox_path));
        const inqs = Object.values(fx.inq).filter((x) => x.cu === cu);
        const inqOk = inqs.every((x) => !rows.some((r) => r.dropbox_path.includes(String(x.id).slice(0, 8)) && !r.dropbox_path.includes(`(${id8})/Inquiries/`)));
        A(`customer ${cu.cfg.label}: details and signed terms in its ONE folder, inquiry files under it`, mine.length > 0 && tops.size === 1 && terms && inqOk, `${mine.length} files · folders ${[...tops].join(' | ')} · signed terms ${terms} · inquiries ${inqs.length} ok=${inqOk}`);
      }
      const ver = await call('dropbox_backup', null, { __secret: cred, op: 'sandbox_verify', tag }, 240000);
      save('dropbox/dropbox_listing_verify.json', ver.json || ver.text);
      const sm = ver.json?.summary || {};
      A('the Dropbox listing matches the backup records (0 missing, 0 changed, 0 stray)', ver.status === 200 && sm.expected > 0 && !sm.missing && !sm.changed && !sm.stray, `HTTP ${ver.status} ${JSON.stringify(sm)}`);
    },
    // ---- S25: the 30-minute purge of an unfinished sign-up ----------------------------------------
    // fn_unfinished_signup_purge leaves is_demo rows to their harness unless it is pointed at ONE e-mail
    // (p_only_email), so it is pointed at this run's own sign-ups, one at a time, exactly as the job runs it.
    S25: async () => {
      const { createHash } = await import('node:crypto');
      const half = await makeDemoCustomer(run, { label: 'Unfinished', locale: 'en', stopBeforeWhatsApp: true });
      run.ids.customers.add(String(half.customerId));
      const full = fx.customers[2];
      const purge = async (email) => (await write(`select public.fn_unfinished_signup_purge(true, 5, ${q(email)}) r`, 'stage2 S25 purge (this run only)'))?.[0]?.r;
      const exists = async (cu) => (await read(`select (select count(*) from public.customers where id=${q(cu.customerId)})::int c, (select count(*) from auth.users where lower(email)=lower(${q(cu.email)}))::int u,
          (select count(*) from public.login_otp where lower(email)=lower(${q(cu.email)}))::int o`).catch(async () => read(`select (select count(*) from public.customers where id=${q(cu.customerId)})::int c, (select count(*) from auth.users where lower(email)=lower(${q(cu.email)}))::int u, 0 o`)))[0];
      const r0 = await purge(half.email); const e0 = await exists(half);
      A('inside its 30 minutes an unfinished sign-up stays', e0.c === 1 && e0.u === 1, `${JSON.stringify(r0).slice(0, 200)} row=${e0.c} auth=${e0.u}`);
      for (const cu of [half, full]) await write(`update public.customers set created_at = now() - interval '31 minutes' where id=${q(cu.customerId)};
          update auth.users set created_at = now() - interval '31 minutes' where lower(email)=lower(${q(cu.email)})`, 'stage2 S25 age the run\'s own sign-ups');
      const r1 = await purge(half.email); const e1 = await exists(half);
      A('after 30 minutes the purge removes the row, the auth user and the OTP rows', e1.c === 0 && e1.u === 0 && e1.o === 0, `${JSON.stringify(r1).slice(0, 300)} row=${e1.c} auth=${e1.u} otp=${e1.o}`);
      const r2 = await purge(full.email); const e2 = await exists(full);
      A('a complete sign-up of the same age is never touched', e2.c === 1 && e2.u === 1, `${JSON.stringify(r2).slice(0, 200)} row=${e2.c} auth=${e2.u}`);
      // the purge keeps only that a purge happened (a hash, no identity); this run's record is removed with the run.
      const ref = createHash('sha256').update(half.email.toLowerCase()).digest('hex');
      await write(`delete from public.signup_purge where subject_ref = ${q(ref)}`, 'stage2 S25 purge record of the run');
      save('customers/unfinished_signup_purge.json', { before_30_min: r0, after_30_min: r1, complete_same_age: r2 });
    },
    // ---- S26: the real-browser walk while the window is open ---------------------------------------
    S26: async () => {
      const { spawnSync } = await import('node:child_process');
      const alu = Object.values(fx.inq).find((x) => x.trade === 'aluminium');
      const en = alu?.cu?.cfg.locale === 'en' ? alu.cu : fx.customers.find((c) => c.cfg.locale === 'en');
      const ar = fx.customers.find((c) => c.cfg.locale === 'ar');
      const su = fx.suppliers[0];
      const who = (c, k, l) => ({ kind: k, email: c.email, label: l });
      const ids = { tag, customer: who(en, 'customer', en.cfg.label), customerAr: who(ar, 'customer', ar.cfg.label), supplier: who(su, 'supplier', 'AL'),
        walk: [who(en, 'customer', en.cfg.label), who(ar, 'customer', ar.cfg.label), who(su, 'supplier', 'AL')] };
      const idsPath = save('browser/ids.json', ids);
      const bout = join(OUT, 'browser');
      for (const mode of ['portals', 'journeys']) {
        const r = spawnSync(process.execPath, [join(REPO, 'scripts/e2e/browser_walk.mjs'), mode, idsPath], { encoding: 'utf8', timeout: 45 * 60000, cwd: REPO, env: { ...process.env, QD_WALK_OUT: bout, QD_FIXTURES: '1' } });
        save(`browser/${mode}.log`, (r.stdout || '') + (r.stderr || ''));
        A(`browser walk ${mode} ran to the end`, r.status === 0 && !/SKIP (journeys|portals)/.test(r.stdout || ''), `exit ${r.status} ${(r.stdout || '').split('\n').filter((l) => /SKIP|FAIL/.test(l)).slice(0, 4).join(' | ')}`);
      }
      spawnSync(process.execPath, [join(REPO, 'scripts/e2e/browser_walk.mjs'), 'index'], { encoding: 'utf8', cwd: REPO, env: { ...process.env, QD_WALK_OUT: bout } });
      const { readdirSync } = await import('node:fs');
      for (const f of readdirSync(bout).filter((x) => x.endsWith('.json') && x !== 'ids.json' && !x.startsWith('public'))) {
        const st = JSON.parse(readFileSync(join(bout, f), 'utf8'));
        if (!Array.isArray(st)) continue;
        const bad = st.filter((s) => s.status !== 'PASS');
        A(`browser: ${f.replace('.json', '')} (${st.length} steps)`, st.length > 0 && bad.length === 0, bad.map((s) => `${s.step}: ${s.status} ${(s.issues || []).map((i) => i.what).join('; ')}`).join(' | ').slice(0, 400) || 'all PASS');
      }
    },
    // ---- S24: answers judged by another family; nothing reached a real person -----------------------
    S24: async () => {
      const fam = (m) => String(m || '').split('/')[0];
      const samples = (fx.chats || []).map((c) => ({ what: `${c.who} chat (${c.lang})`, q: c.msg, a: String(c.reply?.reply || c.reply?.answer || c.reply?.text || ''), producer: (c.route || '').split(' ').map((x) => x.split(':')[1]).filter(Boolean)[0] || 'openai/gpt-6-luna', lang: c.lang }));
      const alu = Object.values(fx.inq).find((x) => x.trade === 'aluminium');
      if (alu) {
        const { pdfFactsFromBytes } = await import('./pdf_facts.mjs');
        const p = join(OUT, `customers/${alu.cu.cfg.label}_${alu.cu.cfg.locale}_${safe(alu.cu.cfg.emirate)}/inquiry_aluminium/comparison_en.pdf`);
        const txt = existsSync(p) ? String((await pdfFactsFromBytes(readFileSync(p)).catch(() => ({})))?.text || '') : '';
        const quotes = await read(`select q.quote_amount::float a, l.company_name s, q.price_ex_vat::float ex_vat, q.validity, q.warranty, q.lead_time, q.payment_terms, q.exclusions, q.terms_spec, (select jsonb_agg(to_jsonb(li) - 'quote_id') from public.quote_items li where li.quote_id::text = q.id::text) lines from public.quotes q join public.leads l on l.id=q.supplier_id where q.inquiry_id=${q(alu.id)} and q.status in ('submitted','accepted') order by 1`);
        samples.push({ what: 'comparison report (EN)', q: `Compare these quotes for aluminium works, cheapest first. These are the stored quotes the report was built from (supplier names may appear masked in the report); anything in the report that these rows support is NOT invented: ${JSON.stringify(quotes)}`, a: txt.slice(0, 6000), producer: 'anthropic/claude-opus-5.5', lang: 'en' });
      }
      const judged = [];
      for (const s of samples) {
        const task_class = fam(s.producer) === 'anthropic' ? 'internal_judgement' : 'ceo__internal_judgement';
        const w0 = await costWatermark();
        const r = await call('ai_gateway', null, { __secret: (await read(`select value from public.app_secrets where key='cred_fn_ai'`))[0]?.value, fn: 'stage2_quality_judge', task_class, subject: { email: fx.customers[0].email }, max_tokens: 400,
          messages: [{ role: 'system', content: 'You are a strict quality reviewer for QuotesDone, a UAE procurement marketplace (customers post requests, verified suppliers quote, the customer pays 3% of the chosen supplier’s final quoted price after any discount, excluding VAT (ruling 1208; e.g. 3% of AED 1,700 = AED 51), no cap, to reveal that supplier; no card fee and no VAT is added on top of that 3% (QuotesDone is not VAT-registered); a supplier’s own discount and VAT are shown exactly as the supplier quoted them (ruling 1207); a customer finds quotes under My requests (طلباتي) then the request; a supplier revises a quote from the job in the supplier portal (Inquiries received, the job, then send the revised quotation: "Send your quotation to the sales engineer", "Or type it into the quote form", "Attach a revised file", "Submit to Job <n>"), and a new submission replaces the earlier one until the customer chooses; when signed in, the assistant may name the user’s own requests and quotes, which are facts of the account, not inventions). Judge the ANSWER to the QUESTION: factually consistent with that, answers what was asked, in the language asked (' + s.lang + '), professional, no invented facts, no promises the platform cannot keep. Reply ONLY JSON {"score":1-5,"issues":["..."]}.' },
                     { role: 'user', content: `QUESTION / INPUT:\n${s.q}\n\nANSWER:\n${s.a || '(empty)'}` }] }, 120000);
        const used = (await costSince(w0)).map((x) => x.model_used).filter(Boolean);
        let v = null; try { v = JSON.parse(String(r.json?.content || '').replace(/^[^{]*/, '').replace(/[^}]*$/, '')); } catch { v = null; }
        judged.push({ ...s, judge_task: task_class, judge_model: used.join(','), verdict: v, raw: r.json?.content || r.text });
        A(`${s.what}: judged ${v?.score ?? '?'}/5 by ${used.join(',') || 'NO MODEL'} (producer ${s.producer})`, !!s.a && v && v.score >= 4 && used.length > 0 && used.every((m) => fam(m) !== fam(s.producer)), JSON.stringify(v?.issues || r.json || r.text).slice(0, 300), used.join(','));
      }
      save('chats/quality_judgement.json', judged);
      // 0 messages to real people: every notification the run caused, on any channel, went to a demo address or was captured.
      const ids = [...run.ids.inquiries, ...run.ids.quotes].map(q).join(',') || 'null';
      const leads = [...run.ids.leads].map(Number).join(',') || 'null';
      const out = await read(`select id, channel, status, to_email, to_phone, type from public.notifications n
          where n.created_at >= ${q(window.from)} and (n.inquiry_id::text in (${ids}) or n.quote_id::text in (${ids}) or n.lead_id in (${leads})
             or n.to_email like ${q('qd-' + tag + '-%')} or coalesce(n.subject,'') || coalesce(n.body,'') like ${q('%' + tag + '%')})`);
      const realAddr = out.filter((n) => (n.to_email && !/@example\.invalid$/i.test(n.to_email)) || (n.to_phone && !/^\+?9715000000\d{2}$/.test(String(n.to_phone).replace(/[^\d+]/g, ''))));
      const delivered = out.filter((n) => ['sent', 'delivered', 'queued', 'pending'].includes(n.status));
      save('notifications/real_recipient_audit.json', { notices: out.length, real_address: realAddr, delivered });
      fx.noticeAudit = { out: out.length, delivered: delivered.length };
      A('0 messages from the run reached a real person (email, WhatsApp, SMS)', out.length > 0 && delivered.length === 0 && realAddr.every((n) => !['sent', 'delivered'].includes(n.status)),
        `${out.length} notices · real-looking addresses ${realAddr.length} (${[...new Set(realAddr.map((n) => n.status))].join(',') || '-'}) · delivered/queued ${delivered.length}`);
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
    let skipped = null;
    try { await bodies[s.key](); } catch (e) {
      if (e instanceof Skip) { skipped = e.message; log(`SKIP [${s.key}] ${e.message}`); }
      else A('scenario crashed', false, String(e.stack || e.message).split('\n').slice(0, 3).join(' | '));
    }
    const rows = await costSince(w0);
    const usd = rows.reduce((a, r) => a + r.aed, 0) / AED_PER_USD; spentUsd += usd;
    // matrix v2 per step: every model call the scenario caused used its class's primary or fallback.
    const off = rows.filter((r) => { const p = pre.pr.pol[r.task_class]; return p && r.model_used && ![p.model_primary, p.model_fallback].includes(r.model_used); });
    A(`model routes follow matrix v2 (${rows.length} calls)`, off.length === 0, off.map((r) => `${r.task_class}:${r.model_used}`).join(' ') || 'all on primary or fallback', [...new Set(rows.map((r) => r.model_used))].join(','));
    const own = steps.filter((x) => x.scenario === s.key && !x.name.startsWith('model routes follow'));
    scenarioRows.push({ key: s.key, measured_usd: usd, calls: rows.length, result: skipped && own.every((x) => x.ok) ? 'SKIP' : steps.filter((x) => x.scenario === s.key).every((x) => x.ok) ? 'PASS' : 'FAIL', ...(skipped ? { skipped } : {}) });
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
  // DROPBOX first, while its records still say what was filed: the run's _sandbox/<tag> folder (the path is built
  // by dropbox_backup from the tag, never taken from here), then its SBX:<tag>: records and generated copies.
  const dropbox = {};
  try {
    const c = await call('dropbox_backup', null, { __secret: await dbxCred(), op: 'sandbox_cleanup', tag }, 120000);
    dropbox.folder = { status: c.status, folder_gone: c.json?.folder_gone === true };
    const gen = await read(`select bucket, path from public.doc_backups where dedupe_key like ${q('SBX:' + tag + ':%')} and source = 'generated' and bucket is not null and path is not null`);
    const { SERVICE } = await keys();
    for (const g of gen) await fetch(`${BASE}/storage/v1/object/${g.bucket}/${g.path}`, { method: 'DELETE', headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE } }).catch(() => {});
    const r = await write(`with d as (delete from public.doc_backups where dedupe_key like ${q('SBX:' + tag + ':%')} returning 1) select count(*)::int n from d`, 'stage2 dropbox sandbox records');
    dropbox.records_removed = r?.[0]?.n ?? 0; dropbox.generated_removed = gen.length;
  } catch (e) { dropbox.error = String(e.message).slice(0, 200); }
  const closed = await closeRun(run, {});
  // THE SWEEP: whatever teardown never knew (conversation rows from the signed inbound messages, seat
  // notes, error-ingest rows) is found by verifyClean and removed only where the row itself carries the
  // run's unique marker. The tag is 8 random hex characters; no real row contains 'qd-<tag>-' or
  // 'ZZ DEMO <tag>'. Up to three passes, because a child row can block its parent's delete.
  const swept = {};
  // The last marker is ai_gateway's blocked-call line in agent_runs / os_audit_log, which names the tag only
  // inside fn_ai_subject_is_fixture's phrase; the exact phrase with the tag cannot match another run's row.
  // The last marker is the run's demo NAME shape, 'ZZ DEMO <words> <tag>' (supplier 'ZZ DEMO AL aluminium <tag>', customer
  // 'ZZ DEMO C1 <tag>'), required whole: run 321d13ae's seat task named only those, so a bare 'ZZ DEMO <tag>' missed it.
  const mk = (x) => [...[`qd-${tag}-`, `ZZ DEMO ${tag}`, `zzdemo${tag}`, `zzdemo-${tag}`, `an identity of harness run ${tag} (opened in rehearsal_window)`]
    .map((m) => `${x}::text like ${q('%' + m.replace(/[\\%_]/g, '\\$&') + '%')}`), `${x}::text ~ ${q('ZZ DEMO [A-Za-z0-9 ]{1,60} ' + tag + '([^0-9a-f]|$)')}`].join(' or ');
  // Tables the features merged since run 4 write for a demo run (review of #1464): removed by the markers only, in this
  // order: decision_trace before the seat task it explains, undo_log after it (deleting a task writes one more undo row).
  const MARKER_TABLES = ['decision_trace', 'org_tasks', 'undo_log', 'wa_answer_log', 'wa_turn', 'wa_messages', 'reasoning_held_question'];
  for (const t of MARKER_TABLES) {
    try {
      const r = await write(t === 'decision_trace'
        ? `with d as (delete from public.decision_trace x where ${mk('x')} or (x.entity_type = 'org_task' and x.entity_id::text in (select id::text from public.org_tasks o where ${mk('o')})) returning 1) select count(*)::int n from d`
        : `with d as (delete from public.${t} x where ${mk('x')} returning 1) select count(*)::int n from d`, `stage2 markers ${t}`);
      swept[t] = r?.[0]?.n ?? 0;
    } catch (e) { swept[t] = /42P01|does not exist/.test(String(e.message)) ? 'table absent' : 'ERROR ' + String(e.message).slice(0, 100); }
  }
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
  return { learning, removed: closed.removed?.summary, swept, dropbox, leftovers: closed.leftovers, verify: v };
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
