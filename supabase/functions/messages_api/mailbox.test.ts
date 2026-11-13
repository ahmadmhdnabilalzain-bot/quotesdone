// deno test --no-lock supabase/functions/messages_api/mailbox.test.ts
//
// The supplier mailbox and its reveal gate (15 Sep 2026), against a fake client. The properties: the
// gate is closed with no revealed job and open with one; only revealed rows become threads; no
// customer identity is ever in the payload. No network, no environment, no real row.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { buildSupplierMailbox, gateOf } from './mailbox.ts';

type Row = Record<string, unknown>;
function fakeAdmin(answers: Record<string, unknown>) {
  const asked: string[] = [];
  const from = (table: string) => {
    const f: string[] = [];
    const q: Record<string, unknown> = {};
    for (const m of ['select', 'order', 'limit']) q[m] = () => q;
    q.eq = (k: string, v: unknown) => { f.push(k + '=' + v); return q; };
    q.not = (k: string, op: string, v: unknown) => { f.push(k + ' not ' + op + ' ' + v); return q; };
    const key = () => table + (f.length ? '?' + f.join('&') : '');
    q.maybeSingle = () => { asked.push(key()); return Promise.resolve(answers[key()] ?? answers[table] ?? { data: null }); };
    q.then = (ok: (v: unknown) => unknown) => { asked.push(key()); return Promise.resolve(answers[key()] ?? answers[table] ?? { data: [], count: 0 }).then(ok); };
    return q;
  };
  return { asked, from, rpc: (fn: string) => Promise.resolve({ data: fn === 'fn_reveal_window' ? { ends_at: '2026-09-22' } : '2026-09-22' }) };  // fn_reveal_window: the one window source (13 Nov 2026)
}

Deno.test('gate: closed with no revealed job, open with one', () => {
  assertEquals(gateOf(0), { open: false, reason: 'no_revealed_job', revealed_jobs: 0 });
  assertEquals(gateOf(2).open, true);
});

Deno.test('a supplier with no reveal gets a closed gate and no threads', async () => {
  const admin = fakeAdmin({});
  const m = await buildSupplierMailbox(admin, 7);
  assertEquals(m.gate.open, false);
  assertEquals(m.threads, []);
  assert(admin.asked[0].includes('supplier_id=7') && admin.asked[0].includes('revealed_at not is null'), 'reads only this supplier\'s revealed rows: ' + admin.asked[0]);
});

Deno.test('a revealed job opens the gate; one thread per job; respond_by from the stamp or the calendar; no customer identity', async () => {
  const admin = fakeAdmin({
    transactions: { data: [
      { inquiry_id: 'q1', revealed_at: '2026-09-10T08:00:00Z', refund_deadline: '2026-09-17T08:00:00Z', supplier_ack_at: null, inquiries: { category: 'hvac', emirate: 'Dubai', summary: 'Chiller' } },
      { inquiry_id: 'q1', revealed_at: '2026-09-10T08:00:00Z', refund_deadline: null, supplier_ack_at: null, inquiries: {} },
      { inquiry_id: 'q2', revealed_at: '2026-09-12T08:00:00Z', refund_deadline: null, supplier_ack_at: '2026-09-13T08:00:00Z', inquiries: { category: 'aluminium' } },
    ] },
    'messages': { data: [], count: 2 },
    'chat_threads?inquiry_id=q1&supplier_id=7': { data: { status: 'open' } },
  });
  const m = await buildSupplierMailbox(admin, 7);
  assertEquals(m.gate, { open: true, reason: 'revealed', revealed_jobs: 2 });
  assertEquals(m.threads.map((t) => t.inquiry_id).sort(), ['q1', 'q2']);
  const q1 = m.threads.find((t) => t.inquiry_id === 'q1')!;
  const q2 = m.threads.find((t) => t.inquiry_id === 'q2')!;
  assertEquals([q1.respond_by, q2.respond_by, q1.chat_status, q2.chat_status], ['2026-09-17T08:00:00Z', '2026-09-22', 'open', 'none']);
  const text = JSON.stringify(m);
  for (const k of ['email', 'phone', 'full_name', 'customer_id']) assert(!text.includes(k), 'identity field in payload: ' + k);
  assertEquals(m.threads.every((t: Row) => t.counterpart === 'customer'), true);
});
