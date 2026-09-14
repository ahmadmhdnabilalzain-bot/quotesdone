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
// WHAT IT NEVER DOES. It does not read binary DXF or DWG (needs 'cad_conversion'), explode blocks,
// apply viewport scales, or guess what a layer means. Without $INSUNITS the unit is a guess and
// every quantity says so at confidence 'low'. Identity is NOT scrubbed here; the caller does that.
import { capText, empty, LIMITS, ok, refuse, type Qty, type ReadContext, type ReadResult } from './types.ts';

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

export async function readDxf(bytes: Uint8Array, _ctx: ReadContext, maxEntities = DXF_MAX_ENTITIES): Promise<ReadResult> {
  const head = new TextDecoder('latin1').decode(bytes.subarray(0, 22));
  if (head.startsWith('AutoCAD Binary DXF')) {
    return ok(empty('dxf', ['Binary DXF: it has to be converted to ASCII DXF or PDF before its content can be read.'], 'cad_conversion'));
  }
  const src = new TextDecoder('utf-8').decode(bytes);
  const lines = src.split(/\r?\n/);
  if (!/^\s*0\s*$/.test(lines[0] ?? '') && !src.slice(0, 2000).includes('SECTION')) {
    return refuse('dxf_unreadable', 'Not an ASCII DXF file (no group-code/value pairs).');
  }

  // Walk pairs, tracking section; collect HEADER $INSUNITS and ENTITIES entities.
  let insunits: number | null = null, section = '', pendingSection = false, lastHeaderVar = '';
  const ents: Ent[] = [];
  let cur: Ent | null = null, capped = false;
  for (let i = 0; i + 1 < lines.length; i += 2) {
    const code = parseInt(lines[i].trim(), 10);
    const val = lines[i + 1].replace(/\s+$/, '');
    if (!Number.isFinite(code)) return refuse('dxf_unreadable', `Group code expected at line ${i + 1}.`);
    if (code === 0) {
      if (cur) { ents.push(cur); cur = null; }
      const t = val.trim();
      if (t === 'SECTION') { pendingSection = true; continue; }
      if (t === 'ENDSEC') { section = ''; continue; }
      if (t === 'EOF') break;
      if (section === 'ENTITIES') {
        if (ents.length >= maxEntities) { capped = true; break; }
        cur = { type: t, pairs: [] };
      }
      continue;
    }
    if (pendingSection && code === 2) { section = val.trim(); pendingSection = false; continue; }
    if (section === 'HEADER') {
      if (code === 9) lastHeaderVar = val.trim();
      else if (lastHeaderVar === '$INSUNITS' && code === 70) insunits = parseInt(val.trim(), 10);
    } else if (cur) cur.pairs.push([code, val]);
  }
  if (cur) ents.push(cur);

  const notes: string[] = [];
  const text: string[] = [];
  const used = { n: 0 };
  const addText = (s: string) => { for (const l of s.split('\n')) { const t = l.trim(); if (t) capText(text, t + '\n', used); } };

  // Pass 1: raw measures in drawing units.
  const lenBy = new Map<string, { v: number; n: number }>();
  const areaBy = new Map<string, { v: number; n: number }>();
  const inserts = new Map<string, number>();
  let anon = 0, extent = 0;
  const bump = (m: Map<string, { v: number; n: number }>, k: string, v: number) => {
    const e = m.get(k) ?? { v: 0, n: 0 }; e.v += v; e.n++; m.set(k, e);
  };
  const num = (e: Ent, c: number, d = 0) => { const p = e.pairs.find((x) => x[0] === c); return p ? parseFloat(p[1]) || 0 : d; };
  const str = (e: Ent, c: number) => e.pairs.find((x) => x[0] === c)?.[1] ?? '';
  const see = (...xs: number[]) => { for (const x of xs) extent = Math.max(extent, Math.abs(x)); };
  let poly: { layer: string; closed: boolean; v: { x: number; y: number; b: number }[] } | null = null;
  const endPoly = () => {
    if (!poly) return;
    const m = polyMeasure(poly.v, poly.closed);
    bump(lenBy, poly.layer, m.len);
    if (poly.closed) bump(areaBy, poly.layer, m.area);
    poly = null;
  };

  for (const e of ents) {
    const layer = str(e, 8).trim() || '0';
    if (e.type !== 'VERTEX' && e.type !== 'SEQEND') endPoly();
    switch (e.type) {
      case 'TEXT': case 'ATTRIB': addText(stripMtext(str(e, 1))); break;
      case 'MTEXT': addText(stripMtext(e.pairs.filter((p) => p[0] === 3).map((p) => p[1]).join('') + str(e, 1))); break;
      case 'DIMENSION': {
        const over = str(e, 1).trim();
        const m = num(e, 42, NaN);
        addText(over && over !== '<>' ? stripMtext(over) : Number.isFinite(m) ? `DIM ${+m.toFixed(3)}` : '');
        break;
      }
      case 'INSERT': {
        const b = str(e, 2).trim();
        if (!b || b.startsWith('*')) { anon++; break; }
        inserts.set(b, (inserts.get(b) ?? 0) + 1);
        break;
      }
      case 'LINE': {
        const [x1, y1, z1, x2, y2, z2] = [num(e, 10), num(e, 20), num(e, 30), num(e, 11), num(e, 21), num(e, 31)];
        see(x1, y1, x2, y2);
        bump(lenBy, layer, Math.hypot(x2 - x1, y2 - y1, z2 - z1));
        break;
      }
      case 'CIRCLE': see(num(e, 10), num(e, 20)); bump(lenBy, layer, 2 * Math.PI * num(e, 40)); break;
      case 'ARC': {
        let sweep = (num(e, 51) - num(e, 50)) % 360; if (sweep <= 0) sweep += 360;
        see(num(e, 10), num(e, 20));
        bump(lenBy, layer, num(e, 40) * sweep * Math.PI / 180);
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
        poly = { layer, closed: (num(e, 70) & 1) === 1, v }; endPoly();
        break;
      }
      case 'POLYLINE': {
        const f = num(e, 70);
        // 16 = polygon mesh, 64 = polyface mesh: surfaces, not outlines; skipped.
        poly = f & 80 ? null : { layer, closed: (f & 1) === 1, v: [] };
        break;
      }
      case 'VERTEX': if (poly) { const p = { x: num(e, 10), y: num(e, 20), b: num(e, 42) }; see(p.x, p.y); poly.v.push(p); } break;
      case 'SEQEND': endPoly(); break;
    }
  }
  endPoly();

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
  return ok({ ...empty('dxf', notes), text: text.join('').trimEnd(), quantities });
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
  if (new TextDecoder('latin1').decode(bytes.subarray(0, 22)).startsWith('AutoCAD Binary DXF')) {
    throw new Error('dxf_binary: a binary DXF cannot be redacted; it must not be passed on');
  }
  const src = new TextDecoder('utf-8').decode(bytes);
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
    else if (code === 8 || (section === 'TABLES' && ent === 'LAYER' && code === 2) || isFreeText(code)) set(i + 1, redact(val));
  }
  const residual: string[] = [];
  for (let i = 0; i + 1 < lines.length; i += 2) {
    const c = parseInt(lines[i].trim(), 10);
    if (isStringCode(c) && lines[i + 1].trim()) residual.push(lines[i + 1].trim());
  }
  return { bytes: new TextEncoder().encode(lines.join(eol)), changed, residualCheck: residual.join('\n') };
}
