// deno test supabase/functions/_shared/boq_open_lines.test.ts
// The hold rule: an uncertain line is shown to the customer as OUR count, one question is asked,
// and every outcome — yes, adjust, not sure, no answer — is recorded on the line. Never silent.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { confirmQuestion, openLines, readConfirmAnswer, settleLines, type Line } from './boq_open_lines.ts';

const BOQ: Line[] = [
  { description: 'Addressable loop addresses, loop L1', qty: 70, unit: 'addresses', qty_status: 'read' },
  { description: 'Smoke detector', qty: null, estimate: 24, unit: 'nos', qty_status: 'to_confirm', type: 'smoke_detector' },
  { description: 'Smoke detector c/w sounder', qty: null, estimate: 9, unit: 'nos', qty_status: 'to_confirm', type: 'smoke_detector_sounder' },
  { description: 'Fire-rated cable', qty: null, unit: 'm', type: 'fire_rated_cable' },
];

Deno.test('a printed or read quantity is not re-asked; uncertain lines are', () => {
  const open = openLines(BOQ);
  assertEquals(open.map((o) => o.key), ['boq_smoke_detector', 'boq_smoke_detector_sounder', 'boq_fire_rated_cable']);
  assertEquals(open.map((o) => o.estimate), [24, 9, null]);
});

Deno.test('the question shows our count and never asks the customer to count', () => {
  const q = confirmQuestion(openLines(BOQ), 'en');
  assert(q.text.includes('24 × Smoke detector'));
  assert(q.text.includes('We could not count: Fire-rated cable'));
  assert(!/how many/i.test(q.text));
  assertEquals(q.options.length, 3);
  const ar = confirmQuestion(openLines(BOQ), 'ar');
  assert(ar.text.includes('24 × Smoke detector') && ar.options[0].startsWith('نعم'));
});

Deno.test('yes / adjust / not sure / no answer all end in a stated line', () => {
  const open = openLines(BOQ);
  assertEquals(readConfirmAnswer(open, 'Yes, that is right').status, 'confirmed');
  assertEquals(readConfirmAnswer(open, 'نعم، هذا صحيح').status, 'confirmed');
  assertEquals(readConfirmAnswer(open, 'Not sure').status, 'not_sure');
  const adj = readConfirmAnswer(open, 'smoke detector c/w sounder 11, smoke detectors 20');
  assertEquals(adj.status, 'adjusted');
  assertEquals(adj.adjustments, { boq_smoke_detector_sounder: 11, boq_smoke_detector: 20 });

  const confirmed = settleLines(BOQ, { status: 'confirmed', lines: open });
  assertEquals(confirmed[1].qty, 24); assertEquals(confirmed[1].qty_status, 'customer_confirmed');
  assertEquals(confirmed[3].qty, null); assertEquals(confirmed[3].qty_status, 'estimated_supplier_to_verify');

  const unanswered = settleLines(BOQ, null);
  assertEquals(unanswered[0], BOQ[0]);
  assert(unanswered.slice(1).every((l) => l.qty_status === 'estimated_supplier_to_verify' && /supplier to verify take-off/.test(l.basis || '')));

  const adjusted = settleLines(BOQ, { status: 'adjusted', lines: open, adjustments: adj.adjustments });
  assertEquals([adjusted[1].qty, adjusted[2].qty], [20, 11]);
  assertEquals(adjusted[1].qty_status, 'customer_stated');
});
