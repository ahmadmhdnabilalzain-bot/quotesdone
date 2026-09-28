// THE CEO'S TARGET ROUTINES READ THE FOUNDER'S YEAR PLAN (28 Sep 2026, ceo).
//
// WHAT FAILS IF THE CAUSE RETURNS. The canonical definition of each CEO target routine (the pending file if one
// defines it, else the file with the highest MANIFEST line) must:
//   * never name a withdrawn contract (REVENUE_AED_1M, SUPPLIERS_1000, CUSTOMERS_1000) in code;
//   * fn_ceo_target_daily_verdict: raise when its metric list is empty (an empty list read as "0 misses") and
//     always grade the supplier milestone;
//   * fn_ceo_target_forecast: grade the plan contract only, not every active contract.
//
//   node --test scripts/checks/the_ceo_target_routines_read_the_year_plan.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const SQL = join(REPO, 'scripts/sql');
const code = (s) => s.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const manifest = readFileSync(join(SQL, 'MANIFEST.txt'), 'utf8').split('\n').map((l) => l.trim().split('/').pop());
const pending = (f) => existsSync(join(SQL, 'pending', f.replace(/\.sql$/, '.txt')));
const WITHDRAWN = /REVENUE_AED_1M|SUPPLIERS_1000|CUSTOMERS_1000/;

function canonicalBody(fn) {
  const re = new RegExp(`create or replace function public\\.${fn}\\([\\s\\S]*?\\$fn\\$[\\s\\S]*?\\$fn\\$`, 'gi');
  const defs = readdirSync(SQL).filter((f) => f.endsWith('.sql') && !f.endsWith('_probe.sql'))
    .map((f) => ({ f, bodies: [...code(readFileSync(join(SQL, f), 'utf8')).matchAll(re)].map((m) => m[0]) }))
    .filter((d) => d.bodies.length);
  assert.ok(defs.length, `${fn} is defined nowhere`);
  const rank = (d) => (pending(d.f) ? Infinity : manifest.lastIndexOf(d.f));
  const top = defs.sort((a, b) => rank(b) - rank(a))[0];
  return { file: top.f, body: top.bodies.at(-1) };
}

test('the daily verdict reads the plan and cannot return an empty list', () => {
  const { file, body } = canonicalBody('fn_ceo_target_daily_verdict');
  assert.ok(!WITHDRAWN.test(body), `${file}: the verdict names a withdrawn contract`);
  assert.match(body, /jsonb_array_length\(v_out\)\s*=\s*0\s+then\s+raise/i, `${file}: an empty metric list does not raise`);
  assert.match(body, /ceo_year_plan_milestone/, `${file}: the verdict does not grade the founder's supplier milestones`);
});

test('the weekly forecast grades the plan contract only', () => {
  const { file, body } = canonicalBody('fn_ceo_target_forecast');
  assert.ok(!WITHDRAWN.test(body), `${file}: the forecast names a withdrawn contract`);
  assert.ok(!/from public\.target_contract where status = 'active' and measure_sql/i.test(body),
    `${file}: the forecast loops over every active contract instead of the plan`);
  assert.match(body, /FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30/, `${file}: the forecast does not read the year-one plan`);
});
