// set_before_model — a PDF drawing set whose text layer code can count is counted by code BEFORE the vision model is
// asked (27 Oct 2026, sales_engineer; founder ledger 580). Measured on production that day: with the model on, the
// 8-sheet ZZ DEMO mechanical set came back from the model with 6 lines, two of them doubled and three items missing,
// while boqFromDrawingSet read every item exactly. This fails if the early set path is removed or moved after the key.
//
// And only when code read the set COMPLETELY (independent review, 27 Oct 2026): a set where code reads two EF fans and
// misses the twelve VRF indoor units beside them must still reach the model, or the take-off is under-counted with only
// the confirm step behind it. The floor and the measurement behind it are in drawing_set.ts (countedCompletely).
//   deno test --no-lock --node-modules-dir=auto --allow-read=. supabase/functions/drawing_boq/set_before_model.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { pdfPages } from '../_shared/pdf_text_positions.ts';
import * as drawingSet from './drawing_set.ts';
import { sheetPdf } from './drawing_set.fixtures.ts';
import { benchPdf, pdfFrom } from './bench.fixtures.ts';
import { zzPdfSet } from '../_shared/doc_read/zz_demo_drawings.fixtures.ts';

// 3 Nov 2026: the coded set is still counted BEFORE the key is read, but where the model can read the drawing it no
// longer answers alone: it cross-checks the model's reading (cross_check.ts, cross_check.test.ts). It answers alone
// only with no model input, no key, or a model that is refused or errs.
Deno.test('drawing_boq counts a PDF set by code before it reads the AI key or calls the model', () => {
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  const early = src.indexOf("fallback_reason: 'code_counted_the_set'");
  const key = src.indexOf("const key = await sec('cred_fn_ai');\n    if (codeSet && !key) return codeAnswer();");
  assert(early > 0, 'the early drawing-set path is gone');
  assert(key > 0, 'the model path moved: re-anchor this test on it');
  assert(early < key, 'the drawing set must be tried before the model path');
});

// ── one ZZ DEMO HVAC plan, drawn twice: the same sheet, the same layout, only the indoor units' tag word differs ──
const PW = 2592, PH = 1728;
const t = (a: number, b: number, size: number, s: string) => `BT /F1 ${size} Tf 1 0 0 1 ${(a * PW).toFixed(1)} ${((1 - b) * PH).toFixed(1)} Tm (${s}) Tj ET\n`;
const l = (a1: number, b1: number, a2: number, b2: number) => `${(a1 * PW).toFixed(1)} ${((1 - b1) * PH).toFixed(1)} m ${(a2 * PW).toFixed(1)} ${((1 - b2) * PH).toFixed(1)} l S\n`;
function hvacPlan(unit: string): Uint8Array {
  let s = t(0.30, 0.05, 28, 'FIRST FLOOR PLAN - HVAC') + t(0.30, 0.09, 11, 'SCALE 1:100');
  s += t(0.10, 0.20, 9, 'EF-1') + t(0.20, 0.20, 9, 'EF-2');
  for (let i = 1; i <= 11; i++) s += t(0.08 + ((i - 1) % 6) * 0.12, 0.35 + Math.floor((i - 1) / 6) * 0.15, 9, `${unit}-${i}`);
  s += t(0.70, 0.60, 9, unit) + t(0.7012, 0.6065, 9, '12');                 // the twelfth drawn as a bubble: type over number
  s += l(0.855, 0.02, 0.855, 0.98) + t(0.865, 0.06, 11, 'ZZ DEMO MEP CONSULTANTS') + t(0.865, 0.11, 11, 'PROJECT: ZZ DEMO VILLA') + t(0.90, 0.93, 28, 'M-1.01');
  return pdfFrom([s], { Title: 'ZZ DEMO HVAC' });
}

// deno-lint-ignore no-explicit-any
const early = (drawingSet as any).setBeforeModel as ((pages: unknown[], hint?: string) => { boq: { type: string; qty: number | null }[] } | null) | undefined;

Deno.test('a set where code reads a few tags and misses most goes to the MODEL (coverage floor)', async () => {
  assert(typeof early === 'function', 'no coverage floor: drawing_boq returns any non-empty coded set before the model');
  const pages = await pdfPages(hvacPlan('IDU'), undefined, { layers: false });
  // Code alone does find something here: the two fans. Before the floor, that was the whole answer.
  const coded = drawingSet.boqFromDrawingSet(pages)!;
  assert(coded, 'the fixture must be one code partly reads, or it tests nothing');
  assertEquals(coded.boq.filter((x) => x.type.startsWith('tag:')).map((x) => x.type).sort(), ['tag:EF-1', 'tag:EF-2']);
  assertEquals((coded as unknown as { coverage: unknown }).coverage, { tags_read: 2, tag_like_unread: 12 }, '11 single-run IDU tags and 1 IDU bubble left unread');
  assertEquals(early!(pages), null, 'a partly read set must not answer before the model');
});

