// deno test --no-lock --node-modules-dir=auto supabase/functions/supplier_api/loss_feedback.test.ts
//
// Per-quote loss feedback: the right reason, and NOTHING of the rival in the output. Pure function,
// ZZ DEMO values only.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { leadDays, lossFeedback } from './loss_feedback.ts';

const chosen = { quote_amount: 48217, lead_time: '9 days', exclusions: null, submittable: true };
const codes = (x: { code: string }[]) => x.map((y) => y.code);

function noRival(out: unknown) {
  const s = JSON.stringify(out);
  for (const leak of ['48217', '48,217', '9 days', '9', 'ZZ DEMO']) assert(!s.includes(leak), `rival detail "${leak}" leaked: ${s}`);
  assert(!/\d/.test(s), `no figure of any kind may reach the supplier: ${s}`);
}

Deno.test('price above the band', () => {
  const out = lossFeedback({ quote_amount: 61000, lead_time: '5 days' }, chosen);
  assertEquals(codes(out), ['price_above']); noRival(out);
});
Deno.test('price close, longer lead time', () => {
  const out = lossFeedback({ quote_amount: 49000, lead_time: '3 weeks' }, chosen);
  assertEquals(codes(out), ['price_close', 'lead_time_longer']); noRival(out);
});
Deno.test('cheaper but incomplete scope', () => {
  const out = lossFeedback({ quote_amount: 30000, lead_time: '5 days', exclusions: 'ZZ DEMO excludes installation' }, chosen);
  assertEquals(codes(out), ['scope_incomplete']); noRival(out);
});
Deno.test('cheaper, faster, complete: overall value', () => {
  const out = lossFeedback({ quote_amount: 30000, lead_time: '2 days' }, chosen);
  assertEquals(codes(out), ['overall_value']); noRival(out);
});
Deno.test('nobody hired: the inquiry reason code, never free text', () => {
  assertEquals(codes(lossFeedback({ quote_amount: 1 }, null, 'no_exact_spec_declined')), ['closed_no_exact_spec']);
  const free = lossFeedback({ quote_amount: 1 }, null, 'went with ZZ DEMO Rival LLC at 48217');
  assertEquals(codes(free), ['closed_no_award']); noRival(free);
});
Deno.test('lead time parsing', () => {
  assertEquals(leadDays('2 weeks'), 14); assertEquals(leadDays('10 working days'), 10); assertEquals(leadDays('1 month'), 30); assertEquals(leadDays('asap'), null);
});
