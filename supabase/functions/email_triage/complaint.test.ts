// A complaint by e-mail enters the register (email_triage/complaint.ts). Stubbed database: no network.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { bareAddress, mailComplaint } from './complaint.ts';
import type { Ticket } from '../_shared/complaint_register.ts';

type Call = [string, Record<string, unknown>];
const T: Ticket = { ticket: 'QD-C-READ00', respondDue: '', acknowledgeDue: '', duplicate: false, acknowledged: false, jobs: [] };
const rpcOf = (calls: Call[]) => ({ rpc: (fn: string, a: Record<string, unknown>) => { calls.push([fn, a]);
  return Promise.resolve({ data: { ok: true, ticket: 'QD-C-TRIAGE', respond_due: '2026-11-30T05:00:00Z', acknowledge_due: '' }, error: null }); } });

Deno.test('the report: one key per mail, the bare sender address, a supplier by its lead, the raw text, a fixture by its address', () => {
  assertEquals(bareAddress('"Sami K" <Sami.K@Firm.AE>'), 'sami.k@firm.ae');
  const c = mailComplaint({ id: 912, from_email: 'Ops <ops@firm.ae>', subject: 'Job 1042', body: 'Your supplier never came.', lead_id: 55 }, 'supplier', 'en');
  assertEquals(c.report.sourceKey, 'email:912');
  assertEquals(c.report.email, 'ops@firm.ae');
  assertEquals([c.report.partyKind, c.report.partyId], ['supplier', '55']);
  assertEquals(c.report.message, 'Job 1042\n\nYour supplier never came.');
  assertEquals(c.report.fixture, false);
  const cust = mailComplaint({ id: 913, from_email: 'zz-demo@example.invalid', subject: 's', body: 'b', lead_id: 55 }, 'customer', 'ar');
  assertEquals(cust.report.partyKind, undefined, 'a customer is linked by address in SQL, never by a lead');
  assertEquals(cust.report.fixture, true);
});

Deno.test('the ticket: the reading\'s own; else the triage model\'s complaint opens it; neither opens nothing', async () => {
  const m = { id: 914, from_email: 'a@firm.ae', subject: 'Overcharged', body: 'You charged me twice.', lead_id: null };
  const c = mailComplaint(m, 'customer', 'en');
  const none: Call[] = [];
  assertEquals((await c.ticket(rpcOf(none), { complaint: true, ticket: T }, null))?.ticket, 'QD-C-READ00');
  assertEquals(await c.ticket(rpcOf(none), { complaint: false, ticket: null }, { category: 'customer_question', summary: 'asks' }), null);
  assertEquals(none.length, 0);
  const calls: Call[] = [];
  const t = await c.ticket(rpcOf(calls), { complaint: false, ticket: null }, { category: 'complaint', summary: 'charged twice' });
  assertEquals(t?.ticket, 'QD-C-TRIAGE');
  assertEquals(calls.length, 1);
  assertEquals(calls[0][1].p_source_key, 'email:914');
  assert(String(calls[0][1].p_reading).startsWith('the triage model read it as a complaint'), String(calls[0][1].p_reading));
});
