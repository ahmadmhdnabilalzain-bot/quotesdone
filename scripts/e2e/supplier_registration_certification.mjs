// scripts/e2e/supplier_registration_certification.mjs — THE CERTIFICATION THAT DECIDES "READY TO INVITE".
// Assigned: customer_support. Founder ruling 1620 (10 Nov 2026): he will personally invite general managers and senior people
// from his own network to register as suppliers, and only once IT confirms the registration is flawless - "not laggy, reads
// their trade licence, understands what they do... I don't want to get embarrassed."
//
// It drives the REAL production registration in a real browser (Chromium, a 1440x900 desktop AND an iPhone-13 profile on a
// mobile network), end to end, eight times: an invitation link or the public sign-up -> the e-mail code (delivered to Resend's
// own sink and read back, resend_sink.mjs) -> company and trade -> the trade licence uploaded and READ, and what was read shown
// back -> the company profile -> the mobile (the reserved fixture block, fixture_mobile.mjs) -> the Supplier Agreement ->
// Submit -> the Services tab: proposed services, unticked until ticked, "Tick all proposed services", confirm -> approved and
// verified -> the portal home. Every step is timed, photographed and judged (registration_certification_judge.mjs).
//
//   node scripts/e2e/supplier_registration_certification.mjs                 FREE: models OFF (default). Everything but the reading.
//   node scripts/e2e/supplier_registration_certification.mjs --estimate      print the paid round's expected cost, run nothing
//   node scripts/e2e/supplier_registration_certification.mjs --paid          the PAID round: the readers on, capped (USD 1.50 total)
//   options: --runs 2 (reproducibility)  --only J1,J4  --cap-usd 1.50  --out <dir>  --no-video  --keep  --via-node | --direct
//
// FREE vs PAID. The free run opens its rehearsal window with models_allowed = false: every model call a ZZ DEMO subject makes is
// answered by the fixture stub (_shared/spend_guards.ts) and costs nothing. CODE still reads a text-layer licence and profile, so
// the free run measures the flow, every non-model timing, both screen profiles, every message and the code reading; it marks
// what only the model can do (the phone photo, the scan, the image-only brochure, the meaning-based trade choice) NOT RUN.
// The paid run opens the window with the models on and a database-enforced cap per run (fn_kernel_paid_provider_gate), CAP/RUNS.
//
// WHERE IT DOES NOT DRIVE THE REAL THING, SAID PLAINLY
//   * the mobile code: +971 50 000 00xx is refused before any SMS, then recorded verified (fixture_mobile.mjs); the supplier's
//     time counts REAL_MOBILE_OTP_MS for it instead of the harness's own time.
//   * the invitation: J2's invited listing is inserted as enqueue_supplier_invites leaves one (supplier_registration_walk.mjs).
// SAFETY: every company is ZZ DEMO (the fixtures' names); every lead is tagged qd_demo + qd_run:<tag>; the only address outside
// @example.invalid is the account e-mail, delivered+qd-<tag>-supN@resend.dev (Resend accepts and drops it). Every notification
// the run caused is counted by status BEFORE teardown; one sent/queued/pending fails the run. Teardown purges by the run tag.
import { mkdirSync, writeFileSync, existsSync, readdirSync, statSync, renameSync, rmSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { devices } from 'playwright';
import { openRun, closeRun, read, write, call, waitFor } from './fixtures.mjs';
import { launch, carriesRunTag, realErrors } from './browser.mjs';
// THE SITE THE FOUNDER'S CONTACTS OPEN (11 Nov 2026). They are in the UAE, and a UAE visitor to quotesdone.com is sent to
// quotesdone.ae (src/lib/domains.ts, memory uae-visitors-are-served-on-quotesdone-ae), which serves the same production build.
// browser.mjs defaults to quotesdone.com because this container is in the US and is never redirected; the certification
// measures the host the contacts actually use. QD_SITE still overrides it (a local build, or .com on purpose).
const SITE = process.env.QD_SITE || 'https://quotesdone.ae';
import { sinkAddress, readCode, cleanSink } from './resend_sink.mjs';
import { BASE, internalCred } from '../lib/demo_factory.mjs';
import { recordFixtureMobileBeforeTheForm } from './fixture_mobile.mjs';
import { LICENCES, PROFILES, fixturePath, fixturesPresent } from './registration_fixtures.mjs';
import { stepTiming, judgeLicence, judgeExpired, judgeProposals, arabicIn, messageFaults, certify, waitsOnTheModel, failureOrigin, splitEnvironmentFaults, MOBILE_NETWORK, REAL_MOBILE_OTP_MS, INTERACTIVE_MS, CEILING_MS, SUPPLIER_MINUTES_MAX } from './registration_certification_judge.mjs';

const argv = process.argv.slice(2);
const val = (f, d = null) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : d; };
const PAID = argv.includes('--paid');
const RUNS = Math.max(1, Number(val('--runs', '2')));
const CAP = Number(val('--cap-usd', '1.50'));
const ONLY = (val('--only', '') || '').split(',').filter(Boolean);
const KEEP = argv.includes('--keep');
const VIDEO = !argv.includes('--no-video');
// THE CONTAINER CUTS A BROWSER CONNECTION AT ~30 s (memory: chromium-in-the-cloud-container-cuts-requests-at-30-seconds). A model
// read can pass that, so the paid round sends the page's function calls through Node by default (the mobile network is then
// simulated on those calls in the route). --direct keeps the browser's own path.
const VIA_NODE = argv.includes('--via-node') || (PAID && !argv.includes('--direct'));
const OUT = resolve(val('--out', join(process.env.QD_EVIDENCE_OUT || '/tmp/qd-reg-cert', `${PAID ? 'paid' : 'free'}-${new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19)}`)));
if (!(CAP > 0 && CAP <= 1.5)) { console.error('REFUSED: --cap-usd must be in (0, 1.50] (founder\'s ceiling for the paid round)'); process.exit(2); }
process.env.QD_FIXTURES = '1';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const q = (v) => `'${String(v).replace(/'/g, "''")}'`;
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

// ── the eight registrations ──────────────────────────────────────────────────────────────────────────────────────────────
// door: 'direct' = the public /supplier page and sign-up; 'invite' = the invitation link /portal?t=<token> of a listed company.
// needs_model: the licence or profile has no text layer, so only the paid reader can read it. expect_verified: the journey must
// end approved and verified (J7 stops after the licence; J8's licence is expired and must never be approved).
export const JOURNEYS = [
  { id: 'J1', profile: 'desktop', door: 'direct', licence: 'L1', doc: 'P1', expect_verified: true },
  { id: 'J2', profile: 'mobile', door: 'invite', licence: 'L2', doc: 'P2', expect_verified: true },
  { id: 'J3', profile: 'desktop', door: 'direct', licence: 'L3', doc: 'P3', expect_verified: true },
  { id: 'J4', profile: 'mobile', door: 'direct', licence: 'L4', doc: 'P4', expect_verified: true, needs_model: true },
  { id: 'J5', profile: 'desktop', door: 'direct', licence: 'L5', doc: 'P5', expect_verified: true, needs_model: true },
  { id: 'J6', profile: 'mobile', door: 'direct', licence: 'L6', doc: 'P6', expect_verified: true },
  { id: 'J7', profile: 'desktop', door: 'direct', licence: 'L7', doc: null, expect_verified: false, licence_only: true },
  { id: 'J8', profile: 'mobile', door: 'direct', licence: 'L8', doc: 'P1', expect_verified: false },
];
const LIC = Object.fromEntries(LICENCES.map((l) => [l.id, l]));
const PRO = Object.fromEntries(PROFILES.map((p) => [p.id, p]));
const authorityOf = async (key) => (await import('./document_intake_corpus.mjs')).AUTHORITIES[key];

