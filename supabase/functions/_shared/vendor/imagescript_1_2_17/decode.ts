// VENDORED from imagescript 1.2.17 (utils/wasm/png.js, utils/wasm/jpeg.js and Image.decode's pixel conversion),
// MIT - see LICENSE.MIT beside this file. Only the change: the .wasm comes from the embedded base64 modules
// (png_wasm.ts, jpeg_wasm.ts) instead of `fetch(import.meta.url.replace('.js', '.wasm'))`, so nothing is fetched
// from deno.land at import or on a cold start, and tests need no network (13 Oct 2026, #1373, sales_engineer).
// Decode only: PNG and JPEG to RGBA. Compiled lazily, on the first decode.
import * as PNG from './png_wasm.ts';
import * as JPEG from './jpeg_wasm.ts';

const bytes = (b64: string) => Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
let pngMod: WebAssembly.Module | null = null;
let jpegMod: WebAssembly.Module | null = null;

export type Rgba = { width: number; height: number; rgba: Uint8Array };

function decodePng(data: Uint8Array): Rgba {
  pngMod ??= new WebAssembly.Module(bytes(PNG.B64));
  let u8: Uint8Array;
  // deno-lint-ignore no-explicit-any
  const ex: any = new WebAssembly.Instance(pngMod, { env: { emscripten_notify_memory_growth() { u8 = new Uint8Array(ex.memory.buffer); } } }).exports;
  u8 = new Uint8Array(ex.memory.buffer);
  const ptr = ex.walloc(data.length);
  u8.set(data, ptr);
  const status = ex.decode(ptr, data.length);
  ex.wfree(ptr);
  if (0 > status) throw new Error(`png: failed to decode (${status})`);
  const width = ex.width(), height = ex.height();
  const rgba = u8.slice(status, status + 4 * width * height);
  ex.wfree(status);
  return { width, height, rgba };
}

function decodeJpeg(data: Uint8Array): Rgba {
  jpegMod ??= new WebAssembly.Module(bytes(JPEG.B64));
  // deno-lint-ignore no-explicit-any
  const w: any = new WebAssembly.Instance(jpegMod).exports;
  const u8 = (p: number, n: number) => new Uint8Array(w.memory.buffer, p, n);
  const bptr = w.walloc(data.length);
  u8(bptr, data.length).set(data);
  const ptr = w.decode(bptr, data.length, undefined, undefined);
  if (0 === ptr) throw new Error('jpg: failed to decode');
  if (1 === ptr) throw new Error('jpg: failed to scale decoder');
  const width = w.decode_width(ptr), height = w.decode_height(ptr), format = w.decode_format(ptr);
  const buf = u8(w.decode_buffer(ptr), w.wlen()).slice();
  w.decode_free(ptr);
  const rgba = new Uint8Array(width * height * 4);
  if (format === 0) { for (let i = 0; i < width * height; i++) { const v = buf[i]; rgba.set([v, v, v, 255], i * 4); } }
  else if (format === 1) { for (let i = 0; i < width * height; i++) { rgba[i * 4] = buf[i * 3]; rgba[i * 4 + 1] = buf[i * 3 + 1]; rgba[i * 4 + 2] = buf[i * 3 + 2]; rgba[i * 4 + 3] = 255; } }
  else if (format === 2) {
    for (let i = 0; i < buf.length; i += 4) {
      const k = 1 - buf[i + 3] / 255;
      rgba[i] = 255 * (1 - buf[i] / 255) * k; rgba[i + 1] = 255 * (1 - buf[i + 1] / 255) * k; rgba[i + 2] = 255 * (1 - buf[i + 2] / 255) * k; rgba[i + 3] = 255;
    }
  } else throw new Error(`jpg: unknown pixel format ${format}`);
  return { width, height, rgba };
}

/** PNG or JPEG bytes -> RGBA; throws on anything else or on a decode failure. */
export function decodeImage(data: Uint8Array): Rgba {
  if (data.length > 8 && data[0] === 0x89 && data[1] === 0x50 && data[2] === 0x4e && data[3] === 0x47) return decodePng(data);
  if (data.length > 3 && data[0] === 0xff && data[1] === 0xd8 && data[2] === 0xff) return decodeJpeg(data);
  throw new Error('Unsupported image type');
}
