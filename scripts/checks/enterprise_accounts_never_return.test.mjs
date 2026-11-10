// ENTERPRISE ACCOUNTS NEVER RETURN (sales_engineer, 30 Sep 2026).
//
// Founder ruling, 30 Sep 2026: "No enterprise accounts. We have customer accounts and supplier accounts, that's it."
// scripts/sql/there_are_no_enterprise_accounts_only_customer_and_supplier_accounts.sql removed the tables, the two
// routines and the weekly duty. WHAT FAILS IF THEY COME BACK:
//   * offline: any SQL file applied after the removal (MANIFEST order, then pending) creates enterprise_account or
//     enterprise_account_member, defines either routine, or schedules the duty; the app, an edge function or a seat's
//     knowledge names an enterprise account;
//   * production, in ONE aborted transaction (the removal file replayed first while it is pending): an enterprise
//     object or the duty survives, or any other sales_engineer duty's routine fails when run. Every write rolls back.
//
//   node --test scripts/checks/enterprise_accounts_never_return.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { manifestWithPending, manifestHas } from '../lib/pending_sql.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const FILE = 'scripts/sql/there_are_no_enterprise_accounts_only_customer_and_supplier_accounts.sql';
const src = readFileSync(join(REPO, FILE), 'utf8');
const stripComments = (s) => s.replace(/--[^\n]*/g, '');

// The one rule, pure so the self-test runs it: what in this SQL text brings an enterprise account back.
export function revivals(sql) {
  // a statement that removes (drop ..., delete ...) is not a revival
  const code = stripComments(sql).split('\n').filter((l) => !/^\s*(drop|delete)\b/i.test(l)).join('\n');
  return [
    /create\s+table\s+(?:if\s+not\s+exists\s+)?public\.enterprise_account(?:_member)?\b/i,
    /function\s+public\.fn_(?:sales_engineer_enterprise_pipeline|enterprise_account_report)\s*\(/i,
    /'sales_engineer\.enterprise_pipeline'\s*,/i,
  ].filter((re) => re.test(code)).map((re) => re.source);
}

test('self-test: a revival is caught and the removal itself is not', () => {
  assert.equal(revivals('create table if not exists public.enterprise_account (id bigint);').length, 1);
  assert.equal(revivals("create or replace function public.fn_enterprise_account_report(p bigint)").length, 1);
  assert.equal(revivals("insert into public.seat_duty values ('sales_engineer.enterprise_pipeline', 'x')").length, 1);
  assert.equal(revivals('-- create table public.enterprise_account (').length, 0);
  assert.deepEqual(revivals(src), []);
});

test('no file applied after the removal brings an enterprise account back', () => {
  const order = manifestWithPending(REPO);
  const at = order.indexOf(FILE);
  assert.ok(at >= 0, `${FILE} is in neither MANIFEST.txt nor a pending note`);
  const back = order.slice(at + 1).filter((f) => existsSync(join(REPO, f)))
    .map((f) => [f, revivals(readFileSync(join(REPO, f), 'utf8'))]).filter(([, r]) => r.length);
  assert.deepEqual(back, [], 'founder ruling 30 Sep 2026: customer and supplier accounts only');
});

test('the app, the edge functions and the seats\' knowledge name no enterprise account', () => {
  const hits = [];
  const walk = (d) => {
    if (!existsSync(d)) return;
    for (const e of readdirSync(d)) {
      const p = join(d, e);
      if (statSync(p).isDirectory()) { if (e !== 'node_modules') walk(p); }
      else if (/\.(ts|tsx|js|mjs|json)$/.test(e) && /enterprise[\s_-]?account|enterprise_pipeline/i.test(readFileSync(p, 'utf8'))) hits.push(p.slice(REPO.length + 1));
    }
  };
  for (const d of ['src', 'supabase/functions', 'knowledge']) walk(join(REPO, d));
  assert.deepEqual(hits, []);
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token';

test('production, aborted: nothing enterprise remains and every other sales_engineer duty still runs', { skip: SKIP }, async () => {
  const { replaySql: sql } = await import('../lib/safe_replay.mjs');   // the one door: cannot commit
  const pending = !manifestHas(FILE);
  const block = String.raw`
do $$ declare o jsonb := '{}'; d record; v jsonb; runs jsonb := '[]'; begin
  o := jsonb_build_object(
    'tables', (select count(*) from pg_class where relnamespace = 'public'::regnamespace and relname like 'enterprise_account%'),
    'routines', (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname ilike '%enterprise%'),
    'duty', (select count(*) from public.seat_duty where duty ilike '%enterprise%' or routine ilike '%enterprise%'),
    'registry', (select count(*) from public.table_export_registry where table_name like 'enterprise_account%'),
    'columns', (select count(*) from information_schema.columns where table_schema = 'public' and column_name ilike 'enterprise_account%'),
    'ops_knowledge', (select count(*) from public.ops_knowledge where record_id like 'ops-department-business-development-%enterprise-account%'),
    'playbook', (select count(*) from public.seat_playbook where seat = 'sales_engineer' and markdown ilike '%enterprise_pipeline%'));
  for d in select duty, routine from public.seat_duty where owner_seat = 'sales_engineer' and enabled order by duty loop
    begin
      execute format('select public.%I()', d.routine) into v;
      runs := runs || jsonb_build_object('duty', d.duty, 'ok', true);
    exception when others then
      runs := runs || jsonb_build_object('duty', d.duty, 'ok', false, 'error', left(sqlerrm, 200));
    end;
  end loop;
  raise exception 'CHK<<%>>', o || jsonb_build_object('runs', runs);
end $$;`;
  let o;
  try { await sql((pending ? src + '\n' : '') + block, { retry: false }); assert.fail('the probe committed'); }
  catch (e) {
    // 10 Nov 2026: db.mjs cuts e.message at 2,000 characters, and the run list of every sales_engineer duty is longer
    // than that now, so the closing >> was cut off and the probe read as failed. The whole answer is in e.body.
    let text = String(e.body ?? e.message);
    try { text = JSON.parse(text.slice(text.indexOf('{'))).message ?? text; } catch { /* keep the raw text */ }
    const m = text.match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + text.slice(0, 800));
    o = JSON.parse(m[1]);
  }
  console.log(JSON.stringify(o));
  assert.deepEqual([o.tables, o.routines, o.duty, o.registry, o.columns, o.ops_knowledge, o.playbook], [0, 0, 0, 0, 0, 0, 0], JSON.stringify(o));
  assert.ok(o.runs.length >= 10, `only ${o.runs.length} sales_engineer duties ran`);
  assert.deepEqual(o.runs.filter((r) => !r.ok), [], 'a sales_engineer duty fails without the enterprise objects');
});
