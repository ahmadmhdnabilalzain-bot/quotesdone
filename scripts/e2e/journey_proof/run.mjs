// scripts/e2e/journey_proof/run.mjs — THE JOURNEY PROOF: each of the founder's journeys walked on the live site and
// written up as ONE DOSSIER PDF on the QuotesDone template, with the evidence itself beside it. Seat: customer_support.
// Founder ledger 1684 (13 Nov 2026); 1604 (10 Nov: "proof, not a test summary ... screenshots and PDFs"); 1683 (anonymity
// is the core); 1671/1672 (every document is a PDF in our template).
//
//   node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON scripts/e2e/journey_proof/run.mjs --dry --journeys A   models OFF, USD 0
//   (the flag only silences Node's notice that it re-parsed _shared/not_reached.ts, a TypeScript module demo_factory imports)
//   node scripts/e2e/journey_proof/run.mjs --journeys A --inputs <dir>        ONE paid journey, capped (scenarios.mjs cap_usd)
//   options: --journeys A,B,B2,C  --inputs <dir with the auditors' files>  --out <dir>  --keep (no teardown)
//            --clean-dropbox (remove this run's _sandbox folder after reading it back; default: left for the founder)
//   env:     SUPABASE_ACCESS_TOKEN (the harness's database door), QD_SITE (default https://quotesdone.com),
//            QD_PIPER_VOICES (B2 and C: the offline voices en_GB-alan-medium, ar_JO-kareem-medium)
//
// EACH JOURNEY IS ITS OWN RUN: its own tag, its own rehearsal window, its own spending CAP (fn_kernel_paid_provider_gate
// refuses a model call once the tag's ai_cost_log spend reaches it), its own teardown. A journey that stops still counts
// its notifications by status, reads its spend and writes its dossier with what it reached.
//
// WHAT THE DOSSIER PROVES, AND HOW (record.mjs is the shape; dossier_body.ts prints it)
//   1  the customer signs up through the site's own door (quotesdone.com/me, a real e-mailed code read from Resend's sink),
//      in a CLEAN phone-size browser: no request interception. His signed-terms certificate is downloaded from Supabase
//      storage (bucket, path, size, SHA-256) and, at the end, read back from Dropbox: the platform's own backup files this
//      run's documents under /QuotesDone Backup/_sandbox/<tag>/ (a demo identity is never queued by the daily backup, so
//      the run asks the same backup code to file it there: fn_backup_sandbox_enqueue + dropbox_backup op 'sandbox', which
//      uploads and reads back size and content hash), then lists that folder against the records (op 'sandbox_verify').
//   2  the chat, turn by turn, timed by the browser: every question, the answer buttons, how long each reply took; each
//      file the customer gave and what the platform read from it (customer_api analyze_drawing / analyze_document).
//   3  the inquiry exactly as a supplier receives it: supplier_api inquiry_pdf, the files of inquiry_documents, the portal
//      screens (CLEAN context), the e-mail and WhatsApp composed for him (notifications; delivery to a demo identity is
//      suppressed by zzzz_notifications_demo_capture), and the ANONYMITY CHECK (anonymity.mjs) over all of it.
//   4  inquiry_matches as the LIVE matcher wrote it, against this run's suppliers made to be right / wrong emirate /
//      unrelated; any supplier the test itself invites is listed apart.
//   5  each supplier's own quotation (full identity), what extract_quote read, the quotation as the CUSTOMER sees it
//      (customer_api quote_pdf, the portal), and the anonymity check the other way.
//   6  every notification composed to the customer, in order. 7 quote_compare + compare_pdf. 8 the reveal in Stripe TEST
//      mode, reveal_invoice, what each side then sees, the confirmations composed. 9 storage.objects and doc_backups.
//   10 findings, ai_cost_log by step (record.mjs costByStep), and every stand-in.
//
// THE RUN TAG AND THE BROWSER (memory: an-intercepted-browser-cannot-prove-what-a-real-browser-allows.md)
//   The platform lets a demo account's model calls through, inside the cap, only for a request that proves the run:
//   the x-qd-e2e-run header with its secret, or a user JWT whose VERIFIED e-mail is qd-<tag>-...@example.invalid
//   (_shared/e2e_run.ts resolveE2eRunByIdentity). A customer who signed up through the real form has a resend.dev
//   address (the form refuses example.invalid), so his chat cannot be tagged by identity. Without the tag the model calls
//   are refused (fixture_no_spend), nothing is attributed to the run's cost and the cap does not apply. Suppression of
//   delivery does NOT depend on the tag (the demo identity alone suppresses it). So:
//     tagged context  ONLY for the steps that make model calls in the page (the chat). The tag rides only on calls to the
//                     project's /functions/v1 (browser.mjs carriesRunTag). Its screenshots are labelled as such.
//     clean context   for every picture that proves what a person SEES (the sign-up, his request, the supplier's screens,
//                     the quotations, the comparison, the reveal): a fresh context with the session in storageState, no
//                     route, no extra header. Each journey first proves its clean context enforces the browser's CORS
//                     rule (a fetch with a header no preflight allows is blocked; the same fetch without it is not).
//     preflight check for every function the page called in the tagged context: an OPTIONS from Node with the page's
//                     own header list and origin, checked by CONTENT (every header allowed, the origin echoed).
//   The supplier side's uploads and the hold desk are the portal's own calls made from Node with the supplier's session
//   (the same body QuoteForm sends), as the evidence pack did; their screens are then captured clean.
//
// SAFETY: ZZ DEMO names, qd-<tag> addresses at example.invalid or Resend's sink (accepted and dropped by Resend), the
// reserved +971 50 000 00xx block; demo and real never pair (a01_* triggers); every notification is counted by status
// before teardown and a sent/queued/pending one is a finding. Stripe TEST mode only (refused otherwise). Never touches a
// real customer or lead. No Dropbox write except the platform's own backup into its sandbox area.
import { mkdirSync, writeFileSync, readFileSync, existsSync, copyFileSync, statSync } from 'node:fs';
import { join, dirname, resolve, basename } from 'node:path';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { openRun, closeRun, makeDemoSupplier, openTradeForDemo, read, write, call, waitFor, BASE } from '../fixtures.mjs';
import { launch, SITE, portalUrl, carriesRunTag } from '../browser.mjs';
import { payHostedTestCheckout } from '../stripe_test_checkout.mjs';
import { readCode, cleanSink, isSink } from '../resend_sink.mjs';
import { keys, internalCred, makeInquiry } from '../../lib/demo_factory.mjs';
import { useHarness, htmlPdf, xlsx, nextAnswer, intakeTurn, speak, VOICE_INIT, quoteOne, summariseTop, quotationHtml } from '../evidence_pack.mjs';
import { SCENARIOS, SITE as JOB, SERVICE_WORDS, customerIdentity, supplierLetterhead, supplierIdentity, withFullIdentity, vatInclusiveOnly, asEvidenceJourney, scenarioProblems, OLD_QUOTATION } from './scenarios.mjs';
import { scan } from './anonymity.mjs';
import { clock, verdict, matcherVerdict, costByStep, secondsBetween, SECTION_TITLES } from './record.mjs';
import { sheets } from './sheet.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, '../../..');
const argv = process.argv.slice(2);
const val = (f, d = null) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : d; };
const DRY = argv.includes('--dry');
const KEEP = argv.includes('--keep');
const CLEAN_DROPBOX = argv.includes('--clean-dropbox');
const KEYS = (val('--journeys', 'A')).split(',').map((s) => s.trim().toUpperCase()).filter(Boolean);
const INPUTS = val('--inputs', process.env.QD_JOURNEY_INPUTS || '');
const OUT = resolve(val('--out', join(process.env.QD_EVIDENCE_OUT || '/tmp/qd-journey-proof', DRY ? 'dry' : 'real')));
const VOICES = process.env.QD_PIPER_VOICES || '';
process.env.QD_FIXTURES = '1';
process.env.QD_CHROMIUM_ARGS = [process.env.QD_CHROMIUM_ARGS || '', '--autoplay-policy=no-user-gesture-required'].join(' ').trim();
const q = (v) => `'${String(v).replace(/'/g, "''")}'`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);
const now = () => new Date().toISOString();
const sha256 = (b) => createHash('sha256').update(b).digest('hex');
/** Dropbox's own content hash (4 MiB blocks, SHA-256 of the concatenated block hashes), to compare with what it read back. */
export function dropboxContentHash(buf) {
  const parts = []; for (let o = 0; o < buf.length; o += 4194304) parts.push(createHash('sha256').update(buf.subarray(o, o + 4194304)).digest());
  return createHash('sha256').update(Buffer.concat(parts)).digest('hex');
}
const PHONE = { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, locale: 'en-GB' };
const CONSENT = JSON.stringify({ necessary: true, analytics: false, marketing: false, ts: Date.now() });
const twinOrigins = () => { const u = new URL(SITE); const h = u.hostname.replace(/^www\./, ''); const alt = h.endsWith('.ae') ? h.replace(/\.ae$/, '.com') : h.replace(/\.com$/, '.ae'); return [...new Set([u.origin, `https://${h}`, `https://www.${h}`, `https://${alt}`, `https://www.${alt}`])]; };
const STORE = { customer: ['qd-cust-token', 'qd-cust-refresh', 'qd-cust-auth'], supplier: ['qd-sup-token', 'qd-sup-refresh', 'qd-portal-auth'] };
/** A session carried into a browser as storage, never by interception. */
function storageFor(kind, s) {
  const [t, r, a] = STORE[kind];
  const auth = JSON.stringify({ access_token: s.access_token, refresh_token: s.refresh_token, expires_in: s.expires_in, expires_at: s.expires_at, token_type: s.token_type || 'bearer', user: s.user });
  return { cookies: [], origins: twinOrigins().map((origin) => ({ origin, localStorage: [{ name: t, value: s.access_token }, { name: r, value: s.refresh_token }, { name: a, value: auth }, { name: 'qd-lang', value: 'en' }, { name: 'qd-cookie-consent', value: CONSENT }] })) };
}
const pdfText = (f) => { const r = spawnSync('pdftotext', ['-layout', f, '-'], { encoding: 'utf8' }); return r.status === 0 ? r.stdout : ''; };
const pdfProps = (f) => { const r = spawnSync('pdfinfo', [f], { encoding: 'utf8' }); return r.status === 0 ? r.stdout.split('\n').filter((l) => /^(Title|Subject|Keywords|Author|Creator|Producer):/.test(l)).join('\n') : ''; };
const htmlText = (h) => String(h || '').replace(/<(script|style)[\s\S]*?<\/\1>/gi, ' ').replace(/<br\s*\/?>/gi, '\n').replace(/<\/(p|div|tr|li|h\d)>/gi, '\n').replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/[ \t]+/g, ' ').replace(/\n\s*\n+/g, '\n').trim();
const fetchBytes = async (url) => { const r = await fetch(url); if (!r.ok) throw new Error(`GET ${String(url).slice(0, 80)}: HTTP ${r.status}`); return Buffer.from(await r.arrayBuffer()); };

let BROWSER = null;

// ── the common stand-ins: what in every journey is not the product ────────────────────────────────────────────────
const STAND_INS = [
  'The customer is a demo identity made for this run (ZZ DEMO name, an address at Resend\'s test sink that accepts and drops mail, a mobile in the reserved block +971 50 000 00xx). He signed up through the real form; the e-mailed code was real and read back from the sink.',
  'His mobile code: a reserved number cannot receive an SMS or WhatsApp. The site refused to send one (shown in step 1) and the test then recorded the number as verified in the database.',
  'After the real sign-up the test gave the same account a password and a run marker, so it could open further browser sessions for him. Real customers sign in by e-mail code each time.',
  'During the chat, the test added its run tag to the platform calls the page made (request interception), because the platform lets a demo account\'s model calls through, inside this journey\'s spending cap, only with that tag. Every picture that proves what the customer or a supplier SEES was taken again in a clean browser with no interception, and the browser rules for the calls made during the chat were checked separately (step 10).',
  'The customer\'s words come from a script matched to the question asked. Nothing on the customer\'s side was written by a model.',
  'The suppliers are demo companies made by the test through the platform\'s own doors (licence and profile documents, the signed Supplier Agreement, services stated through the Services tab\'s own rewrite). They quoted by uploading their own PDF with the same call the portal\'s upload makes, from the test, not by clicking in a browser.',
  'No e-mail, WhatsApp or SMS reached anyone: every message to a demo identity is composed and kept by the platform, marked "suppressed", never handed to the mail or WhatsApp provider.',
  'The reveal fee was paid in Stripe TEST mode with Stripe\'s test card 4242 4242 4242 4242. No money moved.',
  'Dropbox: the daily backup never queues a demo identity\'s files. The test asked the platform\'s own backup code to file this run\'s documents in its sandbox area, /QuotesDone Backup/_sandbox/<run tag>/, by the same path a real customer\'s files take, and to read each one back.',
];

