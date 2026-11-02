// A triage run is never silent (2 Nov 2026, it_engineer; inbound_messages 1615, agent_runs 4602652 and 4642499).
//
// MEASURED: both runs have finished_at null, counts {} and NO fn:email_triage row, so the handler neither returned
// nor threw: the isolate was ended from outside (wall clock or CPU cap; the function log has no per-function id, so
// which of the two is not provable). A kill skips every catch/finally (memory: an-edge-function-has-a-cpu-cap-...),
// so the dying run cannot record its own failure. Three parts, none of which needs the dying run to speak:
//   1. beat(): the run row carries the phase and message it is in, written before each step, so a dead run says where.
//   2. budgetLeft(): the batch stops STARTING messages after BATCH_BUDGET_MS, so a healthy run ends well inside the cap.
//   3. closeStaleRuns(): the NEXT run closes any email_triage row left open, with the reason and the last beat.
// 30 days: 3 of 1476 email_triage runs unfinished (28 Oct 08:10, 1 Nov 21:02, 2 Nov 03:01).

export const BATCH_BUDGET_MS = 90_000;
export const STALE_AFTER_MS = 10 * 60_000;

type Db = { from: (t: string) => any };

export const budgetLeft = (startedAt: number, now = Date.now(), budget = BATCH_BUDGET_MS) => now - startedAt < budget;

/** Written BEFORE the step it names; a failed write never stops the work. */
export async function beat(db: Db, runId: number | undefined, phase: string, now = Date.now()): Promise<void> {
  if (!runId) return;
  try { await db.from('agent_runs').update({ note: ('in progress: ' + phase + ' @ ' + new Date(now).toISOString()).slice(0, 300) }).eq('id', runId).is('finished_at', null); } catch (_e) { /* instrumentation */ }
}

/** Closes runs that started over STALE_AFTER_MS ago and never finished, naming the last beat. Returns how many. */
export async function closeStaleRuns(db: Db, agent: string, now = Date.now()): Promise<number> {
  try {
    const cutoff = new Date(now - STALE_AFTER_MS).toISOString();
    const { data: open } = await db.from('agent_runs').select('id,note').eq('agent', agent).is('finished_at', null).lt('started_at', cutoff).limit(50);
    let n = 0;
    for (const r of (open || []) as { id: number; note: string | null }[]) {
      const why = 'ended without finishing (the platform stopped the function: wall-clock or CPU cap, no catch ran). Last beat: ' + (r.note || 'none, died before the first message') + '. The unfinished message is picked up again by the next run, or by the rescue.';
      const { error } = await db.from('agent_runs').update({ finished_at: new Date(now).toISOString(), status: 'error', note: why.slice(0, 500) }).eq('id', r.id).is('finished_at', null);
      if (!error) n++;
    }
    return n;
  } catch (_e) { return 0; }
}
