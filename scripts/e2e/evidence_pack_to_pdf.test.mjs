// Assigned: it_engineer. The pack lists every document in reading order and NAMES a missing one (19 Nov 2026, ledger 1684).
import test from 'node:test'; import assert from 'node:assert/strict';
import { packPlan, coverHtml, safeTag } from './evidence_pack_to_pdf.mjs';
const files = ['chat_transcript.txt', 'customer_BOQ_villa_HVAC.xlsx', '42_inquiry_as_sent_to_suppliers.pdf', '63_invoice.pdf'];
test('plan is in reading order and flags what is missing', () => {
  const plan = packPlan('/x', files, () => ['Q10_B_supplier_quotation.pdf', 'Q2_A_supplier_quotation.pdf']);
  assert.deepEqual(plan.map((p) => !!p.file), [true, true, false, true, true, true, false, true]);
  assert.match(plan[4].file, /Q2_A/); assert.match(plan[5].file, /Q10_B/);
  assert.match(coverHtml('t', plan, { tag: 'abc', dry: true }), /MISSING/);
});
test('no quotations still lists the gap', () => {
  const plan = packPlan('/x', files, () => []);
  assert.equal(plan.filter((p) => /quotations/.test(p.label) && !p.file).length, 1);
});
test('a run tag can never climb out of evidence_packs/', () => {
  for (const bad of ['../x', '..', '../../etc/passwd', 'a/b', '%2e%2e', '']) { const s = safeTag(bad); assert.ok(!/[/.%]/.test(s), s); assert.ok(s.length > 0); }
  assert.equal(safeTag('run_19nov-A1'), 'run_19nov-A1'); assert.equal(safeTag(undefined), 'untagged');
});
