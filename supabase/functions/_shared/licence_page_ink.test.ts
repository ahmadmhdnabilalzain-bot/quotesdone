// A blank page is blank by code's measurement, before any model is asked (13 Oct 2026, sales_engineer).
import { assertEquals } from 'jsr:@std/assert@1';
import { Image } from 'https://deno.land/x/imagescript@1.2.17/mod.ts';
import { pageInk, pagesBlank } from './licence_page_ink.ts';
import { lowReadProven } from './licence_extract.ts';

const b64 = (u: Uint8Array) => { let s = ''; for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode(...u.subarray(i, i + 0x8000)); return btoa(s); };
const W = 1240, H = 1754; // A4 at 150 dpi

// deterministic noise so the test never flakes
let seed = 7; const rnd = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;

async function whitePng() { const im = new Image(W, H); im.fill(0xffffffff); return b64(await im.encode()); }
async function nearBlankJpeg() {
  const im = new Image(W, H);
  for (let y = 1; y <= H; y++) for (let x = 1; x <= W; x++) { const v = 200 + Math.round((rnd() - 0.5) * 12); im.setPixelAt(x, y, Image.rgbToColor(v, v, v - 4)); }
  return b64(await im.encodeJPEG(80));
}
async function printedPng() { // light ground, rows of black "text" bars, as a licence page has
  const im = new Image(W, H); im.fill(Image.rgbToColor(245, 243, 238));
  for (let row = 0; row < 30; row++) for (let w = 0; w < 8; w++) im.drawBox(120 + w * 130, 150 + row * 50, 90, 14, Image.rgbToColor(20, 20, 20));
  return b64(await im.encode());
}

Deno.test('a page-sized white PNG is blank', async () => {
  const p = await whitePng();
  assertEquals(await pagesBlank([p]), true, JSON.stringify(await pageInk(p)));
});

Deno.test('a low-contrast near-blank JPEG (a white wall, a blank scan) is blank', async () => {
  const p = await nearBlankJpeg();
  assertEquals(await pagesBlank([p]), true, JSON.stringify(await pageInk(p)));
});

Deno.test('a printed page is not blank, and one printed page among blanks is enough', async () => {
  const p = await printedPng();
  assertEquals(await pagesBlank([p]), false, JSON.stringify(await pageInk(p)));
  assertEquals(await pagesBlank([await whitePng(), p]), false);
});

Deno.test('10 pages of 3000 px: at most MAX_PAGES (2) decoded inside the budget, the rest not judged, never blank', async () => {
  // a noisy near-blank 3000 x 3000 JPEG: the worst case to decode (no long runs to compress), and blank
  const big = new Image(3000, 3000);
  for (let y = 1; y <= 3000; y++) for (let x = 1; x <= 3000; x++) { const v = 200 + ((x * 7 + y * 13) % 9) - 4; big.setPixelAt(x, y, Image.rgbToColor(v, v, v)); }
  const page = b64(await big.encodeJPEG(90));
  const t0 = performance.now();
  const r = await pagesBlank(Array(10).fill(page));
  const ms = performance.now() - t0;
  assertEquals(r, null);                          // 2 white pages decoded, 8 not judged -> not "blank"
  assertEquals(ms < 2000, true, `took ${Math.round(ms)} ms`);
  const huge = new Image(5000, 4000); huge.fill(0xffffffff);
  assertEquals(await pagesBlank([b64(await huge.encode(1))]), null); // over MAX_PIXELS: never decoded
});

Deno.test('a page code cannot decode is never judged blank', async () => {
  assertEquals(await pagesBlank([btoa('not an image')]), null);
  assertEquals(await pagesBlank([]), null);
});

Deno.test("a 'low' read is kept only with ink measured or its number in the text layer", () => {
  const low = { confidence: 'low', unreadable: false, license_number: '20840' };
  assertEquals(lowReadProven(low, true, null), true);                          // printed image page measured
  assertEquals(lowReadProven(low, false, 'Licence No. 20840 Expiry 12/04/2027'), true);
  assertEquals(lowReadProven({ ...low, license_number: 'CN-1234567' }, false, 'رقم الرخصة CN-1234567 الانتهاء'), true);
  assertEquals(lowReadProven(low, false, 'Licence No. 208401'), false);        // not the same number
  assertEquals(lowReadProven(low, false, null), false);                        // a scan PDF: nothing proven -> held
  assertEquals(lowReadProven({ ...low, confidence: 'medium' }, false, null), true);
});
