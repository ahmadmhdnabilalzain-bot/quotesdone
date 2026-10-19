// prevented by: this test. The 19 Oct 2026 gap was a chat prompt with no trade knowledge in it at all; this fails if
// the block stops carrying the retrieved rows, if an unrelated row passes the floor, or if a failure breaks the reply.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { givenBlock, givenTradeKnowledge, GIVEN_FLOOR } from './given_trade_knowledge.ts';

const deps = (data: unknown, error: { message: string } | null = null) => ({
  embed: async () => [0.1, 0.2],
  gteReads: () => true,
  rpc: (_fn: string, _a: Record<string, unknown>) => Promise.resolve({ data, error }),
});

Deno.test('the lead-time row reaches the prompt; an unrelated row does not', async () => {
  const rows = await givenTradeKnowledge(deps([
    { title: 'Industrial machinery - typical lead times in the UAE', excerpt: 'New Chinese machines: 6-12 weeks production plus 3-5 weeks sea freight.', similarity: 0.88 },
    { title: 'Pest control', excerpt: 'Termite warranty', similarity: GIVEN_FLOOR - 0.05 },
  ]), 'used vs new injection moulding machine lead time');
  assertEquals(rows.length, 1);
  const b = givenBlock(rows);
  assert(b.includes('6-12 weeks') && b.includes('TRADE KNOWLEDGE'));
});

Deno.test('a failed retrieval leaves the prompt unchanged', async () => {
  assertEquals(await givenTradeKnowledge(deps(null, { message: 'down' }), 'x'), []);
  assertEquals(givenBlock([]), '');
  const throwing = { ...deps([]), embed: async () => { throw new Error('cold'); } };
  assertEquals(await givenTradeKnowledge(throwing, 'x'), []);
});
