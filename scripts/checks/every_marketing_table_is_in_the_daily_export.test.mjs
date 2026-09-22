// EVERY MARKETING TABLE IS IN THE DAILY TABLE EXPORT (marketing, 22 Sep 2026).
//
// The first version of the marketing seat (#834) created five tables and left them out of
// fn_table_export_list, so the founder's ingested posts, the measured access and the ad spend handed to the
// accountant would not have reached the daily export or Dropbox. The coordinator caught it in review.
// This fails when a table created by a marketing_* file or a table named marketing_* is not in the
// fn_table_export_list definition that wins: the last one in scripts/sql/MANIFEST.txt order, or, while a
// file is pending (scripts/sql/pending/), the pending file that redefines it.
//
//   node --test scripts/checks/every_marketing_table_is_in_the_daily_export.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const SQL = join(REPO, 'scripts', 'sql');
const read = (f) => readFileSync(join(REPO, f), 'utf8');
const DEF = /create\s+or\s+replace\s+function\s+public\.fn_table_export_list\s*\(\s*\)[\s\S]*?\$fn\$;/i;

test('every marketing table is exported every day', () => {
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).filter((l) => l.endsWith('.sql'));
  const pendingDir = join(SQL, 'pending');
  const pending = existsSync(pendingDir) ? readdirSync(pendingDir).filter((f) => f.endsWith('.txt')).map((f) => `scripts/sql/${f.slice(0, -4)}.sql`) : [];
  const order = [...manifest, ...pending].filter((f) => existsSync(join(REPO, f)));
  const winner = order.filter((f) => DEF.test(read(f))).pop();
  assert.ok(winner, 'no file defines fn_table_export_list');
  const exported = new Set([...read(winner).match(DEF)[0].matchAll(/\('([a-z0-9_]+)',\s*'[^']*'\)/g)].map((m) => m[1]));

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
  assert.ok(created.size >= 5, `only ${created.size} marketing tables found; the pattern no longer matches`);
  const missing = [...created].filter((t) => !exported.has(t));
  assert.deepEqual(missing, [], `${winner}: add these to fn_table_export_list: ${missing.join(', ')}`);
});
