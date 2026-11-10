// THE MONTH CLOSES ON THE BOOKS AND THE RECORDED MONTH-END EMAIL SCAN (accountant, 10 Nov 2026, rulings 1559 and 1574).
// Measured that day: October had no close because fn_accountant_month_close_status answered 'waiting_for_statement', the
// founder's close pack led with "Bank against the Mashreq statement", and nothing recorded the month-end email scan.
// Fix: scripts/sql/the_month_closes_on_the_books_and_the_recorded_month_end_email_scan.sql
//   node --test scripts/checks/the_month_closes_on_the_books_and_the_recorded_month_end_email_scan.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { canonicalBody, productionSkip, rehearseChain } from '../lib/canonical_body.mjs';

const FILE = 'scripts/sql/the_month_closes_on_the_books_and_the_recorded_month_end_email_scan.sql';
const STATEMENT = /waiting_for_statement|bank_statement_intake|bank_statement_line|fn_accountant_statement_booked/;

test('no close routine waits for, or reads, a bank statement', () => {
  for (const fn of ['fn_accountant_month_close_status', 'fn_accountant_month_close_tick', 'fn_accountant_close_by_day_5',
    'fn_accountant_month_close', 'fn_accountant_founder_close_pack_tick', 'fn_accountant_founder_close_pack_figures']) {
    const { file, body } = canonicalBody(fn);
    assert.doesNotMatch(body.replace(/--[^\n]*/g, ''), STATEMENT, `${file}: ${fn} still reads the bank statement`);
  }
  assert.doesNotMatch(canonicalBody('fn_accountant_founder_close_pack_document').body, /Mashreq statement/, 'the close pack still prints the statement section');
});

test('the close is due by day 5, or two days after a recorded scan, and the pack carries the receipts', () => {
  const { body } = canonicalBody('fn_accountant_month_close_status');
  assert.match(body, /from public\.accountant_month_scan where month = v_m/);
  assert.match(body, /\(s\.scanned_at at time zone 'Asia\/Dubai'\)::date \+ 2/);
  assert.match(canonicalBody('fn_accountant_founder_close_pack_figures').body, /'receipts', v_receipts/);
});

test('a scan cannot claim a booking the books do not hold', () => {
  const { body } = canonicalBody('fn_accountant_month_scan_record');
  assert.match(body, /if p_receipts_booked > v_measured then/);
  assert.match(body, /no figure without a source row/);
});

test('production, rolled back: October closes on the books and its pack builds', { skip: productionSkip() }, async () => {
  const v = await rehearseChain([FILE], FILE.replace(/\.sql$/, '_probe.sql'));
  assert.match(v, /^PROBE OK/, v);
});
