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
import { keys, verifyEmailByOtp, mkAuthUser } from '../lib/demo_factory.mjs';
import { buildCorpus, licenceTruth, licenceTextPdf, licenceSvg, picture, rawPdf, AUTHORITIES } from './document_intake_corpus.mjs';
import { demoPdfPages } from '../lib/demo_pdf.mjs';
import sharp from 'sharp';

const argv = process.argv.slice(2);
const val = (f, d) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : d; };
const ONLY = val('--case', '').split(',').filter(Boolean);
const CONC = Number(val('--concurrency', '3'));
const KEEP = argv.includes('--keep');
const JSON_OUT = val('--json', '');

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
].filter((c) => !ONLY.length || ONLY.includes(c.id));

const b64 = (p) => readFileSync(p).toString('base64');
const results = [];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

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
  const lb = b64(c.licence.file);
  const images = /^image\//.test(c.licence.mime) ? [{ mime: c.licence.mime, data: lb }] : [];
  const t0 = Date.now();
  const lic = await call('supplier_api', jwt, { action: 'process_docs', license: { original_b64: lb, file_b64: lb, images, filename: c.licence.name, mime: c.licence.mime } }, 200000);
  out.licence_response = lic.json?.extracted ?? lic.text?.slice(0, 200);
  step('process_docs takes the licence', lic.status === 200 && lic.json?.ok === true, `HTTP ${lic.status} in ${Date.now() - t0} ms${lic.json?.extracted?.license_error ? ' license_error=' + lic.json.extracted.license_error : ''}`);

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
  step('save_profile answers', sv.status === 200 && sv.json?.ok === true, `HTTP ${sv.status} ${String(sv.text).slice(0, 120)}`);

  // 7. Wait for the reads and the certificate to land, then judge from the row.
  const t1 = Date.now(); let row;
  for (;;) {
    row = (await read(`select l.approval_status status, l.licence_gate_reason reason, l.verified, l.signed_terms_path is not null signed, l.registration_submitted_at is not null submitted,
        l.trade_license_no licence_no, l.licence_legal_name name, l.license_authority authority, l.license_expiry::text expiry, l.doc_extracted_at is not null extracted, l.company_name, l.sector,
        c.source_docs -> 'docs' docs, c.proposed_trades, (select count(*)::int from public.agent_actions a where a.kind='supplier_verification' and a.target_id=l.id::text) decisions
       from public.leads l left join public.supplier_capabilities c on c.supplier_id = l.id where l.id=${lead.id}`))[0];
    const reading = (row.docs || []).some((d) => d.status === 'reading');
    if ((row.signed && !reading && row.status !== 'action_required') || (row.signed && !reading && row.reason !== 'reg_terms') || Date.now() - t1 > 240000) break;
    await sleep(5000);
  }
  out.row = row;
  step('terms: certificate signed, registration submitted', row.signed && row.submitted, `${Date.now() - t1} ms after Save`);
  step(`decision is ${c.want.status}${c.want.reason ? ' / ' + c.want.reason : ''}`, row.status === c.want.status && (row.reason ?? null) === c.want.reason, `got ${row.status} / ${row.reason}`);
  for (const f of c.read || []) step(`the licence read wrote ${f}`, !!row[f], String(row[f]));
  if (c.read?.includes('licence_no') && c.licence.truth?.licence_no) step('the licence number is the printed one', row.licence_no === c.licence.truth.licence_no, `${row.licence_no} vs ${c.licence.truth.licence_no}`);
  if (c.read?.includes('expiry') && c.licence.truth?.expiry_date) step('the expiry is the printed one', row.expiry === c.licence.truth.expiry_date, `${row.expiry} vs ${c.licence.truth.expiry_date}`);
  if (c.read?.length) step('doc_extracted_at is stamped', row.extracted);
  for (const [kind, status] of Object.entries(c.doc || {})) {
    const rec = (row.docs || []).filter((d) => d.kind === kind);
    step(`source_docs holds the ${kind} record, status ${status}`, rec.some((d) => (status === 'read' ? d.status !== 'unreadable' && d.status !== 'reading' && d.status !== 'refused' : d.status === status)), JSON.stringify(rec.map((d) => ({ s: d.status, why: d.reason, trades: d.trades }))).slice(0, 240));
  }

  // 8. What the supplier sees, and what follows from the decision.
  const dash = await call('supplier_portal', jwt, { action: 'dashboard' });
  const card = dash.json?.supplier;
  step('the portal shows the stage', card?.approval_status === row.status && (card?.licence_gate_reason ?? null) === (row.reason ?? null), JSON.stringify({ s: card?.approval_status, r: card?.licence_gate_reason, due: card?.exception_due_at }));
  out.eligibility = dash.json?.eligibility ? { eligible: dash.json.eligibility.eligible, blocking: dash.json.eligibility.blocking?.map((b) => b.code) } : null;
  await sleep(3000);
  const nt = await read(`select type, channel, status, subject from public.notifications where lead_id=${lead.id} order by id`);
  const real = nt.filter((x) => x.status !== 'suppressed');
  step('every notice is suppressed, none sent', real.length === 0, JSON.stringify(real).slice(0, 200));
  if (c.want.status === 'approved') {
    step('the approval notice is written', nt.some((x) => x.type === 'supplier_approved' && x.channel === 'email'), JSON.stringify(nt.map((x) => x.type)));
    step('an approved supplier is eligible for matching', dash.json?.eligibility?.eligible === true, JSON.stringify(out.eligibility));
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
  const spend = await read(`select coalesce(sum(cost_usd),0)::numeric(10,4) usd, count(*)::int calls from public.ai_cost_log where run_tag = 'qd_run:${run.tag}'`).catch((e) => [{ error: String(e.message).slice(0, 120) }]);
  console.log('model spend', JSON.stringify(spend[0]));
} finally {
  const c = await closeRun(run, { keep: KEEP });
  console.log('teardown:', JSON.stringify(c.leftovers || 'kept'));
}
if (JSON_OUT) writeFileSync(JSON_OUT, JSON.stringify(results, null, 1));
for (const r of results) console.log(`${r.ok ? 'CASE PASS' : 'CASE FAIL'} ${r.id}${r.row ? ` -> ${r.row.status}/${r.row.reason} no=${r.row.licence_no} name=${r.row.name} auth=${r.row.authority} exp=${r.row.expiry}` : ''}`);
const failed = results.filter((r) => !r.ok);
console.log(`${results.length - failed.length}/${results.length} cases passed`);
process.exit(failed.length ? 1 : 0);