// ── one journey ────────────────────────────────────────────────────────────────────────────────────────────────────
async function journey(key) {
  const sc = SCENARIOS[key]; const J = asEvidenceJourney(sc);
  const dir = join(OUT, sc.folder); for (const d of ['', 'screens', 'shared', 'quotations', 'messages', 'customer_files']) mkdirSync(join(dir, d), { recursive: true });
  const rec = { journey: { key, title: sc.title, short: sc.short, how_made: sc.how_made, site: SITE, started: now(), finished: null, mode: DRY ? 'dry (models off)' : 'live', cap_usd: sc.cap_usd, estimate_usd: sc.estimate_usd, run_tag: null },
    sections: Object.fromEntries(Object.keys(SECTION_TITLES).map((k) => [k, { verdicts: [], gaps: [] }])), findings: [], stand_ins: [...STAND_INS], exhibits: [], steps: [] };
  const S = rec.sections; const C = clock(rec);
  const finding = (severity, step, text) => { rec.findings.push({ severity, step, text }); log('FINDING', severity, step, text); };
  const exhibit = (file, title, why, extra = {}) => { if (file && !rec.exhibits.some((e) => e.file === file)) rec.exhibits.push({ file, title, why, ...extra }); };
  const save = () => writeFileSync(join(dir, 'record.json'), JSON.stringify(rec, null, 1));
  if (sc.voice && !DRY && (!VOICES || !existsSync(join(VOICES, 'en_GB-alan-medium.onnx')))) throw new Error(`journey ${key} needs QD_PIPER_VOICES (piper voice en_GB-alan-medium) for its voice note`);
  const run = await openRun({ capUsd: sc.cap_usd, minutes: 120 });
  rec.journey.run_tag = run.tag; useHarness({ browser: BROWSER, run });
  if (DRY) await write(`update public.rehearsal_window set models_allowed = false where run_tag = ${q('qd_run:' + run.tag)}`, 'dry run: models off');
  log(`journey ${key}: ${sc.title} · run ${run.tag} · ${DRY ? 'DRY' : `cap USD ${sc.cap_usd}`}`);
  rec.stand_ins = rec.stand_ins.map((s) => s.replace('<run tag>', run.tag));
  const pageHeaders = new Map();   // fn -> the header names the page itself sent (for the preflight content check)
  const ids = { inquiries: new Set(), quotes: new Set() };
  const ctx = { sc, J, dir, rec, S, run, finding, exhibit, save, pageHeaders, ids, cust: null, sups: [], fixtures: [] };
  try {
    await clean_context_enforces_cors(ctx);
    await s1_signup(ctx); save();
    await prep_suppliers(ctx); save();
    await s2_chat(ctx); save();
    if (!ctx.quotable && DRY && ctx.cust) await dryRequest(ctx);
    if (ctx.quotable) {
      await s3_shared(ctx); save();
      await s4_matching(ctx); save();
      await s5_quotes(ctx); save();
      await s7_comparison(ctx); save();
      await s5_reverse_anonymity(ctx); save();
      await s8_reveal(ctx); save();
    } else finding('product', '2', 'The request was never sent to suppliers, so steps 3 to 8 could not happen.');
  } catch (e) { finding('harness', 'run', `the run stopped: ${String(e.stack || e.message).split('\n').slice(0, 3).join(' | ')}`); }
  try { await s6_notifications(ctx); } catch (e) { finding('harness', '6', e.message); }
  try { await co_company(ctx); } catch (e) { finding('harness', 'co', e.message); }
  try { await s9_filing(ctx); } catch (e) { finding('harness', '9', e.message); }
  try { await s10_close(ctx); } catch (e) { finding('harness', '10', e.message); }
  rec.journey.finished = now(); save();
  // teardown, after everything is read
  if (!KEEP) {
    let closed = null; try { closed = await closeRun(run); } catch (e) { await sleep(60000); closed = await closeRun(run).catch((x) => ({ error: x.message })); }
    if (ctx.cust?.email) await cleanSink(ctx.cust.email).catch(() => {});
    rec.teardown = { removed: closed?.removed?.summary ?? closed?.error ?? null, leftovers: closed?.leftovers ?? null };
  } else { await write(`update public.rehearsal_window set ended_at = now(), models_allowed = false where run_tag = ${q('qd_run:' + run.tag)} and ended_at is null`, 'rehearsal window'); rec.teardown = { kept: `node scripts/e2e/run.mjs --purge-tag ${run.tag}` }; }
  save();
  const d = spawnSync('deno', ['run', '--no-lock', '--node-modules-dir=none', `--allow-read=${REPO},${OUT}`, `--allow-write=${OUT}`, join(HERE, 'dossier.ts'), dir], { encoding: 'utf8', cwd: REPO });
  log('dossier', (d.stdout || '').trim(), (d.stderr || '').trim().slice(-400));
  return rec;
}

// ── the clean context: no route, no header; proved to enforce CORS before it is trusted ────────────────────────────
async function cleanContext(kind = null, session = null, opts = {}) {
  return await BROWSER.newContext({ ...PHONE, ...opts, ...(session ? { storageState: storageFor(kind, session) } : {}) });
}
/** A context for the chat only: the run tag on calls to the project's functions, and the page's own headers recorded. */
async function taggedContext(ctx, session) {
  const c = await cleanContext('customer', session);
  const extra = { 'x-qd-e2e-run': ctx.run.tag, 'x-qd-e2e-secret': await internalCred() };
  await c.route((u) => carriesRunTag(u, BASE), async (route) => {
    const req = route.request(); const fn = req.url().split('/functions/v1/')[1]?.split('?')[0];
    if (req.method() === 'OPTIONS') return route.continue();
    const set = ctx.pageHeaders.get(fn) || new Set(); for (const h of Object.keys(req.headers())) set.add(h.toLowerCase()); ctx.pageHeaders.set(fn, set);
    if (process.env.QD_ROUTE_FUNCTIONS_VIA_NODE === '1') {   // the cloud container's ~30 s cut (browser.mjs); off by default
      const h = req.headers(); const fwd = { ...Object.fromEntries(['authorization', 'content-type', 'apikey', 'x-client-info'].filter((k) => h[k]).map((k) => [k, h[k]])), ...extra };
      const res = await fetch(req.url(), { method: req.method(), headers: fwd, body: req.method() === 'GET' ? undefined : req.postData() });
      return route.fulfill({ status: res.status, headers: { 'access-control-allow-origin': '*', 'content-type': res.headers.get('content-type') || 'application/json' }, body: Buffer.from(await res.arrayBuffer()) });
    }
    return route.continue({ headers: { ...req.headers(), ...extra } });
  });
  return c;
}
async function clean_context_enforces_cors(ctx) {
  const c = await cleanContext(); const p = await c.newPage();
  await p.goto(SITE, { waitUntil: 'domcontentloaded', timeout: 60000 }).catch(() => {});
  const probe = (withBad) => p.evaluate(async ([u, bad]) => {
    try { const r = await fetch(u, { method: 'POST', headers: { 'content-type': 'application/json', ...(bad ? { 'x-qd-not-in-any-preflight': '1' } : {}) }, body: '{"action":"ping"}' }); return { reached: true, status: r.status }; }
    catch (e) { return { reached: false, error: String(e).slice(0, 120) }; }
  }, [`${BASE}/functions/v1/customer_api`, withBad]);
  const bad = await probe(true), good = await probe(false);
  await c.close();
  ctx.rec.cors_enforced = { blocked_with_a_disallowed_header: !bad.reached, reached_without_it: good.reached, bad, good };
  if (bad.reached || !good.reached) ctx.finding('harness', '10', `the clean browser context did not behave as a real browser (a disallowed header ${bad.reached ? 'was NOT blocked' : 'was blocked'}; the same call without it ${good.reached ? 'reached' : 'did not reach'} the function): its pictures prove less than they claim`);
}

// ── shots: phone-size, viewport only (a page of a phone), numbered ──────────────────────────────────────────────────
function shooter(ctx, prefix) {
  let n = 0; const list = [];
  const take = async (page, name, caption, { clean = true } = {}) => {
    const f = join(ctx.dir, 'screens', `${prefix}_${String(++n).padStart(2, '0')}_${name}.png`);
    await page.screenshot({ path: f }).catch(() => {});
    if (existsSync(f)) list.push({ path: f, caption: `${caption}${clean ? ' (phone, clean)' : ' (phone, run tag added)'}` });
    return f;
  };
  return { take, list };
}
const rel = (ctx, f) => f ? f.replace(ctx.dir + '/', '') : f;
function sheetsInto(ctx, shots, base) { try { return sheets(shots, join(ctx.dir, 'screens', base)).map((s) => ({ file: rel(ctx, s.path) })); } catch (e) { ctx.finding('harness', '-', `contact sheet ${base}: ${e.message}`); return []; } }

// ── 1 the customer signs up through the site's own door ────────────────────────────────────────────────────────────
async function s1_signup(ctx) {
  const st = clockStart(ctx, 's1'); const { run, S } = ctx; const sec = S.s1;
  const email = `delivered+qd-${run.tag}-cust1@resend.dev`; if (!isSink(email)) throw new Error('sink address shape: ' + email);
  const fullName = `ZZ DEMO ${ctx.sc.label} ${run.tag}`; const mobile = await freeMobile();
  sec.customer = { name: fullName, email, phone: mobile, site: JOB.said };
  sec.signup = { door: `The real sign-up on ${SITE}/me ("Create account"), in a clean phone-size browser: no request was altered or added by the test.`, steps: [], not_real: [] };
  const step = (what, result) => sec.signup.steps.push({ at: now(), what, result });
  const c = await cleanContext(); await c.addInitScript((v) => localStorage.setItem('qd-cookie-consent', v), CONSENT);
  const p = await c.newPage(); p.setDefaultTimeout(45000); const sh = shooter(ctx, 's1');
  try {
    await p.goto(`${SITE}/me`, { waitUntil: 'domcontentloaded' });
    await p.getByRole('tab', { name: /^Create account$/ }).click({ timeout: 30000 }).catch(() => {});
    await sh.take(p, 'create_account', 'He opens quotesdone.com/me, "Create account"');
    await p.getByRole('textbox', { name: /Email address/i }).first().fill(email);
    const t0 = Date.now(); await p.getByRole('button', { name: /^Create my account$/ }).click();
    const codeBox = p.locator('input[autocomplete="one-time-code"]');
    const sent = await codeBox.waitFor({ timeout: 25000 }).then(() => true).catch(() => false);
    await sh.take(p, 'code_step', 'The site e-mails him a 6-digit code');
    step('typed his e-mail and pressed "Create my account"', sent ? 'the code step opened' : 'NO code step');
    if (!sent) throw new Error('no code step');
    const got = await readCode(email, t0);
    step('opened the e-mail', got.code ? `Resend delivered "${got.subject}" from ${got.from} (${got.last_event})` : 'no code e-mail arrived');
    if (!got.code) throw new Error('no code e-mail');
    await codeBox.fill(got.code); await p.getByRole('button', { name: /^Verify & continue$/ }).click();
    await p.getByRole('heading', { name: /Complete your account/ }).waitFor({ timeout: 40000 });
    step('typed the code', '"Complete your account" opened');
    await p.getByRole('textbox', { name: /^Full name$/ }).fill(fullName); await p.getByRole('textbox', { name: /^Mobile$/ }).fill(mobile); await p.locator('#qd-dob').fill('1990-01-15');
    await sh.take(p, 'profile', 'Name, mobile and date of birth');
    await p.getByRole('button', { name: /^Save details$/ }).click();
    await p.getByText(/Verify your mobile/).first().waitFor({ timeout: 30000 }).catch(() => {});
    step('saved his details', 'the mobile step opened');
    await p.getByRole('button', { name: /^Send the code on WhatsApp$/ }).click().catch(() => {});
    await p.waitForTimeout(6000);
    await sh.take(p, 'mobile_refused', 'A reserved test number: the site refuses to send a code');
    const smsBox = await p.locator('input[autocomplete="one-time-code"]').count();
    step('asked for the mobile code', smsBox === 0 ? 'refused: a reserved number gets no SMS or WhatsApp' : 'a code box appeared (unexpected for a reserved number)');
    await write(`update public.customers set phone_verified = true where lower(email) = lower(${q(email)})`, 'fixture mobile verified');
    sec.signup.not_real.push('His mobile was recorded as verified by the test after the site refused to send a code to a reserved number (nobody can read an SMS sent to it).');
    await p.reload({ waitUntil: 'domcontentloaded' }); await p.getByRole('heading', { name: /Complete your account/ }).waitFor({ timeout: 30000 });
    const radio = p.getByRole('radio').first();
    if (await radio.waitFor({ timeout: 20000 }).then(() => true).catch(() => false)) { await radio.check(); await sh.take(p, 'whatsapp', 'Is this also your WhatsApp number?'); await p.getByRole('button', { name: /^Continue$/ }).click(); step('answered the WhatsApp question', '"the same number"'); }
    const terms = p.getByRole('checkbox', { name: /I accept the QuotesDone/ });
    await terms.waitFor({ timeout: 30000 }); await terms.check(); await sh.take(p, 'terms', 'He accepts the QuotesDone terms');
    await p.getByRole('button', { name: /^Finish & continue$/ }).click();
    const dash = await p.getByRole('button', { name: /^New request/ }).first().waitFor({ timeout: 150000 }).then(() => true).catch(() => false);
    await sh.take(p, 'dashboard', 'His dashboard');
    step('accepted the terms and pressed "Finish & continue"', dash ? 'his dashboard opened' : 'the dashboard did NOT open');
  } finally { await c.close(); }
  sec.signup.sheets = sheetsInto(ctx, sh.list, 's1_sheet');
  const row = await waitFor(async () => (await read(`select id::text id, is_demo, tos_version, tos_accepted_at, signed_terms_path, email_verified, phone_verified from public.customers where lower(email) = lower(${q(email)})`))[0] || null, { timeoutMs: 30000 });
  if (!row) throw new Error('no customer row after sign-up');
  run.ids.customers.add(row.id); ctx.custRow = row;
  if (row.is_demo !== true) throw new Error('the customer is not marked demo: STOP (nothing may reach a real supplier)');
  const signed = await waitFor(async () => (await read(`select signed_terms_path, tos_version, tos_accepted_at from public.customers where id = ${q(row.id)}`))[0]?.signed_terms_path ? (await read(`select signed_terms_path, tos_version, tos_accepted_at from public.customers where id = ${q(row.id)}`))[0] : null, { timeoutMs: 90000, everyMs: 3000 });
  const t = sec.terms = { version: signed?.tos_version ?? row.tos_version, accepted_at: signed?.tos_accepted_at ?? row.tos_accepted_at };
  if (signed?.signed_terms_path) {
    const { SERVICE } = await keys();
    const r = await fetch(`${BASE}/storage/v1/object/signed-terms/${signed.signed_terms_path.split('/').map(encodeURIComponent).join('/')}`, { headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE } });
    if (r.ok) {
      const b = Buffer.from(await r.arrayBuffer()); const f = 'customer_files/signed_terms_certificate.pdf'; writeFileSync(join(ctx.dir, f), b);
      const obj = (await read(`select (metadata->>'size')::bigint size from storage.objects where bucket_id = 'signed-terms' and name = ${q(signed.signed_terms_path)}`))[0];
      t.certificate = { file: f, bytes: b.length, sha256: sha256(b) }; t.storage = { bucket: 'signed-terms', path: signed.signed_terms_path, bytes: Number(obj?.size) || b.length, sha256: sha256(b) };
      ctx.certBytes = b; run.ids.storage.push('signed-terms/' + signed.signed_terms_path);
      ctx.exhibit(f, 'His signed-terms certificate', 'The certificate the platform issued when he accepted the terms, downloaded from Supabase storage.');
    } else ctx.finding('product', '1', `the signed-terms certificate is recorded at ${signed.signed_terms_path} but storage answered HTTP ${r.status}`);
  } else ctx.finding('product', '1', 'no signed-terms certificate was stored within 90 seconds of his acceptance');
  sec.verdicts.push(verdict('he signs up through the site\'s own door, accepts the terms, and a signed certificate of that acceptance is stored', `${sec.signup.steps.length} sign-up steps on screen; ${t.certificate ? `certificate stored (${t.certificate.bytes} bytes)` : 'NO certificate stored'}`, !!t.certificate));
  // later sessions for the same account (stand-in, said in the dossier)
  const { SERVICE, ANON } = await keys(); const pw = 'Jp-' + Math.random().toString(36).slice(2) + 'A1!';
  const au = (await read(`select id::text from auth.users where lower(email) = lower(${q(email)})`))[0];
  await fetch(`${BASE}/auth/v1/admin/users/${au.id}`, { method: 'PUT', headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE, 'Content-Type': 'application/json' }, body: JSON.stringify({ password: pw, app_metadata: { e2e_run: run.tag } }) });
  const newSession = async () => { const s = await (await fetch(`${BASE}/auth/v1/token?grant_type=password`, { method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password: pw }) })).json(); if (!s.access_token) throw new Error('no session'); return s; };
  const s0 = await newSession();
  ctx.cust = { kind: 'customer', email, phone: mobile, fullName, customerId: row.id, newSession, session: s0, jwt: s0.access_token };
  clockEnd(st);
}

