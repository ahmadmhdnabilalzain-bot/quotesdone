// table_grid — find RULED TABLES (equipment and fixture schedules) in a grayscale page image, with no
// model and no library (21 Sep 2026, sales_engineer, founder instruction 580).
//
// WHY. An MEP drawing set carries its countable content in SCHEDULES: RTU-1..3, EF-1..10, WC/L-1,
// FD-1... On the two real US bid sets measured today those schedules are either embedded 1-bit raster
// images (mechanical M0.1/M0.2) or vector strokes with no text layer (plumbing P-0.01), so the PDF text
// reader gets 0 characters there. The portal's fallback OCR read whole pages at ~72 dpi and returned
// noise; 4 BOQ lines were invented from it and 0 of 49 answer-key items were found. A schedule is a
// grid: find the grid, and each CELL can be read on its own at a resolution tesseract can use, with
// the row/column structure kept (tag -> manufacturer -> model stays one row).
//
// WHAT IT DOES. Pure function over {data: Uint8Array (0 = black, 255 = white), w, h}; no browser API,
// so it runs in the portal (ocrClient.ocrSchedules), in Deno (the test) and anywhere else.
//   1. Horizontal and vertical dark runs >= minLen (gaps <= maxGap bridged, so an anti-aliased or
//      dashed rule stays one run), linked across adjacent rows/columns into LINES; a line thicker than
//      maxThick is a filled area (poché wall, solid block), not a rule, and is dropped. A line spanning
//      >= 85 % of the page is the sheet border and is dropped, so a table touching it is not swallowed.
//   2. Lines that cross (within tol) are unioned into components.
//   3. A component is a TABLE only if it has >= 2 "data bands": the strip between two consecutive
//      rules that each span >= 90 % of the component width, between minRowFrac and maxRowFrac of the
//      page's long edge high, cut by vertical rules into >= 3 real cells of which at least half hold
//      ink. That is a schedule (a header band plus at least one item row, text in most cells) and not
//      a floor plan (walls span part of the building, a double wall encloses an empty strip, a room
//      is taller than a schedule row, a corridor band is one labelled space between two empty wall
//      strips) — the test file draws both and asserts the plan is refused.
//   4. Grid = the clustered x of every vertical rule and y of every horizontal rule in the table. Grid
//      cells are merged where the separating rule is absent at that band/column (a header spanning five
//      columns, a tag spanning two sub-rows), and each merged region is reported ONCE, anchored at its
//      top-left grid cell with its row/column span.
//
// WHAT IT DOES NOT DO. A table drawn rotated a quarter turn on the page (rows running vertically) is
// not read: pdf.js renders in the display frame (after /Rotate), and every schedule on both measured
// sets comes out upright that way. Unruled tables (text aligned in columns with no lines) are not
// tables to this reader.

export type GrayImage = { data: Uint8Array; w: number; h: number };
export type Rect = { x: number; y: number; w: number; h: number };
export type GridCell = Rect & { r: number; c: number; rs: number; cs: number };
export type TableGrid = { bbox: Rect; rowsY: number[]; colsX: number[]; cells: GridCell[]; bandShare: number }; // bandShare: data-band height / table height

export type GridOpts = {
  dark?: number;       // a pixel is ink when value < dark
  minLen?: number;     // shortest rule, px (default 0.4 % of the long edge, >= 20)
  maxGap?: number;     // bridged gap inside a rule, px
  maxThick?: number;   // thickest rule, px (default 0.15 % of the long edge, >= 4)
  tol?: number;        // crossing / clustering tolerance, px
  minRowFrac?: number; // data band height, fraction of the long edge
  maxRowFrac?: number;
};

type Line = { c: number; p0: number; p1: number; a0: number; a1: number }; // c = centre across, a = along

