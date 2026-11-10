// cad — quantities and text read off an ASCII DXF drawing, with no model and no CAD kernel (14 Sep 2026).
//
// WHY. A DXF is the one CAD format that is plain text and publicly specified (group-code / value
// pairs). Customers export floor plans as DXF; the layer names, block names and closed outlines in it
// ARE the takeoff a quantity surveyor would start from: "block D-900 inserted 14 times", "layer FLOOR,
// 3 closed polylines, 86.40 sqm". Before this reader, a DXF was stored unread.
//
// WHAT IT READS. HEADER $INSUNITS (the drawing unit). ENTITIES section only — BLOCKS holds block
// DEFINITIONS, and counting a door's own lines as walls would double every figure. TEXT, MTEXT (with
// formatting codes stripped), ATTRIB and DIMENSION measured values go to text. INSERTs are counted
// per block name (anonymous '*' blocks are dimension/hatch internals and are skipped). LINE, ARC,
// CIRCLE, LWPOLYLINE and POLYLINE/VERTEX lengths are summed per layer, with bulge arcs measured as
// arcs; closed polylines add their area (shoelace plus each bulge's circular segment) per layer.
// Everything is converted to metres and square metres.
//
// A DWG reaches this reader too: dwg.ts (22 Sep 2026) opens it with LibreDWG and hands its entities over
// as ASCII DXF, so a DWG and a DXF share this one take-off.
//
// A BINARY DXF reaches it too (22 Sep 2026): binaryDxfToAscii below turns its pairs into ASCII first.
//
// THE GEOMETRY (10 Nov 2026, sales_engineer): beside the per-layer totals, the model-space geometry they were summed
// from - segments per layer, closed outlines with their vertices, text with its position, block placements - goes back
// as `cad` (types.ts CadGeometry) for the engineer's take-off: rooms, finishes and schedules (drawing_boq/
// region_takeoff.ts) and duct / pipe / tray / conduit / steel runs by size (drawing_boq/linear_services.ts).
// Paper space (the title block) is left out of it. Capped at GEOM_MAX_* so a dense drawing stays inside the edge.
//
// WHAT IT NEVER DOES. It does not explode blocks,
// apply viewport scales, or guess what a layer means. Without $INSUNITS the unit is a guess and
// every quantity says so at confidence 'low'. Identity is NOT scrubbed here; the caller does that.
import { capText, empty, LIMITS, ok, refuse, type CadGeometry, type Qty, type ReadContext, type ReadResult } from './types.ts';

/** Geometry kept for the take-offs (drawing_boq/architectural.ts, linear_services.ts): past these the geometry is partial. */
export const GEOM_MAX_SEGS = 400_000, GEOM_MAX_CLOSED = 20_000, GEOM_MAX_WORDS = 50_000;

/** A legend's own heading: "LEGEND", "SYMBOL LEGEND", "KEY", "SYMBOLS", "مفتاح الرموز". */
const LEGEND_HEADING = /^\s*(?:(?:electrical|fire\s*alarm|symbols?)\s+)?(?:legend|key|symbols?)(?:\s+(?:of\s+)?symbols?)?\s*:?\s*$|^\s*(?:مفتاح\s*الرموز|دليل\s*الرموز)\s*$/i;

/** 200,000 entities is a dense multi-storey plan; past it the reader stops and says so. */
export const DXF_MAX_ENTITIES = 200_000;

// $INSUNITS code -> metres per drawing unit (AutoCAD DXF reference, HEADER variables).
const UNIT_M: Record<number, [number, string]> = {
  1: [0.0254, 'in'], 2: [0.3048, 'ft'], 3: [1609.344, 'mi'], 4: [0.001, 'mm'], 5: [0.01, 'cm'],
  6: [1, 'm'], 7: [1000, 'km'], 10: [0.9144, 'yd'], 14: [0.1, 'dm'],
};

type Ent = { type: string; pairs: [number, string][] };

