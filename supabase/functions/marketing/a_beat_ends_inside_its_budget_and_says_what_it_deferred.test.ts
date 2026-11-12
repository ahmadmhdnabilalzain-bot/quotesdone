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

// EVERY MODEL CALL OF EVERY DUTY IS BOUNDED BY THE BEAT (second review, 12 Nov 2026): blog_article's own client waited 45 s and
// social_comments' think() calls had no deadline, so the last duty could start at 110 s and end at 160 s, past the 150 s wall.
Deno.test('no duty calls a model past the beat: every model client and think() of the duties takes the beat\'s deadline', () => {
  const read = (f: string) => Deno.readTextFileSync(new URL('./duties/' + f, import.meta.url));
  for (const f of ['shared.ts', 'blog_article.ts']) {
    const src = read(f);
    assert(src.includes("const timeoutMs = ctx.deadline ? Math.max(1_000, Math.min(45000, ctx.deadline - Date.now())) : 45000;"), f + ' has a model client the beat does not bound');
    assert(!/timeoutMs: 45000/.test(src), f + ' still waits a fixed 45 s');
  }
  const social = read('social_comments.ts');
  assert(social.includes("const reasonDeps = () => deadline ? withDeadline(defaultDeps(admin, 'marketing'), deadline) : defaultDeps(admin, 'marketing');"));
  assertEquals((social.match(/defaultDeps\(admin, 'marketing'\)/g) ?? []).length, 2, 'a think() call of social_comments is not on the beat\'s deadline');
  // and no other duty file builds a model client or think() deps of its own
  for (const f of [...Deno.readDirSync(new URL('./duties/', import.meta.url))].map((e) => e.name).filter((n) => n.endsWith('.ts') && !n.endsWith('.test.ts'))) {
    const src = read(f);
    if (f === 'shared.ts' || f === 'blog_article.ts' || f === 'social_comments.ts') continue;
    assert(!/makeLlmRich\(|defaultDeps\(admin/.test(src) || f === 'trends_geo.ts', f + ' calls a model without the beat');
  }
});
