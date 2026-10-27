// EVERY THIRD-PARTY ACTION IS PINNED TO A COMMIT (pre-launch security audit, 27 Oct 2026; seat: it_engineer; ledger 1143).
//
// #1459 (Aikido, 19 Oct) pinned denoland/setup-deno and supabase/setup-cli to commits. Measured 27 Oct: the workflow
// added later, seat-exam-and-gap-audit.yml, ran denoland/setup-deno@v2 and anthropics/claude-code-action@v1 on mutable
// tags, in a job that writes the account-wide SUPABASE_ACCESS_TOKEN to disk and holds contents:write. Whoever can move
// one of those tags runs code with both. Nothing failed, because the pin was a one-time edit and not a rule.
//
// The rule: a `uses:` that is not GitHub's own (actions/*, github/*) and not a local path names a 40-hex commit.
// First-party actions/* on major tags are left alone deliberately (GitHub-owned; the same trust as the runner).
//
//   node --test scripts/checks/every_third_party_action_is_pinned_to_a_commit.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '.github', 'workflows');

export function unpinned(text, file = 'workflow.yml') {
  const out = [];
  text.split(/\r?\n/).forEach((line, i) => {
    const m = line.match(/^\s*-?\s*uses:\s*['"]?([^@\s'"#]+)@([^\s'"#]+)/);
    if (!m) return;
    const [, action, ref] = m;
    if (action.startsWith('./') || /^(actions|github)\//.test(action) || action.startsWith('docker://')) return;
    if (!/^[0-9a-f]{40}$/.test(ref)) out.push(`${file}:${i + 1} ${action}@${ref}`);
  });
  return out;
}

test('the rule catches a tag and passes a commit (the 27 Oct case)', () => {
  assert.deepEqual(unpinned('      - uses: anthropics/claude-code-action@v1\n        uses: denoland/setup-deno@v2\n'),
    ['workflow.yml:1 anthropics/claude-code-action@v1', 'workflow.yml:2 denoland/setup-deno@v2']);
  assert.deepEqual(unpinned('uses: denoland/setup-deno@22d081ff2d3a40755e97629de92e3bcbfa7cf2ed # v2.0.5\n'
    + 'uses: actions/checkout@v7\nuses: ./.github/actions/x\n'), []);
});

test('every third-party action in .github/workflows names a commit, not a tag', () => {
  const files = readdirSync(DIR).filter((f) => /\.ya?ml$/.test(f));
  assert.ok(files.length > 0, 'no workflow found: the walk is wrong, not the workflows');
  const found = files.flatMap((f) => unpinned(readFileSync(join(DIR, f), 'utf8'), f));
  assert.deepEqual(found, [],
    'third-party actions on a mutable ref:\n  ' + found.join('\n  ')
    + '\nPin each to the commit its tag points at today (git ls-remote --tags <repo>) and keep the tag as a comment.');
});
