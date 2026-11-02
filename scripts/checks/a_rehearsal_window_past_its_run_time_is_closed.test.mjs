// A REHEARSAL WINDOW NEVER OUTLIVES ITS RUN (it_engineer, 13 Oct 2026).
//
// Measured 12-13 Oct: nine windows from post-deploy smokes (scripts/e2e/run.mjs) and demo_factory.withRun
// stayed open for hours, and stage2 refuses to start while any window is open.
// WHAT FAILS IF THE CAUSE RETURNS:
//   (a) closeOnExit no longer closes the window on SIGTERM, SIGINT, an uncaught exception or an unhandled
//       rejection (each simulated in a child process), or run.mjs / withRun stop arming it;
//   (b) fn_rehearsal_window_sweep closes a window before its expires_at (a 60-minute nightly with no model
//       calls included), leaves one past it open, or its cron is not registered to it_engineer
//       (production, one rolled-back request, ZZ windows only: the _probe.sql).
//
//   node --test scripts/checks/a_rehearsal_window_past_its_run_time_is_closed.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync, spawn } from 'node:child_process';
import { existsSync, readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { tmpdir, homedir } from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { pendingNotes } from '../lib/pending_sql.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const FACTORY = pathToFileURL(join(ROOT, 'scripts/lib/demo_factory.mjs')).href;

// A child that arms closeOnExit with a closer that writes a marker file, then ends itself the way `how` says.
const child = (how, marker) => `
import { closeOnExit } from ${JSON.stringify(FACTORY)};
import { writeFileSync } from 'node:fs';
closeOnExit(async () => { await new Promise((r) => setTimeout(r, 20)); writeFileSync(${JSON.stringify(marker)}, 'closed'); });
setInterval(() => {}, 1000);
${{ SIGTERM: "process.emit('SIGTERM');", SIGINT: "process.emit('SIGINT');",
    throw: "setTimeout(() => { throw new Error('simulated crash'); }, 10);",
    reject: "Promise.reject(new Error('simulated rejection'));",
    ready: "console.log('ready');" }[how]}
`;

for (const [how, code] of [['SIGTERM', 143], ['SIGINT', 130], ['throw', 1], ['reject', 1]]) {
  test(`(a) ${how} still closes the window before the process exits`, () => {
    const dir = mkdtempSync(join(tmpdir(), 'qd-rw-'));
    const marker = join(dir, 'closed');
    try {
      const r = spawnSync(process.execPath, ['--input-type=module', '-e', child(how, marker)], { encoding: 'utf8', timeout: 30000 });
      assert.ok(existsSync(marker), `window not closed on ${how}: ${r.stderr.slice(0, 400)}`);
      assert.equal(r.status, code);
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });
}

test('(a) a real SIGTERM from outside closes the window', { skip: process.platform === 'win32' ? 'Windows cannot deliver a catchable SIGTERM' : false }, async () => {
  const dir = mkdtempSync(join(tmpdir(), 'qd-rw-'));
  const marker = join(dir, 'closed');
  try {
    const p = spawn(process.execPath, ['--input-type=module', '-e', child('ready', marker)]);
    await new Promise((res) => p.stdout.on('data', res));
    p.kill('SIGTERM');
    const code = await new Promise((res) => p.on('exit', res));
    assert.ok(existsSync(marker), 'window not closed on an external SIGTERM');
    assert.equal(code, 143);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('(a) run.mjs and withRun arm closeOnExit with their own run tag and disarm in finally', () => {
  const run = R('scripts/e2e/run.mjs');
  // 27 Oct 2026: run.mjs arms closeRun (teardown AND the window), not the bare window close.
  assert.match(run, /const disarm = closeOnExit\(\(\) => closeRun\(run, \{ keep: KEEP \}\)\);/);
  assert.match(run.slice(run.indexOf('} finally {')), /closeRun\(run[^\n]*\n\s*disarm\(\);/);
  const fx = R('scripts/e2e/fixtures.mjs');
  assert.match(fx.slice(fx.indexOf('export async function closeRun')), /\} finally \{[\s\S]{0,400}update public\.rehearsal_window set ended_at = now\(\)/, 'closeRun must close the window in its finally');
  const f = R('scripts/lib/demo_factory.mjs');
  const w = f.slice(f.indexOf('export async function withRun'));
  // 27 Oct 2026: the exit handler tears the run down, and closes the window in its finally even when teardown throws.
  assert.match(w, /const disarm = closeOnExit\(async \(\) => \{\s*try \{ if \(!run\.keep\) await teardown\(run\); \} finally \{ await closeRehearsalWindow\(run\.tag\); \}\s*\}\);\s*try \{/);
  assert.match(w, /\} finally \{\s*disarm\(\);/);
});

test('(a) withRun closes the window even when teardown throws (#1436): the close sits in the finally of the teardown try', () => {
  const f = R('scripts/lib/demo_factory.mjs');
  const w = f.slice(f.indexOf('export async function withRun'), f.indexOf('// ---- auth'));
  assert.match(w, /await teardown\(run\);[\s\S]*?\}\s*\}\s*finally \{\s*try \{ await closeRehearsalWindow\(run\.tag\); \}/);
});

const FILE = 'scripts/sql/a_rehearsal_window_past_its_run_time_is_closed.sql';
const PROBE = 'scripts/sql/a_rehearsal_window_past_its_run_time_is_closed_probe.sql';

test('(b) the sweeper is house-shaped: pinned search_path, revoked, no transaction lines, probe note', () => {
  const s = R(FILE);
  assert.match(s, /set search_path to 'public', 'pg_temp'/);
  assert.match(s, /revoke execute on function public\.fn_rehearsal_window_sweep\(\) from public, anon, authenticated;/);
  assert.match(s, /cron\.schedule\('rehearsal_window_sweep'/);
  assert.match(s, /insert into public\.it_watch_finding/);
  assert.doesNotMatch(s.replace(/--.*$/gm, ''), /^\s*(begin|commit)\s*;/im);
  assert.match(pendingNotes().get(PROBE) || '', /^A PROBE\b/);
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('(b) production, rolled back, ZZ windows only: past expires_at closed and logged; smoke, 60-min nightly with no model calls and stage2 inside it left open; cron owned by it_engineer',
  { skip: hasToken ? false : 'no Supabase management token in this environment' }, async () => {
  const pre = pendingNotes().has(FILE) ? R(FILE) + '\n' : '';
  let out = null;
  try { await replaySql(pre + R(PROBE), { retry: false }); } catch (e) {
    const m = String(e.message || e).match(/CHK<<([\s\S]*)>>/);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message || e).slice(0, 800));
    out = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(out, 'the probe committed instead of rolling back');
  assert.equal(out.failures, '', out.failures);
});
