// scripts/e2e/journey_audit_buttons.mjs — journey h: press what the human audit of 21 Sep 2026 pressed.
// Seat: it_engineer. Founder, 21 Sep 2026: "i dont want things to pop up again for the same reasons".
//
// WHY THIS EXISTS. The browser audits of 21 Sep (customer portal, supplier portal) found defects no
// journey had ever reached: the star button answered HTTP 500 for months, "النسخة العربية" served the
// English quotation, Messages had no way to write after a reveal, a quotation PDF was read as "9 things
// needed", prices typed in the review chat were never matched, "Remove this trade" did not persist, a
// magic-link session stayed in the browser's history. Journeys a–g drive the funnel mostly through the
// API; these steps press the same controls the auditor pressed, in the portals, and read the result.
//
// OWNERS. fn_it_journey_ingest assigns a failed step to a seat by the FIRST LETTER of its journey
// label, so the labels below are chosen for the seat that owns the surface, not for this file's letter:
//   'c customer audit'   the customer portal, its PDFs, Messages, rating, sign-in   -> sales_engineer
//   'e customer documents' the reveal invoice and receipt                           -> accountant
//   'b supplier audit'   the supplier portal, the quotation review, Services, notices -> sales_engineer
//
// NOTHING REACHES A PERSON. Every identity is a run fixture (ZZ DEMO, @example.invalid, the reserved
// +971 50 000 00xx block); `demoOnly` refuses to act on any other. Messages and notices to a demo
// identity are captured by zzzz_notifications_demo_capture, and run.mjs asserts nothing was dispatched.
// A magic link is minted with the Auth admin API for a demo supplier: generate_link sends no e-mail.
import { writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { call, read, write } from './fixtures.mjs';
import { signedInPage, openPortal, portalUrl, shot, realErrors, SITE } from './browser.mjs';
import { makeInquiry, keys, BASE } from '../lib/demo_factory.mjs';
import { pdfFacts, isArabic, languageOf, sameDocument, moneyVerdict } from './pdf_facts.mjs';
import { modelHold } from './journeys.mjs';   // runtime use only, so the import cycle is safe

const HERE = dirname(fileURLToPath(import.meta.url));
const FIXTURE_PDF = join(HERE, '..', '..', 'supabase', 'functions', 'supplier_api', 'fixtures', 'ZZDEMO_quotation_D958E1EA.pdf');
const q = (v) => `'${String(v).replace(/'/g, "''")}'`;
const C = 'c customer audit', E = 'e customer documents', B = 'b supplier audit';
const OUR_TEMPLATE = 'QuotesDone pdf_native';   // supabase/functions/pdf_native/render.ts setCreator

/** Refuse to act on anything that is not a run fixture. */
function demoOnly(who) {
  if (!/@example\.invalid$/i.test(String(who?.email || ''))) throw new Error(`refused: ${who?.email} is not a demo identity on @example.invalid`);
  return who;
}

// ---- PDFs: bytes, template, language -----------------------------------------------------------
// "A real PDF on our template with the right language": %PDF- magic, the Creator pdf_native stamps,
// and the share of Arabic letters in the first pages' text. An Arabic document is mostly Arabic; an
// English one is mostly not (a company name or an address in Arabic is allowed). The reading lives in
// ./pdf_facts.mjs so a check can test it without this file's fixtures (and the token they read).
export { pdfFacts, isArabic, languageOf };
const pdfVerdict = (f, lang) => f.ok && f.creator === OUR_TEMPLATE && languageOf(f) === lang;
const pdfDetail = (f, lang) => (f.ok ? `creator="${f.creator}" pages=${f.pages} arabic=${Math.round(f.arabicShare * 100)}% (want ${lang})` : f.why);

// AN ARABIC CUSTOMER DOCUMENT HELD UNDER THE MODEL HOLD IS HELD, NOT FAILED (E2E stage 1 D4, 30 Sep 2026): the same
// rule journeys.mjs applies to the comparison — exactly HTTP 202 arabic_held, AND only while modelHold() says held.
async function heldArabic(lang, res) {
  return lang === 'ar' && res.status === 202 && res.json?.code === 'arabic_held' ? await modelHold() : null;
}
async function assertPdf(ctx, J, name, lang, res) {
  const url = res.json?.url || res.json?.pdf_url || res.json?.file_url;
  const f = await pdfFacts(url).catch((e) => ({ ok: false, why: String(e.message).slice(0, 120) }));
  const held = f.ok ? null : await heldArabic(lang, res);
  if (held) f.held = held;
  ctx.rep.step(J, name, pdfVerdict(f, lang) ? 'PASS' : held ? 'HELD' : 'FAIL',
    `HTTP ${res.status} ${pdfDetail(f, lang)}${f.ok ? '' : ' ' + String(res.text || '').slice(0, 120)}${held ? ' — model hold on (' + held + '); re-proven when it lifts' : ''}`);
  return f;
}

// Words that must never reach a customer's screen (audit items 22 and 24).
const DEV_TEXT = [/not served to the customer portal/i, /in what this page can read/i, /A numeric match score is not recorded/i, /Policy: default/i, /our chief executive refunds you/i];

// ================================================================================================
export async function journeyAuditButtons(ctx) {
  const stop = ctx.outOfTime || (() => false);
  await customerAudit(ctx);
  if (stop()) return ctx.rep.step(B, 'supplier audit not started', 'SKIP', 'the harness deadline passed');
  await supplierAudit(ctx);
}

// ---- the customer ------------------------------------------------------------------------------
async function customerAudit(ctx) {
  const { rep, browser, fx, dir } = ctx;
  const cust = demoOnly(fx.customer);
  const live = (ctx.quoteIds || []).filter((x) => x.status !== 'draft');

  // 1. THE QUOTATION IN BOTH LANGUAGES (audit item 4: "النسخة العربية" answered lang:"en", cached).
  if (live[0]) {
    const pdfs = {};
    for (const lang of ['en', 'ar']) pdfs[lang] = await assertPdf(ctx, C, `quotation PDF is ours and in ${lang}`, lang,
      await call('customer_api', cust.jwt, { action: 'quote_pdf', quote_id: live[0].id, lang }, 120000));
    // Two different documents, and the Arabic one in Arabic. sameDocument refuses an empty side
    // instead of calling it equal (pdf_facts.mjs: pdfjs used to detach the very bytes compared here).
    const d = sameDocument(pdfs.en, pdfs.ar);
    const langs = pdfs.en?.ok && pdfs.ar?.ok ? `en=${languageOf(pdfs.en)} ar=${languageOf(pdfs.ar)}` : 'one of the two did not open';
    rep.step(C, 'the Arabic quotation is not the English file',
      d.comparable && d.same === false && pdfs.ar.ok && languageOf(pdfs.ar) === 'ar' && languageOf(pdfs.en) === 'en' ? 'PASS' : pdfs.ar?.held ? 'HELD' : 'FAIL', `${d.why}; ${langs}`);
    // AND IT IS THE SAME QUOTATION (22 Sep 2026). Two different files in two languages is only half
    // the property the customer cares about: the Arabic version must quote the same money, line for
    // line, as the English one. Measured on production pair QD-8B287960-A - both renders read
    // 95.00 / 17,100.00 / 42.00 / 8,820.00 / 25,920.00 / 25,920.00 (pdf_facts.mjs amounts()).
    const m = moneyVerdict(pdfs.en, pdfs.ar);
    rep.step(C, 'the Arabic quotation states the same money as the English one', pdfs.ar?.held && m.status !== 'PASS' ? 'HELD' : m.status, m.why);
  } else rep.step(C, 'quotation PDF in both languages', 'SKIP', 'no live quote (journey b)');
  // 2. THE COMPARISON IN BOTH LANGUAGES (journey c proves %PDF-; this proves the template and the language).
  if (ctx.inquiryId) {
    for (const lang of ['en', 'ar']) {
      await write(`update public.customers set locale = ${q(lang)} where id = ${q(cust.customerId)} and is_demo and email like '%@example.invalid'`, 'e2e audit language');
      await assertPdf(ctx, C, `comparison PDF is ours and in ${lang}`, lang, await call('customer_api', cust.jwt, { action: 'compare_pdf', inquiry_id: ctx.inquiryId, lang }, 180000));
    }
    await write(`update public.customers set locale = 'en' where id = ${q(cust.customerId)} and is_demo and email like '%@example.invalid'`, 'e2e audit language');
  }

  // 3. AFTER THE REVEAL: rating, invoice, receipt, Messages. All need journey d's TEST payment.
  if (!ctx.paid || !ctx.paidQuote) {
    for (const n of ['rate a revealed supplier (stars, then a comment)', 'Messages after the reveal: write and send']) rep.step(C, n, 'SKIP', 'needs the paid reveal of journey d');
    rep.step(E, 'invoice and receipt PDFs, and the in-app button', 'SKIP', 'needs the paid reveal of journey d');
  } else await afterReveal(ctx, cust);

  // 4. SCREENS: Project room answers no 4xx (item 31), the theme switches on the first press (item 15),
  // a reload keeps the section (item 25), no developer text on any screen (items 22, 24).
  const s = await signedInPage(browser, cust, { lang: 'en', viewport: 'desktop' });
  const bad = [];
  s.page.on('response', (r) => { const u = r.url(); if (r.status() >= 400 && !/googletagmanager|google-analytics|clarity|facebook/.test(u)) bad.push(`${r.status()} ${u.split('?')[0].replace(/^https?:\/\/[^/]+/, '')}`); });
  try {
    await openPortal(s.page, portalUrl('customer', 'en'), s.calls);
    const osx = s.page.locator('.osx').first();
    const th0 = await osx.getAttribute('data-theme').catch(() => null);
    await s.page.getByRole('button', { name: /^(Light mode|Dark mode)$/ }).first().click({ timeout: 8000 }).catch(() => {});
    const th1 = await osx.getAttribute('data-theme').catch(() => null);
    rep.step(C, 'the theme switches on the first press', th0 && th1 && th0 !== th1 ? 'PASS' : 'FAIL', `data-theme ${th0} -> ${th1}`);
    const b0 = bad.length;
    const pr = await s.page.getByRole('button', { name: /^Project room/ }).first().click({ timeout: 10000 }).then(() => true).catch(() => false);
    await s.page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
    await s.page.waitForTimeout(2000);
    rep.step(C, 'Project room opens with no 4xx or 5xx', pr && bad.length === b0 ? 'PASS' : 'FAIL', pr ? (bad.slice(b0).join(', ') || 'every request answered < 400') : 'the Project room button could not be pressed', { shot: await shot(s.page, dir, 'h_project_room') });
    const docs = await s.page.getByRole('button', { name: /^Documents/ }).first().click({ timeout: 10000 }).then(() => true).catch(() => false);
    await s.page.waitForTimeout(1000);
    await s.page.reload({ waitUntil: 'domcontentloaded' });
    const kept = docs && await s.page.locator('button[aria-current="page"]:visible').filter({ hasText: /^Documents/ }).first().waitFor({ timeout: 20000 }).then(() => true).catch(() => false);
    rep.step(C, 'a reload stays on the section it was on', kept ? 'PASS' : 'FAIL', `url=${s.page.url().replace(SITE, '')}`);
    // Every destination's text, read once, for words a customer must never see.
    const seen = [];
    for (const label of ['Overview', 'My requests', 'Documents', 'Orders', 'Messages', 'Projects', 'Project room', 'What you may need next', 'Buying profile', 'Account']) {
      const ok = await s.page.getByRole('button', { name: new RegExp('^' + label) }).first().click({ timeout: 5000 }).then(() => true).catch(() => false);
      if (!ok) continue;
      await s.page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});
      const text = await s.page.locator('main').innerText().catch(() => '');
      for (const re of DEV_TEXT) if (re.test(text)) seen.push(`${label}: ${re.source}`);
    }
    rep.step(C, 'no developer text on any customer screen', seen.length ? 'FAIL' : 'PASS', seen.join(' | ') || `${DEV_TEXT.length} phrases checked on every destination`);
    ctx.consoleErrors.push(...realErrors(s.consoleErrors).map((e) => `[h customer] ${e}`));
  } finally { await s.ctx.close(); }

  // 5. A PROJECT BUDGET HAS A BOUND (item 16: AED 18,000,015,122,026 was stored).
  const big = await call('project_api', cust.jwt, { action: 'create', name: 'ZZ DEMO budget bound', budget_total: 18000015122026 });
  const stored = Number(big.json?.project?.budget_total ?? NaN);
  rep.step(C, 'an absurd project budget is refused', !big.json?.ok || !(stored > 1e11) ? 'PASS' : 'FAIL', `HTTP ${big.status} stored=${big.json?.project?.budget_total ?? '(none)'}`);

  // 6. SIGN-IN: a magic-link (URL-borne) session is REFUSED and leaves no token in history (item 29; CWE-384, 19 Oct 2026), and two roles in one browser
  // do not bounce each other (item 30).
  await signInAudit(ctx, cust, demoOnly(fx.suppliers[0]));
}

