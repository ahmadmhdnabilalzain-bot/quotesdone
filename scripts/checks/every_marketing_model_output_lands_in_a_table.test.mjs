// EVERY MARKETING MODEL OUTPUT LANDS IN A TABLE — and every marketing class is inside the marketing ceiling.
// marketing, 23 Sep 2026; founder instructions 865-867 ("if the structure is wrong, then everything goes wrong").
//
// The model is held today and will be opened. The failure this guards is an answer that exists only in a chat reply
// or a log line: the seat "thought" and nothing durable holds it. So, over the source:
//   1. every step in _shared/marketing_judgement.ts STEPS names a table that a scripts/sql file creates, a
//      task_class that a scripts/sql file registers in model_policy, and fn_marketing_step_accept inserts into it;
//   2. the marketing seat's function never builds a model client except as the callModel of a runStep Deps
//      (so every call goes through request -> hold check -> accept), and never uses the bare makeLlm;
//   3. the ceiling covers every class: the SQL moves every marketing fn_task_class row to dept 'marketing',
//      and (with a management token) production has none outside it.
// QD_MKT_ROOT points the static half at another checkout, which is how it was shown to FAIL on the pre-fix tree.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';

const root = process.env.QD_MKT_ROOT || join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');
const runner = read(join(root, 'supabase', 'functions', '_shared', 'marketing_judgement.ts'));
const SQLDIR = join(root, 'scripts', 'sql');
const allSql = existsSync(SQLDIR) ? readdirSync(SQLDIR).filter((f) => f.endsWith('.sql')).map((f) => read(join(SQLDIR, f))).join('\n') : '';

function steps() {
  const block = runner.slice(runner.indexOf('export const STEPS'), runner.indexOf('};', runner.indexOf('export const STEPS')));
  return [...block.matchAll(/(\w+):\s*\{\s*seat:\s*'(\w+)',\s*taskClass:\s*'(\w+)',\s*table:\s*'(\w+)'\s*\}/g)]
    .map(([, step, seat, taskClass, table]) => ({ step, seat, taskClass, table }));
}
function acceptBody() {
  const i = allSql.lastIndexOf('create or replace function public.fn_marketing_step_accept(');
  return i < 0 ? '' : allSql.slice(i, allSql.indexOf('$fn$;', i));
}

test('every model step names a table, a registered class, and the accept routine writes that table', () => {
  const s = steps();
  assert.ok(s.length >= 7, `marketing_judgement.ts STEPS has ${s.length} steps; the seat's judgement is not built`);
  const body = acceptBody();
  assert.ok(body, 'fn_marketing_step_accept is not defined in any scripts/sql file');
  const bad = [];
  for (const x of s) {
    if (!new RegExp(`create table if not exists public\\.${x.table}\\b`).test(allSql)) bad.push(`${x.step}: table ${x.table} is created nowhere`);
    if (!new RegExp(`insert into public\\.model_policy[\\s\\S]*?\\('${x.taskClass}',`).test(allSql)) bad.push(`${x.step}: class ${x.taskClass} has no model_policy row`);
    if (!new RegExp(`insert into public\\.${x.table}\\b`).test(body)) bad.push(`${x.step}: fn_marketing_step_accept never writes ${x.table}`);
  }
  assert.deepEqual(bad, []);
});

test('the marketing seat builds a model client only as a runStep callModel', () => {
  const dir = join(root, 'supabase', 'functions', 'marketing');
  const files = existsSync(dir) ? readdirSync(dir).filter((f) => f.endsWith('.ts')) : [];
  const bad = [];
  for (const f of files) {
    const lines = read(join(dir, f)).split('\n');
    lines.forEach((l, i) => {
      if (/\bmakeLlm\(/.test(l)) bad.push(`${f}:${i + 1} uses makeLlm (a bare string answer that no table receives)`);
      if (/\bmakeLlmRich\(/.test(l) && !/callModel:/.test(lines.slice(Math.max(0, i - 2), i + 1).join('\n')))
        bad.push(`${f}:${i + 1} builds a model client outside a runStep callModel`);
    });
    if (/makeLlmRich\(/.test(lines.join('\n')) && !/runStep\(/.test(lines.join('\n'))) bad.push(`${f} calls a model and never runs a step`);
  }
  assert.ok(runner.includes("rpc('fn_marketing_step_accept'"), 'the runner does not hand the answer to fn_marketing_step_accept');
  assert.ok(/held\(\)[\s\S]*fn_marketing_step_request/.test(runner.slice(runner.indexOf('export async function runStep'))),
    'the runner does not ask the founder\'s hold before building a request');
  assert.deepEqual(bad, []);
});

test('the SQL puts every marketing task class inside the marketing ceiling, which is AED 150', () => {
  assert.match(allSql, /update public\.fn_task_class set dept_key = 'marketing'[\s\S]{0,120}where \(fn like 'marketing%' or task_class like 'marketing%'\)/,
    'no scripts/sql file moves every marketing fn_task_class row into the marketing ceiling (marketing_draft was orphaned)');
  assert.match(allSql, /update public\.department_budget set monthly_aed = 150[^;]*where dept_key = 'marketing'/,
    'the marketing ceiling is not set to AED 150 in any scripts/sql file');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('production: no marketing task class is outside the marketing ceiling', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const rows = await sql(`select fn, task_class from public.fn_task_class
                           where (fn like 'marketing%' or task_class like 'marketing%') and dept_key is distinct from 'marketing'`, { readOnly: true });
  assert.deepEqual(rows, [], 'these marketing classes are outside every ceiling: ' + JSON.stringify(rows));
});
