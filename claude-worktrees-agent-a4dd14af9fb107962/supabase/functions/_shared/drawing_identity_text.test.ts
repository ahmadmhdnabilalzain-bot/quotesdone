// drawing_identity_text — proves, on the demo office plan, that the deterministic text-layer
// redaction boxes EVERY identity run in the title block and NONE of the technical content.
//
// Why a real plan and not a two-line fixture: the 21 Sep 2026 audit (finding 3) found the
// founder-demo supplier downloading four empty rectangles as a "redacted drawing". The fixture had
// no text, so nothing could show whether redaction keeps what a supplier needs. This test builds the
// same PDF the demo now uses (scripts/lib/demo_pdf.mjs), reads its text layer with
// pdf_text_positions.pdfPages, and checks the two properties that make a redacted page worth
// sending: the identity is covered, the drawing is not.
// deno test --allow-read supabase/functions/_shared/drawing_identity_text.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { pdfPages } from './pdf_text_positions.ts';
import { textLayerBoxes, type Box } from './drawing_identity_text.ts';
// deno-lint-ignore no-explicit-any
const demo: any = await import('../../../scripts/lib/demo_pdf.mjs');

const pdf = new Uint8Array(demo.demoOfficePlanPdf());
const plan = demo.demoOfficePlan();
const pages = await pdfPages(pdf);
const page = pages[0];
const { boxes, rotated } = textLayerBoxes(pages, 0);

const EPS = 1e-6;
const inside = (r: Box, b: Box) => r.x >= b.x - EPS && r.y >= b.y - EPS && r.x + r.w <= b.x + b.w + EPS && r.y + r.h <= b.y + b.h + EPS;
const overlaps = (a: Box, b: Box) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;

Deno.test('the plan PDF has a readable text layer with every drawn string', () => {
  assertEquals(pages.length, 1);
  assert(!rotated);
  assertEquals(page.runs.length, plan.texts.length);
  for (const t of plan.texts) assert(page.runs.some((r) => r.text === t.text), `run missing: ${t.text}`);
});

Deno.test('every title-block identity run is inside a box', () => {
  const identity: string[] = plan.identity;
  assertEquals(identity.length, 7);
  for (const s of identity) {
    const run = page.runs.find((r) => r.text === s)!;
    assert(run, `no run for ${s}`);
    assert(boxes.some((b) => inside(run, b)), `identity NOT boxed: "${s}"`);
  }
});

Deno.test('no box touches a room name, an area, a dimension, the legend, the scale or the north arrow', () => {
  const technical = plan.texts.filter((t: { kind: string }) => t.kind !== 'identity');
  assert(technical.length >= 30, `only ${technical.length} technical texts`);
  for (const t of technical) {
    const run = page.runs.find((r) => r.text === t.text && Math.abs(r.x - t.x / plan.W) < 1e-3)!;
    assert(run, `no run for ${t.text}`);
    const hit = boxes.find((b) => overlaps(run, b));
    assert(!hit, `technical text boxed: "${t.text}" (${t.kind}) by ${JSON.stringify(hit)}`);
  }
});

Deno.test('the boxes all lie within the title block', () => {
  const tb = plan.titleBlock;
  const tbN: Box = { x: tb.x / plan.W, y: tb.y / plan.H, w: tb.w / plan.W, h: tb.h / plan.H };
  assert(boxes.length >= 7, `only ${boxes.length} boxes`);
  for (const b of boxes) assert(inside(b, tbN), `box outside the title block: ${JSON.stringify(b)}`);
});
