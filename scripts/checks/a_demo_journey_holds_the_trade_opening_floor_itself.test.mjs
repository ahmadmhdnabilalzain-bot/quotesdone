// A DEMO JOURNEY HOLDS THE TRADE-OPENING FLOOR ITSELF, AND THE REAL RULE IS NOT BENT TO FIT THE HARNESS.
// Seat: sales_engineer (the journeys' intake doors). 11 Nov 2026.
//
// MEASURED, nightly run 077cbbfc (10 Nov 2026 22:07-23:46 UTC): drawing_reaches_suppliers and cad_identity_reaches_no_supplier
// made one ZZ DEMO HVAC supplier each and customer_api create_inquiry answered HTTP 409 trade_not_open, twice. Since #1911 a
// ZZ DEMO customer's trade opens at trade_opening_rule.floor_suppliers (5, a CHECK) counting demo suppliers; production held
// 0 other matchable demo HVAC suppliers. run.mjs's three aluminium suppliers were short the same way.
// The fix is in the harness (scripts/e2e/fixtures.mjs openTradeForDemo), so this check holds BOTH directions:
//   * the harness: every nightly harness that posts a request asks openTradeForDemo for that trade BEFORE it posts, and the
//     helper reads the floor from the database rather than carrying a number;
//   * the rule: the floor stays a CHECK of 5, the real threshold stays 5..25, a real customer never counts a demo supplier,
//     and the demo branch opens at the floor (not at anything a harness happens to make);
//   * the separation the bench relies on: the opening count is UAE-wide while the matcher gates on the request's emirate,
//     and no nightly request is posted in the bench's emirate.
// Fails on origin/main 57418c095: fixtures.mjs exports no openTradeForDemo and no harness asks for the floor.
//   node --test scripts/checks/a_demo_journey_holds_the_trade_opening_floor_itself.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const src = (p) => readFileSync(p, 'utf8');
const FIXTURES = src('scripts/e2e/fixtures.mjs');
const MIRROR = readSchemaMirror();
const routine = (name) => {
  const at = MIRROR.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  assert.ok(at >= 0, `the schema mirror has no ${name}`);
  const next = MIRROR.indexOf('CREATE OR REPLACE FUNCTION', at + 30);
  return MIRROR.slice(at, next > 0 ? next : undefined);
};

test('the shortfall is the floor minus the run\'s own suppliers, never negative, and refuses nonsense', async () => {
  const { benchShortfall } = await import('../e2e/fixtures.mjs');
  assert.equal(benchShortfall(5, 1), 4);   // one HVAC supplier: the 077cbbfc drawings
  assert.equal(benchShortfall(5, 3), 2);   // run.mjs: A, B, C in aluminium
  assert.equal(benchShortfall(5, 5), 0);   // evidence_pack: five per journey
  assert.equal(benchShortfall(5, 7), 0);
  assert.throws(() => benchShortfall(null, 1));
  assert.throws(() => benchShortfall(5, -1));
  assert.throws(() => benchShortfall('5x', 1));
});

test('the helper reads the floor from the database, asks fn_trade_is_open, and writes no rule', () => {
  const at = FIXTURES.indexOf('export async function openTradeForDemo(');
  assert.ok(at > 0, 'fixtures.mjs exports no openTradeForDemo');
  const body = FIXTURES.slice(at, FIXTURES.indexOf('\n}\n', at));
  assert.match(body, /select floor_suppliers from public\.trade_opening_rule/, 'the floor must be read, not carried');
  assert.match(body, /fn_trade_is_open\(\$\{q\(trade\)\}, true\)/, 'the database itself must say the trade is open for a demo customer');
  assert.match(body, /makeSupplier\(run,/, 'bench suppliers are made through the factory doors every demo supplier passes');
  assert.doesNotMatch(body, /benchShortfall\(\s*\d/, 'no literal floor');
  assert.doesNotMatch(FIXTURES, /(update|insert into)\s+public\.trade_opening_rule/i, 'a harness never writes the opening rule');
  assert.doesNotMatch(FIXTURES, /qd\.trade_opening_fixture_counts/, 'the probe seam is the probe\'s alone');
});

// The nightly harnesses that post a request through customer_api create_inquiry, and the trade each posts in.
const POSTERS = [
  ['scripts/e2e/drawing_reaches_suppliers.mjs', 'hvac'],
  ['scripts/e2e/cad_identity_reaches_no_supplier.mjs', 'hvac'],
  ['scripts/e2e/held_intake_asks_the_open_specs.mjs', 'hvac'],
];
for (const [file, trade] of POSTERS) {
  test(`${file.split('/').pop()} opens ${trade} before it posts`, () => {
    const s = src(file);
    const open = s.indexOf(`openTradeForDemo(run, '${trade}'`);
    const post = s.indexOf("action: 'create_inquiry'");
    assert.ok(post > 0, `${file} no longer posts through create_inquiry: update this list`);
    assert.ok(open > 0 && open < post, `${file} posts in ${trade} without holding the trade-opening floor first`);
    assert.match(s.slice(post, post + 400), /emirate: 'Dubai'/, 'the request must be posted outside the bench emirate');
  });
}
test('run.mjs opens aluminium for the funnel before any journey runs', () => {
  const s = src('scripts/e2e/run.mjs');
  const open = s.indexOf("openTradeForDemo(run, 'aluminium'");
  assert.ok(open > 0 && open < s.indexOf('browser = await launch()'), 'run.mjs must hold the aluminium floor before the journeys start');
  const journeys = src('scripts/e2e/journeys.mjs');
  assert.match(journeys, /aluminium windows supplied and installed for a private villa in Dubai/, 'journey a\'s request is in Dubai');
});

test('the bench emirate is one no nightly request is posted in', async () => {
  const { BENCH_EMIRATE } = await import('../e2e/fixtures.mjs');
  assert.ok(BENCH_EMIRATE && BENCH_EMIRATE !== 'Dubai');
});

test('the real rule is not bent: floor 5 in a CHECK, threshold 5..25, a real customer never counts demo, demo opens at the floor', () => {
  assert.ok(MIRROR.includes('trade_opening_rule_floor_suppliers_check CHECK ((floor_suppliers = 5))'), 'the floor is a CHECK of exactly 5');
  assert.ok(MIRROR.includes('trade_opening_rule_open_at_suppliers_check CHECK (((open_at_suppliers >= 5) AND (open_at_suppliers <= 25)))'), 'the real threshold stays 5..25');
  const count = routine('fn_trade_verified_suppliers');
  assert.match(count, /NOT COALESCE\(l\.is_demo, false\)\) OR p_with_fixtures|not coalesce\(l\.is_demo, false\) or p_with_fixtures/i, 'a demo supplier counts only when the caller is a demo customer');
  assert.doesNotMatch(count, /emirate/i, 'the opening count is UAE-wide');
  const open = routine('fn_trade_is_open');
  assert.match(open, /when p_fixture then \(select n\.v >= r\.floor_suppliers/i, 'a demo customer\'s trade opens at the floor');
  assert.match(open, /n\.v >= r\.open_at_suppliers/i, 'a real customer\'s trade opens at the tuned threshold');
  const match = routine('fn_match_capability');
  assert.match(match, /= any\(loc\.stated\)/, 'the matcher gates on the request\'s emirate, which is what keeps the bench out of the journey\'s routing');
});
