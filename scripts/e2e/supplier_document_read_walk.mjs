// scripts/e2e/supplier_document_read_walk.mjs — A SUPPLIER'S REAL FILES, THROUGH THE REAL ENDPOINTS, TO A DECISION.
// Assigned: sales_engineer. 2 Nov 2026, ledger 1442; whole-picture audit items 6, 7, 10.
//
// Measured before this: all 12 demo approvals carried fixture licence fields with doc_extracted_at null, and 0 of
// 14,755 supplier_capabilities rows held a document record, so nothing proved a licence or profile is ever read.
// Each case here is an invited ZZ DEMO lead that claims its listing and sends generated files through supplier_api
// process_docs and save_profile, exactly the calls the portal makes, with no field written by the harness except the
// fixture mobile (a reserved number that can receive no code; mobile_otp refuses it before any SMS).
//
//   node scripts/e2e/supplier_document_read_walk.mjs [--case a,b] [--concurrency 3] [--keep] [--json <file>]
//
// Exit 1 when any case differs from its expected outcome. A read that stops working fails here: the text case must
// write the licence number, name, authority and expiry and a source_docs record for the licence and the profile, and
// the scan cases must do the same through the model. Nothing can reach a person: @example.invalid mail is suppressed
// by the demo guard, the mobile block is refused before Twilio, and teardown removes the run by its tag.
import { writeFileSync, mkdtempSync, readFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { openRun, closeRun, read, write, call, BASE } from './fixtures.mjs';
import { keys, verifyEmailByOtp, mkAuthUser, internalCred } from '../lib/demo_factory.mjs';
import { buildCorpus, licenceTruth, licenceTextPdf, licenceSvg, picture, rawPdf, AUTHORITIES } from './document_intake_corpus.mjs';
import { demoPdfPages } from '../lib/demo_pdf.mjs';
import sharp from 'sharp';
import { launch, signedInPage, SITE } from './browser.mjs';
import { mkdirSync } from 'node:fs';
import { pdfFactsFromBytes } from './pdf_facts.mjs';

const argv = process.argv.slice(2);
const val = (f, d) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : d; };
const ONLY = val('--case', '').split(',').filter(Boolean);
const CONC = Number(val('--concurrency', '3'));
const KEEP = argv.includes('--keep');
const JSON_OUT = val('--json', '');
const BROWSER = argv.includes('--browser');   // the licence goes in through the portal's own form in a real browser
const SHOTS = val('--shots', 'walk-shots');
if (BROWSER) mkdirSync(SHOTS, { recursive: true });

const TMP = mkdtempSync(join(tmpdir(), 'qd-docwalk-'));
const docs = await buildCorpus(TMP);
const byId = (id) => { const d = docs.find((x) => x.id === id); if (!d) throw new Error('no corpus doc ' + id); return { file: d.file ? join(TMP, d.file) : null, mime: d.mime, name: d.file, truth: d.truth, registered: d.registered_name }; };

// A FOREIGN LICENCE: printed like a UAE one, every field readable, issued abroad. Supplier Agreement v16 clause 13.
const FOREIGN = { emirate: null, authority: 'Ministry of Commerce, Kingdom of Saudi Arabia', layout: 'colon', date: 'dmy/',
  title: ['KINGDOM OF SAUDI ARABIA', 'MINISTRY OF COMMERCE', 'COMMERCIAL REGISTRATION'], form: 'Limited Liability Company', no: (n) => String(4030000000 + n), printsEmirate: false,
  L: { no: 'Licence No', name: 'Company Name', trade: 'Trade Name', form: 'Legal Type', issue: 'Issue Date', expiry: 'Expiry Date', acts: 'Activities', auth: 'Issuing Authority' } };
const foreignTruth = () => { AUTHORITIES.zz_foreign = FOREIGN; const t = licenceTruth('zz_foreign', 3, { legal: 'ZZ DEMO Najd Aluminium LLC' }); delete AUTHORITIES.zz_foreign; return { ...t, authority: FOREIGN.authority, emirate: null }; };
const save = (n, bytes) => { const p = join(TMP, n); writeFileSync(p, bytes); return p; };
const ft = foreignTruth();
const foreignText = { file: save('foreign_text.pdf', licenceTextPdf(FOREIGN, ft)), mime: 'application/pdf', name: 'foreign_text.pdf', truth: ft, registered: ft.legal_name_en };
const fs = await picture(licenceSvg(FOREIGN, ft, 'en'), 'jpg');
const foreignScan = { file: save('foreign_scan.jpg', fs.bytes), mime: fs.mime, name: 'foreign_scan.jpg', truth: ft, registered: ft.legal_name_en };

