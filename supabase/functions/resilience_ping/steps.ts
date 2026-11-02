// How resilience_ping runs its ticks: in order, each on its own, inside a deadline, and with every
// failure named. Pure, so the rules are tested without a network (steps.test.ts).
//
// WHY. Measured 15 Sep 2026: every tick swallowed its error and the endpoint answered ok:true, so the
// accountant's duties answered HTTP 401 on every pass (151 refusals at the gateway in 24 hours) and
// nothing anywhere said so. A step that fails is now returned in `failing` and raised as an IT engineer
// finding by the handler; one step failing never stops the next.
export type Step = { name: string; run: () => Promise<unknown>; always?: boolean; nested?: boolean };
export type Failure = { name: string; error: string; carried?: boolean };

// What counts as a failed step: it threw, it answered {ok:false, error}, or its HTTP call answered 4xx/5xx.
// A seat answering {ok:false} WITHOUT an error string has already reported its own partial failure
// (fn_accountant_duties stages each failed duty as its own finding), so it is not counted twice.
export function failureOf(r: unknown): string | null {
  if (!r || typeof r !== 'object') return null;
  const o = r as Record<string, unknown>;
  if (o.ok === false && typeof o.error === 'string') return o.error.slice(0, 300);
  if (typeof o.status === 'number' && o.status >= 400) return 'HTTP ' + o.status;
  return null;
}

// The error a failed HTTP hop records, with the error the callee gave (22 Sep 2026). backupVerify
// recorded only "dropbox_backup reconcile answered HTTP 500" for two days while the body said
// "apply canceling statement due to statement timeout" -- the cause was in the reply and not in the row.
export function httpHopError(what: string, status: number, body: unknown): string {
  const b = body && typeof body === 'object' ? body as Record<string, unknown> : {};
  const why = typeof b.error === 'string' ? b.error : typeof b.message === 'string' ? b.message : '';
  return (what + ' answered HTTP ' + status + (why ? ': ' + why : '')).slice(0, 300);
}

// THE DEADLINE WAS CHECKED BEFORE A STEP STARTED AND NEVER AGAIN (22 Sep 2026, it_engineer, CONN-02).
// Measured: the check below is the only place the deadline appeared, so a step that STARTED inside it
// could run for its own timeout on top — and 12 steps carry AbortSignal.timeout(55000). A step started
// at 109.9 s therefore returned at up to 164.9 s, and `always` steps skipped the check altogether, so
// the three mail drains could each add their own 55 s after that. The tick's own platform limit is
// 150 s; the measured max tick was 140.9 s, i.e. already inside the last 10 s of the budget.
//
// So the deadline is now a CEILING ON WHEN A STEP MAY STILL BE WAITING, not only on when it may begin.
// Each step is raced against `stepCapMs` below, which is what is left of deadline + RESERVE_MS. The
// race abandons the await; the underlying fetch is not cancelled (its own AbortSignal still bounds it)
// but nothing downstream waits for it, which is the property that was missing.
export const RESERVE_MS = 25_000;
// An `always` step past the ceiling is not skipped — skipping a mail drain holds a real message a whole
// beat — but it is not unbounded either. THE FLOOR IS A POOL THE `always` STEPS SHARE, NOT A GRANT EACH
// (corrected 22 Sep 2026 after independent review). There are THREE of them — it, outbox and archive,
// index.ts STEP_RUN — they run one after another, and a per-step 10 s floor made the worst case
// 95 + 25 + 10 + 10 + 10 = 150 s, which is the platform cap exactly, before the liveness read and
// fn_it_duty_settle that still run after the steps. Shared, the worst case is 95 + 25 + 10 = 130 s and
// there are 20 s left for the tail.
export const ALWAYS_FLOOR_POOL_MS = 10_000;

/** Resolves with the step, or with an {ok:false} failure as soon as `capMs` passes. Never leaks a timer. */
function raceCap<T>(p: Promise<T>, capMs: number, name: string): Promise<T | { ok: false; error: string }> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const bell = new Promise<{ ok: false; error: string }>((resolve) => {
    timer = setTimeout(() => resolve({ ok: false,
      error: 'abandoned after ' + Math.round(capMs / 1000) + 's: the tick was out of budget and stopped waiting for ' + name }),
      Math.max(capMs, 0));
  });
  return Promise.race([p, bell]).finally(() => clearTimeout(timer));
}

/**
 * How long this step may still be waited on: what is left of deadline+reserve, and for an `always`
 * step past that, whatever remains of the SHARED floor pool (`poolLeft`).
 */
export function stepCapMs(elapsedMs: number, deadlineMs: number, always: boolean, reserveMs = RESERVE_MS,
                          poolLeft = ALWAYS_FLOOR_POOL_MS): number {
  const left = deadlineMs + reserveMs - elapsedMs;
  if (!always) return left;
  return Math.max(left, Math.max(poolLeft, 0));
}

