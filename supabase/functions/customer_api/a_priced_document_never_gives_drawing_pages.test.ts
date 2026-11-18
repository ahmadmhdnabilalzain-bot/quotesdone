// A PRICED DOCUMENT NEVER GIVES DRAWING PAGES TO A REQUEST, WHATEVER THE CLIENT SENDS (18 Nov 2026, sales_engineer; re-review of
// c1a934280, item 2). analyze_drawing may have redacted and recorded pages of a document it then judged priced (a quotation or
// a priced BOQ only the model recognised); the runs are the customer's own, so a modified client could name them at
// create_inquiry. The server records its verdict on the stored original (lib/drawings.recordPricedVerdict) and create_inquiry
// refuses the pages (drawingPagesRefused). Offline: the database is a stub that answers the queries it is asked.
//   deno test --no-lock --node-modules-dir=none --allow-read=. --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY supabase/functions/customer_api/a_priced_document_never_gives_drawing_pages.test.ts
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
Deno.env.set('SUPABASE_URL', Deno.env.get('SUPABASE_URL') || 'http://127.0.0.1:1');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || 'test');
const { admin } = await import('./context.ts');
const { PAGES_WITHHELD_MESSAGE, PRICED_PAGES_WITHHELD_MESSAGE, PRICED_VERDICT, PRICED_VERDICT_UNREAD_MESSAGE, drawingPagesRefused, pricedVerdictOf, recordPricedVerdict, resolveRedactedPaths, sourcesJudgedPriced } = await import('./lib/drawings.ts');

const CUST = 'c0000000-0000-4000-8000-00000000000c';
const QUOTE = `drawings/${CUST}/1_ZZ DEMO quotation.pdf`, DRAWING = `drawings/${CUST}/2_ZZ DEMO drawing.pdf`;
type Row = Record<string, unknown>;
/** drawing_redaction_runs as the stub holds it; each query is filtered as PostgREST would filter it. `failInsert`: every insert
 *  answers an error (a lost verdict write); `fail`: every read answers an error. Writes, removals and findings are recorded. */
function stubRuns(rows: Row[], fail = false, o: { failInsert?: boolean } = {}) {
  const asked: string[] = [], inserted: Row[] = [], updated: { set: Row; ids: unknown[] }[] = [], removed: string[][] = [], findings: string[] = [];
  // deno-lint-ignore no-explicit-any
  const a = admin as any;
  a.from = (table: string) => {
    assertEquals(table, 'drawing_redaction_runs');
    let out = [...rows]; let set: Row | null = null; let ids: unknown[] = [];
    const q: Record<string, unknown> = {
      select: () => q, order: () => q, limit: () => q, or: () => q,
      insert: (row: Row) => { if (!o.failInsert) { rows.push(row); inserted.push(row); } return { then: (ok: (x: unknown) => unknown) => ok({ error: o.failInsert ? { message: 'write lost' } : null }) }; },
      update: (row: Row) => { set = row; return q; },
      eq: (k: string, v: unknown) => { asked.push(`${k}=${v}`); out = out.filter((r) => k === 'verify_detail->>reason' ? (r.verify_detail as Row | undefined)?.reason === v : r[k] === v); return q; },
      neq: (k: string, v: unknown) => { out = out.filter((r) => r[k] !== v); return q; },
      in: (k: string, vs: unknown[]) => { asked.push(`${k} in ${vs.length}`); if (k === 'id') ids = vs; out = out.filter((r) => vs.includes(r[k])); return q; },
      then: (ok: (x: unknown) => unknown) => {
        if (set) { for (const r of out) Object.assign(r, set); updated.push({ set, ids }); return ok({ error: null }); }
        return ok(fail ? { data: null, error: { message: 'down' } } : { data: out, error: null });
      },
    };
    return q;
  };
  a.storage = { from: () => ({ remove: async (paths: string[]) => { removed.push(paths); return { error: null }; } }) };
  a.rpc = async (_fn: string, args: Row) => { findings.push(String(args.p_issue_key)); return { error: null }; };
  return Object.assign(asked, { inserted, updated, removed, findings });
}
const verdict = (source: string): Row => ({ id: 'v1', customer_id: CUST, source_path: source, status: 'held', output_paths: [], verify_detail: { reason: PRICED_VERDICT, kind: 'quotation' } });
const run = (id: string, source: string, paths: string[]): Row => ({ id, customer_id: CUST, caller_ref: 'redacted/x/page', source_path: source, output_paths: paths, pages_in: paths.length, pages_out: paths.length, status: 'complete' });

