// cad_dispatch.test — a customer page polling a CAD job raises the held finding at most once a minute, and only for a job the
// CAD read routine has not taken within its interval (10 Nov 2026, it_engineer, R3: nothing is dispatched to GitHub Actions any more).
//   deno test --no-lock --allow-read=. supabase/functions/customer_api/cad_dispatch.test.ts
// deno-lint-ignore-file no-explicit-any
import { assertEquals } from 'jsr:@std/assert@1';
import { CAD_READER_EVERY_MS, CAD_READER_GRACE_MS, cadJobNeedsRedispatch, claimCadDispatch } from './cad_dispatch.ts';

/** One cad_read_jobs row behind the PostgREST chain claimCadDispatch builds: the UPDATE applies only when the
 *  or-filter holds, exactly as `update ... where id = $1 and (last_dispatch_at is null or last_dispatch_at < $since)`. */
function fakeDb(row: { id: string; last_dispatch_at: string | null }, fail = false) {
  return { from: () => ({ update: (v: any) => ({ eq: (_k: string, id: string) => ({ or: (f: string) => ({ select: async () => {
    if (fail) return { data: null, error: { message: 'column "last_dispatch_at" does not exist' } };
    const since = f.match(/last_dispatch_at\.lt\.(.+)$/)![1];
    const ok = id === row.id && (row.last_dispatch_at === null || Date.parse(row.last_dispatch_at) < Date.parse(since));
    if (ok) row.last_dispatch_at = v.last_dispatch_at;
    return { data: ok ? [{ id }] : [], error: null };
  } }) }) }) }) };
}

const T0 = Date.parse('2026-11-03T10:00:00Z');
const job = (status: string, createdAgoMs: number, now: number, claimedAgoMs: number | null = null) =>
  ({ status, created_at: new Date(now - createdAgoMs).toISOString(), claimed_at: claimedAgoMs == null ? null : new Date(now - claimedAgoMs).toISOString() });

Deno.test('a page polling once a second for ten minutes after the routine missed a job raises the finding once a minute', async () => {
  const row = { id: 'j1', last_dispatch_at: null as string | null };
  const db = fakeDb(row);
  const late = CAD_READER_EVERY_MS + CAD_READER_GRACE_MS + 60_000;
  let raised = 0;
  for (let s = 0; s < 600; s++) {
    const now = T0 + s * 1000;
    const redo = cadJobNeedsRedispatch(job('queued', late + s * 1000, now), now);
    if (redo === 'held' && await claimCadDispatch(db, 'j1', now)) raised++;
  }
  assertEquals(raised, 10, 'one held finding per minute of polling, never one per poll');
});

// Proves the WHERE: a second claim in the same instant finds the window taken. That two isolates cannot both win is
// Postgres's (one UPDATE, row lock, WHERE re-read under READ COMMITTED), probed in the SQL file, not here.
Deno.test('a second claim in the same instant finds the slot taken', async () => {
  const db = fakeDb({ id: 'j1', last_dispatch_at: null });
  const won = await Promise.all([claimCadDispatch(db, 'j1', T0), claimCadDispatch(db, 'j1', T0)]);
  assertEquals(won.filter(Boolean).length, 1);
});

Deno.test('a queued job waits for the routine; only one it missed, or a silent worker, raises the held finding; nothing is dispatched', () => {
  assertEquals(cadJobNeedsRedispatch(job('queued', 5 * 60_000, T0), T0), null, 'queued minutes ago: the routine reads it at its next run');
  assertEquals(cadJobNeedsRedispatch(job('queued', CAD_READER_EVERY_MS, T0), T0), null, 'within the routine interval and its run time');
  assertEquals(cadJobNeedsRedispatch(job('queued', CAD_READER_EVERY_MS + CAD_READER_GRACE_MS + 1, T0), T0), 'held', 'the routine missed it');
  assertEquals(cadJobNeedsRedispatch(job('running', 10 * 60_000, T0, 5 * 60_000), T0), null, 'a worker is reading it');
  assertEquals(cadJobNeedsRedispatch(job('running', 40 * 60_000, T0, 31 * 60_000), T0), 'held', 'its worker went silent');
  assertEquals(cadJobNeedsRedispatch(job('done', 5 * 60_000, T0), T0), null);
});

Deno.test('a claim the database refuses is no dispatch', async () => {
  assertEquals(await claimCadDispatch(fakeDb({ id: 'j1', last_dispatch_at: null }, true), 'j1', T0), false);
});
