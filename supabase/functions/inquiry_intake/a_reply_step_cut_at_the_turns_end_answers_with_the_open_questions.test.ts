// A REPLY STEP CUT AT THE TURN'S END ANSWERS WITH THE OPEN QUESTIONS (it_engineer, 12 Nov 2026; founder ledger 1642; review of the
// effort fix, finding 4). Every model step of an intake turn now ends by turn_clock.ts REPLY_END_MS. A held reply that has no time
// left is not left silent and asks nothing already answered: the customer reads the questions still open (heldDraftOf, from
// the request's state). The two reply steps ask the effort that fits their 15 s (effort_policy.ts clock: the held reply at
// medium answered 0 of 8 inside it, low 8 of 8). No network: the model is a stub.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { heldReply, intakeVoice } from './slots.ts';
import type { LlmReply, ThinkDeps } from '../_shared/think.ts';
import type { GateAnswer } from '../_shared/llm_hold.ts';

const CHECKLIST = [
  { key: 'element', question: 'What aluminium work?', required: true, question_plain_en: 'What do you need in aluminium?' },
  { key: 'dimensions_qty', question: 'Sizes and quantity?', required: true, question_plain_en: 'How many pieces, and how big is each one?' },
  { key: 'location', question: 'Which emirate?', required: true, question_plain_en: 'Which emirate and area is it in?' },
];
function stub() {
  const efforts: (string | undefined)[] = [];
  const deps: ThinkDeps = {
    gate: () => Promise.resolve({ allowed: true } as unknown as GateAnswer),
    llm: (_p, _s, _i, o) => { efforts.push(o.effort); return Promise.resolve({ content: JSON.stringify({ answer: 'ZZ DEMO thank you. How many pieces, and how big is each one?' }), model: 'stub/model' } as LlmReply); },
    embed: () => Promise.resolve(null),
    rpc: (fn) => Promise.resolve({ data: fn === 'fn_company_context' ? { block: 'ZZ DEMO company facts.' } : null, error: null }),
  };
  return { deps, efforts };
}

Deno.test('a held reply with no time left before the turn ends lists the questions still open, and only those', async () => {
  const s = stub();
  const r = await heldReply(s.deps, CHECKLIST, ['dimensions_qty', 'location'], 'en', 'ZZ DEMO windows for a villa', [], Date.now() - 1);
  assertEquals(s.efforts.length, 0, 'a model call was started past the turn\'s end');
  assertEquals(r.by, 'outage_fallback');
  assert(r.text.includes('How many pieces, and how big is each one?') && r.text.includes('Which emirate and area is it in?'), r.text);
  assert(!r.text.includes('What do you need in aluminium?'), 'the answered question is asked again: ' + r.text);
});

Deno.test('the held reply and the voice ask the effort that fits the turn (low), not the conversation default', async () => {
  const a = stub();
  await heldReply(a.deps, CHECKLIST, ['location'], 'en', 'ZZ DEMO windows', [], Date.now() + 15_000);
  const b = stub();
  await intakeVoice(b.deps, { draft: 'ZZ DEMO thank you. Which emirate and area is it in?', lang: 'en', message: 'ZZ DEMO windows', conversation: [], deadline: Date.now() + 15_000 });
  assert(a.efforts.length > 0 && b.efforts.length > 0);
  assertEquals([...new Set(a.efforts)], ['low'], 'held reply');
  assertEquals([...new Set(b.efforts)], ['low'], 'voice');
});