/** A reserved fixture mobile (+971 50 000 0040-89) that NO living customer, lead or recent message holds (a reused number once
 *  brought an earlier identity's WhatsApp into a dossier, 13 Nov 2026). Notifications are never selected by phone anyway. */
async function freeMobile() {
  for (let i = 0; i < 40; i++) {
    const m = `+9715000000${String(40 + Math.floor(Math.random() * 50)).padStart(2, '0')}`;
    const held = (await read(`select (select count(*) from public.customers where phone = ${q(m)}) + (select count(*) from public.leads where phone = ${q(m)}) + (select count(*) from public.notifications where to_phone = ${q(m)} and created_at > now() - interval '30 days') n`))[0];
    if (Number(held?.n) === 0) return m;
  }
  throw new Error('no free fixture mobile in +971 50 000 0040-89');
}
const DISCARD = /@resend\.dev$|@example\.invalid$/i;   // Resend's test sink accepts and drops; example.invalid cannot receive
const clockStart = (ctx, id) => clock(ctx.rec).start(id);
const clockEnd = (s) => { s.end = now(); };

// ── the suppliers: right, wrong emirate, unrelated, made BEFORE the request so the matcher may choose ──────────────────
async function prep_suppliers(ctx) {
  const st = clock(ctx.rec).start('prep'); st.title = 'the demo suppliers are made';
  const { sc, run } = ctx; const fx = [];
  const make = async (trade, emirates, should, label) => {
    const sup = await makeDemoSupplier(run, { trade, label, coverage: emirates, activity: SERVICE_WORDS[trade].split(',')[0] });
    const rw = await call('supplier_api', sup.jwt, { action: 'services_rewrite', text: SERVICE_WORDS[trade], removed: [] });
    const named = (rw.json?.meaning?.proposals || []).filter((p) => p.because === 'exact_label').map((p) => p.key);
    const stt = await call('supplier_api', sup.jwt, { action: 'services_state' });
    await call('supplier_api', sup.jwt, { action: 'services_save_rewrite', trades: [...new Set([trade, ...(stt.json?.checklist || []).map((c) => c.code)])], roles: stt.json?.capability?.roles?.length ? stt.json.capability.roles : ['contractor', 'installer', 'supplier'], services: named, implied: (rw.json?.implied || []).filter((i) => !i.removed).map((i) => i.key), removed: [], own_words: rw.json?.own_words || [], raw_text: SERVICE_WORDS[trade] });
    if (sup.certificateRetried) ctx.finding('product', '4', `demo supplier ${label}: the Supplier Agreement certificate was not issued on the first acceptance (compliance_archive cert_record_failed or slower than 60 s); asking again issued it`);
    if (!named.length) ctx.finding('harness', '4', `demo supplier ${label}: the services rewrite named no service for "${SERVICE_WORDS[trade]}"`);
    fx.push({ lead_id: sup.leadId, label, company: sup.company, trade, emirates, should, services: named, fx: sup });
  };
  let i = 0;
  for (const r of sc.matching.right) for (let k = 0; k < r.n; k++) await make(r.trade, r.emirates, 'right', k < sc.quoting.length && r.trade === sc.trade ? sc.quoting[k].label : `${r.trade} ${r.emirates[0]} ${++i}`);
  for (const r of sc.matching.wrong) for (let k = 0; k < r.n; k++) await make(r.trade, r.emirates, 'wrong_emirate', `${r.trade} ${r.emirates[0]} only ${k + 1}`);
  for (const u of sc.matching.unrelated) await make(u.trade, u.emirates, 'unrelated', `${u.trade} (unrelated)`);
  for (const t of sc.trades) {
    const own = fx.filter((f) => f.trade === t).length;
    const o = await openTradeForDemo(run, t, own);
    for (const b of o.bench) fx.push({ lead_id: b, label: `bench supplier (${t}, Fujairah only)`, trade: t, emirates: ['Fujairah'], should: 'bench' });
    if (o.bench.length) ctx.rec.stand_ins.push(`${o.bench.length} more demo ${t} supplier(s) serving Fujairah only were made so the trade counts as open for a demo customer (the platform opens a trade to customers at ${o.floor} verified suppliers); they should not be asked.`);
  }
  ctx.fixtures = fx; ctx.S.s4.fixtures = fx.map(({ fx: _f, ...f }) => f);
  ctx.S.s4.gaps.push('Every demo supplier here was approved by the test, not by the platform: the test uploaded a demo licence and wrote the fields the licence reader would have read (legal name, number, authority, expiry). The platform then approved each one by its own rule once the agreement certificate landed.');
  ctx.rec.stand_ins.push('The demo suppliers\' trade licences were not read by the platform\'s reader: the test wrote the fields a reading would have written (fixtures.makeDemoSupplier). Their agreements were accepted and certified through the platform\'s own doors.');
  st.end = now();
}

