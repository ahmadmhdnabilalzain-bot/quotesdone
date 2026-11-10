// linear_services — duct, pipe, cable tray, ladder, trunking, busway and conduit RUNS measured from a CAD drawing's
// layers and grouped by their printed SIZE, with no model (10 Nov 2026, sales_engineer; founder 10 Nov: the agent drafts
// a BOQ "as if a real engineer saw the drawings").
//
// MEASURED BEFORE THIS FILE. A DXF / DWG reached the BOQ only as per-layer totals (doc_read/cad.ts): "linework on layer
// M-HVAC-SUPP 2,734.2 m". A duct is drawn as TWO walls, so that figure is twice the duct; its sizes (600x400, 400x300)
// were never read, so a supplier could not price it; and cable tray and conduit were never named at all. The PDF set path
// (drawing_lengths.ts) measures ducts and pipes on a PDF's CAD layers; this is the same estimator's method for a CAD file:
//
//  * SERVICE - the layer name says what is drawn (SERVICES below, one table): busway, cable tray, ladder, trunking and
//    conduit before duct and pipe (a "BUS DUCT" is not ductwork; a "CONDUIT" is not condensate). Existing, demolition,
//    annotation, symbol, equipment, grille and title layers are never a run.
//  * DOUBLE-LINE RUNS (duct, tray) - two parallel walls of one layer, 50 mm to 3 m apart (tray 1.2 m), are ONE run along
//    their centreline: the overlap is measured once. The rest of a longer wall goes back to be paired again (a branch
//    splits one wall into two). Where most of a layer pairs, what is left is end caps, transitions and fittings: reported,
//    not counted. A layer that does not pair is drawn single-line and every line is the run.
//  * SIZE - each stretch takes the nearest printed label of its kind within reach (2 m, or 4 duct widths). For a
//    double-line stretch the label must AGREE with the drawn width (within 15 % or 25 mm, either dimension): a 600x400
//    label never sizes a 300 mm wide duct beside it. A stretch with no label in reach takes the label most of its
//    connected run carries; with none, it is grouped by its drawn width and marked "size not labelled", to confirm.
//  * UNITS - the drawing's own ($INSUNITS). A label is millimetres on a metric drawing and inches on an imperial one
//    (or when it carries "). With no stated unit every line is to confirm.
//
// WHAT IT NEVER DOES. Add risers or drops not drawn in plan, count fittings separately, add wastage, or size a run from a
// label of another kind or another stated system ("CHWS" never sizes a condensate run).
import type { CadGeometry } from '../_shared/doc_read/types.ts';
import { neutralCadName } from '../_shared/cad_identity.ts';

export type ServiceKind = 'duct' | 'pipe' | 'tray' | 'ladder' | 'trunking' | 'busway' | 'conduit' | 'steel' | 'member';
export type ServiceRow = { kind: ServiceKind; system: string; en: string; ar: string; re: RegExp };

