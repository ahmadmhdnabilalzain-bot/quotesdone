// it_engineer (704, 28 Sep 2026): a supply gap whose trade and area have no uninvited lead left is deferred by rule
// BEFORE the loop that files open gaps for paid reasoning. Fails if the rule is lost or moved after the loop.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const sql = readFileSync(new URL('../sql/a_supply_gap_with_no_leads_left_is_deferred_by_rule.sql', import.meta.url), 'utf8');

test('the no-leads rule defers open gaps before any is filed for reasoning', () => {
  const rule = sql.search(/set status = 'deferred', decided_by = 'rule:no_uninvited_leads'[\s\S]{0,120}where status = 'open' and uninvited_pool = 0/);
  const loop = sql.indexOf("fn_seat_duty_reason('sales_engineer'");
  assert.ok(rule > 0, 'the rule is present');
  assert.ok(loop > rule, 'the rule runs before the reasoning loop');
});
