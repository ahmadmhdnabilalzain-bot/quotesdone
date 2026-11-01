// scripts/e2e/customer_signup_walk.mjs — a customer's whole sign-up, in a real browser, on the live site, with a REAL emailed code
// (2 Nov 2026, owner: customer_support). Founder: the customer's sign-up must be proved on quotesdone.ae through to the dashboard.
//
//   QD_SITE=https://quotesdone.ae SUPABASE_ACCESS_TOKEN=... node scripts/e2e/customer_signup_walk.mjs [--shots dir] [--summary file]
//
// WHAT IS REAL: /me, the "Create account" tab, the e-mail box, "Create my account", the code the product e-mails to this run's
// Resend sink (delivered+qd-<tag>-cust1@resend.dev: Resend accepts and drops it, so no person's inbox), read back through
// scripts/e2e/resend_sink.mjs and typed, then the profile form (name, date of birth, mobile), WhatsApp question, terms, the dashboard
// and each of its pages. Every screen step is asserted on screen AND in the database.
//
// WHAT IS NOT REAL, said and not hidden:
// - THE MOBILE CODE. A +971 50 000 00xx number is refused before Twilio and no SMS can be read. The refusal is asserted on screen
//   and the number is then recorded verified in the database (as fixtures.makeDemoCustomer does). That step is reported NOT REAL.
// - THE POSTING SESSION. A user created through the real form has no run credential, so the model-backed intake would be held. For
//   the posting leg only, the same account gets the run's app_metadata and a fresh password grant, injected as the harness does.
//
// A POSTED REQUEST CANNOT REACH A REAL SUPPLIER: the account's name is "ZZ DEMO ..." so customers.is_demo is true (generated column),
// demo and real never pair (inquiry_matches), and every notification about a demo inquiry is captured as 'suppressed'
// (scripts/sql/demo_identities_are_marked_and_never_reach_a_real_person.sql). The walk READS is_demo before pressing Send and does
// not press it if it is not true; after Send it counts non-demo matches and non-suppressed notices (both must be 0).
import { launch, SITE, carriesRunTag } from './browser.mjs';
import { openRun, closeRun, read, write, waitFor, BASE } from './fixtures.mjs';
import { keys, demoMobile, internalCred } from '../lib/demo_factory.mjs';
import { isSink, readCode, cleanSink } from './resend_sink.mjs';
import { mkdirSync, writeFileSync, appendFileSync } from 'node:fs';
import { join } from 'node:path';

const argv = process.argv.slice(2);
const val = (f, d) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : d; };
const SHOTS = val('--shots', 'e2e-shots'); const SUMMARY = val('--summary', 'e2e-shots/summary.json');
mkdirSync(SHOTS, { recursive: true });
const results = []; let n = 0;
const step = (name, status, detail = '') => { results.push({ n: ++n, name, status, detail }); console.log(`${status} [${n}] ${name}${detail ? ' — ' + detail : ''}`); };
const ok = (name, cond, detail = '') => step(name, cond ? 'PASS' : 'FAIL', detail);
let page = null;
const shot = async (p, name) => { await p.screenshot({ path: join(SHOTS, `${String(n + 1).padStart(2, '0')}_${name}.png`), fullPage: true }).catch(() => {}); };
const sq = (s) => `'${String(s).replace(/'/g, "''")}'`;