/** Layers that are never a run, whatever else they say. */
export const NOT_A_RUN = /EXIST|EXST|-DEMO|DEMOL|ANNO|TEXT|TXT|-DIMS?\b|DIMENSION|SYMB|IDEN|HATCH|PATT|FIXT|EQPM|EQUIP|GRIL|-DIFF|DIFFUS|REGS|LOUV|GRID|TTLB|TITLE|NOTE|-TAG|LABEL|LEGEND|DETL|SECT|ELEV|DEFPOINTS|VIEWPORT|-INSL|INSUL|HANGER|SUPPORT/;
// ONE TABLE: the layer name's words -> the service a run on it is. First match wins, so the specific rows come first.
export const SERVICES: ServiceRow[] = [
  // Founder ruling 1586 (10 Nov 2026): every trade. Structural steel by its section, and the linear members of
  // landscape, fencing, balustrades and roofs, measured the same way (no size label needed: grouped by layer).
  { kind: 'steel', system: 'steel', en: 'Structural steel member', ar: 'عنصر حديد إنشائي', re: /^S-(?:BEAM|STL|STEEL|COLS?|BRAC|PURL|MEMB|FRAM)|STEEL|STL-|PURLIN|BRACING|RAFTER|GIRT|JOIST/ },
  { kind: 'member', system: 'fence', en: 'Fence', ar: 'سياج', re: /FENC|HOARD/ },
  { kind: 'member', system: 'kerb', en: 'Kerb / edging', ar: 'بردورة / حافة', re: /KERB|CURB|EDGING|EDGE-?STRIP/ },
  { kind: 'member', system: 'balustrade', en: 'Handrail / balustrade', ar: 'درابزين', re: /HANDRAIL|BALUST|RAILING|GUARDRAIL/ },
  { kind: 'member', system: 'gutter', en: 'Gutter / coping', ar: 'مزراب / غطاء جدار', re: /GUTTER|COPING|FLASHING/ },
  { kind: 'member', system: 'drip irrigation', en: 'Drip irrigation line', ar: 'خط ري بالتنقيط', re: /DRIP/ },
  { kind: 'busway', system: 'busway', en: 'Busway / busbar trunking', ar: 'مجاري قضبان التوزيع', re: /BUSWAY|BUSBAR|BUS-?DUCT|BUS-?TRUNK/ },
  { kind: 'ladder', system: 'ladder', en: 'Cable ladder', ar: 'سلم كابلات', re: /LADDER|CBL-?LDR|-LDR\b/ },
  { kind: 'tray', system: 'tray', en: 'Cable tray', ar: 'حامل كابلات', re: /CABLE-?TRAY|C-?TRAY|E-TRAY|\bTRAY|-CT$|-CT-|CBL-?TRY/ },
  { kind: 'trunking', system: 'trunking', en: 'Cable trunking', ar: 'مجرى كابلات (ترنكنج)', re: /TRUNK/ },
  { kind: 'conduit', system: 'conduit', en: 'Conduit', ar: 'مواسير كهربائية (كوندويت)', re: /CONDUIT|CNDT|E-COND\b|-CDT\b/ },
  { kind: 'pipe', system: 'SPR', en: 'Fire sprinkler pipe', ar: 'أنابيب رشاشات الحريق', re: /SPRK|SPRINK|SPKL|F-SPR|FP-SPR/ },
  { kind: 'pipe', system: 'FW', en: 'Fire fighting water pipe', ar: 'أنابيب مياه مكافحة الحريق', re: /HYDR|HOSE|FIRE-?(?:PIPE|WATER|MAIN|FIGHT)|F-PIPE|FP-PIPE|-FH\b|-FW\b/ },
  { kind: 'pipe', system: 'CHW', en: 'Chilled water pipe', ar: 'أنابيب المياه المبردة', re: /CHW|CHILL/ },
  { kind: 'pipe', system: 'HHW', en: 'Heating hot water pipe', ar: 'أنابيب مياه التدفئة', re: /HHW|HTG-?W/ },
  { kind: 'pipe', system: 'CD', en: 'Condensate drain pipe', ar: 'أنابيب صرف التكثيف', re: /CONDENS|-COND\b|-CD\b|PIPE-CD/ },
  { kind: 'pipe', system: 'REF', en: 'Refrigerant pipe', ar: 'أنابيب وسيط التبريد', re: /REFR|RFRG|REFRIG/ },
  { kind: 'pipe', system: 'SS', en: 'Soil and waste pipe', ar: 'أنابيب الصرف الصحي', re: /SANR|-SAN\b|-SAN-|SOIL|WAST|-SS\b|SEWER|SEWR|DRAIN(?!AGE-?STORM)/ },
  { kind: 'pipe', system: 'V', en: 'Vent pipe', ar: 'أنابيب التهوية الصحية', re: /VENT(?!IL)/ },
  { kind: 'pipe', system: 'ST', en: 'Storm water pipe', ar: 'أنابيب مياه الأمطار', re: /STRM|STORM|RAIN/ },
  { kind: 'pipe', system: 'HWR', en: 'Hot water return pipe', ar: 'أنابيب راجع المياه الساخنة', re: /HWR|HWC|RECIRC/ },
  { kind: 'pipe', system: 'HW', en: 'Domestic hot water pipe', ar: 'أنابيب المياه الساخنة', re: /DOMW-HW|DOMW-SHW|-HW\b|HOT-?WATER/ },
  { kind: 'pipe', system: 'CW', en: 'Domestic cold water pipe', ar: 'أنابيب المياه الباردة', re: /DOMW-CW|DOMW-SCW|-CW\b|COLD-?WATER|DOMW|WATER-?SUPPLY/ },
  { kind: 'pipe', system: 'G', en: 'Gas pipe', ar: 'أنابيب الغاز', re: /NGAS|LPG|-GAS\b|GAS-?PIPE/ },
  { kind: 'pipe', system: 'IRR', en: 'Irrigation pipe', ar: 'أنابيب الري', re: /IRRIG|IRRG|L-IRR/ },
  { kind: 'duct', system: 'kitchen exhaust', en: 'Kitchen exhaust duct', ar: 'مجاري عادم المطبخ', re: /KITCHEN-?EXH|K-?EXH|KEX\b|KEXH/ },
  { kind: 'duct', system: 'smoke extract', en: 'Smoke extract duct', ar: 'مجاري سحب الدخان', re: /SMOKE|SMK/ },
  { kind: 'duct', system: 'fresh air', en: 'Fresh air duct', ar: 'مجاري الهواء النقي', re: /FRESH|OUTSIDE-?AIR|TFA|-FA\b|-OA\b|-FAD\b/ },
  { kind: 'duct', system: 'exhaust air', en: 'Exhaust air duct', ar: 'مجاري هواء العادم', re: /EXHS|EXHAUST|-EXH\b|-EA\b|-EAD\b|-TEF\b/ },
  { kind: 'duct', system: 'return air', en: 'Return air duct', ar: 'مجاري الهواء الراجع', re: /RETN|RETURN|-RA\b|-RAD\b/ },
  { kind: 'duct', system: 'supply air', en: 'Supply air duct', ar: 'مجاري هواء التغذية', re: /SUPP|SPLY|SUPPLY|-SA\b|-SAD\b/ },
  { kind: 'duct', system: '', en: 'Ductwork', ar: 'مجاري الهواء', re: /DUCT|HVAC|-AIR\b/ },
];
const SECTION: Record<ServiceKind, [string, string]> = {
  duct: ['Ductwork', 'مجاري الهواء'], pipe: ['Pipework', 'التمديدات والأنابيب'], tray: ['Cable containment', 'حوامل ومجاري الكابلات'],
  steel: ['Structural steel', 'الحديد الإنشائي'], member: ['Linear items', 'بنود طولية'],
  ladder: ['Cable containment', 'حوامل ومجاري الكابلات'], trunking: ['Cable containment', 'حوامل ومجاري الكابلات'],
  busway: ['Cable containment', 'حوامل ومجاري الكابلات'], conduit: ['Conduits', 'المواسير الكهربائية'],
};

