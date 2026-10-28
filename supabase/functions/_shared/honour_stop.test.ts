// A believed stop cancels what is already waiting and marks the lead (28 Oct 2026, supplier-journey audit run 490a318b:
// "Please remove me / stop" left the address sendable; a nudge queued before a stop would still have gone, because
// supplier_invite_nudge is not an OPT_OUT_TYPES type). The client is a stub that records every filter; no network.
import { assertEquals } from 'jsr:@std/assert@1';
import { honourStop, OPT_OUT_TYPES, STOP_CANCELS } from './suppression_policy.ts';

type Call = { table: string; values: Record<string, unknown>; filters: [string, unknown, unknown?][] };
function stubDb(rows: Record<string, number> = { notifications: 2, leads: 1 }) {
  const calls: Call[] = [];
  const builder = (table: string, values: Record<string, unknown>) => {
    const c: Call = { table, values, filters: [] }; calls.push(c);
    const b: Record<string, unknown> = {};
    for (const op of ['ilike', 'in', 'or', 'eq']) b[op] = (...a: unknown[]) => { c.filters.push([op, a[0], a[1]]); return b; };
    b.select = () => Promise.resolve({ data: Array.from({ length: rows[table] ?? 0 }, (_, i) => ({ id: i + 1 })), error: null });
    return b;
  };
  return { calls, db: { from: (table: string) => ({ update: (values: Record<string, unknown>) => builder(table, values) }) } };
}

Deno.test('a stop cancels every waiting invitation, nudge and reminder to the address, and marks the lead', async () => {
  const { calls, db } = stubDb();
  const r = await honourStop(db, 'Delivered+qd-zzdemo_1-sup0@resend.dev');
  assertEquals(r, { cancelled: 2, leads: 2, error: null });   // leads counted on both the email and the claimed_by update
  const n = calls.find((c) => c.table === 'notifications')!;
  assertEquals(n.values.status, 'suppressed');
  assertEquals(n.filters.find((f) => f[0] === 'ilike'), ['ilike', 'to_email', 'delivered+qd-zzdemo\\_1-sup0@resend.dev']);   // exact, case-folded, _ escaped
  assertEquals(n.filters.find((f) => f[0] === 'in' && f[1] === 'type')![2], [...STOP_CANCELS]);
  assertEquals(n.filters.find((f) => f[0] === 'in' && f[1] === 'status')![2], ['queued', 'pending', 'held', 'digest']);
  const l = calls.filter((c) => c.table === 'leads');
  assertEquals(l.map((c) => c.filters[0][1]), ['email', 'claimed_by']);
  assertEquals(l.every((c) => c.values.invite_status === 'unsubscribed'), true);
});

Deno.test('the nudge is cancelled although it is not an OPT_OUT_TYPES type (send_outbox would send it)', () => {
  assertEquals(OPT_OUT_TYPES.includes('supplier_invite_nudge'), false);
  assertEquals(STOP_CANCELS.includes('supplier_invite_nudge'), true);
  for (const t of OPT_OUT_TYPES) assertEquals(STOP_CANCELS.includes(t), true, t);
});

Deno.test('no address, nothing touched', async () => {
  const { calls, db } = stubDb();
  assertEquals((await honourStop(db, '')).error, 'no address');
  assertEquals(calls.length, 0);
});
