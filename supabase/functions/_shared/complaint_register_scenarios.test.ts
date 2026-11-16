// SCENARIOS (EN/AR, every door): a complaint on any channel opens ONE ticket linked as the channel holds the person; a message that
// is not a complaint opens none. The model is a stub that answers what a model reading these messages would answer, so this proves
// the doors' plumbing around the model's reading (which door asks, what it registers, what it must never put in the ticket), not
// the model's judgement. Every door asks the model with the same COMPLAINT_OPTIONS, and that question is checked to reach it.
// No network, no paid call.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import type { LlmReply, ThinkDeps } from './think.ts';
import { COMPLAINT_OPTIONS, complaintFact, portalComplaintReport, registerComplaint, widgetComplaintReport } from './complaint_register.ts';
import { needsAPerson } from './reasoned_decisions.ts';
import { whatsappReadings } from './reasoned_channels.ts';
import { parseReading, readingPrompt } from './inquiry_reading.ts';
import { mailComplaint } from '../email_triage/complaint.ts';
import { waComplaintReport } from '../wa_inbound/complaint.ts';

type Call = [string, Record<string, unknown>];
type Door = 'email' | 'whatsapp' | 'widget' | 'portal';
interface Scenario { name: string; door: Door; lang: 'en' | 'ar'; message: string; modelSays: 'complaint' | 'not_a_complaint';
  must: ((a: Record<string, unknown>) => string | null)[]; mustNot: ((a: Record<string, unknown>) => string | null)[] }

const noAddressInKey = (a: Record<string, unknown>) => /@|\d{9,}/.test(String(a.p_source_key)) ? 'the key carries an address or a number' : null;
const noEmailFromPhone = (a: Record<string, unknown>) => a.p_email != null ? 'an e-mail was put on a WhatsApp ticket' : null;
const channelIs = (c: Door) => (a: Record<string, unknown>) => a.p_channel === c ? null : 'channel ' + String(a.p_channel);
const langIs = (l: 'en' | 'ar') => (a: Record<string, unknown>) => a.p_lang === l ? null : 'lang ' + String(a.p_lang);
const partyIs = (k: string, id: string) => (a: Record<string, unknown>) => a.p_party_kind === k && a.p_party_id === id ? null : 'party ' + String(a.p_party_kind) + ':' + String(a.p_party_id);
const emailIs = (e: string) => (a: Record<string, unknown>) => a.p_email === e ? null : 'email ' + String(a.p_email);

const SCENARIOS: Scenario[] = [
  { name: 'e-mail EN: a supplier no-show', door: 'email', lang: 'en', modelSays: 'complaint', message: 'Job 1042: your supplier never came and nobody answers. This is unacceptable.',
    must: [channelIs('email'), emailIs('owner@firm.ae'), langIs('en')], mustNot: [noAddressInKey] },
  { name: 'e-mail AR: charged twice', door: 'email', lang: 'ar', modelSays: 'complaint', message: 'تم خصم المبلغ مرتين من بطاقتي ولم يرد عليّ أحد',
    must: [channelIs('email'), langIs('ar')], mustNot: [noAddressInKey] },
  { name: 'e-mail EN: how do complaints work (a question)', door: 'email', lang: 'en', modelSays: 'not_a_complaint', message: 'What is your complaints policy and how long do refunds take?', must: [], mustNot: [] },
  { name: 'WhatsApp AR: deposit taken, refund demanded', door: 'whatsapp', lang: 'ar', modelSays: 'complaint', message: 'المورد أخذ العربون واختفى وأريد استرداد مبلغي',
    must: [channelIs('whatsapp'), langIs('ar'), (a) => a.p_phone === '+971500000071' ? null : 'phone ' + String(a.p_phone)], mustNot: [noEmailFromPhone] },
  { name: 'WhatsApp EN: rude supplier', door: 'whatsapp', lang: 'en', modelSays: 'complaint', message: 'The supplier you sent was rude to my staff and left the site dirty.',
    must: [channelIs('whatsapp'), langIs('en')], mustNot: [noEmailFromPhone] },
  { name: 'WhatsApp AR: asks for a person, no complaint', door: 'whatsapp', lang: 'ar', modelSays: 'not_a_complaint', message: 'ممكن أتكلم مع موظف؟', must: [], mustNot: [] },
  { name: 'widget EN: signed-in customer, quote far too high', door: 'widget', lang: 'en', modelSays: 'complaint', message: 'The quote I got is double the market price and the supplier ignores me.',
    must: [channelIs('widget'), partyIs('customer', 'c-uuid-1'), emailIs('cust@firm.ae')], mustNot: [noAddressInKey] },
  { name: 'widget AR: anonymous visitor, misleading site', door: 'widget', lang: 'ar', modelSays: 'complaint', message: 'موقعكم مضلل، دفعت ولم أحصل على شيء',
    must: [channelIs('widget'), langIs('ar'), (a) => a.p_party_kind == null ? null : 'an anonymous visitor was linked to a person'], mustNot: [noAddressInKey] },
  { name: 'widget EN: the sign-in code never came (a fault, not a complaint)', door: 'widget', lang: 'en', modelSays: 'not_a_complaint', message: 'I never got the sign-in code.', must: [], mustNot: [] },
  { name: 'portal EN: no quotes after a week', door: 'portal', lang: 'en', modelSays: 'complaint', message: 'A week and not one quote on my request. Very poor service.',
    must: [channelIs('portal'), partyIs('customer', 'c-uuid-2'), emailIs('p@firm.ae')], mustNot: [noAddressInKey] },
  { name: 'portal AR: thanks (not a complaint)', door: 'portal', lang: 'ar', modelSays: 'not_a_complaint', message: 'شكراً جزيلاً على المساعدة', must: [], mustNot: [] },
  { name: 'portal AR: the supplier damaged the floor', door: 'portal', lang: 'ar', modelSays: 'complaint', message: 'المورد أتلف الأرضية أثناء التركيب ولم يعتذر',
    must: [channelIs('portal'), langIs('ar')], mustNot: [noAddressInKey] },
];