/** The service a CAD layer draws, or null (not a run, or not a service layer). */
export function serviceOf(layer: string): ServiceRow | null {
  const L = String(layer || '').toUpperCase().split('|').pop()!.replace(/[\s_.]+/g, '-');
  if (NOT_A_RUN.test(L)) return null;
  // An MEP layer by its discipline letter (M-, P-, E-, F-, FP-, PL-), or a service word anywhere in the name.
  for (const s of SERVICES) if (s.re.test(L)) return s;
  return null;
}

// ── size labels ─────────────────────────────────────────────────────────────────────────────────────
type Label = { kind: 'rect' | 'round' | 'dn' | 'width' | 'section'; kgm?: number; a: number; b: number; text: string; x: number; y: number; system: string | null; tray: boolean; conduit: boolean; inch: boolean };
const SYS_IN_LABEL: [RegExp, string][] = [[/\bCHW[SR]?\b/, 'CHW'], [/\bHHW[SR]?\b/, 'HHW'], [/\bCD\b|COND(?!UIT)/, 'CD'], [/\b(?:SS|SAN|SOIL|W)\b/, 'SS'], [/\bV\b|\bVENT\b/, 'V'],
  [/\bHWR\b/, 'HWR'], [/\bHW\b/, 'HW'], [/\bCW\b/, 'CW'], [/\bGAS\b|\bG\b/, 'G'], [/\bRWP\b|\bST\b|STORM/, 'ST'], [/SPR/, 'SPR'], [/\bFH\b|HYDR|\bFW\b/, 'FW'], [/REF|\bRL\b|\bGL\b/, 'REF']];
