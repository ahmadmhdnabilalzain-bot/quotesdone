// drawing_lengths — duct and pipe LENGTHS measured from a CAD drawing's layer geometry at its printed
// scale, with no model (22 Sep 2026, agent: sales_engineer; founder instructions 30, 579, 580: "count
// the elements properly"; 31, 63, 64: real quantity take-off, to the OpenConstructionERP bar).
//
// MEASURED BEFORE THIS FILE. On the two real US bid sets (local only, copyrighted) the take-off had every
// duct and pipe SIZE but no LENGTH: 7 of the 10 partial items of the 49-item key were "size found, length
// to be measured". The lengths are not printed. They ARE drawn: both sets carry their CAD layers as PDF
// optional content (57 and 50 layers: M-HVAC-DUCT, P-SANR, P-VENT, P-DOMW-CW, P-DOMW-HW, P-EXIST-SANR ...),
// and pdf_text_positions now returns every stroked segment with its layer. This file turns that into
// lengths the way an estimator scales them off a plan:
//
//  * SCALE - every "SCALE: 1/4" = 1'-0"" / "1:100" label on the sheet, with its position. A run is
//    measured at the scale of the nearest label (a sheet with an enlarged plan beside the main plan has
//    two). No scale label, or "NTS" -> no length, and the line says why. Never guessed.
//  * PIPE - one line per run. The layer names the system (P-SANR = sanitary, P-VENT = vent, P-DOMW-CW =
//    cold water, ...; EXIST layers are existing and are not scope). Lines that touch are joined into
//    runs, and each run takes the size of the nearest label of ITS system ("3" SS" never sizes a vent).
//  * DUCT - see measureDucts: double-line walls paired into a centreline, single-line round runs.
//
// CEILINGS, stated on every line's basis: plan length only - risers and drops drawn as a symbol are not
// in plan and are not added; fittings are measured through along the walls; a flex run drawn as a
// zig-zag is measured along the zig-zag. A PDF with no layers (a scan, a flattened export) gives no
// lengths here and the line keeps asking for the length.
import type { PdfPage, TextRun } from '../_shared/pdf_text_positions.ts';
import type { Box } from '../_shared/anonymise.ts';

const IN_M = 0.0254;
const cx = (r: TextRun) => r.x + r.w / 2;
const cy = (r: TextRun) => r.y + r.h / 2;
const inBox = (x: number, y: number, b: Box | null) => !!b && x >= b.x && x <= b.x + b.w && y >= b.y && y <= b.y + b.h;

/** Real inches per paper point for a printed scale, or null. 1/8" = 1'-0" -> 96 real in per paper in. */
export function parseScale(s: string): number | null {
  const t = s.replace(/[’′]/g, "'").replace(/[”″]/g, '"').toUpperCase();
  if (/\bN\.?T\.?S\b|NOT TO SCALE/.test(t)) return null;
  // imperial architectural: a/b" = f'-i"  or  n" = f'-i"
  let m = /(?:(\d+)\s*\/\s*(\d+)|(\d+(?:\.\d+)?))\s*"\s*=\s*(\d+)\s*'\s*(?:-?\s*(\d+(?:\.\d+)?)\s*")?/.exec(t);
  if (m) {
    const paperIn = m[3] ? Number(m[3]) : Number(m[1]) / Number(m[2]);
    const realIn = Number(m[4]) * 12 + (m[5] ? Number(m[5]) : 0);
    return paperIn > 0 && realIn > 0 ? realIn / paperIn / 72 : null;
  }
  m = /(?<![\d.])1\s*:\s*(\d{1,5})(?!\d)/.exec(t);
  if (m) return Number(m[1]) / 72;                  // 1:N -> N paper inches of site per paper inch
  return null;
}

export type ScaleLabel = { x: number; y: number; text: string; inPerPt: number | null };
/** Every scale label on the sheet with its position ("SCALE:" and its value may be separate runs). */
export function scaleLabels(p: PdfPage, strip: Box | null): ScaleLabel[] {
  const out: ScaleLabel[] = [];
  const runs = p.runs.filter((r) => !r.vertical && !inBox(cx(r), cy(r), strip));
  for (const r of runs) {
    const t = r.text.trim();
    if (!/^SCALE\b/i.test(t)) continue;
    let val = t.replace(/^SCALE\s*:?\s*/i, '');
    if (!val) {
      const nx = runs.filter((o) => o !== r && Math.abs(cy(o) - cy(r)) < r.h * 0.7 && o.x > r.x && o.x < r.x + r.w + 0.06).sort((a, b) => a.x - b.x);
      val = nx.map((o) => o.text.trim()).join(' ');
    }
    if (val) out.push({ x: cx(r), y: cy(r), text: val.trim(), inPerPt: parseScale(val) });
  }
  return out;
}