// ── 2 the chat ────────────────────────────────────────────────────────────────────────────────────────────────────
async function s2_chat(ctx) {
  const st = clockStart(ctx, 's2'); const { sc, J, S, dir, cust } = ctx; const sec = S.s2;
  sec.how = `${sc.how_made}. The pictures of the chat were taken while the test added its run tag to the platform calls (see step 10); his request as he then sees it was photographed again in a clean browser.`;
  sec.turns = []; sec.questions = []; sec.attachments = []; sec.voice_notes = [];
  const c = await taggedContext(ctx, await cust.newSession()); if (sc.voice) await c.addInitScript(VOICE_INIT);
  const page = await c.newPage(); page.setDefaultTimeout(45000); const sh = shooter(ctx, 's2');
  const ev = { transcript: [], voice_notes: [], transcriptions: [] };
  const pushSE = (j, tSent) => {
    if (!j) { sec.turns.push({ role: 'system', text: '(no answer from the sales engineer)', at: now() }); return; }
    const qn = j.next_question; const qText = (x) => typeof x === 'string' ? x : (x?.text || x?.question || x?.label || '');
    const at = now();
    sec.turns.push({ role: 'sales engineer', text: j.assistant_message || (j.pending ? '(still working on the answer)' : ''), at, reply_s: secondsBetween(tSent, at), options: (qn?.options || []).map(qText), status: j.status });
    if (qText(qn)) sec.questions.push({ text: qText(qn), why: qn?.why || qn?.reason || qn?.rationale || null });
  };
  const say = async (text) => { const box = page.locator('#qd-intake-input'); await box.fill(text); const t0 = now(); sec.turns.push({ role: 'customer', text, at: t0 }); const j = await intakeTurn(page, () => box.press('Enter')); pushSE(j, t0); await sh.take(page, `turn_${sec.turns.length}`, `"${text.slice(0, 70)}${text.length > 70 ? '…' : ''}"`, { clean: false }); return j; };
  let j = null;
  try {
    await page.goto(portalUrl('customer', 'en'), { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.getByRole('button', { name: /^New request/ }).first().click({ timeout: 30000 });
    await page.locator('#qd-intake-input').waitFor({ state: 'visible', timeout: 20000 }); await page.waitForTimeout(1500);
    const greet = (await page.locator('section[aria-label="New request"]').first().innerText().catch(() => '')).split('\n').find((l) => /sales engineer/i.test(l));
    sec.turns.push({ role: 'sales engineer', text: greet || '(the greeting)', at: now() });
    await sh.take(page, 'opened', 'He opens "New request"', { clean: false });
    if (sc.opener) j = await say(sc.opener);
    for (const a of sc.attach || []) {
      const file = await customerFile(ctx, a);
      const input = page.locator(`input[type=file][aria-label="${a.input}"]`);
      const t0 = now(); sec.turns.push({ role: 'customer', text: `(attached ${basename(file)})`, at: t0 });
      const resP = page.waitForResponse((r) => r.url().includes('/functions/v1/customer_api') && (r.request().postData() || '').includes(a.action), { timeout: 420000 }).catch(() => null);
      const turnP = page.waitForResponse((r) => r.url().includes('/functions/v1/inquiry_intake') && !/poll_turn_id|carry_from/.test(r.request().postData() || ''), { timeout: 480000 }).catch(() => null);
      await input.setInputFiles(join(dir, file));
      const res = await resP; const rj = res ? await res.json().catch(() => ({})) : {};
      const lines = (rj?.boq?.boq || []).map((l) => ({ description: l.description || l.item, qty: l.qty ?? l.estimate ?? null, unit: l.unit || null }));
      const att = { file, kind: a.kind, http: res?.status() ?? 0, reading: { summary: rj?.boq?.summary || rj?.boq?.title || (lines.length ? `${lines.length} lines read from the file` : (rj?.message || rj?.note || rj?.error || 'nothing read')), lines, missing: rj?.boq?.missing_info || [], held: rj?.drawing_held ?? null, redaction_complete: rj?.redaction_complete ?? null },
        sufficient: 'The platform does not say whether the file alone is enough to quote from. What it read is above; what it asked next is below and in the chat.' };
      await page.waitForTimeout(1500); await sh.take(page, `after_${a.kind}`, `After he attached ${basename(file)}`, { clean: false });
      if (lines.length) { const tj = await turnP; const jj = tj ? await tj.json().catch(() => ({})) : null; pushSE(jj, t0); if (jj) { j = jj; att.sales_engineer_after = jj.assistant_message || null; } }
      sec.attachments.push(att);
    }
    if (sc.voice) {
      const name = 'voice_note_1';
      const t0 = now(); j = await speak(page, sc.voice, name, join(dir, 'customer_files'), ev, (n) => sh.take(page, n, 'The voice note', { clean: false }), (jj) => pushSE(jj, t0));
      const vn = ev.voice_notes[0] || {}; const tr = ev.transcriptions[0] || {};
      sec.voice_notes.push({ file: `customer_files/${vn.file || name + '.wav'}`, seconds: vn.seconds, script: vn.script, heard: tr.text || `(the transcription came back empty: ${tr.error || 'no text'})` });
      sec.turns.push({ role: 'customer', text: `(voice note, ${vn.seconds} s) ${tr.text || ''}`, at: t0 });
      ctx.exhibit(`customer_files/${vn.file || name + '.wav'}`, 'His voice note (audio)', 'The voice note exactly as played into the chat\'s microphone.', { attach: true });
    }
    const given = new Set(); let held = 0;
    for (let turn = 0; turn < 12 && j && j.status !== 'ready'; turn++) {
      if (j.status === 'held' && !j.category && ++held > 2) break;
      let ans = nextAnswer(J, j, given);
      const opts = (j.next_question?.options || []).map((x) => typeof x === 'string' ? x : x?.text || x?.label || '').filter(Boolean);
      if (!ans && opts.length) {
        const pick = j.next_question?.suggested ? String(j.next_question.suggested) : opts[0];
        const chip = page.locator('[role="group"] button').filter({ hasText: pick }).first();
        if (await chip.isVisible().catch(() => false)) { const t0 = now(); sec.turns.push({ role: 'customer', text: `(tapped "${pick}")`, at: t0 }); j = await intakeTurn(page, () => chip.click()); pushSE(j, t0); await sh.take(page, `tap_${turn}`, `He taps "${pick}"`, { clean: false }); continue; }
        ans = pick;
      }
      if (!ans) ans = /\?/.test(String(j.assistant_message || '')) ? 'I am not sure about that one, please let the supplier advise.' : (given.has(sc.confirm) ? 'That is everything we know; please let the supplier advise on anything else.' : sc.confirm);
      given.add(ans); j = await say(ans);
    }
    sec.ready = j?.status === 'ready';
    if (sec.ready) {
      await sh.take(page, 'ready', 'The summary before "Send to suppliers"', { clean: false });
      const [res] = await Promise.all([page.waitForResponse((r) => r.url().includes('/functions/v1/customer_api') && (r.request().postData() || '').includes('create_inquiry'), { timeout: 180000 }).catch(() => null), page.getByRole('button', { name: /Send to suppliers/ }).first().click({ timeout: 20000 })]);
      const cj = res ? await res.json().catch(() => ({})) : {};
      sec.turns.push({ role: 'customer', text: '(pressed "Send to suppliers")', at: now() });
      await page.waitForTimeout(5000); await sh.take(page, 'sent', 'Request sent', { clean: false });
      let inq = cj.inquiry_id ?? cj.id ?? null; let quotable = (cj.quotable_ids || [])[0] || inq;
      const yes = page.getByRole('button', { name: 'Yes, get separate quotes per trade' }).first();
      if (await yes.isVisible().catch(() => false)) {
        await sh.take(page, 'no_single_contractor', 'No single contractor: "separate quotes per trade?"', { clean: false });
        const [rr] = await Promise.all([page.waitForResponse((r) => r.url().includes('/functions/v1/customer_api') && (r.request().postData() || '').includes('repeat_inquiry'), { timeout: 180000 }).catch(() => null), yes.click()]);
        const rj = rr ? await rr.json().catch(() => ({})) : {};
        sec.turns.push({ role: 'customer', text: '(pressed "Yes, get separate quotes per trade")', at: now() });
        if (inq) ctx.run.ids.inquiries.add(String(inq));
        inq = rj.inquiry_id ?? rj.id ?? inq; quotable = (rj.quotable_ids || rj.child_ids || [])[0] || inq;
        for (const x of [...(rj.quotable_ids || []), ...(rj.child_ids || [])]) ctx.run.ids.inquiries.add(String(x));
      }
      for (const x of cj.quotable_ids || []) ctx.run.ids.inquiries.add(String(x));
      if (inq) { ctx.run.ids.inquiries.add(String(inq)); ctx.inquiryId = inq; }
      // the part of a split request in the journey's own trade is the one the suppliers quote
      const all = [...ctx.run.ids.inquiries];
      if (all.length > 1) { const cats = await read(`select id::text id, category, trades from public.inquiries where id::text in (${all.map(q).join(',')})`); quotable = (cats.find((x) => x.category === sc.trade || (x.trades || []).includes(sc.trade)) || { id: quotable }).id; }
      ctx.quotable = quotable; sec.create_inquiry = { http: res?.status() ?? 0, inquiry_id: inq, quotable, matches: cj.matches ?? null, error: cj.error ?? null };
    }
  } catch (e) { ctx.finding('harness', '2', `the chat stopped: ${String(e.message).split('\n')[0]}`); }
  finally { await c.close(); }
  sec.sheets = sheetsInto(ctx, sh.list, 's2_sheet');
  // what the platform itself kept of the chat
  const it = (await read(`select id::text, status, readiness, category, jsonb_array_length(turns) n, (select count(*) from jsonb_array_elements(turns) t where t ? 'at' or t->'slots' ? 'at')::int timed, brief from public.inquiry_intake where customer_id = ${q(cust.customerId)} order by created_at desc limit 1`))[0];
  sec.stored = it ? `${it.n} turns in inquiry_intake.turns (status ${it.status}, readiness ${it.readiness}, trade ${it.category}); ${it.timed} of them carry a time.` : 'no inquiry_intake row was found for him';
  sec.gaps.push('A copy of this chat as a document. The platform keeps the chat only as data (inquiry_intake.turns), mostly without a time on each turn, and issues no transcript; the conversation archive holds e-mail, WhatsApp and notifications only. The transcript above was taken from the screen by the test, with the test\'s own clock.');
  if (sec.attachments.length) sec.gaps.push('A yes or no on whether the file the customer gave is enough to quote from. The platform reads the file and asks questions, but states no judgement of sufficiency.');
  if (sec.questions.length && sec.questions.every((x) => !x.why)) sec.gaps.push('Why each question was asked. The platform gives the question and its answer buttons, not its reason.');
  sec.verdicts.push(verdict('the sales engineer asks only what the job needs, the chat reaches "ready" and the request is sent to suppliers', `${sec.turns.filter((t) => t.role === 'customer').length} customer turns, ${sec.questions.length} questions; ${sec.ready ? 'ready and sent' : 'NOT ready: the request was not sent'}`, !!(sec.ready && ctx.quotable)));
  for (const a of sec.attachments) sec.verdicts.push(verdict(`the platform reads ${a.file.split('/').pop()} and uses it`, `${a.reading.lines.length} lines read; ${a.reading.missing.length} things it said were missing`, a.reading.lines.length > 0 ? null : false));
  // his request as he sees it, in a CLEAN browser
  if (ctx.inquiryId) {
    const cc = await cleanContext('customer', await cust.newSession()); const p = await cc.newPage(); const sh2 = shooter(ctx, 's2c');
    try { await p.goto(portalUrl('customer', 'en', `?request=${ctx.inquiryId}`), { waitUntil: 'domcontentloaded', timeout: 60000 }); await p.waitForTimeout(6000); await sh2.take(p, 'request', 'His request, as he sees it'); await p.mouse.wheel(0, 700); await p.waitForTimeout(800); await sh2.take(p, 'request_more', 'His request, further down'); } catch (e) { ctx.finding('harness', '2', `clean capture of his request: ${e.message}`); }
    finally { await cc.close(); }
    sec.sheets.push(...sheetsInto(ctx, sh2.list, 's2_clean_sheet'));
  }
  clockEnd(st);
}
/** The customer's own file for an attachment: an auditor's adversarial input (copied in) or one the scenario makes. */
async function customerFile(ctx, a) {
  if (a.from) {
    const src = INPUTS ? join(INPUTS, a.from.file) : null;
    if (!src || !existsSync(src)) throw new Error(`the input "${a.from.file}" is not in --inputs (${INPUTS || 'not given'})`);
    const f = `customer_files/${a.from.file}`; copyFileSync(src, join(ctx.dir, f));
    ctx.exhibit(f, `The file the customer gave: ${a.from.file}`, 'His own file, exactly as he attached it, with every identifying detail on it.', { ours: false });
    ctx.inputIdentity = [...(ctx.inputIdentity || []), ...a.from.identity]; ctx.oldPrices = a.from.prices || ctx.oldPrices;
    return f;
  }
  if (a.make === 'pool_boq') { const f = 'customer_files/Pool BOQ - Villa 15.xlsx'; xlsx(join(ctx.dir, f), 'ZZ DEMO Private pool, Villa 15, Al Barsha 2, Dubai - bill of quantities', ctx.sc.boq); ctx.exhibit(f, 'The BOQ he attached (spreadsheet)', 'His bill of quantities, as attached.', { attach: true }); return f; }
  throw new Error('attachment with no file');
}


/** DRY RUN ONLY: with the models off the sales engineer cannot answer, so the chat is held and nothing is sent. So the
 *  rest of the journey can still walk its doors for free, the test writes the request itself (demo_factory makeInquiry)
 *  and invites the suppliers itself. Both are printed as the test's, never as the platform's. */
async function dryRequest(ctx) {
  const { sc, run, cust } = ctx;
  const inq = await makeInquiry(run, { customer: { customerId: cust.customerId, locale: 'en' }, trade: sc.trade, status: 'sent', rfqReady: false, summary: sc.title.replace(/, Villa 15, Al Barsha 2, Dubai$/, ', Dubai'), raw_input: sc.opener || '' });
  await write(`update public.inquiries set category = ${q(sc.trade)}, trades = array[${q(sc.trade)}], emirate = 'Dubai', boq = ${q(JSON.stringify({ boq: asEvidenceJourney(sc).defaultLines }))}::jsonb where id = ${q(inq.id)}`, 'dry run request');
  run.ids.inquiries.add(String(inq.id)); ctx.inquiryId = inq.id; ctx.quotable = String(inq.id); ctx.dryRequest = true;
  ctx.rec.stand_ins.unshift('DRY RUN (models off): the sales engineer cannot answer without a model, so the chat stops at its first question and nothing is sent. To walk the rest of the doors for free, the TEST wrote the request itself (its title is the journey\'s, its lines the journey\'s default lines) and invited the suppliers itself. Steps 3 to 9 show the platform\'s doors on that request; they say nothing about what the chat would have produced.');
  ctx.finding('harness', '2', 'Dry run: the chat could not reach "ready" with the models off; the test wrote the request so that steps 3 to 9 could be walked.');
}
// ── 3 the inquiry as a supplier receives it, and the anonymity check ────────────────────────────────────────────────
async function s3_shared(ctx) {
  const st = clockStart(ctx, 's3'); const { S, dir, cust, quotable } = ctx; const sec = S.s3; sec.messages = []; sec.documents = []; sec.sheets = [];
  const row = (await read(`select id, rfq_no, category, trades, status, emirate, summary, boq, drawing_redacted_paths from public.inquiries where id = ${q(quotable)}`))[0] || {};
  ctx.row = row;
  const matched = (await read(`select supplier_id from public.inquiry_matches where inquiry_id = ${q(quotable)}`)).map((m) => String(m.supplier_id));
  const viewer = ctx.fixtures.find((f) => f.should === 'right' && matched.includes(String(f.lead_id))) || ctx.fixtures.find((f) => f.should === 'right' && f.trade === ctx.sc.trade);
  if (!matched.includes(String(viewer.lead_id))) { await write(`insert into public.inquiry_matches (inquiry_id, supplier_id, match_reason) values (${q(quotable)}, ${Number(viewer.lead_id)}, 'journey proof: invited by the test') on conflict do nothing`, 'journey proof invitation'); ctx.added = [...(ctx.added || []), { lead_id: viewer.lead_id, company: viewer.company }]; }
  sec.viewer = viewer.label; const sup = viewer.fx;
  const surfaces = [];
  const ip = await call('supplier_api', sup.jwt, { action: 'inquiry_pdf', inquiry_id: quotable, lang: 'en' }, 180000);
  if (ip.json?.url) {
    const b = await fetchBytes(ip.json.url); const f = 'shared/inquiry_as_the_supplier_receives_it.pdf'; writeFileSync(join(dir, f), b);
    sec.inquiry_pdf = f; ctx.exhibit(f, 'The inquiry as a supplier receives it', 'supplier_api inquiry_pdf: the document behind the supplier portal\'s PDF button, on our template.');
    const t = pdfText(join(dir, f)); surfaces.push({ where: 'the inquiry PDF (its text)', kind: 'pdf_text', text: t, unreadable: !t.trim(), why: 'no text layer' });
    surfaces.push({ where: 'the inquiry PDF (its file properties)', kind: 'pdf_props', text: pdfProps(join(dir, f)) });
    surfaces.push({ where: 'the inquiry PDF (its file name)', kind: 'file_name', text: decodeURIComponent(new URL(ip.json.url).pathname.split('/').pop() || '') });
  } else ctx.finding('product', '3', `the supplier could not download the inquiry PDF: HTTP ${ip.status} ${String(ip.text).slice(0, 160)}`);
  const docs = await call('supplier_api', sup.jwt, { action: 'inquiry_documents', inquiry_id: quotable });
  for (const d of docs.json?.documents || []) {
    const f = `shared/${String(d.name).replace(/[\\/]/g, '_')}`;
    surfaces.push({ where: `the file name "${d.name}"`, kind: 'file_name', text: d.name });
    try {
      if (d.url) { const b = await fetchBytes(d.url); writeFileSync(join(dir, f), b); }
      else if (d.content) writeFileSync(join(dir, f), d.content);
      const isPdf = existsSync(join(dir, f)) && readFileSync(join(dir, f)).subarray(0, 4).toString() === '%PDF';
      if (isPdf) { const t = pdfText(join(dir, f)); surfaces.push({ where: `${d.name} (its text)`, kind: 'pdf_text', text: t, unreadable: !t.trim(), why: 'the page is a picture' }); surfaces.push({ where: `${d.name} (its file properties)`, kind: 'pdf_props', text: pdfProps(join(dir, f)) }); ctx.exhibit(f, `What the supplier can open: ${d.name}`, 'A file the supplier receives with the inquiry (inquiry_documents).'); }
      else if (d.content) surfaces.push({ where: d.name, kind: 'data', text: String(d.content) });
      else surfaces.push({ where: d.name, kind: 'pdf_text', unreadable: true, why: 'a picture', text: '' });
      sec.documents.push({ name: d.name, what: d.kind === 'drawing_page' ? 'a page of his drawing, as cleaned by the platform' : d.kind === 'boq_csv' ? 'the bill of quantities as a spreadsheet' : d.kind });
    } catch (e) { ctx.finding('harness', '3', `could not fetch ${d.name}: ${e.message}`); }
  }
  // the supplier's portal, in a CLEAN browser
  const cc = await cleanContext('supplier', await sup.newSession()); const p = await cc.newPage(); const sh = shooter(ctx, 's3');
  try {
    await p.goto(portalUrl('supplier', 'en'), { waitUntil: 'domcontentloaded', timeout: 60000 }); await p.waitForTimeout(5000);
    await p.getByRole('button', { name: /Inquiries received/ }).first().click({ timeout: 20000 }).catch(() => {});
    await p.locator(`#qd-inq-${quotable} > button`).waitFor({ timeout: 30000 }).catch(() => {});
    await sh.take(p, 'list', 'Inquiries received, as the supplier sees it');
    surfaces.push({ where: 'the supplier portal: Inquiries received', kind: 'screen', text: await p.locator('main').innerText().catch(() => '') });
    await p.locator(`#qd-inq-${quotable} > button`).click().catch(() => {});
    await p.locator(`#qd-inq-d-${quotable}`).waitFor({ timeout: 30000 }).catch(() => {});
    await p.waitForTimeout(2500); await sh.take(p, 'detail', 'The inquiry opened');
    for (let k = 0; k < 3; k++) { await p.mouse.wheel(0, 700); await p.waitForTimeout(700); await sh.take(p, `detail_${k + 2}`, 'The inquiry, further down'); }
    surfaces.push({ where: 'the supplier portal: the inquiry opened', kind: 'screen', text: await p.locator(`#qd-inq-d-${quotable}`).first().innerText().catch(() => '') });
  } catch (e) { ctx.finding('harness', '3', `supplier screens: ${e.message}`); }
  finally { await cc.close(); }
  sec.sheets = sheetsInto(ctx, sh.list, 's3_sheet');
  // what was composed for the suppliers about this inquiry
  const notes = await read(`select n.id, n.created_at, n.channel, n.type, n.kind, n.subject, n.body, n.html, n.status, n.lead_id from public.notifications n where n.inquiry_id = ${q(quotable)} and n.lead_id is not null order by n.created_at`);
  for (const n of notes) {
    const mine = String(n.lead_id) === String(viewer.lead_id);
    const text = n.body || htmlText(n.html);
    surfaces.push({ where: `the ${n.channel} composed for ${mine ? 'this supplier' : 'supplier ' + n.lead_id} ("${String(n.subject || n.type).slice(0, 60)}")`, kind: 'message', text: `${n.subject || ''}\n${text}\n${htmlText(n.html)}` });
    if (mine) sec.messages.push({ channel: n.channel, to: `the supplier (${viewer.label})`, at: n.created_at, subject: n.subject, text, state: n.status === 'suppressed' ? 'composed, delivery suppressed for a demo identity' : n.status, shot: n.html ? await emailShot(ctx, n.html, `s3_message_${n.id}`) : null });
  }
  if (!notes.length) sec.gaps.push('A message to the supplier about this inquiry: none was composed while this step ran (it may come later; step 6 lists everything by time).');
  // founder 1686: an old supplier's prices are hidden like his name (items, specifications and quantities may pass)
  const priceItems = (ctx.oldPrices || []).map((v) => ({ label: "a price on the customer's old quotation", value: v, kind: 'text' }));
  const items = [...customerIdentity(cust), ...(ctx.inputIdentity || []), ...priceItems];
  sec.anonymity = scan(items, surfaces);
  if (sec.anonymity.leaks) for (const r of sec.anonymity.rows.filter((x) => x.leak)) ctx.finding('leak', '3', `${r.label} ("${r.value}") reached the supplier in ${r.hits.map((h) => h.where).join('; ')}`);
  sec.verdicts.push(verdict('nothing that identifies the customer (his name, contacts, area, villa) or a third party on his documents reaches the supplier before the reveal', sec.anonymity.leaks ? `${sec.anonymity.leaks} LEAK(S): see the table` : `none of the ${sec.anonymity.rows.length} details was found in ${sec.anonymity.checked.length} things the supplier received`, sec.anonymity.leaks === 0));
  // the old supplier's prices: the founder rules on this
  if (ctx.oldPrices?.length) {
    const all = surfaces.filter((x) => !x.unreadable).map((x) => x.text).join('\n');
    const seen = ctx.oldPrices.filter((pr) => all.includes(pr));
    const att = S.s2.attachments.find((a) => a.kind === 'old_quotation');
    if (att) { att.prices_passed_on = seen.length > 0; att.prices_note = seen.length ? `${seen.length} of the old supplier's ${ctx.oldPrices.length} prices appear in what the new suppliers received: ${seen.join(', ')}. Founder ruling 1686: prices are hidden; this is a LEAK.` : `None of the old supplier's ${ctx.oldPrices.length} prices appears in what the new suppliers received.`; }
  }
  clockEnd(st);
}
/** A composed e-mail drawn at phone width, offline (no network, no script), as the person would open it. */
async function emailShot(ctx, html, name) {
  const c = await BROWSER.newContext({ ...PHONE, javaScriptEnabled: false, offline: true }); const p = await c.newPage();
  try { await p.setContent(String(html), { waitUntil: 'load', timeout: 15000 }).catch(() => {}); const f = join(ctx.dir, 'messages', `${name}.png`); await p.screenshot({ path: f, fullPage: true }); return rel(ctx, f); }
  catch { return null; } finally { await c.close(); }
}

// ── 4 who was asked ───────────────────────────────────────────────────────────────────────────────────────────────
async function s4_matching(ctx) {
  const st = clockStart(ctx, 's4'); const sec = ctx.S.s4;
  const all = [...new Set([ctx.quotable, ...ctx.run.ids.inquiries])];
  const m = await read(`select m.inquiry_id::text inquiry_id, m.supplier_id lead_id, l.company_name company, l.is_demo, m.match_reason reason from public.inquiry_matches m join public.leads l on l.id = m.supplier_id where m.inquiry_id::text in (${all.map(q).join(',')}) and coalesce(m.match_reason, '') not like 'journey proof:%' order by m.id`);
  sec.verdict = matcherVerdict(sec.fixtures, m, ctx.added || []);
  if (ctx.dryRequest) { sec.gaps.push('Dry run: the request was written by the test, not sent through "Send to suppliers", so the live matcher never chose anyone. Who should and should not be asked is shown; who WAS asked can only be proved by a paid run.'); clockEnd(st); return; }
  if (sec.verdict.real_supplier_asked.length) ctx.finding('product', '4', 'A REAL supplier was asked for a demo request');
  for (const w of sec.verdict.wrong_asked) ctx.finding('looked_wrong', '4', `${w.label} was asked although it ${w.should === 'wrong_emirate' ? 'does not serve the job\'s emirate' : w.should === 'unrelated' ? 'is of an unrelated trade' : 'is not one of this journey\'s suppliers'}`);
  for (const r of sec.verdict.right_missed) ctx.finding('looked_wrong', '4', `${r.label} (the right trade, serving ${JOB.emirate}) was not asked`);
  const right = sec.fixtures.filter((f) => f.should === 'right').length;
  sec.verdicts.push(verdict(`all ${right} suppliers of the right trade serving ${JOB.emirate} are asked, and none of the others`, `${sec.verdict.right_asked.length} of ${right} right ones asked; ${sec.verdict.wrong_asked.length} wrong ones asked`, sec.verdict.right_missed.length === 0 && sec.verdict.wrong_asked.length === 0));
  clockEnd(st);
}

// ── 5 the quotations ──────────────────────────────────────────────────────────────────────────────────────────────
async function s5_quotes(ctx) {
  const st = clockStart(ctx, 's5'); const { sc, J, dir, run, quotable, row, S } = ctx; const sec = S.s5; sec.quotes = [];
  const asked = new Set((S.s4.verdict?.asked || []).map((a) => String(a.lead_id)));
  const pool = ctx.fixtures.filter((f) => f.should === 'right' && f.trade === sc.trade);
  const chosen = [...pool.filter((f) => asked.has(String(f.lead_id))), ...pool.filter((f) => !asked.has(String(f.lead_id)))].slice(0, sc.quoting.length);
  const ev = { quotes: [] };
  for (const [i, f] of chosen.entries()) {
    if (!asked.has(String(f.lead_id))) { await write(`insert into public.inquiry_matches (inquiry_id, supplier_id, match_reason) values (${q(quotable)}, ${Number(f.lead_id)}, 'journey proof: invited by the test') on conflict do nothing`, 'journey proof invitation'); ctx.added = [...(ctx.added || []), { lead_id: f.lead_id, company: f.company }]; }
    const spec = { ...sc.quoting[i], label: f.label === sc.quoting[i].label ? f.label : sc.quoting[i].label };
    const lh = supplierLetterhead(spec, f.fx, i); f.letterhead = lh;
    const pdfFor = async ({ lines, ref }) => { const doc = quotationHtml({ J, s: spec, company: f.fx.company, rfq: row.rfq_no || quotable.slice(0, 8), ref, lines }); let html = withFullIdentity(doc.html, lh); let d2 = doc; if (spec.vatInclusiveOnly) { html = vatInclusiveOnly(html, doc); d2 = { ...doc, sub: doc.tot, vat: 0 }; } return { doc: { ...d2, html }, pdf: await htmlPdf(html, { landscape: true }), fname: `${lh.trading_name} - Quotation ${ref}.pdf` }; };
    const r = await quoteOne({ J, k: sc.key, i, x: { spec, fx: f.fx }, quotable, row, dir, run, ev, onFinding: (where, what) => ctx.finding('product', '5', `${where}: ${what}`), pdfFor });
    const qrec = { label: lh.trading_name, lead_id: f.lead_id, vat_inclusive_only: !!spec.vatInclusiveOnly, stated: { ex_vat: r.ex_vat, vat: r.vat, total: r.total }, own_file: r.file, quote_id: r.quote_id, path: r.cleared_by || (r.quote_id ? 'submitted' : 'NOT submitted'), read: { amount: r.extract?.amount ?? null, lines: r.extract?.lines ?? null, read_by: r.extract?.read_by ?? null, masked: r.extract?.masked || [] }, identity: [...supplierIdentity(lh), { label: "the supplier's registered mobile", value: f.fx.phone, kind: 'phone' }, { label: "the supplier's login e-mail", value: f.fx.email, kind: 'email' }, { label: "his quotation's file name", value: basename(r.file || ''), kind: 'text' }] };
    ctx.exhibit(r.file, `${lh.trading_name}: his own quotation, as he sent it`, 'The supplier\'s own file, with his full identity on it. Compare it with the next exhibit.', { ours: false });
    if (r.quote_id) {
      ctx.ids.quotes.add(String(r.quote_id));
      const cp = await call('customer_api', ctx.cust.jwt, { action: 'quote_pdf', quote_id: r.quote_id, lang: 'en' }, 180000);
      if (cp.json?.url) { const b = await fetchBytes(cp.json.url); const fc = `quotations/${lh.trading_name} - as the customer sees it.pdf`; writeFileSync(join(dir, fc), b); qrec.customer_pdf = fc; qrec.customer_pdf_url_name = decodeURIComponent(new URL(cp.json.url).pathname.split('/').pop() || ''); ctx.exhibit(fc, `${lh.trading_name}: the quotation as the customer sees it`, 'customer_api quote_pdf, on our template, before the reveal.'); }
      else ctx.finding('product', '5', `${lh.trading_name}: the customer could not download the quotation PDF (HTTP ${cp.status})`);
    }
    sec.quotes.push(qrec);
  }
  const live = await read(`select id::text, status from public.quotes where inquiry_id = ${q(quotable)}`);
  sec.verdicts.push(verdict(`${chosen.length} suppliers quote; each quotation reaches the customer on our template`, `${sec.quotes.filter((x) => x.customer_pdf).length} reached him as our document; quotes on the request: ${live.map((x) => x.status).join(', ') || 'none'}`, sec.quotes.length > 0 && sec.quotes.every((x) => x.customer_pdf)));
  clockEnd(st);
}
/** After the comparison: each supplier's identity searched in everything the customer received before the reveal. */
async function s5_reverse_anonymity(ctx) {
  const { dir, S } = ctx;
  const cmp = S.s7.pdf ? [{ where: 'the comparison report (its text)', kind: 'pdf_text', text: pdfText(join(dir, S.s7.pdf)) }, { where: 'the comparison report (its file properties)', kind: 'pdf_props', text: pdfProps(join(dir, S.s7.pdf)) }] : [];
  const screens = (ctx.customerScreens || []).map((t) => ({ where: t.where, kind: 'screen', text: t.text }));
  const notes = (await read(`select channel, subject, body, html from public.notifications where created_at >= ${q(ctx.rec.journey.started)} and (to_email = ${q(ctx.cust.email)} or (to_role = 'customer' and inquiry_id::text in (${[...ctx.run.ids.inquiries].map(q).join(',') || 'null'}))) order by created_at`)).map((n) => ({ where: `the ${n.channel} to the customer ("${String(n.subject || '').slice(0, 50)}")`, kind: 'message', text: `${n.subject || ''}\n${n.body || ''}\n${htmlText(n.html)}` }));
  for (const qr of S.s5.quotes) {
    const own = qr.customer_pdf ? [{ where: 'his quotation as the customer sees it (text)', kind: 'pdf_text', text: pdfText(join(dir, qr.customer_pdf)) }, { where: 'his quotation as the customer sees it (file properties)', kind: 'pdf_props', text: pdfProps(join(dir, qr.customer_pdf)) }, { where: 'the file name the customer downloads', kind: 'file_name', text: qr.customer_pdf_url_name || '' }] : [];
    qr.anonymity = scan(qr.identity, [...own, ...cmp, ...screens, ...notes]);
    for (const r of qr.anonymity.rows.filter((x) => x.leak)) ctx.finding('leak', '5', `${qr.label}: ${r.label} ("${r.value}") reached the customer in ${r.hits.map((h) => h.where).join('; ')}`);
  }
  const n = S.s5.quotes.reduce((a, x) => a + (x.anonymity?.leaks || 0), 0);
  S.s5.verdicts.push(verdict('nothing that identifies a supplier (name, address, phones, e-mail, TRN, bank, salesperson, file name) reaches the customer before the reveal', n ? `${n} LEAK(S): see each quotation's table` : 'none found', n === 0));
}

// ── 7 the comparison ──────────────────────────────────────────────────────────────────────────────────────────────
async function s7_comparison(ctx) {
  const st = clockStart(ctx, 's7'); const { dir, S, cust, quotable } = ctx; const sec = S.s7;
  const cmp = await call('quote_compare', cust.jwt, { inquiry_id: quotable, lang: 'en' }, 240000);
  const top = summariseTop(cmp.json?.analysis || null, {}) || [];
  const labelOf = new Map(S.s5.quotes.map((x) => [String(x.quote_id), x.label]));
  sec.top = top.map((x) => ({ rank: x.rank, label: `${x.label || ''}${labelOf.get(String(x.quote_id)) ? ` (${labelOf.get(String(x.quote_id))})` : ''}`, price: x.price, why: x.why, quote_id: x.quote_id }));
  for (const x of S.s5.quotes) { const t = top.find((y) => String(y.quote_id) === String(x.quote_id)); if (t?.label) x.letter = t.label; }
  sec.degraded = cmp.json?.degraded ?? null;
  const cp = await call('customer_api', cust.jwt, { action: 'compare_pdf', inquiry_id: quotable, lang: 'en' }, 240000);
  const u = cp.json?.url || cp.json?.pdf_url;
  if (u) { const b = await fetchBytes(u); const f = 'shared/comparison_report.pdf'; writeFileSync(join(dir, f), b); sec.pdf = f; ctx.exhibit(f, 'The comparison report the customer downloads', 'customer_api compare_pdf, on our template.'); }
  else ctx.finding('product', '7', `the customer could not download the comparison report (HTTP ${cp.status})`);
  // what he sees, CLEAN
  const cc = await cleanContext('customer', await cust.newSession()); const p = await cc.newPage(); const sh = shooter(ctx, 's7'); ctx.customerScreens = ctx.customerScreens || [];
  try {
    await p.goto(portalUrl('customer', 'en', `?request=${ctx.inquiryId}`), { waitUntil: 'domcontentloaded', timeout: 60000 }); await p.waitForTimeout(6000);
    await sh.take(p, 'quotes', 'His request with the quotations');
    const btn = p.getByRole('button', { name: /compare/i }).first(); if (await btn.isVisible().catch(() => false)) { await btn.click().catch(() => {}); await p.waitForTimeout(8000); }
    for (let k = 0; k < 4; k++) { await sh.take(p, `compare_${k + 1}`, k ? 'The comparison, further down' : 'The comparison'); await p.mouse.wheel(0, 700); await p.waitForTimeout(700); }
    ctx.customerScreens.push({ where: 'the customer portal: his request, quotations and comparison', text: await p.locator('main').innerText().catch(() => '') });
  } catch (e) { ctx.finding('harness', '7', `customer screens: ${e.message}`); } finally { await cc.close(); }
  sec.sheets = sheetsInto(ctx, sh.list, 's7_sheet');
  sec.verdicts.push(verdict('the customer gets a comparison report on our template that ranks the quotations and says why', `${sec.top.length} ranked; ${sec.top.filter((x) => x.why).length} with a reason; report ${sec.pdf ? 'issued' : 'NOT issued'}${sec.degraded ? ' (the platform says it is a reduced comparison)' : ''}`, !!sec.pdf && sec.top.length > 0 && sec.top.every((x) => x.why)));
  clockEnd(st);
}

// ── 8 the reveal ──────────────────────────────────────────────────────────────────────────────────────────────────
async function s8_reveal(ctx) {
  const st = clockStart(ctx, 's8'); const { dir, S, cust } = ctx; const sec = S.s8;
  const pick = S.s7.top?.[0]?.quote_id || S.s5.quotes.find((x) => x.quote_id)?.quote_id;
  ctx.statusBefore = (await read(`select status from public.inquiries where id = ${q(ctx.quotable)}`))[0]?.status ?? null;
  if (!pick) { ctx.finding('product', '8', 'no quotation could be revealed'); clockEnd(st); return; }
  const chosen = S.s5.quotes.find((x) => String(x.quote_id) === String(pick)); sec.chosen = `${chosen?.letter ? `"${chosen.letter}" ` : ''}(${chosen?.label || pick}), the sales engineer's first pick`;
  const init = await call('stripe_checkout', cust.jwt, { action: 'element_init', quote_id: pick });
  sec.mode = init.json?.mode ?? null;
  if (!(init.json?.mode === 'test' && String(init.json?.publishable_key || '').startsWith('pk_test'))) { ctx.finding('product', '8', 'the reveal was not served Stripe TEST mode: NOT paid'); clockEnd(st); return; }
  const sess = await call('stripe_checkout', cust.jwt, { quote_id: pick, return_url: `${SITE}/me` });
  if (!sess.json?.url) { ctx.finding('product', '8', `no checkout session (HTTP ${sess.status})`); clockEnd(st); return; }
  const cc = await cleanContext('customer', await cust.newSession()); const p = await cc.newPage(); const sh = shooter(ctx, 's8');
  try {
    await p.goto(sess.json.url, { waitUntil: 'domcontentloaded', timeout: 60000 }); await p.locator('#cardNumber').waitFor({ timeout: 60000 });
    await sh.take(p, 'checkout', 'The reveal fee checkout (Stripe TEST mode)');
    await payHostedTestCheckout(p); await sh.take(p, 'card', 'Stripe\'s test card');
    await p.waitForURL(/quotesdone\.(com|ae)/, { timeout: 120000 }).catch(() => {}); await p.waitForTimeout(6000);
    await sh.take(p, 'back', 'Back on QuotesDone after paying');
  } catch (e) { ctx.finding('product', '8', `paying: ${e.message.split('\n')[0]}`); }
  const tx = await waitFor(async () => (await read(`select id::text id, fee_status, reveal_fee, processing_fee, total_charged, quote_amount, revealed_at paid_at, refund_deadline, stripe_invoice_number, stripe_fee_fils, doc_path from public.transactions where quote_id = ${q(pick)}`))[0], { timeoutMs: 120000 });
  ctx.tx = tx; ctx.pick = pick; ctx.chosen = chosen;
  if (tx) {
    const qr = (await read(`select quote_amount, price_ex_vat, vat_amount, gross_amount, amount_as_stated, vat_treatment from public.quotes where id = ${q(pick)}`))[0] || {};
    const ex = Number(qr.price_ex_vat ?? qr.quote_amount), base = Number(tx.quote_amount), fee = Number(tx.reveal_fee), rate = base ? fee / base : null;
    const aedF = (n) => n == null || isNaN(n) ? '—' : `AED ${Number(n).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
    const ok = isFinite(ex) && Math.abs(base - ex) < 0.01;
    sec.vat = { ex_vat: aedF(ex), vat_stated: aedF(qr.vat_amount), gross: aedF(qr.gross_amount ?? qr.amount_as_stated), treatment: chosen?.vat_inclusive_only ? 'his quotation stated ONLY a total including VAT' : (qr.vat_treatment || '—'), base: aedF(base), fee: aedF(fee), rate_words: rate ? `${(rate * 100).toFixed(2)}% of the base` : '—', processing: Number(tx.processing_fee) > 0 ? `${aedF(tx.processing_fee)} CHARGED ON TOP OF THE FEE` : 'none', charged: aedF(tx.total_charged), stripe_cost: tx.stripe_fee_fils != null ? `${aedF(Number(tx.stripe_fee_fils) / 100)} (Stripe's own figure)` : 'not yet reported by Stripe',
      overcharged: (Number(tx.processing_fee) > 0 || Number(tx.total_charged) - Number(tx.reveal_fee) > 0.005) ? `The customer paid ${aedF(tx.total_charged)} for a fee of ${aedF(tx.reveal_fee)}. Since 24 Sep 2026 he pays the fee and nothing else (_shared/reveal_fee.ts).` : null, base_is_ex_vat: isFinite(ex) ? ok : null,
      why: ok ? `The base (${aedF(base)}) is the quotation's total excluding VAT; ${rate ? (rate * 100).toFixed(2) + '%' : '?'} of it is ${aedF(fee)}.` : `The fee was calculated on ${aedF(base)}, but the quotation's total excluding VAT is ${aedF(ex)}${qr.vat_amount ? ` (the supplier stated VAT of ${aedF(qr.vat_amount)})` : ''}.` };
    if (sec.vat.overcharged) ctx.finding('product', '8', `the customer was charged more than the fee: ${sec.vat.overcharged}`);
    if (sec.vat.base_is_ex_vat === false) ctx.finding('product', '8', `the reveal fee was not calculated on the total excluding VAT: ${sec.vat.why}`);
  }
  const vq = S.s5.quotes.find((x) => x.vat_inclusive_only);
  if (vq) { const qr = vq.quote_id ? (await read(`select price_ex_vat, vat_amount, gross_amount, vat_treatment, quote_amount from public.quotes where id = ${q(vq.quote_id)}`))[0] : null;
    sec.verdicts.push(verdict(`${vq.label} stated only a total including VAT (AED ${vq.stated?.total}); the platform takes the VAT out before anything is calculated on it, or asks him`, qr ? `stored: excluding VAT ${qr.price_ex_vat ?? qr.quote_amount}, VAT ${qr.vat_amount ?? '—'}, as ${qr.vat_treatment || '—'}` : 'his quotation was not stored', qr ? Math.abs(Number(qr.price_ex_vat ?? qr.quote_amount) - Number(vq.stated?.total) / 1.05) < 1 : false)); }
  sec.fee = tx ? `AED ${tx.reveal_fee} reveal fee; the customer was charged AED ${tx.total_charged}${Number(tx.total_charged) > Number(tx.reveal_fee) ? ' (MORE than the fee)' : ''}` : 'no payment record'; sec.paid_at = tx?.paid_at; sec.payment_state = tx?.fee_status; sec.paid_with = 'Stripe test card 4242 4242 4242 4242';
  try {
    await p.goto(portalUrl('customer', 'en', `?request=${ctx.inquiryId}&quote=${pick}`), { waitUntil: 'domcontentloaded', timeout: 60000 }); await p.waitForTimeout(6000);
    await sh.take(p, 'revealed', 'What he sees after the reveal'); await p.mouse.wheel(0, 700); await p.waitForTimeout(700); await sh.take(p, 'revealed_more', 'After the reveal, further down');
    sec.revealed = [{ who: 'the customer', sees: (await p.locator('main').innerText().catch(() => '')).replace(/\s+/g, ' ').slice(0, 600) }];
  } catch (e) { ctx.finding('harness', '8', e.message); } finally { await cc.close(); }
  const inv = await waitFor(async () => { const r = await call('reveal_invoice', cust.jwt, { quote_id: pick, doc: 'invoice', lang: 'en' }, 120000); return r.json?.url ? r : null; }, { timeoutMs: 120000, everyMs: 8000 });
  if (inv?.json?.url) { const b = await fetchBytes(inv.json.url); const f = 'shared/invoice.pdf'; writeFileSync(join(dir, f), b); sec.invoice_pdf = f; ctx.exhibit(f, 'The invoice for the reveal fee', 'reveal_invoice, on our template.'); }
  else ctx.finding('product', '8', 'no invoice PDF for the reveal fee');
  // the supplier's side after the reveal, CLEAN
  const f = ctx.fixtures.find((x) => String(x.lead_id) === String(chosen?.lead_id));
  if (f) {
    const sc2 = await cleanContext('supplier', await f.fx.newSession()); const sp = await sc2.newPage();
    try { await sp.goto(portalUrl('supplier', 'en'), { waitUntil: 'domcontentloaded', timeout: 60000 }); await sp.waitForTimeout(5000); await sp.getByRole('button', { name: /Inquiries received|Quotes|My quotes/ }).first().click().catch(() => {}); await sp.waitForTimeout(3000); await sh.take(sp, 'supplier_after', `What ${chosen.label} sees after the reveal`); sec.revealed.push({ who: `the supplier (${chosen.label})`, sees: (await sp.locator('main').innerText().catch(() => '')).replace(/\s+/g, ' ').slice(0, 600) }); }
    catch (e) { ctx.finding('harness', '8', e.message); } finally { await sc2.close(); }
  }
  sec.sheets = sheetsInto(ctx, sh.list, 's8_sheet');
  const since = tx?.paid_at || st.start;
  const conf = await read(`select created_at, channel, type, subject, body, html, status, to_email, to_phone, lead_id from public.notifications where created_at >= ${q(since)} and (to_email = ${q(cust.email)} or lead_id = ${Number(chosen?.lead_id || 0)} or (to_role = 'customer' and quote_id = ${q(pick)})) order by created_at`);
  sec.confirmations = [];
  for (const n of conf) sec.confirmations.push({ channel: n.channel, to: n.lead_id ? `the supplier (${chosen.label})` : 'the customer', at: n.created_at, subject: n.subject, text: n.body || htmlText(n.html), state: n.status === 'suppressed' ? 'composed, delivery suppressed for a demo identity' : n.status, shot: n.html ? await emailShot(ctx, n.html, `s8_${n.channel}_${Date.parse(n.created_at)}`) : null });
  for (const ch of ['email', 'whatsapp']) for (const who of ['the customer', 'the supplier']) if (!sec.confirmations.some((x) => x.channel === ch && x.to.startsWith(who))) sec.gaps.push(`A ${ch === 'email' ? 'e-mail' : 'WhatsApp'} confirmation of the reveal to ${who}: none was composed.`);
  sec.verdicts.push(verdict('he pays the reveal fee (test mode), gets the invoice on our template, sees the supplier; both sides get a confirmation by e-mail and WhatsApp', `${tx ? 'paid' : 'NOT paid'}; invoice ${sec.invoice_pdf ? 'issued' : 'NOT issued'}; ${sec.confirmations.length} confirmation(s) composed`, !!(tx && sec.invoice_pdf && !sec.gaps.length)));
  clockEnd(st);
}

// ── 6 every notification to the customer ──────────────────────────────────────────────────────────────────────────
async function s6_notifications(ctx) {
  const sec = ctx.S.s6; const { cust } = ctx; if (!cust) return;
  const ids = [...ctx.run.ids.inquiries]; const qids = [...ctx.ids.quotes];
  const rows = await read(`select id, created_at, channel, type, kind, subject, body, html, status, to_email from public.notifications where created_at >= ${q(ctx.rec.journey.started)} and (to_email = ${q(cust.email)}${ids.length ? ` or (to_role = 'customer' and inquiry_id::text in (${ids.map(q).join(',')}))` : ''}) order by created_at`);
  sec.notifications = [];
  for (const n of rows) sec.notifications.push({ at: n.created_at, channel: n.channel, type: n.type || n.kind, to: 'the customer', subject: n.subject, text: n.body || htmlText(n.html), state: n.status === 'suppressed' ? 'composed, delivery suppressed for a demo identity' : n.status, shot: n.html ? await emailShot(ctx, n.html, `s6_${n.id}`) : null });
  const chans = new Set(rows.map((r) => r.channel));
  if (ctx.S.s5.quotes?.length && !rows.some((r) => /quote/i.test(`${r.type} ${r.kind} ${r.subject}`))) sec.gaps.push('A notice to the customer that quotations arrived: none was composed in this journey.');
  sec.verdicts.push(verdict('the customer is told, by e-mail and WhatsApp, when his request is sent, when quotations arrive and when he pays', `${rows.length} composed (${[...chans].join(', ') || 'none'}); qids ${qids.length}`, rows.length > 0 && chans.has('email') && chans.has('whatsapp') ? null : false));
  for (const r of rows.filter((x) => ['sent', 'queued', 'pending', 'sending'].includes(x.status))) {
    if (DISCARD.test(String(r.to_email || ''))) ctx.finding('harness', '6', `the ${r.channel} "${r.subject || r.type}" was handed to the mail provider for ${r.to_email}: that is Resend's test address, which accepts mail and throws it away. It reached nobody. (The platform sends a demo account's sign-up mail to the address it signed up with; this run signed up with a discard address on purpose.)`);
    else ctx.finding('product', '6', `the ${r.channel} "${r.subject || r.type}" to ${r.to_email || 'a phone'} is in state ${r.status}: it may have reached a person`);
  }
}

// ── inside the company: who knew, and what they did (founder ledger 1685-1688, 13 Nov 2026) ──────────────────────────
// Read ONLY from rows this run produced: company_event, the task tables (org_tasks, ceo_task, crm_tasks), notifications
// to staff roles, gl_journal + gl_journal_lines, the transaction's refund_deadline. A row that is not there is printed as
// "nobody in the company was told". "Model or code" is inferred: a model call of this run's ai_cost_log within 90 s after
// the row means a model judged; otherwise code ran (said in the dossier as an inference).
async function co_company(ctx) {
  const { rec, run } = ctx; if (!ctx.cust) return; const sec = rec.sections.co; sec.after_payment = [];
  const ids = [ctx.cust.customerId, ...run.ids.inquiries, ...ctx.ids.quotes, ...(ctx.tx ? [ctx.tx.id] : [])].filter(Boolean).map(String);
  const leadIds = (rec.sections.s5.quotes || []).map((x) => String(x.lead_id));
  const like = [...ids, ...leadIds].map((x) => q('%' + x + '%')).join(',');
  const since = rec.journey.started;
  const idList = ids.map(q).join(',') || 'null';
  // HAND-OVERS: agent_actions kind 'handoff' (agent = the receiving seat, detail.from = the sender, detail.type = a
  // seat_handoff_kind type, decided_at/decided_by = picked up). "The sender learned the outcome" = a LATER hand-over
  // addressed back to the sender on the same subject (same target_id or a detail key naming one of this run's ids).
  const ho = await read(`select a.id::text id, a.agent to_seat, a.detail->>'from' from_seat, coalesce(a.detail->>'type', a.title) type, a.status, a.created_at at, a.decided_at, a.decided_by, a.target_id,
      coalesce(k.originator_closes, false) originator_closes, k.meaning
      from public.agent_actions a left join public.seat_handoff_kind k on k.type = a.detail->>'type'
      where a.kind = 'handoff' and a.created_at >= ${q(since)} and (a.target_id in (${idList}) or a.detail->>'transaction_id' in (${idList}) or a.detail->>'quote_id' in (${idList}) or a.detail->>'inquiry_id' in (${idList}) or a.detail->>'customer_id' in (${idList}) or a.detail->>'subject_id' in (${idList}))
      order by a.created_at limit 300`).catch((e) => { ctx.finding('harness', 'co', `agent_actions: ${e.message}`); return []; });
  const ev = await read(`select id::text id, event_type, entity_type, entity_id, actor, occurred_at at, causation_id::text causation_id from public.company_event
      where occurred_at >= ${q(since)} and (entity_id in (${idList}) or payload::text ilike any(array[${like}])) order by occurred_at limit 300`).catch((e) => { ctx.finding('harness', 'co', `company_event: ${e.message}`); return []; });
  const caused = new Set(ev.map((e) => e.causation_id).filter(Boolean));
  const tasks = [
    ...(await read(`select created_at at, coalesce(assigned_agent, dept_key) seat, title, status, decided_by, updated_at from public.org_tasks where created_at >= ${q(since)} and (detail ilike any(array[${like}]) or title ilike any(array[${like}]) or result::text ilike any(array[${like}]))`).catch(() => [])).map((t) => ({ at: t.at, from: s0(t.decided_by), to: s0(t.seat), what: `org task: ${t.title}`, picked: t.status && t.status !== 'open' ? `${t.status}${t.updated_at ? ' at ' + String(t.updated_at).slice(11, 19) : ''}` : 'not picked up', back: 'no row says so' })),
    ...(await read(`select created_at at, title, state, closed_at from public.ceo_task where created_at >= ${q(since)} and (detail ilike any(array[${like}]) or title ilike any(array[${like}]) or evidence ilike any(array[${like}]))`).catch(() => [])).map((t) => ({ at: t.at, from: '—', to: 'ceo', what: `CEO task: ${t.title}`, picked: t.closed_at ? `closed ${String(t.closed_at).slice(11, 19)} (${t.state})` : `${t.state}, not closed`, back: 'no row says so' })),
    ...(await read(`select created_at at, title, status, source, done_at from public.crm_tasks where created_at >= ${q(since)} and (entity_id in (${idList}) or detail ilike any(array[${like}]))`).catch(() => [])).map((t) => ({ at: t.at, from: s0(t.source), to: 'crm', what: `CRM task: ${t.title}`, picked: t.done_at ? `done ${String(t.done_at).slice(11, 19)}` : `${t.status}, not done`, back: 'no row says so' })),
  ];
  const staff = await read(`select created_at at, to_role, type, subject, left(coalesce(body, ''), 400) body, status, channel, requested_by from public.notifications where created_at >= ${q(since)} and coalesce(to_role, '') not in ('', 'customer', 'supplier') and (inquiry_id::text in (${idList}) or quote_id::text in (${idList}) or body ilike any(array[${like}])) order by created_at`).catch(() => []);
  const cost = await read(`select occurred_at at, fn from public.ai_cost_log where e2e_run_tag = ${q(run.tag)} order by occurred_at`).catch(() => []);
  const howOf = (at) => cost.some((c) => { const d = Date.parse(c.at) - Date.parse(at); return d >= 0 && d <= 90000; }) ? 'a model judged (inferred)' : 'code ran (inferred)';
  const stepOf = (at) => (rec.steps || []).find((x) => Date.parse(at) >= Date.parse(x.start) && Date.parse(at) <= Date.parse(x.end || '9999-12-31'))?.id || null;
  const backTo = (h) => { const r = ho.find((x) => Date.parse(x.at) > Date.parse(h.at) && x.to_seat === h.from_seat && (x.target_id === h.target_id || !h.target_id)); return r ? `yes: ${r.type} back to ${h.from_seat} at ${String(r.at).slice(11, 19)}` : (h.originator_closes ? `NO: ${h.from_seat || 'the sender'} must close this kind of hand-over and no reply came back` : 'no reply came back'); };
  sec.events = [
    ...ho.map((h) => ({ at: h.at, from: s0(h.from_seat), to: s0(h.to_seat), what: `hand-over: ${h.type}${h.meaning ? ' (' + h.meaning + ')' : ''}`, picked: h.decided_at ? `${String(h.decided_at).slice(11, 19)} by ${s0(h.decided_by)} (${h.status})` : `NOT picked up (${h.status})`, back: backTo(h), how: howOf(h.at) })),
    ...ev.map((e) => ({ at: e.at, from: s0(e.actor), to: 'the shared event log (no seat addressed)', what: `${e.event_type} on ${e.entity_type} ${String(e.entity_id).slice(0, 8)}`, picked: caused.has(e.id) ? 'another row was caused by it' : 'no row was caused by it', back: '—', how: howOf(e.at) })),
    ...tasks.map((t) => ({ ...t, how: howOf(t.at) })),
    ...staff.map((n) => ({ at: n.at, from: s0(n.requested_by), to: s0(n.to_role), what: `${n.channel || 'message'}: ${n.subject || n.type}`, picked: n.status === 'suppressed' ? 'composed, delivery suppressed (demo)' : n.status, back: '—', how: null })),
  ].filter((e) => e.at).sort((a, b) => Date.parse(a.at) - Date.parse(b.at)).map((e) => ({ ...e, step: stepOf(e.at) }));
  if (!ho.length) ctx.finding('product', 'co', 'no seat handed anything over to another seat in this journey (agent_actions has no hand-over for it)');
  sec.by_step = {}; for (const st of rec.steps || []) sec.by_step[st.id] = sec.events.filter((e) => e.step === st.id);
  if (!sec.events.length) ctx.finding('product', 'co', 'nobody in the company was told anything about this journey: no event, task or staff notice row was written');
  const tx = ctx.tx;
  if (!tx) { sec.after_payment.push({ title: 'After the payment', nobody: 'There was no payment in this journey, so nothing after it could be read.' }); return; }
  // the invoice and the books
  const gl = await read(`select j.id, j.entry_no, j.entry_date, j.memo, j.source, j.source_ref, j.status, l.line_no, l.account_code, (select a.name from public.gl_accounts a where a.code = l.account_code) account, l.debit, l.credit, l.memo line_memo
      from public.gl_journal j join public.gl_journal_lines l on l.journal_id = j.id where j.source_ref in (${[tx.id, tx.stripe_invoice_number].filter(Boolean).map(q).join(',')}) order by j.id, l.line_no`).catch((e) => { ctx.finding('harness', 'co', `gl: ${e.message}`); return []; });
  const dr = gl.reduce((a, l) => a + Number(l.debit || 0), 0), cr = gl.reduce((a, l) => a + Number(l.credit || 0), 0);
  const vatLine = gl.find((l) => /vat|tax/i.test(`${l.account} ${l.line_memo}`));
  const stripeLine = gl.find((l) => /stripe|processing|merchant|bank charge|fee expense/i.test(`${l.account} ${l.line_memo}`) && Number(l.debit) > 0);
  sec.after_payment.push({ title: `The invoice and the books (invoice ${tx.stripe_invoice_number || '(no number recorded)'})`, head: ['Journal', 'Account', 'Debit', 'Credit', 'Memo'], widths: [0.14, 0.32, 0.12, 0.12, 0.3],
    rows: gl.map((l) => [`${l.entry_no || l.id} (${l.status})`, `${l.account_code} ${l.account || ''}`, l.debit ? Number(l.debit).toFixed(2) : '', l.credit ? Number(l.credit).toFixed(2) : '', s0(l.line_memo || l.memo)]),
    text: gl.length ? `Debits ${dr.toFixed(2)} and credits ${cr.toFixed(2)}: ${Math.abs(dr - cr) < 0.005 ? 'balanced' : 'NOT BALANCED'}. ${vatLine ? 'A VAT line is present: WRONG (founder 1687: we collect no VAT on the reveal fee).' : 'No VAT line, as ruled.'} ${stripeLine ? `Stripe's cost is expensed (${Number(stripeLine.debit).toFixed(2)}).` : 'No line expenses Stripe\'s cost.'} Fee arithmetic: ${S0(ctx.S.s8.vat?.why)}` : null,
    nobody: gl.length ? null : `No journal entry was written for this reveal. The books leave out demo payments by design (fn_gl_sync skips a transaction fn_gl_fixture_or_orphan names), so a demo journey cannot show the books. What the rule would write for a real payment of AED ${Number(tx.total_charged).toFixed(2)}: debit 1050 the amount net of Stripe's cost, debit 6100 Stripe's cost (${tx.stripe_fee_fils != null ? 'AED ' + (Number(tx.stripe_fee_fils) / 100).toFixed(2) : 'not reported yet'}), credit 4000 AED ${Number(tx.total_charged).toFixed(2)}; no VAT line.` });
  if (gl.length && Math.abs(dr - cr) >= 0.005) ctx.finding('product', 'co', 'the journal entry for the reveal is not balanced');
  if (vatLine) ctx.finding('product', 'co', 'the journal entry for the reveal carries a VAT line (ruling 1687: no VAT is collected on the fee)');
  if (!gl.length) ctx.finding('looked_wrong', 'co', 'no journal entry for the reveal fee: the books leave out demo payments by design, so the books cannot be proved by a demo journey');
  // the CEO / founder notice of the sale; the sales engineer's closure; the unchosen suppliers; the refund window
  const sale = staff.filter((n) => Date.parse(n.at) >= Date.parse(tx.paid_at || 0) && /ceo|founder|admin|accountant/.test(String(n.to_role)));
  sec.after_payment.push({ title: 'Who in the company heard about the sale', head: ['Time', 'To', 'What it said'], widths: [0.16, 0.16, 0.68], rows: sale.map((n) => [String(n.at).slice(11, 19), n.to_role, `${n.subject || n.type}: ${n.body}`]), nobody: sale.length ? null : 'Nobody in the company was told about this sale (no notice to the CEO, the founder or the accountant was written).' });
  const afterRow = (await read(`select status, outcome, completed_at, hired_supplier_id from public.inquiries where id = ${q(ctx.quotable)}`))[0] || {}; const after = afterRow.status ?? null;
  sec.after_payment.push({ title: 'The sales engineer and the inquiry', text: `The inquiry's status before the payment: ${s0(ctx.statusBefore)}; after it: ${s0(after)} (outcome ${s0(afterRow.outcome)}, completed ${s0(afterRow.completed_at)}, hired supplier ${s0(afterRow.hired_supplier_id)}).${after === ctx.statusBefore ? ' It did NOT change: the sales engineer did not close it.' : ''}` });
  const others = leadIds.filter((x) => x !== String(ctx.chosen?.lead_id));
  const told = others.length ? await read(`select lead_id, channel, subject, status from public.notifications where created_at >= ${q(tx.paid_at || since)} and lead_id in (${others.map(Number).join(',')})`) : [];
  sec.after_payment.push({ title: 'What the suppliers who were not chosen were told', head: ['Supplier', 'Channel', 'What it said'], widths: [0.3, 0.14, 0.56], rows: told.map((n) => [rec.sections.s5.quotes.find((x) => String(x.lead_id) === String(n.lead_id))?.label || n.lead_id, n.channel, `${n.subject} (${n.status})`]), nobody: told.length ? null : 'The suppliers who were not chosen were told nothing.' });
  const end = tx.refund_deadline ? new Date(tx.refund_deadline) : null;
  const custNotes = (await read(`select coalesce(subject, '') || ' ' || coalesce(body, '') || ' ' || coalesce(html, '') t from public.notifications where created_at >= ${q(tx.paid_at || since)} and to_email = ${q(ctx.cust.email)}`)).map((r) => r.t).join('\n');
  const forms = end ? [end.toISOString().slice(0, 10), end.toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'Asia/Dubai' }), end.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'Asia/Dubai' })] : [];
  const toldEnd = forms.some((f) => custNotes.includes(f));
  const startOk = tx.paid_at && end;
  sec.after_payment.push({ title: 'The refund window', text: `It starts at the payment, ${s0(tx.paid_at)} (transactions.revealed_at), and ends ${end ? end.toISOString() : '(no end date recorded)'}; the clock lives in transactions.refund_deadline. The customer was ${toldEnd ? '' : 'NOT '}told the end date in a message composed to him.` , nobody: startOk ? null : 'No refund window was recorded for this payment.' });
  if (!toldEnd) ctx.finding('looked_wrong', 'co', 'the customer was not told the end date of his refund window');
  for (const [t, title] of [['demo_shadow_trace', 'The demo shadow trace (what each seat would have done)'], ['accountant_reveal_payment_check', "The accountant's check of this payment"], ['request_reveal_outcome', "The sales engineer's record of the outcome"]]) {
    const exists = (await read(`select to_regclass(${q('public.' + t)}) is not null e`))[0]?.e;
    if (!exists) { sec.after_payment.push({ title, text: `(public.${t} does not exist on production yet: nothing to read.)` }); continue; }
    const rows = (await read(`select to_jsonb(x) j from public.${t} x where to_jsonb(x)::text ilike any(array[${[tx.id, ctx.pick, ctx.quotable, run.tag].filter(Boolean).map((v) => q('%' + v + '%')).join(',')}]) limit 50`).catch(() => [])).map((r) => r.j);
    sec.after_payment.push({ title, head: ['Row'], widths: [1], rows: rows.map((j) => [JSON.stringify(j).slice(0, 400)]), nobody: rows.length ? null : `public.${t} holds no row for this payment.` });
  }
  sec.verdicts.push(verdict('after the payment the accountant has the invoice in balanced books with no VAT line, the CEO knows of the sale, the sales engineer closes the inquiry, the other suppliers are told, and the refund clock starts at the payment', `${gl.length ? 'journal written' : 'NO journal'}; ${sale.length} staff notice(s) of the sale; status ${s0(ctx.statusBefore)} -> ${s0(after)}; ${told.length} notice(s) to unchosen suppliers; refund end ${end ? end.toISOString().slice(0, 10) : 'none'}`, !!(gl.length && !vatLine && Math.abs(dr - cr) < 0.005 && sale.length && after !== ctx.statusBefore && told.length && startOk)));
}
const s0 = (v) => (v == null || v === '' ? '—' : String(v));
const S0 = s0;

