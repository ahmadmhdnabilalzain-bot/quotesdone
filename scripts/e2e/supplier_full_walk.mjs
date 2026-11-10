// scripts/e2e/supplier_full_walk.mjs — every supplier scenario the registration walk and the quotation
// review do not drive, in a real browser at 1440, 768 and 375 (it_engineer, QA, 19 Oct 2026).
//
//   node scripts/e2e/supplier_full_walk.mjs
//   QD_SHOTS=<dir> QD_VIEWPORTS=desktop,tablet,mobile node scripts/e2e/supplier_full_walk.mjs
//
// Per viewport, one approved ZZ DEMO supplier and its own matched painting jobs, then:
//   a. quote by typing the lines; b. quote by uploading a quotation PDF (read by the real model);
//   c. a PDF carrying two options; d. a vague quote against required specs, which must be HELD;
//   e. refresh (re-send a changed price) before reveal; f. withdraw before reveal;
//   g. the anonymous question to the customer, and no other customer's data anywhere on the page;
//   h. the reveal notice reaching this supplier; i. paying a due: the checkout must be Stripe TEST
//      for an @example.invalid account (the card itself is not typed by this walk);
//   j. a catalogue at the largest size the upload allows; k. account settings; l. sign-out.
// On every screen: no horizontal overflow, no console errors, no Arabic text (ruling 1008).
//
// Nothing reaches a person: ZZ DEMO / @example.invalid only, notices suppressed by the fixture fence.
// The AI is on (ruling 1260): extract_quote and the reveal hand-off run on the real models.
// Teardown is closeRun's: the run fails unless the leftover count is 0.
import { mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { openRun, closeRun, makeDemoCustomer, makeDemoSupplier, read, write, waitFor } from './fixtures.mjs';
import { makeInquiry, makeReveal, uploadObject, q } from '../lib/demo_factory.mjs';
import { demoPdf, demoPdfPages, demoOfficePlanPng } from '../lib/demo_pdf.mjs';
import { launch, signedInPage, openPortal, portalUrl, realErrors, fullPageShot } from './browser.mjs';

const SHOTS = process.env.QD_SHOTS || join(tmpdir(), 'qd-supplier-full');
const VIEWPORTS = (process.env.QD_VIEWPORTS || 'desktop,tablet,mobile').split(',').map((s) => s.trim()).filter(Boolean);
const CATALOGUE_MB = Number(process.env.QD_CATALOGUE_MB || 24); // under the 25 MB ceiling until #1487 is live
mkdirSync(SHOTS, { recursive: true });
const results = [];
const step = (scenario, vp, ok, detail = '') => { results.push({ scenario, vp, ok, detail }); console.log(`${ok ? 'PASS' : 'FAIL'}  [${vp}] ${scenario}${detail ? ' — ' + String(detail).slice(0, 300) : ''}`); };
const ARABIC = /[؀-ۿ]/;
const OTHER_MARKER = 'ZZ DEMO Otherparty Marker';

const BOQ = { boq: [
  { section: 'Internal walls', description: 'Internal wall painting emulsion', qty: 450, unit: 'm2', confidence: 'high' },
  { section: 'Ceilings', description: 'Ceiling painting emulsion', qty: 120, unit: 'm2', confidence: 'medium' },
] };
// The customer named a brand and a finish: a quote that names neither is held for its specs.
const SPECS = { customer_requirements: { version: 1, installation: { required: 'yes' }, warranty: { required: 'yes' } },
  requirements: [{ item: 'Internal wall paint', brand: 'Jotun Fenomastic', finish: 'matt', coats: 2 }] };

async function job(run, customer, supplier, label) {
  const inq = await makeInquiry(run, { customer, trade: 'painting', status: 'sent', rfqReady: false, emirate: 'Dubai', locale: 'en' });
  run.ids.inquiries.add(inq.id);
  const page = `drawings/redacted/${run.tag}/${inq.id}_p1.png`;
  await uploadObject('drawing-files', page, demoOfficePlanPng({ redactTitleBlock: true }), 'image/png');
  run.ids.storage.push(`drawing-files/${page}`);
  await write(`update public.inquiries set boq = ${q(JSON.stringify(BOQ))}::jsonb, boq_confidence = 'high',
      spec = coalesce(spec, '{}'::jsonb) || ${q(JSON.stringify(SPECS))}::jsonb, drawing_redacted_paths = array[${q(page)}]
    where id = ${q(inq.id)}`, `e2e full walk inquiry ${label}`);
  await write(`insert into public.inquiry_matches (inquiry_id, supplier_id, match_reason) values (${q(inq.id)}, ${Number(supplier.leadId)}, 'e2e: full walk') on conflict do nothing`, 'e2e match');
  const rfq = (await read(`select rfq_no from public.inquiries where id = ${q(inq.id)}`))[0]?.rfq_no;
  return { id: inq.id, rfq: String(rfq ?? '') };
}

const quotationPdf = (options) => demoPdfPages([[
  ['ZZ DEMO Painting LLC - Quotation', 16], ['Prices in AED, excluding VAT. Validity: 30 days. Lead time: 3 weeks.', 10],
  ['Warranty: 2 years materials and workmanship. Payment: 50% advance, 50% on completion.', 10],
  ...options.flatMap((o) => [[o.title, 13], ...o.lines.map((l) => [`${l[0]}   ${l[1]} m2 x ${l[2]} = ${l[1] * l[2]}`, 10]), [`Total ${o.title}: AED ${o.lines.reduce((s, l) => s + l[1] * l[2], 0)}`, 11]]),
]]);

async function screenCheck(page, vp, where, consoleErrors) {
  const m = await page.evaluate(() => ({ over: document.documentElement.scrollWidth - window.innerWidth, text: document.body.innerText }));
  step(`${where}: nothing hidden sideways`, vp, m.over <= 1, `overflow ${m.over}px`);
  const ar = (m.text.match(/[^\n]*[؀-ۿ][^\n]*/g) || []).filter((l) => !/^(عربي|العربية)$/.test(l.trim()));
  step(`${where}: all text English`, vp, ar.length === 0, ar.slice(0, 2).join(' | '));
  step(`${where}: no data from another party`, vp, !m.text.includes(OTHER_MARKER));
  const errs = realErrors(consoleErrors.splice(0));
  step(`${where}: no console errors`, vp, errs.length === 0, errs.slice(0, 2).join(' | '));
}

async function openJob(page, j) {
  await page.getByRole('button', { name: /Inquiries received/ }).first().click();
  const row = page.locator(`#qd-inq-${j.id} > button`);
  await row.waitFor({ timeout: 30000 });
  const detail = page.locator(`#qd-inq-d-${j.id}`);
  if (!(await detail.isVisible().catch(() => false))) await row.click();
  await detail.getByText(j.rfq).first().waitFor({ timeout: 30000 });
  return detail;
}

async function openForm(page, detail) {
  await detail.getByRole('button', { name: 'Or type it into the quote form' }).click();
  await detail.getByPlaceholder('Total amount (AED)').waitFor({ timeout: 15000 });
}

async function fillTyped(detail, { amount, lines, vague = false }) {
  await detail.getByPlaceholder('Total amount (AED)').fill(String(amount));
  await detail.getByPlaceholder('Lead time').first().fill('3 weeks');
  await detail.locator('label', { hasText: 'The total above' }).locator('select').selectOption('exclusive');
  await detail.getByPlaceholder(/Quote validity/).fill('30 days');
  await detail.getByPlaceholder(/Payment terms/).fill('50% advance, 50% on completion');
  await detail.getByPlaceholder(/Warranty/).fill(vague ? '' : '2 years materials and workmanship');
  for (let i = 0; i < lines.length; i++) {
    if (i > 0) await detail.getByRole('button', { name: '+ Add item' }).click();
    const [d, qty, unit, price] = lines[i];
    await detail.getByLabel(`Description, line ${i + 1}`).fill(d);
    await detail.getByLabel(`Quantity, line ${i + 1}`).fill(String(qty));
    await detail.getByLabel(`Unit, line ${i + 1}`).fill(unit);
    await detail.getByLabel(`Unit price, line ${i + 1}`).fill(String(price));
  }
}

// A held quote is released the way a supplier releases it: Quotations submitted, "Fill in the missing
// details", the exact values, Save (regenerates), confirm, Approve. Values by the field's own label.
const SPEC_VALUES = [[/Brand/i, 'Jotun'], [/Product name/i, 'Fenomastic'], [/Number of coats/i, '2'], [/installation/i, 'yes'],
  [/warranty covers|Warranty coverage/i, 'Materials and workmanship'], [/Warranty period/i, '2 years'], [/finish|sheen/i, 'matt'], [/colou?r/i, 'White']];
async function releaseHold(page, inquiryId) {
  await page.getByRole('button', { name: /Quotations submitted/ }).first().click();
  const li = page.locator(`#qd-qt-${inquiryId}`);
  await li.waitFor({ timeout: 30000 });
  const fills = li.getByRole('button', { name: 'Fill in the missing details' });
  await fills.first().waitFor({ timeout: 30000 }).catch(() => {});   // the hold panel loads after the list
  const n = await fills.count();
  for (let k = 0; k < n; k++) {
    await li.getByRole('button', { name: 'Fill in the missing details' }).first().click();
    const labels = li.locator('label');
    for (let i = 0; i < await labels.count(); i++) {
      const lab = labels.nth(i); const txt = (await lab.innerText()).trim();
      const v = SPEC_VALUES.find(([re]) => re.test(txt))?.[1] ?? 'As specified';
      const sel = lab.locator('select'); const inp = lab.locator('input:not([type=checkbox])');
      if (await sel.count()) await sel.selectOption(v === 'yes' ? 'yes' : { index: 1 }).catch(() => {});
      else if (await inp.count()) await inp.fill(v).catch(() => {});
    }
    await li.getByRole('button', { name: 'Save and regenerate my quotation' }).click();
    await li.getByRole('checkbox').first().waitFor({ timeout: 120000 });
    await li.getByRole('checkbox').first().check();
    await li.getByRole('button', { name: 'Approve and send to the customer' }).click();
    await page.waitForTimeout(3000);
  }
  return n;
}

// WHAT THE PORTAL WAS TOLD, NOT ONLY WHAT IT SHOWED (10 Nov 2026). Scenarios c and d failed on production with the
// database showing a 200 (c: extract_quote 46 s; d: a held draft) and the screen showing neither the read nor the hold,
// and nothing said which side dropped it. The answer to the browser is now part of the step's detail.
const answerOf = (page, action, timeout = 300000) => page.waitForResponse((r) => r.url().includes('/functions/v1/supplier_api') && (r.request().postData() || '').includes(`"action":"${action}"`), { timeout })
  .then(async (r) => { const j = await r.json().catch(() => null); return { http: r.status(), ok: j?.ok ?? null, code: j?.code ?? j?.error ?? null, total: j?.proposal?.total ?? j?.proposal?.amount ?? null, options: Array.isArray(j?.proposal?.options) ? j.proposal.options.length : null, status: j?.status ?? j?.quote?.status ?? null, issues: Array.isArray(j?.review_issues) ? j.review_issues.map((i) => [i.code, i.attr, i.line_no].filter((x) => x != null).join(':')) : undefined }; })
  .catch((e) => ({ browser_got_no_answer: String(e.message).split('\n')[0].slice(0, 100) }));

// The quote rows once they exist; a held one is released through the portal, then read again.
async function settle(page, supplierId, inquiryId, min) {
  await waitFor(async () => (await quotesOf(supplierId, inquiryId)).length >= min, { timeoutMs: 120000 });
  let held = 0;
  // A DRAFT IS NOT YET A HOLD (10 Nov 2026, run on production, mobile b). An uploaded quotation is a draft at once and its
  // hold opens when the sales engineer's review ends (21 s later that day), so pressing "Fill in the missing details"
  // straight away found no button and the scenario failed on timing. Wait for the hold row (or the send) first; the
  // button must then appear without a reload, which is the portal's job (QuotationsTab re-reads a draft with no hold).
  if ((await quotesOf(supplierId, inquiryId)).some((r) => r.status === 'draft')) {
    await waitFor(async () => {
      const x = await quotesOf(supplierId, inquiryId);
      if (x.every((y) => y.status === 'submitted')) return true;
      return (await read(`select 1 from public.quote_spec_hold where inquiry_id = ${q(inquiryId)} and supplier_id = ${Number(supplierId)} and state in ('open','awaiting_approval') limit 1`)).length > 0;
    }, { timeoutMs: 120000 });
    if ((await quotesOf(supplierId, inquiryId)).some((r) => r.status === 'draft')) held = await releaseHold(page, inquiryId);
  }
  const r = await waitFor(async () => { const x = await quotesOf(supplierId, inquiryId); return x.length >= min && x.every((y) => y.status === 'submitted') ? x : null; }, { timeoutMs: 120000 }) || await quotesOf(supplierId, inquiryId);
  r.held = held; return r;
}
const quotesOf = (supplierId, inquiryId) => read(`select id, status, quote_amount::float amt, source, option_no from public.quotes where inquiry_id = ${q(inquiryId)} and supplier_id = ${Number(supplierId)} order by option_no`);

async function drive(browser, run, s, vp) {
  const { supplier, jobs } = s;
  const { ctx, page, consoleErrors, calls } = await signedInPage(browser, supplier, { lang: 'en', viewport: vp });
  const shot = (n) => fullPageShot(page, join(SHOTS, `${vp}_${n}.png`)).catch(() => {});
  const scen = async (name, fn) => {
    try { await Promise.race([fn(), new Promise((_, rej) => setTimeout(() => rej(new Error('scenario took over 8 minutes')), 480000))]); } catch (e) { step(name, vp, false, String(e.message).split('\n')[0]); await shot(`zz_fail_${name.replace(/[^a-z0-9]+/gi, '_')}`); }
  };
  try {
    await openPortal(page, portalUrl('supplier', 'en'), calls);
    await screenCheck(page, vp, 'portal home', consoleErrors);

    await scen('a. quote by typing the lines', async () => {
      const d = await openJob(page, jobs.typed); await openForm(page, d);
      await fillTyped(d, { amount: 11160, lines: [['Jotun Fenomastic matt emulsion, 2 coats, internal walls', 450, 'm2', 20], ['Jotun Fenomastic matt emulsion, 2 coats, ceilings', 120, 'm2', 18]] });
      await d.getByRole('button', { name: 'Submit quote' }).click();
      const qs = await settle(page, supplier.leadId, jobs.typed.id, 1);
      qs.forEach((r) => run.ids.quotes.add(r.id));
      step('a. quote by typing the lines', vp, qs[0]?.status === 'submitted' && qs[0]?.source === 'form' && qs[0]?.amt === 11160, JSON.stringify(qs));
      await shot('a_typed_submitted'); await screenCheck(page, vp, 'typed quote', consoleErrors);
    });

    await scen('b. quote by uploading a quotation PDF', async () => {
      const d = await openJob(page, jobs.pdf); await openForm(page, d);
      const f = join(SHOTS, `${vp}_quotation.pdf`);
      writeFileSync(f, quotationPdf([{ title: 'Option 1', lines: [['Jotun Fenomastic matt emulsion 2 coats internal walls', 450, 21], ['Jotun Fenomastic matt emulsion 2 coats ceilings', 120, 19]] }]));
      const told = answerOf(page, 'extract_quote');
      await d.locator('label', { hasText: 'Attach file' }).last().locator('input[type=file]').setInputFiles(f);
      await waitFor(async () => Number(await d.getByPlaceholder('Total amount (AED)').inputValue()) > 0, { timeoutMs: 300000, everyMs: 3000 });
      const read1 = await d.getByPlaceholder('Total amount (AED)').inputValue();
      const readAnswer = await told;
      await d.locator('label', { hasText: 'The total above' }).locator('select').selectOption('exclusive');
      await d.getByRole('button', { name: 'Submit quote' }).click();
      const qs = await settle(page, supplier.leadId, jobs.pdf.id, 1);
      qs.forEach((r) => run.ids.quotes.add(r.id));
      step('b. quote by uploading a quotation PDF', vp, qs[0]?.source === 'upload' && qs[0]?.status === 'submitted' && Math.abs(qs[0].amt - 11730) < 1, `read total ${read1}; extract_quote answered ${JSON.stringify(readAnswer)}; ${JSON.stringify(qs)}`);
      await shot('b_pdf_submitted');
    });

    await scen('c. a quotation with two options', async () => {
      const d = await openJob(page, jobs.options); await openForm(page, d);
      const f = join(SHOTS, `${vp}_quotation_two_options.pdf`);
      writeFileSync(f, quotationPdf([
        { title: 'Option 1 - Jotun Fenomastic', lines: [['Jotun Fenomastic matt emulsion 2 coats internal walls', 450, 21], ['Jotun Fenomastic matt emulsion 2 coats ceilings', 120, 19]] },
        { title: 'Option 2 - National Paints', lines: [['National Paints matt emulsion 2 coats internal walls', 450, 16], ['National Paints matt emulsion 2 coats ceilings', 120, 15]] }]));
      const told = answerOf(page, 'extract_quote');
      await d.locator('label', { hasText: 'Attach file' }).last().locator('input[type=file]').setInputFiles(f);
      await waitFor(async () => Number(await d.getByPlaceholder('Total amount (AED)').inputValue()) > 0, { timeoutMs: 300000, everyMs: 3000 });
      const said = await d.innerText();
      const readAnswer = await told;
      await d.locator('label', { hasText: 'The total above' }).locator('select').selectOption('exclusive');
      await d.getByRole('button', { name: 'Submit quote' }).click();
      const qs = await settle(page, supplier.leadId, jobs.options.id, 2);
      qs.forEach((r) => run.ids.quotes.add(r.id));
      step('c. a quotation with two options', vp, qs.length === 2 && new Set(qs.map((r) => r.option_no)).size === 2, `split notice shown: ${/option/i.test(said)}; extract_quote answered ${JSON.stringify(readAnswer)}; ${JSON.stringify(qs)}`);
      await shot('c_two_options');
    });

    await scen('d. incomplete specs are held', async () => {
      const d = await openJob(page, jobs.vague); await openForm(page, d);
      await fillTyped(d, { amount: 9000, lines: [['Painting works', 1, 'lot', 9000]], vague: true });
      const told = answerOf(page, 'submit_quote', 120000);
      await d.getByRole('button', { name: 'Submit quote' }).click();
      const held = await page.getByText(/saved and on hold|saved as a draft|On hold/).first().waitFor({ timeout: 60000 }).then(() => true).catch(() => false);
      const qs = await quotesOf(supplier.leadId, jobs.vague.id); qs.forEach((r) => run.ids.quotes.add(r.id));
      const hold = qs[0] ? (await read(`select count(*)::int n from public.quote_spec_hold where quote_id = ${q(qs[0].id)}`))[0].n : 0;
      step('d. incomplete specs are held', vp, held && qs[0]?.status === 'draft', `on-screen held=${held}; submit_quote answered ${JSON.stringify(await told)}; spec holds ${hold}; ${JSON.stringify(qs)}`);
      await shot('d_held');
    });

    await scen('e. refresh a quote before reveal', async () => {
      const d = await openJob(page, jobs.typed);
      if (!(await d.getByPlaceholder('Total amount (AED)').isVisible().catch(() => false))) await openForm(page, d);
      // A REFRESH STILL ADDS UP (10 Nov 2026). This changed the total to 10,900 and left the lines at 450 x 20 + 120 x 18 =
      // 11,160; the review's rule 4 (the line amounts add up to the total, code total_mismatch) kept it a draft, correctly,
      // and the walk read that as a refresh that failed. The new price is now stated on the line as well: 120 x 15.
      await d.getByLabel('Unit price, line 2').fill('15');
      await d.getByPlaceholder('Total amount (AED)').fill('10800');
      const told = answerOf(page, 'submit_quote', 120000);
      await d.getByRole('button', { name: 'Submit quote' }).click();
      const qs = await settle(page, supplier.leadId, jobs.typed.id, 1);
      step('e. refresh a quote before reveal', vp, qs.length === 1 && qs[0].amt === 10800 && qs[0].status === 'submitted', `submit_quote answered ${JSON.stringify(await told)}; ${JSON.stringify(qs)}`);
      await shot('e_refreshed');
    });

    await scen('f. withdraw a quote before reveal', async () => {
      await page.getByRole('button', { name: /Quotations submitted/ }).first().click();
      await page.waitForTimeout(1500);
      // THE PDF JOB'S OWN CONTROL, AND BOTH PRESSES (10 Nov 2026). Withdraw has asked for a second press ("Confirm
      // withdraw") since the 19 Oct QA walk, because a withdrawn quotation leaves the customer's comparison; this pressed
      // the first "Withdraw" on the page (the newest job's, not the PDF job it then checks) and never confirmed.
      const card = page.locator(`#qd-qt-${jobs.pdf.id}`);
      const btn = card.getByRole('button', { name: /^Withdraw$/ });
      const n = await btn.count();
      await shot('f_withdraw_control');
      if (!n) { step('f. withdraw a quote before reveal', vp, false, 'no Withdraw control on the PDF job\'s card in Quotations submitted'); return; }
      await btn.first().click();
      await card.getByRole('button', { name: /^Confirm withdraw$/ }).click({ timeout: 10000 });
      const qs = await waitFor(async () => { const r = await quotesOf(supplier.leadId, jobs.pdf.id); return r[0]?.status === 'withdrawn' ? r : null; }, { timeoutMs: 30000 });
      step('f. withdraw a quote before reveal', vp, !!qs, JSON.stringify(qs));
    });

    await scen('g. anonymous question; no other customer data', async () => {
      const d = await openJob(page, jobs.typed);
      await d.getByRole('button', { name: 'Scope unclear? Ask the customer (anonymously)' }).click();
      await d.locator('textarea').last().fill('ZZ DEMO question: is the ceiling height above 3 m anywhere?');
      await d.getByRole('button', { name: 'Send question' }).click();
      const ok = await d.getByText(/Your question was sent to the customer/).first().waitFor({ timeout: 30000 }).then(() => true).catch(() => false);
      await shot('g_question_sent');
      // The other customer's inquiry is not matched to this supplier: the API must refuse it, and its marker never shows.
      const other = await page.evaluate(async ([id, token]) => {
        const r = await fetch(`${location.origin}/functions/v1/supplier_api`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: 'Bearer ' + token }, body: JSON.stringify({ action: 'inbox', inquiry_id: id }) }).catch(() => null);
        return r ? { status: r.status, body: (await r.text()).slice(0, 4000) } : null;
      }, [s.otherInquiry, supplier.jwt]);
      const leak = other && other.body.includes(OTHER_MARKER);
      step('g. anonymous question; no other customer data', vp, ok && !leak, `question sent=${ok}; other inquiry via API: ${other?.status} leak=${leak}`);
      await screenCheck(page, vp, 'inquiry with question', consoleErrors);
    });

    await scen('h. reveal notification', async () => {
      const qs = await quotesOf(supplier.leadId, jobs.typed.id);
      const t = await makeReveal(run, { quote: { id: qs[0].id, amount: qs[0].amt }, inquiry: { id: jobs.typed.id }, supplier, customer: s.customer, reveal_fee: Math.round(qs[0].amt * 0.03) });
      if (t.id) run.ids.transactions?.add?.(t.id);
      // Ruling 1199: no notice is filed from a demo row, so a fixture cannot see the reveal e-mail. What it can see
      // is the reveal itself: the job moves to Messages (Projects) with the customer now named.
      await page.reload(); await openPortal(page, portalUrl('supplier', 'en'), calls).catch(() => {});
      await page.getByRole('button', { name: /^Messages/ }).first().click();
      const seen = await page.getByText(/^Revealed /).first().waitFor({ timeout: 60000 }).then(() => true).catch(() => false);
      const filed = await read(`select count(*)::int n from public.agent_actions where kind = 'handoff' and target_id like ${q('%' + qs[0].id + '%')}`);
      step('h. reveal notification', vp, seen, `revealed job in Messages: ${seen}; handoffs filed for the demo reveal: ${filed[0].n} (ruling 1199 files none, so no e-mail/WhatsApp notice exists to assert)`);
      await shot('h_after_reveal');
    });

    await scen('i. paying the fee (checkout opens in Stripe TEST mode)', async () => {
      const due = (await write(`insert into public.supplier_dues (supplier_id, amount_due, currency, status, due_date, reveal_date) values (${Number(supplier.leadId)}, 150, 'AED', 'pending', current_date + 30, current_date) returning id`, 'e2e due'))[0];
      s.dues.push(due.id);
      // Billing is prefetched when the portal opens (tabPrefetch), so a due raised mid-session shows after a reload.
      await page.reload(); await openPortal(page, portalUrl('supplier', 'en'), calls).catch(() => {});
      await page.locator('summary', { hasText: 'Account' }).first().click();
      await page.getByRole('button', { name: 'Billing', exact: true }).first().click();
      const pay = page.getByRole('button', { name: 'Pay now' }).first();
      await pay.waitFor({ timeout: 30000 });
      await shot('i_billing');
      const [nav] = await Promise.all([page.waitForURL(/checkout\.stripe\.com/, { timeout: 30000 }).then(() => page.url()).catch(() => null), pay.click()]);
      const url = nav || page.url();
      step('i. paying the fee (checkout opens in Stripe TEST mode)', vp, /\/cs_test_/.test(url), url.replace(/#.*/, '').slice(0, 120));
      await shot('i_checkout');
      if (/checkout\.stripe\.com/.test(url)) await page.goBack().catch(() => {});
      await openPortal(page, portalUrl('supplier', 'en'), calls).catch(() => {});
    });

    await scen(`j. catalogue upload, ${CATALOGUE_MB} MB PDF`, async () => {
      const f = join(SHOTS, `${vp}_catalogue_${CATALOGUE_MB}mb.pdf`);
      const pad = Buffer.alloc(CATALOGUE_MB * 1024 * 1024 - 4096, 0x20);
      const base = demoPdf([['ZZ DEMO Painting catalogue', 18], ['Jotun Fenomastic, National Paints, Dulux', 11]]);
      writeFileSync(f, Buffer.concat([base, Buffer.from('\n%'), pad, Buffer.from('\n')]));
      await page.getByRole('button', { name: /^Documents/ }).first().click();
      const card = page.locator('.qd-panel').filter({ hasText: /Catalog/i }).filter({ has: page.locator('input[type=file]') }).first();
      await card.locator('input[type=file]').setInputFiles(f);
      await card.getByRole('button', { name: 'Upload', exact: true }).click();
      const cat = await waitFor(async () => { const r = await read(`select catalog_doc_paths catalogs from public.leads where id = ${Number(supplier.leadId)}`); const c = r[0]?.catalogs; return Array.isArray(c) && c.length ? c : null; }, { timeoutMs: 240000, everyMs: 5000 });
      await shot('j_catalogue');
      step(`j. catalogue upload, ${CATALOGUE_MB} MB PDF`, vp, !!cat, JSON.stringify(cat || (await page.locator('[role=status],[role=alert]').allInnerTexts()).slice?.(0, 3)));
    });

    await scen('k. account settings', async () => {
      await page.locator('summary', { hasText: 'Account' }).first().click();
      await page.getByRole('button', { name: 'Settings', exact: true }).first().click();
      await page.waitForTimeout(1500);
      await shot('k_settings');
      const txt = await page.locator('main').innerText();
      step('k. account settings', vp, /Settings|Notifications|Language/i.test(txt) && !/Loading…$/.test(txt.trim()), txt.slice(0, 120));
      await screenCheck(page, vp, 'settings', consoleErrors);
    });

    await scen('l. sign-out', async () => {
      await page.getByRole('button', { name: 'Sign out' }).first().click();
      await page.waitForTimeout(1500);
      const tok = await page.evaluate(() => localStorage.getItem('qd-sup-token'));
      await page.reload(); await page.waitForTimeout(2500);
      const back = await page.getByRole('button', { name: /Inquiries received/ }).count();
      await shot('l_signed_out');
      step('l. sign-out', vp, !tok && back === 0, `token=${!!tok}; portal tabs after reload=${back}`);
    });
  } finally { await ctx.close(); }
}

const run = await openRun();
let fail = false;
const dues = [];
try {
  const customer = await makeDemoCustomer(run, { label: 'FullWalk' });
  const other = await makeDemoCustomer(run, { label: 'Otherparty' });
  const otherInq = await makeInquiry(run, { customer: other, trade: 'painting', status: 'sent', rfqReady: false, emirate: 'Dubai', locale: 'en' });
  run.ids.inquiries.add(otherInq.id);
  await write(`update public.inquiries set summary = ${q(OTHER_MARKER + ' private scope')}, raw_input = ${q(OTHER_MARKER + ' private scope')} where id = ${q(otherInq.id)}`, 'other party marker');
  const browser = await launch();
  try {
    for (const vp of VIEWPORTS) {
      const supplier = await makeDemoSupplier(run, { label: `FW${vp}`, trade: 'painting', activity: 'Painting Works' });
      const jobs = {};
      for (const k of ['typed', 'pdf', 'options', 'vague']) jobs[k] = await job(run, customer, supplier, `${vp}-${k}`);
      await drive(browser, run, { supplier, jobs, customer, otherInquiry: otherInq.id, dues }, vp);
    }
  } finally { await browser.close(); }
} catch (e) {
  fail = true; console.error('RUN FAILED', e);
} finally {
  if (dues.length) await write(`delete from public.supplier_due_checkouts where due_id in (${dues.join(',')})`, 'e2e due checkouts').catch(() => {});
  if (dues.length) await write(`delete from public.supplier_dues where id in (${dues.join(',')})`, 'e2e dues').catch(() => {});
  const c = await closeRun(run);
  const total = c.leftovers?.total ?? -1;
  step('teardown leaves nothing behind', 'all', total === 0, JSON.stringify(c.leftovers));
  writeFileSync(join(SHOTS, 'results.json'), JSON.stringify(results, null, 1));
  process.exitCode = fail || results.some((r) => !r.ok) ? 1 : 0;
}
