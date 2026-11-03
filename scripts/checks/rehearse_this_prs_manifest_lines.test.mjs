// THE REHEARSAL BEHIND "APPLIES AT MERGE", TESTED WITH PRODUCTION STUBBED (it_engineer, 3 Nov 2026).
//
// scripts/ci/rehearse_this_prs_manifest_lines.mjs runs in a throw-away git repository with the real scripts it uses
// (the rehearser, apply_sql.mjs's dry run, safe_replay, db.mjs) copied in. A preloaded module, inherited by the
// apply_sql child through NODE_OPTIONS, replaces fetch: it answers every query from the fixture, logs it, and never
// leaves this machine. The PR adds a.sql (fn_a, no probe), b.sql (fn_b calls fn_a, with a probe) and c.sql (fn_c).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const COPIED = ['scripts/ci/rehearse_this_prs_manifest_lines.mjs', 'scripts/ci/rehearse_sql.mjs', 'scripts/ci/apply_new_manifest_lines.mjs',
  'scripts/apply_sql.mjs', 'scripts/lib/applies_at_merge.mjs', 'scripts/lib/safe_replay.mjs', 'scripts/lib/db.mjs', 'scripts/lib/sql_text.mjs',
  'scripts/lib/supabase_token.mjs', 'scripts/lib/qd_guard.mjs', 'scripts/lib/apply_seat.mjs'];
// A replay answers as Postgres would: the probe's raise, the rows of a read-back, a syntax error, or the closing raise.
const STUB = `import { appendFileSync } from 'node:fs';
globalThis.fetch = async (url, init) => {
  if (!String(url).startsWith('https://api.supabase.com/')) throw new Error('the fixture reached ' + url);
  const q = JSON.parse(init.body).query;
  appendFileSync(process.env.FIXTURE_LOG, JSON.stringify(q) + '\\n');
  const err = (message) => new Response(JSON.stringify({ message }), { status: 400 });
  if (q.includes('pg_get_functiondef')) return new Response(JSON.stringify([{ fp: 'unchanged' }]), { status: 200 });
  if (!q.includes('SAFE_REPLAY_ROLLBACK')) return new Response('[]', { status: 200 });   // apply_sql's callee reads: nothing live
  if (q.includes('FAILME')) return err('ERROR: 42601: syntax error at or near "FAILME"');
  if (q.includes('SAFE_REPLAY_ROWS')) return err('ERROR: P0001: SAFE_REPLAY_ROWS<<' + process.env.FIXTURE_ROWS + '>>SAFE_REPLAY_ROWS');
  if (q.includes("raise exception 'PROBE OK'")) return err('ERROR: P0001: CHK<<PROBE OK>>');
  return err('ERROR: P0001: SAFE_REPLAY_ROLLBACK: the replay is always rolled back');
};\n`;
const fn = (name, body) => `create or replace function public.${name}() returns int language plpgsql as $f$ begin ${body} end $f$;\n`;
const ROWS = [{ proname: 'fn_a', prosrc: 'a' }, { proname: 'fn_b', prosrc: 'b' }, { proname: 'fn_c', prosrc: 'c' }];
const dirs = [];

function rehearse({ a = 'return 1;', aAlso = '', b = 'return public.fn_a();', c = 'return 3;', rows = ROWS } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'rehearse-pr-')); dirs.push(dir);
  const put = (p, text) => { mkdirSync(join(dir, p, '..'), { recursive: true }); writeFileSync(join(dir, p), text); };
  const git = (...a) => execFileSync('git', ['-c', 'core.autocrlf=false', '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', ...a],
    { cwd: dir, encoding: 'utf8' }).trim();
  for (const f of COPIED) cpSync(join(REPO, f), join(dir, f));
  put('stub_fetch.mjs', STUB);
  put('scripts/sql/old.sql', fn('fn_old', 'return 0;'));
  put('scripts/sql/MANIFEST.txt', 'scripts/sql/old.sql\n');
  git('init', '-q'); git('add', '-A'); git('commit', '-qm', 'main');
  const base = git('rev-parse', 'HEAD');
  put('scripts/sql/a.sql', fn('fn_a', a) + aAlso);
  put('scripts/sql/b.sql', fn('fn_b', b));
  put('scripts/sql/b_probe.sql', "do $p$ begin raise exception 'PROBE OK'; end $p$;\n");
  put('scripts/sql/c.sql', fn('fn_c', c));
  put('scripts/sql/MANIFEST.txt', 'scripts/sql/old.sql\nscripts/sql/a.sql\nscripts/sql/b.sql\nscripts/sql/c.sql\n');
  git('add', '-A'); git('commit', '-qm', 'the pull request');
  const log = join(dir, 'queries.log'), out = join(dir, 'results.json');
  const env = { ...process.env, SUPABASE_ACCESS_TOKEN: 'fixture-not-a-token', FIXTURE_LOG: log, FIXTURE_ROWS: JSON.stringify(rows),
    NODE_OPTIONS: `--import=${pathToFileURL(join(dir, 'stub_fetch.mjs')).href}` };
  const r = spawnSync(process.execPath, ['scripts/ci/rehearse_this_prs_manifest_lines.mjs', base, out], { cwd: dir, env, encoding: 'utf8' });
  const queries = existsSync(log) ? readFileSync(log, 'utf8').trim().split('\n').map((l) => JSON.parse(l)) : [];
  return { code: r.status, stdout: r.stdout + r.stderr, results: JSON.parse(readFileSync(out, 'utf8')),
    replays: queries.filter((q) => q.includes('SAFE_REPLAY_ROLLBACK')) };
}
const verdicts = (results) => results.files.map((f) => f.verdict.split(':')[0]);