Deno.test('a quotation brief or a priced reading takes no pages; the BOQ button alone ("boq") is not a verdict', async () => {
  const asked = stubRuns([]);
  assertEquals(await drawingPagesRefused({ custId: CUST, briefSource: 'quotation', pricedReading: false, offered: true, follows: false, sources: [DRAWING] }), 'priced_document');
  assertEquals(await drawingPagesRefused({ custId: CUST, briefSource: 'drawing', pricedReading: true, offered: true, follows: false, sources: [DRAWING] }), 'priced_document', 'a priced reading (quotation or priced BOQ marks)');
  assertEquals(await drawingPagesRefused({ custId: CUST, briefSource: 'quotation', pricedReading: false, offered: false, follows: true, sources: [] }), 'priced_document', 'nor pages that follow');
  assertEquals([...asked], [], 'decided without the database');
  // A drawing PDF sent with the BOQ button, or merged with an unpriced BOQ sheet: 'boq' is the client's label, not a verdict.
  assertEquals(await drawingPagesRefused({ custId: CUST, briefSource: 'boq', pricedReading: false, offered: true, follows: false, sources: [DRAWING] }), false);
  assertEquals(await drawingPagesRefused({ custId: CUST, briefSource: 'quotation', pricedReading: true, offered: false, follows: false, sources: [] }), false, 'nothing offered: nothing refused');
});

Deno.test('a client that names a priced document\'s runs on a "drawing" request is refused: the server\'s verdict decides', async () => {
  // The edge redacted the quotation's pages (run q1) and then judged it priced (the verdict row on its stored original).
  stubRuns([run('11111111-1111-4111-8111-111111111111', QUOTE, ['redacted/q/page_p0.jpg']), verdict(QUOTE)]);
  const rr = await resolveRedactedPaths(CUST, 'u1', { redaction_job_ids: ['11111111-1111-4111-8111-111111111111'], brief_source: 'drawing' });
  assert(!('err' in rr));
  assertEquals(rr.paths, ['redacted/q/page_p0.jpg'], 'the run is the customer\'s own, so it resolves');
  assertEquals(rr.sources, [QUOTE], 'and names the document it was redacted from');
  assertEquals(await drawingPagesRefused({ custId: CUST, briefSource: 'drawing', pricedReading: false, offered: true, follows: false, sources: [DRAWING, ...(rr.sources ?? [])] }), 'priced_document', 'a verdict that was read and found priced says so');
  // The request's own stored drawing judged priced refuses too, even when the runs name another source.
  assertEquals(await sourcesJudgedPriced(CUST, [QUOTE]), true);
  stubRuns([run('22222222-2222-4222-8222-222222222222', DRAWING, ['redacted/d/page_p0.jpg'])]);
  assertEquals(await drawingPagesRefused({ custId: CUST, briefSource: 'drawing', pricedReading: false, offered: true, follows: false, sources: [DRAWING] }), false, 'a drawing nobody judged priced keeps its pages');
  stubRuns([], true);
  assertEquals(await sourcesJudgedPriced(CUST, [DRAWING]), true, 'a verdict nobody could read attaches nothing (fail closed)');
});