function defaults(img: GrayImage, o: GridOpts) {
  const L = Math.max(img.w, img.h);
  return {
    dark: o.dark ?? 170,
    minLen: o.minLen ?? Math.max(20, Math.round(L * 0.004)),
    maxGap: o.maxGap ?? 2,
    maxThick: o.maxThick ?? Math.max(4, Math.round(L * 0.0015)),
    tol: o.tol ?? Math.max(3, Math.round(L * 0.0006)),
    minRow: (o.minRowFrac ?? 0.0025) * L,
    // 0.03 of a 36 in sheet = 1.08 in. Measured at 200 dpi on M0.1/M0.2/P-0.01: item rows 74-85 px
    // (0.37-0.43 in), header bands up to 112 px, P-0.01's WC/L-1 row (three description lines) 184 px
    // (0.92 in); a room at 1/8" = 1'-0" is 1.25 in or more.
    maxRow: (o.maxRowFrac ?? 0.03) * L,
  };
}

// Link 1-px-thick segments (sorted by p = the coordinate across the line) into lines.
function link(segs: { p: number; a0: number; a1: number }[], maxThick: number): Line[] {
  const out: Line[] = [];
  let open: Line[] = [];
  let i = 0;
  while (i < segs.length) {
    const p = segs[i].p;
    const next: Line[] = [];
    const used = new Set<Line>();
    for (; i < segs.length && segs[i].p === p; i++) {
      const s = segs[i];
      let hit: Line | null = null;
      for (const l of open) {
        if (used.has(l) || l.p1 !== p - 1) continue;
        const ov = Math.min(l.a1, s.a1) - Math.max(l.a0, s.a0);
        if (ov > 0.5 * Math.min(l.a1 - l.a0, s.a1 - s.a0)) { hit = l; break; }
      }
      if (hit) { used.add(hit); hit.p1 = p; hit.a0 = Math.min(hit.a0, s.a0); hit.a1 = Math.max(hit.a1, s.a1); next.push(hit); }
      else next.push({ c: 0, p0: p, p1: p, a0: s.a0, a1: s.a1 });
    }
    for (const l of open) if (!used.has(l)) out.push(l);
    open = next;
  }
  out.push(...open);
  return out.filter((l) => l.p1 - l.p0 + 1 <= maxThick).map((l) => ({ ...l, c: (l.p0 + l.p1) / 2 }));
}

export function findRules(img: GrayImage, opts: GridOpts = {}): { h: Line[]; v: Line[] } {
  const o = defaults(img, opts);
  const { data, w, h } = img;
  const hs: { p: number; a0: number; a1: number }[] = [];
  for (let y = 0; y < h; y++) {
    let st = -1, last = -1;
    const row = y * w;
    for (let x = 0; x <= w; x++) {
      const ink = x < w && data[row + x] < o.dark;
      if (ink) { if (st < 0) st = x; last = x; }
      else if (st >= 0 && (x === w || x - last > o.maxGap)) { if (last - st + 1 >= o.minLen) hs.push({ p: y, a0: st, a1: last }); st = -1; }
    }
  }
  // Vertical runs, row-major (one counter per column) so the 30+ megapixel page is read in memory order.
  const st = new Int32Array(w).fill(-1), last = new Int32Array(w).fill(-1);
  const vs: { p: number; a0: number; a1: number }[] = [];
  for (let y = 0; y <= h; y++) {
    const row = y * w;
    for (let x = 0; x < w; x++) {
      const ink = y < h && data[row + x] < o.dark;
      if (ink) { if (st[x] < 0) st[x] = y; last[x] = y; }
      else if (st[x] >= 0 && (y === h || y - last[x] > o.maxGap)) { if (last[x] - st[x] + 1 >= o.minLen) vs.push({ p: x, a0: st[x], a1: last[x] }); st[x] = -1; }
    }
  }
  vs.sort((a, b) => a.p - b.p || a.a0 - b.a0);
  const H = link(hs, o.maxThick).filter((l) => l.a1 - l.a0 < 0.85 * w);
  const V = link(vs, o.maxThick).filter((l) => l.a1 - l.a0 < 0.85 * h);
  return { h: H, v: V };
}

