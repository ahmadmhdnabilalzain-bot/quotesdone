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
// A duty's own fixture switch is read as current_setting('qd.duty_fixtures', true): a string literal, which strip() blanks.
// 10 Nov 2026: so the switch this header names as a predicate could never count, and fn_customer_support_public_complaint_tick
// (which selects (text like 'ZZ DEMO%') = v_fx) read as a demo reader. The switch is looked for with comments removed only.
const SWITCH = /current_setting\(\s*'qd\.duty_fixtures'/i;
export function readsDemoRows(body) {
  const b = strip(body); const m = SUBJECT.exec(b);
  if (!m || DEMO.test(b) || SWITCH.test(body.replace(/--[^\n]*/g, ''))) return null;
  return m[1];
}

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
  assert.equal(readsDemoRows("v_fx boolean := current_setting('qd.duty_fixtures', true) = 'on'; select 1 from support_case"), null);
  assert.equal(readsDemoRows("-- current_setting('qd.duty_fixtures', true)\nselect 1 from support_case"), 'support_case');
});

for (const fn of ['fn_support_case_idle_close', 'fn_ceo_pricing_monitor', 'fn_accountant_ubo_rescreen', 'fn_sales_engineer_comparison_kpi',
  'fn_sales_engineer_supplier_onboarding', 'fn_marketing_reputation', 'fn_sales_engineer_supplier_performance']) {
  test(`${fn} (one of the 8 found on 12 Oct 2026) excludes demo rows`, () => {
    assert.equal(readsDemoRows(canonical(fn)), null, `${fn} reads a subject table with no demo predicate`);
  });
}

// ceo.pricing_evidence (C08) was registered after the 12 Oct sweep and read demo rows until
// scripts/sql/the_ceo_pricing_evidence_reads_only_real_rows.sql (27 Oct 2026).
// The two #1844 duties (3 Nov 2026) that read customers / inquiries with no predicate until
// scripts/sql/two_customer_support_duties_read_only_their_own_kind_of_row.sql (10 Nov 2026).
for (const fn of ['fn_customer_support_closes_status_chases', 'fn_wa_human_request_email_followup', 'fn_customer_support_public_complaint_tick']) {
  test(`${fn} (found 10 Nov 2026) excludes demo rows`, () => {
    assert.equal(readsDemoRows(canonical(fn)), null, `${fn} reads a subject table with no demo predicate`);
  });
}

test('fn_ceo_pricing_evidence (found 27 Oct 2026) excludes demo rows', () => {
  assert.equal(readsDemoRows(canonical('fn_ceo_pricing_evidence')), null, 'fn_ceo_pricing_evidence reads a subject table with no demo predicate');
});

test('the purge\'s Dropbox list in SQL is exactly the frozen list the edge function allows', () => {
  const json = JSON.parse(R('supabase/functions/dropbox_backup/demo_purge_paths.json')).paths;
  const m = /fn_demo_purge_dropbox_paths\(\)[\s\S]*?array\[([\s\S]*?)\]::text\[\]/.exec(R(FILE));
  assert.ok(m, 'fn_demo_purge_dropbox_paths is defined with an array literal');
  const sqlPaths = [...m[1].matchAll(/'((?:[^']|'')*)'/g)].map((x) => x[1].replace(/''/g, "'"));
  assert.deepEqual([...sqlPaths].sort(), [...json].sort());
});

// THE DATA-REQUEST EVIDENCE IS NEVER PURGED (release review of 2953dbf): any mention of a pdpl_ table in the code of the
// purge (quoted, schema-qualified or not, or built at run time) fails; the walk may name it only to refuse it (QD196).
const codeOf = (body) => body.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
export function pdplInPurge(runBody) { return /pdpl_/i.test(codeOf(runBody)); }
export function pdplInWalkOtherThanRefusal(walkBody) {
  return codeOf(walkBody).split('\n').some((l) => /pdpl_/i.test(l) && !(/raise exception/i.test(l) && /QD196/.test(l)));
}
function fnBody(sql, name) {
  const at = sql.indexOf(`create or replace function public.${name}(`);
  assert.ok(at >= 0, name + ' is defined');
  const from = sql.indexOf('$fn$', at);
  return sql.slice(from + 4, sql.indexOf('$fn$', from + 4));
}

test('the pdpl rule catches every form: a plain delete, an unqualified name, a dynamic format()', () => {
  assert.equal(pdplInPurge('  delete from public.pdpl_requests where true;'), true);
  assert.equal(pdplInPurge('  delete from pdpl_operator_log where email = x;'), true);
  assert.equal(pdplInPurge("  execute format('delete from %I', 'PDPL_requests');"), true);
  assert.equal(pdplInPurge("  -- pdpl_requests is never purged\n  select 1;"), false);
  assert.equal(pdplInWalkOtherThanRefusal("  if k ~* '^pdpl_' then raise exception 'x' using errcode = 'QD196'; end if;"), false);
  assert.equal(pdplInWalkOtherThanRefusal("  execute format('delete from %s', 'pdpl_requests');"), true);
});

test('the purge never deletes the data-request evidence (pdpl_requests, pdpl_operator_log)', () => {
  const sql = R(FILE);
  assert.equal(pdplInPurge(fnBody(sql, 'fn_demo_purge_run')), false, 'fn_demo_purge_run names a pdpl table');
  assert.equal(pdplInPurge(fnBody(sql, 'fn_demo_purge')), false, 'fn_demo_purge names a pdpl table');
  assert.equal(pdplInWalkOtherThanRefusal(fnBody(sql, 'fn_demo_purge_walk')), false, 'fn_demo_purge_walk names a pdpl table other than to refuse it');
  assert.match(codeOf(fnBody(sql, 'fn_demo_purge_walk')), /pdpl_.*QD196/i, 'the walk refuses a pdpl table it reaches by a foreign key');
});

test('lead 143027 (Assurance Corps Co., a real sourced company) is never demo and never purged', () => {
  const sql = codeOf(R(FILE));
  assert.match(sql, /fn_is_demo_phone\(phone\) and coalesce\(source, ''\) <> 'marketing_sourcing'/, 'a sourced lead can still be flagged demo by its phone');
  assert.match(sql, /fn_demo_purge_kept_leads\(\)[\s\S]*?array\[143027\]/, '143027 is not on the kept list');
  assert.match(sql, /id <> all\(public\.fn_demo_purge_kept_leads\(\)\)/, 'the purge does not exclude the kept leads');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

test('production: every enabled seat duty that reads a subject table carries the demo predicate', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const rows = await sql(`select d.duty, d.routine, p.prosrc from public.seat_duty d
    join pg_proc p on p.proname = d.routine and p.pronamespace = 'public'::regnamespace where d.enabled`);
  assert.ok(rows.length > 0, 'no enabled seat duty was read');
  // a routine whose fix is committed and pending is judged on that canonical body (10 Nov 2026); the rest on production's
  const pendingDefines = (fn) => [...pendingNotes().keys()].some((f) => existsSync(join(ROOT, f))
    && new RegExp(`create or replace function public\\.${fn}\\(`, 'i').test(R(f)));
  const fixed = (fn) => (pendingDefines(fn) ? canonical(fn) : null);
  const bad = rows.map((r) => [r.duty, r.routine, readsDemoRows(fixed(r.routine) ?? r.prosrc)]).filter((x) => x[2]);
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
