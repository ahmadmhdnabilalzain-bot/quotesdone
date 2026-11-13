// pdf_text_positions — a PDF's text layer WITH page coordinates, deterministically (14 Sep 2026).
//
// WHY. drawing_redact blacks out identity on rasterised drawing pages using boxes a vision model
// names, and every model route is held — so redaction verified nothing (pages_out=0) and a drawing
// could not reach a supplier. A drawing exported from CAD or a PDF writer usually carries its title
// block (consultant, client, phone, email, "Drawn by") as REAL TEXT. That text has a position, and a
// position can be mapped onto the rasterised page and boxed without any model.
//
// WHAT IT READS. Page tree order (Catalog -> /Pages -> /Kids, inheriting /MediaBox, /Rotate and
// /Resources), each page's /Contents (FlateDecode or raw), object streams (PDF 1.5+ hides page dicts
// in them), the text operators BT/ET, Tf, TL, Td, TD, Tm, T*, Tj, TJ, ', " under q/Q/cm, and — since
// 21 Sep 2026 — FORM XOBJECTS (`Do`), followed recursively with their /Matrix and their own
// /Resources, plus fonts' /ToUnicode maps (1- and 2-byte codes, Identity-H).
//
// 21 SEP 2026 (sales_engineer, founder instruction 580). MEASURED on two real US bid sets (a 36x24
// mechanical permit set of 8 sheets and a plumbing bid set of 5, every page /Rotate 270): this reader
// returned 8,005 of 36,949 characters (22 %) and 9,185 of 12,853 (71 %), and ZERO characters on every
// plan and schedule sheet after the first, because CAD writes each sheet's text inside Form XObjects
// and the old header named exactly that ceiling ("Text inside Form XObjects is not followed"). A drawing
// set read that way yields no tags, no scale, no title block — 0 of 49 answer-key items.
//
// COORDINATES ARE IN THE DISPLAY FRAME. Runs, images and lines are normalised 0..1 with a top-left
// origin AS THE PAGE IS SHOWN, i.e. after the page's /Rotate — the same frame pdf.js renders, which is
// the raster the portal uploads and drawing_redact paints on. Before 21 Sep a rotated page's runs were
// in the unrotated frame, so every caller had to refuse rotated pages (a box would land a quarter turn
// out); all 13 sheets of both real sets are rotated, so 0 of 13 pages could ever reach a supplier.
// `rotate` is still reported, as information. `width`/`height` stay the MediaBox (pdf_measure's paths
// are in that frame and it reads the page's own content stream, unchanged).
//
// A run's box is the bounding box of its glyph quad (text matrix x CTM, 4 corners), so text drawn at
// any angle gets an honest box. `vertical` marks a run whose baseline is not horizontal as displayed.
//
// CEILINGS, stated so nobody treats a box from here as exact:
//  * Glyph widths are ESTIMATED (0.6 em per character) — no font metrics are read. Callers pad.
//  * Text drawn as vector strokes (SHX fonts) or inside raster images has no text layer at all; those
//    are read by OCR in the portal (ocrClient.ocrSchedules), never here.
//  * A page stops being read after MAX_OPS operators (its `truncated` flag says so), never silently.
// ponytail: full-buffer object regex, no xref parsing; fine for a drawing set of tens of MB.
import { unescapePdfString, hexToString } from './pdf_text.ts';
import { decodePdfStream } from './pdf_filters.ts';

export type TextRun = { text: string; x: number; y: number; w: number; h: number; vertical?: boolean; at?: string; quad?: [number, number][] };
// `quad` (13 Nov 2026): the glyph quad of a run drawn at an angle that is not a quarter turn, in the display frame
// (baseline start, baseline end, top end, top start). The box above is its axis-aligned bounding box, which for the
// auditor's 28-degree watermark was 66% x 42% of the sheet; a redactor that covers the quad instead keeps Section A-A. // at: "<stream>:<op>" (pdf_vector_redact.ts) // display frame, normalised 0..1, top-left origin
/** An image painted on the page (a logo, a stamp, a scanned schedule): its placement box and pixel size. */
export type PdfImage = { x: number; y: number; w: number; h: number; px: number; py: number; at?: string; name?: string };
/** A straight stroked or filled edge, display frame, normalised. Only axis-aligned ones are kept. */
export type PdfLine = { x1: number; y1: number; x2: number; y2: number };
/** CAD layer geometry (22 Sep 2026): every STROKED segment drawn inside an optional-content group,
 *  keyed by the layer's name ("M-HVAC-DUCT", "P-SANR"), as flat [x1,y1,x2,y2,...] in the display frame,
 *  normalised. Curves are flattened (8 chords). Only present when the PDF carries layers.
 *  `layerWidths` holds each segment's stroke width in paper points, same order (one number each): a CAD
 *  single-line duct is a heavy line and a leader on the same annotation layer is a hairline. */
export type LayerSegs = Record<string, number[]>;
/** A small closed outline (a keyed-note hexagon, a tag circle): its box, its vertex count and its layer. */
export type PdfMark = { x: number; y: number; w: number; h: number; n: number; layer: string };
/** A painted path (pdf_vector_redact.ts): where it was drawn, its operator indexes, its exact source text, and its
 *  display-frame box. Collected only by pdfRedactionView; `clip` paths are never removed. */
export type PdfPath = { at: string; ops: number[]; text: string; x: number; y: number; w: number; h: number; clip: boolean };
export type PdfPage = { width: number; height: number; rotate: number; runs: TextRun[]; undecodable?: number; glyphRows?: { x: number; y: number; w: number; h: number }[]; images?: PdfImage[]; lines?: PdfLine[]; layers?: LayerSegs; layerWidths?: LayerSegs; marks?: PdfMark[]; truncated?: boolean; paths?: PdfPath[] };

const DEC = new TextDecoder('latin1');
type Obj = { dict: string; stream: Uint8Array | null };
type M = [number, number, number, number, number, number];
const mul = (a: M, b: M): M => [a[0] * b[0] + a[1] * b[2], a[0] * b[1] + a[1] * b[3], a[2] * b[0] + a[3] * b[2], a[2] * b[1] + a[3] * b[3], a[4] * b[0] + a[5] * b[2] + b[4], a[4] * b[1] + a[5] * b[3] + b[5]];
const ID: M = [1, 0, 0, 1, 0, 0];
/** Operators interpreted per page, forms included. A dense A1/ANSI-D CAD sheet measured ~1.5M. */
export const MAX_OPS = 4_000_000;
const MAX_FORM_DEPTH = 12;
/** Stroked segments kept per page across all layers (4 numbers each), so a pathological file cannot
 *  exhaust memory; past it the page is marked truncated. */
