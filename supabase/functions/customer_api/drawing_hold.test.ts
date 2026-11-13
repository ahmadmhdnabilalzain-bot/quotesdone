// A drawing whose redaction is not verified never reaches a supplier, and the customer is told.
// Assigned: sales_engineer. Customer audit 21 Sep 2026, finding 9.
//
//   deno test --allow-read --allow-env supabase/functions/customer_api/drawing_hold.test.ts
//
// What is proved, in the order analyze_drawing runs it:
//   1. The DETERMINISTIC path runs first and without any model: a PDF whose title block carries a
//      phone number is boxed by the server (titleBlockBoxes + supplierBoxes), so drawing_redact takes
//      its manual path and the gateway is never asked.
//   2. When the server cannot box the sheet (no title block found) the model is asked; if the gateway
//      refuses, the run comes back with no pages and drawingHandoff HOLDS the drawing: no redacted
//      paths, share_redacted:false, drawing_held:true, and a 'held' ledger row against the original.
//   3. A PARTIAL run (some pages verified) is held the same way — all or nothing.
//   4. A complete run passes its paths through untouched.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { pdfPages } from '../_shared/pdf_text_positions.ts';
import { seedTerms, titleBlockBoxes } from '../_shared/anonymise.ts';
import { supplierBoxes } from '../_shared/supplier_copy.ts';
import { cadNote, drawingHandoff, heldRun } from './drawing_hold.ts';
// The function is index.ts plus its modules (9 Nov 2026 split): read all of it, as the node checks do.
import { functionSource } from '../../../scripts/lib/function_sources.mjs';

const SEEDS = seedTerms({ name: 'ZZ DEMO Customer', email: 'zzdemo@example.invalid', phone: '+971 50 000 0001' });
const ORIGINAL = 'drawings/00000000-0000-0000-0000-000000000000/1_zz_demo_drawing.pdf';

function makePdf(lines: [number, number, string][]): Uint8Array {
  const content = lines.map(([x, y, t]) => `BT /F1 9 Tf 1 0 0 1 ${x} ${y} Tm (${t}) Tj ET`).join('\n');
  const objs = ['<< /Type /Catalog /Pages 2 0 R >>', '<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 1000 700] >>',
    '<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>', `<< /Length ${content.length} >>\nstream\n${content}\nendstream`];
  let pdf = '%PDF-1.4\n';
  objs.forEach((o, i) => { pdf += `${i + 1} 0 obj\n${o}\nendobj\n`; });
  return Uint8Array.from(pdf + 'trailer << /Root 1 0 R >>\n%%EOF\n', (c) => c.charCodeAt(0) & 0xff);
}

Deno.test('1. a phone number in a title block is boxed by code before any model is asked', async () => {
  const pages = await pdfPages(makePdf([
    [80, 600, 'GROUND FLOOR PLAN 1:100'],
    [760, 110, 'CLIENT: ZZ DEMO Customer'], [760, 95, 'PROJECT: ZZ DEMO Villa'], [760, 80, 'Tel +971 50 000 0001'], [760, 65, 'DRAWING NO. A-101 REV 2'],
  ]));
  const tb = titleBlockBoxes(pages, SEEDS);
  assertEquals(tb.confidence, 'medium');
  const boxes = supplierBoxes(tb, null, pages.length);
  assert(boxes && boxes[0].length > 0, 'the server sends its own boxes: drawing_redact takes the manual path, no gateway call');
  const phone = pages[0].runs.find((r) => /0001/.test(r.text))!;
  assert(boxes![0].some((b) => b.x <= phone.x + 0.002 && b.y <= phone.y + 0.002 && b.x + b.w >= phone.x + phone.w - 0.002 && b.y + b.h >= phone.y + phone.h - 0.002), 'the phone run is inside a box');
});

Deno.test('2. no title block found -> model asked -> gateway refused -> the drawing is HELD, nothing offered', async () => {
  const pages = await pdfPages(makePdf([[80, 600, 'GROUND FLOOR PLAN'], [80, 580, 'Tel +971 50 000 0001']]));
  assertEquals(supplierBoxes(titleBlockBoxes(pages, SEEDS), null, 1), null, 'no server boxes: customer_api sends none and drawing_redact tries the model');
  // drawing_redact under a refused gateway: detect_failed, pages_in 1, pages_out 0 (measured 21 Sep 2026).
  const meta = { redaction_pages_in: 1, redaction_pages_out: 0, redaction_complete: false };
  const hand = drawingHandoff(meta, ORIGINAL, []);
  assertEquals(hand.drawing_redacted_paths, []);
  assertEquals(hand.drawing_held, true);
  assertEquals(hand.share_redacted, false);
  const row = heldRun({ customerId: 'c', email: 'zzdemo@example.invalid', sourcePath: ORIGINAL, meta, reason: 'no_server_boxes_and_model_refused' });
  assertEquals(row.status, 'held');
  assertEquals(row.output_paths, []);
  assertEquals(row.source_path, ORIGINAL);
});

Deno.test('3. a partial run is held too: no page of it is offered', () => {
  const hand = drawingHandoff({ redaction_pages_in: 4, redaction_pages_out: 3, redaction_complete: false }, ORIGINAL, ['redacted/x/page_p0.jpg', 'redacted/x/page_p1.jpg', 'redacted/x/page_p2.jpg']);
  assertEquals(hand.drawing_redacted_paths, []);
  assertEquals(hand.drawing_held, true);
  assertEquals(hand.share_redacted, false);
});

