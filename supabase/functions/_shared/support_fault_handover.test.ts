// "It is broken" reaches the IT engineer as a real hand-over (ruling 1705). Stubbed model and database: no network, no paid call.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert';
import type { LlmReply, Phase, ThinkDeps } from './think.ts';
import { caseKeyOf, handFaultToIt, maskedTurns } from './support_fault_handover.ts';
import { needsAPerson, NEEDS_PERSON_OPTIONS } from './reasoned_decisions.ts';

const J = (x: unknown) => JSON.stringify(x);
type Rpc = [string, Record<string, unknown>];

Deno.test('the turns handed over are the person\'s own, masked, at most three', () => {
  const t = maskedTurns({ message: 'still broken, write to me at sami.k@gmail.com or +971 50 123 4567',
    conversation: [{ role: 'customer', text: 'first turn' }, { role: 'seat', text: 'our reply' }, { role: 'customer', text: 'the code never came' },
                   { role: 'customer', text: 'tried twice' }] });
  assertEquals(t.length, 3);
  assertEquals(t.map((x) => x.role), ['person', 'person', 'person']);
  assert(!t.some((x) => /our reply|first turn/.test(x.text)), 'our own replies and older turns are not handed over');
  assertEquals(/gmail|4567/.test(t[2].text), false, 'no address or number leaves the surface: ' + t[2].text);
});

Deno.test('a case key carries no identity, and a key that does is refused', async () => {
  const k = await caseKeyOf('whatsapp', 'whatsapp:+971501234567');
  assertMatch(k, /^whatsapp:[0-9a-f]{24}$/);
  assertEquals(await caseKeyOf('whatsapp', 'whatsapp:+971501234567'), k, 'stable for one conversation');
  const rpcs: Rpc[] = [];
  const r = await handFaultToIt((fn, args) => { rpcs.push([fn, args]); return Promise.resolve({ data: { filed: true }, error: null }); },
    { channel: 'email', caseKey: 'email:sami@x.ae', message: 'broken' });
  assertEquals(r.filed, false);
  assertEquals(rpcs.length, 0, 'nothing is filed under an identifying key');
});

Deno.test('the hand-over files once with the masked turns and never throws', async () => {
  const rpcs: Rpc[] = [];
  const ok = await handFaultToIt((fn, args) => { rpcs.push([fn, args]); return Promise.resolve({ data: { filed: true, issue_key: 'support:fault:abc', can_tell: true }, error: null }); },
    { channel: 'email', caseKey: 'email:0a1b2c', message: 'the upload button does nothing', email: 'Owner@Firm.AE', lang: 'en', audience: 'supplier' });
  assertEquals(ok, { filed: true, reason: undefined, issueKey: 'support:fault:abc', canTell: true });
  assertEquals(rpcs[0][0], 'fn_support_hands_it_a_fault');
  assertEquals(rpcs[0][1].p_email, 'owner@firm.ae');
  assertEquals(rpcs[0][1].p_channel, 'email');
  assertEquals((rpcs[0][1].p_turns as unknown[]).length, 1);
  const err = await handFaultToIt(() => Promise.resolve({ data: null, error: { message: 'permission denied' } }), { channel: 'widget', caseKey: 'widget:aa', message: 'x' });
  assertEquals(err.filed, false);
  assertMatch(String(err.reason), /permission denied/);
  const threw = await handFaultToIt(() => { throw new Error('socket closed'); }, { channel: 'widget', caseKey: 'widget:aa', message: 'x' });
  assertEquals(threw.filed, false);
  assertMatch(String(threw.reason), /socket closed/);
});

// the reasoned reading: the MODEL chooses site_fault (ruling 1663), code only checks the choice and hands it over
function deps(choice: string) {
  const rpcs: Rpc[] = []; const calls: Phase[] = [];
  const d: ThinkDeps = {
    gate: () => Promise.resolve({ allowed: true } as never),
    llm: (phase) => { calls.push(phase);
      return Promise.resolve({ content: J({ answer: 'read', reasoning: ['they say the code never arrived'], cited: [], confidence: 0.9, decision: { choice } }), model: 'stub/a' } as LlmReply); },
    embed: () => Promise.resolve([0.1, 0.2]),
    rpc: (fn, args) => { rpcs.push([fn, args]);
      if (fn === 'fn_support_hands_it_a_fault') return Promise.resolve({ data: { filed: true, issue_key: 'support:fault:x' }, error: null });
      if (fn === 'fn_case_recall') return Promise.resolve({ data: { cases: [] }, error: null });
      if (fn === 'fn_reason_retrieve') return Promise.resolve({ data: [], error: null });
      return Promise.resolve({ data: 1, error: null }); },
  };
  return { d, rpcs, calls };
}

Deno.test('site_fault is an option of the reading, and only the model\'s choice of it hands the fault over', async () => {
  assert(NEEDS_PERSON_OPTIONS.some((o) => o.id === 'site_fault'));
  const fault = { channel: 'widget' as const, caseKey: 'widget:0f0f', lang: 'en' as const, audience: 'visitor' as const };
  const f = deps('site_fault');
  const r = await needsAPerson(f.d, { seat: 'customer_support', surface: 'site_assistant.person', message: 'I never got the sign-in code', audience: 'visitor', fault });
  assertEquals(r.value, false, 'a fault is not a request for a person');
  assertEquals(r.fault, true);
  assertEquals(f.rpcs.filter(([fn]) => fn === 'fn_support_hands_it_a_fault').length, 1);
  const p = deps('needs_a_person');
  const rp = await needsAPerson(p.d, { seat: 'customer_support', surface: 'site_assistant.person', message: 'I want to speak to a manager', audience: 'visitor', fault });
  assertEquals(rp.value, true);
  assertEquals(p.rpcs.filter(([fn]) => fn === 'fn_support_hands_it_a_fault').length, 0, 'a request for a person is not a fault');
  const n = deps('site_fault');
  await needsAPerson(n.d, { seat: 'customer_support', surface: 'wa_inbound.needs_a_person', message: 'the page errors' });
  assertEquals(n.rpcs.filter(([fn]) => fn === 'fn_support_hands_it_a_fault').length, 0, 'a surface that gives no case files nothing');
});
