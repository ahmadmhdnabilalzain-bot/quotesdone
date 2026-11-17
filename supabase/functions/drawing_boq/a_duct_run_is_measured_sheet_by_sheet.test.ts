// A DUCT RUN IS MEASURED SHEET BY SHEET (17 Nov 2026, sales_engineer; paid proof 14173f94, founder ledger 580).
// The proof's BOQ said "Rectangular ductwork, sizes 26x18" with no quantity against 16,432.9 m drawn: the one whole-set
// 'lengths' call took 2,030-2,106 ms of CPU locally (the edge's cap is 2 s) and answered 500 on production. The lengths are
// now read a sheet per drawing_boq call and put together by a last call (drawing_set/lengths.ts, length_read.ts). This
// proves, on the e2e's own 8-sheet set (_shared/testdata, = scripts/e2e/drawing_reaches_suppliers.mjs stressSetPdf(8)):
//   1. the parts, each sheet parsed alone and sent as JSON, give EXACTLY the whole-set lines, and the answer key's metres;
//   2. the requests customer_api now makes, answered by the REAL handler, give the BOQ its metres.
// Each request's CPU budget is held by ./a_duct_run_is_measured_sheet_by_sheet.check.ts (local gate 'lengths-budget'): a CPU
// measurement needs a process of its own per request, and the Deno suite runs without --allow-run.
// Run: deno test --no-lock --node-modules-dir=none --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY --allow-read=. \
//   supabase/functions/drawing_boq/a_duct_run_is_measured_sheet_by_sheet.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { pdfPages } from '../_shared/pdf_text_positions.ts';
import { invoke, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';
import { boqFromDrawingSet, lengthsForSet, lengthsOfParts, lengthsPart } from './drawing_set.ts';
import { layeredSetPdf } from './drawing_lengths.fixtures.ts';
import { LENGTHS_PAGES_PER_CALL, readLengths } from './length_read.ts';

const SET8 = Deno.readFileSync(new URL('../_shared/testdata/zz_demo_mechanical_set_8_sheets.pdf', import.meta.url));
/** The e2e's answer key for the duct (TRUTH 'Duct 26x18': 30 x 0.013 x 2592 / 72 in x 8 ft/in a run, 60 runs, 8 sheets). */
const KEY_M = +(30 * 0.013 * 2592 / 72 * 8 * 0.3048 * 60 * 8).toFixed(1);
/** The e2e's tolerance for that line (TRUTH tolPct). */
const KEY_TOL_PCT = 0.5;
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

// ── the real handler, in this process, every edge stubbed (no CPU is measured here: see the .check.ts) ───────────────
const stub: Stub = { rpc: { fn_internal_auth: { ok: true, context: 'fn.customer_api', credential_id: 7, legacy: false } }, handle: async () => undefined };
const fn = await loadFunction('drawing_boq', () => import('./index.ts'));
let b64 = ''; for (let i = 0; i < SET8.length; i += 0x8000) b64 += String.fromCharCode(...SET8.subarray(i, i + 0x8000));
const ORIGINAL = btoa(b64);

Deno.test('the requests customer_api makes, answered by the real handler, give the BOQ its metres', async () => {
  const first = json(boqFromDrawingSet(await pdfPages(SET8, undefined, { layers: false }))!);
  assert(first.boq.some((l) => l.type === 'duct:rectangular' && l.qty === null && /26x18/.test(l.description)), 'the take-off asks for the 26x18 length');
  const asked: string[] = [];
  const merged = await readLengths(async (b) => {
    asked.push(b.parts ? 'merge' : `sheet ${b.from}`);
    const r = await invoke(fn, stub, { __secret: 'zz-cred-0123456789abcdef0123', ...b, ...(b.parts ? {} : { original_b64: ORIGINAL }) });
    return r.status === 200 ? r.json : null;
  }, first);
  assert(merged, 'the lengths were read');
  assertEquals(asked.length, 8 / LENGTHS_PAGES_PER_CALL + 1, 'a request per sheet and one to put them together');
  const duct = merged.boq.filter((l: any) => /26\s*x\s*18/.test(l.description));
  assertEquals(duct.map((l: any) => [l.type, l.qty]), [['duct:26x18', lengthsForSet(await pdfPages(SET8)).lines[0].qty]], 'the measured line replaced the size-only one');
  assert(!merged.boq.some((l: any) => /^(duct|pipe):/.test(l.type) && l.qty === null), 'no length left blank');
  assert(merged.missing_info[0].startsWith('Duct and pipe lengths are measured in plan'));
});

// ── THE MODEL'S OWN LINES REACH THE MERGE (17 Nov 2026, paid proof 623d9200) ─────────────────────────────────────────────
// SELECT, production agent_runs 17:20:57 and 17:22:38 UTC: every merge request answered HTTP 500
// {"error":"Cannot read properties of undefined (reading 'startsWith')"} in 61-188 ms, twice per take-off (the retry), so the
// 16,432.9 m of 26x18 duct never reached the BOQ. The take-off customer_api sends is the MODEL's reading merged with code's
// (cross_check.ts): a line the model alone read has no `type` at all, and one with no quantity met `l.type.startsWith` in
// mergeLengths. The test above sent code's take-off only, so it never had such a line.
Deno.test('a take-off carrying the model\'s own lines (no type, no quantity) is merged, not answered 500', async () => {
  const { crossCheck } = await import('./cross_check.ts');
  const code = json(boqFromDrawingSet(await pdfPages(SET8, undefined, { layers: false }))!);
  const modelOnly = { section: 'HVAC', item: 'Fire damper at each rated wall', description: 'Fire dampers, quantity per the fire strategy', qty: null, unit: 'nos', confidence: 'low' };
  const first = json({ ...code, boq: crossCheck([modelOnly], code.boq).boq });
  assert(first.boq.some((l: any) => l.type === undefined && l.qty === null), 'the take-off carries a model line with no type and no quantity');
  const statuses: number[] = [];
  const merged = await readLengths(async (b) => {
    const r = await invoke(fn, stub, { __secret: 'zz-cred-0123456789abcdef0123', ...b, ...(b.parts ? {} : { original_b64: ORIGINAL }) });
    if (b.parts) statuses.push(r.status);
    return r.status === 200 ? r.json : null;
  }, first);
  assertEquals(statuses, [200], 'the merge request answers 200 the first time');
  assert(merged, 'the lengths were read');
  assertEquals(merged.boq.filter((l: any) => /26\s*x\s*18/.test(l.description)).map((l: any) => l.type), ['duct:26x18'], 'the BOQ has the measured line');
  assert(merged.boq.some((l: any) => l.item === modelOnly.item && l.qty === null), 'the model\'s own line is kept, still asking for its quantity');
});
