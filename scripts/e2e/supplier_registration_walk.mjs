// scripts/e2e/supplier_registration_walk.mjs — a campaign-invited supplier registers, end to end
// (21 Sep 2026, owner: sales_engineer). Founder, before the supplier registration campaign: "I don't
// want any supplier to enter my platform and then he says, oh, there's a bug, it's not working."
//
//   node scripts/e2e/supplier_registration_walk.mjs [--lang en,ar] [--vp desktop,mobile] [--keep]
//   QD_SITE=http://localhost:3000 node scripts/e2e/supplier_registration_walk.mjs   # a local build
//
// Per matrix it creates ONE invited ZZ DEMO lead (as enqueue_supplier_invites leaves it: invite_status
// 'sent', a claim_token), then walks what that supplier does, asserting each step on screen AND in the
// database, and tears everything down (auth user, lead, files) at the end.
//
// WHERE IT DOES NOT DRIVE THE REAL THING, AND WHY (said, not hidden):
// - The e-mail OTP. A reserved domain can never receive a code, and the sign-up screen refuses one
//   before sending (src/lib/signupEmail.ts). The code is seeded hashed and verified through the real
//   login_otp endpoint (demo_factory.verifyEmailByOtp) — exactly the proof claim reads — and the
//   session is injected with the claim token in sessionStorage, as the landing page leaves it.
// - The mobile OTP. A +971 50 000 00xx number is refused before Twilio (mobile_otp / kyc send_sms);
//   the refusal is asserted, then the number is recorded verified, as fixtures.makeDemoSupplier does.
// Everything after that is the portal's own screens and endpoints.
//
// What it guards (each was a defect found by walking this path on 21 Sep 2026):
//   1. no blank "Register your company" form after the claim (the claim race);
//   2. the WhatsApp question is on screen whenever registration demands it (the edit-mode dead end);
//   3. terms + Save end in approved with a signed certificate (and a failed certificate heals on Save);
//   4. every tab, the bell and the account menu settle (no endless "Loading…").
import { SANDBOX_OUT } from '../lib/sandbox_out.mjs';
import { launch, SITE } from './browser.mjs';
import { openRun, closeRun, read, write, call, BASE, waitFor } from './fixtures.mjs';
import { keys, verifyEmailByOtp, mkAuthUser } from '../lib/demo_factory.mjs';
import { sinkAddress, isSink, readCode, cleanSink } from './resend_sink.mjs';
import { demoPdf, demoTradeLicence } from '../lib/demo_pdf.mjs';
import { writeFileSync, mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const argv = process.argv.slice(2);
const val = (f, d) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : d; };
const LANGS = val('--lang', 'en,ar').split(','); const VPS = val('--vp', 'desktop,mobile').split(',');
const KEEP = argv.includes('--keep');
// --desktop-width (28 Oct 2026, sales_engineer): the founder asked for 1366, the commonest UAE office laptop width;
// 1440 stays the default so earlier runs compare like with like.
const DESKTOP_W = Number(val('--desktop-width', '1440'));
// --real-otp (28 Oct 2026, sales_engineer): the invited leg signs up through the real form with the real e-mail code,
// delivered to the run's Resend sink and read back (scripts/e2e/resend_sink.mjs). Steps over 3 s are reported.
const REAL_OTP = argv.includes('--real-otp');
const sinks = [];
// FOUNDER LEDGER 1469 (2 Nov 2026): a supplier is verified only after it confirms its services. The gate is a database routine applied at merge,
// so the walk asks the database which rule is live and asserts THAT rule: the old order (terms + Save = approved) until the gate is applied,
// the new order (held for services_unconfirmed, then approved by the supplier's own confirm) once it is. The unapplied half is printed as
// NOT RUN, never as a pass.
let gateLive = false;

async function realOtpSignup({ browser, ctxOpts, consent, url, email, company, m }) {
  const ctx = await browser.newContext(ctxOpts); await ctx.addInitScript(consent); const p = await ctx.newPage();
  try {
    await p.goto(url, { waitUntil: 'domcontentloaded' });
    const box = p.locator('#qd-supplier-signin');
    // The supplier's own first move: "Claim my listing" on the invitation card, which must bring the sign-up box
    // into view (at 1366x900 and 390x844 it starts below the fold).
    await box.locator('input').first().waitFor({ timeout: 20000 });
    const claimBtn = p.getByRole('button', { name: /^Claim my listing$/ }).first();
    const hasClaim = await claimBtn.waitFor({ timeout: 15000 }).then(() => true).catch(() => false);   // claim_lookup answers after mount
    if (hasClaim) { await claimBtn.click(); await p.waitForTimeout(900); }
    const inView = await box.locator('input').first().evaluate((el) => { const r = el.getBoundingClientRect(); return r.top >= 0 && r.bottom <= window.innerHeight; }).catch(() => false);
    step(m, '"Claim my listing" brings the e-mail box into view', hasClaim && inView, hasClaim ? (inView ? '' : 'box still off-screen') : 'button missing');
    await box.locator('input').first().fill(email);
    await shot(p, m, 'realotp_email_typed');
    const t0 = Date.now();
    await box.getByRole('button', { name: /^Create my account$/ }).click();
    const codeBox = box.locator('input[autocomplete="one-time-code"]');
    const sentOk = await codeBox.waitFor({ timeout: 20000 }).then(() => true).catch(() => false);
    const sendMs = Date.now() - t0;
    const shown = await box.innerText().catch(() => '');
    await shot(p, m, 'realotp_code_screen');
    step(m, 'the form sends the code and opens the code step', sentOk, `${sendMs} ms${sendMs > 3000 ? ' (>3 s)' : ''}${sentOk ? '' : ' — screen: ' + shown.slice(0, 160)}`);
    if (!sentOk) return null;
    step(m, 'the code step names the address the code went to (#1700)', /We sent a 6-digit code to/.test(shown) && shown.includes(email), shown.split('\n').slice(0, 3).join(' | ').slice(0, 160));
    const got = await readCode(email, t0);
    step(m, 'the code e-mail is delivered and carries a 6-digit code', !!got.code && /delivered|sent/.test(String(got.last_event || '')),
      `from ${got.from}; subject "${got.subject}"; last_event ${got.last_event}; accepted by Resend ${got.queued_ms} ms after the click; read ${got.read_ms} ms`);
    if (!got.code) return null;
    await codeBox.fill(got.code);
    const t1 = Date.now();
    await box.getByRole('button', { name: /^Verify and continue$|^Verify/ }).first().click();
    const heading = p.getByRole('heading', { name: company });
    const ok = await heading.waitFor({ timeout: 30000 }).then(() => true).catch(() => false);
    const vMs = Date.now() - t1;
    await shot(p, m, 'realotp_claimed_company');
    step(m, 'the real code verifies and the invited company opens, claimed', ok, `${vMs} ms${vMs > 3000 ? ' (>3 s)' : ''}`);
    const auth = await p.evaluate(() => { try { return JSON.parse(localStorage.getItem('qd-portal-auth') || 'null'); } catch { return null; } });
    const tok = await p.evaluate(() => ({ a: localStorage.getItem('qd-sup-token'), r: localStorage.getItem('qd-sup-refresh') }));
    return auth?.access_token ? auth : (tok.a ? { access_token: tok.a, refresh_token: tok.r, expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600, user: null } : null);
  } finally { await ctx.close(); }
}
// --shots <dir>: a full-page screenshot of every screen, named <lang>_<vp>_<nn>_<step>.png (24 Sep 2026, ledger 993).
const SHOTS = val('--shots', ''); let shotN = 0;
const shot = async (p, m, name) => { if (!SHOTS) return; const f = join(SHOTS, `${m.replace('/', '_')}_${String(++shotN).padStart(2, '0')}_${name}.png`); await p.screenshot({ path: f, fullPage: true }).catch(() => {}); console.log('  shot', f); };
const TMP = mkdtempSync(join(tmpdir(), 'qd-regwalk-'));
// SUPPLIERS ARE ALWAYS ENGLISH (founder, 28 Sep 2026): SupplierPortal rewrites /ar/portal to /portal and renders
// English. The ar leg is kept to prove an /ar/ invitation link still lands, signs up and registers, so every
// on-screen assertion expects English (19 Oct 2026, sales_engineer, ruling 1230 walk: the ar leg failed on
// "Register as a supplier", then timed out on an Arabic Upload button the portal never shows).
const AR = () => false;
const results = [];
const step = (m, name, ok, detail = '') => { results.push({ m, name, ok, detail }); console.log(`${ok ? 'PASS' : 'FAIL'} [${m}] ${name}${detail ? ' — ' + detail : ''}`); };

