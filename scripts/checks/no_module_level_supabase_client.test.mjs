// NO SUPABASE CLIENT IS BUILT AT IMPORT.
//
// 15 Sep 2026: a module-level createClient('') in CustomerPortal.tsx threw during prerender once
// the Preview env vars were deleted, and every Preview build failed. src/lib/supaClient.ts builds
// the client on first use; this fails if createClient( appears anywhere else in src/.
//
//   node --test scripts/checks/no_module_level_supabase_client.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const SRC = path.join(REPO, 'src');
const OWNER = path.join('src', 'lib', 'supaClient.ts');

test('createClient( is called only inside src/lib/supaClient.ts', () => {
  const hits = [];
  for (const f of readdirSync(SRC, { recursive: true })) {
    if (!/\.[cm]?[jt]sx?$/.test(f)) continue;
    const rel = path.join('src', f);
    if (rel === OWNER) continue;
    readFileSync(path.join(SRC, f), 'utf8').split('\n').forEach((line, i) => {
      if (/\bcreate(Browser|Server)?Client\s*\(/.test(line)) hits.push(`${rel}:${i + 1}`);
    });
  }
  assert.deepEqual(hits, [], 'build Supabase clients through supaClient() so nothing runs at import');
});
