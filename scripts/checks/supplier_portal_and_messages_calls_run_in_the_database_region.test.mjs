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

// THE PINNED CALLERS, BY NAME — AND THERE ARE NOW EXACTLY TWO OF THEM.
//
// 22 Sep 2026 (audit SP-C-05). This used to assert `fetchers >= 14`: the twelve panel components
// that each held a private copy of `call()`, plus supplier/api.ts and comms/api.ts. Those twelve
// copies are gone — each was `return r.json()` with no timeout, no JSON-parse catch and, in seven
// of them, no `.catch` at all, so a non-JSON response left the panel on "Loading" for good. Every
// panel now imports the one shared helper.
//
// The floor counted the defect, so consolidating the defect broke the floor. The rule it was
// reaching for has not changed and is not weakened here — it is TIGHTENED, from "at least 14
// somewhere" to "these two files and no others". A floor could not have failed on a thirteenth
// private fetcher appearing; an exact set does, and it still fails if either shared helper loses
// its pin. The real guard, `doesNotMatch SUPA_FN`, is untouched and runs over every file.
const PINNED = ['src/components/portal/supplier/api.ts', 'src/components/portal/comms/api.ts'];

test('every functions call in the supplier portal and comms is region-pinned', () => {
  const fetchers = [];
  for (const f of files) {
    const s = code(f);
    assert.doesNotMatch(s, /\bSUPA_FN\b/, `${f} builds a functions URL without the region pin — use fnUrl()`);
    if (/fetch\(fnUrl\(/.test(s)) fetchers.push(f);
  }
  assert.deepEqual(fetchers.sort(), [...PINNED].sort(),
    'the only files that may call a function directly are the two shared helpers. A new name here is '
    + 'a private copy of call() that will drift; a missing name is a helper that lost its region pin.');
});

test('the shared callers are the pinned ones', () => {
  assert.match(code('src/components/portal/supplier/api.ts'), /await fetch\(fnUrl\(path\), \{/);
  assert.match(code('src/components/portal/comms/api.ts'), /await fetch\(fnUrl\(fn\), \{/);
});