Deno.test('4. a complete run passes its paths through and is not held', () => {
  const hand = drawingHandoff({ redaction_pages_in: 2, redaction_pages_out: 2, redaction_complete: true }, ORIGINAL, ['redacted/x/page_p0.jpg', 'redacted/x/page_p1.jpg']);
  assertEquals(hand.drawing_redacted_paths.length, 2);
  assertEquals(hand.drawing_held, false);
  assert(!('share_redacted' in hand));
});

Deno.test('no original stored (nothing to hold) is not reported as held', () => {
  assertEquals(drawingHandoff({ redaction_pages_in: 0, redaction_pages_out: 0, redaction_complete: false }, null, []).drawing_held, false);
});

// 5. A DWG THAT cad_convert PICTURED (production, 22 Sep 2026: sample_2000.dwg answered HTTP 200, 3 lines,
// no note - the pictured path's answer never said the CAD file was held). Replays that input's outcome:
// one CAD raster sent, none verified (no text layer, so no server boxes) -> held AND the note.
Deno.test('5. a pictured CAD original that is held says cad_read_not_pictured, on the pictured path too', async () => {
  const CAD = 'drawings/00000000-0000-0000-0000-000000000000/1_zz_demo_small.dwg';
  const hand = drawingHandoff({ redaction_pages_in: 1, redaction_pages_out: 0, redaction_complete: false }, CAD, []);
  assertEquals({ ...hand, ...cadNote(true, hand) }, { drawing_redacted_paths: [], drawing_held: true, share_redacted: false, note: 'cad_read_not_pictured' });
  // A PDF is never given the CAD note, and a fully verified picture set is not called unpictured.
  assertEquals(cadNote(false, hand), {});
  assertEquals(cadNote(true, drawingHandoff({ redaction_pages_in: 1, redaction_pages_out: 1, redaction_complete: true }, CAD, ['redacted/x/page_p0.jpg'])), {});
  // The pictured path's final answer must carry it (the call site was what was missing).
  const src = functionSource('customer_api');
  const finalAnswer = src.split('\n').find((l) => /return J\(\{ ok: true, boq: boqOut, drawing_file_path: path/.test(l)) || '';
  assert(/\.\.\.cadNote\(isCad/.test(finalAnswer), "analyze_drawing's pictured answer does not spread cadNote");
});

// Review of #1838 (3 Nov 2026): the anonymised FILE held for an image straddling the title block was silent.
Deno.test('a held anonymised file is said to the customer, in English and Arabic, with what to do', async () => {
  const { fileHeldNote } = await import('./drawing_hold.ts');
  assertEquals(fileHeldNote(null), {});
  const n = fileHeldNote('image_straddles_title_block') as { drawing_file_held: string; drawing_file_message: { en: string; ar: string } };
  assertEquals(n.drawing_file_held, 'image_straddles_title_block');
  assert(/title block/.test(n.drawing_file_message.en) && /upload the drawing again/.test(n.drawing_file_message.en));
  assert(/إطار العنوان/.test(n.drawing_file_message.ar));
  assert((fileHeldNote('title_block_not_confident') as { drawing_file_message: { en: string } }).drawing_file_message.en.includes('not shared'));
  // Second review of #1838: the note was unit-tested and its CALL SITE was not, the same gap test 5 closed for cadNote.
  // analyze_drawing's final answer spreads fileHeldNote(fileHeld), and fileHeld is set from the anonymiser's `held`.
  const src = functionSource('customer_api');
  const finalAnswer = src.split('\n').find((l) => /return J\(\{ ok: true, boq: boqOut, drawing_file_path: path/.test(l)) || '';
  assert(/\.\.\.fileHeldNote\(fileHeld\)/.test(finalAnswer), "analyze_drawing's final answer does not spread fileHeldNote(fileHeld)");
  assert(/fileHeld = f\.held/.test(src), 'fileHeld is never set from the anonymised file result');
});

// Round 3 of the anonymity fix (13 Nov 2026): drawing_redact answered customer_message when the pixel gate held a page
// for the set's budget, and customer_api dropped it, so the customer saw only the general "held" text.
Deno.test('a set past what the model check may spend is said to the customer in plain words, on the picture, CAD and file routes', async () => {
  const { budgetNote, fileHeldNote } = await import('./drawing_hold.ts');
  const { PIXEL_BUDGET_MESSAGE } = await import('../_shared/drawing_pixel_gate.ts');
  assertEquals(budgetNote(false), {});
  assertEquals(budgetNote(true), { drawing_held_reason: 'pixels_budget', drawing_held_message: PIXEL_BUDGET_MESSAGE });
  assertEquals((fileHeldNote('pixels_budget') as { drawing_file_message: unknown }).drawing_file_message, PIXEL_BUDGET_MESSAGE);
  assert(/Too many large sheets to check today/.test(PIXEL_BUDGET_MESSAGE.en) && PIXEL_BUDGET_MESSAGE.ar.length > 20);
  const src = functionSource('customer_api');
  assert(/if \(rj\?\.customer_message\) budgetHit = true;/.test(src), 'the picture route reads customer_message');
  assert(/const redMeta = \{[^\n]*\.\.\.budgetNote\(budgetHit\)/.test(src), 'the redaction answer does not carry budgetNote(budgetHit)');
  const finalAnswer = src.split('\n').find((l) => /return J\(\{ ok: true, boq: boqOut, drawing_file_path: path/.test(l)) || '';
  assert(/\.\.\.redMeta,/.test(finalAnswer), "analyze_drawing's final answer does not spread redMeta");
  assert(/budgetNote\(cadRed\?\.reason === 'pixels_budget'\)/.test(src), 'the CAD route does not say the budget hold');
});