function cluster(vals: number[], tol: number): number[] {
  const s = [...vals].sort((a, b) => a - b);
  const out: number[] = [];
  let g: number[] = [];
  for (const v of s) {
    if (g.length && v - g[g.length - 1] > tol) { out.push(g.reduce((a, b) => a + b, 0) / g.length); g = []; }
    g.push(v);
  }
  if (g.length) out.push(g.reduce((a, b) => a + b, 0) / g.length);
  return out.map((v) => Math.round(v));
}

/** Share of ink pixels inside a rect, shrunk by `inset` px on every side (to stay off the cell rules). */
export function inkRatio(img: GrayImage, r: Rect, inset = 2, dark = 170): number {
  const x0 = Math.max(0, Math.round(r.x + inset)), y0 = Math.max(0, Math.round(r.y + inset));
  const x1 = Math.min(img.w, Math.round(r.x + r.w - inset)), y1 = Math.min(img.h, Math.round(r.y + r.h - inset));
  if (x1 <= x0 || y1 <= y0) return 0;
  let n = 0;
  for (let y = y0; y < y1; y++) { const row = y * img.w; for (let x = x0; x < x1; x++) if (img.data[row + x] < dark) n++; }
  return n / ((x1 - x0) * (y1 - y0));
}

/** A cell with less ink than a single small character is empty and is not sent to OCR. */
export function isEmptyCell(img: GrayImage, r: Rect, inset = 2, dark = 170): boolean {
  const ratio = inkRatio(img, r, inset, dark);
  const area = Math.max(0, r.w - 2 * inset) * Math.max(0, r.h - 2 * inset);
  return ratio * area < 8 || ratio < 0.002;
}

