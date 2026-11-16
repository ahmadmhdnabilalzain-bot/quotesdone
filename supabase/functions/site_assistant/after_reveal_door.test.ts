// The widget's "problem with this job" door (after_reveal_door.ts, 16 Nov 2026, AFTER_REVEAL). Stubbed RPC; ZZ DEMO ids only.
//   deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/site_assistant/after_reveal_door.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { fileAfterRevealProblem, type Rpc } from './after_reveal_door.ts';

const CUST = { audience: 'customer' as const, id: '0d0d0d0d-0000-4000-8000-000000000001', email: 'zz-widget@example.invalid' };
function rpc(answer: Record<string, unknown> = { ok: true, rfq_no: '1043' }) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const f: Rpc = (fn, args) => { calls.push({ fn, args }); return Promise.resolve({ data: answer, error: null }); };
  return { f, calls };
}

Deno.test('a signed-in customer whose message the reading says needs a person reaches the one door, channel widget', async () => {
  const { f, calls } = rpc();
  const r = await fileAfterRevealProblem(f, CUST, ' ZZ DEMO the supplier I paid for never called ', true);
  assert(r.filed);
  assertEquals(calls, [{ fn: 'fn_customer_after_reveal_message',
    args: { p_customer: CUST.id, p_message: 'ZZ DEMO the supplier I paid for never called', p_channel: 'widget', p_transaction: null } }]);
});
Deno.test('nothing reaches the door when the reading says no, is held, or the caller is not a signed-in customer', async () => {
  for (const [who, person] of [[CUST, false], [CUST, null], [null, true], [{ audience: 'supplier' as const, id: '7' }, true]] as const) {
    const { f, calls } = rpc();
    const r = await fileAfterRevealProblem(f, who, 'ZZ DEMO he raised the price', person);
    assertEquals([r.filed, calls.length], [false, 0]);
  }
});
Deno.test('a door that finds no revealed job says so; it is not counted as filed', async () => {
  const { f } = rpc({ ok: false, code: 'no_revealed_job' });
  assertEquals(await fileAfterRevealProblem(f, CUST, 'ZZ DEMO help', true), { filed: false, why: 'no_revealed_job', result: { ok: false, code: 'no_revealed_job' } });
});
Deno.test('the widget files the door from the reading it already makes, and decides nothing from the words itself', async () => {
  const idx = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  const at = idx.indexOf('fileAfterRevealProblem(');
  assert(at > 0, 'site_assistant/index.ts calls the door');
  assert(at > idx.indexOf('const person = (await needsAPerson('), 'the door is called after the needs-a-person reading, from its value');
  const door = await Deno.readTextFile(new URL('./after_reveal_door.ts', import.meta.url));
  assert(!/text\s*\.\s*(match|includes|search)\(|\.test\(text\)/.test(door), 'the message is never pattern-read in code');
});
