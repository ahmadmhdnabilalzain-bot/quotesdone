// customerReplyGate (customer_support, #1462): the CEO's answer to a support handover passes the same checks as every
// customer reply before it is sent. No network: the brief comes from a stubbed rpc.
import { assert, assertEquals } from 'jsr:@std/assert';
import { customerReplyGate } from './ai_reply.ts';

const COMPANY = 'REVEAL FEE: the customer pays 3.00% of the selected quotation value. No card fee is added.';
const rpc = (fn: string) => Promise.resolve({ data: fn === 'fn_company_context' ? { block: COMPANY } : null, error: null });

Deno.test('a clean English answer passes', async () => {
  assertEquals(await customerReplyGate(rpc, 'The reveal fee is 3% of the quotation you choose, no card fee is added and no VAT is charged on it. Suppliers on the platform quote for you within the request window, and you compare them before choosing one.', 'en', false), []);
});

Deno.test('a leaked phone number and a deferral are held', async () => {
  const p = await customerReplyGate(rpc, "I'm not sure, call the supplier on 050 123 4567.", 'en', false);
  assert(p.some((x) => x.includes('contact or licence details')), p.join('; '));
  assert(p.some((x) => x.includes('defers')), p.join('; '));
});

Deno.test('a supplier is answered in English only, a customer in the inquiry language', async () => {
  assert((await customerReplyGate(rpc, 'شكرًا لسؤالكم، سنرد قريبًا', 'ar', true)).some((x) => x.includes('not in English')));
  assert((await customerReplyGate(rpc, 'Thank you, here is the answer to your question about the fee.', 'ar', false)).some((x) => x.includes('not in Arabic')));
  assertEquals(await customerReplyGate(rpc, '', 'en', false), ['the reply is empty']);
});
