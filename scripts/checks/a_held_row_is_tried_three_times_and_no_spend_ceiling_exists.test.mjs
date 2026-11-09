// A held row is tried 3 times and no spend ceiling exists (it_engineer, 24 Sep 2026).
// The founder, 24 Sep 2026 (founder_instruction 987): no caps on LLM spend; idle spend stays low because the code
// is correct. Fails if: a daily AED ceiling, a per-class call cap or a budget gate is (re)introduced into the gateway,
// the spend guards or any committed SQL; a held row is retried more than 3 times; a founder-hold refusal burns an
// attempt; or the build-test expiry loses its fixture criteria. Offline: reads the committed tree only.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { functionSource } from '../lib/function_sources.mjs';
import { readFileSync, readdirSync } from 'node:fs';
import { sharedModuleSource } from '../lib/function_sources.mjs';

const FILE = 'scripts/sql/a_held_row_is_tried_three_times_and_the_build_test_backlog_is_expired.sql';
const SQL = readFileSync(FILE, 'utf8');
const code = (s) => s.split('\n').filter((l) => !/^\s*(--|\/\/)/.test(l)).join('\n'); // comments may name what was removed
const body = (name) => {
  const i = SQL.indexOf(`create or replace function public.${name}(`);
  assert.ok(i >= 0, `${name} is defined in the file`);
  return SQL.slice(i, SQL.indexOf('end $fn$;', i));
};

test('no spend ceiling or per-class cap exists in the gateway, the guards or any SQL file', () => {
  const ceilingKey = ['llm', 'daily', 'ceiling', 'aed'].join('_');
  const capKey = "'llm_" + "cap_'";
  const gate = ['fn', 'llm', 'budget', 'gate'].join('_');
  for (const f of ['supabase/functions/ai_gateway/index.ts', 'supabase/functions/_shared/spend_guards.ts']) {
    const c = code(f === 'supabase/functions/ai_gateway/index.ts' ? functionSource('ai_gateway') : readFileSync(f, 'utf8'));
    assert.ok(!c.includes(gate) && !c.includes(ceilingKey), `${f} reads no spend ceiling`);
  }
  for (const f of readdirSync('scripts/sql').filter((x) => x.endsWith('.sql'))) {
    const c = code(readFileSync('scripts/sql/' + f, 'utf8'));
    assert.ok(!c.includes(ceilingKey) && !c.includes(capKey) && !c.includes('function public.' + gate), `${f} defines no spend ceiling`);
  }
});

test('a held row is tried 3 times, not 5', () => {
  const due = body('fn_reason_held_due');
  assert.match(due, /attempts >= 3/);
  assert.match(due, /attempts < 3/);
  assert.doesNotMatch(due, /attempts [<>]=? ?5/);
  assert.match(body('fn_reason_held_resolve'), /when attempts >= 3 then 'failed'/);
});

test('waiting while the model is off gives the attempt back', () => {
  assert.match(body('fn_reason_held_resolve'), /'model_hold'[\s\S]*attempts = greatest\(attempts - 1, 0\)/);
});

test('build-test rows are expired only by a fixture marker or the exact e2e fixture text with its inquiry gone', () => {
  const i = SQL.indexOf("set status = 'expired'");
  const upd = SQL.slice(i, SQL.indexOf(');', SQL.indexOf('not exists (select 1 from public.inquiries', i)) + 2);
  assert.match(upd, /h\.status = 'held'/);
  assert.match(upd, /ZZ DEMO\|@example\\.invalid/);
  assert.match(upd, /not exists \(select 1 from public\.inquiries/);
  const e2e = readFileSync('scripts/e2e/journey_audit_buttons.mjs', 'utf8');
  assert.ok(e2e.includes('Gypsum bulkhead standard gypsum board 300mm drop painted finish'), 'the fixture text still lives in the e2e harness');
});

test('a fixture row is never replayed: fn_reason_held_due expires it before any claim; think() files no fixture subject', () => {
  const due = body('fn_reason_held_due');
  const exp = due.indexOf("set status = 'expired'"), claim = due.indexOf('for update skip locked');
  assert.ok(exp > 0 && exp < claim, 'fixture rows are expired before the claim');
  assert.match(due.slice(exp, claim), /ZZ DEMO\|@example\\.invalid[\s\S]*subject->>'fixture' = 'true'/);
  const think = sharedModuleSource('think');
  assert.match(think, /if \(isFixtureRequest\(req\)\)[^\n]*\n\s*else if \(req\.queueWhenHeld !== false\)/);
  assert.match(functionSource('inquiry_intake'), /endsWith\('@example\.invalid'\) \? \{ fixture: true \}/);
});

test('no department budget halt and no pair ceiling: fn_ai_route never refuses or degrades on spend', () => {
  const f = readFileSync('scripts/sql/model_calls_are_never_halted_by_a_department_or_pair_budget.sql', 'utf8');
  const route = code(f.slice(f.indexOf('CREATE OR REPLACE FUNCTION public.fn_ai_route('), f.indexOf('CREATE OR REPLACE FUNCTION public.fn_seat_deliberation_budget(')));
  assert.ok(route.length > 1000, 'fn_ai_route is redefined');
  assert.doesNotMatch(route, /halt_at_pct|degrade_at_pct|'halted'/);
  // The later canonical body (founder_instruction 1056, the seat's own route) must not bring a halt back either.
  const m = readFileSync('scripts/sql/every_seat_runs_the_founders_model_matrix_and_every_review_stays_cross_family.sql', 'utf8');
  const route2 = code(m.slice(m.indexOf('CREATE OR REPLACE FUNCTION public.fn_ai_route('), m.indexOf('create or replace function public.fn_ai_route_review_for(')));
  assert.ok(route2.length > 1000, 'fn_ai_route is redefined in the matrix file');
  assert.doesNotMatch(route2, /halt_at_pct|degrade_at_pct|'halted'/);
  const pair = code(f.slice(f.indexOf('CREATE OR REPLACE FUNCTION public.fn_seat_deliberation_budget(')));
  assert.doesNotMatch(pair, /cap_aed_month/);
  assert.match(pair, /'ok', true/);
  assert.doesNotMatch(code(functionSource('ai_gateway')), /budget_halted/);
});
