// A request the matcher could not reach is matched again (lib/rematch.ts; customer-journey follow-up, 10 Nov 2026).
//   deno test -A --no-lock --node-modules-dir=none supabase/functions/customer_api/rematch.test.ts
// deno-lint-ignore-file no-explicit-any
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { DEFAULT_REMATCH_BACKOFF_MINUTES, failedState, matcherFindingKey, nextRematch, rematchDue, rematchSchedule, rematchWaiting, type RematchIO } from './lib/rematch.ts';

const T0 = new Date('2026-11-10T08:00:00Z');
const mins = (n: number) => new Date(T0.getTime() + n * 60_000);

Deno.test('the schedule is the decision_policy row, or the default when the row is not a list of positive minutes', () => {
  assertEquals(rematchSchedule([5, 10]), [5, 10]);
  assertEquals(rematchSchedule(null), [...DEFAULT_REMATCH_BACKOFF_MINUTES]);
  assertEquals(rematchSchedule([5, -1]), [...DEFAULT_REMATCH_BACKOFF_MINUTES]);
  assertEquals(rematchSchedule('15'), [...DEFAULT_REMATCH_BACKOFF_MINUTES]);
});

Deno.test('backoff: the n-th failure waits the n-th step; after the last step the request is exhausted', () => {
  const s = [15, 60, 240];
  assertEquals(nextRematch(1, T0, s), { next_at: mins(15).toISOString(), exhausted: false });
  assertEquals(nextRematch(3, T0, s), { next_at: mins(240).toISOString(), exhausted: false });
  assertEquals(nextRematch(4, T0, s), { next_at: null, exhausted: true });
});

Deno.test('a failure carries the first failure and counts on from the state it had', () => {
  const first = failedState(null, ' note', T0, [15, 60]);
  assertEquals([first.attempts, first.first_failed_at, first.next_at, first.exhausted, first.extra], [1, T0.toISOString(), mins(15).toISOString(), false, ' note']);
  const third = failedState({ attempts: 2, first_failed_at: T0.toISOString() }, ' note', mins(75), [15, 60]);
  assertEquals([third.attempts, third.first_failed_at, third.exhausted, third.next_at], [3, T0.toISOString(), true, null]);
});

Deno.test('due: only a waiting request whose next try has come; a legacy one with no schedule is due at once', () => {
  const waiting = (next: Date | null, exhausted = false) => ({ matcher_unavailable: true, rematch: { attempts: 1, next_at: next?.toISOString() ?? null, exhausted } });
  assert(rematchDue(waiting(mins(10)), mins(10)));
  assert(!rematchDue(waiting(mins(11)), mins(10)));
  assert(!rematchDue(waiting(mins(0), true), mins(10)));
  assert(rematchDue({ matcher_unavailable: true }, T0), 'a request that failed before the schedule existed');
  assert(!rematchDue({ outcome: 'dispatched' }, T0));
  assert(!rematchDue(null, T0));
});

Deno.test('one finding per request: two outages never share a key', () => {
  assert(matcherFindingKey('a') !== matcherFindingKey('b'));
  assertEquals(matcherFindingKey('a'), 'sales_engineer_match_unavailable:a');
});

function io(routings: Record<string, any>, answers: Record<string, { matches: number; routing: any }>, claimable = true) {
  const log: any[] = [];
  const x: RematchIO = {
    waiting: async () => Object.entries(routings).map(([id, routing]) => ({ id, category: 'plumbing', emirate: 'Dubai', summary: 's', budget: null, routing })),
    claim: async (id) => { log.push(['claim', id]); return claimable; },
    match: async (id, opts, prior) => { log.push(['match', id, opts.extra, prior?.attempts ?? 0]); return answers[id]; },
    told: async (id, n) => { log.push(['told', id, n]); },
    closeFinding: async (id) => { log.push(['close', id]); },
  };
  return { x, log };
}

Deno.test('the sweep re-matches what is due, closes its finding and tells the customer; what is still unanswered waits', async () => {
  const due = { matcher_unavailable: true, rematch: { attempts: 2, next_at: mins(0).toISOString(), exhausted: false, extra: ' X' } };
  const later = { matcher_unavailable: true, rematch: { attempts: 1, next_at: mins(99).toISOString(), exhausted: false } };
  const { x, log } = io({ a: due, b: due, c: later }, {
    a: { matches: 3, routing: { outcome: 'dispatched' } },
    b: { matches: 0, routing: { matcher_unavailable: true, rematch: { attempts: 3, exhausted: true } } },
  });
  const r = await rematchWaiting(x, mins(1), 10);
  assertEquals([r.waiting, r.due, r.rematched, r.reached, r.still_waiting, r.exhausted, r.errors.length], [3, 2, 1, 1, 1, 1, 0]);
  assertEquals(log, [['claim', 'a'], ['match', 'a', ' X', 2], ['close', 'a'], ['told', 'a', 3], ['claim', 'b'], ['match', 'b', ' X', 2]]);
});

Deno.test('a request another sweep claimed first is left to it', async () => {
  const due = { matcher_unavailable: true, rematch: { attempts: 1, next_at: mins(0).toISOString() } };
  const { x, log } = io({ a: due }, {}, false);
  const r = await rematchWaiting(x, mins(1));
  assertEquals([r.due, r.rematched], [1, 0]);
  assertEquals(log, [['claim', 'a']]);
});

Deno.test('matchAndNotify records the schedule, keys the finding per request, and keeps a waiting request out of the rescue', async () => {
  const src = await Deno.readTextFile(new URL('./lib/matching.ts', import.meta.url));
  assert(/routing\.rematch = failedState\(prior, extra/.test(src), 'the failure records its re-match state');
  assert(/p_issue_key: matcherFindingKey\(inqId\)/.test(src), 'the finding is keyed per request');
  assert(!/p_issue_key: 'sales_engineer_match_unavailable'/.test(src), 'no fixed key is left');
  assert(/if \(!routing\.matcher_unavailable\) \{\s*try \{\s*const \{ data: fl \} = await admin\.rpc\('fn_stalled_inquiry_flag'/.test(src), 'a waiting request is not flagged to the rescue');
  const door = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  assert(/peek\.action === 'rematch_waiting'/.test(door) && /requireInternal\(admin, String\(peek\.__secret\), 'customer_api'\)/.test(door), 'the sweep has an internal door');
  const tick = await Deno.readTextFile(new URL('../resilience_ping/index.ts', import.meta.url));
  assert(/specoffer: \{ run: specOfferAndRematchTick, nested: true \}/.test(tick), 'the sweep rides the specoffer step');
});
