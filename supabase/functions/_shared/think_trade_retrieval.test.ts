// A trade question reads its own trade pack (ceo, 19 Oct 2026; a_trade_question_reads_its_own_trade_pack.sql). The
// routine reserves the trade's rows only when think() names the trade, so every retrieval step must carry p_trade, and
// the planner's kind (by meaning) as p_kind. No network.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import type { GateAnswer } from './llm_hold.ts';
import { ENTRY_KINDS, think, type LlmReply, type ThinkDeps } from './think.ts';

const J = (x: unknown) => JSON.stringify(x);

Deno.test('every retrieval step carries the planned trade and kind, and the planner may name the market file', async () => {
  for (const k of ['uae_market_products', 'uae_market_brands', 'uae_market_sizes']) assert((ENTRY_KINDS as readonly string[]).includes(k), k);
  const sent: Record<string, unknown>[] = [];
  const deps: ThinkDeps = {
    gate: () => Promise.resolve({ allowed: true } as unknown as GateAnswer),
    llm: (phase) => Promise.resolve({ model: 'm', content: phase === 'synthesise' ? J({ answer: 'x', reasoning: [], cited: [], confidence: 0.9 })
      : phase === 'verify' ? J({ verdict: 'agree', problems: [] })
      : J({ steps: [{ id: 's1', goal: 'a', query: 'split AC sizes sold in the UAE', needs_knowledge: true },
                    { id: 's2', goal: 'b', query: 'what a 2 TR unit costs', needs_knowledge: true }],
             facts: [], high_stakes: false, trade: 'hvac', kind: 'uae_market_sizes' }) } as LlmReply),
    embed: () => Promise.resolve([0.1, 0.2, 0.3]),
    rpc: (fn, args) => {
      if (String(fn).startsWith('fn_reason_retrieve')) sent.push(args as Record<string, unknown>);
      return Promise.resolve({ data: String(fn).startsWith('fn_case_recall') ? { cases: [] } : [], error: null });
    },
  };
  await think(deps, { context: { audience: 'customer' }, seat: 'sales_engineer', surface: 'test', question: 'Which AC sizes are sold here?' });
  assert(sent.length >= 2, `retrieval ran once per step at least, got ${sent.length}`);
  for (const a of sent) { assertEquals(a.p_trade, 'hvac'); assertEquals(a.p_kind, 'uae_market_sizes'); }
});
