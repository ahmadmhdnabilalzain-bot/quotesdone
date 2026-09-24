// cad_identity — the identity a CAD file carries, taken out of the take-off before a supplier reads it
// (22 Sep 2026, sales_engineer). Founder, 22 Sep: "have you checked if the sales engineer is removing
// the project details from the drawings perfectly without affecting them?"
//
// MEASURED BEFORE THIS FILE (production code, in process, a ZZ fixture DXF whose title block names a
// consultant and a project that are NOT the customer): a customer who uploads a DXF (and, since #821, a
// DWG) is not shown to suppliers as a picture — the file is held — but its TAKE-OFF is, and the take-off
// is written from the file's own names. Served to every matched supplier by supplier_api inbox:
//   block ORBITENG_LOGO 1 nos · block KEYSTONE_TITLEBLOCK_A1 1 nos · linework on layer ZZORBIT-M-DUCT
//   "ZZ HARBOUR TOWER - FCU" 24 nos · "SUPPLY DIFFUSERS AS PER ZZ ORBIT CONSULTING ENGINEERS SPEC" 12 nos
// and the repo's own title-block fixture served "linework on layer AL MANSOORI VILLA". The gates
// (create_inquiry's redactBoq, the inbox's inboxBoq) only know the CUSTOMER's name, e-mail, phone and
// project: a consultant's firm, the project as the consultant named it, a layer prefix and a block
// name are none of those, so every one passed and nothing was held.
//
// WHAT THIS DOES — two rules, both deterministic:
//  1. cadIdentityTerms(dxfText): what the file itself says identifies the job — HEADER $PROJECTNAME /
//     $LASTSAVEDBY / $HYPERLINKBASE, the DWGPROPS summary (title, subject, author, keywords, custom
//     properties), XREF paths, every TEXT / MTEXT / ATTRIB / ATTDEF on a title-block layer or inside a
//     title-block block, an ATTRIB whose TAG names a party (CLIENT, PROJECT, CONSULTANT, DRAWN...), and
//     the value after a "Client:" / "Project:" label anywhere. Those become seed terms (anonymise
//     seedTerms/redactText), so the same name is removed wherever the take-off repeats it.
//  2. neutraliseCadLines(boq): a layer or block NAME is never shown as the file wrote it. Only CAD
//     vocabulary survives (AIA/ISO 13567 layer codes, trades, devices, codes of 3 characters or fewer,
//     numbers); any other word is dropped, so "ZZORBIT-M-DUCT" reads "M-DUCT". A line that counts a title
//     block, a logo, a border, a stamp or an xref is not work anyone prices and is removed.
// Rule 2 needs no file, so the supplier inbox runs it on every stored BOQ — including a DWG's, whose
// entities this file cannot see from customer_api (LibreDWG runs inside drawing_boq).
//
// WHAT IT NEVER DOES: read binary DXF or DWG bytes (rule 1 is DXF text only), change a quantity, or
// touch a line that is not in the CAD reader's shape (section 'Blocks', 'Devices (CAD blocks)',
// 'layer …'). A concrete "block wall" in a spreadsheet BOQ is left alone.
// deno-lint-ignore-file no-explicit-any
import { redactText, seedTerms } from './anonymise.ts';

