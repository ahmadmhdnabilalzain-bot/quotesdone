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
import { openRun, closeRun, makeDemoCustomer, makeDemoSupplier, read, write } from './fixtures.mjs';
import { makeInquiry, uploadObject, q } from '../lib/demo_factory.mjs';
import { demoOfficePlanPng } from '../lib/demo_pdf.mjs';
import { launch, signedInPage, openPortal, portalUrl, realErrors, fullPageShot, SITE } from './browser.mjs';

const SHOTS = process.env.QD_SHOTS || join(tmpdir(), 'qd-quote-review');
let REVIEW_API = process.env.QD_REVIEW_API || '';
/** QD_REVIEW_STANDIN=1 starts review_server.ts here, so a pre-deploy run needs no second terminal. */
const STANDIN = process.env.QD_REVIEW_STANDIN === '1' && !REVIEW_API;
const VIEWPORTS = (process.env.QD_VIEWPORTS || 'desktop,mobile').split(',').map((s) => s.trim()).filter(Boolean);
// Suppliers are English only (founder ruling 1008, #1409): the Arabic passes waited 30 s for an Arabic nav the portal
// deliberately never renders (18 Oct, run 39079803518, ar/desktop and ar/mobile).
const SUPPLIER_LANGS = ['en'];
const FN_URL = 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/supplier_api';
const REVIEW_ACTIONS = ['inquiries_list', 'inquiry_detail', 'inquiry_documents', 'review_thread', 'review_start', 'review_message', 'review_upload', 'review_choose', 'review_submit'];
mkdirSync(SHOTS, { recursive: true });
const report = { site: SITE, review_api: REVIEW_API || 'production', steps: [], shots: [] };
const step = (name, ok, detail = '') => { report.steps.push({ name, ok, detail }); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ' — ' + detail : ''}`); };

// The redacted drawing page a supplier downloads. Until 21 Sep 2026 this was a local drawingPng():
// a white sheet with a plan outline and no text, so the founder-demo supplier saw four empty
// rectangles (audit 21 Sep, finding 3). The page is uploaded straight to drawings/redacted/ and
// drawing_redact never runs on it, so it must already BE the redacted page: the shared office plan
// (rooms, areas, dimensions, legend, north, scale) with its title block painted black.
const drawingPng = () => demoOfficePlanPng({ redactTitleBlock: true });
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
  // The supplier portal is English whatever the language (ruling 1008): `lang` only sets the browser locale.
  const ar = false;
  // The portal's job number is the RFQ number when the inquiry has one, else the id prefix
  // (_shared/quote_documents.ts jobNoOf, since #1364 on 13 Oct). This used the id prefix alone, so on
  // 17 Oct (run 39079803518) "listed by job number" failed and the detail wait timed out at 30 s.
  const rfq = (await read(`select rfq_no from public.inquiries where id = ${q(inquiryId)}`))[0]?.rfq_no;
  const job = rfq != null && String(rfq).trim() !== '' ? String(rfq) : String(inquiryId).slice(0, 8).toUpperCase();
  const L = (en) => en;
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
  // fullPageShot, not page.screenshot({ fullPage: true }): a fullPage capture taken while the page is
  // scrolled paints the sticky top bar at its stuck offset, in the middle of the picture, over the
  // content that happens to be there. That is what made the merged #725 captures look like a bar
  // "moving up and down when you scroll" (founder, 18 Sep 2026). See browser.mjs for the measurement.
  const shot = async (name) => { const f = join(SHOTS, `${lang}_${viewport}_${name}.png`); await fullPageShot(page, f); report.shots.push(f); };
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
    // THE TOP BAR STAYS AT THE TOP OF THE WINDOW, AND HIDES NOTHING (founder, 18 Sep 2026: it
    // "seems like it's moving up and down when you scroll down"). It is position:sticky top-0, so it
    // does not move for a supplier — only a fullPage capture ever moved it. Measured here so the
    // claim is a reading and not an opinion: at three scroll offsets the bar's top edge is 0, and a
    // job row scrolled to by job number lands BELOW the bar, never under it — which is carried by
    // `[id]{scroll-margin-top:92px}` in globals.css, 92px against a 57px bar.
    const bar = await page.evaluate(async (id) => {
      const frame = () => new Promise((r) => requestAnimationFrame(r));
      const h = document.querySelector('header.qd-topbar');
      // A renamed or removed bar must fail THIS step with its own message, not throw into the
      // journey's catch-all where it would read as an opaque exception.
      if (!h) return { tops: [], height: -1, rowTop: -1, missing: true };
      const tops = [];
      for (const y of [0, 400, 900]) { window.scrollTo(0, y); await frame(); await frame(); tops.push(Math.round(h.getBoundingClientRect().top)); }
      const height = Math.round(h.getBoundingClientRect().height);
      document.getElementById('qd-inq-' + id).scrollIntoView({ block: 'start' });
      await frame(); await frame();
      const rowTop = Math.round(document.getElementById('qd-inq-' + id).getBoundingClientRect().top);
      window.scrollTo(0, 0);
      return { tops, height, rowTop };
    }, inquiryId);
    step(name('the top bar stays at the top at every scroll offset, and covers nothing scrolled to'),
      !bar.missing && bar.tops.length === 3 && bar.tops.every((t) => t === 0) && bar.rowTop >= bar.height,
      `bar top at scroll 0/400/900 = ${bar.tops.join('/')}, bar height ${bar.height}, scrolled-to row top ${bar.rowTop}`);
    await row.click();
    const detail = page.locator(`#qd-inq-d-${inquiryId}`);
    await detail.getByText(job).first().waitFor({ timeout: 30000 });
    await detail.getByText(L('Bill of quantities (2 lines, CSV)', 'جدول الكميات (2 بندًا، CSV)')).waitFor({ timeout: 30000 });
    await shot('02_inquiry_detail');
    // Downloads: the BOQ as a file, and the redacted drawing page by its signed URL.
    // Each document is a row with its own four actions (instruction 524), drawing first, BOQ second; a
    // signed-URL download may land in a new tab, so the download is awaited on the page OR its popup.
    const docRow = (re) => detail.locator('li').filter({ hasText: re });
    const anyDownload = () => Promise.race([page.waitForEvent('download', { timeout: 20000 }),
      page.waitForEvent('popup', { timeout: 20000 }).then((pp) => pp.waitForEvent('download', { timeout: 20000 }))]);
    const [dl] = await Promise.all([anyDownload(), docRow(/Bill of quantities \(2 lines, CSV\)/, /Drawing page 1/).getByRole('button', { name: 'Download', exact: true }).click()]);
    const boqFile = join(SHOTS, `${lang}_${dl.suggestedFilename()}`); await dl.saveAs(boqFile);
    const csv = readFileSync(boqFile, 'utf8');
    step(name('BOQ downloads as a CSV with both lines'), /Internal wall painting emulsion/.test(csv) && /Ceiling painting emulsion/.test(csv), dl.suggestedFilename());
    const [dd] = await Promise.all([anyDownload(), docRow(/Drawing page 1 \(identity removed\)/, /Bill of quantities/).getByRole('button', { name: 'Download', exact: true }).click()]);
    const ddFile = join(SHOTS, `${lang}_${viewport}_${dd.suggestedFilename()}`); await dd.saveAs(ddFile);
    step(name('redacted drawing downloads'), readFileSync(ddFile).subarray(1, 4).toString() === 'PNG', dd.suggestedFilename());
    step(name('no customer identity on the inquiry'), !(await detail.innerText()).includes('ZZ DEMO Customer'));

    await detail.getByRole('button', { name: L('Send your quotation to the sales engineer', 'إرسال عرض السعر إلى مهندس المبيعات') }).click();
    const chat = page.locator(`#qd-qt-c-${inquiryId}`);
    // THE ENGINEER'S WORDS ARE THE MODEL'S (rulings 1195-1197, #1335 on 13 Oct 2026): every engineer bubble in this chat
    // is written by a model from what the review decided, so no sentence in it is fixed copy. #1566 (19 Oct) made this
    // wait for one wording ("Job N is open for your quotation") that the product never had on any branch — production's
    // greeting facts read "Hello — I am the QuotesDone sales engineer for Job N…" and the model rewrites even that — so the
    // journey timed out here on every run from 20 Oct (39349907536) to 3 Nov (41598217377). The waits below read only
    // what CODE puts on screen: the state badge (quoteReviewApi.ts REVIEW_STATE), the engineer's bubbles counted by
    // their label, the issue list (issue labels are code), the choice buttons and the submitted line; the points
    // themselves are read from quote_review_request. A model that does not answer is re-asked (_shared/reask.ts), hence
    // 90 s for a bubble.
    // prevented by: scripts/checks/the_quote_review_journeys_wait_only_for_what_code_puts_on_screen.test.mjs
    const badge = (s) => chat.locator('header').getByText(s, { exact: true });
    const engineer = chat.locator('ul[role="log"] > li').filter({ hasText: /^Sales engineer · / });
    const spoke = (n) => engineer.nth(n - 1).waitFor({ timeout: 90000 });
    const points = () => read(`select r.code, r.state from public.quote_review_request r join public.quote_reviews v on v.id = r.review_id
      where v.inquiry_id = ${q(inquiryId)} and v.supplier_id = ${Number(supplier.leadId)} and r.kind <> 'choice'`);
    await badge('Waiting for your file').waitFor({ timeout: 30000 });
    await spoke(1);
    const hello = (await engineer.first().innerText()).replace(/\s+/g, ' ');
    step(name('the review opens: the sales engineer writes first'), true, hello.slice(0, 160));
    step(name('the opening message names the job number'), hello.includes(job), `job ${job}`);
    await shot('03_chat_opened');

    const incompletePath = join(SHOTS, `quote_incomplete_${run.tag}_${lang}.csv`); writeFileSync(incompletePath, INCOMPLETE);
    await page.setInputFiles(`#qd-rv-file-${inquiryId}`, incompletePath);
    const reviewing = await chat.getByText(L('Reviewing your quotation, please wait…', 'جارٍ مراجعة عرض سعرك، يُرجى الانتظار…')).waitFor({ timeout: 5000 }).then(() => true).catch(() => false);
    if (reviewing) await shot('04_reviewing');
    step(name('"Reviewing your quotation, please wait…" is shown'), reviewing);
    await badge('Changes requested').waitFor({ timeout: 90000 });
    await spoke(2);
    const t1 = await chat.innerText();
    step(name('incomplete quotation: the engineer lists what is missing'), [L('BOQ line 2', 'البند 2 من جدول الكميات'), L('valid', 'صلاحية'), L('VAT', 'الضريبة')].every((s) => t1.includes(s)));
    await shot('05_review_comments');

    const p0 = await points();
    const said = await engineer.count();
    await page.fill(`#qd-rv-${inquiryId}`, L('validity 30 days', 'الصلاحية 30 يومًا'));
    await chat.getByRole('button', { name: L('Send', 'إرسال'), exact: true }).click();
    await spoke(said + 1);
    const p1 = await points();
    const openOf = (rows) => rows.filter((r) => r.state === 'open');
    const validity = p1.filter((r) => r.code === 'validity');
    step(name('a text reply closes its point'), p0.some((r) => r.code === 'validity' && r.state === 'open') && validity.length > 0 && validity.every((r) => r.state !== 'open') && openOf(p1).length === openOf(p0).length - 1,
      `open points ${openOf(p0).length} -> ${openOf(p1).length}; validity ${validity.map((r) => r.state).join(',') || 'never raised'}`);
    await shot('06_reply_answered');

    const completePath = join(SHOTS, `quote_complete_${run.tag}_${lang}.csv`); writeFileSync(completePath, COMPLETE);
    const said2 = await engineer.count();
    await page.setInputFiles(`#qd-rv-file-${inquiryId}`, completePath);
    await badge('Approved — your choice').waitFor({ timeout: 90000 });
    await spoke(said2 + 1);
    const p2 = await points();
    step(name('complete quotation: approved for submission, no point left open'), !openOf(p2).length, `open: ${openOf(p2).map((r) => r.code).join(', ') || 'none'}`);
    await shot('07_approved_choice');

    // "Generate it for me" PREVIEWS the standardised quotation and waits in ready_to_submit for the supplier's own Submit
    // (supplier_api quote_review_flow.ts decide, SP-F-07 since 22 Sep 2026: nothing goes out in the supplier's name
    // unseen). This journey pressed Generate and waited for "Submitted", which only Submit produces: branch run
    // 41623020490 timed out there on both devices once the earlier waits were fixed.
    const quoteRows = () => read(`select id, status, quote_amount, source from public.quotes where inquiry_id = ${q(inquiryId)} and supplier_id = ${Number(supplier.leadId)}`);
    const said3 = await engineer.count();
    await chat.getByRole('button', { name: L('Generate it for me', 'أعدّه لي') }).click();
    await badge('Approved — ready to submit').waitFor({ timeout: 90000 });
    await spoke(said3 + 1);
    step(name('Generate shows the quotation first and nothing is submitted before Submit'), (await quoteRows()).every((r) => r.status !== 'submitted'));
    await chat.getByRole('button', { name: `Submit to Job ${job}`, exact: true }).click();
    // Branch run 41636727579 timed out here with no artifact to say why: on a timeout the review row, the quotes and the
    // end of the chat are named in the failure, so the run says whether the submission was held, still running, or
    // submitted and not shown.
    await chat.getByText(L('Submitted to the job.', 'قُدّم العرض إلى الطلب.')).first().waitFor({ timeout: 120000 }).catch(async (e) => {
      const rv = await read(`select status, choice, reviewing_since from public.quote_reviews where inquiry_id = ${q(inquiryId)} and supplier_id = ${Number(supplier.leadId)}`).catch(() => []);
      const qrows = await quoteRows().catch(() => []);
      const tail = (await chat.innerText().catch(() => '')).replace(/\s+/g, ' ').slice(-400);
      throw new Error(`${String(e.message).split('\n')[0]} | review ${JSON.stringify(rv)} | quotes ${JSON.stringify(qrows.map((r) => r.status))} | chat ends: ${tail}`);
    });
    await shot('08_submitted');
    const qs = await quoteRows();
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
    const { keys } = await import('../lib/demo_factory.mjs');
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
  for (const lang of SUPPLIER_LANGS) for (const vp of VIEWPORTS) jobs[`${lang}_${vp}`] = await job(run, customer, supplier, lang);
  const browser = await launch();
  try {
    for (const lang of SUPPLIER_LANGS) for (const vp of VIEWPORTS) await drive(browser, run, supplier, jobs[`${lang}_${vp}`], lang, vp);
  } finally { await browser.close(); }
  // The standardised quotation PDFs quote_pdf printed for this supplier (folder supplier/<id>).
  const pdfs = await read(`select bucket_id b, name from storage.objects where name like ${q(`supplier/${Number(supplier.leadId)}/%`)}`);
  for (const o of pdfs) run.ids.storage.push(`${o.b}/${o.name}`);
  report.pdfs_printed = pdfs.length;
  const { keys, BASE } = await import('../lib/demo_factory.mjs');
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
