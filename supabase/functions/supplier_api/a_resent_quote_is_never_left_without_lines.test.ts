// A RE-SENT QUOTATION IS NEVER LEFT WITHOUT LINES (15 Nov 2026, third review of the certificate branch, item 4). submit_quote over a
// prior quotation writes the new header, then the new lines (writeQuoteLines: delete + insert, the pair retried on a blip). When
// the retry's delete lands and its insert fails again, a quotation the customer already sees had its new amount and terms and NO
// lines, while the supplier read "Nothing is lost". Now every prior quotation is snapshotted first and put back (restoreQuote).
// The steps run here in submit_quote's order on one stateful in-memory table set; ZZ DEMO rows only, no network.
//   deno test --no-lock --node-modules-dir=none --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY --allow-read=. supabase/functions/supplier_api/a_resent_quote_is_never_left_without_lines.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';

Deno.env.set('SUPABASE_URL', 'http://127.0.0.1:9');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-not-a-key');
const ctx = await import('./context.ts');
const { restoreQuote, snapshotQuote, writeQuoteLines } = await import('./lib/quote_acceptance.ts');

type Row = Record<string, unknown>;
const QID = 'aaaaaaaa-0000-4000-8000-0000000000f1';
function database(failInsert: (n: number) => boolean) {
  const t: Record<string, Row[]> = {
    quotes: [{ id: QID, status: 'submitted', submittable: true, quote_amount: 9000, validity: '30 days' }],
    quote_items: [{ id: 501, quote_id: QID, line_no: 1, description: 'ZZ DEMO old line', amount: 9000 }],
  };
  let inserts = 0;
  // deno-lint-ignore no-explicit-any
  (ctx.admin as any).from = (table: string) => {
    const f: ((r: Row) => boolean)[] = []; let op = 'select'; let patch: unknown = null; let one = false; let cols = '*';
    const run = () => {
      const hit = () => t[table].filter((r) => f.every((p) => p(r)));
      if (op === 'update') { for (const r of hit()) Object.assign(r, patch); return { data: null, error: null }; }
      if (op === 'delete') { t[table] = t[table].filter((r) => !f.every((p) => p(r))); return { data: null, error: null }; }
      if (op === 'insert') {
        if (table === 'quote_items' && failInsert(++inserts)) return { data: null, error: { code: '57014', message: 'canceling statement due to statement timeout' } };
        t[table].push(...structuredClone(([] as Row[]).concat(patch as Row[]))); return { data: null, error: null };
      }
      const rows = hit().map((r) => (cols === '*' ? structuredClone(r) : Object.fromEntries(cols.split(',').map((c) => [c, r[c]]))));
      return { data: one ? (rows[0] ?? null) : rows, error: null };
    };
    // deno-lint-ignore no-explicit-any
    const b: any = {
      select: (c?: string) => { if (c) cols = c; return b; }, eq: (k: string, v: unknown) => { f.push((r) => String(r[k]) === String(v)); return b; },
      update: (p: Row) => { op = 'update'; patch = p; return b; }, delete: () => { op = 'delete'; return b; }, insert: (p: Row[]) => { op = 'insert'; patch = p; return b; },
      maybeSingle: () => { one = true; return Promise.resolve(run()); },
      then: (res: (v: unknown) => unknown, rej?: (e: unknown) => unknown) => Promise.resolve(run()).then(res, rej),
    };
    return b;
  };
  return t;
}
const NEW_LINES = [{ quote_id: QID, line_no: 1, description: 'ZZ DEMO new line 1', amount: 6000 }, { quote_id: QID, line_no: 2, description: 'ZZ DEMO new line 2', amount: 6000 }];
const DET = { quote_amount: 12000, validity: '15 days' };

Deno.test('a re-sent live quotation whose line write fails twice is put back as it stood: its header and its own lines', async () => {
  const t = database((n) => n <= 2);   // both tries of the new lines fail; the lock has gone by the time it is put back
  const snap = await snapshotQuote(QID, [...Object.keys(DET), 'status', 'submittable'].join(','));   // before anything is written
  assert(snap);
  await ctx.admin.from('quotes').update(DET).eq('id', QID);                                           // the new header
  const w = await writeQuoteLines(QID, NEW_LINES, () => Promise.resolve());                              // delete lands, insert fails, twice
  assertEquals(w.ok, false);
  assertEquals(t.quote_items.length, 0, 'this is what the customer saw before: the new header over no lines');
  assert(await restoreQuote(QID, snap!));
  assertEquals(t.quotes[0], { id: QID, status: 'submitted', submittable: true, quote_amount: 9000, validity: '30 days' });
  assertEquals(t.quote_items, [{ id: 501, quote_id: QID, line_no: 1, description: 'ZZ DEMO old line', amount: 9000 }], 'its own lines, with their own ids');
});

Deno.test('a blip that clears on the retry writes the new lines once, and nothing is put back', async () => {
  const t = database((n) => n === 1);
  const w = await writeQuoteLines(QID, NEW_LINES, () => Promise.resolve());
  assertEquals(w.ok, true);
  assertEquals(t.quote_items.map((r) => r.description), ['ZZ DEMO new line 1', 'ZZ DEMO new line 2']);
});

Deno.test('submit_quote snapshots every prior quotation and puts it back before it answers quote_not_saved', () => {
  const src = Deno.readTextFileSync(new URL('./actions/quotes.ts', import.meta.url));
  const s = src.slice(src.indexOf("if (action === 'submit_quote')"));
  assert(s.includes('if (prior) {\n          snap = await snapshotQuote(String(prior.id), snapCols);'), 'every prior, not only a dry run');
  assert(!s.includes('if (dryRun && prior) {'), 'the dry-run-only snapshot is gone');
  const snapAt = s.indexOf('snap = await snapshotQuote('), writeAt = s.indexOf("await writeQuoteRow(det, (d) => admin.from('quotes').update(d).eq('id', prior.id))");
  assert(snapAt > 0 && writeAt > snapAt, 'the snapshot is taken before the header is written');
  const restoreAt = s.indexOf('const restored = dryRun || snap ? await restore() : null;'), answerAt = s.indexOf("return J({ ok: false, error: 'quote_not_saved', ...QUOTE_NOT_SAVED, quote_id: qid");
  assert(restoreAt > 0 && answerAt > restoreAt, 'put back before he is answered');
  assert(s.includes('if (snap) return await restoreQuote(qid, snap);'));
});
