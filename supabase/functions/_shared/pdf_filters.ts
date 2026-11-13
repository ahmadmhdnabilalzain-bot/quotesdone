// pdf_filters — a PDF stream's bytes through its WHOLE filter chain: Flate, ASCII85, ASCIIHex, LZW and RunLength,
// in the order /Filter names them, with a PNG or TIFF predictor where /DecodeParms asks for one.
// 13 Nov 2026, sales_engineer (anonymity audit B finding G2 and audit A finding L5).
//
// MEASURED BEFORE: pdf_text_positions.decodeStream decoded /FlateDecode alone and gave up on any other /Filter. A
// normal reportlab PDF writes its content streams as [/ASCII85Decode /FlateDecode] (its default useA85), and the
// auditor's B1 variant written that way (B_drawings/fixtures/b1_a85_variant.pdf) read as 0 text runs: a vector sheet
// was sent down the scan route, and a customer's quotation lost every deterministic layer (title boxes, the parties it
// names). An image filter (DCT, JPX, CCITT, JBIG2) is not text and returns null, as an unknown filter does: a stream
// that cannot be decoded is never guessed at.
import { inflate } from './pdf_text.ts';

/** Every decoder's output ceiling, and the longest filter chain read (13 Nov 2026, review item 12). Past either the
 *  stream is undecodable (null) and the drawing is HELD; a hostile file costs no more than this. */
export const DECODE_CAP = 64 * 1024 * 1024, MAX_CHAIN = 6;
/** The decoders that build a plain array (8 bytes a value) stop at a quarter of that. */
const ARRAY_CAP = DECODE_CAP / 4;
const NAMES: Record<string, string> = { AHx: 'ASCIIHexDecode', A85: 'ASCII85Decode', LZW: 'LZWDecode', Fl: 'FlateDecode', RL: 'RunLengthDecode' };

/** The filter names of a stream dictionary, in application order (full names). [] when it has none. */
export function filtersOf(dict: string): string[] {
  const m = /\/Filter\s*(\[[^\]]*\]|\/[A-Za-z0-9]+)/.exec(dict);
  if (!m) return [];
  return [...m[1].matchAll(/\/([A-Za-z0-9]+)/g)].map((x) => NAMES[x[1]] ?? x[1]);
}

/** The /DecodeParms entry for the i-th filter (a dictionary or an array of them, null entries allowed). */
function parmsOf(dict: string, i: number): Record<string, number> {
  const m = /\/DecodeParms\s*(\[(?:[^\[\]]|\[[^\]]*\])*\]|<<(?:[^<>]|<<[^>]*>>)*>>)/.exec(dict);
  if (!m) return {};
  const items = m[1].startsWith('[') ? [...m[1].slice(1, -1).matchAll(/<<(?:[^<>]|<<[^>]*>>)*>>|null/g)].map((x) => x[0]) : [m[1]];
  const one = items[i] ?? (items.length === 1 && i === 0 ? items[0] : null);
  const out: Record<string, number> = {};
  if (!one || one === 'null') return out;
  for (const k of ['Predictor', 'Colors', 'BitsPerComponent', 'Columns', 'EarlyChange']) {
    const v = new RegExp(`/${k}\\s+(-?\\d+)`).exec(one); if (v) out[k] = Number(v[1]);
  }
  return out;
}

export function asciiHex(b: Uint8Array): Uint8Array {
  const out: number[] = []; let hi = -1;
  for (const c of b) {
    if (c === 0x3e) break;                                           // '>' ends the data
    const v = c >= 48 && c <= 57 ? c - 48 : c >= 65 && c <= 70 ? c - 55 : c >= 97 && c <= 102 ? c - 87 : -1;
    if (v < 0) continue;                                             // whitespace
    if (hi < 0) hi = v; else { out.push(hi * 16 + v); hi = -1; }
  }
  if (hi >= 0) out.push(hi * 16);
  return new Uint8Array(out);
}

export function ascii85(b: Uint8Array): Uint8Array {
  const out: number[] = []; const g: number[] = [];
  let i = 0;
  if (b[0] === 0x3c && b[1] === 0x7e) i = 2;                         // an optional leading "<~"
  for (; i < b.length; i++) {
    const c = b[i];
    if (c === 0x7e) break;                                           // "~>" ends the data
    if (c <= 0x20) continue;
    if (c === 0x7a && g.length === 0) { out.push(0, 0, 0, 0); continue; }
    if (c < 0x21 || c > 0x75) throw new Error('ascii85: bad character');
    g.push(c - 33);
    if (g.length === 5) {
      let v = 0; for (const d of g) v = v * 85 + d;
      if (v > 0xffffffff) throw new Error('ascii85: group overflows 32 bits');   // "uuuuu" decoded before (review item 12)
      if (out.length > ARRAY_CAP) throw new Error('ascii85: output cap');
      out.push((v >>> 24) & 255, (v >>> 16) & 255, (v >>> 8) & 255, v & 255); g.length = 0;
    }
  }
  if (g.length) {
    const n = g.length; while (g.length < 5) g.push(84);
    let v = 0; for (const d of g) v = v * 85 + d;
    if (v > 0xffffffff) throw new Error('ascii85: group overflows 32 bits');
    const bytes = [(v >>> 24) & 255, (v >>> 16) & 255, (v >>> 8) & 255, v & 255];
    out.push(...bytes.slice(0, n - 1));
  }
  return new Uint8Array(out);
}

