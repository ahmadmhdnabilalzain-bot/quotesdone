// ONE LETTER PER SUPPLIER PER REQUEST, GIVEN ONCE AND KEPT (15 Nov 2026, sales_engineer). Journey A: both of the customer's
// quotation PDFs said "Supplier A" while the comparison said B and A. A letter worked out again from ARRIVAL order still moved
// (review REVIEW_plain item 1: a revised upload after a hold, a withdrawal, a re-held live quote). The letter is now STORED the
// first time a supplier is shown (public.customer_supplier_letter via fn_customer_supplier_letters) and read afterwards.
// The fake database below holds the same rule as the SQL function (a supplier is lettered only when it has a live quote or a
// question on the request and is not sanctioned; the next letter is the next free place; a row is never changed); the SQL itself
// is proved on a local database by scripts/sql/a_suppliers_letter_is_kept_from_the_first_time_the_customer_sees_it_probe.sql.
import { assertEquals } from 'jsr:@std/assert@1';
import { arrivalOrder, labelQuotes, letter, recordShown, storedLetterOf, storedLetters, type LabelInput } from './quote_labels.ts';

const T = (h: number) => `2026-11-15T${String(h).padStart(2, '0')}:00:00Z`;
type Quote = LabelInput & { inquiry_id: string; status: string; price?: number };

/** The tables the function reads and writes, and a client with its .rpc and .from as supabase-js gives them. */
function fakeDb() {
  const db = { quotes: [] as Quote[], questions: [] as Array<{ inquiry_id: string; supplier_id: number }>, banned: new Set<string>(),
    letters: [] as Array<{ inquiry_id: string; supplier_id: string; letter: string; seq: number; shown_by: string }>, down: false, rpcCalls: 0 };
  const live = (s: string) => s !== 'draft' && s !== 'withdrawn';
  const admin = {
    rpc: (fn: string, a: { p_inquiry_ids: string[]; p_shown: Array<{ inquiry_id: string; supplier_id: string }>; p_shown_by: string }) => {
      db.rpcCalls++;
      if (db.down || fn !== 'fn_customer_supplier_letters') return Promise.resolve({ data: null, error: { message: 'down' } });
      for (const { inquiry_id: i, supplier_id: s } of a.p_shown) {
        if (!a.p_inquiry_ids.includes(i) || db.letters.some((l) => l.inquiry_id === i && l.supplier_id === String(s))) continue;
        if (db.banned.has(String(s))) continue;
        const seen = db.quotes.some((q) => q.inquiry_id === i && String(q.supplier_id) === String(s) && live(q.status)) || db.questions.some((c) => c.inquiry_id === i && String(c.supplier_id) === String(s));
        if (!seen) continue;
        const seq = db.letters.filter((l) => l.inquiry_id === i).length;
        db.letters.push({ inquiry_id: i, supplier_id: String(s), letter: letter(seq), seq, shown_by: a.p_shown_by });
      }
      return Promise.resolve({ data: db.letters.filter((l) => a.p_inquiry_ids.includes(l.inquiry_id)).map((l) => ({ ...l, supplier_id: Number(l.supplier_id) })), error: null });
    },
    from: (t: string) => {
      const b: Record<string, unknown> = {}; let ids: string[] = [];
      b.select = () => b; b.in = (_c: string, v: string[]) => { ids = v; return b; };
      b.then = (ok: (v: unknown) => unknown) => Promise.resolve(db.down || t !== 'customer_supplier_letter' ? { data: null, error: { message: 'down' } } : { data: db.letters.filter((l) => ids.includes(l.inquiry_id)), error: null }).then(ok);
      return b;
    },
  };
  return { db, admin };
}

/** The portal card (customer_api my_inquiries): it shows the live quotes that are not held and not sanctioned, records them,
 *  and labels them from the stored letters. Returns quote id -> label ("Supplier" when no letter). */
async function card(f: ReturnType<typeof fakeDb>, inq: string, held: Set<string> = new Set()) {
  const live = f.db.quotes.filter((q) => q.inquiry_id === inq && q.status !== 'draft' && q.status !== 'withdrawn');
  const shown = live.filter((q) => !held.has(q.id) && !f.db.banned.has(String(q.supplier_id)));
  const letters = await recordShown(f.admin, { [inq]: shown }, 'quote_card');
  const labels = labelQuotes(shown, letters?.get(inq) ?? new Map(), live);
  return Object.fromEntries(shown.map((q) => [q.id, labels.get(q.id)?.en ?? 'Supplier']));
}

Deno.test('three quotes: the letter is the order they were first shown in, never the price', async () => {
  const f = fakeDb();
  f.db.quotes.push({ id: 'q-breeze', inquiry_id: 'i1', supplier_id: 11, created_at: T(9), status: 'submitted', price: 41000 });
  assertEquals(await card(f, 'i1'), { 'q-breeze': 'Supplier A' });
  f.db.quotes.push({ id: 'q-arabian', inquiry_id: 'i1', supplier_id: 22, created_at: T(10), status: 'submitted', price: 38000 });
  assertEquals(await card(f, 'i1'), { 'q-breeze': 'Supplier A', 'q-arabian': 'Supplier B' });
  f.db.quotes.push({ id: 'q-polar', inquiry_id: 'i1', supplier_id: 33, created_at: T(11), status: 'submitted', price: 29500 });
  // the old surfaces read in PRICE order: the letters do not follow
  f.db.quotes.sort((a, b) => (a.price ?? 0) - (b.price ?? 0));
  assertEquals(await card(f, 'i1'), { 'q-polar': 'Supplier C', 'q-arabian': 'Supplier B', 'q-breeze': 'Supplier A' });
});

