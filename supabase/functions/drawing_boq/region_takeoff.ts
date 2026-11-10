// region_takeoff — what a real engineer measures from the CLOSED OUTLINES of a CAD drawing and the words inside them,
// for every trade, with no model (10 Nov 2026, sales_engineer; founder 10 Nov: a customer's shop, villa or office drawing
// with legends is read "as if a real engineer saw the drawings"; ruling 1586: drawings come from every trade, the
// take-off is generic by layer and by labelled region, and what code cannot read is an explicit assumption or a line to
// confirm, never silence).
//
// MEASURED BEFORE THIS FILE. A DXF reached the BOQ as per-layer totals only: "closed outlines on layer A-AREA, 9 closed
// polylines, 142.6 sqm". Which room, its finish, its walls, its ceiling, its skirting, the doors in the schedule: none.
// A pool, a lift shaft, a planting bed or a scaffold run was "closed outlines on layer X" with no trade word at all.
//
// WHAT IT READS - one table, REGIONS: the layer an outline is drawn on says what the outline IS.
//  * ROOMS (room / space / area / zone layers; or, with none, any outline holding exactly one room name). Per room:
//    its name (the room-name words inside), floor area and perimeter (the outline), skirting (perimeter less the door
//    widths on it), wall area (perimeter x height, less the doors and windows on it), ceiling area (= floor, flat). The
//    height is the ceiling-height note inside the room, else the drawing's general note, else 3.0 m STATED as an
//    assumption and every wall line is to confirm.
//  * FINISHES - a finish legend ("F1 - PORCELAIN TILE 600x600", codes F / W / C / SK) and a room finish schedule (ROOM |
//    FLOOR | WALL | CEILING | SKIRTING) or finish tags inside the room. Lines are one per finish, summed over its rooms.
//  * DOOR / WINDOW SCHEDULE (MARK | TYPE | WIDTH | HEIGHT | QTY) -> one line per mark, counted by its tags on the plan,
//    else the schedule's QTY; sizes from the schedule (they also size the openings deducted from walls).
//  * OTHER TRADES - planting, turf, paving, slab, screed, roof, waterproofing, false-ceiling zones, racking zones: area
//    and edge length. A POOL: water area, coping length, and from its depth notes the average depth, water volume and
//    internal wall area. A LIFT shaft: internal size, and from the notes capacity, persons, speed, stops, travel, pit and
//    overhead - one lift per shaft. SCAFFOLD: the run length on the scaffold layer x the stated scaffold height.
//  * A closed outline on any other layer holding one label is a "labelled area", to confirm: its trade is the label's.
//
// WHAT IT NEVER DOES. Guess a height, a depth or a size silently (each is an assumption the BOQ says), count a legend or
// schedule's own marks as work, or read who the drawing is for (names are scrubbed by the caller's gate).
import type { CadGeometry } from '../_shared/doc_read/types.ts';
import { tablesFromWords, rowsOfWords } from '../_shared/doc_read/word_tables.ts';
import { neutralCadName } from '../_shared/cad_identity.ts';

type Pt = [number, number];
export type Region = { kind: 'room' | 'area' | 'pool' | 'shaft' | 'scaffold'; discipline: string; en: string; ar: string; section: string; section_ar: string };
/** ONE TABLE: the outline's layer -> what it is. First match wins. */
export const REGIONS: { re: RegExp; r: Region }[] = [
  { re: /POOL|SWIM|-SPA\b|JACUZZI/, r: { kind: 'pool', discipline: 'pools', en: 'Swimming pool', ar: 'حوض سباحة', section: 'Swimming pool', section_ar: 'حوض السباحة' } },
  { re: /LIFT|ELEV(?!ATION)|-SHAFT|ESCAL/, r: { kind: 'shaft', discipline: 'lifts', en: 'Lift', ar: 'مصعد', section: 'Lifts', section_ar: 'المصاعد' } },
  { re: /SCAF/, r: { kind: 'scaffold', discipline: 'scaffolding', en: 'Scaffolding', ar: 'سقالات', section: 'Scaffolding', section_ar: 'السقالات' } },
  { re: /TURF|LAWN|GRASS/, r: { kind: 'area', discipline: 'landscape', en: 'Turf / lawn', ar: 'نجيل', section: 'Landscape', section_ar: 'تنسيق المواقع' } },
  { re: /PLNT|PLANT(?:ING)?-?BED|SOFTSCAPE|L-SOFT|SHRUB|GROUNDCOVER|GROUND-COVER/, r: { kind: 'area', discipline: 'landscape', en: 'Planting bed (softscape)', ar: 'أحواض زراعة', section: 'Landscape', section_ar: 'تنسيق المواقع' } },
  { re: /PAVE|PAVING|HARDSCAPE|L-HARD|INTERLOCK/, r: { kind: 'area', discipline: 'landscape', en: 'Paving (hardscape)', ar: 'أرضيات خارجية (بلاط/إنترلوك)', section: 'Landscape', section_ar: 'تنسيق المواقع' } },
  { re: /RACK/, r: { kind: 'area', discipline: 'racking', en: 'Racking zone', ar: 'منطقة الرفوف', section: 'Racking', section_ar: 'الرفوف' } },
  { re: /WATERPR|WPRF|MEMBRANE/, r: { kind: 'area', discipline: 'waterproofing', en: 'Waterproofing', ar: 'العزل المائي', section: 'Waterproofing', section_ar: 'العزل المائي' } },
  { re: /SCREED/, r: { kind: 'area', discipline: 'civil', en: 'Screed', ar: 'طبقة تسوية', section: 'Floors', section_ar: 'الأرضيات' } },
  { re: /S-SLAB|-SLAB\b|SLAB-/, r: { kind: 'area', discipline: 'structure', en: 'Slab', ar: 'بلاطة خرسانية', section: 'Structure', section_ar: 'الهيكل الإنشائي' } },
  { re: /ROOF/, r: { kind: 'area', discipline: 'roofing', en: 'Roof area', ar: 'مساحة السطح', section: 'Roofing', section_ar: 'الأسطح' } },
  { re: /CLNG|CEIL/, r: { kind: 'area', discipline: 'ceilings', en: 'False ceiling zone', ar: 'منطقة سقف مستعار', section: 'Ceilings', section_ar: 'الأسقف' } },
  { re: /ROOM|-RM\b|SPACE|SPCE|A-AREA|NET-?AREA|FLOR-?AREA|-ZONE|ZONE-/, r: { kind: 'room', discipline: 'architecture', en: 'Room', ar: 'غرفة', section: 'Rooms', section_ar: 'الغرف' } },
];
/** Layers whose outlines are never a region (annotation, symbols, furniture, the frame). */
const NOT_A_REGION = /ANNO|TEXT|TXT|IDEN|-TAG|DIMS?\b|HATCH|PATT|SYMB|FURN|FIXT|EQPM|EQUIP|TTLB|TITLE|BORDER|FRAME|DEFPOINTS|VIEWPORT|LEGEND|GRID|DOOR|GLAZ|WIND|-WALL|WALL-|COLS?\b|DUCT|PIPE|TRAY|CNDT|CONDUIT/;
export const regionOf = (layer: string): Region | null => {
  const L = String(layer || '').toUpperCase().split('|').pop()!.replace(/[\s_.]+/g, '-');
  if (NOT_A_REGION.test(L) && !/ROOM|POOL|LIFT|SHAFT/.test(L)) return null;
  return REGIONS.find((x) => x.re.test(L))?.r ?? null;
};

