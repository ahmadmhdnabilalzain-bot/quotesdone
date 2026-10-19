import { assert, assertEquals } from 'jsr:@std/assert@1';
import { accountFacts, customerFacts, mailFacts, SIGN_IN_FACT, supplierFacts } from './account_facts.ts';

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

const custDb = () => { let reads = 0; const db: any = { reads: () => reads,
  from: () => { reads++; const q: any = { select: () => q, ilike: () => q, limit: async () => ({ data: [{ id: 'c1' }] }) }; return q; },
  rpc: async () => ({ data: { inquiries: [{ id: 'i1', category: 'gypsum', status: 'quoted', quotes_count: 1 }] }, error: null }) }; return db; };

Deno.test('DMARC/aligned pass: the account is given', async () => {
  const db = custDb(); const t = await mailFacts(db, 'a@example.invalid', 'customer', { sender_authenticated: true });
  assert(t.includes('Request #i1') && t.includes('status quoted'));
});
Deno.test('authentication failed: no account data, no read, sign-in invited', async () => {
  const db = custDb(); const t = await mailFacts(db, 'a@example.invalid', 'customer', { sender_authenticated: false });
  assertEquals(t, SIGN_IN_FACT); assertEquals(db.reads(), 0); assert(!t.includes('i1'));
});
Deno.test('authentication result missing: no account data, no read, sign-in invited', async () => {
  for (const raw of [null, undefined, {}, { sender_authenticated: 'true' }]) {
    const db = custDb(); assertEquals(await mailFacts(db, 'a@example.invalid', 'supplier', raw), SIGN_IN_FACT); assertEquals(db.reads(), 0);
  }
});
Deno.test('unknown sender: nothing at all', async () => {
  assertEquals(await mailFacts(custDb(), 'a@example.invalid', null, { sender_authenticated: true }), '');
});
