// THE SUPPLIER IS KNOWN ON EVERY CHANNEL (customer_support, 16 Nov 2026; ledgers 1711-1713; who-knows-what audit items 5-7).
// The reading's shape is fn_wa_context's supplier branch as the_supplier_is_known_on_every_channel_probe.sql proves it on a
// local Postgres 16; these tests prove the words every supplier door builds from it.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { readCollaborationRows, readSupplier, supplierKnownFacts, supplierStanding, withSupplierKnown } from './supplier_known.ts';

const HELD = {
  scope: 'supplier', known: true, company: 'ZZ DEMO Held Steel Rival',
  account: { email: 'zz-demo-supknown-b@example.invalid', phone: null },
  profile: { claimed: true, approval_status: 'approved', verified: true, trade_licence_no: 'ZZ-DEMO-1002', licence_expiry: '2026-11-06',
    licence_expired: true, licence_days_left: -10, licence_on_file: true, blocked_because: null },
  services: { confirmed: false, confirmed_at: null, trades: [{ code: 'hvac', label: 'HVAC', open_to_customers: false }], trades_excluded: [],
    services: [], emirates_covered: ['dubai'], uae_wide: false },
  matching: { receives_requests_now: false, jobs_sent_30d: 0, requests_in_his_trades_30d: 0, availability: { state: 'busy', busy_until: '2026-11-23' },
    strikes: 3, strike_limit: 3, matching_paused: true, paused_reason: 'collaboration_hold',
    collaboration: { unanswered_in_a_row: 3, unanswered_total: 4, warned_at: '2026-11-11T10:00:00Z', held_at: '2026-11-14T10:00:00Z', lifted_at: null, on_hold: true },
    why_no_jobs: [
      { code: 'licence_expired', says: 'His trade licence expired on 06 Nov 2026. He should upload the renewed licence in the Documents tab.' },
      { code: 'held_for_unanswered_requests', says: 'Matching is paused because 3 quotations in a row were left unanswered at the customer\'s decision; it is lifted only on review.' },
      { code: 'services_not_confirmed', says: 'He has not confirmed his trades and services in the Services tab of his portal. Requests are matched only on confirmed services.' }] },
  recent_jobs: [{ job: 1043, trade: 'hvac', emirate: 'Dubai', sent_at: '2026-11-15T08:00:00Z', job_status: 'sent', my_quote: null }],
  work: { inquiries_received: 1 },
};
const IDLE = {
  scope: 'supplier', known: true, company: 'ZZ DEMO Polar Duct Works',
  profile: { claimed: true, approval_status: 'approved', verified: true, trade_licence_no: 'ZZ-DEMO-1001', licence_expiry: '2027-06-04', licence_expired: false, licence_days_left: 200 },
  services: { confirmed: true, trades: [{ code: 'hvac', label: 'HVAC', open_to_customers: false }, { code: 'plumbing', label: 'Plumbing', open_to_customers: true }],
    trades_excluded: ['electrical'], services: ['Split AC installation'], emirates_covered: [], uae_wide: true },
  matching: { receives_requests_now: true, jobs_sent_30d: 0, requests_in_his_trades_30d: 0, collaboration: { unanswered_in_a_row: 0, on_hold: false },
    why_no_jobs: [{ code: 'no_requests_in_his_trades', says: 'No customer posted a request in his trades in the last 30 days.' }] },
  recent_jobs: [],
};

Deno.test('the standing carries his trades, emirates, jobs in 30 days and why not more (audit item 5)', () => {
  const t = supplierStanding(IDLE);
  for (const s of ['HVAC (not open to customers yet)', 'Plumbing (open to customers)', 'all of the UAE', 'Split AC installation', 'electrical',
    '0 sent to him in the last 30 days', 'Receives requests now: yes', 'No customer posted a request in his trades', '200 day(s) left']) assert(t.includes(s), `missing "${s}":\n${t}`);
});

Deno.test('a held supplier reads every gate, the expiry and the rule never to call him ready (audit item 7)', () => {
  const t = supplierStanding(HELD);
  for (const s of ['EXPIRED 10 day(s) ago', 'expiry 2026-11-06', 'Receives requests now: NO', 'Documents tab', 'left unanswered', 'on hold since 2026-11-14',
    'NOT confirmed in the Services tab', 'dubai', 'never tell him he is verified, ready to submit']) assert(t.includes(s), `missing "${s}":\n${t}`);
});

Deno.test('a customer reading, an unknown sender or nothing gives no supplier words', () => {
  assertEquals(supplierStanding(null), '');
  assertEquals(supplierStanding({ scope: 'supplier', known: false }), '');
  assertEquals(supplierStanding({ scope: 'customer', known: true, inquiries: [] }), '');
});

Deno.test('the reading before the SQL is applied (no services/matching keys) still states his licence and counts, and invents no trade', () => {
  const t = supplierStanding({ scope: 'supplier', known: true, profile: { approval_status: 'pending', blocked_because: 'licence_number_unread' }, work: { inquiries_received: 2, inquiries_quoted: 1 } });
  assert(t.includes('not approved yet (status: pending; held for: licence_number_unread)') && t.includes('Requests received in total: 2'), t);
  assert(!/Trades on his profile|Why not more/.test(t), t);
});

const stubDb = (reading: unknown, events: unknown[] = []) => {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return { calls, rpc: (fn: string, args: Record<string, unknown>) => { calls.push({ fn, args });
    return Promise.resolve(fn === 'fn_wa_context' ? { data: reading, error: null } : { data: { events }, error: null }); } };
};

Deno.test('readSupplier asks fn_wa_context for the supplier by his own address, and nothing else', async () => {
  const db = stubDb(HELD);
  assertEquals((await readSupplier(db, ' ZZ-Demo-SupKnown-B@example.invalid '))?.company, 'ZZ DEMO Held Steel Rival');
  assertEquals(db.calls, [{ fn: 'fn_wa_context', args: { p_audience: 'supplier', p_phone: 'zz-demo-supknown-b@example.invalid' } }]);
  assertEquals(await readSupplier(stubDb({ scope: 'supplier', known: false }), 'a@example.invalid'), null);
  assertEquals(await readSupplier({ rpc: () => { throw new Error('down'); } }, 'a@example.invalid'), null);
  assertEquals(await readSupplier(stubDb(HELD), 'not-an-address'), null);
});

Deno.test('the collaboration rows are his timeline rows of kind collaboration only', async () => {
  const rows = await readCollaborationRows(stubDb(null, [{ kind: 'message_out', summary: 'x' }, { kind: 'collaboration', at: '2026-11-14T10:00:00Z', summary: 'held — 3 in a row' }]), 'b@example.invalid');
  assertEquals(rows.map((r) => r.summary), ['held — 3 in a row']);
});

Deno.test('supplierKnownFacts: the standing and the collaboration record; the job first in the review facts', async () => {
  const t = await supplierKnownFacts(stubDb(HELD, [{ kind: 'collaboration', at: '2026-11-14T10:00:00Z', summary: 'held — 3 in a row — RFQ 1A2B3C4D' }]), 'zz-demo-supknown-b@example.invalid');
  assert(t.includes('EXPIRED') && t.includes('HIS COLLABORATION RECORD ON THE SHARED TIMELINE') && t.includes('held — 3 in a row'), t);
  const f = withSupplierKnown('Job 164941: ready to submit.', t);
  assert(f.startsWith('Job 164941: ready to submit.') && f.includes('EXPIRED'));
  assertEquals(withSupplierKnown('Job 1', ''), 'Job 1');
  assertEquals(await supplierKnownFacts(stubDb(null), 'x@example.invalid'), '');
});
