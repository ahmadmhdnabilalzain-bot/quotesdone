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
