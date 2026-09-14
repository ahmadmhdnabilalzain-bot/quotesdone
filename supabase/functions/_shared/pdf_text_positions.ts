// pdf_text_positions — a PDF's text layer WITH page coordinates, deterministically (14 Sep 2026).
//
// WHY. drawing_redact blacks out identity on rasterised drawing pages using boxes a vision model
// names, and every model route is held — so redaction verified nothing (pages_out=0) and a drawing
// could not reach a supplier. A drawing exported from CAD or a PDF writer usually carries its title
// block (consultant, client, phone, email, "Drawn by") as REAL TEXT. That text has a position, and a
// position can be mapped onto the rasterised page and boxed without any model.
//
// WHAT IT READS. Page tree order (Catalog -> /Pages -> /Kids, inheriting /MediaBox and /Rotate),
// each page's /Contents (FlateDecode or raw), object streams (PDF 1.5+ hides page dicts in them), and
// the text operators BT/ET, Tf, TL, Td, TD, Tm, T*, Tj, TJ, ', " under q/Q/cm.
//
// CEILINGS, stated so nobody treats a box from here as exact:
//  * Glyph widths are ESTIMATED (0.6 em per character) — no font metrics are read. Callers pad.
//  * Text inside Form XObjects (`Do`) is not followed. Many CAD title blocks are blocks = forms, so
//    an empty result is common and means "not found here", never "the page is clean".
//  * Rotated pages (/Rotate != 0) and CID fonts return runs the caller must not trust for
//    coordinates; rotated pages are flagged, CID strings fail looksLikeText upstream.
// ponytail: full-buffer object regex, no xref parsing; fine for a drawing set of a few MB.
import { inflate, unescapePdfString, hexToString } from './pdf_text.ts';

export type TextRun = { text: string; x: number; y: number; w: number; h: number }; // normalised 0..1, top-left origin
export type PdfPage = { width: number; height: number; rotate: number; runs: TextRun[] };

const DEC = new TextDecoder('latin1');
type Obj = { dict: string; stream: Uint8Array | null };
type M = [number, number, number, number, number, number];
const mul = (a: M, b: M): M => [a[0] * b[0] + a[1] * b[2], a[0] * b[1] + a[1] * b[3], a[2] * b[0] + a[3] * b[2], a[2] * b[1] + a[3] * b[3], a[4] * b[0] + a[5] * b[2] + b[4], a[4] * b[1] + a[5] * b[3] + b[5]];
const ID: M = [1, 0, 0, 1, 0, 0];

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

function pageTree(objs: Map<number, Obj>): { num: number; mb: number[]; rotate: number }[] {
  const out: { num: number; mb: number[]; rotate: number }[] = [];
  const cat = [...objs.entries()].find(([, o]) => /\/Type\s*\/Catalog\b/.test(o.dict));
  const rootRef = cat ? refs((cat[1].dict.match(/\/Pages\s+\d+\s+\d+\s+R/) || [''])[0])[0] : undefined;
  const seen = new Set<number>();
  const walk = (num: number, mb: number[], rot: number) => {
    if (seen.has(num)) return; seen.add(num);
    const o = objs.get(num); if (!o) return;
    const d = o.dict;
    const myMb = numArr((d.match(/\/MediaBox\s*\[([^\]]*)\]/) || [])[1]);
    const mbx = myMb.length === 4 ? myMb : mb;
    const r = d.match(/\/Rotate\s+(-?\d+)/); const rr = r ? Number(r[1]) : rot;
    if (/\/Type\s*\/Pages\b/.test(d)) { for (const k of refs((d.match(/\/Kids\s*\[([^\]]*)\]/) || ['', ''])[1])) walk(k, mbx, rr); }
    else if (/\/Type\s*\/Page\b/.test(d)) out.push({ num, mb: mbx, rotate: ((rr % 360) + 360) % 360 });
  };
  if (rootRef !== undefined) walk(rootRef, [0, 0, 612, 792], 0);
  if (!out.length) for (const [num, o] of objs) if (/\/Type\s*\/Page\b(?!s)/.test(o.dict)) walk(num, [0, 0, 612, 792], 0); // no catalog found: object order
  return out;
}

// Tokeniser for a content stream: numbers, names, strings, arrays (as raw source), operators.
function* tokens(src: string): Generator<{ t: 'num' | 'str' | 'arr' | 'op' | 'name'; v: string }> {
  let i = 0; const n = src.length;
  while (i < n) {
    const c = src[i];
    if (/\s/.test(c)) { i++; continue; }
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
    yield { t: /^[+-]?(\d+\.?\d*|\.\d+)$/.test(w) ? 'num' : 'op', v: w };
  }
}