// ── 9 where everything is filed ───────────────────────────────────────────────────────────────────────────────────
async function s9_filing(ctx) {
  const st = clockStart(ctx, 's9'); const sec = ctx.S.s9; const { run } = ctx; if (!ctx.cust) return;
  const idLike = [ctx.cust.customerId, ...ctx.run.ids.inquiries, ...ctx.ids.quotes].map((x) => `name like ${q('%' + x + '%')}`);
  const objs = await read(`select bucket_id bucket, name path, (metadata->>'size')::bigint bytes from storage.objects where ${[...idLike, `name like ${q('%' + run.tag + '%')}`].join(' or ')} order by bucket_id, name`);
  sec.supabase = objs.map((o) => ({ what: whatIs(o), bucket: o.bucket, path: o.path, bytes: o.bytes }));
  // Dropbox: the platform's own backup, into its sandbox area for this run
  const cred = (await read(`select value from public.app_secrets where key in ('cred_fn_resilience_ping','cred_fn_backup_kick') order by key limit 1`))[0]?.value;
  const enq = await write(`select public.fn_backup_sandbox_enqueue(${q(run.tag)}) r`, 'journey proof: dropbox sandbox enqueue');
  for (let i = 0; i < 8; i++) {
    await call('dropbox_backup', null, { __secret: cred, op: 'sandbox', tag: run.tag }, 240000);
    const left = (await read(`select count(*)::int n from public.doc_backups where dedupe_key like ${q('SBX:' + run.tag + ':%')} and status <> 'done'`))[0].n; if (!left) break;
  }
  const rows = await read(`select doc_type, bucket, path, dropbox_path, status, verified_at, dropbox_content_hash, dropbox_size from public.doc_backups where dedupe_key like ${q('SBX:' + run.tag + ':%')} order by dropbox_path`);
  sec.dropbox = rows.map((r) => ({ what: r.doc_type || whatIs({ bucket: r.bucket, path: r.path }), path: r.dropbox_path, size: r.dropbox_size, hash: r.dropbox_content_hash, verified: !!r.verified_at && r.status === 'done', state: r.status }));
  const ver = await call('dropbox_backup', null, { __secret: cred, op: 'sandbox_verify', tag: run.tag }, 240000);
  const sm = ver.json?.summary || {}; sec.listing = `expected ${sm.expected ?? '?'}, listed ${sm.listed ?? '?'}, missing ${sm.missing ?? '?'}, changed ${sm.changed ?? '?'}, stray ${sm.stray ?? '?'} (HTTP ${ver.status}; enqueue ${JSON.stringify(enq?.[0]?.r || {}).slice(0, 80)})`;
  // the signed terms, in step 1: Dropbox's read-back against the certificate itself
  const t = ctx.S.s1.terms || {};
  const tr = rows.find((r) => t.storage?.path && r.path === t.storage.path) || rows.find((r) => /signed terms/i.test(r.dropbox_path));
  if (tr) t.dropbox = { path: tr.dropbox_path, size: tr.dropbox_size, content_hash: tr.dropbox_content_hash, local_content_hash: ctx.certBytes ? dropboxContentHash(ctx.certBytes) : null, verified_at: tr.verified_at,
    where_demo_files_go: `A real customer's files are filed under /QuotesDone Backup/Customers/<name> (<id>)/ by the daily backup. A demo identity's never are; this run's are under /QuotesDone Backup/_sandbox/${run.tag}/, filed by the same code on the test's request${CLEAN_DROPBOX ? ', and removed after this read-back' : ', and left there for you to open'}.` };
  else ctx.S.s1.gaps.push('The signed terms in Dropbox: no backup record of the certificate was made for this run.');
  ctx.S.s1.verdicts.push(verdict('his signed terms are in Supabase storage and in Dropbox, the same file in both', t.dropbox ? (t.dropbox.local_content_hash === t.dropbox.content_hash ? `the same file: Dropbox's content hash equals the certificate's (${String(t.dropbox.content_hash).slice(0, 16)}…)` : 'Dropbox holds a DIFFERENT file') : 'NOT in Dropbox', !!t.dropbox && t.dropbox.local_content_hash === t.dropbox.content_hash));
  if (CLEAN_DROPBOX) await call('dropbox_backup', null, { __secret: cred, op: 'sandbox_cleanup', tag: run.tag }, 120000);
  sec.verdicts.push(verdict('every document of the journey is in Supabase and has a verified copy in Dropbox', `${sec.supabase.length} files in storage; ${sec.dropbox.filter((x) => x.verified).length} of ${sec.dropbox.length} Dropbox copies read back`, sec.dropbox.length > 0 && sec.dropbox.every((x) => x.verified) && !sm.missing && !sm.changed));
  clockEnd(st);
}
const whatIs = (o) => o.bucket === 'signed-terms' ? 'signed terms certificate' : o.bucket === 'quote-files' ? 'a quotation file' : o.bucket === 'drawing-files' ? (/redacted/.test(o.path) ? 'his drawing, cleaned' : 'his drawing, as given') : o.bucket === 'finance-docs' ? 'invoice' : o.bucket === 'agent-docs' ? 'a document the platform issued' : o.bucket;

