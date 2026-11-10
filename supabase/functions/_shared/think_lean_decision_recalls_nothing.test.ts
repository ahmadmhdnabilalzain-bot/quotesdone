// think(): a lean choice among fixed options for an external audience opens its judgement row but recalls nothing (it_engineer,
// 10 Nov 2026, WhatsApp latency R4/R5): another party's case never reaches an external prompt and an empty plan retrieves nothing,
// so the embedding, the space read, the recall and the handoff reads were round trips ahead of the one model call. No network.
// Red before: fn_case_recall (and the embedding) ran ahead of the decision.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { think, type LlmReply, type ThinkDeps } from './think.ts';

function mock() {
  const rpcs: string[] = []; let embeds = 0;
  const deps = {
    gate: () => Promise.resolve(null),
    llm: () => Promise.resolve({ content: JSON.stringify({ answer: 'read', reasoning: [], cited: [], asked_back: null, decision: { choice: 'none' } }), model: 'stub' } as LlmReply),
    embed: () => { embeds++; return Promise.resolve([0.1, 0.2]); },
    rpc: (fn: string) => { rpcs.push(fn); return Promise.resolve({ data: fn === 'fn_judgement_record' ? 41 : fn.startsWith('fn_case_recall') ? { cases: [] } : [], error: null }); },
  } as unknown as ThinkDeps;
  return { deps, rpcs, embeds: () => embeds };
}
const ask = (audience: string, lean: boolean) => ({ seat: 'customer_support' as const, surface: 'wa_inbound.intent_table', question: 'ZZ DEMO hi',
  context: { audience } as never, decision: { name: 'q', options: [{ id: 'none', meaning: 'none' }, { id: 'x', meaning: 'x' }] }, plan: { steps: [] }, lean });

Deno.test('a lean fixed-option decision for a customer or supplier: no recall, no embedding, the judgement still opened', async () => {
  for (const audience of ['customer', 'supplier']) {
    const m = mock();
    const r = await think(m.deps, ask(audience, true));
    assertEquals(r.status, 'answered');
    assertEquals(m.rpcs.filter((f) => /recall|retrieve|handoff/.test(f)), [], m.rpcs.join(','));
    assertEquals(m.embeds(), 0);
    assert(m.rpcs.includes('fn_judgement_record'), 'the learning loop row is still opened');
  }
});

Deno.test('known-good control: the founder, or a decision that is not lean, still recalls', async () => {
  for (const [audience, lean] of [['founder', true], ['customer', false]] as const) {
    const m = mock();
    await think(m.deps, ask(audience, lean));
    assert(m.rpcs.some((f) => f.startsWith('fn_case_recall')), audience + ' lean=' + lean + ': ' + m.rpcs.join(','));
  }
});
