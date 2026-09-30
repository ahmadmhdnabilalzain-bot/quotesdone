// RETIRED 30 September 2026 — its subject was deleted.
//
// Subject: fn_sales_engineer_enterprise_pipeline, dropped with enterprise accounts by
// scripts/sql/there_are_no_enterprise_accounts_only_customer_and_supplier_accounts.sql (founder ruling 30 Sep 2026:
// "No enterprise accounts. We have customer accounts and supplier accounts, that's it."). The guard that replaces it
// is scripts/checks/enterprise_accounts_never_return.test.mjs.
//
// THE ENTERPRISE PIPELINE'S UPDATE CARRIES A WHERE.
//
// 24-28 Sep 2026: sales_engineer.enterprise_pipeline (fn_sales_engineer_enterprise_pipeline) failed on every
// run with "UPDATE requires a WHERE clause" - the safe-update guard refuses an unscoped UPDATE, correctly.
// It applied cleanly and died only when it ran. This reads the CANONICAL file (the last MANIFEST line that
// defines the routine) and fails if any UPDATE in its body has no WHERE before the statement ends.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const ROOT = new URL('../../', import.meta.url);
const ROUTINE = 'fn_sales_engineer_enterprise_pipeline';

export function unscopedUpdates(body) {
  const code = body.replace(/--[^\n]*/g, '');
  return [...code.matchAll(/\bupdate\s+[\s\S]*?;/gi)].map((m) => m[0]).filter((s) => !/\bwhere\b/i.test(s));
}

function canonicalBody() {
  const files = readFileSync(new URL('scripts/sql/MANIFEST.txt', ROOT), 'utf8')
    .split(/\r?\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith('#'));
  for (const f of files.reverse()) {
    let sql;
    try { sql = readFileSync(new URL(f, ROOT), 'utf8'); } catch { continue; }
    const m = sql.match(new RegExp(`function\\s+public\\.${ROUTINE}\\s*\\([\\s\\S]*?\\$fn\\$([\\s\\S]*?)\\$fn\\$`, 'i'));
    if (m) return { file: f, body: m[1] };
  }
  return null;
}

test('the shape is recognised', () => {
  assert.equal(unscopedUpdates('begin update public.t a set x = 1; end').length, 1);
  assert.equal(unscopedUpdates('begin update public.t a set x = 1 where a.id = 2; end').length, 0);
  assert.equal(unscopedUpdates('begin -- where\n update public.t set x = 1; end').length, 1);
});

test(`${ROUTINE}: every UPDATE in the canonical file has a WHERE`, () => {
  const c = canonicalBody();
  assert.ok(c, `${ROUTINE} is defined by no MANIFEST file`);
  assert.deepEqual(unscopedUpdates(c.body), [], `${c.file}: unscoped UPDATE`);
});