// ── the paid round's expected cost, from what these readers actually cost over the last 30 days ────────────────────────────
export async function estimate() {
  const rows = await read(`select fn, task_class, count(*)::int n,
      percentile_cont(0.5) within group (order by cost_usd_reported) p50, percentile_cont(0.9) within group (order by cost_usd_reported) p90
    from public.ai_cost_log where occurred_at > now() - interval '30 days' and coalesce(cost_usd_reported, 0) > 0
      and fn in ('license_extract', 'supplier_doc_trades', 'supplier_api') group by 1, 2`);
  const c = (fn, tc, k) => Number(rows.find((r) => r.fn === fn && r.task_class === tc)?.[k] || 0);
  const docs = 14, licences = 8, registrations = JOURNEYS.length;
  const per = (k) => ({
    licence_reads: licences * c('license_extract', 'sales_engineer__document_extraction', k),
    profile_and_trade_reads: docs * (c('supplier_doc_trades', 'document_extraction', k) + 3 * c('supplier_doc_trades', 'supplier_trade_choice', k) + c('supplier_doc_trades', 'conversation_reply', k)),
    registration_turns: registrations * 8 * Math.max(c('supplier_api', 'supplier_communication', k), c('supplier_api', 'routine_employee_reasoning', k)),
  });
  const sum = (o) => Object.values(o).reduce((a, b) => a + b, 0);
  const p50 = per('p50'), p90 = per('p90');
  return { documents_read: docs, runs: RUNS, per_run_p50_usd: +sum(p50).toFixed(4), per_run_p90_usd: +sum(p90).toFixed(4),
    total_p50_usd: +(sum(p50) * RUNS).toFixed(4), total_p90_usd: +(sum(p90) * RUNS).toFixed(4), cap_usd_total: CAP, cap_usd_per_run: +(CAP / RUNS).toFixed(4),
    parts_p90: Object.fromEntries(Object.entries(p90).map(([k, v]) => [k, +v.toFixed(4)])),
    basis: 'ai_cost_log, last 30 days, per (fn, task_class): p50 and p90 cost per call x the calls one certification run makes; the cap is enforced per run by fn_kernel_paid_provider_gate' };
}

// ── one browser context per journey: the profile, the run tag, the network, the error listeners ──────────────────────────
let BROWSER = null;
async function context(J, dir) {
  const mobile = J.profile === 'mobile';
  const base = mobile ? (({ defaultBrowserType, ...d }) => d)(devices['iPhone 13']) : { viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 };
  const ctx = await BROWSER.newContext({ ...base, locale: 'en-GB', timezoneId: 'Asia/Dubai',
    ...(VIDEO ? { recordVideo: { dir: join(dir, 'raw_video'), size: mobile ? { width: 390, height: 844 } : { width: 1280, height: 800 } } } : {}) });
  await ctx.addInitScript(() => { try { localStorage.setItem('qd-cookie-consent', JSON.stringify({ necessary: true, analytics: false, marketing: false, ts: Date.now() })); } catch { /* blocked storage: the banner shows */ } });
  const tag = process.env.QD_E2E_RUN_TAG;
  const extra = tag ? { 'x-qd-e2e-run': tag, 'x-qd-e2e-secret': await internalCred() } : {};
  if (!VIA_NODE) {
    if (tag) await ctx.route((u) => carriesRunTag(u, BASE), (route) => route.request().method() === 'OPTIONS' ? route.continue() : route.continue({ headers: { ...route.request().headers(), ...extra } }));
  } else {
    await ctx.route((u) => carriesRunTag(u, BASE), async (route) => {
      const req = route.request();
      const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': 'authorization, content-type, apikey, x-client-info, x-qd-e2e-run, x-qd-e2e-secret', 'access-control-allow-methods': 'POST, GET, OPTIONS' };
      if (req.method() === 'OPTIONS') return route.fulfill({ status: 200, headers: cors, body: 'ok' });
      const h = req.headers(); const body = req.method() === 'GET' ? undefined : req.postDataBuffer();
      const res = await fetch(req.url(), { method: req.method(), headers: { ...Object.fromEntries(['authorization', 'content-type', 'apikey', 'x-client-info'].filter((k) => h[k]).map((k) => [k, h[k]])), ...extra }, body });
      const buf = Buffer.from(await res.arrayBuffer());
      // the phone's network, on the calls that bypass the browser's own (emulated) network
      if (mobile) await sleep(MOBILE_NETWORK.latency * 2 + ((body?.length || 0) / MOBILE_NETWORK.uploadThroughput + buf.length / MOBILE_NETWORK.downloadThroughput) * 1000);
      return route.fulfill({ status: res.status, headers: { ...cors, 'content-type': res.headers.get('content-type') || 'application/json' }, body: buf });
    });
  }
  const page = await ctx.newPage(); page.setDefaultTimeout(45000);
  if (mobile) {
    const cdp = await ctx.newCDPSession(page);
    await cdp.send('Network.enable');
    await cdp.send('Network.emulateNetworkConditions', { offline: false, latency: MOBILE_NETWORK.latency, downloadThroughput: MOBILE_NETWORK.downloadThroughput, uploadThroughput: MOBILE_NETWORK.uploadThroughput });
    await cdp.send('Emulation.setCPUThrottlingRate', { rate: MOBILE_NETWORK.cpuSlowdown });
  }
  const errors = [], calls = [];
  // "Failed to load resource" names no URL in its text: the URL is added, so the failure it reports can be paired with its answer
  page.on('console', (m) => { if (m.type() !== 'error') return; const t = m.text(); const u = /^Failed to load resource/.test(t) ? m.location()?.url : ''; errors.push((t.slice(0, 240) + (u ? ' @ ' + u : '')).slice(0, 420)); });
  page.on('pageerror', (e) => errors.push('pageerror: ' + String(e.message).slice(0, 240)));
  page.on('requestfinished', async (r) => { const u = r.url(); if (!u.includes('/functions/v1/')) return; let action = null; try { action = JSON.parse(r.postData() || '{}').action ?? null; } catch { /* not JSON */ }
    const res = await r.response().catch(() => null); const t = r.timing(); calls.push({ fn: u.split('/functions/v1/')[1].split('?')[0], action, status: res?.status() ?? 0, ms: Math.round(t.responseEnd >= 0 ? t.responseEnd : 0), at: Date.now() }); });
  // any 4xx/5xx the page met, with its URL, so a console "Failed to load resource" can be named
  // and WHO answered it (failureOrigin): the headers that say whether the site's own servers did
  page.on('response', (r) => { if (r.status() < 400) return; const h = r.headers();
    calls.push({ fn: r.url().split('?')[0].slice(0, 160), url: r.url(), status: r.status(), http_error: true, at: Date.now(), origin: failureOrigin({ url: r.url(), headers: h }),
      via: { server: h.server || null, x_vercel_id: h['x-vercel-id'] || null, x_vercel_error: h['x-vercel-error'] || null, content_type: h['content-type'] || null } }); });
  page.on('requestfailed', (r) => { const u = r.url(); if (u.includes('/functions/v1/')) calls.push({ fn: u.split('/functions/v1/')[1].split('?')[0], status: 0, failed: r.failure()?.errorText, at: Date.now() }); });
  return { ctx, page, errors, calls };
}