// A VERDICT THAT COULD NOT BE READ (18 Nov 2026): the pages are refused exactly as before, but the reason, the customer's
// message and the seat's finding say the verdict was unread, never that the document was found to be priced.
Deno.test('an unreadable verdict refuses the pages with reason "priced_verdict_unread"; a readable priced verdict still says "priced_document"', async () => {
  const offer = { custId: CUST, briefSource: 'drawing', pricedReading: false, offered: true, follows: false, sources: [DRAWING] };
  stubRuns([], true);
  assertEquals(await pricedVerdictOf(CUST, [DRAWING]), 'unread');
  assertEquals(await drawingPagesRefused(offer), 'priced_verdict_unread', 'refused (fail closed), for the true reason');
  assertEquals(await drawingPagesRefused({ ...offer, offered: false, follows: true }), 'priced_verdict_unread', 'pages that follow too');
  assertEquals(await sourcesJudgedPriced(CUST, [DRAWING]), true, 'the boolean stays fail closed');
  // A quotation brief or a priced reading is decided without the read, so it is still 'priced_document' while the read fails.
  assertEquals(await drawingPagesRefused({ ...offer, briefSource: 'quotation' }), 'priced_document');
  assertEquals(await drawingPagesRefused({ ...offer, pricedReading: true }), 'priced_document');
  // A thrown read is unread too.
  // deno-lint-ignore no-explicit-any
  (admin as any).from = () => { throw new Error('socket closed'); };
  assertEquals(await drawingPagesRefused(offer), 'priced_verdict_unread');
  // Readable: priced says so, unpriced keeps its pages.
  stubRuns([verdict(DRAWING)]);
  assertEquals(await pricedVerdictOf(CUST, [DRAWING]), 'priced');
  assertEquals(await drawingPagesRefused(offer), 'priced_document');
  stubRuns([]);
  assertEquals(await pricedVerdictOf(CUST, [DRAWING]), 'not_priced');
  assertEquals(await pricedVerdictOf(CUST, ['']), 'not_priced', 'nothing named: nothing to read');
  assertEquals(await drawingPagesRefused(offer), false);
  // What each reason tells the customer: the unread one never says the document was found to be priced.
  assertEquals(PAGES_WITHHELD_MESSAGE.priced_document, PRICED_PAGES_WITHHELD_MESSAGE);
  assertEquals(PAGES_WITHHELD_MESSAGE.priced_verdict_unread, PRICED_VERDICT_UNREAD_MESSAGE);
  assert(!/found to be priced|was priced|is priced/i.test(PRICED_VERDICT_UNREAD_MESSAGE.en), 'no claim that the document is priced');
  assertMatch(PRICED_VERDICT_UNREAD_MESSAGE.en, /could not confirm .* unpriced/);
  assertMatch(PRICED_VERDICT_UNREAD_MESSAGE.en, /separate request, or try again shortly/);
  assert(!PRICED_VERDICT_UNREAD_MESSAGE.ar.includes('تبيّن أنه مُسعَّر'), 'nor in Arabic');
  assertMatch(PRICED_VERDICT_UNREAD_MESSAGE.ar, /لم نتمكّن/);
});