// -- systems ------------------------------------------------------------------------------------------
/** The pipe system a CAD layer draws, from the layer name (AIA / NCS layer names and their variants). */
export function pipeService(layer: string): { svc: string; existing: boolean } | null {
  const L = layer.toUpperCase().replace(/\s+/g, '').split('|').pop()!;
  if (!/^(P|M|PL|PLMB)-/.test(L) || /ANNO|TEXT|TXT|DIM|FITT|FIXT|EQPM|EQUIP|IDEN|SYMB|HATCH|DETL|DUCT|GRD/.test(L)) return null;
  const existing = /EXIST|-EXST|-DEMO/.test(L);
  const svc = /SANR|SAN\b|-SAN-|WAST|-SS\b/.test(L) ? 'SS' : /VENT/.test(L) ? 'V' : /HWR|HWC|RECIRC/.test(L) ? 'HWR'
    : /DOMW-HW|DOMW-SHW|-HW\b/.test(L) ? 'HW' : /DOMW-CW|DOMW-SCW|-CW\b/.test(L) ? 'CW' : /GAS|NGAS/.test(L) ? 'G'
    : /STRM|STORM|RAIN/.test(L) ? 'ST' : /PIPE-CD\b|COND|-CD\b/.test(L) ? 'CD' : /REFRIG|RFRG/.test(L) ? 'REF'
    : /CHW/.test(L) ? 'CHW' : /HHW/.test(L) ? 'HHW' : /-CA\b|AIR/.test(L) ? 'CA' : '';
  return svc ? { svc, existing } : null;
}
export const isDuctLayer = (layer: string) => { const L = layer.toUpperCase().split('|').pop()!; return /DUCT/.test(L) && !/EXIST|EXST|DEMO|ANNO|TEXT/.test(L); };
const LABEL_SVC: Record<string, string> = { SS: 'SS', SAN: 'SS', W: 'SS', V: 'V', VENT: 'V', CW: 'CW', HW: 'HW', HWR: 'HWR', G: 'G', GAS: 'G', ST: 'ST', RD: 'ST', CD: 'CD' };

/** A sheet's page size in paper points, display frame. */
const frame = (p: PdfPage) => ({ W: p.rotate % 180 ? p.height : p.width, H: p.rotate % 180 ? p.width : p.height });

/** A straight line in paper points, after dashes are joined: `pieces` is how many drawn strokes made it. */
export type Line = { ax: number; ay: number; bx: number; by: number; L: number; ux: number; uy: number; layer: string; pieces: number; dashed: boolean };
/** Gap between two strokes of one dashed line that is still the same line (paper points). */
export const DASH_GAP_PT = 9;
/** Lines of one system measured per sheet. Measured 22 Sep 2026: the real M1.0 has ~2,000 duct lines and
 *  measures in ~0.1 s; a synthetic sheet of 20,000 took 1.2-2.4 s, too close to the edge CPU cap. Past this
 *  ceiling the sheet is NOT measured and its lines keep asking for the length (drawing_set says why) -
 *  an honest gap instead of an isolate killed with no answer.
 *  ponytail: a fixed ceiling; split the sheet into tiles across calls if real drawings ever reach it. */
export const MAX_MEASURED_LINES = 10_000;
/** True when a sheet has more lines of duct or pipe than one call measures. */
export function tooDense(p: PdfPage, strip: Box | null): boolean {
  return linesOf(p, isDuctLayer, strip).length > MAX_MEASURED_LINES || linesOf(p, (l) => { const s = pipeService(l); return !!s && !s.existing; }, strip).length > MAX_MEASURED_LINES;
}

/**
 * The layer's segments as LINES. Measured 22 Sep 2026 on the plumbing set: the below-slab sanitary run is
 * drawn dashed and CAD exported every dash as its own segment (13.5 pt dashes, 4.6 pt gaps), so summing
 * segments lost a quarter of the pipe. Collinear strokes with gaps up to DASH_GAP_PT are one line, and the
 * gaps count. A line of three or more short strokes WITH GAPS between them (over 10 % of its length) is `dashed`: a liner,
 * a hidden line. A solid line merely split at every tee has no gaps and stays solid.
 */
