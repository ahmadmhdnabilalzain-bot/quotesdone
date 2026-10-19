import { assert, assertEquals } from 'jsr:@std/assert@1';
import { accountFacts, customerFacts, supplierFacts } from './account_facts.ts';

Deno.test('customer facts carry each request, its status and quotes count', () => {
  const t = customerFacts([{ id: 7, category: 'Painting', emirate: 'Dubai', status: 'sent', quotes_count: 2, created_at: '2026-10-18T00:00:00Z' }]);
  assert(t.includes('Request #7') && t.includes('status sent') && t.includes('2 quote(s)'));
});
Deno.test('supplier facts carry only their own quote', () => {
  const t = supplierFacts('ZZ DEMO Co', [{ inquiry_id: 9, status: 'open', my_quote_status: 'submitted' }]);
  assert(t.includes('Job #9') && t.includes('their quote: submitted'));
});
Deno.test('an unknown sender, or an address on two accounts, gets no account data and no read', async () => {
  let reads = 0;
  const db = { from: () => { reads++; const q: any = { select: () => q, ilike: () => q, limit: async () => ({ data: [{ id: 1 }, { id: 2 }] }) }; return q; }, rpc: () => { throw new Error('no'); } };
  assertEquals(await accountFacts(db, 'x@example.invalid', null), '');
  assertEquals(reads, 0);
  assertEquals(await accountFacts(db, 'x@example.invalid', 'customer'), '');
});
