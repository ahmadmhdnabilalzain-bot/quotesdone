// A QUOTATION READS EVERY MONEY CASE AS THE CORPUS SAYS (sales_engineer, 12 Nov 2026; review rounds 1-3 of the quoting fix).
// money.corpus.json holds every line, totals text and document the reviewer used, with its exact expected reading, and the
// audit's 8 fixtures are read here too. Enforced on every row:
//   - the reading is the pinned one;
//   - where the reviewer stated the intended total ("want"), the reader gives that total or holds the price (null), never
//     another figure;
//   - THE READER'S PRINCIPLE: a price is never smaller than main's unless the file states the figure used (the row's note).
// A change to the reader is done only when the whole corpus passes.
//   deno test --node-modules-dir=none --allow-read --allow-env supabase/functions/quote_extract/a_quotation_reads_every_money_case_as_the_corpus_says.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { linesFromText, quoteFromExtracted, totalsFromText } from './quote_from_document.ts';
import { readDocument } from '../_shared/doc_read/index.ts';

type Reading = Record<string, number | boolean | null>;
type Row = { src: string; name: string; kind: 'doc' | 'line' | 'totals'; text: string; want: number | null; expect: Reading | null; main: Reading | null; note?: string };
const { rows } = JSON.parse(await Deno.readTextFile(new URL('./money.corpus.json', import.meta.url))) as { rows: Row[] };

const doc = (text: string): Reading => { const p = quoteFromExtracted({ ok: true, kind: 'pdf', text, tables: [], children: [] } as never, []); return { amount: p.amount ?? null, ex: p.price_ex_vat ?? null, vat: p.vat_amount ?? null, held: !!p.review_reason }; };
const line = (s: string): Reading | null => { const l = linesFromText(s)[0]; return l ? { amount: l.amount ?? null, qty: l.quantity ?? null, rate: l.unit_price ?? null, held: !!l.held || !!l.mismatch } : null; };
const tot = (s: string): Reading => { const t = totalsFromText(s); return { subtotal: t.subtotal, vat: t.vat, total: t.total }; };
const read = (r: Row) => (r.kind === 'doc' ? doc(r.text) : r.kind === 'line' ? line(r.text) : tot(r.text));
const price = (x: Reading | null) => (x ? (x.amount ?? x.total ?? null) as number | null : null);

Deno.test(`the money corpus is whole: ${rows.length} rows`, () => { assert(rows.length >= 150); });

Deno.test('every money row gives its pinned reading', () => {
  const bad = rows.filter((r) => JSON.stringify(read(r)) !== JSON.stringify(r.expect)).map((r) => `${r.src} ${JSON.stringify(r.name)}: ${JSON.stringify(read(r))}, pinned ${JSON.stringify(r.expect)}`);
  assertEquals(bad, []);
});

Deno.test('where the intended total is known, the reader gives it or holds the price, never another figure', () => {
  const bad = rows.filter((r) => r.want != null && price(read(r)) != null && price(read(r)) !== r.want).map((r) => `${JSON.stringify(r.name)}: ${price(read(r))}, intended ${r.want}`);
  assertEquals(bad, []);
});

Deno.test('the principle: never a price smaller than main\'s unless the file states the figure used', () => {
  const bad = rows.filter((r) => r.kind !== 'totals' && r.want == null && !r.note).filter((r) => { const b = price(read(r)), m = price(r.main); return b != null && m != null && b < m - 0.005; })
    .map((r) => `${JSON.stringify(r.name)}: ${price(read(r))} < main ${price(r.main)}`);
  assertEquals(bad, []);
});

Deno.test('the audit\'s 8 fixtures: the price before VAT is main\'s, to the fil', async () => {
  const MAIN: Record<string, number> = { villa_hvac_Q1: 94820, villa_hvac_Q2: 71966, villa_hvac_Q3: 107099, villa_hvac_Q5: 69188, wall_panels_Q1: 9554, wall_panels_Q2: 7456, wall_panels_Q3: 12028, wall_panels_Q5: 10128 };
  for (const [n, want] of Object.entries(MAIN)) {
    const r = await readDocument(await Deno.readFile(new URL(`fixtures/audit_2026_11_12_${n}.pdf`, import.meta.url)), n + '.pdf', 'application/pdf');
    const p = quoteFromExtracted(r as never, []);
    assertEquals(p.price_ex_vat ?? p.amount, want, n);
  }
});
