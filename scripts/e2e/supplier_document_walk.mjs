// scripts/e2e/supplier_document_walk.mjs: an invited supplier's documents, uploaded on production, at each width.
// Assigned: sales_engineer. 28 Oct 2026. Founder, on the first invitation day: suppliers "uploading their company profile,
// trade licence and other documents".
//
//   node scripts/e2e/supplier_document_walk.mjs [--vp desktop,mobile] [--desktop-width 1366] [--shots <dir>] [--summary <file>]
//
// One invited ZZ DEMO lead per width, signed up through the REAL form with the REAL e-mail code (the run's Resend sink,
// scripts/e2e/resend_sink.mjs). Then it uploads the documents a supplier holds, the way a supplier does:
//   registration form (supplier_api process_docs): a phone PHOTO of the licence;
//   Documents tab (supplier_portal save_documents): the photo, a bilingual Arabic/English licence PDF, a licence 1 MB
//     under the 25 MB limit and one 1 MB over it, the company profile, insurance, ISO and a dealer letter, and last the
//     plain DED licence, so the registration ends on a licence the review can read;
// and finishes registration (terms + Save, approved). Every upload records what the server answered, how long it took,
// what the card says afterwards, and what the row holds. Every fixture prints "ZZ DEMO FIXTURE".
// Teardown removes every supplier-docs object under the lead (replaced versions too), doc_versions, supporting documents,
// the run's rows (closeRun) and the sink accounts; the operator's scan afterwards covers e-mail columns and jsonb.
import { launch, SITE } from './browser.mjs';
import { openRun, closeRun, read, write, call } from './fixtures.mjs';
import { sinkAddress, readCode, cleanSink } from './resend_sink.mjs';
import { demoPdf, demoTradeLicence } from '../lib/demo_pdf.mjs';
import { keys } from '../lib/demo_factory.mjs';
import { BASE } from './fixtures.mjs';
import { writeFileSync, mkdtempSync, readFileSync, statSync, mkdirSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const argv = process.argv.slice(2);
const val = (f, d) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : d; };
const VPS = val('--vp', 'desktop,mobile').split(',');
const DESKTOP_W = Number(val('--desktop-width', '1366'));
const SHOTS = val('--shots', ''); if (SHOTS) mkdirSync(SHOTS, { recursive: true });
const SUMMARY = val('--summary', '');
const SKIP_BIG = argv.includes('--skip-big');
const TMP = mkdtempSync(join(tmpdir(), 'qd-docwalk-'));
const results = [];
const step = (m, name, ok, detail = '') => { results.push({ m, name, ok, detail }); console.log(`${ok ? 'PASS' : 'FAIL'} [${m}] ${name}${detail ? ' — ' + detail : ''}`); };
let shotN = 0;
const shot = async (p, m, name) => { if (!SHOTS) return null; const f = join(SHOTS, `${m}_${String(++shotN).padStart(2, '0')}_${name}.png`); await p.screenshot({ path: f, fullPage: true }).catch(() => {}); return f; };

