// WHAT A CUSTOMER WRITES TO EVERY BIDDER REACHES THEM IN ENGLISH (5 Oct 2026, sales_engineer, founder_instruction 1026,
// release review of #1195). A clarification answer (messages_api clarify_answer) and a note on a live request
// (customer_api rfq_note) are e-mailed to every matched supplier. Suppliers read English only (ledger 993); customers
// write in their own language. So an Arabic text is kept as written (answer_as_written), the supplier copy is held
// (holdForEnglish) and sent only when the model route has written its English (_shared/supplier_english.ts).
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * either handler stores or mails the text BEFORE its Arabic branch, or its Arabic branch writes the supplier
//     copy (answer) or mails anyone;
//   * either handler mails suppliers by any road other than mailMatched (which drops a row carrying Arabic);
//   * the replay stops delivering surface sales_engineer.supplier_english through finishEnglish;
//   * clarify_list shows a supplier a row whose English is still held.
//   node --test scripts/checks/what_a_customer_writes_to_every_bidder_is_english.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { functionSource } from '../lib/function_sources.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
// Code only: a comment describing the rule must not satisfy (or fail) it.
const code = (t) => t.split('\n').filter((l) => !/^\s*\/\//.test(l)).join('\n');

function handler(src, start, end) {
  const from = src.indexOf(start);
  assert.ok(from > 0, `${start}: the handler is gone`);
  const to = src.indexOf(end, from + start.length);
  return src.slice(from, to > from ? to : undefined);
}

function arabicIsHeld(body, label) {
  const gate = body.indexOf('if (hasArabic(');
  assert.ok(gate > 0, `${label}: no Arabic branch`);
  const hold = body.indexOf('holdForEnglish(', gate);
  assert.ok(hold > gate, `${label}: the Arabic branch never files the English (holdForEnglish)`);
  const done = body.indexOf('held_for_english: true', hold);
  assert.ok(done > hold, `${label}: the Arabic branch never answers held_for_english`);
  const branch = body.slice(gate, body.indexOf('\n', done));
  assert.match(branch, /answer_as_written:/, `${label}: the customer's Arabic is not kept as written`);
  assert.match(branch, /english_held_at:/, `${label}: the supplier copy is not marked held`);
  assert.doesNotMatch(branch, /(update|insert)\(\{[^}]*[{ ,]answer: (?!null)/, `${label}: the Arabic branch writes the supplier copy`);
  assert.doesNotMatch(branch, /mailMatched|notify|requestDelivery|queueNotifications/, `${label}: the Arabic branch mails someone`);
  assert.match(branch, /notice: HELD_NOTICE\.ar/, `${label}: the customer is not told in Arabic that it will be passed on`);
  const rest = body.slice(0, gate);
  assert.doesNotMatch(rest, /\.from\('rfq_clarification'\)\.(update|insert)\(|mailMatched\(/, `${label}: the text is stored or mailed before the Arabic branch`);
  assert.match(body.slice(gate), /mailMatched\(/, `${label}: English text no longer reaches suppliers through mailMatched`);
  for (const bad of ['requestDelivery(', 'queueNotifications(', 'notify(']) {
    assert.ok(!body.includes(bad), `${label}: suppliers are mailed through ${bad} instead of mailMatched`);
  }
}

test('a clarification answer in Arabic is kept as written and its supplier copy is held for English', () => {
  arabicIsHeld(handler(code(R('supabase/functions/messages_api/index.ts')), "if (action === 'clarify_answer') {", 'const inquiry_id ='), 'clarify_answer');
});

test('a note on a live request in Arabic is kept as written and its supplier copy is held for English', () => {
  arabicIsHeld(handler(code(functionSource('customer_api')), "if (action === 'rfq_note') {", "if (action === 'my_inquiries')"), 'rfq_note');
});

test('every supplier e-mail on these paths drops a row carrying Arabic', () => {
  const s = code(R('supabase/functions/_shared/supplier_english.ts'));
  assert.match(handler(s, 'export async function mailMatched(', '\n}'), /toSuppliers\(/, 'mailMatched sends without the Arabic filter');
  assert.match(handler(s, 'export async function finishEnglish(', '\n}'), /englishAnswer\(answer\)/, 'the replay stores an answer it never checked for Arabic');
});

test('the replay delivers the held English through finishEnglish', () => {
  const s = code(R('supabase/functions/_shared/reasoned_delivery.ts'));
  assert.match(s, /row\.surface === 'sales_engineer\.supplier_english'[\s\S]{0,300}io\.supplierEnglish\(/, 'no delivery branch for the held English');
  assert.match(s, /supplierEnglish: async[\s\S]{0,200}finishEnglish\(admin/, 'the live delivery does not call finishEnglish');
});

test('a supplier never sees a row whose English is still held', () => {
  const s = code(R('supabase/functions/messages_api/index.ts'));
  assert.match(s, /english_held_at \? \{ \.\.\.r, answer: null, answered_at: null \}/, 'clarify_list shows suppliers a held row');
});
