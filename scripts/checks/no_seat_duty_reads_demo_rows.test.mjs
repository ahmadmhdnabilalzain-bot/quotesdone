// NO SEAT DUTY READS DEMO ROWS, AND THE DEMO PURGE CANNOT REACH A REAL ROW (founder ruling 1199, 12 Oct 2026;
// it_engineer).
//
// "so no agent ever works on it as if it were real": a seat duty that reads customers, leads, inquiries, quotes,
// transactions, support_case or inquiry_intake must carry the shared demo predicate (is_demo, fn_*_is_demo, or a
// duty's own fixture switch). Measured 12 Oct 2026: 8 of 83 enabled duties lacked it; this fails if one returns.
// Boundary: the duty's OWN routine body is read, not every routine it calls.
//
//   node --test scripts/checks/no_seat_duty_reads_demo_rows.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { manifestWithPending, pendingNotes } from '../lib/pending_sql.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const NAME = 'demo_data_is_purged_by_its_marker_and_no_seat_duty_reads_it';
const FILE = `scripts/sql/${NAME}.sql`;
const PROBE = `scripts/sql/${NAME}_probe.sql`;

// a read of a subject table, once comments and string literals are gone (a literal that says "customers" is not a read)
export const SUBJECT = /\b(?:from|join|update|into)\s+(?:public\.)?(customers|leads|inquiries|quotes|transactions|support_case|inquiry_intake)\b/i;
export const DEMO = /is_demo|_is_fixture\b|p_include_fixtures|qd\.duty_fixtures/i;
const strip = (s) => s.replace(/--[^\n]*/g, '').replace(/'(?:[^']|'')*'/g, "''");
export function readsDemoRows(body) { const b = strip(body); const m = SUBJECT.exec(b); return m && !DEMO.test(b) ? m[1] : null; }

function canonical(fn) {
  const re = new RegExp(`create or replace function public\\.${fn}\\(`, 'i');
  const owner = [...manifestWithPending()].reverse().find((f) => existsSync(join(ROOT, f)) && re.test(R(f)));
  assert.ok(owner, `no applied or pending file defines ${fn}`);
  const src = R(owner).slice(R(owner).search(re));
  const tag = src.match(/\bas\s+(\$[a-z_]*\$)/i)[1];
  return src.split(tag)[1] || '';
}

test('the rule itself: a subject read without the predicate is caught, with it is not', () => {
  assert.equal(readsDemoRows('select 1 from public.customers c'), 'customers');
  assert.equal(readsDemoRows('select 1 from public.customers c where not c.is_demo'), null);
  assert.equal(readsDemoRows("select 'from customers'"), null);
  assert.equal(readsDemoRows('-- from leads\nselect 1'), null);
});

for (const fn of ['fn_support_case_idle_close', 'fn_ceo_pricing_monitor', 'fn_accountant_ubo_rescreen', 'fn_sales_engineer_comparison_kpi',
  'fn_sales_engineer_supplier_onboarding', 'fn_marketing_reputation', 'fn_sales_engineer_supplier_performance']) {
  test(`${fn} (one of the 8 found on 12 Oct 2026) excludes demo rows`, () => {
    assert.equal(readsDemoRows(canonical(fn)), null, `${fn} reads a subject table with no demo predicate`);
  });
}

test('the purge\'s Dropbox list in SQL is exactly the frozen list the edge function allows', () => {
  const json = JSON.parse(R('supabase/functions/dropbox_backup/demo_purge_paths.json')).paths;
  const m = /fn_demo_purge_dropbox_paths\(\)[\s\S]*?array\[([\s\S]*?)\]::text\[\]/.exec(R(FILE));
  assert.ok(m, 'fn_demo_purge_dropbox_paths is defined with an array literal');
  const sqlPaths = [...m[1].matchAll(/'((?:[^']|'')*)'/g)].map((x) => x[1].replace(/''/g, "'"));
  assert.deepEqual([...sqlPaths].sort(), [...json].sort());
});

test('the purge never deletes the data-request evidence (pdpl_requests, pdpl_operator_log)', () => {
  const run = R(FILE).split('create or replace function public.fn_demo_purge_run()')[1] || '';
  assert.ok(run, 'fn_demo_purge_run is defined');
  assert.doesNotMatch(run.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n'), /'public\.pdpl_/, 'the purge lists a pdpl table');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

test('production: every enabled seat duty that reads a subject table carries the demo predicate', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const rows = await sql(`select d.duty, d.routine, p.prosrc from public.seat_duty d
    join pg_proc p on p.proname = d.routine and p.pronamespace = 'public'::regnamespace where d.enabled`);
  assert.ok(rows.length > 0, 'no enabled seat duty was read');
  const bad = rows.map((r) => [r.duty, r.routine, readsDemoRows(r.prosrc)]).filter((x) => x[2]);
  assert.deepEqual(bad, [], 'duties reading demo rows: ' + bad.map((x) => `${x[0]} (${x[1]} reads ${x[2]})`).join(', '));
});

test('production, rolled back: the purge refuses to reach a real inquiry and plans without it', { skip: SKIP }, async () => {
  const pre = pendingNotes().has(FILE) ? R(FILE).split(/^-- VERDICT/m)[0] + '\n' : '';
  let out = null;
  try { await replaySql(pre + R(PROBE), { retry: false }); } catch (e) {
    out = String(e.message || e).match(/CHK<<([\s\S]*)>>/)?.[1];
    assert.ok(out, 'the probe failed before it could report: ' + String(e.message || e).slice(0, 800));
  }
  assert.ok(out, 'the probe committed instead of rolling back');
  assert.match(out, /^PROBE OK/, out);
});
