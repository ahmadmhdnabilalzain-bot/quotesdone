// A DUCT RUN IS MEASURED SHEET BY SHEET (17 Nov 2026, sales_engineer; paid proof 14173f94, founder ledger 580).
// The proof's BOQ said "Rectangular ductwork, sizes 26x18" with no quantity against 16,432.9 m drawn: the one whole-set
// 'lengths' call took 2,030-2,106 ms of CPU locally (the edge's cap is 2 s) and answered 500 on production. The lengths are
// now read a sheet per drawing_boq call and put together by a last call (drawing_set/lengths.ts, length_read.ts). This
// proves, on the e2e's own 8-sheet set (_shared/testdata, = scripts/e2e/drawing_reaches_suppliers.mjs stressSetPdf(8)):
//   1. the parts, each sheet parsed alone and sent as JSON, give EXACTLY the whole-set lines, and the answer key's metres;
//   2. every request customer_api now makes runs the REAL handler inside a CPU budget well under the edge's 2 s.
// Run: deno test --no-lock --node-modules-dir=none --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY --allow-read=. --allow-run \
//   supabase/functions/drawing_boq/a_duct_run_is_measured_sheet_by_sheet.test.ts   (--allow-run: each request in its own process)
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { pdfPages } from '../_shared/pdf_text_positions.ts';
import { boqFromDrawingSet, lengthsForSet, lengthsOfParts, lengthsPart } from './drawing_set.ts';
import { layeredSetPdf } from './drawing_lengths.fixtures.ts';
import { LENGTHS_PAGES_PER_CALL, readLengths } from './length_read.ts';

const SET8 = Deno.readFileSync(new URL('../_shared/testdata/zz_demo_mechanical_set_8_sheets.pdf', import.meta.url));
/** The e2e's answer key for the duct (TRUTH 'Duct 26x18': 30 x 0.013 x 2592 / 72 in x 8 ft/in a run, 60 runs, 8 sheets). */
const KEY_M = +(30 * 0.013 * 2592 / 72 * 8 * 0.3048 * 60 * 8).toFixed(1);
/** The e2e's tolerance for that line (TRUTH tolPct). */
const KEY_TOL_PCT = 0.5;
/** A drawing_boq request customer_api makes for the lengths gets at most this much CPU HERE. The edge kills past ~2 s and ran
 *  the redaction's same steps ~1.3x slower than this machine (a_sheet_is_redacted_within_the_edge_budget.check.ts), so
 *  1,400 ms is the most that is still inside it. MEASURED, cold process, real handler: one sheet 349-458 ms, the merge 38 ms;
 *  the whole set in one call (the request customer_api made until now) 2,006-2,106 ms. */
const CALL_CPU_BUDGET_MS = 1_400;
const json = <T>(x: T): T => JSON.parse(JSON.stringify(x));

Deno.test('the sheets measured one by one and put together are the whole-set measurement, to the byte, and the answer key', async () => {
  for (const [name, bytes] of [['the e2e 8-sheet set', SET8], ['the layered plumbing + duct set', layeredSetPdf()]] as const) {
    const whole = lengthsForSet(await pdfPages(bytes));
    const n = (await pdfPages(bytes, undefined, { layers: false })).length;
    const parts = [];
    for (let i = 0; i < n; i++) parts.push(json(lengthsPart(await pdfPages(bytes, [i, i + 1]), i, i + 1)));   // over the wire
    const got = lengthsOfParts(parts.reverse());                                                             // in any order
    assert(got, `${name}: the parts merged`);
    assertEquals(got, json(whole), `${name}: the same lines, quantities, bases and dense sheets`);
    assert(whole.lines.length > 0, `${name}: something was measured`);
  }
  const duct = lengthsForSet(await pdfPages(SET8)).lines.filter((l) => l.type === 'duct:26x18');
  assertEquals(duct.length, 1, 'one 26x18 line for the whole set');
  assert(Math.abs(duct[0].qty! - KEY_M) / KEY_M * 100 < KEY_TOL_PCT, `26x18: ${duct[0].qty} m against the key ${KEY_M} m`);
  assertEquals(duct[0].sheets, ['M1.0', 'M1.1', 'M1.2', 'M1.3', 'M1.4', 'M1.5', 'M1.6', 'M1.7'], 'measured on every sheet');
});

Deno.test('a set of parts that does not cover every sheet once is no measurement', async () => {
  const parts = [];
  for (let i = 0; i < 8; i++) parts.push(json(lengthsPart(await pdfPages(SET8, [i, i + 1]), i, i + 1)));
  assertEquals(lengthsOfParts(parts.slice(1)), null, 'the first sheet missing');
  assertEquals(lengthsOfParts([...parts.slice(0, 7)]), null, 'the last sheet missing');
  assertEquals(lengthsOfParts([...parts, parts[3]]), null, 'a sheet twice');
  assertEquals(lengthsOfParts([...parts.slice(0, 7), { ...parts[7], pages: 9 }]), null, 'a part of another set');
  assertEquals(lengthsOfParts([...parts.slice(0, 7), { ...parts[7], sheets: [{ ...parts[7].sheets[0], measured: [{ key: '26x18' }] }] }]), null, 'a malformed run');
});

// ── the real handler, each request in a fresh process of its own (./a_duct_run_is_measured_sheet_by_sheet.call.ts) ─────
// A fresh process per request is a fresh edge worker, and its CPU is that request's alone: measured in this process, a run of
// this file with the drawing_boq and customer_api suites counted the other files' work and failed (17 Nov 2026).
let b64 = ''; for (let i = 0; i < SET8.length; i += 0x8000) b64 += String.fromCharCode(...SET8.subarray(i, i + 0x8000));
const ORIGINAL = btoa(b64);
const CALL = new URL('./a_duct_run_is_measured_sheet_by_sheet.call.ts', import.meta.url).pathname;
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
  assert(first.boq.some((l) => l.type === 'duct:rectangular' && l.qty === null && /26x18/.test(l.description)), 'the take-off asks for the 26x18 length');
  const spent: { req: string; ms: number }[] = [];
  const merged = await readLengths(async (b) => {
    const body = { __secret: 'zz-cred-0123456789abcdef0123', ...b, ...(b.parts ? {} : { original_b64: ORIGINAL }) };
    const r = await inFreshWorker(body);
    spent.push({ req: b.parts ? 'merge' : `sheet ${b.from}`, ms: r.cpu_ms });
    return r.status === 200 ? r.json : null;
  }, first);
  assert(merged, 'the lengths were read');
  assertEquals(spent.length, 8 / LENGTHS_PAGES_PER_CALL + 1, 'a request per sheet and one to put them together');
  const over = spent.filter((s) => s.ms > CALL_CPU_BUDGET_MS);
  assertEquals(over, [], `requests past ${CALL_CPU_BUDGET_MS} ms of CPU: ${JSON.stringify(spent)}`);
  const duct = merged.boq.filter((l: any) => /26\s*x\s*18/.test(l.description));
  assertEquals(duct.map((l: any) => [l.type, l.qty]), [['duct:26x18', lengthsForSet(await pdfPages(SET8)).lines[0].qty]], 'the measured line replaced the size-only one');
  assert(!merged.boq.some((l: any) => /^(duct|pipe):/.test(l.type) && l.qty === null), 'no length left blank');
  assert(merged.missing_info[0].startsWith('Duct and pipe lengths are measured in plan'));
});
