// The WhatsApp status lane (status_lane.ts; ruling 1571, 10 Nov 2026). No network, no paid call. Fails on the parent of this
// change: every status, invoice-copy and code ask was worded on conversation_reply (Sonnet 5.5) with the company brief, USD 0.0118
// a reply (ai_cost_log, 10 Nov), and a new job asked on WhatsApp got no link to the request chat.
import { assert, assertEquals } from 'jsr:@std/assert';
import { APP_INTENTS, laneMust, laneOf, STATUS_CLASS, STATUS_EFFORT, STATUS_INTENTS, STATUS_RULES } from './status_lane.ts';
import { modelSays, WA_RULES } from './model_says.ts';
import type { LlmReply, ThinkDeps } from '../_shared/think.ts';

Deno.test('the lane follows the reasoned intent; a person needed always takes the full path', () => {
  for (const i of ['my_status', 'my_documents', 'my_quotes', 'my_requests', 'my_jobs', 'by_id', 'invoice_copy', 'verification_code']) {
    assertEquals(laneOf(i, false), 'status', i);
    assertEquals(laneOf(i, true), 'conversation', i + ' with a person needed');
  }
  assertEquals(laneOf('new_request', false), 'app');
  for (const i of ['pricing', 'how_it_works', 'change_request', 'cancel_request', 'contact_human', 'none', null, undefined]) assertEquals(laneOf(i, false), 'conversation', String(i));
  assertEquals(STATUS_INTENTS.size, 8);
  assertEquals([...APP_INTENTS], ['new_request']);
});

Deno.test('the must-carry: the request chat link for a new job, the database answer\'s references for a status', () => {
  assertEquals(laneMust('app', '', 'en'), ['https://quotesdone.com/me?new=1']);
  assertEquals(laneMust('app', '', 'ar'), ['https://quotesdone.com/ar/me?new=1']);
  assertEquals(laneMust('status', 'Request #1043 has 2 quotes; Job 2210 is awarded. #1043 again.', 'en'), ['#1043', 'Job 2210']);
  assertEquals(laneMust('status', 'You have 3 quote(s) with us.', 'en'), [], 'a count is not a reference');
  assertEquals(laneMust('conversation', '#1043', 'en'), []);
});

Deno.test('the status rules forbid stating a state the facts do not state (eval A run 2)', () => {
  assert(/Never say that a report is ready, a request is complete, a quote is accepted or anything has been sent unless the facts say so/.test(STATUS_RULES));
});

Deno.test('a lane reply runs on status_reply, without the brief, with the lane rules after the WhatsApp rules', async () => {
  const calls: { system: string; o: Record<string, unknown> }[] = [];
  const deps = {
    gate: () => Promise.resolve(null), embed: () => Promise.resolve(null),
    llm: (_p: string, system: string, _i: string, o: Record<string, unknown>) => {
      calls.push({ system, o });
      return Promise.resolve({ content: JSON.stringify({ answer: 'Request #1043 has two quotes so far, and you can compare them in My requests.', escalate: false }), model: 'openai/gpt-6-luna-pro' } as LlmReply);
    },
    rpc: (fn: string) => Promise.resolve({ data: fn === 'fn_company_context' ? { block: 'REVEAL FEE: 3%.' } : fn === 'fn_ai_route' ? { model: 'openai/gpt-6-luna-pro' } : null, error: null }),
  } as unknown as ThinkDeps;
  const said = await modelSays(deps, { audience: 'customer', lang: 'en', message: 'any quotes on my request?', situation: 'OUR DATABASE ANSWER: Request #1043 has 2 quotes.',
    taskClass: STATUS_CLASS, briefInPrompt: false, laneRules: STATUS_RULES, must: ['#1043'], effort: STATUS_EFFORT });
  assert(said.text.includes('#1043'));
  assertEquals(calls[0].o.taskClass, 'status_reply');
  assertEquals(calls[0].o.effort, 'medium', 'a status answer is a conversation: medium until the side-by-side proves low (ruling 1630, effort_policy.ts)');
  assertEquals(calls[0].o.sysShared, undefined, 'no company brief on the status lane');
  assert(calls[0].system.includes(WA_RULES + ' ' + STATUS_RULES), 'the lane rules follow the WhatsApp rules');
  // the full path is unchanged: conversation_reply with the brief
  calls.length = 0;
  await modelSays(deps, { audience: 'customer', lang: 'en', message: 'how does it work?', situation: 'x' });
  assertEquals(calls[0].o.taskClass, 'conversation_reply');
  assert(calls[0].o.sysShared, 'the full path carries the brief');
  assertEquals(calls[0].o.effort, 'medium', 'the full path is a conversation: medium (ruling 1630)');
  calls.length = 0;
  await modelSays(deps, { audience: 'customer', lang: 'en', message: 'You quoted the wrong price and I want a refund', situation: 'x' });
  assertEquals(calls[0].o.effort, 'high', 'a refund or a price challenge gets the deeper thinking (ruling 1630)');
});

Deno.test('general_turn sends a status or app ask down its lane and everything else down the full path', async () => {
  const src = await Deno.readTextFile(new URL('./general_turn.ts', import.meta.url));
  assert(/const lane = laneOf\(routedIntent, needsPerson === true \|\| route\?\.needs_a_person === true\);/.test(src));
  assert(/lane === 'conversation' \? await say\(situation\)\s*: await t\.sayLane\(lane, lean, String\(route\?\.deterministic_reply \|\| ''\)\)/.test(src));
  const say = await Deno.readTextFile(new URL('./say.ts', import.meta.url));
  assert(/lane \? \{ taskClass: STATUS_CLASS, briefInPrompt: false, laneRules: STATUS_RULES, effort: STATUS_EFFORT \}/.test(say), 'the lane asks at STATUS_EFFORT');
});

// Final audit 12 Nov 2026, W5: the app and status lanes answered a policy question "I can't confirm" (2 of 2) while the
// conversation lane answered it from the brief. A lane draft that declines is not the reply: general_turn asks the full path.
// The sentences are the production replies of run 71366940 (scratchpad audit/whatsapp out_A, out_B). Fails on main (no laneDeclines).
Deno.test('a lane reply that cannot confirm a policy answer goes to the full path; a refusal to share an identity is not that', async () => {
  const { laneDeclines } = await import('./status_lane.ts');
  for (const d of ["Posting your request is free. I don’t have a confirmed timeframe for receiving quotes or a set number of quotes you’ll see.",
    "I can't confirm how long quotes will take or how many you'll receive.", 'I don’t have a confirmed number of quotes you’ll receive for the windows job.',
    'وعليكم السلام. ما عندي سعر تقديري موثوق لصيانة المكيف؛ التكلفة تعتمد على نوع المكيف والعطل.']) assert(laneDeclines(d), d);
  for (const k of ['Request 165435 (aluminium, Dubai) has been sent to 0 suppliers, and no quotes have been received yet.',
    'I can’t share other suppliers’ identities or what they charged.', "I can't share the customer's name or mobile number.",
    "I can't promise a refund: every refund is decided by the CEO."]) assert(!laneDeclines(k), k);
  const turn = Deno.readTextFileSync(new URL('./general_turn.ts', import.meta.url));
  assert(/if \(lane !== 'conversation' && reply && laneDeclines\(reply\)\) \{[\s\S]{0,120}await say\(situation\)/.test(turn), 'general_turn asks the full path');
});
