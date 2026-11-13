// A WRITE A PERSON DEPENDS ON IS RECORDED, OR ITS CALLER KNOWS IT WAS NOT (it_engineer, 13 Nov 2026).
//
// MEASURED 13 Nov 2026: while rolled-back rehearsals held table locks on production (scripts/lib/replay_guard.mjs), writes
// a person depended on were cancelled by the functions' 8 s statement timeout: a supplier's agreement certificate onto
// leads (compliance_archive, 07:46:10) and a customer's acceptance of the terms (kyc, 08:47), whose result kyc never read.
// Any table lock (an apply, a deploy's migration) can do the same, so these writes are read back and a blip is retried.
//
// The write must come back with the row(s) it wrote (`.select('id')`). A blip (statement or lock timeout, serialization
// failure, deadlock, a dropped connection, a 5xx) is tried again, 3 times in all, 0.8 s then 2 s apart; a caller passes
// only a write that is safe to repeat (the same values, or a compare-and-set). Anything else, or a blip that persists,
// comes back { ok: false } with the reason, and the caller says so to the person and to a seat.
export type WriteResult = { data: unknown[] | null; error: { message?: string; code?: string } | null };
export type Recorded = { ok: true; attempts: number; data: unknown[] } | { ok: false; attempts: number; reason: string; blip: boolean };

const BLIP = /statement timeout|lock timeout|canceling statement|57014|55P03|40001|40P01|fetch failed|connection|ECONNRESET|timed out|\b(?:HTTP|status) 5\d\d\b/i;
export const isBlip = (msg: string) => BLIP.test(msg);

export async function writeRecorded(write: () => PromiseLike<WriteResult>, waits: number[] = [800, 2000],
  sleep: (ms: number) => Promise<void> = (ms) => new Promise((r) => setTimeout(r, ms)),
  { emptyIsFinal = true }: { emptyIsFinal?: boolean } = {}): Promise<Recorded> {
  let reason = ''; let blip = false;
  for (let attempt = 1; attempt <= waits.length + 1; attempt++) {
    let res: WriteResult;
    try { res = await write(); } catch (e) { res = { data: null, error: { message: String((e as Error)?.message ?? e) } }; }
    if (!res.error && Array.isArray(res.data) && res.data.length > 0) return { ok: true, attempts: attempt, data: res.data };
    reason = res.error ? String(res.error.message ?? res.error.code ?? 'write failed') : 'the write matched no row';
    blip = !!res.error && isBlip(reason);
    if ((!res.error && emptyIsFinal) || (res.error && !blip) || attempt > waits.length) return { ok: false, attempts: attempt, reason: reason.slice(0, 300), blip };
    await sleep(waits[attempt - 1]);
  }
  return { ok: false, attempts: waits.length + 1, reason, blip };
}
