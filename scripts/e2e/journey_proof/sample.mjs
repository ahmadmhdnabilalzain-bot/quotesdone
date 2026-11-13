// scripts/e2e/journey_proof/sample.mjs — a SAMPLE dossier of journey A, rendered OFFLINE from stubbed data, so the founder
// sees the form before any money is spent. Seat: customer_support. No call to production of any kind.
//
//   node scripts/e2e/journey_proof/sample.mjs <out dir> [<final pdf path>]
//
// What is real in it: the template (pdf_native's renderer), every document builder (the certificate, the inquiry, the
// quotation, the comparison, the invoice: sample_documents.ts), the supplier's own quotation maker (the evidence pack's,
// with the full identity journey_proof puts on it), and the anonymity check, which is RUN on those documents.
// What is stubbed: everything that would have happened on the live site (the sign-up, the chat, the matcher, the
// notifications, the payment, the books, Dropbox, the cost). Every stubbed value says "stub" where it is printed, and the
// pictures are grey cards that name the screen the real run photographs.
import { mkdirSync, writeFileSync, readFileSync, copyFileSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { SCENARIOS, SITE as JOB, customerIdentity, supplierLetterhead, supplierIdentity, withFullIdentity, vatInclusiveOnly, asEvidenceJourney } from './scenarios.mjs';
import { scan } from './anonymity.mjs';
import { verdict, costByStep } from './record.mjs';
import { sheet } from './sheet.mjs';

const HERE = dirname(fileURLToPath(import.meta.url)); const REPO = resolve(HERE, '../../..');
const dir = resolve(process.argv[2] || '/tmp/qd-journey-proof/sample'); const finalPdf = process.argv[3] || null;
for (const d of ['', 'screens', 'shared', 'quotations', 'customer_files', 'messages']) mkdirSync(join(dir, d), { recursive: true });
const sc = SCENARIOS.A; const J = asEvidenceJourney(sc);
const cust = { name: 'ZZ DEMO JA Villa AC sample01', fullName: 'ZZ DEMO JA Villa AC sample01', email: 'delivered+qd-sample01-cust1@resend.dev', phone: '+971500000042' };
writeFileSync(join(dir, 'customer.json'), JSON.stringify(cust));
const pdfText = (f) => spawnSync('pdftotext', ['-layout', f, '-'], { encoding: 'utf8' }).stdout || '';
const pdfProps = (f) => (spawnSync('pdfinfo', [f], { encoding: 'utf8' }).stdout || '').split('\n').filter((l) => /^(Title|Subject|Keywords|Author|Creator):/.test(l)).join('\n');

// 1 the documents, by the platform's own builders
const d = spawnSync('deno', ['run', '--no-lock', '--node-modules-dir=none', `--allow-read=${REPO},${dir}`, `--allow-write=${dir}`, join(HERE, 'sample_documents.ts'), dir, join(dir, 'customer.json')], { encoding: 'utf8', cwd: REPO });
if (d.status !== 0) { console.error(d.stderr); process.exit(1); }
const M = JSON.parse(d.stdout.trim().split('\n').pop());

// 2 each supplier's OWN quotation, with his full identity (Chrome, offline: setContent only)
const { launch } = await import('../browser.mjs');
const { quotationHtml, quoteLinesFor, useHarness, htmlPdf } = await import('../evidence_pack.mjs');
const browser = await launch(); useHarness({ browser });
const quotes = [];
for (const [i, mq] of M.quotes.entries()) {
  const spec = { ...sc.quoting[i], label: mq.supplier.company_name.replace(/^ZZ DEMO /, '').replace(/ LLC$/, '') };
  const lh = { ...supplierLetterhead(spec, { company: mq.supplier.company_name }, i), mobile: mq.supplier.phone, email: mq.supplier.email };
  const lines = quoteLinesFor(J, spec, mq.items.map((x) => ({ description: x.desc, qty: Number(x.qty), unit: x.unit })));
  const doc = quotationHtml({ J, s: spec, company: mq.supplier.company_name, rfq: 'ZZSAMPLE', ref: `ZZQ-SAMPLE-A${i + 1}`, lines });
  let html = withFullIdentity(doc.html, lh); if (spec.vatInclusiveOnly) html = vatInclusiveOnly(html, doc);
  const own = `quotations/${lh.trading_name} - Quotation ZZQ-SAMPLE-A${i + 1}.pdf`;
  writeFileSync(join(dir, own), await htmlPdf(html, { landscape: true }));
  quotes.push({ mq, lh, own, spec, doc });
}
// stub pictures: grey phone cards naming the screen the real run photographs
const card = (name, title) => { const f = join(dir, 'screens', name + '.png'); spawnSync('python3', ['-c', `
from PIL import Image, ImageDraw, ImageFont
import sys, textwrap
im = Image.new('RGB', (390*2, 844*2), (236, 240, 244)); d = ImageDraw.Draw(im)
f = ImageFont.truetype(sys.argv[3], 40); g = ImageFont.truetype(sys.argv[3], 30)
d.rounded_rectangle([20, 20, 760, 1668], 60, outline=(150, 160, 172), width=6)
d.text((80, 220), 'STUB PICTURE', fill=(160, 120, 20), font=f)
y = 320
for ln in textwrap.wrap(sys.argv[2], 30): d.text((80, y), ln, fill=(40, 52, 66), font=g); y += 46
d.text((80, 1500), 'The real run puts the phone', fill=(110, 120, 132), font=g); d.text((80, 1546), 'screenshot here.', fill=(110, 120, 132), font=g)
im.save(sys.argv[1])`, f, title, join(REPO, 'supabase/functions/pdf_native/fixtures/brand/qd_sora_regular.ttf')]); return f; };
const strip = (base, items) => { const out = []; for (let i = 0; i < items.length; i += 3) { const part = items.slice(i, i + 3); const files = part.map(([n, t]) => card(`${base}_${n}`, t)); const f = `screens/${base}_sheet_${i / 3 + 1}.png`; sheet(files, part.map(([, t]) => t + ' (phone, clean)'), join(dir, f)); out.push({ file: f }); } return out; };

// 3 the anonymity checks, RUN on the documents above
const inq = join(dir, M.inquiry.file);
const s3scan = scan(customerIdentity(cust), [
  { where: 'the inquiry PDF (its text)', kind: 'pdf_text', text: pdfText(inq) }, { where: 'the inquiry PDF (its file properties)', kind: 'pdf_props', text: pdfProps(inq) },
  { where: 'the supplier portal screens', kind: 'screen', unreadable: true, why: 'stubbed in this sample', text: '' },
]);
const cmpText = pdfText(join(dir, M.comparison.file));
const q5 = quotes.map(({ mq, lh, own, spec, doc }) => {
  const f = join(dir, mq.file);
  const identity = [...supplierIdentity(lh), { label: "the supplier's website", value: mq.supplier.website, kind: 'email' }, { label: "his quotation's file name", value: own.split('/').pop(), kind: 'text' }];
  return { label: lh.trading_name, letter: mq.letter, lead_id: i0(mq.quote_id), own_file: own, customer_pdf: mq.file, vat_inclusive_only: !!spec.vatInclusiveOnly, stated: { ex_vat: doc.sub, vat: doc.vat, total: doc.tot },
    path: '(stub) uploaded through the portal\'s door, accepted at upload', read: { amount: mq.amount, lines: mq.items.length, read_by: '(stub: the model reading is not run offline)', masked: [] },
    anonymity: scan(identity, [{ where: 'his quotation as the customer sees it (text)', kind: 'pdf_text', text: pdfText(f) }, { where: 'his quotation as the customer sees it (file properties)', kind: 'pdf_props', text: pdfProps(f) }, { where: 'the comparison report (its text)', kind: 'pdf_text', text: cmpText }]) };
});
function i0(x) { return x; }
await browser.close();

// 4 the record (stubbed where the live site would have answered)
const T = (h, m) => `2026-11-13T${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:00.000Z`;
const steps = [['s1', 6, 0, 6, 4], ['prep', 6, 4, 6, 9], ['s2', 6, 9, 6, 21], ['s3', 6, 21, 6, 24], ['s4', 6, 24, 6, 25], ['s5', 6, 25, 6, 44], ['s7', 6, 44, 6, 47], ['s8', 7, 38, 7, 44], ['s9', 7, 44, 7, 50], ['s10', 7, 50, 7, 52]].map(([id, a, b, c, e]) => ({ id, title: id, start: T(a, b), end: T(c, e) }));
const STUB = '(stub)';
const turns = [
  ['customer', sc.opener, 6, 10, null], ['sales engineer', '(stub) The reply the sales engineer gave, word for word.', 6, 10, 7.4],
  ['customer', sc.facts[1][1], 6, 11, null], ['sales engineer', '(stub) Its next question, with the answer buttons it offered.', 6, 12, 6.1],
  ['customer', sc.confirm, 6, 20, null], ['sales engineer', '(stub) "Thank you, that is everything the suppliers need."', 6, 20, 5.0],
].map(([role, text, h, m, r]) => ({ role, text, at: T(h, m), reply_s: r }));
const sale = M.sale;
const rec = {
  journey: { key: 'A', title: sc.title, short: sc.short, how_made: sc.how_made, site: 'https://quotesdone.com (not visited: stubbed)', started: T(6, 0), finished: T(7, 52), mode: 'stubbed', cap_usd: sc.cap_usd, estimate_usd: sc.estimate_usd, run_tag: 'sample01' },
  steps,
  sections: {
    s1: { customer: { name: cust.name, email: cust.email, phone: cust.phone, site: JOB.said },
      signup: { door: `${STUB} The real run signs him up on quotesdone.com/me ("Create account") in a clean phone-size browser, with the real e-mailed code.`, steps: [['opened /me, "Create account"', 'the form'], ['typed his e-mail', 'the code e-mail (stub)'], ['typed the code', '"Complete your account"'], ['name, mobile, date of birth', 'saved'], ['asked for the mobile code', 'refused: a reserved number'], ['accepted the terms', 'his dashboard']].map(([what, result], k) => ({ at: T(6, k), what, result: `${STUB} ${result}` })),
        sheets: strip('s1', [['1', 'quotesdone.com/me, Create account'], ['2', 'The code e-mail step'], ['3', 'Name, mobile, date of birth'], ['4', 'Mobile code refused (reserved number)'], ['5', 'He accepts the terms'], ['6', 'His dashboard']]), not_real: ['His mobile is recorded verified by the test after the site refuses to text a reserved number.'] },
      terms: { version: 'Terms of Service, version 9 (stub)', accepted_at: T(6, 2), certificate: { file: M.certificate.file, bytes: M.certificate.bytes }, storage: { bucket: 'signed-terms', path: '(stub) customers/<customer id>/terms_v9_<time>.pdf', bytes: M.certificate.bytes, sha256: '(stub)' },
        dropbox: { path: '/QuotesDone Backup/_sandbox/sample01/Customers/ZZ DEMO JA Villa AC sample01 (xxxxxxxx)/Signed Terms/... (stub)', size: M.certificate.bytes, content_hash: '(stub: read back from Dropbox in the real run)', where_demo_files_go: 'A real customer\'s files are filed under /QuotesDone Backup/Customers/<name> (<id>)/ by the daily backup. A demo identity\'s never are; the real run asks the same backup code to file them under /QuotesDone Backup/_sandbox/<run tag>/ and reads each back.' } },
      verdicts: [verdict('he signs up through the site\'s own door and a signed certificate of his acceptance is stored, in Supabase and in Dropbox', `${STUB} the real run fills this line`)], gaps: [] },
    s2: { how: `${sc.how_made}.`, turns, questions: [{ text: '(stub) How many units, and of what capacity?', why: null }, { text: '(stub) Which brands would you accept?', why: null }],
      sheets: strip('s2', [['1', 'He opens New request'], ['2', 'His first message'], ['3', 'The sales engineer\'s question'], ['4', 'His answer'], ['5', 'The summary before Send'], ['6', 'Request sent']]), stored: '(stub) the turns the platform kept, and how many carry a time',
      verdicts: [verdict('the sales engineer asks only what the job needs, the chat reaches "ready" and is sent', `${STUB} the real run fills this line`)],
      gaps: ['A copy of this chat as a document. The platform keeps the chat only as data (inquiry_intake.turns), mostly without a time on each turn, and issues no transcript; the conversation archive holds e-mail, WhatsApp and notifications only. (Read in the code, 13 Nov 2026.)', 'Why each question was asked. The platform gives the question and its answer buttons, not its reason. (Read in the code; the real run confirms it from the replies.)'] },
    s3: { inquiry_pdf: M.inquiry.file, documents: [], sheets: strip('s3', [['1', 'Inquiries received (supplier)'], ['2', 'The inquiry opened'], ['3', 'Further down']]),
      messages: [{ channel: 'email', to: 'the supplier', at: T(6, 22), subject: '(stub) New inquiry: ...', text: '(stub) the e-mail exactly as composed for him', state: 'composed, delivery suppressed for a demo identity' }, { channel: 'whatsapp', to: 'the supplier', at: T(6, 22), subject: null, text: '(stub) the WhatsApp exactly as composed for him', state: 'composed, delivery suppressed for a demo identity' }],
      anonymity: s3scan, verdicts: [verdict('nothing that identifies the customer reaches the supplier before the reveal', s3scan.leaks ? `${s3scan.leaks} LEAK(S) on the inquiry the product's builders drew from the product's own test request (offline; the model's summary is that fixture's text)` : 'none found on the inquiry document (offline, model step stubbed)', s3scan.leaks === 0)], gaps: [] },
    s4: { fixtures: [...sc.matching.right.flatMap((r) => Array.from({ length: r.n }, (_, k) => ({ lead_id: 100 + k, label: k < 3 ? quotes[k].lh.trading_name : `hvac Dubai ${k + 1}`, trade: 'hvac', emirates: r.emirates, should: 'right' }))), { lead_id: 200, label: 'hvac Abu Dhabi only 1', trade: 'hvac', emirates: ['Abu Dhabi'], should: 'wrong_emirate' }, { lead_id: 201, label: 'hvac Abu Dhabi only 2', trade: 'hvac', emirates: ['Abu Dhabi'], should: 'wrong_emirate' }, ...sc.matching.unrelated.map((u, k) => ({ lead_id: 300 + k, label: `${u.trade} (unrelated)`, trade: u.trade, emirates: ['Dubai'], should: 'unrelated' }))],
      verdict: { asked: [100, 101, 102, 103, 104].map((id) => ({ lead_id: id, reason: '(stub) the trades and services that matched, as the platform wrote them' })), right_asked: [1, 2, 3, 4, 5], wrong_asked: [], right_missed: [], real_supplier_asked: [], added_by_test: [] },
      verdicts: [verdict('all 5 suppliers of the right trade serving Dubai are asked, and none of the others', `${STUB} the real run reads inquiry_matches`)], gaps: [] },
    s5: { quotes: q5, verdicts: [verdict('nothing that identifies a supplier reaches the customer before the reveal', q5.some((x) => x.anonymity.leaks) ? 'LEAK(S) found on the documents the product\'s builders drew (offline): see each table' : 'none found on the documents the product\'s builders drew (offline, model reading stubbed)', !q5.some((x) => x.anonymity.leaks))], gaps: [] },
    s6: { notifications: [[6, 21, 'email', '(stub) Your request is with suppliers'], [6, 21, 'whatsapp', '(stub) Your request is with suppliers'], [6, 40, 'email', '(stub) You have quotations'], [7, 41, 'email', '(stub) Your reveal: the supplier\'s details and your invoice']].map(([h, m, ch, sj]) => ({ at: T(h, m), channel: ch, type: 'stub', to: 'the customer', subject: sj, text: '(stub) the exact text as composed', state: 'composed, delivery suppressed for a demo identity' })),
      verdicts: [verdict('he is told by e-mail and WhatsApp when the request is sent, when quotations arrive and when he pays', `${STUB} the real run lists every row`)], gaps: [] },
    s7: { pdf: M.comparison.file, top: M.top3.map((x) => ({ ...x, price: x.price ?? '—' })), sheets: strip('s7', [['1', 'His request with the quotations'], ['2', 'The comparison'], ['3', 'Further down']]), verdicts: [verdict('the comparison ranks the quotations and says why', `${M.top3.length} ranked by the product's deterministic ranking, each with its reason (offline)`, M.top3.every((x) => x.why))], gaps: [] },
    s8: { chosen: `"Supplier A" (${quotes[0].lh.trading_name}), the sales engineer's first pick`, fee: `AED ${sale.reveal_fee} reveal fee + AED ${sale.processing_fee} processing = AED ${sale.total_charged} (stub figures)`, paid_with: 'Stripe test card 4242 (stub: no checkout was opened)', paid_at: sale.paid_at, payment_state: '(stub)', mode: 'test', invoice_pdf: M.invoice.file,
      vat: { ex_vat: `AED ${sale.quote_amount.toLocaleString('en-US')}.00 (stub)`, vat_stated: '(stub)', gross: '(stub)', treatment: '(stub)', base: `AED ${sale.quote_amount.toLocaleString('en-US')}.00`, fee: `AED ${sale.reveal_fee}`, rate_words: '3.00% of the base', processing: `AED ${sale.processing_fee} (stub figure)`, charged: `AED ${sale.total_charged}`, base_is_ex_vat: null, why: '(stub) The real run reads quotes.price_ex_vat and transactions.quote_amount and prints the arithmetic.' },
      revealed: [{ who: 'the customer', sees: '(stub) the supplier\'s name and contacts, as on the screen' }, { who: 'the supplier', sees: '(stub) the customer\'s name and contacts, as on his screen' }], sheets: strip('s8', [['1', 'The reveal fee checkout (test mode)'], ['2', 'After the reveal: the customer'], ['3', 'After the reveal: the supplier']]),
      confirmations: [{ channel: 'email', to: 'the customer', at: T(7, 41), subject: '(stub)', text: '(stub)', state: 'composed, delivery suppressed for a demo identity' }, { channel: 'whatsapp', to: 'the supplier', at: T(7, 41), subject: null, text: '(stub)', state: 'composed, delivery suppressed for a demo identity' }],
      verdicts: [verdict('he pays the fee, gets the invoice on our template, both sides are confirmed by e-mail and WhatsApp', `${STUB} the real run fills this line`), verdict(`${quotes[2].lh.trading_name} stated only a total including VAT; the platform takes the VAT out before the fee is calculated on it, or asks him`, `${STUB} his quotation states only AED ${quotes[2].doc.tot} including VAT; the real run prints what the platform stored`)], gaps: [] },
    co: { events: [[6, 21, 's2', 'sales_engineer', '(stub) inquiry.sent on inquiry 1a2b3c4d (no outcome came back to it)', 'a model judged (inferred)'], [6, 40, 's5', 'sales_engineer', '(stub) quote.received', 'code ran (inferred)'], [7, 41, 's8', 'accountant', '(stub) reveal.paid on transaction ...', 'code ran (inferred)']].map(([h, m, step, seat, what, how]) => ({ at: T(h, m), step, seat, what, how })),
      by_step: { s2: [{ at: T(6, 21), what: '(stub) inquiry.sent', seat: 'sales_engineer' }], s3: [], s8: [{ at: T(7, 41), what: '(stub) reveal.paid', seat: 'accountant' }] },
      after_payment: [
        { title: `The invoice and the books (invoice ${sale.invoice_no}, stub)`, head: ['Journal', 'Account', 'Debit', 'Credit', 'Memo'], widths: [0.14, 0.32, 0.12, 0.12, 0.3], rows: [['(stub)', '1100 Stripe clearing', sale.total_charged.toFixed(2), '', '(stub)'], ['(stub)', '4000 Reveal fee revenue', '', sale.reveal_fee.toFixed(2), '(stub)'], ['(stub)', '4010 Processing recovered', '', sale.processing_fee.toFixed(2), '(stub)']], text: '(stub) The real run prints gl_journal_lines for this reveal and checks: balanced; no VAT line (ruling 1687); Stripe\'s cost expensed; fee = 3% x the total excluding VAT.' },
        { title: 'Who in the company heard about the sale', nobody: '(stub) The real run prints each notice to the CEO, the founder and the accountant, or says that nobody was told.' },
        { title: 'The sales engineer and the inquiry', text: '(stub) The inquiry\'s status before the payment and after it.' },
        { title: 'What the suppliers who were not chosen were told', nobody: '(stub) The real run prints each message, or says they were told nothing.' },
        { title: 'The refund window', text: '(stub) It starts at the payment (transactions.revealed_at) and ends at transactions.refund_deadline; whether the customer was told the end date.' },
      ], verdicts: [verdict('after the payment the accountant, the CEO and the sales engineer each know and act, the other suppliers are told, and the refund clock starts at the payment', `${STUB} the real run reads the rows`)], gaps: [] },
    s9: { supabase: [{ what: 'signed terms certificate', bucket: 'signed-terms', path: '(stub)', bytes: M.certificate.bytes }, { what: 'invoice', bucket: 'finance-docs', path: '(stub)', bytes: M.invoice.bytes }], dropbox: [{ what: 'signed terms', path: '/QuotesDone Backup/_sandbox/sample01/... (stub)', size: M.certificate.bytes, hash: '(stub)', verified: false, state: '(stub) read back in the real run' }], listing: '(stub) expected n, listed n, missing 0, changed 0, stray 0',
      verdicts: [verdict('every document is in Supabase and has a verified copy in Dropbox', `${STUB} the real run fills this line`)], gaps: [] },
    s10: { verdicts: [verdict('no message about this journey reached a real person', `${STUB} counted by status before teardown in the real run`)], gaps: [] },
  },
  findings: [
    ...s3scan.rows.filter((r) => r.leak).map((r) => ({ severity: 'leak', step: '3', text: `${r.label} ("${r.value}") is on the inquiry document the product's builders drew offline from the product's own test request: ${r.hits[0].snippet}` })),
    ...q5.flatMap((x) => x.anonymity.rows.filter((r) => r.leak).map((r) => ({ severity: 'leak', step: '5', text: `${x.label}: ${r.label} on what the customer sees (offline)` }))),
    { severity: 'harness', step: '-', text: 'This is a stubbed sample: every line marked (stub) is filled by the real run.' },
  ],
  cost: { ...costByStep([], steps), note: '(stub) The real run reads ai_cost_log for its run tag and attributes each call to the step whose time window holds it. Estimate for journey A: USD 0.5.' },
  stand_ins: ['THIS SAMPLE: everything that happens on the live site is stubbed (marked "(stub)"); the documents are drawn offline by the product\'s own builders from the product\'s own test fixtures; the anonymity tables are computed for real on those documents.', ...[
    'The customer is a demo identity (ZZ DEMO name, an address at Resend\'s test sink, a reserved mobile). The real run signs him up through the real form with the real e-mailed code.',
    'His mobile code cannot be received; the test records it verified after the site refuses (shown).',
    'During the chat the test adds its run tag to the platform calls (so the model may answer a demo account inside the cap); every picture of what a person SEES is taken again in a clean browser.',
    'The customer\'s words come from a script; nothing on his side is written by a model.',
    'Demo suppliers made through the platform\'s own doors; they upload their own PDF with the portal\'s own call.',
    'No message reaches anyone: composed and kept, marked suppressed. Payment in Stripe TEST mode. Dropbox: the platform\'s own backup into its sandbox area.']],
  exhibits: [],
};
const ex = (file, title, why, extra = {}) => rec.exhibits.push({ file, title, why, ...extra });
ex(M.certificate.file, 'His signed-terms certificate', 'Drawn offline by compliance_archive\'s certificate builder (stub data; no seal offline).');
ex(M.inquiry.file, 'The inquiry as a supplier receives it', 'Drawn offline by quote_documents\' inquiry builder from the product\'s own test request, its summary through the supplier inbox\'s own scrub.');
for (const x of q5) { ex(x.own_file, `${x.label}: his own quotation, as he sent it`, 'The supplier\'s own file with his full identity (the journey\'s quotation maker).', { ours: false }); ex(x.customer_pdf, `${x.label}: the quotation as the customer sees it`, 'Drawn offline by quote_documents\' quotation builder, names masked as production masks them.'); }
ex(M.comparison.file, 'The comparison report', 'Drawn offline by quote_documents\' comparison builder on quote_compare\'s deterministic ranking.');
ex(M.invoice.file, 'The invoice for the reveal fee', 'Drawn offline by reveal_fee_documents (stub sale).');
writeFileSync(join(dir, 'record.json'), JSON.stringify(rec, null, 1));
const r = spawnSync('deno', ['run', '--no-lock', '--node-modules-dir=none', `--allow-read=${REPO},${dir}`, `--allow-write=${dir}`, join(HERE, 'dossier.ts'), dir], { encoding: 'utf8', cwd: REPO });
console.log(r.stdout.trim(), r.stderr.trim().slice(-500));
if (r.status !== 0) process.exit(1);
if (finalPdf) copyFileSync(join(dir, 'Journey A dossier.pdf'), finalPdf);