export function linesOf(p: PdfPage, pick: (layer: string) => boolean, strip: Box | null): Line[] {
  const { W, H } = frame(p);
  const groups = new Map<string, { t0: number; t1: number; layer: string; ux: number; uy: number; ox: number; oy: number }[]>();
  for (const [layer, s] of Object.entries(p.layers || {})) {
    if (!pick(layer)) continue;
    for (let k = 0; k < s.length; k += 4) {
      if (inBox((s[k] + s[k + 2]) / 2, (s[k + 1] + s[k + 3]) / 2, strip)) continue;
      let ax = s[k] * W, ay = s[k + 1] * H, bx = s[k + 2] * W, by = s[k + 3] * H;
      const L = Math.hypot(bx - ax, by - ay); if (L < 0.2) continue;
      let ux = (bx - ax) / L, uy = (by - ay) / L;
      if (ux < -1e-9 || (Math.abs(ux) < 1e-9 && uy < 0)) { [ax, ay, bx, by] = [bx, by, ax, ay]; ux = -ux; uy = -uy; }
      const ang = Math.round(Math.atan2(uy, ux) * 180 / Math.PI * 4) / 4;          // 0.25 degree
      const rho = Math.round((ax * -uy + ay * ux) * 2) / 2;                           // 0.5 pt
      const key = `${layer}|${ang}|${rho}`;
      const t0 = ax * ux + ay * uy, t1 = bx * ux + by * uy;
      const g = groups.get(key) || []; g.push({ t0, t1, layer, ux, uy, ox: ax - t0 * ux, oy: ay - t0 * uy }); groups.set(key, g);
    }
  }
  const out: Line[] = [];
  for (const g of groups.values()) {
    g.sort((a, b) => a.t0 - b.t0);
    let cur = { ...g[0], n: 1, drawn: g[0].t1 - g[0].t0 };
    const flush = () => {
      const L = cur.t1 - cur.t0;
      out.push({ ax: cur.ox + cur.t0 * cur.ux, ay: cur.oy + cur.t0 * cur.uy, bx: cur.ox + cur.t1 * cur.ux, by: cur.oy + cur.t1 * cur.uy, L, ux: cur.ux, uy: cur.uy, layer: cur.layer, pieces: cur.n, dashed: cur.n >= 3 && cur.drawn / cur.n <= 20 && cur.drawn < L * 0.9 });
    };
    for (let i = 1; i < g.length; i++) {
      const s = g[i];
      if (s.t0 - cur.t1 <= DASH_GAP_PT) { if (s.t1 > cur.t1) { cur.drawn += s.t1 - Math.max(s.t0, cur.t1); cur.t1 = s.t1; } cur.n++; }
      else { flush(); cur = { ...s, n: 1, drawn: s.t1 - s.t0 }; }
    }
    flush();
  }
  return out;
}

const distToLine = (x: number, y: number, s: Line) => {
  const t = Math.max(0, Math.min(s.L, (x - s.ax) * s.ux + (y - s.ay) * s.uy));
  return Math.hypot(x - s.ax - t * s.ux, y - s.ay - t * s.uy);
};

/** Lines joined end to end (0.05 paper inch) into runs. `same` decides which lines may join. */
function runsOf(lines: Line[], same: (a: Line, b: Line) => boolean = () => true): Line[][] {
  const parent = lines.map((_, i) => i);
  const find = (i: number): number => (parent[i] === i ? i : (parent[i] = find(parent[i])));
  const tol = 3.6;
  const at = new Map<string, number[]>();
  lines.forEach((s, i) => {
    for (const [x, y] of [[s.ax, s.ay], [s.bx, s.by]]) {
      const kx = Math.round(x / tol), ky = Math.round(y / tol);
      for (let dx = -1; dx <= 1; dx++) for (let dy = -1; dy <= 1; dy++) for (const j of at.get(`${kx + dx},${ky + dy}`) || []) if (same(lines[j], s)) parent[find(i)] = find(j);
      const k = `${kx},${ky}`; const g = at.get(k); if (g) g.push(i); else at.set(k, [i]);
    }
  });
  const runs = new Map<number, Line[]>();
  lines.forEach((s, i) => { const r = find(i); const a = runs.get(r) || []; a.push(s); runs.set(r, a); });
  return [...runs.values()];
}

