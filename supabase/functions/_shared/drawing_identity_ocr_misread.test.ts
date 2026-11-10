// A misread name is still the name: the take-off of a drawing read by OCR loses every line carrying a title-block term.
// sales_engineer, 10 Nov 2026 - evidence run ea40c830 (docs/reports/2026-11-10-journey-evidence.md, still-seen item 2).
//
// THE SHEET is journey 2's HVAC layout M-101 as the harness drew it, rebuilt here with demoPdf (a real text layer, the same
// title strip: consultant, client, plot, project, drawing number, note), so no binary is committed. THE LINES are the 13
// lines the live run's take-off held after the portal OCR'd the rendered sheet (inquiry_intake brief.boq_check, verbatim;
// "Mir. 22 Demo Owner" is tesseract's reading of "Mr. ZZ Demo Owner"). On main the gate, given the strip's own terms,
// dropped 0 of them: it painted "Owner" and kept "Mir. 22 Demo".
//   deno test --no-lock --allow-read supabase/functions/_shared/drawing_identity_ocr_misread.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { pdfPages } from './pdf_text_positions.ts';
import { foldOcr, gateDrawingBoq, ocrTwins, pdfIdentityTerms, setIdentityTerms } from './drawing_identity_gate.ts';
import { boqOf, hvacSheetPdf, IDENTITY_LINES, LIVE_OCR_LINES } from './drawing_identity_ocr_misread.fixtures.ts';


const PDF = hvacSheetPdf();
const TERMS = setIdentityTerms(await pdfPages(PDF, undefined, { layers: false }));

Deno.test("the sheet's title strip names the client, the consultant and the plot", () => {
  for (const want of ['zz demo owner', 'zz demo mep consultants', 'plot 000 0000']) assert(TERMS.some((x) => x.includes(want)), `${want} not among ${JSON.stringify(TERMS)}`);
});

Deno.test('the client name read as "Mir. 22 Demo Owner" is the client name', () => {
  assertEquals(foldOcr('Mir. 22 Demo Owner').includes(foldOcr('zz demo owner')), true);
  assert(ocrTwins(LIVE_OCR_LINES[0], TERMS).length > 0);
  assertEquals(ocrTwins('DSU-02 | Ducted split unit, inverter | Living / Dining', TERMS), []);
});

Deno.test("the live run's OCR take-off loses exactly the lines that carried the title block", () => {
  const g = gateDrawingBoq(boqOf(LIVE_OCR_LINES), TERMS);
  assert(g.boq, 'the take-off is not withheld: only its identity lines go');
  const kept = (g.boq as ReturnType<typeof boqOf>).boq.map((l) => l.description);
  assertEquals(g.dropped_lines, IDENTITY_LINES.length);
  for (const i of IDENTITY_LINES) assert(!kept.some((k) => k.includes(LIVE_OCR_LINES[i].slice(0, 12))), `line ${i} reached the take-off`);
  for (const k of kept) assert(!/demo\s+owner|22\s*demo|zz\s*demo/i.test(k), `a kept line still carries the title block: ${k}`);
  assertEquals(kept.length, LIVE_OCR_LINES.length - IDENTITY_LINES.length, 'no technical line is lost');
});

Deno.test('the stored file is read for its terms; a file that is not a PDF has none, and an unreadable PDF is null', async () => {
  const r = await pdfIdentityTerms(PDF);
  assertEquals(r.pdf, true); assert(r.words > 0); assert(r.terms && r.terms.some((x) => x.includes('zz demo owner')));
  assertEquals(await pdfIdentityTerms(new TextEncoder().encode('Item,Qty\n1,2')), { pdf: false, words: -1, terms: [] });
  const bad = await pdfIdentityTerms(new TextEncoder().encode('%PDF-1.4 garbage'));
  assert(bad.pdf && (bad.terms === null || bad.words === 0), 'a PDF with no readable text layer yields no title-block term');
});
