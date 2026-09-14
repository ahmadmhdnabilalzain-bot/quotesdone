// pdf_measure — lengths and areas measured from a PDF drawing's VECTOR paths, only at a printed scale
// (14 Sep 2026).
//
// WHY. A drawing exported from CAD keeps its lines as PDF path operators, in points (1 pt = 1/72 in =
// 0.3528 mm on paper). With the scale printed on the sheet ("SCALE 1:100"), paper millimetres become
// site metres (paper_mm × N / 1000) with no model — and every model route is on hold.
//
// WHAT IT READS. Each page's content stream (via pdf_text_positions): m l c v y re h, the painting
// operators S s f F f* B B* b b* n, cm and q/Q for the transformation stack, and w for line width.
// Curves are flattened into 16 chords. The scale comes from the page's own text: "SCALE 1:100",
// "Scale: 1/100", "1:50 @ A1", "مقياس 1:100", "Maßstab 1:50".
// It returns, per page: total stroked length (m), and when more than one line weight is present the
// length per weight; the count and total area (sqm) of closed shapes. Confidence is always 'low'.
//
// WHAT IT NEVER DOES. Guess a scale. No scale, "NTS" / "not to scale", or two different scales on one
// page (viewports at 1:50 and 1:100 cannot be told apart from paths alone) -> no quantities, and a note
// saying why. It never follows Form XObjects (`Do`) — CAD blocks drawn as forms are not measured.
//
// FILTERS, because a sheet's vector content is not only the building:
//  * a path whose bounding box spans >= 90% of the page both ways is the sheet border, not geometry;
//  * a stroked path whose paper bounding box is under MIN_STROKE_MM across is text drawn as strokes
//    (CAD SHX fonts), arrowheads or ticks;
//  * a closed shape under MIN_SHAPE_SQM real area is a glyph, a symbol or a hatch cell.
// What still gets counted: dimension lines, grid lines, hatching lines longer than 3 mm, furniture,
// annotations drawn as geometry. The totals are therefore "every drawn line", not "walls": a person
// must read them against the drawing. The basis says so on every quantity.
import { pdfPageContents, tokens, mul, ID, type M } from './pdf_text_positions.ts';
import type { Qty } from './doc_read/types.ts';

/** Operators read per page before giving up on it. A dense A1 CAD sheet measured in the low tens of
 *  thousands of path operators; 200k is headroom, and past it the page returns nothing rather than a
 *  partial total that would read as complete. */
export const MAX_OPS_PER_PAGE = 200_000;
export const MIN_STROKE_MM = 3;
export const MIN_SHAPE_SQM = 0.05;
const PT_MM = 25.4 / 72;
const BEZIER_STEPS = 16;

type Pt = [number, number];
type Sub = { pts: Pt[]; closed: boolean };

/** Distinct scale denominators printed in a page's text, and whether it says not-to-scale. */
export function detectScale(text: string): { scales: number[]; nts: boolean } {
  const found = new Set<number>();
  const add = (s: string) => { const n = Number(s); if (n >= 1 && n <= 10000) found.add(n); };
  for (const m of text.matchAll(/(?:scale|مقياس(?:\s*الرسم)?|ma(?:ß|ss)stab)\s*[:=]?\s*1\s*[:\/]\s*(\d{1,5})(?!\d)/gi)) add(m[1]);
  for (const m of text.matchAll(/(?<![\d.\/:])1\s*:\s*(\d{1,5})\s*@\s*A[0-4]\b/gi)) add(m[1]);
  return { scales: [...found].sort((a, b) => a - b), nts: /\b(nts|n\.t\.s\.?|not to scale)(?![a-z])/i.test(text) };
}

const bbox = (pts: Pt[]) => {
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (const [x, y] of pts) { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); }
  return { w: x1 - x0, h: y1 - y0 };
};

