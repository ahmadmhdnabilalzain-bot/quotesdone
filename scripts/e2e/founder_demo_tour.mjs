// scripts/e2e/founder_demo_tour.mjs — ONE standing demo of both portals, and how to open it signed in.
// Assigned: sales_engineer (the supplier portal is his surface).
//
// THE FOUNDER, 18 Sep 2026: "generate a link for me to access the supplier portal directly without
// signing up." He wants to walk the portal as a supplier walks it — on quotesdone.ae, in his own
// browser, with no sign-up form and no OTP.
//
// WHAT THIS IS NOT. It is not a second demo-data factory. Every identity here is made by
// scripts/e2e/fixtures.mjs (makeDemoSupplier / makeDemoCustomer), which is itself
// scripts/lib/demo_factory.mjs — so there stays exactly ONE way to make a demo supplier, one
// teardown that derives its scope from the database, and one set of guards. What this file adds is
// the CONTENT: services stated in the supplier's own words and rewritten by the sales engineer,
// inquiries with a BOQ and a redacted drawing, a quotation carried through the review conversation
// to submission, supporting documents — so that every tab has something honest to show.
//
// NOTHING HERE CAN REACH A REAL PERSON. Identities are ZZ DEMO / @example.invalid (RFC 2606, nobody
// can receive mail there) on the reserved +9715000000xx mobile block; leads.is_demo and
// customers.is_demo are derived from those, and the guards in
// scripts/sql/demo_identities_are_marked_and_never_reach_a_real_person.sql then hold: a demo
// account is never matched to a real one (a01_inquiry_match_demo_and_real_never_pair returns null
// rather than recording the row), every notice addressed to it is captured by
// zzzz_notifications_demo_capture instead of being handed to Resend or Twilio, it is never counted
// in a business figure, and it can only ever pay in Stripe TEST mode. The run refuses to start
// unless those three triggers are installed. No reveal is seeded and no payment is taken, so
// Messages shows its locked state truthfully.
//
//   node scripts/e2e/founder_demo_tour.mjs --seed --paid  stand the demo up (--paid: the model reads the supplier's words, ~USD 0.005)
//   node scripts/e2e/founder_demo_tour.mjs --link       open both portals, signed in, in a visible browser
//   node scripts/e2e/founder_demo_tour.mjs --verify     sign in by code and prove every tab of both portals opens
//   node scripts/e2e/founder_demo_tour.mjs --teardown   remove every row, file and auth user this seeded
//
// SIGN-IN IS THE ONE-TIME CODE, NOT A URL SESSION (19 Oct 2026, follows #1507). Both portals now refuse
// a session that arrives in the URL, so the magic link this file used to mint opens signed out. A demo
// account signs in the way every account does: login_otp verify. The code is seeded hashed with
// demo_factory.verifyEmailByOtp (the harness's one OTP seed; only delivery is skipped, because
// @example.invalid cannot receive mail) and that function refuses any address that is not
// @example.invalid. The session login_otp answers with is written into the portal's own storage keys,
// exactly where the portal's own verify() puts it. No code is printed.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { openRun, closeRun, makeDemoCustomer, makeDemoSupplier, read, write, REF, BASE, call } from './fixtures.mjs';
import { newRun, makeInquiry, uploadObject, keys, q, num, verifyEmailByOtp } from '../lib/demo_factory.mjs';
import { demoPdf, demoOfficePlanPng } from '../lib/demo_pdf.mjs';

// ONE TAG FOR THE LIFE OF THE DEMO. Not random: the founder's demo is a standing thing, so --link
// and --teardown must be able to find it tomorrow without being told a hex string from today.
export const TAG = 'founderdemo';
export const SITE = process.env.QD_SITE || 'https://quotesdone.ae';

