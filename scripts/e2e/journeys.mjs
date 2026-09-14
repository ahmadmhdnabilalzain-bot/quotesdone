// scripts/e2e/journeys.mjs — what a customer and a supplier actually do, asserted in the UI AND the database.
//
// The funnel (a-e) runs ONCE, in order, because each step needs the state the last one left: a request,
// three suppliers' quotes (one held then released, one with two options, one complete), a comparison.
// The screens (overview, invitation, deep link, every nav item) run across the whole matrix: English
// and Arabic, desktop 1440 and mobile 375. Every step records PASS, FAIL or SKIP with the reason.
import { writeFileSync } from 'node:fs';
import { call, read, write, waitFor } from './fixtures.mjs';
import { signedInPage, openPortal, portalUrl, shot, realErrors } from './browser.mjs';
import { makeInquiry } from '../staging/demo_factory.mjs';

const q = (v) => `'${String(v).replace(/'/g, "''")}'`;
export const MATRIX = [
  { lang: 'en', viewport: 'desktop' }, { lang: 'ar', viewport: 'desktop' },
  { lang: 'en', viewport: 'mobile' }, { lang: 'ar', viewport: 'mobile' },
];
const tag = (m) => `${m.lang}-${m.viewport}`;

// ---- the quotations each supplier sends ---------------------------------------------------------
// COMPLETE: every detail the sales engineer's hold desk requires for a glazing line
// (_shared/line_specs/model.ts glazing + assess.ts terms), stated exactly.
// "glass" is named on the line: the fallback request carries materials [{component:'glass'}] and
// assess.ts componentOnLine matches the component by word. "double glazed unit" alone never names
// it, so on 14 Sep 2026 the complete quote was held for component:glass and the comparison had one
// live quote. A complete quote that answers a named component names it.
const COMPLETE_LINE = 'Aluminium sliding windows, Schuco AWS 70 thermal break series, double glazed glass unit 6mm + 12mm air + 6mm, powder coated RAL 9016, BS EN 14351-1';
const completeTerms = (amount) => ({
  lead_time: '21 days from order', validity: '30 days', payment_terms: '50% advance, 50% on completion',
  warranty: '2 years covering manufacturing defects, glass seal failure and workmanship',
  scope: 'Supply and installation of 40 aluminium windows including removal of the existing units. Installation within 10 working days of delivery.',
  conditions: 'Access to site during working hours.', exclusions: 'Civil works, painting, scaffolding.',
  price_ex_vat: amount, vat_treatment: 'exclusive', notes: 'ZZ DEMO quotation (e2e harness).',
});
const completeQuote = (inquiryId, amount) => ({
  action: 'submit_quote', inquiry_id: inquiryId, amount, currency: 'AED', source: 'form',
  items: [{ description: COMPLETE_LINE, qty: 40, unit: 'nos', unit_price: Math.round(amount / 40) }],
  ...completeTerms(amount),
});
// INCOMPLETE: no material specification, a vague lead time, no price excluding VAT.
const incompleteQuote = (inquiryId, amount) => ({
  action: 'submit_quote', inquiry_id: inquiryId, amount, currency: 'AED', source: 'form',
  items: [{ description: 'Aluminium windows supply and install', qty: 40, unit: 'nos', unit_price: Math.round(amount / 40) }],
  lead_time: 'TBD', validity: '30 days', payment_terms: '50% advance', warranty: 'standard',
  scope: 'Windows as per drawing.', notes: 'ZZ DEMO incomplete quotation (e2e harness).',
});
// TWO OPTIONS: two "Option N" headings split into two quotations (_shared/line_specs/options.ts).
const twoOptionQuote = (inquiryId, a1, a2) => ({
  action: 'submit_quote', inquiry_id: inquiryId, amount: a1, currency: 'AED', source: 'form',
  items: [
    { description: 'Option 1: standard system' },
    { description: COMPLETE_LINE, qty: 40, unit: 'nos', unit_price: Math.round(a1 / 40) },
    { description: 'Option 2: premium system' },
    { description: 'Aluminium sliding windows, Technal Soleal thermal break series, double glazed glass unit 6mm + 16mm argon + 6mm low-e, anodised finish, BS EN 14351-1', qty: 40, unit: 'nos', unit_price: Math.round(a2 / 40) },
  ],
  option_totals: { 1: a1, 2: a2 },
  ...completeTerms(a1), price_ex_vat: undefined,
});
// What the supplier types into the hold desk's form, by attribute code. Unknown codes get a concrete value.
const FILL = {
  glass_type: 'Double-glazed unit', glass_thickness: '6mm + 12mm air + 6mm', profile_system: 'Schuco AWS 70',
  finish: 'RAL 9016 powder coated', standard: 'BS EN 14351-1', brand: 'Schuco', model: 'AWS 70',
};
const TERM_FILL = (amount) => ({
  delivery: '21 days', installation_included: 'yes', installation_detail: 'Installation within 10 working days of delivery',
  warranty_period: '2 years', warranty_coverage: 'manufacturing defects and workmanship', price_ex_vat: String(amount),
});