export const MAX_LAYER_SEGS = 600_000;

// The whole filter chain since 13 Nov 2026 (pdf_filters.ts): Flate alone read a reportlab PDF's ASCII85+Flate
// streams as nothing, and its vector sheet went down the scan route (anonymity audit B, G2; audit A, L5).
const decodeStream = (dict: string, body: Uint8Array): Promise<Uint8Array | null> => decodePdfStream(dict, body);

async function readObjects(bytes: Uint8Array): Promise<Map<number, Obj>> {
  const raw = DEC.decode(bytes);
  const objs = new Map<number, Obj>();
  const re = /(\d+)\s+\d+\s+obj\b/g;
  let m: RegExpExecArray | null;
  // /Length IS HONOURED (13 Nov 2026, independent review of the anonymity fix, item 4): a stream used to end at the
  // first "endstream" after its start, so a note printed as "(SEE SPEC endstream endobj)" ended the content stream
  // there and the owner line after it was never read, while every viewer drew it. A direct /Length is used when
  // "endstream" follows it; an indirect one is resolved once every object is read; only a length that does not
  // check out falls back to the scan.
  const fixLen: { num: number; ref: number; dataStart: number }[] = [];
  const endsAt = (at: number) => { let k = at; while (k < raw.length && (raw[k] === '\r' || raw[k] === '\n' || raw[k] === ' ')) k++; return raw.startsWith('endstream', k) ? k : -1; };
  const trim = (from: number, to: number) => { while (to > from && (bytes[to - 1] === 10 || bytes[to - 1] === 13)) to--; return to; };
  while ((m = re.exec(raw)) !== null) {
    const start = m.index + m[0].length;
    const firstEnd = raw.indexOf('endobj', start);
    if (firstEnd < 0) break;
    const sm = /\bstream\r?\n/.exec(raw.slice(start, firstEnd));
    let stream: Uint8Array | null = null; let dict = raw.slice(start, firstEnd); let end = firstEnd;
    if (sm) {
      dict = raw.slice(start, start + sm.index);
      const dataStart = start + sm.index + sm[0].length;
      const lm = /\/Length\s+(\d+)(\s+\d+\s+R)?/.exec(dict);
      let dataEnd = -1;
      if (lm && !lm[2]) { const n = Number(lm[1]); if (endsAt(dataStart + n) >= 0) dataEnd = dataStart + n; }
      if (dataEnd < 0) {
        if (lm && lm[2]) fixLen.push({ num: Number(m[1]), ref: Number(lm[1]), dataStart });
        const es = raw.indexOf('endstream', dataStart);
        dataEnd = trim(dataStart, es < 0 ? firstEnd : es);
      }
      stream = bytes.subarray(dataStart, dataEnd);
      const after = endsAt(dataEnd);
      const oe = raw.indexOf('endobj', after >= 0 ? after : dataEnd);
      end = oe < 0 ? firstEnd : oe;
    }
    objs.set(Number(m[1]), { dict, stream });
    re.lastIndex = end;
  }
  for (const f of fixLen) {
    const n = Number(((objs.get(f.ref)?.dict || '').match(/^\s*(\d+)\s*$/) || [])[1]);
    if (Number.isFinite(n) && endsAt(f.dataStart + n) >= 0) { const o = objs.get(f.num)!; objs.set(f.num, { ...o, stream: bytes.subarray(f.dataStart, f.dataStart + n) }); }
  }
  // Object streams: "n1 off1 n2 off2 ... " header, then the objects back to back.
  for (const o of [...objs.values()]) {
    if (!o.stream || !/\/Type\s*\/ObjStm\b/.test(o.dict)) continue;
    const dec = await decodeStream(o.dict, o.stream); if (!dec) continue;
    const s = DEC.decode(dec);
    const n = Number((o.dict.match(/\/N\s+(\d+)/) || [])[1] || 0);
    const first = Number((o.dict.match(/\/First\s+(\d+)/) || [])[1] || 0);
    const head = s.slice(0, first).trim().split(/\s+/).map(Number);
    for (let i = 0; i < n; i++) {
      const num = head[2 * i], off = head[2 * i + 1];
      const next = i + 1 < n ? head[2 * i + 3] : s.length - first;
      if (!objs.has(num)) objs.set(num, { dict: s.slice(first + off, first + next), stream: null });
    }
  }
  return objs;
}

const refs = (s: string) => [...s.matchAll(/(\d+)\s+\d+\s+R/g)].map((x) => Number(x[1]));
const numArr = (s: string | undefined) => (s || '').trim().split(/\s+/).map(Number).filter((n) => Number.isFinite(n));

/** The value of `/Key` in a dictionary source: a balanced `<< >>`, an array, a ref (resolved), or a token. */
function dictValue(objs: Map<number, Obj>, d: string, key: string, resolve = true): string | null {
  const re = new RegExp('/' + key + '(?![A-Za-z0-9])\\s*');
  const m = re.exec(d); if (!m) return null;
  let i = m.index + m[0].length;
  if (d.startsWith('<<', i)) {
    let depth = 0, j = i;
    while (j < d.length) { if (d.startsWith('<<', j)) { depth++; j += 2; continue; } if (d.startsWith('>>', j)) { depth--; j += 2; if (!depth) break; continue; } j++; }
    return d.slice(i, j);
  }
  if (d[i] === '[') { const j = d.indexOf(']', i); return d.slice(i, j < 0 ? d.length : j + 1); }
  const r = /^(\d+)\s+\d+\s+R/.exec(d.slice(i, i + 40));
  if (r) { if (!resolve) return r[0]; const o = objs.get(Number(r[1])); return o ? o.dict : null; }
  const t = /^\/?[^\s\/\[\]<>()]+/.exec(d.slice(i, i + 80)); return t ? t[0] : null;
}
/** name -> object number for a resource sub-dictionary (/XObject or /Font). */
function namedRefs(objs: Map<number, Obj>, res: string, key: string): Map<string, number> {
  const out = new Map<string, number>();
  const sub = dictValue(objs, res, key); if (!sub) return out;
  for (const m of sub.matchAll(/\/([^\s\/\[\]<>()]+)\s+(\d+)\s+\d+\s+R/g)) out.set(m[1], Number(m[2]));
  return out;
}

