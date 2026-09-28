// An unmerged file whose PR is red is refused by apply_sql.mjs --apply (28 Sep 2026, it_engineer).
// gh is mocked through QD_GH_CMD; the refusal happens before any database read. apply_sql's
// imports read a token at load, so a dummy one is passed (it is never sent anywhere). CI checks out
// shallow with no origin/main ref, so the "identical to main" case builds its own tiny repo.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync, execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { releaseRefusal } from '../lib/release_guard.mjs';

const dir = mkdtempSync(join(tmpdir(), 'release-guard-'));
const sqlFile = join(dir, 'never_merged.sql');
writeFileSync(sqlFile, 'select 1;\n');
const mockGh = (rollup) => {
  const f = join(dir, `gh_${Math.random().toString(36).slice(2)}.mjs`);
  writeFileSync(f, `process.stdout.write(${JSON.stringify(JSON.stringify({ number: 1, statusCheckRollup: rollup }))});`);
  return f;
};
const env = (gh) => ({ ...process.env, QD_GH_CMD: gh, GITHUB_ACTIONS: '', GITHUB_REF: '', SUPABASE_ACCESS_TOKEN: 'zz-not-a-token' });

test('apply_sql --apply refuses an unmerged file whose PR has a red check', () => {
  const gh = mockGh([{ name: 'checks', conclusion: 'FAILURE' }, { context: 'Vercel', state: 'SUCCESS' }]);
  const r = spawnSync(process.execPath, ['scripts/apply_sql.mjs', sqlFile, '--apply'], { env: env(gh), encoding: 'utf8' });
  assert.equal(r.status, 2, r.stdout + r.stderr);
  assert.match(r.stderr, /REFUSED: .*not on origin\/main.*not green: checks/);
  console.log('prevented by: scripts/lib/release_guard.mjs via apply_sql.mjs --apply -> ' + r.stderr.trim());
});

test('a pending check or no PR also refuses; all green, or a reasoned skip, passes', () => {
  process.env.GITHUB_ACTIONS = ''; process.env.GITHUB_REF = '';
  process.env.QD_GH_CMD = mockGh([{ name: 'checks', status: 'IN_PROGRESS', conclusion: '' }]);
  assert.match(releaseRefusal([sqlFile], []), /not green/);
  process.env.QD_GH_CMD = join(dir, 'missing_gh.mjs');
  assert.match(releaseRefusal([sqlFile], []), /no PR found/);
  process.env.QD_GH_CMD = mockGh([{ name: 'checks', conclusion: 'SUCCESS' }, { context: 'Vercel', state: 'SUCCESS' }]);
  assert.equal(releaseRefusal([sqlFile], []), null);
  assert.match(releaseRefusal([sqlFile], ['--skip-release-guard=']), /needs a reason/);
  assert.equal(releaseRefusal([sqlFile], ['--skip-release-guard=hotfix, founder outage']), null);
  delete process.env.QD_GH_CMD;
});

test('a file identical to origin/main passes without asking gh', () => {
  // A throwaway repo whose origin/main holds same.sql; edited.sql differs from it.
  const repo = mkdtempSync(join(tmpdir(), 'release-guard-repo-'));
  const g = (...a) => execFileSync('git', a, { cwd: repo, stdio: 'ignore' });
  g('init', '-q'); g('config', 'user.email', 'zz@example.invalid'); g('config', 'user.name', 'zz');
  writeFileSync(join(repo, 'same.sql'), 'select 1;\n'); writeFileSync(join(repo, 'edited.sql'), 'select 1;\n');
  g('add', '.'); g('commit', '-qm', 'main'); g('update-ref', 'refs/remotes/origin/main', 'HEAD');
  writeFileSync(join(repo, 'edited.sql'), 'select 2;\n');
  const cwd = process.cwd();
  try {
    process.chdir(repo);
    process.env.GITHUB_ACTIONS = ''; process.env.GITHUB_REF = '';
    process.env.QD_GH_CMD = join(dir, 'missing_gh.mjs');
    assert.equal(releaseRefusal(['same.sql'], []), null);
    // Control: the same repo refuses the edited file, so the pass above is not vacuous.
    assert.match(releaseRefusal(['edited.sql'], []), /not on origin\/main and no PR found/);
  } finally { process.chdir(cwd); delete process.env.QD_GH_CMD; }
});
