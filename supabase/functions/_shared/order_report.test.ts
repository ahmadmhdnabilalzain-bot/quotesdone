// reportOrClose: a CEO order is reported with what was done (third review, item 3); any other hand-over closes as before.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { orderReportText, reportOrClose, type Rpc } from './order_report.ts';

function rpcOf(data: unknown, error: { message?: string } | null = null) {
  const calls: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const rpc: Rpc = (fn, args) => { calls.push({ fn, args }); return Promise.resolve({ data, error }); };
  return { rpc, calls };
}
const order = { id: 71, agent: 'sales_engineer', detail: { type: 'ceo.order', path: 'it_finding' } };
const other = { id: 72, agent: 'sales_engineer', detail: { type: 'knowledge.request' } };

Deno.test('a CEO order is reported through fn_seat_reports_done with the seat and the sentence', async () => {
  const m = rpcOf({ ok: true, handoff_id: 71, propagated: { reported: 1 } });
  const r = await reportOrClose(m.rpc, 'sales_engineer', order, { id: 71, report: 'Re-ran the catalogue sync; it completes now.' });
  assertEquals(r.status, 200);
  assertEquals(m.calls, [{ fn: 'fn_seat_reports_done', args: { p_handoff_id: 71, p_seat: 'sales_engineer', p_report: 'Re-ran the catalogue sync; it completes now.' } }]);
  assertEquals((r.body as Record<string, unknown>).reported, true);
});

Deno.test('an order with no sentence is refused before any call; the evidence reply counts as one', async () => {
  const m = rpcOf({ ok: true });
  assertEquals((await reportOrClose(m.rpc, 'accountant', order, { id: 71, evidence: { outcome: 'done' } })).status, 400);
  assertEquals(m.calls.length, 0);
  assertEquals(orderReportText({ evidence: { reply: '  Booked the probe receipt and reconciled it.  ' } }), 'Booked the probe receipt and reconciled it.');
});

Deno.test('the routine\'s own refusal is a 400 carrying it', async () => {
  const r = await reportOrClose(rpcOf({ ok: false, reason: 'no open hand-over #71 for marketing' }).rpc, 'marketing', order, { report: 'Sent the batch to the gap trades.' });
  assertEquals(r.status, 400);
  assert(JSON.stringify(r.body).includes('no open hand-over'));
});

Deno.test('any other hand-over closes as before, with the caller\'s evidence', async () => {
  const m = rpcOf({ ok: true, handoff_id: 72, type: 'knowledge.request' });
  const r = await reportOrClose(m.rpc, 'sales_engineer', other, { id: 72, evidence: { reply: 'written' } });
  assertEquals(r.status, 200);
  assertEquals(m.calls, [{ fn: 'fn_seat_handoff_complete', args: { p_id: 72, p_evidence: { reply: 'written' } } }]);
});
