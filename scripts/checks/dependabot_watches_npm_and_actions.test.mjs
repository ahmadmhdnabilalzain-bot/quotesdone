// DEPENDABOT WATCHES NPM AND GITHUB ACTIONS (it_engineer, 28 Sep 2026).
//
// Gap: the repository had no .github/dependabot.yml, so no advisory published after a merge ever raised
// a PR. Prevented by: this check fails if the file is missing or drops the npm or github-actions ecosystem.
// (npm audit --audit-level=high in checks.yml refuses a PR that ships a known advisory; this covers later ones.)
//
//   node --test scripts/checks/dependabot_watches_npm_and_actions.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const path = new URL('../../.github/dependabot.yml', import.meta.url);

test('dependabot.yml exists and covers npm and github-actions', () => {
  assert.ok(existsSync(path), '.github/dependabot.yml is missing');
  const text = readFileSync(path, 'utf8');
  assert.match(text, /^version:\s*2\s*$/m);
  for (const eco of ['npm', 'github-actions']) {
    assert.match(text, new RegExp(`package-ecosystem:\\s*["']?${eco}["']?\\s*$`, 'm'), `no ${eco} ecosystem`);
  }
});
