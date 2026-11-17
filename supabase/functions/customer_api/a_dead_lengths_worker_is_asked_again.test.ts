// A DEAD LENGTHS WORKER IS ASKED AGAIN, AND A LENGTH IS NEVER LEFT SILENTLY BLANK (17 Nov 2026, sales_engineer; paid proof
// 14173f94). On production the lengths call answered HTTP 500 in 1.2 s on a worker being shut down (EarlyDrop); this
// function queued the CAD worker only on a 546 or no answer, so the 26x18 duct reached the inquiry with an empty quantity.
// Here: the transport (lib/drawings.ts lengthsCall) and the read (drawing_boq/length_read.ts readLengths) against a stubbed
// drawing_boq that answers 500 and 546; and the request path's handling of a read that still fails.
// Run: deno test --no-lock --node-modules-dir=none --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY --allow-read=. \
//   supabase/functions/customer_api/a_dead_lengths_worker_is_asked_again.test.ts
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { readLengths } from '../drawing_boq/length_read.ts';
import { LENGTH_TO_CONFIRM, lengthsToConfirm } from '../drawing_boq/length_notes.ts';
import { isOpen, openLines } from '../_shared/boq_open_lines.ts';
import { functionSource } from '../../../scripts/lib/function_sources.mjs';

Deno.env.set('SUPABASE_URL', 'http://127.0.0.1:9');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-service');
const { lengthsCall } = await import('./lib/drawings.ts');

const BOQ = { method: 'drawing_set', missing_info: [], boq: [
  { section: 'Ductwork', type: 'duct:rectangular', item: 'Rectangular ductwork', description: 'Rectangular ductwork, sizes 26x18', qty: null, unit: 'm', basis: 'sizes printed on M1.0', confidence: 'low', status: 'new', sheets: ['M1.0'] },
  { section: 'Equipment', type: 'tag:EF-1', item: 'EF-1', description: 'EF-1 - exhaust fan', qty: 1, unit: 'nos', basis: 'tag on M1.0', confidence: 'medium', status: 'new', sheets: ['M1.0'] },
] };
const MEASURED = { ...BOQ, boq: [BOQ.boq[1], { ...BOQ.boq[0], type: 'duct:26x18', description: 'Rectangular ductwork 26x18', qty: 16433.2 }] };

/** drawing_boq, stubbed: a 3-sheet set; `fail(from, attempt)` answers a status instead of the part. */
function drawingBoq(fail: (from: number, attempt: number) => number | null) {
  const seen: { from: number | 'merge'; status: number; original: boolean }[] = [];
  const tries = new Map<number, number>();
  globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
    assertEquals(url, 'http://127.0.0.1:9/functions/v1/drawing_boq');
    const b = JSON.parse(typeof init?.body === 'string' ? init.body : await (init?.body as Blob).text());
    assertEquals(b.mode, 'lengths');
    if (Array.isArray(b.parts)) {
      seen.push({ from: 'merge', status: 200, original: 'original_b64' in b });
      return new Response(JSON.stringify({ ok: true, boq: MEASURED }), { status: 200 });
    }
    const k = (tries.get(b.from) ?? 0) + 1; tries.set(b.from, k);
    const status = fail(b.from, k);
    seen.push({ from: b.from, status: status ?? 200, original: typeof b.original_b64 === 'string' && b.original_b64.length > 0 });
    if (status) return new Response(JSON.stringify({ code: status === 546 ? 'WORKER_LIMIT' : 'InternalServerError' }), { status });
    return new Response(JSON.stringify({ ok: true, pages: 3, from: b.from, sheets: [{ page: b.from }] }), { status: 200 });
  }) as typeof fetch;
  return seen;
}
const call = () => lengthsCall('zz-cred-0123456789abcdef0123', 'JVBERi0xLjUK', Date.now() + 60_000);

Deno.test('a 500 from a dead worker is asked once more, on a fresh request, and the lengths still arrive', async () => {
  const seen = drawingBoq((from, attempt) => (from === 1 && attempt === 1 ? 500 : null));
  const got = await readLengths(call(), BOQ);
  assertEquals(got, MEASURED, 'the measured BOQ came back');
  assertEquals(seen.filter((s) => s.from === 1).map((s) => s.status), [500, 200], 'sheet 2 was asked again after its 500');
  assert(seen.filter((s) => s.from !== 'merge').every((s) => s.original), 'every sheet request carries the original');
  assertEquals(seen.filter((s) => s.from === 'merge').map((s) => s.original), [false], 'the merge carries the parts, not the PDF');
});

Deno.test('a sheet that fails twice (a 546, then a 500) gives the read up: no merge, null for the caller', async () => {
  const seen = drawingBoq((from) => (from === 2 ? (seen.filter((s) => s.from === 2).length ? 500 : 546) : null));
  assertEquals(await readLengths(call(), BOQ), null);
  assertEquals(seen.filter((s) => s.from === 2).map((s) => s.status), [546, 500], 'asked twice, no more');
  assert(!seen.some((s) => s.from === 'merge'), 'nothing was merged from an incomplete set');
});

Deno.test('a read that fails queues the CAD worker on ANY failure, and only unqueued says on the line the length is to be confirmed', () => {
  const src = functionSource('customer_api').replace(/^\s*\/\/.*$/gm, '');
  const at = src.indexOf('const measured = await readLengths(lengthsCall(');
  assert(at > 0, 'analyze_drawing reads the lengths sheet by sheet');
  const block = src.slice(at, src.indexOf('THE VISION COUNT', at) > 0 ? src.indexOf('THE VISION COUNT', at) : at + 2000);
  assert(!/546/.test(block), 'no status is singled out as the only dead worker');
  assertMatch(block, /if \(measured\) Object\.assign\(boqOut, measured\);\s*else \{[\s\S]*queueCadRead\(\{[^}]*why: 'pdf_lengths_worker_died'/);
  assertMatch(block, /if \(!lengthsJob && [^\n]*\) \{\s*boqOut\.boq = lengthsToConfirm\(boqOut\.boq\);\s*boqOut\.missing_info = \[LENGTHS_FAILED_NOTE,/);
  assert(!/mode: 'lengths', boq: boqOut, original_b64/.test(src), 'the whole-set lengths request is gone');
});

Deno.test('an unmeasured length says so on its own line and is an open line; a measured one is untouched', () => {
  // deno-lint-ignore no-explicit-any
  const out: Record<string, any>[] = lengthsToConfirm<Record<string, any>>([...BOQ.boq, { ...BOQ.boq[0], type: 'pipe:3" SS', description: '3" sanitary piping, new', description_ar: 'أنابيب صرف 3"' }, MEASURED.boq[1]]);
  assertEquals(out[0].description, `Rectangular ductwork, sizes 26x18 — ${LENGTH_TO_CONFIRM}`);
  assertEquals(out[0].qty_status, 'to_confirm');
  assert(isOpen(out[0] as never) && openLines(out as never).some((o) => o.type === 'duct:rectangular'), 'it is asked, never sent silently blank');
  assertMatch(String(out[2].description_ar), /الطول قيد التأكيد$/);
  assertEquals(out[1], BOQ.boq[1], 'a counted line is untouched');
  assertEquals(out[3], MEASURED.boq[1], 'a measured length is untouched');
  assertEquals(lengthsToConfirm(out), out, 'said once, however often it is applied');
});