/** Every size a text states: "600x400", "Ø250", "DN50", "100mm", '2"', "CT 300x50", "300W cable tray". */
export function sizeLabels(text: string): Omit<Label, 'x' | 'y'>[] {
  const t = String(text || '').toUpperCase().replace(/%%C/g, 'Ø').replace(/⌀/g, 'Ø').replace(/[″”]/g, '"');
  const out: Omit<Label, 'x' | 'y'>[] = [];
  const tray = /TRAY|\bCT\b|C\.T\.|LADDER|TRUNK/.test(t), conduit = /CONDUIT|\bPVC\b|\bGI\b|\bEMT\b|\bUPVC\b/.test(t);
  const sys = SYS_IN_LABEL.find(([re]) => re.test(t))?.[1] ?? null;
  const inch = /"/.test(t);
  let m: RegExpExecArray | null;
  // A steel section: "UB 406x178x60" (60 kg/m), "UC 203x203x46", "IPE 300", "HEA 200", "SHS 100x100x5", "CHS 114.3x5".
  const sec = /\b(UB|UC|UKB|UKC|IPE|HEA|HEB|HEM|SHS|RHS|CHS|PFC|UPN|UPE|RSJ|W)\s*(\d+(?:\.\d+)?(?:\s*[X×]\s*\d+(?:\.\d+)?){0,3})/.exec(t);
  if (sec) {
    const dims = sec[2].split(/\s*[X×]\s*/).map(Number);
    const kgm = /^(UB|UC|UKB|UKC)$/.test(sec[1]) && dims.length === 3 ? dims[2] : sec[1] === 'W' && dims.length === 2 ? Math.round(dims[1] * 1.488 * 10) / 10 : undefined;
    return [{ kind: 'section', a: dims[0], b: dims[1] ?? dims[0], text: `${sec[1]} ${dims.join('x')}`, system: null, tray: false, conduit: false, inch: false, ...(kgm ? { kgm } : {}) }];
  }
  const rect = /(?<![\d.])(\d{2,4})\s*"?\s*[X×*]\s*(\d{2,4})(?![\d.])/g;
  while ((m = rect.exec(t))) out.push({ kind: 'rect', a: +m[1], b: +m[2], text: `${m[1]}x${m[2]}`, system: sys, tray, conduit, inch });
  const round = /Ø\s*(\d{1,4}(?:\.\d+)?)|(?<![\d.X×])(\d{2,4})\s*(?:MM\s*)?(?:Ø|DIA\b)/g;
  while ((m = round.exec(t))) { const v = +(m[1] ?? m[2]); out.push({ kind: 'round', a: v, b: v, text: `Ø${v}`, system: sys, tray, conduit, inch }); }
  const dn = /\b(?:DN|NB)\s*(\d{2,4})\b/g;
  while ((m = dn.exec(t))) out.push({ kind: 'dn', a: +m[1], b: +m[1], text: `DN${m[1]}`, system: sys, tray, conduit, inch: false });
  if (!out.length) {
    const ip = /(?<![\d.\/])(\d{1,2}(?:\s+\d\/\d|-\d\/\d)?|\d\/\d)\s*"/.exec(t);
    if (ip) { const v = ip[1].includes('/') ? ip[1].split(/[\s-]+/).reduce((s, p) => s + (p.includes('/') ? +p.split('/')[0] / +p.split('/')[1] : +p), 0) : +ip[1]; out.push({ kind: 'round', a: v, b: v, text: `${ip[1].replace(/\s+/g, ' ')}"`, system: sys, tray, conduit, inch: true }); }
    const mm = /(?<![\d.X×])(\d{2,4})\s*(?:MM)?\s*(?:W\b|WIDE)|(?<![\d.X×])(\d{2,3})\s*MM\b(?!\s*[X×])/.exec(t);
    if (!ip && mm) out.push({ kind: mm[1] ? 'width' : 'round', a: +(mm[1] ?? mm[2]), b: +(mm[1] ?? mm[2]), text: mm[1] ? `${mm[1]}W` : `${mm[2]}mm`, system: sys, tray, conduit, inch: false });
  }
  return out;
}
/** Does this label size a run of this kind? */
function fits(l: Label, s: ServiceRow): boolean {
  if (l.system && s.kind === 'pipe' && l.system !== s.system) return false;
  switch (s.kind) {
    case 'steel': return l.kind === 'section';
    case 'member': return false;
    case 'duct': return (l.kind === 'rect' || l.kind === 'round') && !l.tray && !l.conduit;
    case 'tray': case 'ladder': case 'trunking': case 'busway': return l.tray && (l.kind === 'rect' || l.kind === 'width');
    case 'conduit': return l.conduit ? l.kind !== 'rect' : (l.kind === 'round' && l.a <= 63 && !l.system);
    case 'pipe': return (l.kind === 'round' || l.kind === 'dn') && !l.tray && !l.conduit;
  }
  return false;
}

