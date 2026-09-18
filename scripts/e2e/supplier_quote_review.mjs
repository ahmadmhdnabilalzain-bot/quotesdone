// scripts/e2e/supplier_quote_review.mjs — Inquiries received and the quotation review, end to end.
// Assigned: sales_engineer (founder, 15 Sep 2026: "this is the most important part in the whole
// supplier portal, so make sure its built perfectly").
//
// One ZZ DEMO customer, one ZZ DEMO supplier, two painting jobs matched to the supplier (one driven in
// English, one in Arabic), each with a redacted drawing page and a two-line BOQ. For each job, in the
// real portal: open the inquiry by its job number, download the BOQ and a drawing, send an INCOMPLETE
// quotation to the sales engineer (the review lists what is missing), answer one point in text, send
// the COMPLETE quotation (approved for submission), choose "generate", and see it submitted — then
// check the database has the submitted quote. Screenshots of every step, both languages. Teardown
// removes everything; the run fails unless the leftover count is 0.
//
//   node scripts/e2e/supplier_quote_review.mjs
//   QD_SITE=http://localhost:3137 node scripts/e2e/supplier_quote_review.mjs         a local build
//   QD_REVIEW_API=http://localhost:8787 …                                              PRE-DEPLOY: the review
//      actions are answered by a stand-in serving the same code over memory; inbox and submit_quote are production's
//   QD_SHOTS=<dir>                                                                     where screenshots go
//
// Nothing here can reach a real person: every identity is ZZ DEMO / @example.invalid (fixtures.mjs), and
// demo notices are captured, never sent. Check no post-deploy smoke is running before a manual run.
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { deflateSync, crc32 } from 'node:zlib';
import { openRun, closeRun, makeDemoCustomer, makeDemoSupplier, read, write } from './fixtures.mjs';
import { makeInquiry, uploadObject, q } from '../staging/demo_factory.mjs';
import { launch, signedInPage, openPortal, portalUrl, realErrors, SITE } from './browser.mjs';

