// A KPI VIEW NEVER COUNTS A DEMO PARTY (it_engineer, 28 Sep 2026; deep audit runtime finding 6).
//
// Seven aggregate views counted ZZ DEMO inquiries, quotes, customers and suppliers as the company's own.
// This fails if any of them is defined without a demo exclusion (fn_inquiry_is_demo or is_demo).
// Source: the fix file while its scripts/sql/pending note exists, then the live mirror.
//
//   node --test scripts/checks/a_kpi_view_never_counts_a_demo_party.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FIX = 'scripts/sql/a_kpi_view_never_counts_a_demo_party.sql';
const PENDING = 'scripts/sql/pending/a_kpi_view_never_counts_a_demo_party.txt';
const SRC = existsSync(join(REPO, PENDING)) ? read(FIX) : read('supabase/schema/full_schema.sql');
const VIEWS = ['category_price_stats', 'crm_deal_kpis', 'customer_kpis', 'legal_kpis', 'marketing_kpis', 'ops_kpis', 'strategy_kpis'];

// The view's text: from its header to the first statement end.
function viewBody(sql, name) {
  const m = new RegExp(`create or replace view public\\.${name}\\b[\\s\\S]*?;\\s*\\n`, 'i').exec(sql);
  assert.ok(m, name + ' is defined');
  return m[0].split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
}

for (const v of VIEWS) {
  test(`${v} excludes demo parties`, () => {
    assert.match(viewBody(SRC, v), /fn_inquiry_is_demo|is_demo/i, `${v} counts ZZ DEMO rows`);
  });
}