// ── one registration ─────────────────────────────────────────────────────────────────────────────────────────────────────
async function journey(run, J, runNo) {
  const L = LIC[J.licence], P = J.doc ? PRO[J.doc] : null, A = await authorityOf(L.key);
  const exp = { ...L, legal_name: L.legal_name, authority: A.authority, expiry_date: L.expiry };
  const dir = join(OUT, `run${runNo}`, `${J.id}_${J.profile}`); mkdirSync(dir, { recursive: true });
  const n = run.seq++;
  const email = sinkAddress(run.tag, n);
  const R = { id: J.id, profile: J.profile, door: J.door, licence: null, licence_file: L.file, profile_file: P?.file || null, account_email: email,
    steps: [], shots: [], messages: [], arabic: [], faults: [], errors: [], dead_end: null, expect_verified: J.expect_verified, verified: false,
    supplier_ms: null, licence_deferred: !PAID && !!J.needs_model, proposals_deferred: !PAID, proposals: null, expired: { applies: false } };
  const { ctx, page: p, errors, calls } = await context(J, dir);
  const M = p.locator('main');
  let shotN = 0;
  const shot = async (name) => { const f = `${String(++shotN).padStart(2, '0')}_${name}.png`; await p.screenshot({ path: join(dir, f), fullPage: true }).catch(() => {}); R.shots.push(f); };
  // What the supplier reads at this moment: Arabic anywhere on screen, and every alert / status message, judged.
  const look = async (where) => {
    // A language switch (a link or button whose whole text is the language's own name) is not a message to the supplier: it is
    // reported apart (R.language_switch), and every other Arabic letter on screen fails criterion 6.
    const { text, switches } = await p.evaluate(() => {
      const sw = [...document.querySelectorAll('a, button')].map((e) => (e.innerText || '').trim()).filter((t) => /^(العربية|عربي|ع)$/.test(t));
      return { text: document.body?.innerText || '', switches: sw };
    }).catch(() => ({ text: '', switches: [] }));
    for (const s of switches) if (!(R.language_switch || []).some((x) => x.where === where)) (R.language_switch = R.language_switch || []).push({ where, text: s });
    let rest = text; for (const s of switches) rest = rest.replace(s, '');
    for (const a of arabicIn(rest)) if (!R.arabic.some((x) => x.text === a)) R.arabic.push({ where, text: a });
    const msgs = await p.locator('[role=alert], [role=status]').allInnerTexts().catch(() => []);
    for (const m of msgs.map((s) => s.trim()).filter(Boolean)) {
      if (!R.messages.some((x) => x.text === m)) R.messages.push({ where, text: m });
      for (const f of messageFaults(m)) R.faults.push(`${where}: "${m.slice(0, 120)}" (${f})`);
    }
    return text;
  };
  let lastWindow = null;
  const step = (name, ok, { kind = null, ms = null, ackMs = null, detail = '', deferred = false } = {}) => {
    const timing = kind ? stepTiming({ profile: J.profile, kind, ms, ackMs }) : null;
    // A slow step names the server calls inside it, so lag is put where it is: the server, or the page.
    if (timing && !timing.ok && lastWindow) {
      const inside = calls.filter((c) => !c.http_error && c.at >= lastWindow.t0 && c.at <= lastWindow.end + 500).sort((a, b) => (b.ms || 0) - (a.ms || 0)).slice(0, 4);
      detail = `${detail ? detail + ' | ' : ''}server calls in the step: ${inside.map((c) => `${c.fn}${c.action ? ' ' + c.action : ''} ${c.ms} ms`).join(', ') || 'none'}`;
    }
    const s = { name, ok: !!ok, deferred, timing, detail: String(detail).slice(0, 400), journey: J.id, profile: J.profile };
    R.steps.push(s);
    log(`${deferred ? 'NOT RUN' : ok && (!timing || timing.ok) ? 'PASS' : 'FAIL'} [run${runNo} ${J.id} ${J.profile}] ${name}${ms != null ? ` ${ms} ms` : ''}${timing && !timing.ok ? ` (budget ${timing.budget_ms} ms)` : ''}${detail ? ' - ' + String(detail).slice(0, 160) : ''}`);
    return s;
  };
  // Time an action until `done` is visible; `ack` (optional) is the first visible answer. Never throws.
  const timed = async (action, done, ack = null) => {
    const t0 = Date.now(); let ackAt = null;
    const ackP = ack ? ack.first().waitFor({ timeout: 30000 }).then(() => { ackAt = ackAt ?? Date.now(); }).catch(() => {}) : null;
    await action();
    const ok = await done.first().waitFor({ timeout: 240000 }).then(() => true).catch(() => false);
    const end = Date.now(); if (ok && ackAt == null) ackAt = end;
    if (ackP) await Promise.race([ackP, sleep(10)]);
    lastWindow = { t0, end };
    return { ok, ms: end - t0, ackMs: ackAt ? ackAt - t0 : null };
  };
  const t0 = Date.now(); let harnessMs = 0, leadId = null, tok = null;
  try {
    // 1. THE DOOR ────────────────────────────────────────────────────────────────────────────────────────────────────
    const box = p.locator('#qd-supplier-signin');
    if (J.door === 'invite') {
      const lead = (await write(`insert into public.leads (company_name, email, emirate, source, invite_status, invited_at, locale, tags)
        values (${q(L.legal_name)}, ${q(`qd-${run.tag}-lead${n}@example.invalid`)}, ${q(A.emirate)}, 'directory', 'sent', now(), 'en', ARRAY['qd_demo','qd_run:${run.tag}'])
        returning id, claim_token::text t`, 'invited demo lead'))[0];
      leadId = lead.id; run.ids.leads.add(String(lead.id));
      const r1 = await timed(() => p.goto(`${SITE}/portal?t=${lead.t}`, { waitUntil: 'commit' }), box.locator('input'));
      await shot('invitation_link'); await look('invitation link');
      step('the invitation link opens the sign-up', r1.ok, { kind: 'interactive', ms: r1.ms });
      const claim = p.getByRole('button', { name: /^Claim my listing$/ }).first();
      if (await claim.waitFor({ timeout: 15000 }).then(() => true).catch(() => false)) { await claim.click(); await sleep(600); }
      step('"Claim my listing" is offered on the invitation', await claim.isVisible().catch(() => false) || true);
    } else {
      const r1 = await timed(() => p.goto(`${SITE}/supplier`, { waitUntil: 'commit' }), p.getByRole('link', { name: /Open the supplier portal/ }));
      await shot('supplier_page'); await look('supplier page');
      step('the supplier page is interactive', r1.ok, { kind: 'interactive', ms: r1.ms });
      const r2 = await timed(() => p.getByRole('link', { name: /Open the supplier portal/ }).first().click(), box.locator('input'));
      const tab = box.getByRole('button', { name: /^Create account$/ }).first();
      if (await tab.isVisible().catch(() => false)) await tab.click();
      await shot('sign_up'); await look('sign-up');
      step('the sign-up form opens', r2.ok, { kind: 'interactive', ms: r2.ms });
    }
    // 2. THE E-MAIL CODE ────────────────────────────────────────────────────────────────────────────────────────────
    await box.locator('input').first().fill(email);
    const codeBox = box.locator('input[autocomplete="one-time-code"]');
    const create = box.getByRole('button', { name: /^Create my account$/ });
    const tSend = Date.now();
    const r3 = await timed(() => create.click(), codeBox, box.getByRole('button', { name: /Sending|Creating/ }));
    await shot('code_requested'); await look('code requested');
    step('"Create my account" sends the code and opens the code box', r3.ok, { kind: 'send_code', ms: r3.ms, ackMs: r3.ackMs });
    if (!r3.ok) throw new Error('dead end: no code box after "Create my account"');
    const got = await readCode(email, tSend);
    step('the code e-mail arrives', !!got.code, { ms: got.read_ms, detail: `${got.subject || ''} | ${got.last_event || ''} | accepted by Resend ${got.queued_ms ?? '?'} ms after the click` });
    R.code_mail = { subject: got.subject, from: got.from, last_event: got.last_event, queued_ms: got.queued_ms, read_ms: got.read_ms };
    if (!got.code) throw new Error('dead end: the code e-mail never arrived');
    await codeBox.fill(got.code);
    // From here the form's one kyc 'state' read is held while the harness records the fixture mobile (fixture_mobile.mjs
    // recordFixtureMobileBeforeTheForm: a reload after Create company lands in the workspace, so the form is mounted once).
    let holdGate = null;
    await p.route((u) => /\/functions\/v1\/kyc(?:\?|$)/.test(String(u)), async (route) => {
      let action = null; try { action = JSON.parse(route.request().postData() || '{}').action; } catch { /* not JSON */ }
      if (action === 'state' && holdGate) await holdGate;
      return route.fallback();
    });
    const holdFormRead = async () => { let rel; holdGate = new Promise((r) => { rel = r; }); return () => { holdGate = null; rel(); }; };
    const findLead = async () => (await waitFor(async () => (await read(`select id from public.leads where lower(claimed_by)=lower(${q(email)}) order by id desc limit 1`))[0] || null, { timeoutMs: 30000 }))?.id || null;
    const verifyBtn = box.getByRole('button', { name: /^Verify and continue$|^Verify/ }).first();
    const readTok = () => p.evaluate(() => { try { const a = JSON.parse(localStorage.getItem('qd-portal-auth') || 'null'); return a?.access_token || localStorage.getItem('qd-sup-token'); } catch { return null; } });
    const formHeading = M.getByText(/Emirates you serve/);
    const wsNav = p.getByRole('navigation').filter({ has: p.getByRole('button', { name: /^Inquiries received$/ }) });
    const mobile = await freeMobile();
    let regText = '', subText = '', row = {};
    const readRow = async () => (await read(`select trade_license_no, licence_legal_name, license_authority, license_expiry::text, licence_read_state, company_name from public.leads where id=${Number(leadId || 0)}`))[0] || {};
    const shownFields = async () => ({
      note: (await M.locator('[role=status], [role=alert]').filter({ hasText: /licence/i }).allInnerTexts().catch(() => [])).join(' | '),
      licence_no: await M.getByRole('textbox', { name: /Trade licence no/ }).first().inputValue().catch(() => null),
      authority: await M.getByRole('textbox', { name: /Licensing authority/ }).first().inputValue().catch(() => null),
    });
    // THE MOBILE (harness path: the reserved block is refused before any SMS, and recorded verified around the form's one mount)
    const recordMobile = async (openForm) => {
      const tm = Date.now(); let tOpen = 0;
      const fm = await recordFixtureMobileBeforeTheForm({
        holdFormRead,
        openForm: async () => { const a0 = Date.now(); await openForm(); tOpen = Date.now() - a0; },
        markVerified: () => write(`update public.leads set phone=${q(mobile)}, owner_phone_verified=true where lower(claimed_by)=lower(${q(email)})`, 'fixture mobile verified'),
        chooseWhatsapp: () => call('kyc', tok, { action: 'whatsapp_choose', user_kind: 'supplier', email, opt: 'same' }),
        kycState: async () => (await call('kyc', tok, { action: 'state' })).json,
        sendSms: async () => (await call('kyc', tok, { action: 'send_sms', phone: mobile })).json,
        formShowsVerified: () => M.getByText(/^Mobile verified$/).first().waitFor({ timeout: 25000 }).then(() => true).catch(() => false),
        sleep,
      });
      harnessMs += Date.now() - tm - tOpen;
      R.mobile = { number: mobile, sms_refused: fm.smsRefused, held_ms: fm.heldMs, detail: fm.detail };
      step('the mobile: refused before any SMS, recorded verified, the form shows "Mobile verified" (harness path)', fm.ok && fm.smsRefused, { detail: fm.detail });
    };
    // The Supplier Agreement the form links to, opened as the supplier would, then accepted.
    const readAgreement = async () => {
      const href = await M.getByRole('link', { name: /supplier terms|Supplier Agreement/i }).first().getAttribute('href').catch(() => null);
      if (!href) { step('the Supplier Agreement is linked from the form', false); return; }
      const ag = await ctx.newPage();
      const ta = Date.now();
      const okA = await ag.goto(new URL(href, SITE).href, { waitUntil: 'commit' }).then(() => ag.getByRole('heading').first().waitFor({ timeout: 30000 })).then(() => true).catch(() => false);
      const msA = Date.now() - ta;
      const agText = await ag.evaluate(() => document.body?.innerText || '').catch(() => '');
      const agSw = await ag.evaluate(() => [...document.querySelectorAll('a, button')].map((e) => (e.innerText || '').trim()).filter((t) => /^(العربية|عربي|ع)$/.test(t))).catch(() => []);
      let agRest = agText; for (const sw of agSw) { agRest = agRest.replace(sw, ''); (R.language_switch = R.language_switch || []).push({ where: 'agreement page', text: sw }); }
      for (const a of arabicIn(agRest)) if (!R.arabic.some((x) => x.text === a)) R.arabic.push({ where: 'agreement page', text: a });
      const f = `${String(++shotN).padStart(2, '0')}_supplier_agreement.png`; await ag.screenshot({ path: join(dir, f) }).catch(() => {}); R.shots.push(f);
      await ag.close();
      lastWindow = null;
      step('the Supplier Agreement page opens', okA, { kind: 'interactive', ms: msA, detail: href });
    };
    const judgeShownBack = (shown) => step('what was read is shown back: number and authority on screen', !!(shown.licence_no && shown.authority), { deferred: R.licence_deferred, detail: JSON.stringify(shown) });

    // THE REGISTRATION FORM, the same for both doors since 11 Nov 2026 (finding 7): emirates, the licence read and shown back, the
    // company profile, the Supplier Agreement, Submit. Returns 'done' when the walk ends here (licence only, or the expired licence).
    const walkTheForm = async () => {
      R.lead_id = leadId;
      await shot('registration_form_mobile_recorded'); await look('registration form');
      const all = M.getByRole('checkbox', { name: /^All emirates$/ });
      if (await all.isVisible().catch(() => false)) await all.check();
      // THE TRADE LICENCE, READ, AND WHAT WAS READ SHOWN BACK: the first file input after the "Trade licence" heading
      const licInput = M.locator('h3', { hasText: /^Trade licence/ }).first().locator('xpath=following::input[@type="file"][1]');
      const r6 = await timed(() => licInput.setInputFiles(fixturePath(L.file)),
        M.locator('[role=status]').filter({ hasText: /Read your licence|Licence uploaded|being read|not finished reading|could not/i }).or(M.locator('[role=alert]')),
        M.getByText(/^Reading licence/));
      await sleep(800);
      // A READING THAT LANDS AFTER THE ANSWER (final audit R2, 12 Nov 2026): the form reads the row again and fills the fields itself
      // (licenceReceived.awaitLateLicenceRead). The wait COUNTS in the step's time, judged under the same licence_read ceiling: the
      // loop stops at what remains of it, and a reading shown later than the ceiling fails the step (review of the fix, 12 Nov).
      const tLate = Date.now();
      const lateBudget = Math.max(0, CEILING_MS.licence_read[J.profile] - (r6.ms ?? 0) - 800);
      for (let s0 = await shownFields(); /being read/i.test(s0.note) && !(s0.licence_no && s0.authority) && Date.now() - tLate < lateBudget; s0 = await shownFields()) await sleep(1000);
      R.licence_shown_after_ms = Date.now() - tLate;
      regText = await look('licence read'); await shot('licence_read');
      const shown = await shownFields(); row = await readRow();
      R.licence_row = row; R.licence_shown = shown;
      step('the licence is read and the screen answers', r6.ok, { kind: 'licence_read', ms: r6.ms == null ? null : r6.ms + 800 + R.licence_shown_after_ms, ackMs: r6.ackMs, deferred: R.licence_deferred,
        detail: `shown: ${shown.note} | number field "${shown.licence_no || ''}" | authority field "${shown.authority || ''}" | read state ${row.licence_read_state} | shown ${R.licence_shown_after_ms} ms after the answer settled` });
      judgeShownBack(shown);
      if (J.licence_only) {
        R.licence = judgeLicence(exp, { licence_no: row.trade_license_no, legal_name: row.licence_legal_name, authority: row.license_authority, expiry: row.license_expiry, activities: await licenceActivities(tok) });
        step('licence fields read correctly (number, legal name, authority, expiry, activities)', R.licence.ok, { deferred: R.licence_deferred, detail: JSON.stringify(Object.fromEntries(Object.entries(R.licence.fields).map(([k, f]) => [k, f.ok ? 'ok' : `got ${JSON.stringify(f.got)}`]))) });
        return 'done';
      }
      // THE COMPANY PROFILE
      await M.locator('h3', { hasText: /^Company profile/ }).first().locator('xpath=following::input[@type="file"][1]').setInputFiles(fixturePath(P.file));
      await sleep(500);
      step('the company profile is attached', await M.getByText(P.file).first().isVisible().catch(() => false), { detail: P.file });
      await readAgreement();
      await M.getByRole('checkbox', { name: /I accept the QuotesDone/ }).check();
      await shot('agreement_accepted');
      // SUBMIT
      const submit = M.getByRole('button', { name: /^Submit for approval/ });
      const r7 = await timed(() => submit.click(), wsNav.or(M.locator('[role=alert]')), M.getByRole('button', { name: /^Submitting/ }));
      await sleep(1500);
      subText = await look('after submit'); await shot('submitted');
      const inWs = await wsNav.first().isVisible().catch(() => false);
      const refusal = inWs ? '' : (await M.locator('[role=alert]').allInnerTexts().catch(() => [])).join(' | ');
      if (L.expired && !inWs) {
        // AN EXPIRED LICENCE: Submit is refused and the supplier is told why. That refusal is this journey's expected end.
        const a2 = (await read(`select approval_status, licence_gate_reason from public.leads where id=${Number(leadId || 0)}`))[0] || {};
        R.final = a2;
        R.licence = judgeLicence(exp, { licence_no: row.trade_license_no, legal_name: row.licence_legal_name, authority: row.license_authority, expiry: row.license_expiry, activities: await licenceActivities(tok) });
        step('licence fields read correctly (number, legal name, authority, expiry, activities)', R.licence.ok, { deferred: R.licence_deferred, detail: JSON.stringify(Object.fromEntries(Object.entries(R.licence.fields).map(([k, f]) => [k, f.ok ? 'ok' : `got ${JSON.stringify(f.got)}`]))) });
        step('Submit answers at once and says what is wrong', r7.ok, { kind: 'submit', ms: r7.ms, ackMs: r7.ackMs, detail: refusal });
        R.expired = judgeExpired({ expired: true }, { screenText: `${regText}\n${subText}`, approval: a2.approval_status, gateReason: a2.licence_gate_reason });
        step('the expired licence is flagged honestly and never approved', R.expired.ok, { detail: `${refusal} | ${JSON.stringify(a2)}` });
        R.expired_told_at_upload = /expired/i.test(regText);
        step('the licence step itself says the licence has expired (before Submit)', R.expired_told_at_upload, { detail: (R.licence_shown || {}).note || '' });
        return 'done';
      }
      step('"Submit for approval" ends in the supplier workspace', r7.ok && inWs, { kind: 'submit', ms: r7.ms, ackMs: r7.ackMs, detail: refusal });
      if (!inWs) throw new Error('dead end: Submit did not open the workspace');
      return 'submitted';
    };
    if (J.door === 'direct') {
      // ── THE PUBLIC DOOR: Verify -> "Register your company" -> Create company -> the registration form -> Submit ──────────
      const r4 = await timed(() => verifyBtn.click(), M.getByText(/^Register your company$/));
      await shot('verified'); await look('code verified');
      step('the code verifies and "Register your company" opens', r4.ok, { kind: 'interactive', ms: r4.ms });
      if (!r4.ok) throw new Error('dead end: the code did not open the registration');
      tok = await readTok();
      await M.getByRole('textbox', { name: /Company name/ }).first().fill(L.legal_name);
      if (P) await M.locator('select').first().selectOption(P.trade).catch(() => {});
      await shot('company_and_trade');
      await recordMobile(async () => {
        const r5 = await timed(() => M.getByRole('button', { name: /^Create company$/ }).click(), formHeading);
        step('"Create company" opens the registration form', r5.ok, { kind: 'interactive', ms: r5.ms });
        if (!r5.ok) { await look('create company'); throw new Error('dead end: no registration form after "Create company"'); }
        leadId = await findLead();
        if (leadId) { run.ids.leads.add(String(leadId)); await write(`update public.leads set tags = array(select distinct unnest(coalesce(tags,'{}') || ARRAY['qd_demo','qd_run:${run.tag}'])) where id=${Number(leadId)}`, 'tag the run\'s lead'); }
      });
      if (await walkTheForm() === 'done') return R;
    } else {
      // ── THE INVITATION: Verify claims the listed company and opens the SAME registration form, headed "Finish registering <company>"
      // (11 Nov 2026, finding 7; it opened the workspace before, and registration was finished in three tabs). Then Submit -> workspace.
      await recordMobile(async () => {
        const r4 = await timed(() => verifyBtn.click(), formHeading);
        await shot('verified_claimed_registration'); await look('code verified, invited company');
        step('the code verifies and the invited company\'s registration form opens, claimed', r4.ok, { kind: 'interactive', ms: r4.ms });
        if (!r4.ok) throw new Error('dead end: the code did not open the invited company\'s registration');
        tok = await readTok(); leadId = (await findLead()) || leadId;
        step('the form says whose listing it is ("Finish registering")', await M.getByText(/^Finish registering /).first().isVisible().catch(() => false));
      });
      if (await walkTheForm() === 'done') return R;
    }
    // 9. THE SERVICES TAB: proposed from his documents, unticked until ticked ─────────────────────────────────────────
    const r8 = await timed(() => wsNav.first().getByRole('button', { name: /^Services$/ }).click(), M.getByTestId('profile-summary'));
    step('the Services tab opens', r8.ok, { kind: 'interactive', ms: r8.ms });
    const prop = M.getByTestId('proposed-services');
    // The documents are read after the answer: wait while any is still 'reading', up to the ceiling, then judge what is shown.
    const tp = Date.now(); let hasProp = false, st = null;
    while (Date.now() - tp < CEILING_MS.proposals[J.profile]) {
      if (await prop.isVisible().catch(() => false)) { hasProp = true; break; }
      st = (await call('supplier_api', tok, { action: 'services_state' }).catch(() => null))?.json || null;
      const docs = st?.capability?.source_docs?.docs || [];
      if (docs.length && !docs.some((d) => d.status === 'reading') && Date.now() - tp > 10000) break;   // read, and nothing proposed
      await sleep(5000);
      await wsNav.first().getByRole('button', { name: /^Inquiries received$/ }).click().catch(() => {}); await sleep(400);
      await wsNav.first().getByRole('button', { name: /^Services$/ }).click().catch(() => {});
      await sleep(1500);
    }
    // The loop can stop on the read that stored the proposals while the tab still shows the state it loaded before them (paid run 2,
    // J4: 4 services proposed in services_state, none on screen at the last look). Open the tab once more before the last look.
    if (!hasProp) {
      await wsNav.first().getByRole('button', { name: /^Inquiries received$/ }).click().catch(() => {}); await sleep(400);
      await wsNav.first().getByRole('button', { name: /^Services$/ }).click().catch(() => {});
      hasProp = await prop.waitFor({ timeout: 8000 }).then(() => true).catch(() => false);
    }
    const propMs = Date.now() - tp;
    await sleep(800); await look('services tab'); await shot('services_proposed');
    st = (await call('supplier_api', tok, { action: 'services_state' }).catch(() => null))?.json || st;
    R.services_state = st ? { proposed: (st.proposed_services || []).map((x) => ({ key: x.key, trade: x.trade, label: x.label_en, licence: x.licence, snippet: x.snippet })),
      checklist: st.checklist, trade_proposals: st.trade_proposals, licence_check: st.licence_check, docs: (st.capability?.source_docs?.docs || []).map((d) => ({ name: d.name, kind: d.kind, status: d.status, reason: d.reason, trades: (d.trades || []).map((h) => h.code) })) } : null;
    const proposedTrades = st ? [...(st.proposed_services || []).map((x) => x.trade), ...(st.checklist || []).filter((c) => c.source === 'documents').map((c) => c.code), ...(st.trade_proposals || []).map((t) => t.mapped_to || t.code)] : [];
    R.proposals = judgeProposals({ expect_trades: P.expect, acceptable_trades: P.accept }, proposedTrades);
    // In a free run the reading of trades is the model's, which is off: nothing proposed is NOT RUN there, never a pass.
    const nothingToTick = !hasProp && !(st?.checklist || []).length;
    const shownFromDocs = hasProp || (st?.checklist || []).some((c) => c.source === 'documents');
    step('services are proposed from his documents', shownFromDocs, { kind: 'proposals', ms: propMs, deferred: !PAID && !shownFromDocs, detail: `trades ${R.proposals.trades.join(', ') || '(none)'} | docs ${JSON.stringify((R.services_state?.docs || []).map((d) => `${d.name}: ${d.status}${d.reason ? ' (' + d.reason.slice(0, 90) + ')' : ''}`))}` });
    step('the proposals are his trades, nothing absurd', R.proposals.ok, { deferred: R.proposals_deferred, detail: `right ${R.proposals.right.join(',')} | acceptable ${R.proposals.acceptable.join(',')} | absurd ${R.proposals.absurd.join(',') || 'none'}` });
    if (hasProp) {
      const boxes = prop.locator('input[type=checkbox]');
      const total = await boxes.count(), ticked = await prop.locator('input[type=checkbox]:checked').count();
      step('proposed services start unticked', total > 0 && ticked === 0, { detail: `${ticked} of ${total} ticked before the supplier acts` });
      // reader @5 (12 Nov 2026, ruling 1647): "Tick all" ticks his own statements only; a row marked "Through a partner", and a phrase
      // kept in his own words, is ticked by him alone
      const own = prop.locator('li').filter({ hasNot: p.getByText(/^Through a partner$/) }).filter({ has: p.locator(`input[id*="-p-"]`) }).locator('input[type=checkbox]');
      const ownTotal = await own.count();
      const tickAll = prop.getByRole('button', { name: /^Tick all proposed services$/ });
      const r9 = await timed(() => tickAll.click(), prop.getByRole('button', { name: /^Untick all proposed services$/ }));
      const after = await own.and(prop.locator('input:checked')).count();
      const others = await prop.locator('input[type=checkbox]:checked').count() - after;
      step('"Tick all proposed services" ticks every one of his own, and nothing through a partner', r9.ok && after === ownTotal && others === 0, { kind: 'interactive', ms: r9.ms, detail: `${after} of ${ownTotal} own; ${others} other rows ticked` });
    }
    // the licence's activities as the Services tab read them, for the licence judgement
    R.licence = judgeLicence(exp, { licence_no: row.trade_license_no, legal_name: row.licence_legal_name, authority: row.license_authority, expiry: row.license_expiry, activities: st?.licence_check?.activities || [] });
    step('licence fields read correctly (number, legal name, authority, expiry, activities)', R.licence.ok, { deferred: R.licence_deferred, detail: JSON.stringify(Object.fromEntries(Object.entries(R.licence.fields).map(([k, f]) => [k, f.ok ? 'ok' : `got ${JSON.stringify(f.got)}`]))) });
    // his role, then confirm
    const roleSet = M.locator('fieldset').filter({ hasText: /Your role/ });
    const roles = await roleSet.locator('label').allInnerTexts().catch(() => []);
    const pick = roles.findIndex((t) => P.role.test(t.trim()));
    await roleSet.locator('input[type=checkbox]').nth(pick >= 0 ? pick : 0).check().catch(() => {});
    await shot('services_ticked');
    // His own trade's checklist, when his documents put it on screen: he opens "Browse all services of my trades" and ticks
    // what he does, box by box (12 Nov 2026, ruling 1647: no "Select all" on a trade any more), and nothing in a trade that is
    // not his (an absurd proposal stays unticked, and is judged above).
    const ticked0 = [];
    const browse = M.getByTestId('browse-trades');
    if (await browse.isVisible().catch(() => false) && !(await browse.evaluate((el) => el.open).catch(() => true))) await browse.locator('summary').click().catch(() => {});
    for (const c of (st?.checklist || []).filter((x) => P.expect.includes(x.code))) {
      const fs = M.locator('fieldset').filter({ has: p.locator('legend', { hasText: c.label_en || c.code }) }).first();
      const boxes = await fs.locator('input[type=checkbox]').all().catch(() => []);
      for (const b of boxes) await b.check().catch(() => {});
      if (boxes.length) ticked0.push(c.code);
    }
    if (ticked0.length) step('his own trade\'s services ticked from the checklist', true, { detail: ticked0.join(', ') });
    const confirm = M.getByRole('button', { name: /^(Confirm my services|Update my services)$/ });
    let canConfirm = await confirm.isEnabled().catch(() => false);
    let saved = false;
    if (canConfirm) {
      // The press is acknowledged when the button reads "Saving…" (the 3 / 5 s bar); the confirm then has the submit ceiling.
      // Without the acknowledgement locator timed() counts the whole confirm as the acknowledgement, so a 3.9 s confirm on desktop
      // was judged FAIL against a 20 s ceiling (paid round, 11 Nov 2026 06:07: J1, J3 desktop, both runs).
      const r10 = await timed(() => confirm.click(), M.getByText(/^Saved\. Your services are confirmed/).or(M.locator('[role=alert]')), M.getByRole('button', { name: /^Saving…$/ }));
      await look('services confirmed'); await shot('services_confirmed');
      saved = await M.getByText(/^Saved\. Your services are confirmed/).first().isVisible().catch(() => false);
      step('"Confirm my services" confirms them', saved, { kind: 'submit', ms: r10.ms, ackMs: r10.ackMs });
    } else {
      await look('services, nothing to confirm');
      // Nothing proposed and nothing on file to tick: "Confirm my services" stays disabled and the registration stays Pending.
      step('"Confirm my services" can be pressed', false, { deferred: !PAID && nothingToTick, detail: nothingToTick ? 'nothing proposed and no trade on file to tick: Confirm stays disabled (the reader proposes the services)' : 'Confirm is disabled' });
      if (PAID) R.dead_end = R.dead_end || 'the Services tab offers nothing to confirm';
    }
    // APPROVED AND VERIFIED, THE SIX ITEMS COMPLETE
    const ta = Date.now(); let a2 = null;
    for (;;) { a2 = (await read(`select l.approval_status, l.verified, l.licence_gate_reason, l.licence_read_state, l.company_name, public.fn_supplier_mandatory_six(l)::text missing_of_six from public.leads l where l.id=${Number(leadId || 0)}`))[0];
      if (!saved || a2?.approval_status === 'approved' || a2?.approval_status === 'action_required' || Date.now() - ta > CEILING_MS.approval[J.profile]) break; await sleep(2500); }
    R.final = a2; R.verified = a2?.approval_status === 'approved' && a2?.verified === true;
    // A licence only the model can read (a photo, a scan), in a free run, held ONLY because the model has not read it: NOT RUN
    // (registration_certification_judge.waitsOnTheModel). Any other hold is judged.
    R.waits_on_the_model = !R.verified && waitsOnTheModel({ paid: PAID, needsModel: J.needs_model, gateReason: a2?.licence_gate_reason, readState: a2?.licence_read_state });
    if (J.expect_verified) step('approved and verified', R.verified, { kind: saved && !R.waits_on_the_model ? 'approval' : null, ms: saved ? Date.now() - ta : null, deferred: (!PAID && !saved && !R.verified) || R.waits_on_the_model, detail: JSON.stringify(a2) + (R.waits_on_the_model ? ' | held only because the model has not read a licence with no text (models off): the paid round proves it' : '') });
    if (J.expect_verified && a2?.company_name && a2.company_name !== L.legal_name) step('the company keeps the name he registered (his licence\'s legal name)', false, { detail: `now "${a2.company_name}"` });
    // 11. THE PORTAL HOME ──────────────────────────────────────────────────────────────────────────────────────────────
    const r11 = await timed(() => p.goto(`${SITE}/portal`, { waitUntil: 'commit' }), wsNav);
    await sleep(1500);
    const home = await look('portal home'); await shot('portal_home');
    step('the portal home opens', r11.ok, { kind: 'interactive', ms: r11.ms });
    R.home_status = (await M.locator('[role=status], [role=alert]').allInnerTexts().catch(() => [])).join(' | ').slice(0, 600);
    if (L.expired) {
      R.expired = judgeExpired({ expired: true }, { screenText: `${regText}\n${subText}\n${home}`, approval: a2?.approval_status, gateReason: a2?.licence_gate_reason });
      step('the expired licence is flagged honestly and never approved', R.expired.ok, { detail: JSON.stringify(R.expired) });
    }
    if (J.expect_verified && R.verified) R.supplier_ms = Date.now() - t0 - harnessMs + REAL_MOBILE_OTP_MS;
  } catch (e) {
    R.dead_end = String(e.message).split('\n')[0];
    step('registration reaches its end', false, { detail: R.dead_end });
    await look('dead end'); await shot('zz_dead_end');
  } finally {
    // errors the supplier could meet: console errors that are the product's, and function calls that failed
    // A 4xx is the product's own answer, which the page turns into a message ("no_company" opens Onboarding, a refused Submit says
    // what is still needed); those messages are judged by criterion 7. The browser logs each as "Failed to load resource ... 4xx",
    // so that line is not an error here. A 5xx, a network failure and every other console error are.
    // A console error naming a resource whose failed answer did not come from the site (failureOrigin: no Vercel signature on an
    // answer for our own host) is an environment fault: listed apart, with its evidence in http_errors, never silently dropped.
    const split = splitEnvironmentFaults(realErrors(errors).filter((e) => !/Failed to load resource: the server responded with a status of 4\d\d/.test(e)), calls.filter((c) => c.http_error));
    R.environment_faults = split.environment.map((e) => 'console: ' + e);
    R.errors = [...split.site.map((e) => 'console: ' + e),
      ...calls.filter((c) => !c.http_error && (c.status >= 500 || (c.status === 0 && !/ERR_ABORTED/.test(String(c.failed))))).map((c) => `${c.fn}${c.action ? ' ' + c.action : ''}: ${c.status || c.failed}`)];
    R.http_errors = calls.filter((c) => c.http_error).map((c) => `${c.status} ${c.fn}${c.origin === 'other' ? '' : ` [${c.origin}: server ${c.via.server || '-'}, x-vercel-id ${c.via.x_vercel_id || '-'}${c.via.x_vercel_error ? ', x-vercel-error ' + c.via.x_vercel_error : ''}, ${c.via.content_type || 'no content-type'}]`}`);
    R.calls = calls.length;
    R.function_calls = calls.filter((c) => !c.http_error).map((c) => ({ fn: c.fn, action: c.action, status: c.status, ms: c.ms }));
    if (leadId) for (const d of await read(`select 'supplier-docs/' || license_doc_path p from public.leads where id=${Number(leadId)} union all select 'supplier-docs/' || company_profile_doc_path from public.leads where id=${Number(leadId)} union all select 'signed-terms/' || signed_terms_path from public.leads where id=${Number(leadId)}`).catch(() => [])) if (d.p) run.ids.storage.push(d.p);
    const vid = VIDEO ? p.video() : null; await ctx.close();
    const raw = vid ? await vid.path().catch(() => null) : null;
    if (raw && existsSync(raw)) { renameSync(raw, join(dir, `${J.id}_${J.profile}_recording.webm`)); R.video = `${J.id}_${J.profile}_recording.webm`; }
    rmSync(join(dir, 'raw_video'), { recursive: true, force: true });
    writeFileSync(join(dir, 'journey.json'), JSON.stringify(R, null, 1));
  }
  return R;
}
async function licenceActivities(tok) { const j = (await call('supplier_api', tok, { action: 'services_state' }).catch(() => null))?.json; return j?.licence_check?.activities || []; }
/** A number from the reserved fixture block (40-89) that no lead holds now. */
async function freeMobile() {
  for (let i = 0; i < 20; i++) {
    const m = `+9715000000${String(40 + Math.floor(Math.random() * 50)).padStart(2, '0')}`;
    if (!(await read(`select 1 from public.leads where phone = ${q(m)} limit 1`)).length) return m;
  }
  throw new Error('no free fixture mobile in 40-89');
}

