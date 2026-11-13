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
  'scripts/apply_sql.mjs', 'scripts/lib/applies_at_merge.mjs', 'scripts/lib/safe_replay.mjs', 'scripts/lib/replay_guard.mjs', 'scripts/lib/db.mjs', 'scripts/lib/sql_text.mjs',
  'scripts/lib/supabase_token.mjs', 'scripts/lib/qd_guard.mjs', 'scripts/lib/apply_seat.mjs'];
// A replay answers as Postgres would: the probe's raise, the rows of a read-back, a syntax error, or the closing raise.
const STUB = `import { appendFileSync } from 'node:fs';
globalThis.fetch = async (url, init) => {
  if (!String(url).startsWith('https://api.supabase.com/')) throw new Error('the fixture reached ' + url);
  const q = JSON.parse(init.body).query;
  appendFileSync(process.env.FIXTURE_LOG, JSON.stringify(q) + '\\n');
  const err = (message) => new Response(JSON.stringify({ message }), { status: 400 });
  if (q.includes('pg_get_functiondef')) return new Response(JSON.stringify([{ fp: 'unchanged' }]), { status: 200 });
  if (!q.includes('SAFE_REPLAY_ROLLBACK')) {   // apply_sql's callee reads: what production holds today
    const live = JSON.parse(q.includes('pg_class') ? process.env.FIXTURE_LIVE_RELATIONS : process.env.FIXTURE_LIVE);
    return new Response(JSON.stringify(live.map((n) => ({ n }))), { status: 200 });
  }
  if (q.includes('FAILME')) return err('ERROR: 42601: syntax error at or near "FAILME"');
  if (q.includes('SAFE_REPLAY_ROWS')) {
    // the read-back gets the fixture's rows; a file's own last statement answers with the literal verdict it selects
    const verdict = /from \\(\\s*select '([^']*)' as verdict\\s*;?\\s*\\) safe_replay_row/.exec(q);
    const rows = q.includes("'routine' as kind") ? process.env.FIXTURE_ROWS : JSON.stringify(verdict ? [{ verdict: verdict[1] }] : []);
    return err('ERROR: P0001: SAFE_REPLAY_ROWS<<' + rows + '>>SAFE_REPLAY_ROWS');
  }
  if (q.includes("raise exception 'PROBE OK'")) return err('ERROR: P0001: CHK<<PROBE OK>>');
  return err('ERROR: P0001: SAFE_REPLAY_ROLLBACK: the replay is always rolled back');
};\n`;
const fn = (name, body) => `create or replace function public.${name}() returns int language plpgsql as $f$ begin ${body} end $f$;\n`;
const ROWS = ['a', 'b', 'c'].map((x) => ({ kind: 'routine', name: `fn_${x}`, prosrc: x }));
const dirs = [];