type PageRef = { num: number; mb: number[]; rotate: number; res: string };
function pageTree(objs: Map<number, Obj>): PageRef[] {
  const out: PageRef[] = [];
  const cat = [...objs.entries()].find(([, o]) => /\/Type\s*\/Catalog\b/.test(o.dict));
  const rootRef = cat ? refs((cat[1].dict.match(/\/Pages\s+\d+\s+\d+\s+R/) || [''])[0])[0] : undefined;
  const seen = new Set<number>();
  const walk = (num: number, mb: number[], rot: number, res: string) => {
    if (seen.has(num)) return; seen.add(num);
    const o = objs.get(num); if (!o) return;
    const d = o.dict;
    const myMb = numArr((d.match(/\/MediaBox\s*\[([^\]]*)\]/) || [])[1]);
    const mbx = myMb.length === 4 ? myMb : mb;
    const r = d.match(/\/Rotate\s+(-?\d+)/); const rr = r ? Number(r[1]) : rot;
    const myRes = dictValue(objs, d, 'Resources') ?? res;
    if (/\/Type\s*\/Pages\b/.test(d)) { for (const k of refs((d.match(/\/Kids\s*\[([^\]]*)\]/) || ['', ''])[1])) walk(k, mbx, rr, myRes); }
    else if (/\/Type\s*\/Page\b/.test(d)) out.push({ num, mb: mbx, rotate: ((rr % 360) + 360) % 360, res: myRes });
  };
  if (rootRef !== undefined) walk(rootRef, [0, 0, 612, 792], 0, '');
  if (!out.length) for (const [num, o] of objs) if (/\/Type\s*\/Page\b(?!s)/.test(o.dict)) walk(num, [0, 0, 612, 792], 0, '');
  return out;
}

// Tokeniser for a content stream: numbers, names, strings, arrays (as raw source), operators.
// `p` / `e`: the token's start and end offsets in `src` (pdf_vector_redact.ts cuts operators out by them).
function* tokens(src: string): Generator<{ t: 'num' | 'str' | 'arr' | 'op' | 'name'; v: string; p: number; e: number; d?: string }> {
  let i = 0; const n = src.length;
  while (i < n) {
    const c = src[i];
    if (c === ' ' || c === '\n' || c === '\r' || c === '\t' || c === '\f' || c === '\0') { i++; continue; }
    if (c === '%') { while (i < n && src[i] !== '\n' && src[i] !== '\r') i++; continue; }
    if (c === '(') {
      let depth = 1, j = i + 1, s = '';
      while (j < n && depth) { const d = src[j]; if (d === '\\') { s += d + (src[j + 1] ?? ''); j += 2; continue; } if (d === '(') depth++; else if (d === ')') { depth--; if (!depth) break; } s += d; j++; }
      yield { t: 'str', v: unescapePdfString(s), p: i, e: j + 1 }; i = j + 1; continue;
    }
    if (c === '<' && src[i + 1] !== '<') { const j = src.indexOf('>', i); yield { t: 'str', v: hexToString(src.slice(i + 1, j < 0 ? n : j)), p: i, e: j < 0 ? n : j + 1 }; i = j < 0 ? n : j + 1; continue; }
    if (c === '<' || c === '>') { i += 2; continue; }                       // dictionary delimiters (inline images' BI dicts are rare in drawings)
    if (c === '[') {
      let depth = 1, j = i + 1;
      while (j < n && depth) { const d = src[j]; if (d === '(') { let pd = 1; j++; while (j < n && pd) { if (src[j] === '\\') j++; else if (src[j] === '(') pd++; else if (src[j] === ')') pd--; j++; } continue; } if (d === '[') depth++; else if (d === ']') depth--; j++; }
      yield { t: 'arr', v: src.slice(i + 1, j - 1), p: i, e: j }; i = j; continue;
    }
    if (c === '/') { let j = i + 1; while (j < n && !/[\s\/\[\]()<>{}%]/.test(src[j])) j++; yield { t: 'name', v: src.slice(i + 1, j), p: i, e: j }; i = j; continue; }
    let j = i; while (j < n && !/[\s\/\[\]()<>{}%]/.test(src[j])) j++;
    if (j === i) { i++; continue; }
    const w = src.slice(i, j); const p0 = i; i = j;
    // AN INLINE IMAGE IS ONE OPERATOR, ITS BYTES SKIPPED (13 Nov 2026, independent review item 1): BI <dict> ID <data> EI
    // was tokenised as text, so a "(" in one image's bytes and a ")" in a later one's swallowed the owner line drawn
    // between them, and an inline-image map was never reported as a picture. It is now yielded as 'BI_IMG' with its
    // dictionary, spanning to the EI, and the interpreter reports it as an image like any XObject.
    if (w === 'BI') {
      const id = /\sID[\s]/.exec(src.slice(j));
      if (!id) { i = n; continue; }
      const dict = src.slice(j, j + id.index);
      const dataStart = j + id.index + id[0].length;
      const len = Number((dict.match(/\/L(?:ength)?\s+(\d+)/) || [])[1]);
      let ei = -1;
      if (Number.isFinite(len) && len > 0) { const k = dataStart + len; const mm = /^\s*EI(?=[\s]|$)/.exec(src.slice(k, k + 8)); if (mm) ei = k + mm[0].length; }
      if (ei < 0) { const mm = /\sEI(?=[\s]|$)/.exec(src.slice(dataStart)); ei = mm ? dataStart + mm.index + mm[0].length : n; }
      yield { t: 'op', v: 'BI_IMG', p: p0, e: ei, d: dict }; i = ei; continue;
    }
    const c0 = w.charCodeAt(0);
    yield { p: p0, e: j, t: (c0 >= 48 && c0 <= 57) || c0 === 45 || c0 === 43 || c0 === 46 ? (/^[+-]?(\d+\.?\d*|\.\d+)$/.test(w) ? 'num' : 'op') : 'op', v: w };
  }
}

