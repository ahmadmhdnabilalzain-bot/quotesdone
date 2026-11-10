// THE CHECK OF THE CHECK: a pull request is not red for what its own merge applies, and nothing else is set aside
// (it_engineer, 3 Nov 2026; the rule is in scripts/lib/applies_at_merge.mjs).
//
// The REAL canonical_routine_manifest.mjs runs in throw-away git repositories: the check and the libraries it imports
// are copied in, so it reads each fixture's MANIFEST, pending notes and mirror, never this repository's. Production is
// a stub: a preloaded module replaces fetch, so every query the check sends is answered from the fixture and nothing
// leaves this machine. Main holds applied files (old.sql: fn_old and other.sql: fn_other, both live); the PR adds
// new.sql (fn_new, not live, with a _probe.sql sibling) unless a case says otherwise.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { cpSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { PARTS } from '../lib/schema_mirror.mjs';
import { sha256 } from '../lib/applies_at_merge.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const OLD = 'select 1;', OTHER = 'select 5;', NEW = 'select 2;', NEW2 = 'select 3;', PROBE = "do $p$ begin raise exception 'PROBE OK'; end $p$;";
const fn = (name, body) => `create or replace function public.${name}() returns int language sql as $f$ ${body} $f$;\n`;
const COPIED = ['scripts/checks/canonical_routine_manifest.mjs', 'scripts/lib/canonical_routines.mjs', 'scripts/lib/supabase_token.mjs', 'scripts/lib/pending_sql.mjs',
  'scripts/lib/schema_mirror.mjs', 'scripts/lib/applies_at_merge.mjs', 'scripts/ci/apply_new_manifest_lines.mjs'];
const STUB = `globalThis.fetch = async (url, init) => {
  if (!String(url).startsWith('https://api.supabase.com/')) throw new Error('the fixture reached ' + url);
  const q = JSON.parse(init.body).query;
  const rows = q.includes('pg_get_function_identity_arguments') ? JSON.parse(process.env.FIXTURE_LIVE) : [];
  return new Response(JSON.stringify(rows), { status: 200 });
};\n`;
const dirs = [];

/** A fixture repository: main's MANIFEST (`main`, other.sql always listed), then the PR commit (`pr`). */
function fixture({ main = ['old'], pr = ['old', 'new'], prFiles = { new: NEW }, mainAlreadyHasThePr = false } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'applies-at-merge-')); dirs.push(dir);
  const put = (p, text) => { mkdirSync(join(dir, p, '..'), { recursive: true }); writeFileSync(join(dir, p), text); };
  const git = (...a) => execFileSync('git', ['-c', 'core.autocrlf=false', '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', ...a],
    { cwd: dir, encoding: 'utf8' }).trim();
  const manifest = (names) => [...names, ...(names.includes('other') ? [] : ['other'])]
    .map((n) => (n.startsWith('"') ? `"scripts/sql/${n.slice(1)}.sql"` : `scripts/sql/${n}.sql`)).join('\n') + '\n';
  for (const f of COPIED) cpSync(join(REPO, f), join(dir, f));
  for (const p of PARTS) put(`supabase/schema/full_schema/${p.file}`, '');
  put('stub_fetch.mjs', STUB);
  put('scripts/sql/old.sql', fn('fn_old', OLD));
  put('scripts/sql/other.sql', fn('fn_other', OTHER));
  put('scripts/sql/MANIFEST.txt', manifest(main));
  git('init', '-q'); git('add', '-A'); git('commit', '-qm', 'main');
  const base = git('rev-parse', 'HEAD');
  for (const [n, body] of Object.entries(prFiles)) put(`scripts/sql/${n}.sql`, fn(`fn_${n}`, body));
  put('scripts/sql/new_probe.sql', PROBE);
  put('scripts/sql/pending/new_probe.txt', 'A PROBE: runs after new.sql is applied');
  put('scripts/sql/MANIFEST.txt', manifest(pr));
  git('add', '-A'); git('commit', '-qm', 'the pull request');
  // main moved on after the PR's base sha and already lists the PR's line
  if (mainAlreadyHasThePr) git('update-ref', 'refs/remotes/origin/main', 'HEAD');
  return { dir, base };
}

