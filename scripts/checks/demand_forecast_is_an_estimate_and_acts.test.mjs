// THE DEMAND FORECAST IS AN ESTIMATE, IS CODE, AND ACTS (sales_engineer, 5 Oct 2026, backlog T4 ledger 1019).
//
// WHAT FAILS IF THE CAUSE RETURNS:
//   * a forecast row can be stored without basis = 'estimate', or the method/sufficiency label is gone;
//   * the tick reaches a model (fn_reason_hold / think) - this forecast is arithmetic;
//   * a fixture customer's inquiry (is_demo, ZZ DEMO, @example.invalid) or one with no customer is counted, or
//     searches are added into the inquiry projection;
//   * forecast demand no longer moves a below-target supply gap to recruit, or moves one with nobody left to
//     invite, or the canonical supply-gap tick stops releasing a rule:forecast_demand gap (review of #1182);
//   * the search id sequence is open to anon/authenticated, or searches older than 90 days are kept;
//   * the brief box stops recording a recognised trade, or a search keeps the visitor's text;
//   * production, in ONE aborted transaction: the _probe.sql answers PROBE OK (see the pending note).
//
//   node --test scripts/checks/demand_forecast_is_an_estimate_and_acts.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const src = read('scripts/sql/the_sales_engineer_forecasts_thirty_and_ninety_days_of_demand_per_trade_and_emirate.sql');
const tick = src.slice(src.indexOf('function public.fn_demand_forecast_tick('), src.indexOf('insert into public.seat_duty'));
const gapTick = src.slice(src.indexOf('create or replace function public.fn_sales_engineer_supply_gap('));

test('every stored forecast is labelled an estimate, with its method and sufficiency', () => {
  assert.match(src, /basis\s+text not null default 'estimate' check \(basis = 'estimate'\)/);
  assert.match(tick, /insufficient_data/);
  assert.match(tick, /'basis', 'estimate'/);
});

test('code only: no model, demo excluded, searches never added to inquiries', () => {
  assert.doesNotMatch(tick, /fn_reason_hold|think\(|fn_reason_ask/);
  // review of #1182: the canonical demo rule (a_demo_request_is_never_supply_gap_demand.sql), not is_demo alone
  assert.match(tick, /and i\.customer_id is not null and not coalesce\(public\.fn_seat_clock_customer_is_fixture\(c\), false\)/);
  assert.doesNotMatch(tick, /not coalesce\(c\.is_demo, false\)/);
  assert.match(tick, /array\(select distinct t from unnest\(coalesce\(i\.trades/, 'an inquiry whose trades repeat its category is counted twice');
  assert.match(tick, /count\(\*\) filter \(where k = 'i'\)::int as i90/);
  assert.doesNotMatch(tick, /i30 \+ a?\.?s30|i90 \+ a?\.?s90/);
});

test('it acts: forecast demand moves a below-target gap to recruit, and it is a daily sales_engineer duty', () => {
  assert.match(tick, /set status = 'recruit', decided_by = 'rule:forecast_demand'/);
  assert.match(tick, /g\.matchable < g\.target/);
  assert.match(src, /'sales_engineer\.demand_forecast', 'sales_engineer', '1 day', 'fn_demand_forecast_tick'/);
});

test('the brief box records the recognised trade, never the text, and the recorder is service-role only', () => {
  const site = read('supabase/functions/public_site/index.ts');
  assert.match(site, /rpc\('fn_demand_search_record', \{ p_category: category, p_emirate: emirate \}\)/);
  assert.match(site, /if \(category && await rl\('demand_search_ip:' \+ ip, 5, 86400\)\)/, 'search recording is not rate-limited per IP');
});

test('searches alone never start recruitment (review of #1182: an anonymous visitor could)', () => {
  assert.match(tick, /and f\.forecast_90d >= 1 /);
  assert.doesNotMatch(tick, /searches_30d >= \d/);
  assert.doesNotMatch(src, /demand_search \([^)]*\btext\b[^)]*\)\s*select/);
  assert.match(src, /revoke execute on function public\.fn_demand_search_record\(text, text\) from public, anon, authenticated;/);
  assert.match(src, /revoke all on public\.demand_search from anon, authenticated;/);
});

test('a forecast recruitment never overrides "nobody to invite", and the canonical tick releases it (review of #1182)', () => {
  assert.match(tick, /and g\.uninvited_pool > 0 and g\.decided_by is distinct from 'rule:no_uninvited_leads'/);
  assert.ok(gapTick.length > 0, 'fn_sales_engineer_supply_gap is not redefined in this file');
  assert.match(gapTick, /where g\.status = 'recruit' and g\.decided_by = 'rule:forecast_demand'\s+and not exists \(select 1 from public\.demand_forecast f/);
  assert.match(gapTick, /revoke execute on function public\.fn_sales_engineer_supply_gap\(integer\) from public, anon, authenticated;/);
  // the rest of the canonical body is carried over unchanged (the demo rule and the customer-waiting release)
  assert.match(gapTick, /and not coalesce\(public\.fn_seat_clock_customer_is_fixture\(c\), false\)/);
  assert.match(gapTick, /decided_by = 'rule:customer_waiting' and short_open = 0 and demand_90d = 0/);
});

test('the search id sequence is closed and old searches are purged (review of #1182)', () => {
  assert.match(src, /revoke all on sequence public\.demand_search_id_seq from anon, authenticated;/);
  assert.match(tick, /delete from public\.demand_search where searched_at < now\(\) - interval '90 days'/);
});

test('the probe proves a fixture customer and a customer-less inquiry never act (review of #1182)', () => {
  const probe = read('scripts/sql/the_sales_engineer_forecasts_thirty_and_ninety_days_of_demand_per_trade_and_emirate_probe.sql');
  assert.match(probe, /'ZZ DEMO forecast probe', 'forecast-probe@example\.invalid'/);
  assert.match(probe, /a fixture or customer-less inquiry moved its gap/);
  assert.match(probe, /a forecast recruitment was not released/);
  assert.match(probe, /a gap with no lead left was recruited for/);
  assert.doesNotMatch(probe, /'ZZ DEMO probe inquiry', 'quoted'\);/, 'a customer-less ZZ DEMO inquiry must not be the case that acts');
});
