// gypsum_rules_proof.mjs — the end-to-end proof of docs/knowledge/GYPSUM_PROOF_21_SEP_2026.md.
//
// Stands up, inside a demo_factory run (ZZ DEMO names, @example.invalid, +9715000000xx; torn down in
// finally), the D958E1EA-shaped gypsum inquiry (Business Bay office fit-out: 320 m2 partitions,
// 410 m2 600x600 mineral-fibre ceiling, 64 m painted bulkhead) and two quotations:
//   A — compliant: MR 12.5 mm Knauf board on 0.6 mm studs, insulation, jointing and finish, grid,
//       fixings, deflection head, cut-outs, debris removal; market rates.
//   B — standard board substituted for the requested moisture-resistant board, 9.5 mm, no jointing/
//       finish line (mandatory), no insulation, and AED 38/m2 on the partition (band 60-130).
// BEFORE: the DEPLOYED quote_compare (main's code path) is called on the inquiry, EN and AR.
// AFTER:  the wired engine (this branch's compare.ts + rules.ts with rules/gypsum.json) runs over the
//         same rows through gypsum_rules_proof.after.ts, EN and AR.
// Both are written to the scratch directory given as argv[2]; nothing is written to the repository.
//
//   node scripts/staging/gypsum_rules_proof.mjs <out_dir>
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { call, internalCred, jb, makeCustomer, makeInquiry, makeQuote, makeSupplier, num, q, REF, withRun } from './demo_factory.mjs';
import { mgmtFixture, mgmtRead } from './qd_guard.mjs';

const OUT = process.argv[2];
if (!OUT) { console.error('usage: node scripts/staging/gypsum_rules_proof.mjs <out_dir>'); process.exit(2); }
fs.mkdirSync(OUT, { recursive: true });
const HERE = path.dirname(fileURLToPath(import.meta.url));

const BOQ = [
  { qty: 320, unit: 'm2', section: 'Partitions', confidence: 'high', description: 'Gypsum board partition, 100mm metal stud, both faces' },
  { qty: 410, unit: 'm2', section: 'Ceilings', confidence: 'high', description: 'Suspended false ceiling, 600x600 mineral fibre tiles' },
  { qty: 64, unit: 'm', section: 'Ceilings', confidence: 'medium', description: 'Gypsum bulkhead, 300mm drop, painted finish' },
];
const SUMMARY = 'Gypsum partitions and false ceiling for an office fit-out in Business Bay, Dubai';
const REQUIREMENTS = { version: 1, warranty: { required: 'yes' }, installation: { required: 'yes' }, materials: [{ component: 'partitions', label_en: 'Partition board', choice: 'Moisture-resistant board', choice_en: 'Moisture-resistant board' }] };
const TERMS = { lead_time: '3 weeks', validity: '30 days', warranty: '12 months on materials and workmanship', payment_terms: '50% advance, 50% on completion', conditions: 'Access to site during working hours.', exclusions: 'MEP works above the ceiling.' };
const A_LINES = [
  { line_no: 1, description: 'Gypsum board partition 12.5mm moisture-resistant Knauf board both faces on 100mm x 0.6mm GI studs at 600mm centres, 50mm rockwool 40kg/m3 insulation, taping, jointing compound and Q3 finish', qty: 320, unit: 'm2', unit_price: 95, amount: 30400 },
  { line_no: 2, description: 'Suspended ceiling 600x600 mineral fibre tiles 15mm on Knauf grid system with hangers and perimeter trim', qty: 410, unit: 'm2', unit_price: 68, amount: 27880 },
  { line_no: 3, description: 'Gypsum bulkhead 12.5mm standard board on furring channels, painted; screws, corner beads and trims; deflection head track; cut-outs; debris removal', qty: 64, unit: 'm', unit_price: 27, amount: 1728 },
];
const B_LINES = [
  { line_no: 1, description: 'Gypsum board partition 9.5mm standard gypsum board both faces on 100mm studs', qty: 320, unit: 'm2', unit_price: 38, amount: 12160 },
  { line_no: 2, description: 'Suspended ceiling 600x600 ceiling tiles 12mm on exposed T-grid 24mm profiles with hangers and perimeter trim', qty: 410, unit: 'm2', unit_price: 42, amount: 17220 },
  { line_no: 3, description: 'Gypsum bulkhead 12.5mm standard board on furring channels, screws and beads', qty: 64, unit: 'm', unit_price: 25, amount: 1600 },
];
const A_SCOPE = 'Supply and installation included: site measurement, fixing and finishing of partitions, ceilings and bulkheads.';
const B_SCOPE = 'Supply and installation included: site measurement and fixing.';
const sum = (ls) => ls.reduce((s, l) => s + l.amount, 0);

