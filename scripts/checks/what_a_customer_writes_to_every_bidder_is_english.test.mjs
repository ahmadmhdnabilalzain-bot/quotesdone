// WHAT A CUSTOMER WRITES TO EVERY BIDDER IS ENGLISH (5 Oct 2026, sales_engineer, founder_instruction 1026).
// A clarification answer (messages_api clarify_answer) and a note on a live request (customer_api rfq_note) are
// stored on rfq_clarification and e-mailed to every matched supplier. Suppliers read English only (ledger 993), so
// both refuse Arabic script BEFORE the row is stored or any supplier is notified (_shared/supplier_english.ts).
//   node --test scripts/checks/what_a_customer_writes_to_every_bidder_is_english.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');

const gateBefore = (src, start, store, label) => {
  const from = src.indexOf(start);
  assert.ok(from > 0, `${label}: the handler is gone`);
  const gate = src.indexOf('if (hasArabic(', from);
  const write = src.indexOf(store, from);
  assert.ok(gate > from && write > from, `${label}: no English-only gate or no store`);
  assert.ok(gate < write, `${label}: the English-only gate runs after the text is stored`);
};

test('a clarification answer in Arabic is refused before it is stored or sent to any bidder', () => {
  gateBefore(R('supabase/functions/messages_api/index.ts'), "if (action === 'clarify_answer') {", ".from('rfq_clarification').update(", 'clarify_answer');
});

test('a note on a live request in Arabic is refused before it is stored or sent to any bidder', () => {
  gateBefore(R('supabase/functions/customer_api/index.ts'), "if (action === 'rfq_note') {", ".from('rfq_clarification').insert(", 'rfq_note');
});