// ── fonts: /ToUnicode CMaps (bfchar / bfrange), code width from the codespace ─────────────────────
type Font = { two: boolean; map: Map<number, string> | null; undecodable?: boolean };
const hexCode = (h: string) => parseInt(h, 16);
const utf16 = (h: string) => { let s = ''; for (let i = 0; i + 3 < h.length; i += 4) s += String.fromCharCode(parseInt(h.slice(i, i + 4), 16)); return s; };
function parseCMap(src: string): { two: boolean; map: Map<number, string> } {
  const map = new Map<number, string>();
  const cs = src.match(/begincodespacerange\s*<([0-9A-Fa-f]+)>/);
  const two = cs ? cs[1].length >= 4 : false;
  for (const blk of src.matchAll(/beginbfchar([\s\S]*?)endbfchar/g)) for (const m of blk[1].matchAll(/<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]*)>/g)) map.set(hexCode(m[1]), utf16(m[2]));
  for (const blk of src.matchAll(/beginbfrange([\s\S]*?)endbfrange/g)) {
    for (const m of blk[1].matchAll(/<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*(<([0-9A-Fa-f]+)>|\[([^\]]*)\])/g)) {
      const lo = hexCode(m[1]), hi = Math.min(hexCode(m[2]), lo + 0xffff);
      if (m[4] !== undefined) { const base = parseInt(m[4].slice(-4) || '0', 16); const pre = utf16(m[4].slice(0, -4)); for (let c = lo; c <= hi; c++) map.set(c, pre + String.fromCharCode(base + (c - lo))); }
      else { const items = [...(m[5] || '').matchAll(/<([0-9A-Fa-f]*)>/g)].map((x) => utf16(x[1])); for (let c = lo; c <= hi && c - lo < items.length; c++) map.set(c, items[c - lo]); }
    }
  }
  return { two, map };
}

type Ctx = { objs: Map<number, Obj>; forms: Map<number, string | null>; fonts: Map<number, Font>; ocg: Map<number, string | null>; ops: number; truncated: boolean; segs: number; layers: boolean; paths?: boolean; undecodable?: number };
async function fontOf(ctx: Ctx, num: number): Promise<Font> {
  const hit = ctx.fonts.get(num); if (hit) return hit;
  const o = ctx.objs.get(num); let f: Font = { two: false, map: null };
  if (o) {
    const two = /\/Identity-[HV]\b/.test(o.dict) || /\/Subtype\s*\/Type0\b/.test(o.dict);
    const tu = /\/ToUnicode\s+(\d+)\s+\d+\s+R/.exec(o.dict);
    const cm = tu ? ctx.objs.get(Number(tu[1])) : null;
    const dec = cm?.stream ? await decodeStream(cm.dict, cm.stream) : null;
    if (dec) { const p = parseCMap(DEC.decode(dec)); f = { two: two || p.two, map: p.map.size ? p.map : null }; } else f = { two, map: null };
    // TEXT NO READER CAN DECODE (13 Nov 2026, review item 2): a Type3 font, a composite font with no ToUnicode, or a
    // simple font whose /Differences rename glyphs (/g1../gN) draws words a viewer shows and this reader cannot read.
    // The run is still reported (its position is real); the page is marked, and titleBlockBoxes lowers its confidence.
    const diffs = /\/Differences\s*\[([^\]]*)\]/.exec(o.dict)?.[1] || (/\/Encoding\s+(\d+)\s+\d+\s+R/.exec(o.dict) ? (/\/Differences\s*\[([^\]]*)\]/.exec(ctx.objs.get(Number(/\/Encoding\s+(\d+)/.exec(o.dict)![1]))?.dict || '')?.[1] || '') : '');
    const oddNames = (diffs.match(/\/[A-Za-z0-9_.]+/g) || []).filter((n) => /^\/(?:g|glyph|cid|c|G|index)\d+$|^\/[A-Za-z]?\d+$/.test(n)).length;
    if (!f.map && (/\/Subtype\s*\/Type3\b/.test(o.dict) || f.two || oddNames >= 3)) f.undecodable = true;
  }
  ctx.fonts.set(num, f); return f;
}
function decodeText(f: Font | null, s: string): string {
  if (!f || (!f.map && !f.two)) return s;
  let out = '';
  if (f.two) { for (let i = 0; i + 1 < s.length; i += 2) { const c = (s.charCodeAt(i) << 8) | s.charCodeAt(i + 1); out += f.map?.get(c) ?? ''; } return out; }
  for (let i = 0; i < s.length; i++) { const c = s.charCodeAt(i); out += f.map!.get(c) ?? s[i]; }
  return out;
}

function arrPieces(a: string): { s: string; gap: boolean }[] {
  const out: { s: string; gap: boolean }[] = [];
  for (const t of tokens(a)) { if (t.t === 'str') out.push({ s: t.v, gap: false }); else if (t.t === 'num' && Number(t.v) <= -200) out.push({ s: '', gap: true }); }
  return out;
}

async function formContent(ctx: Ctx, num: number): Promise<string | null> {
  if (ctx.forms.has(num)) return ctx.forms.get(num)!;
  const o = ctx.objs.get(num); let src: string | null = null;
  if (o?.stream && /\/Subtype\s*\/Form\b/.test(o.dict)) { const d = await decodeStream(o.dict, o.stream); src = d ? DEC.decode(d) : null; }
  ctx.forms.set(num, src); return src;
}

