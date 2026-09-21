// THE PURGE CANNOT TAKE THE DATABASE DOWN — the recurrence check for the 21 Sep 2026 outage.
//
// fn_kb_purge_batch(50000) planned a whole-table scan, outlived the gateway, was retried on top of
// itself, and production restarted at 17:44:10 UTC. This FAILS if the batch size creeps back over the
// measured safe size, if the pick can plan a sequential scan again, if the driver retries a batch on a
// 5xx, runs a batch without the load guard, or runs outside UAE night hours; and it replays the guard's
// decisions on the incident's numbers. Reads committed files only — no database.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { BATCH_DEFAULT, BATCH_MAX, LIMITS, loadVerdict, inNightWindow } from './purge_guard.mjs';
import { pendingNotes } from '../lib/pending_sql.mjs';

const root = new URL('../../', import.meta.url);
const driver = readFileSync(new URL('scripts/kb/purge_kb_bulk.mjs', root), 'utf8');

// The definition that wins is the LAST file in MANIFEST/PENDING order that defines the routine; the check
// reads every file that defines fn_kb_purge_batch and holds the newest one (by MANIFEST, then PENDING) to it.
function latestBatchDefinition() {
  const order = [
    ...readFileSync(new URL('scripts/sql/MANIFEST.txt', root), 'utf8').split('\n'),
    ...pendingNotes().keys(),
  ].map(l => l.trim()).filter(l => l && !l.startsWith('#')).map(l => l.replace(/^scripts\/sql\//, ''));
  const files = readdirSync(new URL('scripts/sql/', root)).filter(f => f.endsWith('.sql'));
  let best = null, bestAt = -1;
  for (const f of files) {
    const src = readFileSync(new URL(`scripts/sql/${f}`, root), 'utf8');
    const m = src.match(/create or replace function public\.fn_kb_purge_batch\([\s\S]*?\nend \$\$;/i);
    if (!m) continue;
    const at = order.lastIndexOf(f);
    if (at > bestAt) { best = { file: f, body: m[0] }; bestAt = at; }
  }
  return best;
}

test('fn_kb_purge_batch: default and maximum are within the measured safe size, and the pick cannot seq-scan', () => {
  const d = latestBatchDefinition();
  assert.ok(d, 'no file in MANIFEST/PENDING defines fn_kb_purge_batch');
  const def = Number(d.body.match(/p_limit integer default (\d+)/i)?.[1]);
  const max = Number(d.body.match(/p_limit > (\d+)/)?.[1]);
  assert.ok(def > 0 && def <= BATCH_MAX, `${d.file}: default batch ${def} exceeds ${BATCH_MAX}`);
  assert.ok(max > 0 && max <= BATCH_MAX, `${d.file}: fn_kb_purge_batch accepts up to ${max} rows; measured safe maximum is ${BATCH_MAX}`);
  assert.match(d.body, /set enable_seqscan to 'off'/i, `${d.file}: the pick may plan a whole-table scan again (it did at 50,000)`);
  assert.match(d.body, /set max_parallel_workers_per_gather to '0'/i, `${d.file}: a batch may start parallel workers`);
  assert.match(d.body, /pg_try_advisory_xact_lock/, `${d.file}: two batches can overlap again`);
});

test('the driver: bounded limit, no 5xx retry on a batch, the load guard before every batch, night hours', () => {
  assert.ok(BATCH_DEFAULT <= BATCH_MAX && BATCH_MAX <= 5000, 'purge_guard.mjs raised the batch size past the measured 5,000');
  assert.match(driver, /LIMIT < 1 \|\| LIMIT > BATCH_MAX/, 'the driver no longer refuses a --limit above BATCH_MAX');
  const loop = driver.slice(driver.indexOf('── 3. The batches'), driver.indexOf('── 4. Reclaim'));
  assert.ok(loop.length > 0, 'the batch section moved; re-anchor this check');
  const call = loop.match(/fn_kb_purge_batch\(\$\{LIMIT\}\)`([^)]*)\)/);
  assert.ok(call && /0,\s*false/.test(call[1]), 'the batch call is retried on a 5xx again — a 524 leaves the backend running and a retry stacks a second batch');
  const guard = loop.indexOf('fn_kb_purge_load()'), verdict = loop.indexOf('loadVerdict('), batch = loop.indexOf('fn_kb_purge_batch(');
  assert.ok(guard > -1 && verdict > guard && batch > verdict, 'the batch loop no longer reads the load guard before each batch');
  assert.match(loop, /await sleep\(PAUSE_MS\)/, 'no pause between batches');
  assert.match(driver, /RUN && !FORCE_HOURS && !inNightWindow\(\)/, 'the driver no longer refuses to start outside UAE night hours');
});

test('the guard replays 21 Sep: an overlapping batch, no disk figure, daytime, full WAL and a busy database are not "go"', () => {
  const night = new Date('2026-09-21T20:30:00Z');          // 00:30 Dubai
  const calm = { wal_bytes: 1073741824, active_others: 2, longest_active_s: 1, purge_running: 0, export_running: false, dubai_time: '00:30' };
  const disk = 5432131584;                                   // measured fs_avail_bytes, 21 Sep 17:49 UTC
  assert.equal(loadVerdict(calm, disk, { now: night }).action, 'go');
  assert.equal(loadVerdict({ ...calm, purge_running: 1 }, disk, { now: night }).action, 'stop');
  assert.equal(loadVerdict(calm, null, { now: night }).action, 'stop');
  assert.equal(loadVerdict(null, disk, { now: night }).action, 'stop');
  assert.equal(loadVerdict(calm, 2 * 1024 ** 3, { now: night }).action, 'stop');
  assert.equal(loadVerdict(calm, disk, { now: new Date('2026-09-21T17:35:00Z') }).action, 'stop');  // 21:35 Dubai, the outage
  assert.equal(loadVerdict({ ...calm, wal_bytes: LIMITS.walBytes + 1 }, disk, { now: night }).action, 'wait');
  assert.equal(loadVerdict({ ...calm, active_others: 20 }, disk, { now: night }).action, 'wait');
  assert.equal(loadVerdict({ ...calm, longest_active_s: 81 }, disk, { now: night }).action, 'wait');  // the 81 s lock waits of 17:42
  assert.equal(loadVerdict({ ...calm, export_running: true }, disk, { now: night }).action, 'wait');
  assert.equal(loadVerdict(calm, disk, { now: new Date('2026-09-21T22:55:00Z') }).action, 'wait');   // 02:55 Dubai
  assert.equal(inNightWindow(new Date('2026-09-21T19:00:00Z')), true);   // 23:00 Dubai
  assert.equal(inNightWindow(new Date('2026-09-22T02:00:00Z')), false);  // 06:00 Dubai
});
