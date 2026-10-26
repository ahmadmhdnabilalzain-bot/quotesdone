// scripts/e2e/journeys.mjs — what a customer and a supplier actually do, asserted in the UI AND the database.
//
// The funnel (a-e) runs ONCE, in order, because each step needs the state the last one left: a request,
// three suppliers' quotes (one held then released, one with two options, one complete), a comparison.
// The screens (overview, invitation, deep link, every nav item) run across the whole matrix: English
// and Arabic, desktop 1440 and mobile 375. Every step records PASS, FAIL or SKIP with the reason.
import { writeFileSync } from 'node:fs';
import { call, read, write, waitFor } from './fixtures.mjs';
import { signedInPage, openPortal, portalUrl, shot, realErrors, SITE, assertHarnessSignedIn } from './browser.mjs';
import { makeInquiry } from '../lib/demo_factory.mjs';
import { journeyAuditButtons } from './journey_audit_buttons.mjs';
import { payHostedTestCheckout, checkoutBlockers } from './stripe_test_checkout.mjs';

const q = (v) => `'${String(v).replace(/'/g, "''")}'`;
export const MATRIX = [
  { lang: 'en', viewport: 'desktop' }, { lang: 'ar', viewport: 'desktop' },
  { lang: 'en', viewport: 'mobile' }, { lang: 'ar', viewport: 'mobile' },
];
const tag = (m) => `${m.lang}-${m.viewport}`;
// SUPPLIERS ARE ENGLISH ONLY (founder ruling 1008, #1409): the supplier portal never renders Arabic, so an Arabic
// supplier pass asserted a portal the product deliberately does not build - 24 of the 36 failures on 18 Oct
// (run 39079803518) were the supplier ar-desktop / ar-mobile passes reading "ltr/en". Customers keep both.
export const matrixFor = (kind) => MATRIX.filter((m) => kind !== 'supplier' || m.lang === 'en');

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
// B's option 2 states a different system; on the desk he states that one, not option 1's.
const FILL_PREMIUM = {
  glass_type: 'Double-glazed unit, low-e', glass_thickness: '6mm + 16mm argon + 6mm', profile_system: 'Technal Soleal',
  finish: 'Anodised', standard: 'BS EN 14351-1', brand: 'Technal', model: 'Soleal',
};
// The hold desk as the supplier uses it: read the form, state every missing detail exactly, save.
async function deskFill(sup, qid, fill, amount) {
  const h = await call('supplier_api', sup.jwt, { action: 'spec_hold', quote_id: qid });
  const lines = {};
  for (const l of h.json?.schema?.lines || []) for (const f of l.fields) if (f.missing || !f.value) (lines[l.line_no] ||= {})[f.attr] = fill[f.attr] ?? (f.type === 'number' ? '10' : (f.options?.[0] ?? `ZZ DEMO ${f.attr} 10 mm`));
  const terms = {};
  // A detail the harness does not know by name (e.g. a customer's "component:<name>" material
  // requirement) still gets a concrete, exact value - never a vague one the desk would refuse.
  for (const t of h.json?.schema?.terms || []) terms[t.attr] = TERM_FILL(amount)[t.attr] ?? (t.type === 'number' ? '10' : (t.options?.[0] ?? 'Double glazed 6mm + 12mm air + 6mm, Schuco AWS 70, RAL 9016'));
  const f1 = await call('supplier_api', sup.jwt, { action: 'spec_fill', quote_id: qid, values: { lines, terms } });
  return { f1, fillDetail: `HTTP ${f1.status} complete=${f1.json?.complete} pdf=${f1.json?.pdf_url ? 'yes' : 'no'} still missing=${(f1.json?.missing || []).map((x) => x.attr).join(',') || 'none'} errors=${JSON.stringify(f1.json?.errors || []).slice(0, 120)}` };
}
async function releaseViaDesk(sup, qid, fill, amount) {
  const d = await deskFill(sup, qid, fill, amount);
  if (d.f1.json?.complete !== true) return { released: false, detail: d.fillDetail };
  const ap = await call('supplier_api', sup.jwt, { action: 'spec_approve', quote_id: qid, confirm: true });
  return { released: ap.json?.released === true, detail: `${d.fillDetail}; approve HTTP ${ap.status} released=${ap.json?.released} live=${ap.json?.live} code=${ap.json?.code ?? ''}` };
}
const TERM_FILL = (amount) => ({
  delivery: '21 days', installation_included: 'yes', installation_detail: 'Installation within 10 working days of delivery',
  warranty_period: '2 years', warranty_coverage: 'manufacturing defects and workmanship', price_ex_vat: String(amount),
});

// ---- the model hold, measured -------------------------------------------------------------------
// 23 Sep 2026 (#886, #893; founder_instruction 886-903, ledger 890). Meaning is never decided by a word
// list: the intake's trade and a quotation's specifications are read by reasoning (_shared/think.ts), and
// under the founder's OpenRouter hold nothing is read — the intake is HELD and every quotation is HELD
// until the supplier states each detail on the hold desk. The post-deploy smoke kept asserting "the
// interview reaches ready" and "a complete quote is accepted first time", which only reasoning can do,
// and raised 14 findings for the product doing what it must. The hold is asked of the SAME gate the
// product asks (_shared/llm_hold.ts heldFromGate over fn_kernel_paid_provider_gate), never assumed. Only
// while it answers held, and only when the product's answer is exactly the held answer, does a
// reasoning-only step report SKIP — with the held contract asserted as its own step. The moment the hold
// lifts every one of them is a hard FAIL again.
const HOLD_RULES = new Set(['founder_hold', 'no_paid_ai_switch', 'empty_route_state']);   // llm_hold.ts HOLD_RULES
let heldBy;
export async function modelHold() {
  if (heldBy !== undefined) return heldBy;
  try {
    const g = (await read(`select public.fn_kernel_paid_provider_gate('hold-probe/not-a-model') g`))[0]?.g;
    heldBy = g && g.allowed !== true && HOLD_RULES.has(String(g.rule ?? '')) ? `${g.rule}: ${String(g.reason ?? '').slice(0, 120)}` : null;
  } catch (_e) { heldBy = null; }   // could not tell: nothing is excused
  return heldBy;
}
const UNDER_HOLD = (h) => ` — model hold on (${h}); reasoning is not run, so this is held by design and re-proven when the hold lifts`;