/** Stroked lengths per device line width and closed-shape areas, in PDF points, for one content stream. */
export function measureContent(src: string, pageW: number, pageH: number, mPerPt: number) {
  const strokes = new Map<number, { len: number; n: number }>();
  const shapes: number[] = [];
  let ctm: M = ID, lw = 1, ops = 0;
  const stack: [M, number][] = [];
  let subs: Sub[] = [], cur: Sub | null = null, last: Pt = [0, 0];
  let nums: number[] = [];
  const T = (x: number, y: number): Pt => [ctm[0] * x + ctm[2] * y + ctm[4], ctm[1] * x + ctm[3] * y + ctm[5]];
  const moveTo = (p: Pt) => { cur = { pts: [p], closed: false }; subs.push(cur); last = p; };
  const lineTo = (p: Pt) => { if (!cur) moveTo(last); cur!.pts.push(p); last = p; };
  const curve = (p1: Pt, p2: Pt, p3: Pt) => {
    const p0 = last;
    for (let i = 1; i <= BEZIER_STEPS; i++) {
      const t = i / BEZIER_STEPS, u = 1 - t;
      const k = [u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t];
      lineTo([k[0] * p0[0] + k[1] * p1[0] + k[2] * p2[0] + k[3] * p3[0], k[0] * p0[1] + k[1] * p1[1] + k[2] * p2[1] + k[3] * p3[1]]);
    }
  };
  const close = () => { if (cur && cur.pts.length) { cur.closed = true; last = cur.pts[0]; cur = null; } };
  const paint = (stroke: boolean, fill: boolean) => {
    const wDev = Math.round(lw * Math.sqrt(Math.abs(ctm[0] * ctm[3] - ctm[1] * ctm[2])) * 100) / 100;
    for (const s of subs) {
      if (s.pts.length < 2) continue;
      const b = bbox(s.pts);
      if (b.w >= 0.9 * pageW && b.h >= 0.9 * pageH) continue;              // the sheet border
      const ring = s.closed || fill;
      if (stroke && Math.hypot(b.w, b.h) * PT_MM >= MIN_STROKE_MM) {
        let len = 0;
        for (let i = 1; i < s.pts.length; i++) len += Math.hypot(s.pts[i][0] - s.pts[i - 1][0], s.pts[i][1] - s.pts[i - 1][1]);
        if (s.closed) len += Math.hypot(s.pts[0][0] - s.pts.at(-1)![0], s.pts[0][1] - s.pts.at(-1)![1]);
        const g = strokes.get(wDev) || { len: 0, n: 0 }; g.len += len; g.n++; strokes.set(wDev, g);
      }
      if (ring && s.pts.length >= 3) {
        let a = 0;
        for (let i = 0; i < s.pts.length; i++) { const [x0, y0] = s.pts[i], [x1, y1] = s.pts[(i + 1) % s.pts.length]; a += x0 * y1 - x1 * y0; }
        a = Math.abs(a) / 2;
        if (a * mPerPt * mPerPt >= MIN_SHAPE_SQM) shapes.push(a);
      }
    }
    subs = []; cur = null;
  };
  for (const tk of tokens(src)) {
    if (tk.t === 'num') { nums.push(Number(tk.v)); continue; }
    if (tk.t !== 'op') { nums = []; continue; }
    if (++ops > MAX_OPS_PER_PAGE) return { overflow: true as const, strokes, shapes };
    const a = nums; nums = [];
    switch (tk.v) {
      case 'q': stack.push([ctm, lw]); break;
      case 'Q': [ctm, lw] = stack.pop() || [ID, 1]; break;
      case 'cm': if (a.length >= 6) ctm = mul(a.slice(-6) as M, ctm); break;
      case 'w': if (a.length) lw = a[a.length - 1]; break;
      case 'm': if (a.length >= 2) moveTo(T(a[0], a[1])); break;
      case 'l': if (a.length >= 2) lineTo(T(a[0], a[1])); break;
      case 'c': if (a.length >= 6) curve(T(a[0], a[1]), T(a[2], a[3]), T(a[4], a[5])); break;
      case 'v': if (a.length >= 4) curve(last, T(a[0], a[1]), T(a[2], a[3])); break;
      case 'y': if (a.length >= 4) { const p3 = T(a[2], a[3]); curve(T(a[0], a[1]), p3, p3); } break;
      case 're': if (a.length >= 4) {
        const [x, y, w, h] = a;
        subs.push({ pts: [T(x, y), T(x + w, y), T(x + w, y + h), T(x, y + h)], closed: true });
        cur = null; last = T(x, y);
      } break;
      case 'h': close(); break;
      case 'S': paint(true, false); break;
      case 's': close(); paint(true, false); break;
      case 'f': case 'F': case 'f*': paint(false, true); break;
      case 'B': case 'B*': paint(true, true); break;
      case 'b': case 'b*': close(); paint(true, true); break;
      case 'n': subs = []; cur = null; break;                               // end path, no paint (after a clip W)
    }
  }
  return { overflow: false as const, strokes, shapes };
}

