// deno test --no-lock --node-modules-dir=auto supabase/functions/supplier_portal/overview.test.ts
//
// The combined supplier overview (15 Sep 2026). A fake client answers every read after a fixed delay
// and records what was asked, so the tests measure the two things the change is for: how many reads
// the dashboard makes, and how many of them wait on another (the wall time over the delay). No
// network, no environment, no real row — nothing here can reach a person.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { buildAlerts, buildDashboard, buildEligibility, type Supplier } from './overview.ts';

const DELAY = 40;
type Answer = { data?: unknown; count?: number | null; error?: unknown };

// `rejects`: table names whose single-row read throws, the way a dropped connection does.
function fakeAdmin(answers: Record<string, Answer> = {}, rejects: string[] = []) {
  const reads: string[] = [];
  // An answer keyed by the exact read wins; one keyed by the table or routine name is the fallback.
  const settle = (key: string): Promise<Answer> => new Promise((res) => setTimeout(() => res(answers[key] ?? answers[key.split('?')[0]] ?? { data: null, count: 0 }), DELAY));
  const table = (name: string) => {
    const filters: string[] = [];
    const q: Record<string, unknown> = {};
    for (const m of ['select', 'eq', 'in', 'neq', 'not', 'is', 'order', 'limit', 'gte']) q[m] = (...a: unknown[]) => { if (m === 'eq' || m === 'in') filters.push(String(a[0]) + '=' + JSON.stringify(a[1])); return q; };
    const key = () => name + (filters.length ? '?' + filters.join('&') : '');
    q.maybeSingle = () => { reads.push(key()); return rejects.includes(name) ? new Promise((_, rej) => setTimeout(() => rej(new Error('read failed')), DELAY)) : settle(name); };
    q.then = (ok: (v: Answer) => unknown, bad?: (e: unknown) => unknown) => { reads.push(key()); return settle(key()).then(ok, bad); };
    return q;
  };
  return { reads, from: table, rpc: (fn: string) => { reads.push('rpc:' + fn); return settle('rpc:' + fn); } };
}

const SUP: Supplier = { id: 7, company_name: 'ZZ DEMO — fixture', approval_status: 'pending', registration_status: null, license_expiry: null, name_corrected_from: null };

Deno.test('alerts: two waves, not five in a row', async () => {
  const admin = fakeAdmin({
    'inquiry_matches?supplier_id=7': { data: [{ inquiry_id: 'a' }, { inquiry_id: 'b' }] },
    'quotes?supplier_id=7': { data: [{ inquiry_id: 'b' }] },
    'inquiries?id=["a","b"]&status=["sent","open","active","collecting","live","quoted"]': { data: [{ id: 'a' }, { id: 'b' }] },
  });
  const t0 = performance.now();
  const alerts = await buildAlerts(admin, 7);
  const ms = performance.now() - t0;
  // Serial, the five reads cost 5 x DELAY. Two waves cost 2 x DELAY.
  assert(ms < DELAY * 3, `alerts took ${ms.toFixed(0)} ms — reads are waiting on each other`);
  assertEquals(alerts.map((a) => a.kind), ['new_rfq']);
  assertEquals(alerts[0].count, 1, 'the quoted inquiry is not an RFQ waiting');
});

Deno.test('eligibility: every read in one wave, and an unconfirmed scope blocks', async () => {
  const admin = fakeAdmin({ leads: { data: { id: 7, sector: 'hvac', registration_submitted_at: '2026-09-01', phone: '+971500000000' } } });
  const t0 = performance.now();
  const e = await buildEligibility(admin, 7);
  const ms = performance.now() - t0;
  assert(ms < DELAY * 3, `eligibility took ${ms.toFixed(0)} ms`);
  assertEquals(e.eligible, false);
  assert(e.blocking.some((b: { code: string }) => b.code === 'scope_unconfirmed'));
  assertEquals(e.reach.shortlist_size, 8);
});

Deno.test('eligibility: a scope read that throws fails closed — the scope gate still blocks', async () => {
  const admin = fakeAdmin({ leads: { data: { id: 7, sector: 'hvac', registration_submitted_at: '2026-09-01' } }, supplier_capabilities: { data: { confirmed_at: '2026-09-01' } } }, ['supplier_capabilities']);
  const e = await buildEligibility(admin, 7);
  assertEquals(e.eligible, false);
  assert(e.blocking.some((b: { code: string }) => b.code === 'scope_unconfirmed'), 'a failed read must never read as a confirmed scope');
});

Deno.test('dashboard: one payload carries stats, alerts, eligibility, impact and the bell counts', async () => {
  const admin = fakeAdmin({
    'rpc:fn_supplier_stats': { data: { quotes_total: 3 } },
    'rpc:fn_supplier_document_impact': { data: { documents: [] } },
    'messages?supplier_id=7&sender="customer"&read_by_supplier=false&blocked=false': { count: 2 },
    'quote_spec_hold?supplier_id=7&state=["open","awaiting_approval"]': { count: 1 },
  });
  const t0 = performance.now();
  const { status, body } = await buildDashboard(admin, SUP);
  const ms = performance.now() - t0;
  assertEquals(status, 200);
  assertEquals(body.stats, { quotes_total: 3 });
  assertEquals(body.notifications, { unread_messages: 2, spec_holds: 1 });
  assertEquals(body.document_impact, { ok: true, documents: [] });
  assertEquals(body.eligibility.ok, true);
  assertEquals(body.supplier.company_name, 'ZZ DEMO — fixture');
  // The deepest chain is alerts (matches, then open inquiries) and the mandatory-six check; nothing
  // waits on fn_supplier_stats any more. Before: 8 serial reads in overview alone.
  assert(ms < DELAY * 4, `dashboard took ${ms.toFixed(0)} ms — expected at most three waves`);
  console.log(`dashboard: ${admin.reads.length} reads, ${ms.toFixed(0)} ms at ${DELAY} ms per read (${(ms / DELAY).toFixed(1)} waves)`);
});

Deno.test('dashboard: a stats failure is a 500, not an empty dashboard', async () => {
  const admin = fakeAdmin({ 'rpc:fn_supplier_stats': { data: null, error: { message: 'boom' } } });
  const { status, body } = await buildDashboard(admin, SUP);
  assertEquals(status, 500);
  assertEquals(body.error, 'boom');
});

Deno.test('dashboard: a failed impact read is null, never zeros', async () => {
  const admin = fakeAdmin({ 'rpc:fn_supplier_document_impact': { data: null, error: { message: 'x' } } });
  const { body } = await buildDashboard(admin, SUP);
  assertEquals(body.document_impact, null);
});
