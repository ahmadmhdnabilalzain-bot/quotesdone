// cad_vector_text — does a CAD drawing carry WORDS DRAWN AS LINES? (25 Sep 2026, sales_engineer; third independent
// review of #967.) When SHX text is exploded, or a PDF is converted to DWG, a title block's words stop being TEXT
// entities and become short polylines, arcs and lines. cad_render judges every TEXT; it cannot judge geometry, so
// the review's probe drew "CLIENT: ZZ OMEGA", a firm, a phone number, the customer's name and a monogram logo as
// plain linework on a supplier's page. This file finds that shape so the renderer can HOLD the page (vector_text).
//
// THE SHAPE. A glyph is a small cluster of strokes that touch one another; a word is a ROW of such clusters of like
// height, a glyph's width or less apart, sitting on one baseline (or one vertical line, for text turned 90 degrees).
// A row of 4 or more glyph clusters that are not all the same shape is text. Walls and rooms are far larger than a
// glyph; a door swing is one cluster; chairs round a table, a hatch drawn as lines and dimension ticks repeat ONE
// shape and are set aside. Device symbols and dimensions are left out by the caller (they are block INSERTs and
// DIMENSIONs, whose own words are TEXT). What this misses - text drawn inside a block, a word of 3 letters, a logo
// that is not a row - the CAD worker's OCR of the rendered page catches before publishing (scan_redact.ts
// verifyRenderedCad). Pure: no I/O, no randomness.

type B = { x0: number; y0: number; x1: number; y1: number; n: number };

/** Glyph clusters, as a share of the drawing's long side: smaller is a dot, larger is a room or a door. */
const GLYPH_MIN = 0.0008, GLYPH_MAX = 0.04;
/** Clusters in a row before it is read as a word. */
export const ROW_MIN = 4;

const box = (p: number[]): B => { let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity; for (let i = 0; i + 1 < p.length; i += 2) { if (p[i] < x0) x0 = p[i]; if (p[i] > x1) x1 = p[i]; if (p[i + 1] < y0) y0 = p[i + 1]; if (p[i + 1] > y1) y1 = p[i + 1]; } return { x0, y0, x1, y1, n: 1 }; };

/** Rows of glyph-sized linework in `parts` (each a flat [x, y, x, y ...] polyline, in drawing units). */
export function vectorTextRows(parts: number[][]): { rows: number; glyphs: number } {
  if (parts.length < ROW_MIN) return { rows: 0, glyphs: 0 };
  const all = parts.map(box);
  let X0 = Infinity, Y0 = Infinity, X1 = -Infinity, Y1 = -Infinity;
  for (const b of all) { if (b.x0 < X0) X0 = b.x0; if (b.y0 < Y0) Y0 = b.y0; if (b.x1 > X1) X1 = b.x1; if (b.y1 > Y1) Y1 = b.y1; }
  const L = Math.max(X1 - X0, Y1 - Y0);
  if (!(L > 0)) return { rows: 0, glyphs: 0 };
  const size = (b: B) => Math.max(b.x1 - b.x0, b.y1 - b.y0);
  const small = all.filter((b) => { const d = size(b); return d >= GLYPH_MIN * L && d <= GLYPH_MAX * L; });
  if (small.length < ROW_MIN) return { rows: 0, glyphs: 0 };
  // 1. strokes that touch (within 5% of the larger's size) are one glyph cluster.
  const cell = GLYPH_MAX * L;
  const parent = small.map((_, i) => i);
  const find = (i: number): number => (parent[i] === i ? i : (parent[i] = find(parent[i])));
  const grid = new Map<string, number[]>();
  small.forEach((b, i) => {
    for (let gx = Math.floor(b.x0 / cell); gx <= Math.floor(b.x1 / cell); gx++) for (let gy = Math.floor(b.y0 / cell); gy <= Math.floor(b.y1 / cell); gy++) {
      const k = gx + ',' + gy; const list = grid.get(k) ?? grid.set(k, []).get(k)!;
      for (const j of list) {
        const a = small[j], t = 0.05 * Math.max(size(a), size(b));
        if (a.x0 <= b.x1 + t && b.x0 <= a.x1 + t && a.y0 <= b.y1 + t && b.y0 <= a.y1 + t) parent[find(i)] = find(j);
      }
      list.push(i);
    }
  });
  const glyphs = new Map<number, B>();
  small.forEach((b, i) => { const r = find(i), g = glyphs.get(r); if (!g) glyphs.set(r, { ...b }); else { g.x0 = Math.min(g.x0, b.x0); g.y0 = Math.min(g.y0, b.y0); g.x1 = Math.max(g.x1, b.x1); g.y1 = Math.max(g.y1, b.y1); g.n++; } });
  const gl = [...glyphs.values()].filter((g) => size(g) <= GLYPH_MAX * L);
  // 2. rows of like-height glyphs on one baseline, a glyph's height or less apart: read across, then read turned.
  let rows = 0, inRows = 0;
  for (const turned of [false, true]) {
    const G = gl.map((g) => (turned ? { x0: g.y0, x1: g.y1, y0: g.x0, y1: g.x1, n: g.n } : g))
      .map((g) => ({ ...g, h: Math.max(g.y1 - g.y0, 1e-9), w: g.x1 - g.x0 }))
      .filter((g) => g.h >= 0.3 * g.w && g.w <= 2.5 * g.h)                      // a letter's shape, not a dash or a bar
      .sort((a, b) => a.x0 - b.x0);
    const up = G.map((_, i) => i);
    const f = (i: number): number => (up[i] === i ? i : (up[i] = f(up[i])));
    for (let i = 0; i < G.length; i++) for (let j = i + 1; j < G.length && G[j].x0 - G[i].x1 <= 1.2 * Math.max(G[i].h, G[j].h); j++) {
      const a = G[i], b = G[j], h = Math.max(a.h, b.h), lo = Math.min(a.h, b.h);
      if (h > 2.2 * lo) continue;
      const overlap = Math.min(a.y1, b.y1) - Math.max(a.y0, b.y0);
      if (overlap < 0.6 * lo || Math.abs(a.y0 - b.y0) > 0.35 * h) continue;
      if (b.x0 - a.x1 < -0.1 * h) continue;                                        // lying over each other: not a row
      up[f(i)] = f(j);
    }
    const by = new Map<number, typeof G>();
    G.forEach((g, i) => { const r = f(i); (by.get(r) ?? by.set(r, []).get(r)!).push(g); });
    for (const row of by.values()) {
      if (row.length < ROW_MIN) continue;
      // One shape repeated (chairs, hatch lines, ticks) is a pattern, not a word.
      const sig = new Set(row.map((g) => `${g.n}:${Math.round(4 * g.w / g.h)}`));
      if (sig.size < 2) continue;
      rows++; inRows += row.length;
    }
  }
  return { rows, glyphs: inRows };
}