// ── words ───────────────────────────────────────────────────────────────────────────────────────────
/** What a room is called, EN and AR (a room name on a plan, never a party). */
export const ROOM_NAME = new RegExp(String.raw`\b(?:master\s*)?bed\s*-?\s*room|\bbedroom|\bliving|\bfamily\s*(?:room|hall|living)|\bdining|\bkitchen(?:ette)?|\bpantry|\bmajlis|\bguest|\bbath(?:room)?\b|\btoilet|\bw\.?c\.?\b|\bpowder|en-?\s*suite|\bdressing|\bcloset|\bwardrobe|\bmaid|\bdriver|\blaundry|\bstore(?:room)?\b|\bstorage|\butility|\bcorridor|\blobby|\bfoyer|\bentrance|\bhall\b|\breception|\boffice|\bmeeting|\bconference|\bboard\s*room|\bserver|\bplant\s*room|\bpump\s*room|\belectrical\s*room|\bmech(?:anical)?\s*room|\bstair(?:case|s)?\b|\bbalcony|\bterrace|\bgarage|\bparking|\bshop\b|\bsales\s*(?:area|floor)|\bretail|\bdisplay|\bfitting\s*room|\bcashier|\bstock\s*room|\bback\s*of\s*house|\bprayer|\bablution|\bgym\b|\bstudy|\blibrary|\bnursery|\bplay\s*room|\bcafeteria|\bcanteen|\bcaf[eé]\b|\brestaurant|\bwaiting|\bclinic|\bconsult|\btreatment|\bclassroom|\blab(?:oratory)?\b|\bworkshop|\bwarehouse|\bloading|\bsecurity|\bguard\s*room|\bpool\s*deck|غرف[ةه]\s*نوم|صال[ةه]|معيش[ةه]|مطبخ|مجلس|حمام|دور[ةه]\s*مياه|مخزن|ممر|مدخل|استقبال|مكتب|اجتماعات|غرف[ةه]\s*خادم[ةه]|غسيل|شرف[ةه]|مصلى|مواقف`, 'i');
const HEIGHT = /(?:\bC\.?\s*H\.?|\bCLG\.?\s*(?:HT|HEIGHT|LEVEL|LVL)|CEILING\s*(?:HT|HEIGHT|LEVEL|LVL)|\bF\.?F\.?L\.?\s*(?:TO|-)\s*(?:F\.?C\.?L|C\.?L|SOFFIT)|\bF\.?C\.?L\.?|ارتفاع\s*السقف)\s*[:=@]?\s*\+?\s*(\d+(?:[.,]\d+)?)\s*(MM|M|CM)?\b/i;
const FINISH_WORD = /tile|porcelain|ceramic|marble|granite|terrazzo|vinyl|carpet|parquet|laminate|epoxy|screed|paint|emulsion|plaster|render|wallpaper|wall\s*paper|cladding|panel|gypsum|acoustic|board|mosaic|stone|wood|timber|veneer|skirting|stainless|glass|mirror|fabric|leather|concrete|polished|بلاط|رخام|دهان|جبس|سيراميك|باركيه|سجاد|خشب|حجر/i;
const FINISH_CODE = /^(F|FF|FL|FLR|W|WF|WL|C|CF|CL|CLG|SK|SKT|SKR)[-.]?(\d{1,2}[A-Z]?)$/i;
const elementOf = (code: string): 'floor' | 'wall' | 'ceiling' | 'skirting' | null => {
  const p = code.toUpperCase().replace(/[-.]?\d.*$/, '');
  return /^SK/.test(p) ? 'skirting' : /^F/.test(p) ? 'floor' : /^W/.test(p) ? 'wall' : /^C/.test(p) ? 'ceiling' : null;
};
const normCode = (c: string) => c.toUpperCase().replace(/[-.\s]/g, '');
const normName = (s: string) => s.toUpperCase().replace(/[^A-Z0-9؀-ۿ]+/g, ' ').trim();