async function afterReveal(ctx, cust) {
  const { rep, browser, dir } = ctx;
  const qid = ctx.paidQuote;
  // Rating, through the API first: stars alone, then a short comment refused in words, never a 500.
  const shortC = await call('customer_api', cust.jwt, { action: 'rate_supplier', quote_id: qid, rating: 4, comment: 'ok!' });
  rep.step(C, 'a 3-character rating comment is refused readably, not with a 500', shortC.status === 400 ? 'PASS' : 'FAIL', `HTTP ${shortC.status} ${shortC.text.slice(0, 120)}`);
  const s = await signedInPage(browser, cust, { lang: 'en', viewport: 'desktop' });
  try {
    await openPortal(s.page, portalUrl('customer', 'en', `?request=${ctx.inquiryId}&quote=${qid}`), s.calls);
    await s.page.waitForTimeout(1500);
    // Stars only — the press the audit found answering 500 for months.
    const star = s.page.getByRole('button', { name: 'Rate 5 of 5' }).first();
    const [rr] = await Promise.all([
      s.page.waitForResponse((r) => r.url().includes('/functions/v1/customer_api') && (r.request().postData() || '').includes('rate_supplier'), { timeout: 30000 }).catch(() => null),
      star.click({ timeout: 15000 }).catch(() => {}),
    ]);
    rep.step(C, 'rate a revealed supplier: stars only', rr?.status() === 200 ? 'PASS' : 'FAIL', rr ? `HTTP ${rr.status()} ${(await rr.text().catch(() => '')).slice(0, 120)}` : 'no star to press, or no rate_supplier call', { shot: await shot(s.page, dir, 'h_rated') });
    const box = s.page.locator(`[id="rv-${qid}"]`);
    const hasBox = await box.waitFor({ state: 'visible', timeout: 10000 }).then(() => true).catch(() => false);
    let cr = null;
    if (hasBox) {
      await box.fill('ZZ DEMO harness: tidy work, on time.');
      [cr] = await Promise.all([
        s.page.waitForResponse((r) => r.url().includes('/functions/v1/customer_api') && (r.request().postData() || '').includes('rate_supplier'), { timeout: 30000 }).catch(() => null),
        s.page.getByRole('button', { name: 'Add comment' }).first().click({ timeout: 10000 }).catch(() => {}),
      ]);
    }
    rep.step(C, 'rate a revealed supplier: a 10+ character comment', cr?.status() === 200 ? 'PASS' : 'FAIL', hasBox ? `HTTP ${cr?.status() ?? 0}` : 'no comment box offered after the stars');
    const review = (await read(`select rating, comment from public.reviews r join public.transactions t on t.id = r.transaction_id where t.quote_id = ${q(qid)}`))[0];
    rep.step(C, 'database: the review holds the stars and the comment', review?.rating === 5 && /tidy work/.test(review?.comment || '') ? 'PASS' : 'FAIL', JSON.stringify(review || {}));

    // The invoice button used to open an EMPTY TAB (row 31 of the recurrence table). Pressed, and the
    // tab it opens must end on a PDF of ours.
    const [pop] = await Promise.all([
      s.page.waitForEvent('popup', { timeout: 20000 }).catch(() => null),
      s.page.getByRole('button', { name: /Invoice \(PDF\)/ }).first().click({ timeout: 10000 }).catch(() => {}),
    ]);
    // Headless Chromium has no PDF viewer: a tab pointed at a PDF DOWNLOADS it and its URL never
    // leaves about:blank. So the tab's first http(s) request is what the button sent it to.
    let popUrl = '';
    if (pop) popUrl = await pop.waitForEvent('request', { predicate: (r) => /^https?:/.test(r.url()), timeout: 60000 }).then((r) => r.url()).catch(() => pop.url());
    const pf = await pdfFacts(/^https?:/.test(popUrl) ? popUrl : null).catch((e) => ({ ok: false, why: e.message }));
    rep.step(E, 'the in-app "Invoice (PDF)" button opens our invoice, not an empty tab', pf.ok && pf.creator === OUR_TEMPLATE ? 'PASS' : 'FAIL',
      pop ? `tab ended on ${popUrl.split('?')[0].slice(0, 90) || '(blank)'}; ${pdfDetail(pf, 'en')}` : 'no tab opened');
    if (pop) await pop.close().catch(() => {});

    // Messages after the reveal: open the conversation and send (item 6: no compose control at all).
    const sup = ctx.fx.suppliers.find((x) => String(x.leadId) === String((ctx.quoteIds || []).find((r) => r.id === qid)?.supplier_id));
    await s.page.getByRole('button', { name: /^Messages/ }).first().click({ timeout: 10000 }).catch(() => {});
    await s.page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
    if (sup) await s.page.locator('main').getByText(sup.company, { exact: false }).first().click({ timeout: 8000 }).catch(() => {});
    const compose = s.page.locator('main textarea').first();
    const canWrite = await compose.waitFor({ state: 'visible', timeout: 15000 }).then(() => true).catch(() => false);
    let sent = null;
    if (canWrite) {
      await compose.fill('ZZ DEMO harness message after the reveal.');
      [sent] = await Promise.all([
        s.page.waitForResponse((r) => r.url().includes('/functions/v1/messages_api') && /"action":"(send|request_chat)"/.test(r.request().postData() || ''), { timeout: 30000 }).catch(() => null),
        s.page.locator('main').getByRole('button', { name: /^(Send|Ask)/ }).first().click({ timeout: 8000 }).catch(() => {}),
      ]);
    }
    const sj = sent ? await sent.json().catch(() => ({})) : {};
    rep.step(C, 'Messages after the reveal: write and send', sent?.status() === 200 && sj.ok !== false ? 'PASS' : 'FAIL',
      canWrite ? `HTTP ${sent?.status() ?? 0} ${JSON.stringify(sj).slice(0, 140)}` : `no text box in Messages${sup ? ` after opening ${sup.company}` : ''}`, { shot: await shot(s.page, dir, 'h_messages') });
    ctx.consoleErrors.push(...realErrors(s.consoleErrors).map((e) => `[h revealed] ${e}`));
  } finally { await s.ctx.close(); }

  // Invoice and receipt, both languages, through the endpoint the buttons call.
  for (const doc of ['invoice', 'receipt']) for (const lang of ['en', 'ar']) {
    await assertPdf(ctx, E, `${doc} PDF is ours and in ${lang}`, lang, await call('reveal_invoice', cust.jwt, { quote_id: qid, doc, lang }, 120000));
  }
}

