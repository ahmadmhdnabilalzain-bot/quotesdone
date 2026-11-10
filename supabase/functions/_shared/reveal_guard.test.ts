// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/reveal_guard.test.ts
//
// The guard every reveal door calls (customer-portal audit CP-01 / CP-09 / CP-15). The fake admin
// answers the five reads canReveal makes, so each refusal is proved without a database.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { assessInput, canReveal, heldQuoteIds, refuse } from './reveal_guard.ts';

// A complete quote of the kind line_specs ranks (same shape as line_specs/compare.test.ts's A).
const COMPLETE = { id: 'q1', inquiry_id: 'i1', supplier_id: 7, status: 'submitted', quote_amount: 6000,
  price_ex_vat: 6000, lead_time: '21 days', warranty: '2 years on workmanship',
  scope: 'Supply and installation of wardrobes by our team',
  terms_spec: { installation: { included: 'yes', detail: 'by our team', source: 'reasoned' }, warranty: { period: '2 years', coverage: 'workmanship', source: 'reasoned' } } };
// As the gate stores it after reading (reasoned_matching.ts): the values and their source, the terms on terms_spec.
const ITEM = { quote_id: 'q1', line_no: 1, description: 'Wardrobes 18mm MR MDF, HPL finish', amount: 6000,
  spec: { material: 'MR MDF', thickness_mm: '18', finish: 'HPL' }, spec_source: { material: 'reasoned', thickness_mm: 'reasoned', finish: 'reasoned' } };

// deno-lint-ignore no-explicit-any
type Rows = Record<string, any>;
/** One read per table; `.in()` returns the list, `.maybeSingle()` the row, `.range()` one page. */
function fakeAdmin(rows: Rows) {
  const mk = (table: string) => {
    const all = () => (rows[table] ?? []);
    // deno-lint-ignore no-explicit-any
    const b: any = {
      select: () => b, eq: () => b, in: () => b, not: () => b, order: () => b,
      limit: () => ({ data: all(), error: null }),
      // itemsByQuote pages to exhaustion; a page beyond the rows must come back empty or it loops.
      range: (from: number, to: number) => Promise.resolve({ data: all().slice(from, to + 1), error: null }),
      maybeSingle: () => Promise.resolve({ data: rows[table] ?? null, error: null }),
      then: (f: (r: { data: unknown; error: null }) => unknown) => Promise.resolve(f({ data: all(), error: null })),
    };
    return b;
  };
  // The accountant's money screen: rows.money_screen is its answer ({hold}); calls are recorded so a test can
  // see that a paid reveal is never re-screened.
  const calls: unknown[] = [];
  const rpc = (fn: string, args: unknown) => { calls.push({ fn, args });
    // the trade-opening floor (ledger 1614): rows.trade_reveal is its answer ({allowed}); unset reads as allowed
    if (fn === 'fn_trade_reveal_allowed') return Promise.resolve(rows.trade_reveal_error ? { data: null, error: rows.trade_reveal_error } : { data: rows.trade_reveal ?? { allowed: true }, error: null });
    return Promise.resolve(rows.money_screen_error ? { data: null, error: rows.money_screen_error } : { data: rows.money_screen ?? { hold: false }, error: null }); };
  return { from: mk, rpc, calls };
}

Deno.test('a complete quote is not on hold; the same quote without its ex-VAT price is', () => {
  const held = heldQuoteIds([{ quote: COMPLETE, items: [ITEM] }], 'joinery', null);
  assertEquals([...held], []);
  const noPrice = heldQuoteIds([{ quote: { ...COMPLETE, price_ex_vat: null, quote_amount: null }, items: [ITEM] }], 'joinery', null);
  assertEquals([...noPrice], ['q1']);
  // THE HEADLINE TOTAL IS NOT THE EX-VAT PRICE (review of #850). Nulling both hid the gap: with a
  // `?? quote_amount` fallback a quote that states only its VAT-inclusive total read as complete
  // and became revealable. Only price_ex_vat is nulled here, and the quote must still be held.
  const headlineOnly = heldQuoteIds([{ quote: { ...COMPLETE, price_ex_vat: null, quote_amount: 6300 }, items: [ITEM] }], 'joinery', null);
  assertEquals([...headlineOnly], ['q1']);
  assertEquals(assessInput({ ...COMPLETE, price_ex_vat: null, quote_amount: 6300 }, [ITEM]).terms.price_ex_vat, null);
  // The mapping is what the three callers share: lines and terms, nothing invented.
  const inp = assessInput(COMPLETE, [ITEM]);
  assertEquals([inp.lines.length, inp.terms.price_ex_vat, inp.lines[0].line_no], [1, 6000, 1]);
});

Deno.test('canReveal allows a complete, owned, unsanctioned quote', async () => {
  const r = await canReveal(fakeAdmin({ quotes: COMPLETE, inquiries: { id: 'i1', customer_id: 'c1', status: 'sent', category: 'joinery', spec: null }, quote_items: [ITEM], transactions: null, sanctions_ban: [] }), { quoteId: 'q1', customerId: 'c1' });
  assert(r.ok, 'a complete quote on the customer\'s own live request is revealable');
  assertEquals(r.already_revealed, false);
});