// ── fixtures ──────────────────────────────────────────────────────────────────────────────────────────────────────
// A PDF padded to `bytes` with a comment block after the header; every xref offset and startxref is moved by the pad, so
// the file stays a valid PDF (pdf.js reads it normally) and its size is exact.
function padPdf(buf, bytes) {
  const s = buf.toString('latin1'); const head = '%PDF-1.4\n';
  const padLen = Math.max(0, bytes - buf.length); if (!padLen) return buf;
  // hex digits only: random base64 can spell "/JS" and be refused as embedded JavaScript (measured 28 Oct), which is
  // the padding talking, not the file under test
  const line = (n) => '%' + randomBytes(Math.ceil(n / 2)).toString('hex').slice(0, n - 2) + '\n';
  let pad = ''; let left = padLen; while (left > 0) { const n = Math.min(4096, left); pad += n >= 3 ? line(n) : '\n'.repeat(n); left -= n; }
  const body = s.slice(head.length).replace(/^(\d{10}) 00000 n $/gm, (_x, o) => String(Number(o) + padLen).padStart(10, '0') + ' 00000 n ')
    .replace(/startxref\n(\d+)\n/, (_x, o) => `startxref\n${Number(o) + padLen}\n`);
  return Buffer.from(head + pad + body, 'latin1');
}
const licenceHtml = ({ company, licenceNo, arabic }) => `<!doctype html><html><head><meta charset="utf-8"><style>
  body{margin:0;font-family:'FreeSerif','DejaVu Sans',serif;background:#fff;color:#111}
  .page{width:794px;padding:40px 48px;box-sizing:border-box;border:6px double #1a5e3a}
  .top{display:flex;justify-content:space-between;align-items:flex-start;border-bottom:2px solid #1a5e3a;padding-bottom:10px}
  .ar{direction:rtl;text-align:right;font-size:17px} h1{font-size:22px;margin:6px 0;color:#1a5e3a}
  table{width:100%;border-collapse:collapse;margin-top:14px;font-size:14px} td{border:1px solid #9bb;padding:6px 8px;vertical-align:top}
  td.l{width:30%;background:#eef5f0;font-weight:bold} .fx{margin-top:14px;font-size:11px;color:#a00}
</style></head><body><div class="page">
  <div class="top"><div><b>GOVERNMENT OF DUBAI</b><br>Department of Economy and Tourism</div>
  ${arabic ? '<div class="ar"><b>حكومة دبي</b><br>دائرة الاقتصاد والسياحة</div>' : ''}</div>
  <h1>TRADE LICENCE ${arabic ? '<span class="ar">رخصة تجارية</span>' : ''}</h1>
  <table>
   <tr><td class="l">Licence No.${arabic ? ' / رقم الرخصة' : ''}</td><td>${licenceNo}</td></tr>
   <tr><td class="l">Company Name${arabic ? ' / الاسم التجاري' : ''}</td><td>${company}${arabic ? '<div class="ar">زد زد ديمو للألمنيوم والزجاج ذ.م.م</div>' : ''}</td></tr>
   <tr><td class="l">Legal Type${arabic ? ' / الشكل القانوني' : ''}</td><td>Limited Liability Company${arabic ? ' / شركة ذات مسؤولية محدودة' : ''}</td></tr>
   <tr><td class="l">Issuing Authority</td><td>Dubai Department of Economy and Tourism</td></tr>
   <tr><td class="l">Emirate${arabic ? ' / الإمارة' : ''}</td><td>Dubai${arabic ? ' / دبي' : ''}</td></tr>
   <tr><td class="l">Issue Date${arabic ? ' / تاريخ الإصدار' : ''}</td><td>15/03/2025</td></tr>
   <tr><td class="l">Expiry Date${arabic ? ' / تاريخ الانتهاء' : ''}</td><td>14/03/2028</td></tr>
   <tr><td class="l">Activities${arabic ? ' / الأنشطة' : ''}</td><td>Aluminium and Glass Works${arabic ? '<div class="ar">أعمال الألمنيوم والزجاج</div>' : ''}</td></tr>
  </table>
  <div class="fx">ZZ DEMO FIXTURE: QuotesDone test document, not a real company or licence.</div>
</div></body></html>`;

