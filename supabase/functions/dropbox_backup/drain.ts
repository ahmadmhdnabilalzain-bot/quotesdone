// Walking one claimed batch of doc_backups rows (it_engineer, 15 Sep 2026).
//
// Measured 15 Sep 07:22:02Z and 07:22:05Z: two runs stopped on their first row (a refused token refresh)
// with 24 and 7 more rows claimed. Those rows stayed 'processing' until fn_doc_backups_next requeues
// expired claims after 10 minutes. Here every way a run stops early hands the rows it never reached
// back to `release` at once:
//   * the run's deadline      -> the row in hand and everything after it are released;
//   * AuthUnavailable         -> the row in hand is requeued (not failed, attempts unchanged), the rest released;
//   * 'no_dropbox_auth'       -> the row in hand fails loudly as before, the rest are released.
// Any other error fails that one row and the walk goes on.
import { AuthUnavailable, isAuthStop } from './dropbox.ts';

export type DrainHooks<R> = {
  deadline: number; now?: () => number;
  process: (row: R) => Promise<void>;                  // throws when the row did not succeed
  fail: (row: R, msg: string) => Promise<void>;        // mark the row failed
  requeue: (row: R, msg: string) => Promise<void>;     // the token endpoint was unavailable: back to pending
  release: (ids: number[]) => Promise<number>;         // rows never reached: back to pending, answers how many
};
export type DrainResult = { failed: number; released: number; authUnavailable: string; notes: string[] };

export async function drainClaim<R extends { id: number }>(claimed: R[], h: DrainHooks<R>): Promise<DrainResult> {
  const now = h.now ?? Date.now;
  let stop = claimed.length, failed = 0, released = 0, authUnavailable = ''; const notes: string[] = [];
  for (let i = 0; i < claimed.length; i++) {
    if (now() >= h.deadline) { stop = i; break; }
    const row = claimed[i];
    try { await h.process(row); } catch (e) {
      const msg = String((e as Error)?.message || e).slice(0, 300);
      if (e instanceof AuthUnavailable) { authUnavailable = msg; await h.requeue(row, msg); released++; stop = i + 1; break; }
      await h.fail(row, msg); failed++;
      if (notes.length < 3) notes.push('#' + row.id + ': ' + msg.slice(0, 120));
      if (isAuthStop(e)) { stop = i + 1; break; }     // no_dropbox_auth: every further row would fail the same way
    }
  }
  const unreached = claimed.slice(stop).map((r) => r.id);
  if (unreached.length) released += await h.release(unreached);
  return { failed, released, authUnavailable, notes };
}
