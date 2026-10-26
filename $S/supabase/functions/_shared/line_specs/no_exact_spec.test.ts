// no_exact_spec.test.ts — when no supplier quoted the customer's exact spec (founder_instruction #321).
// 23 Sep 2026 (decision point 28): the comparison PROPOSES (no quote's value is the customer's, exactly); an
// offer is made only when reasoning finds the difference genuine (reasoned_matching.test.ts reasonedOffers).
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/line_specs/no_exact_spec.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { technicalComparison } from './compare.ts';
import { noExactSpec, offerMessage, acceptedMessage, apologyMessage, offerTexts } from './no_exact_spec.ts';
import { latinLeaks } from '../trade_glossary_ar.test.ts';
import type { Requirements } from './assess.ts';

const now = new Date('2026-09-14T10:00:00Z');
const terms = (p: number) => ({ lead_time: '21 days', price_ex_vat: p, terms_spec: {
  installation: { included: 'yes' as const, detail: 'by our team', source: 'reasoned' as const }, warranty: { period: '2 years', coverage: 'workmanship', source: 'reasoned' as const } } });
// A quote line as the gate stores it after reading: the board it quotes, and that the line names the customer's "board".
const q = (id: string, letter: string, board: string, p: number, option_no = 1) => ({ quote_id: id, label_en: `Supplier ${letter}`, label_ar: `المورّد ${letter}`, supplier_letter: letter, option_no,
  lines: [{ line_no: 1, description: `Wardrobes 18mm ${board}, HPL finish`, amount: p, spec: { material: board, thickness_mm: '18', finish: 'HPL', '_names:board': 'Wardrobes' },
    spec_source: { material: 'reasoned' as const, thickness_mm: 'reasoned' as const, finish: 'reasoned' as const, '_names:board': 'reasoned' as const } }], terms: terms(p) });
// The customer asked, in the intake, for an MR MDF board (mandatory for joinery).
const REQ: Requirements = { version: 1, installation: { required: 'yes' }, warranty: { required: 'yes' }, materials: [{ component: 'board', label_en: 'Board', choice: 'mr_mdf', choice_en: 'MR MDF' }] };
const REQ_LINE = [{ line_no: 1, description: 'Wardrobe 18mm MR MDF HPL finish', qty: 4, unit: 'nos' }];
const tech = (quotes: ReturnType<typeof q>[], accepted: Array<{ line_no: number; attr: string; accepted: string }> = []) =>
  technicalComparison({ category: 'joinery', request_lines: REQ_LINE, requirements: REQ, quotes, on_hold: 0, now, accepted });

Deno.test('proposes when no eligible quote states the requested value exactly and at least one states another', () => {
  const t = tech([q('q1', 'A', 'Plywood', 5000), q('q2', 'B', 'plywood', 5200), q('q3', 'C', 'Particle board', 6000)]);
  const offers = noExactSpec(t);
  const mat = offers.find((o) => o.attr === 'material')!;
  assert(mat, 'material offer proposed: ' + JSON.stringify(offers.map((o) => o.attr)));
  assertEquals(mat.requested, 'MR MDF');
  assertEquals(mat.alternatives, [{ option_id: 'o1', value: 'Plywood', suppliers: 2 }, { option_id: 'o2', value: 'Particle board', suppliers: 1 }]);
  assertEquals(mat.line_no, 1);
});

Deno.test('does not propose when ANY eligible quote states the exact spec (format aside)', () => {
  const t = tech([q('q1', 'A', 'Plywood', 5000), q('q2', 'B', 'mr-mdf', 5200)]);
  assertEquals(noExactSpec(t).filter((o) => o.attr === 'material'), []);
});

Deno.test('a value that merely CONTAINS the spec is not the spec: it is proposed, and reasoning decides', () => {
  const t = tech([q('q1', 'A', 'MR MDF with melamine face', 5000)]);
  assertEquals(noExactSpec(t).find((o) => o.attr === 'material')?.alternatives.map((a) => a.value), ['MR MDF with melamine face']);
});

Deno.test('two options of one supplier count as ONE supplier offering that value', () => {
  const t = tech([q('q1', 'A', 'Plywood', 5000, 1), q('q1b', 'A', 'Plywood', 5100, 2), q('q2', 'B', 'Particle board', 6000)]);
  const mat = noExactSpec(t).find((o) => o.attr === 'material')!;
  assertEquals(mat.alternatives.map((a) => [a.value, a.suppliers]), [['Particle board', 1], ['Plywood', 1]]);
});

Deno.test('once the customer accepts an alternative it is their request: the matching quote matches and nothing re-triggers', () => {
  const qs = [q('q1', 'A', 'Plywood', 5000), q('q2', 'B', 'Particle board', 6000)];
  const t = tech(qs, [{ line_no: 1, attr: 'material', accepted: 'Plywood' }]);
  const row = t.lines[0].attributes.find((a) => a.code === 'material')!;
  assertEquals([row.requested, row.requested_source], ['Plywood', 'accepted']);
  assertEquals(row.cells.map((c) => c.flag), ['match', 'differs'], 'the accepted spec is not a deviation; another value still is');
  assertEquals(noExactSpec(t).filter((o) => o.attr === 'material'), []);
});