// --case <truth id,...> (13 Oct 2026, ruling 1230, it_engineer): instead of a generated licence, upload a corpus
// licence (default corpus: the 12 Oct accuracy run) under an invited name that DIFFERS from it, and assert ruling
// 1176 (the read licence name becomes the company name), the licence number and expiry, the profile + catalogue
// (ruling 1177), and the outcome the corpus truth expects: approved, or held with a reason. Scans and Arabic-only
// licences need the vision model; openRun's window has models on for every run (ruling 1260).
const CASES = val('--case', '').split(',').filter(Boolean);
const CORPUS = val('--corpus', join(SANDBOX_OUT, 'documents/run-final-12-oct-model-on/corpus'));
const TRUTH = CASES.length ? JSON.parse(readFileSync(join(CORPUS, 'truth.json'), 'utf8')).docs : [];
const MATRIX = CASES.length ? CASES.map((c, i) => ({ lang: 'en', vp: VPS[i % VPS.length], c: TRUTH.find((d) => d.id === c) || (() => { throw new Error('no corpus case ' + c); })() }))
  : LANGS.flatMap((lang) => VPS.map((vp) => ({ lang, vp, c: null })));
const esc = (x) => String(x).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// --fresh (27 Oct 2026, it_engineer, founder: "is the browser test for the supplier register journey done?"): a
// supplier who was NOT invited, from the public /supplier page through the sign-up form, "Register your company"
// with its trade, the registration form (emirates, licence, company profile, catalogue, mobile, WhatsApp, terms),
// Submit, the Services tab (the sales engineer's rewrite, confirmed) and the Inquiries received tab. Each of the
// founder's seven steps is timed and written to --summary <file>. The invited legs are unchanged.
const FRESH = argv.includes('--fresh');
const SUMMARY = val('--summary', '');
// --cap-usd: the run's rehearsal-window ceiling on tagged model spend (fn_kernel_paid_provider_gate). openRun's default stays.
const CAP = val('--cap-usd', '');
const journey = [];
const jstep = (m, no, name, ok, ms, detail = '') => { journey.push({ m, step: no, name, status: ok ? 'PASS' : 'FAIL', ms, detail }); step(m, `STEP ${no} ${name}`, ok, `${ms} ms${detail ? ' — ' + detail : ''}`); };

