// A DRAWING IS ANALYSED WITHIN THE EDGE BUDGET (17 Nov 2026, sales_engineer; live bug of the paid proof 712aae1d).
// MEASURED (SELECT, function logs): analyze_drawing 546 "CPU Time exceeded" at 3108 ms (8 sheets) and 3098 ms (one sheet of
// the same set), killed while decoding the whole original PDF and boxing every title block on the request path, with no
// outbound call in the last 3.2 s. The read now runs in drawing_redact, page by page (_shared/drawing_plan.ts, whose test
// proves the verdict is the whole-set one). This holds the request path to that: nothing here parses the PDF.
import { assert, assertMatch } from 'jsr:@std/assert@1';

const code = (u: URL) => Deno.readTextFileSync(u).replace(/^\s*\/\/.*$/gm, '');
const docs = code(new URL('./actions/documents.ts', import.meta.url));
const analyze = docs.slice(docs.indexOf("if (action === 'analyze_drawing')"));

Deno.test('analyze_drawing does not decode or parse the original PDF on its request path', () => {
  assert(analyze.length > 1000, 'the analyze_drawing handler is found');
  for (const [what, re] of [
    ['the PDF text-layer parser', /\bpdfPages\s*\(/], ['the title-block boxing', /\btitleBlockBoxes\s*\(/],
    ['the line reader over the whole set', /\blinesFromRuns\s*\(/], ['a decode of the original', /\batob\s*\(/],
  ] as const) assert(!re.test(analyze), `analyze_drawing calls ${what} again`);
  assert(!/from '\.\.\/\.\.\/_shared\/pdf_text_positions\.ts'/.test(docs), 'documents.ts imports the PDF parser again');
});

Deno.test('the read goes to drawing_redact page by page, and its answer is used as the whole-set read was', () => {
  assertMatch(analyze, /const plan = await readPdfPlan\(pdfPlanCall\(secret, String\(body\.original_b64\), analyzeAt \+ ANALYZE_DRAWING_BUDGET_MS\), seedTerms\(/);
  assertMatch(analyze, /serverBoxes = supplierBoxes\(tb, manualBoxes, images\.length\); floorSeeds = \[\.\.\.new Set\(\[\.\.\.floorSeeds, \.\.\.tb\.setSeeds\]\)\];/);
  assertMatch(analyze, /\} else serverBoxes = null;/, 'no answer is the old parse failure: no server boxes');
  const lib = code(new URL('./lib/drawings.ts', import.meta.url));
  assertMatch(lib, /export function pdfPlanCall\([^)]*\)[\s\S]{0,800}functions\/v1\/drawing_redact/);
  // the original is serialised once per read (_shared/drawing_plan.ts planBodies), never once per call
  const call = lib.slice(lib.indexOf('export function pdfPlanCall'), lib.indexOf('export async function redactFile'));
  assertMatch(call, /const bodyOf = planBodies\(secret, b64\.replace\([^\n]*\)\);[\s\S]*return async \(b\) => \{[\s\S]*body: bodyOf\(b\),/);
  assert(!/JSON\.stringify\([^)]*original/.test(call), 'pdfPlanCall serialises the original per call again');
  const red = code(new URL('../drawing_redact/index.ts', import.meta.url));
  assertMatch(red, /if \(body\.mode === 'plan'\) \{[\s\S]{0,900}planBoxes\(bytes, from, to,[\s\S]{0,200}planStrips\(bytes, from, to\)/);
  // the plan mode sits behind the same internal-credential gate as every other mode
  assert(red.indexOf("requireInternal(admin, body?.__secret, 'drawing_redact')") < red.indexOf("body.mode === 'plan'"));
});
