// EVERY LIVE QUOTE IS IN THE COMPARISON, CHEAPEST FIRST (sandbox run 5, tag 321d13ae, 19 Oct 2026).
// Four submitted aluminium quotes (118,500 / 124,900 / 131,000 / 142,000); the model detailed three and
// quote_compare caps `quotes` at three, so the report and compare_csv showed three columns and the
// 131,000 quote was in neither. The roster (all_quotes) carries all four; every one must be a column.
//   deno test --no-lock --node-modules-dir=auto --allow-read=. supabase/functions/_shared/quote_documents_every_quote_listed.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { compareTable } from './quote_documents.ts';

const roster = [
  { label: 'Supplier A', price: 118500, lead_time: '8 weeks', warranty: '12 months', status: 'shortlisted', rank: 1 },
  { label: 'Supplier B', price: 124900, lead_time: '8 weeks', warranty: '12 months', status: 'shortlisted', rank: 3 },
  { label: 'Supplier C', price: 131000, lead_time: '8 weeks', warranty: '12 months', status: 'received', rank: null },
  { label: 'Supplier D', price: 142000, lead_time: '4 weeks', warranty: '12 months', status: 'shortlisted', rank: 2 },
];
// The model's detail, in the model's own order, for three of the four.
const quotes = [
  { label: 'Supplier A', price: 118500, lead_time: '8 weeks', getting: 'Supply and install.' },
  { label: 'Supplier D', price: 142000, lead_time: '4 weeks', getting: 'Faster.' },
  { label: 'Supplier B', price: 124900, lead_time: '8 weeks', getting: 'Same as A.' },
];

Deno.test('four submitted quotes: all four are columns, cheapest first, in EN and AR', () => {
  const a = { quotes, all_quotes: roster, top3: [{ label: 'Supplier A', rank: 1 }, { label: 'Supplier D', rank: 2 }, { label: 'Supplier B', rank: 3 }] };
  for (const ar of [false, true]) {
    const t = compareTable(a, ar)!;
    assertEquals(t.head.length - 1, 4, 'one column per live quote');
    const price = t.rows[0].slice(1).map((c) => Number(c.replace(/[^\d]/g, '')));
    assertEquals(price, [118500, 124900, 131000, 142000]);
  }
});

Deno.test('a held quote stays out; with no roster the model detail is used', () => {
  const held = roster.map((r) => r.label === 'Supplier C' ? { ...r, status: 'held' } : r);
  assertEquals(compareTable({ quotes, all_quotes: held }, false)!.head.length - 1, 3);
  assertEquals(compareTable({ quotes }, false)!.head.length - 1, 3);
});
