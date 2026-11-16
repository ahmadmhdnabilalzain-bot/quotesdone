// A QUOTATION IS SAVED EVEN BEFORE THE COLUMN FOR ITS PRINTED DATE EXISTS (15 Nov 2026, review of ledger 1697, item 1). submit_quote
// wrote `quotation_date` on every insert and update, null or not; deployed before the SQL that adds the column, PostgREST refused
// every write with PGRST204 and every quotation was refused. Now the key is written only with a date, and a write (or the snapshot
// of a prior quotation) refused for that pending column is tried once more without it. ZZ DEMO rows only, no network.
//   deno test --no-lock --node-modules-dir=none --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY --allow-read=. supabase/functions/supplier_api/a_quotation_is_saved_before_its_date_column_exists.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';

Deno.env.set('SUPABASE_URL', 'http://127.0.0.1:9');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-not-a-key');
const ctx = await import('./context.ts');
const { snapshotQuote, writeQuoteRow, columnNotApplied } = await import('./lib/quote_acceptance.ts');

type Row = Record<string, unknown>;
const QID = 'aaaaaaaa-0000-4000-8000-0000000000d7';
/** A quotes table as PostgREST answers it; `hasDate` false = the SQL is not applied (no quotation_date column). */
function database(hasDate: boolean, otherError?: { code: string; message: string }) {
  const t: Record<string, Row[]> = { quotes: [{ id: QID, status: 'submitted', quote_amount: 9000, validity: '30 days' }], quote_items: [] };
  const writes: Row[] = [];
  const missing = (keys: string[]) => !hasDate && keys.includes('quotation_date');
  // deno-lint-ignore no-explicit-any
  (ctx.admin as any).from = (table: string) => {
    const f: ((r: Row) => boolean)[] = []; let op = 'select'; let patch: Row | null = null; let cols = '*';
    const run = () => {
      if (op === 'select' && cols !== '*' && missing(cols.split(','))) return { data: null, error: { code: '42703', message: 'column quotes.quotation_date does not exist' } };
      if ((op === 'insert' || op === 'update') && missing(Object.keys(patch || {}))) return { data: null, error: { code: 'PGRST204', message: "Could not find the 'quotation_date' column of 'quotes' in the schema cache" } };
      if ((op === 'insert' || op === 'update') && otherError) return { data: null, error: otherError };
      if (op === 'update') { writes.push({ ...patch }); for (const r of t[table].filter((r) => f.every((p) => p(r)))) Object.assign(r, patch); return { data: null, error: null }; }
      if (op === 'insert') { writes.push({ ...patch }); t[table].push({ id: 'new', ...patch }); return { data: { id: 'new' }, error: null }; }
      const rows = t[table].filter((r) => f.every((p) => p(r))).map((r) => (cols === '*' ? { ...r } : Object.fromEntries(cols.split(',').map((c) => [c, r[c] ?? null]))));
      return { data: table === 'quotes' ? (rows[0] ?? null) : rows, error: null };
    };
    // deno-lint-ignore no-explicit-any
    const b: any = {
      select: (c?: string) => { if (c) cols = c; return b; }, eq: (k: string, v: unknown) => { f.push((r) => String(r[k]) === String(v)); return b; },
      update: (p: Row) => { op = 'update'; patch = p; return b; }, insert: (p: Row) => { op = 'insert'; patch = p; return b; },
      single: () => Promise.resolve(run()), maybeSingle: () => Promise.resolve(run()),
      then: (res: (v: unknown) => unknown, rej?: (e: unknown) => unknown) => Promise.resolve(run()).then(res, rej),
    };
    return b;
  };
  return { t, writes };
}
const insertQuote = (det: Row) => writeQuoteRow(det, (d) => ctx.admin.from('quotes').insert({ ...d, status: 'draft' }).select('id').single());

Deno.test('before the SQL: a quotation with a printed date is saved without it, once retried; one without a date is saved at once', async () => {
  const db = database(false);
  const r = await insertQuote({ inquiry_id: 'i', validity: '30 days', quotation_date: '2026-11-12' });
  assertEquals(r.error, null, 'the quotation is saved, not refused with PGRST204');
  assertEquals(db.writes.length, 1);
  assert(!('quotation_date' in db.writes[0]), 'saved without the column it does not have');
  const db2 = database(false);
  assertEquals((await insertQuote({ inquiry_id: 'i', validity: '30 days' })).error, null);
  assertEquals(db2.writes.length, 1);
});

Deno.test('after the SQL: the printed date is saved with the quotation, in one write', async () => {
  const db = database(true);
  const det: Row = { validity: '30 days', quotation_date: '2026-11-12' };
  assertEquals((await writeQuoteRow(det, (d) => ctx.admin.from('quotes').update(d).eq('id', QID))).error, null);
  assertEquals(db.t.quotes[0].quotation_date, '2026-11-12');
  assertEquals(db.writes.length, 1);
});

Deno.test('any other refusal is answered as it came, never retried or hidden', async () => {
  const db = database(true, { code: '57014', message: 'canceling statement due to statement timeout' });
  const det: Row = { validity: '30 days', quotation_date: '2026-11-12' };
  const r = await writeQuoteRow(det, (d) => ctx.admin.from('quotes').update(d).eq('id', QID));
  assertEquals(r.error?.code, '57014');
  assertEquals(det.quotation_date, '2026-11-12', 'the date is not dropped for a refusal that is not about its column');
  assertEquals(db.writes.length, 0);
  assert(columnNotApplied({ code: 'PGRST204' }) && columnNotApplied({ code: '42703' }) && !columnNotApplied({ code: '23505' }) && !columnNotApplied(null));
});

Deno.test('before the SQL: the snapshot of a prior quotation is taken without the pending column, and says it left it out', async () => {
  database(false);
  const snap = await snapshotQuote(QID, 'quote_amount,validity,quotation_date,status');
  assert(snap, 'a re-sent quotation is not refused with quote_not_saved');
  assertEquals(snap!.dropped, ['quotation_date']);
  assertEquals(snap!.row, { quote_amount: 9000, validity: '30 days', status: 'submitted' });
  database(true);
  const after = await snapshotQuote(QID, 'quote_amount,validity,quotation_date,status');
  assertEquals(after!.dropped, undefined);
  assertEquals(after!.row.quotation_date, null);
});

Deno.test('submit_quote writes the date key only with a date, and every quotes write and snapshot goes through the fallback', () => {
  const src = Deno.readTextFileSync(new URL('./actions/quotes.ts', import.meta.url));
  const s = src.slice(src.indexOf("if (action === 'submit_quote')"));
  assert(!/quotation_date: quotationDateOf\(/.test(s), 'the key is never written as null');
  assert(s.includes('...(qDate ? { quotation_date: qDate } : {})'));
  assert(s.includes("await writeQuoteRow(det, (d) => admin.from('quotes').update(d).eq('id', prior.id))"));
  assert(s.includes("await writeQuoteRow(det, (d) => admin.from('quotes').insert({ ...d, status: 'draft' }).select('id').single())"));
  assert(s.includes('for (const c of snap?.dropped || []) delete (det as Record<string, unknown>)[c];'));
  assert(!s.includes("admin.from('quotes').update(det)") && !s.includes("admin.from('quotes').insert({ ...det"), 'no write around the fallback');
});
