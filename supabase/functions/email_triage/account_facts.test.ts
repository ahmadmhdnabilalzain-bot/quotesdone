import { assert, assertEquals } from 'jsr:@std/assert@1';
import { accountFacts, customerFacts, mailFacts, SIGN_IN_FACT, SUPPLIER_SIGN_IN_FACT, supplierFacts } from './account_facts.ts';

Deno.test('customer facts carry each request by its number, what he asked, each quote as his portal shows it, and the rule', async () => {
  const { OWN_REQUEST_RULE } = await import('../_shared/own_request_facts.ts');
  const t = customerFacts([{ ref: 1043, category: 'Painting', emirate: 'Dubai', status: 'quoted', quotes_received: 2,
    asked: { budget_as_he_stated_it: 'around 3k' }, quotes: [{ letter: 'A', price_ex_vat_aed: 3400, revealed: false, warranty_as_stated: '1 year Grohe' }] }]);
  assert(t.includes('"ref":1043') && t.includes('"status":"quoted"') && t.includes('around 3k') && t.includes('3400') && t.includes(OWN_REQUEST_RULE));
  assert(!t.includes('Grohe'), 'a sealed quote named its brand');
  assert(customerFacts([]).includes('no requests yet'));
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
  rpc: async (fn: string) => ({ data: fn === 'fn_customer_inquiry_facts' ? [{ ref: 'i1', category: 'gypsum', status: 'quoted', quotes_received: 1 }] : null, error: null }) }; return db; };

Deno.test('DMARC/aligned pass: the account is given', async () => {
  const db = custDb(); const t = await mailFacts(db, 'a@example.invalid', 'customer', { sender_authenticated: true });
  assert(t.includes('"ref":"i1"') && t.includes('"status":"quoted"'));
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
  assertEquals(db.matchReads(), 0);   // no jobs are read for a company that has no account
});

// PREVENTED BY (28 Oct 2026, it_engineer audit of the supplier journey, ledger 1401): eight real-path replies each
// promised "reply with the trades … our team will set up the page for you" (nothing does it: the invite.reply handler
// only waits) and listed the steps without the company profile and the supplier terms (two of the six).
const SIX = [/licensed name/i, /UAE mobile/i, /e-mail/i, /trade licence/i, /company profile/i, /supplier terms/i];
const OFFER = /our team (will|can) set up|set up (the|your|their) (company )?page for (them|you)|reply with the trades/i;
Deno.test('an invited supplier is told all six items and is never offered a set-up nobody performs', async () => {
  const facts = [
    await mailFacts(leadDb({ id: 5, company_name: 'ZZ DEMO Glass LLC', claimed: false, claim_token: TOKEN }), 'sales@example.invalid', 'supplier', { sender_authenticated: true }),
    SUPPLIER_SIGN_IN_FACT,
  ];
  for (const t of facts) {
    for (const re of SIX) assert(re.test(t), `missing ${re}: ${t}`);
    assert(/never offer to register them/i.test(t), t);
    assert(/add supplier@quotesdone.com to their contacts/i.test(t), `the first reply must ask for the contact: ${t}`);
    // the facts may FORBID the offer, never make it: take the forbidding sentence out before looking for the offer
    assert(!OFFER.test(t.replace(/Never offer to register them[^.]*\.[^.]*\./i, '')), t);
  }
});
Deno.test('known-bad control: the facts of #1699 are caught', () => {
  const before = 'then confirm the company details and the trades they cover, upload the trade licence and verify their mobile. '
    + 'If they would rather not do it themselves, they can reply with the trades they cover and our team will set up the page for them.';
  assert(OFFER.test(before));
  assert(!/company profile/i.test(before) && !/supplier terms/i.test(before));
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
