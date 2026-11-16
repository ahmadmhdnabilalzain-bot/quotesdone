// A fault reported at one door is on the person's case, so every other door sees where its repair stands (16 Nov 2026, founder
// ledgers 1711-1713; WHO_KNOWS_WHAT item 8). Stubbed database: no network, no model. The SQL half (the link and the timeline's
// 'it_fault' branch) is proved by scripts/sql/every_door_and_the_ceo_read_the_same_case_probe.sql on the local database.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { handFaultToIt, type Rpc } from './support_fault_handover.ts';

type Call = [string, Record<string, unknown>];
const filed = (calls: Call[], link: (args: Record<string, unknown>) => Promise<{ data?: unknown; error?: { message?: string } | null }> =
  () => Promise.resolve({ data: { linked: true, case_ref: 'QD-S-ABC123' }, error: null })): Rpc => (fn, args) => {
  calls.push([fn, args]);
  if (fn === 'fn_support_hands_it_a_fault') return Promise.resolve({ data: { filed: true, issue_key: 'support:fault:0123456789abcdef', can_tell: false }, error: null });
  if (fn === 'fn_support_case_links_a_fault') return link(args);
  return Promise.resolve({ data: null, error: { message: 'unexpected ' + fn } });
};

Deno.test('a WhatsApp fault goes onto his case by his number, and the IT report still carries no number', async () => {
  const calls: Call[] = [];
  const r = await handFaultToIt(filed(calls), { channel: 'whatsapp', caseKey: 'whatsapp:0a1b2c3d', message: 'the upload button does nothing',
    audience: 'customer', person: { phone: 'whatsapp:+971501234567' } });
  assertEquals(r.filed, true);
  assert(r.linking, 'the link is started when the surface knows the person');
  assertEquals(await r.linking, { linked: true, caseRef: 'QD-S-ABC123', reason: undefined });
  const [hand, link] = calls;
  assertEquals(hand[0], 'fn_support_hands_it_a_fault');
  assertEquals(JSON.stringify(hand[1]).includes('501234567'), false, 'the number never reaches the IT engineer: ' + JSON.stringify(hand[1]));
  assertEquals(link[0], 'fn_support_case_links_a_fault');
  assertEquals(link[1], { p_party_kind: 'customer', p_party_id: null, p_email: null, p_phone: 'whatsapp:+971501234567',
    p_issue_key: 'support:fault:0123456789abcdef', p_channel: 'whatsapp' });
});

Deno.test('a signed-in widget fault is linked by the account, an e-mail fault by the sender', async () => {
  const calls: Call[] = [];
  const w = await handFaultToIt(filed(calls), { channel: 'widget', caseKey: 'widget:aa', message: 'error on upload', audience: 'supplier',
    email: 'Owner@Firm.AE', person: { partyId: '4242', email: 'Owner@Firm.AE' } });
  await w.linking;
  const e = await handFaultToIt(filed(calls), { channel: 'email', caseKey: 'email:bb', message: 'the page is blank', audience: 'customer',
    person: { email: 'buyer@example.ae' } });
  await e.linking;
  const links = calls.filter(([fn]) => fn === 'fn_support_case_links_a_fault').map(([, a]) => a);
  assertEquals(links.map((a) => [a.p_party_kind, a.p_party_id, a.p_email, a.p_phone, a.p_channel]),
    [['supplier', '4242', 'owner@firm.ae', null, 'widget'], ['customer', null, 'buyer@example.ae', null, 'email']]);
});

Deno.test('no person, no filed report, or no identity: nothing is linked', async () => {
  const calls: Call[] = [];
  const anon = await handFaultToIt(filed(calls), { channel: 'widget', caseKey: 'widget:cc', message: 'broken' });
  assertEquals('linking' in anon, false, 'an anonymous visitor has no case to put it on');
  const empty = await handFaultToIt(filed(calls), { channel: 'widget', caseKey: 'widget:dd', message: 'broken', person: { email: 'not an address', phone: '12' } });
  assertEquals('linking' in empty, false);
  const notFiled: Rpc = (fn, args) => { calls.push([fn, args]); return Promise.resolve({ data: { filed: false, reason: 'a demo report is not filed (ruling 1199)' }, error: null }); };
  const demo = await handFaultToIt(notFiled, { channel: 'whatsapp', caseKey: 'whatsapp:ee', message: 'broken', person: { phone: '+971501234567' } });
  assertEquals('linking' in demo, false, 'a report that was not filed links nothing');
  assertEquals(calls.filter(([fn]) => fn === 'fn_support_case_links_a_fault').length, 0);
});

Deno.test('the link never holds the hand-over and never throws', async () => {
  const calls: Call[] = [];
  let release!: () => void;
  const slow = filed(calls, () => new Promise((res) => { release = () => res({ data: { linked: true, case_ref: 'QD-S-LATE01' }, error: null }); }));
  const t0 = performance.now();
  const r = await handFaultToIt(slow, { channel: 'whatsapp', caseKey: 'whatsapp:ff', message: 'broken', audience: 'customer', person: { phone: '+971501234567' } });
  const ms = performance.now() - t0;
  assert(ms < 50, 'the hand-over answered while its link was still pending: ' + ms.toFixed(1) + ' ms');
  assertEquals(r.filed, true);
  release();
  assertEquals((await r.linking!)?.caseRef, 'QD-S-LATE01');
  const failing = await handFaultToIt(filed([], () => Promise.resolve({ data: null, error: { message: 'function does not exist' } })),
    { channel: 'email', caseKey: 'email:gg', message: 'broken', person: { email: 'a@b.ae' } });
  assertMatch(String((await failing.linking!)?.reason), /does not exist/);
  const throwing = await handFaultToIt(filed([], () => { throw new Error('socket closed'); }),
    { channel: 'email', caseKey: 'email:hh', message: 'broken', person: { email: 'a@b.ae' } });
  assertEquals((await throwing.linking!)?.linked, false);
  assertEquals(throwing.filed, true, 'a failed link leaves the hand-over filed');
});

Deno.test('the three doors that hand a fault over pass the person they already know', async () => {
  const src = (p: string) => Deno.readTextFile(new URL(p, import.meta.url));
  assertMatch(await src('../wa_inbound/classification.ts'), /handFaultToIt\([\s\S]{0,700}person: \{ phone: From \}/);
  assertMatch(await src('../site_assistant/index.ts'), /fault: \{ channel: 'widget'[\s\S]{0,700}person: \{ partyId: String\(who\.id\), email: who\.email/);
  assertMatch(await src('../email_triage/index.ts'), /fault: \{ channel: 'email'[\s\S]{0,700}person: \{ email: String\(m\.from_email/);
});
