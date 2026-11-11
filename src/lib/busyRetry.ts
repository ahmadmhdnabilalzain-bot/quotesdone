// THE WIDGET ASKS AGAIN WHEN A WORKER IS FULL (it_engineer, 11 Nov 2026, load test round 2, founder ruling 1622).
// site_assistant answers a turn its worker has no CPU room for with { busy: true, retry_after_ms } at once, before it
// reads, writes or spends anything (supabase/functions/site_assistant/worker_admission.ts: in the 02:42 UTC load run one
// worker took 18 turns at once and was killed with 17 of them, HTTP 546). The widget then waits that long plus jitter, so a
// burst does not come back at once, and sends the same message again while it shows "Still working on your answer…".
// After BUSY_TRIES answers of busy it stops and shows its own error line, as for any turn with no answer.
// SIX TRIES, NOT FOUR (11 Nov 2026, round 4): in the 04:28 UTC run 4 turns were still busy after 4 tries, 3 of them sent at
// 04:33:22-29, 15-20 s into the 100-user ramp while 50 new users arrived in 5 s and new workers booted; 4 tries wait ~16 s
// on average. Six, with each wait's growth capped at 2x, wait ~29 s on average (~46 s at worst) on "Still working on your
// answer…": longer than that ramp, and every extra try costs the visitor only a short wait, never an error.
// prevented by: src/lib/busyRetry.test.mjs
export const BUSY_TRIES = 6;
/** How long to wait before asking again, or null when this answer is not busy or the tries are used up. */
export function busyRetryDelay(done: Record<string, unknown> | null | undefined, attempt: number, rnd: () => number = Math.random): number | null {
  if (!done || done.busy !== true || attempt >= BUSY_TRIES - 1) return null;
  const asked = Number(done.retry_after_ms);
  const base = Number.isFinite(asked) && asked > 0 ? Math.min(asked, 10_000) : 3_000;
  return Math.round(base * Math.min(1 + attempt / 2, 2) + rnd() * 1_500);
}

// A TURN THAT NEVER REACHED A WORKER IS SENT AGAIN ONCE (it_engineer, 11 Nov 2026, load test round 3). The 03:46 UTC run had
// 2 widget requests time out at the driver's 60 s while site_assistant's turn clock is 35 s (turn_outcome.ts SITE_TURN_MS):
// function_edge_logs holds 264 site_assistant responses for that run, every one HTTP 200 and none over 14.8 s, and nothing
// for those two, so they never got a response from any worker. The widget had no deadline at all: a request held like that
// left the visitor on "Typing…" until the browser gave up. It now stops waiting at CLIENT_TURN_MS (well past the turn's own
// clock), looks for a stored answer briefly (a turn that did run is stored under the conversation), and only when there
// is none sends the message once more.
// prevented by: src/lib/busyRetry.test.mjs
export const CLIENT_TURN_MS = 50_000;
/** What to do after a request that ended without a verdict: 'resend' once for a request the deadline cut, else 'stop'. */
export function afterNoAnswer(o: { timedOut: boolean; resent: boolean; stored: string }): 'use_stored' | 'resend' | 'stop' {
  if (o.stored.trim()) return 'use_stored';
  return o.timedOut && !o.resent ? 'resend' : 'stop';
}