const run = await openRun({});
const email = `delivered+qd-${run.tag}-cust1@resend.dev`;
if (!isSink(email)) throw new Error('sink address shape: ' + email);
const fullName = `ZZ DEMO Signup ${run.tag}`;
const mobile = demoMobile();
const consent = () => localStorage.setItem('qd-cookie-consent', JSON.stringify({ necessary: true, analytics: false, marketing: false, ts: Date.now() }));
const browser = await launch();
const errs = [];
// A VERCEL PREVIEW HAS NO SUPABASE TARGET (src/lib/supaEnv.ts): it calls /functions/v1 on its own origin. Only when QD_SITE is a
// preview (not quotesdone.ae / .com) those calls are forwarded to the project, as scripts/e2e/browser.mjs does. On the live site
// this never fires. Used to prove a fix on its own branch before it is deployed.
const forwardIfPreview = async (ctx, extra = {}) => {
  const host = new URL(SITE).hostname; if (/^(www\.)?quotesdone\.(ae|com)$/.test(host)) return;
  await ctx.route(`${new URL(SITE).origin}/functions/v1/**`, async (route) => {
    const req = route.request(); const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': 'authorization, content-type, apikey, x-client-info', 'access-control-allow-methods': 'POST, GET, OPTIONS' };
    if (req.method() === 'OPTIONS') return route.fulfill({ status: 200, headers: cors, body: 'ok' });
    const h = req.headers();
    const res = await fetch(BASE + '/functions/v1/' + req.url().split('/functions/v1/')[1], { method: req.method(), headers: { ...extra, authorization: h['authorization'] || '', 'content-type': h['content-type'] || 'application/json' }, body: req.method() === 'GET' ? undefined : req.postData() });
    return route.fulfill({ status: res.status, headers: { ...cors, 'content-type': res.headers.get('content-type') || 'application/json' }, body: Buffer.from(await res.arrayBuffer()) });
  });
};
let teardown = null;
try {
  const ctx = await browser.newContext({ viewport: { width: 1366, height: 900 }, locale: 'en-GB' });
  await ctx.addInitScript(consent); await forwardIfPreview(ctx);
  page = await ctx.newPage(); page.setDefaultTimeout(45000);
  page.on('pageerror', (e) => errs.push(String(e.message).slice(0, 300) + ' @ ' + String(e.stack || '').split('\n')[1]?.trim().slice(0, 120)));
  const cons = [], fails = [];
  page.on('console', (m) => { if (m.type() === 'error') cons.push(m.text().slice(0, 200)); });
  page.on('response', (r) => { if (r.status() >= 400 && /supabase|functions/.test(r.url())) fails.push(`${r.status()} ${r.url().split('?')[0].slice(-60)}`); });
  const M = page.locator('main');

  // 1. /me and the Create account tab
  await page.goto(`${SITE}/me`, { waitUntil: 'domcontentloaded' });
  const tab = page.getByRole('tab', { name: /^Create account$/ });
  await tab.waitFor({ timeout: 30000 }).catch(() => {});
  await tab.click().catch(() => {});
  const h1 = await page.locator('h1').first().innerText().catch(() => '');
  await shot(page, 'me_create_account_tab');
  ok('/me opens, tab "Create account" shows "Create your account"', /Create your account/.test(h1), `site ${SITE}; h1 "${h1}"`);
  const emailBox = page.getByRole('textbox', { name: /Email address/i }).first();

  // 2. a reserved address is refused before any code is sent
  await emailBox.fill(`qd-${run.tag}-x@example.invalid`);
  await page.getByRole('button', { name: /^Create my account$/ }).click();
  const refused = await page.getByText(/reserved for examples and testing/).first().waitFor({ timeout: 10000 }).then(() => true).catch(() => false);
  await shot(page, 'reserved_refused');
  ok('a reserved address (example.invalid) is refused on screen before any code', refused);

  // 3. the run's sink address: Create my account sends the real code
  await emailBox.fill(email);
  await shot(page, 'email_typed');
  const t0 = Date.now();
  await page.getByRole('button', { name: /^Create my account$/ }).click();
  const codeBox = page.locator('input[autocomplete="one-time-code"]');
  const sent = await codeBox.waitFor({ timeout: 25000 }).then(() => true).catch(() => false);
  await shot(page, 'code_step');
  ok('"Create my account" sends the code and opens the code step', sent, `${Date.now() - t0} ms; ${sent ? '' : (await page.locator('[role=alert]').allInnerTexts().catch(() => [])).join(' | ')}`);
  if (!sent) throw new Error('no code step');
  const ev = (await read(`select count(*)::int c from public.email_verifications where lower(email)=lower(${sq(email)})`))[0];
  ok('database: a verification row exists for the address', ev.c > 0, `email_verifications ${ev.c}`);

  // 4. the REAL code from the delivered e-mail
  const got = await readCode(email, t0);
  ok('the code e-mail is delivered by Resend and carries a 6-digit code', !!got.code && /delivered|sent/.test(String(got.last_event || '')),
    `from ${got.from}; subject "${got.subject}"; last_event ${got.last_event}; accepted ${got.queued_ms} ms after the click; read ${got.read_ms} ms`);
  if (!got.code) throw new Error('no code in the delivered e-mail');
  await codeBox.fill(got.code);
  await page.getByRole('button', { name: /^Verify & continue$/ }).click();
  const gate = await page.getByRole('heading', { name: /Complete your account/ }).waitFor({ timeout: 40000 }).then(() => true).catch(() => false);
  await shot(page, 'after_code_complete_your_account');
  ok('the real code verifies and "Complete your account" opens', gate, gate ? '' : `screen: "${(await page.locator('body').innerText().catch(() => '')).replace(/\s+/g, ' ').slice(0, 120)}"; page errors: ${errs.join(' | ') || 'none'}; console: ${cons.slice(-6).join(' | ')}; failed requests: ${fails.slice(-6).join(' | ')}`);
  const au = (await read(`select id::text, email_confirmed_at is not null conf from auth.users where lower(email)=lower(${sq(email)})`))[0];
  ok('database: the auth user exists and its e-mail is confirmed', !!au?.id && au.conf === true, JSON.stringify(au));
  if (!gate) throw new Error('profile form never opened');

  // 5. name, mobile, date of birth, Save details
  await page.getByRole('textbox', { name: /^Full name$/ }).fill(fullName);
  await page.getByRole('textbox', { name: /^Mobile$/ }).fill(mobile);
  await page.locator('#qd-dob').fill('1990-01-15');
  await shot(page, 'profile_filled');
  await page.getByRole('button', { name: /^Save details$/ }).click();
  const mobHead = await page.getByText(/Verify your mobile/).first().waitFor({ timeout: 30000 }).then(() => true).catch(() => false);
  const cu = await waitFor(async () => (await read(`select id::text, full_name, date_of_birth::text dob, phone, email_verified, phone_verified, is_demo from public.customers where lower(email)=lower(${sq(email)})`))[0] || null, { timeoutMs: 20000 });
  if (cu?.id) run.ids.customers.add(cu.id);
  ok('Save details: name, date of birth and mobile are stored; the account is marked demo', mobHead && cu?.full_name === fullName && cu?.dob === '1990-01-15' && !!cu?.phone && cu?.is_demo === true, JSON.stringify(cu));

  // 6. mobile code: refused for a fixture number (no SMS can be read). Asserted, then recorded verified.
  await page.getByRole('button', { name: /^Send the code on WhatsApp$/ }).click();
  await page.waitForTimeout(6000);
  const smsBox = await page.locator('input[autocomplete="one-time-code"]').count();
  const errTxt = (await M.innerText().catch(() => '')).replace(/\s+/g, ' ').slice(-260);
  await shot(page, 'mobile_code_refused');
  ok('a fixture mobile is refused before any SMS (no code box appears)', smsBox === 0, `screen text: ${JSON.stringify(errTxt)}`);
  await write(`update public.customers set phone_verified = true where lower(email)=lower(${sq(email)})`, 'fixture mobile verified');
  step('mobile verification by SMS/WhatsApp code', 'NOT REAL', 'no SMS to a fixture number can be read; the number was recorded verified in the database after the refusal above');
  await page.reload({ waitUntil: 'domcontentloaded' });
  await page.getByRole('heading', { name: /Complete your account/ }).waitFor({ timeout: 30000 });

  // 7. e-mail: the first code already verified it; if the form still asks, use a second real code
  const emBtn = page.getByRole('button', { name: /email code/i });
  if (await emBtn.isVisible().catch(() => false)) {
    const t1 = Date.now(); await emBtn.click();
    const g2 = await readCode(email, t1);
    await page.locator('input[aria-label="Verification code"]').fill(g2.code || '');
    await page.getByRole('button', { name: /^Verify$/ }).click();
    step('profile form asked for the e-mail code again', g2.code ? 'PASS' : 'FAIL', 'second real code read from the sink (the sign-up code did not mark the e-mail verified on this screen)');
  }

  // 8. WhatsApp question, terms, Finish
  const radio = page.getByRole('radio').first();
  const waSeen = await radio.waitFor({ timeout: 20000 }).then(() => true).catch(() => false);
  if (waSeen) { await radio.check(); await shot(page, 'whatsapp_question'); await page.getByRole('button', { name: /^Continue$/ }).click(); }
  ok('the WhatsApp question is shown and answered ("same number")', waSeen);
  const terms = page.getByRole('checkbox', { name: /I accept the QuotesDone/ });
  const termsSeen = await terms.waitFor({ timeout: 30000 }).then(() => true).catch(() => false);
  if (termsSeen) { await terms.check(); await shot(page, 'terms'); }
  ok('the terms step appears once mobile, e-mail and WhatsApp are settled', termsSeen);
  await page.getByRole('button', { name: /^Finish & continue$/ }).click();
  const dash = await page.getByRole('button', { name: /^New request/ }).first().waitFor({ timeout: 60000 }).then(() => true).catch(() => false);
  await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});
  await shot(page, 'dashboard');
  ok('Finish & continue lands on the customer dashboard', dash);
  const fin = await waitFor(async () => { const r = (await read(`select email_verified, phone_verified, date_of_birth is not null dob, is_demo, tos_version, (signed_terms_path is not null or signed_terms_url is not null) signed from public.customers where lower(email)=lower(${sq(email)})`))[0]; return r?.signed ? r : null; }, { timeoutMs: 60000 });
  ok('database: e-mail and mobile verified, terms accepted and signed, still demo', !!fin && fin.email_verified && fin.phone_verified && fin.dob && fin.is_demo && !!fin.tos_version, JSON.stringify(fin));

  // 9. the dashboard's pages, each signed in with the REAL session this sign-up made
  for (const id of ['', 'projects', 'spatial', 'documents', 'messages', 'orders', 'predict', 'profile', 'account']) {
    await page.goto('about:blank'); await page.goto(`${SITE}/me${id ? '#' + id : ''}`, { waitUntil: 'domcontentloaded' });
    await page.locator('nav:visible, button[aria-controls="qd-nav-more"]:visible').first().waitFor({ timeout: 30000 }).catch(() => {});
    const t = Date.now(); let busy = true;
    while (Date.now() - t < 25000 && busy) { busy = await page.locator('main').evaluate((el) => /Loading|Measuring/.test(el.innerText) || !!el.querySelector('[aria-busy="true"]')).catch(() => false); if (busy) await page.waitForTimeout(300); }
    const body = (await page.locator('main').innerText().catch(() => '')).replace(/\s+/g, ' ');
    await shot(page, 'page_' + (id || 'overview'));
    ok(`dashboard page "${id || 'overview'}" opens and settles`, !busy && body.length > 40 && !/something went wrong|couldn.t load your account|session has expired/i.test(body), `${Date.now() - t} ms; "${body.slice(0, 90)}"`);
  }
  ok('no uncaught page errors during sign-up and the dashboard walk', errs.length === 0, errs.join(' | '));
  await ctx.close();

  // 10. posting a request, as far as it can go without reaching a real supplier
  const { SERVICE, ANON } = await keys();
  const pw = 'Demo-' + Math.random().toString(36).slice(2) + 'A1!';
  const up = await fetch(`${BASE}/auth/v1/admin/users/${au.id}`, { method: 'PUT', headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE, 'Content-Type': 'application/json' }, body: JSON.stringify({ password: pw, app_metadata: { e2e_run: run.tag } }) });
  const s = await (await fetch(`${BASE}/auth/v1/token?grant_type=password`, { method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password: pw }) })).json();
  ok('posting leg: a run-scoped session for the same account', up.ok && !!s.access_token, `admin update HTTP ${up.status}`);
  if (!s.access_token) throw new Error('no session for posting');
  const ctx2 = await browser.newContext({ viewport: { width: 1366, height: 900 }, locale: 'en-GB' });
  const extra = { 'x-qd-e2e-run': run.tag, 'x-qd-e2e-secret': await internalCred() };
  await forwardIfPreview(ctx2, extra);
  await ctx2.route((u) => carriesRunTag(u, BASE), (route) => route.request().method() === 'OPTIONS' ? route.continue() : route.continue({ headers: { ...route.request().headers(), ...extra } }));
  await ctx2.addInitScript(([s]) => { try {
    localStorage.setItem('qd-cust-token', s.access_token); localStorage.setItem('qd-cust-refresh', s.refresh_token);
    localStorage.setItem('qd-cust-auth', JSON.stringify({ access_token: s.access_token, refresh_token: s.refresh_token, expires_in: s.expires_in, expires_at: s.expires_at, token_type: 'bearer', user: s.user }));
    localStorage.setItem('qd-lang', 'en'); localStorage.setItem('qd-cookie-consent', JSON.stringify({ necessary: true, analytics: false, marketing: false, ts: Date.now() }));
  } catch {} }, [s]);
  const p2 = await ctx2.newPage(); page = p2; p2.setDefaultTimeout(45000);
  await p2.goto(`${SITE}/me`, { waitUntil: 'domcontentloaded' });
  await p2.getByRole('button', { name: /^New request/ }).first().click({ timeout: 40000 });
  const box = p2.locator('#qd-intake-input'); await box.waitFor({ state: 'visible', timeout: 20000 });
  const answers = ['We need 40 aluminium windows supplied and installed for a private villa in Dubai Marina. Sizes 1200 x 1500 mm, double glazed, powder coated white.',
    'Installation is required, including removal of the old windows. We need a 2 year warranty covering materials and workmanship.',
    'Materials: thermal break aluminium frames, double glazed 6-12-6 glass, powder coated RAL 9016. Delivery needed by 30 November 2026.',
    'Ground and first floor, direct vehicle access, no crane needed. Budget is open.', 'Please proceed with these details.', 'Yes, that is correct.'];
  let status = null, turns = 0; const deadline = Date.now() + 5 * 60 * 1000;
  const ask = async (act) => { const [r] = await Promise.all([p2.waitForResponse((x) => x.url().includes('/functions/v1/inquiry_intake'), { timeout: 90000 }).catch(() => null), act()]); turns++; const j = r ? await r.json().catch(() => ({})) : {}; status = j.status ?? status; };
  for (const a of answers) {
    if (Date.now() > deadline || status === 'ready') break;
    await box.fill(a); await ask(() => box.press('Enter'));
    if (status === 'ready') break;
    const chip = p2.locator('[role="group"] button').first();
    if (await chip.isVisible().catch(() => false)) await ask(() => chip.click().catch(() => {}));
  }
  await shot(p2, 'intake_conversation');
  ok('the sales-engineer interview reaches ready', status === 'ready', `${turns} turn(s), status ${status}`);
  if (status === 'ready') {
    // THE GUARANTEE, read before the send button is pressed.
    const g = (await read(`select is_demo, public.fn_is_demo_phone(phone) phone_demo from public.customers where lower(email)=lower(${sq(email)})`))[0];
    if (g?.is_demo !== true) { step('send to suppliers', 'BLOCKED', `customers.is_demo is ${g?.is_demo}: it cannot be guaranteed that no real supplier is reached, so Send was NOT pressed`); }
    else {
      const [res] = await Promise.all([
        p2.waitForResponse((r) => r.url().includes('/functions/v1/customer_api') && (r.request().postData() || '').includes('create_inquiry'), { timeout: 90000 }).catch(() => null),
        p2.getByRole('button', { name: /Send to suppliers/ }).first().click({ timeout: 20000 }),
      ]);
      const j = res ? await res.json().catch(() => ({})) : {};
      const iid = j.inquiry_id ?? j.parent_id ?? j.id ?? null;
      for (const c of [iid, ...(Array.isArray(j.child_ids) ? j.child_ids : [])]) if (c) run.ids.inquiries.add(String(c));
      await p2.getByText(/Request sent/).first().waitFor({ timeout: 20000 }).catch(() => {});
      await shot(p2, 'request_posted');
      ok('"Send to suppliers" posts the request', !!iid, `HTTP ${res?.status() ?? 0}; ${JSON.stringify(j).slice(0, 160)}`);
      if (iid) {
        await new Promise((r) => setTimeout(r, 20000));
        const ids = [...run.ids.inquiries].map(sq).join(',');
        const d = (await read(`select (select count(*)::int from public.inquiries i join public.customers c on c.id=i.customer_id where i.id in (${ids}) and lower(c.email)=lower(${sq(email)})) mine,
          (select count(*)::int from public.inquiries where id in (${ids}) and public.fn_inquiry_is_demo(id)) demo,
          (select count(*)::int from public.inquiry_matches m join public.leads l on l.id=m.supplier_id where m.inquiry_id in (${ids}) and l.is_demo is not true) real_matches,
          (select count(*)::int from public.inquiry_matches where inquiry_id in (${ids})) all_matches,
          (select count(*)::int from public.notifications where inquiry_id in (${ids}) and status not in ('suppressed')) live_notices,
          (select count(*)::int from public.notifications where inquiry_id in (${ids})) all_notices`))[0];
        ok('database: the request is the customer\'s and is a demo request', d.mine >= 1 && d.demo >= 1, JSON.stringify(d));
        ok('database: no real supplier is matched and no notice about it is live (all suppressed)', d.real_matches === 0 && d.live_notices === 0, `real matches ${d.real_matches} of ${d.all_matches}; non-suppressed notices ${d.live_notices} of ${d.all_notices}`);
      }
    }
  }
  await ctx2.close();
} catch (e) {
  console.error('WALK ERROR', String(e?.message || e).split('\n')[0]);
  step('walk completed', 'FAIL', String(e?.message || e).split('\n')[0]);
  if (page) await page.screenshot({ path: join(SHOTS, `error_${Date.now()}.png`), fullPage: true }).catch(() => {});
  process.exitCode = 1;
} finally {
  await browser.close();
  try {
    const c = await closeRun(run, {}); const l = await cleanSink(email).catch((e) => ({ error: String(e.message) }));
    teardown = { run: c.leftovers, sink: l };
    console.log('teardown:', JSON.stringify(teardown));
    const dirty = (c.leftovers?.total ?? 0) + Object.values(l || {}).reduce((a, b) => a + (Number(b) || 0), 0);
    step('teardown leaves nothing behind', dirty === 0 ? 'PASS' : 'FAIL', JSON.stringify(teardown));
  } catch (e) { step('teardown leaves nothing behind', 'FAIL', String(e.message).slice(0, 200)); }
}
const bad = results.filter((r) => r.status === 'FAIL' || r.status === 'BLOCKED');
writeFileSync(SUMMARY, JSON.stringify({ tag: run.tag, site: SITE, email, results, teardown }, null, 2));
if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, `## Customer sign-up walk (${SITE})\n\n| # | result | step | detail |\n|---|---|---|---|\n` + results.map((r) => `| ${r.n} | ${r.status} | ${r.name} | ${String(r.detail).replace(/\|/g, '/').slice(0, 220)} |`).join('\n') + '\n');
console.log(`${results.length - bad.length}/${results.length} not failed (NOT REAL steps are listed as such)`);
process.exit(bad.length ? 1 : 0);
