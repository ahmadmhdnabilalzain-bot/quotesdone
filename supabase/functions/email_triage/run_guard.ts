// A triage run is never silent (2 Nov 2026, it_engineer; inbound_messages 1615, agent_runs 4602652 and 4642499).
//
// MEASURED: both runs have finished_at null, counts {} and NO fn:email_triage row, so the handler neither returned
// nor threw: the isolate was ended from outside (wall clock or CPU cap; the function log has no per-function id, so
// which of the two is not provable). A kill skips every catch/finally (memory: an-edge-function-has-a-cpu-cap-...),
// so the dying run cannot record its own failure. Three parts, none of which needs the dying run to speak:
//   1. beat(): the run row carries the phase and message it is in, written before each step, so a dead run says where.
//   2. budgetLeft(): the batch stops STARTING messages after BATCH_BUDGET_MS, so a healthy run ends well inside the cap.
//   3. closeStaleRuns(): the NEXT run closes any email_triage row left open, with the reason and the last beat, and
//      reopens the message the dead run was answering (triaged_at back to null, only if nothing was sent: index.ts marks a
//      message triaged BEFORE it answers, so without this a kill in between left a sender never answered).
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

/**
 * A message the killed run had triaged and was answering is REOPENED (2 Nov 2026, founder's rule: no unanswered sender).
 * index.ts marks a message triaged BEFORE it answers, and the selector skips a triaged row, so a kill between the two
 * left a message nobody would ever answer. fn_inbox_send queues the reply and sets replied_at in ONE function (one
 * transaction), so "replied_at is null" proves nothing was sent and reopening cannot send twice; a message already
 * handed to the ceo (owner_role) or answered is left alone. Throws when the write fails, so the caller keeps the run open.
 */
async function reopenAnswering(db: Db, note: string | null): Promise<void> {
  const id = Number(/message (\d+) \(answer\)/.exec(note || '')?.[1]);
  if (!id) return;
  const { error } = await db.from('inbound_messages').update({ triaged_at: null }).eq('id', id)
    .eq('needs_review', true).is('replied_at', null).is('owner_role', null).not('triaged_at', 'is', null);
  if (error) throw new Error('reopen ' + id + ': ' + error.message);
}

/**
 * Closes runs that started over STALE_AFTER_MS ago and never finished, naming the last beat, and reopens the message
 * the run died answering. The run is closed only after the reopen succeeded, so a failed reopen is retried by the next
 * run instead of being forgotten. Returns how many runs were closed.
 */
export async function closeStaleRuns(db: Db, agent: string, now = Date.now()): Promise<number> {
  try {
    const cutoff = new Date(now - STALE_AFTER_MS).toISOString();
    const { data: open } = await db.from('agent_runs').select('id,note').eq('agent', agent).is('finished_at', null).lt('started_at', cutoff).limit(50);
    let n = 0;
    for (const r of (open || []) as { id: number; note: string | null }[]) {
      try { await reopenAnswering(db, r.note); } catch (_e) { continue; }
      const why = 'ended without finishing (the platform stopped the function: wall-clock or CPU cap, no catch ran). Last beat: ' + (r.note || 'none, died before the first message') + '. A message it died answering, if none was sent, is reopened for the next run; one it had not triaged is still waiting.';
      const { error } = await db.from('agent_runs').update({ finished_at: new Date(now).toISOString(), status: 'error', note: why.slice(0, 500) }).eq('id', r.id).is('finished_at', null);
      if (!error) n++;
    }
    return n;
  } catch (_e) { return 0; }
}
