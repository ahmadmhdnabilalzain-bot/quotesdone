// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/reveal_standing.test.ts
//
// THE REVEAL DOOR READS THE SUPPLIER'S LIVE STANDING (sales_engineer, 16 Nov 2026; SUPPLIER hole 3, CUSTOMER hole 8).
// canReveal asks fn_reveal_standing (a_supplier_can_say_not_for_me_and_is_never_stopped_without_being_told.sql) before any
// charge: a supplier away is "back on <date>", one whose account or licence is not in order is not revealable, and a total far
// from its peers that he has not confirmed waits for him. Each answer is in both languages, and the customer is never charged.
// Before this file canReveal checked none of these (_shared/reveal_guard.ts:157-200 on origin/main).
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { canReveal, refuseAway } from './reveal_guard.ts';

const COMPLETE = { id: 'q1', inquiry_id: 'i1', supplier_id: 7, status: 'submitted', quote_amount: 6000,
  price_ex_vat: 6000, lead_time: '21 days', warranty: '2 years on workmanship',
  scope: 'Supply and installation of wardrobes by our team',
  terms_spec: { installation: { included: 'yes', detail: 'by our team', source: 'reasoned' }, warranty: { period: '2 years', coverage: 'workmanship', source: 'reasoned' } } };
const ITEM = { quote_id: 'q1', line_no: 1, description: 'Wardrobes 18mm MR MDF, HPL finish', amount: 6000,
  spec: { material: 'MR MDF', thickness_mm: '18', finish: 'HPL' }, spec_source: { material: 'reasoned', thickness_mm: 'reasoned', finish: 'reasoned' } };

// deno-lint-ignore no-explicit-any
function fakeAdmin(rows: Record<string, any>, standing: unknown, standingError: unknown = null) {
  const mk = (table: string) => {
    const all = () => (rows[table] ?? []);
    // deno-lint-ignore no-explicit-any
    const b: any = {
      select: () => b, eq: () => b, in: () => b, not: () => b, order: () => b,
      limit: () => ({ data: all(), error: null }),
      range: (from: number, to: number) => Promise.resolve({ data: all().slice(from, to + 1), error: null }),
      maybeSingle: () => Promise.resolve({ data: rows[table] ?? null, error: null }),
      then: (f: (r: { data: unknown; error: null }) => unknown) => Promise.resolve(f({ data: all(), error: null })),
    };
    return b;
  };
  const calls: string[] = [];
  const rpc = (fn: string) => {
    calls.push(fn);
    if (fn === 'fn_reveal_standing') return Promise.resolve(standingError ? { data: null, error: standingError } : { data: standing, error: null });
    if (fn === 'fn_trade_reveal_allowed') return Promise.resolve({ data: { allowed: true }, error: null });
    return Promise.resolve({ data: { hold: false }, error: null });
  };
  return { from: mk, rpc, calls };
}
const base = { quotes: COMPLETE, inquiries: { id: 'i1', customer_id: 'c1', status: 'sent', category: 'joinery', spec: null }, quote_items: [ITEM], transactions: null, sanctions_ban: [] };

Deno.test('a supplier away is "back on <date>" in both languages, before any charge and before the money screen', async () => {
  const a = fakeAdmin(base, { outcome: 'away', why: 'busy', back_on: '2026-12-05' });
  const r = await canReveal(a, { quoteId: 'q1', customerId: 'c1' });
  assert(!r.ok);
  assertEquals([r.code, r.status], ['supplier_away', 409]);
  assertMatch(r.message, /back on 5 Dec 2026/);
  assertMatch(r.message, /not been charged/);
  assertMatch(r.message_ar, /2026/);
  assertMatch(r.message_ar, /لم يُخصم/);
  assert(!a.calls.includes('fn_accountant_money_screen'), 'nothing that writes runs for a refused reveal');
});

Deno.test('paused with no date says paused, never a made-up date', () => {
  const r = refuseAway(null);
  assertMatch(r.message, /paused/);
  assert(!/back on/.test(r.message));
});

Deno.test('licence lapsed, not approved or closed: not revealable; an unconfirmed far total waits for the supplier', async () => {
  const code = async (standing: unknown) => { const r = await canReveal(fakeAdmin(base, standing), { quoteId: 'q1', customerId: 'c1' }); return r.ok ? 'allowed' : r.code; };
  assertEquals(await code({ outcome: 'not_revealable', why: 'licence_expired' }), 'supplier_not_revealable');
  assertEquals(await code({ outcome: 'figure_unconfirmed', why: 'price_far_from_peers' }), 'figure_unconfirmed');
  assertEquals(await code({ outcome: 'proceed' }), 'allowed');
});

Deno.test('an unreadable standing refuses (the caller answers 500), never charges; a paid reveal is not asked again', async () => {
  let threw = false;
  try { await canReveal(fakeAdmin(base, null, { message: 'down' }), { quoteId: 'q1', customerId: 'c1' }); } catch (_e) { threw = true; }
  assert(threw);
  const paid = fakeAdmin({ ...base, transactions: { id: 'tx1' } }, { outcome: 'away', back_on: '2026-12-05' });
  assert((await canReveal(paid, { quoteId: 'q1', customerId: 'c1' })).ok, 'what the customer already paid for is shown again');
  assertEquals(paid.calls, []);
});
