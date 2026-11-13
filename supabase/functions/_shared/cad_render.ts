// cad_render — a customer's CAD drawing (DXF, binary DXF, or a DWG's entities) drawn as the page a
// supplier may see, with the project's identity LEFT OUT of the drawing rather than painted over it
// (24 Sep 2026, sales_engineer). Founder instructions 32, 580, 703: "no details at all" may reach a
// supplier, "without affecting" the drawing.
//
// MEASURED BEFORE THIS FILE (production, read-only, 24 Sep 2026): drawing_redaction_runs held 6 rows and
// not one had reached 'complete'. A CAD upload was never shown to a supplier: analyze_drawing sent it to
// cad_convert (a paid CloudConvert raster that reads nothing), the raster has no text layer, the server
// could not box its title block, and the model that would have looked is held. So every DXF and DWG a
// customer sent went out as a take-off only, with "the drawing is held" beside it.
//
// WHY DRAW IT RATHER THAN MASK IT. A CAD file is not a picture of the drawing: it IS the drawing, as
// entities with layers, blocks and text we can read. A pixel mask over a picture has to FIND the identity
// first; here the identity is a TEXT entity, an ATTRIB of a title-block INSERT, a layer called TITLE, a
// paper-space layout or a header variable, and each of those is decided by code before anything is drawn:
//   * paper space (code 67 = 1), where title blocks and sheet frames live, is not drawn at all;
//   * a title-block / logo / stamp / revision INSERT or layer (cad_identity.FRAME_NAME) is drawn as ONE
//     solid black box over its extent: the supplier sees that something was removed, and where;
//   * a border / frame / viewport INSERT keeps its lines and loses every word in it;
//   * every other TEXT, MTEXT, ATTRIB and dimension text is drawn ONLY if it reads as drawing content
//     (drawing_text_policy.isDrawingContent: numbers, codes from a closed list, the trade's vocabulary) and
//     names no seed - the file's own identity terms (cad_identity.cadIdentityTerms) and the customer's -
//     alone, joined with the runs along its baseline, or joined with the line stacked above or below it.
//     A label ("CLIENT:", "Drawn by") takes the words beside it and under it with it. A text that fails
//     is not drawn, and a black box marks where it stood. FAIL CLOSED (second review of #967): a sheet
//     written one glyph per TEXT is held as glyph_per_text rather than reassembled;
//   * embedded raster images (IMAGE, OLE: logos, scanned stamps) are never reproduced;
//   * header variables, xref paths, layer names and block names are never drawn by anything here.
// What IS drawn: every line, arc, circle, polyline, ellipse, spline (through its fit or control points),
// solid outline, leader, dimension (its own block), table, block INSERT (exploded, nested, arrays), and
// every word that passed: room names, dimensions, tags, notes, schedule cells, legends.
//
// THE PAGE IS PROVED, NOT TRUSTED. drawn_texts is every string that was put on the page; the caller (and
// cad_render.test.ts) re-scans it for identity. withheld counts what was left out. A drawing too dense
// for the edge's CPU (maxSegments) is not half-drawn: the answer is ok:false, the page is held.
//
// WHAT IT DOES NOT DO: draw fills (HATCH patterns and gradient fills are counted and skipped, their
// boundaries are not drawn), apply line types / weights / colours (everything is one ink), lay out MTEXT
// columns or word-wrap, or letter non-Latin text (stroke_font.ts draws such characters as boxes and counts
// them). Those are said in `notes`, which become what the customer is told.
import { binaryDxfToAscii, stripMtext } from './doc_read/cad.ts';
import { cadIdentityTerms, FRAME, tokens } from './cad_identity.ts';
import { isDrawingContent, namesParty, partyLabel, partyTag, seedHit } from './drawing_text_policy.ts';
import { residualScan, seedTerms } from './anonymise.ts';
import { textStrokes } from './stroke_font.ts';

type Pair = [number, string];
type Ent = { type: string; p: Pair[]; attribs: Ent[]; verts: Ent[] };
type Block = { name: string; bx: number; by: number; ents: Ent[]; flags: number };
type M = [number, number, number, number, number, number]; // x' = a x + c y + e, y' = b x + d y + f
type BBox = { x0: number; y0: number; x1: number; y1: number };

/** The page a supplier sees: the long edge in pixels. drawing_redact keeps portal pages at the same 2600. */
export const RENDER_LONG_EDGE = 2600;
/** Past this many drawn segments the edge would run out of CPU; the page is held, never half-drawn, and customer_api
 *  queues the drawing for the CAD worker (which draws with a 5,000,000 budget). Review of #967, measured on the edge:
 *  ~1.35 s of CPU at 150k segments and 3.1 s at 390k before the JPEG, against a 2 s cap - so 120k, not 400k. */
export const RENDER_MAX_SEGMENTS = 120_000;
/** Block nesting and exploded-entity ceilings (a block that inserts itself must not loop). */
const MAX_DEPTH = 8, MAX_EXPANDED = 250_000;
/** A title region larger than this share of the sheet is not blacked out (it would take the drawing
 *  with it); its words are withheld and its lines drawn - the same 0.35 as anonymise.MAX_STRIP. */
export const MAX_TITLE_SHARE = 0.35;
const INK = [32, 32, 32] as const;
/** A sheet with more single-character TEXTs than this, or with more than GLYPH_SHARE of its texts single characters
 *  (and at least 4), is HELD as glyph_per_text: a PDF converted to DWG writes every glyph as its own TEXT, and a
 *  name split that way defeats any reassembly (second review of #967: "CLIENT: ZZ OMEGA", "TEL 04 123 4567" and the
 *  customer's name, rotated, stacked or spaced three heights apart, were all drawn). A structural grid's A-H and
 *  1-12 bubbles are 20. */
export const GLYPH_MAX = 20, GLYPH_SHARE = 0.3;

const TITLE_TOK = /^(?:TITLE|TITLES|TITLEBLOCK|TITLEBLK|TTLB|TTL|TB|TBLK|LOGO|LOGOS|STAMP|SEAL|REVISION|REVISIONS|REVS|XREF|XREFS)$/i;
/** 'title': drawn as one black box. 'border': lines kept, words withheld. null: ordinary content. */
export function frameKind(name: string): 'title' | 'border' | null {
  const t = tokens(name);
  if (t.some((x) => TITLE_TOK.test(x)) || /title\s*block|titleblock/i.test(name)) return 'title';
  if (t.some((x) => FRAME.test(x)) || /sheet\s*frame/i.test(name)) return 'border';
  return null;
}

