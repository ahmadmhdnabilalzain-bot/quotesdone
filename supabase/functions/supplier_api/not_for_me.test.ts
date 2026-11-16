// deno test --no-lock --node-modules-dir=none supabase/functions/supplier_api/not_for_me.test.ts
//
// THE PORTAL'S "NOT FOR ME" (sales_engineer, 16 Nov 2026; holes SUPPLIER 2/3/7, OPERATIONS H8, CUSTOMER 8). Before this file
// supplier_api's forty-odd actions had no decline, no "I'm available", no figure confirmation and no choice about live quotes when
// going on leave. The supplier id is the caller's; every write is a scoped routine (stubbed here as the SQL answers).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { NOT_FOR_ME_ACTIONS, notForMe } from './not_for_me.ts';

const INQ = '11111111-2222-3333-4444-555555555555', Q = '99999999-2222-3333-4444-555555555555';
function stub(answers: Record<string, unknown> = {}) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const updates: unknown[] = [];
  return {
    calls, updates,
    rpc: (fn: string, args: Record<string, unknown>) => { calls.push({ fn, args }); return Promise.resolve({ data: answers[fn] ?? { ok: true }, error: null }); },
    // deno-lint-ignore no-explicit-any
    from: (_t: string) => { const b: any = { update: (u: unknown) => { updates.push(u); return b; }, eq: (...a: unknown[]) => { updates.push(['eq', ...a]); return b; }, in: (...a: unknown[]) => { updates.push(['in', ...a]); return b; }, select: () => Promise.resolve({ data: [{ id: Q }], error: null }) }; return b; },
  };
}

Deno.test('one tap declines with an optional reason, scoped to the caller, and offers to stop the trade only when it can', async () => {
  const a = stub({ fn_supplier_declines_request: { ok: true, trade: 'plumbing', trade_label: 'Plumbing', can_remove_trade: true, strikes: 0 } });
  const [s, o] = await notForMe(a, 42, 'decline_request', { inquiry_id: INQ, reason: 'we only do tiling', supplier_id: 7 });
  assertEquals(s, 200);
  assertEquals(a.calls[0].args, { p_supplier: 42, p_inquiry: INQ, p_reason: 'we only do tiling', p_channel: 'portal' });
  assertEquals(o.offer, { trades: ['plumbing'], label: 'Plumbing' });
  const b = stub({ fn_supplier_declines_request: { ok: true, trade: 'plumbing', can_remove_trade: false } });
  assertEquals((await notForMe(b, 42, 'decline_request', { inquiry_id: INQ }))[1].offer, null);
  assertEquals(b.calls[0].args.p_reason, null, 'the reason is optional');
  assertEquals((await notForMe(stub(), 42, 'decline_request', { inquiry_id: 'x' }))[0], 400);
  assertEquals((await notForMe(stub({ fn_supplier_declines_request: { ok: false, code: 'already_quoted' } }), 42, 'decline_request', { inquiry_id: INQ }))[0], 409);
});

Deno.test('the portal tap removing a trade is his confirmation: proposed, applied through the writer, decided', async () => {
  const a = stub({ fn_supplier_trade_correction_propose: { ok: true, correction: { id: 3, remove_trades: ['plumbing'], remove_services: [], labels: ['Plumbing'] } } });
  const removed: unknown[] = [];
  const [s, o] = await notForMe(a, 42, 'remove_work', { trades: ['plumbing'], from_decline: true, inquiry_id: INQ }, { remove: ((_a: unknown, sid: number, r: unknown) => { removed.push([sid, r]); return Promise.resolve({ ok: true }); }) as never });
  assertEquals([s, o.removed], [200, ['Plumbing']]);
  assertEquals(removed, [[42, { trades: ['plumbing'], services: [] }]]);
  assertEquals(a.calls.map((c) => c.fn), ['fn_supplier_trade_correction_propose', 'fn_supplier_trade_correction_decide']);
  assertEquals([a.calls[0].args.p_source, a.calls[1].args.p_decision], ['not_for_me', 'applied']);
});

Deno.test('a suggestion from the weekly review is applied or kept only while it is the open one', async () => {
  const open = { open_correction: { id: 5, remove_trades: ['painting'], remove_services: [], labels: ['Painting'] } };
  const a = stub({ fn_supplier_live_standing: open });
  assertEquals((await notForMe(a, 42, 'correction_decide', { id: 5, decision: 'keep' }))[1], { ok: true, kept: ['Painting'] });
  assertEquals(a.calls[1].args.p_decision, 'declined');
  assertEquals((await notForMe(stub({ fn_supplier_live_standing: open }), 42, 'correction_decide', { id: 6, decision: 'apply' }))[0], 409);
});

Deno.test('"I\'m available", standing and figure confirmation go to their routines with his id', async () => {
  const a = stub();
  await notForMe(a, 42, 'say_available', {});
  await notForMe(a, 42, 'standing', {});
  await notForMe(a, 42, 'confirm_quote_figure', { quote_id: Q });
  assertEquals(a.calls.map((c) => [c.fn, c.args.p_supplier]), [['fn_supplier_says_available', 42], ['fn_supplier_live_standing', 42], ['fn_supplier_confirms_quote_figure', 42]]);
  assertEquals(a.calls[2].args.p_quote, Q);
});

Deno.test('going on leave: keep changes nothing; withdraw touches only his own live, unrevealed quotations', async () => {
  const a = stub({ fn_supplier_live_quotes: [{ quote_id: Q }] });
  assertEquals((await notForMe(a, 42, 'leave_quotes', { decision: 'keep' }))[1], { ok: true, kept: 1 });
  assertEquals(a.updates, []);
  const b = stub({ fn_supplier_live_quotes: [{ quote_id: Q }] });
  assertEquals((await notForMe(b, 42, 'leave_quotes', { decision: 'withdraw' }))[1], { ok: true, withdrawn: 1 });
  assertEquals(b.updates, [{ status: 'withdrawn' }, ['eq', 'supplier_id', 42], ['in', 'id', [Q]], ['in', 'status', ['draft', 'submitted']]]);
  assert(NOT_FOR_ME_ACTIONS.includes('leave_quotes'));
});