// Runs every step in order. A step not started by `deadlineMs` after `t0` is skipped and counted as
// failing, unless it is `always` (the mail drains: skipping them would hold a message a whole beat).
// Every step that does start — `always` included — is then bounded by stepCapMs.
export async function runSteps(steps: Step[], t0: number, deadlineMs: number, now: () => number = Date.now,
                               reserveMs = RESERVE_MS, poolMs = ALWAYS_FLOOR_POOL_MS) {
  const results: Record<string, unknown> = {};
  const failing: Failure[] = [];
  // How long each step that actually ran took. Two Date.now() calls a step, so it costs nothing it is
  // measuring, and it is what fn_resilience_step_record folds into each step's ewma_ms — the estimate
  // the plan uses to decide what fits. Before this existed the only number anyone had was the tick's
  // total, and "which step is eating the budget" had to be inferred from the sub-functions' own
  // agent_runs rows, which says nothing at all about the steps that are pure RPCs.
  const ms: Record<string, number> = {};
  // The shared overrun allowance for the `always` steps — see ALWAYS_FLOOR_POOL_MS.
  let poolLeft = poolMs;
  for (const s of steps) {
    if (!s.always && now() - t0 > deadlineMs) {
      results[s.name] = { skipped: 'deadline' };
      failing.push({ name: s.name, error: 'not run: the tick passed its ' + Math.round(deadlineMs / 1000) + 's deadline' });
      continue;
    }
    const s0 = now();
    const cap = stepCapMs(s0 - t0, deadlineMs, !!s.always, reserveMs, poolLeft);
    let r: unknown;
    try { r = await raceCap(s.run(), cap, s.name); } catch (e) { r = { ok: false, error: String((e as Error)?.message || e) }; }
    ms[s.name] = now() - s0;
    // What an `always` step spent BEYOND the ceiling comes out of the shared pool, so the second and
    // third drains cannot each claim the whole floor again.
    if (s.always) {
      const overrun = (s0 - t0) + ms[s.name] - (deadlineMs + reserveMs);
      if (overrun > 0) poolLeft = Math.max(0, poolLeft - overrun);
    }
    results[s.name] = r;
    // A NESTED STEP IS STILL JUDGED AT ITS OWN LEVEL FIRST (18 Sep 2026, it_engineer).
    // Found in review: the nested branch only looked at the entries, so a nested step that THREW —
    // wrapped as {ok:false, error} by the catch above — had that shape split into the entries
    // ('ok', false) and ('error', '...'), neither of which failureOf can read, and the failure
    // vanished. Same for a nested step that returns a bare {ok:false, error} because it never got
    // as far as having sub-results, which is exactly what a gate RPC failing looks like. The top
    // level is asked first; only a step that is itself fine is opened up and read per entry.
    const top = failureOf(r);
    if (top) {
      failing.push({ name: s.name, error: top });
    } else if (s.nested && r && typeof r === 'object') {
      for (const [k, v] of Object.entries(r as Record<string, unknown>)) {
        const f = failureOf(v);
        if (f) failing.push({ name: s.name + '.' + k, error: f });
      }
    }
  }
  return { results, failing, ms };
}

// WHAT THE TICK TELLS THE SCHEDULE AFTERWARDS, in the shape fn_resilience_step_record reads. A step is
// `ok` when nothing in `failing` names it — either the step itself or one of its nested entries, because
// `orphans.sanctions_screen` failing means the orphans step did not do its job. A deferred step stamps
// nothing: leaving its last attempt untouched is exactly what makes it the stalest step next tick, so
// this function is the other half of the starvation guarantee that lives in fn_resilience_tick_plan.
export function stepRows(ranMs: Record<string, number>, failing: Failure[], deferred: string[]) {
  const bad = new Set<string>();
  for (const f of failing) bad.add(f.name.split('.')[0]);
  const rows: Array<Record<string, unknown>> = Object.entries(ranMs)
    .map(([step, ms]) => ({ step, ms, ok: !bad.has(step) }));
  for (const step of deferred) rows.push({ step, deferred: true });
  return rows;
}

