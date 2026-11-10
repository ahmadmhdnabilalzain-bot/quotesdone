// A TURNKEY MISS ASKS THE CUSTOMER AND NEVER SPLITS ON ITS OWN (sales_engineer; evidence run of 10 Nov 2026, ledger 1604,
// finding c; standing rulings 1021 and 1025). The fake RPC answers as the write-up's read-only probe measured on production:
// [interior_fitout, joinery] with the four PVC services -> the wallpaper supplier at 'executes', nobody at 'whole_scope'.
// FAILS IF a whole_scope miss invites anyone per trade without the customer's recorded 'multi': the rows the matcher returns
// (the only rows customer_api writes and notifies) must stay the whole_scope answer, and only repeat_inquiry with the
// customer's sourcing 'multi' turns the request into separate quotes. Pure: no database, no network, no person.
// deno test --no-lock --node-modules-dir=none supabase/functions/sales_engineer/a_turnkey_miss_asks_the_customer_and_never_splits_on_its_own.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { matchTurnkeyOrAsk, type Rpc } from './lib/turnkey_miss.ts';
import { repeatPlan, type Original } from '../customer_api/repeat.ts';

const WALLPAPER = { supplier_id: 900201, company_name: 'ZZ DEMO Wall Panels', score: 15 };
// The caller's call with its own need, `over` replacing it (operator.ts writes the real one).
const probe = (perNeed: Record<string, unknown[]>, calls: string[] = [], own = 'whole_scope'): Rpc => (over) => { const n = over.p_need ?? own; calls.push(n); return Promise.resolve({ data: perNeed[n] ?? [], error: null }); };

Deno.test('RFQ 164464: a whole_scope miss invites nobody per trade; it counts the specialists and asks the customer', async () => {
  const calls: string[] = [];
  const m = await matchTurnkeyOrAsk(probe({ whole_scope: [], executes: [WALLPAPER] }, calls), 'whole_scope');
  assertEquals(calls, ['whole_scope', 'executes'], 'counted per trade; only the need is replaced, every other criterion is the caller\'s own');
  assertEquals(m.rows, [], 'a per-trade supplier was returned to be invited without the customer\'s recorded multi (rulings 1021, 1025)');
  assertEquals(m.separate_offer, { ask: 'separate_quotes_per_trade', specialists: 1 });
});

Deno.test('a turnkey contractor that matches is invited; a per-trade request is never re-asked; nobody either way asks nothing', async () => {
  const TK = { supplier_id: 900202, company_name: 'ZZ DEMO Turnkey', score: 40 };
  const a = await matchTurnkeyOrAsk(probe({ whole_scope: [TK], executes: [WALLPAPER] }), 'whole_scope');
  assertEquals([a.rows.map((r) => r.supplier_id), a.separate_offer], [[900202], null]);
  const calls: string[] = [];
  const b = await matchTurnkeyOrAsk(probe({ executes: [] }, calls, 'executes'), 'executes');
  assertEquals([calls, b.rows.length, b.separate_offer], [['executes'], 0, null]);
  const c = await matchTurnkeyOrAsk(probe({ whole_scope: [], executes: [] }), 'whole_scope');
  assertEquals([c.rows.length, c.separate_offer], [0, null], 'nobody per trade either: a coverage gap, and no question with no answer behind it');
  const e = await matchTurnkeyOrAsk(() => Promise.resolve({ data: null, error: { message: 'statement timeout' } }), 'whole_scope');
  assertEquals([e.error?.message, e.rows.length, e.separate_offer], ['statement timeout', 0, null]);
});

Deno.test('only the customer\'s recorded multi re-posts a turnkey request per trade (repeat_inquiry -> create_inquiry)', () => {
  const o: Original = { id: 'inq-zz-tk', category: 'fitout', emirate: 'Dubai', raw_input: 'ZZ DEMO PVC panels', summary: 'ZZ DEMO PVC panels', budget: null,
    scope_type: 'turnkey', trades: ['interior-design', 'carpentry-joinery'], floor: null, project_id: null, lang: 'en', created_at: '2026-11-10T10:00:00Z', spec: {} };
  const now = new Date('2026-11-10T12:00:00Z');
  assertEquals(repeatPlan(o, now).body.scope_type, 'turnkey', 'without the customer\'s answer it stays one contractor');
  assertEquals(repeatPlan(o, now, { sourcing: 'separate' }).body.scope_type, 'turnkey', 'only the exact recorded answer counts');
  assertEquals(repeatPlan(o, now, { sourcing: 'multi' }).body.scope_type, 'multi');
  assertEquals(repeatPlan({ ...o, trades: ['wallpaper'] }, now, { sourcing: 'multi' }).body.scope_type, 'turnkey', 'one trade has nothing to split');
  assertEquals(repeatPlan({ ...o, scope_type: 'single' }, now, { sourcing: 'multi' }).body.scope_type, 'single', 'only a turnkey request is offered the choice');
});