const liveRows = (old) => [
  { proname: 'fn_old', sig_args: '', prosrc: ` ${old} `, nspname: 'public', owner: 'postgres', ext: 0 },
  { proname: 'fn_other', sig_args: '', prosrc: ` ${OTHER} `, nspname: 'public', owner: 'postgres', ext: 0 },
];
const entry = (file, body, over = {}) => ({ file: `scripts/sql/${file}.sql`, sha256: sha256(fn(`fn_${file}`, body)),
  probe: file === 'new' ? 'scripts/sql/new_probe.sql' : null, probe_sha256: file === 'new' ? sha256(PROBE) : null,
  verdict: file === 'new' ? 'PROBE OK' : 'REHEARSED', ...over });
const rehearsed = (base, { file = {}, files, post_state } = {}) => ({
  base, error: '', files: files ?? [entry('new', NEW, file)],
  post_state: post_state ?? { ok: true, routines: { fn_new: [` ${NEW} `] } },
});

function check({ dir, base }, { event = 'pull_request', results = rehearsed(base), old = OLD } = {}) {
  const resultsFile = join(dir, 'results.json');
  rmSync(resultsFile, { force: true });
  if (results) writeFileSync(resultsFile, JSON.stringify(results));
  const env = { ...process.env, SUPABASE_ACCESS_TOKEN: 'fixture-not-a-token', FIXTURE_LIVE: JSON.stringify(liveRows(old)),
    GITHUB_EVENT_NAME: event, QD_PR_BASE_SHA: base, QD_REHEARSAL_RESULTS: resultsFile };
  delete env.QD_REQUIRE_GIT_HISTORY; delete env.NODE_OPTIONS;
  const r = spawnSync(process.execPath, ['--import', pathToFileURL(join(dir, 'stub_fetch.mjs')).href, 'scripts/checks/canonical_routine_manifest.mjs', '--all'],
    { cwd: dir, env, encoding: 'utf8' });
  return { code: r.status, out: r.stdout + r.stderr };
}
const section = (out, title) => out.split(`\n${title}`)[1]?.split('\n\n')[0] ?? '';
const listed = (out, title, name) => new RegExp(`\\n\\s+${name}\\s`).test(section(out, title));
const counted = (out, name) => listed(out, 'REPOSITORY -> PRODUCTION', name);
const setAside = (out, name) => listed(out, 'APPLIES AT MERGE', name);

const ONE = fixture();

test('(a) a PR adding a file whose routines are not live, rehearsed with PROBE OK and read back: exit 0, listed under APPLIES AT MERGE', () => {
  const { code, out } = check(ONE);
  assert.equal(code, 0, out);
  assert.match(section(out, 'APPLIES AT MERGE'), /: 1\n\s+fn_new\s+NOT PRESENT on production\s+\[scripts\/sql\/new\.sql\]/, out);
  assert.match(section(out, 'REPOSITORY -> PRODUCTION'), /: 0/, out);
});

test('(b) the same PR when the rehearsal failed, is missing, is stale, or reads back a different body: exit 1, the finding counts', () => {
  for (const [why, results] of [
    ['the probe failed', rehearsed(ONE.base, { file: { verdict: 'FAILED: PROBE FAILED: fn_new returned 3' } })],
    ['no rehearsal ran', null],
    ['the file changed after it was rehearsed', rehearsed(ONE.base, { file: { sha256: sha256('an earlier version') } })],
    ['the probe changed after it was rehearsed', rehearsed(ONE.base, { file: { probe_sha256: sha256('an earlier probe') } })],
    ['the probe sibling was not used', rehearsed(ONE.base, { file: { probe: null, probe_sha256: null, verdict: 'REHEARSED' } })],
    ['the rehearsal was for another base', { ...rehearsed(ONE.base), base: '0000000' }],
    ['the read-back is not the canonical body', rehearsed(ONE.base, { post_state: { ok: true, routines: { fn_new: [` ${NEW} `, ' select 9; '] } } })],
    ['the read-back failed', rehearsed(ONE.base, { post_state: { ok: false, error: 'HTTP 524' } })],
  ]) {
    const { code, out } = check(ONE, { results });
    assert.equal(code, 1, `${why}:\n${out}`);
    assert.ok(counted(out, 'fn_new') && !setAside(out, 'fn_new'), `${why}:\n${out}`);
  }
});