// A SCANNED COMPANY PROFILE: an image-only PDF, no text layer. The other profiles come from the corpus.
const profLines = ['ZZ DEMO Reem Projects LLC - Company Profile', 'Our services', '- Thermal break aluminium windows and doors', '- Curtain wall and glass facade installation', 'Serving Dubai and Sharjah since 2012', '(QuotesDone synthetic fixture - not a real company)'];
const profSvg = Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="1240" height="1754"><rect width="100%" height="100%" fill="#fff"/>${profLines.map((l, k) => `<text x="80" y="${140 + k * 70}" font-family="Arial" font-size="34">${l}</text>`).join('')}</svg>`);
const profJpeg = await sharp(profSvg).flatten({ background: '#ffffff' }).jpeg({ quality: 80 }).toBuffer();
const profileScan = { file: save('profile_scan.pdf', rawPdf([{ jpeg: profJpeg, w: 1240, h: 1754 }])), mime: 'application/pdf', name: 'profile_scan.pdf' };
const profileText = { ...byId('profile_pdf') };
const profilePng = { ...byId('profile_png') };
const profileBlank = { file: save('profile_blank.pdf', rawPdf([{ content: '' }])), mime: 'application/pdf', name: 'profile_blank.pdf' };

// licence: what is uploaded. want: the decision a supplier must get. read: fields the licence read must have written.
// doc: the source_docs status each document must end in. uae_trade: this registration should become matchable.
const APPROVE = { status: 'approved', reason: null };
const CASES = [
  { id: 'clean_text', licence: byId('lic_dubai_det_text'), profile: profileText, want: APPROVE, read: ['licence_no', 'name', 'authority', 'expiry'], doc: { licence: 'read', profile: 'read' } },
  { id: 'bilingual_scanned_pdf', licence: byId('lic_abu_dhabi_added_bi_scan_pdf'), profile: profileScan, want: APPROVE, read: ['licence_no', 'name', 'authority', 'expiry'], doc: { licence: 'read', profile: 'read' } },
  { id: 'phone_photo', licence: byId('lic_sharjah_sedd_bi_phone'), profile: profilePng, want: APPROVE, read: ['licence_no', 'name', 'authority', 'expiry'], doc: { licence: 'read', profile: 'read' } },
  { id: 'arabic_only', licence: byId('lic_ajman_ded_ar_png'), profile: profileText, want: { status: 'pending', reason: 'licence_unreadable' } },
  { id: 'expired_text', licence: byId('lic_expired_text'), profile: profileText, want: { status: 'action_required', reason: 'licence_expired' }, read: ['licence_no', 'name', 'authority', 'expiry'] },
  { id: 'expired_scan', licence: byId('lic_expired_scan'), profile: profileText, want: { status: 'action_required', reason: 'licence_expired' }, read: ['name', 'expiry'] },
  { id: 'foreign_text', licence: foreignText, profile: profileText, want: { status: 'pending', reason: 'licence_authority_not_uae' }, read: ['licence_no', 'name', 'authority', 'expiry'] },
  { id: 'foreign_scan', licence: foreignScan, profile: profileText, want: { status: 'pending', reason: 'licence_authority_not_uae' } },
  { id: 'blank_photo', licence: byId('lic_blank_photo'), profile: profileText, want: { status: 'pending', reason: 'licence_unreadable' } },
  { id: 'blank_profile', licence: byId('lic_dubai_ded_old_text'), profile: profileBlank, want: APPROVE, doc: { licence: 'read', profile: 'unreadable' } },
  // 2 Nov 2026, ledger 1467/1468: the seven files a supplier actually sends, each judged against its printed truth.
  // observe: the decision is reported, not asserted (what the system does with it is the question).
  { id: 't_text_pdf', licence: byId('lic_dubai_det_text'), profile: profileText, want: APPROVE, read: ['licence_no', 'name', 'authority', 'expiry'] },
  { id: 't_scanned_pdf', licence: byId('lic_dubai_ded_old_scan_pdf'), profile: profileText, want: APPROVE, read: ['licence_no', 'name', 'authority', 'expiry'] },
  { id: 't_png', licence: byId('lic_dubai_det_png'), profile: profileText, want: APPROVE, read: ['licence_no', 'name', 'authority', 'expiry'] },
  { id: 't_jpg', licence: byId('lic_abu_dhabi_added_jpg'), profile: profileText, want: APPROVE, read: ['licence_no', 'name', 'authority', 'expiry'] },
  { id: 't_blank_pdf', licence: byId('lic_blank_pdf'), profile: profileText, want: { status: 'pending', reason: 'licence_unreadable' } },
  { id: 't_wrong_company', licence: byId('lic_mismatch_text'), profile: profileText, want: APPROVE, nameFromLicence: true, read: ['licence_no', 'name', 'authority', 'expiry'] },
  { id: 't_expired', licence: byId('lic_expired_text'), profile: profileText, want: { status: 'action_required', reason: 'licence_expired' }, read: ['licence_no', 'name', 'authority', 'expiry'] },
].filter((c) => !ONLY.length || ONLY.includes(c.id));

const b64 = (p) => readFileSync(p).toString('base64');
const results = [];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let BR = null;
// The licence through the portal's OWN form, in a real browser on the live site: the file is picked, the browser renders
// a PDF's pages, process_docs is sent, and what the supplier sees afterwards is read off the screen. A form that never
// answers is a hang. The caller falls back to the API only when the form was not reached.
async function browserLicence(c, who, id) {
  BR ||= await launch();
  const { ctx, page } = await signedInPage(BR, who, { lang: 'en', viewport: 'desktop' });
  const o = { reached: false, answered: false, hung: false, ms: null, sees: null, alerts: [], shot: null, response: null };
  try {
    await page.goto(`${SITE}/portal`, { waitUntil: 'domcontentloaded', timeout: 60000 });
    // A claimed supplier manages the licence in the Documents tab (SupplierPortal: save_documents), not the sign-up form.
    await page.getByRole('button', { name: /^Documents$/ }).first().click({ timeout: 60000 });
    const head = page.getByText('Documents & certificates').first();
    await head.waitFor({ timeout: 60000 });
    const input = head.locator('xpath=following::input[@type="file"][1]');
    await input.waitFor({ state: 'attached', timeout: 60000 });
    o.reached = true;
    const isLic = (r) => /\/functions\/v1\/supplier_portal/.test(r.url()) && /save_documents/.test(r.request().postData() || '');
    const t0 = Date.now();
    const ans = page.waitForResponse(isLic, { timeout: 200000 }).then(async (r) => { o.answered = true; o.ms = Date.now() - t0; o.response = `HTTP ${r.status()} ${(await r.text().catch(() => '')).slice(0, 600)}`; }).catch(() => { o.hung = true; o.ms = Date.now() - t0; });
    await input.setInputFiles(c.licence.file);
    await input.locator('xpath=../..').getByRole('button', { name: /^Upload$/ }).click({ timeout: 15000 });
    await ans;
    await page.getByText(/^Uploading…/).first().waitFor({ state: 'detached', timeout: 20000 }).catch(() => { o.still_reading = true; });
    await page.waitForTimeout(1500);
    const main = (await page.locator('main').first().innerText().catch(() => page.locator('body').innerText())).replace(/[ \t]+/g, ' ');
    o.unread_badge = /Could not be read/.test(main) && /use Replace|upload a clear/i.test(main);
    o.sees = main.split('\n').map((l) => l.trim()).filter((l) => /licen|expir|read|upload|could not|auto|number|authority|wrong|action|review/i.test(l)).slice(0, 14).join(' | ').slice(0, 900);
    o.alerts = await page.getByRole('alert').allInnerTexts().catch(() => []);
    o.shot = join(SHOTS, `${id}.png`);
    await page.screenshot({ path: o.shot, fullPage: true }).catch(() => {});
  } catch (e) {
    o.error = String(e.message).slice(0, 200);
    o.shot = join(SHOTS, `${id}_form_not_reached.png`);
    await page.screenshot({ path: o.shot, fullPage: true }).catch(() => {});
    o.page_text = (await page.locator('body').innerText().catch(() => '')).replace(/s+/g, ' ').slice(0, 700);
    o.url = page.url();
  }
  await ctx.close().catch(() => {});
  return o;
}

async function walk(run, c, n) {
  const out = { id: c.id, steps: [], ok: true };
  const step = (name, ok, detail = '') => { out.steps.push({ name, ok: !!ok, detail }); if (!ok) out.ok = false; console.log(`${ok ? 'PASS' : 'FAIL'} [${c.id}] ${name}${detail ? ' — ' + detail : ''}`); };
  const email = `qd-${run.tag}-sup${n}@example.invalid`, mobile = `+9715000000${String(10 + n).padStart(2, '0')}`;
  const company = c.licence.registered || `ZZ DEMO Walk ${run.tag} ${n}`;
  const lead = (await write(`insert into public.leads (company_name, email, emirate, source, invite_status, invited_at, locale, tags)
     values ('${company.replace(/'/g, "''")}', '${email}', 'Dubai', 'directory', 'sent', now(), 'en', ARRAY['qd_demo','qd_run:${run.tag}']) returning id, claim_token::text t`, 'invited demo lead'))[0];
  run.ids.leads.add(String(lead.id)); out.lead = lead.id;

  // 1. Account and e-mail code: the code is seeded hashed and verified through the real login_otp endpoint.
  const u = await mkAuthUser(run, email);
  const v = await verifyEmailByOtp(email, 'supplier');
  const { ANON } = await keys();
  const s = await (await fetch(`${BASE}/auth/v1/token?grant_type=password`, { method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password: u.password }) })).json();
  step('account + e-mail code (login_otp)', v.json?.ok === true && !!s.access_token, `HTTP ${v.status}`);
  if (!s.access_token) return out;
  const jwt = s.access_token;

  // 2. The invitation claim.
  const cl = await call('supplier_api', jwt, { action: 'claim', t: lead.t, first_touch: null });
  const claimed = (await read(`select claimed, owner_email_verified ev from public.leads where id=${lead.id}`))[0];
  step('the invited listing is claimed', cl.status === 200 && claimed?.claimed && claimed?.ev, `HTTP ${cl.status} ${JSON.stringify(claimed)}`);

  // 3. Mobile: a reserved number is refused before any SMS, then recorded verified (the one written field).
  const sms = await call('kyc', jwt, { action: 'send_sms', phone: mobile });
  step('a fixture mobile is refused before any SMS', sms.json?.ok !== true, String(sms.text).slice(0, 80));
  await write(`update public.leads set phone='${mobile}', owner_phone_verified=true where id=${lead.id}`, 'fixture mobile verified');
  await call('kyc', jwt, { action: 'whatsapp_choose', user_kind: 'supplier', email, opt: 'same' });

  // 4. The licence, as the form sends it: base64 plus page images (an image file is its own page; a PDF's pages are
  // rendered by the browser, and with none the server sends the file itself to the model).
  let viaBrowser = false;
  if (BROWSER && c.licence.file) {
    const who = { kind: 'supplier', email, newSession: async () => s };
    const b = await browserLicence(c, who, c.id); out.browser = b;
    viaBrowser = b.reached;
    step('the portal form takes the licence in a real browser', b.reached && b.answered && !b.hung, `reached=${b.reached} answered=${b.answered} hung=${b.hung} ${b.ms} ms ${b.error || ''} url=${b.url} page=${b.page_text} ${String(b.response).slice(0, 300)}`);
    step('what the supplier sees after the read', true, `${b.sees} | alerts: ${JSON.stringify(b.alerts)}`);
    out.licence_response = b.response;
    if (c.id === 't_blank_pdf') step('an unreadable licence says it could not be read and offers Replace', b.unread_badge === true, `badge+instruction on the card: ${b.unread_badge}`);
  }
  if (!viaBrowser) {
    const lb = b64(c.licence.file);
    const images = /^image\//.test(c.licence.mime) ? [{ mime: c.licence.mime, data: lb }] : [];
    const t0 = Date.now();
    const lic = await call('supplier_api', jwt, { action: 'process_docs', license: { original_b64: lb, file_b64: lb, images, filename: c.licence.name, mime: c.licence.mime } }, 200000);
    out.licence_response = lic.json?.extracted ?? lic.text?.slice(0, 200);
    step('process_docs takes the licence (API; the form was not reached)', lic.status === 200 && lic.json?.ok === true, `HTTP ${lic.status} in ${Date.now() - t0} ms${lic.json?.extracted?.license_error ? ' license_error=' + lic.json.extracted.license_error : ''}`);
  }

  // 5. The company profile, as the form sends it: straight to storage on a signed URL, then named by path.
  const up = await call('supplier_api', jwt, { action: 'upload_url', kind: 'profile', filename: c.profile.name, mime: c.profile.mime });
  let profBody = null;
  if (up.json?.ok) {
    const put = await fetch(`${BASE}/storage/v1/object/upload/sign/supplier-docs/${up.json.path}?token=${up.json.token}`, { method: 'PUT', headers: { 'Content-Type': c.profile.mime, 'x-upsert': 'true' }, body: readFileSync(c.profile.file) });
    step('the profile uploads straight to storage', put.ok, `HTTP ${put.status}`);
    profBody = { path: up.json.path, filename: c.profile.name, mime: c.profile.mime };
    run.ids.storage.push('supplier-docs/' + up.json.path);
  } else step('the profile upload is prepared', false, up.text?.slice(0, 160));
  const pr = await call('supplier_api', jwt, { action: 'process_docs', company_profile: profBody, catalogs: [] }, 120000);
  step('process_docs takes the profile', pr.status === 200 && pr.json?.ok === true, `HTTP ${pr.status}`);

  // 6. Terms + Save, then the certificate, as the form does.
  const payload = { action: 'save_profile', service_emirates: ['Dubai'], accept_terms: true, marketing_consent: false, contact_name: 'ZZ DEMO Contact', signatory_name: 'ZZ DEMO Signatory' };
  let sv = await call('supplier_api', jwt, payload, 60000);
  await call('kyc', jwt, { action: 'accept_terms' }, 60000).catch(() => null);
  step('save_profile answers (a held decision is saved too)', (sv.status === 200 && sv.json?.ok === true) || (sv.json?.saved === true && c.want.status !== 'approved'), `HTTP ${sv.status} ${String(sv.text).slice(0, 120)}`);

  // 7. Wait for the reads and the certificate to land, then judge from the row.
  const t1 = Date.now(); let row;
  const rowSql = `select l.approval_status status, l.licence_gate_reason reason, l.verified, l.signed_terms_path is not null signed, l.signed_terms_path stp, l.accepted_terms_ip ip, to_char(l.accepted_terms_at at time zone 'UTC','YYYY-MM-DD HH24:MI:SS') acc_utc, l.registration_submitted_at is not null submitted,
        l.trade_license_no licence_no, l.licence_legal_name name, l.license_authority authority, l.license_expiry::text expiry, l.doc_extracted_at is not null extracted, l.company_name, l.sector,
        c.source_docs -> 'docs' docs, c.proposed_trades, (select count(*)::int from public.agent_actions a where a.kind='supplier_verification' and a.target_id=l.id::text) decisions
       from public.leads l left join public.supplier_capabilities c on c.supplier_id = l.id where l.id=${lead.id}`;
  for (;;) {
    row = (await read(rowSql))[0];
    const reading = (row.docs || []).some((d) => d.status === 'reading');
    // settled = certificate signed, nothing still being read, and the gate is no longer waiting on a read or on the terms
    if ((row.signed && !reading && row.reason !== 'documents_being_read' && row.reason !== 'reg_terms') || Date.now() - t1 > 240000) break;
    await sleep(5000);
  }
  // LEDGER 1469 (2 Nov 2026): a supplier is verified only after it confirms its services. Terms + Save complete the registration and hold
  // an otherwise-clean one at pending/services_unconfirmed; the supplier's own confirm (supplier_api capability_confirm, the writer the
  // Services tab uses) releases the approval. Every read assertion below is unchanged and judges the row after the release.
  if (c.want.status === 'approved') {
    step('ledger 1469: before the supplier confirms its services it is held (pending / services_unconfirmed)', row.status === 'pending' && row.reason === 'services_unconfirmed', `got ${row.status} / ${row.reason}`);
    const pick = (await read(`select s.trade_code, s.trade_code || '.' || s.code as k, (select code from public.taxonomy_role where active order by sort limit 1) as role from public.taxonomy_trade_service s where s.active order by s.trade_code, s.sort limit 1`))[0];
    // retried on a platform blip (502/503/504/546), never on a refusal
    let cc;
    for (let k = 0; k < 3; k++) { cc = await call('supplier_api', jwt, { action: 'capability_confirm', trades: [pick.trade_code], roles: [pick.role], services: [pick.k] }, 60000); if (![0, 502, 503, 504, 546].includes(cc.status)) break; await sleep(3000); }
    step('ledger 1469: the supplier confirms its services', cc.json?.ok === true, `HTTP ${cc.status} ${String(cc.text).slice(0, 120)}`);
    const t1b = Date.now();
    for (;;) { row = (await read(rowSql))[0]; if (row.status === 'approved' || Date.now() - t1b > 60000) break; await sleep(2000); }
  }
  out.row = row;
  // The certificate itself, read back from the signed-terms bucket: is the IP printed inside it? (ledger 1468)
  if (row.stp) {
    try {
      const { SERVICE } = await keys();
      const r = await fetch(`${BASE}/storage/v1/object/signed-terms/${row.stp}`, { headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}` } });
      const f = r.ok ? await pdfFactsFromBytes(new Uint8Array(await r.arrayBuffer())) : { ok: false, why: 'HTTP ' + r.status };
      const m = f.ok ? f.text.match(/IP address\s+(\d[\d.:a-f]*)/i) : null;
      const tm = f.ok ? f.text.match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC/) : null;
      out.certificate = { ok: f.ok, why: f.why, bytes: f.bytes?.length, ip_in_row: row.ip, ip_in_certificate: m?.[1] ?? null, ip_line: m?.[0] ?? null, time_in_row_utc: row.acc_utc, time_in_certificate: tm?.[0] ?? null, time_matches: !!tm && tm[0].startsWith(row.acc_utc) };
      run.ids.storage.push('signed-terms/' + row.stp);
    } catch (e) { out.certificate = { error: String(e.message).slice(0, 160) }; }
    step('the signed certificate prints the IP', !!out.certificate?.ip_in_certificate && out.certificate.time_matches === true, JSON.stringify(out.certificate));
  }
  step('terms: certificate signed, registration submitted', row.signed && row.submitted, `${Date.now() - t1} ms after Save`);
  step(`decision is ${c.want.status}${c.want.reason ? ' / ' + c.want.reason : ''}${c.observe ? ' (observed, not asserted)' : ''}`, c.observe || (row.status === c.want.status && (row.reason ?? null) === c.want.reason), `got ${row.status} / ${row.reason}`);
  for (const f of c.read || []) step(`the licence read wrote ${f}`, !!row[f], String(row[f]));
  if (c.read?.includes('licence_no') && c.licence.truth?.licence_no) step('the licence number is the printed one', row.licence_no === c.licence.truth.licence_no, `${row.licence_no} vs ${c.licence.truth.licence_no}`);
  if (c.read?.includes('expiry') && c.licence.truth?.expiry_date) step('the expiry is the printed one', row.expiry === c.licence.truth.expiry_date, `${row.expiry} vs ${c.licence.truth.expiry_date}`);
  if (c.read?.includes('name') && c.licence.truth?.legal_name_en) step('the company name read is the printed one', row.name === c.licence.truth.legal_name_en, `${row.name} vs ${c.licence.truth.legal_name_en} (registered as ${c.licence.registered})`);
  if (c.read?.includes('authority') && c.licence.truth?.authority) step('the authority read is the printed one', row.authority === c.licence.truth.authority, `${row.authority} vs ${c.licence.truth.authority}`);
  out.truth = c.licence.truth ? { licence_no: c.licence.truth.licence_no, name: c.licence.truth.legal_name_en, authority: c.licence.truth.authority, issue: c.licence.truth.issue_date, expiry: c.licence.truth.expiry_date } : null;
  // FOUNDER RULING 1176 (7 Oct 2026): a licence name that differs becomes the company name; the old name is kept in
  // history and the supplier is told, in English, instead of any hold or rejection for the name alone.
  if (c.nameFromLicence) {
    step('1176: the licence name became the company name', row.company_name === c.licence.truth.legal_name_en, `${row.company_name} (registered as ${c.licence.registered})`);
    const hist = await read(`select detail->>'previous_name' prev, detail->>'new_name' nw from public.agent_actions where kind='supplier_name_from_licence' and target_table='leads' and target_id='${lead.id}'`);
    step('1176: the old name is kept in history (agent_actions supplier_name_from_licence)', hist.length === 1 && hist[0].prev === c.licence.registered && hist[0].nw === c.licence.truth.legal_name_en, JSON.stringify(hist));
    const told = await read(`select to_jsonb(n)::text j from public.notifications n where lead_id=${lead.id} and type='company_name_from_licence' and channel='email'`);
    const tj = told[0]?.j || '';
    step('1176: the supplier is told by e-mail, in English, with both names', told.length === 1 && /updated to match your trade licence/.test(tj) && tj.includes(c.licence.registered) && tj.includes(c.licence.truth.legal_name_en) && !/[؀-ۿ]/.test(tj), tj.slice(0, 260));
  }
  if (c.read?.length) {
    const iss = await read(`select license_issue_date::text d from public.leads where id=${lead.id}`).then((x) => x[0]?.d ?? null).catch(() => 'COLUMN_ABSENT');
    out.issue = iss;
    if (c.licence.truth?.issue_date) step('the issue date is read and kept', iss === c.licence.truth.issue_date, `${iss} vs ${c.licence.truth.issue_date}${iss === 'COLUMN_ABSENT' ? ' (leads.license_issue_date is not live: pending SQL)' : ''}`);
  }
  if (c.read?.length) step('doc_extracted_at is stamped', row.extracted);
  for (const [kind, status] of Object.entries(c.doc || {})) {
    const rec = (row.docs || []).filter((d) => d.kind === kind);
    step(`source_docs holds the ${kind} record, status ${status}`, rec.some((d) => (status === 'read' ? d.status !== 'unreadable' && d.status !== 'reading' && d.status !== 'refused' : d.status === status)), JSON.stringify(rec.map((d) => ({ s: d.status, why: d.reason, trades: d.trades }))).slice(0, 240));
  }

  // 8. What the supplier sees, and what follows from the decision.
  const dash = await call('supplier_portal', jwt, { action: 'dashboard' });
  const card = dash.json?.supplier;
  step('the portal shows the stage', card?.approval_status === row.status && (card?.licence_gate_reason ?? null) === (row.reason ?? null), JSON.stringify({ s: card?.approval_status, r: card?.licence_gate_reason, due: card?.exception_due_at }));
  if (BROWSER && c.nameFromLicence) {
    const who = { kind: 'supplier', email, newSession: async () => s };
    BR ||= await launch();
    const { ctx, page } = await signedInPage(BR, who, { lang: 'en', viewport: 'desktop' });
    let txt = '';
    try {
      await page.goto(`${SITE}/portal`, { waitUntil: 'domcontentloaded', timeout: 60000 });
      await page.locator('nav:visible, button[aria-controls="qd-nav-more"]:visible').first().waitFor({ timeout: 60000 });
      await page.waitForTimeout(1500);
      txt = (await page.locator('body').innerText()).replace(/\s+/g, ' ');
      await page.screenshot({ path: join(SHOTS, `${c.id}_after_rename.png`), fullPage: true }).catch(() => {});
    } catch (e) { txt = 'ERR ' + e.message; }
    await ctx.close().catch(() => {});
    step('1176: on screen the supplier sees the licence name as the company name', txt.includes(c.licence.truth.legal_name_en) && !txt.includes(c.licence.registered), txt.includes(c.licence.registered) ? 'old name still on screen' : (txt.includes(c.licence.truth.legal_name_en) ? 'new name on screen' : txt.slice(0, 200)));
  }
  out.card = { s: card?.approval_status, r: card?.licence_gate_reason, due: card?.exception_due_at };
  out.eligibility = dash.json?.eligibility ? { eligible: dash.json.eligibility.eligible, blocking: dash.json.eligibility.blocking?.map((b) => b.code) } : null;
  await sleep(3000);
  const nt = await read(`select type, channel, status, subject from public.notifications where lead_id=${lead.id} order by id`);
  out.notices = nt.map((x) => `${x.type}/${x.channel}/${x.status}: ${x.subject}`);
  const real = nt.filter((x) => x.status !== 'suppressed');
  // A type written twice on ONE channel would be a duplicate mail; one per channel (email + in-app/WhatsApp) is the designed pair.
  const perChannel = {}; for (const x of nt) perChannel[`${x.type}/${x.channel}`] = (perChannel[`${x.type}/${x.channel}`] || 0) + 1;
  step('no notice is written twice on the same channel (no duplicate mail)', Object.values(perChannel).every((k) => k === 1), JSON.stringify(out.notices));
  step('every notice is suppressed, none sent', real.length === 0, JSON.stringify(real).slice(0, 200));
  if (c.want.status === 'approved') {
    step('the approval notice is written', nt.some((x) => x.type === 'supplier_approved' && x.channel === 'email'), JSON.stringify(nt.map((x) => x.type)));
    // A fixture confirms no services and has no catalogue, so these two always block a demo supplier; anything else blocking is a real finding.
    const FIXTURE_ONLY = new Set(['scope_unconfirmed', 'undiscoverable']);
    step('an approved supplier has no blocker but the fixture own unconfirmed scope', (out.eligibility?.blocking || []).every((b) => FIXTURE_ONLY.has(b)), JSON.stringify(out.eligibility));
  } else {
    step('a held supplier is told why', nt.length > 0, JSON.stringify(nt.map((x) => x.subject)).slice(0, 240));
    step('a held supplier is never approved or verified', row.verified !== true);
  }
  return out;
}

const run = await openRun({ capUsd: 5, minutes: 60 });
try {
  const queue = CASES.map((c, i) => [c, run.seq++ + i]);
  await Promise.all(Array.from({ length: Math.max(1, CONC) }, async () => {
    for (let job = queue.shift(); job; job = queue.shift()) {
      try { results.push(await walk(run, job[0], job[1])); }
      catch (e) { console.error('LEG ERROR', job[0].id, String(e?.stack || e).slice(0, 400)); results.push({ id: job[0].id, ok: false, error: String(e?.message || e) }); }
    }
  }));
  const spend = await read(`select coalesce(sum(cost_usd_reported),0)::numeric(10,4) usd, count(*)::int calls from public.ai_cost_log where e2e_run_tag = '${run.tag}'`).catch((e) => [{ error: String(e.message).slice(0, 120) }]);
  console.log('model spend', JSON.stringify(spend[0]));
} finally {
  // Is Dropbox ready? (read-only ping of the archive function; ledger 1468)
  try { const { ANON } = await keys(); const pg = await call('compliance_archive', ANON, { action: 'ping', __secret: await internalCred() }, 30000); console.log('compliance_archive ping', pg.status, String(pg.text).slice(0, 160)); } catch (e) { console.log('compliance_archive ping failed', String(e.message).slice(0, 160)); }
  await BR?.close().catch(() => {});
  const c = await closeRun(run, { keep: KEEP });
  console.log('teardown:', JSON.stringify(c.leftovers || 'kept'));
}
if (JSON_OUT) writeFileSync(JSON_OUT, JSON.stringify(results, null, 1));
for (const r of results) console.log(`${r.ok ? 'CASE PASS' : 'CASE FAIL'} ${r.id}${r.row ? ` -> ${r.row.status}/${r.row.reason} no=${r.row.licence_no} name=${r.row.name} auth=${r.row.authority} exp=${r.row.expiry}` : ''}`);
const failed = results.filter((r) => !r.ok);
console.log(`${results.length - failed.length}/${results.length} cases passed`);
process.exit(failed.length ? 1 : 0);