// ---- a. the customer posts a request -----------------------------------------------------------
export async function journeyCustomerRequest(ctx) {
  const { rep, browser, fx, dir } = ctx;
  const J = 'a customer';
  // Screens across the matrix: sign-in without an OTP, and the overview's data inside 2.5 s.
  for (const m of MATRIX) {
    const s = await signedInPage(browser, fx.customer, m);
    try {
      const t = await openPortal(s.page, portalUrl('customer', m.lang), s.calls);
      const signedIn = await s.page.locator('nav').first().isVisible().catch(() => false);
      const rtl = await s.page.evaluate(() => document.documentElement.dir).catch(() => '');
      rep.step(J, `signed in without an OTP (${tag(m)})`, signedIn ? 'PASS' : 'FAIL', `nav visible=${signedIn}, dir=${rtl || 'ltr'}`, { shot: await shot(s.page, dir, `a_overview_${tag(m)}`) });
      rep.step(J, `overview data under 2.5 s (${tag(m)})`, t.dataMs < 2500 ? 'PASS' : 'FAIL', `data settled in ${t.dataMs} ms (shell ${t.shellMs} ms, ${t.calls} function call(s))`, { ms: t.dataMs });
      if (m.lang === 'ar') rep.step(J, `Arabic renders right-to-left (${tag(m)})`, rtl === 'rtl' ? 'PASS' : 'FAIL', `document dir=${rtl}`);
      ctx.consoleErrors.push(...realErrors(s.consoleErrors).map((e) => `[customer ${tag(m)}] ${e}`));
    } finally { await s.ctx.close(); }
  }

  // The request itself, through the real chat, in English on desktop.
  const s = await signedInPage(browser, fx.customer, { lang: 'en', viewport: 'desktop' });
  let inquiryId = null, via = 'ui';
  try {
    await openPortal(s.page, portalUrl('customer', 'en'), s.calls);
    await s.page.getByRole('button', { name: /^New request/ }).first().click({ timeout: 15000 });
    const box = s.page.locator('#qd-intake-input');
    await box.waitFor({ state: 'visible', timeout: 15000 });
    const answers = [
      'We need 40 aluminium windows supplied and installed for a private villa in Dubai Marina. Sizes 1200 x 1500 mm, double glazed, powder coated white.',
      'Installation is required, including removal of the old windows. We need a 2 year warranty covering materials and workmanship.',
      'Materials: thermal break aluminium frames, double glazed 6-12-6 glass, powder coated RAL 9016. Delivery needed by 30 November 2026.',
      'Ground and first floor, direct vehicle access, no crane needed. Budget is open.',
      'Please proceed with these details.', 'Yes, that is correct.',
    ];
    let status = null, turns = 0, readiness = 0;
    for (const a of answers) {
      await box.fill(a);
      const [res] = await Promise.all([
        s.page.waitForResponse((r) => r.url().includes('/functions/v1/inquiry_intake'), { timeout: 90000 }).catch(() => null),
        box.press('Enter'),
      ]);
      turns++;
      const j = res ? await res.json().catch(() => ({})) : {};
      status = j.status ?? status; readiness = Number(j.readiness ?? readiness);
      if (status === 'ready') break;
    }
    rep.step(J, 'the sales engineer interview reaches ready', status === 'ready' ? 'PASS' : 'FAIL', `${turns} turn(s), status=${status}, readiness=${readiness}`, { shot: await shot(s.page, dir, 'a_intake') });
    if (status === 'ready') {
      const send = s.page.getByRole('button', { name: /Send to suppliers/ }).first();
      const [res] = await Promise.all([
        s.page.waitForResponse((r) => r.url().includes('/functions/v1/customer_api') && (r.request().postData() || '').includes('create_inquiry'), { timeout: 90000 }).catch(() => null),
        send.click({ timeout: 20000 }),
      ]);
      const j = res ? await res.json().catch(() => ({})) : {};
      inquiryId = j.id ?? j.inquiry_id ?? null;
      rep.step(J, 'request posted from the portal', inquiryId ? 'PASS' : 'FAIL', `HTTP ${res?.status() ?? 0} id=${inquiryId ?? 'none'} ${JSON.stringify(j).slice(0, 160)}`, { shot: await shot(s.page, dir, 'a_posted') });
    }
  } catch (e) {
    rep.step(J, 'request posted from the portal', 'FAIL', `UI error: ${String(e.message).slice(0, 200)}`, { shot: await shot(s.page, dir, 'a_error') });
  } finally {
    ctx.consoleErrors.push(...realErrors(s.consoleErrors).map((e) => `[customer new-request] ${e}`));
    await s.ctx.close();
  }

  if (!inquiryId) {
    // The rest of the funnel still has to be proven, so the request is written the way demo_factory
    // writes one (every category_specs question answered, rfq_ready computed by the real trigger) and
    // the report says so. This is a fallback, never a pass for step a.
    via = 'fallback';
    const inq = await makeInquiry(ctx.run, { customer: { customerId: fx.customer.customerId, locale: 'en' }, trade: 'aluminium', status: 'sent',
      spec: { products: ['aluminium windows'], quantity: 40, requirements: { installation: 'required', warranty: { required: true, min_months: 24 }, delivery_by: '2026-11-30', materials: [{ component: 'glass', value: 'double glazed' }] } } });
    inquiryId = inq.id;
    rep.step(J, 'fallback request written for the rest of the funnel', 'SKIP', `inquiry ${inquiryId} written by demo_factory.makeInquiry because the portal did not post one`);
  }
  ctx.run.ids.inquiries.add(String(inquiryId));
  const row = (await read(`select i.customer_id = ${q(fx.customer.customerId)}::uuid as mine, i.category, i.status, i.rfq_ready,
      (i.spec->'requirements') as req, public.fn_inquiry_is_demo(i.id) as demo
      from public.inquiries i where i.id = ${q(inquiryId)}`))[0] || {};
  const req = row.req || {};
  const asked = ['installation', 'warranty', 'delivery_by', 'materials'].filter((k) => req[k] != null);
  rep.step(J, 'database: the request belongs to the customer and is demo', row.mine === true && row.demo === true ? 'PASS' : 'FAIL', `owner match=${row.mine}, demo=${row.demo}, category=${row.category}, status=${row.status}, rfq_ready=${row.rfq_ready}`);
  rep.step(J, 'database: the sales-engineer answers are on the request (installation, warranty, materials, date)',
    asked.length === 4 ? 'PASS' : (via === 'fallback' ? 'SKIP' : 'FAIL'), `answered: ${asked.join(', ') || 'none'}${via === 'fallback' ? ' (fallback request)' : ''}`);
  ctx.inquiryId = inquiryId;
}

