// THE DEMAND FORECAST IS AN ESTIMATE, IS CODE, AND ACTS (sales_engineer, 5 Oct 2026, backlog T4 ledger 1019).
//
// WHAT FAILS IF THE CAUSE RETURNS:
//   * a forecast row can be stored without basis = 'estimate', or the method/sufficiency label is gone;
//   * the tick reaches a model (fn_reason_hold / think) - this forecast is arithmetic;
//   * demo inquiries are counted, or searches are added into the inquiry projection;
//   * forecast demand no longer moves a below-target supply gap to recruit;
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

test('every stored forecast is labelled an estimate, with its method and sufficiency', () => {
  assert.match(src, /basis\s+text not null default 'estimate' check \(basis = 'estimate'\)/);
  assert.match(tick, /insufficient_data/);
  assert.match(tick, /'basis', 'estimate'/);
});

test('code only: no model, demo excluded, searches never added to inquiries', () => {
  assert.doesNotMatch(tick, /fn_reason_hold|think\(|fn_reason_ask/);
  assert.match(tick, /not coalesce\(c\.is_demo, false\)/);
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
  assert.doesNotMatch(src, /demand_search \([^)]*\btext\b[^)]*\)\s*select/);
  assert.match(src, /revoke execute on function public\.fn_demand_search_record\(text, text\) from public, anon, authenticated;/);
  assert.match(src, /revoke all on public\.demand_search from anon, authenticated;/);
});
