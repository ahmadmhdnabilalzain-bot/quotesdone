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
const { PRICED_VERDICT, drawingPagesRefused, resolveRedactedPaths, sourcesJudgedPriced } = await import('./lib/drawings.ts');

const CUST = 'c0000000-0000-4000-8000-00000000000c';
const QUOTE = `drawings/${CUST}/1_ZZ DEMO quotation.pdf`, DRAWING = `drawings/${CUST}/2_ZZ DEMO drawing.pdf`;
type Row = Record<string, unknown>;
/** drawing_redaction_runs as the stub holds it; each query is filtered as PostgREST would filter it. */
function stubRuns(rows: Row[], fail = false) {
  const asked: string[] = [];
  // deno-lint-ignore no-explicit-any
  (admin as any).from = (table: string) => {
    assertEquals(table, 'drawing_redaction_runs');
    let out = [...rows]; const q: Record<string, unknown> = {
      select: () => q, order: () => q, limit: () => q, or: () => q,
      eq: (k: string, v: unknown) => { asked.push(`${k}=${v}`); out = out.filter((r) => k === 'verify_detail->>reason' ? (r.verify_detail as Row | undefined)?.reason === v : r[k] === v); return q; },
      neq: (k: string, v: unknown) => { out = out.filter((r) => r[k] !== v); return q; },
      in: (k: string, vs: unknown[]) => { asked.push(`${k} in ${vs.length}`); out = out.filter((r) => vs.includes(r[k])); return q; },
      then: (ok: (x: unknown) => unknown) => ok(fail ? { data: null, error: { message: 'down' } } : { data: out, error: null }),
    };
    return q;
  };
  return asked;
}
const verdict = (source: string): Row => ({ id: 'v1', customer_id: CUST, source_path: source, status: 'held', output_paths: [], verify_detail: { reason: PRICED_VERDICT, kind: 'quotation' } });
const run = (id: string, source: string, paths: string[]): Row => ({ id, customer_id: CUST, caller_ref: 'redacted/x/page', source_path: source, output_paths: paths, pages_in: paths.length, pages_out: paths.length, status: 'complete' });

Deno.test('a quotation\'s or a priced BOQ\'s brief takes no pages at all, without asking the database', async () => {
  const asked = stubRuns([]);
  for (const briefSource of ['quotation', 'boq', null]) assertEquals(await drawingPagesRefused({ custId: CUST, briefSource, offered: true, follows: false, sources: [DRAWING] }), true, String(briefSource));
  assertEquals(await drawingPagesRefused({ custId: CUST, briefSource: 'quotation', offered: false, follows: true, sources: [] }), true, 'nor pages that follow');
  assertEquals(asked, []);
  assertEquals(await drawingPagesRefused({ custId: CUST, briefSource: 'quotation', offered: false, follows: false, sources: [] }), false, 'nothing offered: nothing refused');
});

Deno.test('a client that names a priced document\'s runs on a "drawing" request is refused: the server\'s verdict decides', async () => {
  // The edge redacted the quotation's pages (run q1) and then judged it priced (the verdict row on its stored original).
  stubRuns([run('11111111-1111-4111-8111-111111111111', QUOTE, ['redacted/q/page_p0.jpg']), verdict(QUOTE)]);
  const rr = await resolveRedactedPaths(CUST, 'u1', { redaction_job_ids: ['11111111-1111-4111-8111-111111111111'], brief_source: 'drawing' });
  assert(!('err' in rr));
  assertEquals(rr.paths, ['redacted/q/page_p0.jpg'], 'the run is the customer\'s own, so it resolves');
  assertEquals(rr.sources, [QUOTE], 'and names the document it was redacted from');
  assertEquals(await drawingPagesRefused({ custId: CUST, briefSource: 'drawing', offered: true, follows: false, sources: [DRAWING, ...(rr.sources ?? [])] }), true);
  // The request's own stored drawing judged priced refuses too, even when the runs name another source.
  assertEquals(await sourcesJudgedPriced(CUST, [QUOTE]), true);
  stubRuns([run('22222222-2222-4222-8222-222222222222', DRAWING, ['redacted/d/page_p0.jpg'])]);
  assertEquals(await drawingPagesRefused({ custId: CUST, briefSource: 'drawing', offered: true, follows: false, sources: [DRAWING] }), false, 'a drawing nobody judged priced keeps its pages');
  stubRuns([], true);
  assertEquals(await sourcesJudgedPriced(CUST, [DRAWING]), true, 'a verdict nobody could read attaches nothing (fail closed)');
});

Deno.test('wired: analyze_drawing and analyze_document record the verdict; create_inquiry decides before any page is attached', () => {
  const docs = Deno.readTextFileSync(new URL('./actions/documents.ts', import.meta.url));
  assertMatch(docs, /if \(priced && path\) await recordPricedVerdict\(\{ customerId: cust\.id, email, sourcePath: path, kind: priced\.document_kind \}\);\s*if \(priced\) return J\(/);
  assertMatch(docs, /const pk = pricedDocumentKind\(\[\], jd\.boq\);\s*if \(pk && path\) await recordPricedVerdict\(/);
  const create = Deno.readTextFileSync(new URL('./actions/inquiry_create.ts', import.meta.url));
  assertMatch(create, /const pagesRefused = await drawingPagesRefused\(\{ custId: String\(cust\.id\), briefSource, offered: !!offered, follows: follow\.follows, sources: \[drawingPath \?\? '', \.\.\.\(rr\.sources \?\? \[\]\), \.\.\.\(follow\.sources \?\? \[\]\)\] \}\);/);
  assertMatch(create, /const drawingRedacted = pagesRefused \? null : offered;\s*const pagesFollow = !pagesRefused && !drawingRedacted && follow\.follows;/);
  assertMatch(create, /isQuotationReading\(boqObj\) \? 'quotation' : isPricedReading\(boqObj\) \? 'boq' :/, 'a priced BOQ reading is a priced brief whatever the client says');
});