// ── 10 the close: safety, preflights, cost ─────────────────────────────────────────────────────────────────────────
async function s10_close(ctx) {
  const st = clockStart(ctx, 's10'); const { run, rec } = ctx; const sec = rec.sections.s10;
  // the preflight of every function the page called in the tagged context, by CONTENT
  const pf = [];
  for (const [fn, hs] of ctx.pageHeaders) {
    const want = [...hs].filter((h) => !/^x-qd-e2e-/.test(h) && !['accept', 'referer', 'user-agent', 'origin', 'content-length', 'accept-language', 'sec-ch-ua', 'sec-ch-ua-mobile', 'sec-ch-ua-platform'].includes(h) && !h.startsWith('sec-'));
    for (const origin of twinOrigins().slice(0, 2)) {
      const r = await fetch(`${BASE}/functions/v1/${fn}`, { method: 'OPTIONS', headers: { Origin: origin, 'Access-Control-Request-Method': 'POST', 'Access-Control-Request-Headers': want.join(',') } }).catch(() => null);
      const allow = (r?.headers.get('access-control-allow-headers') || '').toLowerCase().split(',').map((x) => x.trim());
      const ao = r?.headers.get('access-control-allow-origin') || '';
      const missing = want.filter((h) => !allow.includes(h) && !allow.includes('*'));
      pf.push({ fn, origin, status: r?.status ?? 0, missing, origin_ok: ao === '*' || ao === origin });
      if (missing.length || !(ao === '*' || ao === origin)) rec.findings.push({ severity: 'product', step: '10', text: `${fn}: a real browser on ${origin} would refuse the page's call: the preflight does not allow ${missing.join(', ') || 'this origin'}` });
    }
  }
  rec.preflights = pf;
  sec.verdicts.push(verdict('every call the page made during the chat would also be allowed by a real browser (each function\'s preflight allows the page\'s own headers and origin)', `${pf.filter((x) => !x.missing.length && x.origin_ok).length} of ${pf.length} preflights allow it`, pf.every((x) => !x.missing.length && x.origin_ok)));
  if (rec.cors_enforced) sec.verdicts.push(verdict('the clean browser used for the pictures enforces the browser\'s rules', `a call with a header no preflight allows was ${rec.cors_enforced.blocked_with_a_disallowed_header ? 'blocked' : 'NOT blocked'}; without it, it ${rec.cors_enforced.reached_without_it ? 'reached' : 'did NOT reach'} the platform`, rec.cors_enforced.blocked_with_a_disallowed_header && rec.cors_enforced.reached_without_it));
  // safety: every notification the run caused, counted by status before teardown
  const ids = (s) => [...s].map(q).join(',') || 'null';
  const notes = await read(`select status, (to_email ~* '@resend\\.dev$|@example\\.invalid$') discard, count(*)::int n from public.notifications where created_at >= ${q(rec.journey.started)} and (to_email ilike ${q('%qd-' + run.tag + '-%')} or lead_id::text in (${ids(run.ids.leads)}) or inquiry_id::text in (${ids(run.ids.inquiries)}) or quote_id::text in (${ids(ctx.ids.quotes)})) group by 1, 2`);
  rec.safety = { notifications_by_status: notes, dispatched: notes.filter((r) => ['sent', 'queued', 'pending', 'sending'].includes(r.status) && !r.discard).reduce((a, r) => a + r.n, 0), to_discard_addresses: notes.filter((r) => r.discard).reduce((a, r) => a + r.n, 0) };
  if (rec.safety.dispatched) rec.findings.push({ severity: 'product', step: '10', text: `${rec.safety.dispatched} message(s) about this demo journey are not suppressed (${JSON.stringify(notes)})` });
  sec.verdicts.push(verdict('no message about this journey reached a real person', `${notes.map((r) => `${r.n} ${r.status}${r.discard ? ' (to a discard address)' : ''}`).join(', ') || 'no messages'}`, rec.safety.dispatched === 0));
  // cost, by step
  const rows = await read(`select occurred_at at, fn, model_used model, cost_usd_reported usd from public.ai_cost_log where e2e_run_tag = ${q(run.tag)} order by occurred_at`);
  rec.cost = { ...costByStep(rows, rec.steps), note: 'USD as reported by the model provider per call (ai_cost_log.cost_usd_reported), attributed to the step whose time window holds the call.' };
  if (ctx.added?.length) rec.stand_ins.push(`The test itself invited ${ctx.added.length} supplier(s) the platform did not choose, so that quotations could be shown: ${ctx.added.map((a) => a.company).join(', ')} (listed in step 4).`);
  ctx.S.s4.verdict = { ...(ctx.S.s4.verdict || {}), added_by_test: (ctx.added || []).map((a) => ({ ...a, label: ctx.fixtures.find((f) => String(f.lead_id) === String(a.lead_id))?.label || a.company })) };
  clockEnd(st);
}