test('a probe replays its file on top of the earlier ones, and one read-back replays all of them; every replay is time-limited', () => {
  const { code, stdout, results, replays } = rehearse();
  assert.equal(code, 0, stdout);
  assert.deepEqual(verdicts(results), ['REHEARSED', 'PROBE OK', 'REHEARSED'], stdout);
  assert.equal(replays.length, 2, 'one probe replay (b) and one read-back, nothing more:\n' + replays.join('\n----\n'));
  const [probe, readBack] = replays;
  const defines = (q, n) => q.includes(`create or replace function public.fn_${n}()`);
  assert.ok(defines(probe, 'a') && defines(probe, 'b') && probe.includes("'PROBE OK'") && !defines(probe, 'c'), probe);
  assert.ok(defines(readBack, 'a') && defines(readBack, 'b') && defines(readBack, 'c') && readBack.includes('SAFE_REPLAY_ROWS'), readBack);
  for (const q of replays) assert.match(q, /^set local lock_timeout = '5s';\nset local statement_timeout = '90s';/, q);
  assert.deepEqual(results.post_state, { ok: true, routines: { fn_a: ['a'], fn_b: ['b'], fn_c: ['c'] } });
});

test('the first failure stops the rest: nothing after it is rehearsed and there is no read-back', () => {
  const probeFails = rehearse({ b: 'return FAILME;' });
  assert.deepEqual(verdicts(probeFails.results), ['NOT REHEARSED', 'FAILED', 'NOT REHEARSED'], probeFails.stdout);
  assert.equal(probeFails.results.post_state, null);
  assert.ok(!probeFails.replays.some((q) => q.includes('SAFE_REPLAY_ROWS')), 'a read-back ran after a failure');
  const firstFails = rehearse({ a: 'return public.fn_nowhere();' });
  assert.equal(firstFails.code, 0, firstFails.stdout);
  assert.deepEqual(verdicts(firstFails.results), ['FAILED', 'NOT REHEARSED', 'NOT REHEARSED'], firstFails.stdout);
  assert.equal(firstFails.replays.length, 0, 'b was replayed after a had failed:\n' + firstFails.replays.join('\n----\n'));
});

test('apply_sql.mjs\'s guards run first: a callee nobody defines is refused, one an earlier file of the PR defines is not', () => {
  const { code, stdout, results, replays } = rehearse({ c: 'return public.fn_nowhere();' });
  assert.equal(code, 0, stdout);
  assert.deepEqual(verdicts(results), ['NOT REHEARSED', 'PROBE OK', 'FAILED'], stdout);
  assert.match(results.files[2].verdict, /apply_sql\.mjs refused it \(exit 4\)[\s\S]*fn_nowhere/, results.files[2].verdict);
  assert.ok(!replays.some((q) => q.includes('SAFE_REPLAY_ROWS')), 'a read-back ran after a refusal');
});

test('a commented-out or dropped definition in an earlier file is no credit: the merge\'s dry run would refuse the call', () => {
  for (const [why, aAlso] of [
    ['commented out', '-- retired: create or replace function public.fn_ghost(\n'],
    ['defined, then dropped', fn('fn_ghost', 'return 9;') + 'drop function public.fn_ghost();\n'],
  ]) {
    const { code, stdout, results, replays } = rehearse({ aAlso, c: 'return public.fn_ghost();' });
    assert.equal(code, 0, stdout);
    assert.deepEqual(verdicts(results), ['NOT REHEARSED', 'PROBE OK', 'FAILED'], `${why}:\n${stdout}`);
    assert.match(results.files[2].verdict, /apply_sql\.mjs refused it \(exit 4\)[\s\S]*fn_ghost/, `${why}: ${results.files[2].verdict}`);
    assert.ok(!replays.some((q) => q.includes('SAFE_REPLAY_ROWS')), `${why}: a read-back ran after a refusal`);
  }
});

test('a credited routine the read-back does not hold fails the file that called it', () => {
  const { code, stdout, results } = rehearse({ rows: ROWS.filter((r) => r.proname !== 'fn_a') });
  assert.equal(code, 0, stdout);
  assert.deepEqual(verdicts(results), ['REHEARSED', 'FAILED', 'REHEARSED'], stdout);
  assert.match(results.files[1].verdict, /calls on fn_a, credited to an earlier file/, results.files[1].verdict);
});

test.after(() => { for (const d of dirs) rmSync(d, { recursive: true, force: true }); });
