// resend_inbound must never separate a booked expense from the receipt that evidences it.
//
// Two defects sat behind this file, and only one of them was visible in the code that "handles"
// the failure. v14 booked the expense, logged an error and returned 200 when the archive write was
// refused. The remedy printed by v_expense_receipt_gap - "re-forward the vendor email to the
// inbound address to retry" - could NOT work, because the re-forward hit the DEDUP guard, which
// returned BEFORE any upload was attempted. The entry kept doc_path NULL for ever and the operator
// was told to perform an action that did nothing.
//
// Returning non-200 instead is not the fix: Resend's own redelivery lands on the same dedup guard.
// The fix is that a receipt for an entry with no document is not a duplicate - it is the retry.
//
// These are source assertions, like the other checks in this directory: the behaviour lives in a
// Deno edge function that cannot be imported by the Node test runner, so the guard asserts the
// SHAPE that makes the behaviour possible, and one test asserts the old broken shape is gone.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const src = readFileSync(join(root, 'supabase', 'functions', 'resend_inbound', 'index.ts'), 'utf8');

// The receipt branch only - so an assertion cannot be satisfied by unrelated code elsewhere.
const dedupStart = src.indexOf("const { data: sameDay }");
const receiptEnd = src.indexOf('// ---- Supplier document handling');
assert.ok(dedupStart > 0, 'the same-day dedup lookup is gone from resend_inbound - this guard is now testing nothing');
assert.ok(receiptEnd > dedupStart, 'could not locate the end of the receipt branch in resend_inbound');
const receipt = src.slice(dedupStart, receiptEnd);

test('the dedup lookup reads doc_path, so it can tell a duplicate from a missing receipt', () => {
  assert.match(receipt, /select\('id,amount,currency,doc_path'\)/,
    'the same-day lookup does not select doc_path, so it cannot distinguish "already booked WITH its receipt" ' +
    'from "already booked WITHOUT its receipt". Those are different situations and only one of them is a duplicate.');
});

test('a same-day entry that is missing its receipt is NOT discarded as a duplicate', () => {
  assert.match(receipt, /const gapRow[^\n]*=\s*\(sameDay \|\| \[\]\)\.find\(/,
    'no gapRow is computed. Without it the dedup guard cannot let a retry through.');
  assert.match(receipt, /if \(sameDay && sameDay\.length && !gapRow\) \{/,
    'the dedup early-return is not conditioned on !gapRow, so a re-forwarded receipt for an entry with ' +
    'doc_path NULL is still discarded and v_expense_receipt_gap\'s printed remedy is a no-op.');
});

test('the v14 shape that made the documented remedy impossible cannot come back', () => {
  assert.doesNotMatch(receipt, /select\('id,amount,currency'\)[\s\S]{0,400}?if \(sameDay && sameDay\.length\) \{/,
    'resend_inbound has returned to the v14 dedup guard, which returns before any upload is attempted. ' +
    'Re-forwarding a receipt would silently do nothing again.');
});

test('the backfill attaches the document to the EXISTING entry and books no second expense', () => {
  const gap = receipt.slice(receipt.indexOf('if (gapRow) {'));
  assert.ok(gap.length > 0, 'the gapRow backfill branch is missing');
  const branch = gap.slice(0, gap.indexOf('return J('));
  assert.match(branch, /from\('expense_entries'\)\.update\(\{ doc_path/,
    'the backfill branch does not update expense_entries.doc_path - the receipt would be archived to storage ' +
    'and still not linked to the expense.');
  assert.doesNotMatch(branch, /from\('expense_entries'\)\.insert\(/,
    'the backfill branch inserts an expense_entries row. A retry must never book the same cost twice - that is ' +
    'the exact defect the v14 dedup guard was written to prevent.');
  assert.doesNotMatch(branch, /from\('expenses'\)\.(insert|update)\(/,
    'the backfill branch touches the subscriptions table. The subscription was already upserted when the expense ' +
    'was first booked; re-running it on a retry can overwrite a corrected amount with a re-read one.');
  assert.ok(gap.includes('return J('),
    'the backfill branch does not return, so execution falls through into the insert and books a duplicate expense');
});

test('a refused archive is retried in-process, not deferred to a re-forward that may never come', () => {
  assert.match(receipt, /for \(let attempt = 1; attempt <= 3 && !docPath; attempt\+\+\)/,
    'the receipt upload is attempted once. A transient storage refusal then costs a manual re-forward - ' +
    'and expense_entries#29 (Apify, 3 Aug 2026) is what one refusal produced: the receipt was received and ' +
    'read, and the expense was booked without it.');
});

test('a retry that eventually succeeded is not reported as a failure', () => {
  // fn_watch_failed_runs pages on ANY agent_runs row with status='error'. Keying the run status on
  // upErr - which now holds the LAST error of up to three attempts - would page on every archive
  // that failed once and succeeded on the retry. A monitor that cries wolf gets muted.
  assert.doesNotMatch(receipt, /logRun\(upErr \? 'error' : 'ok'/,
    'the booked-receipt run status is still keyed on upErr. After the v15 retry loop upErr survives a later ' +
    'successful attempt, so a recovered archive would be logged as an error and page an operator for nothing.');
  assert.match(receipt, /logRun\(docPath \? 'ok' : 'error'/,
    'the booked-receipt run status is not keyed on docPath, which is the only value that says whether the ' +
    'document actually reached the archive.');
});