/** Interpret one content stream (a page's, or a form's) into runs, images and axis-aligned lines. */
async function interpret(ctx: Ctx, src: string, res: string, ctm0: M, depth: number, emit: {
  run: (text: string, m: M, size: number, n: number, at: string) => void; image: (m: M, px: number, py: number, at: string, name: string) => void; seg: (x1: number, y1: number, x2: number, y2: number) => void;
  layerSeg: (layer: string, x1: number, y1: number, x2: number, y2: number, width: number) => void; mark: (layer: string, pts: [number, number][]) => void;
  fill?: (pts: [number, number][]) => void;
  paint?: (at: string, ops: number[], text: string, pts: [number, number][], clip: boolean) => void;
}, active: Set<number>, layer0 = '', lw0 = 1, sid = 'p'): Promise<void> {
  let ctm: M = ctm0; const stack: [M, number][] = []; let lw = lw0; let opn = 0;
  let tm: M = ID, tlm: M = ID; let size = 12, lead = 0; let font: Font | null = null;
  let nums: number[] = []; let pStr: string | undefined; let pArr: string | undefined; let pName: string | undefined;
  const xobjs = namedRefs(ctx.objs, res, 'XObject');
  const fontRefs = namedRefs(ctx.objs, res, 'Font');
  // Optional content (CAD layers): `/OC /MC0 BDC ... EMC`, MC0 named in the resources' /Properties and
  // pointing at an OCG whose /Name is the layer. Measured 22 Sep 2026 on the two real bid sets: 57 and
  // 50 layers, among them M-HVAC-DUCT, P-SANR, P-VENT, P-DOMW-CW, P-DOMW-HW - the system each line is.
  const props = namedRefs(ctx.objs, res, 'Properties');
  const layers: string[] = []; let layer = layer0;
  const ocgName = (num: number | undefined): string | null => {
    if (num === undefined) return null;
    if (ctx.ocg.has(num)) return ctx.ocg.get(num)!;
    const d = ctx.objs.get(num)?.dict || '';
    const m = /\/Name\s*\(((?:\\.|[^\\)])*)\)/.exec(d);
    const h = m ? null : /\/Name\s*<([0-9A-Fa-f]+)>/.exec(d);
    const nm = /\/Type\s*\/OCG\b/.test(d) ? (m ? unescapePdfString(m[1]) : h ? hexToString(h[1]) : '').replace(/^\xfe\xff/, '').replace(/\x00/g, '') : null;
    ctx.ocg.set(num, nm); return nm;
  };
  let path: [number, number][][] = []; let curPath: [number, number][] | null = null;
  const T = (x: number, y: number): [number, number] => [ctm[0] * x + ctm[2] * y + ctm[4], ctm[1] * x + ctm[3] * y + ctm[5]];
  // `decoded` is already through decodeText (Tj/'/" and each TJ piece are decoded by the caller).
  // Measured 21 Sep 2026 (sales_engineer, drawing_chain.test.ts): decoding it a SECOND time here
  // turned every Type0 / Identity-H run into '' — our own inquiry PDF (Sora, Identity-H) read back
  // as 0 runs on both pages — and remapped 1-byte ToUnicode runs through their map twice.
  const show = (decoded: string) => {
    const text = decoded.replace(/[\x00-\x08\x0b\x0c\x0e-\x1f]/g, '');
    const n = text.length;
    if (font?.undecodable && text.trim()) ctx.undecodable = (ctx.undecodable || 0) + 1;
    if (text.trim()) emit.run(text, mul(tm, ctm), size, n, `${sid}:${opn}`);
    tm = mul([1, 0, 0, 1, n * 0.6 * size, 0], tm);
  };
  const newline = (tx: number, ty: number) => { tlm = mul([1, 0, 0, 1, tx, ty], tlm); tm = tlm; };
  const flushPath = (stroked: boolean) => {
    for (const sp of path) {
      for (let i = 1; i < sp.length; i++) emit.seg(sp[i - 1][0], sp[i - 1][1], sp[i][0], sp[i][1]);
      if (layer && stroked && ctx.layers) { const wd = lw * Math.sqrt(Math.abs(ctm[0] * ctm[3] - ctm[1] * ctm[2])); for (let i = 1; i < sp.length; i++) emit.layerSeg(layer, sp[i - 1][0], sp[i - 1][1], sp[i][0], sp[i][1], wd); }
      if (layer && sp.length >= 5 && sp[0][0] === sp[sp.length - 1][0] && sp[0][1] === sp[sp.length - 1][1]) emit.mark(layer, sp);
      if (!stroked && emit.fill && sp.length >= 3) emit.fill(sp);
    }
    path = []; curPath = null;
  };
  // Curves are flattened into chords so a duct elbow or a round bubble keeps its true length and shape.
  const bez = (p1: [number, number], p2: [number, number], p3: [number, number]) => {
    if (!curPath) return; const p0 = curPath[curPath.length - 1];
    for (let i = 1; i <= 8; i++) { const t = i / 8, u = 1 - t; const k0 = u * u * u, k1 = 3 * u * u * t, k2 = 3 * u * t * t, k3 = t * t * t; curPath.push([k0 * p0[0] + k1 * p1[0] + k2 * p2[0] + k3 * p3[0], k0 * p0[1] + k1 * p1[1] + k2 * p2[1] + k3 * p3[1]]); }
  };
  // The path being built, for emit.paint: its first operand's offset, its operator indexes, whether it clips.
  let argStart = -1, pathStart = -1, pathOps: number[] = [], pathClip = false;
  const painted = (tk: { e: number }) => {
    if (emit.paint && pathOps.length && pathStart >= 0) emit.paint(sid, [...pathOps, opn], src.slice(pathStart, tk.e), path.flat(), pathClip);
    pathOps = []; pathStart = -1; pathClip = false;
  };
  for (const tk of tokens(src)) {
    if (tk.t !== 'op' && argStart < 0) argStart = tk.p;
    if (tk.t === 'num') { nums.push(Number(tk.v)); continue; }
    if (tk.t === 'str') { pStr = tk.v; continue; }
    if (tk.t === 'arr') { pArr = tk.v; continue; }
    if (tk.t === 'name') { pName = tk.v; continue; }
    if (++ctx.ops > MAX_OPS) { ctx.truncated = true; return; }
    opn++;
    const opStart = argStart >= 0 ? argStart : tk.p; argStart = -1;
    if (/^(?:m|l|c|v|y|re|h)$/.test(tk.v)) { if (!pathOps.length) pathStart = opStart; pathOps.push(opn); }
    else if (tk.v === 'W' || tk.v === 'W*') { pathClip = true; pathOps.push(opn); }
    else if (/^(?:S|s|B|B\*|b|b\*|f|F|f\*)$/.test(tk.v)) painted(tk);
    else if (tk.v === 'n') { pathOps = []; pathStart = -1; pathClip = false; }
    const a = nums; const str = pStr; const arr = pArr; const name = pName;
    nums = []; pStr = undefined; pArr = undefined; pName = undefined;
    switch (tk.v) {
      case 'q': stack.push([ctm, lw]); break;
      case 'Q': { const g = stack.pop(); ctm = g ? g[0] : ctm0; lw = g ? g[1] : lw0; } break;
      case 'w': if (a.length) lw = a[a.length - 1]; break;
      case 'cm': if (a.length >= 6) ctm = mul(a.slice(-6) as M, ctm); break;
      case 'BT': tm = ID; tlm = ID; break;
      case 'Tf': {
        if (a.length) size = a[a.length - 1] || size;
        const fr = name !== undefined ? fontRefs.get(name) : undefined;
        font = fr !== undefined ? await fontOf(ctx, fr) : null;
      } break;
      case 'TL': if (a.length) lead = a[0]; break;
      case 'Td': if (a.length >= 2) newline(a[0], a[1]); break;
      case 'TD': if (a.length >= 2) { lead = -a[1]; newline(a[0], a[1]); } break;
      case 'Tm': if (a.length >= 6) { tlm = a.slice(-6) as M; tm = tlm; } break;
      case 'T*': newline(0, -lead); break;
      case 'Tj': if (str !== undefined) show(decodeText(font, str)); break;
      case "'": newline(0, -lead); if (str !== undefined) show(decodeText(font, str)); break;
      case '"': newline(0, -lead); if (str !== undefined) show(decodeText(font, str)); break;
      case 'TJ': if (arr !== undefined) {
        // A TJ array is one run unless a large kerning gap splits it into words.
        let acc = ''; for (const p of arrPieces(arr)) acc += p.gap ? ' ' : decodeText(font, p.s);
        show(acc);
      } break;
      case 'm': if (a.length >= 2) { curPath = [T(a[0], a[1])]; path.push(curPath); } break;
      case 'l': if (a.length >= 2) { if (!curPath) { curPath = [T(a[0], a[1])]; path.push(curPath); } else curPath.push(T(a[0], a[1])); } break;
      case 'c': if (a.length >= 6 && curPath) bez(T(a[0], a[1]), T(a[2], a[3]), T(a[4], a[5])); break;
      case 'v': if (a.length >= 4 && curPath) bez(curPath[curPath.length - 1], T(a[0], a[1]), T(a[2], a[3])); break;
      case 'y': if (a.length >= 4 && curPath) bez(T(a[0], a[1]), T(a[2], a[3]), T(a[2], a[3])); break;
      case 're': if (a.length >= 4) { const [x, y, w, h] = a; path.push([T(x, y), T(x + w, y), T(x + w, y + h), T(x, y + h), T(x, y)]); curPath = null; } break;
      case 'h': if (curPath && curPath.length > 1) curPath.push(curPath[0]); break;
      case 'S': case 's': case 'B': case 'B*': case 'b': case 'b*': flushPath(true); break;
      case 'f': case 'F': case 'f*': flushPath(false); break;
      case 'BDC': { layers.push(layer); const nm = name !== undefined ? ocgName(props.get(name)) : null; if (nm) layer = nm; } break;
      case 'BMC': layers.push(layer); break;
      case 'EMC': layer = layers.length ? layers.pop()! : layer0; break;
      case 'n': path = []; curPath = null; break;
      case 'BI_IMG': {
        const d = tk.d || '';
        const px = Number((d.match(/\/W(?:idth)?\s+(\d+)/) || [])[1] || 0), py = Number((d.match(/\/H(?:eight)?\s+(\d+)/) || [])[1] || 0);
        emit.image(ctm, px, py, `${sid}:${opn}`, '__inline');
      } break;
      case 'Do': {
        if (name === undefined) break;
        const num = xobjs.get(name); if (num === undefined) break;
        const o = ctx.objs.get(num); if (!o) break;
        if (/\/Subtype\s*\/Image\b/.test(o.dict)) {
          const px = Number((o.dict.match(/\/Width\s+(\d+)/) || [])[1] || 0), py = Number((o.dict.match(/\/Height\s+(\d+)/) || [])[1] || 0);
          emit.image(ctm, px, py, `${sid}:${opn}`, name); break;
        }
        if (depth >= MAX_FORM_DEPTH || active.has(num)) break;
        const fsrc = await formContent(ctx, num); if (fsrc === null) break;
        const mtx = numArr((o.dict.match(/\/Matrix\s*\[([^\]]*)\]/) || [])[1]);
        const fres = dictValue(ctx.objs, o.dict, 'Resources') ?? res;
        active.add(num);
        await interpret(ctx, fsrc, fres, mul(mtx.length === 6 ? mtx as M : ID, ctm), depth + 1, emit, active, layer, lw, 'f' + num);
        active.delete(num);
        if (ctx.truncated) return;
      } break;
    }
  }
}

