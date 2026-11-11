// THE WIDGET ASKS AGAIN WHEN A WORKER IS FULL (it_engineer, 11 Nov 2026, load test round 2, founder ruling 1622).
// site_assistant answers a turn its worker has no CPU room for with { busy: true, retry_after_ms } at once, before it
// reads, writes or spends anything (supabase/functions/site_assistant/worker_admission.ts: in the 02:42 UTC load run one
// worker took 18 turns at once and was killed with 17 of them, HTTP 546). The widget then waits that long plus jitter, so a
// burst does not come back at once, and sends the same message again while it shows "Still working on your answer…".
// After BUSY_TRIES answers of busy it stops and shows its own error line, as for any turn with no answer.
// prevented by: src/lib/busyRetry.test.mjs
export const BUSY_TRIES = 4;
/** How long to wait before asking again, or null when this answer is not busy or the tries are used up. */
export function busyRetryDelay(done: Record<string, unknown> | null | undefined, attempt: number, rnd: () => number = Math.random): number | null {
  if (!done || done.busy !== true || attempt >= BUSY_TRIES - 1) return null;
  const asked = Number(done.retry_after_ms);
  const base = Number.isFinite(asked) && asked > 0 ? Math.min(asked, 10_000) : 3_000;
  return Math.round(base * (1 + attempt / 2) + rnd() * 1_500);
}
