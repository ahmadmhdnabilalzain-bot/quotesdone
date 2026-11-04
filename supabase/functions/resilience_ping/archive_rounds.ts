// How the heartbeat drives conversation_archive under its CPU budget (it_engineer, 2 Nov 2026; review of #1797).
//
// The sweep now stops inside a render budget (conversation_archive/budget.ts) and reports `deferred`. Four slices once
// a tick would then fall below the 64 PDFs an hour this tick was raised to on 6 Oct (16/h breached the 2-hour keep
// check on 5 Oct), so the tick runs ANOTHER round of slices while any slice deferred and the archive's wall budget
// lasts. And a slice whose worker died without an answer (a 546 on one oversized message) is re-run one message per
// worker, so that message dies alone and the three behind it are still drawn: one message can never block the queue.
// Offsets are re-based for what the lower slices archived in the same round (the list is oldest-first and an
// archived row leaves it); a guess one row off draws a message twice (an upsert), never skips one.
// prevented by: resilience_ping/archive_rounds.test.ts
// The step is `always` (it runs past the tick's 110 s deadline), so its own wall is bounded: no new round starts after
// ARCHIVE_WALL_MS, and every call of every round shares one ARCHIVE_HARD_MS clock - the 50 s the single round had.
export const ARCHIVE_ROUNDS_MAX = 4;
export const ARCHIVE_WALL_MS = 30_000;
export const ARCHIVE_HARD_MS = 50_000;

export type SliceOut = { offset: number; status?: number; result?: { ok?: boolean; archived?: number; deferred?: number } | null };

// The sweep's own answer always carries `ok`; a worker the platform killed answers 546 with its own JSON
// ({code: 'WORKER_LIMIT', ...}) or nothing at all, so "answered" is the envelope, not the content type.
const answered = (s: SliceOut) => !!s.result && typeof s.result === 'object' && 'ok' in s.result;

/** Offsets to re-run one message each: the rows of every slice that died, re-based for what lower slices archived. */
export function isolateOffsets(slices: SliceOut[], batch: number): number[] {
  const out: number[] = [];
  for (const s of slices) {
    if (answered(s)) continue;                                        // the sweep answered: nothing to isolate
    const before = slices.filter((o) => o.offset < s.offset).reduce((n, o) => n + (Number(o.result?.archived) || 0), 0);
    const from = Math.max(0, s.offset - before);
    for (let k = 0; k < batch; k++) out.push(from + k);
  }
  return out;
}

/** Run another round? Only while some slice deferred work and the wall budget allows another round. */
export function anotherRound(slices: SliceOut[], round: number, elapsedMs: number): boolean {
  const deferred = slices.reduce((n, s) => n + (Number(s.result?.deferred) || 0), 0);
  return deferred > 0 && round + 1 < ARCHIVE_ROUNDS_MAX && elapsedMs < ARCHIVE_WALL_MS;
}