/** Normalised display-frame point from a user-space point, for a page's MediaBox and /Rotate. */
export function toDisplay(x: number, y: number, mb: number[], rotate: number): [number, number] {
  const [x0, y0, x1, y1] = mb; const W = (x1 - x0) || 1, H = (y1 - y0) || 1;
  const u = (x - x0) / W, v = 1 - (y - y0) / H;                       // unrotated, top-left origin
  switch (rotate) {
    case 90: return [1 - v, u];
    case 180: return [1 - u, 1 - v];
    case 270: return [v, 1 - u];
    default: return [u, v];
  }
}

async function readPage(ctx: Ctx, p: PageRef): Promise<{ page: PdfPage; content: string }> {
  const d = ctx.objs.get(p.num)!.dict;
  const cm = d.match(/\/Contents\s*(\[[^\]]*\]|\d+\s+\d+\s+R)/);
  let src = '';
  // /Contents may name an ARRAY OBJECT ("/Contents 28 0 R" where 28 is "[2 0 R 3 0 R 4 0 R]"). Measured
  // 21 Sep 2026: that is how pages 2+ of both real bid sets are written, and reading 28 as a stream
  // read nothing — the other half of why those sheets returned zero characters.
  const contentRefs = (cm ? refs(cm[1]) : []).flatMap((r) => { const o = ctx.objs.get(r); return o && !o.stream && /^\s*\[/.test(o.dict) ? refs(o.dict) : [r]; });
  for (const r of contentRefs) {
    const o = ctx.objs.get(r); if (!o || !o.stream) continue;
    const dec = await decodeStream(o.dict, o.stream); if (dec) src += DEC.decode(dec) + '\n';
  }
  const runs: TextRun[] = []; const images: PdfImage[] = []; const lines: PdfLine[] = [];
  const layerSegs: LayerSegs = {}; const layerWidths: LayerSegs = {}; const marks: PdfMark[] = []; ctx.segs = 0; let paths: PdfPath[] | undefined;
  const D = (x: number, y: number) => toDisplay(x, y, p.mb, p.rotate);
  const box = (pts: [number, number][]) => {
    const xs = pts.map((q) => q[0]), ys = pts.map((q) => q[1]);
    const x = Math.min(...xs), y = Math.min(...ys); return { x, y, w: Math.max(...xs) - x, h: Math.max(...ys) - y };
  };
  ctx.ops = 0; ctx.truncated = false; ctx.undecodable = 0;
  const fills: { x: number; y: number; w: number; h: number }[] = [];
  const emitAll: Parameters<typeof interpret>[5] = {
    run: (text, m, size, n, where) => {
      const W = n * 0.6 * size;
      const at = (tx: number, ty: number) => D(m[0] * tx + m[2] * ty + m[4], m[1] * tx + m[3] * ty + m[5]);
      const q = [at(0, -0.2 * size), at(W, -0.2 * size), at(W, size), at(0, size)];
      const b = box(q);
      const base = [at(0, 0), at(W || 1, 0)];
      const vertical = (p.rotate % 180 === 0) ? Math.abs(m[1]) > Math.abs(m[0]) : Math.abs(m[0]) > Math.abs(m[1]);
      const ang = Math.atan2(base[1][1] - base[0][1], base[1][0] - base[0][0]) * 180 / Math.PI;
      const tilted = Math.abs(((ang % 90) + 90) % 90) > 2 && Math.abs(((ang % 90) + 90) % 90) < 88;
      runs.push({ text, ...b, ...(vertical ? { vertical: true } : {}), at: where, ...(tilted ? { quad: q as [number, number][] } : {}) });
    },
    image: (m, px, py, at, name) => { images.push({ ...box([D(m[4], m[5]), D(m[0] + m[4], m[1] + m[5]), D(m[2] + m[4], m[3] + m[5]), D(m[0] + m[2] + m[4], m[1] + m[3] + m[5])]), px, py, at, name }); },
    seg: (ax, ay, bx, by) => {
      const [x1, y1] = D(ax, ay), [x2, y2] = D(bx, by);
      const dx = Math.abs(x2 - x1), dy = Math.abs(y2 - y1);
      if ((dy < 1e-4 && dx >= 0.004) || (dx < 1e-4 && dy >= 0.004)) lines.push({ x1: Math.min(x1, x2), y1: Math.min(y1, y2), x2: Math.max(x1, x2), y2: Math.max(y1, y2) });
    },
    layerSeg: (l, ax, ay, bx, by, wd) => {
      if (++ctx.segs > MAX_LAYER_SEGS) { ctx.truncated = true; return; }
      const [x1, y1] = D(ax, ay), [x2, y2] = D(bx, by);
      if (x1 === x2 && y1 === y2) return;
      (layerSegs[l] ||= []).push(x1, y1, x2, y2); (layerWidths[l] ||= []).push(Math.round(wd * 100) / 100);
    },
    ...(ctx.paths ? { paint: (at: string, ops: number[], text: string, pts: [number, number][], clip: boolean) => { if (pts.length) (paths ||= []).push({ at, ops, text, clip, ...box(pts.map(([x, y]) => D(x, y))) }); } } : {}),
    mark: (l, pts) => {
      const b = box(pts.map(([x, y]) => D(x, y)));
      if (b.w < 0.02 && b.h < 0.02 && b.w > 0 && b.h > 0) marks.push({ ...b, n: pts.length - 1, layer: l });
    },
    fill: (pts) => { if (fills.length < 20000) { const b = box(pts.map(([x, y]) => D(x, y))); if (b.w < 0.012 && b.h < 0.012) fills.push(b); } },
  };
  await interpret(ctx, src, p.res, ID, 0, emitAll, new Set());
  // TILING PATTERNS (13 Nov 2026, review item 6): a pattern cell is a content stream of its own; one drew "ARJAN PLOT
  // 6512 VILLA" over a rectangle outside the strip and nothing read it. Each tiling pattern the page's resources name
  // is read like a form, at its /Matrix (pattern space = the page's default space), so its text is a run like any other.
  for (const num of namedRefs(ctx.objs, p.res, 'Pattern').values()) {
    const o = ctx.objs.get(num);
    if (!o?.stream || !/\/PatternType\s+1\b/.test(o.dict) || ctx.truncated) continue;
    if (!ctx.forms.has(num)) { const dd = await decodeStream(o.dict, o.stream); ctx.forms.set(num, dd ? DEC.decode(dd) : null); }
    const psrc = ctx.forms.get(num); if (!psrc) continue;
    const mtx = numArr((o.dict.match(/\/Matrix\s*\[([^\]]*)\]/) || [])[1]);
    await interpret(ctx, psrc, dictValue(ctx.objs, o.dict, 'Resources') ?? p.res, mtx.length === 6 ? mtx as M : ID, 1, emitAll, new Set([num]), '', 1, 'f' + num);
  }
  // TEXT DRAWN AS SHAPES (review item 2): a row of small filled shapes - an outlined label, a pixel-font name, a QR code
  // - is text no reader can read. Rows of 15 or more small fills, abutting along one band, are reported as glyph rows.
  const glyphRows: { x: number; y: number; w: number; h: number }[] = [];
  { const fs = fills.filter((f) => f.w > 0 || f.h > 0).sort((a, b) => (a.y + a.h / 2) - (b.y + b.h / 2) || a.x - b.x);
    let i = 0;
    while (i < fs.length) {
      const cy = fs[i].y + fs[i].h / 2; let j = i; while (j < fs.length && (fs[j].y + fs[j].h / 2) - cy <= 0.004) j++;
      const band = fs.slice(i, j).sort((a, b) => a.x - b.x);
      let run = [band[0]];
      const flush = () => { if (run.length >= 15) { const x0 = Math.min(...run.map((r) => r.x)), y0 = Math.min(...run.map((r) => r.y)); glyphRows.push({ x: x0, y: y0, w: Math.max(...run.map((r) => r.x + r.w)) - x0, h: Math.max(...run.map((r) => r.y + r.h)) - y0 }); } };
      for (let k = 1; k < band.length; k++) { if (band[k].x - (run[run.length - 1].x + run[run.length - 1].w) <= 0.008) run.push(band[k]); else { flush(); run = [band[k]]; } }
      if (run.length) flush();
      i = j;
    }
  }
  const hasLayers = Object.keys(layerSegs).length > 0;
  return { page: { width: p.mb[2] - p.mb[0], height: p.mb[3] - p.mb[1], rotate: p.rotate, runs, images, lines, ...(ctx.undecodable ? { undecodable: ctx.undecodable } : {}), ...(glyphRows.length ? { glyphRows } : {}), ...(hasLayers ? { layers: layerSegs, layerWidths } : {}), ...(marks.length ? { marks } : {}), ...(ctx.truncated ? { truncated: true } : {}), ...(paths ? { paths } : {}) }, content: src };
}