async function signInAudit(ctx, cust, sup) {
  const { rep, browser, dir } = ctx;
  const s = await signedInPage(browser, cust, { lang: 'en', viewport: 'desktop' });
  try {
    await openPortal(s.page, portalUrl('customer', 'en'), s.calls);
    const { SERVICE } = await keys();
    const gl = await fetch(`${BASE}/auth/v1/admin/generate_link`, {
      method: 'POST', headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE, 'Content-Type': 'application/json' },
      body: JSON.stringify({ type: 'magiclink', email: sup.email, redirect_to: SITE + '/portal' }),
    }).then((r) => r.json()).catch(() => ({}));
    const link = gl.action_link || gl.properties?.action_link;
    if (!link) { rep.step(C, 'magic link: does NOT sign in (URL sessions are refused), and no session is left in history', 'SKIP', 'generate_link returned no link'); return; }
    // The supplier signs in by magic link in a SECOND TAB of the SAME browser.
    const p2 = await s.ctx.newPage();
    await p2.goto(link, { waitUntil: 'domcontentloaded', timeout: 60000 });
    const signedIn = await p2.locator('nav:visible, button[aria-controls="qd-nav-more"]:visible').first().waitFor({ timeout: 30000 }).then(() => true).catch(() => false);
    const hereNow = p2.url();
    await p2.goBack({ timeout: 10000 }).catch(() => {});
    const back = p2.url();
    const leaked = /access_token=|refresh_token=/.test(hereNow + back);
    // CWE-384 (19 Oct 2026): a URL session is never adopted, so the link must NOT sign in (no login fixation).
    rep.step(C, 'magic link: does NOT sign in (URL sessions are refused), and no session is left in the address bar or one Back press away', !signedIn && !leaked ? 'PASS' : 'FAIL',
      `signed in=${signedIn}; address bar ${/access_token=/.test(hereNow) ? 'HOLDS THE TOKEN' : 'clean'}; Back ${/access_token=/.test(back) ? 'SHOWS THE TOKEN URL' : 'clean'}`, { shot: await shot(p2, dir, 'h_magic_link') });
    await p2.close().catch(() => {});
    // The customer's tab must stay the customer's (item 30: "redirected the customer's /me tab to /portal").
    const navs = [];
    s.page.on('framenavigated', (f) => { if (f === s.page.mainFrame()) navs.push(f.url()); });
    await s.page.bringToFront().catch(() => {});
    await s.page.waitForTimeout(20000);
    const path = new URL(s.page.url()).pathname;
    rep.step(C, 'two roles in one browser: the customer tab stays on /me', /^\/(ar\/)?me\/?$/.test(path) ? 'PASS' : 'FAIL', `after 20 s the customer tab is on ${path}${navs.length ? '; navigated: ' + navs.map((u) => new URL(u).pathname).join(' -> ') : ''}`);
  } finally { await s.ctx.close(); }
}