// Layer / block names that ARE a title block, a sheet frame or an external reference.
export const FRAME = /^(?:TITLE|TITLES|TITLEBLOCK|TITLEBLK|TTLB|TTL|TB|TBLK|BORDER|BORDERS|BRDR|LOGO|LOGOS|STAMP|SEAL|XREF|XREFS|VPORT|VIEWPORT|DEFPOINTS|FRAME|NPLT|NOPLOT|SHEETFRAME|REVISION|REVISIONS|REVS)$/i;
export const FRAME_NAME = (name: string) => tokens(name).some((t) => FRAME.test(t)) || /title\s*block|titleblock|sheet\s*frame/i.test(name);
// An ATTRIB tag that names a party or the job.
export const PARTY_TAG = /^(?:CLIENT|OWNER|EMPLOYER|CUSTOMER|PROJECT|PROJ|PROJECT_?NAME|PROJ_?NAME|PROJECT_?(?:NO|NUM|NUMBER)|JOB|JOB_?(?:NO|NUM|NAME)|SITE|LOCATION|ADDRESS|ADDR|PLOT|MAKANI|CONSULTANT|ARCHITECT|ENGINEER|CONTRACTOR|DEVELOPER|COMPANY|FIRM|DRAWN|DRAWN_?BY|DRN|CHECKED|CHECKED_?BY|CHK|APPROVED|APPROVED_?BY|APP|DESIGNED|DESIGNED_?BY|DES|DWG_?(?:NO|NUM)|DRAWING_?(?:NO|NUM|NUMBER)|PHONE|TEL|EMAIL|WEB|WEBSITE)$/i;
const LABEL_VALUE = /\b(?:client|owner|employer|customer|consultant|contractor|architect|engineer|developer|project(?:\s*(?:name|title))?|site(?:\s*address)?|location|address|drawn\s*by|checked\s*by|approved\s*by|designed\s*by)\s*[:：]\s*([^\n]{2,80})/gi;
const HEADER_VARS = new Set(['$PROJECTNAME', '$LASTSAVEDBY', '$HYPERLINKBASE', '$STYLESHEET', '$MENU']);
// Text on a title block that is DRAWING content, not a party: a view title, a scale, a date, a sheet number.
const CONTENT = /\b(?:PLANS?|SCHEDULES?|DETAILS?|DIAGRAMS?|SECTIONS?|ELEVATIONS?|LEGEND|NOTES|INDEX|SPECIFICATIONS?|SCALE|SHEET|REV(?:ISION)?S?|DATE|NTS|NORTH|ISSUED|FOR\s+CONSTRUCTION|TENDER|PERMIT|BID\s+SET)\b|^\s*[\d\s:./\-]+\s*$|^[A-Z]{1,2}-?\d{1,3}(?:\.\d{1,2})?[A-Z]?$/i;

export const tokens = (s: string) => String(s || '').split(/[\s\-_.,/\\|+]+/).filter(Boolean);

