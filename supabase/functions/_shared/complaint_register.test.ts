// A complaint on any channel enters the register (complaint_register.ts). Stubbed model and database: no network, no paid call.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import type { LlmReply, Phase, ThinkDeps } from './think.ts';
import { acknowledgeIfCarried, complaintFact, COMPLAINT_OPTIONS, dueDate, hashedKey, registerComplaint, type Ticket } from './complaint_register.ts';
import { needsAPerson } from './reasoned_decisions.ts';
import { whatsappReadings } from './reasoned_channels.ts';

const J = (x: unknown) => JSON.stringify(x);
type Call = [string, Record<string, unknown>];
const opened = (ticket = 'QD-C-ABCDEF') => ({ ok: true, duplicate: false, ticket, respond_due: '2026-11-30T05:00:00Z', acknowledge_due: '2026-11-18T05:00:00Z', inquiry_refs: ['1042'] });

Deno.test('the ticket is opened once per message with what the channel holds, and never throws', async () => {
  const calls: Call[] = [];
  const r = await registerComplaint((fn, a) => { calls.push([fn, a]); return Promise.resolve({ data: opened(), error: null }); },
    { channel: 'email', sourceKey: 'email:77', message: 'the supplier never came', reading: 'a no-show', email: ' Owner@Firm.AE ', partyKind: 'supplier', partyId: '12', lang: 'en' });
  assertEquals(r.opened, true);
  assertEquals(r.ticket?.ticket, 'QD-C-ABCDEF');
  assertEquals(r.ticket?.jobs, ['1042']);
  assertEquals(calls[0][0], 'fn_complaint_open_from_message');
  assertEquals(calls[0][1].p_email, 'owner@firm.ae');
  assertEquals(calls[0][1].p_source_key, 'email:77');
  assertEquals(calls[0][1].p_party_kind, 'supplier');
  // refused before any call: no key, a key carrying an address, an empty message
  const none: Call[] = [];
  const rpc = (fn: string, a: Record<string, unknown>) => { none.push([fn, a]); return Promise.resolve({ data: opened(), error: null }); };
  assertEquals((await registerComplaint(rpc, { channel: 'widget', sourceKey: ' ', message: 'x' })).opened, false);
  assertEquals((await registerComplaint(rpc, { channel: 'portal', sourceKey: 'portal:a@b.ae', message: 'x' })).opened, false);
  assertEquals((await registerComplaint(rpc, { channel: 'whatsapp', sourceKey: 'whatsapp:SM1', message: '  ' })).opened, false);
  assertEquals(none.length, 0);
  // the database refusing, or throwing, is a reason, never a throw
  const err = await registerComplaint(() => Promise.resolve({ data: null, error: { message: 'function does not exist' } }), { channel: 'email', sourceKey: 'email:1', message: 'x' });
  assertMatch(String(err.reason), /does not exist/);
  const threw = await registerComplaint(() => { throw new Error('socket closed'); }, { channel: 'email', sourceKey: 'email:1', message: 'x' });
  assertEquals(threw.opened, false);
});

Deno.test('the reply is told the ticket and its date; only a reply that carried it is the acknowledgement', async () => {
  const t: Ticket = { ticket: 'QD-C-ABCDEF', respondDue: '2026-11-29T21:00:00Z', acknowledgeDue: '', duplicate: false, acknowledged: false, jobs: [] };
  const f = complaintFact(t);
  assert(f.includes('QD-C-ABCDEF') && f.includes(dueDate(t.respondDue)), f);
  assertEquals(dueDate('2026-11-29T21:00:00Z'), '2026-11-30', 'the date is Dubai time');
  const calls: Call[] = [];
  const rpc = (fn: string, a: Record<string, unknown>) => { calls.push([fn, a]); return Promise.resolve({ data: true, error: null }); };
  assertEquals(await acknowledgeIfCarried(rpc, t, 'We are sorry. Your complaint is registered.', 'email'), false, 'a reply without the ticket is not the acknowledgement');
  assertEquals(await acknowledgeIfCarried(rpc, t, 'Registered under QD-C-ABCDEF; our response by 30 Nov.', 'email'), true);
  assertEquals(await acknowledgeIfCarried(rpc, { ...t, acknowledged: true }, 'QD-C-ABCDEF', 'email'), false, 'never twice');
  assertEquals(calls.length, 1);
  assertEquals(calls[0][0], 'fn_complaint_acknowledge');
  assertMatch(await hashedKey('widget', '203.0.113.9:2026-11-16T10:abc'), /^widget:[0-9a-f]{24}$/);
});