const r2 = (n: number) => Math.round(n * 100) / 100;

/** Every page of a PDF drawing: the scale found in its text and, only when there is exactly one, the measured quantities. */
export async function measurePdf(bytes: Uint8Array): Promise<{ pages: { page: number; scale: string | null; quantities: Qty[] }[]; notes: string[] }> {
  const notes: string[] = [];
  const pages: { page: number; scale: string | null; quantities: Qty[] }[] = [];
  const all = await pdfPageContents(bytes);
  if (!all.length) notes.push('No readable PDF pages (not a PDF, encrypted, or no page tree found); nothing was measured.');
  for (const [i, { page, content }] of all.entries()) {
    const n = i + 1;
    const { scales, nts } = detectScale(page.runs.map((r) => r.text).join(' '));
    const scale = scales.length === 1 ? `1:${scales[0]}` : null;
    const quantities: Qty[] = [];
    pages.push({ page: n, scale, quantities });
    if (nts) { notes.push(`Page ${n} is marked not to scale; nothing was measured.`); continue; }
    if (!scales.length) { notes.push(`Page ${n}: no drawing scale found in the page text; nothing was measured.`); continue; }
    if (scales.length > 1) { notes.push(`Page ${n} prints several scales (${scales.map((s) => '1:' + s).join(', ')}); its views cannot be told apart, so nothing was measured.`); continue; }
    const mPerPt = (PT_MM * scales[0]) / 1000;
    const m = measureContent(content, page.width, page.height, mPerPt);
    if (m.overflow) { notes.push(`Page ${n} has more than ${MAX_OPS_PER_PAGE} drawing operators; it was not measured rather than measured in part.`); continue; }
    const basis = (what: string) => `page ${n}, ${what}, measured from vector paths at SCALE ${scale} as printed on the page; the drawing may be not-to-scale or hold views at other scales, and every drawn line counts (dimensions, hatching, annotation), so check against the drawing`;
    const sec = `Page ${n}`;
    const total = [...m.strokes.values()].reduce((s, g) => s + g.len, 0);
    const count = [...m.strokes.values()].reduce((s, g) => s + g.n, 0);
    if (total > 0) quantities.push({ section: sec, description: 'Stroked line length, all line weights', qty: r2(total * mPerPt), unit: 'm', basis: basis(`${count} stroked paths`), confidence: 'low' });
    if (m.strokes.size > 1) for (const [w, g] of [...m.strokes.entries()].sort((a, b) => b[0] - a[0])) {
      quantities.push({ section: sec, description: `Stroked line length at ${w} pt line weight`, qty: r2(g.len * mPerPt), unit: 'm', basis: basis(`${g.n} stroked paths at ${w} pt`), confidence: 'low' });
    }
    if (m.shapes.length) {
      quantities.push({ section: sec, description: 'Closed shapes', qty: m.shapes.length, unit: 'nos', basis: basis(`closed shapes of at least ${MIN_SHAPE_SQM} sqm`), confidence: 'low' });
      quantities.push({ section: sec, description: 'Closed shape area, total', qty: r2(m.shapes.reduce((s, a) => s + a, 0) * mPerPt * mPerPt), unit: 'sqm', basis: basis(`${m.shapes.length} closed shapes, overlaps counted twice`), confidence: 'low' });
    }
    if (!quantities.length) notes.push(`Page ${n}: scale ${scale} found, but no vector paths were drawn on the page itself (it may be a scanned image or use Form XObjects).`);
  }
  return { pages, notes };
}
