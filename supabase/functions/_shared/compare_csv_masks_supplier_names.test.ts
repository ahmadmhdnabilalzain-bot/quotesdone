// compare_csv_masks_supplier_names.test.ts — the comparison CSV masks the same supplier names as the comparison PDF
// (13 Nov 2026, anonymity audit REPORT_C L7: "balance on completion - Desert Brush team" crossed in the CSV after the PDF
// hid it). RAW text in, so a lost mask is seen (mutant M5 of the review survived when the text was already anonymised).
// deno test --no-lock supabase/functions/_shared/compare_csv_masks_supplier_names.test.ts
import { assert } from 'jsr:@std/assert@1';
import { compareDocument, compareTable, maskContacts, toCsv } from './quote_documents.ts';

Deno.test('the CSV hides every quoting supplier\'s name and contacts, as the PDF does', async () => {
  const names = ['ZZ DEMO Desert Brush Painting LLC', 'rashid@desertbrush.example.invalid', '+971 50 123 4567'];
  const q = { label: 'Supplier A', quote_id: 'q1', price: 24600, lead_time: '10 days', validity: '30 days', warranty: '5 years', itemised: true,
    payment_terms: 'balance on completion - ZZ DEMO Desert Brush Painting LLC, call +971 50 123 4567', exclusions: 'Scaffolding by ZZ DEMO Desert Brush Painting LLC',
    getting: 'Interior painting by ZZ DEMO Desert Brush Painting LLC', includes: ['Paint by ZZ DEMO Desert Brush Painting LLC'], excludes: ['rashid@desertbrush.example.invalid'] };
  const a = { quotes: [q], top3: [], all_quotes: [{ label: 'Supplier A', quote_id: 'q1' }] };
  const t = compareTable(a, false, {}, names)!;
  const csv = toCsv(t.head, t.rows);
  for (const gone of ['Desert Brush', 'desertbrush', '4567']) assert(!csv.includes(gone), csv);
  // REPORT_C L1's own string: the name without its trade word, which only the names given can catch (mutant M5).
  const q2 = { ...q, payment_terms: 'balance on completion - Desert Brush team', exclusions: 'Desert Brush warranty 2 years', getting: 'Two coats', includes: [], excludes: [] };
  const t2 = compareTable({ quotes: [q2], top3: [], all_quotes: [{ label: 'Supplier A', quote_id: 'q1' }] }, false, {}, names)!;
  const csv2 = toCsv(t2.head, t2.rows);
  assert(!csv2.includes('Desert Brush'), csv2);
  // A lead whose registered name has no legal form ("ZZ DEMO Desert Brush"): only the names given can catch it.
  const bare = ['ZZ DEMO Desert Brush'];
  const q3 = { ...q, payment_terms: 'balance to ZZ DEMO Desert Brush on completion', getting: 'Interior painting by ZZ DEMO Desert Brush', includes: ['Paint by ZZ DEMO Desert Brush'], excludes: [] };
  const a3 = { quotes: [q3], top3: [], all_quotes: [{ label: 'Supplier A', quote_id: 'q1' }] };
  const ar3 = compareTable(a3, true, {}, bare)!;
  assert(!ar3.untranslated.join(' ').includes('Desert Brush'), ar3.untranslated.join(' | '));
  const doc3 = compareDocument({ analysis: a3, inquiry: { id: 'i1', rfq_no: 990457, category: 'painting', summary: 'Painting', emirate: 'Dubai' } as never, lang: 'en', maskNames: bare });
  assert(!JSON.stringify(doc3.body).includes('Desert Brush'), 'compare PDF, bare name');
  // The Arabic CSV sends its untranslated cells to the Arabic writer: they are masked BEFORE they leave (mutant M5).
  const ar = compareTable(a, true, {}, names)!;
  assert(!ar.untranslated.join(' ').includes('Desert Brush'), ar.untranslated.join(' | '));
  // The comparison PDF's "What you get" row is masked too (mutant N2).
  const doc = compareDocument({ analysis: a, inquiry: { id: 'i1', rfq_no: 990457, category: 'painting', summary: 'Painting', emirate: 'Dubai' } as never, lang: 'en', maskNames: names });
  assert(!JSON.stringify(doc.body).includes('Desert Brush'), 'compare PDF');
  // and compare_csv passes the PDF's names (customer_api/actions/reports.ts)
  const src = await Deno.readTextFile(new URL('../customer_api/actions/reports.ts', import.meta.url));
  assert(/compareTable\(analysis, lang === 'ar', \{\}, maskNames\)/.test(src) && /compareMaskNames\(iid\)/.test(src), 'compare_csv must mask with compareMaskNames');
});
Deno.test('maskContacts matches a known name BEFORE the place rule: "Al Quoz Trading" goes whole, never "Dubai Trading"', () => {
  const out = maskContacts('Supplied by Al Quoz Trading, delivered from Al Quoz Trading warehouse', ['ZZ DEMO Al Quoz Trading LLC'], 'en');
  assert(!/Quoz|Dubai Trading/.test(out), out);
});
