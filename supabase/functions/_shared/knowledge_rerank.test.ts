// The knowledge rerank (12 Oct 2026, it_engineer): the model may only reorder what retrieval found, and any failure keeps
// the fused order. These replay the cases that decide it. No network.
import { assertEquals } from 'jsr:@std/assert';
import { applyRanking, rerankInput, EXCERPT, RERANK_TOP } from './knowledge_rerank.ts';
import { think, type ThinkDeps } from './think.ts';

const C = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];

Deno.test('the model\'s picks come first, then the rest in fused order', () => {
  assertEquals(applyRanking(C, '{"ranking":[3,1,7]}'), { order: ['c', 'a', 'g', 'b', 'd', 'e', 'f'], reranked: true });
});

Deno.test('a malformed, empty or out-of-range reply keeps the fused order: nothing added, nothing dropped', () => {
  for (const reply of [null, '', 'not json', '{"ranking":[]}', '{"ranking":[0,99,-1]}', '{"other":[1]}']) {
    assertEquals(applyRanking(C, reply), { order: C, reranked: false });
  }
  const r = applyRanking(C, '```json\n{"ranking":[2,2,2,5,1,4,6,7]}\n```');
  assertEquals(r.order, ['b', 'e', 'a', 'd', 'f', 'c', 'g']);   // duplicates removed, at most RERANK_TOP picks
  assertEquals(r.order.length, C.length);
  assertEquals(RERANK_TOP, 5);
});

Deno.test('the prompt cuts each candidate to EXCERPT characters and numbers them from 1', () => {
  const t = rerankInput('ما الرولمانات المتوفرة؟', [{ title: 'T1', excerpt: 'x'.repeat(5000) }, { title: 'T2', excerpt: 'short' }]);
  assertEquals(t.split('\n')[3].length <= 3 + 2 + 3 + EXCERPT + 5, true);
  assertEquals(t.includes('1. T1'), true);
  assertEquals(t.includes('2. T2 — short'), true);
});

function deps(rerankReply: string | null) {
  const rpcs: [string, Record<string, unknown>][] = [];
  const llmCalls: string[] = [];
  const inputs: Record<string, string> = {};
  const J = JSON.stringify;
  const rows = Array.from({ length: 8 }, (_, i) => ({ source: 'sales_knowledge', id: 'r' + (i + 1), title: 't' + (i + 1), excerpt: 'e', similarity: 0.9 - i / 100, trust: 'reviewed' }));
  const d: ThinkDeps = {
    gate: () => Promise.resolve({ allowed: true } as never),
    llm: (phase, _sys, input) => {
      llmCalls.push(phase); inputs[phase] ??= input;
      if (phase === 'rerank') return Promise.resolve({ content: rerankReply, model: 'm' });
      return Promise.resolve({ content: phase === 'decompose' ? J({ steps: [{ id: 's1', goal: 'g', query: 'which bearings are sold' }], facts: [] })
        : phase === 'verify' ? J({ verdict: 'agree', problems: [] }) : J({ answer: 'a', reasoning: [], cited: [], confidence: 0.9 }), model: 'm' });
    },
    embed: (_t, s) => Promise.resolve([s === 'ml' ? 0.9 : 0.1, 0.2]),
    rpc: (fn, args) => { rpcs.push([fn, args]); return Promise.resolve({ data: fn.startsWith('fn_case_recall') ? { cases: [] } : fn === 'fn_reason_retrieve_ml' ? rows : [], error: null }); },
    space: () => Promise.resolve('ml'),
  };
  // the order the sources reach the synthesis prompt
  const order = () => [...String(inputs.synthesise ?? '').matchAll(/sales_knowledge:r[0-9]+/g)].map((m) => m[0]).filter((x, i, a) => a.indexOf(x) === i);
  return { d, rpcs, llmCalls, order };
}

Deno.test('ml space: think asks for 20 candidates and the rerank reorders them before they become sources', async () => {
  const m = deps('{"ranking":[8,7]}');
  await think(m.d, { seat: 'sales_engineer', surface: 'think.answer', question: 'which bearings are sold in the UAE?' });
  assertEquals(m.rpcs.find(([f]) => f === 'fn_reason_retrieve_ml')![1].p_k, 10);
  assertEquals(m.llmCalls.includes('rerank'), true);
  assertEquals(m.order().slice(0, 3), ['sales_knowledge:r8', 'sales_knowledge:r7', 'sales_knowledge:r1']);
});

Deno.test('ml space: a failed rerank keeps the fused order and the answer still comes', async () => {
  const m = deps(null);
  const r = await think(m.d, { seat: 'sales_engineer', surface: 'think.answer', question: 'which bearings are sold in the UAE?' });
  assertEquals(m.order().slice(0, 2), ['sales_knowledge:r1', 'sales_knowledge:r2']);
  assertEquals(typeof r.answer, 'string');
});