const result = await withRun(async (run) => {
  const customer = await makeCustomer(run, { email: `zz-demo-${run.tag}-customer@example.invalid`, full_name: 'ZZ DEMO Gypsum Customer' });
  const supA = await makeSupplier(run, { trade: 'gypsum', email: `zz-demo-${run.tag}-a@example.invalid`, company_name: `ZZ DEMO Gypsum A ${run.tag.slice(0, 4)}` });
  const supB = await makeSupplier(run, { trade: 'gypsum', email: `zz-demo-${run.tag}-b@example.invalid`, company_name: `ZZ DEMO Gypsum B ${run.tag.slice(0, 4)}` });
  const inquiry = await makeInquiry(run, { customer, trade: 'gypsum', emirate: 'Dubai', summary: SUMMARY, raw_input: SUMMARY + '. ' + BOQ.map((b) => `${b.description} (${b.qty} ${b.unit})`).join('; ') });
  await mgmtFixture(REF, `update public.inquiries set boq = ${jb({ boq: BOQ })}, spec = coalesce(spec, '{}'::jsonb) || ${jb({ customer_requirements: REQUIREMENTS })} where id = ${q(inquiry.id)}`, 'proof boq + requirements');
  const mk = async (sup, lines, scope) => {
    const quote = await makeQuote(run, { inquiry, supplier: sup, amount: sum(lines), scope, ...TERMS });
    await mgmtFixture(REF, `update public.quotes set price_ex_vat = ${num(sum(lines))} where id = ${q(quote.id)}`, 'proof price_ex_vat');
    await mgmtFixture(REF, `insert into public.quote_items (quote_id, line_no, description, qty, unit, unit_price, amount, spec, spec_source) values ` +
      lines.map((l) => `(${q(quote.id)}, ${num(l.line_no)}, ${q(l.description)}, ${num(l.qty)}, ${q(l.unit)}, ${num(l.unit_price)}, ${num(l.amount)}, '{}'::jsonb, '{}'::jsonb)`).join(',\n'), 'proof quote items');
    return quote;
  };
  const qa = await mk(supA, A_LINES, A_SCOPE);
  const qb = await mk(supB, B_LINES, B_SCOPE);
  run.log(`inquiry ${inquiry.id}; quotes ${qa.id} (A, AED ${sum(A_LINES)}) and ${qb.id} (B, AED ${sum(B_LINES)})`);

  // BEFORE: the deployed function, main's code path, on the real rows.
  const cred = await internalCred();
  const before = {};
  for (const lang of ['en', 'ar']) {
    const r = await call('quote_compare', null, { __secret: cred, inquiry_id: inquiry.id, lang }, 170000);
    before[lang] = { status: r.status, json: r.json ?? r.text };
    fs.writeFileSync(path.join(OUT, `before.${lang}.json`), JSON.stringify(before[lang], null, 2));
  }
  const rows = await mgmtRead(REF, `select id, price_ex_vat, quote_amount, status from public.quotes where inquiry_id = ${q(inquiry.id)} order by quote_amount`);
  const items = await mgmtRead(REF, `select quote_id, line_no, description, qty, unit, unit_price, amount from public.quote_items where quote_id::text in (${q(qa.id)}, ${q(qb.id)}) order by quote_id, line_no`);

  // AFTER: the wired engine over the same rows (read back from the sandbox, not from the constants).
  const quoteOf = (id, letter) => ({ quote_id: String(id), label_en: `Supplier ${letter}`, label_ar: `المورّد ${letter === 'A' ? 'أ' : 'ب'}`, supplier_letter: letter, option_no: 1,
    lines: items.filter((i) => String(i.quote_id) === String(id)).map((i) => ({ line_no: Number(i.line_no), description: i.description, qty: Number(i.qty), unit: i.unit, unit_price: Number(i.unit_price), amount: Number(i.amount) })),
    terms: { ...TERMS, scope: letter === 'A' ? A_SCOPE : B_SCOPE, price_ex_vat: Number(rows.find((r) => String(r.id) === String(id))?.price_ex_vat) } });
  const input = { category: 'gypsum', emirate: 'Dubai', request_text: SUMMARY, request_lines: BOQ.map((b, i) => ({ line_no: i + 1, description: b.description, qty: b.qty, unit: b.unit })), requirements: REQUIREMENTS, quotes: [quoteOf(qa.id, 'A'), quoteOf(qb.id, 'B')] };
  const after = spawnSync('deno', ['run', '--allow-read', path.join(HERE, 'gypsum_rules_proof.after.ts')], { input: JSON.stringify(input), encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  if (after.status !== 0) throw new Error('after runner failed: ' + after.stderr.slice(0, 800));
  fs.writeFileSync(path.join(OUT, 'after.json'), after.stdout);
  return { inquiry_id: inquiry.id, quotes: { a: qa.id, b: qb.id }, before_status: { en: before.en.status, ar: before.ar.status }, before_engine: { en: before.en.json?.analysis?.engine ?? before.en.json?.error ?? null, ar: before.ar.json?.analysis?.engine ?? before.ar.json?.error ?? null }, before_degraded: before.en.json?.degraded ?? null, after: JSON.parse(after.stdout).en.rules_applied };
}, { tag: process.env.QD_RUN_TAG });
console.log(JSON.stringify(result, null, 2));
