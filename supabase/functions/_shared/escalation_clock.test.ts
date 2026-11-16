// Every escalation carries a clock; the CEO's model decides; customer_support's model tells the person (16 Nov 2026, agent
// FOUNDER_CLOCK). Stubbed models and database: no network, no paid call. Scenarios named after what a real company does.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import {
  ceoPrompt, type ClockIO, type DueClock, escalationFactsText, holdingRules, isStanding, messagePrompt, parseCeoDecision, parseMessage,
  pressLegalPosition, purposeOf, readEscalationFacts, STANDING_OPTIONS, workEscalationClocks,
} from './escalation_clock.ts';
import { needsAPerson } from './reasoned_decisions.ts';
import type { LlmReply, ThinkDeps } from './think.ts';
import { BRIEF_TEXT } from './brief.generated.ts';

const NOW = Date.parse('2026-11-16T08:00:00Z');
const J = (x: unknown) => JSON.stringify(x);
const clock = (o: Partial<DueClock> = {}): DueClock => ({
  id: 7, ref: 'ESC-7', due_for: 'decide', kind: 'person', channel: 'email', audience: 'customer', lang: 'en', state: 'open',
  subject_line: 'Re: my request', request_text: 'ZZ DEMO I want to speak to a real person, nobody answers me', promised: 'a member of the team will reply in this same thread',
  promised_at: '2026-11-16T02:00:00Z', hours_waiting: 6, statuses_sent: 0, next_word_in_hours: 24, switch_reads_off: false, has_contact: true,
  status_due: true, founder: { founder_last_answered_at: '2026-11-07T09:00:00Z', founder_hours_since: 215, channels_down_founder_credential: [] }, ...o,
});

type Call = [string, ...unknown[]];
function io(o: { due: DueClock[]; ceo?: string | null; write?: string | null; deliver?: { sent: boolean; via?: string; reason?: string }; decidedAs?: string }) {
  const calls: Call[] = [];
  const x: ClockIO = {
    now: () => NOW,
    due: (limit) => { calls.push(['due', limit]); return Promise.resolve(o.due); },
    askCeo: (c, system, input) => { calls.push(['askCeo', c.id, system, input]); return Promise.resolve({ content: o.ceo ?? null, model: o.ceo ? 'stub/ceo' : null }); },
    decided: (id, d, model) => { calls.push(['decided', id, d, model]); return Promise.resolve({ ok: true, decision: o.decidedAs ?? d.decision }); },
    ceoFailed: (id, e) => { calls.push(['ceoFailed', id, e]); return Promise.resolve({ ok: true }); },
    write: (c, system, input) => { calls.push(['write', c.id, system, input]); return Promise.resolve({ content: o.write ?? null, model: o.write ? 'stub/support' : null }); },
    deliver: (id, stage, subject, body) => { calls.push(['deliver', id, stage, subject, body]); return Promise.resolve(o.deliver ?? { sent: true, via: 'email' }); },
    told: (id, stage, result, text) => { calls.push(['told', id, stage, result, text]); return Promise.resolve({ ok: true }); },
  };
  return { x, calls, of: (k: string) => calls.filter((c) => c[0] === k) };
}
const MSG = J({ subject: 'About your request', message: 'ZZ DEMO We said we would reply and we are late; we are sorry. ... QuotesDone Customer Support' });

