// A CUSTOMER WITH NO SUPPLIER IS PROMISED NO QUOTE, AND NOTHING IS LEFT WAITING (sales_engineer, 2 Nov 2026, ledger 1456).
//   node --test scripts/checks/a_customer_with_no_supplier_is_promised_no_quote.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const R = (p) => readFileSync(fileURLToPath(new URL('../../' + p, import.meta.url)), 'utf8');
const SQL = R('scripts/sql/a_customer_with_no_supplier_is_told_the_truth_and_nothing_is_left_waiting.sql');

test('the screen promises no quote, and the list does not then say matching', () => {
  const none = /nr_posted_none: '[^\n]*/.exec(R('src/components/me/portalText.ts'))[0];
  assert.match(none, /cannot promise a quote/);
  assert.doesNotMatch(none, /as soon as a quote arrives/);
  assert.match(R('src/components/me/NewRequest.tsx'), /onDone\(\{ none: true/);
  assert.match(R('src/components/me/CustomerPortal.tsx'), /r && r\.none \? ''/);
});

test('the e-mails promise no quote to a request nobody has', () => {
  assert.match(SQL, /we cannot promise a quote/);
  assert.match(SQL, /case when v_unreachable then 'We cannot promise a quotation/);
  assert.doesNotMatch(SQL, /We will write as soon as one of them has your request/);
});

test('a request held for its specs is not told it has no supplier, and is not closed', () => {
  assert.match(SQL, /and not public\.fn_inquiry_awaits_specs\(i\.id\)/);
  assert.match(SQL, /finding_suppliers'\)::boolean, false\) and not public\.fn_inquiry_awaits_specs/);
});

test('a request that reached nobody is closed on the clock, and the customer is told', () => {
  assert.match(SQL, /interval '14 days'[\s\S]*status = 'expired'[\s\S]*request_closed_no_supplier/);
  assert.match(R('supabase/functions/resilience_ping/index.ts'), /rpc\('fn_sales_engineer_closes_unreached_requests'\)/);
});
