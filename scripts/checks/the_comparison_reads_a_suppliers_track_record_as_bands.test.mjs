// THE COMPARISON READS A SUPPLIER'S TRACK RECORD AS BANDS (customer_support, supplier-reviews audit of 10 Nov 2026,
// founder ruling 1608).
//
// MEASURED on origin/main: quote_compare handed the comparison model each supplier's EXACT QuotesDone rating, review
// count, years trading, jobs won and win rate; the model's track_record_note is printed in the comparison the customer
// reads BEFORE paying the reveal fee (_shared/quote_documents/compare_rows.ts "Track record"). "4.6 stars, 23 reviews,
// trading since 2011" is the fingerprint customer_api has banded since 27 Jul 2026 (my_inquiries). The bands now live in
// one module, _shared/pre_reveal_bands.ts, and both read it; win rate and jobs won are withheld, as customer_api does.
//
//   node --test scripts/checks/the_comparison_reads_a_suppliers_track_record_as_bands.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const REPO = join(import.meta.dirname, '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');

test('the track record the comparison model reads is banded, and carries no win rate or jobs won', () => {
  const src = read('supabase/functions/quote_compare/index.ts');
  const i = src.indexOf('trackBySupplier[String(l.id)] = {');
  assert.ok(i > 0, 'the track record is built in quote_compare/index.ts');
  const obj = src.slice(i, src.indexOf('};', i));
  assert.match(obj, /rating: ratingBand\(/);
  assert.match(obj, /review_count: reviewCountBand\(/);
  assert.match(obj, /years_active: [^,]*yearsBand\(/);
  assert.doesNotMatch(obj, /win_rate|jobs_won/);
});

test('one home for the bands', () => {
  assert.match(read('supabase/functions/_shared/pre_reveal_bands.ts'), /export function ratingBand/);
  const pricing = read('supabase/functions/customer_api/lib/pricing.ts');
  assert.doesNotMatch(pricing, /export function (ratingBand|reviewCountBand|yearsBand)/, 'a second copy of a band');
  assert.match(pricing, /from '\.\.\/\.\.\/_shared\/pre_reveal_bands\.ts'/);
});
