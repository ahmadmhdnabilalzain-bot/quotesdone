// THE CLAIM IN THE HEADER WAS THE TEST, AND THE TEST WAS FALSE.
//
// scripts/kb/import_packs.mjs says, in its own header: "Re-running a fully imported corpus inserts
// nothing; that is the test, and it is how this was verified against production." On 13 Aug 2026 a
// second run died before reading a single file:
//
//   ERROR 23505: duplicate key value violates unique constraint "kb_stage_runs_pkg_idx"
//   Key (package_id, package_version, COALESCE(package_sha256, ''))
//        =(ALL_KNOWLEDGE_86_CATEGORIES, v2026.07.31, ) already exists.
//
// kb_stage.ingestion_runs is unique on that expression — one row per package version, a state
// record rather than a per-execution log — and the importer opened every run with a plain insert.
// It went unnoticed for as long as it did precisely because the claim was written once and never
// re-executed. A sentence in a header is not a check.
//
// Two things have to stay true for the fix to hold, and they live in different places: the source
// must upsert, and the live index must still be the expression the upsert names. Drop or redefine
// that index and `on conflict (package_id, package_version, coalesce(package_sha256,''))` raises
// 42P10 "no unique or exclusion constraint matching the ON CONFLICT specification" — the same
// failure, one layer along. Both are asserted here.
//
//   node --test scripts/checks/
import { SUPABASE_TOKEN_FILE } from '../lib/supabase_token.mjs';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const SRC = readFileSync('scripts/kb/import_packs.mjs', 'utf8');

// The kb branch only. ops_kb_stage.ingestion_runs carries just its pkey, has no equivalent
// constraint, and never had the fault — asserting an upsert there would be inventing a rule.
const runInsert = (() => {
  const at = SRC.indexOf('kb_stage.ingestion_runs (package_id, package_version)');
  assert.ok(at > 0, 'import_packs no longer opens a kb_stage.ingestion_runs row the way this check parses');
  return SRC.slice(at, at + 500);
})();

test('a repeated import re-opens its run row instead of colliding with it', () => {
  assert.match(runInsert, /on conflict \(package_id, package_version, coalesce\(package_sha256,''\)\)/,
    'the kb ingestion_runs insert is not an upsert on the unique expression, so the second run of a '
    + 'fully imported corpus dies with 23505 before it reads a single file — which is exactly what '
    + "the file's own header claims is impossible");
  assert.match(runInsert, /do update set status='started'/,
    'the conflict branch must re-open the row, not do nothing — a run that resumes has to be visible as started');
  assert.match(runInsert, /completed_at=null/,
    'a re-opened run still carrying its previous completed_at reads as finished while it is running');
});

const LOCAL_TOKEN = SUPABASE_TOKEN_FILE;
const mgmtToken = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();

// staging was a second target until its Supabase project was deleted on 15 Aug 2026; the same
// assertions now run against production alone.
for (const [label, project] of [['production', 'htdblwldjkcgjvmqkbeh']]) {
  test(`the index the upsert names still exists on ${label}`, async (t) => {
    if (!mgmtToken) { t.skip('no management token, so the live index cannot be read'); return; }
    const r = await fetch(`https://api.supabase.com/v1/projects/${project}/database/query`, {
      method: 'POST', headers: { Authorization: 'Bearer ' + mgmtToken, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query: "select indexdef from pg_indexes where schemaname='kb_stage' "
        + "and tablename='ingestion_runs' and indexdef ilike '%unique%'" }),
    });
    assert.ok(r.ok, `could not read pg_indexes on ${label}: ${r.status}`);
    const defs = (await r.json()).map((x) => String(x.indexdef));
    const match = defs.find((d) => /package_id, package_version, COALESCE\(package_sha256/i.test(d));
    assert.ok(match,
      `no unique index on (package_id, package_version, coalesce(package_sha256,'')) exists on ${label}. `
      + "The importer's ON CONFLICT names that exact expression and will raise 42P10 without it. "
      + `Indexes found: ${defs.join(' | ') || 'none'}`);
    console.log(`${label}: ${match.replace(/^CREATE UNIQUE INDEX /, '')}`);
  });
}
