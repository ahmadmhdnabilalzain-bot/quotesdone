// symbol_count — how many of each LEGEND symbol a raster drawing shows, counted by template matching.
// Pure TypeScript over pixel arrays: no OpenCV, no WASM, no model, no network.
//
// WHERE IT RUNS. In the customer's browser beside the OCR (ocrClient.ocrDrawing hands it the canvas
// pixels and the OCR's legend lines), and in the fixture test. NOT in an edge function: a Supabase
// edge isolate gets ~2 s of CPU per request and the server never holds a photo's pixels as text.
// Measured time on the fixture is printed by drawing_image_ocr.test.ts.
//
// HOW.
//   1. Templates from the drawing's own legend. Each legend entry's symbol sits immediately left of
//      its text; the OCR gives the text's box, so the coloured ink in a band around its left edge,
//      cropped tight, IS that entry's template, and its mean colour is that symbol's colour. No
//      symbol library is assumed. (The band reaches 1.5 line heights right of the text's left edge:
//      measured, OCR read the beacon's flash as a "J" and started the text box inside the symbol.)
//   2. Colour-specific ink. A pixel is ink FOR A TEMPLATE when it is saturated colour within
//      COLOR_TOL of that template's colour. Measured on the fixture, one mask for all colour also
//      held the blue address tags and the magenta sound-level boxes, and matched them.
//   3. Candidates. Every window whose ink count is within [0.5x, 2x] the template's (an integral image
//      makes this O(1) per position) is scored by binary normalised cross-correlation, at SCALES —
//      measured, the fixture draws plan symbols at ~0.8x their legend size.
//   4. Non-maximum suppression across ALL types: the best-scoring match claims its box, so one symbol
//      is never counted as two types.
//   5. Excluded: the legend's side strip (legend left edge to sheet edge, full height, when the
//      legend sits in the right quarter — where legend, notes and title block live), so the legend's
//      own symbols and a coloured logo are not counted.
//
// WHAT IT NEVER DOES. Report a count as fact. Its numbers are ESTIMATES that go to the customer as
// our count on a marked-up copy (boq_open_lines + markup.ts), and crossCheck() tests them against the
// distinct loop addresses first.

export type Rect = { x: number; y: number; w: number; h: number };
export type Img = { w: number; h: number; px: Uint8Array | Uint8ClampedArray; channels: 3 | 4 };
export type LegendRow = { type: string; bbox: Rect; text?: string };
export type Match = { type: string; box: Rect; score: number; scale?: number };
export type SymbolCounts = { counts: Record<string, number>; matches: Match[]; templates: Record<string, Rect>; excluded: Rect[]; ms: number };

export const INK_SAT = 70;
export const COLOR_TOL = 110;
export const MIN_SCORE = 0.5;
export const IOU_NMS = 0.2;
export const SCALES = [0.7, 0.8, 0.9, 1, 1.1];

const sat = (r: number, g: number, b: number, t = INK_SAT) => Math.max(r, g, b) - Math.min(r, g, b) > t;

type Tpl = { type: string; w: number; h: number; on: number[]; n: number; rgb: [number, number, number] };

