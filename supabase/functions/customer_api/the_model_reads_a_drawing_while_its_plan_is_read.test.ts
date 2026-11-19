// THE MODEL READS A DRAWING WHILE ITS PLAN IS READ (19 Nov 2026, sales_engineer; founder ruling 1533: "Drawings should feel
// like attaching a drawing to Claude: it understands it, fast").
// MEASURED (SELECT, function_edge_logs, the 16 analyze_drawing requests of 17-18 Nov 2026, the only ones in 30 days):
// analyze_drawing p50 109.5 s / p90 129.5 s; drawing_boq's read p50 87.0 s / p90 100.5 s, and it started only after the plan
// read answered (p50 18.9 s / p90 28.0 s). The read needs nothing from the plan, so it now starts first and runs beside it.
// Proved here, on the handler's own code: the read is started before the plan is awaited; its body names nothing the plan
// gives; an early failure cannot escape as an unhandled rejection; and every decision taken from its answer (priced or not,
// queued or not) is still taken only after it has answered.
import { assert } from 'jsr:@std/assert@1';

const code = (u: URL) => Deno.readTextFileSync(u).replace(/^\s*\/\/.*$/gm, '');
const docs = code(new URL('./actions/documents.ts', import.meta.url));
const analyze = docs.slice(docs.indexOf("if (action === 'analyze_drawing')"));
const at = (s: string) => { const i = analyze.indexOf(s); assert(i > 0, `analyze_drawing has ${s}`); return i; };

Deno.test('the model read is started before the plan read is awaited', () => {
  assert(at('const boqP = timedFetch(') < at('await readPdfPlan('), 'drawing_boq still waits for the plan');
  assert(at('const boqBody =') < at('await readPdfPlan('));
});

Deno.test('the read is sent the upload as before, and nothing the plan or the pages decide', () => {
  const body = analyze.slice(at('const boqBody ='), at('const boqP = timedFetch('));
  for (const fromPlan of ['pdfLines', 'pdfWords', 'serverBoxes', 'floorSeeds', 'manualBoxes', 'planLost', 'redacted', 'redJobs', 'pricedByCode'])
    assert(!new RegExp(`\\b${fromPlan}\\b`).test(body), `the read's body uses ${fromPlan}`);
  for (const asBefore of ['images', 'original_b64', 'ocr_text', 'drawingOcr(body)', 'scheduleTables(body)', "mode: 'document'"])
    assert(body.includes(asBefore), `the read's body lost ${asBefore}`);
});

Deno.test('a read that fails early is observed at once, and still answered as a failed read', () => {
  assert(at('boqP.catch(() => {})') < at('await readPdfPlan('), 'an early rejection would be unhandled while the plan runs');
  assert(at('Promise.allSettled([boqP])') > at('await readPdfPlan('));
  assert(/if \(boqRes\.status !== 'fulfilled'\) return J\(\{ ok: false, error: 'analysis_exception', detail: 'boq_fetch_failed'/.test(analyze));
});

Deno.test('priced or not, and queued or not, are still decided only after the read has answered', () => {
  const answered = at('Promise.allSettled([boqP])');
  assert(answered < at('pricedRoute({'), 'the priced verdict is read before the model answered');
  assert(answered < at('queuePagesOnce('), 'a set is queued before the model said it is not priced');
  assert(answered < at("mode: 'confirm'"), 'the confirm runs before the read');
  assert(at('eachPageInTime(') < at("mode: 'confirm'"), 'the confirm no longer waits for the redaction');
});
