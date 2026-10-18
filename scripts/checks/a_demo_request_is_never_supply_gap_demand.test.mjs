// A DEMO REQUEST IS NEVER SUPPLY-GAP DEMAND (sales_engineer, 5 Oct 2026).
//
// WHAT FAILS IF THE CAUSE RETURNS: the canonical fn_sales_engineer_supply_gap counts an inquiry without excluding
// fixture customers; a recruit held by rule:customer_waiting is no longer undone once its customer is gone; an area row
// no counted request names keeps its old demand. Production, in ONE aborted transaction: the _probe.sql answers
// PROBE OK (a new demo request moves nothing, the demo-only gaps leave recruit, a real request still recruits).
//
//   node --test scripts/checks/a_demo_request_is_never_supply_gap_demand.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');

// the LAST file in apply order (MANIFEST, then pending) that defines the routine is the one production runs
const order = [...read('scripts/sql/MANIFEST.txt').split('\n').map((l) => l.trim()).filter((l) => l.endsWith('.sql')),
  'scripts/sql/a_demo_request_is_never_supply_gap_demand.sql'];
const canonical = order.filter((p) => { try { return /function public\.fn_sales_engineer_supply_gap\(/.test(read(p)); } catch { return false; } }).pop();
const src = read(canonical);

test('supply-gap demand excludes fixture customers', () => {
  const inq = src.slice(src.indexOf('inq as materialized'), src.indexOf('pool as materialized'));
  assert.match(inq, /left join public\.customers c on c\.id = i\.customer_id/);
  assert.match(inq, /and not coalesce\(public\.fn_seat_clock_customer_is_fixture\(c\), false\)/);
});

test('a customer-waiting recruit with no counted request left is decided again, and stale area demand is cleared', () => {
  assert.match(src, /where status = 'recruit' and decided_by = 'rule:customer_waiting' and short_open = 0 and demand_90d = 0;/);
  assert.match(src, /set demand_90d = 0, short_open = 0, measured_at = now\(\)\s+where measured_at < now\(\)/);
  assert.ok(src.indexOf("decided_by = 'rule:customer_waiting' and short_open = 0") < src.indexOf('-- A CUSTOMER IS ALREADY WAITING'),
    'the undo must run before the rule re-applies');
});
