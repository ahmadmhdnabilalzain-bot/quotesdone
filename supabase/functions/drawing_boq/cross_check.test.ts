// cross_check.test — the model's reading of a PDF set is cross-checked by code's complete count (3 Nov 2026).
//   deno test --no-lock --node-modules-dir=auto --allow-read=. supabase/functions/drawing_boq/cross_check.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { crossCheck, crossCheckNotes } from './cross_check.ts';
import { pdfPages } from '../_shared/pdf_text_positions.ts';
import { setBeforeModel } from './drawing_set.ts';
import { zzPdfSheet, PDF_COUNTS } from '../_shared/doc_read/zz_demo_drawings.fixtures.ts';

// The 27 Oct 2026 failure, replayed: the model doubled EF-1 and missed WC/L-1 on a set code read exactly.
const code = [
  { item: 'EF-1 Exhaust fan', description: 'EF-1 — Exhaust fan', qty: 1, unit: 'nos', type: 'tag:EF-1' },
  { item: 'RTU-1 Rooftop unit', description: 'RTU-1 — Rooftop unit', qty: 1, unit: 'nos', type: 'tag:RTU-1' },
  { item: 'WC/L-1 Wall cap', description: 'WC/L-1 — Wall cap', qty: 1, unit: 'nos', type: 'tag:WC/L-1:new' },
];
const model = [
  { section: 'HVAC', description: 'EF-1 exhaust fan', qty: 2, unit: 'nos' },
  { section: 'HVAC', description: 'RTU 1 rooftop unit', qty: 1, unit: 'nos' },
  { section: 'Ceiling', description: 'Suspended ceiling, ground floor', qty: 120, unit: 'sqm' },
];

Deno.test('agreement is confirmed, disagreement keeps the tag count and is flagged, model-only scope is an estimate', () => {
  const x = crossCheck(model, code);
  const by = (t: string) => x.boq.find((l) => l.type === t)!;
  assertEquals(by('tag:RTU-1').cross_check, { by: 'model', model_qty: 1, agrees: true });
  assertEquals(by('tag:EF-1').qty, 1, 'the printed-tag count stays the quantity');
  assertEquals(by('tag:EF-1').qty_status, 'to_confirm', 'a disagreement is asked, never waved through');
  assertEquals(by('tag:EF-1').cross_check.model_qty, 2);
  assertEquals(by('tag:WC/L-1:new').cross_check.agrees, null, 'the model did not list it: kept, marked');
  const ceiling = x.boq.find((l) => /ceiling/i.test(l.description))!;
  assertEquals([ceiling.qty_status, ceiling.estimate], ['to_confirm', 120], "the model's own scope is an estimate to confirm");
  assertEquals([x.agreed, x.disagreed.length, x.code_only, x.model_only], [1, 1, ['WC/L-1'], 1]);
  assertEquals(crossCheckNotes(x).length, 3);
});

Deno.test('a tag is matched as a whole token: FD-1 is not FD-10', () => {
  const x = crossCheck([{ description: 'FD-10 floor drain', qty: 7 }], [{ description: 'FD-1 — Floor drain', qty: 7, type: 'tag:FD-1:new' }]);
  assertEquals(x.boq.find((l) => l.type)!.cross_check.agrees, null);
  assertEquals(x.model_only, 1);
});

Deno.test('on the journey fixture, a model that reads the sheet right is confirmed line by line and nothing is lost', async () => {
  const set = setBeforeModel(await pdfPages(zzPdfSheet(), undefined, { layers: false }))!;
  assert(set, 'the ZZ DEMO plumbing + HVAC sheet must be counted completely by code');
  const right = [{ description: 'FD-1 - floor drain', qty: 7, unit: 'nos' }, { description: 'WC-1 - water closet', qty: 5, unit: 'nos' },
    { description: 'FCU-1 - fan coil unit', qty: 1, unit: 'nos' }, { description: 'FCU-2 - fan coil unit', qty: 1, unit: 'nos' }, { description: 'FCU-3 - fan coil unit', qty: 1, unit: 'nos' }];
  const x = crossCheck(right, set.boq);
  assertEquals([x.agreed, x.disagreed, x.model_only], [5, [], 0]);
  const sum = (re: RegExp) => x.boq.filter((l) => re.test(String(l.description))).reduce((a, l) => a + Number(l.qty), 0);
  assertEquals([sum(/FD-1/), sum(/WC-1/), sum(/FCU-\d/)], [PDF_COUNTS['FD-1'], PDF_COUNTS['WC-1'], PDF_COUNTS.FCU]);
});

Deno.test('drawing_boq merges the coded set into the model reading instead of answering before the model', () => {
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  const model = src.indexOf('const payload = { __secret: key, fn: \'drawing_boq\'');
  const merge = src.indexOf('const x = crossCheck(ai.boq, codeSet.boq || [])');
  assert(model > 0 && merge > model, 'the cross-check must run on the model reading, after the model call');
  assert(/gateDrawingBoq\(merged, drawingIdentityTerms\(pdfText\), false\)/.test(src), 'the merged take-off must pass the identity gate');
  assert(/if \(codeSet && !key\) return codeAnswer\(\);/.test(src) && /ok === false\) \{ if \(codeSet\) return codeAnswer\(\);/.test(src), 'without the model the coded set still answers');
});
