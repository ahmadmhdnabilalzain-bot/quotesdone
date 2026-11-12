// THE CUSTOMER READS THE COMPARISON AND THE QUOTATION AS THEY WERE MADE (sales_engineer, 12 Nov 2026; final audit
// customer_journey M1, M2, M4, fix group Q6, ledger 1642). Three labels said something the analysis did not:
//   M1  the expert comparison was titled "Comparison by our rules · specs not assessed": Comparison.tsx read any
//       analysis.disclaimer as degraded, and quote_compare sets a disclaimer on the expert path too;
//   M2  "Best value" sat on the quote the comparison rejected ("a lower spec, not a saving"): the badge ranked on stated
//       price alone, over a quote our own review flags as falling short of the request;
//   M4  every customer quotation printed "Supplier's note: Read from the PDF file with no model: N priced line(s). Please
//       check every figure before sending.": QuoteForm put the reader's internal note into the notes-for-customer field.
// The components are inline JSX, so the rule is read from the source, code lines only (never the comments).
//   node --test scripts/checks/the_customer_reads_the_comparison_and_the_quotation_as_they_were_made.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));
const code = (p) => readFileSync(ROOT + p, 'utf8').split('\n').filter((l) => !/^\s*(\/\/|\{\/\*)/.test(l)).join('\n');

test('M1: only quote_compare\'s own `degraded` makes the comparison "by our rules"', () => {
  const c = code('src/components/me/requests/Comparison.tsx');
  assert.match(c, /setDegraded\(!!j\.degraded\);/);
  assert.doesNotMatch(c, /setDegraded\([^)]*disclaimer/, 'a disclaimer is read as degraded again');
  const q = code('supabase/functions/quote_compare/index.ts');
  assert.match(q, /parsed\.disclaimer = \(lang === 'ar'\) \? DISCLAIMER_AR : DISCLAIMER_EN;/, 'the expert path no longer sets its disclaimer: re-check what the card reads');
  assert.match(q, /return J\(\{ ok: true, analysis: await gated\(withRoster\(parsed\), authorModel\) \}\);/, 'the expert answer now says degraded');
});

test('M2: "Best value" is never given to a quote the review says falls short of the request', () => {
  const c = code('src/components/me/requests/InquiryCard.tsx');
  assert.match(c, /const fallsShort = \(q\) => Array\.isArray\(q\.review_notes\) && q\.review_notes\.some\(\(n\) => n && n\.severity === 'high'\);/);
  assert.match(c, /const bestId = quotes\.length >= 2 && eligible\.length \? eligible\.slice\(\)/);
});

test('M2: no value score is shown on a quote that falls short, and with every quote short there is no badge', () => {
  const c = code('src/components/me/requests/InquiryCard.tsx');
  assert.match(c, /const shownValue = Object\.fromEntries\(quotes\.map\(\(q\) => \[q\.id, fallsShort\(q\) \? null : vmap\[q\.id\]\]\)\);/);
  assert.match(c, /<LevelledRows quotes=\{quotes\} vmap=\{shownValue\}/, 'the table shows the raw score');
  assert.match(c, /vscore=\{shownValue\[q\.id\]\}/, 'the card shows the raw score');
  assert.doesNotMatch(c, /vmap=\{vmap\}|vscore=\{vmap\[/);
  // the rule itself, replayed: the badge goes to the best ELIGIBLE quote, or to none
  const fallsShort = (q) => Array.isArray(q.review_notes) && q.review_notes.some((n) => n && n.severity === 'high');
  const pick = (quotes, vmap) => { const eligible = quotes.filter((q) => !fallsShort(q)); return quotes.length >= 2 && eligible.length ? eligible.slice().sort((a, b) => (vmap[b.id] || 0) - (vmap[a.id] || 0))[0].id : null; };
  const low = { id: 'a', review_notes: [{ severity: 'high', code: 'grade_lower' }] }, ok = { id: 'b', review_notes: [{ severity: 'info' }] };
  assert.equal(pick([low, ok], { a: 100, b: 64 }), 'b');
  assert.equal(pick([low, { ...low, id: 'c' }], { a: 100, c: 90 }), null);
});

test('M4: the reader\'s internal note never becomes the supplier\'s note to the customer', () => {
  const f = code('src/components/portal/supplier/core/QuoteForm.tsx');
  assert.doesNotMatch(f, /setNotes\(pr\.notes\)/);
  const reader = code('supabase/functions/quote_extract/quote_from_document.ts');
  assert.match(reader, /notes: `Read from the \$\{ex\.kind\.toUpperCase\(\)\} file with no model/, 'the reader note changed: re-check where it can surface');
});