// ---- the supplier ------------------------------------------------------------------------------
// The BOQ of the auditor's job D958E1EA (supabase/functions/supplier_api/fixtures/22_Job_D958E1EA_BOQ.csv),
// the job the fixture quotation PDF prices.
const GYPSUM_BOQ = { boq: [
  { section: 'Partitions', description: 'Gypsum board partition, 100mm metal stud, both faces', qty: 320, unit: 'm2', confidence: 'high' },
  { section: 'Ceilings', description: 'Suspended false ceiling, 600x600 mineral fibre tiles', qty: 410, unit: 'm2', confidence: 'high' },
  { section: 'Ceilings', description: 'Gypsum bulkhead, 300mm drop, painted finish', qty: 64, unit: 'm', confidence: 'high' },
] };
const REQ = { customer_requirements: { version: 1, installation: { required: 'yes' }, warranty: { required: 'yes' } } };
// What the fixture PDF genuinely does not say (supplier_api/quote_review.test.ts, "finding 1").
const GENUINELY_MISSING = ['installation_included|||installation_included', 'spec|1||thickness_mm', 'spec|3||board_type', 'warranty_coverage|||warranty_coverage', 'warranty_period|||warranty_period'];
// A quotation that names the three lines and every term, and prices only the first. (One with no
// price at all is refused outright — "I could not find a priced list" — so there is nothing for a
// typed price to answer; measured on the first run, 21 Sep 2026.)
const UNPRICED_CSV = 'Description,Qty,Unit,Rate,Amount\n'
  + 'Gypsum board partition 12.5mm board 100mm metal stud both faces,320,m2,95,30400\n'
  + 'Suspended false ceiling 600x600 mineral fibre tiles,410,m2,,\n'
  + 'Gypsum bulkhead standard gypsum board 300mm drop painted finish,64,m,,\n'
  + 'Validity: 30 days\nLead time: 4 weeks from LPO\nPrices exclude VAT\nInstallation included, 4 weeks on site\nWarranty: 2 years parts and labour\n';

