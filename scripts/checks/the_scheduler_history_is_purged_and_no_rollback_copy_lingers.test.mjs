// THE SCHEDULER HISTORY IS PURGED AND NO ROLLBACK COPY LINGERS (it_engineer, 9 Nov 2026).
//
// Measured that day on production: the database was 11 GB for a company with no customers. 8.1 GB of it was
// public.kb_chunks_old, the rollback copy of the 6-7 Oct kb_chunks rewrite that the runbook said to drop the next
// day; 349 MB was cron.job_run_details, 698,599 rows since 19 Jul that nothing ever deleted (~26,000 a day).
// scripts/sql/the_kb_chunks_rollback_copy_is_dropped_and_scheduler_history_keeps_seven_days.sql fixed both.
//
// This fails if either comes back: a schema in which kb_chunks_old exists (the mirror, after its next
// regeneration) with no later MANIFEST file dropping it, or no hourly purge of the scheduler history.
// It reads the schema mirror (what production runs) together with the MANIFEST-listed SQL (what merges apply),
// because the mirror only catches up after the apply-at-merge and its regeneration.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const ROOT = join(import.meta.dirname, '..', '..');
const manifest = readFileSync(join(ROOT, 'scripts/sql/MANIFEST.txt'), 'utf8').split('\n').map((l) => l.trim())
  .filter((l) => l && !l.startsWith('#')).map((l) => (l.startsWith('scripts/') ? l : `scripts/sql/${l}`));
const applied = manifest.filter((f) => existsSync(join(ROOT, f))).map((f) => readFileSync(join(ROOT, f), 'utf8')).join('\n');
const mirror = readSchemaMirror();

test('no kb_chunks rollback copy outlives its rewrite', () => {
  const inMirror = /^CREATE TABLE (IF NOT EXISTS )?public\.kb_chunks_old\b/m.test(mirror);
  const dropped = /drop table if exists public\.kb_chunks_old\s*;/i.test(applied);
  assert.ok(!inMirror || dropped, 'public.kb_chunks_old is in the schema and no MANIFEST file drops it (docs/runbooks/kb_chunks_rewrite.md step 8)');
});

test('the scheduler history is purged every hour, in batches, keeping seven days', () => {
  const both = mirror + '\n' + applied;
  assert.match(both, /cron\.schedule\('cron_history_purge_hourly',\s*'37 \* \* \* \*',\s*\$CRON\$select public\.fn_cron_history_purge\(\);\$CRON\$\)/,
    'cron_history_purge_hourly is not scheduled');
  const fn = both.match(/function public\.fn_cron_history_purge\(p_keep interval default (?:interval )?'7 days'[^]*?\$fn\$;/i);
  assert.ok(fn, 'fn_cron_history_purge(p_keep interval default 7 days, p_batch) is not defined');
  assert.match(fn[0], /limit greatest\(p_batch, 1\)/, 'the purge must delete in bounded batches (21 Sep: an unbounded delete restarted production)');
  assert.match(both, /revoke execute on function public\.fn_cron_history_purge\(interval, int\) from public, anon, authenticated/i);
});