export type Measured = { key: string; svc: string; kind: 'pipe' | 'duct'; pt: number; realIn: number; labelled: boolean; scale: string; layers: Set<string>; runs: number; single?: number };

function nearestScale(scales: ScaleLabel[], x: number, y: number): ScaleLabel | null {
  let best: ScaleLabel | null = null, bd = Infinity;
  for (const s of scales) { if (!s.inPerPt) continue; const d = Math.hypot(s.x - x, s.y - y); if (d < bd) { bd = d; best = s; } }
  return best;
}
const add = (out: Map<string, Measured>, k: string, init: Omit<Measured, 'pt' | 'realIn' | 'runs' | 'layers'>, pt: number, inPerPt: number, layers: string[]) => {
  const g = out.get(k) || { ...init, pt: 0, realIn: 0, runs: 0, layers: new Set<string>() };
  g.pt += pt; g.realIn += pt * inPerPt; g.runs++; layers.forEach((l) => g.layers.add(l)); out.set(k, g);
};
export type Trace = (x1: number, y1: number, x2: number, y2: number, key: string) => void;

/** Pipe runs of one plan sheet: new work only, sized by the nearest label of the same system. */
export function measurePipes(p: PdfPage, strip: Box | null, scales: ScaleLabel[], trace?: Trace): Measured[] {
  const { W, H } = frame(p);
  const lines = linesOf(p, (l) => { const s = pipeService(l); return !!s && !s.existing; }, strip);
  if (!lines.length || lines.length > MAX_MEASURED_LINES) return [];
  // Size labels of NEW pipe: "3" SS", "3/4" HW". "(E)4" SS" is existing and never sizes a new run.
  const labels: { svc: string; size: string; x: number; y: number }[] = [];
  for (const r of p.runs) {
    if (inBox(cx(r), cy(r), strip)) continue;
    const m = /^(?:\((E|R|N|D)\))?\s*(\d+(?:\s?\d\/\d)?|\d\/\d|\d+-\d\/\d)"\s*(SS|SAN|V|VENT|W|CW|HW|HWR|G|GAS|ST|RD|CD)$/.exec(r.text.trim().toUpperCase());
    if (m && m[1] !== 'E') labels.push({ svc: LABEL_SVC[m[3]], size: `${m[2].replace(/\s+/g, ' ')}"`, x: cx(r) * W, y: cy(r) * H });
  }
  const svcOf = (s: Line) => pipeService(s.layer)!.svc;
  const out = new Map<string, Measured>();
  for (const run of runsOf(lines, (a, b) => svcOf(a) === svcOf(b))) {
    const svc = svcOf(run[0]);
    const pt = run.reduce((a, s) => a + s.L, 0);
    if (pt < 3) continue;                                                        // a tick or a dot, not a run
    let best: typeof labels[number] | null = null, bd = Infinity;
    for (const l of labels) {
      if (l.svc !== svc) continue;
      const d = Math.min(...run.map((s) => distToLine(l.x, l.y, s)));
      if (d < bd) { bd = d; best = l; }
    }
    const mx = run.reduce((a, s) => a + s.ax + s.bx, 0) / (2 * run.length), my = run.reduce((a, s) => a + s.ay + s.by, 0) / (2 * run.length);
    const sc = nearestScale(scales, mx / W, my / H); if (!sc) continue;
    const k = best ? `${best.size} ${svc}` : `${svc} (size not labelled)`;
    add(out, k, { key: k, svc, kind: 'pipe', labelled: !!best, scale: sc.text }, pt, sc.inPerPt!, run.map((s) => s.layer));
    if (trace) for (const s of run) trace(s.ax / W, s.ay / H, s.bx / W, s.by / H, k);
  }
  return [...out.values()];
}

/**
 * Duct of one plan sheet, drawn two ways and measured both ways:
 *  * DOUBLE-LINE (rectangular and large round): two SOLID parallel walls. Each wall is paired with the
 *    nearest solid parallel wall 3.5"–42" away; the overlap is the centreline, the gap is the plan width,
 *    and the stretch takes the nearest printed size of that width. Dashed lines between the walls are the
 *    liner (measured 22 Sep 2026: a lined 28x20 carries dashed lines 4" inside each wall, and pairing a
 *    wall with its liner had booked 98 ft of "4" round"), so they never pair.
 *  * SINGLE-LINE (small round, drawn as one line with its "8"Ø" label): a run of the duct layer that is
 *    not part of a double-line system. It takes the nearest round size label.
 */