// the reasoned reading: the MODEL chooses `complaint` in the same call (ruling 1663); code only opens the ticket
function deps(person: string, complaint: string | null, choice = person) {
  const calls: Call[] = []; const phases: Phase[] = [];
  const d: ThinkDeps = {
    gate: () => Promise.resolve({ allowed: true } as never),
    llm: (phase) => { phases.push(phase);
      return Promise.resolve({ content: J({ answer: 'they say the supplier took the deposit and vanished', reasoning: ['read'], cited: [], confidence: 0.9,
        decision: { choice }, ...(complaint ? { complaint } : {}), needs_a_person: person, menu_meaning: 'other' }), model: 'stub/a' } as LlmReply); },
    embed: () => Promise.resolve([0.1, 0.2]),
    rpc: (fn, args) => { calls.push([fn, args]);
      if (fn === 'fn_complaint_open_from_message') return Promise.resolve({ data: opened(), error: null });
      if (fn === 'fn_case_recall') return Promise.resolve({ data: { cases: [] }, error: null });
      if (fn === 'fn_reason_retrieve') return Promise.resolve({ data: [], error: null });
      return Promise.resolve({ data: 1, error: null }); },
  };
  return { d, calls, phases };
}
const opens = (c: Call[]) => c.filter(([fn]) => fn === 'fn_complaint_open_from_message');

Deno.test('needsAPerson: the complaint is read in the same call and opens the ticket only when the model says so', async () => {
  assert(COMPLAINT_OPTIONS.some((o) => o.id === 'complaint') && COMPLAINT_OPTIONS.some((o) => o.id === 'not_a_complaint'));
  const report = { channel: 'widget' as const, sourceKey: 'widget:0f0f', lang: 'en' as const };
  const c = deps('needs_a_person', 'complaint');
  const r = await needsAPerson(c.d, { seat: 'customer_support', surface: 'site_assistant.person', message: 'you took my money and the supplier vanished', complaint: report });
  assertEquals(r.value, true, 'a complaint still needs a person, as before');
  assertEquals(r.complaint, true);
  assertEquals(r.ticket?.ticket, 'QD-C-ABCDEF');
  assertEquals(opens(c.calls).length, 1);
  assertEquals(c.phases.filter((p) => p === 'synthesise').length <= 2, true, 'no extra model call for the complaint');
  const n = deps('needs_a_person', 'not_a_complaint');
  const rn = await needsAPerson(n.d, { seat: 'customer_support', surface: 'site_assistant.person', message: 'can I speak to a person?', complaint: report });
  assertEquals(rn.complaint, false);
  assertEquals(opens(n.calls).length, 0, 'a request for a person is not a complaint');
  const s = deps('needs_a_person', 'complaint');
  await needsAPerson(s.d, { seat: 'marketing', surface: 'marketing_social.needs_a_person', message: 'terrible service' });
  assertEquals(opens(s.calls).length, 0, 'a surface that gives no register files nothing');
});

Deno.test('whatsappReadings: the complaint reading comes back with the others', async () => {
  const c = deps('needs_a_person', 'complaint', 'none');
  const r = await whatsappReadings(c.d, { message: 'المورد أخذ العربون واختفى', intents: [{ intent_key: 'contact_human', label: 'a person' }], trades: [], phone: '+971500000071',
    messageSid: 'SM1', audience: 'customer', conversation: [], menu: [] } as never);
  assertEquals(r.complaint, true);
  assertEquals(r.intent, 'intent:contact_human', 'the other readings are unchanged');
  const n = deps('no_person', 'not_a_complaint', 'none');
  const rn = await whatsappReadings(n.d, { message: 'how do refunds work?', intents: [], trades: [], phone: '+971500000071', messageSid: 'SM2', audience: 'customer', conversation: [], menu: [] } as never);
  assertEquals(rn.complaint, false);
});
