// tradeOfText with a MOCKED model (no network, no paid call): exact trade or none, and held means null, never a word.
//   deno test --no-lock --allow-read=. supabase/functions/_shared/reasoned_trades.test.ts
import { assert, assertEquals } from 'jsr:@std/assert';
import { NONE, tradeOfText } from './reasoned_trades.ts';
import type { ThinkDeps } from './think.ts';

const PLAN = JSON.stringify({ steps: [{ id: 's1', goal: 'what work is this', query: 'q', needs_knowledge: false }], facts: [] });
export function mockDeps(o: { hold?: boolean; choice?: string }) {
  const rpcs: [string, Record<string, unknown>][] = []; const prompts: string[] = [];
  const deps: ThinkDeps = {
    gate: () => Promise.resolve((o.hold ? { allowed: false, rule: 'founder_hold', held: 1, routes: 8 } : { allowed: false, rule: 'route_not_registered' }) as never),
    llm: (phase, system) => {
      prompts.push(system);
      const content = phase === 'decompose' ? PLAN : JSON.stringify({ answer: 'ZZ reasoning.', reasoning: ['s1: read'], confidence: 0.9, decision: { choice: o.choice } });
      return Promise.resolve({ content, model: 'mock' });
    },
    embed: () => Promise.resolve(null),
    rpc: (fn, args) => { rpcs.push([fn, args]); return Promise.resolve({ data: fn === 'fn_reason_hold' ? 99 : [], error: null }); },
  };
  return { deps, rpcs, prompts };
}
const OPTIONS = [{ slug: 'aluminium', label: 'Aluminium & cladding' }, { slug: 'glass', label: 'Glass & glazing' }];

Deno.test('answered: the reasoned slug, chosen among the real options offered, with none offered beside them', async () => {
  const m = mockDeps({ choice: 'aluminium' });
  const r = await tradeOfText(m.deps, { surface: 'customer_api.keywords', text: '40 aluminium windows, 6-12-6 glass', options: OPTIONS, audience: 'customer' });
  assertEquals(r.value, 'aluminium');
  const synth = m.prompts.find((p) => p.includes('This is a DECISION'))!;
  assert(synth.includes('aluminium (the work or product is exactly Aluminium & cladding)') && synth.includes(NONE + ' (none of the listed trades'));
  assertEquals((await tradeOfText(mockDeps({ choice: NONE }).deps, { surface: 'customer_api.keywords', text: 'bake me a cake', options: OPTIONS, audience: 'customer' })).value, NONE);
});

Deno.test('an invented trade is never taken: think refuses a choice that is not an option, and the value is null', async () => {
  const r = await tradeOfText(mockDeps({ choice: 'windows' }).deps, { surface: 'customer_api.keywords', text: 'windows', options: OPTIONS, audience: 'customer' });
  assertEquals(r.value, null);
  assertEquals(r.result.status, 'held');
});

Deno.test('held: null, filed in the sales engineer queue with its surface, dedupe key and subject — no model is called', async () => {
  const m = mockDeps({ hold: true, choice: 'aluminium' });
  const r = await tradeOfText(m.deps, { surface: 'inbound_email.infer_sector', text: 'we fabricate aluminium', options: OPTIONS, audience: 'supplier',
    dedupeKey: 'lead_sector:7', subject: { lead_id: 7 } });
  assertEquals(r.value, null);
  assertEquals(m.prompts.length, 0);
  const hold = m.rpcs.find(([f]) => f === 'fn_reason_hold')![1];
  assertEquals([hold.p_seat, hold.p_surface, hold.p_dedupe_key, hold.p_subject], ['sales_engineer', 'inbound_email.infer_sector', 'lead_sector:7', { lead_id: 7 }]);
});

Deno.test('discover: held with queueWhenHeld false files nothing (the answer is a live search the customer runs again)', async () => {
  const m = mockDeps({ hold: true });
  const r = await tradeOfText(m.deps, { surface: 'customer_api.resolve_trade', text: 'marble', options: OPTIONS, audience: 'customer', queueWhenHeld: false });
  assertEquals(r.value, null);
  assertEquals(m.rpcs.filter(([f]) => f === 'fn_reason_hold').length, 0);
});