Deno.test('wired: analyze_drawing and analyze_document record the verdict; create_inquiry decides before any page is attached', () => {
  const docs = Deno.readTextFileSync(new URL('./actions/documents.ts', import.meta.url));
  assertMatch(docs, /if \(priced && path\) await recordPricedVerdict\(\{ customerId: cust\.id, email, sourcePath: path, kind: priced\.document_kind, runIds: redJobs, paths: redacted \}\);\s*if \(priced\) return J\(/);
  assertMatch(docs, /const pk = pricedDocumentKind\(\[\], jd\.boq\);\s*if \(pk && path\) await recordPricedVerdict\(/);
  const create = Deno.readTextFileSync(new URL('./actions/inquiry_create.ts', import.meta.url));
  assertMatch(create, /const pagesRefused = await drawingPagesRefused\(\{ custId: String\(cust\.id\), briefSource, pricedReading: isQuotationReading\(boqObj\) \|\| isPricedReading\(boqObj\), offered: !!offered, follows: follow\.follows, sources: \[drawingPath \?\? '', \.\.\.\(rr\.sources \?\? \[\]\), \.\.\.\(follow\.sources \?\? \[\]\)\] \}\);/);
  // The customer is told when pages were refused, and the seat too, a BOQ-button PDF included.
  // The reason is the decision's own (18 Nov 2026): 'priced_document' or 'priced_verdict_unread', each with its own message.
  assertMatch(create, /: pagesRefused \? \{ drawing_pages_withheld: true, drawing_pages_withheld_reason: pagesRefused, drawing_pages_withheld_message: PAGES_WITHHELD_MESSAGE\[pagesRefused\] \} : \{\};/);
  assert(!/drawing_pages_withheld_reason: 'priced_document'/.test(create), 'no hard-coded "priced" reason');
  assertMatch(create, /if \(pagesRefused\) await drawingIdentityFinding\(pagesRefused === 'priced_verdict_unread' \? 'priced_verdict_unread' : 'priced_pages_refused', /, 'the seat is told a failed read as a failed read');
  assertMatch(create, /\(briefSource === 'drawing' \|\| \(briefSource === 'boq' && \/\\\.pdf\$\/i\.test\(drawingPath\)\) \|\| drawing\?\.held === true \|\| pagesRefused\)\) await drawingIdentityFinding\('sent_without_drawing'/);
  assertEquals((create.match(/return J\(\{ \.\.\.followSaid, /g) ?? []).length, 3, 'single, turnkey and every split answer carry it');
  assertMatch(create, /const drawingRedacted = pagesRefused \? null : offered;\s*const pagesFollow = !pagesRefused && !drawingRedacted && follow\.follows;/);
  assertMatch(create, /isQuotationReading\(boqObj\) \? 'quotation' : isPricedReading\(boqObj\) \? 'boq' :/, 'a priced BOQ reading is a priced brief whatever the client says');
});

// RE-REVIEW OF 464673eff, ITEM 2: a verdict that cannot be written must not leave the document's runs attachable.
Deno.test('a priced verdict that cannot be recorded retires the document\'s runs and removes their pages: still nothing to attach', async () => {
  const RUN = '33333333-3333-4333-8333-333333333333';
  const rows: Row[] = [run(RUN, QUOTE, ['redacted/q/page_p0.jpg'])];
  const st = stubRuns(rows, false, { failInsert: true });
  const ok = await recordPricedVerdict({ customerId: CUST, email: 'zz@example.invalid', sourcePath: QUOTE, kind: 'quotation', runIds: [RUN], paths: ['redacted/q/page_p0.jpg'] });
  assertEquals(ok, true, 'held by the retirement');
  assertEquals(st.inserted, [], 'the verdict itself was lost (asked twice)');
  assertEquals(st.updated.map((u) => [u.set.status, u.set.output_paths, (u.set.verify_detail as Row).reason, u.ids]), [['held', [], PRICED_VERDICT, [RUN]]]);
  assertEquals(st.removed, [['redacted/q/page_p0.jpg']], 'the stored pages are removed');
  assert(st.findings.some((k) => k.startsWith('sales_engineer:priced_verdict_unrecorded:')), 'and the IT engineer is told');
  // The retired run is now the verdict: the document is judged priced, and the run no longer resolves for any request.
  assertEquals(await sourcesJudgedPriced(CUST, [QUOTE]), true);
  const rr = await resolveRedactedPaths(CUST, 'u1', { redaction_job_ids: [RUN] });
  assert('err' in rr && rr.status === 403, 'a client naming the run is refused');
  // Nothing to retire and the write lost: false, so the caller knows (and the finding says so).
  stubRuns([], false, { failInsert: true });
  assertEquals(await recordPricedVerdict({ customerId: CUST, email: 'zz@example.invalid', sourcePath: QUOTE, kind: 'quotation' }), false);
  // The write that succeeds is the verdict row, nothing retired.
  const fine = stubRuns([run(RUN, QUOTE, ['redacted/q/page_p0.jpg'])]);
  assertEquals(await recordPricedVerdict({ customerId: CUST, email: 'zz@example.invalid', sourcePath: QUOTE, kind: 'quotation', runIds: [RUN], paths: ['redacted/q/page_p0.jpg'] }), true);
  assertEquals([fine.inserted.length, fine.updated.length, fine.removed.length], [1, 0, 0]);
});
