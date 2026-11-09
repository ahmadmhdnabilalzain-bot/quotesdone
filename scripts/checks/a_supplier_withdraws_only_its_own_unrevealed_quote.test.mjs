// A supplier may withdraw a quotation before the reveal, and only that (QA walk, 19 Oct 2026: the
// "Withdrawn" status had no way in). supplier_api withdraw_quote must key the quote on THIS supplier,
// re-ask the match, refuse a revealed quote, and only move draft/submitted; the portal must offer it.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { functionSource } from '../lib/function_sources.mjs';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const api = functionSource('supplier_api');
const body = api.split("if (action === 'withdraw_quote') {")[1]?.split("if (action === 'submit_quote') {")[0] || '';

test('withdraw_quote exists and is fenced', () => {
  assert.ok(body, 'supplier_api has a withdraw_quote action');
  assert.match(body, /\.eq\('supplier_id', sup\.id\)/, 'the quote is keyed on the signed-in supplier');
  assert.match(body, /matchedInquiry\(Number\(sup\.id\)/, 'the enquiry match is re-asked');
  assert.match(body, /from\('transactions'\)[\s\S]*already_revealed/, 'a revealed quote is refused');
  assert.match(body, /\.in\('status', \['draft', 'submitted'\]\)/, 'only a draft or submitted quote moves');
});
test('the portal offers Withdraw before the reveal', () => {
  const tab = fs.readFileSync(path.join(ROOT, 'src/components/portal/supplier/QuotationsTab.tsx'), 'utf8');
  assert.match(tab, /!i\.revealed && !i\.concluded/);
  assert.match(tab, /qr\.withdraw\(/);
});
