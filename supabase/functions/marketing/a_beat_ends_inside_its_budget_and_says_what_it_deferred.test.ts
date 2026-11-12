// A BEAT ENDS INSIDE ITS BUDGET AND SAYS WHAT IT DEFERRED (it_engineer, 12 Nov 2026; founder ledger 1642; review of the effort
// fix, finding 1). marketing's duties run in series in one 150 s edge invocation; at high effort one think() answer runs to
// 105 s, so a beat could pass the wall and die with nothing recorded. The beat has MARKETING_BEAT_BUDGET_MS: a duty with
// under DUTY_MIN_START_MS left is not started and is reported as deferred, and the think() and model calls of the duties that
// do run are bounded by the beat's deadline. Offline (twilio_free_harness): no network, no model.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { loadFunction } from '../_shared/twilio_free_harness.ts';
import { think, type LlmReply, type Phase, type ThinkDeps } from '../_shared/think.ts';
import type { GateAnswer } from '../_shared/llm_hold.ts';
import { judgeTrend } from './duties/trends_geo.ts';

await loadFunction('marketing', () => import('./index.ts'));
const { runDuties, MARKETING_BEAT_BUDGET_MS, DUTY_MIN_START_MS } = await import('./index.ts');
const { DUTIES } = await import('./duties.ts');

Deno.test('a beat with its budget spent starts no further duty and lists each as deferred', async () => {
  const t0 = 1_000_000; let calls = 0;
  // the first reading starts the beat; every later one is past its budget less the minimum start
  const now = () => (calls++ === 0 ? t0 : t0 + MARKETING_BEAT_BUDGET_MS - DUTY_MIN_START_MS + 1);
  const r = await runDuties(now);
  const names = DUTIES.map((d) => d.name);
  const deferred = r.deferred as string[];
  assert(deferred.length > 0, JSON.stringify(r).slice(0, 400));
  for (const n of deferred) assert(String((r.results as Record<string, { deferred?: string }>)[n]?.deferred).includes('next beat'), n);
  assertEquals(deferred.every((n) => names.includes(n)), true);
});

Deno.test("a duty's think() run is bounded by the beat's deadline: a spent deadline asks no model", async () => {
  const calls: Phase[] = [];
  const deps: ThinkDeps = {
    gate: () => Promise.resolve({ allowed: true } as unknown as GateAnswer),
    llm: (phase) => { calls.push(phase); return Promise.resolve({ content: '{}', model: 'm' } as LlmReply); },
    embed: () => Promise.resolve([0.1]),
    rpc: () => Promise.resolve({ data: null, error: null }),
  };
  const j = await judgeTrend(deps, { id: 1, title: 'ZZ DEMO headline', url: 'https://example.invalid/zz', source: 'ZZ DEMO feed' }, { plansNothing: true, deadlineAt: Date.now() - 1 });
  assertEquals([j, calls.length], [null, 0], 'a model was asked past the beat');
  // and with no deadline named, an internal run still has one (think/tunables.ts INTERNAL_RUN_DEADLINE_MS)
  const seen: (number | undefined)[] = [];
  const d2: ThinkDeps = { ...deps, llm: (_p, _s, _i, o) => { seen.push(o.timeoutMs); return Promise.resolve({ content: '{}', model: 'm' } as LlmReply); } };
  await think(d2, { seat: 'marketing', surface: 'marketing.zz_demo', question: 'ZZ DEMO?', context: { audience: 'internal' }, plan: { steps: [] } });
  assert(seen.length > 0 && seen.every((t) => (t ?? Infinity) <= 130_000), JSON.stringify(seen));
});