const argv = process.argv.slice(2);
const has = (f) => argv.includes(f);
const step = (name, ok, detail = '') => console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ' — ' + detail : ''}`);

// ── the demo's own content ────────────────────────────────────────────────────────────────────
// The founder's sentence, verbatim, so the Services tab shows HIS feature doing the work: the sales
// engineer's rewrite turns these words into the service list, nothing is typed in as a list.
const OWN_WORDS = 'we do gypsum partitions, false ceilings and painting';

// EVERY JOB IS IN DUBAI. The demo supplier's stated coverage comes from makeSupplier
// (scripts/lib/demo_factory.mjs: service_emirates = EMIRATES.slice(0, 1 + variant % 3), which
// always starts with 'Dubai'; measured 21 Sep 2026 on lead 126512: coverage_emirates {Dubai}). A
// supplier who limited itself is matched only inside its stated emirates (audit finding 25,
// a_supplier_who_limits_its_emirates_is_matched_only_there.sql), so an Abu Dhabi or Sharjah job would
// never reach it through the real matcher, and this tour now asks the matcher before it invites.
const JOBS = [
  { key: 'office', trade: 'gypsum', emirate: 'Dubai',
    summary: 'Gypsum partitions and false ceiling for an office fit-out in Business Bay, Dubai',
    boq: [{ section: 'Partitions', description: 'Gypsum board partition, 100mm metal stud, both faces', qty: 320, unit: 'm2', confidence: 'high' },
          { section: 'Ceilings', description: 'Suspended false ceiling, 600x600 mineral fibre tiles', qty: 410, unit: 'm2', confidence: 'high' },
          { section: 'Ceilings', description: 'Gypsum bulkhead, 300mm drop, painted finish', qty: 64, unit: 'm', confidence: 'medium' }] },
  { key: 'villa', trade: 'gypsum', emirate: 'Dubai',
    summary: 'False ceilings and gypsum cornice for a private villa in Jumeirah, Dubai',
    boq: [{ section: 'Ceilings', description: 'Plain gypsum false ceiling with cove lighting detail', qty: 180, unit: 'm2', confidence: 'high' },
          { section: 'Ceilings', description: 'Gypsum cornice 150mm, supplied and fixed', qty: 210, unit: 'm', confidence: 'medium' }] },
  { key: 'retail', trade: 'painting', emirate: 'Dubai',
    summary: 'Internal painting for a retail unit handover in Al Nahda, Dubai',
    boq: [{ section: 'Internal walls', description: 'Internal wall painting, emulsion, two coats', qty: 540, unit: 'm2', confidence: 'high' },
          { section: 'Ceilings', description: 'Ceiling painting, emulsion, two coats', qty: 150, unit: 'm2', confidence: 'medium' }] },
];

// The two quotation files the review conversation is driven with. The first is deliberately
// incomplete — that is what makes the sales engineer's review list something, which is the part of
// the portal the founder called the most important. The second answers every point.
const QUOTE_INCOMPLETE = 'Description,Qty,Unit,Rate,Amount\n'
  + 'Plain gypsum false ceiling with cove lighting detail,180,m2,95,17100\n'
  + 'Total,,,,17100\n';
const QUOTE_COMPLETE = 'Description,Qty,Unit,Rate,Amount\n'
  + 'Knauf gypsum false ceiling 12.5mm with cove lighting detail,180,m2,95,17100\n'
  + 'Knauf gypsum cornice 150mm supplied and fixed,210,m,42,8820\n'
  + 'Total,,,,25920\n'
  + 'Validity: 30 days\nLead time: 4 weeks\nWarranty: 2 years materials and workmanship\n'
  + 'Payment terms: 50% advance, 50% on completion\nPrices exclude VAT\n'
  + 'Exclusions: electrical fittings, painting of walls, scaffolding above 4m\n';
const QUOTE_PAINTING = 'Description,Qty,Unit,Rate,Amount\n'
  + 'Internal wall painting - Brand: Jotun - Product: Fenomastic Emulsion - 2 coats over primer,540,m2,30,16200\n'
  + 'Ceiling painting - Brand: Jotun - Product: Fenomastic Emulsion - 2 coats,150,m2,36,5400\n'
  + 'Total,,,,21600\n'
  + 'Validity: 30 days\nLead time: 3 weeks\nWarranty: 12 months, covers parts and labour\n'
  + 'Installation included, 6 working days on site\n'
  + 'Payment terms: 50% advance, 50% on completion\nNot VAT registered; prices exclude VAT\n'
  + 'Exclusions: scaffolding above 4m, decorative finishes, external works\n';

// WHAT THIS SUPPLIER ANSWERS WHEN THE SALES ENGINEER ASKS. The review is deterministic
// (supplier_api/quote_review.ts — no model call), and it holds a quotation until every point it
// raised is answered: measured 18 Sep 2026, the "complete" file above still left five open, because
// the gypsum line specs want a board type and a frame gauge per line that no CSV total carries.
// A real supplier answers them in the chat, so this one does too — in the engineer's own phrasing,
// keyed by the `attr` and `line_no` it returns, so a new required attribute is answered the day it
// is added rather than the day someone edits a hard-coded script.
const ANSWERS = {
  board_type: 'Knauf standard gypsum board, 12.5 mm',
  frame: 'Galvanised steel C-channel, 0.6 mm gauge, at 600 mm centres',
  thickness_mm: '12.5 mm',
  brand: 'Jotun',
  product: 'Fenomastic Emulsion',
  coats: '2 coats',
  sheen: 'Matt',
  installation_included: 'installation included, 10 working days on site',
  vat: 'not VAT registered',
  validity: 'validity 30 days',
  delivery: 'lead time 4 weeks',
  warranty_period: 'warranty 2 years',
  warranty_coverage: 'warranty covers parts and labour',
};
const ATTR_LABEL = { board_type: 'board type', frame: 'frame', thickness_mm: 'thickness', coats: 'number of coats' };
/** One reply line per open point, in the shape the engineer's own example sentence asks for. */
function replyTo(issues) {
  const lines = [];
  for (const i of issues || []) {
    const v = ANSWERS[i.attr] || ANSWERS[i.code];
    if (!v) continue;
    lines.push(i.line_no ? `line ${i.line_no} ${ATTR_LABEL[i.attr] || i.attr}: ${v}` : v);
  }
  return [...new Set(lines)].join('. ');
}

/** The open points of a thread view: the LAST review message carries them all; open_requests is narrower. */
const openIssues = (view) => (view.messages || []).slice().reverse().find((m) => (m.issues || []).length)?.issues
  || view.open_requests || [];

/**
 * Carry one quotation through the review to submission, answering whatever the engineer still asks.
 * Six rounds is a bound, not a target: a round that answers nothing new stops the loop, and the
 * caller reports the state that was actually reached rather than looping on it.
 */
async function reviewToSubmission(rv, files) {
  await rv('review_start');
  let view = {};
  for (const f of files) {
    view = (await rv('review_upload', { file: { b64: b64(f.csv), filename: f.name, mime: 'text/csv' } })).json || {};
    if (f.thenSay) view = (await rv('review_message', { text: f.thenSay })).json || {};
  }
  const raised = openIssues(view).length;
  for (let i = 0; i < 6 && view.can_choose !== true && view.state !== 'awaiting_choice'; i++) {
    const text = replyTo(openIssues(view));
    if (!text) break;
    view = (await rv('review_message', { text })).json || {};
  }
  if (view.state === 'awaiting_choice' || view.can_choose === true) {
    const ch = await rv('review_choose', { choice: 'generate' });
    view = ch.json?.state === 'submitted' ? ch.json : ((await rv('review_submit')).json || view);
  }
  return { view, raised, still_open: openIssues(view).length };
}

// The redacted drawing page a supplier downloads. Until 21 Sep 2026 this was a local drawingPng():
// a white sheet with a plan outline and no text, so the founder-demo supplier saw four empty
// rectangles (audit 21 Sep, finding 3). The page is uploaded straight to drawings/redacted/ and
// drawing_redact never runs on it, so it must already BE the redacted page: the shared office plan
// (rooms, areas, dimensions, legend, north, scale) with its title block painted black.
const drawingPng = () => demoOfficePlanPng({ redactTitleBlock: true });

const b64 = (s) => Buffer.from(s, 'utf8').toString('base64');

// ── signing in ─────────────────────────────────────────────────────────────────────────────────
/** A session for one demo account, minted by login_otp verify against a freshly seeded code. */
export async function signInByCode(email, kind) {
  const r = await verifyEmailByOtp(email, kind, String(100000 + Math.floor(Math.random() * 900000)));
  if (!r.json?.ok || !r.json?.access_token) throw new Error(`login_otp verify refused ${email}: HTTP ${r.status} ${r.json?.code || r.json?.error || ''}`);
  return r.json;
}

const STORE = { supplier: ['qd-sup-token', 'qd-sup-refresh', '/portal'], customer: ['qd-cust-token', 'qd-cust-refresh', '/me'] };

/** A fresh browser context signed in as one demo account through the code path, open on its portal. */
async function openSignedIn(browser, email, kind) {
  const s = await signInByCode(email, kind);
  const [tk, rf, path] = STORE[kind];
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  await ctx.addInitScript(([tk, rf, a, r]) => { try { if (!localStorage.getItem(tk)) { localStorage.setItem(tk, a); localStorage.setItem(rf, r); } } catch {} },
    [tk, rf, s.access_token, s.refresh_token]);
  const page = await ctx.newPage();
  await page.goto(`${SITE}${path}`, { waitUntil: 'domcontentloaded', timeout: 90000 });
  // A NEW SUPPLIER AGREEMENT puts a re-accept gate in front of every tab (v15 on 19 Oct 2026). The
  // demo supplier accepts it the way a supplier does, through the portal's own button.
  if (kind === 'supplier') {
    const gate = page.getByRole('button', { name: 'Accept and continue' });
    if (await gate.waitFor({ timeout: 20000 }).then(() => true, () => false)) {
      await page.locator('label:has-text("Supplier Agreement") input[type=checkbox], input[type=checkbox]').first().check();
      await gate.click();
    }
  }
  return { ctx, page };
}

/** The identities of a demo that is already standing. */
async function standing() {
  const sup = (await read(`select id, company_name, claimed_by from public.leads
      where ${q('qd_run:' + TAG)} = any(coalesce(tags,'{}')) order by id limit 1`))[0];
  const cust = (await read(`select id, email, full_name from public.customers
      where email like ${q('qd-' + TAG + '-%')} order by created_at limit 1`))[0];
  return { sup, cust };
}

// ── seeding ───────────────────────────────────────────────────────────────────────────────────
async function seed() {
  // The three guards that make a demo identity incapable of reaching a real person. Without them a
  // fixture mobile could reach Twilio, so this refuses rather than seeds.
  const guards = (await read(`select tgname from pg_trigger where not tgisinternal and tgname in
    ('zzzz_notifications_demo_capture','a01_inquiry_match_demo_and_real_never_pair','a01_quote_demo_and_real_never_pair')`)).map((r) => r.tgname);
  if (guards.length !== 3) {
    throw new Error(`REFUSED: the demo guards are not installed on ${REF} (found ${guards.join(', ') || 'none'}). ` +
      'Apply scripts/sql/demo_identities_are_marked_and_never_reach_a_real_person.sql first.');
  }
  const already = await standing();
  if (already.sup) throw new Error(`a demo tagged ${TAG} is already standing (lead ${already.sup.id}, ${already.sup.claimed_by}). ` +
    'Run --link to open it, or --teardown first.');

  const run = await openRun({ tag: TAG });
  const out = { tag: TAG, site: SITE, jobs: [] };
  try {
    // ── the supplier: the mandatory six as evidence, approved by the sales engineer ────────────
    const sup = await makeDemoSupplier(run, { trade: 'gypsum', label: 'Interiors' });
    out.supplier = { email: sup.email, company: sup.company, leadId: sup.leadId, phone: sup.phone };
    step('supplier approved with the mandatory six', sup.row.approval_status === 'approved' && (sup.row.missing || []).length === 0,
      `lead ${sup.leadId} ${sup.company}`);

    // ── Services: HIS words, the sales engineer's rewrite, saved through the product ───────────
    // PAID SINCE 12 Nov 2026 (rulings 1663/1664, review of PR #1980): the model reads his own words (two steps, about USD 0.005), so this
    // step runs only with --paid, in the style of supplier_registration_certification.mjs.
    if (!argv.includes('--paid')) throw new Error('--seed reads the supplier\'s own words with the model (a paid call, about USD 0.005): run it again with --paid');
    const rw = await call('supplier_api', sup.jwt, { action: 'services_rewrite', text: OWN_WORDS, removed: [] });
    // nothing is listed for him: what the model offers he adds, as the demo supplier does here (meaning.proposals, off until added)
    const keysOut = [...(rw.json?.service_keys || []), ...(rw.json?.meaning?.proposals || []).map((p) => p.key)];
    const implied = (rw.json?.implied || []).filter((i) => !i.removed).map((i) => i.key);
    const ownWords = rw.json?.own_words || [];
    step('the sales engineer rewrote the supplier\'s own sentence into services',
      rw.json?.ok === true && (keysOut.length + implied.length + ownWords.length) > 0,
      `${keysOut.length} stated, ${implied.length} implied, ${ownWords.length} own words`);
    const state = await call('supplier_api', sup.jwt, { action: 'services_state' });
    const sv = await call('supplier_api', sup.jwt, {
      action: 'services_save_rewrite',
      trades: (state.json?.checklist || []).map((c) => c.code),
      roles: state.json?.capability?.roles?.length ? state.json.capability.roles : ['executes'],
      services: keysOut, implied, removed: [], own_words: ownWords, raw_text: OWN_WORDS,
    });
    step('the rewritten services were saved', sv.json?.ok === true, JSON.stringify(sv.json).slice(0, 160));
    out.services = { stated: keysOut.length, implied: implied.length, own_words: ownWords.length };

    // ── two customers and three inquiries, each with a BOQ and a redacted drawing page ─────────
    const custA = await makeDemoCustomer(run, { label: 'Customer A' });
    const custB = await makeDemoCustomer(run, { label: 'Customer B' });
    out.customer = { email: custA.email, name: custA.fullName, id: custA.customerId };
    const owners = { office: custA, villa: custA, retail: custB };

    for (const j of JOBS) {
      const cust = owners[j.key];
      // rfqReady:false deliberately: an rfq_ready inquiry is dispatchable, and dispatch is the one
      // path that could put a demo brief in front of a real supplier. The match below is written
      // directly instead, and a01_inquiry_match_demo_and_real_never_pair would drop it if the
      // supplier on the other side were real.
      const inq = await makeInquiry(run, { customer: cust, trade: j.trade, status: 'sent',
        rfqReady: false, emirate: j.emirate, summary: j.summary });
      run.ids.inquiries.add(inq.id);
      const page = `drawings/redacted/${run.tag}/${inq.id}_p1.png`;
      await uploadObject('drawing-files', page, drawingPng(), 'image/png');
      run.ids.storage.push(`drawing-files/${page}`);
      await write(`update public.inquiries
          set boq = ${q(JSON.stringify({ boq: j.boq }))}::jsonb, boq_confidence = 'high',
              spec = coalesce(spec,'{}'::jsonb) || ${q(JSON.stringify({ customer_requirements: { version: 1, installation: { required: 'yes' }, warranty: { required: 'yes' } } }))}::jsonb,
              drawing_redacted_paths = array[${q(page)}]
        where id = ${q(inq.id)}`, 'founder demo inquiry');
      // THE MATCHER DECIDES FIRST. The real fn_match_capability is asked whether this supplier is
      // returned for the job's trade in the job's emirate (stated coverage honoured, audit finding 25).
      // Only then is the match written -- and it is still written directly, not dispatched, because
      // dispatch is the one path that could put a demo brief in front of a real supplier.
      const hit = await read(`select supplier_id, why from public.fn_match_capability(
          array[${q(j.trade)}], 'executes', '{}'::text[], '{}'::text[], null, null, ${q(j.emirate)}, 50)
          where supplier_id = ${num(sup.leadId)}`);
      step(`the matcher returns the demo supplier for ${j.trade} in ${j.emirate} (${j.key})`,
        (hit || []).length === 1, hit?.[0]?.why || 'not returned: a gate (coverage, trade, role, confirmed scope) refused it');
      const m = (hit || []).length === 1
        ? await write(`insert into public.inquiry_matches (inquiry_id, supplier_id, similarity, match_reason)
            values (${q(inq.id)}, ${num(sup.leadId)}, 0.92, 'founder demo: matcher-confirmed invitation')
            on conflict do nothing returning inquiry_id`, 'founder demo match')
        : [];
      step(`job ${String(inq.id).slice(0, 8).toUpperCase()} (${j.key}) is in the supplier's inbox`,
        (m || []).length === 1, `${j.boq.length} BOQ lines, 1 drawing page`);
      j.id = inq.id;
      out.jobs.push({ key: j.key, id: inq.id, job_no: String(inq.rfq_no ?? (await read(`select rfq_no from public.inquiries where id = ${q(inq.id)}`))[0]?.rfq_no ?? ''), summary: j.summary });
    }

    // ── the review conversation, carried to a submitted quotation (the villa job) ──────────────
    // The villa job shows the WHOLE arc: an incomplete file, the engineer's list, a text answer, the
    // revised file, and submission. The retail job goes straight in with a complete file, so the two
    // tabs do not read as one story told twice. The office job stays un-quoted — a new brief waiting.
    out.review = [];
    for (const [key, files] of [
      ['villa', [{ csv: QUOTE_INCOMPLETE, name: 'quotation-draft.csv', thenSay: 'Validity 30 days. Warranty 2 years materials and workmanship.' },
                 { csv: QUOTE_COMPLETE, name: 'quotation-final.csv' }]],
      ['retail', [{ csv: QUOTE_PAINTING, name: 'painting-quotation.csv' }]],
    ]) {
      const job = JOBS.find((x) => x.key === key);
      const rv = (action, body = {}) => call('supplier_api', sup.jwt, { action, inquiry_id: job.id, ...body }, 180000);
      const r = await reviewToSubmission(rv, files);
      const quotes = await read(`select id, status, quote_amount from public.quotes
          where inquiry_id = ${q(job.id)} and supplier_id = ${num(sup.leadId)}`);
      for (const x of quotes) run.ids.quotes.add(x.id);
      const thread = (await rv('review_thread')).json || {};
      step(`${key}: the sales engineer reviewed the quotation`, r.raised > 0, `${r.raised} point(s) raised`);
      step(`${key}: the quotation reached the customer`, quotes.some((x) => x.status === 'submitted'),
        `state=${r.view.state}, still open ${r.still_open}, quotes ${JSON.stringify(quotes.map((x) => ({ status: x.status, amount: Number(x.quote_amount) })))}`);
      out.review.push({ job: key, inquiry_id: job.id, messages: (thread.messages || []).length,
        state: thread.state, points_raised: r.raised, points_still_open: r.still_open,
        submitted: quotes.filter((x) => x.status === 'submitted').length });
    }

    // ── supporting company documents ──────────────────────────────────────────────────────────
    const docs = [
      ['ISO 9001:2015 certificate', 'certificate', 'ISO 9001-2015 certificate.pdf',
       ['ISO 9001:2015 CERTIFICATE (ZZ DEMO FIXTURE — NOT A REAL CERTIFICATE)', 13], ['Quality management system', 11]],
      ['Completed projects reference list', 'project_reference', 'project references.pdf',
       ['PROJECT REFERENCES (ZZ DEMO FIXTURE — NOT A REAL COMPANY)', 13], ['Office fit-outs and villa ceilings, 2024-2026, UAE', 11]],
    ];
    for (const [label, type, filename, l1, l2] of docs) {
      const pdf = demoPdf([l1, l2, [`Run ${run.tag}`, 9]]);
      const r = await call('supplier_portal', sup.jwt, {
        action: 'supporting_document_save', label, type, filename, mime: 'application/pdf',
        original_b64: Buffer.from(pdf).toString('base64'),
      }, 120000);
      step(`supporting document "${label}" uploaded`, r.json?.ok === true, JSON.stringify(r.json).slice(0, 140));
    }

    // ── what each tab will actually show, MEASURED through the portal's own endpoints ─────────
    out.tabs = await measureTabs(sup.jwt);

    out.sign_in = 'node scripts/e2e/founder_demo_tour.mjs --link (one-time code, no URL session)';
  } finally {
    // KEPT ON PURPOSE. The founder needs this alive; --teardown is the only thing that removes it.
    // closeRun still closes the rehearsal window, so the failed-run watcher is not silenced for ever.
    await closeRun(run, { keep: true });
  }
  return out;
}