const SHOTS = process.env.QD_SHOTS || join(tmpdir(), 'qd-quote-review');
let REVIEW_API = process.env.QD_REVIEW_API || '';
/** QD_REVIEW_STANDIN=1 starts review_server.ts here, so a pre-deploy run needs no second terminal. */
const STANDIN = process.env.QD_REVIEW_STANDIN === '1' && !REVIEW_API;
const VIEWPORTS = (process.env.QD_VIEWPORTS || 'desktop,mobile').split(',').map((s) => s.trim()).filter(Boolean);
const FN_URL = 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/supplier_api';
const REVIEW_ACTIONS = ['inquiries_list', 'inquiry_detail', 'inquiry_documents', 'review_thread', 'review_start', 'review_message', 'review_upload', 'review_choose', 'review_submit'];
mkdirSync(SHOTS, { recursive: true });
const report = { site: SITE, review_api: REVIEW_API || 'production', steps: [], shots: [] };
const step = (name, ok, detail = '') => { report.steps.push({ name, ok, detail }); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ' — ' + detail : ''}`); };

/** A small drawing page as a PNG: a white sheet with a plan outline, no text. */
function drawingPng(w = 480, h = 340) {
  const px = Buffer.alloc((w * 3 + 1) * h, 255);
  const dot = (x, y) => { const o = y * (w * 3 + 1) + 1 + x * 3; px[o] = 30; px[o + 1] = 60; px[o + 2] = 90; };
  for (let x = 40; x < w - 40; x++) { dot(x, 40); dot(x, h - 40); dot(x, 170); }
  for (let y = 40; y < h - 40; y++) { dot(40, y); dot(w - 40, y); dot(250, y); }
  for (let y = 0; y < h; y++) px[y * (w * 3 + 1)] = 0;
  const chunk = (type, data) => { const len = Buffer.alloc(4); len.writeUInt32BE(data.length); const td = Buffer.concat([Buffer.from(type), data]); const c = Buffer.alloc(4); c.writeUInt32BE(crc32(td) >>> 0); return Buffer.concat([len, td, c]); };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', ihdr), chunk('IDAT', deflateSync(px)), chunk('IEND', Buffer.alloc(0))]);
}
const BOQ = { boq: [
  { section: 'Internal walls', description: 'Internal wall painting emulsion', qty: 450, unit: 'm2', confidence: 'high' },
  { section: 'Ceilings', description: 'Ceiling painting emulsion', qty: 120, unit: 'm2', confidence: 'medium' },
] };
const REQUIREMENTS = { customer_requirements: { version: 1, installation: { required: 'no' }, warranty: { required: 'yes' } } };
const INCOMPLETE = 'Description,Qty,Unit,Rate,Amount\nJotun Fenomastic emulsion 2 coats internal walls,450,m2,20,9000\nTotal,,,,9000\n';
const COMPLETE = 'Description,Qty,Unit,Rate,Amount\nJotun Fenomastic emulsion 2 coats internal walls,450,m2,20,9000\nJotun Fenomastic emulsion 2 coats ceiling painting,120,m2,18,2160\nTotal,,,,11160\n'
  + 'Validity: 30 days\nLead time: 3 weeks\nWarranty: 2 years materials and workmanship\nPrices exclude VAT\n';

async function job(run, customer, supplier, lang) {
  const inq = await makeInquiry(run, { customer, trade: 'painting', status: 'sent', rfqReady: false, emirate: 'Dubai', locale: lang });
  run.ids.inquiries.add(inq.id);
  const page = `drawings/redacted/${run.tag}/${inq.id}_p1.png`;
  await uploadObject('drawing-files', page, drawingPng(), 'image/png');
  run.ids.storage.push(`drawing-files/${page}`);
  await write(`update public.inquiries set boq = ${q(JSON.stringify(BOQ))}::jsonb, boq_confidence = 'high',
      spec = coalesce(spec, '{}'::jsonb) || ${q(JSON.stringify(REQUIREMENTS))}::jsonb, drawing_redacted_paths = array[${q(page)}]
    where id = ${q(inq.id)}`, 'e2e quote review inquiry');
  await write(`insert into public.inquiry_matches (inquiry_id, supplier_id, match_reason) values (${q(inq.id)}, ${Number(supplier.leadId)}, 'e2e: quotation review') on conflict do nothing`, 'e2e match');
  return inq.id;
}

async function drive(browser, run, supplier, inquiryId, lang, viewport) {
  const ar = lang === 'ar';
  const job = String(inquiryId).slice(0, 8).toUpperCase();
  const L = (en, a) => (ar ? a : en);
  const { ctx, page, consoleErrors, calls } = await signedInPage(browser, supplier, { lang, viewport });
  if (REVIEW_API) {
    // PRE-DEPLOY: the new actions go to the stand-in; everything else stays on production.
    const hop = async (route) => {
      const req = route.request();
      if (req.method() === 'OPTIONS') return route.fulfill({ status: 200, headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': 'authorization, content-type, apikey, x-client-info', 'access-control-allow-methods': 'POST, OPTIONS' }, body: 'ok' });
      let action = null; try { action = JSON.parse(req.postData() || '{}').action; } catch { /* */ }
      if (!REVIEW_ACTIONS.includes(action)) return route.fallback();
      const r = await fetch(REVIEW_API, { method: 'POST', headers: { authorization: req.headers()['authorization'] || '', 'content-type': 'application/json' }, body: req.postData() });
      return route.fulfill({ status: r.status, headers: { 'access-control-allow-origin': '*', 'content-type': 'application/json' }, body: Buffer.from(await r.arrayBuffer()) });
    };
    await ctx.route(FN_URL, hop);
    await ctx.route(`${new URL(SITE).origin}/functions/v1/supplier_api`, hop);
  }
  const shot = async (name) => { const f = join(SHOTS, `${lang}_${viewport}_${name}.png`); await page.screenshot({ path: f, fullPage: true }); report.shots.push(f); };
  const name = (s) => `${lang}/${viewport}: ${s}`;
  try {
    await openPortal(page, portalUrl('supplier', lang), calls);
    // THE SUPPLIER'S REGISTERED LANGUAGE WINS ONCE SIGNED IN (founder, 14 Sep 2026), so /ar/portal
    // does NOT put a supplier registered in English into Arabic — leads.locale does. The Arabic
    // journey therefore switches the way a supplier switches: the header's own language button,
    // which calls save_settings. It stays switched for the journeys that follow.
    if (ar) {
      const toggle = page.getByRole('button', { name: 'عربي', exact: true }).first();
      if (await toggle.isVisible().catch(() => false)) await toggle.click();
      await page.getByRole('button', { name: /الاستفسارات الواردة/ }).first().waitFor({ timeout: 30000 });
    }
    await page.getByRole('button', { name: new RegExp(L('Inquiries received', 'الاستفسارات الواردة')) }).first().click();
    const row = page.locator(`#qd-inq-${inquiryId} > button`);
    await row.waitFor({ timeout: 30000 });
    step(name(`inquiry listed by job number ${job}`), (await row.innerText()).includes(job));
    await shot('01_inquiries_received');
    await row.click();
    const detail = page.locator(`#qd-inq-d-${inquiryId}`);
    await detail.getByText(job).first().waitFor({ timeout: 30000 });
    await detail.getByText(L('Bill of quantities (2 lines, CSV)', 'جدول الكميات (2 بندًا، CSV)')).waitFor({ timeout: 30000 });
    await shot('02_inquiry_detail');
    // Downloads: the BOQ as a file, and the redacted drawing page by its signed URL.
    const [dl] = await Promise.all([page.waitForEvent('download', { timeout: 20000 }), detail.getByRole('button', { name: L('Download', 'تنزيل') }).first().click()]);
    const boqFile = join(SHOTS, `${lang}_${dl.suggestedFilename()}`); await dl.saveAs(boqFile);
    const csv = readFileSync(boqFile, 'utf8');
    step(name('BOQ downloads as a CSV with both lines'), /Internal wall painting emulsion/.test(csv) && /Ceiling painting emulsion/.test(csv), dl.suggestedFilename());
    const href = await detail.locator('a[download]').first().getAttribute('href');
    const img = href ? await fetch(href) : null;
    step(name('redacted drawing downloads by signed URL'), !!img && img.ok && /image\/png/.test(img.headers.get('content-type') || ''), href ? new URL(href).pathname.split('/').slice(-2).join('/') : 'no link');
    step(name('no customer identity on the inquiry'), !(await detail.innerText()).includes('ZZ DEMO Customer'));

    await detail.getByRole('button', { name: L('Send your quotation to the sales engineer', 'أرسل عرض سعرك إلى مهندس المبيعات') }).click();
    const chat = page.locator(`#qd-qt-c-${inquiryId}`);
    await chat.getByText(L('I am the QuotesDone sales engineer', 'أنا مهندس المبيعات')).waitFor({ timeout: 30000 });
    await shot('03_chat_opened');

    const incompletePath = join(SHOTS, `quote_incomplete_${run.tag}_${lang}.csv`); writeFileSync(incompletePath, INCOMPLETE);
    await page.setInputFiles(`#qd-rv-file-${inquiryId}`, incompletePath);
    const reviewing = await chat.getByText(L('Reviewing your quotation, please wait…', 'جارٍ مراجعة عرض سعرك، يُرجى الانتظار…')).waitFor({ timeout: 5000 }).then(() => true).catch(() => false);
    if (reviewing) await shot('04_reviewing');
    step(name('"Reviewing your quotation, please wait…" is shown'), reviewing);
    await chat.getByText(L('Before it can be submitted', 'قبل تقديمه')).first().waitFor({ timeout: 60000 });
    const t1 = await chat.innerText();
    step(name('incomplete quotation: the engineer lists what is missing'), [L('BOQ line 2', 'البند 2 من جدول الكميات'), L('valid', 'صلاحية'), L('VAT', 'الضريبة')].every((s) => t1.includes(s)));
    await shot('05_review_comments');

    await page.fill(`#qd-rv-${inquiryId}`, L('validity 30 days', 'الصلاحية 30 يومًا'));
    await chat.getByRole('button', { name: L('Send', 'إرسال'), exact: true }).click();
    await chat.getByText(L('Thank you — noted: validity 30 days', 'شكرًا — سجّلت: الصلاحية 30')).first().waitFor({ timeout: 30000 });
    step(name('a text reply closes its point'), true);
    await shot('06_reply_answered');

    const completePath = join(SHOTS, `quote_complete_${run.tag}_${lang}.csv`); writeFileSync(completePath, COMPLETE);
    await page.setInputFiles(`#qd-rv-file-${inquiryId}`, completePath);
    await chat.getByText(L('Quotation approved for submission.', 'تمت الموافقة على عرض السعر للتقديم.')).first().waitFor({ timeout: 60000 });
    step(name('complete quotation: "Quotation approved for submission"'), true);
    await shot('07_approved_choice');

    await chat.getByRole('button', { name: L('Generate it for me', 'أعدّه لي') }).click();
    await chat.getByText(L('Submitted to the job.', 'قُدّم العرض إلى الطلب.')).first().waitFor({ timeout: 90000 });
    await shot('08_submitted');
    const qs = await read(`select id, status, quote_amount, source from public.quotes where inquiry_id = ${q(inquiryId)} and supplier_id = ${Number(supplier.leadId)}`);
    for (const r of qs) run.ids.quotes.add(r.id);
    step(name('submitted through submit_quote: the quote is with the customer'), qs.some((r) => r.status === 'submitted'), JSON.stringify(qs.map((r) => ({ status: r.status, amount: Number(r.quote_amount), source: r.source }))));
    const errs = realErrors(consoleErrors);
    step(name('no console errors'), errs.length === 0, errs.slice(0, 3).join(' | '));
  } catch (e) {
    await shot('zz_failure').catch(() => {});
    step(name('journey completed'), false, String(e.message).slice(0, 300));
  } finally {
    await ctx.close();
  }
}

