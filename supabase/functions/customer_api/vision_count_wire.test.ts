// vision_count_wire — a photo's legend is sent to drawing_boq's vision count, and only the count it chose is applied.
// deno test supabase/functions/customer_api/vision_count_wire.test.ts
//
// Measured 27 Oct 2026 (founder ledger 580): drawing_boq mode 'vision_count' had no caller anywhere. The lines below
// are the shape drawing_from_ocr.ts readDrawing gives a photographed fire-alarm sheet, with the template counts the
// drawing bench measured on the phone photo (53 call points against 10, 74 smoke detectors against 11) and a loop
// whose highest address is 21. Fails on the old code: there was no module and no caller.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { applyVisionCounts, isPhotoOrScan, visionCountBody } from './vision_count_wire.ts';

const PHOTO_BOQ = [
  { section: 'Fire alarm — addressable loop', type: 'loop_l1_addresses', item: 'Loop L1 addresses', qty: null, estimate: 21, unit: 'addresses', qty_status: 'to_confirm' },
  { section: 'Fire alarm — devices (from the legend)', type: 'smoke_detector', description: 'Optical smoke detector', item: 'Optical smoke detector', qty: null, estimate: 74, unit: 'nos', qty_status: 'to_confirm', basis: 'counted on the drawing: template match' },
  { section: 'Fire alarm — devices (from the legend)', type: 'manual_call_point', description: 'Manual call point', item: 'Manual call point', qty: null, estimate: 53, unit: 'nos', qty_status: 'to_confirm', basis: 'counted on the drawing: template match' },
  { section: 'Fire alarm — devices (from the legend)', type: 'sounder', description: 'Wall sounder', item: 'Wall sounder', qty: null, estimate: null, unit: 'nos', qty_status: 'to_confirm' },
  { section: 'Fire alarm — cable', type: 'fire_rated_cable', description: 'Fire-rated cable, 1.5mm 2-core', qty: null, unit: 'm' },
];

Deno.test('only a photo or a scanned PDF is sent; never CAD, never a PDF with a text layer', () => {
  assert(isPhotoOrScan('image/jpeg', -1, false));
  assert(isPhotoOrScan('application/pdf', 0, false));
  assert(!isPhotoOrScan('application/pdf', 812, false), 'a vector PDF is counted by code');
  assert(!isPhotoOrScan('image/vnd.dwg', -1, true), 'CAD is counted by code');
  assert(!isPhotoOrScan('application/pdf', -1, false), 'an unread PDF is not assumed to be a scan');
});

Deno.test('the request carries the legend types, the code counts and the loop size, nothing else', () => {
  const b = visionCountBody(PHOTO_BOQ)!;
  assertEquals(b.legend, [{ type: 'smoke_detector', en: 'Optical smoke detector' }, { type: 'manual_call_point', en: 'Manual call point' }, { type: 'sounder', en: 'Wall sounder' }]);
  assertEquals(b.code_counts, { smoke_detector: 74, manual_call_point: 53 }, 'a type with no template count sends none');
  assertEquals(b.addresses, 21);
  assertEquals(visionCountBody([PHOTO_BOQ[4]]), null, 'no legend line: no call');
  assertEquals(visionCountBody(null), null);
});

Deno.test('the model\'s counts replace the template estimates, still to confirm, when drawing_boq chose them', () => {
  const reply = { ok: true, source: 'vision', agrees: true, vision: { smoke_detector: 11, manual_call_point: 10, sounder: 0 }, counts: { smoke_detector: 11, manual_call_point: 10, sounder: 0 } };
  const out = applyVisionCounts(PHOTO_BOQ, reply) as any[];
  assertEquals(out[1].estimate, 11); assertEquals(out[2].estimate, 10); assertEquals(out[3].estimate, 0);
  for (const l of out.slice(1, 4)) { assertEquals(l.qty, null, 'never a settled quantity'); assertEquals(l.qty_status, 'to_confirm'); assertEquals(l.count_source, 'vision'); }
  assert(out[1].basis.includes('template count 74') && out[1].basis.includes('loop addresses'));
  assertEquals(out[0], PHOTO_BOQ[0], 'the loop line is untouched');
  assertEquals(out[4], PHOTO_BOQ[4], 'a non-legend line is untouched');
});

Deno.test('the code stands when drawing_boq kept the code, refused, or did not answer', () => {
  for (const r of [null, { ok: false }, { ok: true, source: 'code', counts: { smoke_detector: 74 }, vision: { smoke_detector: 11 } }, { ok: true, source: 'vision', counts: { smoke_detector: 11 }, vision: null }]) {
    assertEquals(applyVisionCounts(PHOTO_BOQ, r as any), PHOTO_BOQ, JSON.stringify(r));
  }
});

Deno.test('vision_count has a caller: cad_read_status runs it for a scan job and analyze_drawing records the request', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  assert(/mode: 'vision_count'/.test(src), 'customer_api calls drawing_boq mode vision_count');
  assert(/vision_count: vcBody, vision_lines: boqOut\.boq/.test(src), 'analyze_drawing puts the legend request on the queued scan job');
  const portal = await Deno.readTextFile(new URL('../../../src/components/me/NewRequest.tsx', import.meta.url));
  assert(/s\.counted_boq/.test(portal), 'the portal adopts the counted take-off when the scan job is done');
});