export function measureDucts(p: PdfPage, strip: Box | null, scales: ScaleLabel[], trace?: Trace): Measured[] {
  const { W, H } = frame(p);
  const lines = linesOf(p, isDuctLayer, strip);
  if (!lines.length || lines.length > MAX_MEASURED_LINES) return [];
  const labels: { key: string; w: number; round: boolean; x: number; y: number }[] = [];
  for (const r of p.runs) {
    if (inBox(cx(r), cy(r), strip)) continue;
    const t = r.text.trim().toUpperCase();
    let m = /^(\d{1,2})\s*"?\s*X\s*(\d{1,2})"?(\s*\(1"\s*LNR\))?(?:\s*\(\d\))?(?:\s+(?:UP|DN|DOWN))?$/.exec(t);
    if (m) { labels.push({ key: `${m[1]}x${m[2]}${m[3] ? ' (1" liner)' : ''}`, w: Number(m[1]), round: false, x: cx(r) * W, y: cy(r) * H }); continue; }
    m = /^(\d{1,2})\s*"\s*(?:Ø|DIA)(?:\s+(?:UP|DN|DOWN))?$/.exec(t);
    if (m) labels.push({ key: `${m[1]}" round`, w: Number(m[1]), round: true, x: cx(r) * W, y: cy(r) * H });
  }
  const out = new Map<string, Measured>();
  type Part = { k: string; round: boolean; labelled: boolean; len: number; inPt: number; scale: string; x1: number; y1: number; x2: number; y2: number };
  const parts = new Map<Line, Part[]>();
  const covered = new Map<Line, number>();
  // A small CLOSED outline (a duct-up box, a roof-curb opening, both under 4 ft across) is a symbol: its
  // sides are parallel and would otherwise pair into a phantom stretch of duct.
  const symbol = new Set<Line>();
  for (const run of runsOf(lines)) {
    const deg = new Map<string, number>();
    for (const s of run) for (const [x, y] of [[s.ax, s.ay], [s.bx, s.by]]) { const k = `${Math.round(x / 3.6)},${Math.round(y / 3.6)}`; deg.set(k, (deg.get(k) || 0) + 1); }
    if ([...deg.values()].some((n) => n === 1)) continue;
    const xs = run.flatMap((s) => [s.ax, s.bx]), ys = run.flatMap((s) => [s.ay, s.by]);
    const sc = nearestScale(scales, (Math.min(...xs) + Math.max(...xs)) / 2 / W, (Math.min(...ys) + Math.max(...ys)) / 2 / H);
    if (sc && Math.max(Math.max(...xs) - Math.min(...xs), Math.max(...ys) - Math.min(...ys)) * sc.inPerPt! < 48) run.forEach((s) => symbol.add(s));
  }
  const solid = lines.filter((s) => !s.dashed && !symbol.has(s));
  // Parallel partners are looked up in a grid, never by scanning every line against every line: a dense
  // sheet of 20,000 duct lines cost 4.8 s of CPU with a coarser index in drawing_lengths.test.ts
  // (measured 22 Sep 2026), past the edge function's CPU cap, which kills the isolate with no answer
  // (memory: an edge function has a CPU cap a deadline does not bound). Each line is filed in every cell
  // its box touches; a line meets only the lines filed in the cells within the widest duct (42") of it.
  const minIn = Math.min(...scales.filter((s) => s.inPerPt).map((s) => s.inPerPt!));
  const cell = Math.max(24, 42 / minIn);
  const grid = new Map<string, number[]>();
  const cellsOf = (x0: number, y0: number, x1: number, y1: number, f: (k: string) => void) => {
    for (let i = Math.floor(x0 / cell); i <= Math.floor(x1 / cell); i++) for (let j = Math.floor(y0 / cell); j <= Math.floor(y1 / cell); j++) f(`${i},${j}`);
  };
  solid.forEach((s, n) => cellsOf(Math.min(s.ax, s.bx), Math.min(s.ay, s.by), Math.max(s.ax, s.bx), Math.max(s.ay, s.by), (k) => { const g = grid.get(k); if (g) g.push(n); else grid.set(k, [n]); }));
  const seen = new Int32Array(solid.length).fill(-1);
  const near = (a: Line, ai: number): Line[] => {
    const out: Line[] = [];
    cellsOf(Math.min(a.ax, a.bx) - cell, Math.min(a.ay, a.by) - cell, Math.max(a.ax, a.bx) + cell, Math.max(a.ay, a.by) + cell, (k) => {
      for (const n of grid.get(k) || []) if (seen[n] !== ai) { seen[n] = ai; out.push(solid[n]); }
    });
    return out;
  };
  const nearestOfWidth = (d: number, x: number, y: number) => {
    const tolW = Math.max(1.5, d * 0.12);
    let best: typeof labels[number] | null = null, bd = Infinity;
    for (const l of labels) { if (Math.abs(l.w - d) > tolW) continue; const e = Math.hypot(l.x - x, l.y - y); if (e < bd) { bd = e; best = l; } }
    return best;
  };
  for (let ai = 0; ai < solid.length; ai++) {
    const a = solid[ai];
    const sc = nearestScale(scales, (a.ax + a.bx) / 2 / W, (a.ay + a.by) / 2 / H); if (!sc) continue;
    const inPt = sc.inPerPt!;
    if (a.L * inPt < 6) continue;                                                // under 6 real inches: a fitting edge
    const cand: { d: number; lo: number; hi: number }[] = [];
    for (const b of near(a, ai)) {
      if (b === a || Math.abs(a.ux * b.uy - a.uy * b.ux) > 0.02) continue;
      const d = Math.abs((b.ax - a.ax) * -a.uy + (b.ay - a.ay) * a.ux) * inPt;   // real inches
      if (d < 3.5 || d > 42) continue;
      const t1 = (b.ax - a.ax) * a.ux + (b.ay - a.ay) * a.uy, t2 = (b.bx - a.ax) * a.ux + (b.by - a.ay) * a.uy;
      const lo = Math.max(0, Math.min(t1, t2)), hi = Math.min(a.L, Math.max(t1, t2));
      if ((hi - lo) * inPt >= 6) cand.push({ d, lo, hi });
    }
    if (!cand.length) continue;
    // Along the wall, each stretch takes its NEAREST partner: a wall beside a trunk and a branch has two.
    cand.sort((x, y) => x.d - y.d);
    const taken: [number, number][] = [];
    const mine: Part[] = []; let cov = 0;
    for (const c of cand) {
      let pieces: [number, number][] = [[c.lo, c.hi]];
      for (const [tl, th] of taken) pieces = pieces.flatMap(([l, h]) => (th <= l || tl >= h ? [[l, h]] : [...(tl > l ? [[l, tl]] : []), ...(th < h ? [[th, h]] : [])]) as [number, number][]);
      pieces = pieces.filter(([l, h]) => (h - l) * inPt >= 3);
      if (!pieces.length) continue;
      taken.push([c.lo, c.hi]);
      // A long wall can carry two sizes one after the other (a lined 28x20 that continues as 26x18 at the
      // same outside width): every foot of it takes the nearest printed size of that width.
      const step = 12 / inPt;
      for (const [l, h] of pieces) {
        cov += h - l;
        for (let t = l; t < h; t += step) {
          const e = Math.min(h, t + step), m = (t + e) / 2;
          const best = nearestOfWidth(c.d, a.ax + a.ux * m, a.ay + a.uy * m);
          mine.push({ k: best ? best.key : `${Math.round(c.d)}" wide (size not labelled)`, round: !!best?.round, labelled: !!best, len: (e - t) / 2, inPt, scale: sc.text, x1: a.ax + a.ux * t, y1: a.ay + a.uy * t, x2: a.ax + a.ux * e, y2: a.ay + a.uy * e });
        }
      }
    }
    if (mine.length) { parts.set(a, mine); covered.set(a, cov); }
  }
  // Each line is either a WALL (at least half of it paired: its stretches count) or not. Lines that are not
  // walls are joined into runs, and a run is a SINGLE-LINE duct counted at its full length (measured 22 Sep
  // 2026: the 10x10, 8x8, 6x6 and 8"Ø branches of M1.0 are one heavy line each, some drawn dashed, and they
  // meet the double-line trunk end to end) unless it is:
  //  * a LINER - a dashed line within 6" of a wall, parallel to it (a lined 28x20 carries one 4" inside
  //    each wall);
  //  * a FITTING - no straight line of 1 ft, or under 18" in all (elbow arcs are short chords, a tap is a
  //    stub), or every free end sits on a wall's end (an end cap, a transition edge);
  //  * a SYMBOL - closed, with no free end (a duct-up box, an opening in a roof curb).
  const walls = lines.filter((s) => (covered.get(s) || 0) >= s.L * 0.5);
  const wallEnds = new Set<string>();
  const q = (x: number, y: number) => `${Math.round(x / 3.6)},${Math.round(y / 3.6)}`;
  for (const s of walls) for (const [x, y] of [[s.ax, s.ay], [s.bx, s.by]]) { const [kx, ky] = q(x, y).split(',').map(Number); for (let dx = -1; dx <= 1; dx++) for (let dy = -1; dy <= 1; dy++) wallEnds.add(`${kx + dx},${ky + dy}`); }
  const isLiner = (s: Line) => {
    const sc = nearestScale(scales, (s.ax + s.bx) / 2 / W, (s.ay + s.by) / 2 / H); if (!sc) return false;
    return walls.some((w) => Math.abs(s.ux * w.uy - s.uy * w.ux) <= 0.02 && Math.abs((s.ax - w.ax) * -w.uy + (s.ay - w.ay) * w.ux) * sc.inPerPt! < 6
      && Math.min(w.L, Math.max((s.ax - w.ax) * w.ux + (s.ay - w.ay) * w.uy, (s.bx - w.ax) * w.ux + (s.by - w.ay) * w.uy)) - Math.max(0, Math.min((s.ax - w.ax) * w.ux + (s.ay - w.ay) * w.uy, (s.bx - w.ax) * w.ux + (s.by - w.ay) * w.uy)) > 0);
  };
  const other: Line[] = [];
  for (const s of lines) {
    if ((covered.get(s) || 0) >= s.L * 0.5) {
      for (const p2 of parts.get(s) || []) {
        add(out, p2.k, { key: p2.k, svc: p2.round ? 'round' : 'rect', kind: 'duct', labelled: p2.labelled, scale: p2.scale }, p2.len, p2.inPt, [s.layer]);
        if (trace) trace(p2.x1 / W, p2.y1 / H, p2.x2 / W, p2.y2 / H, p2.k);
      }
    } else if (!(s.dashed && isLiner(s))) other.push(s);
  }
  for (const run of runsOf(other)) {
    const xs = run.flatMap((s) => [s.ax, s.bx]), ys = run.flatMap((s) => [s.ay, s.by]);
    const mx = (Math.min(...xs) + Math.max(...xs)) / 2, my = (Math.min(...ys) + Math.max(...ys)) / 2;
    const sc = nearestScale(scales, mx / W, my / H); if (!sc) continue;
    const total = run.reduce((a, s) => a + s.L, 0);
    if (Math.max(...run.map((s) => s.L)) * sc.inPerPt! < 12 || total * sc.inPerPt! < 18) continue;
    const ends = new Map<string, number>();
    for (const s of run) for (const [x, y] of [[s.ax, s.ay], [s.bx, s.by]]) { const k = q(x, y); ends.set(k, (ends.get(k) || 0) + 1); }
    const free = [...ends.entries()].filter(([, n]) => n === 1).map(([k]) => k);
    if (!free.length) continue;                                                  // closed: a symbol
    if (free.every((k) => wallEnds.has(k))) continue;                            // an end cap or a transition edge
    let best: typeof labels[number] | null = null, bd = Infinity;
    for (const l of labels) { const d = Math.min(...run.map((s) => distToLine(l.x, l.y, s))); if (d < bd) { bd = d; best = l; } }
    const k = best ? best.key : 'single-line duct (size not labelled)';
    add(out, k, { key: k, svc: best?.round ? 'round' : 'rect', kind: 'duct', labelled: !!best, scale: sc.text }, total, sc.inPerPt!, run.map((s) => s.layer));
    out.get(k)!.single = (out.get(k)!.single || 0) + total * sc.inPerPt!;
    if (trace) for (const s of run) trace(s.ax / W, s.ay / H, s.bx / W, s.by / H, k + ' single');
  }
  return [...out.values()];
}

export const metres = (realIn: number) => Math.round(realIn * IN_M * 10) / 10;
export const feet = (realIn: number) => Math.round((realIn / 12) * 10) / 10;
