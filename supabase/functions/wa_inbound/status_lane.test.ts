// The WhatsApp status lane (status_lane.ts; ruling 1571, 10 Nov 2026). No network, no paid call. Fails on the parent of this
// change: every status, invoice-copy and code ask was worded on conversation_reply (Sonnet 5.5) with the company brief, USD 0.0118
// a reply (ai_cost_log, 10 Nov), and a new job asked on WhatsApp got no link to the request chat.
import { assert, assertEquals } from 'jsr:@std/assert';
import { APP_INTENTS, laneMust, laneOf, STATUS_CLASS, STATUS_INTENTS, STATUS_RULES } from './status_lane.ts';
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
    taskClass: STATUS_CLASS, briefInPrompt: false, laneRules: STATUS_RULES, must: ['#1043'] });
  assert(said.text.includes('#1043'));
  assertEquals(calls[0].o.taskClass, 'status_reply');
  assertEquals(calls[0].o.sysShared, undefined, 'no company brief on the status lane');
  assert(calls[0].system.includes(WA_RULES + ' ' + STATUS_RULES), 'the lane rules follow the WhatsApp rules');
  // the full path is unchanged: conversation_reply with the brief
  calls.length = 0;
  await modelSays(deps, { audience: 'customer', lang: 'en', message: 'how does it work?', situation: 'x' });
  assertEquals(calls[0].o.taskClass, 'conversation_reply');
  assert(calls[0].o.sysShared, 'the full path carries the brief');
});

Deno.test('general_turn sends a status or app ask down its lane and everything else down the full path', async () => {
  const src = await Deno.readTextFile(new URL('./general_turn.ts', import.meta.url));
  assert(/const lane = laneOf\(routedIntent, needsPerson === true \|\| route\?\.needs_a_person === true\);/.test(src));
  assert(/lane === 'conversation' \? await say\(situation\)\s*: await t\.sayLane\(lane, lean, String\(route\?\.deterministic_reply \|\| ''\)\)/.test(src));
});
