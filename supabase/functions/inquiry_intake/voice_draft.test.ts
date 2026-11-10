// The request chat's voice: its own class, no company brief, and EVERY turn (it_engineer, 10 Nov 2026; rulings 1571, 1572).
// Stubbed gateway and database; no network, no paid call. Fails on the parent of this change: intakeVoice sent
// conversation.slice(-12) on conversation_reply with the ~35k-token brief, so an answer given at message 2 of a 30-message
// intake was not in the call, and every voice call paid Sonnet 5.5 for the brief.
import { assert, assertEquals } from 'jsr:@std/assert';
import { intakeVoice, VOICE_CLASS } from './slots.ts';
import type { LlmReply, ThinkDeps } from '../_shared/think.ts';

const A = (answer: string) => JSON.stringify({ answer });
function stub(answers: (string | null)[]) {
  const calls: { system: string; input: string; o: Record<string, unknown> }[] = [];
  const deps = {
    gate: () => Promise.resolve(null), embed: () => Promise.resolve(null),
    llm: (_p: string, system: string, input: string, o: Record<string, unknown>) => {
      calls.push({ system, input, o }); const a = answers.shift();
      return Promise.resolve((a == null ? { content: null, error: 'gateway_http_503' } : { content: a, model: 'openai/gpt-6-luna-pro' }) as LlmReply);
    },
    rpc: (fn: string) => Promise.resolve({ data: fn === 'fn_company_context' ? { block: 'REVEAL FEE: 3%.' } : fn === 'fn_ai_route' ? { model: 'openai/gpt-6-luna-pro' } : null, error: null }),
  } as unknown as ThinkDeps;
  return { deps, calls };
}

// 30 messages: the ceiling height is given at message 2 and never again.
const conversation = Array.from({ length: 30 }, (_, i) => i === 1
  ? { role: 'user', text: 'The ceiling is 3.2 m high, villa in Al Barsha' }
  : { role: i % 2 ? 'user' : 'assistant', text: i % 2 ? 'ok, noted ' + i : 'Thanks. Next detail ' + i + '?' });

Deno.test('the voice runs on voice_draft, without the brief, and hears message 2 of 30', async () => {
  const s = stub([A('Thanks, noted. How many rooms need the gypsum ceiling?')]);
  const v = await intakeVoice(s.deps, { draft: 'Noted.', lang: 'en', message: 'next', conversation, next: { text: 'How many rooms?' } });
  assertEquals(v.by, 'model');
  assertEquals(s.calls[0].o.taskClass, VOICE_CLASS);
  assertEquals(VOICE_CLASS, 'voice_draft');
  assertEquals(s.calls[0].o.sysShared, undefined, 'no company brief rides with the voice');
  assertEquals(s.calls[0].o.sysStable, undefined);
  const history = s.calls[0].o.history as { role: string; content: string }[];
  assertEquals(history.length, 30, 'every turn is sent, not the last 12');
  assert(history.some((t) => t.content.includes('3.2 m')), 'the fact given at message 2 is in the call');
  assert(s.calls[0].system.includes('You do NOT have the company brief'), 'the brief-less rules apply');
});

Deno.test('the voice still falls back to the drafted sentence only in an outage', async () => {
  const s = stub([null, null, null, null]);
  const v = await intakeVoice(s.deps, { draft: 'Noted.', lang: 'en', message: 'next', conversation: [] });
  assertEquals([v.by, v.text, v.outage], ['outage_fallback', 'Noted.', true]);
});