const run = await openRun();
let result = null;
let standin = null;
try {
  if (STANDIN) {
    // The nine actions are served here by the same code over memory; everything else stays production's.
    const { keys } = await import('../staging/demo_factory.mjs');
    const { ANON } = await keys();
    const port = 8787 + (process.pid % 200);
    standin = spawn('deno', ['run', '--allow-net', '--allow-env', '--allow-read', 'scripts/e2e/review_server.ts'],
      { env: { ...process.env, PORT: String(port), QD_ANON_KEY: ANON }, stdio: ['ignore', 'pipe', 'pipe'] });
    standin.stdout.on('data', (d) => process.stdout.write('[standin] ' + d));
    standin.stderr.on('data', (d) => process.stdout.write('[standin] ' + d));
    REVIEW_API = `http://127.0.0.1:${port}`;
    for (let i = 0; i < 60; i++) {
      const up = await fetch(REVIEW_API, { method: 'OPTIONS' }).then((r) => r.ok).catch(() => false);
      if (up) break;
      if (i === 59) throw new Error('the review stand-in did not start');
      await new Promise((r) => setTimeout(r, 500));
    }
    report.review_api = REVIEW_API + ' (stand-in: memory conversation, production inbox and submit_quote)';
  }
  const customer = await makeDemoCustomer(run, { label: 'QuoteReview' });
  const supplier = await makeDemoSupplier(run, { label: 'QR' });
  // One job per journey: a conversation ends submitted, so each language and each viewport gets its own.
  const jobs = {};
  for (const lang of ['en', 'ar']) for (const vp of VIEWPORTS) jobs[`${lang}_${vp}`] = await job(run, customer, supplier, lang);
  const browser = await launch();
  try {
    for (const lang of ['en', 'ar']) for (const vp of VIEWPORTS) await drive(browser, run, supplier, jobs[`${lang}_${vp}`], lang, vp);
  } finally { await browser.close(); }
  // The standardised quotation PDFs quote_pdf printed for this supplier (folder supplier/<id>).
  const pdfs = await read(`select bucket_id b, name from storage.objects where name like ${q(`supplier/${Number(supplier.leadId)}/%`)}`);
  for (const o of pdfs) run.ids.storage.push(`${o.b}/${o.name}`);
  report.pdfs_printed = pdfs.length;
  const { keys, BASE } = await import('../staging/demo_factory.mjs');
  const { SERVICE } = await keys();
  for (const o of pdfs) await fetch(`${BASE}/storage/v1/object/${o.b}`, { method: 'DELETE', headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE, 'Content-Type': 'application/json' }, body: JSON.stringify({ prefixes: [o.name] }) });
} catch (e) {
  step('fixtures', false, String(e.message).slice(0, 300));
} finally {
  if (standin) { try { standin.kill(); } catch { /* the stand-in owns nothing to clean up */ } }
  result = await closeRun(run);
  report.teardown = result.removed?.summary; report.leftovers = result.leftovers;
  step('teardown leaves nothing behind', result.leftovers?.total === 0, JSON.stringify(result.leftovers));
}
writeFileSync(join(SHOTS, 'report.json'), JSON.stringify(report, null, 2));
console.log('\nscreenshots:', SHOTS);
process.exit(report.steps.every((s) => s.ok) ? 0 : 1);
