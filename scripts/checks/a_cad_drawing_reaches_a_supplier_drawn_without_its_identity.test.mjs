// A CAD DRAWING REACHES A SUPPLIER DRAWN WITHOUT ITS IDENTITY (24 Sep 2026, sales_engineer; founder
// instructions 32, 580, 701, 703).
//
// MEASURED (production, read-only, 24 Sep 2026): public.drawing_redaction_runs held 6 rows and none was
// 'complete'. Every CAD upload went to cad_convert (a paid CloudConvert raster with no text layer), the server
// could not box its title block, the model is held, and the drawing was held: no DXF or DWG ever reached a
// supplier. The in-process proof is supabase/functions/_shared/cad_render.test.ts and
// supabase/functions/drawing_boq/every_drawing_format.test.ts; this check pins the WIRING, so the capability
// cannot be quietly disconnected again the way the DWG reader once was (a_cad_upload_reaches_the_cad_reader).
//
//   node --test scripts/checks/a_cad_drawing_reaches_a_supplier_drawn_without_its_identity.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const api = read('supabase/functions/customer_api/index.ts');
const redact = read('supabase/functions/drawing_redact/index.ts');
const page = read('supabase/functions/_shared/drawing_redact_page.ts');
const worker = read('scripts/cad_read_worker.ts');
const nightly = read('.github/workflows/nightly-journey.yml');
const checks = read('.github/workflows/checks.yml');
const between = (s, a, b) => s.slice(s.indexOf(a), s.indexOf(b, s.indexOf(a) + 1));