Deno.test('STRUCTURAL: an alternative carries option_id, value and a supplier count — never a supplier identity', () => {
  const t = tech([q('quote-uuid-1', 'A', 'Plywood', 5000), q('quote-uuid-2', 'B', 'Particle board', 6000)]);
  const offers = noExactSpec(t);
  assert(offers.length > 0);
  for (const o of offers) {
    assertEquals(Object.keys(o).sort(), ['alternatives', 'attr', 'item', 'label_ar', 'label_en', 'line_no', 'requested']);
    for (const a of o.alternatives) {
      assertEquals(Object.keys(a).sort(), ['option_id', 'suppliers', 'value']);
      assertEquals(typeof a.suppliers, 'number');
    }
    const s = JSON.stringify(o);
    for (const id of ['quote-uuid-1', 'quote-uuid-2', 'Supplier A', 'Supplier B', 'المورّد A', 'المورّد B']) assert(!s.includes(id), 'identity leaked: ' + id);
  }
  // And every message built from it.
  for (const lang of ['en', 'ar'] as const) for (const m of [offerMessage(offers[0], lang, { rfqNo: 1042 }), apologyMessage(offers[0], lang, 'declined')])
    for (const id of ['quote-uuid', 'Supplier A', 'Supplier B', 'المورّد A', 'المورّد B']) assert(!(m.subject + m.body).includes(id), 'identity in a message: ' + id);
});

const OFFER = { item: 'Wardrobe', label_en: 'Thickness', label_ar: 'السماكة', requested: '18', alternatives: [{ option_id: 'o1', value: '16', suppliers: 2 }, { option_id: 'o2', value: '25', suppliers: 1 }], accepted_value: '16' };

Deno.test('the question, the reminders, the confirmation and the apology: English and fully Arabic', () => {
  const en = offerMessage(OFFER, 'en', { rfqNo: 1042, portalUrl: 'https://quotesdone.com/me?request=x' });
  assert(en.body.includes('No supplier was able to quote your exact specification'));
  assert(en.body.includes('1) 16 — 2 suppliers') && en.body.includes('2) 25 — 1 supplier'));
  assert(/Reply with the option number, or NO/.test(en.body));
  assert(offerMessage(OFFER, 'en', { reminder: 2, final: true }).subject.startsWith('Final reminder: '));
  for (const m of [offerMessage(OFFER, 'ar', { rfqNo: 1042 }), offerMessage(OFFER, 'ar', { reminder: 1 }), offerMessage(OFFER, 'ar', { reminder: 2, final: true }),
    acceptedMessage(OFFER, 'ar', { rfqNo: 1042 }), apologyMessage(OFFER, 'ar', 'declined', { rfqNo: 1042 }), apologyMessage(OFFER, 'ar', 'no_reply')]) {
    // Without a reasoned translation the person's own words are a ⟦placeholder⟧ and the message reports them in
    // `untranslated` — such a message is never sent (it is retried or parked). Everything around them is Arabic.
    const primary = (m.subject + '\n' + m.body).replace(/⟦[^⟧]*⟧/g, '');
    assertEquals(latinLeaks(primary), [], 'English in an Arabic message: ' + m.subject);
  }
  assert(offerMessage(OFFER, 'ar', {}).body.includes('مورّدان'), 'two suppliers in Arabic');
  assert(apologyMessage(OFFER, 'en', 'no_reply').body.includes('nothing has been charged'));
  assert(apologyMessage(OFFER, 'ar', 'declined').body.includes('دون أي رسوم'));
});

Deno.test('no message tells the customer to contact a supplier', () => {
  const all = (['en', 'ar'] as const).flatMap((l) => [offerMessage(OFFER, l), acceptedMessage(OFFER, l), apologyMessage(OFFER, l, 'declined'), apologyMessage(OFFER, l, 'no_reply')]);
  for (const m of all) assert(!/contact the supplier|ask the supplier|تواصل مع المورّ?د|اسأل المورّ?د/i.test(m.body), m.body);
});

Deno.test('an Arabic message prints the reasoned Arabic of the words when it has it, and is NOT sendable when it does not', () => {
  const arTexts = { Wardrobe: 'خزانة ملابس' };
  assertEquals(offerTexts(OFFER), ['Wardrobe', '18', '16', '16', '25']);
  const withIt = offerMessage(OFFER, 'ar', { arTexts });
  assert(withIt.body.includes('البند: خزانة ملابس'), withIt.body);
  assertEquals(latinLeaks(withIt.body), []);
  assertEquals(withIt.untranslated, [], 'a whole Arabic message may go');
  const held = offerMessage(OFFER, 'ar', {});
  assertEquals(held.untranslated, ['Wardrobe'], 'the caller must not send it: it is retried or parked until reasoned');
  assert(held.body.includes('البند: ⟦Wardrobe⟧'), 'the placeholder fn_arabic_outbound_flush fills: ' + held.body);
  assert(!/خزانة|«Wardrobe»/.test(held.body), 'nothing is guessed and nothing is quoted');
  assertEquals(acceptedMessage({ ...OFFER, accepted_value: 'E1 MDF' }, 'ar', {}).untranslated, ['E1 MDF']);
  assertEquals(acceptedMessage(OFFER, 'ar', {}).untranslated, [], 'a number needs no translation');
});
