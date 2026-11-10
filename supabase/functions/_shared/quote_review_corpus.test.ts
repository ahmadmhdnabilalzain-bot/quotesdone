// quote_review_corpus.test.ts — THE GATE over the 24-trade corpus (two trades from each of the twelve taxonomy groups):
// what the customer reads before the reveal names no planted identifier, every planted deviation is noted on its line,
// the control quote that answers the request exactly draws no deviation note and loses no specification token.
// Seat: sales_engineer. 10 Nov 2026, founder ledger 1588-1590. The same measurement prints the before -> after table:
//   deno run --no-lock --allow-read scripts/e2e/quote_review_corpus.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { measureCorpus } from './quote_review_corpus.ts';
import { CORPUS } from './quote_review.fixture.ts';

const rows = measureCorpus();

Deno.test('the corpus is two trades from each of the twelve groups, goods and services', () => {
  assertEquals(rows.length, 24);
  const byGroup = new Map<string, number>(); for (const r of rows) byGroup.set(r.group, (byGroup.get(r.group) || 0) + 1);
  assertEquals(byGroup.size, 12); for (const [g, n] of byGroup) assertEquals(n, 2, g);
  for (const t of CORPUS) assert(t.supplier.startsWith('ZZ DEMO ') && t.deviant.ids.some((x) => x.endsWith('.example.invalid')), t.code);
});

Deno.test('the measurement is not blind: the old serving leaked most planted identifiers', () => {
  // A check that reads 0 leaks because it cannot see one is worse than none: before this change the same corpus,
  // served the old way (save scrub only, columns raw), showed the customer 125 of 177 planted identifiers.
  const before = rows.reduce((s, r) => s + r.before.deviant.leaks + r.before.control.leaks, 0);
  assert(before >= 100, `the old serving leaked ${before}`);
});

for (const r of rows) {
  Deno.test(`${r.group} / ${r.code}: no identity leak, every planted deviation noted, no false flag, no spec lost`, () => {
    assertEquals(r.after.deviant.leaked, [], 'leaked on the deviant quote');
    assertEquals(r.after.control.leaked, [], 'leaked on the control quote');
    assertEquals(r.after.missed, [], 'planted deviations not noted');
    assertEquals(r.after.extra, [], 'deviation notes nobody planted (false flags)');
    assertEquals(r.after.over_redacted, [], 'specification tokens the customer can no longer read');
    assertEquals(r.after.caught, r.planted);
  });
}
