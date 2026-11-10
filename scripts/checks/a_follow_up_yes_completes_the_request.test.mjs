// A FOLLOW-UP "YES" COMPLETES THE REQUEST, EXACTLY AS HIRE DOES (sales_engineer, customer-journey follow-up 10 Nov 2026).
//
// MEASURED on origin/main: fn_customer_followup_answer's yes wrote hired_supplier_id only: the request stayed 'revealed',
// with no outcome and no completed_at, and the losing suppliers were never told. The Hire door (customer_api
// complete_inquiry) writes status 'completed', outcome 'hired' and completed_at and tells the losers. This holds the two
// doors to the same write, each guarded so the losers are told once whichever comes first; the SQL file's _probe.sql
// proves it rolled back on production.
//   node --test scripts/checks/a_follow_up_yes_completes_the_request.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { canonicalBody, read } from '../lib/canonical_body.mjs';

test('the yes writes what Hire writes, guarded like Hire, and tells the losers only when it changed the row', () => {
  const { body } = canonicalBody('fn_customer_followup_answer');
  assert.match(body, /set status = 'completed', outcome = 'hired', completed_at = coalesce\(completed_at, now\(\)\), hired_supplier_id = t\.supplier_id/,
    'the follow-up yes does not complete the request');
  assert.match(body, /\(hired_supplier_id is null or hired_supplier_id = t\.supplier_id\)\s+and coalesce\(status, ''\) <> 'completed'/, 'the yes is not guarded like Hire');
  assert.match(body, /if v_won > 0 then[\s\S]{0,200}fn_sales_engineer_tells_losing_suppliers\(t\.inquiry_id, t\.supplier_id\)/, 'the losers are not told, or told on every yes');
  const hire = read('supabase/functions/customer_api/actions/inquiry_lifecycle.ts');
  assert.match(hire, /update\(\{ status: 'completed', hired_supplier_id: q\.supplier_id, completed_at: new Date\(\)\.toISOString\(\), outcome: 'hired' \}\)/,
    'the Hire door no longer writes the same four fields');
});

test('the losers are every other supplier who quoted, once each, never a sanctioned or banned one', () => {
  const { body } = canonicalBody('fn_sales_engineer_tells_losing_suppliers');
  assert.match(body, /q\.supplier_id is distinct from p_winner/);
  assert.match(body, /not public\.fn_is_sanctioned_lead\(le\.id\)/);
  assert.match(body, /'dedupe_key', 'job_awarded_other:' \|\| p_inquiry \|\| ':' \|\| l\.id/);
});