async function freshLeg({ run, browser, m, n, lang, vp, email, company }) {
  const mobile = vp === 'mobile';
  const ctxOpts = { viewport: mobile ? { width: 390, height: 844 } : { width: DESKTOP_W, height: 900 }, locale: 'en-GB', ...(mobile ? { isMobile: true, hasTouch: true, deviceScaleFactor: 2 } : {}) };
  const consent = () => localStorage.setItem('qd-cookie-consent', JSON.stringify({ necessary: true, analytics: false, marketing: false, ts: Date.now() }));
  const pre = lang === 'ar' ? '/ar' : '';
  const fixtureMobile = `+9715000000${String(10 + n).padStart(2, '0')}`;

  // STEP 1. The supplier landing page, its call to action, and the sign-up form it opens.
  let refusal = { ok: false, ms: 0 }; let kept = null;
  { const ctx = await browser.newContext(ctxOpts); await ctx.addInitScript(consent); const p = await ctx.newPage(); const t0 = Date.now();
    await p.goto(`${SITE}${pre}/supplier`, { waitUntil: 'domcontentloaded' });
    const h1 = await p.locator('h1').first().innerText({ timeout: 20000 }).catch(() => '');
    await shot(p, m, 'step1_supplier_landing');
    const cta = p.getByRole('link', { name: /Open the supplier portal|بوابة المور/ }).first();
    const ctaSeen = await cta.isVisible().catch(() => false);
    if (ctaSeen) await cta.click();
    await p.waitForURL(/\/portal/, { timeout: 20000 }).catch(() => {});
    await p.locator('#qd-supplier-signin').waitFor({ timeout: 20000 }).catch(() => {});
    const tab = p.locator('#qd-supplier-signin').getByRole('button', { name: /^(Create account|إنشاء حساب)$/ }).first();
    if (await tab.isVisible().catch(() => false)) await tab.click();
    const form = await p.locator('#qd-supplier-signin h1').innerText({ timeout: 10000 }).catch(() => '');
    await shot(p, m, 'step1_signup_form');
    jstep(m, 1, 'supplier landing page and sign-up form', !!h1 && ctaSeen && /\/portal/.test(p.url()) && /Register as a supplier/.test(form), Date.now() - t0,
      `landing h1 "${h1.slice(0, 60)}"; CTA ${ctaSeen ? 'shown' : 'MISSING'} -> ${p.url().replace(SITE, '')}; form "${form}"`);

    // STEP 2a. The real form refuses a reserved test domain BEFORE any code is sent (no OTP bypass in production code).
    const t1 = Date.now();
    await p.locator('#qd-supplier-signin input').first().fill(REAL_OTP ? `qd-${run.tag}-refuse${n}@example.invalid` : email);
    await p.locator('#qd-supplier-signin').getByRole('button', { name: /^(Create my account|إنشاء حسابي)$/ }).click();
    const refused = await p.getByText(/reserved for examples and testing|محجوز للأمثلة/).first().waitFor({ timeout: 10000 }).then(() => true).catch(() => false);
    await shot(p, m, 'step2_reserved_domain_refused');
    refusal = { ok: refused, ms: Date.now() - t1 };
    if (REAL_OTP) kept = { ctx, p }; else await ctx.close(); }

  // STEP 2 (--real-otp): the REAL e-mail code. The same page types the run's Resend sink address into the real form, the
  // server sends the code through Resend, the delivered message is read back (resend_sink.mjs) and typed. No seeded OTP,
  // no injected session: the session the page ends with is the one the real verification minted.
  let sReal = null;
  if (REAL_OTP) {
    const { p } = kept; const box = p.locator('#qd-supplier-signin'); const t2r = Date.now();
    await box.locator('input').first().fill(email);
    await shot(p, m, 'step2_real_email_typed');
    const tSend = Date.now();
    await box.getByRole('button', { name: /^Create my account$/ }).click();
    const codeBox = box.locator('input[autocomplete="one-time-code"]');
    const sentOk = await codeBox.waitFor({ timeout: 20000 }).then(() => true).catch(() => false);
    const shown = await box.innerText().catch(() => '');
    await shot(p, m, 'step2_code_screen');
    let got = { code: null }, claimed = false;
    if (sentOk) {
      got = await readCode(email, tSend);
      if (got.code) {
        await codeBox.fill(got.code);
        await box.getByRole('button', { name: /^Verify and continue$|^Verify/ }).first().click();
        claimed = await p.locator('main').getByText(/^Register your company$/).first().waitFor({ timeout: 30000 }).then(() => true).catch(() => false);
      }
    }
    await shot(p, m, 'step2_after_verify');
    const tok = await p.evaluate(() => { try { const a = JSON.parse(localStorage.getItem('qd-portal-auth') || 'null'); return a?.access_token ? a : { access_token: localStorage.getItem('qd-sup-token'), refresh_token: localStorage.getItem('qd-sup-refresh') }; } catch { return null; } });
    sReal = tok?.access_token ? tok : null;
    const ev = (await read(`select count(*)::int n from auth.users where lower(email)=lower('${email}') and email_confirmed_at is not null`))[0].n;
    jstep(m, 2, 'REAL e-mail code: the form sends it, Resend delivers it, it is read back and typed, the real session opens the registration form',
      refusal.ok && sentOk && !!got.code && claimed && !!sReal && ev === 1, refusal.ms + (Date.now() - t2r),
      `reserved-domain refusal ${refusal.ok}; code step ${sentOk}; mail from ${got.from}, subject "${got.subject}", last_event ${got.last_event}, accepted ${got.queued_ms} ms after click; code typed ${!!got.code}; registration form opened ${claimed}; auth user confirmed in DB ${ev}${sentOk ? '' : '; screen: ' + shown.slice(0, 120)}`);
    if (!sReal) { await kept.ctx.close(); return; }
  }

  // STEP 2b. The e-mail code: seeded hashed and verified through the real login_otp endpoint (the harness's OTP path).
  const t2 = Date.now();
  const u = REAL_OTP ? null : await mkAuthUser(run, email);
  const v = REAL_OTP ? null : await verifyEmailByOtp(email, 'supplier');
  const { ANON } = await keys();
  const s = REAL_OTP ? sReal : await (await fetch(`${BASE}/auth/v1/token?grant_type=password`, { method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password: u.password }) })).json();
  if (!REAL_OTP) jstep(m, 2, 'e-mail verification (form refuses the reserved domain before sending; code verified through login_otp)', refusal.ok && v.json?.ok === true && !!s.access_token, refusal.ms + (Date.now() - t2),
    `reserved-domain refusal on screen: ${refusal.ok}; login_otp HTTP ${v.status} ok=${v.json?.ok}; session ${s.access_token ? 'issued' : 'MISSING'}`);
  if (!s.access_token) return;

  const ctx = kept ? kept.ctx : await browser.newContext(ctxOpts); if (!kept) await ctx.addInitScript(consent);
  if (!kept) await ctx.addInitScript(([s]) => {
    localStorage.setItem('qd-sup-token', s.access_token); localStorage.setItem('qd-sup-refresh', s.refresh_token);
    localStorage.setItem('qd-portal-auth', JSON.stringify({ access_token: s.access_token, refresh_token: s.refresh_token, expires_in: s.expires_in, expires_at: s.expires_at, token_type: 'bearer', user: s.user }));
  }, [s]);
  const p = kept ? kept.p : await ctx.newPage(); lastPage = p; p.setDefaultTimeout(45000); const M = p.locator('main');
  // The workspace's own tab strip (the site header has a navigation landmark too).
  const wsNav = () => p.getByRole('navigation').filter({ has: p.getByRole('button', { name: /^(Inquiries received|الاستفسارات الواردة)$/ }) }).first();
  const errs = []; p.on('pageerror', (e) => errs.push(String(e.message).slice(0, 160)));
  try {
    // STEP 3. Company details and trade, then the emirates: every UAE supplier covers the whole country.
    const t3 = Date.now();
    await p.goto(`${SITE}${pre}/portal`, { waitUntil: 'domcontentloaded' });
    const reg = await M.getByText(/^(Register your company|تسجيل الشركة)$/).first().waitFor({ timeout: 30000 }).then(() => true).catch(() => false);
    await shot(p, m, 'step3_register_company');
    let lead = null, sms = { json: null, text: 'not sent' };
    if (reg) {
      await M.getByRole('textbox', { name: /Company name|اسم الشركة/ }).first().fill(company);
      await M.locator('select').first().selectOption('aluminium');
      await shot(p, m, 'step3_company_and_trade_filled');
      // THE FIXTURE MOBILE, WITHOUT LEAVING THE FORM. A +971 50 000 00xx number is refused before any SMS, so it is
      // recorded verified in the database, as fixtures.makeDemoSupplier does. The registration form reads that state
      // once, when it mounts (kyc state), and a reload sends a supplier whose company exists to the workspace instead
      // of this form (measured 27 Oct, pre-fix run). So the form's first kyc state request is HELD — never answered by
      // the test — until the row says verified, then sent to the real server unchanged.
      let release; const phoneReady = new Promise((r) => { release = r; });
      await p.route('**/functions/v1/kyc**', async (route) => { if (/"action"\s*:\s*"state"/.test(route.request().postData() || '')) await phoneReady; await route.continue(); });
      await M.getByRole('button', { name: /^(Create company|إنشاء الشركة)$/ }).click();
      lead = await waitFor(async () => (await read(`select id, sector, company_name from public.leads where lower(claimed_by)=lower('${email}') order by id desc limit 1`))[0] || null, { timeoutMs: 30000 }).catch(() => null);
      // Scope the new row to this run at once, so teardown reaches it whatever happens next.
      if (lead) {
        run.ids.leads.add(String(lead.id)); await write(`update public.leads set tags = array(select distinct unnest(coalesce(tags,'{}') || ARRAY['qd_demo','qd_run:${run.tag}'])) where id=${lead.id}`, 'tag the run\'s new lead');
        sms = await call('kyc', s.access_token, { action: 'send_sms', phone: fixtureMobile });
        await write(`update public.leads set phone='${fixtureMobile}', owner_phone_verified=true where id=${lead.id}`, 'fixture mobile verified');
        await call('kyc', s.access_token, { action: 'whatsapp_choose', user_kind: 'supplier', email, opt: 'same' });
      }
      release();
      await M.getByText(/Emirates you serve|الإمارات التي تخدمونها/).first().waitFor({ timeout: 30000 }).catch(() => {});
      await p.unroute('**/functions/v1/kyc**');
    }
    const legend = await M.locator('fieldset legend').filter({ hasText: /Emirates you serve|الإمارات/ }).first().innerText().catch(() => '');
    const allBox = M.getByRole('checkbox', { name: /^(All emirates|كل الإمارات)$/ });
    const hasAll = await allBox.isVisible().catch(() => false);
    if (hasAll) await allBox.check();
    const ticked = await M.locator('fieldset').filter({ hasText: /Emirates you serve|الإمارات/ }).locator('input[type=checkbox]:checked').count();
    await shot(p, m, 'step3_emirates_all_uae');
    const optional = /Optional|اختياري/.test(legend) && !/Required|مطلوب/.test(legend);
    jstep(m, 3, 'company details + trade; emirates optional with "All emirates" (no restriction)', reg && !!lead && lead.sector === 'aluminium' && hasAll && ticked === 8 && optional, Date.now() - t3,
      `lead ${lead?.id} sector=${lead?.sector}; legend "${legend.replace(/\s+/g, ' ')}"; "All emirates" ${hasAll ? 'present' : 'MISSING'}; ${ticked}/8 boxes ticked`);
    if (!lead) return;

    // The licence (required), then the fixture mobile: refused before any SMS, then recorded verified.
    const lic = join(TMP, `${run.tag}_${n}_trade_licence.pdf`), prof = join(TMP, `${run.tag}_${n}_company_profile.pdf`), cat = join(TMP, `${run.tag}_${n}_catalogue.pdf`);
    writeFileSync(lic, demoTradeLicence({ company, licenceNo: `ZZDEMO-${run.tag}-${n}`.toUpperCase(), activity: 'Aluminium and Glass Works' }));
    writeFileSync(prof, demoPdf([['COMPANY PROFILE (ZZ DEMO FIXTURE - NOT A REAL COMPANY)', 14], [company, 12], ['Aluminium windows, doors, curtain walls and glass facades across the UAE.', 11]]));
    writeFileSync(cat, demoPdf([['PRODUCT CATALOGUE (ZZ DEMO FIXTURE - NOT A REAL COMPANY)', 14], [company, 12], ['Sliding windows, casement windows, aluminium doors, shopfronts, skylights.', 11]]));
    const tLic = Date.now();
    // Timed by its own request: the PDF is rendered to page images IN THE BROWSER first (fileToImages), then
    // process_docs is sent. reqMs - 0 is the client's part, resMs - reqMs the server's.
    let reqMs = -1, resMs = -1;
    const isLic = (r) => /\/functions\/v1\/supplier_api/.test(r.url()) && /"process_docs"/.test(r.postData() || '') && /"license"/.test(r.postData() || '');
    const onReq = (r) => { if (reqMs < 0 && isLic(r)) reqMs = Date.now() - tLic; };
    const onRes = (r) => { if (resMs < 0 && isLic(r.request())) resMs = Date.now() - tLic; };
    p.on('request', onReq); p.on('response', onRes);
    await M.locator('input[type=file]').nth(0).setInputFiles(lic);
    await M.getByText(/^(Reading licence…|جارٍ قراءة)/).first().waitFor({ timeout: 10000 }).catch(() => {});
    await M.getByText(/^(Reading licence…|جارٍ قراءة)/).first().waitFor({ state: 'detached', timeout: 180000 }).catch(() => {});
    const licRow = await waitFor(async () => { const x = (await read(`select license_doc_path from public.leads where id=${lead.id}`))[0]; return x?.license_doc_path ? x : null; }, { timeoutMs: 60000 }).catch(() => null);
    const licMs = Date.now() - tLic; p.off('request', onReq); p.off('response', onRes);
    const mobileOk = await M.getByText(/Mobile verified|تم التحقق من الجوال/).first().isVisible().catch(() => false);
    await M.getByRole('textbox', { name: /Contact name|جهة الاتصال/ }).first().fill('ZZ DEMO Contact');

    // STEP 4 + 5. Company profile and catalogue picked on the form; Submit uploads both straight to storage
    // (supplier_api upload_url + the signed PUT that #1642 repaired) and must END, not hang on "Submitting…".
    await M.locator('input[type=file]').nth(1).setInputFiles(prof);
    await M.locator('input[type=file]').nth(2).setInputFiles(cat);
    await M.getByRole('checkbox', { name: /I accept the QuotesDone|أوافق/ }).check();
    await shot(p, m, 'step4_profile_and_catalogue_picked');
    const t4 = Date.now();
    await M.getByRole('button', { name: /^(Submit for approval|إرسال للموافقة)/ }).click();
    const done = await wsNav().waitFor({ timeout: 120000 }).then(() => true).catch(() => false);
    const submitMs = Date.now() - t4;
    const alertTxt = done ? '' : await M.getByRole('alert').first().innerText({ timeout: 1000 }).catch(() => '');
    const hung = !done && await M.getByRole('button', { name: /Submitting|جارٍ/ }).isVisible().catch(() => false);
    await shot(p, m, 'step4_after_submit');
    const docs = (await read(`select company_profile_doc_path prof, coalesce(array_length(catalog_doc_paths,1),0) cats, license_doc_path lic,
        (select count(*)::int from storage.objects o where o.bucket_id='supplier-docs' and (o.name = l.company_profile_doc_path)) prof_obj,
        (select count(*)::int from storage.objects o where o.bucket_id='supplier-docs' and o.name = any(coalesce(l.catalog_doc_paths,'{}'))) cat_obj
      from public.leads l where id=${lead.id}`))[0];
    jstep(m, 4, 'company profile upload completes (stored, object in supplier-docs)', done && !!docs?.prof && docs.prof_obj === 1, submitMs + licMs,
      `licence ${licRow ? 'stored' : 'NOT stored'} in ${licMs} ms (request sent at ${reqMs} ms after the file was picked, answered at ${resMs} ms); Submit ended in ${submitMs} ms${hung ? ' — STILL "Submitting…"' : ''}${alertTxt ? ' — alert: ' + alertTxt.slice(0, 160) : ''}; profile ${docs?.prof || 'none'} (object ${docs?.prof_obj})`);
    jstep(m, 5, 'catalogue upload completes (stored, object in supplier-docs)', done && docs?.cats >= 1 && docs.cat_obj >= 1, submitMs,
      `catalog_doc_paths ${docs?.cats}, objects ${docs?.cat_obj}`);
    for (const d of await read(`select license_doc_path p from public.leads where id=${lead.id} union all select company_profile_doc_path from public.leads where id=${lead.id} union all select unnest(catalog_doc_paths) from public.leads where id=${lead.id}`)) if (d.p) run.ids.storage.push('supplier-docs/' + d.p);
    step(m, 'a fixture mobile is refused before any SMS', sms.json?.ok !== true, sms.text.slice(0, 90));
    step(m, 'NOT REAL: the mobile SMS code (no readable phone; the fixture number is recorded verified in the database, then the form shows it)', mobileOk);

    // Ruling 1230: registration completes 100% on ZZ DEMO — approved, signed certificate, every mandatory field stored.
    const t5 = Date.now(); let r;
    for (;;) { r = (await read(`select approval_status, signed_terms_path, licence_gate_reason, owner_phone_verified pv, owner_email_verified ev, accepted_terms_ip is not null ip,
        accepted_terms_sha256 is not null sha, service_emirates, contact_name from public.leads where id=${lead.id}`))[0];
      if (((r.approval_status === 'approved' || (gateLive && r.licence_gate_reason === 'services_unconfirmed')) && r.signed_terms_path) || Date.now() - t5 > 90000) break; await new Promise((x) => setTimeout(x, 3000)); }
    if (r?.signed_terms_path) run.ids.storage.push('signed-terms/' + r.signed_terms_path);
    const allUae = ['Abu Dhabi', 'Dubai', 'Sharjah', 'Ajman', 'Umm Al Quwain', 'Ras Al Khaimah', 'Fujairah'].every((e) => JSON.stringify(r.service_emirates || []).includes(e));
    if (gateLive) {
      step(m, 'ledger 1469: every mandatory field stored and the certificate signed, but NOT approved: held for services_unconfirmed',
        r.approval_status === 'pending' && r.licence_gate_reason === 'services_unconfirmed' && !!r.signed_terms_path && r.pv && r.ev && r.ip && r.sha && allUae, JSON.stringify(r));
      await p.reload({ waitUntil: 'domcontentloaded' }); await wsNav().waitFor({ timeout: 30000 });
      const told = await p.getByText(/you have not yet confirmed what your company does/).first().waitFor({ timeout: 20000 }).then(() => true).catch(() => false);
      await shot(p, m, 'step5b_held_and_told_why');
      step(m, 'ledger 1469: the held supplier is told on screen, in English, what is left and why', told);
    } else {
      step(m, 'ruling 1230 (services gate not applied yet): registration completes 100% — approved, signed certificate, mobile + e-mail verified, acceptance hashed, all 7 emirates',
        r.approval_status === 'approved' && !!r.signed_terms_path && !r.licence_gate_reason && r.pv && r.ev && r.ip && r.sha && allUae, `${JSON.stringify(r)}; approved ${Date.now() - t5} ms after Submit returned`);
      console.log('NOT RUN until the gate is applied: held for services_unconfirmed, told on screen, approved only after the supplier confirms');
    }

    // STEP 6. "Set up my page": the supplier's services, rewritten by the sales engineer and confirmed.
    const t6 = Date.now();
    await p.reload({ waitUntil: 'domcontentloaded' }); const nav = wsNav(); await nav.waitFor({ timeout: 30000 });
    const setupBtn = await p.getByRole('button', { name: /set up my page/i }).or(p.getByRole('link', { name: /set up my page/i })).count();
    await nav.getByRole('button', { name: /^(Services|الخدمات)$/ }).click();
    const ta = M.locator('textarea').first(); await ta.waitFor({ timeout: 30000 });
    await ta.fill('We supply and install aluminium sliding and casement windows, aluminium doors, shopfronts and glass curtain walls for villas and offices.');
    await M.getByRole('button', { name: /^(Rewrite my services|إعادة صياغة خدماتي)$/ }).click();
    await M.getByRole('button', { name: /Our sales engineer is reading it|يقرأ مهندس المبيعات/ }).waitFor({ state: 'detached', timeout: 150000 }).catch(() => {});
    await shot(p, m, 'step6_sales_engineer_rewrite');
    // ledger 1469: the Services tab says why confirming matters and shows what was read from the company profile.
    const verifyNote = await M.getByTestId('verify-needed').isVisible().catch(() => false);
    const profileBox = await M.getByTestId('profile-summary').innerText().catch(() => '');
    step(m, 'ledger 1469: the Services tab tells the supplier that confirming is how it is verified, and shows the profile summary section', verifyNote && /Summary of your company profile/.test(profileBox), `profile section: ${profileBox.replace(/\s+/g, ' ').slice(0, 220)}`);
    const roleBoxes = M.locator('fieldset').filter({ hasText: /role|دور/i }).locator('input[type=checkbox]');
    if ((await roleBoxes.count()) && !(await roleBoxes.locator(':checked').count().catch(() => 0))) await roleBoxes.first().check().catch(() => {});
    const confirm = M.getByRole('button', { name: /^(Confirm my services|Update my services|تأكيد خدماتي|تحديث خدماتي)$/ });
    const canConfirm = await confirm.isEnabled().catch(() => false);
    // The server's own answer to the confirm is kept, so a refusal is named by its code, not only by the screen.
    // A request the BROWSER gives up on (its own abort, or a dropped connection) never produces a response, so it is
    // caught as requestfailed with the browser's reason and the moment, rather than read as "no answer".
    const isSave = (r) => /\/functions\/v1\/supplier_api/.test(r.url()) && /services_save_rewrite/.test(r.postData() || '');
    // net::ERR_FAILED is also how Chromium reports a CORS refusal (a response it was given but may not read). The
    // network layer's own view is kept: the status it received, the response headers, and the CORS or block reason.
    const cdp = (process.env.QD_WALK_CDP !== '0') ? await ctx.newCDPSession(p).catch(() => null) : null;
    // Every supplier_api request after the click is followed (postData is not always on the CDP event); the save is the
    // one in flight longest, so the report names each request's outcome and time.
    const net = { reqs: new Map(), t0: 0 };
    if (cdp) {
      await cdp.send('Network.enable').catch(() => {});
      cdp.on('Network.requestWillBeSent', (e) => { if (net.t0 && /\/functions\/v1\/supplier_api/.test(e.request.url) && e.request.method === 'POST') net.reqs.set(e.requestId, { sent_ms: Date.now() - net.t0 }); });
      cdp.on('Network.responseReceived', (e) => { const r = net.reqs.get(e.requestId); if (r) Object.assign(r, { status: e.response.status, at_ms: Date.now() - net.t0, acao: e.response.headers['access-control-allow-origin'] ?? null, proto: e.response.protocol }); });
      cdp.on('Network.loadingFailed', (e) => { const r = net.reqs.get(e.requestId); if (r) Object.assign(r, { failed: e.errorText, canceled: e.canceled, blocked: e.blockedReason, cors: e.corsErrorStatus?.corsError, at_ms: Date.now() - net.t0 }); });
      cdp.on('Network.loadingFinished', (e) => { const r = net.reqs.get(e.requestId); if (r && !r.at_ms) r.at_ms = Date.now() - net.t0; });
    }
    const tSave = Date.now(); net.t0 = tSave;
    const saveAns = canConfirm ? Promise.race([
      p.waitForResponse((r) => isSave(r.request()), { timeout: 150000 }).then(async (r) => `HTTP ${r.status()} after ${Date.now() - tSave} ms ${(await r.text().catch(() => '')).slice(0, 240)}`),
      p.waitForEvent('requestfailed', { predicate: isSave, timeout: 150000 }).then((r) => `request FAILED in the browser after ${Date.now() - tSave} ms: ${r.failure()?.errorText}`),
    ]).catch((e) => 'no answer: ' + String(e.message).slice(0, 80)) : Promise.resolve('not pressed');
    if (canConfirm) await confirm.click();
    const savedAns = await saveAns + (cdp ? ` | network: ${JSON.stringify([...net.reqs.values()])}` : '');
    const savedNote = await M.getByText(/^Saved\. Your services are confirmed|^تم الحفظ/).first().waitFor({ timeout: 30000 }).then(() => true).catch(() => false);
    await shot(p, m, 'step6_services_confirmed');
    const capn = (await read(`select count(*)::int n from public.supplier_capability_confirmation where supplier_id=${lead.id}`))[0].n;
    jstep(m, 6, 'page set up: services rewritten by the sales engineer and confirmed', canConfirm && savedNote && capn > 0, Date.now() - t6,
      `"Set up my page" control on screen: ${setupBtn ? 'yes' : 'NO — no such control exists in the portal; the Services tab confirm is the step that publishes what the supplier offers'}; confirm enabled ${canConfirm}; saved note ${savedNote}; server ${savedAns}; capability confirmations ${capn}`);

    if (gateLive) {
      let a2; const t6b = Date.now();
      for (;;) { a2 = (await read(`select approval_status, verified, licence_gate_reason from public.leads where id=${lead.id}`))[0]; if (a2?.approval_status === 'approved' || Date.now() - t6b > 60000) break; await new Promise((x) => setTimeout(x, 2000)); }
      step(m, 'ledger 1469: after the supplier confirms its services it is approved and verified', a2?.approval_status === 'approved' && a2.verified === true && !a2.licence_gate_reason, `${JSON.stringify(a2)} in ${Date.now() - t6b} ms`);
    }

    // STEP 7. The dashboard loads, and the supplier can see the inquiries area.
    const t7 = Date.now();
    await nav.getByRole('button', { name: /^(Inquiries received|الاستفسارات الواردة)$/ }).click();
    const settle = async () => { const t0 = Date.now(); while (Date.now() - t0 < 25000) { if (!(await M.evaluate((el) => /Loading|Measuring|جارٍ/.test(el.innerText) || !!el.querySelector('[aria-busy="true"]')))) return Date.now() - t0; await p.waitForTimeout(250); } return -1; };
    const ms = await settle();
    const body = (await M.innerText().catch(() => '')).replace(/\s+/g, ' ');
    await shot(p, m, 'step7_inquiries_received');
    const tabs = await nav.getByRole('button').allInnerTexts();
    jstep(m, 7, 'dashboard loads; "Inquiries received" opens and settles', ms >= 0 && tabs.length >= 5 && !/something went wrong|تعذّر/i.test(body), Date.now() - t7,
      `tabs ${JSON.stringify(tabs)}; settled ${ms} ms; panel text "${body.slice(0, 140)}"; page errors ${errs.length ? errs.join(' | ') : 'none'}`);
    for (const name of tabs) { await nav.getByRole('button', { name, exact: true }).click(); const t = await settle(); step(m, `tab "${name}" settles`, t >= 0, `${t} ms`); await shot(p, m, 'tab_' + name.replace(/[^a-z0-9]+/gi, '_').slice(0, 20)); }
  } finally { await ctx.close(); }
}

