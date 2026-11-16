// deno test --no-lock --node-modules-dir=none supabase/functions/supplier_api/loss_feedback.test.ts
//
// WHY A QUOTATION WAS NOT CHOSEN (16 Nov 2026, SUPPLIER hole 9; agent SUPPLIER_W2). Before: a fixed 5 % band over quote_amount
// (mixed VAT bases) and a regex over lead times decided "why", the customer was never asked, and a request that ended revealed or
// expired said nothing. Now the model writes the reason once from the customer's word and the EX-VAT facts, and code only refuses a
// written reason that carries a figure that is not his own or anything of the chosen supplier's name. ZZ DEMO values; stub model.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import * as lf from './loss_feedback.ts';
import { type LossDue, LOSS_SYS, lossFeedbackShown, lossInput, lossLeaks, lossReasonsSweep, NEUTRAL, NOT_YET, writeLossReason } from './loss_feedback.ts';

const D: LossDue = {
  inquiry_id: 'i-1', supplier_id: 7, ref: 'RFQ-164810', trade: 'plumbing', status: 'completed', outcome: 'hired_other',
  decision_reason: 'ZZ DEMO they could start on Sunday and visited the site first',
  mine: { ex_vat: 9000, lead_time: '10 days', exclusions: 'scaffolding', submittable: true },
  chosen: { ex_vat: 9450, lead_time: '7 days', exclusions: null, submittable: true }, chosen_name: 'ZZ DEMO Falcon Plumbing LLC',
};

Deno.test('the code rule is gone: no price band, no lead-time regex, nothing that decides "why" without the model', () => {
  assertEquals(typeof (lf as Record<string, unknown>).lossFeedback, 'undefined');
  assertEquals(typeof (lf as Record<string, unknown>).leadDays, 'undefined');
});

Deno.test('the model is given the customer\'s word, the outcome and an ex-VAT comparison; the rival\'s figures are marked private', () => {
  const s = lossInput(D);
  assertMatch(s, /start on Sunday and visited the site/);
  assertMatch(s, /AED 9,000 before VAT/);
  assertMatch(s, /his price before VAT was LOWER than the chosen one/);
  assertMatch(s, /PRIVATE COMPARISON \(never to be shown\)/);
  assert(!s.includes('9450') && !s.includes('9,450'), 'the rival\'s amount never reaches the model as a figure, only as a comparison');
  assertMatch(LOSS_SYS, /NEVER write any figure/);
});

Deno.test('a price stated with VAT is never compared: without both ex-VAT figures the model is told they cannot be compared', () => {
  const s = lossInput({ ...D, chosen: { ex_vat: null, lead_time: '7 days' } });
  assertMatch(s, /cannot be compared before VAT/);
});

Deno.test('the check refuses the rival\'s amount, days, any other figure and the rival\'s name; it keeps his own figures', () => {
  assertEquals(lossLeaks('Your quotation of AED 9,000 was lower, but the customer valued a site visit and an earlier start.', D), null);
  assertMatch(String(lossLeaks('The chosen quote was AED 9,450.', D)), /figure 9450/);
  assertMatch(String(lossLeaks('The winner could finish in 7 days.', D)), /figure 7/);
  assertMatch(String(lossLeaks('The customer chose ZZ DEMO Falcon Plumbing LLC.', D)), /named/);
  assertMatch(String(lossLeaks('Falcon visited the site first.', D)), /falcon/);
  assertEquals(lossLeaks('Your 10 days lead time was longer.', D), null);
});

Deno.test('EN: the model\'s clean reason is stored as written; a leaking one is replaced by the neutral line and marked refused', async () => {
  const ok = await writeLossReason(() => Promise.resolve('Your price was lower, but the customer chose a supplier who visited the site and could start sooner.'), D);
  assertEquals(ok?.basis.written_by, 'model');
  // review supplierw2: the rival's start day the customer named ("Sunday") is a date of the chosen quotation, refused
  assertMatch(String(lossLeaks('The customer chose a supplier who could start on Sunday.', D)), /customer named Sunday/);
  // Arabic-Indic digits, spelled numbers, ranks and a brand the customer named are refused
  assertMatch(String(lossLeaks('The chosen quotation was AED \u0669\u0664\u0665\u0660.', D)), /figure 9450/);
  assertMatch(String(lossLeaks('It was about twenty percent lower.', D)), /number or rank word/);
  assertMatch(String(lossLeaks('Yours came third.', D)), /number or rank word/);
  assertMatch(String(lossLeaks('The customer preferred Daikin units.', { ...D, decision_reason: 'they offered Daikin units' })), /customer named Daikin/);
  assertMatch(ok!.text, /visited the site/);
  const bad = await writeLossReason(() => Promise.resolve('The chosen supplier quoted AED 9,450 and 7 days.'), D);
  assertEquals(bad?.text, NEUTRAL);
  assertEquals(bad?.basis.fallback, 'refused');
  assertEquals(await writeLossReason(() => Promise.resolve(null), D), null);
});

Deno.test('AR customer word: an Arabic reason reaches the model as data and the supplier\'s reason is English', async () => {
  const d = { ...D, decision_reason: 'اخترنا المورد الذي زار الموقع وبدأ أسرع' };
  let seen = '';
  const r = await writeLossReason((_s, input) => { seen = input; return Promise.resolve('The customer chose a supplier who visited the site and could start sooner; consider offering a site visit.'); }, d);
  assertMatch(seen, /زار الموقع/);
  assert(!/[؀-ۿ]/.test(r!.text));
});

Deno.test('the sweep stores each reason once, and the inbox shows the stored one or says it is being written', async () => {
  const inserted: Record<string, unknown>[] = [];
  // deno-lint-ignore no-explicit-any
  const admin: any = { rpc: () => Promise.resolve({ data: [D, { ...D, supplier_id: 8 }] }), from: () => ({ insert: (r: Record<string, unknown>) => { inserted.push(r); return Promise.resolve({ error: null }); } }) };
  let n = 0;
  const res = await lossReasonsSweep(admin, () => Promise.resolve(n++ === 0 ? 'The customer valued a site visit before deciding.' : 'Rival quoted 9450.'));
  assertEquals(res, { written: 1, refused: 1, skipped: 0 });
  assertEquals(inserted.map((r) => r.supplier_id), [7, 8]);
  assertEquals(lossFeedbackShown({ text: 'X' }), [{ code: 'reason', text: 'X' }]);
  assertEquals(lossFeedbackShown(null), [NOT_YET]);
  assert(!/\d/.test(NOT_YET.text + NEUTRAL));
});
