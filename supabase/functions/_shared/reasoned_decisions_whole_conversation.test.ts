// The intake's two readings see the whole conversation (reasoned_decisions.ts tradeOf / statedSpecs, 10 Nov 2026, ledger
// 1572): they sent its first 4,000 characters, so an answer given late in a long chat never reached them. No network.
// Run: deno test --no-lock --node-modules-dir=none supabase/functions/_shared/reasoned_decisions_whole_conversation.test.ts
import { assert } from 'jsr:@std/assert@1';
import { newest, statedSpecs, tradeOf } from './reasoned_decisions.ts';

const early = 'I need a partition clad. ' + 'We talked about many other things. '.repeat(200);   // ~7,000 characters before the answer
const late = 'The finish I want is PVC wall panels in light oak.';
const conversation = early + late;

// deno-lint-ignore no-explicit-any
function capture(): { deps: any; inputs: string[] } {
  const inputs: string[] = [];
  return { inputs, deps: { gate: () => Promise.resolve(null), embed: () => Promise.resolve(null), rpc: () => Promise.resolve({ data: null, error: null }),
    llm: (_p: string, _s: string, input: string) => { inputs.push(input); return Promise.resolve({ content: '{}', model: 'm' }); } } };
}

Deno.test('the spec reader is given the late answer (it read only the first 4,000 characters)', async () => {
  const c = capture();
  await statedSpecs(c.deps, { conversation, category: 'wallpaper', fields: [{ key: 'finish', question: 'the finish' }] }).catch(() => null);
  assert(c.inputs.length > 0, 'no model call was made');
  assert(c.inputs.some((i) => i.includes('PVC wall panels in light oak')), 'the late answer never reached the reader');
});

Deno.test('the trade reading is given the late part too, and the question carries the newest text', async () => {
  const c = capture();
  await tradeOf(c.deps, { conversation, candidates: [{ slug: 'wallpaper', label: 'wallpaper' }, { slug: 'painting', label: 'painting' }] }).catch(() => null);
  assert(c.inputs.some((i) => i.includes('PVC wall panels in light oak')), 'the late answer never reached the trade reading');
  assert(newest(conversation).endsWith(late) && newest(conversation).length === 4000);
  assert(newest('short') === 'short');
});