function rehearse({ a = 'return 1;', aAlso = '', b = 'return public.fn_a();', c = 'return 3;', rows = ROWS, live = [], liveRelations = [] } = {}) {
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
  // fetch is stubbed (stub_fetch.mjs below), so the child reaches no host: it gets the fixture token even under the offline
  // gate, whose QD_OFFLINE=1 makes supabaseTokenOrEmpty() return '' (review of #1874, 9 Nov 2026).
  const env = { ...process.env, QD_OFFLINE: '', SUPABASE_ACCESS_TOKEN: 'fixture-not-a-token', FIXTURE_LOG: log, FIXTURE_ROWS: JSON.stringify(rows),
    FIXTURE_LIVE: JSON.stringify(live), FIXTURE_LIVE_RELATIONS: JSON.stringify(liveRelations),
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
  for (const q of replays) assert.match(q, /^set local lock_timeout = '1s'; set local transaction_timeout = '120s'; do \$qd_one\$[^\n]*\$qd_one\$; set local lock_timeout = '1s';\nset local statement_timeout = '90s';/, q);
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

test('a commented-out or dropped definition in an earlier file is no credit, and a call to it fails', () => {
  for (const [why, aAlso, said] of [
    ['commented out', '-- retired: create or replace function public.fn_ghost(\n', /apply_sql\.mjs refused it \(exit 4\)[\s\S]*fn_ghost/],
    ['defined, then dropped', fn('fn_ghost', 'return 9;') + 'drop function public.fn_ghost();\n', /calls fn_ghost, which an earlier file of this PR drops/],
  ]) {
    const { code, stdout, results, replays } = rehearse({ aAlso, c: 'return public.fn_ghost();' });
    assert.equal(code, 0, stdout);
    assert.deepEqual(verdicts(results), ['NOT REHEARSED', 'PROBE OK', 'FAILED'], `${why}:\n${stdout}`);
    assert.match(results.files[2].verdict, said, `${why}: ${results.files[2].verdict}`);
    assert.ok(!replays.some((q) => q.includes('SAFE_REPLAY_ROWS')), `${why}: a read-back ran after a refusal`);
  }
});

test('a routine LIVE today that an earlier file drops fails the later file that calls it, the drop plain or in a string', () => {
  for (const [why, aAlso] of [
    ['plain drop', 'drop function public.fn_ghost();\n'],
    ['drop inside an execute string', "do $d$ begin execute 'drop function if exists public.fn_ghost()'; end $d$;\n"],
  ]) {
    const { code, stdout, results } = rehearse({ aAlso, c: 'return public.fn_ghost();', live: ['fn_ghost'],
      rows: [...ROWS, { kind: 'routine', name: 'fn_ghost', prosrc: 'x' }] });
    assert.equal(code, 0, stdout);
    assert.deepEqual(verdicts(results), ['NOT REHEARSED', 'PROBE OK', 'FAILED'], `${why}:\n${stdout}`);
    assert.match(results.files[2].verdict, /calls fn_ghost, which an earlier file of this PR drops/, `${why}: ${results.files[2].verdict}`);
  }
});

test('anything a file calls that the read-back after every file does not hold fails it: credited, or live today', () => {
  const credited = rehearse({ rows: ROWS.filter((r) => r.name !== 'fn_a') });
  assert.equal(credited.code, 0, credited.stdout);
  assert.deepEqual(verdicts(credited.results), ['REHEARSED', 'FAILED', 'REHEARSED'], credited.stdout);
  assert.match(credited.results.files[1].verdict, /calls fn_a, and the read-back after every file of this PR holds no such routine or relation/);
  // live today, gone where no pattern can see it: the dry run passes, the read-back does not
  const liveToday = rehearse({ c: 'return public.fn_live();', live: ['fn_live'] });
  assert.deepEqual(verdicts(liveToday.results), ['REHEARSED', 'PROBE OK', 'FAILED'], liveToday.stdout);
  assert.match(liveToday.results.files[2].verdict, /calls fn_live, and the read-back/);
  const readBack = liveToday.replays.find((q) => q.includes('SAFE_REPLAY_ROWS')) || '';
  assert.match(readBack, /p\.proname = any\(array\[[^\]]*'fn_live'/, 'the read-back never asked for the callee:\n' + readBack);
  assert.match(readBack, /c\.relname = any\(array\[[^\]]*'fn_live'/, 'the read-back never asked whether the callee is a relation:\n' + readBack);
});

test('a file\'s own inline verdict is read as apply_sql reads it: PROBE OK passes, with nothing appended to the replay', () => {
  const { code, stdout, results, replays } = rehearse({ aAlso: "select 'PROBE OK: fn_a answers 1' as verdict;\n" });
  assert.equal(code, 0, stdout);
  assert.deepEqual(verdicts(results), ['REHEARSED', 'PROBE OK', 'REHEARSED'], stdout);
  assert.equal(replays.length, 3, 'a\'s own verdict, b\'s probe, and the read-back:\n' + replays.join('\n----\n'));
  const own = replays[0];
  assert.match(own, /^set local lock_timeout = '1s'; set local transaction_timeout = '120s'; do \$qd_one\$[^\n]*\$qd_one\$; set local lock_timeout = '1s';\nset local statement_timeout = '90s';/, own);
  assert.ok(/from \(\s*select 'PROBE OK: fn_a answers 1' as verdict/.test(own) && !own.includes('as rehearsed') && !own.includes('fn_b'), own);
});

test('a file\'s own inline verdict FAILS the file when it says PROBE FAILED, or promises one and returns none', () => {
  for (const [why, aAlso, said] of [
    ['PROBE FAILED', "select 'PROBE FAILED: fn_a returned 2' as verdict;\n", /its own verdict: PROBE FAILED: fn_a returned 2/],
    ['a marker, and the last statement is not a query', "do $v$ begin if false then raise exception 'PROBE OK'; end if; end $v$;\n", /promises a verdict[\s\S]*returned none/],
    ['a marker, and the last query returns no verdict', "select v from (values ('PROBE OK')) t(v) where false;\n", /promises a verdict[\s\S]*returned none/],
  ]) {
    const { code, stdout, results, replays } = rehearse({ aAlso });
    assert.equal(code, 0, stdout);
    assert.deepEqual(verdicts(results), ['FAILED', 'NOT REHEARSED', 'NOT REHEARSED'], `${why}:\n${stdout}`);
    assert.match(results.files[0].verdict, said, `${why}: ${results.files[0].verdict}`);
    assert.ok(!replays.some((q) => q.includes("'routine' as kind")), `${why}: a read-back ran after a failure`);
  }
  // a marker only in a comment is prose, not a promise (apply_sql's rule)
  const prose = rehearse({ aAlso: '-- the probe file must print PROBE OK\n' });
  assert.deepEqual(verdicts(prose.results), ['REHEARSED', 'PROBE OK', 'REHEARSED'], prose.stdout);
});

test('a call-shaped name that is a relation in the read-back is not a missing routine', () => {
  const { code, stdout, results } = rehearse({ c: 'insert into public.fn_tbl (x) values (1); return 3;', liveRelations: ['fn_tbl'],
    rows: [...ROWS, { kind: 'relation', name: 'fn_tbl', prosrc: null }] });
  assert.equal(code, 0, stdout);
  assert.deepEqual(verdicts(results), ['REHEARSED', 'PROBE OK', 'REHEARSED'], stdout);
});

test.after(() => { for (const d of dirs) rmSync(d, { recursive: true, force: true }); });