/** Ask each tab's own endpoint what it holds. A claim about a tab is a reading, never a guess. */
export async function measureTabs(jwt) {
  const one = async (slug, body) => (await call(slug, jwt, body, 120000)).json || {};
  const dash = await one('supplier_portal', { action: 'dashboard' });
  const inqs = await one('supplier_api', { action: 'inquiries_list' });
  const services = await one('supplier_api', { action: 'services_state' });
  const mail = await one('messages_api', { action: 'mailbox' });
  const sup = await one('supplier_portal', { action: 'supporting_documents' });
  const ins = await one('supplier_portal', { action: 'insights' });
  const quoted = (inqs.inquiries || []).filter((i) => (i.quotes || []).length);
  return {
    services: { stated: (services.selected_services || []).length, trades: (services.checklist || []).length, raw_text: !!services.raw_text },
    rfqs: { inquiries: (inqs.inquiries || []).length, with_boq: (inqs.inquiries || []).filter((i) => i.boq_lines > 0).length,
            with_drawing: (inqs.inquiries || []).filter((i) => i.drawing_pages > 0).length },
    quotes: { quoted_jobs: quoted.length, quotes: quoted.reduce((a, i) => a + i.quotes.length, 0),
              reviews: (inqs.inquiries || []).filter((i) => i.review).length },
    messages: { threads: (mail.threads || []).length, ok: mail.ok === true },
    documents: { supporting: (sup.documents || []).length },
    // `insights` answers one row per panel with `available` and the BASIS of that answer, so an empty
    // panel is reported as an empty population rather than as a broken routine. Both are listed.
    insights: { available: (ins.panels || []).filter((p) => p.available).map((p) => p.key),
                unavailable: (ins.panels || []).filter((p) => !p.available).map((p) => `${p.key}:${p.basis}`) },
    overview: { approval: dash.supplier?.approval_status ?? null, active_matches: dash.active_matches ?? null,
                alerts: dash.alerts_count ?? null, notifications: (dash.notifications || []).length,
                stats: Object.entries(dash.stats || {}).filter(([, v]) => Number(v) > 0).map(([k, v]) => `${k}=${v}`) },
  };
}

