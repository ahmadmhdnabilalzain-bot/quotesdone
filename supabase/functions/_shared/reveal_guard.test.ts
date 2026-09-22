// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/reveal_guard.test.ts
//
// The guard every reveal door calls (customer-portal audit CP-01 / CP-09 / CP-15). The fake admin
// answers the five reads canReveal makes, so each refusal is proved without a database.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { assessInput, canReveal, heldQuoteIds, refuse } from './reveal_guard.ts';

// A complete quote of the kind line_specs ranks (same shape as line_specs/compare.test.ts's A).
const COMPLETE = { id: 'q1', inquiry_id: 'i1', supplier_id: 7, status: 'submitted', quote_amount: 6000,
  price_ex_vat: 6000, lead_time: '21 days', warranty: '2 years on workmanship',
  scope: 'Supply and installation of wardrobes by our team' };
const ITEM = { quote_id: 'q1', line_no: 1, description: 'Wardrobes 18mm MR MDF, HPL finish', amount: 6000 };

// deno-lint-ignore no-explicit-any
type Rows = Record<string, any>;
/** One read per table; `.in()` returns the list, `.maybeSingle()` the row. */
function fakeAdmin(rows: Rows) {
  const mk = (table: string) => {
    // deno-lint-ignore no-explicit-any
    const b: any = {
      select: () => b, eq: () => b, in: () => b, order: () => b, limit: () => (table === 'sanctions_ban' ? { data: rows.sanctions_ban ?? [], error: null } : { data: rows[table] ?? [], error: null }),
      maybeSingle: () => Promise.resolve({ data: rows[table] ?? null, error: null }),
      then: (f: (r: { data: unknown; error: null }) => unknown) => Promise.resolve(f({ data: rows[table] ?? [], error: null })),
    };
    return b;
  };
  return { from: mk };
}

Deno.test('a complete quote is not on hold; the same quote without its ex-VAT price is', () => {
  const held = heldQuoteIds([{ quote: COMPLETE, items: [ITEM] }], 'joinery', null);
  assertEquals([...held], []);
  const noPrice = heldQuoteIds([{ quote: { ...COMPLETE, price_ex_vat: null, quote_amount: null }, items: [ITEM] }], 'joinery', null);
  assertEquals([...noPrice], ['q1']);
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
  // A reveal already paid for is disclosed again, and is never re-held.
  const paid = await canReveal(fakeAdmin({ ...base, quotes: { ...COMPLETE, price_ex_vat: null, quote_amount: null }, transactions: { id: 'tx1' } }), { quoteId: 'q1', customerId: 'c1' });
  assertEquals([paid.ok, paid.ok && paid.already_revealed], [true, true]);
});

Deno.test('every refusal carries a machine code and both languages', () => {
  for (const c of ['quote_not_found', 'not_your_inquiry', 'inquiry_closed', 'quote_on_hold', 'account_sanctioned', 'something_new']) {
    const r = refuse(c);
    assertEquals(r.code, c);
    assert(r.status >= 400 && r.status < 500, c + ' refuses with a 4xx');
    assert(r.message.length > 10 && /[؀-ۿ]/.test(r.message_ar), c + ' answers in English and Arabic');
  }
});
