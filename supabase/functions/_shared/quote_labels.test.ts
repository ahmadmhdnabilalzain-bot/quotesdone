// ONE LETTER PER SUPPLIER PER REQUEST, GIVEN ONCE (15 Nov 2026, sales_engineer; journey A exhibits 4/6/8/9: both of the customer's
// quotation PDFs said "Supplier A" while the comparison said B and A). Every customer surface reads _shared/quote_labels.ts:
// a supplier's letter is the order its first quote reached the customer, so three quotes arriving in any order, at any price,
// read and re-read at any moment, keep the letters they were first given.
import { assertEquals } from 'jsr:@std/assert@1';
import { arrivals, customerQuoteLabels, labelQuotes, type LabelInput } from './quote_labels.ts';

// Three suppliers, three prices that do NOT follow arrival: the cheapest arrives last.
const T = (h: number) => `2026-11-15T${String(h).padStart(2, '0')}:00:00Z`;
const Q = {
  breeze: { id: 'q-breeze', supplier_id: 11, created_at: T(9), price: 41000 },   // arrives first, dearest
  arabian: { id: 'q-arabian', supplier_id: 22, created_at: T(10), price: 38000 },
  polar: { id: 'q-polar', supplier_id: 33, created_at: T(11), price: 29500 },    // arrives last, cheapest
};
const permutations = <X>(xs: X[]): X[][] => xs.length <= 1 ? [xs] : xs.flatMap((x, i) => permutations([...xs.slice(0, i), ...xs.slice(i + 1)]).map((p) => [x, ...p]));

Deno.test('three quotes: the letter is the order they arrived in, whatever order a surface reads them in', () => {
  const all = [Q.breeze, Q.arabian, Q.polar];
  for (const order of permutations(all)) {
    const l = labelQuotes(order.map(({ price: _p, ...q }) => q));
    assertEquals([l.get('q-breeze')!.en, l.get('q-arabian')!.en, l.get('q-polar')!.en], ['Supplier A', 'Supplier B', 'Supplier C'], order.map((q) => q.id).join(','));
  }
  // the old surfaces read in PRICE order: still the same letters
  const byPrice = [...all].sort((a, b) => a.price - b.price).map(({ price: _p, ...q }) => q);
  assertEquals(labelQuotes(byPrice).get('q-polar')!.letter, 'C');
});

Deno.test('a letter once given never changes: each later quote, cheaper or not, takes the next letter', () => {
  const seen: Record<string, string> = {};
  const arrived: LabelInput[] = [];
  for (const q of [Q.breeze, Q.arabian, Q.polar]) {
    const { price: _p, ...row } = q;
    arrived.push(row);
    // every surface (card, PDF, comparison) reads at this moment, in its own order
    for (const order of permutations(arrived)) {
      const l = labelQuotes(order);
      for (const r of arrived) {
        const L = l.get(r.id)!.letter;
        if (seen[r.id]) assertEquals(L, seen[r.id], `${r.id} moved after ${q.id} arrived`);
        seen[r.id] = L;
      }
    }
  }
  assertEquals(seen, { 'q-breeze': 'A', 'q-arabian': 'B', 'q-polar': 'C' });
});

Deno.test('journey A replay: two suppliers get two letters, never "Supplier A" twice', () => {
  // Arabian quoted first; Cool Breeze later and cheaper. The price rank made each PDF "A" at its own moment.
  const arabian = { id: 'q-ara', supplier_id: 1, created_at: T(12) };
  const breeze = { id: 'q-cb', supplier_id: 2, created_at: T(14) };
  const pdfArabian = labelQuotes([arabian]).get('q-ara')!.letter;               // made when Arabian's was the only quote
  const pdfBreeze = labelQuotes([breeze, arabian]).get('q-cb')!.letter;         // made after Cool Breeze, the cheapest, arrived
  const compare = labelQuotes([breeze, arabian]);                               // the comparison, cheapest first
  assertEquals([pdfArabian, pdfBreeze], ['A', 'B']);
  assertEquals([compare.get('q-ara')!.letter, compare.get('q-cb')!.letter], [pdfArabian, pdfBreeze]);
});