Deno.test('several suppliers shown for the first time in one view are lettered in the order their quotes arrived', async () => {
  const f = fakeDb();
  f.db.quotes.push({ id: 'q3', inquiry_id: 'i1', supplier_id: 3, created_at: T(11), status: 'submitted' },
    { id: 'q1', inquiry_id: 'i1', supplier_id: 1, created_at: T(9), status: 'submitted' }, { id: 'q2', inquiry_id: 'i1', supplier_id: 2, created_at: T(10), status: 'submitted' });
  assertEquals(arrivalOrder(f.db.quotes), ['1', '2', '3']);
  assertEquals(await card(f, 'i1'), { q3: 'Supplier C', q1: 'Supplier A', q2: 'Supplier B' });
});

Deno.test('review case (a): a revised upload after a hold never takes the letter of a supplier shown meanwhile', async () => {
  // X is held at 08:00 (a draft while held); Y goes live at 09:00 and is shown as A. X uploads a revised quote: the hold is
  // superseded (no released_at) and X is live again with its OLD created_at, 08:00, earlier than Y's.
  const f = fakeDb();
  f.db.quotes.push({ id: 'q-x', inquiry_id: 'i1', supplier_id: 7, created_at: T(8), status: 'draft' }, { id: 'q-y', inquiry_id: 'i1', supplier_id: 8, created_at: T(9), status: 'submitted' });
  assertEquals(await card(f, 'i1'), { 'q-y': 'Supplier A' });
  f.db.quotes[0].status = 'submitted';
  assertEquals(await card(f, 'i1'), { 'q-x': 'Supplier B', 'q-y': 'Supplier A' });
});

Deno.test('review case (b): a withdrawal never moves the letter of a supplier still quoting', async () => {
  const f = fakeDb();
  f.db.quotes.push({ id: 'q-x', inquiry_id: 'i1', supplier_id: 7, created_at: T(8), status: 'submitted' }, { id: 'q-y', inquiry_id: 'i1', supplier_id: 8, created_at: T(9), status: 'submitted' });
  assertEquals(await card(f, 'i1'), { 'q-x': 'Supplier A', 'q-y': 'Supplier B' });
  f.db.quotes[0].status = 'withdrawn';
  assertEquals(await card(f, 'i1'), { 'q-y': 'Supplier B' });
  // X quotes again later: it is still A, the letter the customer knew it by
  f.db.quotes.push({ id: 'q-x2', inquiry_id: 'i1', supplier_id: 7, created_at: T(12), status: 'submitted' });
  assertEquals(await card(f, 'i1'), { 'q-y': 'Supplier B', 'q-x2': 'Supplier A' });
});

Deno.test('review case (c): a live quote re-held and released later keeps its letter, and so does everyone else', async () => {
  const f = fakeDb();
  f.db.quotes.push({ id: 'q-x', inquiry_id: 'i1', supplier_id: 7, created_at: T(8), status: 'submitted' }, { id: 'q-y', inquiry_id: 'i1', supplier_id: 8, created_at: T(9), status: 'submitted' });
  assertEquals(await card(f, 'i1'), { 'q-x': 'Supplier A', 'q-y': 'Supplier B' });
  f.db.quotes[0].status = 'draft';   // re-held on resubmission (workflow.ts, quotes.ts): back to draft
  assertEquals(await card(f, 'i1'), { 'q-y': 'Supplier B' });
  f.db.quotes.push({ id: 'q-z', inquiry_id: 'i1', supplier_id: 9, created_at: T(10), status: 'submitted' });
  assertEquals(await card(f, 'i1'), { 'q-y': 'Supplier B', 'q-z': 'Supplier C' });
  f.db.quotes[0].status = 'submitted';   // released
  assertEquals(await card(f, 'i1'), { 'q-x': 'Supplier A', 'q-y': 'Supplier B', 'q-z': 'Supplier C' });
});