Deno.test('canReveal refuses a draft, another customer\'s request, a closed request, a sanctioned supplier and a held quote', async () => {
  const base = { quotes: COMPLETE, inquiries: { id: 'i1', customer_id: 'c1', status: 'sent', category: 'joinery', spec: null }, quote_items: [ITEM], transactions: null, sanctions_ban: [] };
  const code = async (rows: Rows) => {
    const r = await canReveal(fakeAdmin(rows), { quoteId: 'q1', customerId: 'c1' });
    return r.ok ? 'allowed' : r.code + ':' + r.status;
  };
  assertEquals(await code({ ...base, quotes: { ...COMPLETE, status: 'draft' } }), 'quote_not_found:404');
  assertEquals(await code({ ...base, quotes: null }), 'quote_not_found:404');
  assertEquals(await code({ ...base, inquiries: { ...base.inquiries, customer_id: 'c2' } }), 'not_your_inquiry:403');
  assertEquals(await code({ ...base, inquiries: { ...base.inquiries, status: 'cancelled' } }), 'inquiry_closed:409');
  assertEquals(await code({ ...base, sanctions_ban: [{ lead_id: 7 }] }), 'account_sanctioned:403');
  assertEquals(await code({ ...base, quotes: { ...COMPLETE, price_ex_vat: null, quote_amount: null } }), 'quote_on_hold:409');
  assertEquals(await code({ ...base, quotes: { ...COMPLETE, price_ex_vat: null, quote_amount: 6300 } }), 'quote_on_hold:409');
  // The accountant's screen holds a reveal a high-severity fraud flag touches (no ban, no charge).
  assertEquals(await code({ ...base, money_screen: { hold: true, hold_id: 1 } }), 'under_review:409');
  // A reveal already paid for is disclosed again, and is never re-held.
  const paid = await canReveal(fakeAdmin({ ...base, quotes: { ...COMPLETE, price_ex_vat: null, quote_amount: null }, transactions: { id: 'tx1' } }), { quoteId: 'q1', customerId: 'c1' });
  assertEquals([paid.ok, paid.ok && paid.already_revealed], [true, true]);
});

Deno.test('the money screen runs before a charge, never on a paid reveal, and fails closed', async () => {
  const base = { quotes: COMPLETE, inquiries: { id: 'i1', customer_id: 'c1', status: 'sent', category: 'joinery', spec: null }, quote_items: [ITEM], transactions: null, sanctions_ban: [] };
  const a = fakeAdmin(base);
  assert((await canReveal(a, { quoteId: 'q1', customerId: 'c1' })).ok);
  // the trade floor is read first (it writes nothing), then the screen, which writes (ledger 1614)
  assertEquals(a.calls, [{ fn: 'fn_trade_reveal_allowed', args: { p_inquiry: 'i1' } }, { fn: 'fn_accountant_money_screen', args: { p_move: 'reveal', p_ref: 'q1', p_customer: 'c1', p_supplier: 7 } }]);
  const paid = fakeAdmin({ ...base, transactions: { id: 'tx1' }, money_screen: { hold: true } });
  assert((await canReveal(paid, { quoteId: 'q1', customerId: 'c1' })).ok, 'a paid reveal is disclosed again, whatever the screen says now');
  assertEquals(paid.calls, []);
  let threw = false;
  try { await canReveal(fakeAdmin({ ...base, money_screen_error: { message: 'down' } }), { quoteId: 'q1', customerId: 'c1' }); } catch (_e) { threw = true; }
  assert(threw, 'an unreadable screen must refuse (the caller answers 500), never charge');
});

Deno.test('every refusal carries a machine code and both languages', () => {
  for (const c of ['quote_not_found', 'not_your_inquiry', 'inquiry_closed', 'quote_on_hold', 'under_review', 'account_sanctioned', 'something_new']) {
    const r = refuse(c);
    assertEquals(r.code, c);
    assert(r.status >= 400 && r.status < 500, c + ' refuses with a 4xx');
    assert(r.message.length > 10 && /[؀-ۿ]/.test(r.message_ar), c + ' answers in English and Arabic');
  }
});

Deno.test('canReveal refuses a quote its supplier withdrew before the reveal: nobody pays for a price that was taken back', async () => {
  const rows = { quotes: { ...COMPLETE, status: 'withdrawn' }, inquiries: { id: 'i1', customer_id: 'c1', status: 'sent', category: 'joinery', spec: null }, quote_items: [ITEM], transactions: null, sanctions_ban: [] };
  const r = await canReveal(fakeAdmin(rows), { quoteId: 'q1', customerId: 'c1' });
  assert(!r.ok, 'a withdrawn quote is not revealable');
  assertEquals(r.ok ? '' : r.code, 'quote_not_found');
});

Deno.test('canReveal refuses a paid reveal while the request\'s trade is under the floor of 5 verified suppliers (ledger 1614)', async () => {
  const base = { quotes: COMPLETE, inquiries: { id: 'i1', customer_id: 'c1', status: 'sent', category: 'joinery', spec: null }, quote_items: [ITEM], transactions: null, sanctions_ban: [] };
  const under = await canReveal(fakeAdmin({ ...base, trade_reveal: { allowed: false, floor: 5, below_floor: [{ code: 'joinery', verified: 4 }] } }), { quoteId: 'q1', customerId: 'c1' });
  assertEquals(under.ok ? 'allowed' : under.code + ':' + under.status, 'trade_below_floor:409');
  assert(!under.ok && /ريثما/.test(under.message_ar), 'the refusal carries its Arabic');
  // an unreadable answer never lets money move
  let threw = false;
  try { await canReveal(fakeAdmin({ ...base, trade_reveal_error: { message: 'boom' } }), { quoteId: 'q1', customerId: 'c1' }); } catch (_e) { threw = true; }
  assert(threw, 'an unreadable trade answer must fail closed');
  // a reveal already paid for is never re-gated
  const paid = await canReveal(fakeAdmin({ ...base, transactions: { id: 'tx1' }, trade_reveal: { allowed: false } }), { quoteId: 'q1', customerId: 'c1' });
  assertEquals([paid.ok, paid.ok && paid.already_revealed], [true, true]);
});
