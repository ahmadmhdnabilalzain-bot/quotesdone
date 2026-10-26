// A CAD upload reaches the CAD reader (22 Sep 2026, sales_engineer; founder instructions 31, 63, 64).
//
// MEASURED. doc_read gained a DWG reader (LibreDWG -> the DXF take-off), and the portal sends a .dwg to
// customer_api analyze_drawing (NewRequest.tsx: only DOC_RE files go to analyze_document, and .dwg is not
// in it). analyze_drawing handed drawing_boq the RASTERISED sheets and never the file, so the reader had
// no entry point: a finished capability no customer could reach. This check fails if that returns:
//   * a CAD original must be sent to drawing_boq's 'document' mode (the mode that runs doc_read), both
//     when the sheet was pictured and when it could not be;
//   * a .dwg must still be routed by the portal to one of the two paths that do this.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';

const api = readFileSync(new URL('../../supabase/functions/customer_api/index.ts', import.meta.url), 'utf8');
const portal = readFileSync(new URL('../../src/components/me/NewRequest.tsx', import.meta.url), 'utf8');
const block = api.slice(api.indexOf("action === 'analyze_drawing'"), api.indexOf("action === 'create_inquiry'"));

test('analyze_drawing sends a CAD original to the reader, pictured or not', () => {
  assert.ok(block.length > 1000, 'the analyze_drawing block was not found');
  const toReader = block.match(/isCad && body\.original_b64[\s\S]{0,900}?mode: 'document', file_b64: body\.original_b64/g) || [];
  assert.ok(toReader.length >= 2, `CAD originals must reach drawing_boq mode 'document' on both paths; found ${toReader.length}`);
});

test('the portal routes a .dwg to analyze_drawing or analyze_document', () => {
  const src = (name) => (portal.match(new RegExp(`const ${name} = (\\/.*\\/[a-z]*);`)) || [])[1];
  const re = (s) => new RegExp(s.slice(1, s.lastIndexOf('/')), s.slice(s.lastIndexOf('/') + 1));   // the portal's own pattern
  const doc = src('DOC_RE'), refused = src('REFUSED_DRAWING_RE');
  assert.ok(doc && refused, 'DOC_RE / REFUSED_DRAWING_RE not found in NewRequest.tsx');
  assert.ok(!re(refused).test('plan.dwg'), 'a .dwg must not be refused');
  const toDocument = re(doc).test('plan.dwg');
  const toDrawing = /onAny = \(f\) => \([^\n]*DOC_RE\.test\(f\.name\) \? onBoq\(f\) : onFile\(f\)\)/.test(portal) && /action: 'analyze_drawing'/.test(portal);
  assert.ok(toDocument || toDrawing, 'a .dwg reaches neither analyze_document nor analyze_drawing');
});

// 22 Sep 2026 (founder: "customer will share cad files or pdf mainly"). A DWG the edge cannot read -
// past dwg.ts's ceiling, or its drawing_boq worker killed (546; on production every DWG died that way
// until the memory floor was lowered) - must be QUEUED for the CAD worker on both CAD paths, never
// dropped, and the customer's screen must be able to fetch the result. This fails if that returns.
const worker = readFileSync(new URL('../../.github/workflows/cad-read-worker.yml', import.meta.url), 'utf8');
const workerTs = readFileSync(new URL('../cad_read_worker.ts', import.meta.url), 'utf8');

test('a CAD drawing the edge cannot read is queued on both paths, and 546 counts as cannot', () => {
  const queued = block.match(/cadQueueReason\([^)]*\)[\s\S]{0,300}?queueCadRead\(/g) || [];
  assert.ok(queued.length >= 2, `both CAD paths must queue; found ${queued.length}`);
  const reason = api.slice(api.indexOf('function cadQueueReason'), api.indexOf('async function queueCadRead'));
  assert.match(reason, /status === 546/);
  assert.match(reason, /over_edge_ceiling/);
});

