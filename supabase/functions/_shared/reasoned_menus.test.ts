// menuMeaning with a MOCKED model: greeting / salam / problem / other, reasoned; held is null and nothing is queued.
//   deno test --no-lock --allow-read=. supabase/functions/_shared/reasoned_menus.test.ts
import { assert, assertEquals } from 'jsr:@std/assert';
import { menuMeaning } from './reasoned_menus.ts';
import { mockDeps } from './reasoned_trades.test.ts';

Deno.test('greeting_state: a reasoned hello, salam or other; "problem" is not even offered outside the problem state', async () => {
  assertEquals((await menuMeaning(mockDeps({ choice: 'salam' }).deps, { text: 'السلام عليكم', awaitingProblem: false })).value, 'salam');
  const m = mockDeps({ choice: 'problem' });
  assertEquals((await menuMeaning(m.deps, { text: 'hi, my quote vanished', awaitingProblem: false })).value, null, 'problem is not an option here');
  assert(!m.prompts.some((p) => p.includes('problem (the person describes')));
});

Deno.test('problem_state: the surface is wa_inbound.problem_state and "problem" is an option', async () => {
  const m = mockDeps({ choice: 'problem' });
  assertEquals((await menuMeaning(m.deps, { text: 'the supplier never came', awaitingProblem: true })).value, 'problem');
  assert(m.prompts.some((p) => p.includes('problem (the person describes')));
});

Deno.test('held: null, and nothing is filed — the conversation has moved on by the time the hold lifts', async () => {
  const m = mockDeps({ hold: true });
  assertEquals((await menuMeaning(m.deps, { text: 'Hi', awaitingProblem: true, messageSid: 'SMzz' })).value, null);
  assertEquals(m.rpcs.filter(([f]) => f === 'fn_reason_hold').length, 0);
});
