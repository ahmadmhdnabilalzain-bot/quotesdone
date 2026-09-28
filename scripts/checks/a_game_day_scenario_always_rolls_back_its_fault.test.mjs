// A GAME DAY SCENARIO ALWAYS ROLLS BACK ITS FAULT (it_engineer, founder_instruction 1009).
// The monthly game day injects real faults into production tables (a lowered threshold, an expired credential,
// an open WhatsApp-down finding). What makes that safe is one shape per scenario: everything happens inside a
// BEGIN ... EXCEPTION block that ends by raising the rollback marker, and the handler returns the measurements
// only for that marker. Lose the raise and the fault is committed. This fails if any scenario loses it.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const FILE = 'scripts/sql/the_it_engineer_breaks_the_company_once_a_month_to_prove_it_heals.sql';
const SCENARIOS = ['email_provider_down', 'whatsapp_down', 'edge_function_slow', 'db_connection', 'credential_expired'];
const sql = readFileSync(FILE, 'utf8');

function body(name) {
  const start = sql.indexOf(`create or replace function public.fn_it_game_day_${name}()`);
  assert.ok(start >= 0, `${name}: routine missing`);
  const end = sql.indexOf('end $fn$;', start);
  return sql.slice(start, end);
}

for (const s of SCENARIOS) {
  test(`${s} raises the rollback marker and only that marker returns a result`, () => {
    const b = body(s);
    assert.match(b, /raise exception 'QD_GAME_DAY_ROLLBACK';\s*\n\s*exception when others then/);
    assert.match(b, /if sqlerrm = 'QD_GAME_DAY_ROLLBACK' then/);
  });
}

test('the runner names all five scenarios and the duty is monthly', () => {
  for (const s of SCENARIOS) assert.ok(sql.includes(`'${s}'`), s);
  assert.match(sql, /\('it_engineer\.game_day', 'it_engineer', interval '1 month', 'fn_it_engineer_game_day'/);
});