test('the queue has a worker, a queued job is held for the sales_engineer, and the status is the owner\'s only', () => {
  assert.match(worker, /scripts\/cad_read_worker\.ts/);
  assert.match(workerTs, /fn_cad_read_claim\(/);
  assert.match(workerTs, /readDwg\(bytes, ctx, Infinity\)/);
  const status = api.slice(api.indexOf("action === 'cad_read_status'"), api.indexOf("action === 'analyze_boq'"));
  assert.match(status, /\.eq\('customer_id', cust\.id\)/);
  // 27 Oct 2026: GitHub Actions is off, so nothing starts the worker. A queued job raises the hour's
  // sales_engineer finding at once (one per hour: the worker reads every queued job in one run), and a polled open job tells the screen who holds it.
  const queue = api.slice(api.indexOf('async function queueCadRead'), api.indexOf('async function cadReadHeld'));
  assert.match(queue, /await cadReadHeld\(String\(data\.id\), o\.why\)/);
  const held = api.slice(api.indexOf('async function cadReadHeld'), api.indexOf('// A CAD DRAWING IS DRAWN FOR SUPPLIERS'));
  assert.match(held, /fn_it_engineer_finding_upsert[\s\S]{0,200}sales_engineer:cad_read_held:' \+ new Date\(\)\.toISOString\(\)\.slice\(0, 13\)[\s\S]{0,800}p_raised_by: 'sales_engineer'/);
  assert.match(held, /if \(error\) console\.error\(/, 'a finding that was not written is said, never swallowed');
  assert.match(status, /held_for: 'sales_engineer'/);
});

test('a PDF set whose lengths call dies is queued with its counted take-off, and the worker merges them', () => {
  assert.match(block, /lr\.status === 546[\s\S]{0,200}queueCadRead\([\s\S]{0,300}why: 'pdf_lengths_worker_died', boqIn: boqOut/);
  assert.match(workerTs, /job\.boq_in[\s\S]{0,200}lengthsInto\(job\.boq_in, bytes\)/);
  assert.match(portal, /res\.note === 'lengths_queued'[\s\S]{0,80}pollCad\(res, file\.name, source, true\)/);
});

// Founder ruling 1000: drawings are accepted as PDF and CAD (DWG/DXF) only; Revit, IFC and DGN are refused.
test('the portal refuses Revit, IFC and DGN, accepts DWG/DXF and polls a queued CAD read', () => {
  const refused = new RegExp(portal.match(/const REFUSED_DRAWING_RE = \/(.*)\/i;/)[1], 'i');
  for (const f of ['m.rvt', 'm.rfa', 'm.ifc', 'm.dgn']) assert.ok(refused.test(f), `${f} must be refused`);
  for (const f of ['m.dwg', 'm.dxf', 'm.pdf']) assert.ok(!refused.test(f), `${f} must not be refused`);
  assert.match(portal, /onAny = \(f\) => \(f && REFUSED_DRAWING_RE\.test\(f\.name\) \? refuseDrawing\(\)/);
  const accept = portal.match(/ref=\{fileRef\} type="file" accept="([^"]*)"/)[1];
  assert.match(accept, /\.dwg/);
  assert.match(accept, /\.dxf/);
  assert.doesNotMatch(accept, /\.(rvt|ifc|dgn)\b/);
  assert.match(portal, /action: 'cad_read_status'/);
});

// 27 Oct 2026: a dispatch to a GitHub workflow while Actions is off reaches nothing, and the job it was meant
// to start waits forever. No edge function may hand work to a GitHub workflow.
test('no edge function dispatches a GitHub workflow', () => {
  const dir = new URL('../../supabase/functions/', import.meta.url);
  const hits = [];
  for (const f of readdirSync(dir, { recursive: true })) {
    if (!/\.ts$/.test(String(f))) continue;
    const src = readFileSync(new URL(String(f).replace(/\\/g, '/'), dir), 'utf8');
    if (/api\.github\.com\/repos\/[^'"`\s]*\/(actions\/workflows\/[^'"`\s]*\/dispatches|dispatches)/.test(src)) hits.push(String(f));
  }
  assert.deepEqual(hits, [], 'these edge functions dispatch a GitHub workflow, which does not run: ' + hits.join(', '));
});