Deno.test('a quote held or released later never moves another supplier\'s letter', () => {
  // X was submitted first but held by the quality check for a day; Y arrived meanwhile and was shown as Supplier A.
  const x = { id: 'q-x', supplier_id: 7, created_at: T(8), status: 'submitted' };
  const y = { id: 'q-y', supplier_id: 8, created_at: T(9), status: 'submitted' };
  const beforeRelease = labelQuotes(arrivals([{ ...x, status: 'draft' }, y], [{ quote_id: 'q-x', released_at: null }]));
  assertEquals(beforeRelease.get('q-y')!.letter, 'A');
  assertEquals(beforeRelease.has('q-x'), false, 'a draft takes no letter');
  const afterRelease = labelQuotes(arrivals([x, y], [{ quote_id: 'q-x', released_at: '2026-11-16T08:00:00Z' }]));
  assertEquals([afterRelease.get('q-y')!.letter, afterRelease.get('q-x')!.letter], ['A', 'B']);
  // withdrawn quotes leave the letters (the earlier rule, quote_live.ts)
  assertEquals(labelQuotes(arrivals([{ ...x, status: 'withdrawn' }, y])).get('q-y')!.letter, 'A');
});

Deno.test('a supplier\'s second option keeps its first quote\'s letter', () => {
  const l = labelQuotes([
    { id: 'b1', supplier_id: 2, option_no: 1, created_at: T(10) },
    { id: 'a1', supplier_id: 1, option_no: 1, created_at: T(9) },
    { id: 'a2', supplier_id: 1, option_no: 2, created_at: T(15) },   // the second option arrives after B
  ]);
  assertEquals([l.get('a1')!.en, l.get('a2')!.en, l.get('b1')!.en], ['Supplier A – Option 1', 'Supplier A – Option 2', 'Supplier B']);
  assertEquals(l.get('b1')!.ar, 'المورّد B');
});

Deno.test('the one read: card, PDF and comparison get the same letters from customerQuoteLabels', async () => {
  // a fake PostgREST client: the live quotes of the request (PRICE order, as the old reads asked) and one released hold
  const rows = [
    { id: 'q-polar', supplier_id: 33, option_no: 1, created_at: T(11), status: 'submitted' },
    { id: 'q-arabian', supplier_id: 22, option_no: 1, created_at: T(10), status: 'submitted' },
    { id: 'q-breeze', supplier_id: 11, option_no: 1, created_at: T(9), status: 'submitted' },
  ];
  const calls: string[] = [];
  const chain = (table: string) => {
    const b: Record<string, unknown> = {};
    const res = table === 'quotes' ? { data: rows, error: null } : { data: [{ quote_id: 'q-breeze', released_at: T(12) }], error: null };
    for (const m of ['select', 'eq', 'not', 'limit', 'order', 'in']) b[m] = (...a: unknown[]) => { calls.push(`${table}.${m}(${a.map(String).join(',')})`); return b; };
    b.then = (ok: (v: unknown) => unknown) => Promise.resolve(res).then(ok);
    return b;
  };
  const admin = { from: (t: string) => chain(t) };
  const l = await customerQuoteLabels(admin, 'inq-1');
  // Breeze was held by the quality check until 12:00, so it reached the customer after the other two
  assertEquals([l.get('q-arabian')!.letter, l.get('q-polar')!.letter, l.get('q-breeze')!.letter], ['A', 'B', 'C']);
  assertEquals(calls.some((c) => c.startsWith('quotes.not(status,in,("draft","withdrawn"))')), true);
  // a read that fails gives no letter at all, never a guessed one
  const broken = { from: () => { throw new Error('down'); } };
  assertEquals((await customerQuoteLabels(broken, 'inq-1')).size, 0);
});