test('(c) drift in a file the PR did NOT add still fails, even when the read-back carries that routine\'s canonical body', () => {
  const results = rehearsed(ONE.base, { post_state: { ok: true, routines: { fn_new: [` ${NEW} `], fn_old: [` ${OLD} `] } } });
  const { code, out } = check(ONE, { old: 'select 7;', results });
  assert.equal(code, 1, out);
  assert.match(section(out, 'REPOSITORY -> PRODUCTION'), /: 1\n\s+fn_old\s+DRIFTED.*\[scripts\/sql\/old\.sql\]/, out);
  assert.ok(setAside(out, 'fn_new'), out);
});

test('(d) on push to main (and any run that is not a pull request) every drift counts, rehearsal or not', () => {
  for (const event of ['push', 'schedule', 'workflow_dispatch', '']) {
    const { code, out } = check(ONE, { event });
    assert.equal(code, 1, `${event}:\n${out}`);
    assert.match(section(out, 'REPOSITORY -> PRODUCTION'), /: 1\n\s+fn_new\s+NOT PRESENT/, `${event}:\n${out}`);
    assert.doesNotMatch(out, /APPLIES AT MERGE/, `${event}:\n${out}`);
  }
});

test('(e) the set is the set the merge applies: a quoted new line, which the merge never applies, counts', () => {
  const f = fixture({ pr: ['old', '"new'] });
  const { code, out } = check(f, { results: rehearsed(f.base) });
  assert.equal(code, 1, out);
  assert.ok(counted(out, 'fn_new') && !setAside(out, 'fn_new'), out);
  assert.match(out, /STILL COUNTs: the merge would apply \[\] but the MANIFEST lines new to main are \[scripts\/sql\/new\.sql\]/, out);
});

test('(f) a moved existing line, which the merge re-applies unrehearsed, makes every finding count', () => {
  const f = fixture({ main: ['old', 'other'], pr: ['other', 'old', 'new'] });
  const { code, out } = check(f, { results: rehearsed(f.base) });
  assert.equal(code, 1, out);
  assert.ok(counted(out, 'fn_new') && !setAside(out, 'fn_new'), out);
  assert.match(out, /STILL COUNTs: the merge would apply \[[^\]]*scripts\/sql\/(old|other)\.sql/, out);
});

test('(g) a rehearsal that covered only one of the PR\'s two files sets nothing aside; one covering both does', () => {
  const f = fixture({ pr: ['old', 'new', 'new2'], prFiles: { new: NEW, new2: NEW2 } });
  const routines = { fn_new: [` ${NEW} `], fn_new2: [` ${NEW2} `] };
  const partial = check(f, { results: rehearsed(f.base, { post_state: { ok: true, routines } }) });
  assert.equal(partial.code, 1, partial.out);
  assert.ok(counted(partial.out, 'fn_new') && counted(partial.out, 'fn_new2'), partial.out);
  const both = check(f, { results: rehearsed(f.base, { files: [entry('new', NEW), entry('new2', NEW2)], post_state: { ok: true, routines } }) });
  assert.equal(both.code, 0, both.out);
  assert.ok(setAside(both.out, 'fn_new') && setAside(both.out, 'fn_new2'), both.out);
});

test('(h) a line origin/main already lists is not this PR\'s, even when the event\'s base sha is older', () => {
  const f = fixture({ mainAlreadyHasThePr: true });
  const { code, out } = check(f, { results: rehearsed(f.base) });
  assert.equal(code, 1, out);
  assert.ok(counted(out, 'fn_new') && !setAside(out, 'fn_new'), out);
});

test.after(() => { for (const d of dirs) rmSync(d, { recursive: true, force: true }); });
