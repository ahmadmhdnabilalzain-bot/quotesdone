// cad_dispatch — when a polled CAD job may start its worker again (3 Nov 2026, sales_engineer; independent review of #1837).
//
// The first version let a dispatch through on every poll in the first 15 s of each minute of the job's age, with no
// state and no age cap: a customer page polling once a second dispatched the GitHub workflow ~15 times a minute, for
// as long as the page stayed open. Now:
//   * a job is re-dispatched only while it is stuck (queued past 2 minutes, or running with no word for 30) and younger
//     than ONE HOUR; past that a dispatch has had 60 chances, so the poll raises the hour's held finding instead;
//   * every poll first CLAIMS the job's slot in the database, one UPDATE with the window in its WHERE, so at most one
//     poll a minute, across every isolate, wins it (cad_read_jobs.last_dispatch_at, scripts/sql/a_polled_cad_job_is_dispatched_at_most_once_a_minute.sql).
// Prevented by cad_dispatch.test.ts and scripts/checks/a_cad_upload_reaches_the_cad_reader.test.mjs.
// deno-lint-ignore-file no-explicit-any

// 10 Nov 2026 (it_engineer, channels audit R3): nothing is dispatched any more. The CAD read routine (lib/drawings.ts
// CAD_READER_ROUTINE) reads every queued job every CAD_READER_EVERY_MS; a poll only raises the held finding, once a minute at
// most (the claimed slot below), for a job the routine has not taken within its interval and run time (CAD_READER_GRACE_MS),
// or one a worker claimed and went silent on.
export const DISPATCH_EVERY_MS = 60_000;
export const CAD_READER_EVERY_MS = 2 * 60 * 60_000;   // the routine's cron: 15 */2 * * * (every 2 h, at :15)
export const CAD_READER_GRACE_MS = 45 * 60_000;       // its run time and a late start

/** What a poll of this job should do: raise the held finding, or nothing (the routine reads the queue). */
export function cadJobNeedsRedispatch(job: { status: string; created_at: string; claimed_at: string | null }, now = Date.now()): 'held' | null {
  const age = (t: string | null) => (t ? now - Date.parse(t) : 0);
  const missed = job.status === 'queued' && age(job.created_at) > CAD_READER_EVERY_MS + CAD_READER_GRACE_MS;
  const silent = job.status === 'running' && age(job.claimed_at) > 30 * 60_000;
  return missed || silent ? 'held' : null;
}

/** Take the job's dispatch slot: true for at most one caller per minute. A failed claim is false and said, never a dispatch. */
export async function claimCadDispatch(db: any, jobId: string, now = Date.now()): Promise<boolean> {
  const since = new Date(now - DISPATCH_EVERY_MS).toISOString();
  const { data, error } = await db.from('cad_read_jobs').update({ last_dispatch_at: new Date(now).toISOString() })
    .eq('id', jobId).or(`last_dispatch_at.is.null,last_dispatch_at.lt.${since}`).select('id');
  if (error) { console.error(`[cad] the dispatch slot of job ${jobId} could not be claimed: ${error.message}`); return false; }
  return Array.isArray(data) && data.length > 0;
}
