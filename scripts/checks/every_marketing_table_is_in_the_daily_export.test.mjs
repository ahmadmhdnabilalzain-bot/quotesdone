// EVERY MARKETING TABLE IS IN THE DAILY TABLE EXPORT (marketing, 22 Sep 2026).
//
// The first version of the marketing seat (#834) created five tables and left them out of
// fn_table_export_list, so the founder's ingested posts, the measured access and the ad spend handed to the
// accountant would not have reached the daily export or Dropbox. The coordinator caught it in review.
// This fails when a table created by a marketing_* file or a table named marketing_* is not exported by
// public.table_export_registry (since 29 Sep 2026 the list fn_table_export_list reads), replayed from the SQL
// files in apply order - MANIFEST, then pending files (scripts/lib/table_export_registry.mjs).
//
//   node --test scripts/checks/every_marketing_table_is_in_the_daily_export.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { exportedTables } from '../lib/table_export_registry.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const SQL = join(REPO, 'scripts', 'sql');

test('every marketing table is exported every day', () => {
  const exported = exportedTables(REPO);
  const winner = 'public.table_export_registry';

  const created = new Set();
  for (const f of readdirSync(SQL).filter((x) => x.endsWith('.sql'))) {
    const body = readFileSync(join(SQL, f), 'utf8');
    for (const m of body.matchAll(/create\s+table\s+(?:if\s+not\s+exists\s+)?public\.([a-z0-9_]+)/gi)) {
      if (f.startsWith('the_marketing_') || m[1].startsWith('marketing_')) created.add(m[1]);
    }
  }
  // marketing_library and marketing_snapshots are June-era tables the 7 Sep cull left without a writer;
  // they are not the seat's records.
  for (const old of ['marketing_library', 'marketing_snapshots']) created.delete(old);
  // marketing_meta_page is a cache of the Facebook page ACCESS TOKEN (every_social_message_is_answered.sql),
  // re-derived from meta_access_token on demand. A credential never goes to the daily export or Dropbox,
  // and nothing is lost without it. 22 Sep 2026, PR #835.
  created.delete('marketing_meta_page');
  assert.ok(created.size >= 5, `only ${created.size} marketing tables found; the pattern no longer matches`);
  const missing = [...created].filter((t) => !exported.has(t));
  assert.deepEqual(missing, [], `${winner}: insert an exported row for each of these:${missing.join(', ')}`);
});