// ── geometry ────────────────────────────────────────────────────────────────────────────────────────
type Piece = { ax: number; ay: number; bx: number; by: number; layer: string };
type Stretch = { ax: number; ay: number; bx: number; by: number; len: number; width: number | null; layer: string };
const len = (p: { ax: number; ay: number; bx: number; by: number }) => Math.hypot(p.bx - p.ax, p.by - p.ay);
function distPointSeg(px: number, py: number, s: { ax: number; ay: number; bx: number; by: number }): number {
  const dx = s.bx - s.ax, dy = s.by - s.ay, L2 = dx * dx + dy * dy;
  const t = L2 ? Math.max(0, Math.min(1, ((px - s.ax) * dx + (py - s.ay) * dy) / L2)) : 0;
  return Math.hypot(px - (s.ax + t * dx), py - (s.ay + t * dy));
}

/** Two walls of one run -> its centreline stretches; what does not pair comes back as `left`. Metres. */
export function pairWalls(pieces: Piece[], minW: number, maxW: number): { stretches: Stretch[]; left: Piece[] } {
  type Q = Piece & { ux: number; uy: number; ang: number; rho: number; t0: number; t1: number };
  const norm = (p: Piece): Q | null => {
    let { ax, ay, bx, by } = p; const L = Math.hypot(bx - ax, by - ay); if (L < 0.02) return null;
    let ux = (bx - ax) / L, uy = (by - ay) / L;
    if (ux < -1e-9 || (Math.abs(ux) < 1e-9 && uy < 0)) { [ax, ay, bx, by] = [bx, by, ax, ay]; ux = -ux; uy = -uy; }
    const ang = Math.round(Math.atan2(uy, ux) * 180 / Math.PI) % 180;
    return { ...p, ax, ay, bx, by, ux, uy, ang, rho: ax * -uy + ay * ux, t0: ax * ux + ay * uy, t1: bx * ux + by * uy };
  };
  const pool: Q[] = pieces.map(norm).filter((q): q is Q => !!q).sort((a, b) => (b.t1 - b.t0) - (a.t1 - a.t0));
  // Per direction, the walls sorted by their offset (rho): a partner is looked for only within maxW of it.
  const byAng = new Map<number, Q[]>();
  const put = (q: Q) => { const a = byAng.get(q.ang) ?? byAng.set(q.ang, []).get(q.ang)!; let lo = 0, hi = a.length; while (lo < hi) { const m = (lo + hi) >> 1; if (a[m].rho < q.rho) lo = m + 1; else hi = m; } a.splice(lo, 0, q); };
  for (const q of pool) put(q);
  const near = (q: Q): Q[] => {
    const out: Q[] = [];
    for (const k of [q.ang - 1, q.ang, q.ang + 1]) {
      const a = byAng.get((k + 180) % 180); if (!a) continue;
      let lo = 0, hi = a.length; while (lo < hi) { const m = (lo + hi) >> 1; if (a[m].rho < q.rho - maxW) lo = m + 1; else hi = m; }
      for (let i = lo; i < a.length && a[i].rho <= q.rho + maxW; i++) out.push(a[i]);
    }
    return out;
  };
  const stretches: Stretch[] = [], left: Piece[] = [];
  const used = new Set<Q>();
  const piece = (q: Q, t0: number, t1: number): Q => ({ ...q, t0, t1, ax: q.ux * t0 - q.uy * q.rho, ay: q.uy * t0 + q.ux * q.rho, bx: q.ux * t1 - q.uy * q.rho, by: q.uy * t1 + q.ux * q.rho });
  const queue = [...pool];
  let head = 0;
  while (head < queue.length && head < 400_000) {
    const q = queue[head++];
    if (used.has(q)) continue;
    let best: Q | null = null, bestD = Infinity, bestO = 0;
    for (const o of near(q)) {
      if (o === q || used.has(o)) continue;
      const d = Math.abs(o.rho - q.rho);
      if (d < minW || d > maxW || d >= bestD) continue;
      const lo = Math.max(q.t0, o.t0), hi = Math.min(q.t1, o.t1);
      if (hi - lo < 0.5 * Math.min(q.t1 - q.t0, o.t1 - o.t0) && hi - lo < 0.3) continue;
      if (hi <= lo) continue;
      best = o; bestD = d; bestO = hi - lo;
    }
    if (!best) continue;
    used.add(q); used.add(best);
    const lo = Math.max(q.t0, best.t0), hi = lo + bestO;
    const mid = (q.rho + best.rho) / 2;
    const c = piece({ ...q, rho: mid }, lo, hi);
    stretches.push({ ax: c.ax, ay: c.ay, bx: c.bx, by: c.by, len: hi - lo, width: bestD, layer: q.layer });
    // The rest of each wall goes back to be paired again (a branch splits one wall into two).
    for (const w of [q, best]) for (const [a, b] of [[w.t0, lo], [hi, w.t1]]) if (b - a > 0.05) { const r = piece(w, a, b); queue.push(r); put(r); }
  }
  for (const q of queue) if (!used.has(q) && q.t1 - q.t0 > 0) left.push({ ax: q.ax, ay: q.ay, bx: q.bx, by: q.by, layer: q.layer });
  return { stretches, left };
}