// ── entry points ──────────────────────────────────────────────────────────────────────────────
const SHOTS = process.env.QD_SHOTS || join(tmpdir(), 'qd-founder-demo');

if (has('--teardown')) {
  const run = newRun({ tag: TAG, quiet: true });
  run.ids = { inquiries: new Set(), quotes: new Set(), leads: new Set(), customers: new Set(), storage: [] };
  process.env.QD_FIXTURES = '1';
  const r = await closeRun(run, { keep: false });
  console.log('torn down:', JSON.stringify(r.removed.summary ?? r.removed));
  console.log('leftovers:', JSON.stringify(r.leftovers));
  process.exit(r.leftovers && r.leftovers.total > 0 ? 1 : 0);
}

if (has('--link')) {
  const { chromium } = await import('playwright');
  const { sup, cust } = await standing();
  if (!sup) { console.error(`no demo tagged ${TAG} is standing — run --seed first`); process.exit(1); }
  const browser = await chromium.launch({ headless: false });
  await openSignedIn(browser, sup.claimed_by, 'supplier');
  if (cust) await openSignedIn(browser, cust.email, 'customer');
  console.log('both portals are open and signed in by one-time code; close the browser to finish.');
  await new Promise((res) => browser.on('disconnected', res));
  process.exit(0);
}

