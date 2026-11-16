import { assert, assertEquals } from 'jsr:@std/assert@1';
import { accountFacts, customerFacts, mailFacts, SIGN_IN_FACT, SUPPLIER_SIGN_IN_FACT, supplierFacts, timelineReplyFacts } from './account_facts.ts';

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

// PREVENTED BY (16 Nov 2026, customer_support; founder ledgers 1711-1713, who-knows-what audit item 6): a registered supplier
// writing "why is my account not approved?" or "why do I get no jobs?" was answered from leads and inquiry_matches read here,
// blind to his approval, licence, holds, trades and emirates, while WhatsApp read them. The reply now reads fn_wa_context.
const HELD_READING = {
  scope: 'supplier', known: true, company: 'ZZ DEMO Held Steel Rival',
  profile: { approval_status: 'approved', verified: true, trade_licence_no: 'ZZ-DEMO-1002', licence_expiry: '2026-11-06', licence_expired: true, licence_days_left: -10 },
  services: { confirmed: true, trades: [{ code: 'hvac', label: 'HVAC', open_to_customers: true }], trades_excluded: [], services: [], emirates_covered: ['dubai', 'sharjah'] },
  matching: { receives_requests_now: false, jobs_sent_30d: 1, requests_in_his_trades_30d: 2, collaboration: { unanswered_in_a_row: 3, on_hold: true, held_at: '2026-11-14T10:00:00Z' },
    why_no_jobs: [{ code: 'licence_expired', says: 'His trade licence expired on 06 Nov 2026. He should upload the renewed licence in the Documents tab.' }] },
  recent_jobs: [{ job: 1043, trade: 'hvac', emirate: 'Dubai', sent_at: '2026-11-15T08:00:00Z', job_status: 'sent', my_quote: 'submitted' }],
};
const readingDb = (lead: Record<string, unknown>, reading: unknown) => { const tables: string[] = []; const rpcs: { fn: string; args: unknown }[] = [];
  const db: any = { tables, rpcs,
    from: (t: string) => { tables.push(t); const q: any = { select: () => q, ilike: () => q, eq: () => q, in: () => q, order: () => q,
      limit: async () => (t === 'leads' ? { data: [lead] } : { data: [] }) }; return q; },
    rpc: async (fn: string, args: unknown) => { rpcs.push({ fn, args }); return { data: reading, error: null }; } }; return db; };

Deno.test('a registered supplier is answered from the one reading: licence, approval, holds, trades, emirates, jobs and why not more', async () => {
  const db = readingDb({ id: 7, company_name: 'ZZ DEMO Held Steel Rival', claimed: true }, HELD_READING);
  const t = await mailFacts(db, 'zz-demo-supknown-b@example.invalid', 'supplier', { sender_authenticated: true });
  for (const s of ['THE SENDER IS A REGISTERED SUPPLIER', 'Job #1043', 'their quote: submitted', 'EXPIRED 10 day(s) ago', 'Documents tab', 'HVAC (open to customers)',
    'dubai, sharjah', '1 sent to him in the last 30 days', 'Receives requests now: NO', 'on hold since 2026-11-14']) assert(t.includes(s), `missing "${s}":\n${t}`);
  assertEquals(db.rpcs, [{ fn: 'fn_wa_context', args: { p_audience: 'supplier', p_phone: 'zz-demo-supknown-b@example.invalid' } }]);
  assertEquals(db.tables.filter((x: string) => x !== 'leads'), [], 'the e-mail reply no longer reads jobs or quotes itself');
});
Deno.test('a registered supplier whose reading fails is told nothing about his jobs or status, never "no jobs yet"', async () => {
  const db = readingDb({ id: 7, company_name: 'ZZ DEMO Steel', claimed: true }, null);
  const t = await mailFacts(db, 'a@example.invalid', 'supplier', { sender_authenticated: true });
  assert(t.startsWith('THE SENDER IS A REGISTERED SUPPLIER') && t.includes('could not be read') && !/No jobs have been sent/.test(t), t);
});

// who-knows-what gap 4 (16 Nov 2026): the timeline the classifier reads reaches the reply, under the account's spoof rule
Deno.test('the case timeline reaches the reply only for an authenticated known sender', async () => {
  const tl = '\n\nSENDER CASE TIMELINE (newest first): [{"channel":"whatsapp","summary":"refund REF-1 with the CEO"}]';
  assert(timelineReplyFacts(tl, 'customer', { sender_authenticated: true }).includes('REF-1'));
  assertEquals(timelineReplyFacts(tl, 'customer', { sender_authenticated: false }), '');
  assertEquals(timelineReplyFacts(tl, null, { sender_authenticated: true }), '');
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  assert(/timelineReplyFacts\(tlText, relation/.test(src), 'index.ts does not pass the timeline it read into the reply facts');
});

// wave C release (16 Nov 2026): his money cases (fn_customer_money_cases) ride beside his requests, as on WhatsApp and the widget
Deno.test('a customer\'s open refund and dispute reach the e-mail facts; none, or a failed read, adds nothing', async () => {
  const { customerFacts, moneyCasesFact, accountFacts } = await import('./account_facts.ts');
  const money = { refunds: [{ ref: 'QD-RF-7', status: 'pending', rfq_no: 1042 }], disputes: [], being_read: [], revealed_jobs: [] };
  const t = customerFacts([{ ref: 1042, status: 'revealed' }], money);
  assert(t.includes('HIS MONEY CASES') && t.includes('QD-RF-7') && !t.includes('"disputes"'), t);
  assertEquals(moneyCasesFact({ refunds: [], disputes: [], being_read: [], revealed_jobs: [] }), '');
  assertEquals(moneyCasesFact(null), '');
  const db: any = { from: () => { const q: any = { select: () => q, ilike: () => q, limit: async () => ({ data: [{ id: 'c1' }] }) }; return q; },
    rpc: async (fn: string) => fn === 'fn_customer_money_cases' ? { data: null, error: { message: 'missing' } } : { data: [{ ref: 7, status: 'sent' }], error: null } };
  const f = await accountFacts(db, 'a@example.invalid', 'customer');
  assert(f.includes('THE SENDER IS A REGISTERED CUSTOMER') && !f.includes('MONEY CASES'), f);
});