/** MTEXT inline formatting -> plain text. \P paragraph, \f..; font, {\C1;..} groups, %%c/%%d/%%p symbols. */
export function stripMtext(s: string): string {
  return s
    .replace(/\\\\/g, '\u0000')                        // a literal backslash, restored below
    .replace(/\\U\+([0-9A-Fa-f]{4})/g, (_m, h) => String.fromCharCode(parseInt(h, 16)))
    .replace(/\\P/g, '\n').replace(/\\~/g, ' ')
    .replace(/\\S([^;]*?)[\^#/]([^;]*);/g, '$1/$2')
    .replace(/\\[fFcCHhTtQqWwAap][^;\\{}]*;/g, '')   // codes that end in ';' (font, colour, height...)
    .replace(/\\[LlOoKkNnX]/g, '')                    // toggles with no argument (underline, overline...)
    .replace(/\\\\/g, '\u0000').replace(/[{}]/g, '').replace(/\u0000/g, '\\')
    .replace(/%%[cC]/g, 'Ø').replace(/%%[dD]/g, '°').replace(/%%[pP]/g, '±').replace(/%%%/g, '%');
}

/** Length and signed area contribution of one polyline edge with a bulge (tan of a quarter of the arc angle). */
function edge(x1: number, y1: number, x2: number, y2: number, b: number): { len: number; seg: number } {
  const c = Math.hypot(x2 - x1, y2 - y1);
  if (!b || !c) return { len: c, seg: 0 };
  const th = 4 * Math.atan(b);                 // signed included angle
  const r = c / (2 * Math.sin(Math.abs(th) / 2));
  return { len: r * Math.abs(th), seg: (r * r / 2) * (th - Math.sin(th)) };
}

function polyMeasure(v: { x: number; y: number; b: number }[], closed: boolean): { len: number; area: number } {
  let len = 0, shoe = 0, seg = 0;
  const n = v.length, last = closed ? n : n - 1;
  for (let i = 0; i < last; i++) {
    const a = v[i], z = v[(i + 1) % n];
    const e = edge(a.x, a.y, z.x, z.y, a.b);
    len += e.len; seg += e.seg;
    shoe += a.x * z.y - z.x * a.y;
  }
  return { len, area: closed && n >= 2 ? Math.abs(shoe / 2 + seg) : 0 };
}

// ---------------------------------------------------------------------------------------------------
// BINARY DXF (22 Sep 2026, founder instructions 31/63/64/696). The same group-code/value pairs as an
// ASCII DXF, written as bytes: the 22-byte sentinel "AutoCAD Binary DXF\r\n\x1a\0", then each pair as a
// group code (2 bytes little-endian from R13; 1 byte in R12, where 255 means "a 2-byte code follows")
// and a value whose TYPE is fixed by the code's range (AutoCAD DXF Reference, "Group Code Value Types"):
// strings end in NUL, reals are 8-byte IEEE, integers 2/4/8 bytes, 290-299 booleans 1 byte, and binary
// chunks (310-319, 1004) a length byte and that many bytes. binaryDxfToAscii writes the pairs back out
// as ASCII DXF and readDxf does the ONE take-off. MEASURED on LibreDWG's test-data example_2000.dxfb
// and example_2018.dxfb against the ASCII DXF of the same drawing: see cad.test.ts (fetched at test
// time, never committed). A code outside every range, or a value running past the end, stops the read:
// a misread type would shift every following pair, so nothing after it could be trusted.
type BinT = 's' | 'f' | 'h' | 'i' | 'q' | 'b' | 'x';
function binType(c: number): BinT | null {
  if (c <= 9 || c === 100 || c === 101 || c === 102 || c === 105 || (c >= 300 && c <= 309) || (c >= 320 && c <= 369) || (c >= 390 && c <= 399) ||
    (c >= 410 && c <= 419) || (c >= 430 && c <= 439) || (c >= 470 && c <= 481) || c === 999 || (c >= 1000 && c <= 1009 && c !== 1004)) return 's';
  if ((c >= 10 && c <= 59) || (c >= 110 && c <= 149) || (c >= 210 && c <= 239) || (c >= 460 && c <= 469) || (c >= 1010 && c <= 1059)) return 'f';
  if ((c >= 60 && c <= 79) || (c >= 170 && c <= 179) || (c >= 270 && c <= 289) || (c >= 370 && c <= 389) || (c >= 400 && c <= 409) || (c >= 1060 && c <= 1070)) return 'h';
  if ((c >= 90 && c <= 99) || (c >= 420 && c <= 429) || (c >= 440 && c <= 459) || c === 1071) return 'i';
  if (c >= 160 && c <= 169) return 'q';
  if (c >= 290 && c <= 299) return 'b';
  if ((c >= 310 && c <= 319) || c === 1004) return 'x';
  return null;
}

/** Binary DXF bytes -> ASCII DXF text. Throws on a structure it cannot follow (caller refuses). */
export function binaryDxfToAscii(bytes: Uint8Array, maxPairs = DXF_MAX_ENTITIES * 40): { dxf: string; pairs: number; capped: boolean } {
  const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const n = bytes.length;
  // R12 writes 1-byte codes: the first pair after the sentinel is code 0 "SECTION", so byte 22 is 0 and
  // byte 23 is 'S' (0x53) in R12, while R13+ has a second zero byte there.
  const wide = bytes[23] === 0;
  const lat = new TextDecoder('latin1'), utf = new TextDecoder('utf-8');
  const out: string[] = [];
  let p = 22, pairs = 0, capped = false, utf8 = false;
  const need = (k: number) => { if (p + k > n) throw new Error(`binary DXF truncated at byte ${p}`); };
  while (p < n) {
    if (pairs >= maxPairs) { capped = true; break; }
    need(wide ? 2 : 1);
    let code: number;
    if (wide) { code = dv.getInt16(p, true); p += 2; } else { code = bytes[p++]; if (code === 255) { need(2); code = dv.getInt16(p, true); p += 2; } }
    const t = binType(code);
    if (!t) throw new Error(`binary DXF: group code ${code} at byte ${p} has no known value type`);
    let v: string;
    switch (t) {
      case 's': { const e = bytes.indexOf(0, p); if (e < 0) throw new Error(`binary DXF: unterminated string at byte ${p}`); v = (utf8 ? utf : lat).decode(bytes.subarray(p, e)); p = e + 1; break; }
      case 'f': need(8); v = String(dv.getFloat64(p, true)); p += 8; break;
      case 'h': need(2); v = String(dv.getInt16(p, true)); p += 2; break;
      case 'i': need(4); v = String(dv.getInt32(p, true)); p += 4; break;
      case 'q': need(8); v = String(dv.getBigInt64(p, true)); p += 8; break;
      case 'b': need(1); v = String(bytes[p++]); break;
      case 'x': { need(1); const len = bytes[p++]; need(len); v = [...bytes.subarray(p, p + len)].map((x) => x.toString(16).padStart(2, '0')).join('').toUpperCase(); p += len; break; }
    }
    // From AutoCAD 2007 (AC1021) text is UTF-8; before it, the $DWGCODEPAGE code page (read as latin1).
    if (code === 1 && out[out.length - 1] === '$ACADVER') utf8 = v >= 'AC1021';
    out.push(String(code), v.replace(/\r?\n/g, '\\P'));
    pairs++;
    if (code === 0 && v === 'EOF') break;
  }
  return { dxf: out.join('\n') + '\n', pairs, capped };
}

/** Binary DXF: converted to ASCII pairs, then the one take-off below. */
async function readBinaryDxf(bytes: Uint8Array, ctx: ReadContext, maxEntities: number): Promise<ReadResult> {
  let conv: ReturnType<typeof binaryDxfToAscii>;
  try { conv = binaryDxfToAscii(bytes); } catch (e) { return refuse('dxf_unreadable', String((e as Error)?.message || e).slice(0, 160)); }
  const r = await readDxf(new TextEncoder().encode(conv.dxf), ctx, maxEntities);
  if (!r.ok) return r;
  const notes = [`Read from binary DXF: ${conv.pairs} group-code pairs.`];
  if (conv.capped) notes.push(`The binary DXF has more than ${conv.pairs} group-code pairs; reading stopped there, so totals are partial.`);
  return ok({ ...r, notes: [...notes, ...r.notes] });
}

export async function readDxf(bytes: Uint8Array, ctx: ReadContext, maxEntities = DXF_MAX_ENTITIES): Promise<ReadResult> {
  const head = new TextDecoder('latin1').decode(bytes.subarray(0, 22));
  if (head.startsWith('AutoCAD Binary DXF')) return readBinaryDxf(bytes, ctx, maxEntities);
  const src = new TextDecoder('utf-8').decode(bytes);
  const lines = src.split(/\r?\n/);
  if (!/^\s*0\s*$/.test(lines[0] ?? '') && !src.slice(0, 2000).includes('SECTION')) {
    return refuse('dxf_unreadable', 'Not an ASCII DXF file (no group-code/value pairs).');
  }

  // Walk pairs, tracking section; collect HEADER $INSUNITS and ENTITIES entities.
  let insunits: number | null = null, section = '', pendingSection = false, lastHeaderVar = '';
  const ents: Ent[] = [];
  let cur: Ent | null = null, capped = false;
  // Block definitions (BLOCKS) and the block table's handles (TABLES BLOCK_RECORD), for nested and dynamic blocks.
  const defs = new Map<string, Ent[]>();
  let defName = '', defEnts: Ent[] | null = null, rec: Ent | null = null;
  const recs: Ent[] = [];
  for (let i = 0; i + 1 < lines.length; i += 2) {
    const code = parseInt(lines[i].trim(), 10);
    const val = lines[i + 1].replace(/\s+$/, '');
    if (!Number.isFinite(code)) return refuse('dxf_unreadable', `Group code expected at line ${i + 1}.`);
    if (code === 0) {
      if (cur) { if (section === 'ENTITIES') ents.push(cur); cur = null; }
      const t = val.trim();
      if (t === 'SECTION') { pendingSection = true; continue; }
      if (t === 'ENDSEC') { section = ''; continue; }
      if (t === 'EOF') break;
      if (section === 'ENTITIES') {
        if (ents.length >= maxEntities) { capped = true; break; }
        cur = { type: t, pairs: [] };
      } else if (section === 'BLOCKS') {
        if (t === 'BLOCK') { defName = ''; defEnts = []; rec = { type: t, pairs: [] }; }
        else if (t === 'ENDBLK') { if (defName && defEnts) defs.set(defName, defEnts); defEnts = null; rec = null; }
        else if (defEnts) { rec = null; cur = { type: t, pairs: [] }; defEnts.push(cur); }
      } else if (section === 'TABLES') { rec = t === 'BLOCK_RECORD' ? { type: t, pairs: [] } : null; if (rec) recs.push(rec); }
      continue;
    }
    if (pendingSection && code === 2) { section = val.trim(); pendingSection = false; continue; }
    if (section === 'HEADER') {
      if (code === 9) lastHeaderVar = val.trim();
      else if (lastHeaderVar === '$INSUNITS' && code === 70) insunits = parseInt(val.trim(), 10);
    } else if (section === 'BLOCKS' && rec && !cur) { if (code === 2) defName = val.trim(); }
    else if (section === 'TABLES' && rec) rec.pairs.push([code, val]);
    else if (cur) cur.pairs.push([code, val]);
  }
  if (cur && section === 'ENTITIES') ents.push(cur);

  const notes: string[] = [];
  const text: string[] = [];
  const used = { n: 0 };
  const addText = (s: string) => { for (const l of s.split('\n')) { const t = l.trim(); if (t) capText(text, t + '\n', used); } };

  // Pass 1: raw measures in drawing units.
  const lenBy = new Map<string, { v: number; n: number }>();
  const areaBy = new Map<string, { v: number; n: number }>();
  const inserts = new Map<string, number>();
  const placed: { name: string; x: number; y: number; n: number; layer: string; rot: number; paper: boolean }[] = [];
  // THE GEOMETRY (10 Nov 2026): model space only - a paper-space title block is not part of what is built.
  const geo: CadGeometry = { toM: 1, unitStated: false, unitName: 'm', segs: {}, closed: [], words: [], inserts: [], capped: false };
  let nSegs = 0;
  const seg = (layer: string, x1: number, y1: number, x2: number, y2: number) => {
    if (nSegs >= GEOM_MAX_SEGS) { geo.capped = true; return; }
    (geo.segs[layer] ??= []).push(x1, y1, x2, y2); nSegs++;
  };
  const word = (s: string, x: number, y: number, h: number, layer: string) => {
    const t = s.trim(); if (!t) return;
    if (geo.words.length >= GEOM_MAX_WORDS) { geo.capped = true; return; }
    for (const l of t.split('\n')) if (l.trim()) geo.words.push({ s: l.trim(), x, y, h, layer });
  };
  // DYNAMIC BLOCKS (19 Oct 2026, sales_engineer; founder 580). AutoCAD writes every flipped or stretched dynamic
  // block as an anonymous *U block whose BLOCK_RECORD carries XDATA AcDbBlockRepBTag -> the handle of the real
  // block. Those were all skipped as "anonymous", so dynamic doors were never counted. Resolved here by handle.
  const byHandle = new Map<string, string>(), dyn = new Map<string, string>();
  for (const r of recs) { const h = r.pairs.find((x) => x[0] === 5)?.[1].trim(), n = r.pairs.find((x) => x[0] === 2)?.[1].trim(); if (h && n) byHandle.set(h.toUpperCase(), n); }
  for (const r of recs) {
    const n = r.pairs.find((x) => x[0] === 2)?.[1].trim() ?? '', k = r.pairs.findIndex((x) => x[0] === 1001 && x[1].trim() === 'AcDbBlockRepBTag');
    const h = k >= 0 ? r.pairs.slice(k + 1).find((x) => x[0] === 1005)?.[1].trim().toUpperCase() : undefined;
    if (n.startsWith('*') && h && byHandle.has(h)) dyn.set(n, byHandle.get(h)!);
  }
  const blockOf = (e: Ent) => { const b = (e.pairs.find((x) => x[0] === 2)?.[1] ?? '').trim(); return b.startsWith('*') ? dyn.get(b) ?? null : b || null; };
  // MINSERT is an array of one block: columns (70) x rows (71).
  const copies = (e: Ent) => e.type === 'MINSERT' ? Math.max(1, parseInt(e.pairs.find((x) => x[0] === 70)?.[1] ?? '1', 10) || 1) * Math.max(1, parseInt(e.pairs.find((x) => x[0] === 71)?.[1] ?? '1', 10) || 1) : 1;
  // NESTED BLOCKS: a socket drawn inside a typical-room block is a socket in every room the block is placed in.
  const nested = (name: string, depth = 0, seen = new Set<string>()): Map<string, number> => {
    const out = new Map<string, number>();
    if (depth > 8 || seen.has(name)) return out;
    for (const c of defs.get(name) ?? []) {
      if (c.type !== 'INSERT' && c.type !== 'MINSERT') continue;
      const b = blockOf(c); if (!b) continue;
      const k = copies(c);
      out.set(b, (out.get(b) ?? 0) + k);
      for (const [g, v] of nested(b, depth + 1, new Set([...seen, name]))) out.set(g, (out.get(g) ?? 0) + k * v);
    }
    return out;
  };
  const words: { s: string; x: number; y: number; h: number }[] = [];
  let anon = 0, extent = 0;
  const bump = (m: Map<string, { v: number; n: number }>, k: string, v: number) => {
    const e = m.get(k) ?? { v: 0, n: 0 }; e.v += v; e.n++; m.set(k, e);
  };
  const num = (e: Ent, c: number, d = 0) => { const p = e.pairs.find((x) => x[0] === c); return p ? parseFloat(p[1]) || 0 : d; };
  const str = (e: Ent, c: number) => e.pairs.find((x) => x[0] === c)?.[1] ?? '';
  const see = (...xs: number[]) => { for (const x of xs) extent = Math.max(extent, Math.abs(x)); };
  let poly: { layer: string; closed: boolean; v: { x: number; y: number; b: number }[]; paper: boolean } | null = null;
  const endPoly = () => {
    if (!poly) return;
    const m = polyMeasure(poly.v, poly.closed);
    bump(lenBy, poly.layer, m.len);
    if (poly.closed) bump(areaBy, poly.layer, m.area);
    if (!poly.paper && poly.v.length >= 2) {
      const v = poly.v, last = poly.closed ? v.length : v.length - 1;
      for (let i = 0; i < last; i++) { const a = v[i], z = v[(i + 1) % v.length]; seg(poly.layer, a.x, a.y, z.x, z.y); }
      if (poly.closed && v.length >= 3) {
        if (geo.closed.length < GEOM_MAX_CLOSED) geo.closed.push({ layer: poly.layer, pts: v.map((p) => [p.x, p.y] as [number, number]), area: m.area, perim: m.len });
        else geo.capped = true;
      }
    }
    poly = null;
  };

  for (const e of ents) {
    const layer = str(e, 8).trim() || '0';
    const paper = str(e, 67).trim() === '1';
    if (e.type !== 'VERTEX' && e.type !== 'SEQEND') endPoly();
    switch (e.type) {
      case 'TEXT': case 'ATTRIB': addText(stripMtext(str(e, 1))); if (e.type === 'TEXT') words.push({ s: stripMtext(str(e, 1)).trim(), x: num(e, 10), y: num(e, 20), h: num(e, 40, 0) });
        if (!paper) word(stripMtext(str(e, 1)), num(e, 10), num(e, 20), num(e, 40, 0), layer); break;
      case 'MTEXT': { const s = stripMtext(e.pairs.filter((p) => p[0] === 3).map((p) => p[1]).join('') + str(e, 1)); addText(s); words.push({ s: s.trim(), x: num(e, 10), y: num(e, 20), h: num(e, 40, 0) });
        if (!paper) word(s, num(e, 10), num(e, 20), num(e, 40, 0), layer); break; }
      case 'DIMENSION': {
        const over = str(e, 1).trim();
        const m = num(e, 42, NaN);
        addText(over && over !== '<>' ? stripMtext(over) : Number.isFinite(m) ? `DIM ${+m.toFixed(3)}` : '');
        break;
      }
      case 'INSERT': case 'MINSERT': {
        const b = blockOf(e);
        if (!b) { anon++; break; }
        placed.push({ name: b, x: num(e, 10), y: num(e, 20), n: copies(e), layer, rot: num(e, 50), paper });
        break;
      }
      case 'LINE': {
        const [x1, y1, z1, x2, y2, z2] = [num(e, 10), num(e, 20), num(e, 30), num(e, 11), num(e, 21), num(e, 31)];
        see(x1, y1, x2, y2);
        bump(lenBy, layer, Math.hypot(x2 - x1, y2 - y1, z2 - z1));
        if (!paper) seg(layer, x1, y1, x2, y2);
        break;
      }
      case 'CIRCLE': see(num(e, 10), num(e, 20)); bump(lenBy, layer, 2 * Math.PI * num(e, 40)); break;
      case 'ARC': {
        let sweep = (num(e, 51) - num(e, 50)) % 360; if (sweep <= 0) sweep += 360;
        see(num(e, 10), num(e, 20));
        bump(lenBy, layer, num(e, 40) * sweep * Math.PI / 180);
        if (!paper) {                                                   // a bend: its chords, one per 15 degrees
          const [cx0, cy0, r0, a0] = [num(e, 10), num(e, 20), num(e, 40), num(e, 50) * Math.PI / 180];
          const k = Math.max(1, Math.ceil(sweep / 15)), d = sweep * Math.PI / 180 / k;
          for (let i = 0; i < k; i++) seg(layer, cx0 + r0 * Math.cos(a0 + i * d), cy0 + r0 * Math.sin(a0 + i * d), cx0 + r0 * Math.cos(a0 + (i + 1) * d), cy0 + r0 * Math.sin(a0 + (i + 1) * d));
        }
        break;
      }
      case 'LWPOLYLINE': {
        const v: { x: number; y: number; b: number }[] = [];
        for (const [c, s] of e.pairs) {
          if (c === 10) v.push({ x: parseFloat(s) || 0, y: 0, b: 0 });
          else if (c === 20 && v.length) v[v.length - 1].y = parseFloat(s) || 0;
          else if (c === 42 && v.length) v[v.length - 1].b = parseFloat(s) || 0;
        }
        for (const p of v) see(p.x, p.y);
        poly = { layer, closed: (num(e, 70) & 1) === 1, v, paper }; endPoly();
        break;
      }
      case 'POLYLINE': {
        const f = num(e, 70);
        // 16 = polygon mesh, 64 = polyface mesh: surfaces, not outlines; skipped.
        poly = f & 80 ? null : { layer, closed: (f & 1) === 1, v: [], paper };
        break;
      }
      case 'VERTEX': if (poly) { const p = { x: num(e, 10), y: num(e, 20), b: num(e, 42) }; see(p.x, p.y); poly.v.push(p); } break;
      case 'SEQEND': endPoly(); break;
    }
  }
  endPoly();

  // LEGEND SAMPLES ARE NOT WORK (24 Sep 2026, sales_engineer; founder instruction 580: "make sure that he's
  // doing the count properly"). A legend draws one of each symbol beside its description, and those are
  // block INSERTs like every device on the plan: counted as they stood, the ZZ DEMO plan's 7 smoke detectors
  // read 8 and its 5 sockets 6. An insert is a legend sample only when ALL of these hold:
  //   * it lies under a LEGEND / KEY / SYMBOLS heading, in a column at most 1.5 m across in real units, and the
  //     column is walked DOWN row by row: the first row within 1.5 m of the heading, each next row within 1.2 m of
  //     the row above, and the walk stops at the first gap wider than that (review of #967: a window of 80 x 40
  //     heading heights was 10 m x 20 m under a 250 mm heading and swallowed five real detectors beside CORRIDOR
  //     tags; the second review: a hard 3 m stop counted the last rows of a 10-row legend at 400 and 600 mm pitch);
  //   * a DESCRIPTION sits beside it on its own row, within 1 m: text that names the block, or reads as a legend
  //     entry ("SD - SMOKE DETECTOR", "SKT = SOCKET"), or is plain words ("TWIN SOCKET OUTLET"), not a room or a
  //     tag; "beside" is measured from the symbol's right edge (its block's extent), so a 900 mm door sample counts;
  //   * it stands in the legend's COLUMN: within 0.3 m of the column's median x.
  // Anything else is counted, and what was set aside is said in the notes, so a surprising count can be checked.
  const legendToM = insunits && UNIT_M[insunits] ? UNIT_M[insunits][0] : extent > 500 ? 0.001 : 1;
  const within = (m: number, h: number, k: number) => Math.min(k * h, m / legendToM);
  const describes = (w: { s: string }, block: string) => w.s.toUpperCase().startsWith(block.toUpperCase()) || /\S\s*[-–=:]\s+\S/.test(w.s)
    || (/^[A-Za-z][A-Za-z/&.]+(?:\s+[A-Za-z0-9/&.x]+)+$/.test(w.s.trim()) && !/\b[A-Z]{0,3}-?\d{2,3}[A-Z]?\b/.test(w.s.trim().split(/\s+/).length >= 3 ? w.s.replace(/\b\d+\s*x\s*\d+\b|\b\d{3,4}\b/g, '') : w.s));
  // A block's width in drawing units (its definition's x extent from its base point), for "beside".
  const widthOf = (name: string) => { let m = 0; for (const c of defs.get(name) ?? []) for (const [k, v] of c.pairs) if (k === 10 || k === 11) m = Math.max(m, parseFloat(v) || 0); return m; };
  const anchors = words.filter((w) => w.h > 0 && LEGEND_HEADING.test(w.s));
  const candidates = new Set<(typeof placed)[number]>();
  for (const a of anchors) {
    // Every described insert below the heading, in the heading's column, top down.
    const rows = placed.filter((p) => p.y <= a.y + a.h && p.x >= a.x - within(0.2, a.h, 3) && p.x - a.x <= within(1.5, a.h, 80)
      && words.some((w) => w !== a && w.s && Math.abs(w.y - p.y) <= 1.5 * a.h && w.x > p.x && w.x - p.x - widthOf(p.name) <= within(1, a.h, 12) && describes(w, p.name)))
      .sort((u, v) => v.y - u.y);
    const inWindow: typeof rows = [];
    let lastY = a.y;
    for (const p of rows) {
      if (lastY - p.y > (inWindow.length ? within(1.2, a.h, 8) : within(1.5, a.h, 10))) break;
      inWindow.push(p); lastY = p.y;
    }
    if (!inWindow.length) continue;
    const xs = inWindow.map((p) => p.x).sort((u, v) => u - v), mid = xs[Math.floor(xs.length / 2)];
    for (const p of inWindow) if (Math.abs(p.x - mid) <= 0.3 / legendToM) candidates.add(p);
  }
  let samples = 0, nestedN = 0;
  for (const p of placed) {
    if (candidates.has(p)) { samples++; continue; }
    if (!p.paper) geo.inserts.push({ name: p.name, x: p.x, y: p.y, n: p.n, layer: p.layer, rot: p.rot, width: widthOf(p.name) });
    inserts.set(p.name, (inserts.get(p.name) ?? 0) + p.n);
    for (const [b, k] of nested(p.name)) { inserts.set(b, (inserts.get(b) ?? 0) + p.n * k); nestedN += p.n * k; }
  }
  if (dyn.size) notes.push(`${dyn.size} dynamic block variant(s) (*U) were counted as the block they are drawn from.`);
  if (nestedN) notes.push(`${nestedN} block insert(s) nested inside other blocks were counted once per placement of their parent.`);
  if (samples) notes.push(`${samples} block insert(s) drawn as legend samples beside their descriptions were not counted.`);

  // Units.
  let toM = 1, unitName = 'm', confidence: Qty['confidence'] = 'medium';
  if (insunits && UNIT_M[insunits]) [toM, unitName] = UNIT_M[insunits];
  else {
    confidence = 'low';
    // A building drawn in metres rarely has a coordinate past 500; one drawn in mm nearly always does.
    if (extent > 500) { toM = 0.001; unitName = 'mm'; notes.push(`The drawing states no unit ($INSUNITS ${insunits ?? 'absent'}); coordinates reach ${Math.round(extent)}, so millimetres were assumed. Check every length and area.`); }
    else notes.push(`The drawing states no unit ($INSUNITS ${insunits ?? 'absent'}); metres were assumed. Check every length and area.`);
  }
  const unitBasis = insunits && UNIT_M[insunits] ? `$INSUNITS=${insunits} (${unitName})` : `unit assumed ${unitName}`;

  const quantities: Qty[] = [];
  for (const [b, n] of [...inserts].sort((a, z) => z[1] - a[1])) {
    quantities.push({ section: 'Blocks', description: `block ${b}`, qty: n, unit: 'nos', basis: `block ${b} inserted ${n} times`, confidence: 'medium' });
  }
  for (const [l, a] of [...areaBy].sort()) {
    if (a.v <= 0) continue;
    quantities.push({ section: `layer ${l}`, description: `closed outlines on layer ${l}`, qty: +(a.v * toM * toM).toFixed(2), unit: 'sqm', basis: `layer ${l}, ${a.n} closed polylines, ${unitBasis}`, confidence });
  }
  for (const [l, a] of [...lenBy].sort()) {
    if (a.v <= 0) continue;
    quantities.push({ section: `layer ${l}`, description: `linework on layer ${l}`, qty: +(a.v * toM).toFixed(2), unit: 'm', basis: `layer ${l}, ${a.n} lines/arcs/polylines, ${unitBasis}`, confidence });
  }
  if (quantities.length > LIMITS.maxQuantities) {
    notes.push(`${quantities.length} quantities found; the first ${LIMITS.maxQuantities} are kept.`);
    quantities.length = LIMITS.maxQuantities;
  }
  if (anon) notes.push(`${anon} anonymous block inserts (dimensions, hatches, dynamic blocks) were not counted.`);
  if (capped) notes.push(`The drawing has more than ${maxEntities} entities; reading stopped there, so totals are partial.`);
  notes.push('Lengths are per layer as drawn; block contents are not exploded and viewport scales are not applied.');
  // dxf_text: the ASCII DXF this take-off came from (the file, a converted binary DXF, or a DWG's entities
  // written by dwg.ts), for cad_identity's identity scan by the caller. Every CAD reader passes through here.
  geo.toM = toM; geo.unitName = unitName; geo.unitStated = !!(insunits && UNIT_M[insunits]);
  if (capped) geo.capped = true;
  return ok({ ...empty('dxf', notes), text: text.join('').trimEnd(), quantities, dxf_text: src, cad: geo });
}

// ---------------------------------------------------------------------------------------------------
// REDACTION (14 Sep 2026). Founder rule: nothing identifying the customer may reach a supplier in any
// drawing format, and it fails closed. redactDxf builds the DERIVED ASCII DXF a supplier may see:
//   - every free-text value goes through `redact`: codes 1 and 3 (TEXT, MTEXT, ATTRIB, ATTDEF,
//     DIMENSION override, XRECORD/DICTIONARY strings), 300-309, 999 comments, 1000/1001 extended data;
//   - MTEXT is joined across its 250-character code-3 chunks and stripped of formatting BEFORE `redact`
//     sees it, because "{\fArial;Ahmed Al} Mansoori" split over a chunk or a font code would slip past
//     any name matcher. The redacted text goes back in code 1 with \P line breaks; formatting is lost;
//   - layer names (code 8 everywhere, code 2 of LAYER table records) go through `redact`, so an entity
//     stays on its renamed layer and the geometry is untouched;
//   - HEADER $PROJECTNAME, $LASTSAVEDBY, $HYPERLINKBASE, $FINGERPRINTGUID, $VERSIONGUID, $MENU,
//     $STYLESHEET are blanked ($DWGCODEPAGE is kept: without it the text cannot be decoded);
//   - an external-reference BLOCK (flag 70 bit 4) has its path (code 1) blanked.
// residualCheck is every string value left in the output, one per line, for the caller's residual
// scan. A binary or unparseable DXF throws: it cannot be redacted, so it must not be passed on.
const HEADER_BLANK = new Set(['$PROJECTNAME', '$LASTSAVEDBY', '$HYPERLINKBASE', '$FINGERPRINTGUID', '$VERSIONGUID', '$MENU', '$STYLESHEET']);
const isStringCode = (c: number) => (c >= 1 && c <= 9) || (c >= 300 && c <= 309) || (c >= 410 && c <= 419) ||
  (c >= 430 && c <= 439) || (c >= 470 && c <= 479) || c === 999 || (c >= 1000 && c <= 1009);
const isFreeText = (c: number) => c === 1 || c === 3 || (c >= 300 && c <= 309) || c === 999 || c === 1000 || c === 1001;

export function redactDxf(bytes: Uint8Array, redact: (s: string) => string): { bytes: Uint8Array; changed: number; residualCheck: string } {
  // A binary DXF is converted to ASCII first (22 Sep 2026), so the supplier's copy is the redacted ASCII
  // DXF. A binary file the converter cannot follow throws here, and so is never passed on.
  const src = new TextDecoder('latin1').decode(bytes.subarray(0, 22)).startsWith('AutoCAD Binary DXF')
    ? binaryDxfToAscii(bytes).dxf
    : new TextDecoder('utf-8').decode(bytes);
  const eol = src.includes('\r\n') ? '\r\n' : '\n';
  const lines = src.split(/\r?\n/);
  if (!src.slice(0, 2000).includes('SECTION')) throw new Error('dxf_unreadable: not an ASCII DXF');
  let section = '', pendingSection = false, ent = '', headerVar = '', xref = false, changed = 0;
  let chunks: number[] = [];                      // line indexes of the current MTEXT's code-3 chunks
  const set = (idx: number, v: string) => { if (lines[idx] !== v) { lines[idx] = v; changed++; } };
  for (let i = 0; i + 1 < lines.length; i += 2) {
    const code = parseInt(lines[i].trim(), 10);
    if (!Number.isFinite(code)) throw new Error(`dxf_unreadable: group code expected at line ${i + 1}`);
    const val = lines[i + 1];
    if (code === 0) {
      ent = val.trim(); xref = false; chunks = [];
      if (ent === 'SECTION') pendingSection = true; else if (ent === 'ENDSEC') section = '';
      continue;
    }
    if (pendingSection && code === 2) { section = val.trim(); pendingSection = false; continue; }
    if (section === 'HEADER') {
      if (code === 9) headerVar = val.trim();
      else if (HEADER_BLANK.has(headerVar) && isStringCode(code)) set(i + 1, '');
      continue;
    }
    if (ent === 'BLOCK' && code === 70) xref = (parseInt(val.trim(), 10) & 4) === 4;
    if (ent === 'MTEXT' && code === 3) { chunks.push(i + 1); continue; }
    if (ent === 'MTEXT' && code === 1) {
      const full = chunks.map((k) => lines[k]).join('') + val;
      for (const k of chunks) set(k, '');
      chunks = [];
      set(i + 1, redact(stripMtext(full)).replace(/\r?\n/g, '\\P'));
    } else if (ent === 'BLOCK' && code === 1 && xref) set(i + 1, '');
    else if (code === 8 || (section === 'TABLES' && ent === 'LAYER' && code === 2) || isFreeText(code)
      // DWGPROPS and other XRECORDs keep title / author / comments in codes 2-9 (measured: author and job no. survived)
      || (ent === 'XRECORD' && isStringCode(code))) set(i + 1, redact(val));
  }
  const residual: string[] = [];
  for (let i = 0; i + 1 < lines.length; i += 2) {
    const c = parseInt(lines[i].trim(), 10);
    if (isStringCode(c) && lines[i + 1].trim()) residual.push(lines[i + 1].trim());
  }
  return { bytes: new TextEncoder().encode(lines.join(eol)), changed, residualCheck: residual.join('\n') };
}
