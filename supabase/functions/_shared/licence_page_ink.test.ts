// A blank page is blank by code's measurement, before any model is asked (13 Oct 2026, sales_engineer).
// Runs in `npm test` with --allow-read=. and NO network: the decoder is vendored (vendor/imagescript_1_2_17) and
// the test pages are made here (PNG) or read from testdata (a near-blank JPEG made once with imagescript 1.2.17).
import { assertEquals } from 'jsr:@std/assert@1';
import { pageInk, pagesBlank } from './licence_page_ink.ts';
import * as PNG from './vendor/imagescript_1_2_17/png_wasm.ts';
import * as JPEG from './vendor/imagescript_1_2_17/jpeg_wasm.ts';

const b64 = (u: Uint8Array) => { let s = ''; for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode(...u.subarray(i, i + 0x8000)); return btoa(s); };

// A minimal RGB PNG encoder (zlib via CompressionStream 'deflate'), enough to make test pages with no library.
const CRC = new Uint32Array(256).map((_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
const crc32 = (u: Uint8Array) => { let c = 0xffffffff; for (const b of u) c = CRC[(c ^ b) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
async function png(w: number, h: number, px: (x: number, y: number) => number): Promise<string> {
  const raw = new Uint8Array((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) { const o = y * (w * 3 + 1); for (let x = 0; x < w; x++) { const v = px(x, y); raw[o + 1 + x * 3] = v; raw[o + 2 + x * 3] = v; raw[o + 3 + x * 3] = v; } }
  const z = new Uint8Array(await new Response(new Blob([raw]).stream().pipeThrough(new CompressionStream('deflate'))).arrayBuffer());
  const chunk = (type: string, data: Uint8Array) => {
    const td = new Uint8Array(4 + data.length); td.set(new TextEncoder().encode(type)); td.set(data, 4);
    const out = new Uint8Array(12 + data.length); const dv = new DataView(out.buffer);
    dv.setUint32(0, data.length); out.set(td, 4); dv.setUint32(8 + data.length, crc32(td)); return out;
  };
  const ihdr = new Uint8Array(13); const dv = new DataView(ihdr.buffer); dv.setUint32(0, w); dv.setUint32(4, h); ihdr.set([8, 2, 0, 0, 0], 8);
  const parts = [new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', ihdr), chunk('IDAT', z), chunk('IEND', new Uint8Array())];
  return b64(new Uint8Array(await new Blob(parts).arrayBuffer()));
}
const W = 1240, H = 1754; // A4 at 150 dpi
const whitePng = () => png(W, H, () => 255);
const printedPng = () => png(W, H, (x, y) => (y >= 150 && (y - 150) % 50 < 14 && y < 1650 && x >= 120 && (x - 120) % 130 < 90 && x < 1160) ? 20 : 244);
const nearBlankJpeg = async () => b64(await Deno.readFile(new URL('./testdata/licence_near_blank.jpg', import.meta.url)));

Deno.test('the vendored wasm is the pinned imagescript 1.2.17 build', async () => {
  for (const [m, size, sha] of [[PNG, 103776, '3687bebda95af7572626ab02c09c60a79f160385abad979dbb494f6b17cda2cf'], [JPEG, 91769, '019bcef4d864045e9b2df7e39ef6e7f3227d80b08a33742e1438441f2ddc2368']] as const) {
    const u = Uint8Array.from(atob(m.B64), (c) => c.charCodeAt(0));
    const hex = [...new Uint8Array(await crypto.subtle.digest('SHA-256', u))].map((b) => b.toString(16).padStart(2, '0')).join('');
    assertEquals([u.length, hex, m.SHA256], [size, sha, sha]);
  }
});

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
  const page = await png(3000, 3000, (x, y) => 200 + ((x * 7 + y * 13) % 9) - 4); // noisy near-blank, poor compression
  const t0 = performance.now();
  const r = await pagesBlank(Array(10).fill(page));
  const ms = performance.now() - t0;
  assertEquals(r, null);                          // 2 pages decoded (blank), 8 not judged -> not "blank"
  assertEquals(ms < 2000, true, `took ${Math.round(ms)} ms`);
  assertEquals(await pagesBlank([await png(5000, 4000, () => 255)]), null); // over MAX_PIXELS: never decoded
});

Deno.test('a page code cannot decode is never judged blank', async () => {
  assertEquals(await pagesBlank([btoa('not an image')]), null);
  assertEquals(await pagesBlank([]), null);
});