/** Pages in order, each with its text runs AND its decoded content stream (for pdf_measure's path
 *  operators). [] when unreadable. */
/** `only` = [from, to): interpret only those pages (0-based); the others come back as empty stubs in their
 *  place, so page indexes stay the same. 22 Sep 2026: drawing_redact parsed the WHOLE set on every 4-page
 *  call, which with the pixel work put each call past the edge CPU cap (HTTP 546 on production). */
export async function pdfPageContents(bytes: Uint8Array, only?: [number, number], opts: { layers?: boolean } = {}): Promise<{ page: PdfPage; content: string }[]> {
  if (!bytes || bytes.length < 5 || DEC.decode(bytes.subarray(0, 5)) !== '%PDF-') return [];
  const head = DEC.decode(bytes.subarray(0, Math.min(bytes.length, 4096)));
  if (/\/Encrypt\b/.test(head) || /\/Encrypt\b/.test(DEC.decode(bytes.subarray(Math.max(0, bytes.length - 4096))))) return [];
  const objs = await readObjects(bytes);
  const ctx: Ctx = { objs, forms: new Map(), fonts: new Map(), ocg: new Map(), ops: 0, truncated: false, segs: 0, layers: opts.layers !== false };
  const pages: { page: PdfPage; content: string }[] = [];
  const tree = pageTree(objs);
  for (let i = 0; i < tree.length; i++) {
    const p = tree[i];
    if (only && (i < only[0] || i >= only[1])) { pages.push({ page: { width: p.mb[2] - p.mb[0], height: p.mb[3] - p.mb[1], rotate: p.rotate, runs: [] }, content: '' }); continue; }
    pages.push(await readPage(ctx, p));
  }
  return pages;
}

