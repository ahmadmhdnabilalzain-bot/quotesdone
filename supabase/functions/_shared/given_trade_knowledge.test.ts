// prevented by: this test. The 19 Oct 2026 gap was a chat prompt with no trade knowledge in it at all; this fails if
// the block stops carrying the retrieved trade row, if an unrelated, internal, priced or supplier-identifying row
// reaches the prompt, if the read is not the customer-facing scope, or if a slow read holds the answer.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { givenBlock, givenTradeKnowledge, GIVEN_FLOOR } from './given_trade_knowledge.ts';

const seen: Record<string, unknown>[] = [];
const deps = (data: unknown, error: { message: string } | null = null) => ({
  embed: async () => [0.1, 0.2],
  gteReads: () => true,
  rpc: (_fn: string, a: Record<string, unknown>) => { seen.push(a); return Promise.resolve({ data, error }); },
});
const trade = { source: 'sales_knowledge', id: 'industrial_machinery:lead-times', title: 'Industrial machinery - typical lead times', excerpt: 'New machines built to order: 6-12 weeks production plus 3-5 weeks sea freight.', similarity: 0.88 };

Deno.test('the trade row reaches the prompt; unrelated, internal, priced and supplier rows do not', async () => {
  const rows = await givenTradeKnowledge(deps([
    trade,
    { source: 'sales_knowledge', id: 'pest_control:x', title: 'Pest control', excerpt: 'Termite warranty', similarity: GIVEN_FLOOR - 0.05 },
    { source: 'support_knowledge', id: 'internal-escalation', title: 'Internal: seat escalation rule', excerpt: 'Escalate refunds to the CEO seat before replying.', similarity: 0.95 },
    { source: 'kb_chunks', id: '991', title: 'Library page', excerpt: 'Unreviewed library text about machinery.', similarity: 0.93 },
    { source: 'sales_knowledge', id: 'hvac:price', title: 'Split AC supply and install', excerpt: 'Typical rate AED 2,400 per 1.5 TR unit installed.', similarity: 0.92 },
    { source: 'sales_knowledge', id: 'hvac:arabic-price', title: 'تكييف', excerpt: 'السعر 2400 درهم للوحدة', similarity: 0.91 },
    { source: 'sales_knowledge', id: 'steel:supplier', title: 'Steel stockist', excerpt: 'Call Example Steel LLC on +971 4 000 0000 or sales@example.invalid.', similarity: 0.9 },
  ]), 'used vs new injection moulding machine lead time');
  assertEquals(rows.map((r) => r.id), ['industrial_machinery:lead-times']);
  const b = givenBlock(rows);
  assert(b.includes('6-12 weeks') && b.includes('TRADE KNOWLEDGE'));
  for (const bad of ['CEO seat', 'Unreviewed', 'AED', 'درهم', '+971', 'LLC']) assert(!b.includes(bad), bad + ' reached the prompt');
  assertEquals(seen.at(-1)?.p_seat, 'customer_support');
  assertEquals(seen.at(-1)?.p_audience, 'visitor');   // explicit, never left to which signature is live
});

Deno.test('a failed or slow retrieval leaves the prompt unchanged and never holds the answer', async () => {
  assertEquals(await givenTradeKnowledge(deps(null, { message: 'down' }), 'x'), []);
  assertEquals(givenBlock([]), '');
  const throwing = { ...deps([]), embed: async () => { throw new Error('cold'); } };
  assertEquals(await givenTradeKnowledge(throwing, 'x'), []);
  let slowTimer: ReturnType<typeof setTimeout> | undefined;
  const slow = { ...deps([trade]), embed: () => new Promise<number[]>((res) => { slowTimer = setTimeout(() => res([0.1]), 500); }) };
  const t0 = Date.now();
  assertEquals(await givenTradeKnowledge(slow, 'x', 6, 50), []);
  assert(Date.now() - t0 < 400, 'the answer waited for a slow read');
  clearTimeout(slowTimer);
});