/** The coloured ink beside a legend entry's text, cropped tight, with its mean colour. */
export function templateFor(img: Img, row: LegendRow): { rect: Rect; tpl: Tpl } | null {
  const { w: W, h: H, px, channels: C } = img;
  const lh = Math.max(6, Math.min(row.bbox.h, 14));
  const x0 = Math.max(0, Math.floor(row.bbox.x - 5 * lh)), x1 = Math.min(W - 1, Math.floor(row.bbox.x + 1.5 * lh));
  const cy = row.bbox.y + row.bbox.h / 2;
  const y0 = Math.max(0, Math.floor(cy - 1.6 * lh)), y1 = Math.min(H - 1, Math.ceil(cy + 1.6 * lh));
  // The band reaches 1.6 line heights up and down, so it can hold the bottom of the symbol ABOVE (measured: the
  // beacon's template took the lower arc of the heat-detector-with-sounder ring and became 27 x 33 px). Only the ink
  // components centred on THIS row are the symbol; specks of fewer than 3 px are scanner / JPEG noise.
  const bw = x1 - x0 + 1, bh = y1 - y0 + 1, lab = new Int32Array(bw * bh).fill(-1);
  const isInk = (x: number, y: number) => { const p = (y * W + x) * C; return sat(px[p], px[p + 1], px[p + 2], INK_SAT * 0.6); };
  const keep: number[] = [];
  for (let s = 0; s < bw * bh; s++) {
    if (lab[s] !== -1 || !isInk(x0 + (s % bw), y0 + Math.floor(s / bw))) continue;
    const comp: number[] = [s]; lab[s] = s;
    for (let q = 0; q < comp.length; q++) {
      const cx = comp[q] % bw, cyy = Math.floor(comp[q] / bw);
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
        const nx = cx + dx, ny = cyy + dy; if (nx < 0 || ny < 0 || nx >= bw || ny >= bh) continue;
        const t = ny * bw + nx; if (lab[t] === -1 && isInk(x0 + nx, y0 + ny)) { lab[t] = s; comp.push(t); }
      }
    }
    const my = comp.reduce((a, t) => a + Math.floor(t / bw), 0) / comp.length + y0;
    if (comp.length >= 3 && Math.abs(my - cy) <= lh) keep.push(...comp);
  }
  let minX = Infinity, minY = Infinity, maxX = -1, maxY = -1; let sr = 0, sg = 0, sb = 0, k = 0;
  for (const t of keep) {
    const x = x0 + (t % bw), y = y0 + Math.floor(t / bw), p = (y * W + x) * C;
    if (x < minX) minX = x; if (x > maxX) maxX = x; if (y < minY) minY = y; if (y > maxY) maxY = y;
    if (sat(px[p], px[p + 1], px[p + 2])) { sr += px[p]; sg += px[p + 1]; sb += px[p + 2]; k++; }  // colour from the strong ink only
  }
  if (maxX < 0 || !k || maxX - minX < 4 || maxY - minY < 4) return null;
  const rgb: [number, number, number] = [sr / k, sg / k, sb / k];
  const w = maxX - minX + 1, h = maxY - minY + 1;
  const on = keep.map((t) => (y0 + Math.floor(t / bw) - minY) * w + (x0 + (t % bw) - minX));
  return { rect: { x: minX, y: minY, w, h }, tpl: { type: row.type, w, h, on, n: w * h, rgb } };
}

function colourMask(img: Img, rgb: [number, number, number]): Uint8Array {
  const out = new Uint8Array(img.w * img.h);
  const t2 = COLOR_TOL * COLOR_TOL;
  for (let i = 0, p = 0; i < out.length; i++, p += img.channels) {
    const r = img.px[p], g = img.px[p + 1], b = img.px[p + 2];
    if (!sat(r, g, b)) continue;
    const d = (r - rgb[0]) ** 2 + (g - rgb[1]) ** 2 + (b - rgb[2]) ** 2;
    if (d < t2) out[i] = 1;
  }
  // Specks with fewer than two inked neighbours are JPEG / scanner noise, not a line of a symbol.
  const W = img.w, clean = new Uint8Array(out.length);
  for (let i = W + 1; i < out.length - W - 1; i++) if (out[i] && out[i - 1] + out[i + 1] + out[i - W] + out[i + W] + out[i - W - 1] + out[i - W + 1] + out[i + W - 1] + out[i + W + 1] >= 2) clean[i] = 1;
  return clean;
}

function integral(ink: Uint8Array, w: number, h: number): Uint32Array {
  const I = new Uint32Array((w + 1) * (h + 1));
  for (let y = 1; y <= h; y++) { let row = 0; for (let x = 1; x <= w; x++) { row += ink[(y - 1) * w + (x - 1)]; I[y * (w + 1) + x] = I[(y - 1) * (w + 1) + x] + row; } }
  return I;
}
const sumIn = (I: Uint32Array, w: number, x: number, y: number, tw: number, th: number) =>
  I[(y + th) * (w + 1) + (x + tw)] - I[y * (w + 1) + (x + tw)] - I[(y + th) * (w + 1) + x] + I[y * (w + 1) + x];

function scaled(t: Tpl, s: number): Tpl {
  if (s === 1) return t;
  const w = Math.max(3, Math.round(t.w * s)), h = Math.max(3, Math.round(t.h * s));
  const src = new Uint8Array(t.n); for (const i of t.on) src[i] = 1;
  const on: number[] = [];
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) if (src[Math.min(t.h - 1, Math.floor(y / s)) * t.w + Math.min(t.w - 1, Math.floor(x / s))]) on.push(y * w + x);
  return { ...t, w, h, on, n: w * h };
}

/** A directional symbol (a beacon, an arrow) is drawn turned to face its wall: measured, three of the four beacons
 *  on the real sample point up or down while the legend's points right. The 90 / 180 / 270 degree turns of a template,
 *  skipped for a symbol that looks the same turned (a ring), so a ring is not matched four times over. */
