// Prevents the journey harness drifting back to two retired expectations (it_engineer, 19 Oct 2026):
//   G3 — #919: the buyer pays the reveal BASE fee only; processing_fee is 0 (Cabinet Res. 66/2023
//        Art. 5(3)). A harness that grosses the fee up for card processing fails every paid run.
//   G4 — founder ruling 1008: suppliers are always English. A harness that expects an Arabic or
//        right-to-left supplier portal, or clicks Arabic supplier labels, measures a screen that
//        cannot exist. Customer Arabic passes are untouched and not checked here.
// Reads source only; journeys.mjs is not imported (it loads the production fixtures).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const SRC = readFileSync(new URL('../e2e/journeys.mjs', import.meta.url), 'utf8');

test('journey d expects the base fee only, with no card processing fee', () => {
  assert.doesNotMatch(SRC, /\(1 - PCT\)|FIXED_F/, 'the reveal is grossed up for card processing again');
  assert.match(SRC, /Number\(tx\.processing_fee\) \* 100\) === 0/, 'journey d no longer asserts processing_fee = 0');
  assert.match(SRC, /Number\(tx\.total_charged\) \* 100\) === baseF/, 'journey d no longer asserts total_charged = base');
});

test('supplier passes expect English, left-to-right, and click no Arabic label', () => {
  assert.match(SRC, /const uiLang = \(kind, lang\) => \(kind === 'supplier' \? 'en' : lang\);/, 'the crawl no longer pins suppliers to English');
  assert.match(SRC, /const lang = uiLang\(who\.kind, m\.lang\);/, 'the crawl picks supplier labels by the registration language');
  assert.doesNotMatch(SRC, /supplierTab\(m\.lang/, 'journey b clicks a supplier tab by the pass language');
  assert.match(SRC, /supDir === 'ltr\/en'/, 'journey b no longer asserts an English, ltr supplier portal');
  assert.doesNotMatch(SRC, /supplier[^\n]*rtl\/ar|NAV\.supplier\.ar|ACCOUNT_MENU\.ar\b/, 'a supplier view is expected in Arabic');
});
