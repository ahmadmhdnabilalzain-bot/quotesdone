// node --test src/components/portal/supplier/workspaceCopy.test.mjs
// Walk of 12 Nov 2026 (sales_engineer, built by it_engineer). S5: the supporting-documents line promised sharing that does not exist
// ("Only you see these files until you share them"; no share control, and supporting_documents.ts keeps them from customers by
// design). S12: Insights printed "You were the lowest bid on 0." and "1 inquiries you have not priced" (p1_iphone_a_insights.jpg).
// This fails if either comes back.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ws } from './workspaceCopy.ts';

test('the supporting-documents line promises no sharing', () => {
  assert.doesNotMatch(ws('en', 'sd_sub'), /share|helps a customer/i);
  assert.match(ws('en', 'sd_sub'), /customers never do/);
});

test('English counts say one in the singular, and nothing is said about a lowest price of none', () => {
  assert.equal(ws('en', 'hint_quote_more_t', { unquoted: 1 }), '1 inquiry you have not priced');
  assert.equal(ws('en', 'hint_quote_more_t', { unquoted: 4 }), '4 inquiries you have not priced');
  assert.equal(ws('en', 'days', { n: 1 }), '1 day');
  assert.equal(ws('en', 'hint_doc_expiring_t', { doc: 'ISO certification', days: 1 }), 'ISO certification expires in 1 day');
  assert.equal(ws('en', 'hint_lead_time_t', { days: 9 }), 'Average lead time 9 days');
  const none = ws('en', 'price_detail', { pct: '+3%', n: 4, lowest: 0 });
  assert.equal(none, 'On average your quotes are +3% against the market average, across 4 competitive inquiries.');
  assert.doesNotMatch(none, /lowest/);
  assert.equal(ws('en', 'price_detail', { pct: '−2%', n: 1, lowest: 1 }), 'On average your quotes are −2% against the market average, across 1 competitive inquiry. Yours was the lowest price on one of them.');
});