function turns(t: Tpl): Tpl[] {
  const set = (w: number, on: number[]) => new Set(on.map((i) => `${i % w},${Math.floor(i / w)}`));
  const rot = (s: Tpl): Tpl => ({ ...s, w: s.h, h: s.w, on: s.on.map((i) => { const x = i % s.w, y = Math.floor(i / s.w); return x * s.h + (s.h - 1 - y); }) });
  const r1 = rot(t), r2 = rot(r1), r3 = rot(r2);
  const a = set(t.w, t.on), same = (u: Tpl) => { if (u.w !== t.w) return false; const b = set(u.w, u.on); let n = 0; for (const k of b) if (a.has(k)) n++; return n / Math.max(a.size, b.size) > 0.6; };
  // A wide box turned upright (a panel) is a new shape that two parallel cables also make; only near-square symbols turn.
  if (t.w > t.h * 1.3 || t.h > t.w * 1.3) return [];
  return [r1, r2, r3].filter((u) => !same(u));
}

const iou = (a: Rect, b: Rect) => {
  const ix = Math.max(0, Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x)), iy = Math.max(0, Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y));
  const i = ix * iy; return i / (a.w * a.h + b.w * b.h - i);
};
const inside = (p: { x: number; y: number }, r: Rect) => p.x >= r.x && p.x <= r.x + r.w && p.y >= r.y && p.y <= r.y + r.h;

export function countSymbols(img: Img, rows: LegendRow[]): SymbolCounts {
  const t0 = Date.now();
  const W = img.w, H = img.h;
  const templates: Record<string, Rect> = {};
  const base: Tpl[] = [];
  for (const r of rows) { const t = templateFor(img, r); if (t) { templates[r.type] = t.rect; base.push(t.tpl); base.push(...turns(t.tpl)); } }
  const excluded: Rect[] = [];
  const lefts = Object.values(templates).map((r) => r.x);
  if (lefts.length && Math.min(...lefts) > W * 0.75) { const x = Math.min(...lefts) - 6; excluded.push({ x, y: 0, w: W - x, h: H }); }
  // One mask per distinct template colour (quantised), shared by the templates of that colour.
  const masks = new Map<string, { ink: Uint8Array; I: Uint32Array }>();
  const cands: Match[] = [];
  for (const b of base) {
    const key = b.rgb.map((c) => Math.round(c / 32)).join(',');
    if (!masks.has(key)) { const ink = colourMask(img, b.rgb); masks.set(key, { ink, I: integral(ink, W, H) }); }
    const { ink, I } = masks.get(key)!;
    for (const s of SCALES) {
      const t = scaled(b, s);
      const k = t.on.length; if (k < 6) continue;
      const mt = k / t.n, varT = k - t.n * mt * mt;
      // The symbol's INSIDE (centre half of its box) is what tells a call point's dot from a detector's "So" or "H"
      // when the rings are the same size; measured, whole-box correlation let the ring decide and a 16 px call-point
      // template took 23 detectors. The score is the mean of the whole-box and the inside correlation.
      const ix0 = Math.floor(t.w / 4), iy0 = Math.floor(t.h / 4), iw = Math.max(2, t.w - 2 * ix0), ih = Math.max(2, t.h - 2 * iy0), inN = iw * ih;
      const inOn = t.on.filter((o) => { const ox = o % t.w, oy = Math.floor(o / t.w); return ox >= ix0 && ox < ix0 + iw && oy >= iy0 && oy < iy0 + ih; });
      const mti = inOn.length / inN, varTi = inOn.length - inN * mti * mti;
      for (let y = 0; y + t.h <= H; y++) {
        for (let x = 0; x + t.w <= W; x++) {
          const a = sumIn(I, W, x, y, t.w, t.h);
          if (a < k * 0.5 || a > k * 2) continue;
          if (excluded.some((r) => inside({ x: x + t.w / 2, y: y + t.h / 2 }, r))) continue;
          let both = 0; for (const o of t.on) both += ink[(y + Math.floor(o / t.w)) * W + x + (o % t.w)];
          const ma = a / t.n, varA = a - t.n * ma * ma;
          const full = (both - t.n * ma * mt) / Math.sqrt(Math.max(1e-9, varA * varT));
          if (full < 0.3 || both < k * 0.5) continue;  // a ring is mostly THERE: measured, cable crossings passed the correlation with a third of a ring
          const ai = sumIn(I, W, x + ix0, y + iy0, iw, ih);
          let bi = 0; for (const o of inOn) bi += ink[(y + Math.floor(o / t.w)) * W + x + (o % t.w)];
          const mai = ai / inN, varAi = ai - inN * mai * mai;
          const inner = varTi > 1e-9 && varAi > 1e-9 ? (bi - inN * mai * mti) / Math.sqrt(varAi * varTi) : (ai === 0) === (inOn.length === 0) ? 1 : 0;
          const score = (full + inner) / 2;
          if (score >= 0.4 && inner >= 0.2) cands.push({ type: t.type, box: { x, y, w: t.w, h: t.h }, score, scale: s });
        }
      }
    }
  }
  // ONE PLAN SCALE. Every symbol on a sheet is drawn at the same ratio to its legend sample, so the ratio is found
  // once (the scale whose non-overlapping matches score highest in total) and a match more than one step from it is
  // dropped: measured, a 16 px detector matched a 20 px detector-with-sounder template at 0.8x.
  const nms = (cs: Match[]) => { const out: Match[] = []; for (const c of cs) if (!out.some((m) => iou(m.box, c.box) > IOU_NMS)) out.push(c); return out; };
  cands.sort((a, b) => b.score - a.score);
  let plan = 1, best = -1;
  for (const s of SCALES) { const tot = nms(cands.filter((c) => c.scale === s)).reduce((q, c) => q + c.score, 0); if (tot > best) { best = tot; plan = s; } }
  const matches = nms(cands.filter((c) => Math.abs((c.scale ?? 1) - plan) <= 0 + 1e-9));
  const counts: Record<string, number> = {};
  for (const r of rows) counts[r.type] = 0;
  for (const m of matches) counts[m.type] = (counts[m.type] || 0) + 1;
  return { counts, matches, templates, excluded, ms: Date.now() - t0 };
}