async function gypsumJob(ctx, sup, contact) {
  const cust = ctx.fx.customer;
  // The customer's own contact details are written INTO the request text on purpose: the supplier must
  // never be served them (scrubbed by the inbox), in the portal or in the inquiry PDF.
  const inq = await makeInquiry(ctx.run, { customer: { customerId: cust.customerId, locale: 'en' }, trade: 'gypsum', status: 'sent', rfqReady: false, emirate: 'Dubai',
    summary: `Office fit-out partitions and ceilings. Call ${contact.phone} or e-mail ${contact.email}.` });
  ctx.run.ids.inquiries.add(String(inq.id));
  await write(`update public.inquiries set boq = ${q(JSON.stringify(GYPSUM_BOQ))}::jsonb, boq_confidence = 'high',
      spec = coalesce(spec, '{}'::jsonb) || ${q(JSON.stringify(REQ))}::jsonb
    where id = ${q(inq.id)} and public.fn_inquiry_is_demo(id)`, 'e2e audit gypsum job');
  await write(`insert into public.inquiry_matches (inquiry_id, supplier_id, match_reason) values (${q(inq.id)}, ${Number(sup.leadId)}, 'e2e audit: direct invitation') on conflict do nothing`, 'e2e audit match');
  return String(inq.id);
}

