import { assert, assertEquals } from 'jsr:@std/assert@1';
import { accountFacts, customerFacts, mailFacts, SIGN_IN_FACT, SUPPLIER_SIGN_IN_FACT, supplierFacts } from './account_facts.ts';

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
    const db = custDb(); assertEquals(await mailFacts(db, 'a@example.invalid', 'customer', raw), SIGN_IN_FACT); assertEquals(db.reads(), 0);
    const db2 = custDb(); assertEquals(await mailFacts(db2, 'a@example.invalid', 'supplier', raw), SUPPLIER_SIGN_IN_FACT); assertEquals(db2.reads(), 0);
  }
});
Deno.test('unknown sender: nothing at all', async () => {
  assertEquals(await mailFacts(custDb(), 'a@example.invalid', null, { sender_authenticated: true }), '');
});

// PREVENTED BY (28 Oct 2026, sales_engineer, ledger 1375): an invited supplier's "yes" to the variant A invitation was
// answered from facts calling it "A REGISTERED SUPPLIER" with "No jobs ... yet" and no way in. Replays that lead.
const TOKEN = '6f1c2a9e-3b4d-4e5f-8a7b-9c0d1e2f3a4b';
const leadDb = (lead: Record<string, unknown>) => { let matchReads = 0; const db: any = { matchReads: () => matchReads,
  from: (t: string) => { if (t === 'inquiry_matches') matchReads++;
    const q: any = { select: () => q, ilike: () => q, eq: () => q, in: () => q, order: () => q,
      limit: async () => (t === 'leads' ? { data: [lead] } : { data: [] }) }; return q; } }; return db; };

Deno.test('an invited supplier that has not registered is never told it is registered, and gets its own registration link', async () => {
  const db = leadDb({ id: 5, company_name: 'ZZ DEMO Glass LLC', claimed: false, claim_token: TOKEN });
  const t = await mailFacts(db, 'sales@example.invalid', 'supplier', { sender_authenticated: true });
  assert(!/REGISTERED SUPPLIER/.test(t), t);
  assert(t.includes('HAVE NOT REGISTERED YET'));
  assert(t.includes('https://quotesdone.com/portal?t=' + TOKEN));
  assert(t.includes('ZZ DEMO Glass LLC'));
  assert(/reply with the trades/.test(t));
  assertEquals(db.matchReads(), 0);   // no jobs are read for a company that has no account
});
Deno.test('an unregistered lead with no claim token still gets the portal, never a broken link', async () => {
  const t = await mailFacts(leadDb({ id: 6, company_name: 'X', claimed: false, claim_token: null }), 'a@example.invalid', 'supplier', { sender_authenticated: true });
  assert(t.includes('https://quotesdone.com/portal ') && !t.includes('?t='));
});
Deno.test('a supplier that claimed its listing is still answered as registered', async () => {
  const t = await mailFacts(leadDb({ id: 7, company_name: 'ZZ DEMO Steel', claimed: true, claim_token: TOKEN }), 'a@example.invalid', 'supplier', { sender_authenticated: true });
  assert(t.startsWith('THE SENDER IS A REGISTERED SUPPLIER') && !t.includes(TOKEN));
});
Deno.test('an unverified lead is told both routes and gets no personal link', () => {
  assert(SUPPLIER_SIGN_IN_FACT.includes('quotesdone.com/portal') && /Create account/.test(SUPPLIER_SIGN_IN_FACT) && !SUPPLIER_SIGN_IN_FACT.includes('?t='));
});