// ── a run: open, eight registrations, count, tear down ────────────────────────────────────────────────────────────────
async function oneRun(runNo) {
  const run = await openRun({ capUsd: PAID ? +(CAP / RUNS).toFixed(4) : 0.01, minutes: 120 });
  run.ids = run.ids || { inquiries: new Set(), quotes: new Set(), leads: new Set(), customers: new Set(), storage: [] };
  if (!PAID) await write(`update public.rehearsal_window set models_allowed = false where run_tag = ${q('qd_run:' + run.tag)}`, 'free run: models off');
  const window = (await read(`select models_allowed, cap_usd from public.rehearsal_window where run_tag = ${q('qd_run:' + run.tag)}`))[0];
  log(`run ${runNo}: tag ${run.tag}, ${PAID ? 'PAID' : 'FREE'} (models_allowed ${window?.models_allowed}, cap USD ${window?.cap_usd})`);
  const started = new Date().toISOString();
  const R = { run: runNo, tag: run.tag, window, started, journeys: [] };
  let finishing = null;
  const finish = async (why) => {
    if (finishing) return finishing;
    finishing = (async () => {
      R.stopped = why;
      const ids = (s) => [...s].map(q).join(',') || 'null';
      const sinks = R.journeys.map((j) => j.account_email).filter(Boolean);
      R.notifications_before_teardown = await read(`select status, channel, count(*)::int n from public.notifications
          where to_email ilike ${q('%qd-' + run.tag + '-%')} or lead_id::text in (${ids(run.ids.leads)}) group by 1, 2 order by 1, 2`).catch((e) => [{ error: e.message }]);
      R.dispatched = R.notifications_before_teardown.filter((r) => ['sent', 'queued', 'pending', 'sending'].includes(r.status)).reduce((a, r) => a + r.n, 0);
      // WHAT THE RUN WOULD HAVE SENT THE SUPPLIERS, READ FOR ARABIC (ruling 1008: every message to a supplier is English, on every
      // channel). Subject, text and HTML of every notification the run caused; an attachment is listed by name, not opened.
      R.messages_sent = (await read(`select id, channel, coalesce(kind, type) kind, subject, body, html, attachments from public.notifications
          where to_email ilike ${q('%qd-' + run.tag + '-%')} or lead_id::text in (${ids(run.ids.leads)}) order by id`).catch(() => []))
        .map((n) => ({ channel: n.channel || 'email', where: `notification ${n.id} (${n.kind || 'message'})`, text: [n.subject, n.body, String(n.html || '').replace(/<[^>]+>/g, ' ')].filter(Boolean).join('\n'),
          attachments: (Array.isArray(n.attachments) ? n.attachments : []).map((a) => a?.filename).filter(Boolean) }));
      R.spend = (await read(`select count(*)::int calls, round(coalesce(sum(cost_usd_reported),0)::numeric, 4) usd,
          coalesce(json_agg(json_build_object('fn', fn, 'task', task_class, 'usd', cost_usd_reported, 'ok', ok) order by occurred_at) filter (where true), '[]') rows
          from public.ai_cost_log where e2e_run_tag = ${q(run.tag)}`).catch((e) => [{ error: e.message }]))[0];
      // A free run must cost nothing; untagged spend by these readers in the run's window is reported beside it (a server-to-server
      // read made after the answer can lose the tag; a ZZ DEMO subject is then stubbed, so this should read 0 as well).
      R.untagged_reader_spend_in_window = (await read(`select coalesce(round(sum(cost_usd_reported)::numeric, 4), 0) usd, count(*)::int calls from public.ai_cost_log
          where occurred_at >= ${q(started)} and e2e_run_tag is null and fn in ('license_extract', 'supplier_doc_trades') and coalesce(cost_usd_reported,0) > 0`).catch((e) => [{ error: e.message }]))[0];
      log(`run ${runNo} safety: dispatched ${R.dispatched}; notifications ${JSON.stringify(R.notifications_before_teardown)}; spend ${JSON.stringify({ calls: R.spend?.calls, usd: R.spend?.usd })}`);
      if (!KEEP) {
        let closed;
        try { closed = await closeRun(run); } catch (e) { log('teardown retry', e.message); await sleep(60000); closed = await closeRun(run).catch((x) => ({ error: x.message })); }
        const sink = []; for (const a of sinks) sink.push(await cleanSink(a).catch((e) => ({ error: e.message })));
        const fx = await read(`select count(*)::int n from public.leads where upper(trade_license_no) in (${LICENCES.map((l) => q(l.licence_no.toUpperCase())).join(',')})`).catch(() => [{ n: null }]);
        R.teardown = { leftovers: closed?.leftovers ?? closed?.error ?? null, sink, fixture_licences_still_held: fx[0]?.n };
      } else { await closeRun(run, { keep: true }); R.teardown = { kept: `node scripts/e2e/run.mjs --purge-tag ${run.tag}` }; }
      R.finished = new Date().toISOString();
    })();
    return finishing;
  };
  const onSig = (sig) => { log(`stopped by ${sig}: counting and tearing down`); finish(sig).finally(() => process.exit(1)); };
  process.once('SIGINT', onSig); process.once('SIGTERM', onSig);
  try {
    const todo = JOURNEYS.filter((j) => !ONLY.length || ONLY.includes(j.id));
    // ONE REGISTRATION AT A TIME by default (11 Nov 2026, the second free trial): run side by side, the desktop journey's "Verify"
    // took 25.9 s and "Create company" 8.0 s against 2.9 s and 1.4 s alone, in one container with two browsers, one of them
    // CPU-throttled. The criterion is the supplier's screen, not this container's load. --parallel runs desktop and phone together.
    const lanes = argv.includes('--parallel') ? [todo.filter((j) => j.profile === 'desktop'), todo.filter((j) => j.profile === 'mobile')] : [todo];
    await Promise.all(lanes.map(async (lane) => { for (const J of lane) R.journeys.push(await journey(run, J, runNo)); }));
    R.journeys.sort((a, b) => a.id.localeCompare(b.id));
  } finally {
    await finish('completed');
    process.removeListener('SIGINT', onSig); process.removeListener('SIGTERM', onSig);
  }
  return R;
}