const run = await openRun(CAP ? { capUsd: Number(CAP) } : {});
gateLive = !!(await read(`select position('services_unconfirmed' in pg_get_functiondef('public.fn_sales_engineer_verifies_supplier(bigint,text)'::regprocedure)) > 0 as live`))[0]?.live;
console.log(gateLive ? 'services gate: LIVE (approval needs a confirmed services record)' : 'services gate: NOT APPLIED YET (the new-order steps are reported NOT RUN)');
// Ruling 1260 (19 Oct 2026): every run has the AI on. openRun opens the capped model window for every leg, so the
// case-only override (USD 1, 1 hour) is gone: it only ever LOWERED the run's ceiling below openRun's.
const browser = await launch();
// The page on screen when a step throws is captured before teardown (28 Oct 2026: the 390 px leg timed out on the
// licence Upload button and left no picture of why).
let lastPage = null;
let teardownOut = null;
try {
  for (const { lang, vp, c } of MATRIX) {
    const m = `${lang}/${vp}${c ? '/' + c.id : ''}`, n = run.seq++;
    const approveCase = !c || ['approve', 'name_autofilled'].includes(c.expected);
    const email = REAL_OTP ? sinkAddress(run.tag, n) : `qd-${run.tag}-sup${n}@example.invalid`, company = `ZZ DEMO Walk ${run.tag} ${lang} ${vp} ${n}`;
    if (isSink(email)) sinks.push(email);
    if (FRESH) { await freshLeg({ run, browser, m, n, lang, vp, email, company }); continue; }
    const lead = (await write(`insert into public.leads (company_name, email, emirate, source, invite_status, invited_at, locale, tags)
      values ('${company}', '${isSink(email) ? `qd-${run.tag}-lead${n}@example.invalid` : email}', 'Dubai', 'directory', 'sent', now(), '${lang}', ARRAY['qd_demo','qd_run:${run.tag}'])
      returning id, claim_token::text t`, 'invited demo lead'))[0];
    run.ids.leads.add(String(lead.id));
    const mobile = vp === 'mobile';
    const ctxOpts = { viewport: mobile ? { width: Number(val('--mobile-width', '390')), height: 844 } : { width: DESKTOP_W, height: 900 }, locale: lang === 'ar' ? 'ar-AE' : 'en-GB', ...(mobile ? { isMobile: true, hasTouch: true, deviceScaleFactor: 2 } : {}) };
    const consent = () => localStorage.setItem('qd-cookie-consent', JSON.stringify({ necessary: true, analytics: false, marketing: false, ts: Date.now() }));
    const url = `${SITE}/${lang}/portal?t=${lead.t}`;

    // 1. the link from the email, signed out
    { const ctx = await browser.newContext(ctxOpts); await ctx.addInitScript(consent); const p = await ctx.newPage(); const t0 = Date.now();
      await p.goto(url, { waitUntil: 'domcontentloaded' });
      const seen = await p.getByText(company).first().waitFor({ timeout: 20000 }).then(() => true).catch(() => false);
      step(m, 'the invitation names the company on landing', seen, `${Date.now() - t0} ms`); await shot(p, m, 'landing_from_invitation');
      const h1 = await p.locator('#qd-supplier-signin h1').innerText().catch(() => '');
      step(m, 'the form opens on create-account, not "Welcome back"', (AR(lang) ? /سجّل|التسجيل|إنشاء حساب/.test(h1) && !/بعودت/.test(h1) : /Register/.test(h1) && !/Welcome back/i.test(h1)), h1);
      await shot(p, m, 'signup_form');
      await ctx.close(); }

    // 2. sign-up, then the portal with the claim token. --real-otp: the form itself sends the code to the run's
    // Resend sink, the delivered message is read and the code typed (resend_sink.mjs). Otherwise (see header) the
    // OTP is seeded and verified through login_otp.
    let s;
    if (isSink(email)) s = await realOtpSignup({ browser, ctxOpts, consent, url, email, company, m });
    else {
      const u = await mkAuthUser(run, email);
      const v = await verifyEmailByOtp(email, 'supplier');
      step(m, 'the sign-up e-mail code verifies through login_otp', v.json?.ok === true, `HTTP ${v.status}`);
      const { ANON } = await keys();
      s = await (await fetch(`${BASE}/auth/v1/token?grant_type=password`, { method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password: u.password }) })).json();
    }
    if (!s?.access_token) { step(m, 'a session exists after sign-up', false, 'no session: the leg stops here'); continue; }
    const ctx = await browser.newContext(ctxOpts); await ctx.addInitScript(consent);
    await ctx.addInitScript(([s, lang, t]) => {
      localStorage.setItem('qd-sup-token', s.access_token); localStorage.setItem('qd-sup-refresh', s.refresh_token);
      localStorage.setItem('qd-portal-auth', JSON.stringify({ access_token: s.access_token, refresh_token: s.refresh_token, expires_in: s.expires_in, expires_at: s.expires_at, token_type: 'bearer', user: s.user }));
      localStorage.setItem('qd-lang', lang); try { sessionStorage.setItem('qd-claim-token', t); } catch { /* */ }
    }, [s, lang, lead.t]);
    const p = await ctx.newPage(); lastPage = p; p.setDefaultTimeout(45000); const M = p.locator('main');
    // --slow (13 Oct 2026, ruling 1230): a poor mobile connection on every portal request (CDP throttling: 400 ms, ~400 kbit/s).
    if (argv.includes('--slow')) { const cdp = await ctx.newCDPSession(p); await cdp.send('Network.enable'); await cdp.send('Network.emulateNetworkConditions', { offline: false, latency: 400, downloadThroughput: 50000, uploadThroughput: 50000 }); }
    const blank = { hit: false };
    p.on('framenavigated', () => {});
    const t1 = Date.now();
    await p.goto(url, { waitUntil: 'domcontentloaded' });
    // Poll the whole claim window: the blank company form must NEVER appear.
    const heading = p.getByRole('heading', { name: c?.truth?.legal_name_en ? new RegExp(`^(${esc(company)}|${esc(c.truth.legal_name_en)})$`) : company });
    for (let i = 0; i < 60 && !(await heading.isVisible().catch(() => false)); i++) {
      if (await M.getByText(AR(lang) ? 'تسجيل الشركة' : 'Register your company', { exact: true }).isVisible().catch(() => false)) blank.hit = true;
      await p.waitForTimeout(500);
    }
    step(m, 'the claimed company opens — never a blank "Register your company"', !blank.hit && await heading.isVisible(), `${Date.now() - t1} ms`);
    await shot(p, m, 'portal_after_claim');
    const claimed = (await read(`select claimed, lower(claimed_by)=lower('${email}') mine, owner_email_verified ev from public.leads where id=${lead.id}`))[0];
    step(m, 'the listing is claimed by this account with the e-mail proof carried', claimed?.claimed && claimed?.mine && claimed?.ev, JSON.stringify(claimed));

    // A portal that never opened on the company cannot be walked further; the step above already failed.
    if (!(await heading.isVisible().catch(() => false))) { await ctx.close(); continue; }
    // THE WORKSPACE'S OWN TAB STRIP (28 Oct 2026). `navigation.first()` is the SITE header on a 390 px phone, whose
    // nth(4) button does not exist, and a click with no timeout waited for ever: the en/mobile leg hung 3+ minutes
    // and was killed before teardown. The strip is the navigation that holds "Inquiries received".
    const nav = p.getByRole('navigation').filter({ has: p.getByRole('button', { name: /^(Inquiries received|الاستفسارات الواردة)$/ }) }).first();
    const settle = async () => { const t0 = Date.now(); while (Date.now() - t0 < 25000) { if (!(await M.evaluate((el) => /Loading|Measuring|جارٍ/.test(el.innerText) || !!el.querySelector('[aria-busy="true"]')))) return Date.now() - t0; await p.waitForTimeout(250); } return -1; };

    // 3. documents: licence + company profile
    await nav.getByRole('button').nth(4).click(); await M.getByRole('progressbar').first().waitFor({ timeout: 30000 });
    const lic = join(TMP, `${run.tag}_${n}_trade_licence.pdf`), prof = join(TMP, `${run.tag}_${n}_company_profile.pdf`);
    if (c) { writeFileSync(prof, readFileSync(join(CORPUS, 'profile_pdf.pdf'))); }
    else {
    writeFileSync(lic, demoTradeLicence({ company, licenceNo: `ZZDEMO-${run.tag}-${n}`.toUpperCase(), activity: 'Aluminium and Glass Works' }));
    writeFileSync(prof, demoPdf([['COMPANY PROFILE (ZZ DEMO FIXTURE - NOT A REAL COMPANY)', 14], [company, 12]])); }
    const licUp = c ? join(TMP, `${run.tag}_${n}_${c.file}`) : lic; if (c) writeFileSync(licUp, readFileSync(join(CORPUS, c.file)));
    const upBtn = () => M.locator('button:enabled').filter({ hasText: AR(lang) ? /^(رفع|تحميل)$/ : /^Upload$/ }).first();
    // EACH FILE GOES TO ITS OWN CARD (28 Oct 2026). input[type=file] nth(0)/nth(1) is a different input at 390 px: the
    // licence landed in "Supporting company documents" and no Upload button ever enabled. The card is found by its
    // heading, the way a supplier finds it.
    const card = (name) => M.locator('.qd-panel').filter({ has: p.locator('b', { hasText: new RegExp('^' + name + '$') }) }).last();
    const cardUpload = async (name, file) => { const c = card(name); await c.locator('input[type=file]').first().setInputFiles(file); await c.getByRole('button', { name: /^Upload$/ }).click(); };
    await cardUpload('Trade licence', licUp); await settle();
    await M.getByText(/2028/).first().waitFor({ timeout: 30000 }).catch(() => {});
    await M.locator('button:enabled').filter({ hasText: AR(lang) ? /^(رفع|تحميل)$/ : /^Upload$/ }).first().waitFor({ state: 'detached', timeout: 5000 }).catch(() => {});
    await p.waitForTimeout(1500);
    await cardUpload('Company profile', prof); await settle(); await p.waitForTimeout(2500);
    if (c) {
      // ruling 1177: a catalogue is read too. The third file input on the Documents tab is the catalogue door.
      const cat = join(TMP, `${run.tag}_${n}_catalogue.pdf`); writeFileSync(cat, readFileSync(join(CORPUS, 'catalogue_pdf.pdf')));
      const inputs = await M.locator('input[type=file]').count();
      if (inputs > 2) { await M.locator('input[type=file]').nth(2).setInputFiles(cat); await upBtn().click().catch(() => {}); await settle(); await p.waitForTimeout(2500); }
      let d; const t0 = Date.now();
      for (;;) { d = (await read(`select license_doc_path is not null lic, company_profile_doc_path is not null prof, coalesce(array_length(catalog_doc_paths,1),0) cats,
          trade_license_no, license_expiry::text exp, licence_legal_name from public.leads where id=${lead.id}`))[0];
        if ((d.licence_legal_name && d.exp) || Date.now() - t0 > 90000 || !approveCase) break; await new Promise((r) => setTimeout(r, 3000)); }
      step(m, `licence (${c.format}) + profile + catalogue stored`, d.lic && d.prof && d.cats > 0, JSON.stringify(d) + ` file inputs ${inputs}`);
      if (approveCase) step(m, 'the licence was read: number, legal name, expiry as printed', d.trade_license_no === c.truth.licence_no && d.licence_legal_name === c.truth.legal_name_en && d.exp === c.truth.expiry_date,
        `read ${JSON.stringify({ no: d.trade_license_no, name: d.licence_legal_name, exp: d.exp })} truth ${JSON.stringify({ no: c.truth.licence_no, name: c.truth.legal_name_en, exp: c.truth.expiry_date })} in ${Date.now() - t0} ms`);
    } else {
    // Polled, not read once: the profile write lands after the upload button settles (measured 28 Oct 2026: read
    // prof=false at once, the path present a minute later, the card already "On file").
    let docs; for (let i = 0; i < 15; i++) { docs = (await read(`select license_doc_path is not null lic, license_expiry, company_profile_doc_path is not null prof from public.leads where id=${lead.id}`))[0]; if (docs?.lic && docs?.prof) break; await new Promise((r) => setTimeout(r, 2000)); }
    step(m, 'licence + company profile uploaded; licence expiry read', docs?.lic && docs?.prof && String(docs?.license_expiry || '').startsWith('2028'), JSON.stringify(docs));
    // D1 (E2E stage 1, 30 Sep 2026): the Documents tab reads the NAME the licence prints, by code, and that name
    // matches the company, so verification can pass on the name-match path (not licence_name_unread / a mismatch).
    const nm = (await read(`select licence_legal_name, company_name,
        public.fn_company_name_norm(licence_legal_name) = public.fn_company_name_norm(company_name) as matches,
        public.fn_supplier_licence_name_mismatch(l) as mismatch
      from public.leads l where id=${lead.id}`))[0];
    step(m, 'the Documents tab read the licence name and it matches the company', !!nm?.licence_legal_name && nm?.matches === true && nm?.mismatch === false, JSON.stringify(nm));
    }
    await shot(p, m, 'documents_uploaded');
    // EVERY BUTTON IS ON THE SCREEN (28 Oct 2026: at 390 px the Insurance, ISO and dealer-letter Upload buttons sat past
    // the right edge, clipped, so a phone could not reach them; documentElement.scrollWidth still read 390 because the
    // overflow is clipped, so the check is on the buttons themselves).
    // An element inside a strip that scrolls sideways on purpose (the tab strip, SupplierPortal "scrolls sideways rather
    // than wrapping") is reachable by swiping, so it is reported apart and does not fail the step.
    { const off = await p.evaluate(() => [...document.querySelectorAll('main button, main label, main input, main a')].filter((b) => {
          const r = b.getBoundingClientRect(); const cs = getComputedStyle(b);
          // A closed <details> (the account menu) keeps a box for content it does not render: measured 28 Oct, its three
          // items read right=462 at 390 px with no text. Not on screen, so not a defect; the open menu is walked below.
          const closed = b.closest('details:not([open])'); if (closed && !b.closest('summary')) return false;
          return r.width > 0 && r.height > 0 && cs.visibility !== 'hidden' && r.right > window.innerWidth + 1; }).map((b) => {
          let a = b.parentElement, scroller = false; while (a && a !== document.body) { const o = getComputedStyle(a).overflowX; if (o === 'auto' || o === 'scroll') { scroller = true; break; } a = a.parentElement; }
          const name = (b.innerText || b.getAttribute('aria-label') || b.getAttribute('placeholder') || b.getAttribute('type') || '').trim().slice(0, 24);
          let clip = b.parentElement; while (clip && clip !== document.body && getComputedStyle(clip).overflowX !== 'hidden' && getComputedStyle(clip).overflowX !== 'clip') clip = clip.parentElement;
          const where = clip && clip !== document.body ? ' clipped by ' + clip.tagName.toLowerCase() + '.' + String(clip.className || '').split(' ').slice(0, 3).join('.') : '';
          return { what: `${b.tagName.toLowerCase()}${name ? ' "' + name + '"' : ''} right=${Math.round(b.getBoundingClientRect().right)} ${b.outerHTML.slice(0, 140).replace(/\s+/g, ' ')}${where}`, scroller }; }));
      const bad = off.filter((o) => !o.scroller), swipe = off.filter((o) => o.scroller);
      step(m, 'every button on the Documents tab is inside the screen', bad.length === 0,
        (bad.length ? `past the right edge: ${bad.map((o) => o.what).join('; ')}` : '') + (swipe.length ? ` (in a sideways strip: ${swipe.map((o) => o.what).join('; ')})` : '')); }
    for (const d of await read(`select license_doc_path p from public.leads where id=${lead.id} union all select company_profile_doc_path from public.leads where id=${lead.id} union all select unnest(catalog_doc_paths) from public.leads where id=${lead.id}`)) if (d.p) run.ids.storage.push('supplier-docs/' + d.p);

    // 4. mobile: the fixture refusal, then recorded verified
    const sms = await call('kyc', s.access_token, { action: 'send_sms', phone: `+9715000000${String(10 + n).padStart(2, '0')}` });
    step(m, 'a fixture mobile is refused before any SMS', sms.json?.ok !== true, sms.text.slice(0, 90));
    await write(`update public.leads set phone='+9715000000${String(10 + n).padStart(2, '0')}', owner_phone_verified=true where id=${lead.id}`, 'fixture mobile verified');

    // 5. profile: the WhatsApp question is on screen, terms + Save
    await p.reload({ waitUntil: 'domcontentloaded' }); await heading.waitFor({ timeout: 30000 });
    const acct = M.locator('details').last(); await acct.locator('summary').click(); await acct.getByRole('button').first().click(); await settle();
    const waQ = await M.getByText(/WhatsApp|واتساب/).first().waitFor({ timeout: 15000 }).then(() => true).catch(() => false);
    if (!waQ) await p.screenshot({ path: join(TMP, `wa_${n}.png`), fullPage: true });
    step(m, 'the WhatsApp question is on the Profile tab while registration needs it', waQ, waQ ? '' : 'screen: ' + join(TMP, `wa_${n}.png`));
    await shot(p, m, 'profile_whatsapp_question');
    const wa = await call('kyc', s.access_token, { action: 'whatsapp_choose', user_kind: 'supplier', email, opt: 'same' });
    step(m, 'the WhatsApp answer is recorded', wa.json?.ok === true, `HTTP ${wa.status}`);
    await p.reload({ waitUntil: 'domcontentloaded' }); await heading.waitFor({ timeout: 30000 });
    await acct.locator('summary').click(); await acct.getByRole('button').first().click(); await settle();
    await M.getByRole('textbox', { name: AR(lang) ? /جهة الاتصال/ : /Contact name/ }).first().fill('ZZ DEMO Contact');
    await M.getByRole('textbox', { name: AR(lang) ? /المفو/ : /Authorized signatory/ }).first().fill('ZZ DEMO Signatory');
    await M.getByRole('checkbox', { name: AR(lang) ? 'دبي' : 'Dubai', exact: true }).check();
    await M.getByRole('checkbox', { name: AR(lang) ? /أوافق/ : /I accept the QuotesDone/ }).check();
    const t2 = Date.now();
    await M.getByRole('button', { name: AR(lang) ? /^حفظ/ : /^Save changes$/ }).click();
    await M.getByRole('button', { name: /Saving|جارٍ الحفظ/ }).waitFor({ state: 'detached', timeout: 90000 }).catch(() => {});
    // Since #1151 (30 Sep 2026) Save answers before the certificate renders, and approval lands when the PDF does.
    // Poll up to 60 s, and report both times.
    const t3 = Date.now(); let reg;
    for (;;) {
      reg = (await read(`select approval_status, signed_terms_path, signatory_name, approval_decided_by, licence_gate_reason from public.leads where id=${lead.id}`))[0];
      if (((reg?.approval_status === 'approved' || (gateLive && reg?.licence_gate_reason === 'services_unconfirmed')) && reg?.signed_terms_path) || (!approveCase && reg?.licence_gate_reason && reg.licence_gate_reason !== 'reg_terms') || Date.now() - t3 > 60000) break;
      await new Promise((r) => setTimeout(r, 2000));
    }
    if (approveCase && gateLive) {
      // Ledger 1469: terms + Save complete the six, not the verification. The supplier's own confirm of its services (the portal's
      // supplier_api capability_confirm, the same writer the Services tab uses) is what releases the approval.
      step(m, 'ledger 1469: terms + Save → signed certificate, all six present, held for services_unconfirmed (not approved)', reg?.approval_status === 'pending' && reg?.licence_gate_reason === 'services_unconfirmed' && !!reg?.signed_terms_path, JSON.stringify(reg));
      const pick = (await read(`select s.trade_code, s.trade_code || '.' || s.code as k, (select code from public.taxonomy_role where active order by sort limit 1) as role from public.taxonomy_trade_service s where s.active order by s.trade_code, s.sort limit 1`))[0];
      const cc = await call('supplier_api', s.access_token, { action: 'capability_confirm', trades: [pick.trade_code], roles: [pick.role], services: [pick.k] });
      step(m, 'ledger 1469: the supplier confirms its services', cc.json?.ok === true, `HTTP ${cc.status} ${cc.text.slice(0, 120)}`);
      const t3b = Date.now(); let reg2;
      for (;;) { reg2 = (await read(`select approval_status, verified, signed_terms_path, licence_gate_reason from public.leads where id=${lead.id}`))[0]; if (reg2?.approval_status === 'approved' || Date.now() - t3b > 60000) break; await new Promise((r) => setTimeout(r, 2000)); }
      step(m, 'ledger 1469: after the confirm it is approved and verified with the signed certificate and no hold', reg2?.approval_status === 'approved' && reg2.verified === true && !!reg2.signed_terms_path && !reg2.licence_gate_reason, JSON.stringify(reg2));
      reg = reg2;
    } else if (approveCase) step(m, 'terms + Save → approved with a signed certificate, by the deterministic check with no licence hold (services gate not applied yet)', reg?.approval_status === 'approved' && !!reg?.signed_terms_path && !reg?.licence_gate_reason,
      `${JSON.stringify(reg)}; Save answered in ${t3 - t2} ms, approved ${Date.now() - t3} ms after`);
    // The reason must be the LICENCE's, not "terms still missing" (reg_terms is only the certificate not landed yet).
    else step(m, `terms + Save → NOT approved, held for the licence (corpus expects ${c.expected})`, reg?.approval_status !== 'approved' && !!reg?.licence_gate_reason && reg.licence_gate_reason !== 'reg_terms', JSON.stringify(reg));
    // ruling 1230: the acceptance is stored with IP, the authorised person and the signature; every typed field saved.
    const tr = (await read(`select accepted_terms_ip is not null ip, accepted_terms_user_agent is not null ua, accepted_terms_version v, accepted_terms_sha256 is not null sha, signatory_name, contact_name, service_emirates, owner_phone_verified pv, owner_email_verified ev, company_name from public.leads where id=${lead.id}`))[0];
    step(m, 'acceptance stored with IP, agent, version, hash, signatory; mobile + e-mail verified; fields as typed', tr.ip && tr.ua && !!tr.v && tr.sha && tr.signatory_name === 'ZZ DEMO Signatory' && tr.contact_name === 'ZZ DEMO Contact' && JSON.stringify(tr.service_emirates || '').includes('Dubai') && tr.pv && tr.ev, JSON.stringify(tr));
    if (c?.truth?.legal_name_en && approveCase) {
      const aa = (await read(`select count(*)::int n from public.agent_actions where kind='supplier_name_from_licence' and target_id::text='${lead.id}'`))[0];
      step(m, 'ruling 1176: the read licence name became the company name, the old name logged', tr.company_name === c.truth.legal_name_en && aa.n > 0, `company_name=${tr.company_name}; log rows ${aa.n}`);
    }
    // THE DECISION REACHES THE SUPPLIER. A demo delivery request writes its notification as status 'suppressed' with its
    // dedupe_key (#1497, on top of ruling 1199), so the walk requires the row itself: exactly one suppressed e-mail
    // supplier_approved notice for an approval, and suppressed notice rows plus the reason on the supplier's own screen
    // (#1406) for a hold. Every row must be suppressed, never sent. The sales engineer's decision record
    // (agent_actions supplier_approved_notice) is asserted as well, in addition, never instead.
    await new Promise((r) => setTimeout(r, 4000));
    const nt = await read(`select type, channel, status from public.notifications where lead_id=${lead.id} order by id`);
    const allSuppressed = nt.every((x) => x.status === 'suppressed');
    if (approveCase) {
      const approvedMail = nt.filter((x) => x.type === 'supplier_approved' && x.channel === 'email');
      // --real-otp: the account is the run's Resend sink, not an @example.invalid address, so the seat clock refuses the
      // approval mail outright ("a fixture subject may not write to a real address", fn_seat_clock_refusal) and records
      // the skip. That refusal is the guard working: a ZZ DEMO lead never mails an address outside the reserved domains.
      if (isSink(email)) {
        const sk = (await read(`select count(*)::int n from public.agent_actions where kind='supplier_approved_notice' and target_id='${lead.id}' and status='skipped' and detail->>'not_sent' ilike '%fixture subject%'`))[0];
        step(m, 'the approval mail to the sink is refused by the fixture guard and the skip is on record', approvedMail.length === 0 && allSuppressed && sk.n === 1, JSON.stringify(nt));
      } else
      step(m, 'exactly one approval notice is written, suppressed (fixture: never sent)', approvedMail.length === 1 && allSuppressed, JSON.stringify(nt));
      const decided = (await read(`select count(*)::int n from public.agent_actions where kind='supplier_approved_notice' and status in ('auto_done','skipped') and target_table='leads' and target_id='${lead.id}'`))[0].n;
      step(m, 'the approval notice decision is on record', decided > 0, `agent_actions rows ${decided}`);
    } else {
      step(m, 'the hold notice is written, suppressed (fixture: never sent)', nt.length > 0 && allSuppressed, JSON.stringify(nt));
      await p.reload({ waitUntil: 'domcontentloaded' }); await heading.waitFor({ timeout: 30000 }).catch(() => {});
      const said = await p.getByText(/^Why: /).first().innerText({ timeout: 15000 }).catch(() => '');
      step(m, 'the hold reason is on the supplier screen', !!said, said);
    }
    await shot(p, m, 'after_submit');
    if (reg?.signed_terms_path) run.ids.storage.push('signed-terms/' + reg.signed_terms_path);

    // 6. every tab, the bell and the account menu settle
    await p.reload({ waitUntil: 'domcontentloaded' }); await heading.waitFor({ timeout: 30000 });
    for (const name of await nav.getByRole('button').allInnerTexts()) {
      await nav.getByRole('button', { name, exact: true }).click(); const ms = await settle();
      step(m, `tab "${name}" settles`, ms >= 0, `${ms} ms${ms > 3000 ? ' (>3 s)' : ''}`);
      await shot(p, m, 'tab_' + name.replace(/[^a-z0-9]+/gi, '_').slice(0, 20));
    }
    for (let k = 0; k < 3; k++) {
      await acct.locator('summary').click(); const b = acct.getByRole('button').nth(k); const name = await b.innerText();
      await b.click(); const ms = await settle(); step(m, `account "${name}" settles`, ms >= 0, `${ms} ms${ms > 3000 ? ' (>3 s)' : ''}`);
    }
    await ctx.close();
  }
} catch (e) {
  console.error('LEG ERROR', String(e?.message || e).split('\n')[0]);
  if (lastPage && SHOTS) await lastPage.screenshot({ path: join(SHOTS, `error_${Date.now()}.png`), fullPage: true }).catch(() => {});
  process.exitCode = 1;
} finally {
  await browser.close();
  const c = await closeRun(run, { keep: KEEP }); teardownOut = c;
  if (!KEEP) for (const a of sinks) { const l = await cleanSink(a).catch((e) => ({ error: String(e.message) })); console.log('sink teardown', a, JSON.stringify(l)); if (teardownOut) (teardownOut.sinks ||= []).push({ a, l }); }
  console.log('teardown:', JSON.stringify(c.leftovers || 'kept'));
}
const failed = results.filter((r) => !r.ok);
if (SUMMARY) writeFileSync(SUMMARY, JSON.stringify({ tag: run.tag, site: SITE, journey, results, teardown: teardownOut }, null, 2));
console.log(`${results.length - failed.length}/${results.length} passed`);
process.exit(failed.length ? 1 : 0);
