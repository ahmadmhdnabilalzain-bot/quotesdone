// THE CHECK OF THE CHECK: a pull request is not red for what its own merge applies, and nothing else is set aside
// (it_engineer, 3 Nov 2026; the rule is in scripts/lib/applies_at_merge.mjs).
//
// The REAL canonical_routine_manifest.mjs runs in a throw-away git repository: the check and the four libraries it
// imports are copied in, so it reads the fixture's MANIFEST, pending notes and mirror, never this repository's.
// Production is a stub: a preloaded module replaces fetch, so every query the check sends is answered from the
// fixture and nothing leaves this machine. One routine in an old, applied file (fn_old) and one in the PR's new
// file (fn_new, not live, with a _probe.sql sibling).
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
const OLD = 'select 1;', NEW = 'select 2;', PROBE = "do $p$ begin raise exception 'PROBE OK'; end $p$;";
const fn = (name, body) => `create or replace function public.${name}() returns int language sql as $f$ ${body} $f$;\n`;

const dir = mkdtempSync(join(tmpdir(), 'applies-at-merge-'));
const put = (p, text) => { mkdirSync(join(dir, p, '..'), { recursive: true }); writeFileSync(join(dir, p), text); };
const git = (...a) => execFileSync('git', ['-c', 'core.autocrlf=false', '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', ...a], { cwd: dir, encoding: 'utf8' }).trim();
for (const f of ['scripts/checks/canonical_routine_manifest.mjs', 'scripts/lib/supabase_token.mjs', 'scripts/lib/pending_sql.mjs',
  'scripts/lib/schema_mirror.mjs', 'scripts/lib/applies_at_merge.mjs']) cpSync(join(REPO, f), join(dir, f));
for (const p of PARTS) put(`supabase/schema/full_schema/${p.file}`, '');
put('scripts/sql/old.sql', fn('fn_old', OLD));
put('scripts/sql/MANIFEST.txt', 'scripts/sql/old.sql\n');
git('init', '-q'); git('add', '-A'); git('commit', '-qm', 'main');
const BASE = git('rev-parse', 'HEAD');
put('scripts/sql/new.sql', fn('fn_new', NEW));
put('scripts/sql/new_probe.sql', PROBE);
put('scripts/sql/pending/new_probe.txt', 'A PROBE: runs after new.sql is applied');
put('scripts/sql/MANIFEST.txt', 'scripts/sql/old.sql\nscripts/sql/new.sql\n');
git('add', '-A'); git('commit', '-qm', 'the pull request');

// Production, as the stub answers it: rows for the routine query, nothing for the DDL query.
put('stub_fetch.mjs', `globalThis.fetch = async (url, init) => {
  if (!String(url).startsWith('https://api.supabase.com/')) throw new Error('the fixture reached ' + url);
  const q = JSON.parse(init.body).query;
  const rows = q.includes('pg_get_function_identity_arguments') ? JSON.parse(process.env.FIXTURE_LIVE) : [];
  return new Response(JSON.stringify(rows), { status: 200 });
};\n`);
const live = (old = OLD) => [{ proname: 'fn_old', sig_args: '', prosrc: ` ${old} `, nspname: 'public', owner: 'postgres', ext: 0 }];
const rehearsed = (over = {}) => ({
  base: BASE, error: '',
  files: [{ file: 'scripts/sql/new.sql', sha256: sha256(fn('fn_new', NEW)), probe: 'scripts/sql/new_probe.sql', probe_sha256: sha256(PROBE), verdict: 'PROBE OK', ...over.file }],
  post_state: over.post_state ?? { ok: true, routines: { fn_new: [` ${NEW} `] } },
});

function check({ event = 'pull_request', results = rehearsed(), old = OLD } = {}) {
  const resultsFile = join(dir, 'results.json');
  rmSync(resultsFile, { force: true });
  if (results) writeFileSync(resultsFile, JSON.stringify(results));
  const env = { ...process.env, SUPABASE_ACCESS_TOKEN: 'fixture-not-a-token', FIXTURE_LIVE: JSON.stringify(live(old)),
    GITHUB_EVENT_NAME: event, QD_PR_BASE_SHA: BASE, QD_REHEARSAL_RESULTS: resultsFile };
  delete env.QD_REQUIRE_GIT_HISTORY;
  const r = spawnSync(process.execPath, ['--import', pathToFileURL(join(dir, 'stub_fetch.mjs')).href, 'scripts/checks/canonical_routine_manifest.mjs', '--all'],
    { cwd: dir, env, encoding: 'utf8' });
  return { code: r.status, out: r.stdout + r.stderr };
}
const section = (out, title) => out.split(`\n${title}`)[1]?.split('\n\n')[0] ?? '';

test('(a) a PR adding a file whose routines are not live, rehearsed with PROBE OK and read back: exit 0, listed under APPLIES AT MERGE', () => {
  const { code, out } = check();
  assert.equal(code, 0, out);
  assert.match(section(out, 'APPLIES AT MERGE'), /: 1\n\s+fn_new\s+NOT PRESENT on production\s+\[scripts\/sql\/new\.sql\]/, out);
  assert.match(section(out, 'REPOSITORY -> PRODUCTION'), /: 0/, out);
});

test('(b) the same PR when the rehearsal failed, is missing, is stale, or reads back a different body: exit 1, the finding counts', () => {
  for (const [why, results] of [
    ['the probe failed', rehearsed({ file: { verdict: 'FAILED: PROBE FAILED: fn_new returned 3' } })],
    ['no rehearsal ran', null],
    ['the file changed after it was rehearsed', rehearsed({ file: { sha256: sha256('an earlier version') } })],
    ['the probe sibling was not used', rehearsed({ file: { probe: null, probe_sha256: null, verdict: 'REHEARSED' } })],
    ['the rehearsal was for another base', { ...rehearsed(), base: '0000000' }],
    ['the read-back is not the canonical body', rehearsed({ post_state: { ok: true, routines: { fn_new: [` ${NEW} `, ' select 9; '] } } })],
    ['the read-back failed', rehearsed({ post_state: { ok: false, error: 'HTTP 524' } })],
  ]) {
    const { code, out } = check({ results });
    assert.equal(code, 1, `${why}:\n${out}`);
    assert.match(section(out, 'REPOSITORY -> PRODUCTION'), /: 1\n\s+fn_new\s/, `${why}:\n${out}`);
    assert.match(section(out, 'APPLIES AT MERGE'), /: 0/, `${why}:\n${out}`);
  }
});

test('(c) drift in a file the PR did NOT add still fails, while the PR\'s own file is set aside', () => {
  const { code, out } = check({ old: 'select 7;' });
  assert.equal(code, 1, out);
  assert.match(section(out, 'REPOSITORY -> PRODUCTION'), /: 1\n\s+fn_old\s+DRIFTED.*\[scripts\/sql\/old\.sql\]/, out);
  assert.match(section(out, 'APPLIES AT MERGE'), /fn_new/, out);
});

test('(d) on push to main (and any run that is not a pull request) every drift counts, rehearsal or not', () => {
  for (const event of ['push', 'schedule', 'workflow_dispatch', '']) {
    const { code, out } = check({ event });
    assert.equal(code, 1, `${event}:\n${out}`);
    assert.match(section(out, 'REPOSITORY -> PRODUCTION'), /: 1\n\s+fn_new\s+NOT PRESENT/, `${event}:\n${out}`);
    assert.doesNotMatch(out, /APPLIES AT MERGE/, `${event}:\n${out}`);
  }
});

test.after(() => rmSync(dir, { recursive: true, force: true }));