export function detectTables(img: GrayImage, opts: GridOpts = {}): TableGrid[] {
  const o = defaults(img, opts);
  const { h: H, v: V } = findRules(img, opts);
  const n = H.length + V.length;
  const parent = new Int32Array(n).map((_, i) => i);
  const find = (i: number): number => { while (parent[i] !== i) { parent[i] = parent[parent[i]]; i = parent[i]; } return i; };
  const t = o.tol;
  for (let i = 0; i < H.length; i++) {
    const a = H[i];
    for (let j = 0; j < V.length; j++) {
      const b = V[j];
      if (b.c >= a.a0 - t && b.c <= a.a1 + t && a.c >= b.a0 - t && a.c <= b.a1 + t) {
        const ra = find(i), rb = find(H.length + j); if (ra !== rb) parent[ra] = rb;
      }
    }
  }
  const groups = new Map<number, { h: Line[]; v: Line[] }>();
  for (let i = 0; i < n; i++) {
    const r = find(i);
    if (!groups.has(r)) groups.set(r, { h: [], v: [] });
    if (i < H.length) groups.get(r)!.h.push(H[i]); else groups.get(r)!.v.push(V[i - H.length]);
  }
  const tables: TableGrid[] = [];
  for (const g of groups.values()) {
    if (g.h.length < 4 || g.v.length < 3) continue;
    const ys = cluster(g.h.map((l) => l.c), t), xs = cluster(g.v.map((l) => l.c), t);
    if (ys.length < 4 || xs.length < 3) continue;
    const X0 = xs[0], X1 = xs[xs.length - 1], Y0 = ys[0], Y1 = ys[ys.length - 1];
    const tw = X1 - X0;
    if (tw <= 0 || Y1 <= Y0) continue;
    const hAt = (yi: number, x: number) => g.h.some((l) => Math.abs(l.c - ys[yi]) <= t && x >= l.a0 - t && x <= l.a1 + t);
    const vAt = (xi: number, y: number) => g.v.some((l) => Math.abs(l.c - xs[xi]) <= t && y >= l.a0 - t && y <= l.a1 + t);
    const full = ys.map((y) => g.h.some((l) => Math.abs(l.c - y) <= t && l.a1 - l.a0 >= 0.9 * tw));
    // Data bands (criterion 3 in the header). A band runs between CONSECUTIVE FULL-WIDTH rules; a
    // partial rule inside it (a two-level header, RTU-2's supply/exhaust sub-rows) does not split it.
    // Measured on M0.1 of the real mechanical set: with every rule splitting bands, the one-row
    // schedules (UH-1, AC-1, CU-1) and the two-row one (IRH-1/2) had < 3 bands and 5 of 7 schedules
    // on the sheet were refused. A band counts when >= 3 of its cells are wider than minRow and at
    // least half of those hold ink (measured per CELL, inset off its rules: the strip between a double
    // wall's two lines is crossed by the other walls, so a whole-band ink test let the test's corridor
    // plan through; its cells, rules excluded, are empty).
    const F = ys.filter((_, i) => full[i]);
    let bands = 0, bandSum = 0;
    for (let k = 0; k + 1 < F.length; k++) {
      const bh = F[k + 1] - F[k];
      if (bh < o.minRow || bh > o.maxRow) continue;
      const ym = (F[k] + F[k + 1]) / 2;
      const cuts = [0]; for (let c = 1; c + 1 < xs.length; c++) if (vAt(c, ym)) cuts.push(c);
      cuts.push(xs.length - 1);
      let wide = 0, inked = 0;
      for (let j = 0; j + 1 < cuts.length; j++) {
        const cw = xs[cuts[j + 1]] - xs[cuts[j]];
        if (cw < o.minRow) continue;
        wide++;
        if (!isEmptyCell(img, { x: xs[cuts[j]], y: F[k], w: cw, h: bh }, t + 1, o.dark)) inked++;
      }
      if (wide >= 3 && inked * 2 >= wide) { bands++; bandSum += bh; }
    }
    // ...and those bands make up >= 20 % of the table's height. A detail sheet's layout frame (M0.3 and
    // M0.4 of the mechanical set: 4 boxes 1,717 px tall with 120 px title strips at 200 dpi) passed the
    // band test on its title strips alone; its bands are 6.5 % of its height. The schedules on M0.1,
    // M0.2 and P-0.01 measured 29-74 %, the notes block under a schedule being most of the rest.
    if (bands < 2 || bandSum < 0.2 * (Y1 - Y0)) continue;
    // merged regions
    const R = ys.length - 1, C = xs.length - 1;
    const id = new Int32Array(R * C).map((_, i) => i);
    const f2 = (i: number): number => { while (id[i] !== i) { id[i] = id[id[i]]; i = id[i]; } return i; };
    const join = (a: number, b: number) => { const ra = f2(a), rb = f2(b); if (ra !== rb) id[Math.max(ra, rb)] = Math.min(ra, rb); };
    for (let r = 0; r < R; r++) for (let c = 0; c < C; c++) {
      if (c + 1 < C && !vAt(c + 1, (ys[r] + ys[r + 1]) / 2)) join(r * C + c, r * C + c + 1);
      if (r + 1 < R && !hAt(r + 1, (xs[c] + xs[c + 1]) / 2)) join(r * C + c, (r + 1) * C + c);
    }
    const reg = new Map<number, { r0: number; r1: number; c0: number; c1: number }>();
    for (let r = 0; r < R; r++) for (let c = 0; c < C; c++) {
      const k = f2(r * C + c); const e = reg.get(k);
      if (!e) reg.set(k, { r0: r, r1: r, c0: c, c1: c });
      else { e.r0 = Math.min(e.r0, r); e.r1 = Math.max(e.r1, r); e.c0 = Math.min(e.c0, c); e.c1 = Math.max(e.c1, c); }
    }
    const cells: GridCell[] = [...reg.values()].map((e) => ({
      r: e.r0, c: e.c0, rs: e.r1 - e.r0 + 1, cs: e.c1 - e.c0 + 1,
      x: xs[e.c0], y: ys[e.r0], w: xs[e.c1 + 1] - xs[e.c0], h: ys[e.r1 + 1] - ys[e.r0],
    })).sort((a, b) => a.r - b.r || a.c - b.c);
    tables.push({ bbox: { x: X0, y: Y0, w: tw, h: Y1 - Y0 }, rowsY: ys, colsX: xs, cells, bandShare: bandSum / (Y1 - Y0) });
  }
  // reading order: top to bottom, then left to right
  return tables.sort((a, b) => a.bbox.y - b.bbox.y || a.bbox.x - b.bbox.x);
}
