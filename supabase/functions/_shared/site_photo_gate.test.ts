// A customer's site photo reaches no supplier unchecked (15 Nov 2026, sales_engineer; founder rulings 1683 and 1704).
// The OCR engine and the final look are stubbed (no model call, no network): the planted text is what the engine "reads".
// Pins: a villa number, a car plate, a name, a phone number are MASKED and named; identity still read after masking, writing no
// word covers, a photo mostly painted, a look that does not answer or is unsure, an engine that throws are WITHHELD; a face the
// look names is painted and looked at again; plain technical text (a nameplate's ratings) is kept; the customer's notice names
// the photo and why.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { checkSitePhoto, lineKind, photoNotice, MAX_MASKED, type PhotoLook } from './site_photo_gate.ts';
import type { OcrLine, Rgba } from './scan_redact.ts';

const W = 400, H = 300;
const blank = (): Rgba => ({ w: W, h: H, rgba: new Uint8ClampedArray(W * H * 4).fill(255) });
const line = (text: string, x0: number, y0: number, x1: number, y1: number, conf = 90): OcrLine =>
  ({ text, conf, bbox: { x0, y0, x1, y1 }, words: text.split(' ').map((t, i, a) => ({ text: t, conf, bbox: { x0: x0 + ((x1 - x0) * i) / a.length, y0, x1: x0 + ((x1 - x0) * (i + 1)) / a.length, y1 } })) });
/** An engine that reads `first` on the upright original only, and `after` on the upright painted photo (call 4). */
function engine(first: OcrLine[], after: OcrLine[] = []) {
  let n = 0;
  return async (_bmp: Uint8Array) => { const k = n++; return k === 0 ? first : k === 4 ? after : []; };
}
const clean: PhotoLook = async () => ({ clean: true, regions: [] });
const SEEDS = ['omar haddad', 'haddad'];

Deno.test('a villa number, a car plate, a name and a phone number are masked and named', async () => {
  for (const [text, why] of [['VILLA 23', 'house_number'], ['DUBAI A 12345', 'car_plate'], ['To: Mr Omar Haddad', 'name'], ['Call 050 123 4567', 'contact']] as const) {
    const r = await checkSitePhoto(blank(), engine([line(text, 40, 40, 200, 70)]), SEEDS, clean);
    assertEquals(r.status, 'masked', `${text}: ${JSON.stringify(r)}`);
    assert(r.reasons.includes(why), `${text}: ${r.reasons}`);
    if (r.status === 'masked') { const k = (55 * W + 100) * 4; assertEquals([r.image.rgba[k], r.image.rgba[k + 1], r.image.rgba[k + 2]], [0, 0, 0], `${text}: the line was not painted`); }
  }
});

Deno.test('plain technical text on a nameplate is kept, and a photo with nothing to cover is released after the look', async () => {
  assertEquals(lineKind('230V 50Hz', []), null);
  const r = await checkSitePhoto(blank(), engine([line('230V 50Hz', 40, 40, 200, 70)]), SEEDS, clean);
  assertEquals(r.status, 'released');
  const none = await checkSitePhoto(blank(), engine([]), SEEDS, clean);
  assertEquals(none.status, 'released');
});

Deno.test('identity still read after masking withholds the photo', async () => {
  const r = await checkSitePhoto(blank(), engine([line('VILLA 23', 40, 40, 200, 70)], [line('Villa 23', 250, 200, 380, 230)]), SEEDS, clean);
  assertEquals(r.status, 'withheld');
});

Deno.test('writing that no read word covers withholds the photo (an angled sign, a smudged plate)', async () => {
  const img = blank();
  // five glyph-sized dark blobs in a row, like letters nobody read
  for (let g = 0; g < 5; g++) for (let y = 150; y < 162; y++) for (let x = 100 + g * 12; x < 108 + g * 12; x++) { const k = (y * W + x) * 4; img.rgba[k] = img.rgba[k + 1] = img.rgba[k + 2] = 0; }
  const r = await checkSitePhoto(img, engine([]), SEEDS, clean);
  assertEquals(r.status, 'withheld');
  assert(r.reasons.includes('unread_writing'));
});

Deno.test('a photo mostly painted is withheld', async () => {
  const r = await checkSitePhoto(blank(), engine([line('VILLA 23 AL BARSHA SOUTH GATE 4', 0, 0, W, H * (MAX_MASKED + 0.1))]), SEEDS, clean);
  assertEquals(r.status, 'withheld');
  assert(r.reasons.includes('too_much_masked'));
});

Deno.test('OCR never releases a photo alone: no look, a look that does not answer, or an unsure look withholds it', async () => {
  assertEquals((await checkSitePhoto(blank(), engine([]), SEEDS, null)).status, 'withheld');
  assertEquals((await checkSitePhoto(blank(), engine([]), SEEDS, async () => null)).status, 'withheld');
  assertEquals((await checkSitePhoto(blank(), engine([]), SEEDS, async () => ({ clean: false, unsure: true, regions: [] }))).status, 'withheld');
  const thrown = await checkSitePhoto(blank(), async () => { throw new Error('engine down'); }, SEEDS, clean);
  assertEquals(thrown.status, 'withheld');
});

Deno.test('a face the look names is painted, looked at again, and the photo goes out masked', async () => {
  let looks = 0;
  const look: PhotoLook = async () => (looks++ === 0 ? { clean: false, regions: [{ x: 0.6, y: 0.1, w: 0.15, h: 0.2, what: 'face' }] } : { clean: true, regions: [] });
  const r = await checkSitePhoto(blank(), engine([]), SEEDS, look);
  assertEquals(r.status, 'masked');
  assert(r.reasons.includes('face_or_other'));
  assertEquals(looks, 2);
  // still seen after painting: withheld
  const stubborn: PhotoLook = async () => ({ clean: false, regions: [{ x: 0.1, y: 0.1, w: 0.1, h: 0.1, what: 'plate' }] });
  assertEquals((await checkSitePhoto(blank(), engine([]), SEEDS, stubborn)).status, 'withheld');
});

Deno.test('the customer is told which photo and why, in his language', async () => {
  const r = await checkSitePhoto(blank(), engine([line('DUBAI A 12345', 40, 40, 200, 70)], [line('DUBAI A 12345', 40, 40, 200, 70)]), SEEDS, clean);
  assertEquals(r.status, 'withheld');
  const en = photoNotice(2, 'Each outdoor unit and where it sits', r, 'en');
  assertMatch(en, /^Photo 2 \(Each outdoor unit and where it sits\): not sent to the suppliers, because it shows a car number plate/);
  assertMatch(photoNotice(2, null, r, 'ar'), /^الصورة 2: لن تُرسل إلى الموردين لأنها تُظهر لوحة سيارة/);
  const m = await checkSitePhoto(blank(), engine([line('VILLA 23', 40, 40, 200, 70)]), SEEDS, clean);
  assertMatch(photoNotice(1, null, m, 'en'), /^Photo 1: we covered a house, villa or building number before the suppliers see it\.$/);
});
