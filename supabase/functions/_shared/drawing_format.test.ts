// Founder ruling 28 Sep 2026: a customer's drawing is PDF or CAD (DWG/DXF) only. Assigned: sales_engineer.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { DRAWING_FORMAT_ERROR, DRAWING_FORMAT_MESSAGE, drawingFormatRefusal } from './drawing_format.ts';
import { readDocument } from './doc_read/index.ts';

Deno.test('an .rvt / .rfa / .ifc / .dgn upload is refused with the message, in English and Arabic', () => {
  for (const n of ['tower.rvt', 'door.rfa', 'model.IFC', 'site.dgn', 'plan.dwf', 'shed.skp']) {
    const r = drawingFormatRefusal(n, '');
    assert(r, n);
    assertEquals(r.error, DRAWING_FORMAT_ERROR);
    assertEquals(r.message, 'Please upload your drawing as PDF or CAD (DWG/DXF).');
    assert(/PDF/.test(r.message_ar) && /DWG\/DXF/.test(r.message_ar));
  }
  assert(drawingFormatRefusal('x.bin', 'application/vnd.autodesk.revit'));
});

Deno.test('.pdf, .dwg and .dxf are accepted, and a BOQ spreadsheet is not a drawing', () => {
  for (const [n, m] of [['a.pdf', 'application/pdf'], ['b.dwg', 'image/vnd.dwg'], ['c.dxf', 'image/vnd.dxf'], ['boq.xlsx', ''], ['boq.csv', 'text/csv']])
    assertEquals(drawingFormatRefusal(n, m), null, n);
});

// The server decides on the SNIFFED type too: an IFC renamed .txt is refused on the customer path with the
// ruling's message. The IFC reader is deleted (#1022), so without the flag it is a plain file_type_not_allowed.
const IFC = new TextEncoder().encode("ISO-10303-21;\nHEADER;\nFILE_SCHEMA(('IFC4'));\nENDSEC;\nDATA;\nENDSEC;\nEND-ISO-10303-21;\n");
Deno.test('readDocument refuses a renamed IFC when pdfCadDrawingsOnly is set', async () => {
  const r = await readDocument(IFC, 'notes.txt', '', 0, { pdfCadDrawingsOnly: true });
  assertEquals(r.ok, false);
  assertEquals((r as { error?: string }).error, DRAWING_FORMAT_ERROR);
  assertEquals((r as { detail?: string }).detail, DRAWING_FORMAT_MESSAGE);
  const internal = await readDocument(IFC, 'notes.txt');
  assert((internal as { error?: string }).error !== DRAWING_FORMAT_ERROR);
});

Deno.test('readDocument does not refuse a DXF on the customer path', async () => {
  const dxf = new TextEncoder().encode('0\nSECTION\n2\nENTITIES\n0\nLINE\n8\n0\n10\n0\n20\n0\n11\n1\n21\n0\n0\nENDSEC\n0\nEOF\n');
  const r = await readDocument(dxf, 'plan.dxf', '', 0, { pdfCadDrawingsOnly: true });
  assert((r as { error?: string }).error !== DRAWING_FORMAT_ERROR);
});
