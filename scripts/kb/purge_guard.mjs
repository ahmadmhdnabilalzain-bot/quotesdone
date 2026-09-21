// THE PURGE'S LOAD GUARD — the one place that decides whether the next batch may run.
//
// Seat: it_engineer. 21 Sep 2026: fn_kb_purge_batch(50000) planned a full-table scan, outlived the
// gateway, was retried on top of itself, and the production database restarted at 17:44:10 UTC after
// memory commitment passed its limit (scripts/sql/the_purge_cannot_take_the_database_down.sql has the
// measurements). purge_kb_bulk.mjs reads public.fn_kb_purge_load() and the management API's disk figure
// before EVERY batch and asks this module what to do. Pure functions, so the test replays the incident.

// Measured 21 Sep 2026: 5,000 rows = 2.4 s and 22.6 MB WAL; 2,000 rows = 2.0 s and 14.0 MB WAL.
export const BATCH_DEFAULT = 2000;
export const BATCH_MAX = 5000;          // the SQL refuses above this too
export const PAUSE_MS = 5000;           // ~7 s per 2,000-row batch => ~120 MB WAL a minute, ~2.4 h for 2.47 M rows

export const LIMITS = {
  walBytes: 2 * 1024 ** 3,              // pg_wal holds 1 GB at rest (min_wal_size); over 2 GB, checkpoints are behind
  diskFreeBytes: 3 * 1024 ** 3,         // 5.4 GB free on 21 Sep of an 18 GB disk; the purge writes ~11 GB of WAL in total
  activeOthers: 8,                      // other non-idle client backends (applies, crons, the site)
  longestActiveS: 60,                   // something heavy is running — let it finish first
};

// UAE night only: 23:00-06:00 Asia/Dubai. The daily export opens at 03:00 Dubai, so 02:50-03:00 waits too
// and a running export always waits (fn_kb_purge_load().export_running).
export function dubaiMinutes(date = new Date()) {
  const s = date.toLocaleTimeString('en-GB', { timeZone: 'Asia/Dubai', hour12: false, hour: '2-digit', minute: '2-digit' });
  const [h, m] = s.split(':').map(Number);
  return (h % 24) * 60 + m;
}
export function inNightWindow(date = new Date()) {
  const m = dubaiMinutes(date);
  return m >= 23 * 60 || m < 6 * 60;
}

/**
 * @param load  the jsonb of public.fn_kb_purge_load()
 * @param diskFreeBytes  fs_avail_bytes from /v1/projects/{ref}/config/disk/util (null = unknown)
 * @returns {{action: 'go'|'wait'|'stop', reason: string}}
 */
export function loadVerdict(load, diskFreeBytes, { now = new Date(), forceHours = false } = {}) {
  if (!load || typeof load !== 'object') return { action: 'stop', reason: 'the load guard returned nothing — refusing to delete blind' };
  if (Number(load.purge_running) > 0) return { action: 'stop', reason: `another purge batch is running (${load.purge_running}) — never overlap` };
  if (diskFreeBytes == null) return { action: 'stop', reason: 'disk free space unknown — refusing to write WAL blind' };
  if (Number(diskFreeBytes) < LIMITS.diskFreeBytes) return { action: 'stop', reason: `disk free ${(diskFreeBytes / 1024 ** 3).toFixed(1)} GB < ${LIMITS.diskFreeBytes / 1024 ** 3} GB` };
  if (!forceHours && !inNightWindow(now)) return { action: 'stop', reason: `outside 23:00-06:00 Asia/Dubai (it is ${load.dubai_time ?? 'unknown'}); re-run tonight or pass --force-hours` };
  const m = dubaiMinutes(now);
  if (!forceHours && m >= 2 * 60 + 50 && m < 3 * 60) return { action: 'wait', reason: 'the daily export opens at 03:00 Dubai' };
  if (load.export_running) return { action: 'wait', reason: 'the daily export is running' };
  if (Number(load.wal_bytes) > LIMITS.walBytes) return { action: 'wait', reason: `pg_wal ${(load.wal_bytes / 1024 ** 3).toFixed(2)} GB > ${LIMITS.walBytes / 1024 ** 3} GB — waiting for a checkpoint` };
  if (Number(load.active_others) > LIMITS.activeOthers) return { action: 'wait', reason: `${load.active_others} other active connections > ${LIMITS.activeOthers}` };
  if (Number(load.longest_active_s) > LIMITS.longestActiveS) return { action: 'wait', reason: `a statement has been running ${load.longest_active_s} s` };
  return { action: 'go', reason: 'load within limits' };
}