export type ServiceLine = {
  section: string; section_ar: string; item: string; description: string; description_ar: string; qty: number; unit: 'm' | 't'; basis: string;
  confidence: 'low' | 'medium'; qty_status: 'read' | 'to_confirm'; estimate?: number; type: string;
};
export type ServicesTakeoff = { lines: ServiceLine[]; layers: string[]; assumptions: string[]; missing: string[] };

const r1 = (v: number) => Math.round(v * 10) / 10;
const sizeText = (l: Label, inch: boolean) => l.kind === 'section' ? l.text : l.kind === 'rect' ? `${l.a}x${l.b}${inch ? ' in' : ' mm'}` : l.kind === 'dn' ? l.text : l.kind === 'width' ? `${l.a}${inch ? ' in' : ' mm'} wide` : inch ? `Ø${l.text.replace(/^Ø/, '').replace(/"$/, '')} in` : `Ø${l.a} mm`;

/** The runs of every service layer of a CAD drawing, measured and grouped by service and size. */
export function measureServices(g: CadGeometry): ServicesTakeoff {
  const toM = g.toM || 1;
  const imperial = /^(in|ft|yd|mi)$/.test(g.unitName);
  const bySvc = new Map<ServiceRow, Piece[]>();
  const layers: string[] = [];
  for (const [layer, s] of Object.entries(g.segs)) {
    const svc = serviceOf(layer); if (!svc) continue;
    layers.push(layer);
    const arr = bySvc.get(svc) ?? bySvc.set(svc, []).get(svc)!;
    for (let k = 0; k + 3 < s.length; k += 4) arr.push({ ax: s[k] * toM, ay: s[k + 1] * toM, bx: s[k + 2] * toM, by: s[k + 3] * toM, layer });
  }
  const lines: ServiceLine[] = [], missing: string[] = [];
  if (!bySvc.size) return { lines, layers, assumptions: [], missing };
  // Every label on the drawing, placed at the centre of its text.
  const labels: Label[] = [];
  for (const w of g.words) for (const l of sizeLabels(w.s)) {
    const inch = l.inch || imperial;
    labels.push({ ...l, inch, x: (w.x + 0.3 * w.h * w.s.length) * toM, y: (w.y + 0.5 * w.h) * toM });
  }
  const mOf = (l: Label, v: number) => v * (l.inch ? 0.0254 : 0.001);
  let leftOver = 0;
  for (const [svc, pieces] of bySvc) {
    const total = pieces.reduce((a, p) => a + len(p), 0);
    let stretches: Stretch[] = [];
    if (svc.kind === 'duct' || svc.kind === 'tray' || svc.kind === 'ladder' || svc.kind === 'trunking' || svc.kind === 'busway') {
      const pw = pairWalls(pieces, 0.05, svc.kind === 'duct' ? 3 : 1.2);
      const paired = pw.stretches.reduce((a, s) => a + s.len, 0);
      if (paired * 2 >= total * 0.5) { stretches = pw.stretches; leftOver += pw.left.reduce((a, p) => a + len(p), 0); }
      else stretches = pieces.map((p) => ({ ...p, len: len(p), width: null }));
    } else stretches = pieces.map((p) => ({ ...p, len: len(p), width: null }));
    // The size of each stretch.
    const fitting = labels.filter((l) => fits(l, svc));
    // The labels in 3 m cells, so a stretch asks only the cells within its reach.
    const CELL = 3, grid = new Map<string, Label[]>();
    for (const l of fitting) { const k = `${Math.floor(l.x / CELL)}|${Math.floor(l.y / CELL)}`; (grid.get(k) ?? grid.set(k, []).get(k)!).push(l); }
    const around = (s: Stretch, reach: number): Label[] => {
      const out: Label[] = [];
      for (let i = Math.floor((Math.min(s.ax, s.bx) - reach) / CELL); i <= Math.floor((Math.max(s.ax, s.bx) + reach) / CELL); i++)
        for (let j = Math.floor((Math.min(s.ay, s.by) - reach) / CELL); j <= Math.floor((Math.max(s.ay, s.by) + reach) / CELL); j++) out.push(...(grid.get(`${i}|${j}`) ?? []));
      return out;
    };
    const sizeOf = stretches.map((s): Label | null => {
      const reach = Math.max(2, (s.width ?? 0) * 4);
      let best: Label | null = null, bd = Infinity;
      for (const l of around(s, reach)) {
        let d = distPointSeg(l.x, l.y, s); if (d > reach) continue;
        if (s.width != null) {
          const wa = mOf(l, l.a), wb = mOf(l, l.b), tol = Math.max(0.15 * s.width, 0.025);
          if (Math.abs(wa - s.width) > tol && Math.abs(wb - s.width) > tol) continue;
          // A size is written width first: a label that matches only by its depth ranks a metre behind one that matches by width.
          if (Math.abs(wa - s.width) > tol) d += 1;
        }
        if (d >= bd) continue;
        best = l; bd = d;
      }
      return best;
    });
    // A stretch with no label in reach takes the label most of its connected run carries.
    const tol = 0.03;
    const parent = stretches.map((_, i) => i);
    const find = (i: number): number => (parent[i] === i ? i : (parent[i] = find(parent[i])));
    const ends = new Map<string, number>();
    const key = (x: number, y: number) => `${Math.round(x / tol)}|${Math.round(y / tol)}`;
    stretches.forEach((s, i) => { for (const [x, y] of [[s.ax, s.ay], [s.bx, s.by]]) { const k = key(x, y); const j = ends.get(k); if (j === undefined) ends.set(k, i); else parent[find(i)] = find(j); } });
    const runLabel = new Map<number, Map<string, { l: Label; m: number }>>();
    stretches.forEach((s, i) => { const l = sizeOf[i]; if (!l) return; const r = find(i); const m = runLabel.get(r) ?? runLabel.set(r, new Map()).get(r)!; const k = sizeText(l, l.inch); const e = m.get(k) ?? { l, m: 0 }; e.m += s.len; m.set(k, e); });
    const groups = new Map<string, { label: Label | null; width: number | null; m: number; n: number; layers: Set<string>; inherited: number }>();
    stretches.forEach((s, i) => {
      let l = sizeOf[i], inherited = false;
      if (!l) {
        const cands = [...(runLabel.get(find(i))?.values() ?? [])].sort((a, b) => b.m - a.m);
        const c = cands.find((x) => s.width == null || Math.min(Math.abs(mOf(x.l, x.l.a) - s.width), Math.abs(mOf(x.l, x.l.b) - s.width)) <= Math.max(0.15 * s.width, 0.025));
        if (c) { l = c.l; inherited = true; }
      }
      const k = l ? sizeText(l, l.inch) : svc.kind === 'member' ? 'as drawn' : s.width != null ? `${Math.round(s.width * (imperial ? 39.37 : 1000) / (imperial ? 1 : 50)) * (imperial ? 1 : 50)}${imperial ? ' in' : ' mm'} wide (size not labelled)` : 'size not labelled';
      const e = groups.get(k) ?? { label: l, width: s.width, m: 0, n: 0, layers: new Set<string>(), inherited: 0 };
      e.m += s.len; e.n++; e.layers.add(s.layer); if (inherited) e.inherited += s.len; groups.set(k, e);
    });
    const [section, sectionAr] = SECTION[svc.kind];
    const unitWord = g.unitStated ? `drawing unit ${g.unitName} ($INSUNITS)` : `drawing unit assumed ${g.unitName}`;
    for (const [k, e] of [...groups].sort((a, b) => b[1].m - a[1].m)) {
      if (e.m < 0.05) continue;
      const labelled = !!e.label;
      const shape = svc.kind !== 'duct' ? '' : !e.label ? '' : e.label.kind === 'rect' ? 'Rectangular ' : 'Round ';
      const shapeAr = svc.kind !== 'duct' || !e.label ? '' : e.label.kind === 'rect' ? ' مستطيلة' : ' دائرية';
      const what = svc.kind === 'duct' ? `${shape}${shape ? 'duct' : 'Duct'} ${k}${svc.system ? ` (${svc.system})` : ''}` : `${svc.en} ${k}`;
      const whatAr = svc.kind === 'duct' ? `${svc.ar}${shapeAr} ${k.replace(' (size not labelled)', ' (المقاس غير مكتوب)').replace(' wide', ' عرض')}` : `${svc.ar} ${k.replace(' (size not labelled)', ' (المقاس غير مكتوب)').replace('size not labelled', 'المقاس غير مكتوب').replace(' wide', ' عرض')}`;
      const how = e.width != null || (svc.kind === 'duct' && stretches.some((s) => s.width != null)) ? 'centreline between the two drawn walls' : 'drawn line';
      const sized = labelled ? `sized by the printed label ${e.label!.text}${e.width != null ? ' (its width matches the drawn width)' : ''}${e.inherited ? `; ${r1(e.inherited)} m of it takes the size its connected run is labelled with` : ''}` : 'no size label in reach of these stretches';
      const ok = (labelled || svc.kind === 'member') && g.unitStated;
      const qty = r1(e.m);
      lines.push({ section, section_ar: sectionAr, item: what, description: what, description_ar: whatAr, qty, unit: 'm',
        basis: `${how} on layer ${[...new Set([...e.layers].map(neutralCadName))].sort().join(', ')}, ${e.n} stretch(es), ${sized}; ${unitWord}`,
        confidence: ok ? 'medium' : 'low', qty_status: ok ? 'read' : 'to_confirm', ...(ok ? {} : { estimate: qty }),
        type: `${svc.kind}:${e.label ? e.label.text.replace(/\s+/g, '') : 'unlabelled'}${svc.system && svc.kind !== svc.system ? ':' + svc.system.replace(/\s+/g, '_') : ''}` });
      // Steel by weight where the section names its mass (UB 406x178x60 = 60 kg/m): tonnes, from the measured length.
      if (svc.kind === 'steel' && e.label?.kgm && ok) {
        const t = Math.round(e.m * e.label.kgm / 1000 * 1000) / 1000;
        lines.push({ section, section_ar: sectionAr, item: `${e.label.text} steel (by weight)`, description: `Structural steel ${e.label.text} (by weight)`, description_ar: `حديد إنشائي ${e.label.text} (بالوزن)`, qty: t, unit: 't',
          basis: `${qty} m measured x ${e.label.kgm} kg/m (the mass the section designation states); connections, plates and bolts not included`, confidence: 'medium', qty_status: 'read', type: `steel_t:${e.label.text.replace(/\s+/g, '')}` });
      }
      if (!labelled && svc.kind !== 'member') missing.push(`${qty} m of ${svc.en.toLowerCase()} has no size label within reach on the drawing; its size is to be confirmed.`);
    }
  }
  if (leftOver > 0.5) missing.push(`${r1(leftOver)} m of duct and tray linework that does not pair into a run (end caps, transitions, fittings) was not counted as length.`);
  return { lines, layers, missing, assumptions: [SERVICES_NOTE] };
}
export const SERVICES_NOTE = 'Duct, pipe, cable tray and conduit lengths are measured in plan along the drawn centreline in the drawing\'s own unit and grouped by the printed size; risers and drops not drawn in plan, fittings (measured through) and wastage are not added.';