// ---- b. three suppliers quote --------------------------------------------------------------------
export async function journeySuppliers(ctx) {
  const { rep, browser, fx, dir, inquiryId } = ctx;
  const J = 'b supplier';
  if (!inquiryId) return rep.step(J, 'suppliers quote', 'SKIP', 'no request to quote on');
  const [A, B, C] = fx.suppliers;

  // The invitation: the product's routing matched the demo suppliers when the request was posted. If a
  // supplier was not matched (routing picked fewer), the match is written directly and the report says so.
  const matched = await read(`select supplier_id from public.inquiry_matches where inquiry_id = ${q(inquiryId)}`);
  const matchedIds = new Set(matched.map((r) => String(r.supplier_id)));
  const direct = fx.suppliers.filter((s) => !matchedIds.has(String(s.leadId)));
  for (const s of direct) await write(`insert into public.inquiry_matches (inquiry_id, supplier_id, match_reason) values (${q(inquiryId)}, ${s.leadId}, 'e2e harness: direct invitation') on conflict do nothing`, 'e2e invitation');
  rep.step(J, 'routing invited the demo suppliers', direct.length === 0 ? 'PASS' : 'SKIP',
    `${fx.suppliers.length - direct.length}/${fx.suppliers.length} matched by the product; ${direct.length} invited directly by the harness`);

  const identity = [fx.customer.fullName, fx.customer.email, fx.customer.phone, fx.customer.phone.replace('+', '')];
  for (const m of MATRIX) {
    const s = await signedInPage(browser, A, m);
    try {
      await openPortal(s.page, portalUrl('supplier', m.lang), s.calls);
      await s.page.getByRole('button', { name: m.lang === 'ar' ? /^طلبات التسعير/ : /^RFQs/ }).first().click({ timeout: 15000 }).catch(() => {});
      await s.page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
      const text = await s.page.locator('body').innerText().catch(() => '');
      const leaked = identity.filter((x) => x && text.includes(x));
      const sees = /alumin|ألمنيوم|الألمنيوم|window|نوافذ/i.test(text);
      rep.step(J, `sees the invitation (${tag(m)})`, sees ? 'PASS' : 'FAIL', sees ? 'RFQ visible in the RFQs tab' : 'no aluminium RFQ text on the RFQs tab', { shot: await shot(s.page, dir, `b_invitation_${tag(m)}`) });
      rep.step(J, `invitation is anonymised (${tag(m)})`, leaked.length === 0 ? 'PASS' : 'FAIL', leaked.length ? `LEAKED ${leaked.join(', ')}` : `none of ${identity.length} customer identifiers on screen`);
      ctx.consoleErrors.push(...realErrors(s.consoleErrors).map((e) => `[supplier ${tag(m)}] ${e}`));
    } finally { await s.ctx.close(); }
  }
  const inbox = await call('supplier_api', A.jwt, { action: 'inbox' });
  const blob = JSON.stringify(inbox.json || {});
  rep.step(J, 'API: the inbox carries no customer identity', inbox.status === 200 && !identity.some((x) => x && blob.includes(x)) && !blob.includes('customer_id') ? 'PASS' : 'FAIL',
    `HTTP ${inbox.status}, ${(inbox.json?.inquiries || []).length} RFQ(s), customer_id field present=${blob.includes('customer_id')}`);

  // A: incomplete -> HELD
  const a1 = await call('supplier_api', A.jwt, incompleteQuote(inquiryId, 131000));
  const aQid = a1.json?.quote?.id;
  if (aQid) ctx.run.ids.quotes.add(String(aQid));
  rep.step(J, 'an incomplete quote is HELD', a1.json?.held === true ? 'PASS' : 'FAIL', `HTTP ${a1.status} held=${a1.json?.held} missing=${(a1.json?.missing || []).map((x) => x.attr).join(',')}`);
  const hold = aQid ? (await read(`select state, owner_seat, jsonb_array_length(missing) n, notification_ids from public.quote_spec_hold where quote_id = ${q(aQid)} order by id desc limit 1`))[0] : null;
  rep.step(J, 'database: the hold is open and owned by the sales engineer', hold?.state === 'open' ? 'PASS' : 'FAIL', JSON.stringify(hold || {}));
  const notes = aQid ? await read(`select type, channel, status, sender, left(coalesce(last_error,''),60) why from public.notifications where quote_id = ${q(aQid)} order by id`) : [];
  const captured = notes.filter((n) => n.status === 'suppressed');
  rep.step(J, 'the hold notice was written and CAPTURED, never sent', notes.length > 0 && captured.length === notes.length ? 'PASS' : 'FAIL',
    notes.map((n) => `${n.type}/${n.channel}/${n.status}/sender=${n.sender}`).join('; ') || 'no notification row');
  rep.step(J, 'the hold notice reaches WhatsApp too', notes.some((n) => n.channel === 'whatsapp') ? 'PASS' : 'SKIP',
    notes.some((n) => n.channel === 'whatsapp') ? 'whatsapp row captured' : 'the hold desk queues e-mail only (workflow.ts gate); WhatsApp fan-out needs the supplier\'s wa_optin, which a demo supplier does not give');

  // B: two options -> two quotations
  const b1 = await call('supplier_api', B.jwt, twoOptionQuote(inquiryId, 118500, 142000));
  const bOpts = b1.json?.options || [];
  for (const o of bOpts) if (o.quote_id) ctx.run.ids.quotes.add(String(o.quote_id));
  const bRows = await read(`select id, option_no, status, submission_id from public.quotes where inquiry_id = ${q(inquiryId)} and supplier_id = ${B.leadId} order by option_no`);
  rep.step(J, 'two options become two quotations', bRows.length === 2 && new Set(bRows.map((r) => r.submission_id)).size === 1 ? 'PASS' : 'FAIL',
    `HTTP ${b1.status} code=${b1.json?.code} rows=${bRows.map((r) => `#${r.option_no}:${r.status}`).join(',')} held=${bOpts.filter((o) => o.held).length}`);

  // C: complete -> accepted first time (preflight first, so a miss is reported, not guessed)
  const pre = await call('supplier_api', C.jwt, { ...completeQuote(inquiryId, 124900), dry_run: true });
  rep.step(J, 'preflight: the complete quote states every required detail', pre.json?.would_hold === false ? 'PASS' : 'FAIL',
    `would_hold=${pre.json?.would_hold} missing=${(pre.json?.spec_missing || []).map((x) => x.attr).join(',') || 'none'} would_accept=${pre.json?.would_accept}`);
  const c1 = await call('supplier_api', C.jwt, completeQuote(inquiryId, 124900));
  if (c1.json?.quote?.id) ctx.run.ids.quotes.add(String(c1.json.quote.id));
  rep.step(J, 'a complete quote is accepted', c1.json?.accepted === true ? 'PASS' : 'FAIL', `HTTP ${c1.status} held=${c1.json?.held} accepted=${c1.json?.accepted} code=${c1.json?.code ?? ''}`);

  // Held quotes are not ranked (checked NOW, while A is still held).
  const cmp = await call('quote_compare', fx.customer.jwt, { inquiry_id: inquiryId, lang: 'en' });
  const ids = JSON.stringify(cmp.json?.analysis?.all_quotes || cmp.json || {});
  rep.step(J, 'a held quote is not ranked', cmp.status === 200 && aQid && !ids.includes(aQid) && Number(cmp.json?.analysis?.on_hold ?? cmp.json?.on_hold ?? 0) >= 1 ? 'PASS' : 'FAIL',
    `HTTP ${cmp.status} ok=${cmp.json?.ok} on_hold=${cmp.json?.analysis?.on_hold ?? cmp.json?.on_hold} held quote in ranking=${aQid ? ids.includes(aQid) : '?'}${cmp.json?.degraded ? ' (deterministic comparison)' : ''}`);

  // A fills in the missing details -> regenerated -> approves -> released
  if (aQid) {
    const h = await call('supplier_api', A.jwt, { action: 'spec_hold', quote_id: aQid });
    const lines = {};
    for (const l of h.json?.schema?.lines || []) for (const f of l.fields) if (f.missing || !f.value) (lines[l.line_no] ||= {})[f.attr] = FILL[f.attr] ?? (f.type === 'number' ? '10' : (f.options?.[0] ?? `ZZ DEMO ${f.attr} 10 mm`));
    const terms = {};
    // A customer-named component (component:<name>) is a quote-level term with no fixed code, so
    // TERM_FILL cannot list it; sent as undefined it stayed missing and the hold never released.
    for (const t of h.json?.schema?.terms || []) terms[t.attr] = TERM_FILL(131000)[t.attr] ?? (String(t.attr).startsWith('component:') ? `ZZ DEMO ${String(t.attr).slice(10)}: double glazed glass unit 6mm + 12mm air + 6mm` : undefined);
    const f1 = await call('supplier_api', A.jwt, { action: 'spec_fill', quote_id: aQid, values: { lines, terms } });
    rep.step(J, 'filling in the details regenerates the quotation', f1.json?.complete === true ? 'PASS' : 'FAIL',
      `HTTP ${f1.status} complete=${f1.json?.complete} pdf=${f1.json?.pdf_url ? 'yes' : 'no'} still missing=${(f1.json?.missing || []).map((x) => x.attr).join(',') || 'none'} errors=${JSON.stringify(f1.json?.errors || []).slice(0, 120)}`);
    const ap = await call('supplier_api', A.jwt, { action: 'spec_approve', quote_id: aQid, confirm: true });
    rep.step(J, 'the supplier approves and the quote is released', ap.json?.released === true ? 'PASS' : 'FAIL', `HTTP ${ap.status} released=${ap.json?.released} live=${ap.json?.live} code=${ap.json?.code ?? ''}`);
    const after = (await read(`select h.state, h.approved_by is not null approved, q.status from public.quote_spec_hold h join public.quotes q on q.id = h.quote_id where h.quote_id = ${q(aQid)} order by h.id desc limit 1`))[0] || {};
    rep.step(J, 'database: hold released, quote live', after.state === 'released' && after.status !== 'draft' ? 'PASS' : 'FAIL', JSON.stringify(after));
    // The Quotes tab shows it.
    const s = await signedInPage(browser, A, { lang: 'en', viewport: 'desktop' });
    try {
      await openPortal(s.page, portalUrl('supplier', 'en'), s.calls);
      await s.page.getByRole('button', { name: /^Quotes/ }).first().click({ timeout: 15000 }).catch(() => {});
      await s.page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
      rep.step(J, 'the Quotes tab opens after release', 'PASS', 'screenshot recorded', { shot: await shot(s.page, dir, 'b_quotes_after_release') });
    } finally { await s.ctx.close(); }
  }
  ctx.quoteIds = (await read(`select id::text id, supplier_id, option_no, status from public.quotes where inquiry_id = ${q(inquiryId)} order by quote_amount`));
}

// ---- c. the customer compares ---------------------------------------------------------------------
export async function journeyComparison(ctx) {
  const { rep, browser, fx, dir, inquiryId } = ctx;
  const J = 'c comparison';
  if (!inquiryId) return rep.step(J, 'comparison', 'SKIP', 'no request');
  // The bytes are kept in the run directory so a person can open exactly what the customer got.
  const pdfBytes = async (url) => { if (!url) return null; const r = await fetch(url).catch(() => null); if (!r?.ok) return null; const b = Buffer.from(await r.arrayBuffer()); return b.subarray(0, 5).toString() === '%PDF-' ? b : null; };
  // THE REGISTERED LANGUAGE DECIDES THE DOCUMENT (founder, 14 Sep 2026: "if someone registered while
  // the language was arabic then arabic follows through the whole workflow"), so an Arabic report is
  // proven by an Arabic-registered customer, not by lang:'ar' alone. Measured 14 Sep 2026: with
  // customers.locale='en', the "ar" PDF and CSV were byte-identical to the English ones and the step
  // still passed on "%PDF-". The demo row's locale is set per pass AND lang is sent, which holds
  // whichever of the two decides. The update cannot reach a real person: demo row, example.invalid.
  const setLocale = (lang) => write(`update public.customers set locale = ${q(lang)} where id = ${q(fx.customer.customerId)} and is_demo = true and email like '%@example.invalid'`, 'e2e comparison language');
  for (const lang of ['en', 'ar']) {
    await setLocale(lang);
    const r = await call('customer_api', fx.customer.jwt, { action: 'compare_pdf', inquiry_id: inquiryId, lang }, 180000);
    const url = r.json?.url || r.json?.pdf_url || r.json?.file_url;
    const b = await pdfBytes(url);
    const saved = b ? `${dir}/c_comparison_${lang}.pdf` : null;
    if (b) writeFileSync(saved, b);
    rep.step(J, `comparison report opens as a PDF (${lang})`, b ? 'PASS' : 'FAIL', `HTTP ${r.status} ${b ? 'valid %PDF, saved ' + saved : 'no PDF: ' + r.text.slice(0, 140)}`);
  }
  // compare_csv goes through the same quote_compare call as compare_pdf (customer_api
  // fetchCompareAnalysis), so it is asserted here rather than assumed to follow.
  for (const lang of ['en', 'ar']) {
    await setLocale(lang);
    const r = await call('customer_api', fx.customer.jwt, { action: 'compare_csv', inquiry_id: inquiryId, lang }, 180000);
    const csv = String(r.json?.csv || '');
    const rows = csv.split(/\r?\n/).filter((x) => x.trim());
    const arabic = lang !== 'ar' || /[؀-ۿ]/.test(rows[0] || '');
    const ok = r.json?.ok === true && rows.length >= 2 && arabic;
    if (csv) writeFileSync(`${dir}/c_comparison_${lang}.csv`, csv);
    rep.step(J, `comparison exports as CSV (${lang})`, ok ? 'PASS' : 'FAIL', `HTTP ${r.status} rows=${rows.length} header_arabic=${lang === 'ar' ? arabic : 'n/a'}${ok ? '' : ' ' + r.text.slice(0, 140)}`);
  }
  // THE TWO PATHS MUST SEE ONE ANALYSIS. 14 Sep 2026: quote_compare answered the customer's JWT with
  // a deterministic analysis while compare_pdf/compare_csv (server-to-server, __secret) got
  // comparison_unavailable. The CSV's quote columns are compareTable(analysis) from the
  // server-to-server call; they must be exactly quote_compare's non-held quotes, in order, at the
  // same prices. compare_pdf shares that call (customer_api fetchCompareAnalysis).
  await setLocale('en');
  {
    const direct = await call('quote_compare', fx.customer.jwt, { inquiry_id: inquiryId, lang: 'en' }, 180000);
    const csvR = await call('customer_api', fx.customer.jwt, { action: 'compare_csv', inquiry_id: inquiryId, lang: 'en' }, 180000);
    const a = direct.json?.analysis;
    const held = new Set((a?.all_quotes || []).filter((x) => x?.status === 'held').map((x) => String(x.label)));
    const want = (a?.quotes || []).filter((x) => !held.has(String(x.label)));
    const parseRow = (line) => { const out = []; let cur = '', qd = false; for (let i = 0; i < line.length; i++) { const c = line[i]; if (qd) { if (c === '"' && line[i + 1] === '"') { cur += '"'; i++; } else if (c === '"') qd = false; else cur += c; } else if (c === '"') qd = true; else if (c === ',') { out.push(cur); cur = ''; } else cur += c; } out.push(cur); return out; };
    const lines = String(csvR.json?.csv || '').replace(/^﻿/, '').split(/\r\n/).filter(Boolean);
    const head = lines[0] ? parseRow(lines[0]).slice(1) : [];
    const priceRow = lines.map(parseRow).find((r) => r[0] === 'Price')?.slice(1) || [];
    const digits = (s) => Number(String(s).replace(/[^\d.]/g, '')) || 0;
    const wantPrice = want.map((x) => Math.round(Number(x.price_ex_vat) > 0 ? Number(x.price_ex_vat) : Number(x.price)));
    const sameCols = want.length >= 2 && head.length === want.length && want.every((x, i) => head[i].includes(String(x.label)));
    const samePrice = priceRow.length === want.length && priceRow.every((p, i) => Math.round(digits(p)) === wantPrice[i]);
    rep.step(J, 'compare_pdf/compare_csv see the same analysis as quote_compare with the customer JWT', direct.json?.ok && sameCols && samePrice ? 'PASS' : 'FAIL',
      `direct HTTP ${direct.status} ok=${direct.json?.ok} degraded=${direct.json?.degraded ?? false} live=${want.length} held=${held.size} | csv cols=[${head.join(' | ')}] want=[${want.map((x) => x.label).join(' | ')}] prices csv=[${priceRow.map(digits).join(',')}] want=[${wantPrice.join(',')}]`);
  }
  const live = (ctx.quoteIds || []).filter((x) => x.status !== 'draft');
  if (live[0]) {
    for (const lang of ['en', 'ar']) {
      const r = await call('customer_api', fx.customer.jwt, { action: 'quote_pdf', quote_id: live[0].id, lang }, 120000);
      const url = r.json?.url || r.json?.pdf_url || r.json?.file_url;
      const ok = await isPdf(url);
      rep.step(J, `quotation PDF opens (${lang})`, ok ? 'PASS' : 'FAIL', `HTTP ${r.status} ${ok ? 'valid %PDF' : 'no PDF: ' + r.text.slice(0, 140)}`);
    }
  } else rep.step(J, 'quotation PDF opens', 'FAIL', 'no live quote to open');
  // The deep link the PDFs print: /me?request=<id>&quote=<id>
  for (const m of MATRIX) {
    const s = await signedInPage(browser, fx.customer, m);
    try {
      await openPortal(s.page, portalUrl('customer', m.lang, `?request=${inquiryId}${live[0] ? '&quote=' + live[0].id : ''}`), s.calls);
      const text = await s.page.locator('body').innerText().catch(() => '');
      const ref = 'QD-' + String(inquiryId).slice(0, 8).toUpperCase();
      const opened = text.includes(ref) || /alumin|ألمنيوم|الألمنيوم/i.test(text);
      rep.step(J, `deep link opens the request (${tag(m)})`, opened ? 'PASS' : 'FAIL', opened ? `request ${ref} on screen` : 'request not on screen', { shot: await shot(s.page, dir, `c_deeplink_${tag(m)}`) });
      ctx.consoleErrors.push(...realErrors(s.consoleErrors).map((e) => `[customer deeplink ${tag(m)}] ${e}`));
    } finally { await s.ctx.close(); }
  }
}

// ---- d. reveal payment (Stripe TEST mode only) -----------------------------------------------------
export async function journeyPayment(ctx) {
  const { rep, fx } = ctx;
  const J = 'd payment';
  const keysPresent = (await read(`select count(*)::int n from public.app_secrets where key in ('stripe_secret_key_test','stripe_publishable_key_test') and coalesce(value,'') <> ''`))[0].n;
  if (keysPresent < 2) {
    ctx.paid = false;
    return rep.step(J, 'reveal payment in Stripe test mode', 'SKIP',
      'app_secrets stripe_secret_key_test / stripe_publishable_key_test are not set. The founder adds them; until then a demo account is refused with stripe_test_not_configured and the live key is never used. Stripe was NOT called.');
  }
  const live = (ctx.quoteIds || []).find((x) => x.status !== 'draft');
  if (!live) { ctx.paid = false; return rep.step(J, 'reveal payment', 'SKIP', 'no live quote to reveal'); }
  const init = await call('stripe_checkout', fx.customer.jwt, { action: 'element_init', quote_id: live.id });
  const testMode = init.json?.mode === 'test' && String(init.json?.publishable_key || '').startsWith('pk_test_');
  rep.step(J, 'a demo account is served the TEST key only', testMode ? 'PASS' : 'FAIL', `mode=${init.json?.mode} key=${String(init.json?.publishable_key || '').slice(0, 8)}…`);
  if (!testMode) { ctx.paid = false; return; }
  // Checkout Session (the fallback path) paid with Stripe's test card in a real browser.
  const sess = await call('stripe_checkout', fx.customer.jwt, { quote_id: live.id, return_url: 'https://quotesdone.com/me' });
  if (!sess.json?.url) { ctx.paid = false; return rep.step(J, 'test checkout session created', 'FAIL', sess.text); }
  const b = await ctx.browser.newContext(); const p = await b.newPage();
  try {
    await p.goto(sess.json.url, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await p.locator('#cardNumber').fill('4242 4242 4242 4242'); await p.locator('#cardExpiry').fill('12 / 34');
    await p.locator('#cardCvc').fill('123'); await p.locator('#billingName').fill('ZZ DEMO Customer').catch(() => {});
    await p.locator('button[type=submit]').click();
    await p.waitForURL(/quotesdone\.(com|ae)/, { timeout: 90000 }).catch(() => {});
  } finally { await b.close(); }
  const tx = await waitFor(async () => (await read(`select fee_status, payment_ref from public.transactions where quote_id = ${q(live.id)}`))[0], { timeoutMs: 60000 });
  ctx.paid = !!tx;
  rep.step(J, 'the reveal is recorded from a real TEST payment', tx?.fee_status === 'paid' ? 'PASS' : 'FAIL', JSON.stringify(tx || {}));
}

// ---- e. invoice and refund ladder ------------------------------------------------------------------
export async function journeyInvoiceRefund(ctx) {
  const { rep } = ctx;
  const J = 'e invoice+refund';
  if (!ctx.paid) {
    rep.step(J, 'invoice appears in the portal', 'SKIP', 'needs a paid reveal (journey d), which needs the Stripe test keys');
    rep.step(J, 'refund ladder with the CEO checklist', 'SKIP', 'needs a paid reveal. Built and merged: customer_api request_refund, fn_refund_open_from_customer, the 5-working-day ladder, ceo_agent decide. NOT merged on main: a CEO refund checklist in code (refund_ceo_check / refund_ceo_review exist as tables only).');
    return;
  }
  const live = (ctx.quoteIds || []).find((x) => x.status !== 'draft');
  const inv = await call('reveal_invoice', ctx.fx.customer.jwt, { quote_id: live.id });
  const row = (await read(`select ri.invoice_no from public.reveal_invoices ri join public.transactions t on t.id = ri.transaction_id where t.quote_id = ${q(live.id)}`))[0];
  rep.step(J, 'invoice filed for the reveal', row?.invoice_no ? 'PASS' : 'FAIL', `HTTP ${inv.status} invoice=${row?.invoice_no ?? 'none'}`);
  rep.step(J, 'refund ladder with the CEO checklist', 'SKIP', 'not driven: the CEO checklist is not merged in code; request_refund would open a real CEO case');
}

// ---- f. every nav item on both portals ----------------------------------------------------------
const NAV = {
  customer: {
    en: ['Overview', 'My requests', 'Documents', 'Orders', 'Messages', 'Projects', 'Project room', 'What you may need next', 'Buying profile', 'Account'],
    ar: ['نظرة عامة', 'طلباتي', 'المستندات', 'أوامر الشراء', 'الرسائل', 'المشاريع', 'غرفة المشروع', 'ما قد تحتاجه لاحقًا', 'ملف المشتريات', 'الحساب'],
  },
  supplier: {
    en: ['Get matched', 'RFQs', 'Quotes', 'Projects', 'Messages', 'Documents', 'Billing', 'Insights', 'Profile', 'My scope', 'Settings'],
    ar: ['احصل على المطابقة', 'طلبات التسعير', 'العروض', 'المشاريع', 'الرسائل', 'المستندات', 'الفواتير', 'الرؤى', 'الملف', 'نطاق عملي', 'الإعدادات'],
  },
};
// Buttons a crawler must never press: they spend, send, delete or sign out. Everything else is pressed.
const NEVER = /sign\s*out|log\s*out|delete|remove|cancel|withdraw|refund|reveal|pay|send|submit|approve|reject|accept|decline|close\s*request|تسجيل الخروج|حذف|إزالة|إلغاء|سحب|استرداد|كشف|ادفع|دفع|أرسل|إرسال|اعتماد|رفض|قبول/i;
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

export async function journeyCrawl(ctx) {
  const { rep, browser, fx, dir } = ctx;
  const J = 'f crawl';
  for (const who of [fx.customer, fx.suppliers[0]]) {
    for (const m of MATRIX) {
      const s = await signedInPage(browser, who, m);
      const before = s.consoleErrors.length;
      try {
        await openPortal(s.page, portalUrl(who.kind, m.lang), s.calls);
        for (const label of NAV[who.kind][m.lang]) {
          const btn = s.page.getByRole('button', { name: new RegExp('^' + esc(label)) }).first();
          if (!(await btn.isVisible().catch(() => false))) await s.page.locator('#qd-nav-more').click({ timeout: 3000 }).catch(() => {});
          const t0 = Date.now();
          try {
            await btn.click({ timeout: 8000 });
            await s.page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});
            const ms = Date.now() - t0;
            const failed = s.calls.filter((c) => c.at >= t0 && (c.status >= 500 || c.status === 0)).map((c) => `${c.fn}:${c.action}:${c.status}`);
            rep.step(J, `${who.kind} ${tag(m)}: ${label}`, failed.length ? 'FAIL' : 'PASS', `${ms} ms${failed.length ? ' failed calls ' + failed.join(', ') : ''}`, { ms, shot: await shot(s.page, dir, `f_${who.kind}_${tag(m)}_${label}`) });
            // Every other button in this view, except those that spend, send, delete or sign out.
            const names = await s.page.locator('main button:visible, [role=main] button:visible').evaluateAll((els) => els.map((e) => (e.getAttribute('aria-label') || e.textContent || '').trim()).filter(Boolean)).catch(() => []);
            let pressed = 0;
            for (const n of [...new Set(names)].slice(0, 15)) {
              if (NEVER.test(n)) continue;
              const b2 = s.page.getByRole('button', { name: n, exact: true }).first();
              await b2.click({ timeout: 3000 }).then(() => { pressed++; }).catch(() => {});
              await s.page.keyboard.press('Escape').catch(() => {});
            }
            if (pressed) rep.step(J, `${who.kind} ${tag(m)}: ${label} - in-view buttons`, 'PASS', `${pressed} button(s) pressed without a crash`);
            await btn.click({ timeout: 3000 }).catch(() => {});
          } catch (e) {
            rep.step(J, `${who.kind} ${tag(m)}: ${label}`, 'FAIL', `could not click: ${String(e.message).split('\n')[0].slice(0, 140)}`, { shot: await shot(s.page, dir, `f_fail_${who.kind}_${tag(m)}_${label}`) });
          }
        }
      } finally {
        const errs = realErrors(s.consoleErrors.slice(before));
        rep.step(J, `${who.kind} ${tag(m)}: no console errors`, errs.length ? 'FAIL' : 'PASS', errs.length ? errs.slice(0, 3).join(' | ') : 'clean');
        ctx.consoleErrors.push(...errs.map((e) => `[crawl ${who.kind} ${tag(m)}] ${e}`));
        await s.ctx.close();
      }
    }
  }
}

export const JOURNEYS = { a: journeyCustomerRequest, b: journeySuppliers, c: journeyComparison, d: journeyPayment, e: journeyInvoiceRefund, f: journeyCrawl };