// ── the run ───────────────────────────────────────────────────────────────────────────────────────────────────────
const MAIN = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (MAIN) {
  for (const k of KEYS) { if (!SCENARIOS[k]) { console.error(`REFUSED: no journey ${k} (A, B, B2, C)`); process.exit(2); } const pr = scenarioProblems(SCENARIOS[k]); if (pr.length) { console.error('REFUSED:', pr.join('; ')); process.exit(2); } }
  for (const k of KEYS) for (const a of SCENARIOS[k].attach || []) if (a.from && (!INPUTS || !existsSync(join(INPUTS, a.from.file)))) { console.error(`REFUSED: journey ${k} needs "${a.from.file}" in --inputs`); process.exit(2); }
  const guards = (await read(`select tgname from pg_trigger where not tgisinternal and tgname in ('zzzz_notifications_demo_capture','a01_inquiry_match_demo_and_real_never_pair','a01_quote_demo_and_real_never_pair')`)).map((r) => r.tgname);
  if (guards.length !== 3) { console.error('REFUSED: the demo guards are not installed: ' + guards.join(',')); process.exit(2); }
  mkdirSync(OUT, { recursive: true });
  BROWSER = await launch();
  const done = [];
  let stopping = false;
  for (const sig of ['SIGINT', 'SIGTERM']) process.once(sig, () => { stopping = true; log(`${sig}: the journey in progress finishes its count and teardown, then the run stops`); });
  try { for (const k of KEYS) { if (stopping) break; done.push(await journey(k)); } }
  finally { await BROWSER.close().catch(() => {}); }
  for (const r of done) log(`journey ${r.journey.key}: tag ${r.journey.run_tag}, ${r.findings.length} findings, USD ${r.cost?.total_usd ?? '?'}, dossier in ${join(OUT, SCENARIOS[r.journey.key].folder)}`);
  process.exit(0);
}
