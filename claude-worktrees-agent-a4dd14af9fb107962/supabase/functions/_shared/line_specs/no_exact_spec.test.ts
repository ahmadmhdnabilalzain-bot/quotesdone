// no_exact_spec.test.ts — when no supplier quoted the customer's exact spec (founder_instruction #321).
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/line_specs/no_exact_spec.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { technicalComparison } from './compare.ts';
import { noExactSpec, offerMessage, acceptedMessage, apologyMessage } from './no_exact_spec.ts';
import { latinLeaks } from '../trade_glossary_ar.test.ts';
import type { Requirements } from './assess.ts';

const now = new Date('2026-09-14T10:00:00Z');
const terms = (p: number) => ({ lead_time: '21 days', warranty: '2 years on workmanship', scope: 'Supply and installation of wardrobes by our team', price_ex_vat: p });
const q = (id: string, letter: string, desc: string, p: number, option_no = 1) => ({ quote_id: id, label_en: `Supplier ${letter}`, label_ar: `المورّد ${letter}`, supplier_letter: letter, option_no, lines: [{ line_no: 1, description: desc, amount: p }], terms: terms(p) });
// The customer asked for 18 mm MR MDF wardrobes (thickness from the BOQ wording: mandatory for joinery).
const REQ_LINE = [{ line_no: 1, description: 'Wardrobe 18mm MR MDF HPL finish', qty: 4, unit: 'nos' }];
const tech = (quotes: ReturnType<typeof q>[], accepted: Array<{ line_no: number; attr: string; accepted: string }> = []) =>
  technicalComparison({ category: 'joinery', request_lines: REQ_LINE, requirements: null as unknown as Requirements, quotes, on_hold: 0, now, accepted });

Deno.test('triggers when no eligible quote matches a mandatory requested value and at least one offers another', () => {
  const t = tech([q('q1', 'A', 'Wardrobes 16mm MR MDF, HPL finish', 5000), q('q2', 'B', 'Wardrobes 16mm MR MDF, HPL finish', 5200), q('q3', 'C', 'Wardrobes 25mm MR MDF, HPL finish', 6000)]);
  const offers = noExactSpec(t);
  const thk = offers.find((o) => o.attr === 'thickness_mm')!;
  assert(thk, 'thickness offer opened: ' + JSON.stringify(offers.map((o) => o.attr)));
  assertEquals(thk.requested, '18');
  assertEquals(thk.alternatives, [{ option_id: 'o1', value: '16', suppliers: 2 }, { option_id: 'o2', value: '25', suppliers: 1 }]);
  assertEquals(thk.line_no, 1);
});

Deno.test('does not trigger when ANY eligible quote matches the exact spec', () => {
  const t = tech([q('q1', 'A', 'Wardrobes 16mm MR MDF, HPL finish', 5000), q('q2', 'B', 'Wardrobes 18mm MR MDF, HPL finish', 5200)]);
  assertEquals(noExactSpec(t).filter((o) => o.attr === 'thickness_mm'), []);
});

Deno.test('two options of one supplier count as ONE supplier offering that value', () => {
  const t = tech([q('q1', 'A', 'Wardrobes 16mm MR MDF, HPL finish', 5000, 1), q('q1b', 'A', 'Wardrobes 16mm MR MDF, HPL finish', 5100, 2), q('q2', 'B', 'Wardrobes 25mm MR MDF, HPL finish', 6000)]);
  const thk = noExactSpec(t).find((o) => o.attr === 'thickness_mm')!;
  assertEquals(thk.alternatives.map((a) => [a.value, a.suppliers]), [['16', 1], ['25', 1]]);
});

Deno.test('once the customer accepts an alternative it is their request: the matching quote matches and nothing re-triggers', () => {
  const qs = [q('q1', 'A', 'Wardrobes 16mm MR MDF, HPL finish', 5000), q('q2', 'B', 'Wardrobes 25mm MR MDF, HPL finish', 6000)];
  const t = tech(qs, [{ line_no: 1, attr: 'thickness_mm', accepted: '16' }]);
  const row = t.lines[0].attributes.find((a) => a.code === 'thickness_mm')!;
  assertEquals([row.requested, row.requested_source], ['16', 'accepted']);
  assertEquals(row.cells.map((c) => c.flag), ['match', 'differs'], 'the accepted spec is not a deviation; another value still is');
  assertEquals(noExactSpec(t).filter((o) => o.attr === 'thickness_mm'), []);
});

Deno.test('STRUCTURAL: an alternative carries option_id, value and a supplier count — never a supplier identity', () => {
  const t = tech([q('quote-uuid-1', 'A', 'Wardrobes 16mm MR MDF, HPL finish', 5000), q('quote-uuid-2', 'B', 'Wardrobes 25mm MR MDF, HPL finish', 6000)]);
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
    // Supplier or customer wording the glossary cannot finish may only follow "كما وردت".
    const primary = (m.subject + '\n' + m.body).replace(/\(كما وردت: [^)]*\)/g, '');
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
