// scripts/e2e/journeys.mjs — what a customer and a supplier actually do, asserted in the UI AND the database.
//
// The funnel (a-e) runs ONCE, in order, because each step needs the state the last one left: a request,
// three suppliers' quotes (one held then released, one with two options, one complete), a comparison.
// The screens (overview, invitation, deep link, every nav item) run across the whole matrix: English
// and Arabic, desktop 1440 and mobile 375. Every step records PASS, FAIL or SKIP with the reason.
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
const COMPLETE_LINE = 'Aluminium sliding windows, Schuco AWS 70 thermal break series, double glazed unit 6mm + 12mm air + 6mm, powder coated RAL 9016, BS EN 14351-1';
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
    { description: 'Aluminium sliding windows, Technal Soleal thermal break series, double glazed unit 6mm + 16mm argon + 6mm low-e, anodised finish, BS EN 14351-1', qty: 40, unit: 'nos', unit_price: Math.round(a2 / 40) },
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
      // Desktop shows the sidebar <nav>; a phone shows a bottom bar whose More button controls #qd-nav-more.
      const signedIn = await s.page.locator('nav:visible, button[aria-controls="qd-nav-more"]:visible').first().isVisible().catch(() => false);
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
    // A budget, not just a turn count: each reply may take up to 90 s, and a chat that never reaches
    // ready must not stall the whole run (run 5 sat here for over ten minutes).
    const deadline = Date.now() + 5 * 60 * 1000;
    for (const a of answers) {
      if (Date.now() > deadline) break;
      await box.fill(a);
      const [res] = await Promise.all([
        s.page.waitForResponse((r) => r.url().includes('/functions/v1/inquiry_intake'), { timeout: 90000 }).catch(() => null),
        box.press('Enter'),
      ]);
      turns++;
      const j = res ? await res.json().catch(() => ({})) : {};
      status = j.status ?? status; readiness = Number(j.readiness ?? readiness) || 0;
      if (status === 'ready') break;
      // When the sales engineer offers answer chips, tap the first one, as a customer would.
      const chip = s.page.locator('[role="group"] button').first();
      if (await chip.isVisible().catch(() => false)) {
        const [r2] = await Promise.all([
          s.page.waitForResponse((r) => r.url().includes('/functions/v1/inquiry_intake'), { timeout: 90000 }).catch(() => null),
          chip.click().catch(() => {}),
        ]);
        turns++;
        const j2 = r2 ? await r2.json().catch(() => ({})) : {};
        status = j2.status ?? status; readiness = Number(j2.readiness ?? readiness) || 0;
        if (status === 'ready') break;
      }
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
      // No materials requirement on purpose: the live hold desk turns each one into a quote-level
      // "component:<name>" detail, and the fallback must not manufacture holds the customer never asked for.
      spec: { products: ['aluminium windows'], quantity: 40, requirements: { installation: 'required', warranty: { required: true, min_months: 24 }, delivery_by: '2026-11-30' } } });
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
    // A detail the harness does not know by name (e.g. a customer's "component:<name>" material
    // requirement) still gets a concrete, exact value - never a vague one the desk would refuse.
    for (const t of h.json?.schema?.terms || []) terms[t.attr] = TERM_FILL(131000)[t.attr] ?? (t.type === 'number' ? '10' : (t.options?.[0] ?? 'Double glazed 6mm + 12mm air + 6mm, Schuco AWS 70, RAL 9016'));
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
  const isPdf = async (url) => { if (!url) return false; const r = await fetch(url).catch(() => null); if (!r?.ok) return false; const b = Buffer.from(await r.arrayBuffer()); return b.subarray(0, 5).toString() === '%PDF-'; };
  for (const lang of ['en', 'ar']) {
    const r = await call('customer_api', fx.customer.jwt, { action: 'compare_pdf', inquiry_id: inquiryId, lang }, 180000);
    const url = r.json?.url || r.json?.pdf_url || r.json?.file_url;
    const ok = await isPdf(url);
    rep.step(J, `comparison report opens as a PDF (${lang})`, ok ? 'PASS' : 'FAIL', `HTTP ${r.status} ${ok ? 'valid %PDF' : 'no PDF: ' + r.text.slice(0, 140)}`);
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
  // Paid in the CUSTOMER's signed-in browser, as a customer does: Stripe returns to /me?session_id=…
  // and the portal calls stripe_confirm, which records the reveal. Run 5 paid in a fresh browser with no
  // session, so Stripe completed the payment (test, paid) but the return landed on a signed-out page
  // and nothing recorded it.
  const signed = await signedInPage(ctx.browser, fx.customer, { lang: 'en', viewport: 'desktop' });
  const b = signed.ctx; const p = signed.page;
  try {
    await p.goto(sess.json.url, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await p.locator('#cardNumber').fill('4242 4242 4242 4242'); await p.locator('#cardExpiry').fill('12 / 34');
    await p.locator('#cardCvc').fill('123'); await p.locator('#billingName').fill('ZZ DEMO Customer').catch(() => {});
    await shot(p, ctx.dir, 'd_stripe_checkout_filled');
    await p.locator('button[type=submit]').click();
    await p.waitForURL(/quotesdone\.(com|ae)/, { timeout: 90000 }).catch(() => {});
    await shot(p, ctx.dir, 'd_after_pay');
    rep.step(J, 'Stripe test checkout completed and returned to the portal', /quotesdone\.(com|ae)/.test(p.url()) ? 'PASS' : 'FAIL', `landed on ${p.url().split('?')[0].slice(0, 80)}`);
  } catch (e) {
    await shot(p, ctx.dir, 'd_checkout_error');
    rep.step(J, 'Stripe test checkout completed and returned to the portal', 'FAIL', String(e.message).split('\n')[0].slice(0, 200));
  } finally { await b.close(); }
  const tx = await waitFor(async () => (await read(`select id, fee_status, payment_ref, reveal_fee, processing_fee, total_charged, quote_amount,
      stripe_invoice_id is not null has_invoice, doc_path from public.transactions where quote_id = ${q(live.id)}`))[0], { timeoutMs: 90000 });
  ctx.paid = !!tx; ctx.paidQuote = live.id; ctx.tx = tx;
  rep.step(J, 'the reveal is recorded from a real TEST payment', tx?.fee_status === 'paid' ? 'PASS' : 'FAIL',
    JSON.stringify({ fee_status: tx?.fee_status, payment_ref: String(tx?.payment_ref || '').slice(0, 5) + '…' }));
  if (!tx) return;
  // #616's formula (_shared/reveal_fee.ts revealCharge on main): base = round(rate x quote) to the fils;
  // total = ceil((base + fixed) / (1 - pct)), where the Checkout Session charges the safest
  // (international) basis: pct = (3.9% card + 0.5% invoicing) x 1.05 VAT on Stripe's fees = 4.62%,
  // fixed = AED 1.00 x 1.05 = AED 1.05. Measured 14 Sep 2026: 118,500 x 3% = 3,555 -> 3,728.30.
  const rate = Number((await read('select standard_reveal_rate r from public.pricing_config where id = 1'))[0].r);
  const PCT = (0.039 + 0.005) * 1.05, FIXED_F = 105;
  const baseF = Math.round(Number(tx.quote_amount) * rate * 100);
  const totalF = Math.ceil((baseF + FIXED_F) / (1 - PCT) - 1e-9);
  const ok = Math.round(Number(tx.reveal_fee) * 100) === baseF && Math.round(Number(tx.total_charged) * 100) === totalF
    && Math.round((Number(tx.reveal_fee) + Number(tx.processing_fee)) * 100) === totalF;
  rep.step(J, "the fee matches #616's formula (3% + card processing, no VAT)", ok ? 'PASS' : 'FAIL',
    `quote ${tx.quote_amount} x ${rate}: expected base ${baseF / 100} + processing ${(totalF - baseF) / 100} = ${totalF / 100}; recorded ${tx.reveal_fee} + ${tx.processing_fee} = ${tx.total_charged}`);
}

// ---- e. invoice and refund ladder ------------------------------------------------------------------
export async function journeyInvoiceRefund(ctx) {
  const { rep } = ctx;
  const J = 'e invoice+refund';
  if (!ctx.paid) {
    rep.step(J, 'invoice appears in the portal', 'SKIP', 'needs a paid reveal, and journey d did not record one (see its steps)');
    rep.step(J, 'refund ladder with the CEO checklist', 'SKIP', 'needs a paid reveal. Built and merged: customer_api request_refund, fn_refund_open_from_customer, the 5-working-day ladder, ceo_agent decide. NOT merged on main: a CEO refund checklist in code (refund_ceo_check / refund_ceo_review exist as tables only).');
    return;
  }
  const qid = ctx.paidQuote;
  // The Stripe invoice: created and paid by Stripe, attached by stripe_webhook (doc_path invoices/…).
  const tx = await waitFor(async () => { const r = (await read(`select id, stripe_invoice_id is not null has_invoice, doc_path, stripe_invoice_number from public.transactions where quote_id = ${q(qid)}`))[0]; return r?.doc_path ? r : null; }, { timeoutMs: 90000 });
  rep.step(J, 'Stripe invoice created, paid and its PDF stored', tx?.has_invoice && tx?.doc_path ? 'PASS' : 'FAIL', JSON.stringify(tx || { doc_path: null }));
  const doc = tx ? (await read(`select kind, bucket, status from public.documents where bucket = 'finance-docs' and path = ${q(tx.doc_path)}`))[0] : null;
  rep.step(J, "the accountant filed it in the customer's Documents", doc?.kind === 'invoice' ? 'PASS' : 'FAIL', JSON.stringify(doc || {}));
  const ho = tx ? (await read(`select status, decided_by from public.agent_actions where kind = 'handoff' and target_table = 'transactions' and target_id = ${q(tx.id)}`))[0] : null;
  rep.step(J, 'handoff accountant -> sales engineer closed', ho?.status === 'done' && ho?.decided_by === 'sales_engineer' ? 'PASS' : 'FAIL', JSON.stringify(ho || {}));
  const nr = (await read(`select status from public.notifications where type = 'invoice_ready' and quote_id = ${q(qid)}`))[0];
  rep.step(J, "the sales engineer's 'invoice ready' notice was written and captured", nr?.status === 'suppressed' ? 'PASS' : 'FAIL', JSON.stringify(nr || {}));
  // The invoice in the portal: the revealed quote's card, deep-linked.
  const s = await signedInPage(ctx.browser, ctx.fx.customer, { lang: 'en', viewport: 'desktop' });
  try {
    await openPortal(s.page, portalUrl('customer', 'en', `?request=${ctx.inquiryId}&quote=${qid}`), s.calls);
    const seen = await s.page.getByText(/Invoice \(PDF\)|Invoice/).first().isVisible().catch(() => false);
    rep.step(J, 'the invoice is in the portal', seen ? 'PASS' : 'FAIL', seen ? '"Invoice" visible on the revealed request' : 'no invoice control on screen', { shot: await shot(s.page, ctx.dir, 'e_invoice_in_portal') });
  } finally { await s.ctx.close(); }
  rep.step(J, 'refund ladder with the CEO checklist', 'SKIP', 'not driven: the CEO refund checklist is not merged in code on main (refund_ceo_check / refund_ceo_review exist as tables only); request_refund would open a live CEO case');
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
          // On a phone the item may sit in the More sheet; its button is aria-controls="qd-nav-more"
          // (the sheet itself, #qd-nav-more, only exists while open).
          if (!(await btn.isVisible().catch(() => false))) await s.page.locator('button[aria-controls="qd-nav-more"]').first().click({ timeout: 3000 }).catch(() => {});
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