async function openJob(page, inquiryId) {
  await page.getByRole('button', { name: /^Inquiries received/ }).first().click({ timeout: 15000 });
  const row = page.locator(`#qd-inq-${inquiryId} > button`);
  await row.waitFor({ timeout: 30000 });
  const detail = page.locator(`#qd-inq-d-${inquiryId}`);
  // The row TOGGLES: pressing an open job closes it (the first run did exactly that).
  if (!(await detail.isVisible().catch(() => false))) await row.click();
  await detail.waitFor({ timeout: 30000 });
  return detail;
}
// The engineer's bubbles are the MODEL's words (rulings 1195-1197, #1335 on 13 Oct 2026), so these waits read what code
// puts on screen — the state badge (quoteReviewApi.ts REVIEW_STATE) and the engineer's bubbles counted by their label —
// never a sentence of the engineer's. The greeting wait on a fixed phrase timed out on every run from 14 Oct to 3 Nov.
// prevented by: scripts/checks/the_quote_review_journeys_wait_only_for_what_code_puts_on_screen.test.mjs
const reviewBadge = (chat, s) => chat.locator('header').getByText(s, { exact: true });
const engineerSaid = (chat) => chat.locator('ul[role="log"] > li').filter({ hasText: /^Sales engineer · / });
async function openReview(page, inquiryId) {
  const detail = await openJob(page, inquiryId);
  await detail.getByRole('button', { name: 'Send your quotation to the sales engineer' }).click({ timeout: 15000 });
  const chat = page.locator(`#qd-qt-c-${inquiryId}`);
  await reviewBadge(chat, 'Waiting for your file').waitFor({ timeout: 30000 });
  await engineerSaid(chat).first().waitFor({ timeout: 90000 });
  return chat;
}
/** The review of an uploaded file is in: the badge says changes are requested and the engineer has answered it. */
async function reviewed(chat, before) {
  await reviewBadge(chat, 'Changes requested').waitFor({ timeout: 90000 });
  await engineerSaid(chat).nth(before).waitFor({ timeout: 90000 });
}