function arrText(a: string): string {
  let out = '';
  for (const t of tokens(a)) { if (t.t === 'str') out += t.v; else if (t.t === 'num' && Number(t.v) <= -200) out += ' '; }
  return out;
}

function runsFromContent(src: string, mb: number[]): TextRun[] {
  const [x0, y0, x1, y1] = mb; const W = (x1 - x0) || 1, H = (y1 - y0) || 1;
  const runs: TextRun[] = [];
  let ctm: M = ID; const stack: M[] = [];
  let tm: M = ID, tlm: M = ID; let size = 12, lead = 0;
  let nums: number[] = []; let pStr: string | undefined; let pArr: string | undefined;
  const show = (s: string) => {
    const text = s.replace(/[\x00-\x08\x0b\x0c\x0e-\x1f]/g, '');
    const m = mul(tm, ctm);
    const scale = Math.hypot(m[2], m[3]) || 1;               // vertical scale of the text matrix
    const hgt = size * scale; const wid = text.length * 0.6 * size * Math.hypot(m[0], m[1]);
    if (text.trim()) runs.push({ text, x: (m[4] - x0) / W, y: 1 - ((m[5] - y0) + hgt) / H, w: wid / W, h: (hgt * 1.25) / H });
    tm = mul([1, 0, 0, 1, text.length * 0.6 * size, 0], tm);
  };
  const newline = (tx: number, ty: number) => { tlm = mul([1, 0, 0, 1, tx, ty], tlm); tm = tlm; };
  for (const tk of tokens(src)) {
    if (tk.t === 'num') { nums.push(Number(tk.v)); continue; }
    if (tk.t === 'str') { pStr = tk.v; continue; }
    if (tk.t === 'arr') { pArr = tk.v; continue; }
    if (tk.t === 'name') continue;
    const a = nums; const str = pStr; const arr = pArr;
    nums = []; pStr = undefined; pArr = undefined;
    switch (tk.v) {
      case 'q': stack.push(ctm); break;
      case 'Q': ctm = stack.pop() || ID; break;
      case 'cm': if (a.length >= 6) ctm = mul(a.slice(-6) as M, ctm); break;
      case 'BT': tm = ID; tlm = ID; break;
      case 'Tf': if (a.length) size = a[a.length - 1] || size; break;
      case 'TL': if (a.length) lead = a[0]; break;
      case 'Td': if (a.length >= 2) newline(a[0], a[1]); break;
      case 'TD': if (a.length >= 2) { lead = -a[1]; newline(a[0], a[1]); } break;
      case 'Tm': if (a.length >= 6) { tlm = a.slice(-6) as M; tm = tlm; } break;
      case 'T*': newline(0, -lead); break;
      case 'Tj': if (str !== undefined) show(str); break;
      case "'": newline(0, -lead); if (str !== undefined) show(str); break;
      case '"': newline(0, -lead); if (str !== undefined) show(str); break;
      case 'TJ': if (arr !== undefined) show(arrText(arr)); break;
    }
  }
  return runs;
}

/** Pages in order, each with its text runs in normalised top-left coordinates. [] when unreadable. */
export async function pdfPages(bytes: Uint8Array): Promise<PdfPage[]> {
  if (!bytes || bytes.length < 5 || DEC.decode(bytes.subarray(0, 5)) !== '%PDF-') return [];
  const head = DEC.decode(bytes.subarray(0, Math.min(bytes.length, 4096)));
  if (/\/Encrypt\b/.test(head) || /\/Encrypt\b/.test(DEC.decode(bytes.subarray(Math.max(0, bytes.length - 4096))))) return [];
  const objs = await readObjects(bytes);
  const pages: PdfPage[] = [];
  for (const p of pageTree(objs)) {
    const d = objs.get(p.num)!.dict;
    const cm = d.match(/\/Contents\s*(\[[^\]]*\]|\d+\s+\d+\s+R)/);
    let src = '';
    for (const r of cm ? refs(cm[1]) : []) {
      const o = objs.get(r); if (!o || !o.stream) continue;
      const dec = await decodeStream(o.dict, o.stream); if (dec) src += DEC.decode(dec) + '\n';
    }
    pages.push({ width: p.mb[2] - p.mb[0], height: p.mb[3] - p.mb[1], rotate: p.rotate, runs: runsFromContent(src, p.mb) });
  }
  return pages;
}