async function makeFixtures(browser, { company, licenceNo }) {
  const f = {};
  const ctx = await browser.newContext({ viewport: { width: 900, height: 1200 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
  // a phone photo: the licence slightly rotated on a desk, JPEG
  await p.setContent(`<body style="margin:0;background:#6b5a46;display:flex;align-items:center;justify-content:center;height:1200px">
    <div style="transform:rotate(-3deg) scale(.96);box-shadow:0 18px 40px rgba(0,0,0,.5);filter:blur(.4px) brightness(.97)">${licenceHtml({ company, licenceNo, arabic: false }).replace(/^[\s\S]*<body>|<\/body>[\s\S]*$/g, '')}</div></body>`);
  f.photo = join(TMP, 'licence_photo.jpg'); writeFileSync(f.photo, await p.screenshot({ type: 'jpeg', quality: 72 }));
  // a bilingual licence PDF with a text layer (Chromium prints the text, Arabic included)
  await p.setContent(licenceHtml({ company, licenceNo, arabic: true }));
  f.bilingual = join(TMP, 'licence_bilingual.pdf'); writeFileSync(f.bilingual, await p.pdf({ format: 'A4', printBackground: true }));
  await ctx.close();
  f.ded = join(TMP, 'trade_licence.pdf'); writeFileSync(f.ded, demoTradeLicence({ company, licenceNo, activity: 'Aluminium and Glass Works' }));
  const base = readFileSync(f.ded);
  if (!SKIP_BIG) {
    // either side of the portal's read cap (supplier/api.ts MAX_READ_BYTES = 10 MB, measured: 9.66 MB read, 14.50 MB
    // ended the function at its CPU cap); the server's own 25 MB limit is behind it
    f.near = join(TMP, 'licence_9_5mb.pdf'); writeFileSync(f.near, padPdf(base, Math.round(9.5 * 1024 * 1024)));
    f.over = join(TMP, 'licence_12mb.pdf'); writeFileSync(f.over, padPdf(base, 12 * 1024 * 1024));
  }
  f.profile = join(TMP, 'company_profile.pdf'); writeFileSync(f.profile, demoPdf([['COMPANY PROFILE', 16], [company, 13], ['ZZ DEMO FIXTURE - NOT A REAL COMPANY', 10], ['', 10],
    ['About us: aluminium and glass works contractor serving Dubai and Sharjah since 2012.', 11], ['Services:', 12], ['Aluminium windows and doors', 11], ['Curtain wall and glass facades', 11],
    ['Shower enclosures and glass partitions', 11], ['Projects: villas, offices and retail fit-out.', 11]]));
  f.insurance = join(TMP, 'insurance_schedule.pdf'); writeFileSync(f.insurance, demoPdf([['POLICY SCHEDULE - CONTRACTORS ALL RISKS', 15], ['ZZ DEMO FIXTURE - NOT A REAL POLICY', 10],
    ['Insurer: ZZ Demo Insurance PJSC', 12], ['Policy No.: ZZD-CAR-2026-0042', 12], [`Insured: ${company}`, 11], ['Period of Insurance: From 01/01/2026 To 31/12/2026', 12], ['Expiry Date: 31/12/2026', 12], ['Limit: AED 5,000,000', 12]]));
  f.iso = join(TMP, 'iso_9001.pdf'); writeFileSync(f.iso, demoPdf([['CERTIFICATE OF REGISTRATION', 16], ['ISO 9001:2015 Quality Management System', 13], ['ZZ DEMO FIXTURE - NOT A REAL CERTIFICATE', 10],
    [`Awarded to: ${company}`, 11], ['Certificate No.: ZZD-QMS-7781', 12], ['Original Certification Date: 10/02/2024', 12], ['Expiry Date: 09/02/2027', 12]]));
  f.dealer = join(TMP, 'dealer_letter.pdf'); writeFileSync(f.dealer, demoPdf([['LETTER OF AUTHORISATION', 16], ['ZZ DEMO FIXTURE - NOT A REAL LETTER', 10],
    [`We confirm that ${company}`, 11], ['is an authorised dealer of ZZ Demo Aluminium Systems in the UAE.', 11], ['Valid Until: 30/06/2027', 12], ['Signed: ZZ Demo Aluminium Systems GmbH', 11]]));
  for (const [k, v] of Object.entries(f)) console.log('  fixture', k, (statSync(v).size / 1048576).toFixed(2) + ' MB');
  return f;
}

// ── the sign-up, with the real code (as supplier_registration_walk --real-otp) ──────────────────────────────────────
async function realOtpSignup(browser, ctxOpts, consent, url, email, company, m) {
  const ctx = await browser.newContext(ctxOpts); await ctx.addInitScript(consent); const p = await ctx.newPage(); p.setDefaultTimeout(45000);
  try {
    await p.goto(url, { waitUntil: 'domcontentloaded' });
    const box = p.locator('#qd-supplier-signin');
    await box.locator('input').first().waitFor({ timeout: 30000 });
    const claim = p.getByRole('button', { name: /^Claim my listing$/ }).first();
    if (await claim.waitFor({ timeout: 15000 }).then(() => true).catch(() => false)) { await claim.click(); await p.waitForTimeout(700); }
    await box.locator('input').first().fill(email);
    const t0 = Date.now();
    await box.getByRole('button', { name: /^Create my account$/ }).click();
    const codeBox = box.locator('input[autocomplete="one-time-code"]');
    if (!(await codeBox.waitFor({ timeout: 25000 }).then(() => true).catch(() => false))) { step(m, 'the sign-up form sends the code', false, (await box.innerText()).slice(0, 160)); return null; }
    const got = await readCode(email, t0);
    step(m, 'the real sign-up code is delivered to the sink and read', !!got.code, `last_event ${got.last_event}, ${got.read_ms} ms`);
    if (!got.code) return null;
    await codeBox.fill(got.code);
    await box.getByRole('button', { name: /^Verify/ }).first().click();
    const ok = await p.getByRole('heading', { name: company }).waitFor({ timeout: 40000 }).then(() => true).catch(() => false);
    step(m, 'the real code verifies and the invited company opens, claimed', ok);
    const tok = await p.evaluate(() => { try { return JSON.parse(localStorage.getItem('qd-portal-auth') || 'null'); } catch { return null; } });
    return tok?.access_token ? tok : null;
  } finally { await ctx.close(); }
}

// ── one upload, measured ──────────────────────────────────────────────────────────────────────────────────────────
// waits for the named action's response; returns { status, json, ms } (json null when the page timed out first).
function awaitAction(p, fn, action, timeout = 150000) {
  return p.waitForResponse((r) => r.url().includes('/functions/v1/' + fn) && (r.request().postData() || '').includes(`"action":"${action}"`), { timeout })
    .then(async (r) => ({ status: r.status(), json: await r.json().catch(() => null) })).catch((e) => ({ status: 0, json: null, err: String(e.message).split('\n')[0] }));
}
const rowOf = async (id) => (await read(`select license_doc_path, license_expiry::text license_expiry, trade_license_no, license_authority, licence_legal_name,
    company_profile_doc_path, insurance_doc_path, insurance_expiry::text insurance_expiry, iso_doc_path, iso_expiry::text iso_expiry,
    manufacturer_auth_doc_path, manufacturer_auth_expiry::text manufacturer_auth_expiry, approval_status, licence_gate_reason from public.leads where id=${id}`))[0];

async function leg(browser, run, vp) {
  const n = run.seq++, m = `${vp}${vp === 'desktop' ? DESKTOP_W : 390}`;
  const email = sinkAddress(run.tag, n), company = `ZZ DEMO Docs ${run.tag} ${vp} ${n}`, licenceNo = `ZZDEMO-${run.tag}-${n}`.toUpperCase();
  const lead = (await write(`insert into public.leads (company_name, email, emirate, source, invite_status, invited_at, locale, tags)
      values ('${company}', 'qd-${run.tag}-lead${n}@example.invalid', 'Dubai', 'directory', 'sent', now(), 'en', ARRAY['qd_demo','qd_run:${run.tag}']) returning id, claim_token::text t`, 'invited demo lead'))[0];
  run.ids.leads.add(String(lead.id)); run.sinks.push(email); run.leadIds.push(lead.id);
  const mobile = vp === 'mobile';
  const ctxOpts = { viewport: mobile ? { width: 390, height: 844 } : { width: DESKTOP_W, height: 900 }, locale: 'en-GB', ...(mobile ? { isMobile: true, hasTouch: true, deviceScaleFactor: 2 } : {}) };
  const consent = () => localStorage.setItem('qd-cookie-consent', JSON.stringify({ necessary: true, analytics: false, marketing: false, ts: Date.now() }));
  const url = `${SITE}/portal?t=${lead.t}`;
  const fx = await makeFixtures(browser, { company, licenceNo });
  const s = await realOtpSignup(browser, ctxOpts, consent, url, email, company, m);
  if (!s) return;
  const ctx = await browser.newContext(ctxOpts); await ctx.addInitScript(consent);
  await ctx.addInitScript(([s, t]) => { localStorage.setItem('qd-sup-token', s.access_token); localStorage.setItem('qd-sup-refresh', s.refresh_token);
    localStorage.setItem('qd-portal-auth', JSON.stringify(s)); localStorage.setItem('qd-lang', 'en'); try { sessionStorage.setItem('qd-claim-token', t); } catch { /* */ } }, [s, lead.t]);
  const p = await ctx.newPage(); p.setDefaultTimeout(60000); const M = p.locator('main');
  const heading = p.getByRole('heading', { name: company });
  await p.goto(url, { waitUntil: 'domcontentloaded' }); await heading.waitFor({ timeout: 40000 });
  const nav = p.getByRole('navigation').filter({ has: p.getByRole('button', { name: /^Inquiries received$/ }) }).first();
  const acct = M.locator('details').last();
  const settle = async () => { const t0 = Date.now(); while (Date.now() - t0 < 30000) { if (!(await M.evaluate((el) => /Loading|Measuring/.test(el.innerText) || !!el.querySelector('[aria-busy="true"]')))) return Date.now() - t0; await p.waitForTimeout(250); } return -1; };

  // A. THE REGISTRATION FORM'S LICENCE BOX (supplier_api process_docs). An INVITED supplier never sees this box: it renders
  // only in Onboarding, for an account with no company (the fresh-supplier path). It is the box #1707 repaired, so it is
  // replayed here with the portal's exact body for a photo (SupplierPortal.tsx fileToImages: images [{ mime, data }]).
  { const b64 = readFileSync(fx.photo).toString('base64'); const t0 = Date.now();
    const r = await call('supplier_api', s.access_token, { action: 'process_docs', license: { original_b64: b64, file_b64: b64, images: [{ mime: 'image/jpeg', data: b64 }], filename: 'licence_photo.jpg', mime: 'image/jpeg' } }, 150000);
    const ms = Date.now() - t0; const ex = r.json?.extracted?.license || null;
    step(m, 'registration-form licence box (portal body replayed): a phone photo stores', r.status === 200 && r.json?.ok === true, `HTTP ${r.status} in ${ms} ms`);
    step(m, 'registration-form licence box: the phone photo is READ (number + expiry)', ex?.license_number === licenceNo && ex?.expiry === '2028-03-14',
      `extracted=${JSON.stringify(ex)}; license_error=${JSON.stringify(r.json?.extracted?.license_error ?? null)}; ${ms} ms`); }

  // B. THE DOCUMENTS TAB (supplier_portal save_documents). Each card is found by its heading, as a supplier finds it.
  await nav.getByRole('button', { name: 'Documents', exact: true }).click().catch(async () => { await nav.getByRole('button').nth(4).click(); });
  await M.getByRole('progressbar').first().waitFor({ timeout: 30000 });
  const card = (name) => M.locator('.qd-panel').filter({ has: p.locator('b', { hasText: new RegExp('^' + name + '$') }) }).last();
  const upload = async (cardName, file, label, { action = 'save_documents', fn = 'supplier_portal' } = {}) => {
    const c = card(cardName); const t0 = Date.now();
    const wait = awaitAction(p, fn, action);
    await c.locator('input[type=file]').first().setInputFiles(file);
    const btn = c.getByRole('button', { name: /^Upload$/ });
    if (await btn.isVisible().catch(() => false)) await btn.click();
    let r = await wait;
    // the profile goes up to storage first; the save carries its path
    if (action === 'upload_url') r = { ...r, save: await awaitAction(p, 'supplier_portal', 'save_documents') };
    const ms = Date.now() - t0; await settle(); await p.waitForTimeout(1200);
    const cardText = (await c.innerText().catch(() => '')).replace(/\s+/g, ' ').slice(0, 260);
    const docsCard = M.locator('.qd-panel').filter({ hasText: 'Documents & certificates' }).first();
    const errText = (await docsCard.innerText().catch(() => '')).split('\n').filter((l) => /fail|could not|cannot|too large|larger|try again|up to|MB/i.test(l)).join(' | ');
    const sh = await shot(p, m, label);
    return { r, ms, cardText, errText, sh };
  };
  const docsRow = async () => rowOf(lead.id);

  // B1. phone photo of the licence (images reach license_extract as { b64 }: this path is not the one #1707 fixes)
  { const u = await upload('Trade licence', fx.photo, 'docs_licence_photo'); const j = u.r.json || {}; const row = await docsRow();
    step(m, 'Documents: phone-photo licence stores', u.r.status === 200 && (j.saved || []).includes('license') && !!row.license_doc_path, `HTTP ${u.r.status} in ${u.ms} ms; failed=${JSON.stringify(j.failed || [])}`);
    step(m, 'Documents: phone-photo licence is read, or says plainly it was not', !!row.license_expiry || /could not read the expiry/i.test(u.cardText),
      `row ${JSON.stringify({ no: row.trade_license_no, exp: row.license_expiry, name: row.licence_legal_name })}; read=${JSON.stringify(j.read?.license || null)}; card: "${u.cardText}"; ${u.sh || ''}`);
    step(m, 'Documents: the photo upload answers inside the portal\'s wait for a read (90 s, #1709)', u.ms < 90000 && u.r.status === 200, `${u.ms} ms`); }
  // B2. bilingual Arabic / English licence PDF (Replace on the licence card)
  { const u = await upload('Trade licence', fx.bilingual, 'docs_licence_bilingual'); const j = u.r.json || {}; const row = await docsRow();
    step(m, 'Documents: bilingual (Arabic/English) licence PDF stores and is read', u.r.status === 200 && (j.saved || []).includes('license') && row.license_expiry === '2028-03-14',
      `HTTP ${u.r.status} in ${u.ms} ms; row ${JSON.stringify({ no: row.trade_license_no, exp: row.license_expiry, name: row.licence_legal_name, auth: row.license_authority })}; card: "${u.cardText}"; ${u.sh || ''}`); }
  if (!SKIP_BIG) {
    // B3. 9.5 MB: under the read cap, must store and be read
    { const u = await upload('Trade licence', fx.near, 'docs_licence_9_5mb'); const row = await docsRow();
      step(m, 'Documents: a 9.5 MB licence PDF (under the 10 MB read cap) stores and is read', u.r.status === 200 && !!row.license_doc_path && row.license_expiry === '2028-03-14',
        `HTTP ${u.r.status} in ${u.ms} ms${u.r.err ? ' ' + u.r.err : ''}; screen: "${u.errText}"; ${u.sh || ''}`); }
    // B4. 12 MB: over the read cap, refused in the browser before anything is sent, in plain words (no platform text)
    { let sent = false; const onReq = (r) => { if (r.url().includes('/functions/v1/supplier_portal') && (r.postData() || '').includes('"save_documents"')) sent = true; };
      p.on('request', onReq);
      const c = card('Trade licence'); await c.locator('input[type=file]').first().setInputFiles(fx.over);
      const btn = c.getByRole('button', { name: /^Upload$/ }); if (await btn.isVisible().catch(() => false)) await btn.click();
      await p.waitForTimeout(2500); p.off('request', onReq);
      const said = (await M.locator('.qd-panel').filter({ hasText: 'Documents & certificates' }).first().innerText().catch(() => '')).replace(/\s+/g, ' ');
      const sh = await shot(p, m, 'docs_licence_12mb_refused');
      step(m, 'Documents: a 12 MB licence is refused in the browser, before it is sent, in plain words', !sent && /We can read files up to 10 MB/.test(said) && !/compute resources|check logs/i.test(said),
        `request sent: ${sent}; screen: "${(said.match(/That file is[^.]*\.[^.]*\./) || [said.slice(0, 200)])[0]}"; ${sh || ''}`); }
  }
  // B5. company profile (direct upload to storage, then save_documents with the path)
  { const u = await upload('Company profile', fx.profile, 'docs_profile', { fn: 'supplier_api', action: 'upload_url' }); const row = await docsRow();
    step(m, 'Documents: company profile PDF stores', !!row.company_profile_doc_path && u.r.save?.json?.ok === true, `upload_url HTTP ${u.r.status}; save HTTP ${u.r.save?.status} in ${u.ms} ms; card: "${u.cardText}"; ${u.sh || ''}`); }
  // B6-8. insurance, ISO, dealer letter: the expiry is read off the file and offered to confirm
  for (const [cardName, key, file, expect, col] of [['Insurance', 'insurance', fx.insurance, '2026-12-31', 'insurance'], ['ISO certification', 'iso', fx.iso, '2027-02-09', 'iso'], ['Manufacturer authorisation letter', 'manufacturer', fx.dealer, '2027-06-30', 'manufacturer_auth']]) {
    const name = cardName;
    if (!(await card(name).count())) { step(m, `Documents: the ${cardName} card is on the tab`, false, 'card not found'); continue; }
    const u = await upload(name, file, 'docs_' + key); const j = u.r.json || {};
    const read1 = j.read?.[key] || null;
    step(m, `Documents: ${cardName} stores, and its expiry is read off the file`, u.r.status === 200 && (j.saved || []).includes(key) && read1?.expiry === expect, `HTTP ${u.r.status} in ${u.ms} ms; read=${JSON.stringify(read1)}; card: "${u.cardText}"; ${u.sh || ''}`);
    const confirm = card(name).getByRole('button', { name: /^Confirm$/ });
    if (await confirm.isVisible().catch(() => false)) { const w = awaitAction(p, 'supplier_portal', 'set_expiry'); await confirm.click(); const r2 = await w; await settle(); await p.waitForTimeout(800); }
    const row = await docsRow();
    step(m, `Documents: ${cardName} expiry confirmed and on file`, !!row[col + '_doc_path'] && row[col + '_expiry'] === expect, `row ${col}_expiry=${row[col + '_expiry']}`);
  }
  // B9. the plain DED licence last, so registration ends on a licence the review reads
  { const u = await upload('Trade licence', fx.ded, 'docs_licence_ded'); const j = u.r.json || {}; const row = await docsRow();
    const nm = (await read(`select public.fn_company_name_norm(licence_legal_name) = public.fn_company_name_norm(company_name) matches from public.leads where id=${lead.id}`))[0];
    step(m, 'Documents: DED licence PDF stores; number, expiry and name read by code; name matches', u.r.status === 200 && row.trade_license_no === licenceNo && row.license_expiry === '2028-03-14' && nm.matches === true,
      `HTTP ${u.r.status} in ${u.ms} ms; row ${JSON.stringify({ no: row.trade_license_no, exp: row.license_expiry, name: row.licence_legal_name })}; ${u.sh || ''}`); }
  // every button inside the screen (390 px clip check, as the registration walk)
  { const off = await p.evaluate(() => [...document.querySelectorAll('main button, main label, main input')].filter((b) => { const r = b.getBoundingClientRect(); if (b.closest('details:not([open])') && !b.closest('summary')) return false;
      let a = b.parentElement; while (a && a !== document.body) { const o = getComputedStyle(a).overflowX; if (o === 'auto' || o === 'scroll') return false; a = a.parentElement; }
      return r.width > 0 && r.height > 0 && r.right > window.innerWidth + 1; }).map((b) => (b.innerText || b.getAttribute('aria-label') || b.tagName).trim().slice(0, 30)));
    step(m, 'Documents: every control is inside the screen after all uploads', off.length === 0, off.join('; ')); }
  await shot(p, m, 'docs_all_on_file');

  // C. finish registration: fixture mobile (refused before any SMS, then recorded), WhatsApp answer, terms, Save.
  await write(`update public.leads set phone='+9715000000${String(10 + n).padStart(2, '0')}', owner_phone_verified=true where id=${lead.id}`, 'fixture mobile verified');
  await call('kyc', s.access_token, { action: 'whatsapp_choose', user_kind: 'supplier', email, opt: 'same' });
  await p.reload({ waitUntil: 'domcontentloaded' }); await heading.waitFor({ timeout: 40000 });
  await acct.locator('summary').click(); await acct.getByRole('button').first().click(); await settle();
  await M.getByRole('textbox', { name: /Contact name/ }).first().fill('ZZ DEMO Contact');
  await M.getByRole('textbox', { name: /Authorized signatory/ }).first().fill('ZZ DEMO Signatory');
  await M.getByRole('checkbox', { name: 'Dubai', exact: true }).check();
  await M.getByRole('checkbox', { name: /I accept the QuotesDone/ }).check();
  await M.getByRole('button', { name: /^Save changes$/ }).click();
  await M.getByRole('button', { name: /Saving/ }).waitFor({ state: 'detached', timeout: 90000 }).catch(() => {});
  const t3 = Date.now(); let reg;
  for (;;) { reg = await rowOf(lead.id); if ((reg.approval_status === 'approved') || Date.now() - t3 > 75000) break; await new Promise((r) => setTimeout(r, 2500)); }
  const sh = await shot(p, m, 'after_submit');
  step(m, 'the supplier finishes registration: approved, no licence hold', reg.approval_status === 'approved' && !reg.licence_gate_reason, `${JSON.stringify({ a: reg.approval_status, why: reg.licence_gate_reason })}; ${sh || ''}`);
  await ctx.close();
}

// ── run ───────────────────────────────────────────────────────────────────────────────────────────────────────────
const run = await openRun({ capUsd: 0.5, minutes: 60 }); run.seq = 1; run.sinks = []; run.leadIds = [];
console.log('run', run.tag, 'site', SITE);
const browser = await launch();
let teardownOut = null;
try {
  for (const vp of VPS) { try { await leg(browser, run, vp); } catch (e) { step(vp, 'the leg ran to the end', false, String(e?.message || e).split('\n')[0]); } }
} finally {
  await browser.close();
  // Every object under the lead (replaced versions stay in storage by design), its version rows and supporting documents.
  const { SERVICE } = await keys();
  for (const id of run.leadIds) {
    const objs = await read(`select name from storage.objects where bucket_id='supplier-docs' and name ~ '^[a-z_]+/${Number(id)}/'`);
    for (let i = 0; i < objs.length; i += 50) await fetch(`${BASE}/storage/v1/object/supplier-docs`, { method: 'DELETE', headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE, 'Content-Type': 'application/json' }, body: JSON.stringify({ prefixes: objs.slice(i, i + 50).map((o) => o.name) }) });
    await write(`delete from public.doc_versions where entity_type='supplier_document' and entity_id like '${Number(id)}:%';
                 delete from public.documents where ref_table='supplier_supporting' and ref_id='${Number(id)}'`, 'document walk cleanup');
    console.log('removed', objs.length, 'supplier-docs objects for lead', id);
  }
  const c = await closeRun(run); teardownOut = c;
  for (const a of run.sinks) { const l = await cleanSink(a).catch((e) => ({ error: String(e.message) })); (teardownOut.sinks ||= []).push({ a, l }); }
  console.log('teardown:', JSON.stringify(teardownOut));
}
const failed = results.filter((r) => !r.ok);
if (SUMMARY) writeFileSync(SUMMARY, JSON.stringify({ tag: run.tag, site: SITE, leads: run.leadIds, results, teardown: teardownOut }, null, 2));
console.log(`${results.length - failed.length}/${results.length} passed`);
process.exit(failed.length ? 1 : 0);
