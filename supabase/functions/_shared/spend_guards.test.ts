// The rules that stop a paid call repeating itself (it_engineer, 22 Sep 2026, founder instruction 705).
// Each test replays the input that used to multiply spend.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { rehearsalLetsFixtureThrough,
  activeFailure, attemptPlan, COMPARE_RETRY_BASE_MS, COMPARE_RETRY_MAX_MS, failureKind, failureRecord,
  fixtureVerdict, isCachedAnalysis, MAX_PAID_CALLS_PER_REQUEST, nextAttempt, ownWorkByName, subjectOf,
} from './spend_guards.ts';

// Walk a plan the way ai_gateway does, with every attempt failing at `status`; returns the models called.
function walk(ladder: string[], status: number | null): string[] {
  const plan = attemptPlan(ladder); const called: string[] = [];
  for (let i = 0; i >= 0 && i < plan.length; i = nextAttempt(plan, i, failureKind(status))) called.push(plan[i]);
  return called;
}

Deno.test('a request makes at most two paid calls, however the ladder fails (was 2 attempts x 2 models = 4)', () => {
  assertEquals(MAX_PAID_CALLS_PER_REQUEST, 2);
  assertEquals(walk(['sonnet', 'flash'], 503), ['sonnet', 'flash']);
  assertEquals(walk(['sonnet', 'flash'], null), ['sonnet', 'flash']);      // empty completion / network
  assertEquals(walk(['sonnet'], 503), ['sonnet', 'sonnet']);               // a lone model keeps its one retry
  assertEquals(walk(['a', 'b', 'c'], 500).length, 2);
  assertEquals(walk([], 500), []);
});

Deno.test('an account refusal (401/402/403) stops the ladder: no second model on the same empty account', () => {
  for (const s of [401, 402, 403]) {
    assertEquals(walk(['sonnet', 'flash'], s), ['sonnet']);
    assertEquals(walk(['sonnet'], s), ['sonnet']);
  }
});

Deno.test('a request the model refuses (400/404/413/422) is never re-sent to the same model', () => {
  for (const s of [400, 404, 413, 422]) {
    assertEquals(walk(['sonnet', 'flash'], s), ['sonnet', 'flash']);
    assertEquals(walk(['sonnet'], s), ['sonnet']);
  }
});

Deno.test('transient failures are worth the one retry', () => {
  for (const s of [408, 429, 500, 502, 503, null]) assertEquals(failureKind(s), 'retry');
});

Deno.test('our own probes, rehearsals, smokes and evals are recognised by the calling function', () => {
  for (const fn of ['quality_axis_probe', 'accountant_eval', 'it_engineer_eval', 'e2e_journey', 'smoke_staging', 'rehearsal_reveal', 'probe'])
    assert(ownWorkByName(fn), fn);
  for (const fn of ['quote_compare', 'inquiry_intake', 'site_assistant', 'email_triage', 'probes_are_not_a_word_here_reprobed', '', null, undefined])
    assert(!ownWorkByName(fn as string), String(fn));
});

Deno.test('the subject keeps only what the database check reads', () => {
  assertEquals(subjectOf(null), null);
  assertEquals(subjectOf('x'), null);
  assertEquals(subjectOf({ inquiry_id: '', email: '  ' }), null);
  assertEquals(subjectOf({ inquiry_id: 'a', supplier_id: 7, admin: true }), { inquiry_id: 'a', supplier_id: '7' });
});

Deno.test('only an explicit "not a fixture" reaches a paid call', () => {
  assertEquals(fixtureVerdict({ fixture: false }, null).stub, false);
  assertEquals(fixtureVerdict({ fixture: true, why: 'demo' }, null), { stub: true, why: 'demo' });
  assert(fixtureVerdict(null, null).stub);
  assert(fixtureVerdict({ fixture: 'false' }, null).stub);
  assert(fixtureVerdict({}, null).stub);
  assert(fixtureVerdict({ fixture: false }, { message: 'function does not exist' }).stub);
});

Deno.test('a failed comparison is cached: 15 minutes, doubling, never more than a day', () => {
  const t0 = new Date('2026-09-22T10:00:00Z');
  const f1 = failureRecord(null, 'http503:none:circuit_open', t0);
  assertEquals(f1.__failed.count, 1);
  assertEquals(Date.parse(f1.__failed.retry_after) - t0.getTime(), COMPARE_RETRY_BASE_MS);
  const f2 = failureRecord(f1, 'parse:sonnet', t0);
  assertEquals(f2.__failed.count, 2);
  assertEquals(Date.parse(f2.__failed.retry_after) - t0.getTime(), 2 * COMPARE_RETRY_BASE_MS);
  let f = f2; for (let i = 0; i < 20; i++) f = failureRecord(f, 'x', t0);
  assertEquals(Date.parse(f.__failed.retry_after) - t0.getTime(), COMPARE_RETRY_MAX_MS);
  // a success row replaces a failure row, and neither is mistaken for the other
  assert(!isCachedAnalysis(f1)); assert(isCachedAnalysis({ top3: [] })); assert(!isCachedAnalysis(null));
});

Deno.test('a card view inside the retry window is served from the cached failure; after it, the model is asked again', () => {
  const t0 = new Date('2026-09-22T10:00:00Z');
  const f1 = failureRecord(null, 'empty_shortlist', t0);
  assert(activeFailure(f1, new Date(t0.getTime() + 60_000)), 'one minute later: no new paid call');
  assertEquals(activeFailure(f1, new Date(t0.getTime() + COMPARE_RETRY_BASE_MS + 1)), null, 'after the window: try again');
  assertEquals(activeFailure({ top3: [1] }, t0), null);
  assertEquals(activeFailure(null, t0), null);
});