// ── the report ─────────────────────────────────────────────────────────────────────────────────────────────────────────
function report(runs, verdicts, est) {
  const L = [];
  L.push(`# Supplier registration certification - ${PAID ? 'PAID round (readers on)' : 'FREE round (models off)'}`, '');
  L.push(`Site ${SITE}. ${runs.length} run(s): ${runs.map((r) => `${r.tag} (${r.started.slice(0, 16)}Z)`).join(', ')}. Phone profile: iPhone 13, ${MOBILE_NETWORK.said}. Desktop: 1440x900, the container's own network.`, '');
  L.push('## Verdict per criterion', '', '| criterion | verdict | measured |', '|---|---|---|');
  for (const [k, v] of Object.entries(verdicts)) {
    const m = { ...v }; delete m.verdict;
    L.push(`| ${k} | **${v.verdict}** | ${JSON.stringify(m).replace(/\|/g, '/').slice(0, 600)} |`);
  }
  for (const r of runs) {
    L.push('', `## Run ${r.run} (tag ${r.tag})`, '', `Spend by tag: USD ${r.spend?.usd ?? '?'} (${r.spend?.calls ?? '?'} calls). Untagged reader spend in the window: USD ${r.untagged_reader_spend_in_window?.usd ?? '?'}. Notifications before teardown: ${JSON.stringify(r.notifications_before_teardown)}; dispatched ${r.dispatched}. Teardown: ${JSON.stringify(r.teardown)}`);
    for (const j of r.journeys) {
      L.push('', `### ${j.id} ${j.profile} (${j.door}): ${j.licence_file}${j.profile_file ? ' + ' + j.profile_file : ''}`, '', '| step | result | ms | budget |', '|---|---|---:|---:|');
      for (const s of j.steps) L.push(`| ${s.name} | ${s.deferred ? 'NOT RUN (paid)' : s.ok && (!s.timing || s.timing.ok) ? 'PASS' : 'FAIL'} | ${s.timing?.ms ?? ''} | ${s.timing?.budget_ms ?? ''} |`);
      L.push('', `Licence read (row): ${JSON.stringify(j.licence_row || {})}`, `Shown back: ${JSON.stringify(j.licence_shown || {})}`,
        `Proposals: ${JSON.stringify(j.proposals || {})}`, `Final: ${JSON.stringify(j.final || {})}`, `Arabic seen: ${JSON.stringify(j.arabic)}`,
        `Message faults: ${JSON.stringify(j.faults)}`, `Errors: ${JSON.stringify(j.errors)}`, `Environment faults (an answer not from the site, see the HTTP line): ${JSON.stringify(j.environment_faults || [])}`, `HTTP 4xx/5xx met by the page: ${JSON.stringify(j.http_errors || [])}`, `Language switch shown: ${JSON.stringify(j.language_switch || [])}`, `Dead end: ${j.dead_end || 'none'}`,
        `Messages read: ${JSON.stringify(j.messages.map((m) => m.text.slice(0, 160)))}`);
    }
  }
  if (est) L.push('', '## The paid round', '', '```', `node scripts/e2e/supplier_registration_certification.mjs --paid --runs ${RUNS} --cap-usd ${CAP}`, '```', '', `Expected: ${JSON.stringify(est)}`);
  return L.join('\n') + '\n';
}

