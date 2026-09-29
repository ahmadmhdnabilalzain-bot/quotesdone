// A HELD REQUEST CAN BE COMPLETED BY ITS CUSTOMER (customer_support, 29 Sep 2026; founder ledger 1018).
//
// scripts/sql/a_held_request_takes_its_missing_specs_from_the_customer_and_is_released_when_complete.sql built the
// one door (fn_inquiry_add_missing_specs) and its _probe.sql proves what it does. Before it, a request held for its
// specs could not be completed by anyone: the portal's edit wrote summary, budget and emirate only. This fails when
// the way back in is lost again:
//   * customer_api answers missing_specs and add_missing_specs through the SQL routines, refuses a banned customer,
//     and offers a completed request that reached no supplier to the matcher;
//   * the request list carries rfq_ready, and the portal shows MissingSpecs on a held, open request.
// Run: node --test scripts/checks/a_held_request_can_be_completed_by_its_customer.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (f) => readFileSync(join(REPO, f), 'utf8');

test('customer_api reads and writes the missing specs through the one door, and releases a completed request', () => {
  const src = read('supabase/functions/customer_api/index.ts');
  assert.match(src, /\.rpc\('fn_inquiry_missing_specs'/, 'missing_specs no longer asks the live hold check');
  assert.match(src, /\.rpc\('fn_inquiry_add_missing_specs'[^)]*p_source: 'customer_portal'/, 'add_missing_specs does not go through the one door');
  assert.match(src, /const MUTATING = \[[^\]]*'add_missing_specs'/, 'a banned customer could still add specs');
  assert.match(src, /r\.ready === true && r\.reached_suppliers === false\)[\s\S]{0,120}matchAndNotify\(/, 'a completed request that reached nobody is not offered to the matcher');
  assert.match(src, /const cols = '[^']*\brfq_ready\b/, 'the request list no longer says whether a request is held');
});

test('the portal shows the missing fields on a held, open request', () => {
  const cp = read('src/components/me/CustomerPortal.tsx');
  assert.match(cp, /inq\.rfq_ready === false[\s\S]{0,160}<MissingSpecs /, 'the portal does not show MissingSpecs on a held request');
  const ms = read('src/components/me/MissingSpecs.tsx');
  assert.match(ms, /action: 'missing_specs'/);
  assert.match(ms, /action: 'add_missing_specs'/);
});
