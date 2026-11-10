// What may be written for suppliers from a request's drawing, decided at Send (./drawing_send_gate.ts). sales_engineer,
// 10 Nov 2026 - evidence run ea40c830. create_inquiry stores the BOQ the BROWSER sends; on main it ran redactBoq with the
// customer's account terms only, and copied the open lines into spec.boq_check (supplier-facing) before even that.
//   deno test --no-lock --allow-read supabase/functions/customer_api/drawing_send_gate.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { pdfPages } from '../_shared/pdf_text_positions.ts';
import { setIdentityTerms } from '../_shared/drawing_identity_gate.ts';
import { boqOf, hvacSheetPdf, IDENTITY_LINES, LIVE_OCR_LINES } from '../_shared/drawing_identity_ocr_misread.fixtures.ts';
import { gateAtSend } from './drawing_send_gate.ts';

const TERMS = setIdentityTerms(await pdfPages(hvacSheetPdf(), undefined, { layers: false }));
const SRC = await Deno.readTextFile(new URL('./actions/inquiry_create.ts', import.meta.url));
const LIB = await Deno.readTextFile(new URL('./lib/drawings.ts', import.meta.url));

Deno.test('the OCR take-off the browser sends reaches suppliers without the title block', () => {
  const g = gateAtSend(boqOf(LIVE_OCR_LINES), TERMS, 'drawing');
  assertEquals(g.held, null);
  assertEquals(g.dropped_lines, IDENTITY_LINES.length);
  const out = JSON.stringify(g.boq);
  for (const bad of ['Demo Owner', '22 Demo', 'DEMO FIXTURE']) assert(!out.includes(bad), `${bad} reached the supplier copy`);
});

Deno.test('lines read from a drawing that cannot be read back are held; a BOQ sheet of the customer is not', () => {
  assertEquals(gateAtSend(boqOf(LIVE_OCR_LINES), null, 'drawing'), { boq: null, held: 'drawing_unreadable', dropped_lines: 0 });
  const sheet = boqOf(['Ducted split unit 3.0 TR, inverter, concealed', 'GI ductwork with 25 mm thermal insulation, to SMACNA']);
  assertEquals(gateAtSend(sheet, null, 'boq').held, null);
  assertEquals(gateAtSend(null, TERMS, 'drawing'), { boq: null, held: null, dropped_lines: 0 });
});

Deno.test('a misread name outside the lines holds the whole take-off; one written out is painted', () => {
  const g = gateAtSend({ ...boqOf(['Copper refrigerant piping with insulation']), summary: 'Take-off of the drawing for Mir. 22 Demo Owner' }, TERMS, 'drawing');
  assertEquals(g.boq, null); assertEquals(g.held, 'identity_left');
  const w = gateAtSend({ ...boqOf(['Copper refrigerant piping with insulation']), summary: 'Take-off of the drawing for Mr. ZZ Demo Owner' }, TERMS, 'drawing');
  assert(w.boq && !JSON.stringify(w.boq).includes('Demo Owner'), 'a name written out is redacted and the take-off kept');
});

Deno.test('create_inquiry gates the BOQ before the open lines, redactBoq and the first insert, from the stored file', () => {
  const gate = SRC.indexOf('gateAtSend(boqObj, at.terms, briefSource)');
  assert(gate > 0, 'create_inquiry no longer calls gateAtSend on the BOQ');
  assert(SRC.indexOf('await storedDrawingTerms(drawingPath)') > 0 && SRC.indexOf('await storedDrawingTerms(drawingPath)') < gate, 'the terms are read from the stored drawing, before the gate');
  for (const later of ['const open = openLines(boqObj.boq);', 'const gate = redactBoq(boqObj, seeds);', ".from('inquiries').insert("]) {
    const at = SRC.indexOf(later);
    assert(at > gate, `${later} must come after the send gate`);
  }
});

Deno.test('a held drawing, and a held or trimmed take-off, is the sales engineer\'s finding', () => {
  const held = LIB.slice(LIB.indexOf('export async function recordHeld'), LIB.indexOf('const FINDING_TITLE'));
  assert(/await drawingIdentityFinding\('drawing_held'/.test(held), 'recordHeld raises the drawing_held finding');
  for (const kind of ['boq_held', 'boq_identity_dropped', 'sent_without_drawing']) assert(SRC.includes(`drawingIdentityFinding('${kind}'`), `create_inquiry raises ${kind}`);
  assert(/p_raised_by: 'sales_engineer'/.test(LIB.slice(LIB.indexOf('export async function drawingIdentityFinding'))));
});