/** Every identity term an ASCII DXF states about its own job. Binary or non-DXF input returns []. */
export function cadIdentityTerms(dxfText: string): string[] {
  const src = String(dxfText || '');
  if (!src.slice(0, 4000).includes('SECTION')) return [];
  const lines = src.split(/\r?\n/);
  const out = new Set<string>();
  const add = (v: string) => {
    const t = String(v || '').replace(/\\P/g, ' ').replace(/\{\\[^;]*;|[{}]/g, '').replace(/\s+/g, ' ').trim();
    if (t.length < 4 || CONTENT.test(t)) return;
    out.add(t);
    for (const m of t.matchAll(LABEL_VALUE)) if (m[1].trim().length >= 4) out.add(m[1].trim());
  };
  let section = '', pendingSection = false, headerVar = '';
  let ent = '', layer = '', tag = '', text: string[] = [], blockName = '', inFrameBlock = false, afterFrameInsert = false, xrec = false, xref = false;
  const flush = () => {
    const v = text.join('');
    if (v && /^(?:TEXT|MTEXT|ATTRIB|ATTDEF)$/.test(ent)) {
      if (inFrameBlock || FRAME_NAME(layer) || (ent === 'ATTRIB' && afterFrameInsert) || ((ent === 'ATTRIB' || ent === 'ATTDEF') && PARTY_TAG.test(tag))) add(v);
      else for (const m of v.matchAll(LABEL_VALUE)) add(m[1]);
    }
    text = []; tag = ''; layer = '';
  };
  for (let i = 0; i + 1 < lines.length; i += 2) {
    const code = parseInt(lines[i].trim(), 10);
    if (!Number.isFinite(code)) break;
    const val = lines[i + 1];
    if (code === 0) {
      flush();
      ent = val.trim(); xrec = ent === 'XRECORD'; xref = false;
      if (ent === 'SECTION') pendingSection = true;
      else if (ent === 'ENDSEC') section = '';
      else if (ent === 'ENDBLK') { inFrameBlock = false; blockName = ''; }
      else if (ent === 'SEQEND') afterFrameInsert = false;
      else if (ent !== 'ATTRIB') afterFrameInsert = false;
      continue;
    }
    if (pendingSection && code === 2) { section = val.trim(); pendingSection = false; continue; }
    if (section === 'HEADER') {
      if (code === 9) headerVar = val.trim();
      else if (HEADER_VARS.has(headerVar) && code >= 1 && code <= 9) add(val.replace(/^.*[\\/]/, ''));
      continue;
    }
    if (code === 8) layer = val.trim();
    if (ent === 'BLOCK' && code === 2) { blockName = val.trim(); inFrameBlock = FRAME_NAME(blockName); }
    if (ent === 'BLOCK' && code === 70) xref = (parseInt(val.trim(), 10) & 4) === 4;
    if (ent === 'BLOCK' && code === 1 && xref) { const f = val.trim().replace(/^.*[\\/]/, '').replace(/\.[a-z0-9]{2,4}$/i, ''); add(f); add(val.trim().split(/[\\/]/).slice(-2, -1)[0] || ''); }
    if (ent === 'INSERT' && code === 2) afterFrameInsert = FRAME_NAME(val.trim());
    if ((ent === 'ATTRIB' || ent === 'ATTDEF') && code === 2) tag = val.trim();
    if (/^(?:TEXT|ATTRIB|ATTDEF)$/.test(ent) && code === 1) text.push(val);
    if (ent === 'MTEXT' && (code === 3 || code === 1)) text.push(val);
    // DWGPROPS: title (2), subject (3), author (4), comments (6), keywords (7), last saved by (8), custom 300-309.
    if (xrec && ((code >= 2 && code <= 8) || (code >= 300 && code <= 309))) add(code >= 300 ? val.replace(/^[^=]*=/, '') : val);
  }
  flush();
  return [...out];
}

// CAD vocabulary: the words a layer or block name may keep. AIA CAD Layer Guidelines major/minor groups,
// ISO 13567 element words, trades and devices a supplier prices. Codes of 3 characters or fewer and
// numbers are always kept (discipline letters, sizes, tags like D-900) — they identify nobody.
const VOCAB = new Set(`
  wall walls door doors glaz glazing wind window windows flor floor floors clng ceiling ceilings roof roofs
  strs stair stairs ramp elev elevator lift lifts furn furniture fixt fixture fixtures eqpm equip equipment
  duct ducts ductwork pipe pipes piping hvac plmb plumbing fire sprk spkl sprinkler sprinklers elec electrical
  lite light lights lighting powr power comm communication data tele anno note notes text symb symbol symbols
  iden iden patt hatch grid dims dimension dimensions case casework cols column columns beam beams slab slabs
  fndn foundation footing conc concrete steel stl masonry block brick tile tiles paving pave site topo cont
  road curb kerb park parking land landscape plnt plant plants tree trees irrg irrigation fenc fence gate gates
  supp supply retn return exhs exhaust exh diff diffuser diffusers grille grilles grilles regs register louv louver
  louvre damp damper dampers vav fcu ahu fan fans pump pumps valve valves boiler chiller chillers tank tanks
  cool cooling heat heating vent ventilation drain drains drainage sani sanitary sewr sewer storm strm dome
  domestic cold hot water gas medg medical oxygen vacuum cond condensate refr refrigerant
  smoke detector detectors alarm alarms bell bells horn strobe sounder beacon call point panel panels mcp fap
  socket sockets outlet outlets switch switches recp receptacle cable cables tray trays trunking conduit
  ladder busbar busway meter meters db dbs mdb smdb board boards lum luminaire luminaires emergency exit
  cctv camera cameras access control speaker speakers pa bms tv sat
  toilet toilets wc basin basins sink sinks shower showers bath bathtub urinal urinals tap taps mixer heater
  kitchen pantry counter cabinet cabinets wardrobe bed beds sofa table tables chair chairs desk desks
  villa room rooms area areas zone zones level levels ground first second third mezz mezzanine basement
  new existing demo demolition remove removed proposed future temp typical typ
  outline outlines boundary plot interior exterior int ext main sub north south east west
  insulation cladding facade curtain partition partitions gypsum board paint finish finishes skirting
  marble granite porcelain ceramic carpet vinyl wood timber aluminium aluminum glass handrail railing balustrade
`.split(/\s+/).filter(Boolean));
const keepWord = (t: string) => t.length <= 3 || /^\d+[a-z]?$/i.test(t) || VOCAB.has(t.toLowerCase());

/** A layer or block name with every word that is not CAD vocabulary removed. */
export function neutralCadName(name: string): string {
  const kept = tokens(name).filter(keepWord);
  return kept.length ? kept.join('-') : 'unnamed';
}

const CAD_SECTION = (s: unknown) => s === 'Blocks' || s === 'Devices (CAD blocks)' || /^layer /.test(String(s || ''));
const renameIn = (s: string) => String(s ?? '')
  .replace(/^(block )(.+?)( inserted \d+ times.*)?$/, (_m, a, n, z) => a + neutralCadName(n) + (z || ''))
  .replace(/^((?:closed outlines|linework) on layer )(.+)$/, (_m, a, n) => a + neutralCadName(n))
  .replace(/^(layer )(.+?)(, \d+ .*)?$/, (_m, a, n, z) => a + neutralCadName(n) + (z || ''));
const frameLine = (l: any) => {
  const m = String(l?.basis || '').match(/^block (.+?) inserted/) || String(l?.description || '').match(/^block (.+)$/) || String(l?.section || '').match(/^layer (.+)$/);
  return !!m && FRAME_NAME(m[1]);
};

/** Rule 2 on a BOQ object ({ boq: [...] }) or a bare line array. Quantities are never changed. */
export function neutraliseCadLines<T>(boq: T): T {
  const fix = (lines: any[]) => lines.filter((l) => !(CAD_SECTION(l?.section) && frameLine(l))).map((l) => CAD_SECTION(l?.section)
    ? { ...l, section: renameIn(l.section), ...(l.item != null ? { item: renameIn(l.item) } : {}), description: renameIn(l.description), basis: String(l.basis ?? '').replace(/^(block |layer )(.+?)(?= inserted \d+ times|, \d+ )/, (_m, a, n) => a + neutralCadName(n)) }
    : l);
  if (Array.isArray(boq)) return fix(boq) as unknown as T;
  if (boq && typeof boq === 'object' && Array.isArray((boq as any).boq)) return { ...(boq as any), boq: fix((boq as any).boq) };
  return boq;
}

/**
 * Both rules, for the take-off of one CAD file. `dxfText` is the ASCII DXF (empty for a DWG read
 * elsewhere: rule 2 still applies). Every string is passed through redactText with the file's terms.
 */
export function cadSupplierBoq<T>(boq: T, dxfText = ''): T {
  const terms = cadIdentityTerms(dxfText);
  const seeds = terms.length ? seedTerms({ extra: terms }) : [];
  const walk = (v: unknown): unknown => typeof v === 'string' ? (seeds.length ? redactText(v, seeds).text : v)
    : Array.isArray(v) ? v.map(walk)
    : v && typeof v === 'object' ? Object.fromEntries(Object.entries(v as Record<string, unknown>).map(([k, x]) => [k, walk(x)])) : v;
  return walk(neutraliseCadLines(boq)) as T;
}

/** The ASCII DXF text of an upload, or '' when it is not one (a DWG, a binary DXF, anything else). */
export function dxfTextOf(b64: string): string {
  try {
    const bin = atob(String(b64 || '').replace(/^data:[^;]+;base64,/, '').slice(0, 36 * 1024 * 1024));
    if (bin.startsWith('AutoCAD Binary DXF') || !bin.slice(0, 4000).includes('SECTION')) return '';
    return new TextDecoder('utf-8').decode(Uint8Array.from(bin, (c) => c.charCodeAt(0)));
  } catch (_e) { return ''; }
}
