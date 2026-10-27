// A supplier can add a second option by typing (QA walk, 19 Oct 2026: QuoteForm's newOption existed, and
// supplier_api submit_quote's new_option makes it option max+1, but no control ever opened the form that way).
// The browser walk supplier_full_walk.mjs drives it end to end; this keeps the wiring from being dropped.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
const read = (p) => fs.readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
test('Inquiries offers "Add another option" once a quote exists, and opens the form as a new option', () => {
  const tab = read('src/components/portal/supplier/InquiriesTab.tsx');
  assert.match(tab, /addOption: 'Add another option'/);
  assert.match(tab, /\{ newOption: form === 'new' \}/);
});
test('the portal passes it to QuoteForm, which sends new_option', () => {
  const portal = read('src/components/portal/SupplierPortal.tsx');
  assert.match(portal, /newOption=\{!!o\?\.newOption\}/);
  assert.match(portal, /newOption \? \{ new_option: true \}/);
});