test('both CAD entry points draw the original through drawing_redact mode cad, and neither calls cad_convert', () => {
  const helper = between(api, 'async function redactCad(', 'async function recordHeld(');
  assert.match(helper, /functions\/v1\/drawing_redact/);
  assert.match(helper, /mode: 'cad', original_b64: o\.b64, seed_terms: o\.seeds/);
  const drawing = between(api, "action === 'analyze_drawing'", "action === 'create_inquiry'");
  const document = between(api, "action === 'analyze_document'", "action === 'analyze_drawing'");
  assert.match(drawing, /await redactCad\(/, 'analyze_drawing no longer draws a CAD original');
  assert.match(document, /await redactCad\(/, 'analyze_document no longer draws a CAD original');
  for (const [name, b] of [['analyze_drawing', drawing], ['analyze_document', document]]) {
    assert.match(b, /drawingHandoff\((?:cadRed|red)\.meta, path, (?:cadRed|red)\.redacted\)/, `${name}: the hold is not decided by drawingHandoff`);
  }
  assert.doesNotMatch(api, /functions\/v1\/cad_convert/, 'customer_api calls the paid raster converter again');
  // Review of #967: the edge dies (546) near 150k segments, so the cap is 120k and a denser drawing goes to the worker.
  assert.ok(read('supabase/functions/_shared/cad_render.ts').includes('export const RENDER_MAX_SEGMENTS = 120_000;'), 'the edge render cap moved');
  assert.equal((api.match(/reason === 'cad_render_too_dense' && path/g) || []).length, 2, 'a too-dense CAD drawing is not queued for the worker on both paths');
  // Second review of #967: a sheet drawn one glyph per TEXT is held, and a short word passes only from a closed list.
  const render = read('supabase/functions/_shared/cad_render.ts');
  assert.ok(render.includes('export const GLYPH_MAX = 20, GLYPH_SHARE = 0.3;') && render.includes("reason: 'glyph_per_text'"), 'a glyph-per-TEXT sheet is no longer held');
  assert.ok(read('supabase/functions/_shared/drawing_vocabulary.ts').includes('if (l.length <= 3) return CODES.has(l) || WORDS.has(l);'), 'short words are no longer limited to the closed list');
});

test('drawing_redact draws, uploads, records, and removes the upload when the record fails', () => {
  assert.match(redact, /if \(body\.mode === 'cad'\)/);
  assert.match(redact, /await cadPage\(b64ToBytes\(body\.original_b64\), seeds\)/);
  const publish = between(redact, 'async function publish(', 'Deno.serve(');
  assert.match(publish, /const recorded = await recordRun\(id, body, o\)/);
  assert.match(publish, /if \(!recorded && o\.paths\.length\)[\s\S]{0,200}\.remove\(o\.paths\)/, 'an unrecorded run leaves its pages behind');
  assert.doesNotMatch(redact.slice(redact.indexOf('Deno.serve(')), /await recordRun\(/, 'a run is recorded without the orphan clean-up');
  assert.match(redact, /if \(await modelHeld\(admin\)\)/, 'the model path asks a held model instead of saying it is held');
  assert.match(page, /export async function cadPage\([\s\S]{0,900}renderCadForSupplier\(/);
  assert.match(page, /export async function serverBoxedPage\([\s\S]{0,700}supplierPageReadable\(/, 'a page the server cannot read is no longer held');
});

test('the CAD worker draws what the edge cannot, records it, and raises a job that fails for good', () => {
  assert.match(worker, /await cadPage\(bytes, seeds, \{ maxDwgBytes: Infinity/);
  assert.match(worker, /insert into public\.drawing_redaction_runs[\s\S]{0,600}'complete'/);
  // 28 Sep 2026 (#1056): the drawn page is published first and a failed publish is returned as it is; the
  // anonymised drawing FILE is attached beside it only when its verifier passed, and a held file never loses the page.
  assert.match(worker, /const out = await publishPages\(job, key, \[page\.jpg\], \{ method: 'cad_render'[\s\S]{0,120}if \(out\.redaction_complete !== true\) return out;/);
  assert.match(worker, /const f = await anonymisedDrawingFile\([\s\S]{0,80}if \(!f\.ok\) \{[\s\S]{0,160}?return out; \}/, 'an unproved drawing file is no longer left out');
  assert.match(worker, /fn_it_engineer_finding_upsert\(\s*'cad_read_worker:job_failed'/);
  assert.match(worker, /if \(job\.attempts >= 3\) await raiseFailed\(job, msg\)/);
  const status = between(api, "action === 'cad_read_status'", "action === 'analyze_boq'");
  assert.match(status, /drawing_redacted_paths: pages/, 'the worker\'s drawn page never reaches the customer');
});

test('the drawing journeys run every night, and the pixel proof runs on every push', () => {
  // Review of #967: the journeys ran AFTER the report, so a failure reached nobody. They now run before it, and
  // their results are written into the run's steps.json (journey 'f-...', owned by the sales engineer).
  const drawings = nightly.indexOf('run: node scripts/e2e/drawing_journeys_into_report.mjs e2e-out');
  const report = nightly.indexOf('run: node scripts/e2e/report_to_it_engineer.mjs e2e-out');
  assert.ok(drawings > 0 && report > drawings, 'the drawing journeys do not run before the nightly report');
  const runner = read('scripts/e2e/drawing_journeys_into_report.mjs');
  for (const s of ['drawing_reaches_suppliers.mjs', 'cad_identity_reaches_no_supplier.mjs', 'every_drawing_format_is_read.mjs']) assert.ok(runner.includes(`'${s}'`), `${s} is not walked`);
  assert.ok(read('scripts/e2e/cad_identity_reaches_no_supplier.mjs').includes('matched.every((m) => m.is_demo === true)'), 'the CAD journey no longer proves it matched only demo suppliers');
  assert.match(checks, /--allow-net=deno\.land\s+supabase\/functions\/_shared\/drawing_redact_page\.check\.ts/);
});

test('a drawing journey\'s lines become report steps the sales engineer owns; a silent crash is a failure', async () => {
  const { stepsOf } = await import('../e2e/drawing_journeys_into_report.mjs');
  const out = stepsOf('cad_identity_reaches_no_supplier.mjs', 'PASS  read the DXF - 3 lines\nFAIL  no name from the file - ["ORBIT"]\nINFO  x', 1);
  assert.deepEqual(out.map((s) => [s.journey[0], s.status]), [['f', 'PASS'], ['f', 'FAIL']]);
  const dead = stepsOf('every_drawing_format_is_read.mjs', 'Error: boom', 1);
  assert.equal(dead.length, 1); assert.equal(dead[0].status, 'FAIL');
});

test('the CAD journeys expect the preview page AND the anonymised file #1056 records beside it', async () => {
  // Nightly 18 Oct 2026: both CAD journeys failed "one recorded page" on a correct run (redaction_complete true,
  // 2 paths: <prefix>_p0.jpg + <prefix>_drawing.dxf). redactCad pushes the file path after the preview.
  assert.match(between(api, 'async function redactCad(', 'async function redactFile('), /if \(f\) \{ redacted\.push\(f\.path\)/, 'the anonymised file no longer rides beside the preview; revisit cad_redacted_paths.mjs');
  const { cadRedactionShape } = await import('../e2e/cad_redacted_paths.mjs');
  assert.ok(cadRedactionShape(['redacted/a_p0.jpg', 'redacted/a_drawing.dxf']).ok, 'preview + anonymised file is the correct shape');
  assert.ok(cadRedactionShape(['redacted/a_p0.jpg']).ok, 'a preview whose file was held is still correct');
  assert.ok(cadRedactionShape(['https://x/redacted/a_p0.jpg?token=t', 'https://x/redacted/a_drawing.dxf?token=t']).ok, 'signed inbox URLs');
  for (const bad of [[], ['redacted/a_drawing.dxf'], ['redacted/a_p0.jpg', 'redacted/a_p1.jpg'], ['redacted/a_p0.jpg', 'redacted/orig.dwg']]) assert.equal(cadRedactionShape(bad).ok, false, JSON.stringify(bad));
  for (const j of ['cad_identity_reaches_no_supplier.mjs', 'every_drawing_format_is_read.mjs']) {
    const s = read('scripts/e2e/' + j);
    assert.ok(s.includes('cadRedactionShape('), `${j} does not use cadRedactionShape`);
    assert.doesNotMatch(s, /(drawing_redacted_paths \|\| \[\]\)|pages|drawing_pages)\.length === 1/, `${j} expects exactly one CAD path again`);
  }
});
