// A DUCT RUN IS MEASURED SHEET BY SHEET, EACH REQUEST INSIDE THE EDGE CPU BUDGET (17 Nov 2026, sales_engineer; paid proof
// 14173f94, founder ledger 580). The proof's 26x18 duct (16,432.9 m) reached the inquiry with no quantity: the one whole-set
// drawing_boq 'lengths' request took ~2 s of CPU (the edge's cap) and answered 500 on production. customer_api now asks a
// sheet per request and one more to put them together (drawing_boq/length_read.ts); the correctness of that is proved by
// ./a_duct_run_is_measured_sheet_by_sheet.test.ts. This file holds each request's CPU.
//
// EACH REQUEST IN A FRESH PROCESS OF ITS OWN (./a_duct_run_is_measured_sheet_by_sheet.call.ts: the REAL handler, every edge
// stubbed, answering once and printing its own CPU over the handler call). A fresh process is a fresh edge worker, and its CPU
// is that request's alone: measured in the test runner's process, the drawing_boq + customer_api suites run together counted
// the other files' work and failed. A .check.ts, not a .test.ts: it needs --allow-run, which the Deno suite does not grant,
// so it is its own local gate step ('lengths-budget'), run alone of the other heavy steps like 'redact-budget'.
//
//   deno test --no-lock --node-modules-dir=none --allow-read=. --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY --allow-run \
//     supabase/functions/drawing_boq/a_duct_run_is_measured_sheet_by_sheet.check.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { pdfPages } from '../_shared/pdf_text_positions.ts';
import { boqFromDrawingSet } from './drawing_set.ts';
import { LENGTHS_PAGES_PER_CALL, readLengths } from './length_read.ts';

/** A drawing_boq request customer_api makes for the lengths gets at most this much CPU HERE. The edge kills past ~2 s and ran
 *  the redaction's same steps ~1.3x slower than this machine (drawing_redact/a_sheet_is_redacted_within_the_edge_budget
 *  .check.ts), so 1,400 ms is the most that is still inside it. MEASURED, a fresh process per request, real handler: one
 *  sheet 493-533 ms, the merge ~40 ms; the whole set in one request (what customer_api asked until now) 1,920-1,924 ms. */
export const CALL_CPU_BUDGET_MS = 1_400;

const SET8 = Deno.readFileSync(new URL('../_shared/testdata/zz_demo_mechanical_set_8_sheets.pdf', import.meta.url));
let b64 = ''; for (let i = 0; i < SET8.length; i += 0x8000) b64 += String.fromCharCode(...SET8.subarray(i, i + 0x8000));
const ORIGINAL = btoa(b64);
const SECRET = 'zz-cred-0123456789abcdef0123';
const CALL = new URL('./a_duct_run_is_measured_sheet_by_sheet.call.ts', import.meta.url).pathname;
const json = <T>(x: T): T => JSON.parse(JSON.stringify(x));

// deno-lint-ignore no-explicit-any
async function inFreshWorker(body: Record<string, unknown>): Promise<{ status: number; json: any; cpu_ms: number }> {
  const p = new Deno.Command(Deno.execPath(), {
    args: ['run', '--no-lock', '--node-modules-dir=none', '--allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY,RESEND_INBOUND_NO_SERVE', '--allow-read=.', CALL],
    stdin: 'piped', stdout: 'piped', stderr: 'piped',
  }).spawn();
  const w = p.stdin.getWriter(); await w.write(new TextEncoder().encode(JSON.stringify(body))); await w.close();
  const out = await p.output();
  const text = new TextDecoder().decode(out.stdout).trim().split('\n').pop() || '';
  assert(out.success && text.startsWith('{'), `the request's process failed: ${new TextDecoder().decode(out.stderr).slice(-600)}`);
  return JSON.parse(text);
}

Deno.test('every lengths request customer_api makes runs inside the edge CPU budget, and the BOQ gets the metres', async () => {
  const first = json(boqFromDrawingSet(await pdfPages(SET8, undefined, { layers: false }))!);
  const spent: { req: string; ms: number }[] = [];
  const merged = await readLengths(async (b) => {
    const r = await inFreshWorker({ __secret: SECRET, ...b, ...(b.parts ? {} : { original_b64: ORIGINAL }) });
    spent.push({ req: b.parts ? 'merge' : `sheet ${b.from}`, ms: r.cpu_ms });
    return r.status === 200 ? r.json : null;
  }, first);
  assert(merged, `the lengths were read: ${JSON.stringify(spent)}`);
  assertEquals(spent.length, 8 / LENGTHS_PAGES_PER_CALL + 1, 'a request per sheet and one to put them together');
  assertEquals(spent.filter((s) => s.ms > CALL_CPU_BUDGET_MS), [], `requests past ${CALL_CPU_BUDGET_MS} ms of CPU: ${JSON.stringify(spent)}`);
  // deno-lint-ignore no-explicit-any
  assertEquals(merged.boq.filter((l: any) => /26\s*x\s*18/.test(l.description)).map((l: any) => l.type), ['duct:26x18'], 'the BOQ has the measured line');
});

Deno.test('the budget is one the old whole-set request breaks: measured the same way, it is past it', async () => {
  // The request customer_api made until 17 Nov (drawing_boq still answers it, for a caller deployed before the change).
  const r = await inFreshWorker({ __secret: SECRET, mode: 'lengths', boq: json(boqFromDrawingSet(await pdfPages(SET8, undefined, { layers: false }))!), original_b64: ORIGINAL });
  assertEquals(r.status, 200);
  assert(r.cpu_ms > CALL_CPU_BUDGET_MS, `the whole set in one request took ${r.cpu_ms} ms: the budget would not have caught it`);
});
