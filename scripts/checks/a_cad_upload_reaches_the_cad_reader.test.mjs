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
import { readFileSync } from 'node:fs';

const api = readFileSync(new URL('../../supabase/functions/customer_api/index.ts', import.meta.url), 'utf8');
const portal = readFileSync(new URL('../../src/components/me/NewRequest.tsx', import.meta.url), 'utf8');
const block = api.slice(api.indexOf("action === 'analyze_drawing'"), api.indexOf("action === 'create_inquiry'"));

test('analyze_drawing sends a CAD original to the reader, pictured or not', () => {
  assert.ok(block.length > 1000, 'the analyze_drawing block was not found');
  const toReader = block.match(/isCad && body\.original_b64[\s\S]{0,900}?mode: 'document', file_b64: body\.original_b64/g) || [];
  assert.ok(toReader.length >= 2, `CAD originals must reach drawing_boq mode 'document' on both paths; found ${toReader.length}`);
});

test('the portal routes a .dwg to analyze_drawing or analyze_document', () => {
  const doc = (portal.match(/const DOC_RE = (\/.*\/[a-z]*);/) || [])[1];
  assert.ok(doc, 'DOC_RE not found in NewRequest.tsx');
  const docRe = new RegExp(doc.slice(1, doc.lastIndexOf('/')), doc.slice(doc.lastIndexOf('/') + 1));   // the portal's own pattern
  const toDocument = docRe.test('plan.dwg');
  const toDrawing = /onAny = \(f\) => \(f && DOC_RE\.test\(f\.name\) \? onBoq\(f\) : onFile\(f\)\)/.test(portal) && /action: 'analyze_drawing'/.test(portal);
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

test('the queue has a worker, the dispatch names it, and the status is the owner\'s only', () => {
  assert.ok(api.includes('/actions/workflows/cad-read-worker.yml/dispatches'), 'customer_api dispatches the CAD worker workflow');
  assert.match(worker, /workflow_dispatch/);
  assert.match(worker, /schedule:/);
  assert.match(worker, /scripts\/cad_read_worker\.ts/);
  assert.match(workerTs, /fn_cad_read_claim\(/);
  assert.match(workerTs, /readDwg\(bytes, ctx, Infinity\)/);
  const status = api.slice(api.indexOf("action === 'cad_read_status'"), api.indexOf("action === 'analyze_boq'"));
  assert.match(status, /\.eq\('customer_id', cust\.id\)/);
  // The queue triggers the worker: a polled job that has not started is dispatched again.
  assert.match(status, /cadJobNeedsRedispatch\([^)]*\)\) await dispatchCadWorker\(id\)/);
});

test('a PDF set whose lengths call dies is queued with its counted take-off, and the worker merges them', () => {
  assert.match(block, /lr\.status === 546[\s\S]{0,200}queueCadRead\([\s\S]{0,300}why: 'pdf_lengths_worker_died', boqIn: boqOut/);
  assert.match(workerTs, /job\.boq_in[\s\S]{0,200}lengthsInto\(job\.boq_in, bytes\)/);
  assert.match(portal, /res\.note === 'lengths_queued'[\s\S]{0,80}pollCad\(res, file\.name, source, true\)/);
});

test('the portal accepts Revit and DGN and polls a queued CAD read', () => {
  assert.match(portal, /accept="[^"]*\.rvt[^"]*\.dgn/);
  assert.match(portal, /action: 'cad_read_status'/);
});
