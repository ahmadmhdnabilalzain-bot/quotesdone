// THE FUNCTION DEPLOY PINS ITS SUPABASE CLI (it_engineer, 21 Sep 2026).
//
// `supabase/setup-cli` with `version: latest` resolves the release through the GitHub API with no
// token; when the runner's shared rate limit is spent the deploy job fails before it deploys anything
// (PR #785, run 35627998129: "Failed to resolve latest Supabase CLI release: rate limit exceeded").
// Every workflow that installs the CLI must name an exact version.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';

const dir = new URL('../../.github/workflows/', import.meta.url);

test('every supabase/setup-cli step names an exact version', () => {
  let steps = 0;
  for (const f of readdirSync(dir).filter((n) => /\.ya?ml$/.test(n))) {
    const lines = readFileSync(new URL(f, dir), 'utf8').split('\n');
    lines.forEach((l, i) => {
      if (!/^\s*-?\s*uses:\s*supabase\/setup-cli@/.test(l)) return;
      steps++;
      const block = lines.slice(i + 1, i + 5).join('\n');
      const v = block.match(/^\s*version:\s*['"]?([^'"\s#]+)/m);
      assert.ok(v, `${f}:${i + 1} setup-cli has no version`);
      assert.match(v[1], /^\d+\.\d+\.\d+$/, `${f}:${i + 1} setup-cli version "${v[1]}" is not an exact release`);
    });
  }
  assert.ok(steps > 0, 'no supabase/setup-cli step found — the walk is wrong, not the workflows');
});