// ── parsing ────────────────────────────────────────────────────────────────────────────────────────
function asciiOf(bytesOrText: Uint8Array | string): string {
  if (typeof bytesOrText === 'string') return bytesOrText;
  const head = new TextDecoder('latin1').decode(bytesOrText.subarray(0, 22));
  if (head.startsWith('AutoCAD Binary DXF')) return binaryDxfToAscii(bytesOrText).dxf;
  return new TextDecoder('utf-8').decode(bytesOrText);
}

export type ParsedDxf = { ents: Ent[]; blocks: Map<string, Block> };
export function parseDxf(src: string): ParsedDxf {
  const lines = src.split(/\r?\n/);
  const ents: Ent[] = [];
  const blocks = new Map<string, Block>();
  let section = '', pending = false;
  let cur: Ent | null = null;
  let block: Block | null = null;
  let inBlockHeader = false;
  let lastInsert: Ent | null = null, lastPoly: Ent | null = null;
  const target = () => (section === 'BLOCKS' ? block?.ents : section === 'ENTITIES' ? ents : null);
  const close = () => {
    if (!cur) return;
    const list = target();
    if (list) {
      if (cur.type === 'ATTRIB' && lastInsert) lastInsert.attribs.push(cur);
      else if (cur.type === 'VERTEX' && lastPoly) lastPoly.verts.push(cur);
      else if (cur.type === 'SEQEND') { lastInsert = null; lastPoly = null; }
      else {
        list.push(cur);
        lastInsert = cur.type === 'INSERT' ? cur : null;
        lastPoly = cur.type === 'POLYLINE' ? cur : null;
      }
    }
    cur = null;
  };
  for (let i = 0; i + 1 < lines.length; i += 2) {
    const code = parseInt(lines[i].trim(), 10);
    if (!Number.isFinite(code)) throw new Error(`dxf_unreadable: group code expected at line ${i + 1}`);
    const val = lines[i + 1].replace(/\s+$/, '');
    if (code === 0) {
      close();
      const t = val.trim();
      if (t === 'SECTION') { pending = true; continue; }
      if (t === 'ENDSEC') { section = ''; block = null; continue; }
      if (t === 'EOF') break;
      if (section === 'BLOCKS' && t === 'BLOCK') { block = { name: '', bx: 0, by: 0, ents: [], flags: 0 }; inBlockHeader = true; continue; }
      if (section === 'BLOCKS' && t === 'ENDBLK') { if (block?.name) blocks.set(block.name, block); block = null; inBlockHeader = false; continue; }
      inBlockHeader = false;
      if ((section === 'ENTITIES') || (section === 'BLOCKS' && block)) cur = { type: t, p: [], attribs: [], verts: [] };
      continue;
    }
    if (pending && code === 2) { section = val.trim(); pending = false; continue; }
    if (inBlockHeader && block) {
      if (code === 2) block.name = val.trim();
      else if (code === 10) block.bx = parseFloat(val) || 0;
      else if (code === 20) block.by = parseFloat(val) || 0;
      else if (code === 70) block.flags = parseInt(val, 10) || 0;
      continue;
    }
    if (cur) cur.p.push([code, val]);
  }
  close();
  return { ents, blocks };
}

const num = (e: Ent, c: number, d = 0) => { const p = e.p.find((x) => x[0] === c); if (!p) return d; const v = parseFloat(p[1]); return Number.isFinite(v) ? v : d; };
const has = (e: Ent, c: number) => e.p.some((x) => x[0] === c);
const str = (e: Ent, c: number) => e.p.find((x) => x[0] === c)?.[1] ?? '';
const all = (e: Ent, c: number) => e.p.filter((x) => x[0] === c).map((x) => parseFloat(x[1]) || 0);

// ── geometry ───────────────────────────────────────────────────────────────────────────────────────
const mul = (m: M, n: M): M => [m[0] * n[0] + m[2] * n[1], m[1] * n[0] + m[3] * n[1], m[0] * n[2] + m[2] * n[3], m[1] * n[2] + m[3] * n[3], m[0] * n[4] + m[2] * n[5] + m[4], m[1] * n[4] + m[3] * n[5] + m[5]];
const tr = (x: number, y: number): M => [1, 0, 0, 1, x, y];
const rot = (deg: number): M => { const r = deg * Math.PI / 180, c = Math.cos(r), s = Math.sin(r); return [c, s, -s, c, 0, 0]; };
const scl = (sx: number, sy: number): M => [sx, 0, 0, sy, 0, 0];
const ID: M = [1, 0, 0, 1, 0, 0];
const ap = (m: M, x: number, y: number): [number, number] => [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]];
/** An entity whose extrusion is (0,0,-1) is drawn mirrored in X (the common mirrored-arc case). */
const ocs = (e: Ent): M => (num(e, 230, 1) < 0 ? [-1, 0, 0, 1, 0, 0] : ID);

function arcPts(cx: number, cy: number, r: number, a0: number, a1: number): number[] {
  let sweep = a1 - a0; while (sweep <= 0) sweep += 360; if (sweep > 360) sweep = 360;
  const n = Math.max(4, Math.ceil(sweep / 4));
  const out: number[] = [];
  for (let i = 0; i <= n; i++) { const t = (a0 + sweep * i / n) * Math.PI / 180; out.push(cx + r * Math.cos(t), cy + r * Math.sin(t)); }
  return out;
}
function bulgePts(x1: number, y1: number, x2: number, y2: number, b: number): number[] {
  const c = Math.hypot(x2 - x1, y2 - y1);
  if (!b || !c) return [x2, y2];
  const th = 4 * Math.atan(b);
  const r = c / (2 * Math.sin(Math.abs(th) / 2));
  const mx = (x1 + x2) / 2, my = (y1 + y2) / 2;
  const d = Math.sqrt(Math.max(0, r * r - (c / 2) ** 2)) * (Math.abs(th) > Math.PI ? -1 : 1) * Math.sign(b);
  const cx = mx - d * (y2 - y1) / c, cy = my + d * (x2 - x1) / c;
  const a0 = Math.atan2(y1 - cy, x1 - cx), n = Math.max(2, Math.ceil(Math.abs(th) * 180 / Math.PI / 6));
  const out: number[] = [];
  for (let i = 1; i <= n; i++) { const t = a0 + th * i / n; out.push(cx + r * Math.cos(t), cy + r * Math.sin(t)); }
  return out;
}