function deps(modelSays: string, choice = 'needs_a_person') {
  const calls: Call[] = []; const prompts: string[] = [];
  const d: ThinkDeps = {
    gate: () => Promise.resolve({ allowed: true } as never),
    llm: (_p, sys, input) => { prompts.push(String(sys) + '\n' + String(input));
      return Promise.resolve({ content: JSON.stringify({ answer: 'the reading', reasoning: ['read'], cited: [], confidence: 0.9, decision: { choice },
        complaint: modelSays, needs_a_person: 'needs_a_person', menu_meaning: 'other' }), model: 'stub/a' } as LlmReply); },
    embed: () => Promise.resolve([0.1]),
    rpc: (fn, args) => { calls.push([fn, args]);
      if (fn === 'fn_complaint_open_from_message') return Promise.resolve({ data: { ok: true, duplicate: false, ticket: 'QD-C-SCENE2', respond_due: '2026-11-30T05:00:00Z', acknowledge_due: '' }, error: null });
      if (fn === 'fn_case_recall') return Promise.resolve({ data: { cases: [] }, error: null });
      return Promise.resolve({ data: [], error: null }); },
  };
  return { d, calls, prompts };
}

async function runDoor(s: Scenario) {
  const x = deps(s.modelSays, s.door === 'whatsapp' ? 'none' : 'needs_a_person');
  if (s.door === 'email') {
    const c = mailComplaint({ id: 4242, from_email: 'Owner <owner@firm.ae>', subject: 'Complaint', body: s.message, lead_id: null }, 'customer', s.lang);
    const person = await needsAPerson(x.d, { seat: 'customer_support', surface: 'email_triage.needs_a_person', message: s.message, complaint: c.report });
    const t = await c.ticket(x.d, person, null);
    if (t) assert(complaintFact(t).includes(t.ticket), 'the reply is told the ticket');
  } else if (s.door === 'whatsapp') {
    const r = await whatsappReadings(x.d, { message: s.message, intents: [{ intent_key: 'contact_human', label: 'a person' }], trades: [], phone: 'whatsapp:+971500000071',
      messageSid: 'SMscene', audience: 'customer', conversation: [], menu: [] } as never);
    if (r.complaint) await registerComplaint(x.d.rpc, await waComplaintReport({ from: 'whatsapp:+971500000071', body: s.message, messageSid: 'SMscene', receivedAt: '2026-11-16T10:00:00Z',
      reading: r.result.answer, arabic: s.lang === 'ar' }));
  } else if (s.door === 'widget') {
    const who = s.name.includes('signed-in') ? { email: 'cust@firm.ae', audience: 'customer' as const, id: 'c-uuid-1' } : null;
    await needsAPerson(x.d, { seat: 'customer_support', surface: 'site_assistant.person', message: s.message, audience: 'visitor',
      complaint: await widgetComplaintReport({ caller: who ? 'customer:c-uuid-1' : '203.0.113.9', hour: '2026-11-16T10', msgKey: 'abcd', who, lang: s.lang, message: s.message }) });
  } else {
    // the portal's turn reading (one json_extraction call) answers the complaint field; the door registers it
    const p = readingPrompt({ taxonomy: [{ code: 'flooring', label: 'Flooring', group_code: 'construction_building' }], problems: [], lastSeat: '', message: s.message });
    x.prompts.push(p.sys);
    const reading = parseReading(JSON.stringify({ trade_codes: [], complaint: s.modelSays === 'complaint' ? 'they complain: ' + s.message.slice(0, 40) : '' }),
      { taxonomy: [{ code: 'flooring', label: 'Flooring', group_code: 'construction_building' }] });
    if (reading?.complaint) await registerComplaint(x.d.rpc, await portalComplaintReport({ episodeKey: 'portal:ep1', turn: 3, customerId: 'c-uuid-2', email: 'p@firm.ae',
      message: s.message, reading: reading.complaint, lang: s.lang }));
  }
  return x;
}

Deno.test('at least ten scenarios, both languages, every door, with must and must-not', () => {
  assert(SCENARIOS.length >= 10);
  assertEquals(new Set(SCENARIOS.map((s) => s.lang)).size, 2);
  assertEquals(new Set(SCENARIOS.map((s) => s.door)).size, 4);
});

for (const s of SCENARIOS) {
  Deno.test('scenario: ' + s.name, async () => {
    const x = await runDoor(s);
    // the model is asked whether it is a complaint, on every door
    assert(x.prompts.some((p) => s.door === 'portal' ? /complaint: when the customer/.test(p) : p.includes(COMPLAINT_OPTIONS[0].meaning.slice(0, 60))),
      'the complaint question did not reach the model');
    const opens = x.calls.filter(([fn]) => fn === 'fn_complaint_open_from_message');
    if (s.modelSays === 'not_a_complaint') { assertEquals(opens.length, 0, 'MUST NOT open a ticket'); return; }
    assertEquals(opens.length, 1, 'MUST open exactly one ticket');
    const a = opens[0][1];
    assert(String(a.p_source_key).length > 0 && String(a.p_message).trim().length > 0);
    for (const f of s.must) { const why = f(a); assertEquals(why, null, 'MUST: ' + why); }
    for (const f of s.mustNot) { const why = f(a); assertEquals(why, null, 'MUST NOT: ' + why); }
  });
}