// A STEP THAT FAILED STAYS FAILED UNTIL IT RUNS AGAIN (22 Sep 2026, it_engineer). The heartbeat duty is
// settled every tick with the failures of THIS tick, and fn_it_duty_settle closes every open
// duty:heartbeat key not in that list. A step on a 6-hour cadence (backupVerify) therefore had its
// finding closed 15 minutes after each failure, on a tick where it simply was not due: MEASURED 21 Sep,
// duty:heartbeat:backupVerify raised 17:16Z ("canceling statement due to statement timeout"), closed
// 17:31Z "the heartbeat duty no longer finds it", while resilience_step still read last_ok_at 20 Sep
// 03:31Z. So the ledger said healthy for 23 of every 24 ticks of a check that had not passed in 38 hours.
// A step whose last attempt is newer than its last success, and which did not run this tick, is carried
// as still failing, with `carried` so fn_it_duty_settle holds the open finding instead of re-seeing it.
export type StepState = { step: string; last_started_at: string | null; last_ok_at: string | null };
export function carriedFailures(state: StepState[], ranMs: Record<string, number>, failing: Failure[]): Failure[] {
  const named = new Set(failing.map((f) => f.name.split('.')[0]));
  return state
    .filter((s) => !(s.step in ranMs) && !named.has(s.step) && s.last_started_at !== null
      && (s.last_ok_at === null || Date.parse(s.last_ok_at) < Date.parse(s.last_started_at)))
    .map((s) => ({ name: s.step, error: 'its last run at ' + s.last_started_at + ' failed and it has not passed since (last ok: '
      + (s.last_ok_at ?? 'never') + ')', carried: true }));
}

// A DETACHED RUN'S FAILURES AS fn_it_duty_settle ITEMS (12 Oct 2026, it_engineer). `marketing` and `itlater`
// run in their own invocation (index.ts, DETACHED), so their failures no longer reach the tick's heartbeat;
// each failing sub-step is one item, keyed by its own name, so a nested runner's map is read per entry.
// WHERE A DETACHED RUN SPENT ITS TIME (it_engineer, 27 Oct 2026). duty:detached_itlater:itlater reopened at 22:03:12Z
// (seen 53) saying only "passed its 120000 ms limit": the 120 s race in runDetached threw away the run's per-step
// results, and nothing stored per-step timing, so the finding could not say which of 25 steps was still running. Every
// step of a nested run now reports to a StepClock the run shares with runDetached; the clock survives the race. Its
// snapshot goes into the finding (title: the step still running and for how long; evidence.timing: every finished step
// with its ms) and, for every run, pass or fail, into the function log as one `detached_timing` line.
// prevented by: resilience_ping/steps.test.ts ("a detached run that overruns names the step it was in")
export type StepTime = { step: string; ms: number; ok: boolean };
export type Timing = { total_ms: number; steps: StepTime[]; running: { step: string; ms: number } | null };
export type StepClock = { begin(step: string): void; end(step: string, ok: boolean): void; snapshot(): Timing };
export function stepClock(now: () => number = Date.now): StepClock {
  const t0 = now();
  const steps: StepTime[] = [];
  let running: { step: string; at: number } | null = null;
  return {
    begin(step) { running = { step, at: now() }; },
    end(step, ok) {
      const at = running?.step === step ? running.at : now();
      steps.push({ step, ms: now() - at, ok });
      running = null;
    },
    snapshot() {
      return { total_ms: now() - t0, steps: steps.map((s) => ({ ...s })), running: running ? { step: running.step, ms: now() - running.at } : null };
    },
  };
}
/** "running routine_judgements for 93410 ms; slowest finished review_requests 12034 ms" - empty when nothing was timed. */
export function timingLine(t: Timing | undefined): string {
  if (!t) return '';
  const parts: string[] = [];
  if (t.running) parts.push('running ' + t.running.step + ' for ' + t.running.ms + ' ms');
  const slow = [...t.steps].sort((a, b) => b.ms - a.ms)[0];
  if (slow) parts.push('slowest finished ' + slow.step + ' ' + slow.ms + ' ms');
  return parts.join('; ');
}

export function detachedItems(name: string, out: unknown, nested: boolean, timing?: Timing) {
  // A whole-run failure (the 120 s cap, a throw) is {ok:false,error} even for a nested runner: it is ONE item
  // under the step's name, never read entry by entry, or an empty list would close open findings over a hung run.
  const whole = failureOf(out);
  const line = timingLine(timing);
  if (whole) return [{ item: name, title: ('detached ' + name + ' failed: ' + whole + (line ? ' (' + line + ')' : '')).slice(0, 300),
    owner_seat: 'it_engineer', subject: 'resilience_ping', blast: 'agent_facing', affected: 1,
    evidence: { step: name, error: whole, ...(timing ? { timing } : {}) } }];
  const parts: Record<string, unknown> = nested && out && typeof out === 'object' ? out as Record<string, unknown> : { [name]: out };
  return Object.entries(parts).flatMap(([k, v]) => {
    const f = failureOf(v);
    const ms = timing?.steps.find((s) => s.step === k)?.ms;
    return f ? [{ item: k, title: 'detached ' + name + ' step ' + k + ' failed: ' + f, owner_seat: 'it_engineer',
      subject: 'resilience_ping', blast: 'agent_facing', affected: 1,
      evidence: { step: name, sub: k, error: f, ...(ms !== undefined ? { ms } : {}), ...(timing ? { timing } : {}) } }] : [];
  });
}
