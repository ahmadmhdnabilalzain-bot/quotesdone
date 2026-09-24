// What a LinkedIn reply means — reasoned with a MOCKED model; no network, no paid call, ZZ DEMO only.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import type { LlmReply, Phase, ThinkDeps } from './think.ts';
import { deliverOutreach, replyClass } from './reasoned_outreach.ts';

const J = (x: unknown) => JSON.stringify(x);
function mock(o: { held?: boolean; choices?: string[] }) {
  const rpcs: [string, Record<string, unknown>][] = []; const inputs: string[] = [];
  const choices = [...(o.choices ?? [])];
  const deps: ThinkDeps = {
    gate: () => Promise.resolve(o.held ? { allowed: false, rule: 'founder_hold' } : { allowed: true, rule: 'ok' }),
    llm: (phase: Phase, _s: string, input: string) => {
      inputs.push(input);
      if (phase === 'decompose') return Promise.resolve({ content: J({ steps: [{ id: 's1', goal: 'read the reply', needs_knowledge: false }], facts: [] }) } as LlmReply);
      return Promise.resolve({ content: J({ answer: 'Read as a whole, in context.', reasoning: ['s1'], decision: { choice: choices.shift() } }) } as LlmReply);
    },
    embed: () => Promise.resolve(null),
    rpc: (fn, args) => { rpcs.push([fn, args]); return Promise.resolve({ data: 5, error: null }); },
  };
  return { deps, rpcs, inputs };
}
const ASK = { sent: 'Hello ZZ-Sara, QuotesDone lets a buyer describe a job once ...', token: 'zz-demo-token', language: 'en' as const };

Deno.test('"not interested" and "interested" are told apart by meaning, not by which list matched first', async () => {
  assertEquals((await replyClass(mock({ choices: ['decline'] }).deps, { ...ASK, reply: 'Thanks, but not interested at the moment.' })).value, 'decline');
  const m = mock({ choices: ['positive'] });
  assertEquals((await replyClass(m.deps, { ...ASK, reply: 'I am not sure yet, but interested - can you share the fee structure?' })).value, 'positive');
  assert(m.inputs[0].includes('QuotesDone lets a buyer'), 'the message the reply answers is part of the reasoning');
});

Deno.test('under the hold: no class, nobody closed, the reply waits in the marketing queue', async () => {
  const m = mock({ held: true });
  const r = await replyClass(m.deps, { ...ASK, reply: 'no thanks' });
  assertEquals([r.value, r.result.status], [null, 'held']);
  const [, a] = m.rpcs.find(([f]) => f === 'fn_reason_hold')!;
  assertEquals([a.p_seat, a.p_surface, a.p_dedupe_key], ['marketing', 'marketing.outreach_reply', 'outreach_reply:zz-demo-token']);
  assertEquals(a.p_subject, { mark_token: 'zz-demo-token' });
});

Deno.test('a class that is not one of the four is refused and held', async () => {
  const r = await replyClass(mock({ choices: ['maybe', 'maybe'] }).deps, { ...ASK, reply: 'hmm' });
  assertEquals(r.value, null);
});

Deno.test('the replay drafts the follow-up in the prospect\'s language and records the class', async () => {
  const log: string[] = [];
  const io = { outreachPage: () => Promise.resolve({ full_name: 'ZZ DEMO سارة', language: 'ar' as const }),
               outreachReasoned: (t: string, c: string, f: string | null) => { log.push(`${t} ${c} ${f}`); return Promise.resolve({ ok: true }); } };
  const res = { status: 'answered' as const, answer: 'x', decision: { choice: 'decline', fields: {} }, steps: [], context_used: {}, missing_context: [], sources: [], confidence: 1 };
  const d = await deliverOutreach({ id: 1, seat: 'marketing', surface: 'marketing.outreach_reply', subject: { mark_token: 'zz-demo-token' }, request: { seat: 'marketing', surface: 'marketing.outreach_reply', question: 'لا شكرا' } }, res, io);
  assertEquals(d?.via, 'outreach_follow_up');
  assert(/^zz-demo-token decline .*لن أعاود التواصل/.test(log[0]), log[0]);
});
