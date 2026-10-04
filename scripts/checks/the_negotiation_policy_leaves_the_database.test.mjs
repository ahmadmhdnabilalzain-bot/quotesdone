// THE NEGOTIATION POLICY LEAVES THE DATABASE (30 Sep 2026, sales_engineer; founder ruling 527 removed negotiation,
// ruling 17: no escalation to a human).
//
// MEASURED: public.supplier_negotiation_policy held one row with an "escalate_to_human" band, read by fn_customer_savings.
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * static: any edge function, portal file, SQL routine body in this change, demo fixture or scorer names the table
//     again; the file carries both (or neither of) a pending note and a MANIFEST line;
//   * production, in ONE aborted transaction (the file replayed first while pending): the table exists, a routine body
//     names it, or fn_customer_savings no longer answers with its minimum sample of 4.
//
//   node --test scripts/checks/the_negotiation_policy_leaves_the_database.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, dirname, relative } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/the_negotiation_policy_leaves_the_database.sql';
const pending = () => existsSync(join(REPO, 'scripts/sql/pending', FILE.split('/').pop().replace(/\.sql$/, '.txt')));
const walk = (d, out = []) => { for (const n of readdirSync(d)) { const p = join(d, n); if (statSync(p).isDirectory()) { if (n !== 'node_modules') walk(p, out); } else if (/\.(ts|tsx|mjs)$/.test(n)) out.push(p); } return out; };
// code only: a line comment that records the drop is history, not a reader
const code = (s) => s.split('\n').filter((l) => !/^\s*(\/\/|\*|--)/.test(l)).join('\n');

test('static: nothing in the code reads the negotiation policy', () => {
  const T = 'supplier_negotiation_policy';
  const bad = [join(REPO, 'supabase', 'functions'), join(REPO, 'src'), join(REPO, 'scripts', 'lib'), join(REPO, 'scripts', 'staging')]
    .flatMap((d) => walk(d)).filter((f) => !/\.RETIRED\.mjs$/.test(f) && code(readFileSync(f, 'utf8')).includes(T));
  assert.deepEqual(bad.map((f) => relative(REPO, f)), [], 'the negotiation policy is read again');
  const sql = read(FILE);
  assert.match(sql, /drop table if exists public\.supplier_negotiation_policy;/);
  assert.match(sql, /delete from public\.table_export_registry where table_name = 'supplier_negotiation_policy';/);
  assert.doesNotMatch(code(sql.slice(sql.indexOf('create or replace function'), sql.indexOf('delete from public.table_export_registry'))), /supplier_negotiation_policy/, 'fn_customer_savings still reads it');
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim());
  assert.ok(pending() !== manifest.includes(FILE), 'exactly one of a pending note and a MANIFEST line');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: no table, no reader, savings unchanged', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const replay = pending() ? read(FILE) + '\n' : '';
  let o;
  try {
    await sql(replay + `
do $$ begin
  raise exception 'CHK<<%>>', jsonb_build_object(
    'table', to_regclass('public.supplier_negotiation_policy') is not null,
    'readers', (select coalesce(jsonb_agg(p.oid::regprocedure::text), '[]'::jsonb) from pg_proc p
                 where p.pronamespace = 'public'::regnamespace and p.prosrc ilike '%supplier_negotiation_policy%'),
    'registry', exists (select 1 from public.table_export_registry where table_name = 'supplier_negotiation_policy'),
    'min_sample', public.fn_customer_savings('00000000-0000-0000-0000-000000000000'::uuid)->'min_sample')::text;
end $$;`, { retry: false });
  } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    o = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(o, 'the probe committed instead of rolling back');
  assert.deepEqual(o, { table: false, readers: [], registry: false, min_sample: 4 });
});