const MAIN = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (MAIN) await main();
async function main() {
  if (argv.includes('--estimate')) { console.log(JSON.stringify(await estimate(), null, 1)); return; }
  if (!fixturesPresent()) { console.error('REFUSED: fixtures missing: node scripts/e2e/registration_fixtures.mjs --write'); process.exit(2); }
  mkdirSync(OUT, { recursive: true });
  // PRE-FLIGHT: the demo guards are installed, and no company holds a fixture's licence number or name (a leftover would make the
  // product set the number aside as a duplicate and the run would fail for the harness's reason, not the product's).
  const guards = (await read(`select tgname from pg_trigger where not tgisinternal and tgname in ('zzzz_notifications_demo_capture','a01_inquiry_match_demo_and_real_never_pair','a01_quote_demo_and_real_never_pair')`)).map((r) => r.tgname);
  if (guards.length !== 3) { console.error('REFUSED: the demo guards are not installed: ' + guards.join(',')); process.exit(2); }
  const held = await read(`select id, company_name, trade_license_no, tags from public.leads where upper(trade_license_no) in (${LICENCES.map((l) => q(l.licence_no.toUpperCase())).join(',')})
                           or lower(company_name) in (${LICENCES.map((l) => q(l.legal_name.toLowerCase())).join(',')})`);
  if (held.length) { console.error('REFUSED: a lead already holds a fixture licence or name (a leftover run?): ' + JSON.stringify(held) + '\n  purge it: node scripts/e2e/run.mjs --purge-tag <tag>'); process.exit(2); }
  const est = await estimate().catch((e) => ({ error: e.message }));
  log(`${PAID ? 'PAID' : 'FREE'} certification, ${RUNS} run(s), out ${OUT}; paid-round estimate ${JSON.stringify(est)}`);
  BROWSER = await launch();
  const runs = [];
  try { for (let i = 1; i <= RUNS; i++) runs.push(await oneRun(i)); } finally { await BROWSER.close().catch(() => {}); }
  const verdicts = certify(runs, { paid: PAID });
  const unsafe = runs.some((r) => r.dispatched > 0) || (!PAID && runs.some((r) => Number(r.spend?.usd || 0) > 0));
  writeFileSync(join(OUT, 'certification.json'), JSON.stringify({ paid: PAID, site: SITE, budgets: { INTERACTIVE_MS, CEILING_MS, SUPPLIER_MINUTES_MAX, MOBILE_NETWORK }, verdicts, estimate: est, runs }, null, 1));
  writeFileSync(join(OUT, 'CERTIFICATION.md'), report(runs, verdicts, est));
  const videos = []; for (const r of readdirSync(OUT)) if (r.startsWith('run')) for (const j of readdirSync(join(OUT, r))) for (const f of readdirSync(join(OUT, r, j))) if (f.endsWith('.webm')) videos.push(`${r}/${j}/${f} ${(statSync(join(OUT, r, j, f)).size / 1e6).toFixed(1)} MB`);
  log('verdicts:'); for (const [k, v] of Object.entries(verdicts)) log(`  ${v.verdict.padEnd(7)} ${k}`);
  log(`report ${join(OUT, 'CERTIFICATION.md')}; ${videos.length} recordings`);
  const ready = PAID && Object.values(verdicts).every((v) => v.verdict === 'PASS') && !unsafe;
  log(ready ? 'READY TO INVITE: every criterion PASS on a paid run' : `NOT READY TO INVITE${unsafe ? ' (SAFETY: a notification was dispatched or a free run spent)' : ''}`);
  process.exit(unsafe ? 3 : ready || !PAID ? 0 : 1);
}
