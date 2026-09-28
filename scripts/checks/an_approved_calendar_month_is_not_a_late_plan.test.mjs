// A MONTH AN APPROVED CALENDAR ALREADY COVERS IS NOT A LATE PLAN (marketing + ceo, 28 Sep 2026).
//
// On 28 Sep the CEO's watch reported the October 2026 plan as late (due 23 Sep, "no plan row"). October was
// already planned: the founder approved campaign 7 on 24 Sep, with posts to 21 Oct. The model queue would also
// have drafted a second October plan once the model hold lifted. This fails if either routine stops asking
// fn_marketing_month_covered_by_approved_calendar, or if coverage stops requiring an approved, non-demo,
// non-cancelled post inside the month.
//
//   node --test scripts/checks/an_approved_calendar_month_is_not_a_late_plan.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const FILE = 'scripts/sql/a_month_an_approved_calendar_already_covers_is_not_a_late_plan.sql';
const SQL = readFileSync(fileURLToPath(new URL('../../' + FILE, import.meta.url)), 'utf8');
const code = SQL.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');
const body = (name) => {
  const i = code.indexOf('create or replace function public.' + name + '(');
  assert.ok(i >= 0, name + ' is defined in ' + FILE);
  const next = code.indexOf('create or replace function', i + 1);
  return code.slice(i, next < 0 ? code.length : next);
};

test('coverage needs an approved, non-demo campaign with a live post inside the month', () => {
  const b = body('fn_marketing_month_covered_by_approved_calendar');
  assert.match(b, /not c\.is_demo/);
  assert.match(b, /c\.approved_hash is not null/);
  assert.match(b, /p\.status <> 'cancelled'/);
  assert.match(b, /interval '1 month'/);
});

test('the CEO watch is never late on a covered month, and closes a late item for one', () => {
  const b = body('fn_ceo_marketing_plan_watch');
  assert.match(b, /v_late := [^;]*and not v_covered;/);
  assert.match(b, /elsif public\.fn_marketing_month_covered_by_approved_calendar\(r\.m\) then\s+perform public\.fn_ceo_improvement_close/);
});

test('the model queue drafts no plan for a covered month', () => {
  const b = body('fn_marketing_steps_due');
  assert.match(b, /if \(cal->>'in_window'\)::boolean\s+and not public\.fn_marketing_month_covered_by_approved_calendar\(\(cal->>'plan_month'\)::date\) then/);
});

test('the new routine is closed to anon and authenticated', () => {
  assert.match(code, /revoke execute on function public\.fn_marketing_month_covered_by_approved_calendar\(date\) from public, anon, authenticated;/);
});