/** What pdf_vector_redact.ts needs to cut a run out of the file: every page with its object number and
 *  decoded content, and the decoded source of every Form XObject the pages drew (by object number).
 *  A run's / an image's `at` is "p:<op>" (the page's content, all its streams joined) or "f<num>:<op>". */
export async function pdfRedactionView(bytes: Uint8Array): Promise<{ pages: { num: number; page: PdfPage; content: string }[]; forms: Map<number, string> } | null> {
  if (!bytes || bytes.length < 5 || DEC.decode(bytes.subarray(0, 5)) !== '%PDF-') return null;
  const objs = await readObjects(bytes);
  const ctx: Ctx = { objs, forms: new Map(), fonts: new Map(), ocg: new Map(), ops: 0, truncated: false, segs: 0, layers: true, paths: true };
  const pages: { num: number; page: PdfPage; content: string }[] = [];
  for (const p of pageTree(objs)) pages.push({ num: p.num, ...(await readPage(ctx, p)) });
  const forms = new Map<number, string>();
  for (const [k, v] of ctx.forms) if (v !== null) forms.set(k, v);
  return { pages, forms };
}

/** Each page's LARGEST image XObject as its dictionary and its still-encoded stream bytes (null when the page
 *  paints none): what a scanned sheet is. scan_takeoff.ts decodes it (DCT as JPEG, Flate 8-bit Gray/RGB). */
export async function pdfPageImages(bytes: Uint8Array): Promise<({ dict: string; raw: Uint8Array; inflated: Uint8Array | null; w: number; h: number } | null)[]> {
  if (!bytes || bytes.length < 5 || DEC.decode(bytes.subarray(0, 5)) !== '%PDF-') return [];
  const objs = await readObjects(bytes);
  const out: ({ dict: string; raw: Uint8Array; inflated: Uint8Array | null; w: number; h: number } | null)[] = [];
  for (const p of pageTree(objs)) {
    let best: { dict: string; raw: Uint8Array; w: number; h: number } | null = null;
    for (const num of namedRefs(objs, p.res, 'XObject').values()) {
      const o = objs.get(num);
      if (!o?.stream || !/\/Subtype\s*\/Image\b/.test(o.dict)) continue;
      const w = Number((o.dict.match(/\/Width\s+(\d+)/) || [])[1] || 0), h = Number((o.dict.match(/\/Height\s+(\d+)/) || [])[1] || 0);
      if (!best || w * h > best.w * best.h) best = { dict: o.dict, raw: o.stream, w, h };
    }
    out.push(best ? { ...best, inflated: /\/DCTDecode\b/.test(best.dict) ? null : await decodeStream(best.dict, best.raw) } : null);
  }
  return out;
}

/** Pages in order, each with its text runs in normalised top-left display coordinates. [] when unreadable. */
/** `opts.layers: false` skips the CAD layer geometry (the cheap read drawing_boq's first call makes). */
export async function pdfPages(bytes: Uint8Array, only?: [number, number], opts: { layers?: boolean } = {}): Promise<PdfPage[]> {
  return (await pdfPageContents(bytes, only, opts)).map((p) => p.page);
}

/**
 * The page's text as LINES: runs sharing a baseline joined left to right, lines top to bottom, pages in
 * order. Written 14 Sep 2026 for the Mashreq e-statement: pdf_text.ts returns '' for it (its Arabic
 * captions are a font this estate cannot map, and that glyph noise correctly fails looksLikeText), and its
 * table is only a table when the runs are put back into rows. Nothing is judged here — the statement parser
 * proves every row it reads against the printed running balance.
 */
export function linesFromRuns(pages: PdfPage[], tolerance = 0.003): string {
  return pages.map((p) => {
    const runs = p.runs.filter((r) => !r.vertical).sort((a, b) => a.y - b.y || a.x - b.x);
    const rows: TextRun[][] = [];
    for (const r of runs) {
      const last = rows[rows.length - 1];
      if (last && Math.abs(last[0].y - r.y) <= tolerance) last.push(r); else rows.push([r]);
    }
    return rows.map((row) => row.sort((a, b) => a.x - b.x).map((r) => r.text).join(' ').replace(/\s+/g, ' ').trim())
      .filter(Boolean).join('\n');
  }).join('\n');
}

/** linesFromRuns over a PDF's bytes; '' when the file cannot be read. */
export async function pdfTextByRows(bytes: Uint8Array): Promise<string> {
  return linesFromRuns(await pdfPages(bytes));
}

// Shared with pdf_measure, which walks the same content streams for path operators.
export { tokens, mul, ID };
export type { M };
