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
import { launch, SITE } from './browser.mjs';
import { openRun, closeRun, read, write, call, BASE } from './fixtures.mjs';
import { keys, verifyEmailByOtp, mkAuthUser } from '../lib/demo_factory.mjs';
import { demoPdf, demoTradeLicence } from '../lib/demo_pdf.mjs';
import { writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const argv = process.argv.slice(2);
const val = (f, d) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : d; };
const LANGS = val('--lang', 'en,ar').split(','); const VPS = val('--vp', 'desktop,mobile').split(',');
const KEEP = argv.includes('--keep');
const TMP = mkdtempSync(join(tmpdir(), 'qd-regwalk-'));
const AR = (l) => l === 'ar';
const results = [];
const step = (m, name, ok, detail = '') => { results.push({ m, name, ok, detail }); console.log(`${ok ? 'PASS' : 'FAIL'} [${m}] ${name}${detail ? ' — ' + detail : ''}`); };

const run = await openRun();
const browser = await launch();
try {
  for (const lang of LANGS) for (const vp of VPS) {
    const m = `${lang}/${vp}`, n = run.seq++;
    const email = `qd-${run.tag}-sup${n}@example.invalid`, company = `ZZ DEMO Walk ${run.tag} ${lang} ${vp}`;
    const lead = (await write(`insert into public.leads (company_name, email, emirate, source, invite_status, invited_at, locale, tags)
      values ('${company}', '${email}', 'Dubai', 'directory', 'sent', now(), '${lang}', ARRAY['qd_demo','qd_run:${run.tag}'])
      returning id, claim_token::text t`, 'invited demo lead'))[0];
    run.ids.leads.add(String(lead.id));
    const mobile = vp === 'mobile';
    const ctxOpts = { viewport: mobile ? { width: 390, height: 844 } : { width: 1440, height: 900 }, locale: AR(lang) ? 'ar-AE' : 'en-GB', ...(mobile ? { isMobile: true, hasTouch: true, deviceScaleFactor: 2 } : {}) };
    const consent = () => localStorage.setItem('qd-cookie-consent', JSON.stringify({ necessary: true, analytics: false, marketing: false, ts: Date.now() }));
    const url = `${SITE}/${lang}/portal?t=${lead.t}`;

    // 1. the link from the email, signed out
    { const ctx = await browser.newContext(ctxOpts); await ctx.addInitScript(consent); const p = await ctx.newPage(); const t0 = Date.now();
      await p.goto(url, { waitUntil: 'domcontentloaded' });
      const seen = await p.getByText(company).first().waitFor({ timeout: 20000 }).then(() => true).catch(() => false);
      step(m, 'the invitation names the company on landing', seen, `${Date.now() - t0} ms`);
      const h1 = await p.locator('#qd-supplier-signin h1').innerText().catch(() => '');
      step(m, 'the form opens on create-account, not "Welcome back"', (AR(lang) ? /سجّل|التسجيل|إنشاء حساب/.test(h1) && !/بعودت/.test(h1) : /Register/.test(h1) && !/Welcome back/i.test(h1)), h1);
      await ctx.close(); }

    // 2. sign-up (see header: OTP seeded, verified through login_otp), then the portal with the claim token
    const u = await mkAuthUser(run, email);
    const v = await verifyEmailByOtp(email, 'supplier');
    step(m, 'the sign-up e-mail code verifies through login_otp', v.json?.ok === true, `HTTP ${v.status}`);
    const { ANON } = await keys();
    const session = async () => (await fetch(`${BASE}/auth/v1/token?grant_type=password`, { method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password: u.password }) })).json();
    const s = await session();
    const ctx = await browser.newContext(ctxOpts); await ctx.addInitScript(consent);
    await ctx.addInitScript(([s, lang, t]) => {
      localStorage.setItem('qd-sup-token', s.access_token); localStorage.setItem('qd-sup-refresh', s.refresh_token);
      localStorage.setItem('qd-portal-auth', JSON.stringify({ access_token: s.access_token, refresh_token: s.refresh_token, expires_in: s.expires_in, expires_at: s.expires_at, token_type: 'bearer', user: s.user }));
      localStorage.setItem('qd-lang', lang); try { sessionStorage.setItem('qd-claim-token', t); } catch { /* */ }
    }, [s, lang, lead.t]);
    const p = await ctx.newPage(); const M = p.locator('main');
    const blank = { hit: false };
    p.on('framenavigated', () => {});
    const t1 = Date.now();
    await p.goto(url, { waitUntil: 'domcontentloaded' });
    // Poll the whole claim window: the blank company form must NEVER appear.
    const heading = p.getByRole('heading', { name: company });
    for (let i = 0; i < 60 && !(await heading.isVisible().catch(() => false)); i++) {
      if (await M.getByText(AR(lang) ? 'تسجيل الشركة' : 'Register your company', { exact: true }).isVisible().catch(() => false)) blank.hit = true;
      await p.waitForTimeout(500);
    }
    step(m, 'the claimed company opens — never a blank "Register your company"', !blank.hit && await heading.isVisible(), `${Date.now() - t1} ms`);
    const claimed = (await read(`select claimed, lower(claimed_by)=lower('${email}') mine, owner_email_verified ev from public.leads where id=${lead.id}`))[0];
    step(m, 'the listing is claimed by this account with the e-mail proof carried', claimed?.claimed && claimed?.mine && claimed?.ev, JSON.stringify(claimed));

    // A portal that never opened on the company cannot be walked further; the step above already failed.
    if (!(await heading.isVisible().catch(() => false))) { await ctx.close(); continue; }
    const nav = p.getByRole('navigation').first();
    const settle = async () => { const t0 = Date.now(); while (Date.now() - t0 < 25000) { if (!(await M.evaluate((el) => /Loading|Measuring|جارٍ/.test(el.innerText) || !!el.querySelector('[aria-busy="true"]')))) return Date.now() - t0; await p.waitForTimeout(250); } return -1; };

    // 3. documents: licence + company profile
    await nav.getByRole('button').nth(4).click(); await M.getByRole('progressbar').first().waitFor({ timeout: 30000 });
    const lic = join(TMP, `${run.tag}_${n}_trade_licence.pdf`), prof = join(TMP, `${run.tag}_${n}_company_profile.pdf`);
    writeFileSync(lic, demoTradeLicence({ company, licenceNo: `ZZDEMO-${run.tag}-${n}`.toUpperCase(), activity: 'Aluminium and Glass Works' }));
    writeFileSync(prof, demoPdf([['COMPANY PROFILE (ZZ DEMO FIXTURE - NOT A REAL COMPANY)', 14], [company, 12]]));
    const upBtn = () => M.locator('button:enabled').filter({ hasText: AR(lang) ? /^(رفع|تحميل)$/ : /^Upload$/ }).first();
    await M.locator('input[type=file]').nth(0).setInputFiles(lic); await upBtn().click(); await settle();
    await M.getByText(/2028/).first().waitFor({ timeout: 30000 }).catch(() => {});
    await M.locator('button:enabled').filter({ hasText: AR(lang) ? /^(رفع|تحميل)$/ : /^Upload$/ }).first().waitFor({ state: 'detached', timeout: 5000 }).catch(() => {});
    await p.waitForTimeout(1500);
    await M.locator('input[type=file]').nth(1).setInputFiles(prof); await upBtn().click(); await settle(); await p.waitForTimeout(2500);
    const docs = (await read(`select license_doc_path is not null lic, license_expiry, company_profile_doc_path is not null prof from public.leads where id=${lead.id}`))[0];
    step(m, 'licence + company profile uploaded; licence expiry read', docs?.lic && docs?.prof && String(docs?.license_expiry || '').startsWith('2028'), JSON.stringify(docs));
    for (const d of await read(`select license_doc_path p from public.leads where id=${lead.id} union all select company_profile_doc_path from public.leads where id=${lead.id}`)) if (d.p) run.ids.storage.push('supplier-docs/' + d.p);

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
    const reg = (await read(`select approval_status, signed_terms_path, signatory_name from public.leads where id=${lead.id}`))[0];
    step(m, 'terms + Save → approved with a signed certificate', reg?.approval_status === 'approved' && !!reg?.signed_terms_path, `${JSON.stringify(reg)} in ${Date.now() - t2} ms`);
    if (reg?.signed_terms_path) run.ids.storage.push('signed-terms/' + reg.signed_terms_path);

    // 6. every tab, the bell and the account menu settle
    await p.reload({ waitUntil: 'domcontentloaded' }); await heading.waitFor({ timeout: 30000 });
    for (const name of await nav.getByRole('button').allInnerTexts()) {
      await nav.getByRole('button', { name, exact: true }).click(); const ms = await settle();
      step(m, `tab "${name}" settles`, ms >= 0, `${ms} ms${ms > 3000 ? ' (>3 s)' : ''}`);
    }
    for (let k = 0; k < 3; k++) {
      await acct.locator('summary').click(); const b = acct.getByRole('button').nth(k); const name = await b.innerText();
      await b.click(); const ms = await settle(); step(m, `account "${name}" settles`, ms >= 0, `${ms} ms${ms > 3000 ? ' (>3 s)' : ''}`);
    }
    await ctx.close();
  }
} finally {
  await browser.close();
  const c = await closeRun(run, { keep: KEEP });
  console.log('teardown:', JSON.stringify(c.leftovers || 'kept'));
}
const failed = results.filter((r) => !r.ok);
console.log(`${results.length - failed.length}/${results.length} passed`);
process.exit(failed.length ? 1 : 0);