async function supplierAudit(ctx) {
  const { rep, browser, fx, dir } = ctx;
  const sup = demoOnly(fx.suppliers[0]);
  const contact = demoOnly(fx.customer);
  await write(`update public.leads set locale = 'en' where id = ${Number(sup.leadId)} and is_demo`, 'e2e audit supplier language');
  const job1 = await gypsumJob(ctx, sup, contact);
  const job2 = await gypsumJob(ctx, sup, contact);
  const identity = [contact.fullName, contact.email, contact.phone, contact.phone.replace('+', ''), contact.phone.replace('+971', '0')];

  // Inquiry PDF (EN + AR) and the drawing: nothing that reaches the customer.
  for (const lang of ['en', 'ar']) {
    const r = await call('supplier_api', sup.jwt, { action: 'inquiry_pdf', inquiry_id: job1, lang }, 120000);
    const f = await pdfFacts(r.json?.url).catch((e) => ({ ok: false, why: e.message }));
    const leaked = f.ok ? identity.filter((x) => x && f.text.includes(x)) : [];
    // SUPPLIERS ALWAYS GET ENGLISH (founder, 28 Sep 2026; E2E stage 1 D4): even a request for 'ar' must come back
    // as the English document, so both requests expect English.
    rep.step(B, `inquiry PDF (asked ${lang}) is ours, in English, and carries no customer contact`, pdfVerdict(f, 'en') && !leaked.length ? 'PASS' : 'FAIL',
      `HTTP ${r.status} ${pdfDetail(f, 'en')}${leaked.length ? ' LEAKED ' + leaked.join(', ') : ''}`);
  }
  const docs = await call('supplier_api', sup.jwt, { action: 'inquiry_documents', inquiry_id: job1 });
  const docBlob = JSON.stringify(docs.json || {});
  const drawings = (docs.json?.documents || []).filter((d) => d.kind === 'drawing_page');
  const notRedacted = drawings.filter((d) => !/\/drawings\/redacted\//.test(decodeURIComponent(String(d.url || ''))));
  const leakedDocs = identity.filter((x) => x && docBlob.includes(x));
  rep.step(B, 'inquiry documents: only redacted drawing pages, and no customer contact', docs.status === 200 && !notRedacted.length && !leakedDocs.length ? 'PASS' : 'FAIL',
    `HTTP ${docs.status} ${drawings.length} drawing page(s), ${notRedacted.length} outside drawings/redacted/${leakedDocs.length ? '; LEAKED ' + leakedDocs.join(', ') : ''}`);

  const s = await signedInPage(browser, sup, { lang: 'en', viewport: 'desktop' });
  try {
    await openPortal(s.page, portalUrl('supplier', 'en'), s.calls);
    // The inquiry as the supplier sees it on screen: no customer contact.
    const detail = await openJob(s.page, job1).catch(() => null);
    const shown = detail ? await detail.innerText().catch(() => '') : '';
    const leakedUi = identity.filter((x) => x && shown.includes(x));
    rep.step(B, 'the inquiry on screen carries no customer contact', detail && !leakedUi.length ? 'PASS' : 'FAIL', detail ? (leakedUi.length ? 'LEAKED ' + leakedUi.join(', ') : 'none on screen') : 'the job could not be opened');

    // 1. THE AUDITOR'S TEXT PDF (item 1: "9 things needed"). Only what it genuinely does not say is asked.
    try {
      const chat = await openReview(s.page, job1);
      const n1 = await engineerSaid(chat).count();
      await s.page.setInputFiles(`#qd-rv-file-${job1}`, FIXTURE_PDF);
      await reviewed(chat, n1);
      const th = await call('supplier_api', sup.jwt, { action: 'review_thread', inquiry_id: job1 });
      const open = (th.json?.open_requests || []).map((x) => x.key).sort();
      const extra = open.filter((k) => !GENUINELY_MISSING.includes(k));
      const missed = GENUINELY_MISSING.filter((k) => !open.includes(k));
      rep.step(B, 'quotation PDF upload: the review opens only the genuinely missing points', !extra.length && !missed.length ? 'PASS' : 'FAIL',
        `${open.length} open; asked but stated: ${extra.join(', ') || 'none'}; not asked: ${missed.join(', ') || 'none'}`, { shot: await shot(s.page, dir, 'h_review_pdf', { fullPage: true }) });
    } catch (e) { rep.step(B, 'quotation PDF upload: the review opens only the genuinely missing points', 'FAIL', String(e.message).split('\n')[0].slice(0, 200), { shot: await shot(s.page, dir, 'h_review_pdf_fail', { fullPage: true }) }); }

    // 2. PRICES TYPED IN THE CHAT (item 2: "I could not match that to an open point").
    try {
      await s.page.goto(portalUrl('supplier', 'en'), { waitUntil: 'domcontentloaded' });
      const chat = await openReview(s.page, job2);
      const f = join(ctx.dir, `h_unpriced_${ctx.run.tag}.csv`);
      writeFileSync(f, UNPRICED_CSV);
      const n2 = await engineerSaid(chat).count();
      await s.page.setInputFiles(`#qd-rv-file-${job2}`, f);
      await reviewed(chat, n2);
      const priceKeys = (j) => (j.json?.open_requests || []).filter((x) => /boq_line_not_priced|line_unpriced|total/.test(String(x.code))).map((x) => x.key);
      const before = priceKeys(await call('supplier_api', sup.jwt, { action: 'review_thread', inquiry_id: job2 }));
      // The auditor's own grammar (quote_review.test.ts "finding 2").
      const n3 = await engineerSaid(chat).count();
      await s.page.fill(`#qd-rv-${job2}`, 'BOQ line 2 AED 27,880; BOQ line 3 AED 7,680');
      await chat.getByRole('button', { name: 'Send', exact: true }).click();
      // The FIRST bubble after the send is the acknowledgement ("BOQ line 2 priced ..."), written before the review runs;
      // the review is its own message (kind 'review'). Run 077cbbfc read the thread on the acknowledgement and saw the
      // old total. The step now waits for the review message that follows the supplier's typed line (or 90 s).
      const answered = await engineerSaid(chat).nth(n3).waitFor({ timeout: 90000 }).then(() => true, () => false);
      const reviewedAfterTyped = (j) => { const m = j.json?.messages || []; const k = m.findLastIndex((x) => x.role === 'supplier'); return k >= 0 && m.slice(k + 1).some((x) => x.role === 'sales_engineer' && x.kind === 'review'); };
      let after = await call('supplier_api', sup.jwt, { action: 'review_thread', inquiry_id: job2 });
      for (const t0 = Date.now(); !reviewedAfterTyped(after) && Date.now() - t0 < 90000;) {
        await new Promise((r) => setTimeout(r, 3000));
        after = await call('supplier_api', sup.jwt, { action: 'review_thread', inquiry_id: job2 });
      }
      const still = priceKeys(after);
      const total = Number(after.json?.total_ex_vat);
      const said = await chat.innerText().catch(() => '');
      rep.step(B, 'prices typed in the chat are matched to the BOQ lines', answered && before.length > 0 && !still.length && total === 65960 && !/could not match/i.test(said) ? 'PASS' : 'FAIL',
        `${answered ? '' : 'the engineer never answered the typed prices; '}price points before=${before.length} after=${still.length} (${still.join(', ') || '-'}), total_ex_vat=${after.json?.total_ex_vat ?? '?'} (want 65960)${/could not match/i.test(said) ? ', the engineer said it could not match' : ''}`, { shot: await shot(s.page, dir, 'h_review_prices', { fullPage: true }) });
    } catch (e) { rep.step(B, 'prices typed in the chat are matched to the BOQ lines', 'FAIL', String(e.message).split('\n')[0].slice(0, 200), { shot: await shot(s.page, dir, 'h_review_prices_fail', { fullPage: true }) }); }

    // 3. THE BELL (item 5: "1 new RFQ" deep-linked to /me). Every item keeps the supplier in /portal.
    try {
      await s.page.goto(portalUrl('supplier', 'en'), { waitUntil: 'domcontentloaded' });
      await s.page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
      const bell = s.page.locator('details > summary[aria-label^="Notifications"]').first();
      const n = await bell.getAttribute('aria-label').then((a) => Number((a.match(/\((\d+)\)/) || [])[1] || 0)).catch(() => -1);
      const wrong = [];
      for (let i = 0; i < Math.max(0, n); i++) {
        await bell.click().catch(() => {});
        await s.page.locator('details[open] ul li button').nth(i).click({ timeout: 5000 }).catch(() => {});
        await s.page.waitForTimeout(800);
        const path = new URL(s.page.url()).pathname;
        if (!/^\/(ar\/)?portal\/?$/.test(path)) { wrong.push(path); await s.page.goto(portalUrl('supplier', 'en'), { waitUntil: 'domcontentloaded' }); }
      }
      // And the notices written for this supplier (captured, never sent) link to the supplier portal.
      const notes = await read(`select type, coalesce(body,'') || ' ' || coalesce(html,'') as t from public.notifications
        where (to_email = ${q(sup.email)} or lead_id = ${Number(sup.leadId)}) and to_email like '%@example.invalid'`);
      const toMe = notes.filter((x) => /quotesdone\.(com|ae)(\/ar)?\/me\b/.test(x.t)).map((x) => x.type);
      rep.step(B, 'bell items and notices send the supplier to /portal, never /me', n >= 0 && !wrong.length && !toMe.length ? 'PASS' : 'FAIL',
        `${n} bell item(s)${wrong.length ? ', landed on ' + wrong.join(', ') : ''}; ${notes.length} notice(s), ${toMe.length} linking to /me${toMe.length ? ' (' + [...new Set(toMe)].join(', ') + ')' : ''}`);
    } catch (e) { rep.step(B, 'bell items and notices send the supplier to /portal, never /me', 'FAIL', String(e.message).split('\n')[0].slice(0, 200)); }

    // 4. "REMOVE THIS TRADE" PERSISTS (item 10: removed, Update, reload — the card came back).
    try {
      const st0 = await call('supplier_api', sup.jwt, { action: 'services_state' });
      const roles = (st0.json?.capability?.roles || []).length ? st0.json.capability.roles : ['contractor'];
      // #868: a confirm that ticks no service is refused (services_none_ticked), so the setup ticks one
      // real service per trade, as a supplier must. With services: [] this step had SKIPPED since #868.
      const ticked = (await read(`select distinct on (trade_code) trade_code || '.' || code as code from public.taxonomy_trade_service
        where active and trade_code in ('aluminium','glazing') order by trade_code, sort, code`)).map((r) => r.code);
      const set = await call('supplier_api', sup.jwt, { action: 'services_save_rewrite', trades: ['aluminium', 'glazing'], roles, services: ticked, implied: [], removed: [], own_words: [], raw_text: '' });
      const st1 = await call('supplier_api', sup.jwt, { action: 'services_state' });
      const codes1 = (st1.json?.checklist || []).map((t) => t.code);
      if (!set.json?.ok || !codes1.includes('glazing')) {
        rep.step(B, '"Remove this trade" persists after Update and a reload', 'SKIP', `setup: could not give the demo supplier a second trade (HTTP ${set.status} ${set.text.slice(0, 100)}; checklist ${codes1.join(',')})`);
      } else {
        const label = (st1.json.checklist.find((t) => t.code === 'glazing') || {}).label_en || 'Glass';
        await s.page.goto(portalUrl('supplier', 'en'), { waitUntil: 'domcontentloaded' });
        await s.page.getByRole('button', { name: /^Services/ }).first().click({ timeout: 15000 });
        // The card is the fieldset whose legend names the trade; its own Remove button is pressed.
        const card = () => s.page.locator('fieldset').filter({ has: s.page.locator('legend', { hasText: label }) }).first();
        await card().getByRole('button', { name: /Remove this trade/ }).click({ timeout: 15000 });
        const [saved] = await Promise.all([
          s.page.waitForResponse((r) => r.url().includes('/functions/v1/supplier_api') && (r.request().postData() || '').includes('services_save_rewrite'), { timeout: 30000 }).catch(() => null),
          s.page.getByRole('button', { name: 'Update my services' }).first().click({ timeout: 15000 }),
        ]);
        await s.page.reload({ waitUntil: 'domcontentloaded' });
        await s.page.getByRole('button', { name: /^Services/ }).first().click({ timeout: 15000 }).catch(() => {});
        await s.page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
        const back = await card().isVisible().catch(() => false);
        const codes2 = ((await call('supplier_api', sup.jwt, { action: 'services_state' })).json?.checklist || []).map((t) => t.code);
        rep.step(B, '"Remove this trade" persists after Update and a reload', saved?.status() === 200 && !back && !codes2.includes('glazing') ? 'PASS' : 'FAIL',
          `save HTTP ${saved?.status() ?? 0}; after reload the ${label} card is ${back ? 'BACK' : 'gone'}; stored trades ${codes2.join(', ')}`, { shot: await shot(s.page, dir, 'h_services_after_remove', { fullPage: true }) });
      }
    } catch (e) { rep.step(B, '"Remove this trade" persists after Update and a reload', 'FAIL', String(e.message).split('\n')[0].slice(0, 200)); }
    ctx.consoleErrors.push(...realErrors(s.consoleErrors).map((e) => `[h supplier] ${e}`));
  } finally { await s.ctx.close(); }
}