export function lzw(b: Uint8Array, earlyChange = 1): Uint8Array {
  const out: number[] = [];
  let dict: number[][] = [];
  const reset = () => { dict = []; for (let i = 0; i < 256; i++) dict.push([i]); dict.push([], []); };
  reset();
  let width = 9, bitBuf = 0, bitLen = 0, prev: number[] | null = null;
  for (let i = 0; i < b.length; i++) {
    bitBuf = (bitBuf << 8) | b[i]; bitLen += 8;
    while (bitLen >= width) {
      const code = (bitBuf >>> (bitLen - width)) & ((1 << width) - 1);
      bitLen -= width; bitBuf &= (1 << bitLen) - 1;
      if (code === 256) { reset(); width = 9; prev = null; continue; }
      if (code === 257) return new Uint8Array(out);
      let entry: number[];
      if (code < dict.length && (code < 256 || dict[code].length)) entry = dict[code];
      else if (prev && code === dict.length) entry = [...prev, prev[0]];
      else throw new Error('lzw: bad code');
      if (out.length + entry.length > ARRAY_CAP) throw new Error('lzw: output cap');
      for (const x of entry) out.push(x);
      if (prev) dict.push([...prev, entry[0]]);
      prev = entry;
      const next = dict.length + earlyChange;
      if (next >= (1 << width) && width < 12) width++;
    }
  }
  return new Uint8Array(out);
}

export function runLength(b: Uint8Array): Uint8Array {
  const out: number[] = [];
  for (let i = 0; i < b.length;) {
    const n = b[i++];
    if (n === 128) break;
    if (out.length > ARRAY_CAP) throw new Error('runlength: output cap');
    if (n < 128) { for (let k = 0; k <= n && i < b.length; k++) out.push(b[i++]); }
    else { const v = b[i++]; for (let k = 0; k < 257 - n; k++) out.push(v); }
  }
  return new Uint8Array(out);
}

/** PNG (10-15) and TIFF (2) predictors, as /DecodeParms states them. */
export function unpredict(b: Uint8Array, p: Record<string, number>): Uint8Array {
  const pred = p.Predictor ?? 1;
  if (pred <= 1) return b;
  const colors = p.Colors ?? 1, bpc = p.BitsPerComponent ?? 8, cols = p.Columns ?? 1;
  const bpp = Math.max(1, Math.ceil((colors * bpc) / 8)), row = Math.ceil((colors * bpc * cols) / 8);
  // /Columns 0 never advanced the row loop (an infinite loop, review item 12): a row of no bytes is a broken stream.
  if (!(row >= 1) || !Number.isFinite(row) || row > DECODE_CAP) throw new Error('predictor: bad row');
  if (pred === 2) {
    if (bpc !== 8) return b;
    const o = new Uint8Array(b);
    for (let r = 0; r + row <= o.length; r += row) for (let i = bpp; i < row; i++) o[r + i] = (o[r + i] + o[r + i - bpp]) & 255;
    return o;
  }
  const out = new Uint8Array(Math.floor(b.length / (row + 1)) * row);
  let up = new Uint8Array(row);
  for (let r = 0, o = 0; r + row + 1 <= b.length; r += row + 1, o += row) {
    const t = b[r], cur = out.subarray(o, o + row);
    for (let i = 0; i < row; i++) {
      const x = b[r + 1 + i], a = i >= bpp ? cur[i - bpp] : 0, u = up[i], c = i >= bpp ? up[i - bpp] : 0;
      let v = x;
      if (t === 1) v = x + a; else if (t === 2) v = x + u; else if (t === 3) v = x + ((a + u) >> 1);
      else if (t === 4) { const pp = a + u - c, pa = Math.abs(pp - a), pb = Math.abs(pp - u), pc = Math.abs(pp - c); v = x + (pa <= pb && pa <= pc ? a : pb <= pc ? u : c); }
      cur[i] = v & 255;
    }
    up = cur;
  }
  return out;
}

/** The stream's decoded bytes, or null when a filter in its chain is an image codec or unknown, or the data is bad. */
export async function decodePdfStream(dict: string, body: Uint8Array): Promise<Uint8Array | null> {
  let b: Uint8Array = body;
  const fs = filtersOf(dict);
  if (fs.length > MAX_CHAIN) return null;
  try {
    for (let i = 0; i < fs.length; i++) {
      const p = parmsOf(dict, i);
      switch (fs[i]) {
        case 'FlateDecode': { const d = (await inflate(b, 'deflate', DECODE_CAP)) ?? (await inflate(b, 'deflate-raw', DECODE_CAP)); if (!d) return null; b = unpredict(d, p); break; }
        case 'ASCII85Decode': b = ascii85(b); break;
        case 'ASCIIHexDecode': b = asciiHex(b); break;
        case 'LZWDecode': b = unpredict(lzw(b, p.EarlyChange ?? 1), p); break;
        case 'RunLengthDecode': b = runLength(b); break;
        default: return null;                                        // DCT, JPX, CCITT, JBIG2, Crypt, unknown
      }
    }
  } catch (_e) { return null; }
  return b;
}
