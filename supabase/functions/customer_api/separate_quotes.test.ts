// The separate-quotes question is asked once (lib/separate_quotes.ts; customer-journey audit 10 Nov 2026).
//   deno test -A --no-lock --node-modules-dir=none supabase/functions/customer_api/separate_quotes.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { answeredSeparately, separateQuotesOf } from './lib/separate_quotes.ts';

const ORIG = { id: 'T1', scope_type: 'turnkey', parent_inquiry_id: null, routing: { separate_offer: { specialists: 4 } } };

Deno.test('an unanswered turnkey miss asks, with the specialist count', () => {
  assertEquals(separateQuotesOf(ORIG, answeredSeparately([ORIG])), { specialists: 4 });
});

Deno.test('once the per-trade copy exists the question is not asked again', () => {
  const copy = { id: 'M1', scope_type: 'multi', repeat_of: 'T1', parent_inquiry_id: null };
  assertEquals(separateQuotesOf(ORIG, answeredSeparately([copy, ORIG])), null);
});

Deno.test('a plain repeat (one contractor again) or a trade part of a split is not the answer', () => {
  const again = { id: 'T2', scope_type: 'turnkey', repeat_of: 'T1', parent_inquiry_id: null };
  const child = { id: 'C1', scope_type: 'single', repeat_of: 'T1', parent_inquiry_id: 'M1' };
  assertEquals(separateQuotesOf(ORIG, answeredSeparately([again, child, ORIG])), { specialists: 4 });
});

Deno.test('no offer, or not turnkey: nothing to ask', () => {
  assertEquals(separateQuotesOf({ ...ORIG, routing: {} }, new Set()), null);
  assertEquals(separateQuotesOf({ ...ORIG, scope_type: 'single' }, new Set()), null);
});

Deno.test('my_inquiries serves the question through this rule, and repeat_inquiry refuses a second per-trade copy', async () => {
  const life = await Deno.readTextFile(new URL('./actions/inquiry_lifecycle.ts', import.meta.url));
  assert(/separate_quotes:\s*separateQuotesOf\(i, answeredSep\)/.test(life), 'my_inquiries computes separate_quotes with separateQuotesOf');
  assert(/answeredSeparately\(tops\)/.test(life), 'from the customer\'s own top-level requests');
  const create = await Deno.readTextFile(new URL('./actions/inquiry_create.ts', import.meta.url));
  const rep = create.slice(create.indexOf("if (action === 'repeat_inquiry')"), create.indexOf("if (action === 'create_inquiry')"));
  assert(/already_separate/.test(rep) && /\.eq\('repeat_of', o\.id\)\.eq\('scope_type', 'multi'\)/.test(rep), 'repeat_inquiry refuses a second per-trade copy of the same request');
});
