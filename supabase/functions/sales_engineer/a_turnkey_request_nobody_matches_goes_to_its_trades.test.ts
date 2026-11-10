// A TURNKEY REQUEST NOBODY MATCHES GOES TO ITS TRADES' SPECIALISTS, AND SAYS SO (sales_engineer; evidence run of
// 10 Nov 2026, ledger 1604, finding c). The fake RPC answers exactly as the write-up's read-only probe measured on
// production: [interior_fitout, joinery] with the four PVC services -> the wallpaper supplier at 'executes', nobody at
// 'whole_scope'. Pure: no database, no network, no person.
// deno test --no-lock --node-modules-dir=none supabase/functions/sales_engineer/a_turnkey_request_nobody_matches_goes_to_its_trades.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { matchWithNeedFallback, type Rpc } from './lib/need_fallback.ts';

const WALLPAPER = { supplier_id: 900201, company_name: 'ZZ DEMO Wall Panels', score: 15, why: 'reached through wallpaper (the named service\'s trade) · 2/4 services · in Dubai' };
const ARGS = { p_trades: ['interior_fitout', 'joinery'], p_services: ['wallpaper.wall_cladding', 'wallpaper.wall_panels', 'interior_fitout.refurbishment', 'joinery.wood_panelling'], p_emirate: 'Dubai' };
const probe = (perNeed: Record<string, unknown[]>, calls: string[] = []): Rpc => (args) => { calls.push(String(args.p_need)); return Promise.resolve({ data: perNeed[String(args.p_need)] ?? [], error: null }); };

Deno.test('RFQ 164464: turnkey found nobody, so the request goes per trade to the wallpaper supplier, and says so', async () => {
  const calls: string[] = [];
  const m = await matchWithNeedFallback(probe({ whole_scope: [], executes: [WALLPAPER] }, calls), { ...ARGS, p_need: 'whole_scope' });
  assertEquals(calls, ['whole_scope', 'executes'], 'every other criterion unchanged; only the need is asked again');
  assertEquals(m.rows.map((r) => r.supplier_id), [900201]);
  assertEquals([m.need, m.fallback?.from, m.fallback?.to, m.fallback?.reason], ['executes', 'whole_scope', 'executes', 'no_turnkey_contractor_matched']);
});

Deno.test('a turnkey contractor that matches is kept; a per-trade request is never re-asked; an honest zero stays zero', async () => {
  const TK = { supplier_id: 900202, company_name: 'ZZ DEMO Turnkey', score: 40 };
  const a = await matchWithNeedFallback(probe({ whole_scope: [TK], executes: [WALLPAPER] }), { ...ARGS, p_need: 'whole_scope' });
  assertEquals([a.rows.map((r) => r.supplier_id), a.fallback], [[900202], null]);
  const calls: string[] = [];
  const b = await matchWithNeedFallback(probe({ executes: [] }, calls), { ...ARGS, p_need: 'executes' });
  assertEquals([calls, b.rows.length, b.fallback], [['executes'], 0, null]);
  const c = await matchWithNeedFallback(probe({ whole_scope: [], executes: [] }), { ...ARGS, p_need: 'whole_scope' });
  assertEquals([c.rows.length, c.need, c.fallback], [0, 'whole_scope', null], 'nobody per trade either: a coverage gap, flagged as one');
});

Deno.test('a matcher error is returned, never read as an empty market', async () => {
  const rpc: Rpc = () => Promise.resolve({ data: null, error: { message: 'statement timeout' } });
  const m = await matchWithNeedFallback(rpc, { ...ARGS, p_need: 'whole_scope' });
  assertEquals([m.error?.message, m.rows.length, m.fallback], ['statement timeout', 0, null]);
});
