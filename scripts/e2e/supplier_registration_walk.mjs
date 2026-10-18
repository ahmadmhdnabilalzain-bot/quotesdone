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
import { writeFileSync, mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const argv = process.argv.slice(2);
const val = (f, d) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : d; };
const LANGS = val('--lang', 'en,ar').split(','); const VPS = val('--vp', 'desktop,mobile').split(',');
const KEEP = argv.includes('--keep');
// --shots <dir>: a full-page screenshot of every screen, named <lang>_<vp>_<nn>_<step>.png (24 Sep 2026, ledger 993).
const SHOTS = val('--shots', ''); let shotN = 0;
const shot = async (p, m, name) => { if (!SHOTS) return; const f = join(SHOTS, `${m.replace('/', '_')}_${String(++shotN).padStart(2, '0')}_${name}.png`); await p.screenshot({ path: f, fullPage: true }).catch(() => {}); console.log('  shot', f); };
const TMP = mkdtempSync(join(tmpdir(), 'qd-regwalk-'));
const AR = (l) => l === 'ar';
const results = [];
const step = (m, name, ok, detail = '') => { results.push({ m, name, ok, detail }); console.log(`${ok ? 'PASS' : 'FAIL'} [${m}] ${name}${detail ? ' — ' + detail : ''}`); };

// --case <truth id,...> (13 Oct 2026, ruling 1230, it_engineer): instead of a generated licence, upload a corpus
// licence (default corpus: the 12 Oct accuracy run) under an invited name that DIFFERS from it, and assert ruling
// 1176 (the read licence name becomes the company name), the licence number and expiry, the profile + catalogue
// (ruling 1177), and the outcome the corpus truth expects: approved, or held with a reason. Scans and Arabic-only
// licences need the vision model, so this run's own rehearsal window is opened to models (cap USD 1, 1 hour).
const CASES = val('--case', '').split(',').filter(Boolean);
const CORPUS = val('--corpus', 'C:/Users/Opera/Desktop/QuotesDone Sandbox Test 2026-10/documents/run-final-12-oct-model-on/corpus');
const TRUTH = CASES.length ? JSON.parse(readFileSync(join(CORPUS, 'truth.json'), 'utf8')).docs : [];
const MATRIX = CASES.length ? CASES.map((c, i) => ({ lang: 'en', vp: VPS[i % VPS.length], c: TRUTH.find((d) => d.id === c) || (() => { throw new Error('no corpus case ' + c); })() }))
  : LANGS.flatMap((lang) => VPS.map((vp) => ({ lang, vp, c: null })));
const esc = (x) => String(x).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const run = await openRun();
if (CASES.length) await write(`update public.rehearsal_window set models_allowed = true, cap_usd = 1, expires_at = now() + interval '1 hour'
  where run_tag = 'qd_run:${run.tag}' and ended_at is null`, 'case walk: models on for this run only');
const browser = await launch();
try {
  for (const { lang, vp, c } of MATRIX) {
    const m = `${lang}/${vp}${c ? '/' + c.id : ''}`, n = run.seq++;
    const approveCase = !c || ['approve', 'name_autofilled'].includes(c.expected);
    const email = `qd-${run.tag}-sup${n}@example.invalid`, company = `ZZ DEMO Walk ${run.tag} ${lang} ${vp} ${n}`;
    const lead = (await write(`insert into public.leads (company_name, email, emirate, source, invite_status, invited_at, locale, tags)
      values ('${company}', '${email}', 'Dubai', 'directory', 'sent', now(), '${lang}', ARRAY['qd_demo','qd_run:${run.tag}'])
      returning id, claim_token::text t`, 'invited demo lead'))[0];
    run.ids.leads.add(String(lead.id));
    const mobile = vp === 'mobile';
    const ctxOpts = { viewport: mobile ? { width: Number(val('--mobile-width', '390')), height: 844 } : { width: 1440, height: 900 }, locale: AR(lang) ? 'ar-AE' : 'en-GB', ...(mobile ? { isMobile: true, hasTouch: true, deviceScaleFactor: 2 } : {}) };
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
    const nav = p.getByRole('navigation').first();
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
    await M.locator('input[type=file]').nth(0).setInputFiles(licUp); await upBtn().click(); await settle();
    await M.getByText(/2028/).first().waitFor({ timeout: 30000 }).catch(() => {});
    await M.locator('button:enabled').filter({ hasText: AR(lang) ? /^(رفع|تحميل)$/ : /^Upload$/ }).first().waitFor({ state: 'detached', timeout: 5000 }).catch(() => {});
    await p.waitForTimeout(1500);
    await M.locator('input[type=file]').nth(1).setInputFiles(prof); await upBtn().click(); await settle(); await p.waitForTimeout(2500);
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
    const docs = (await read(`select license_doc_path is not null lic, license_expiry, company_profile_doc_path is not null prof from public.leads where id=${lead.id}`))[0];
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
      if ((reg?.approval_status === 'approved' && reg?.signed_terms_path) || (!approveCase && reg?.licence_gate_reason && reg.licence_gate_reason !== 'reg_terms') || Date.now() - t3 > 60000) break;
      await new Promise((r) => setTimeout(r, 2000));
    }
    if (approveCase) step(m, 'terms + Save → approved with a signed certificate, by the deterministic check with no licence hold', reg?.approval_status === 'approved' && !!reg?.signed_terms_path && !reg?.licence_gate_reason,
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
    // the decision reaches the supplier: written, and fenced for an @example.invalid fixture (suppressed, never sent)
    await new Promise((r) => setTimeout(r, 4000));
    const nt = await read(`select type, channel, status from public.notifications where lead_id=${lead.id} order by id`);
    const want = approveCase ? nt.some((x) => x.type === 'supplier_approved' && x.channel === 'email') : nt.length > 0;
    step(m, `the ${approveCase ? 'approval' : 'hold'} notice is written (fixture: suppressed, never sent)`, want && nt.every((x) => x.status === 'suppressed'), JSON.stringify(nt));
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
} finally {
  await browser.close();
  const c = await closeRun(run, { keep: KEEP });
  console.log('teardown:', JSON.stringify(c.leftovers || 'kept'));
}
const failed = results.filter((r) => !r.ok);
console.log(`${results.length - failed.length}/${results.length} passed`);
process.exit(failed.length ? 1 : 0);