Deno.test('1. the company position is section 14 of the brief, the one copy, with the holding line and the formal address', () => {
  const p = pressLegalPosition();
  assertMatch(p, /^## 14\. Press/);
  assertMatch(p, /management@quotesdone\.com/);
  assertMatch(p, /holding line/i);
  assert(!/1633275/.test(p), 'never the licence number');
  assert(BRIEF_TEXT.includes(p), 'compiled into the brief every customer-facing seat reads');
});

Deno.test('2. "I want a person": the CEO decides within its authority and the person is told the decision in the same tick', async () => {
  const s = io({ due: [clock()], ceo: J({ decision: 'decided', standing: 'customer', outcome: 'ZZ DEMO Your request is re-sent to three more suppliers today.', reasons: 'ZZ DEMO only two suppliers had it.' }), write: MSG });
  const out = await workEscalationClocks(s.x, 3);
  assertEquals(s.of('decided').length, 1);
  assertEquals(s.of('write').length, 1);
  assertMatch(String(s.of('write')[0][2]), /The matter is decided/);
  assertMatch(String(s.of('write')[0][3]), /re-sent to three more suppliers/, 'the decision the CEO made is what the message carries');
  assertEquals(s.of('deliver')[0][2], 'decision');
  assertEquals(s.of('told')[0][2], 'decision');
  assertEquals(out[1].sent, true);
});

Deno.test('3. the founder is only for what the law reserves to him: the person gets an honest status, the CEO prompt says so', async () => {
  const { system } = ceoPrompt(clock({ kind: 'legal' }));
  assertMatch(system, /founder_by_law" ONLY/);
  assertMatch(system, /a complaint, a request for a person, a refund, a journalist or a lawyer's letter\s+is yours/);
  const s = io({ due: [clock({ kind: 'legal' })], ceo: J({ decision: 'founder_by_law', standing: 'legal', outcome: '', reasons: 'ZZ DEMO a summons addressed to the licence holder', law: 'ZZ DEMO the summons names the licence holder in person' }), write: MSG });
  await workEscalationClocks(s.x);
  assertEquals((s.of('decided')[0][2] as { law: string }).law, 'ZZ DEMO the summons names the licence holder in person');
  assertMatch(String(s.of('write')[0][2]), /legal representative in person/);
  assert(/never mention the founder/.test(String(s.of('write')[0][2])), 'the person is never told to wait for the founder');
  assertEquals(s.of('deliver')[0][2], 'status_1');
});

Deno.test('4. not decided yet and the clock has not run out: nothing is sent; run out: an honest status with the next word', async () => {
  const notYet = J({ decision: 'not_yet', standing: 'customer', outcome: 'ZZ DEMO checking the supplier', reasons: 'ZZ DEMO the supplier has not answered' });
  const quiet = io({ due: [clock({ status_due: false })], ceo: notYet, write: MSG });
  await workEscalationClocks(quiet.x);
  assertEquals(quiet.of('write').length, 0);
  const late = io({ due: [clock({ status_due: true })], ceo: notYet, write: MSG });
  await workEscalationClocks(late.x);
  const sys = String(late.of('write')[0][2]);
  assertMatch(sys, /not decided yet/);
  assertMatch(sys, /apologise once/);
  assertMatch(sys, /by 17 Nov 2026, 12:00 Dubai time/, 'the one time it may promise: the clock\'s next word, in Dubai time');
});

Deno.test('5. the CEO model does not answer: recorded, and the person still gets an honest status when the clock has run out', async () => {
  const s = io({ due: [clock({ status_due: true })], ceo: null, write: MSG });
  const out = await workEscalationClocks(s.x);
  assertEquals(s.of('ceoFailed').length, 1);
  assertEquals(s.of('deliver')[0][2], 'status_1');
  assertEquals(out[0].decide, false);
  const bad = io({ due: [clock({ status_due: false })], ceo: J({ decision: 'maybe', reasons: 'x' }), write: MSG });
  await workEscalationClocks(bad.x);
  assertMatch(String(bad.of('ceoFailed')[0][2]), /MALFORMED_DECISION/);
  assertEquals(bad.of('write').length, 0);
});

Deno.test('6. no model writes the message: nothing is sent, no code-written text stands in (ruling 1339), the clock retries', async () => {
  const s = io({ due: [clock({ due_for: 'status', state: 'open' })], write: null });
  await workEscalationClocks(s.x);
  assertEquals(s.of('deliver').length, 0);
  const told = s.of('told')[0];
  assertEquals((told[3] as { sent: boolean }).sent, false);
  assertMatch(String((told[3] as { reason: string }).reason), /no model wrote the message/);
  assertEquals(told[4], '');
});

Deno.test('7. a payer held by the live hold: an honest status while it is on, "payment is open" the day it reads off, never a CEO call', async () => {
  const on = io({ due: [clock({ kind: 'held_payment', due_for: 'status', switch_reads_off: false, statuses_sent: 1 })], write: MSG });
  await workEscalationClocks(on.x);
  assertEquals(on.of('askCeo').length, 0);
  assertMatch(String(on.of('write')[0][2]), /not open yet\. Nothing has been charged/);
  assertMatch(String(on.of('write')[0][2]), /give no date for it/);
  assertEquals(on.of('deliver')[0][2], 'status_2');
  const off = io({ due: [clock({ kind: 'held_payment', due_for: 'tell', switch_reads_off: true })], write: MSG });
  await workEscalationClocks(off.x);
  assertEquals(purposeOf(clock({ kind: 'held_payment', switch_reads_off: true })), 'payment_open');
  assertMatch(String(off.of('write')[0][2]), /now open/);
  assertEquals(off.of('deliver')[0][2], 'payment_open');
});

Deno.test('8. a journalist: the message keeps to the company position; the CEO is told who is writing', () => {
  const { system, input } = messagePrompt(clock({ kind: 'press', audience: 'press', due_for: 'status' }), 'status', NOW);
  assertMatch(system, /They write as press: keep to the company position/);
  assert(JSON.parse(input).company_position.startsWith('## 14. Press'));
  const ceo = JSON.parse(ceoPrompt(clock()).input);
  assert(String(ceo.company_position_press_legal_regulator).includes('holding line'));
  assertEquals(ceo.founder.hours_since, 215, 'the CEO knows the founder has not answered for nine days');
  assertEquals(parseCeoDecision(J({ decision: 'decided', standing: 'press', outcome: 'ZZ DEMO the holding line stands', reasons: 'ZZ DEMO no comment' }))?.standing, 'press');
});

Deno.test('9. Arabic for an Arabic customer, English for a supplier who wrote in Arabic (ruling 1008)', () => {
  assertMatch(messagePrompt(clock({ lang: 'ar' }), 'status', NOW).system, /formal Gulf Arabic/);
  assertMatch(messagePrompt(clock({ lang: 'ar', audience: 'supplier' }), 'status', NOW).system, /UAE English/);
});

Deno.test('10. the case facts every seat reads: the open promise, overdue flagged, the founder\'s last word, a founder-credential channel down', () => {
  assertEquals(escalationFactsText({ open_escalations: [], channels_down_founder_credential: [], founder_last_answered_at: '2026-11-01T00:00:00Z' }, NOW), '',
    'nothing to say: nothing added to the prompt (the founder alone is not a fact about this person)');
  const t = escalationFactsText({
    open_escalations: [{ ref: 'ESC-3', kind: 'person', channel: 'whatsapp', promised: 'ZZ DEMO someone will call you', promised_at: '2026-11-14T08:00:00Z', next_word_due: '2026-11-15T08:00:00Z', state: 'open' }],
    founder_last_answered_at: '2026-11-07T09:00:00Z',
    channels_down_founder_credential: [{ integration: 'meta_whatsapp', what: 'ZZ DEMO the Meta sign-in expired', since: '2026-11-12T00:00:00Z' }],
  }, NOW);
  assertMatch(t, /ESC-3 \(person, raised on whatsapp\)/);
  assertMatch(t, /overdue: say so and apologise/);
  assertMatch(t, /founder last answered the company on 07 Nov 2026/);
  assertMatch(t, /never page him: the CEO decides/);
  assertMatch(t, /Channel down until a credential only the founder can renew is renewed: meta_whatsapp/);
});

Deno.test('11. the facts read never blocks a turn: no identity reads nothing, an error or a throw is the empty string', async () => {
  let n = 0;
  assertEquals(await readEscalationFacts(() => { n++; return Promise.resolve({ data: {}, error: null }); }, { email: null, phone: '12' }), '');
  assertEquals(n, 0);
  assertEquals(await readEscalationFacts(() => Promise.resolve({ data: null, error: { message: 'boom' } }), { email: 'a@b.ae' }), '');
  assertEquals(await readEscalationFacts(() => { throw new Error('socket'); }, { phone: '+971 50 000 0097' }), '');
  const args: Record<string, unknown>[] = [];
  await readEscalationFacts((_f, a) => { args.push(a); return Promise.resolve({ data: { open_escalations: [] }, error: null }); }, { email: ' Owner@Firm.ae ', phone: null });
  assertEquals(args[0], { p_email: 'Owner@Firm.ae', p_phone: null });
});

Deno.test('12. who is writing is the model\'s reading, in the same call as the person question; a threat is not press', async () => {
  assertEquals(STANDING_OPTIONS.map((o) => o.id), ['press', 'legal', 'regulator', 'party']);
  assertMatch(STANDING_OPTIONS[3].meaning, /mention law, lawyers or the press as a threat/);
  assert(isStanding('legal') && !isStanding('party'));
  assertMatch(holdingRules('legal'), /No comment on the substance, no admission/);
  for (const [standing, expect] of [['press', 'press'], ['party', null]] as const) {
    let llmCalls = 0;
    const deps: ThinkDeps = {
      gate: () => Promise.resolve({ allowed: true } as never),
      llm: () => { llmCalls++; return Promise.resolve({ content: J({ answer: 'read', reasoning: ['ZZ DEMO a reporter asks for a comment'], cited: [], confidence: 0.9, decision: { choice: 'no_person' }, standing }), model: 'stub/a' } as LlmReply); },
      embed: () => Promise.resolve([0.1, 0.2]),
      rpc: (fn) => Promise.resolve(fn === 'fn_case_recall' ? { data: { cases: [] }, error: null } : fn === 'fn_reason_retrieve' ? { data: [], error: null } : { data: 1, error: null }),
    };
    const r = await needsAPerson(deps, { seat: 'customer_support', surface: 'email_triage.needs_a_person', message: 'ZZ DEMO I am a reporter at a newspaper; can you comment?' });
    assertEquals(r.standing, expect);
    assertEquals(r.value, false);
    assert(llmCalls >= 1);
  }
});

Deno.test('13. a failed queue read or a throwing clock never throws out of the heartbeat', async () => {
  const broken: ClockIO = { ...io({ due: [] }).x, due: () => Promise.reject(new Error('timeout')) };
  const out = await workEscalationClocks(broken);
  assertMatch(String(out[0].error), /due: timeout/);
  const s = io({ due: [clock({ due_for: 'status' })], write: MSG });
  s.x.deliver = () => Promise.reject(new Error('net down'));
  const r = await workEscalationClocks(s.x);
  assertMatch(String(r[0].error), /net down/);
  assertEquals(parseMessage('```json\n' + MSG + '\n```')?.subject, 'About your request');
  assertEquals(parseMessage(J({ message: '' })), null);
});

Deno.test('14. a decision the database refused to record is not told as decided', async () => {
  const s = io({ due: [clock({ status_due: false })], ceo: J({ decision: 'decided', outcome: 'ZZ DEMO x', reasons: 'ZZ DEMO y' }), write: MSG });
  s.x.decided = () => Promise.resolve({ ok: false, reason: 'clock 7 is already closed' });
  await workEscalationClocks(s.x);
  assertEquals(s.of('write').length, 0);
});
