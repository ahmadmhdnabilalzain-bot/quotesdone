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
import { inflate, unescapePdfString, hexToString } from './pdf_text.ts';

export type TextRun = { text: string; x: number; y: number; w: number; h: number; vertical?: boolean }; // display frame, normalised 0..1, top-left origin
/** An image painted on the page (a logo, a stamp, a scanned schedule): its placement box and pixel size. */
export type PdfImage = { x: number; y: number; w: number; h: number; px: number; py: number };
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
export type PdfPage = { width: number; height: number; rotate: number; runs: TextRun[]; images?: PdfImage[]; lines?: PdfLine[]; layers?: LayerSegs; layerWidths?: LayerSegs; marks?: PdfMark[]; truncated?: boolean };

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

async function decodeStream(dict: string, body: Uint8Array): Promise<Uint8Array | null> {
  if (/\/FlateDecode\b/.test(dict)) return (await inflate(body, 'deflate')) ?? (await inflate(body, 'deflate-raw'));
  if (!/\/Filter\b/.test(dict)) return body;
  return null;
}

async function readObjects(bytes: Uint8Array): Promise<Map<number, Obj>> {
  const raw = DEC.decode(bytes);
  const objs = new Map<number, Obj>();
  const re = /(\d+)\s+\d+\s+obj\b/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(raw)) !== null) {
    const start = m.index + m[0].length;
    const end = raw.indexOf('endobj', start);
    if (end < 0) break;
    const chunk = raw.slice(start, end);
    const si = chunk.search(/\bstream\r?\n/);
    let stream: Uint8Array | null = null; let dict = chunk;
    if (si >= 0) {
      dict = chunk.slice(0, si);
      const dataStart = start + si + chunk.slice(si).match(/^stream\r?\n/)![0].length;
      let dataEnd = raw.indexOf('endstream', dataStart);
      if (dataEnd < 0) dataEnd = end;
      while (dataEnd > dataStart && (bytes[dataEnd - 1] === 10 || bytes[dataEnd - 1] === 13)) dataEnd--;
      stream = bytes.subarray(dataStart, dataEnd);
    }
    objs.set(Number(m[1]), { dict, stream });
    re.lastIndex = end;
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
function* tokens(src: string): Generator<{ t: 'num' | 'str' | 'arr' | 'op' | 'name'; v: string }> {
  let i = 0; const n = src.length;
  while (i < n) {
    const c = src[i];
    if (c === ' ' || c === '\n' || c === '\r' || c === '\t' || c === '\f' || c === '\0') { i++; continue; }
    if (c === '%') { while (i < n && src[i] !== '\n' && src[i] !== '\r') i++; continue; }
    if (c === '(') {
      let depth = 1, j = i + 1, s = '';
      while (j < n && depth) { const d = src[j]; if (d === '\\') { s += d + (src[j + 1] ?? ''); j += 2; continue; } if (d === '(') depth++; else if (d === ')') { depth--; if (!depth) break; } s += d; j++; }
      yield { t: 'str', v: unescapePdfString(s) }; i = j + 1; continue;
    }
    if (c === '<' && src[i + 1] !== '<') { const j = src.indexOf('>', i); yield { t: 'str', v: hexToString(src.slice(i + 1, j < 0 ? n : j)) }; i = j < 0 ? n : j + 1; continue; }
    if (c === '<' || c === '>') { i += 2; continue; }                       // dictionary delimiters (inline images' BI dicts are rare in drawings)
    if (c === '[') {
      let depth = 1, j = i + 1;
      while (j < n && depth) { const d = src[j]; if (d === '(') { let pd = 1; j++; while (j < n && pd) { if (src[j] === '\\') j++; else if (src[j] === '(') pd++; else if (src[j] === ')') pd--; j++; } continue; } if (d === '[') depth++; else if (d === ']') depth--; j++; }
      yield { t: 'arr', v: src.slice(i + 1, j - 1) }; i = j; continue;
    }
    if (c === '/') { let j = i + 1; while (j < n && !/[\s\/\[\]()<>{}%]/.test(src[j])) j++; yield { t: 'name', v: src.slice(i + 1, j) }; i = j; continue; }
    let j = i; while (j < n && !/[\s\/\[\]()<>{}%]/.test(src[j])) j++;
    if (j === i) { i++; continue; }
    const w = src.slice(i, j); i = j;
    const c0 = w.charCodeAt(0);
    yield { t: (c0 >= 48 && c0 <= 57) || c0 === 45 || c0 === 43 || c0 === 46 ? (/^[+-]?(\d+\.?\d*|\.\d+)$/.test(w) ? 'num' : 'op') : 'op', v: w };
  }
}

// ── fonts: /ToUnicode CMaps (bfchar / bfrange), code width from the codespace ─────────────────────
type Font = { two: boolean; map: Map<number, string> | null };
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

type Ctx = { objs: Map<number, Obj>; forms: Map<number, string | null>; fonts: Map<number, Font>; ocg: Map<number, string | null>; ops: number; truncated: boolean; segs: number; layers: boolean };
async function fontOf(ctx: Ctx, num: number): Promise<Font> {
  const hit = ctx.fonts.get(num); if (hit) return hit;
  const o = ctx.objs.get(num); let f: Font = { two: false, map: null };
  if (o) {
    const two = /\/Identity-[HV]\b/.test(o.dict) || /\/Subtype\s*\/Type0\b/.test(o.dict);
    const tu = /\/ToUnicode\s+(\d+)\s+\d+\s+R/.exec(o.dict);
    const cm = tu ? ctx.objs.get(Number(tu[1])) : null;
    const dec = cm?.stream ? await decodeStream(cm.dict, cm.stream) : null;
    if (dec) { const p = parseCMap(DEC.decode(dec)); f = { two: two || p.two, map: p.map.size ? p.map : null }; } else f = { two, map: null };
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
  run: (text: string, m: M, size: number, n: number) => void; image: (m: M, px: number, py: number) => void; seg: (x1: number, y1: number, x2: number, y2: number) => void;
  layerSeg: (layer: string, x1: number, y1: number, x2: number, y2: number, width: number) => void; mark: (layer: string, pts: [number, number][]) => void;
}, active: Set<number>, layer0 = '', lw0 = 1): Promise<void> {
  let ctm: M = ctm0; const stack: [M, number][] = []; let lw = lw0;
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
    if (text.trim()) emit.run(text, mul(tm, ctm), size, n);
    tm = mul([1, 0, 0, 1, n * 0.6 * size, 0], tm);
  };
  const newline = (tx: number, ty: number) => { tlm = mul([1, 0, 0, 1, tx, ty], tlm); tm = tlm; };
  const flushPath = (stroked: boolean) => {
    for (const sp of path) {
      for (let i = 1; i < sp.length; i++) emit.seg(sp[i - 1][0], sp[i - 1][1], sp[i][0], sp[i][1]);
      if (layer && stroked && ctx.layers) { const wd = lw * Math.sqrt(Math.abs(ctm[0] * ctm[3] - ctm[1] * ctm[2])); for (let i = 1; i < sp.length; i++) emit.layerSeg(layer, sp[i - 1][0], sp[i - 1][1], sp[i][0], sp[i][1], wd); }
      if (layer && sp.length >= 5 && sp[0][0] === sp[sp.length - 1][0] && sp[0][1] === sp[sp.length - 1][1]) emit.mark(layer, sp);
    }
    path = []; curPath = null;
  };
  // Curves are flattened into chords so a duct elbow or a round bubble keeps its true length and shape.
  const bez = (p1: [number, number], p2: [number, number], p3: [number, number]) => {
    if (!curPath) return; const p0 = curPath[curPath.length - 1];
    for (let i = 1; i <= 8; i++) { const t = i / 8, u = 1 - t; const k0 = u * u * u, k1 = 3 * u * u * t, k2 = 3 * u * t * t, k3 = t * t * t; curPath.push([k0 * p0[0] + k1 * p1[0] + k2 * p2[0] + k3 * p3[0], k0 * p0[1] + k1 * p1[1] + k2 * p2[1] + k3 * p3[1]]); }
  };
  for (const tk of tokens(src)) {
    if (tk.t === 'num') { nums.push(Number(tk.v)); continue; }
    if (tk.t === 'str') { pStr = tk.v; continue; }
    if (tk.t === 'arr') { pArr = tk.v; continue; }
    if (tk.t === 'name') { pName = tk.v; continue; }
    if (++ctx.ops > MAX_OPS) { ctx.truncated = true; return; }
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
      case 'Do': {
        if (name === undefined) break;
        const num = xobjs.get(name); if (num === undefined) break;
        const o = ctx.objs.get(num); if (!o) break;
        if (/\/Subtype\s*\/Image\b/.test(o.dict)) {
          const px = Number((o.dict.match(/\/Width\s+(\d+)/) || [])[1] || 0), py = Number((o.dict.match(/\/Height\s+(\d+)/) || [])[1] || 0);
          emit.image(ctm, px, py); break;
        }
        if (depth >= MAX_FORM_DEPTH || active.has(num)) break;
        const fsrc = await formContent(ctx, num); if (fsrc === null) break;
        const mtx = numArr((o.dict.match(/\/Matrix\s*\[([^\]]*)\]/) || [])[1]);
        const fres = dictValue(ctx.objs, o.dict, 'Resources') ?? res;
        active.add(num);
        await interpret(ctx, fsrc, fres, mul(mtx.length === 6 ? mtx as M : ID, ctm), depth + 1, emit, active, layer, lw);
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
  const layerSegs: LayerSegs = {}; const layerWidths: LayerSegs = {}; const marks: PdfMark[] = []; ctx.segs = 0;
  const D = (x: number, y: number) => toDisplay(x, y, p.mb, p.rotate);
  const box = (pts: [number, number][]) => {
    const xs = pts.map((q) => q[0]), ys = pts.map((q) => q[1]);
    const x = Math.min(...xs), y = Math.min(...ys); return { x, y, w: Math.max(...xs) - x, h: Math.max(...ys) - y };
  };
  ctx.ops = 0; ctx.truncated = false;
  await interpret(ctx, src, p.res, ID, 0, {
    run: (text, m, size, n) => {
      const W = n * 0.6 * size;
      const at = (tx: number, ty: number) => D(m[0] * tx + m[2] * ty + m[4], m[1] * tx + m[3] * ty + m[5]);
      const q = [at(0, -0.2 * size), at(W, -0.2 * size), at(W, size), at(0, size)];
      const b = box(q);
      const base = [at(0, 0), at(W || 1, 0)];
      const vertical = (p.rotate % 180 === 0) ? Math.abs(m[1]) > Math.abs(m[0]) : Math.abs(m[0]) > Math.abs(m[1]);
      runs.push({ text, ...b, ...(vertical ? { vertical: true } : {}) });
    },
    image: (m, px, py) => { images.push({ ...box([D(m[4], m[5]), D(m[0] + m[4], m[1] + m[5]), D(m[2] + m[4], m[3] + m[5]), D(m[0] + m[2] + m[4], m[1] + m[3] + m[5])]), px, py }); },
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
    mark: (l, pts) => {
      const b = box(pts.map(([x, y]) => D(x, y)));
      if (b.w < 0.02 && b.h < 0.02 && b.w > 0 && b.h > 0) marks.push({ ...b, n: pts.length - 1, layer: l });
    },
  }, new Set());
  const hasLayers = Object.keys(layerSegs).length > 0;
  return { page: { width: p.mb[2] - p.mb[0], height: p.mb[3] - p.mb[1], rotate: p.rotate, runs, images, lines, ...(hasLayers ? { layers: layerSegs, layerWidths } : {}), ...(marks.length ? { marks } : {}), ...(ctx.truncated ? { truncated: true } : {}) }, content: src };
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