// ── geometry ────────────────────────────────────────────────────────────────────────────────────────
function inside(x: number, y: number, pts: Pt[]): boolean {
  let c = false;
  for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    const [xi, yi] = pts[i], [xj, yj] = pts[j];
    if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) c = !c;
  }
  return c;
}
function distToEdges(x: number, y: number, pts: Pt[]): number {
  let d = Infinity;
  for (let i = 0; i < pts.length; i++) {
    const [ax, ay] = pts[i], [bx, by] = pts[(i + 1) % pts.length];
    const dx = bx - ax, dy = by - ay, L2 = dx * dx + dy * dy;
    const t = L2 ? Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / L2)) : 0;
    d = Math.min(d, Math.hypot(x - (ax + t * dx), y - (ay + t * dy)));
  }
  return d;
}
const r2 = (v: number) => Math.round(v * 100) / 100;
const centre = (w: { s: string; x: number; y: number; h: number }): Pt => [w.x + 0.3 * w.h * Math.min(w.s.length, 30), w.y + 0.5 * w.h];

export type RoomRow = { name: string; layer: string; floor_sqm: number; perimeter_m: number; skirting_m: number; height_m: number; height_stated: boolean;
  wall_sqm: number; ceiling_sqm: number; openings: number; finish: { floor?: string; wall?: string; ceiling?: string; skirting?: string } };
export type RegionLine = { section: string; section_ar?: string; item: string; description: string; description_ar?: string; qty: number | null; unit: string; basis: string;
  confidence: 'low' | 'medium'; qty_status: 'read' | 'to_confirm'; estimate?: number | null; type: string };
export type RegionTakeoff = { lines: RegionLine[]; rooms: RoomRow[]; layers: string[]; blocks: string[]; assumptions: string[]; missing: string[]; disciplines: Record<string, { exact: string[]; assumed: string[] }> };

/** A height or depth written as "2700", "2.70", "2.7 M", "+3.000": metres. */
const metres = (v: string, unit?: string) => { const n = Number(v.replace(',', '.')); const u = (unit || '').toUpperCase(); return u === 'MM' ? n / 1000 : u === 'CM' ? n / 100 : u === 'M' ? n : n > 50 ? n / 1000 : n; };
export const ASSUMED_HEIGHT_M = 3.0;

