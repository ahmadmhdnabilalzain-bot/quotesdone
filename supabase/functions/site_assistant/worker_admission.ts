// ONE WORKER TAKES ONLY AS MANY TURNS AS ITS CPU BUDGET CAN FINISH (it_engineer, 11 Nov 2026, load test round 2, ruling 1622).
//
// Measured on production, 11 Nov 2026 02:42-02:46 UTC (main 2bd2fa971, after #1923; 50 concurrent website chats):
//   - the edge runtime gives a worker ONE CPU budget for its whole life. supabase.com/docs/guides/functions/limits says
//     "Maximum CPU Time: 2s (Amount of actual time spent on the CPU per request...)" and that a worker "can serve
//     multiple requests"; the logs show the budget is spent per WORKER: worker 8872b574 was killed (Shutdown reason
//     CPUTime) at cpu_time_used 2,003 ms holding 18 turns that all arrived within 8.5 s of each other (~111 ms each),
//     and all 17 still running came back HTTP 546. The other workers of the run were retired (EarlyDrop) at 1,175-1,893
//     ms after 6-12 turns: the runtime stops sending a worker new requests near a soft limit, and the turns already
//     inside keep spending until the hard one.
//   - a site_assistant turn on a young worker costs ~100 ms of production CPU (124-210 ms a turn including the boot,
//     about 300 ms, spread over a worker's 6-12 turns). Every worker is young: none lives past ~12 turns.
//   - nothing bounded how many turns the router stacks on one worker: 18 on 8872b574, 1 to 6 on the four workers that
//     booted in the same two seconds.
// So the kill is decided at admission, not by how cheap a turn is: ~1 s of headroom past the soft limit divided by
// ~100 ms a turn is ~10 turns in flight, and the router sent 18. Cutting per-turn CPU (this branch does that too) only
// moves the number.
//
// THE RULE: a worker runs at most `cap` turns at once (WORKER_TURNS_DEFAULT, retunable in app_secrets as
// site_assistant_worker_turns without a deploy). One more is answered at once, before any read, write or model call,
// with { busy: true, retry_after_ms }: no reply text (founder_instruction 1339: code writes no reply), not an error
// status, and no rate-limit bucket spent, so asking again costs the visitor nothing. The widget asks again after that
// delay plus jitter while it shows "Still working on your answer…" (src/lib/busyRetry.ts); by then a slot is free or the
// router has a fresh worker. With cap 8 a worker's overshoot past its soft limit is at most ~8 x 100 ms, under the ~1 s
// between the lowest retirements seen (~1.1 s) and the kill (2 s). Setting the app_secrets value very high turns the gate off.
// prevented by: site_assistant/worker_admission.test.ts, src/lib/busyRetry.test.mjs
export const WORKER_TURNS_DEFAULT = 8;
/** The delay the busy answer asks for, before the client's own jitter: spread so a burst does not come back at once. */
export const BUSY_RETRY_MS: [number, number] = [1500, 4500];

export interface Gate { enter(): (() => void) | null; inflight(): number; shed(): number }
/** A per-worker gate. `cap()` is read on every entry, so a retuned limit applies to the next turn. */
export function workerGate(cap: () => number): Gate {
  let inflight = 0, shed = 0;
  return {
    enter() {
      const c = Math.max(1, Math.floor(cap() || WORKER_TURNS_DEFAULT));
      if (inflight >= c) { shed++; return null; }
      inflight++;
      let done = false;
      return () => { if (!done) { done = true; inflight--; } };
    },
    inflight: () => inflight,
    shed: () => { const n = shed; shed = 0; return n; },   // read-and-reset: the next observe row reports what was shed since
  };
}

/** The body of a shed turn: nothing to show, ask again after the delay. */
export function busyBody(rnd: () => number = Math.random): { reply: ''; busy: true; retry_after_ms: number } {
  const [lo, hi] = BUSY_RETRY_MS;
  return { reply: '', busy: true, retry_after_ms: Math.round(lo + (hi - lo) * rnd()) };
}