Deno.test('a set code reads completely still takes the early path', async () => {
  assert(typeof early === 'function', 'no coverage floor');
  // The paired control: the same sheet with the indoor units tagged FCU, a word the reader knows.
  const fcu = early!(await pdfPages(hvacPlan('FCU'), undefined, { layers: false }));
  assert(fcu, 'a completely read sheet must answer before the model');
  assertEquals(fcu.boq.filter((x) => x.type.startsWith('tag:')).length, 14, 'EF-1, EF-2 and FCU-1..FCU-12');
  // And the repository's drawing fixtures, every one measured at 0 unread tag-shaped runs.
  for (const [name, bytes] of [['drawing_set sheetPdf', sheetPdf()], ['bench benchPdf', benchPdf()], ['zz_demo zzPdfSet', await zzPdfSet()]] as const) {
    assert(early!(await pdfPages(bytes, undefined, { layers: false })), `${name} must still take the early path`);
  }
});

Deno.test('a set with no tag at all has nothing to judge coverage by: it goes to the model, as before the early path', () => {
  assert(typeof drawingSet.countedCompletely === 'function', 'no coverage floor');
  assertEquals(drawingSet.countedCompletely({ coverage: { tags_read: 0, tag_like_unread: 0 } }), false);
  assertEquals(drawingSet.countedCompletely(null), false);
  assertEquals(drawingSet.countedCompletely({ coverage: { tags_read: 5, tag_like_unread: 0 } }), true);
  assertEquals(drawingSet.countedCompletely({ coverage: { tags_read: 40, tag_like_unread: 1 } }), false);
});

Deno.test('index.ts gates the early return on the coverage floor, not on any non-empty set', () => {
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  const at = src.indexOf("fallback_reason: 'code_counted_the_set'");
  const block = src.slice(src.lastIndexOf('if (pdfB64 && body.deterministic !== true)', at), at);
  assert(/const set = setBeforeModel\(/.test(block) && /codeSet = set;/.test(block), 'the early path must call setBeforeModel (boqFromDrawingSet alone has no floor)');
});

// ── independent review of 29dda0b5a (27 Oct 2026): the floor knew only one spelling of a tag ──────────────────────────
// TAG_SHAPE alone let each case below through with 2 of 14 units read, and the set answered before the model: the twelve
// indoor units spelled with a floor code, a space, four digits, a hyphenated or five-letter type, or a dotted number, or
// tagged on a sheet titled LAYOUT (no PLAN in the title, so the take-off skips it). Every tag here is ONE run, so the
// bubble rule of unreadTagLike cannot catch it by accident. With the series rule the repository fixtures above (rooms
// "OFFICE 101" among them) still read 0 unread and take the early path.
function plansOf(sheets: { title: string; tags: string[] }[]): Uint8Array {
  return pdfFrom(sheets.map(({ title, tags }, n) => {
    let s = t(0.30, 0.05, 28, title) + t(0.30, 0.09, 11, 'SCALE 1:100');
    tags.forEach((g, i) => { s += t(0.08 + (i % 6) * 0.12, 0.35 + Math.floor(i / 6) * 0.15, 9, g); });
    return s + l(0.855, 0.02, 0.855, 0.98) + t(0.865, 0.06, 11, 'ZZ DEMO MEP CONSULTANTS') + t(0.90, 0.93, 28, `M-1.0${n + 1}`);
  }), { Title: 'ZZ DEMO HVAC' });
}
const twelve = (f: (i: number) => string) => Array.from({ length: 12 }, (_, i) => f(i + 1));
const PLAN = 'FIRST FLOOR PLAN - HVAC';

Deno.test('every common spelling of an unread tag series sends the set to the model', async () => {
  assert(typeof early === 'function', 'no coverage floor');
  const spellings: [string, (i: number) => string][] = [
    ['a floor code', (i) => `IDU-GF-${String(i).padStart(2, '0')}`], ['a space', (i) => `IDU ${i}`], ['four digits', (i) => `IDU-${1000 + i}`],
    ['a hyphenated type', (i) => `VRF-IDU-${i}`], ['a five-letter type', (i) => `SPLIT-${i}`], ['a dotted number', (i) => `IDU-1.${String(i).padStart(2, '0')}`],
  ];
  for (const [what, f] of spellings) {
    const pages = await pdfPages(plansOf([{ title: PLAN, tags: ['EF-1', 'EF-2', ...twelve(f)] }]), undefined, { layers: false });
    const coded = drawingSet.boqFromDrawingSet(pages)!;
    assertEquals(coded.boq.filter((x) => x.type.startsWith('tag:')).length, 2, `${what}: code reads only the two fans`);
    assertEquals(early!(pages), null, `${what}: 2 of 14 read must not answer before the model`);
  }
});

Deno.test('tags on a sheet the take-off does not count as a plan send the set to the model', async () => {
  assert(typeof early === 'function', 'no coverage floor');
  for (const unit of ['FCU', 'IDU']) {
    const pages = await pdfPages(plansOf([{ title: PLAN, tags: ['EF-1', 'EF-2'] }, { title: 'GROUND FLOOR AC LAYOUT', tags: twelve((i) => `${unit}-${i}`) }]), undefined, { layers: false });
    assertEquals(early!(pages), null, `${unit}-1..12 on a LAYOUT sheet are not counted: the set must reach the model`);
  }
});

Deno.test('a series of sheet references is not an unread tag series', async () => {
  assert(typeof early === 'function', 'no coverage floor');
  const pages = await pdfPages(plansOf([{ title: PLAN, tags: ['EF-1', 'EF-2', 'M-5.01', 'M-5.02', 'M-5.03'] }]), undefined, { layers: false });
  assert(early!(pages), 'detail references are not units: a completely read set must still answer early');
});