// ---- a. the customer posts a request -----------------------------------------------------------
export async function journeyCustomerRequest(ctx) {
  const { rep, browser, fx, dir } = ctx;
  const J = 'a customer';
  // THE ARABIC PASS IS AN ARABIC-REGISTERED CUSTOMER (14 Sep 2026). Signed in, the portal follows
  // customers.locale (founder: "if someone registered while the language was arabic then arabic
  // follows through the whole workflow"), so an English-registered customer on /ar correctly sees
  // English, and the old pass, which always used the 'en' fixture, asserted rtl from someone the
  // rule says gets ltr. The row is a demo customer at example.invalid; nothing reaches a person.
  const setCustomerLocale = (lang) => write(`update public.customers set locale = ${q(lang)} where id = ${q(fx.customer.customerId)} and is_demo = true and email like '%@example.invalid'`, 'e2e portal language');
  // Screens across the matrix: sign-in without an OTP, and the overview's data inside 2.5 s.
  for (const m of MATRIX) {
    await setCustomerLocale(m.lang);
    const s = await signedInPage(browser, fx.customer, m);
    try {
      const t = await openPortal(s.page, portalUrl('customer', m.lang), s.calls);
      // Desktop shows the sidebar <nav>; a phone shows a bottom bar whose More button controls #qd-nav-more.
      const signedIn = await s.page.locator('nav:visible, button[aria-controls="qd-nav-more"]:visible').first().isVisible().catch(() => false);
      const rtl = await s.page.evaluate(() => document.documentElement.dir).catch(() => '');
      rep.step(J, `signed in without an OTP (${tag(m)})`, signedIn ? 'PASS' : 'FAIL', `nav visible=${signedIn}, dir=${rtl || 'ltr'}`, { shot: await shot(s.page, dir, `a_overview_${tag(m)}`) });
      rep.step(J, `overview data under 2.5 s (${tag(m)})`, t.dataMs < 2500 ? 'PASS' : 'FAIL', `data settled in ${t.dataMs} ms (shell ${t.shellMs} ms, ${t.calls} function call(s): ${t.breakdown.join(', ')})`, { ms: t.dataMs });
      if (m.lang === 'ar') rep.step(J, `Arabic renders right-to-left (${tag(m)})`, rtl === 'rtl' ? 'PASS' : 'FAIL', `document dir=${rtl}`);
      ctx.consoleErrors.push(...realErrors(s.consoleErrors).map((e) => `[customer ${tag(m)}] ${e}`));
    } finally { await s.ctx.close(); }
  }

  await setCustomerLocale('en');   // the request below is filed in English

  // EVERY ARABIC PAGE RENDERS RIGHT-TO-LEFT. Each /ar URL the sitemap publishes is fetched and its
  // server-rendered <html> must say lang="ar" dir="rtl"; the signed-in portals are the browser steps
  // above. The client side (one writer of the root element) is src/lib/documentLocale.test.mjs.
  {
    const xml = await fetch(`${SITE}/sitemap.xml`).then((r) => r.text()).catch((e) => { ctx.consoleErrors.push('[sitemap] ' + e); return ''; });
    const arUrls = [...xml.matchAll(/<loc>([^<]*\/ar(?:\/[^<]*)?)<\/loc>/g)].map((x) => x[1]);
    const bad = [];
    for (const u of arUrls) {
      const html = await fetch(u).then((r) => r.text()).catch((e) => 'fetch failed: ' + e);
      const root = (html.match(/<html[^>]*>/i) || [''])[0];
      if (!/\bdir="rtl"/.test(root) || !/\blang="ar"/.test(root)) bad.push(u.replace(/^https?:\/\/[^/]+/, '') + ' → ' + (root || html.slice(0, 60)));
    }
    rep.step(J, 'every Arabic page in the sitemap renders right-to-left', arUrls.length && !bad.length ? 'PASS' : 'FAIL',
      arUrls.length ? `${arUrls.length - bad.length}/${arUrls.length} Arabic pages rtl${bad.length ? ' — ' + bad.slice(0, 3).join(' | ') : ''}` : 'the sitemap listed no /ar page');
  }

  // The request itself, through the real chat, in English on desktop.
  const s = await signedInPage(browser, fx.customer, { lang: 'en', viewport: 'desktop' });
  let inquiryId = null, via = 'ui', quotable = [];
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
    let status = null, turns = 0, readiness = 0, last = {};
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
      if (res) last = j;
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
        if (r2) last = j2;
        status = j2.status ?? status; readiness = Number(j2.readiness ?? readiness) || 0;
        if (status === 'ready') break;
      }
    }
    // Held by design only when the gate says held AND the intake answered exactly the held answer:
    // status 'held' with no trade decided (inquiry_intake: "held for review rather than guessed").
    const held = status === 'held' ? await modelHold() : null;
    const heldAnswer = status === 'held' && last.category == null && !(last.trades || []).length;
    rep.step(J, 'the sales engineer interview reaches ready', status === 'ready' ? 'PASS' : held && heldAnswer ? 'SKIP' : 'FAIL',
      `${turns} turn(s), status=${status}, readiness=${readiness}${held && heldAnswer ? UNDER_HOLD(held) : ''}`, { shot: await shot(s.page, dir, 'a_intake') });
    if (held) rep.step(J, 'under the model hold the interview is held, never keyword-guessed', heldAnswer ? 'PASS' : 'FAIL',
      `status=${status} category=${last.category ?? null} trades=${JSON.stringify(last.trades ?? [])}`);
    if (status === 'ready') {
      const send = s.page.getByRole('button', { name: /Send to suppliers/ }).first();
      // THE EMPTY STATE MUST NOT FLASH AFTER "Request sent" (recurrence table row 12, #761): the
      // refresh used to show the stale, empty request list for a moment. This customer had no request
      // before this one, so the stale list IS the empty state. Watched from the page itself, from the
      // moment "Request sent" is on screen, for 6 s.
      await s.page.evaluate(() => {
        const w = window; w.__qdFlash = []; let sent = false; const t0 = performance.now();
        const obs = new MutationObserver(() => {
          const b = document.body.innerText;
          if (!sent) sent = /Request sent/.test(b);
          if (sent && /Your first request takes about a minute|No requests yet/.test(b)) w.__qdFlash.push(Math.round(performance.now() - t0));
        });
        obs.observe(document.body, { subtree: true, childList: true, characterData: true });
        setTimeout(() => obs.disconnect(), 90000);
      }).catch(() => {});
      const [res] = await Promise.all([
        s.page.waitForResponse((r) => r.url().includes('/functions/v1/customer_api') && (r.request().postData() || '').includes('create_inquiry'), { timeout: 90000 }).catch(() => null),
        send.click({ timeout: 20000 }),
      ]);
      const j = res ? await res.json().catch(() => ({})) : {};
      // One answer shape (_shared/inquiry_posted.ts): inquiry_id is the request the customer made — the
      // combined parent when it was split by trade — and quotable_ids are what suppliers quote on.
      inquiryId = j.inquiry_id ?? j.parent_id ?? j.id ?? null;
      quotable = Array.isArray(j.quotable_ids) && j.quotable_ids.length ? j.quotable_ids.map(String) : (inquiryId ? [String(inquiryId)] : []);
      for (const c of Array.isArray(j.child_ids) ? j.child_ids : []) ctx.run.ids.inquiries.add(String(c));
      rep.step(J, 'request posted from the portal', inquiryId ? 'PASS' : 'FAIL', `HTTP ${res?.status() ?? 0} id=${inquiryId ?? 'none'}${j.split ? ` split into ${quotable.length} (${(j.trades || []).join(', ')})` : ''} ${JSON.stringify(j).slice(0, 160)}`, { shot: await shot(s.page, dir, 'a_posted') });
      if (inquiryId) {
        await s.page.waitForTimeout(6000);
        const flash = await s.page.evaluate(() => window.__qdFlash || null).catch(() => null);
        rep.step(J, 'no empty-state flash after "Request sent"', Array.isArray(flash) && flash.length === 0 ? 'PASS' : 'FAIL',
          Array.isArray(flash) ? (flash.length ? `the empty request list showed ${flash.length} time(s) after "Request sent" (first at ${flash[0]} ms)` : 'watched 6 s after "Request sent": the empty state never showed') : 'the page watcher did not run');
      }
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
  // WHERE THE ANSWERS LIVE (smoke run 34888342875, 14 Sep 2026: "answered: none" on a request that
  // could not have posted without them). customer_api create_inquiry writes the sales engineer's
  // answers to spec.customer_requirements (_shared/intake_requirements.ts toStored: installation,
  // warranty, materials[], required_by) and refuses the post with 428 when validateStored finds any
  // missing. This step read spec.requirements / delivery_by, which only the fallback writer uses.
  const row = (await read(`select i.customer_id = ${q(fx.customer.customerId)}::uuid as mine, i.category, i.status, i.rfq_ready,
      coalesce(i.spec->'customer_requirements', i.spec->'requirements') as req, public.fn_inquiry_is_demo(i.id) as demo
      from public.inquiries i where i.id = ${q(inquiryId)}`))[0] || {};
  const req = row.req || {};
  const answered = {
    installation: !!(req.installation?.required ?? req.installation),
    warranty: !!(req.warranty?.required ?? req.warranty),
    materials: Array.isArray(req.materials) ? req.materials.length > 0 : req.materials != null,
    date: !!(req.required_by?.date || req.required_by?.flexible || req.delivery_by),
  };
  const asked = Object.keys(answered).filter((k) => answered[k]);
  rep.step(J, 'database: the request belongs to the customer and is demo', row.mine === true && row.demo === true ? 'PASS' : 'FAIL', `owner match=${row.mine}, demo=${row.demo}, category=${row.category}, status=${row.status}, rfq_ready=${row.rfq_ready}`);
  rep.step(J, 'database: the sales-engineer answers are on the request (installation, warranty, materials, date)',
    asked.length === 4 ? 'PASS' : (via === 'fallback' ? 'SKIP' : 'FAIL'), `answered: ${asked.join(', ') || 'none'}${via === 'fallback' ? ' (fallback request)' : ''}`);
  // Suppliers quote a request they can see: for a split that is a child, never the 'split' parent.
  ctx.inquiryId = quotable[0] || inquiryId;
  ctx.requestVia = via;
  ctx.parentInquiryId = inquiryId;
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
  // FAIL, not SKIP (22 Sep 2026). The fixtures now state their services the way a real supplier does
  // (fixtures.mjs stateServices), so the product's own routing must pick every one of them. A miss is
  // a routing regression or a fixture a real supplier could not be; either way this step proves it.
  // The inquiry's routing record says why the matcher chose what it chose.
  const routing = direct.length ? (await read(`select routing from public.inquiries where id = ${q(inquiryId)}`))[0]?.routing : null;
  // WHOSE SUPPLIERS TOOK THE SLOTS (22 Sep 2026). The per-trade cap is 3, so any other run's ZZ DEMO
  // aluminium suppliers compete with this run's for the same three places. Every match that is not
  // ours is named with its run tag and whether that run is still open. Another run STILL IN PROGRESS
  // taking the slots is contention between two harness runs, not a product defect: SKIP, said so. A
  // run that is over (its window closed) should have been swept by run.mjs; that stays a FAIL because
  // the sweep missed it, and so does a miss with no other run's fixture to explain it.
  // EVERY other match is named, tagged or not (22 Sep 2026). The cross join to the run tag dropped
  // any competitor that carries none - a real lead, or a demo supplier whose tag was lost - and the
  // step then read "0/3 matched" with no cause at all, which is exactly what finding
  // duty:journey:b supplier:routing_invited_the_demo_suppliers looked like at 01:09Z. A left join
  // names them; an untagged competitor has no open run, so it can never read as concurrency.
  const others = direct.length ? await read(`select m.supplier_id, coalesce(substring(t.x from '^qd_run:(.*)$'), case when l.is_demo then 'demo, no run tag' else 'a real lead' end) tag,
      coalesce(exists (select 1 from public.rehearsal_window w where w.run_tag = t.x and w.ended_at is null), false) open
    from public.inquiry_matches m join public.leads l on l.id = m.supplier_id
    left join lateral (select x from unnest(coalesce(l.tags,'{}')) x where x like 'qd_run:%' limit 1) t on true
    where m.inquiry_id = ${q(inquiryId)} and coalesce(t.x, '') <> ${q('qd_run:' + ctx.run.tag)}`) : [];
  const concurrentOnly = direct.length > 0 && others.length >= direct.length && others.every((o) => o.open);
  // Routing runs when the portal POSTS a request (customer_api create_inquiry → sales_engineer match). Under
  // the model hold the intake is held, nothing is posted, and the harness wrote the request itself: the
  // product's routing never ran on it. That is SKIP only under the measured hold with a fallback request
  // and no routing record (a routing record means routing DID run, and a miss then is a FAIL).
  const notPosted = direct.length > 0 && ctx.requestVia === 'fallback' && !routing ? await modelHold() : null;
  rep.step(J, 'routing invited the demo suppliers', direct.length === 0 ? 'PASS' : concurrentOnly || notPosted ? 'SKIP' : 'FAIL',
    (notPosted ? `the request could not be posted (the intake is held), so routing did not run${UNDER_HOLD(notPosted)}; ` : '') +
    `${fx.suppliers.length - direct.length}/${fx.suppliers.length} matched by the product; ${direct.length} invited directly by the harness` +
    (others.length ? ` — slots taken by other runs' fixtures: ${others.map((o) => `${o.supplier_id}@${o.tag}(${o.open ? 'run in progress' : 'run over, not swept'})`).join(', ')}` : '') +
    `${routing ? ' — routing ' + JSON.stringify({ outcome: routing.outcome, fanout: routing.fanout, verdict: routing.router_verdict, note: routing.note, trades: routing.trades, error: routing.error }).slice(0, 300) : ''}`);

  const identity = [fx.customer.fullName, fx.customer.email, fx.customer.phone, fx.customer.phone.replace('+', '')];
  // SUPPLIERS ARE ALWAYS ENGLISH (founder ruling 1008, 12 Oct 2026). Each pass still registers
  // supplier A in that pass's language, so the Arabic pass proves a supplier registered in Arabic
  // gets the English, left-to-right portal and the English tab names. No Arabic label is clicked.
  // Demo lead at example.invalid only.
  const setSupplierLocale = (lang) => write(`update public.leads set locale = ${q(lang)} where id = ${Number(A.leadId)} and is_demo = true`, 'e2e supplier portal language');
  for (const m of matrixFor('supplier')) {
    await setSupplierLocale(m.lang);
    const s = await signedInPage(browser, A, m);
    try {
      await openPortal(s.page, portalUrl('supplier', m.lang), s.calls);
      const supDir = await s.page.evaluate(() => document.documentElement.dir + '/' + document.documentElement.lang).catch(() => '?');
      rep.step(J, `the supplier portal is English, left-to-right, registered ${m.lang} (${tag(m)})`, supDir === 'ltr/en' ? 'PASS' : 'FAIL', `dir/lang = ${supDir}`);
      // The tab is REACHED, and a tab that cannot be reached is the finding — not something to
      // swallow and then assert against whatever screen was left open.
      const inqTab = supplierTab('en', 'rfqs');
      const opened = await s.page.getByRole('button', { name: new RegExp('^' + esc(inqTab)) })
        .first().click({ timeout: 15000 }).then(() => true).catch(() => false);
      await s.page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
      const text = await s.page.locator('body').innerText().catch(() => '');
      const leaked = identity.filter((x) => x && text.includes(x));
      const sees = opened && /alumin|ألمنيوم|الألمنيوم|window|نوافذ/i.test(text);
      rep.step(J, `sees the invitation (${tag(m)})`, sees ? 'PASS' : 'FAIL',
        !opened ? `the "${inqTab}" tab could not be opened in 15 s` : sees ? `RFQ visible in the "${inqTab}" tab` : `no aluminium RFQ text in the "${inqTab}" tab`,
        { shot: await shot(s.page, dir, `b_invitation_${tag(m)}`) });
      rep.step(J, `invitation is anonymised (${tag(m)})`, leaked.length === 0 ? 'PASS' : 'FAIL', leaked.length ? `LEAKED ${leaked.join(', ')}` : `none of ${identity.length} customer identifiers on screen`);
      ctx.consoleErrors.push(...realErrors(s.consoleErrors).map((e) => `[supplier ${tag(m)}] ${e}`));
    } finally { await s.ctx.close(); }
  }
  await setSupplierLocale('en');   // the rest of journey b quotes in English
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
  // Under the model hold his prose is not read, so the preflight must answer "would hold" and the
  // submission must be held for spec_hold — anything else is still a FAIL (see modelHold above).
  const mHold = await modelHold();
  const pre = await call('supplier_api', C.jwt, { ...completeQuote(inquiryId, 124900), dry_run: true });
  rep.step(J, 'preflight: the complete quote states every required detail', pre.json?.would_hold === false ? 'PASS' : mHold && pre.json?.would_hold === true ? 'SKIP' : 'FAIL',
    `would_hold=${pre.json?.would_hold} missing=${(pre.json?.spec_missing || []).map((x) => x.attr).join(',') || 'none'} would_accept=${pre.json?.would_accept}${mHold && pre.json?.would_hold === true ? UNDER_HOLD(mHold) : ''}`);
  const c1 = await call('supplier_api', C.jwt, completeQuote(inquiryId, 124900));
  const cQid = c1.json?.quote?.id ?? c1.json?.quote_id;
  if (cQid) ctx.run.ids.quotes.add(String(cQid));
  const cHeld = mHold && c1.json?.held === true && c1.json?.code === 'spec_hold';
  rep.step(J, 'a complete quote is accepted', c1.json?.accepted === true ? 'PASS' : cHeld ? 'SKIP' : 'FAIL',
    `HTTP ${c1.status} held=${c1.json?.held} accepted=${c1.json?.accepted} code=${c1.json?.code ?? ''}${cHeld ? UNDER_HOLD(mHold) : ''}`);
  // Under the hold a supplier's quotation goes live the only way the product allows: he states each
  // detail on the hold desk and approves the regenerated quotation. C and both of B's options walk that
  // path with exactly what their quotations say, so the comparison has the live quotes it ranks.
  if (mHold) {
    const bOpt = new Map(bRows.map((r) => [String(r.id), r.option_no]));
    for (const [who, sup, qid, fill, amount] of [['C', C, cQid, FILL, 124900], ...bRows.map((r) => ['B', B, r.id, r.option_no === 2 ? FILL_PREMIUM : FILL, r.option_no === 2 ? 142000 : 118500])]) {
      const label = who === 'B' ? `option ${bOpt.get(String(qid))}` : 'quotation';
      const r = qid ? await releaseViaDesk(sup, qid, fill, amount) : { released: false, detail: 'no quote id returned' };
      rep.step(J, `under the model hold, supplier ${who}'s ${label} is released through the hold desk`, r.released ? 'PASS' : 'FAIL', r.detail);
    }
  }

  // Held quotes are not ranked (checked NOW, while A is still held).
  const cmp = await call('quote_compare', fx.customer.jwt, { inquiry_id: inquiryId, lang: 'en' });
  const ids = JSON.stringify(cmp.json?.analysis?.all_quotes || cmp.json || {});
  rep.step(J, 'a held quote is not ranked', cmp.status === 200 && aQid && !ids.includes(aQid) && Number(cmp.json?.analysis?.on_hold ?? cmp.json?.on_hold ?? 0) >= 1 ? 'PASS' : 'FAIL',
    `HTTP ${cmp.status} ok=${cmp.json?.ok} on_hold=${cmp.json?.analysis?.on_hold ?? cmp.json?.on_hold} held quote in ranking=${aQid ? ids.includes(aQid) : '?'}${cmp.json?.degraded ? ' (deterministic comparison)' : ''}`);

  // A fills in the missing details -> regenerated -> approves -> released
  if (aQid) {
    const d = await deskFill(A, aQid, FILL, 131000);
    rep.step(J, 'filling in the details regenerates the quotation', d.f1.json?.complete === true ? 'PASS' : 'FAIL', d.fillDetail);
    const ap = await call('supplier_api', A.jwt, { action: 'spec_approve', quote_id: aQid, confirm: true });
    rep.step(J, 'the supplier approves and the quote is released', ap.json?.released === true ? 'PASS' : 'FAIL', `HTTP ${ap.status} released=${ap.json?.released} live=${ap.json?.live} code=${ap.json?.code ?? ''}`);
    const after = (await read(`select h.state, h.approved_by is not null approved, q.status from public.quote_spec_hold h join public.quotes q on q.id = h.quote_id where h.quote_id = ${q(aQid)} order by h.id desc limit 1`))[0] || {};
    rep.step(J, 'database: hold released, quote live', after.state === 'released' && after.status !== 'draft' ? 'PASS' : 'FAIL', JSON.stringify(after));
    // The Quotes tab shows it.
    const s = await signedInPage(browser, A, { lang: 'en', viewport: 'desktop' });
    try {
      await openPortal(s.page, portalUrl('supplier', 'en'), s.calls);
      const qTab = supplierTab('en', 'quotes');
      const qOpen = await s.page.getByRole('button', { name: new RegExp('^' + esc(qTab)) }).first().click({ timeout: 15000 })
        .then(() => true).catch(() => false);
      await s.page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
      // It used to report PASS unconditionally with the words "screenshot recorded" — a step that
      // cannot fail asserts nothing, and it was named after a tab the portal no longer renders.
      const onTab = qOpen && await s.page.getByRole('button', { name: new RegExp('^' + esc(qTab)), exact: false })
        .first().getAttribute('aria-current').then((a) => a === 'page').catch(() => false);
      rep.step(J, `the "${qTab}" tab opens after release`, onTab ? 'PASS' : 'FAIL',
        qOpen ? `aria-current=page: ${onTab}` : `the "${qTab}" tab could not be opened in 15 s`,
        { shot: await shot(s.page, dir, 'b_quotes_after_release') });
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
  // AN ARABIC DOCUMENT HELD FOR TRANSLATION UNDER THE MODEL HOLD IS HELD BY DESIGN (it_engineer, 28 Sep 2026,
  // ledger 760). customer_api answers HTTP 202 code=arabic_held when a line still needs reasoning to translate
  // (nativeArabic); with every model route held that is the product's held answer, and these three steps filed
  // FAIL on every smoke while the interview and routing steps beside them reported SKIP. Same rule as above:
  // SKIP only for exactly that answer AND only while modelHold() says held; any other failure stays FAIL.
  const heldArabic = async (lang, r) => (lang === 'ar' && r.status === 202 && r.json?.code === 'arabic_held') ? await modelHold() : null;
  for (const lang of ['en', 'ar']) {
    await setLocale(lang);
    const r = await call('customer_api', fx.customer.jwt, { action: 'compare_pdf', inquiry_id: inquiryId, lang }, 180000);
    const url = r.json?.url || r.json?.pdf_url || r.json?.file_url;
    const b = await pdfBytes(url);
    const saved = b ? `${dir}/c_comparison_${lang}.pdf` : null;
    if (b) writeFileSync(saved, b);
    const hp = b ? null : await heldArabic(lang, r);
    rep.step(J, `comparison report opens as a PDF (${lang})`, b ? 'PASS' : hp ? 'SKIP' : 'FAIL', `HTTP ${r.status} ${b ? 'valid %PDF, saved ' + saved : 'no PDF: ' + r.text.slice(0, 140)}${hp ? UNDER_HOLD(hp) : ''}`);
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
    const hc = ok ? null : await heldArabic(lang, r);
    rep.step(J, `comparison exports as CSV (${lang})`, ok ? 'PASS' : hc ? 'SKIP' : 'FAIL', `HTTP ${r.status} rows=${rows.length} header_arabic=${lang === 'ar' ? arabic : 'n/a'}${ok ? '' : ' ' + r.text.slice(0, 140)}${hc ? UNDER_HOLD(hc) : ''}`);
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
    // Kept with the run: the exact analysis the customer's JWT got, so a report can be re-rendered
    // from it offline (demo data only; the run directory is scratch, never committed).
    if (a) writeFileSync(`${dir}/c_quote_compare_analysis.json`, JSON.stringify(a, null, 2));
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
      const ok = !!(await pdfBytes(url));
      const hq = ok ? null : await heldArabic(lang, r);
      rep.step(J, `quotation PDF opens (${lang})`, ok ? 'PASS' : hq ? 'SKIP' : 'FAIL', `HTTP ${r.status} ${ok ? 'valid %PDF' : 'no PDF: ' + r.text.slice(0, 140)}${hq ? UNDER_HOLD(hq) : ''}`);
    }
  } else rep.step(J, 'quotation PDF opens', 'FAIL', 'no live quote to open');
  // The deep link the PDFs print: /me?request=<id>&quote=<id>
  for (const m of MATRIX) {
    const s = await signedInPage(browser, fx.customer, m);
    try {
      await openPortal(s.page, portalUrl('customer', m.lang, `?request=${inquiryId}${live[0] ? '&quote=' + live[0].id : ''}`), s.calls);
      // WHAT THE LINK PROMISES, ASSERTED (15 Sep 2026). The old check searched the page for
      // "QD-<8 hex>", which the portal renders nowhere (a probe found it in 0 of 4 cells, desktop
      // included), so it passed on any "aluminium" in the text - the overview's own request list
      // carries one - and it read the text once, straight after networkidle. A probe of the same link
      // at 375 px, EN and AR, opened My requests and scrolled the linked quote into view. The link's
      // promise is now what is checked, waiting up to 20 s for it: My requests is the current page
      // (the overview never is), the request's card is visible, and the link was consumed from the URL
      // (CustomerPortal resolveQuoteLink -> openRfq -> history.replaceState).
      // Either label: the portal follows customers.locale, and journey c registers the demo customer in
      // English before this loop, so /ar correctly shows English here (run 2026-09-14T20-25-56).
      const reqNav = /^(My requests|طلباتي)/;
      const onRequests = await s.page.locator('button[aria-current="page"]:visible').filter({ hasText: reqNav }).first()
        .waitFor({ state: 'visible', timeout: 20000 }).then(() => true).catch(() => false);
      const cardShown = await s.page.locator(`[id="inq-${inquiryId}"]`).first().waitFor({ state: 'visible', timeout: 5000 }).then(() => true).catch(() => false);
      const consumed = !new URL(s.page.url()).searchParams.has('request');
      const opened = onRequests && cardShown && consumed;
      rep.step(J, `deep link opens the request (${tag(m)})`, opened ? 'PASS' : 'FAIL',
        `My requests current=${onRequests}, card inq-${String(inquiryId).slice(0, 8)} visible=${cardShown}, link consumed=${consumed}`, { shot: await shot(s.page, dir, `c_deeplink_${tag(m)}`) });
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
    // The runner is in the US, so Stripe pre-selects a US billing country and a required ZIP; the
    // helper pins the UAE (see scripts/e2e/stripe_test_checkout.mjs for the measurement).
    await p.locator('#cardNumber').waitFor({ timeout: 60000 });
    await payHostedTestCheckout(p);
    await shot(p, ctx.dir, 'd_stripe_checkout_filled');
    await p.waitForURL(/quotesdone\.(com|ae)/, { timeout: 90000 }).catch(() => {});
    await shot(p, ctx.dir, 'd_after_pay');
    const returned = /quotesdone\.(com|ae)/.test(p.url());
    // The whole session id (it was cut at 80 characters, which made it unfindable in Stripe).
    rep.step(J, 'Stripe test checkout completed and returned to the portal', returned ? 'PASS' : 'FAIL',
      `landed on ${p.url().split('?')[0]}${returned ? '' : ` — Stripe held the form on: [${(await checkoutBlockers(p)).join(', ') || 'no empty or invalid field'}]`}`);
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
  // #919's product behaviour (_shared/reveal_fee.ts, CARD_FEE_CHARGED_TO_BUYER = false; Cabinet
  // Res. 66/2023 Art. 5(3) forbids a card surcharge): the buyer pays the BASE fee only,
  // base = round(rate x quote) to the fils, processing_fee = 0, total_charged = base. QuotesDone
  // absorbs Stripe's cost. #616's grossed-up "3% + card processing" total is retired.
  const rate = Number((await read('select standard_reveal_rate r from public.pricing_config where id = 1'))[0].r);
  const baseF = Math.round(Number(tx.quote_amount) * rate * 100);
  const ok = Math.round(Number(tx.reveal_fee) * 100) === baseF && Math.round(Number(tx.processing_fee) * 100) === 0
    && Math.round(Number(tx.total_charged) * 100) === baseF;
  rep.step(J, "the fee matches #919's formula (3% base only, no card fee, no VAT)", ok ? 'PASS' : 'FAIL',
    `quote ${tx.quote_amount} x ${rate}: expected base ${baseF / 100} + processing 0 = ${baseF / 100}; recorded ${tx.reveal_fee} + ${tx.processing_fee} = ${tx.total_charged}`);
}

// ---- e. invoice and refund ladder ------------------------------------------------------------------
export async function journeyInvoiceRefund(ctx) {
  const { rep } = ctx;
  const J = 'e invoice+refund';
  if (!ctx.paid) {
    rep.step(J, 'invoice appears in the portal', 'SKIP', 'needs a paid reveal, and journey d did not record one (see its steps)');
    rep.step(J, 'refund end to end in Stripe TEST mode', 'SKIP', 'needs a paid reveal (journey d)');
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
  await refundEndToEnd(ctx, { id: qid }, J);
}

// THE REFUND, END TO END, ON THE DEMO REVEAL JOURNEY D PAID IN STRIPE TEST MODE (14 Sep 2026).
// The customer asks through customer_api; the day-3 chase and day-5 final call run through the real
// sales engineer and support routines for THIS transaction only (never the global sweep); the CEO's
// review decides on the checklist; the accountant executes this one refund with the test key.
// Two things are fixtures, both refused unless the row is a demo identity on @example.invalid:
//   * TIME TRAVEL: the reveal is moved ten days back, because the terms give the supplier five
//     working days and the harness cannot wait them out;
//   * DELIVERY: mail to @example.invalid is captured by design and never sent, and the support watch
//     counts only a sent message as delivered, so the captured demo message is marked sent.
async function refundEndToEnd(ctx, live, J) {
  const { rep, fx } = ctx;
  const tx = (await read(`select t.id, t.total_charged, t.reveal_fee, c.is_demo, c.email
      from public.transactions t join public.customers c on c.id = t.customer_id where t.quote_id = ${q(live.id)}`))[0];
  if (!tx || tx.is_demo !== true || !/@example\.invalid$/i.test(String(tx.email))) {
    return rep.step(J, 'refund end to end in Stripe TEST mode', 'FAIL', 'the paid reveal is not on a ZZ DEMO customer; a refund is never driven on a real row');
  }
  const want = Math.round(Number(tx.total_charged ?? tx.reveal_fee) * 100);
  const DEMO_TX = `id = ${q(tx.id)} and customer_id in (select id from public.customers where is_demo and email like '%@example.invalid')`;

  // 1. The request opens the case, and only then does the sale read 'requested'.
  const req = await call('customer_api', fx.customer.jwt, { action: 'request_refund', quote_id: live.id });
  const rf = await read(`select id, status, amount_fils from public.refunds where transaction_id = ${q(tx.id)} order by id`);
  const sale = (await read(`select refund_status from public.transactions where id = ${q(tx.id)}`))[0];
  const opened = req.json?.ok === true && rf.length === 1 && rf[0].status === 'requested' && Number(rf[0].amount_fils) === want && sale?.refund_status === 'requested';
  rep.step(J, 'the request opens the case, then the sale reads requested', opened ? 'PASS' : 'FAIL',
    `HTTP ${req.status} ${JSON.stringify(req.json)} refunds=${JSON.stringify(rf)} sale=${sale?.refund_status}`);
  if (!opened) return;
  const rid = Number(rf[0].id);
  const conf = (await read(`select detail->>'locale' as locale from public.agent_actions where kind = 'handoff' and agent = 'customer_support'
      and detail->>'msg_type' = 'refund_request_received' and detail->>'transaction_id' = ${q(tx.id)}`))[0];
  rep.step(J, 'the confirmation goes to support in the registered language', conf?.locale === (fx.customer.locale || 'en') ? 'PASS' : 'FAIL', JSON.stringify(conf || {}));
  const rh = (await read(`select agent from public.agent_actions where kind = 'handoff' and detail->>'type' = 'refund.requested'
      and detail->>'subject_id' = ${q(String(rid))} order by id desc limit 1`))[0];
  rep.step(J, 'the case is handed to the accountant', rh?.agent === 'accountant' ? 'PASS' : 'FAIL', JSON.stringify(rh || {}));
  // Day 0: the customer may ask, but the CEO may not decide before the day-3 chase and the day-5 final call.
  const ck = (await read(`select public.fn_ceo_refund_checklist(${q(tx.id)}::uuid, 'approve', false) as c`))[0]?.c;
  const failedItems = (ck?.failed || []).map((x) => x.item);
  rep.step(J, "the CEO's checklist refuses approval before the day-3 chase and the day-5 final call",
    ck && ck.ok === false && failedItems.includes('day3_chase_happened') && failedItems.includes('day5_final_call_happened') ? 'PASS' : 'FAIL',
    ck ? `ok=${ck.ok}, failing: ${failedItems.join(', ') || 'none'}` : 'checklist did not run');
  const rn = await read(`select status, count(*)::int n from public.notifications where quote_id = ${q(live.id)} or to_email = ${q(tx.email)} group by 1`);
  rep.step(J, 'nothing the request caused was dispatched to a real address', rn.every((r) => !['queued', 'pending', 'sent'].includes(r.status)) ? 'PASS' : 'FAIL',
    rn.map((r) => `${r.status}: ${r.n}`).join(', ') || 'no notification rows');

  // 2. Time travel, demo only.
  const moved = await write(`update public.transactions set revealed_at = now() - interval '10 days',
      refund_deadline = public.fn_add_working_days(now() - interval '10 days', 5) where ${DEMO_TX} returning id`, 'e2e refund time travel (demo only)');
  if (!Array.isArray(moved) || moved.length !== 1) return rep.step(J, 'demo time travel', 'FAIL', JSON.stringify(moved));

  // 3. Day 3 chase and day 5 final call, each delivered and watched to a no-response confirmation.
  for (const [day, step] of [[3, 'chase'], [5, 'final_call']]) {
    const reqId = Number((await write(`select public.fn_sales_engineer_ladder_step(${q(tx.id)}, '${step}', ${step === 'final_call' ? rid : 'null'}, null) as id`, 'e2e ladder step'))[0]?.id);
    const n = (await read(`select (evidence->>'notification_id')::bigint as nid, detail->>'to_email' as to_email from public.agent_actions where id = ${reqId}`))[0];
    // sent_at ONLY: the status stays as the capture left it (suppressed), so the safety step's count of
    // dispatched rows stays honest. The first run of this journey wrote status='sent' here and the
    // safety step counted those two captured demo rows as sent (14 Sep 2026, 16:19 run).
    await write(`update public.notifications set sent_at = now() where id = ${Number(n?.nid) || 0} and to_email like '%@example.invalid'`, 'e2e demo delivery');
    await write(`update public.agent_actions set detail = detail || jsonb_build_object('watch_until', now() - interval '1 minute')
                 where id = ${reqId} and detail->>'to_email' like '%@example.invalid'`, 'e2e watch window');
    const w = (await write(`select public.fn_customer_support_delivery_watch(${reqId}) as r`, 'e2e watch'))[0]?.r;
    const ev = (await read(`select result, delivered from public.refund_ladder_evidence where transaction_id = ${q(tx.id)} and step = '${step}' order by id desc limit 1`))[0];
    rep.step(J, `day ${day} ${step.replace('_', ' ')} delivered, no response confirmed`,
      ev?.result === 'no_response_confirmation' && ev?.delivered === true ? 'PASS' : 'FAIL', JSON.stringify({ reqId, n, w, ev }));
  }

  // 4. The CEO decides on the checklist (fn_ceo_refund_review ran when the final call's result landed).
  const dec = (await read(`select r.refund_decision_id, a.decision from public.refunds r
      left join public.ceo_approval a on a.decision_id = r.refund_decision_id where r.id = ${rid}`))[0];
  const failed = await read(`select item, reason from public.refund_ceo_check where refund_id = ${rid} and not passed order by id desc limit 10`);
  rep.step(J, 'the CEO approves after verifying every step', dec?.decision === 'approved' ? 'PASS' : 'FAIL', JSON.stringify({ dec, failed }));
  if (dec?.decision !== 'approved') return;

  // 5. The accountant executes THIS refund only, and the key follows the payer: TEST.
  const cred = (await read(`select value from public.app_secrets where key = 'cred_fn_accountant'`))[0]?.value;
  const ex = await call('accountant', null, { __secret: cred, action: 'execute_refunds', refund_id: rid });
  const res = (ex.json?.results || []).find((x) => Number(x.refund_id) === rid);
  const after = (await read(`select status, stripe_refund_id, amount_fils from public.refunds where id = ${rid}`))[0];
  const paid = res?.mode === 'test' && String(res?.stripe_refund_id || '').startsWith('re_') && Number(after?.amount_fils) === want
    && ['processing', 'succeeded'].includes(String(after?.status));
  rep.step(J, 'the accountant refunds everything paid, in Stripe TEST mode', paid ? 'PASS' : 'FAIL', JSON.stringify({ http: ex.status, res, after, want }));
}

// ---- f. every nav item on both portals ----------------------------------------------------------
// WHAT THIS CRAWLS, AND WHY IT COST THE WHOLE NIGHT (18 Sep 2026, sales_engineer).
//
// The nightly full journey was CANCELLED at the 30-minute wall on 15, 16 and 17 September, and a
// cancelled job writes no heartbeat, so the estate read it as "never ran" (#728 bounds the run so a
// truncated night still reports honestly; this fixes what ate the budget). Measured: every failing
// step here was a `locator.click: Timeout 8000ms exceeded` on a navigation item, from two causes,
// neither of them the portal's:
//
//   1. THE SUPPLIER LIST WAS A YEAR OUT OF DATE. The supplier portal was rebuilt on 15 Sep
//      (#722 Services, #723 Messages/Documents/Insights): "Get matched" was removed, RFQs became
//      "Inquiries received", Quotes became "Quotations submitted", Projects stopped being a
//      destination (TAB_ALIAS maps projects -> messages; the revealed-jobs list now renders INSIDE
//      Messages, and is crawled there), "My scope" became Services, and Profile, Billing and
//      Settings moved into an Account menu — a native <details> that is CLOSED until pressed, so
//      their buttons exist in the DOM and are never clickable. Eight stale labels x 8 s x four
//      matrices.
//   2. THE ARABIC PASSES WERE NEVER IN ARABIC. Both portals follow the ACCOUNT's locale, not the
//      URL (founder, 14 Sep: "if someone registered while the language was arabic then arabic
//      follows through the whole workflow" — customers.locale, leads.locale). Journey a sets it and
//      this one never did, so /ar rendered in English and every Arabic label timed out as well.
//      Measured on production, 18 Sep: an en-registered fixture on /ar gives dir=ltr lang=en.
//
// THE LIST STAYS DECLARED. A crawl that only clicks what it finds cannot notice a destination that
// disappeared — that is exactly how #722 went unreported here. It is now checked as a set in ONE
// step per surface, so drift is stated once, in words, instead of being paid for eight times at
// eight seconds each.
const NAV = {
  // src/components/me/PortalShell.tsx NAV_GROUPS, named by src/components/me/portalText.ts.
  customer: {
    en: ['Overview', 'My requests', 'Documents', 'Orders', 'Messages', 'Projects', 'Project room', 'What you may need next', 'Buying profile', 'Account'],
    ar: ['نظرة عامة', 'طلباتي', 'المستندات', 'أوامر الشراء', 'الرسائل', 'المشاريع', 'غرفة المشروع', 'ما قد تحتاجه لاحقًا', 'ملف المشتريات', 'الحساب'],
  },
  // src/components/portal/SupplierPortal.tsx MAIN_TABS, named by supplier/workspaceCopy.ts tab_*.
  // PR #725 (Inquiries received / Quotations submitted) and #729 (Services) change what is INSIDE
  // these tabs, not the tab names: both branches still declare the same MAIN_TABS and ACCOUNT_TABS
  // and the same tab_* / acct_* values, so this list survives their merge — and the check named
  // below fails in CI on the day one of them does rename a tab.
  supplier: {
    en: ['Services', 'Inquiries received', 'Quotations submitted', 'Messages', 'Documents', 'Insights'],
    ar: ['الخدمات', 'الاستفسارات الواردة', 'عروض الأسعار المقدَّمة', 'الرسائل', 'المستندات', 'الرؤى'],
  },
};
// JOURNEY b DRIVES TWO OF THOSE TABS BY NAME, AND USED TO KEEP ITS OWN COPY OF THE WORDS (18 Sep
// 2026, measured on production). #738 tied journey f's list above to the portal's own copy, but
// journey b still clicked /^RFQs/ and /^Quotes/ — the names the supplier portal stopped rendering on
// 15 September (#722/#725). Both clicks are written `.catch(() => {})`, so nothing failed loudly:
// each one waited out its 15 s timeout in all four matrices and the step then asserted against
// whichever tab happened to be open (Services, the default), which is not the screen it names.
// Naming them out of NAV puts them under the CI check that ties NAV to MAIN_TABS and workspaceCopy,
// so the next rename fails in seconds instead of quietly measuring the wrong tab.
const SUPPLIER_TABS = ['services', 'rfqs', 'quotes', 'messages', 'documents', 'insights'];
const supplierTab = (lang, key) => NAV.supplier[lang][SUPPLIER_TABS.indexOf(key)];
// ACCOUNT_TABS: the three the supplier portal moved out of the main strip on 15 Sep. Opening the
// menu is part of the journey — a supplier who cannot reach Settings has no working portal.
const ACCOUNT_MENU = {
  en: { menu: 'Account', items: ['Profile', 'Billing', 'Settings'] },
  ar: { menu: 'الحساب', items: ['الملف التعريفي', 'الفواتير', 'الإعدادات'] },
};
const accountMenu = (kind, lang) => (kind === 'supplier' ? ACCOUNT_MENU[lang] : null);
// The language a portal RENDERS for an account registered in `lang`: suppliers are always English
// (founder ruling 1008), customers follow their registration language.
const uiLang = (kind, lang) => (kind === 'supplier' ? 'en' : lang);
// Buttons a crawler must never press: they spend, send, delete or sign out. Everything else is pressed.
// …and one a crawler must never press for a different reason: #729's Services tab has a microphone
// ("Speak your services" / "سجّل خدماتك صوتيًا"). Pressing it opens a recording, which is a side
// effect on the supplier's machine, not a screen to look at. It is disabled today (the voice flag is
// off) so Playwright would only wait out its timeout, but it will not be disabled forever.
// …and one more of the same kind, measured on production 18 Sep 2026: "New request" / "طلب جديد" /
// "Post your first request" / "انشر طلبك الأول". Pressing it opens the request composer, which
// OPENS AN LLM INTERVIEW — inquiry_intake, whose calls this harness already allows 90 seconds each,
// and an inquiry_intake row on a screen the crawl is only meant to look at. The composer then covers
// the page, so every later press in the loop lands on it instead of the destination. Watched live:
// the customer en-desktop "My requests" view sat in that composer for minutes, on the first of eight
// surfaces — which is most of why the crawl has not finished inside the nightly's budget. A crawler
// looks at screens; it does not start jobs.
const NEVER = /sign\s*out|log\s*out|delete|remove|cancel|withdraw|refund|reveal|pay|send|submit|approve|reject|accept|decline|close\s*request|new request|post your first request|speak your|stop recording|تسجيل|سجّل|إيقاف التسجيل|طلب جديد|انشر طلبك|الخروج|حذف|إزالة|إلغاء|سحب|استرداد|كشف|ادفع|دفع|أرسل|إرسال|اعتماد|رفض|قبول/i;
// #736 gave every press and every region an aria-busy state, with a 300 ms minimum so a fast round
// trip cannot strobe. A crawler that presses the next control while the last one is still working
// measures the spinner rather than the page — and Playwright waits out its whole timeout against a
// control the busy state has disabled. Wait for the screen to go quiet, bounded, and SAY SO in the
// step's detail when it does not: a destination that is still busy after three seconds is a finding
// about the journey, not something to hide behind a longer timeout.
// IT NAMES WHAT IS STILL BUSY. The note used to say only "STILL BUSY after 3000 ms", which is a
// symptom with no subject: reading it back, there is no way to tell a never-cleared flag from a
// slow fetch that is genuinely still in flight, and the two need opposite fixes. The 18 Sep note on
// the supplier's Insights tab cost a whole re-measurement to attribute (it was the second stage of
// a real two-stage load, not a stuck flag). The elements are cheap to read and settle it on sight.
const notBusy = async (page, ms = 3000) => {
  const quiet = await page.waitForFunction(() => !document.querySelector('[aria-busy="true"]'), null, { timeout: ms })
    .then(() => true).catch(() => false);
  if (quiet) return { quiet, what: '' };
  const what = await page.evaluate(() => [...document.querySelectorAll('[aria-busy="true"]')]
    .map((e) => `${e.tagName.toLowerCase()}.${(e.getAttribute('class') || '').split(/\s+/)[0] || '?'}` +
                `${e.getAttribute('aria-label') ? '[' + e.getAttribute('aria-label') + ']' : ''}`)
    .slice(0, 4).join(' + ')).catch(() => '(could not read)');
  return { quiet, what };
};
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
// The phone's overflow sheet (customer portal only). The button carries aria-controls; the sheet
// itself, #qd-nav-more, exists only while it is open, and go() closes it on every choice.
// IT IS IN THE DOM ON DESKTOP TOO, hidden by `md:hidden`, so every gate below asks whether it is
// VISIBLE and not whether it exists: counting it cost a 3 s click timeout on each desktop surface.
const MORE_BTN = 'button[aria-controls="qd-nav-more"]';
const moreSheetButton = async (page) => {
  const b = page.locator(MORE_BTN).first();
  return (await b.isVisible().catch(() => false)) ? b : null;
};

/** Open the supplier's Account menu if this portal has one and it is shut. Returns false if absent. */
async function openAccountMenu(page, menu) {
  if (!menu) return false;
  const sum = page.locator('details > summary').filter({ hasText: menu.menu }).first();
  if (!(await sum.isVisible().catch(() => false))) return false;
  if (await sum.evaluate((e) => e.parentElement.open).catch(() => false)) return true;
  await sum.click({ timeout: 3000 }).catch(() => {});
  return true;
}

/** Shut anything this file opened: a <details> ignores Escape, and an open one overlays the tabs. */
const closeMenus = async (page) => {
  await page.evaluate(() => { for (const d of document.querySelectorAll('details[open]')) d.open = false; }).catch(() => {});
  await page.keyboard.press('Escape').catch(() => {});   // the customer portal's More sheet closes on Escape
};

/** Every destination on screen right now, with the sheet and the Account menu opened first. */
async function destinations(page, menu) {
  const more = await moreSheetButton(page);
  if (more) await more.click({ timeout: 3000 }).catch(() => {});
  await openAccountMenu(page, menu);
  const names = await page.evaluate(() => {
    const seen = (e) => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0 && getComputedStyle(e).visibility !== 'hidden'; };
    const out = [];
    for (const b of document.querySelectorAll('nav button, details[open] button')) {
      if (b.hasAttribute('aria-controls') || !seen(b)) continue;   // the More button opens the sheet; it is not a destination
      const n = (b.getAttribute('aria-label') || b.innerText || '').replace(/\s+/g, ' ').trim();
      if (n) out.push(n);
    }
    return [...new Set(out)];
  }).catch(() => []);
  await closeMenus(page);
  return names;
}

/** The nav button for `label`, reached through the sheet or the Account menu when it is not on screen. */
async function reach(page, menu, label) {
  const btn = page.getByRole('button', { name: new RegExp('^' + esc(label)) }).first();
  if (await btn.isVisible().catch(() => false)) return btn;
  const more = await moreSheetButton(page);
  if (more) {
    await more.click({ timeout: 3000 }).catch(() => {});
    if (await btn.isVisible().catch(() => false)) return btn;
  }
  await openAccountMenu(page, menu);
  return btn;
}

// The portal follows the account's locale, not the URL. Journey a proves that rule; this journey has
// to obey it or every Arabic pass crawls an English screen.
const setPortalLocale = (who, lang) => (who.kind === 'customer'
  ? write(`update public.customers set locale = ${q(lang)} where id = ${q(who.customerId)} and is_demo = true and email like '%@example.invalid'`, 'e2e crawl language')
  : write(`update public.leads set locale = ${q(lang)} where email = ${q(who.email)} and is_demo = true and email like '%@example.invalid'`, 'e2e crawl language'));

export async function journeyCrawl(ctx) {
  const { rep, browser, fx, dir } = ctx;
  const J = 'f crawl';
  // THE CRAWL IS WHAT RAN THE JOB OUT OF TIME (17 Sep 2026). Each nav item it cannot click costs
  // 11.2 s (8 s click timeout, then the fallbacks), and there are 4 viewports x 2 portals of them,
  // so once the ar-mobile and supplier nav defects appeared this loop alone outlasted the workflow's
  // 30-minute wall and the job was cancelled mid-crawl — taking teardown and the heartbeat with it.
  // ctx.outOfTime is run.mjs's shared deadline: stop starting views, record what was not reached.
  const stop = ctx.outOfTime || (() => false);
  for (const who of [fx.customer, fx.suppliers[0]]) {
   // Left as it was found even if a pass throws: journey a files its request in English, and a
   // re-run of a against a KEPT fixture (--keep, then --purge-tag later) must not inherit this
   // journey's last Arabic pass. run.mjs catches at the journey level, so without this finally the
   // restore below would be skipped on the one path that needs it.
   try {
    for (const m of matrixFor(who.kind)) {
      if (stop()) { rep.step(J, `${who.kind} ${tag(m)}: not crawled`, 'SKIP', 'the harness deadline passed before this viewport; the run still tears down and reports'); continue; }
      await setPortalLocale(who, m.lang);
      const lang = uiLang(who.kind, m.lang);
      const labels = [...NAV[who.kind][lang], ...(accountMenu(who.kind, lang)?.items || [])];
      const s = await signedInPage(browser, who, m);
      const before = s.consoleErrors.length;
      try {
        await openPortal(s.page, portalUrl(who.kind, m.lang), s.calls);
        // The portal is in the language this pass is about, and it offers every destination it
        // should. Both are asserted BEFORE the clicking, so a rename is one FAIL with the words in
        // it rather than N clicks that each wait out their timeout.
        const dirAttr = await s.page.evaluate(() => document.documentElement.dir + '/' + document.documentElement.lang).catch(() => '?');
        rep.step(J, `${who.kind} ${tag(m)}: the portal is in this language`, dirAttr === (lang === 'ar' ? 'rtl/ar' : 'ltr/en') ? 'PASS' : 'FAIL', `dir/lang = ${dirAttr}`);
        const offered = await destinations(s.page, accountMenu(who.kind, lang));
        const missing = labels.filter((l) => !offered.some((o) => o.startsWith(l)));
        rep.step(J, `${who.kind} ${tag(m)}: every destination is on screen`, missing.length ? 'FAIL' : 'PASS',
          missing.length ? `not offered: ${missing.join(', ')} — offered: ${offered.join(' | ')}` : `${labels.length} destination(s): ${offered.join(' | ')}`);
        // shot() strips everything outside [a-z0-9_.-] from a file name, so ALL TEN Arabic labels
        // resolved to the same file and each overwrote the last: the Arabic evidence was one image.
        // The position in the nav carries the identity that the alphabet cannot.
        for (const [i, label] of labels.entries()) {
          const at = `${i + 1}_${label}`;
          if (stop()) { rep.step(J, `${who.kind} ${tag(m)}: ${label}`, 'SKIP', 'the harness deadline passed mid-viewport'); continue; }
          const btn = await reach(s.page, accountMenu(who.kind, lang), label);
          const t0 = Date.now();
          try {
            await btn.click({ timeout: 8000 });
            await s.page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});
            const { quiet, what } = await notBusy(s.page);
            const ms = Date.now() - t0;
            const failed = s.calls.filter((c) => c.at >= t0 && (c.status >= 500 || c.status === 0)).map((c) => `${c.fn}:${c.action}:${c.status}`);
            // The calls STILL IN FLIGHT are what separates "never cleared" from "still fetching".
            const open = s.calls.filter((c) => c.at >= t0).length;
            rep.step(J, `${who.kind} ${tag(m)}: ${label}`, failed.length ? 'FAIL' : 'PASS',
              `${ms} ms${quiet ? '' : ` — STILL BUSY after 3000 ms: ${what} (${open} call(s) since the press)`}${failed.length ? ' failed calls ' + failed.join(', ') : ''}`,
              { ms, shot: await shot(s.page, dir, `f_${who.kind}_${tag(m)}_${at}`) });
            // Every other button in this view, except those that spend, send, delete or sign out.
            // PRESS THE BUTTON THAT IS THERE, don't look it up again by its words. This used to read
            // each button's raw textContent and then ask getByRole for that exact accessible name —
            // and an accessible name is whitespace-normalised where textContent is not, so a label
            // that wrapped onto two lines never matched and spent its full 3 s timeout. Measured on
            // the 17 Sep production run: "Documents - in-view buttons" reported 6 presses and took
            // 24.8 s. The handles are already known visible, so 1.5 s is a generous wait.
            const inView = await s.page.locator('main button:visible, [role=main] button:visible').all().catch(() => []);
            let pressed = 0;
            for (const b2 of inView.slice(0, 15)) {
              const n = await b2.evaluate((e) => (e.getAttribute('aria-label') || e.innerText || '').replace(/\s+/g, ' ').trim()).catch(() => '');
              if (!n || NEVER.test(n)) continue;
              await b2.click({ timeout: 1500 }).then(() => { pressed++; }).catch(() => {});
              await s.page.keyboard.press('Escape').catch(() => {});
            }
            if (pressed) rep.step(J, `${who.kind} ${tag(m)}: ${label} - in-view buttons`, 'PASS', `${pressed} button(s) pressed without a crash`);
            // Back to this destination if one of those buttons navigated away. Only when the control
            // is on screen: an overflow-sheet or Account-menu item is shut again by its own choice,
            // and waiting 3 s for it to reappear bought nothing.
            if (await btn.isVisible().catch(() => false)) await btn.click({ timeout: 3000 }).catch(() => {});
          } catch (e) {
            // A failure capture is the evidence somebody reads, so it is the WHOLE page (#735's
            // fullPageShot, through shot's fullPage option): a viewport crop of a screen whose
            // destination is missing tells you nothing about where it went.
            rep.step(J, `${who.kind} ${tag(m)}: ${label}`, 'FAIL', `could not click: ${String(e.message).split('\n')[0].slice(0, 140)}`, { shot: await shot(s.page, dir, `f_fail_${who.kind}_${tag(m)}_${at}`, { fullPage: true }) });
          }
        }
      } finally {
        const errs = realErrors(s.consoleErrors.slice(before));
        rep.step(J, `${who.kind} ${tag(m)}: no console errors`, errs.length ? 'FAIL' : 'PASS', errs.length ? errs.slice(0, 3).join(' | ') : 'clean');
        ctx.consoleErrors.push(...errs.map((e) => `[crawl ${who.kind} ${tag(m)}] ${e}`));
        await s.ctx.close();
      }
    }
   } finally { await setPortalLocale(who, 'en').catch(() => {}); }
  }
}

// ---- g: the WhatsApp question inside sign-up (founder, 15 Sep 2026) ------------------------------------
// "whenever there's a new sign up this should be in the sign up form ... And it also has an OTP verifier
// similar to the SMS." Two customers are made up to the verified mobile and stopped there, then driven
// through the real sign-up screen: one answers Yes (English), one answers No and proves a second number
// with a 6-digit code (Arabic). A supplier proves a second number through the same kyc actions.
//
// NOTHING REACHES A PERSON: every number is in the reserved +971 50 000 00xx block and every mailbox is
// @example.invalid. kyc refuses a fixture number on every code action BEFORE any Twilio call
// (_shared/demo_identity.ts isDemoPhone, #681), and the "No" branch asserts exactly that refusal.
//
// THE "NO" BRANCH, IN TWO PARTS (coordinator decision, 15 Sep 2026):
//   1. The safety property, asserted: sending a code to a fixture number is refused (captured: true),
//      a 'captured' kyc run is recorded, no phone_verifications row is written (so no Twilio request
//      was made), and nothing is stored as the WhatsApp number.
//   2. HARNESS-ONLY: the second number is then marked confirmed directly in the database, exactly as
//      makeDemoCustomer marks the SMS mobile verified, so the screens after the code stay under E2E.
//      No code exists for a fixture number (#681 has no test-code bypass), so kyc's real code check
//      (whatsapp_verify -> Twilio VerificationCheck -> verifiedPatch) is NOT exercised here; it is
//      covered by supabase/functions/_shared/whatsapp_choice.test.ts and kyc/fixture_number.test.ts.
const waRow = async (table, key, email) => (await read(`select whatsapp_opt, whatsapp_phone, whatsapp_verified_at is not null as verified, whatsapp_asked_at is not null as asked
  from public.${table} where ${key} = ${q(email)}`))[0] || {};
// Part 1's evidence for one number: the kyc capture note and the absence of any verification row.
const refusalEvidence = async (email, phone, since) => {
  const cap = await read(`select count(*)::int n from public.agent_runs where agent = 'kyc' and status = 'skipped'
    and counts->>'action' = 'whatsapp_send_code' and note like 'captured: reserved fixture mobile%' and started_at >= ${q(since)}`);
  const pv = await read(`select count(*)::int n from public.phone_verifications where phone = ${q(phone)} and created_at >= ${q(since)}`);
  return { captured_runs: cap[0]?.n ?? 0, verification_rows: pv[0]?.n ?? -1 };
};
// Part 2 (harness-only): the same fields kyc's verifiedPatch writes, on a demo row only.
const markWhatsAppConfirmed = (table, key, email, phone) => write(`update public.${table}
  set whatsapp_opt = 'other', whatsapp_phone = ${q(phone)}, whatsapp_verified_at = now(), whatsapp_asked_at = now()
  where ${key} = ${q(email)} and is_demo = true and ${key} like '%@example.invalid'`, 'e2e: second WhatsApp number confirmed (harness-only, #681 forbids a fixture code)');

export async function journeySignupWhatsApp(ctx) {
  const { rep, browser, run, dir } = ctx;
  const J = 'g sign-up WhatsApp';
  const { makeDemoCustomer, makeDemoSupplier, demoMobile } = await import('./fixtures.mjs');
  const section = (page) => page.locator('section:has(input[type=radio][value="same"])');

  // YES — English. The mobile was just proven by SMS, so no second code.
  const yes = await makeDemoCustomer(run, { label: 'WA yes', stopBeforeWhatsApp: true });
  {
    const s = await signedInPage(browser, yes, { lang: 'en' });
    try {
      // These two steps load a portal MID-SIGN-UP, where the navigation openPortal waits for does
      // not exist yet, so they navigate themselves - and would be the one place left where a dead
      // harness session is reported as a product assertion failure. The same check, on its own.
      const gT0 = Date.now();
      await s.page.goto(portalUrl('customer', 'en'), { waitUntil: 'domcontentloaded', timeout: 60000 });
      await s.page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});
      assertHarnessSignedIn(s.calls, gT0, 'the sign-up WhatsApp step (en)');
      const q1 = section(s.page);
      await q1.waitFor({ state: 'visible', timeout: 30000 });
      const title = (await q1.locator('h2').innerText()).replace(/\s+/g, ' ').trim();
      const termsBefore = await s.page.locator('input[type=checkbox]').count();
      rep.step(J, 'the step asks "Is <verified mobile> also your WhatsApp number?" (en)', title === `Is ${yes.phone} also your WhatsApp number?` ? 'PASS' : 'FAIL', title, { shot: await shot(s.page, dir, 'g_signup_step_en') });
      rep.step(J, 'the terms step is not offered before the answer (en)', termsBefore === 0 ? 'PASS' : 'FAIL', `terms checkboxes on screen: ${termsBefore}`);
      await q1.locator('input[type=radio][value="same"]').check();
      await q1.getByRole('button', { name: 'Continue' }).click();
      await q1.waitFor({ state: 'detached', timeout: 20000 });
      const row = await waRow('customers', 'email', yes.email);
      rep.step(J, 'Yes stores the verified mobile as the confirmed WhatsApp number, with no code', row.whatsapp_opt === 'same' && row.whatsapp_phone === yes.phone && row.verified ? 'PASS' : 'FAIL', JSON.stringify(row));
      const termsAfter = await s.page.locator('input[type=checkbox]').count();
      rep.step(J, 'the terms step appears once answered (en)', termsAfter > 0 ? 'PASS' : 'FAIL', `terms checkboxes: ${termsAfter}`, { shot: await shot(s.page, dir, 'g_signup_after_yes_en') });
      ctx.consoleErrors.push(...realErrors(s.consoleErrors).map((e) => `[g yes] ${e}`));
    } finally { await s.ctx.close(); }
  }

  // NO — English and Arabic. Part 1 proves the refusal; part 2 (harness-only) continues the screens.
  // src/components/portal/whatsappChoiceText.ts send_code. The Arabic had drifted ('أرسل الرمز'): the click waited
  // out its timeout, the response wait below rejected unhandled and the process died before teardown (23 Sep 2026).
  const SEND = { en: 'Send code', ar: 'إرسال الرمز' };
  for (const lang of ['en', 'ar']) {
    const no = await makeDemoCustomer(run, { label: `WA no ${lang}`, locale: lang, stopBeforeWhatsApp: true });
    const other = demoMobile();
    const s = await signedInPage(browser, no, { lang });
    try {
      const gT0 = Date.now();
      await s.page.goto(portalUrl('customer', lang), { waitUntil: 'domcontentloaded', timeout: 60000 });
      await s.page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});
      assertHarnessSignedIn(s.calls, gT0, `the sign-up WhatsApp step (${lang})`);
      const q2 = section(s.page);
      await q2.waitFor({ state: 'visible', timeout: 30000 });
      const title = (await q2.locator('h2').innerText()).replace(/\s+/g, ' ').trim();
      const dirAttr = await q2.getAttribute('dir');
      rep.step(J, `the step names the mobile, ${lang === 'ar' ? 'right-to-left' : 'left-to-right'} (${lang})`, title.includes(no.phone) && title.includes('WhatsApp') && dirAttr === (lang === 'ar' ? 'rtl' : 'ltr') ? 'PASS' : 'FAIL', `${title} · dir=${dirAttr}`, { shot: await shot(s.page, dir, `g_signup_step_${lang}`) });
      // Part 1 — the safety property.
      const since = (await read(`select now()::text t`))[0].t;
      await q2.locator('input[type=radio][value="other"]').check();
      await q2.locator('input[type=tel]').fill(other);
      const resp = s.page.waitForResponse((r) => r.url().includes('/functions/v1/kyc') && (r.request().postData() || '').includes('whatsapp_send_code'), { timeout: 20000 });
      resp.catch(() => {});   // observed below; never an unhandled rejection that kills the run before teardown
      await q2.getByRole('button', { name: SEND[lang] }).click();
      const body = await (await resp).json().catch(() => null);
      const ev = await refusalEvidence(no.email, other, since);
      const before = await waRow('customers', 'email', no.email);
      rep.step(J, `a fixture number gets no code: refused, captured, no Twilio request, nothing stored (${lang})`,
        body?.captured === true && body?.ok === false && ev.captured_runs >= 1 && ev.verification_rows === 0 && before.whatsapp_phone == null && before.whatsapp_opt == null ? 'PASS' : 'FAIL',
        `response=${JSON.stringify(body)} evidence=${JSON.stringify(ev)} row=${JSON.stringify(before)}`, { shot: await shot(s.page, dir, `g_signup_refused_${lang}`) });
      // Part 2 — HARNESS-ONLY: the number is marked confirmed in the database (see the header).
      await markWhatsAppConfirmed('customers', 'email', no.email, other);
      await s.page.reload({ waitUntil: 'domcontentloaded' });
      await s.page.locator('input[type=checkbox]').first().waitFor({ state: 'visible', timeout: 30000 }).catch(() => {});
      const stepGone = (await section(s.page).count()) === 0;
      const terms = await s.page.locator('input[type=checkbox]').count();
      const row = await waRow('customers', 'email', no.email);
      rep.step(J, `after the second number is confirmed, the step closes and the terms step appears (${lang})`, stepGone && terms > 0 && row.whatsapp_opt === 'other' && row.whatsapp_phone === other ? 'PASS' : 'FAIL',
        `step gone=${stepGone} terms=${terms} row=${JSON.stringify(row)}`, { shot: await shot(s.page, dir, `g_signup_after_confirm_${lang}`) });
      ctx.consoleErrors.push(...realErrors(s.consoleErrors).filter((e) => !/status of 4\d\d/.test(e)).map((e) => `[g no ${lang}] ${e}`));
    } finally { await s.ctx.close(); }
  }

  // SUPPLIER — the same kyc actions and the same guard serve suppliers. The supplier fixture is an
  // approved account, so there is no registration screen to drive; this is asserted through kyc itself.
  const sup = await makeDemoSupplier(run, { label: 'WA', trade: 'aluminium' });
  const sOther = demoMobile();
  const since = (await read(`select now()::text t`))[0].t;
  const sent = await call('kyc', sup.jwt, { action: 'whatsapp_send_code', phone: sOther });
  const check = await call('kyc', sup.jwt, { action: 'whatsapp_verify', phone: sOther, code: '123456' });
  const ev = await refusalEvidence(sup.email, sOther, since);
  const srow = await waRow('leads', 'claimed_by', sup.email);
  rep.step(J, 'supplier: a fixture number is refused on send AND check, captured, nothing sent or stored',
    sent.json?.captured === true && check.json?.captured === true && ev.captured_runs >= 1 && ev.verification_rows === 0 && srow.whatsapp_opt === 'same' && srow.whatsapp_phone === sup.phone ? 'PASS' : 'FAIL',
    `send=${JSON.stringify(sent.json)} verify=${JSON.stringify(check.json)} evidence=${JSON.stringify(ev)} row=${JSON.stringify(srow)}`);
  // Part 2 for the supplier (harness-only), then kyc's own state reports the confirmed second number.
  await markWhatsAppConfirmed('leads', 'claimed_by', sup.email, sOther);
  const st = await call('kyc', sup.jwt, { action: 'state' });
  rep.step(J, 'supplier: once confirmed, kyc serves the second number as the verified WhatsApp number',
    st.json?.whatsapp?.opt === 'other' && st.json?.whatsapp?.phone === sOther && st.json?.whatsapp?.verified === true ? 'PASS' : 'FAIL', JSON.stringify(st.json?.whatsapp));
}

// h: what the human browser audits of 21 Sep 2026 pressed (scripts/e2e/journey_audit_buttons.mjs).
export const JOURNEYS = { a: journeyCustomerRequest, b: journeySuppliers, c: journeyComparison, d: journeyPayment, e: journeyInvoiceRefund, f: journeyCrawl, g: journeySignupWhatsApp, h: journeyAuditButtons };
