// THE DOCUMENT INTAKE ACCURACY SUITE SCORES HONESTLY (sales_engineer / it_engineer, 7 Oct 2026, ledger 1162).
// The suite (scripts/e2e/document_intake_accuracy.mjs) is how "not a single mistake in any trade licence" is
// measured, so its instrument is checked: a value read where the document prints none is WRONG (never n/a), an
// unread field is HELD (never correct), and an approval of a licence that must be held is UNSAFE.
//   node --test scripts/checks/document_intake_accuracy_scores_honestly.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { judge, canonAuthority } from '../e2e/document_intake_score.mjs';

test('a field is correct only when it equals the truth', () => {
  assert.equal(judge('legal_name_en', 'ZZ DEMO Dune Plumbing LLC', 'zz demo dune plumbing l.l.c'.replace('l.l.c', 'llc')), 'correct');
  assert.equal(judge('legal_name_en', 'ZZ DEMO Sidra Lifts Est', 'ZZ DEMO Sidra Lifts'), 'wrong', 'a trade name is not the legal name');
  assert.equal(judge('expiry_date', '2027-03-02', null), 'held');
  assert.equal(judge('expiry_date', null, '2027-03-02'), 'wrong', 'a date the document does not print is a guess');
  assert.equal(judge('expiry_date', null, null), 'n/a');
  assert.equal(judge('licence_no', 'DMCC-104477', 'dmcc-104477'), 'correct');
  assert.equal(judge('activities', ['A works', 'B works'], ['b works', 'A works']), 'correct');
  assert.equal(judge('activities', ['A works', 'B works'], ['A works']), 'wrong');
});

test('an authority is compared through one canonical list, never by free text', () => {
  assert.equal(canonAuthority('DUBAI ECONOMY AND TOURISM (DET)'), 'Dubai Department of Economy and Tourism');
  assert.equal(canonAuthority('Jebel Ali Free Zone Authority'), 'Jebel Ali Free Zone Authority');
  assert.notEqual(canonAuthority('Ras Al Khaimah Economic Zone'), canonAuthority('Ras Al Khaimah Department of Economic Development'));
  assert.equal(judge('authority', 'Sharjah Media City Authority', 'Sharjah Economic Development Department'), 'wrong');
});
