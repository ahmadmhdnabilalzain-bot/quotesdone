// A customer's site photo reaches no supplier unchecked (15 Nov 2026, sales_engineer; founder rulings 1683 and 1704).
// The OCR engine and the final look are stubbed (no model call, no network): the planted text is what the engine "reads".
// Pins: a villa number, a car plate, a name, a phone number are MASKED and named; identity still read after masking, writing no
// word covers, a photo mostly painted, a look that does not answer or is unsure, an engine that throws are WITHHELD; a face the
// look names is painted and looked at again; plain technical text (a nameplate's ratings) is kept; the customer's notice names
// the photo and why.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { checkSitePhoto, lineKind, photoBudget, photoLookPlan, photoNotice, photoScale, MAX_MASKED, PHOTO_JOB_MS, PHOTO_USD_CAP, type PhotoLook } from './site_photo_gate.ts';
import { pageSizeFromPixels, pixelBudget, planTiles } from './drawing_pixel_gate.ts';
import { MAX_PHOTOS, PHOTOS_PER_DAY } from './site_photos.ts';
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
  assertMatch(photoNotice(1, null, m, 'en'), /^Photo 1: we covered a house, villa, office, shop or building number before the suppliers see it\.$/);
});

// Review of bf8b9ea45, item 5: lineKind returned null (kept) for these, probed in Deno on bf8b9ea45.
Deno.test('an office, shop, suite, room, unit, warehouse or plot number, and a meter, premise, account or contract number, are identity', () => {
  for (const t of ['Office 1204', 'Shop 12', 'Room 1204', 'Suite 301', 'Unit 7', 'Warehouse 14', 'Plot 345', 'Flat 22', 'Store No. 9',
    'مكتب 1204', 'محل ١٢', 'غرفة 305', 'مستودع 7'])
    assertEquals(lineKind(t, []), 'house_number', t);
  for (const t of ['Meter No. 123456789', 'Meter 2045', 'DEWA Premise No: 6543210987', 'Account No 2001234567', 'Contract 445566', 'Consumer no. 300 123 4567',
    'رقم العداد 123456789', 'رقم الحساب: 2001234567'])
    assert(lineKind(t, []) !== null, t);
  assertEquals(lineKind('Meter 2045', []), 'account_number');
  assertEquals(lineKind('DEWA Premise No: 6543210987', []), 'account_number');
  // the job itself stays readable: ratings, refrigerant, an A/C nameplate, a room's use
  for (const t of ['230V 50Hz', 'R410A', '24000 BTU']) assertEquals(lineKind(t, []), null, t);
  assert(lineKind('A/C 24000 BTU', []) !== 'account_number', 'an air-conditioner nameplate read as an account number');
  assertMatch(photoNotice(0, null, { status: 'masked', image: blank(), reasons: ['account_number'], masked: 0.02 }, 'en'), /a meter, account or contract number/);
});

// Review of bf8b9ea45, item 6: a photo was planned as the larger of A1 and its pixels (a 1600 x 1200 photo: 20 tiles and a whole view,
// about $0.084 a look). It is now planned as a photo: a few tiles, a cap per photo, per request and per customer per day.
Deno.test('a photo is tiled as a photo: a few views a look, a capped spend per photo, and the job inside its time', () => {
  const old = planTiles(pageSizeFromPixels(1600, 1200));
  assert(old.calls >= 20, 'the known-bad control: the A1 plan of a photo (' + old.calls + ' calls)');
  for (const [w, h] of [[1600, 1200], [4000, 3000], [3000, 4000], [2000, 2000], [4000, 1000], [640, 480]]) {
    const p = photoLookPlan(w, h);
    assert(p.calls <= 5, `${w}x${h}: ${p.calls} views a look`);
    assert(p.maxUsd <= PHOTO_USD_CAP, `${w}x${h}: up to $${p.maxUsd.toFixed(4)} a photo, over the $${PHOTO_USD_CAP} cap`);
  }
  // the cost per photo, as the hand-back states it: a 4:3 photo, one look and every round of the gate
  const p43 = photoLookPlan(1600, 1200);
  assertEquals([p43.calls, Number(p43.usd.toFixed(4)), Number(p43.maxUsd.toFixed(4))], [4, 0.0141, 0.0422]);
  assert(Math.round(MAX_PHOTOS * PHOTO_USD_CAP * 100) <= 60 && Math.round(PHOTOS_PER_DAY * PHOTO_USD_CAP * 100) <= 120, 'the request and day caps');
  // scaled down before eight OCR reads, never up
  assertEquals(photoScale(4000, 3000), { w: 2000, h: 1500, scaled: true });
  assertEquals(photoScale(800, 600), { w: 800, h: 600, scaled: false });
  // the set's budget is capped for one photo, counting what its job already spent (the worker's spent_usd)
  const b = photoBudget(pixelBudget(3), 0.04);
  assert(Math.abs(b.left() - 0.01) < 1e-9, String(b.left()));
  b.spend(0.01);
  assert(b.left() <= 1e-9);
  // the job's own cut is inside the worker's five minutes, and the worker uses the same number
  assert(PHOTO_JOB_MS < 5 * 60_000);
  const worker = Deno.readTextFileSync(new URL('../../../scripts/cad_read_worker.ts', import.meta.url));
  assert(worker.includes(`const PHOTO_JOB_MS = ${PHOTO_JOB_MS / 60_000} * 60_000;`), 'the worker cuts a photo at another time');
  assert(worker.includes('photoScale(img0.width, img0.height)'), 'the worker does not scale the photo down first');
  const edge = Deno.readTextFileSync(new URL('../drawing_redact/index.ts', import.meta.url));
  assert(edge.includes('gateBudget = photo ? photoBudget(setBudget, body.spent_usd) : setBudget') && edge.includes(', jpg, gateBudget, photoSize, clock.stopAt'), 'the edge does not cap a photo\'s spend');
  assert(edge.includes('photoSize = photo ? photoPageSize(px?.w ?? 1600, px?.h ?? 1200) : size'), 'the edge does not tile a photo as a photo');
});

Deno.test('a check that did not finish is said as that, never as something the photo shows', () => {
  const t = photoNotice(0, 'The isolator switch', { status: 'withheld', reasons: ['not_checked'], detail: 'site_photo_time' }, 'en');
  assertEquals(t, 'This photo (The isolator switch): not sent to the suppliers, because its check could not be finished. You can send it again later.');
  assertMatch(photoNotice(0, null, { status: 'withheld', reasons: ['not_checked'], detail: 'x' }, 'ar'), /لم يكتمل/);
});
