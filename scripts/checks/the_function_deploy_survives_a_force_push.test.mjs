// scripts/ci/resolve_diff_base.sh must return a usable base after a rebase/force-push, where
// github.event.before is no longer in history. Builds a throwaway repo with an "origin" and
// simulates exactly that. (#1158, #1173, #1179, #1183, #1186, #1193 failed on it.)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const script = resolve('scripts/ci/resolve_diff_base.sh');

test('a force-pushed branch resolves to the merge-base with main, without error', () => {
  const dir = mkdtempSync(join(tmpdir(), 'qd-diffbase-'));
  try {
    const git = (...a) => execFileSync('git', a, { cwd: dir, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
    const commit = (f) => { writeFileSync(join(dir, f), f); git('add', f); git('commit', '-qm', f); return git('rev-parse', 'HEAD'); };
    const resolveBase = (...a) => execFileSync('bash', [script, ...a], { cwd: dir, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();

    git('init', '-q', '-b', 'main');
    git('config', 'user.email', 't@example.invalid'); git('config', 'user.name', 't');
    const m1 = commit('m1');
    git('update-ref', 'refs/remotes/origin/main', m1);
    git('checkout', '-qb', 'feature');
    const oldTip = commit('f1');
    // force-push: rewrite the branch so oldTip is no longer an ancestor
    git('reset', '-q', '--hard', m1);
    const newTip = commit('f1b');

    assert.equal(resolveBase(oldTip, 'main', 'false'), m1, 'rewritten before -> merge-base');
    assert.equal(resolveBase('deadbeef'.repeat(5), 'main', 'false'), m1, 'missing before -> merge-base');
    assert.equal(resolveBase('0'.repeat(40), 'main', 'false'), m1, 'all-zeros before -> merge-base');
    // the diff the old workflow choked on now runs
    execFileSync('git', ['diff', '--name-only', `${resolveBase(oldTip, 'main', 'false')}...HEAD`], { cwd: dir });

    // normal push: before is an ancestor, used as-is (main's post-merge behaviour unchanged)
    const next = commit('f2');
    assert.equal(resolveBase(newTip, 'main', 'false'), newTip);
    assert.equal(resolveBase(newTip, 'main', 'true'), newTip);
    // main with an unusable before -> HEAD~1
    assert.equal(resolveBase(oldTip, 'main', 'true'), newTip);
    assert.ok(next);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