// ── the model: what would be drawn, before anything is ─────────────────────────────────────────────
type TextItem = { s: string; m: M; w: number; unknown: number; strokes: [number, number][][]; box: BBox; frame: boolean; tag: string; label: boolean; h: number; x: number; y: number; rotDeg: number };
type Region = { box: BBox; parts: number[][]; texts: TextItem[] };
type Ctx = { m: M; layer: string; depth: number; frame: 'border' | null; title: Region | null };

export type CadRenderResult =
  | { ok: true; rgba: Uint8ClampedArray; width: number; height: number; drawn_texts: string[]; withheld: { texts: number; regions: number; samples_redacted: number }; counts: Record<string, number>; notes: string[]; regions_px: { kind: 'title' | 'text'; x: number; y: number; w: number; h: number }[] }
  | { ok: false; reason: 'unreadable' | 'empty' | 'too_dense' | 'residual' | 'title_unbounded' | 'glyph_per_text'; detail: string };

const bboxOf = (pts: number[]): BBox => { let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity; for (let i = 0; i + 1 < pts.length; i += 2) { x0 = Math.min(x0, pts[i]); x1 = Math.max(x1, pts[i]); y0 = Math.min(y0, pts[i + 1]); y1 = Math.max(y1, pts[i + 1]); } return { x0, y0, x1, y1 }; };
const grow = (a: BBox, b: BBox): BBox => ({ x0: Math.min(a.x0, b.x0), y0: Math.min(a.y0, b.y0), x1: Math.max(a.x1, b.x1), y1: Math.max(a.y1, b.y1) });
const EMPTY: BBox = { x0: Infinity, y0: Infinity, x1: -Infinity, y1: -Infinity };
const finite = (b: BBox) => Number.isFinite(b.x0) && Number.isFinite(b.x1) && Number.isFinite(b.y0) && Number.isFinite(b.y1);

/**
 * Draw a CAD drawing for a supplier. `input` is DXF bytes (ASCII or binary) or ASCII DXF text (a DWG's
 * entities as dwg.ts writes them). `seeds` are the customer's own terms (anonymise.seedTerms).
 */