if (has('--verify')) {
  const { chromium } = await import('playwright');
  const { sup } = await standing();
  if (!sup) { console.error(`no demo tagged ${TAG} is standing — run --seed first`); process.exit(1); }
  mkdirSync(SHOTS, { recursive: true });
  const browser = await chromium.launch({ headless: process.env.QD_HEADED !== '1' });
  // A CLEAN CONTEXT holding only the session login_otp just answered with.
  let page, ok = false, detail = '', failed = 0;
  try {
    ({ page } = await openSignedIn(browser, sup.claimed_by, 'supplier'));
    // Signed in is not "the page loaded": the supplier's own tabs only exist once a token is held.
    await page.getByRole('tab', { name: /Inquiries received|الاستفسارات الواردة/ }).or(page.getByRole('button', { name: /Inquiries received|الاستفسارات الواردة/ })).first().waitFor({ timeout: 90000 });
    const tk = await page.evaluate(() => localStorage.getItem('qd-sup-token'));
    ok = !!tk;
    detail = `url ${page.url().split('#')[0]}, qd-sup-token ${tk ? 'held' : 'absent'}`;
  } catch (e) {
    detail = String(e.message).slice(0, 300);
  }
  const shotFile = join(SHOTS, 'supplier_portal_signed_in.png');
  await page?.screenshot({ path: shotFile, fullPage: false }).catch(() => {});
  step('one-time code signs the supplier portal in', ok, detail);
  console.log(`screenshot ${shotFile}`);
  // WHAT EACH TAB ACTUALLY SHOWS, read off the rendered page. The endpoint counts in --seed say what
  // the data holds; this says what the founder will see, which is the claim being made to him.
  if (ok) {
    for (const [key, label] of [['services', /^Services$/], ['rfqs', /^Inquiries received/], ['quotes', /^Quotations submitted$/],
                                ['messages', /^Messages/], ['documents', /^Documents$/], ['insights', /^Insights$/]]) {
      try {
        await page.getByRole('tab', { name: label }).or(page.getByRole('button', { name: label })).first().click();
        // Each tab fetches on open; the wait is generous rather than tight because what is being
        // captured is what the founder sees, and a screenshot of a spinner is not that.
        await page.waitForFunction(() => !/Loading (your )?\w+…/.test(document.body.innerText), { timeout: 30000 }).catch(() => {});
        await page.waitForTimeout(2500);
        const f = join(SHOTS, `tab_${key}.png`);
        await page.screenshot({ path: f, fullPage: true });
        const text = (await page.locator('main, body').first().innerText()).replace(/\s+/g, ' ').trim();
        step(`supplier tab ${key} reached`, true, text.slice(0, 160));
      } catch (e) { failed++; step(`supplier tab ${key} reached`, false, String(e.message).slice(0, 120)); }
    }
    console.log(`tab screenshots in ${SHOTS}`);
  }
  // The customer portal, signed in the same way and in its own clean context.
  const { cust } = await standing();
  let cok = !cust;
  if (cust) {
    let cctx, cpage, cdetail = '';
    try {
      ({ ctx: cctx, page: cpage } = await openSignedIn(browser, cust.email, 'customer'));
      await cpage.waitForFunction(() => !!localStorage.getItem('qd-cust-token'), { timeout: 90000 });
      await cpage.waitForTimeout(6000);
      // Signed in is the dashboard, not the sign-in form.
      cok = !(await cpage.locator('input[type=email], input[autocomplete=email]').first().isVisible().catch(() => false));
      cdetail = `url ${cpage.url().split('#')[0]}, qd-cust-token held`;
    } catch (e) { cdetail = String(e.message).slice(0, 300); }
    const cf = join(SHOTS, 'customer_portal_signed_in.png');
    await cpage?.screenshot({ path: cf, fullPage: true }).catch(() => {});
    step('one-time code signs the customer portal in', cok, cdetail);
    console.log(`screenshot ${cf}`);
    await cctx?.close();
  }
  await browser.close();
  process.exit(ok && cok && !failed ? 0 : 1);
}

if (has('--seed')) {
  const out = await seed();
  mkdirSync(SHOTS, { recursive: true });
  const f = join(SHOTS, 'founder_demo_tour.json');
  writeFileSync(f, JSON.stringify(out, null, 2));
  console.log('\n' + JSON.stringify(out, null, 2));
  console.log(`\nwritten to ${f}`);
  process.exit(0);
}

console.error(readFileSync(new URL(import.meta.url)).toString().split('\n').slice(26, 31).join('\n'));
process.exit(2);