export function regionTakeoff(g: CadGeometry): RegionTakeoff {
  const toM = g.toM || 1;
  const out: RegionTakeoff = { lines: [], rooms: [], layers: [], blocks: [], assumptions: [], missing: [], disciplines: {} };
  const disc = (d: string) => (out.disciplines[d] ??= { exact: [], assumed: [] });
  const W = g.words.map((w) => ({ ...w, x: w.x * toM, y: w.y * toM, h: (w.h || 0.2 / toM) * toM }));
  // Words by the x of their centre, so an outline asks only the words over its own width (a dense plan has 20,000
  // outlines and 50,000 words: every word against every outline would not finish inside the edge's CPU).
  const byX = W.map((w) => ({ w, c: centre(w) })).sort((a, b) => a.c[0] - b.c[0]);
  const wordsIn = (pts: Pt[]) => {
    let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
    for (const [x, y] of pts) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
    let lo = 0, hi = byX.length;
    while (lo < hi) { const m = (lo + hi) >> 1; if (byX[m].c[0] < x0) lo = m + 1; else hi = m; }
    const out: typeof W = [];
    for (let i = lo; i < byX.length && byX[i].c[0] <= x1; i++) { const { w, c } = byX[i]; if (c[1] >= y0 && c[1] <= y1 && inside(c[0], c[1], pts)) out.push(w); }
    return out;
  };
  const polys = g.closed.map((c) => ({ ...c, pts: c.pts.map(([x, y]) => [x * toM, y * toM] as Pt), area: c.area * toM * toM, perim: c.perim * toM }));
  const unit = g.unitStated ? `drawing unit ${g.unitName} ($INSUNITS)` : `drawing unit assumed ${g.unitName}`;
  const status = (sure: boolean) => (sure && g.unitStated ? 'read' as const : 'to_confirm' as const);

  // ── schedules and legends (rows of positioned words: y flipped so it grows down) ─────────────────
  const placed = W.map((w) => ({ s: w.s, x: w.x, y: -w.y - w.h, w: 0.6 * w.h * w.s.length, h: w.h }));
  const boxes: { x0: number; y0: number; x1: number; y1: number }[] = [];
  const tables = tablesFromWords(placed, 400, boxes);
  const inTable = (x: number, y: number) => boxes.some((b) => x >= b.x0 && x <= b.x1 && -y >= b.y0 - 0.5 && -y <= b.y1 + 0.5);
  const col = (head: string[], re: RegExp) => head.findIndex((h) => re.test(h));
  // Finish legend: "F1 - PORCELAIN TILE" written as one text, or the code and its description on one row.
  const finishes = new Map<string, { element: 'floor' | 'wall' | 'ceiling' | 'skirting'; desc: string }>();
  for (const row of rowsOfWords(placed)) {
    const cells = row.cells.map((c) => c.s);
    for (let k = 0; k < cells.length; k++) {
      const one = /^([A-Z]{1,3}[-.]?\d{1,2}[A-Z]?)\s*[-–:=]\s*(.{3,})$/i.exec(cells[k]);
      const [code, desc] = one ? [one[1], one[2]] : FINISH_CODE.test(cells[k]) && cells[k + 1] ? [cells[k], cells[k + 1].replace(/^[-–:=]\s*/, '')] : [null, null];
      if (!code || !desc || !FINISH_CODE.test(code) || !FINISH_WORD.test(desc)) continue;
      const el = elementOf(code); if (el) finishes.set(normCode(code), { element: el, desc: desc.trim() });
    }
  }
  // Room finish schedule: ROOM | FLOOR | WALL | CEILING | SKIRTING.
  const finishRows = new Map<string, Partial<Record<'floor' | 'wall' | 'ceiling' | 'skirting', string>>>();
  // Door / window schedules: MARK | TYPE | WIDTH | HEIGHT | QTY (or SIZE "900x2100").
  type Opening = { mark: string; kind: 'door' | 'window'; desc: string; w: number | null; h: number | null; qty: number | null };
  const openings = new Map<string, Opening>();
  for (const t of tables) {
    const head = t[0].map((c) => String(c ?? '').toLowerCase());
    const room = col(head, /room|space|الغرف/), fl = col(head, /floor|الأرضي/), wa = col(head, /wall|الجدر/), ce = col(head, /ceiling|السقف/), sk = col(head, /skirting/);
    if (room >= 0 && (fl >= 0 || wa >= 0 || ce >= 0)) {
      for (const r of t.slice(1)) {
        const name = normName(String(r[room] ?? '')); if (!name) continue;
        const get = (k: number) => (k >= 0 ? String(r[k] ?? '').trim() : '');
        finishRows.set(name, { floor: get(fl) || undefined, wall: get(wa) || undefined, ceiling: get(ce) || undefined, skirting: get(sk) || undefined });
      }
      continue;
    }
    const mark = col(head, /^(mark|tag|ref|no\.?|type\s*no|door\s*(no|mark)|window\s*(no|mark))/), wid = col(head, /width|العرض/), hei = col(head, /height|الارتفاع/), size = col(head, /size|w\s*x\s*h|dimension/);
    const qty = col(head, /qty|quantity|no\.?\s*of|nos|الكمية/), desc = col(head, /type|description|material|leaf|frame|النوع|الوصف/);
    if (mark < 0 || (wid < 0 && size < 0)) continue;
    const isWin = /window|glaz|نافذ/.test(head.join(' ')) || t.slice(1).every((r) => /^W/i.test(String(r[mark] ?? '')));
    for (const r of t.slice(1)) {
      const m = String(r[mark] ?? '').trim().toUpperCase(); if (!/^[A-Z]{1,3}[-.]?\d{1,3}[A-Z]?$/.test(m)) continue;
      const sz = size >= 0 ? /(\d{3,4})\s*[xX×]\s*(\d{3,4})/.exec(String(r[size] ?? '')) : null;
      const wv = sz ? +sz[1] : Number(String(r[wid] ?? '').replace(/[^\d.]/g, '')) || null, hv = sz ? +sz[2] : Number(String(r[hei] ?? '').replace(/[^\d.]/g, '')) || null;
      const q = qty >= 0 ? Number(String(r[qty] ?? '').replace(/[^\d]/g, '')) || null : null;
      const kind = isWin || /window|glaz/i.test(String(r[desc] ?? '')) ? 'window' : 'door';
      openings.set(normCode(m), { mark: m, kind, desc: desc >= 0 ? String(r[desc] ?? '').trim() : '', w: wv ? metres(String(wv), 'MM') : null, h: hv ? metres(String(hv), 'MM') : null, qty: q });
    }
  }

  // ── opening instances on the plan (door / window blocks), sized by schedule, block name or block width ──
  const DOORISH = /DOOR|^D[-_]?\d|^DR[-_]?\d/i, WINISH = /WIN|WNDW|GLAZ|^W[-_]?\d|^WN[-_]?\d/i;
  const tags = W.filter((w) => /^[A-Z]{1,3}[-.]?\d{1,3}[A-Z]?$/i.test(w.s) && openings.has(normCode(w.s)) && !inTable(w.x, w.y));
  const inst = g.inserts.filter((i) => DOORISH.test(i.name) || WINISH.test(i.name) || /A-DOOR|A-GLAZ|A-WIND/i.test(i.layer)).map((i) => {
    const x = i.x * toM, y = i.y * toM;
    const tag = tags.map((t) => ({ t, d: Math.hypot(centre(t)[0] - x, centre(t)[1] - y) })).filter((o) => o.d <= 1.5).sort((a, b) => a.d - b.d)[0]?.t;
    const sched = tag ? openings.get(normCode(tag.s)) : openings.get(normCode(i.name));
    const nm = /(\d{3,4})(?:\s*[xX]\s*(\d{3,4}))?/.exec(i.name);
    const kind: 'door' | 'window' = sched?.kind ?? (WINISH.test(i.name) || /GLAZ|WIND/i.test(i.layer) ? 'window' : 'door');
    const w = sched?.w ?? (nm ? metres(nm[1], 'MM') : i.width ? i.width * toM : null);
    const h = sched?.h ?? (nm?.[2] ? metres(nm[2], 'MM') : null);
    return { x, y, n: i.n, kind, w, h, hAssumed: h == null, name: i.name };
  });

  // ── rooms ────────────────────────────────────────────────────────────────────────────────────────
  const names = W.filter((w) => ROOM_NAME.test(w.s) && w.s.length <= 40 && !inTable(w.x, w.y));
  const typed = polys.map((p) => ({ p, r: regionOf(p.layer) }));
  let roomPolys = typed.filter((x) => x.r?.kind === 'room').map((x) => x.p);
  const viaName = !roomPolys.length;
  const nameSet = new Set(names);
  if (viaName) roomPolys = typed.filter((x) => !x.r && !NOT_A_REGION.test(x.p.layer.toUpperCase()) && x.p.area >= 1).map((x) => x.p).filter((p) => wordsIn(p.pts).filter((w) => nameSet.has(w)).length === 1);
  // Each name belongs to the SMALLEST outline that holds it.
  const owner = new Map<typeof names[number], typeof roomPolys[number]>();
  for (const p of roomPolys) for (const n of wordsIn(p.pts)) if (nameSet.has(n) && (!owner.has(n) || owner.get(n)!.area > p.area)) owner.set(n, p);
  const heightNotes = W.map((w) => ({ w, m: HEIGHT.exec(w.s) })).filter((x) => x.m).map((x) => ({ c: centre(x.w), v: metres(x.m![1], x.m![2]) })).filter((x) => x.v >= 2 && x.v <= 12);
  // The general note is the one outside every room ("CLG HT 3000 UNLESS NOTED"); a note inside a room is that room's.
  const generalHeight = (heightNotes.find((hN) => !roomPolys.some((p) => inside(hN.c[0], hN.c[1], p.pts))) ?? null)?.v ?? null;
  const codesIn = (p: { pts: Pt[] }) => wordsIn(p.pts).flatMap((w) => w.s.split(/[\s/,+]+/)).filter((c) => FINISH_CODE.test(c) && finishes.has(normCode(c))).map(normCode);
  let heightAssumed = 0;
  for (const p of roomPolys) {
    const own = names.filter((n) => owner.get(n) === p).sort((a, b) => b.y - a.y);
    if (!own.length && viaName) continue;
    if (own.length > 1 && !viaName) { if (p.area > 400) continue; }
    // The room tag beside the name ("G01", "101"), when it is inside too.
    const num = wordsIn(p.pts).find((w) => /^[A-Z]?\d{2,3}[A-Z]?$/.test(w.s) && own.some((n) => Math.abs(n.y - w.y) < 3 * n.h));
    const name = own.length ? [own.map((n) => n.s.trim()).join(' / '), num?.s].filter(Boolean).join(' ') : `Unnamed space ${out.rooms.length + 1}`;
    const local = heightNotes.find((hN) => inside(hN.c[0], hN.c[1], p.pts));
    const height = local?.v ?? generalHeight ?? ASSUMED_HEIGHT_M;
    const stated = !!(local || generalHeight);
    if (!stated) heightAssumed++;
    const onEdge = inst.filter((o) => distToEdges(o.x, o.y, p.pts) <= 0.35);
    const doorW = onEdge.filter((o) => o.kind === 'door' && o.w).reduce((a, o) => a + (o.w ?? 0) * o.n, 0);
    const openA = onEdge.reduce((a, o) => a + (o.w ?? 0) * (o.h ?? (o.kind === 'door' ? 2.1 : 1.2)) * o.n, 0);
    const sched = finishRows.get(normName(own.map((n) => n.s).join(' '))) ?? finishRows.get(normName(own[0]?.s ?? '')) ?? (num ? finishRows.get(normName(num.s)) : undefined);
    const tagged = codesIn(p);
    const pick = (el: 'floor' | 'wall' | 'ceiling' | 'skirting') => {
      const s = sched?.[el]; if (s) { const c = s.split(/[\s/,+]+/).find((x) => FINISH_CODE.test(x)); return c ? normCode(c) : s; }
      return tagged.find((c) => finishes.get(c)?.element === el);
    };
    const perim = p.perim;
    out.rooms.push({ name, layer: neutralCadName(p.layer), floor_sqm: r2(p.area), perimeter_m: r2(perim), skirting_m: r2(Math.max(0, perim - doorW)), height_m: height, height_stated: stated,
      wall_sqm: r2(Math.max(0, perim * height - openA)), ceiling_sqm: r2(p.area), openings: onEdge.reduce((a, o) => a + o.n, 0),
      finish: { floor: pick('floor'), wall: pick('wall'), ceiling: pick('ceiling'), skirting: pick('skirting') ?? (pick('floor') ? `to match ${pick('floor')}` : undefined) } });
    out.layers.push(p.layer);
  }
  if (out.rooms.length) {
    const d = disc('architecture');
    d.exact.push('floor area, perimeter and ceiling area per room (closed outlines)');
    const named = (c: string | undefined) => (c && finishes.get(c) ? `${c} - ${finishes.get(c)!.desc}` : c);
    const agg = (el: 'floor' | 'wall' | 'ceiling' | 'skirting', qtyOf: (r: RoomRow) => number, unitW: string, en: string, ar: string) => {
      const by = new Map<string, RoomRow[]>();
      for (const r of out.rooms) { const k = r.finish[el] ?? ''; by.set(k, [...(by.get(k) ?? []), r]); }
      for (const [k, rs] of by) {
        const q = r2(rs.reduce((a, r) => a + qtyOf(r), 0)); if (q <= 0) continue;
        const assumed = (el === 'wall') && rs.some((r) => !r.height_stated);
        const label = k ? named(k)! : 'finish not specified';
        out.lines.push({ section: 'Finishes', section_ar: 'التشطيبات', item: `${en}, ${label}`, description: `${en}, ${label}`, description_ar: `${ar}، ${k ? named(k) : 'التشطيب غير محدد'}`,
          qty: q, unit: unitW, basis: `${rs.length} room(s): ${rs.map((r) => `${r.name} ${qtyOf(r)}`).join(', ').slice(0, 160)}; ${el === 'wall' ? `perimeter x ${assumed ? `height (${ASSUMED_HEIGHT_M} m ASSUMED where no ceiling height is written)` : 'the written ceiling height'}, less door and window openings; ` : el === 'skirting' ? 'perimeter less door openings; ' : el === 'ceiling' ? 'flat ceiling taken equal to the floor outline; ' : ''}${unit}`,
          confidence: assumed || !k ? 'low' : 'medium', qty_status: status(!assumed && !!k), ...(assumed || !k ? { estimate: q } : {}), type: `finish:${el}:${k || 'unspecified'}` });
      }
    };
    agg('floor', (r) => r.floor_sqm, 'sqm', 'Floor finish', 'تشطيب الأرضية');
    agg('skirting', (r) => r.skirting_m, 'm', 'Skirting', 'نعلات الجدران');
    agg('wall', (r) => r.wall_sqm, 'sqm', 'Wall finish', 'تشطيب الجدران');
    agg('ceiling', (r) => r.ceiling_sqm, 'sqm', 'Ceiling finish', 'تشطيب السقف');
    if (heightAssumed) { out.assumptions.push(HEIGHT_NOTE(ASSUMED_HEIGHT_M, heightAssumed)); d.assumed.push(`wall height ${ASSUMED_HEIGHT_M} m in ${heightAssumed} room(s)`); } else d.exact.push('wall areas from the written ceiling height');
    if (inst.some((o) => o.hAssumed)) out.assumptions.push(OPENING_NOTE);
    if (out.rooms.some((r) => !r.finish.floor)) d.assumed.push('finishes for rooms the schedule / legend does not name');
    if (viaName) out.assumptions.push(ROOMS_BY_NAME_NOTE);
  }
  // ── door / window schedule lines ───────────────────────────────────────────────────────────────
  for (const o of openings.values()) {
    const onPlan = tags.filter((t) => normCode(t.s) === normCode(o.mark)).length;
    const qty = onPlan || o.qty;
    const sz = o.w && o.h ? `${Math.round(o.w * 1000)} x ${Math.round(o.h * 1000)} mm` : o.w ? `${Math.round(o.w * 1000)} mm wide` : '';
    const what = `${o.mark} - ${o.desc || (o.kind === 'door' ? 'Door' : 'Window')}${sz ? `, ${sz}` : ''}`;
    const disagree = onPlan && o.qty && onPlan !== o.qty;
    out.lines.push({ section: o.kind === 'door' ? 'Doors' : 'Windows', section_ar: o.kind === 'door' ? 'الأبواب' : 'النوافذ', item: what, description: what,
      description_ar: `${o.mark} - ${o.kind === 'door' ? 'باب' : 'نافذة'}${o.desc ? ` (${o.desc})` : ''}${sz ? `، ${sz.replace('mm wide', 'مم عرض').replace(' mm', ' مم')}` : ''}`,
      qty: qty ?? null, unit: 'nos', basis: onPlan ? `tag ${o.mark} drawn ${onPlan} time(s) on the plan; size and type from the schedule${disagree ? `; the schedule's QTY says ${o.qty}` : ''}` : o.qty ? `the schedule's QTY column for ${o.mark}` : `${o.mark} is in the schedule but no tag or quantity was found`,
      confidence: qty && !disagree ? 'medium' : 'low', qty_status: qty && !disagree ? 'read' : 'to_confirm', ...(disagree ? { estimate: onPlan } : {}), type: `opening:${normCode(o.mark)}` });
    disc('architecture').exact.push(`${o.mark} count (${onPlan ? 'tags on the plan' : 'schedule QTY'})`);
  }
  if (openings.size) for (const i of g.inserts) if (DOORISH.test(i.name) || WINISH.test(i.name) || /A-DOOR|A-GLAZ|A-WIND/i.test(i.layer)) out.blocks.push(i.name);

  // ── other trades' regions ──────────────────────────────────────────────────────────────────────
  const notesText = W.map((w) => w.s).join('\n');
  const num1 = (re: RegExp) => { const m = re.exec(notesText); return m ? metres(m[1], m[2]) : null; };
  const shafts = new Map<string, { n: number; w: number; d: number; layer: string; esc: boolean }>();
  let liftSpec = '';
  const labelled: { p: typeof polys[number]; label: string }[] = [];
  for (const { p, r } of typed) {
    if (!r && !NOT_A_REGION.test(p.layer.toUpperCase()) && p.area >= 1 && !roomPolys.includes(p)) {
      const ws = wordsIn(p.pts).filter((w) => /[A-Za-z\u0600-\u06FF]{3,}/.test(w.s) && !ROOM_NAME.test(w.s) && !HEIGHT.test(w.s));
      if (ws.length === 1 && ws[0].s.length <= 40) labelled.push({ p, label: ws[0].s.trim() });
    }
    if (!r || r.kind === 'room') continue;
    out.layers.push(p.layer);
    const label = wordsIn(p.pts).filter((w) => !ROOM_NAME.test(w.s) && /[A-Za-z؀-ۿ]{3,}/.test(w.s)).map((w) => w.s.trim()).slice(0, 2).join(' / ');
    const base = `closed outline on layer ${neutralCadName(p.layer)}${label ? ` labelled "${label.slice(0, 60)}"` : ''}; ${unit}`;
    const push = (item: string, ar: string, qty: number | null, unitW: string, basis: string, sure: boolean, type: string) =>
      out.lines.push({ section: r.section, section_ar: r.section_ar, item, description: item, description_ar: ar, qty: qty == null ? null : r2(qty), unit: unitW, basis, confidence: sure && g.unitStated ? 'medium' : 'low', qty_status: status(sure), ...(sure ? {} : { estimate: qty == null ? null : r2(qty) }), type });
    const d = disc(r.discipline);
    if (r.kind === 'area') {
      const what = label ? `${r.en} - ${label.slice(0, 60)}` : r.en;
      push(what, `${r.ar}${label ? ` - ${label.slice(0, 60)}` : ''}`, p.area, 'sqm', base, true, `area:${r.discipline}`);
      if (r.discipline === 'landscape' && /PAVE|HARD/i.test(p.layer)) push(`Edging to ${r.en.toLowerCase()}`, `حافة ${r.ar}`, p.perim, 'm', `perimeter of the ${base}`, true, `edge:${r.discipline}`);
      d.exact.push(`${r.en.toLowerCase()} area`);
    } else if (r.kind === 'pool') {
      const shallow = num1(/SHALLOW(?:\s*END)?\s*(?:DEPTH)?\s*[:=]?\s*(\d+(?:\.\d+)?)\s*(MM|M|CM)?/i), deep = num1(/DEEP(?:\s*END)?\s*(?:DEPTH)?\s*[:=]?\s*(\d+(?:\.\d+)?)\s*(MM|M|CM)?/i);
      const single = num1(/(?:WATER\s*)?DEPTH\s*[:=]?\s*(\d+(?:\.\d+)?)\s*(MM|M|CM)?/i);
      const avg = shallow != null && deep != null ? (shallow + deep) / 2 : single;
      const depthSure = avg != null, depth = avg ?? 1.4;
      push('Pool shell / floor finish (water surface area)', 'أرضية وتشطيب حوض السباحة (مساحة سطح الماء)', p.area, 'sqm', base, true, 'pool:area');
      push('Pool coping / edge', 'حافة حوض السباحة', p.perim, 'm', `perimeter of the ${base}`, true, 'pool:coping');
      push(`Pool internal wall finish (perimeter x average depth ${r2(depth)} m)`, 'تشطيب الجدران الداخلية للحوض', p.perim * depth, 'sqm', depthSure ? `perimeter x average of the written depths (${[shallow, deep, single].filter((x) => x != null).join(' / ')} m)` : `perimeter x ${depth} m ASSUMED: no depth is written on the drawing`, depthSure, 'pool:walls');
      push(`Pool water volume (average depth ${r2(depth)} m)`, 'حجم مياه الحوض', p.area * depth, 'm3', depthSure ? 'water area x average written depth' : `water area x ${depth} m ASSUMED depth`, depthSure, 'pool:volume');
      d.exact.push('water area, coping length'); (depthSure ? d.exact : d.assumed).push(depthSure ? 'average depth from the written depths' : 'average depth 1.4 m');
      if (!depthSure) out.assumptions.push(POOL_DEPTH_NOTE);
    } else if (r.kind === 'shaft') {
      const xs = p.pts.map((q) => q[0]), ys = p.pts.map((q) => q[1]);
      const w = Math.max(...xs) - Math.min(...xs), dd = Math.max(...ys) - Math.min(...ys);
      const cap = /(\d{3,4})\s*KG/i.exec(notesText)?.[1], pers = /(\d{1,2})\s*(?:PERSONS?|PAX|PASSENGERS?)/i.exec(notesText)?.[1];
      const speed = /(\d(?:\.\d+)?)\s*M\/S/i.exec(notesText)?.[1], stops = /(\d{1,3})\s*(?:STOPS|LANDINGS|FLOORS\s*SERVED)|(?:STOPS|LANDINGS)\s*[:=]?\s*(\d{1,3})/i.exec(notesText);
      const travel = num1(/TRAVEL\s*[:=]?\s*(\d+(?:\.\d+)?)\s*(MM|M)?/i), pit = num1(/PIT(?:\s*DEPTH)?\s*[:=]?\s*(\d+(?:\.\d+)?)\s*(MM|M)?/i), oh = num1(/(?:OVERHEAD|HEADROOM)\s*[:=]?\s*(\d+(?:\.\d+)?)\s*(MM|M)?/i);
      const spec = [cap && `${cap} kg`, pers && `${pers} persons`, speed && `${speed} m/s`, stops && `${stops[1] ?? stops[2]} stops`, travel != null && `travel ${travel} m`, pit != null && `pit ${pit} m`, oh != null && `overhead ${oh} m`].filter(Boolean).join(', ');
      const sk = `${r2(w)}x${r2(dd)}|${/ESCAL/i.test(p.layer)}`;
      const e = shafts.get(sk) ?? { n: 0, w, d: dd, layer: p.layer, esc: /ESCAL/i.test(p.layer) }; e.n++; shafts.set(sk, e);
      d.exact.push('number of lifts (shafts) and shaft size');
      liftSpec = spec;
      const unstated = [!cap && !pers && 'capacity', !speed && 'speed', !stops && 'stops', travel == null && 'travel', pit == null && 'pit depth', oh == null && 'overhead'].filter(Boolean) as string[];
      if (unstated.length) { out.missing.push(LIFT_NOTE(unstated.join(', '))); d.assumed.push(`${unstated.join(', ')} not written`); } else d.exact.push('capacity, speed, stops, travel, pit, overhead from the notes');
    } else if (r.kind === 'scaffold') {
      const h = num1(/(?:SCAFFOLD(?:ING)?\s*)?HEIGHT\s*[:=]?\s*(\d+(?:\.\d+)?)\s*(MM|M)?/i);
      push(`Scaffolding, ${h != null ? `${h} m high` : 'height to confirm'}`, `سقالات${h != null ? ` بارتفاع ${h} م` : ''}`, h != null ? p.perim * h : null, 'sqm', h != null ? `run length ${r2(p.perim)} m (perimeter of the ${base}) x written height ${h} m` : `run length ${r2(p.perim)} m measured; no scaffold height is written`, h != null, 'scaffold:area');
      d.exact.push('scaffold run length'); (h != null ? d.exact : d.assumed).push(h != null ? 'scaffold height from the note' : 'scaffold height not written');
    }
  }
  // One line per shaft size: the BOQ counts lifts, it does not repeat a line per shaft.
  const spec = liftSpec;
  for (const sh of shafts.values()) {
    out.lines.push({ section: 'Lifts', section_ar: 'المصاعد', item: `${sh.esc ? 'Escalator' : 'Passenger lift'} in shaft ${r2(sh.w)} x ${r2(sh.d)} m${spec ? ` (${spec})` : ''}`, description: `${sh.esc ? 'Escalator' : 'Passenger lift'} in shaft ${r2(sh.w)} x ${r2(sh.d)} m${spec ? ` (${spec})` : ''}`,
      description_ar: `${sh.esc ? 'سلم متحرك' : 'مصعد ركاب'} في بئر ${r2(sh.w)} × ${r2(sh.d)} م${spec ? ` (${spec})` : ''}`, qty: sh.n, unit: 'nos',
      basis: `one per shaft outline on layer ${neutralCadName(sh.layer)} (${sh.n}); internal shaft size from the outline${spec ? '; capacity, speed, stops, travel, pit and overhead as written in the notes' : ''}; ${unit}`, confidence: g.unitStated ? 'medium' : 'low', qty_status: status(true), type: 'lift:unit' });
  }
  // A closed outline on a layer no row names, holding exactly one label: its trade is the label's, to confirm.
  for (const { p, label } of labelled) {
    out.lines.push({ section: 'Labelled areas', section_ar: 'مساحات موسومة', item: `Area: ${label}`, description: `Area: ${label}`, description_ar: `مساحة: ${label}`, qty: r2(p.area), unit: 'sqm',
      basis: `closed outline on layer ${neutralCadName(p.layer)} holding the label "${label}"; what is to be done on it is the label's word, to confirm; ${unit}`, confidence: 'low', qty_status: 'to_confirm', estimate: r2(p.area), type: 'area:labelled' });
    disc('other').assumed.push(`what the labelled area "${label}" is for`);
  }
  // Scaffolding drawn as a run (open polyline / lines on a scaffold layer), not an outline.
  const scafLen = Object.entries(g.segs).filter(([l]) => regionOf(l)?.kind === 'scaffold').reduce((a, [, s]) => { let t = 0; for (let k = 0; k + 3 < s.length; k += 4) t += Math.hypot(s[k + 2] - s[k], s[k + 3] - s[k + 1]); return a + t * toM; }, 0);
  if (scafLen > 0 && !typed.some((x) => x.r?.kind === 'scaffold')) {
    const h = num1(/(?:SCAFFOLD(?:ING)?\s*)?HEIGHT\s*[:=]?\s*(\d+(?:\.\d+)?)\s*(MM|M)?/i);
    out.lines.push({ section: 'Scaffolding', section_ar: 'السقالات', item: `Scaffolding, ${h != null ? `${h} m high` : 'height to confirm'}`, description: `Scaffolding, ${h != null ? `${h} m high` : 'height to confirm'}`, description_ar: 'سقالات',
      qty: h != null ? r2(scafLen * h) : null, unit: 'sqm', basis: `run length ${r2(scafLen)} m drawn on the scaffold layer${h != null ? ` x written height ${h} m` : '; no scaffold height is written'}; ${unit}`, confidence: h != null ? 'medium' : 'low', qty_status: status(h != null), ...(h != null ? {} : { estimate: null }), type: 'scaffold:area' });
    const d = disc('scaffolding'); d.exact.push('scaffold run length'); (h != null ? d.exact : d.assumed).push(h != null ? 'scaffold height from the note' : 'scaffold height not written');
    out.layers.push(...Object.keys(g.segs).filter((l) => regionOf(l)?.kind === 'scaffold'));
  }
  out.layers = [...new Set(out.layers)]; out.blocks = [...new Set(out.blocks)];
  return out;
}
export const HEIGHT_NOTE = (m: number, n: number) => `No ceiling height is written for ${n} room(s); their wall areas use ${m} m as an assumption and are marked to confirm.`;
export const OPENING_NOTE = 'Where a door or window height is not in a schedule or its block name, 2.1 m (door) and 1.2 m (window) are assumed for the opening deducted from the wall area.';
export const ROOMS_BY_NAME_NOTE = 'No room layer is drawn: a room is a closed outline holding exactly one room name.';
export const POOL_DEPTH_NOTE = 'No pool depth is written on the drawing: the pool volume and internal wall area use an average depth of 1.4 m as an assumption and are marked to confirm.';
export const LIFT_NOTE = (what: string) => `The lift notes do not state: ${what}. They are asked of the customer before suppliers price the lift.`;
