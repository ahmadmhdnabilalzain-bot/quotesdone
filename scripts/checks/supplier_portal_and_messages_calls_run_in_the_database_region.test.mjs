// THE SUPPLIER PORTAL AND THE MESSAGE CENTRE CALL THEIR FUNCTIONS IN THE DATABASE'S REGION.
//
// 21 Sep 2026, it_watch_finding latency: supplier_portal 3,328 ms against a baseline of 705 ms,
// messages_api 2,602 ms against 563 ms. No code change caused it (the 09:34 UTC slow run predates
// every supplier_portal deploy that day). function_edge_logs, POST, 20-21 Sep, p50 execution_time_ms
// by the region that served the call:
//   supplier_portal  ap-south-1 967 (n 62) | us-west-2 1,538 | us-west-1 2,377 | us-east-2 3,336 | us-east-1 3,556
//   messages_api     ap-south-1 936 (n 42) | us-west-2 1,360 | us-west-1 2,153 | us-east-2 2,556 | us-east-1 3,222
// Supabase runs a function in the region nearest the CALLER; the database is in ap-southeast-1 and
// each call makes several serial auth/DB hops, so a US caller (the post-deploy smoke on GitHub's
// runners, HeadlessChrome from Cheyenne/us-east-2) paid an ocean per hop. Pinning with fnUrl()
// (supaEnv.ts, forceFunctionRegion=ap-southeast-1) makes it one client-to-Singapore trip instead.
// This fails if any supplier-portal or comms component builds an unpinned functions URL again.
// Comments are stripped before matching, so the explanation in those files cannot satisfy it.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const code = (p) => readFileSync(root + p, 'utf8').replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:'"`\\])\/\/.*$/gm, '$1');
const DIRS = ['src/components/portal/supplier', 'src/components/portal/comms'];
const files = DIRS.flatMap((d) => readdirSync(root + d).filter((f) => /\.(ts|tsx)$/.test(f) && !/\.test\./.test(f)).map((f) => `${d}/${f}`));

test('every functions call in the supplier portal and comms is region-pinned', () => {
  let fetchers = 0;
  for (const f of files) {
    const s = code(f);
    assert.doesNotMatch(s, /\bSUPA_FN\b/, `${f} builds a functions URL without the region pin — use fnUrl()`);
    if (/fetch\(fnUrl\(/.test(s)) fetchers++;
  }
  // 12 components + supplier/api.ts + comms/api.ts on 21 Sep 2026. Fewer means a caller moved
  // somewhere this check does not look, not that it went away.
  assert.ok(fetchers >= 14, `expected >= 14 region-pinned fetchers, found ${fetchers}`);
});

test('the shared callers are the pinned ones', () => {
  assert.match(code('src/components/portal/supplier/api.ts'), /await fetch\(fnUrl\(path\), \{/);
  assert.match(code('src/components/portal/comms/api.ts'), /await fetch\(fnUrl\(fn\), \{/);
});