Deno.test('the gap: a sanctioned or held quote never gets a letter, so the letters the customer sees run A, B with no C missing', async () => {
  const f = fakeDb();
  f.db.banned.add('5');
  f.db.quotes.push({ id: 'q-ban', inquiry_id: 'i1', supplier_id: 5, created_at: T(7), status: 'submitted' },
    { id: 'q-held', inquiry_id: 'i1', supplier_id: 6, created_at: T(8), status: 'submitted' },
    { id: 'q-x', inquiry_id: 'i1', supplier_id: 7, created_at: T(9), status: 'submitted' }, { id: 'q-y', inquiry_id: 'i1', supplier_id: 8, created_at: T(10), status: 'submitted' });
  // q-held is held for missing details (reveal_guard heldQuoteIds): the card leaves it out
  assertEquals(await card(f, 'i1', new Set(['q-held'])), { 'q-x': 'Supplier A', 'q-y': 'Supplier B' });
  // even a caller that passes the sanctioned supplier gets no letter for it (the function refuses)
  const r = await recordShown(f.admin, { i1: f.db.quotes }, 'comparison');
  assertEquals(r?.get('i1')?.has('5'), false);
  assertEquals([...(r?.get('i1') ?? new Map())].sort(), [['6', 'C'], ['7', 'A'], ['8', 'B']]);
  // a never-shown supplier (no live quote, no question) is refused too
  assertEquals((await recordShown(f.admin, { i1: [{ id: 'q-none', supplier_id: 99, created_at: T(6) }] }, 'quote_card'))?.get('i1')?.has('99'), false);
});

Deno.test('a supplier the customer first met by its question keeps that letter when it quotes', async () => {
  const f = fakeDb();
  f.db.questions.push({ inquiry_id: 'i1', supplier_id: 33 });
  const thread = await recordShown(f.admin, { i1: [{ id: '501', supplier_id: 33, created_at: T(8) }] }, 'question');
  assertEquals(thread?.get('i1')?.get('33'), 'A');
  f.db.quotes.push({ id: 'q-breeze', inquiry_id: 'i1', supplier_id: 11, created_at: T(9), status: 'submitted' }, { id: 'q-polar', inquiry_id: 'i1', supplier_id: 33, created_at: T(11), status: 'submitted' });
  assertEquals(await card(f, 'i1'), { 'q-breeze': 'Supplier B', 'q-polar': 'Supplier A' });
  assertEquals(f.db.letters.find((l) => l.supplier_id === '33')?.shown_by, 'question');
});

Deno.test('a supplier\'s second option keeps its first quote\'s letter, and a held sibling still makes them options', async () => {
  const f = fakeDb();
  f.db.quotes.push({ id: 'a1', inquiry_id: 'i1', supplier_id: 1, option_no: 1, created_at: T(9), status: 'submitted' }, { id: 'b1', inquiry_id: 'i1', supplier_id: 2, option_no: 1, created_at: T(10), status: 'submitted' },
    { id: 'a2', inquiry_id: 'i1', supplier_id: 1, option_no: 2, created_at: T(15), status: 'submitted' });
  assertEquals(await card(f, 'i1'), { a1: 'Supplier A – Option 1', b1: 'Supplier B', a2: 'Supplier A – Option 2' });
  assertEquals(await card(f, 'i1', new Set(['a2'])), { a1: 'Supplier A – Option 1', b1: 'Supplier B' });
  const l = labelQuotes(f.db.quotes, new Map([['1', 'A'], ['2', 'B']]));
  assertEquals(l.get('a2')!.ar, 'المورّد A – الخيار 2');
});

Deno.test('a failed read never guesses: the card says "Supplier", the PDF and the invoice are told to refuse', async () => {
  const f = fakeDb();
  f.db.quotes.push({ id: 'q-x', inquiry_id: 'i1', supplier_id: 7, created_at: T(8), status: 'submitted' }, { id: 'q-y', inquiry_id: 'i1', supplier_id: 8, created_at: T(9), status: 'submitted' });
  f.db.down = true;
  assertEquals(await card(f, 'i1'), { 'q-x': 'Supplier', 'q-y': 'Supplier' });
  assertEquals(await storedLetters(f.admin, ['i1']), null);
  assertEquals(await storedLetterOf(f.admin, { inquiry_id: 'i1', supplier_id: 7 }), { ok: false });
  f.db.down = false;
  // read fine, supplier never shown: no letter (the document prints "Supplier"), not "A"
  assertEquals(await storedLetterOf(f.admin, { inquiry_id: 'i1', supplier_id: 7 }), { ok: true, letter: null });
  await card(f, 'i1');
  assertEquals(await storedLetterOf(f.admin, { inquiry_id: 'i1', supplier_id: 8 }), { ok: true, letter: 'B' });
  // the PDF, the invoice and the chat only read: they never write a letter
  const before = f.db.rpcCalls; await storedLetters(f.admin, ['i1']); assertEquals(f.db.rpcCalls, before);
});

Deno.test('many requests in one call (the portal list): each request lettered on its own', async () => {
  const f = fakeDb();
  f.db.quotes.push({ id: 'q1', inquiry_id: 'i1', supplier_id: 33, created_at: T(9), status: 'submitted' }, { id: 'q2', inquiry_id: 'i2', supplier_id: 44, created_at: T(9), status: 'submitted' },
    { id: 'q3', inquiry_id: 'i2', supplier_id: 33, created_at: T(10), status: 'submitted' });
  const r = await recordShown(f.admin, new Map([['i1', [f.db.quotes[0]]], ['i2', [f.db.quotes[2], f.db.quotes[1]]]]), 'quote_card');
  assertEquals([r?.get('i1')?.get('33'), r?.get('i2')?.get('44'), r?.get('i2')?.get('33')], ['A', 'A', 'B']);
  assertEquals(f.db.rpcCalls, 1);
});