/**
 * Legend rows from OCR lines: lines in the sheet's right quarter that name a device type. One row
 * per type, the LONGEST text (the entry, not a stray "FAP" label); a fragment carrying "c/w" that
 * did not resolve to a combined device is dropped rather than read as its last word.
 */
export function legendRows(lines: { text: string; bbox: Rect }[], sheetW: number, typeOf: (t: string) => { type: string } | null): LegendRow[] {
  const best = new Map<string, LegendRow>();
  for (const l of printedLines(lines.filter((x) => x.bbox.x >= sheetW * 0.75))) {
    let d = typeOf(l.text); if (!d || /isolator|cable/.test(d.type)) continue;
    // "¢/w" is how OCR prints c/w. A detector "c/w" whose last word OCR lost ("SMOKE DETICTOR c 'wr SOBER", measured
    // on the phone photo) is the detector-with-sounder entry; any other unresolved combined device is dropped.
    if (/\bc\s*['‘’/]?\s*(?:w|=)/i.test(l.text.replace(/[¢©]/g, 'c')) && !/_sounder$/.test(d.type)) {
      const s = /^(smoke|heat)_detector$/.test(d.type) ? typeOf(`${d.type.replace('_', ' ')} c/w sounder`) : null;
      if (!s) continue; d = s;
    }
    const cur = best.get(d.type);
    if (!cur || l.text.length > (cur.text || '').length) best.set(d.type, { type: d.type, bbox: l.bbox, text: l.text });
  }
  return [...best.values()];
}

/**
 * One entry per PRINTED line. Two passes and overlapping tiles read the same line with different
 * truncations ("WALL MOUNTED SOUNDER BEACON" and "V/ALL MOUNTED SOUNDER BE"); measured, the short one
 * was then classified on its own as a plain sounder. Lines on the same baseline whose boxes overlap
 * are one printed line, and its longest reading stands for it.
 */
export function printedLines<T extends { text: string; bbox: Rect }>(lines: T[]): T[] {
  const out: T[] = [];
  for (const l of [...lines].sort((a, b) => b.text.length - a.text.length)) {
    const cy = l.bbox.y + l.bbox.h / 2;
    const same = out.find((o) => Math.abs((o.bbox.y + o.bbox.h / 2) - cy) < Math.max(4, Math.min(o.bbox.h, l.bbox.h) * 0.6)
      && l.bbox.x < o.bbox.x + o.bbox.w && o.bbox.x < l.bbox.x + l.bbox.w);
    if (!same) out.push(l);
  }
  return out;
}

// Addresses per device on an addressable loop: a detector with a sounder base is two addressable
// points on one head; the panel is not on the loop. Everything else is one.
export const ADDRESSES_PER_DEVICE: Record<string, number> = {
  fire_alarm_control_panel: 0, repeater_panel: 0,
  smoke_detector_sounder: 2, heat_detector_sounder: 2,
};

/** Do the per-type counts account for the distinct loop addresses? Exact agreement only. */
export function crossCheck(counts: Record<string, number>, addresses: number | null): { implied: number; addresses: number | null; agrees: boolean } {
  const implied = Object.entries(counts).reduce((s, [t, n]) => s + n * (ADDRESSES_PER_DEVICE[t] ?? 1), 0);
  return { implied, addresses, agrees: addresses != null && implied === addresses };
}
