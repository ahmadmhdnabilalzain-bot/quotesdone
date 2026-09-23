// A vector is only ever put to the routine of its own space. Seat: it_engineer. 23 Sep 2026.
// gte-small and multilingual-e5-small are both 384-d, so nothing in Postgres would refuse a gte vector sent to
// an ml routine — it would just rank nonsense. These replay the three cases that decide it. No network.
import { assertEquals } from 'jsr:@std/assert';
import { think, type EmbedSpace, type ThinkDeps } from './think.ts';
import { rowText, TEXT_CUT } from './ml_embed_recipe.ts';

const J = JSON.stringify;
function deps(space: EmbedSpace | undefined, mlWorks: boolean) {
  const rpcs: [string, Record<string, unknown>][] = [];
  const embeds: (EmbedSpace | undefined)[] = [];
  const d: ThinkDeps = {
    gate: () => Promise.resolve({ allowed: true } as never),
    llm: (phase) => Promise.resolve({ content: phase === 'decompose' ? J({ steps: [{ id: 's1', goal: 'g', query: 'ما هو حد التسجيل لضريبة القيمة المضافة' }], facts: [] })
      : phase === 'verify' ? J({ verdict: 'agree', problems: [] }) : J({ answer: 'a', reasoning: [], cited: [], confidence: 0.9 }), model: 'm' }),
    embed: (_t, s) => { embeds.push(s); return Promise.resolve(s === 'ml' && !mlWorks ? null : [s === 'ml' ? 0.9 : 0.1, 0.2]); },
    rpc: (fn, args) => { rpcs.push([fn, args]); return Promise.resolve({ data: fn.startsWith('fn_case_recall') ? { cases: [] } : [], error: null }); },
    ...(space ? { space: () => Promise.resolve(space) } : {}),
  };
  return { d, rpcs, embeds };
}
const called = (rpcs: [string, unknown][]) => rpcs.map(([f]) => f).filter((f) => /recall|retrieve/.test(f));

Deno.test('ml space: the question and every step are embedded multilingual and read by the _ml routines', async () => {
  const m = deps('ml', true);
  await think(m.d, { seat: 'accountant', surface: 'think.answer', question: 'متى يستحق إقرار ضريبة الشركات؟' });
  assertEquals(called(m.rpcs), ['fn_case_recall_ml', 'fn_reason_retrieve_ml']);
  assertEquals(m.rpcs.find(([f]) => f === 'fn_case_recall_ml')![1].p_embedding, '[0.9,0.2]');
  // the fused search gets both vectors, each from its own model
  const r = m.rpcs.find(([f]) => f === 'fn_reason_retrieve_ml')![1];
  assertEquals([r.p_embedding, r.p_embedding_gte], ['[0.9,0.2]', '[0.1,0.2]']);
});

Deno.test('ml space but the multilingual embedder fails: gte vector, gte routines — never a gte vector to an _ml routine', async () => {
  const m = deps('ml', false);
  await think(m.d, { seat: 'accountant', surface: 'think.answer', question: 'when is the CT return due?' });
  assertEquals(called(m.rpcs), ['fn_case_recall', 'fn_reason_retrieve']);
  for (const [, a] of m.rpcs.filter(([f]) => /recall|retrieve/.test(f))) assertEquals(a.p_embedding, '[0.1,0.2]');
});

Deno.test('no space dependency (every existing caller and test): gte, exactly as before', async () => {
  const m = deps(undefined, true);
  await think(m.d, { seat: 'ceo', surface: 'think.answer', question: 'are we on track?' });
  assertEquals(called(m.rpcs), ['fn_case_recall', 'fn_reason_retrieve']);
  assertEquals(m.embeds.includes('ml'), false);
});

Deno.test('a knowledge row is one text: title, newline, body, cut where gte-small is cut', () => {
  assertEquals(rowText('T', 'one'), 'T\none');
  assertEquals(rowText(null, 'body'), 'body');
  assertEquals(rowText('T', 'x'.repeat(5000)).length, TEXT_CUT);
});