export function renderCadForSupplierSync(input: Uint8Array | string, opts: { seeds?: string[]; longEdge?: number; maxSegments?: number; textsOnly?: boolean; identity?: Set<string> } = {}): CadRenderResult {
  let src: string;
  let parsed: ParsedDxf;
  try { src = asciiOf(input); if (!src.slice(0, 4000).includes('SECTION')) return { ok: false, reason: 'unreadable', detail: 'not a DXF' }; parsed = parseDxf(src); }
  catch (e) { return { ok: false, reason: 'unreadable', detail: String((e as Error)?.message || e).slice(0, 160) }; }
  const seeds = [...new Set([...(opts.seeds ?? []), ...seedTerms({ extra: cadIdentityTerms(src) })])];
  const counts: Record<string, number> = { entities: 0, paper_space_skipped: 0, hatch_skipped: 0, images_skipped: 0, other_skipped: 0, unknown_glyphs: 0, inserts: 0, segments: 0 };
  const ink: number[][] = [];
  const texts: TextItem[] = [];
  const titleRegions: Region[] = [];
  // One region per title-block LAYER (every entity on it together), one per title-block INSERT.
  const layerRegions = new Map<string, Region>();
  const newRegion = (): Region => { const r: Region = { box: EMPTY, parts: [], texts: [] }; titleRegions.push(r); return r; };
  let expanded = 0;
  // A DIMENSION with no block of its own carries no text height (that lives in its DIMSTYLE); it is drawn
  // at the drawing's median text height, not a hard-coded 2.5 that is a dot on a sheet drawn in mm.
  const hs = parsed.ents.filter((e) => e.type === 'TEXT' || e.type === 'MTEXT').map((e) => num(e, 40, 0)).filter((h) => h > 0).sort((a, b) => a - b);
  const dimH = hs.length ? hs[Math.floor(hs.length / 2)] : 2.5;

  const addText = (s: string, m: M, x: number, y: number, h: number, rotDeg: number, wf: number, hAlign: number, vAlign: number, ctx: Ctx, tag = '') => {
    const clean = s.replace(/\s+$/, '');
    if (!clean.trim() || !(h > 0)) return;
    const ts = textStrokes(clean, wf > 0 ? wf : 1);
    const dx = -ts.width * (hAlign === 1 || hAlign === 4 ? 0.5 : hAlign === 2 ? 1 : 0);
    const dy = -(vAlign === 2 ? 0.5 : vAlign === 3 ? 1 : 0);
    const tm = mul(ctx.m, mul(m, mul(tr(x, y), mul(rot(rotDeg), mul(scl(h, h), tr(dx, dy))))));
    const strokes = ts.strokes.map((st) => st.map(([u, v]) => ap(tm, u, v)));
    const corners = [ap(tm, 0, -0.3), ap(tm, ts.width, -0.3), ap(tm, ts.width, 1.1), ap(tm, 0, 1.1)].flat();
    const item: TextItem = { s: clean, m: tm, w: ts.width, unknown: ts.unknown, strokes, box: bboxOf(corners), frame: !!ctx.frame, tag, label: partyLabel(clean), h: Math.hypot(tm[2], tm[3]), x: ap(tm, 0, 0)[0], y: ap(tm, 0, 0)[1], rotDeg };
    if (ctx.title) { ctx.title.box = grow(ctx.title.box, item.box); ctx.title.texts.push(item); return; }
    texts.push(item);
  };
  const addPoly = (pts: number[], m: M, ctx: Ctx) => {
    if (pts.length < 4) return;
    const out: number[] = [];
    for (let i = 0; i + 1 < pts.length; i += 2) out.push(...ap(ctx.m, ...ap(m, pts[i], pts[i + 1])));
    if (ctx.title) { ctx.title.box = grow(ctx.title.box, bboxOf(out)); ctx.title.parts.push(out); return; }
    ink.push(out);
  };

  const drawEnt = (e: Ent, ctx: Ctx, blocks: Map<string, Block>) => {
    if (++expanded > MAX_EXPANDED) return;
    counts.entities++;
    if (ctx.depth === 0 && str(e, 67).trim() === '1') { counts.paper_space_skipped++; return; }
    const layerRaw = str(e, 8).trim() || '0';
    const layer = layerRaw === '0' ? ctx.layer : layerRaw;
    const o = ocs(e);
    const layerKind = frameKind(layer);
    // A title-block LAYER collects into its own region, exactly like a title-block INSERT.
    if (layerKind === 'title' && !ctx.title) {
      let region = layerRegions.get(layer);
      if (!region) { region = newRegion(); layerRegions.set(layer, region); }
      drawEnt1(e, { ...ctx, layer, title: region }, blocks, o, layer);
      return;
    }
    const c2: Ctx = layerKind === 'border' && !ctx.frame ? { ...ctx, layer, frame: 'border' } : { ...ctx, layer };
    drawEnt1(e, c2, blocks, o, layer);
  };

  const drawEnt1 = (e: Ent, ctx: Ctx, blocks: Map<string, Block>, o: M, layer: string) => {
    switch (e.type) {
      case 'LINE': addPoly([num(e, 10), num(e, 20), num(e, 11), num(e, 21)], ID, ctx); break;
      case 'CIRCLE': addPoly(arcPts(num(e, 10), num(e, 20), num(e, 40), 0, 360), o, ctx); break;
      case 'ARC': addPoly(arcPts(num(e, 10), num(e, 20), num(e, 40), num(e, 50), num(e, 51)), o, ctx); break;
      case 'ELLIPSE': {
        const cx = num(e, 10), cy = num(e, 20), mx = num(e, 11), my = num(e, 21), r = num(e, 40, 1);
        let t0 = num(e, 41, 0), t1 = num(e, 42, Math.PI * 2); while (t1 <= t0) t1 += Math.PI * 2;
        const n = Math.max(8, Math.ceil((t1 - t0) * 180 / Math.PI / 4)), pts: number[] = [];
        for (let i = 0; i <= n; i++) { const t = t0 + (t1 - t0) * i / n; pts.push(cx + mx * Math.cos(t) - r * my * Math.sin(t), cy + my * Math.cos(t) + r * mx * Math.sin(t)); }
        addPoly(pts, o, ctx); break;
      }
      case 'LWPOLYLINE': {
        const v: { x: number; y: number; b: number }[] = [];
        for (const [c, s] of e.p) {
          if (c === 10) v.push({ x: parseFloat(s) || 0, y: 0, b: 0 });
          else if (c === 20 && v.length) v[v.length - 1].y = parseFloat(s) || 0;
          else if (c === 42 && v.length) v[v.length - 1].b = parseFloat(s) || 0;
        }
        polyOf(v, (num(e, 70) & 1) === 1, o, ctx); break;
      }
      case 'POLYLINE': {
        if (num(e, 70) & 80) { counts.other_skipped++; break; }   // polygon / polyface meshes are surfaces
        polyOf(e.verts.map((x) => ({ x: num(x, 10), y: num(x, 20), b: num(x, 42) })), (num(e, 70) & 1) === 1, o, ctx); break;
      }
      case 'SPLINE': {
        const fx = all(e, 11), fy = all(e, 21), cx = all(e, 10), cy = all(e, 20);
        const [xs, ys] = fx.length >= 2 ? [fx, fy] : [cx, cy];
        const pts: number[] = []; for (let i = 0; i < Math.min(xs.length, ys.length); i++) pts.push(xs[i], ys[i]);
        addPoly(pts, ID, ctx); break;
      }
      case 'SOLID': case 'TRACE': case '3DFACE': {
        const q = [num(e, 10), num(e, 20), num(e, 11), num(e, 21), num(e, 13), num(e, 23), num(e, 12), num(e, 22)];
        if (e.type === '3DFACE') [q[4], q[5], q[6], q[7]] = [num(e, 12), num(e, 22), num(e, 13), num(e, 23)];
        addPoly([...q, q[0], q[1]], e.type === '3DFACE' ? ID : o, ctx); break;
      }
      case 'LEADER': { const xs = all(e, 10), ys = all(e, 20); const pts: number[] = []; for (let i = 0; i < Math.min(xs.length, ys.length); i++) pts.push(xs[i], ys[i]); addPoly(pts, ID, ctx); break; }
      case 'TEXT': case 'ATTRIB': {
        if (e.type === 'ATTRIB' && (num(e, 70) & 1)) break;           // an invisible attribute is not drawn by CAD either
        const hA = num(e, 72), vA = e.type === 'ATTRIB' ? num(e, 74) : num(e, 73);
        const aligned = (hA !== 0 || vA !== 0) && has(e, 11) && hA !== 3 && hA !== 5;
        const x = aligned ? num(e, 11) : num(e, 10), y = aligned ? num(e, 21) : num(e, 20);
        addText(stripMtext(str(e, 1)), o, x, y, num(e, 40, 2.5), num(e, 50), num(e, 41, 1), aligned ? hA : 0, aligned ? vA : 0, ctx, e.type === 'ATTRIB' ? str(e, 2).trim() : '');
        break;
      }
      case 'MTEXT': {
        const raw = e.p.filter((p) => p[0] === 3).map((p) => p[1]).join('') + str(e, 1);
        const lines = stripMtext(raw).split('\n');
        const h = num(e, 40, 2.5), att = num(e, 71, 1);
        const r = has(e, 11) ? Math.atan2(num(e, 21), num(e, 11)) * 180 / Math.PI : num(e, 50);
        const hA = [0, 0, 1, 2, 0, 1, 2, 0, 1, 2][att] ?? 0;
        const total = lines.length * h * 1.667;
        const top = att <= 3 ? 0 : att <= 6 ? total / 2 : total;
        const base = mul(o, mul(tr(num(e, 10), num(e, 20)), rot(r)));
        lines.forEach((ln, i) => addText(ln, base, 0, top - h - i * h * 1.667, h, 0, 1, hA, 0, ctx));
        break;
      }
      case 'INSERT': case 'DIMENSION': case 'ACAD_TABLE': {
        const name = str(e, 2).trim();
        const blk = blocks.get(name);
        if (e.type === 'INSERT') counts.inserts++;
        if (!blk) {
          if (e.type === 'DIMENSION') { const over = str(e, 1).trim(); const mv = num(e, 42, NaN); const s = over && over !== '<>' ? stripMtext(over) : Number.isFinite(mv) ? String(+mv.toFixed(2)) : ''; if (s) addText(s, ID, num(e, 11), num(e, 21), dimH, num(e, 53), 1, 1, 2, ctx); }
          for (const a of e.attribs) drawEnt1(a, ctx, blocks, ocs(a), layer);
          break;
        }
        if (ctx.depth >= MAX_DEPTH || (blk.flags & 4)) break;      // an xref's path is never followed or drawn
        const kind = e.type === 'INSERT' ? frameKind(name) : null;
        const sx = num(e, 41, 1) || 1, sy = num(e, 42, 1) || 1, ang = num(e, 50);
        // Code 70 / 71 are an INSERT's column / row counts; on a DIMENSION code 70 is its type flags.
        const cols = e.type === 'INSERT' ? Math.max(1, Math.min(100, num(e, 70, 1))) : 1, rows = e.type === 'INSERT' ? Math.max(1, Math.min(100, num(e, 71, 1))) : 1;
        const cs = num(e, 44), rs = num(e, 45);
        // A DIMENSION's block is written in world coordinates; an ACAD_TABLE's in the table's own, from its
        // insertion point along its direction (measured on LibreDWG's example_2018.dxf: the *T block's cells
        // sit at 0..300 while the table stands at 3299, 840).
        const baseM = e.type === 'INSERT' ? mul(o, mul(tr(num(e, 10), num(e, 20)), rot(ang)))
          : e.type === 'ACAD_TABLE' ? mul(tr(num(e, 10), num(e, 20)), rot(Math.atan2(num(e, 21, 0), num(e, 11, 1)) * 180 / Math.PI)) : ID;
        let sub: Ctx = { m: ctx.m, layer, depth: ctx.depth + 1, frame: ctx.frame, title: ctx.title };
        if (kind === 'title' && !ctx.title) sub = { ...sub, title: newRegion() };
        else if (kind === 'border') sub = { ...sub, frame: 'border' };
        for (let c = 0; c < cols; c++) for (let r = 0; r < rows; r++) {
          const im = e.type === 'INSERT' ? mul(baseM, mul(tr(c * cs, r * rs), mul(scl(sx, sy), tr(-blk.bx, -blk.by)))) : baseM;
          const cm: Ctx = { ...sub, m: mul(ctx.m, im) };
          for (const be of blk.ents) { if (be.type === 'ATTDEF') continue; drawEnt(be, cm, blocks); }
        }
        // ATTRIBs are in world (OCS) coordinates already; they belong to the insert's frame kind. An INSERT with ANY
        // party-like tag (CLIENT_NAME, PROJECT_TITLE, DWG_NO, DATE ...) is a title block by what it carries, whatever
        // its block is called (review of #967: "ISO_A1"), so every one of its values is withheld.
        const attrCtx: Ctx = e.attribs.some((a) => partyTag(str(a, 2).trim())) && !sub.title ? { ...sub, frame: 'border' } : sub;
        for (const a of e.attribs) drawEnt1(a, attrCtx, blocks, ocs(a), layer);
        break;
      }
      case 'HATCH': case 'MPOLYGON': counts.hatch_skipped++; break;
      case 'IMAGE': case 'OLE2FRAME': case 'OLEFRAME': case 'WIPEOUT': counts.images_skipped++; break;
      default: counts.other_skipped++;
    }
  };
  const polyOf = (v: { x: number; y: number; b: number }[], closed: boolean, o: M, ctx: Ctx) => {
    if (v.length < 2) return;
    const pts: number[] = [v[0].x, v[0].y];
    const n = v.length, last = closed ? n : n - 1;
    for (let i = 0; i < last; i++) { const a = v[i], z = v[(i + 1) % n]; pts.push(...bulgePts(a.x, a.y, z.x, z.y, a.b)); }
    addPoly(pts, o, ctx);
  };

  const root: Ctx = { m: ID, layer: '0', depth: 0, frame: null, title: null };
  for (const e of parsed.ents) drawEnt(e, root, parsed.blocks);
  const notes: string[] = [];
  if (expanded > MAX_EXPANDED) notes.push(`The drawing expands to more than ${MAX_EXPANDED} entities once its blocks are exploded; the page shows the first ${MAX_EXPANDED}.`);

  // ── which words may be drawn ───────────────────────────────────────────────────────────────────────
  const withheldBoxes: BBox[] = [];
  const singles = texts.filter((t) => t.s.trim().length === 1).length;
  if (singles > GLYPH_MAX || (singles >= 4 && singles > GLYPH_SHARE * texts.length)) {
    return { ok: false, reason: 'glyph_per_text', detail: `${singles} of ${texts.length} texts are a single character` };
  }
  // THE DEFAULT IS WITHHOLD (drawing_text_policy.ts): a word is drawn only when it reads as drawing content -
  // numbers, dimensions, codes from a closed list, the trade's vocabulary - and names no seed, even fuzzily.
  // The strings a model marked as identity (drawing_string_reading.ts, design change B, 13 Nov 2026), matched whole and
  // line by line, are never drawn; with the deny floor (isDrawingContent: only what code can prove is a party or a place).
  const marked = new Set([...(opts.identity ?? [])].map((x) => x.replace(/\s+/g, ' ').trim().toUpperCase()).filter(Boolean));
  const textLeaks = (x: string) => marked.has(x.replace(/\s+/g, ' ').trim().toUpperCase()) || !isDrawingContent(x) || !!seedHit(x, seeds) || residualScan(x, seeds).length > 0 || namesParty(x);
  const identity = (t: TextItem) => t.frame || partyTag(t.tag) || textLeaks(t.s);
  const out = new Set<TextItem>();
  for (const t of texts) if (identity(t)) out.add(t);
  // RUNS ARE READ TOGETHER ALONG THEIR OWN BASELINE (second review of #967: grouping by y alone missed a name
  // rotated 90 degrees or spaced three heights apart). Runs at the same angle whose baselines lie within 0.6 of a
  // text height of each other, and whose ends come within 3 heights, are one line; the line is judged spaced
  // ("ZZ ORB IT") and as it stands on the page, abutting runs joined ("ZZ ORBIT"), by the same full policy. A line
  // that fails withholds every run in it. Then two lines stacked within 2.4 heights are joined, so a phone or an
  // e-mail broken over two lines is read whole.
  type Geo = { t: TextItem; ang: number; a0: number; a1: number; perp: number; h: number };
  const geoOf = (t: TextItem): Geo => {
    const d = Math.hypot(t.m[0], t.m[1]) || 1, dx = t.m[0] / d, dy = t.m[1] / d;
    const [x0, y0] = ap(t.m, 0, 0), [x1, y1] = ap(t.m, t.w, 0);
    const a0 = x0 * dx + y0 * dy, a1 = x1 * dx + y1 * dy;
    return { t, ang: Math.round(((Math.atan2(dy, dx) * 180 / Math.PI) + 360) % 360 / 2) % 180, a0: Math.min(a0, a1), a1: Math.max(a0, a1), perp: -x0 * dy + y0 * dx, h: t.h || 1 };
  };
  const byAngle = (items: TextItem[]) => {
    const m = new Map<number, Geo[]>();
    for (const t of items) { const g = geoOf(t); (m.get(g.ang) ?? m.set(g.ang, []).get(g.ang)!).push(g); }
    for (const list of m.values()) list.sort((u, v) => u.perp - v.perp);
    return m;
  };
  const baselineGroups = (items: TextItem[]): Geo[][] => {
    const groups: Geo[][] = [];
    for (const list of byAngle(items).values()) {
      const parent = list.map((_, i) => i);
      const find = (i: number): number => (parent[i] === i ? i : (parent[i] = find(parent[i])));
      const hMax = Math.max(...list.map((g) => g.h));
      for (let i = 0; i < list.length; i++) {
        for (let j = i + 1; j < list.length && list[j].perp - list[i].perp <= 0.6 * hMax; j++) {
          const u = list[i], v = list[j], h = Math.max(u.h, v.h);
          if (v.perp - u.perp > 0.6 * h) continue;
          if (Math.max(v.a0 - u.a1, u.a0 - v.a1) > 3 * h) continue;
          parent[find(i)] = find(j);
        }
      }
      const by = new Map<number, Geo[]>();
      list.forEach((g, i) => { const r = find(i); (by.get(r) ?? by.set(r, []).get(r)!).push(g); });
      for (const g of by.values()) groups.push(g.sort((u, v) => u.a0 - v.a0));
    }
    return groups;
  };
  const joins = (g: Geo[]) => {
    const spaced = g.map((x) => x.t.s.trim()).join(' ');
    let tight = '';
    // Runs that ABUT (end to start within 0.35 of a height either way) read as one word; runs apart, or lying over
    // each other (a drafting overlap, not a word), read as two.
    g.forEach((x, i) => { const gap = i ? (x.a0 - g[i - 1].a1) / Math.max(x.h, g[i - 1].h) : 0; tight += (i && (gap > 0.35 || gap < -0.5) ? ' ' : '') + x.t.s.trim(); });
    return [spaced, tight];
  };
  // The spaced line is judged by the whole policy; the abutting reading ("ZZ ORBIT", "050 123" + "4567") by every
  // identity rule - seeds, company words, licence numbers, contacts - but not by the vocabulary, since two labels
  // that merely touch ("MEETING ROOM 102" against "STORE 103") make a non-word that names nobody.
  const tightLeaks = (x: string) => !!seedHit(x, seeds) || residualScan(x, seeds).length > 0 || namesParty(x);
  const lineLeaks = (g: Geo[]) => { const [spaced, tight] = joins(g); return textLeaks(spaced) || tightLeaks(tight); };
  const groupLeaks = (g: Geo[]) => g.length > 1 && lineLeaks(g);
  const stackLeaks = (upper: string[], lower: string[]) => upper.some((a) => lower.some((b) => [`${a} ${b}`, `${a}${b}`].some((j) => namesParty(j) || !!seedHit(j, seeds))));
  const stackedPairs = (groups: Geo[][]) => {
    const lines = groups.map((g) => ({ g, ang: g[0].ang, perp: g.reduce((n, x) => n + x.perp, 0) / g.length, a0: Math.min(...g.map((x) => x.a0)), a1: Math.max(...g.map((x) => x.a1)), h: Math.max(...g.map((x) => x.h)), text: joins(g) }));
    const pairs: [typeof lines[number], typeof lines[number]][] = [];
    const byA = new Map<number, typeof lines>();
    for (const l of lines) (byA.get(l.ang) ?? byA.set(l.ang, []).get(l.ang)!).push(l);
    for (const list of byA.values()) {
      list.sort((u, v) => u.perp - v.perp);
      const hMax = Math.max(...list.map((l) => l.h));
      for (let i = 0; i < list.length; i++) for (let j = i + 1; j < list.length && list[j].perp - list[i].perp <= 2.4 * hMax; j++) {
        const lo = list[i], up = list[j], h = Math.max(lo.h, up.h), d = up.perp - lo.perp;
        if (d <= 0.6 * h || d > 2.4 * h || Math.max(up.a0 - lo.a1, lo.a0 - up.a1) > h) continue;
        pairs.push([up, lo]);
      }
    }
    return pairs;
  };
  const allGroups = baselineGroups(texts);
  for (const g of allGroups) if (groupLeaks(g)) for (const x of g) out.add(x.t);
  for (const [up, lo] of stackedPairs(allGroups)) if (stackLeaks(up.text, lo.text)) for (const x of [...up.g, ...lo.g]) out.add(x.t);
  // A label takes its value with it: the words to its right on the same line, and the cell under it.
  for (const l of texts) {
    if (!l.label) continue;
    for (const t of texts) {
      if (t === l || out.has(t) && t !== l) continue;
      const sameLine = Math.abs(t.y - l.y) <= l.h * 0.6 && t.x >= l.x && t.x <= l.box.x1 + 40 * l.h;
      const below = t.y < l.y && l.y - t.y <= 2.6 * l.h && t.box.x1 >= l.box.x0 && t.box.x0 <= l.box.x1 + 2 * l.h;
      if (sameLine || below) out.add(t);
    }
  }

  // Title regions: black boxes, unless one would swallow the drawing.
  // The share is of the whole SHEET: the drawing and every title region together.
  const drawingBox = [...ink.map(bboxOf), ...texts.map((t) => t.box), ...titleRegions.map((r) => r.box).filter(finite)].reduce(grow, EMPTY);
  const sheetArea = finite(drawingBox) ? Math.max(1e-9, (drawingBox.x1 - drawingBox.x0) * (drawingBox.y1 - drawingBox.y0)) : 1;
  const blackRegions: BBox[] = [];
  const area = (b: BBox) => (b.x1 - b.x0) * (b.y1 - b.y0);
  for (const r of titleRegions) {
    if (!finite(r.box)) continue;
    const share = area(r.box) / sheetArea;
    if (share <= MAX_TITLE_SHARE) { blackRegions.push(r.box); continue; }
    // A title layer that spans the sheet usually does so because the SHEET BORDER is on it. Its linework is never
    // drawn (review of #967: a vector logo and SHX-exploded text reached a supplier that way): the region is
    // blacked out tight round everything on it except the outer border; if even that is most of the sheet, HOLD.
    // The border is a large AXIS-ALIGNED outline (every edge horizontal or vertical); a long diagonal or a cross
    // on the title layer is not a border and stays inside what must be covered.
    // Second review of #967: a border drawn as four LINEs, or a rectangle made of loose segments, is a border too.
    // The OUTLINE is the box round every long axis-aligned part (one spanning half the region's width or height);
    // when that is most of the region, every part whose segments ALL run along the outline's edges is border. A line
    // across the middle, or a diagonal, is not. Nothing on a title layer is ever drawn, so this only decides how
    // big the black box is.
    const R = r.box, tol = 0.005 * Math.max(R.x1 - R.x0, R.y1 - R.y0);
    const segs = (p: number[]) => { const o: [number, number, number, number][] = []; for (let i = 0; i + 3 < p.length; i += 2) o.push([p[i], p[i + 1], p[i + 2], p[i + 3]]); return o; };
    const axisOnly = (p: number[]) => p.length >= 4 && segs(p).every(([x0, y0, x1, y1]) => Math.abs(y1 - y0) <= tol || Math.abs(x1 - x0) <= tol);
    const long = r.parts.filter((p) => { if (!axisOnly(p)) return false; const b = bboxOf(p); return b.x1 - b.x0 >= 0.5 * (R.x1 - R.x0) || b.y1 - b.y0 >= 0.5 * (R.y1 - R.y0); });
    const O = long.map(bboxOf).reduce(grow, EMPTY);
    const outlined = finite(O) && area(O) >= 0.6 * area(R);
    const near = (v: number, u: number, w: number) => Math.abs(v - u) <= tol || Math.abs(v - w) <= tol;
    const isBorder = (p: number[]) => outlined && axisOnly(p) && segs(p).every(([x0, y0, x1, y1]) =>
      (Math.abs(y1 - y0) <= tol && near(y0, O.y0, O.y1)) || (Math.abs(x1 - x0) <= tol && near(x0, O.x0, O.x1)));
    const inner = [...r.parts.filter((p) => !isBorder(p)).map(bboxOf), ...r.texts.map((t) => t.box)].reduce(grow, EMPTY);
    if (!finite(inner)) continue;                               // the border alone: nothing to cover, nothing drawn
    if (area(inner) / sheetArea > MAX_TITLE_SHARE) return { ok: false, reason: 'title_unbounded', detail: `the title layer covers ${Math.round(100 * area(inner) / sheetArea)}% of the sheet inside its border` };
    blackRegions.push(inner);
    notes.push(`A title-block layer spans the sheet (its border); everything on it inside the border is blacked out and none of its lines are drawn.`);
  }
  // A kept word whose middle lies inside a blacked-out title region is under the box anyway; not drawn.
  const inside = (b: BBox, t: TextItem) => { const cx = (t.box.x0 + t.box.x1) / 2, cy = (t.box.y0 + t.box.y1) / 2; return cx >= b.x0 && cx <= b.x1 && cy >= b.y0 && cy <= b.y1; };
  for (const t of texts) if (!out.has(t) && blackRegions.some((b) => inside(b, t))) out.add(t);
  for (const t of out) withheldBoxes.push(t.box);
  const kept = texts.filter((t) => !out.has(t));
  // THE RE-READ, of what will actually be drawn, and only that: the kept runs are grouped again as they will stand
  // on the page and every line, and every stacked pair of lines, is judged by the same policy. Any hit holds the
  // page (removing a run can join two others). The pixels are re-read by OCR in scan_redact.check.ts.
  const drawnTexts = kept.map((t) => t.s);
  const keptGroups = baselineGroups(kept);
  const leak = keptGroups.filter(lineLeaks).length + stackedPairs(keptGroups).filter(([up, lo]) => stackLeaks(up.text, lo.text)).length;
  if (leak) return { ok: false, reason: 'residual', detail: `${leak} drawn line(s) still read as identity` };
  // THE TEXTS ALONE (13 Nov 2026, anonymity audit B finding L1): the anonymised CAD FILE keeps exactly the words this
  // preview draws (cad_file_redact.ts), so its redactor asks for the decision without paying for the pixels.
  if (opts.textsOnly) return { ok: true, rgba: new Uint8ClampedArray(0), width: 0, height: 0, drawn_texts: drawnTexts, withheld: { texts: out.size, regions: 0, samples_redacted: withheldBoxes.length }, counts, notes, regions_px: [] };
  for (const t of kept) counts.unknown_glyphs += t.unknown;
  if (counts.unknown_glyphs) notes.push(`${counts.unknown_glyphs} character(s) outside the Latin stroke font (for example Arabic) are drawn as boxes; the take-off still reads them.`);
  if (counts.paper_space_skipped) notes.push(`${counts.paper_space_skipped} paper-space entities (sheet layouts, where title blocks live) are not drawn.`);
  if (counts.hatch_skipped) notes.push(`${counts.hatch_skipped} hatch fill(s) are not drawn.`);
  if (counts.images_skipped) notes.push(`${counts.images_skipped} embedded image(s) (logos, scans) are never reproduced.`);

  // ── extents: everything drawn, with a far-flung stray point unable to shrink the drawing to a dot ──
  const pts: number[] = [];
  for (const p of ink) for (let i = 0; i < p.length; i += Math.max(2, 2 * Math.floor(p.length / 64))) pts.push(p[i], p[i + 1]);
  for (const t of kept) pts.push(t.box.x0, t.box.y0, t.box.x1, t.box.y1);
  for (const b of blackRegions) pts.push(b.x0, b.y0, b.x1, b.y1);
  // The title layer's full extent (its sheet border) still frames the page, though none of it is drawn.
  for (const r of titleRegions) if (finite(r.box)) pts.push(r.box.x0, r.box.y0, r.box.x1, r.box.y1);
  if (pts.length < 4) return { ok: false, reason: 'empty', detail: 'nothing drawable in model space' };
  let ext = bboxOf(pts);
  if (pts.length > 200) {
    const xs = pts.filter((_, i) => i % 2 === 0).sort((a, b) => a - b), ys = pts.filter((_, i) => i % 2 === 1).sort((a, b) => a - b);
    const q = (a: number[], f: number) => a[Math.min(a.length - 1, Math.max(0, Math.floor(a.length * f)))];
    const core = { x0: q(xs, 0.005), x1: q(xs, 0.995), y0: q(ys, 0.005), y1: q(ys, 0.995) };
    const cw = core.x1 - core.x0, ch = core.y1 - core.y0;
    if (cw > 0 && ch > 0 && ((ext.x1 - ext.x0) > 20 * cw || (ext.y1 - ext.y0) > 20 * ch)) {
      ext = { x0: core.x0 - cw * 0.05, x1: core.x1 + cw * 0.05, y0: core.y0 - ch * 0.05, y1: core.y1 + ch * 0.05 };
      notes.push('Entities far outside the drawing were left off the page.');
    }
  }
  const dw = Math.max(1e-9, ext.x1 - ext.x0), dh = Math.max(1e-9, ext.y1 - ext.y0);
  const L = opts.longEdge ?? RENDER_LONG_EDGE;
  const W = dw >= dh ? L : Math.max(400, Math.round(L * dw / dh)), H = dw >= dh ? Math.max(400, Math.round(L * dh / dw)) : L;
  const pad = Math.round(L * 0.02);
  const s = Math.min((W - 2 * pad) / dw, (H - 2 * pad) / dh);
  const ox = (W - dw * s) / 2, oy = (H - dh * s) / 2;
  const px = (x: number) => ox + (x - ext.x0) * s, py = (y: number) => H - (oy + (y - ext.y0) * s);

  // ── raster ─────────────────────────────────────────────────────────────────────────────────────────
  // Plain RGBA: this module draws, drawing_redact_page.ts encodes (imagescript's Deno build fetches its codec
  // .wasm at import, so the drawing decisions here stay testable with no network).
  const bm = new Uint8ClampedArray(W * H * 4);
  bm.fill(255);
  const maxSeg = opts.maxSegments ?? RENDER_MAX_SEGMENTS;
  let segs = 0;
  const dot = (x: number, y: number) => {
    for (let yy = y; yy <= y + 1; yy++) for (let xx = x; xx <= x + 1; xx++) {
      if (xx < 0 || yy < 0 || xx >= W || yy >= H) continue;
      const k = (yy * W + xx) * 4; bm[k] = INK[0]; bm[k + 1] = INK[1]; bm[k + 2] = INK[2]; bm[k + 3] = 255;
    }
  };
  const line = (x0: number, y0: number, x1: number, y1: number) => {
    let a = Math.round(x0), b = Math.round(y0); const c = Math.round(x1), d = Math.round(y1);
    if ((a < 0 && c < 0) || (b < 0 && d < 0) || (a >= W && c >= W) || (b >= H && d >= H)) return;
    const dx = Math.abs(c - a), dy = -Math.abs(d - b), sx = a < c ? 1 : -1, sy = b < d ? 1 : -1;
    let err = dx + dy, guard = dx - dy + 2;
    for (;;) { dot(a, b); if ((a === c && b === d) || --guard < 0) break; const e2 = 2 * err; if (e2 >= dy) { err += dy; a += sx; } if (e2 <= dx) { err += dx; b += sy; } }
  };
  const poly = (p: number[]) => { for (let i = 0; i + 3 < p.length; i += 2) { if (++segs > maxSeg) return; line(px(p[i]), py(p[i + 1]), px(p[i + 2]), py(p[i + 3])); } };
  for (const p of ink) { poly(p); if (segs > maxSeg) break; }
  for (const t of kept) { for (const st of t.strokes) poly(st.flat()); if (segs > maxSeg) break; }
  if (segs > maxSeg) return { ok: false, reason: 'too_dense', detail: `more than ${maxSeg} segments` };
  counts.segments = segs;
  const regionsPx: { kind: 'title' | 'text'; x: number; y: number; w: number; h: number }[] = [];
  const black = (b: BBox, padPx: number, kind: 'title' | 'text') => {
    const x = Math.max(0, Math.floor(px(b.x0)) - padPx), y = Math.max(0, Math.floor(py(b.y1)) - padPx);
    const x2 = Math.min(W, Math.ceil(px(b.x1)) + padPx), y2 = Math.min(H, Math.ceil(py(b.y0)) + padPx);
    if (x2 <= x || y2 <= y) return;
    for (let yy = y; yy < y2; yy++) { const row = yy * W * 4; for (let xx = x; xx < x2; xx++) { const k = row + xx * 4; bm[k] = 0; bm[k + 1] = 0; bm[k + 2] = 0; bm[k + 3] = 255; } }
    regionsPx.push({ kind, x, y, w: x2 - x, h: y2 - y });
  };
  for (const b of blackRegions) black(b, 3, 'title');
  for (const b of withheldBoxes) black(b, 2, 'text');
  return { ok: true, rgba: bm, width: W, height: H, drawn_texts: drawnTexts, withheld: { texts: out.size, regions: blackRegions.length, samples_redacted: withheldBoxes.length }, counts, notes, regions_px: regionsPx };
}

/** The same, as a promise (callers await it; the work is synchronous CPU). */
export const renderCadForSupplier = (input: Uint8Array | string, opts: { seeds?: string[]; longEdge?: number; maxSegments?: number; textsOnly?: boolean; identity?: Set<string> } = {}): Promise<CadRenderResult> =>
  Promise.resolve().then(() => renderCadForSupplierSync(input, opts));
