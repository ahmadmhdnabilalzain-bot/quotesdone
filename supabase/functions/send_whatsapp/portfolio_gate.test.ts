// The portfolio re-check fails closed and never stalls the drain (review of #869).
//   deno test supabase/functions/send_whatsapp/portfolio_gate.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { portfolioGate } from './portfolio_gate.ts';

const answer = (data: unknown, error: { message: string } | null = null) => () => Promise.resolve({ data, error });

Deno.test('still due -> send; complete -> cancel', async () => {
  assertEquals((await portfolioGate(answer(true), 1)).action, 'send');
  assertEquals((await portfolioGate(answer(false), 1)).action, 'cancel');
});

Deno.test('an error, a null, a throw or no lead id holds the row: never sent', async () => {
  assertEquals((await portfolioGate(answer(null, { message: 'function does not exist' }), 1)).action, 'hold');
  assertEquals((await portfolioGate(answer(null), 1)).action, 'hold');
  assertEquals((await portfolioGate(() => { throw new Error('boom'); }, 1)).action, 'hold');
  assertEquals((await portfolioGate(answer(true), null)).action, 'hold');
});

Deno.test('a hung re-check holds within the deadline, and the rest of the queue still drains', async () => {
  const hung = () => new Promise<never>(() => {});
  const queue = [{ id: 1, rpc: hung }, { id: 2, rpc: answer(null, { message: 'forced error' }) }, { id: 3, rpc: answer(true) }];
  const sent: number[] = []; const held: number[] = [];
  const t0 = Date.now();
  for (const n of queue) {
    const g = await portfolioGate(n.rpc, 7, 50);
    if (g.action === 'send') sent.push(n.id); else held.push(n.id);
  }
  assertEquals(held, [1, 2]);
  assertEquals(sent, [3]);
  assertEquals(Date.now() - t0 < 1000, true);
});
