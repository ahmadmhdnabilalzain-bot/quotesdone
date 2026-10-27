// THE SCHEDULES MOVED OFF GITHUB STAY ON PG_CRON, AND NO WORKFLOW STARTS ITSELF (it_engineer, 26 Oct 2026).
// Founder, 26 Oct 2026: Ubicloud stopped, no paid CI (GitHub-hosted minutes included) until the bugs clear.
// Fails if: a workflow regains an automatic trigger without the founder note being removed with it (a run would
// queue on a stopped runner or bill minutes), a workflow loses workflow_dispatch (it could not be run by hand), the
// pg_cron file stops scheduling the two moved jobs, or production lacks them once the file is applied.
//   node --test scripts/checks/the_schedules_moved_off_github_stay_on_pg_cron.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const NOTE = '# founder 26 Oct: automatic triggers off until bugs clear; re-enable push/pull_request/schedule then';
const FILE = 'scripts/sql/the_github_schedules_that_can_move_run_on_pg_cron_while_actions_are_off.sql';
const JOBS = ['dropbox_backup_second_scheduler', 'kb_embed_daily'];
const WF = '.github/workflows';

// The `on:` block of a workflow: the lines after `on:` up to the next top-level key.
const onBlock = (src) => {
  const lines = src.split(/\r?\n/); const at = lines.findIndex((l) => /^on:\s*$/.test(l));
  assert.ok(at >= 0, 'no block-style on:');
  const out = [];
  for (let i = at + 1; i < lines.length && (lines[i] === '' || /^\s/.test(lines[i]) || lines[i].startsWith('#')); i++) out.push(lines[i]);
  return { before: lines[at - 1], keys: out.map((l) => l.match(/^ {2}([a-z_]+):/)?.[1]).filter(Boolean) };
};

test('every workflow starts only by hand while the founder note stands above its triggers', () => {
  const files = readdirSync(WF).filter((f) => f.endsWith('.yml'));
  assert.ok(files.length > 0);
  for (const f of files) {
    const { before, keys } = onBlock(readFileSync(join(WF, f), 'utf8'));
    assert.ok(keys.includes('workflow_dispatch'), `${f}: no workflow_dispatch, so nobody can run it by hand`);
    if (before === NOTE) assert.deepEqual(keys, ['workflow_dispatch'], `${f}: an automatic trigger is live under the founder note`);
  }
});

test('the pg_cron file schedules both moved jobs and the heartbeat counts the pg_cron kick', () => {
  const src = readFileSync(FILE, 'utf8');
  for (const j of JOBS) assert.match(src, new RegExp(`cron\\.schedule\\('${j}'`), `${j} is not scheduled`);
  assert.match(src, /counts->>'reason' in \('github_actions', 'pg_cron_second_scheduler'\)/, 'dropbox_kick ignores the pg_cron kick');
  assert.match(src, /fn_kb_embed_scheduled_run\(\)[\s\S]*if coalesce\(\(v_t->'dispatch'->>'ok'\)::boolean, false\) then\s+perform public\.fn_it_duty_ran\('kb_embed'/,
    'the daily kb run beats without checking its dispatch');
  const manifest = readFileSync('scripts/sql/MANIFEST.txt', 'utf8').split(/\r?\n/).includes(FILE);
  const pending = existsSync(`scripts/sql/pending/${FILE.split('/').pop().replace(/\.sql$/, '.txt')}`);
  assert.ok(manifest !== pending, `${FILE}: exactly one of a pending note and a MANIFEST line`);
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const applied = readFileSync('scripts/sql/MANIFEST.txt', 'utf8').split(/\r?\n/).includes(FILE);

test('production: both moved jobs are scheduled and active', { skip: !hasToken ? 'no Supabase management token' : !applied ? 'file still pending' : false }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const rows = await sql(`select jobname from cron.job where active and jobname in (${JOBS.map((j) => `'${j}'`).join(',')})`);
  assert.deepEqual(rows.map((r) => r.jobname).sort(), [...JOBS].sort());
});
