// drawing_from_ocr — what a drawing SAYS, read from its OCR with rules, and the BOQ draft that
// follows from it. No model, no network.
//
// WHY (14 Sep 2026). The founder's sample fire alarm layout went through the real customer path and
// came out as a BOQ of 0 lines against a 7-line answer key: the only free reader, boqFromLines,
// looks for "<description> <qty> <unit>" and a drawing states almost nothing that way. What a
// drawing does state is structural — a title block, a legend, numbered notes, room labels, device
// address tags. Founder: "if something can be coded then we do it".
//
// INPUT. OCR lines WITH their page boxes (the portal sends them as ocr_lines; ocrPlan.ts makes them),
// or plain text when that is all there is. Geometry matters for the title block: sorted top-to-
// bottom, a plan's room labels interleave with the title block's cells, and "the line under CLIENT"
// in text order was a room label three columns away (measured: client read as "INT"). With boxes,
// a label's value is the line directly BELOW it in the same cell.
//
// WHAT IT READS (each separately scoreable):
//   titleBlock  label/value pairs — CLIENT, SITE, PROJECT, DRAWING TITLE, SCALE, DATE, DRAWN,
//               DRAWING REF, REVISION, ISSUE — found by fuzzy label match (OCR reads CLIENT as
//               "CUENT", DRAWING REF as "CRAVING REF"), plus shape rules needing no label: an
//               ISO 19650-style reference, a date (repairing "2002/2020" -> 20/02/2020, the slash
//               OCR drops), NTS or 1:n, an issue status.
//   legend      entries mapped to device types (legend_vocabulary.ts).
//   notes       the cable specification and the isolator statement, read through a fixed
//               fire-alarm note vocabulary so "cadlo nstaled usng" is still cable installed using.
//   rooms       "<Name> Room" and plain room words.
//   addresses   loop tags "L1/01", OCR-tolerant, DISTINCT per loop; an address far above the rest
//               of its loop is a misread and is reported, not counted.
//   fap         where the panel is: the room label nearest the plan's FAP mark.
//
// THE BOQ IT DRAFTS — only what the reading supports; nothing is invented:
//   * the loop: distinct addresses read, the highest one, which ones were not read. A loop is
//     numbered consecutively from 01, so the highest address is its size; that inference is written
//     into the line and the line goes to the customer as our count (boq_open_lines), never silently.
//   * one line per legend device type: a counter's number arrives as `estimate`, qty_status
//     'to_confirm'; with no counter it is null and says so.
//   * the cable named in the notes (no length on an NTS sheet: null, said so) and loop isolators
//     where a note says which devices carry them.
//
// IDENTITY. Client, site, project, company, reference and drawn-by are read so they can be REMOVED:
// they are returned in `identity` for scrubbing and never written into a BOQ line a supplier sees.
import { DEVICE_TYPES, deviceTypeIn, EMPTY_VOCAB, type Vocab } from './legend_vocabulary.ts';
import { printedLines } from './symbol_count.ts';
import type { Line } from '../_shared/boq_open_lines.ts';

export type Rect = { x: number; y: number; w: number; h: number };
export type OcrLine = { text: string; bbox: Rect };

export type TitleBlock = {
  drawing_title: string | null; drawing_type: string | null; scale: string | null; date: string | null;
  revision: string | null; issue: string | null; revision_history: string[];
  // identity — used for redaction and scrubbing only
  client: string | null; site: string[]; project: string | null; company: string | null;
  drawing_ref: string | null; drawn_by: string | null;
};

const clean = (s: string) => String(s || '').replace(/\s+/g, ' ').trim();
const textLines = (text: string) => String(text || '').split(/\r?\n/).map(clean).filter(Boolean);

/** Levenshtein distance, for OCR-tolerant label and vocabulary matching. */
export function lev(a: string, b: string): number {
  if (a === b) return 0;
  const m = a.length, n = b.length; if (!m) return n; if (!n) return m;
  let prev = Array.from({ length: n + 1 }, (_, j) => j);
  for (let i = 1; i <= m; i++) {
    const cur = [i];
    for (let j = 1; j <= n; j++) cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    prev = cur;
  }
  return prev[n];
}
const near = (s: string, word: string) => { const a = s.toLowerCase().replace(/[^a-z ]/g, '').trim(); return !!a && lev(a, word) <= Math.max(1, Math.floor(word.length * 0.3)); };

// ── TITLE BLOCK ────────────────────────────────────────────────────────────────────────────────────
type Label = 'client' | 'site' | 'project' | 'drawing_title' | 'scale' | 'date' | 'drawn' | 'checked' | 'drawing_ref' | 'revision' | 'issue' | 'notes' | 'legend' | 'description' | 'rev';
const LABEL_WORDS: [Label, string[]][] = [
  ['client', ['client', 'owner', 'employer']], ['site', ['site', 'site address', 'location']], ['project', ['project']],
  ['drawing_title', ['drawing title', 'title']], ['scale', ['scale', 'scale @ a3', 'scale @ a1', 'scale @ a2']], ['date', ['date']],
  ['drawn', ['drawn', 'drawn by']], ['checked', ['checked', 'checked by']], ['drawing_ref', ['drawing ref', 'drawing no', 'dwg no', 'drawing number']],
  ['revision', ['revision']], ['issue', ['issue']], ['notes', ['notes']], ['legend', ['legend']], ['description', ['description']], ['rev', ['rev']],
];
/**
 * The label a short line IS, or begins with. OCR tolerance is 40% of the label's length (measured:
 * "SCAEQ A" for SCALE, "ORAWN" for DRAWN, "CUENT" for CLIENT). A cell that prints two labels side by
 * side ("DRAWN CHECKED") is read as its first.
 */
export function labelOf(s: string): Label | null {
  const t = s.toLowerCase().replace(/[^a-z@0-9 ]/g, ' ').replace(/\s+/g, ' ').trim();
  if (!t || t.length > 20) return null;
  const words = t.split(' ');
  for (const [lab, list] of LABEL_WORDS) for (const w of list) {
    const tol = Math.max(1, Math.floor(w.length * 0.4));
    const head = words.slice(0, w.split(' ').length).join(' ');
    if (lev(t, w) <= tol || (head.length >= 4 && lev(head, w) <= tol)) return lab;
  }
  return null;
}

const DREF = /\b(\d{4,}[-–][A-Z0-9]{2,6}(?:[-–][A-Z0-9]{1,5}){3,6})\b/;
const SCALE = /\b(NTS|N\.T\.S\.?|1\s*:\s*\d{1,4})\b/i;
const ISSUE = /\b(AS\s+INSTALLED|AS\s+BUILT|FOR\s+CONSTRUCTION|FOR\s+TENDER|FOR\s+APPROVAL|PRELIMINARY|FOR\s+INFORMATION)\b/i;

/** A date as printed, or as OCR prints it without its first slash ("2002/2020" is 20/02/2020). */
export function readDate(s: string): string | null {
  const m = s.match(/\b(\d{1,2})\s*[\/.\-]\s*(\d{1,2})\s*[\/.\-]\s*(\d{2,4})\b/) || s.match(/\b(\d{2})(\d{2})\s*[\/.\-]\s*(\d{2}|\d{4})\b/);
  if (!m) return null;
  const d = +m[1], mo = +m[2];
  if (d < 1 || d > 31 || mo < 1 || mo > 12) return null;
  return `${m[1].padStart(2, '0')}/${m[2].padStart(2, '0')}/${m[3]}`;
}
/** UK-style postcode spacing restored ("AB12CD" -> "AB1 2CD"); anything else unchanged. */
const postcode = (s: string) => s.replace(/^([A-Z]{1,2}\d{1,2}[A-Z]?)\s?(\d[A-Z]{2})$/, '$1 $2');

const empty = (): TitleBlock => ({ drawing_title: null, drawing_type: null, scale: null, date: null, revision: null, issue: null, revision_history: [], client: null, site: [], project: null, company: null, drawing_ref: null, drawn_by: null });

/** Lines under a label, in the same cell: below it, starting within its column, until the next label. */
function valuesUnder(lab: OcrLine, all: OcrLine[], max = 4): OcrLine[] {
  const h = Math.max(5, Math.min(lab.bbox.h, 14));
  const below = all.filter((l) => l !== lab && l.bbox.y > lab.bbox.y + 0.5 * h && l.bbox.y < lab.bbox.y + 9 * h
    && l.bbox.x > lab.bbox.x - 3 * h && l.bbox.x < lab.bbox.x + 25 * h).sort((a, b) => a.bbox.y - b.bbox.y);
  const out: OcrLine[] = [];
  for (const l of below) { if (labelOf(l.text)) break; out.push(l); if (out.length >= max) break; }
  return out;
}

export function titleBlockFromLines(lines: OcrLine[], sheetW: number): TitleBlock {
  const tb = empty();
  const strip = lines.filter((l) => l.bbox.x > sheetW * 0.75);
  const set = <K extends keyof TitleBlock>(k: K, v: TitleBlock[K]) => { if (tb[k] == null || (Array.isArray(tb[k]) && !(tb[k] as unknown[]).length)) tb[k] = v; };
  for (const lab of strip) {
    const kind = labelOf(lab.text); if (!kind) continue;
    const vals = valuesUnder(lab, strip).map((l) => clean(l.text)).filter((v) => /[A-Za-z0-9\-]/.test(v));
    if (!vals.length) continue;
    if (kind === 'client') set('client', vals[0]);
    else if (kind === 'project') set('project', vals[0]);
    else if (kind === 'site') set('site', vals.filter((v) => /[A-Z]{2,}/.test(v)).slice(0, 4).map(postcode));
    else if (kind === 'drawing_title') { const t = vals.filter((v) => /^[A-Z0-9 &\-]+$/.test(v)).join(' '); if (t && (!tb.drawing_title || t.length > tb.drawing_title.length)) tb.drawing_title = t; }
    else if (kind === 'scale') { const s = vals.join(' ').match(SCALE); if (s) set('scale', s[1].toUpperCase().replace(/\s/g, '').replace('N.T.S', 'NTS').replace(/\.$/, '') + (/@\s*A([0-4])/i.test(lab.text) ? ` @ A${lab.text.match(/@\s*A([0-4])/i)![1]}` : '')); }
    else if (kind === 'date') { const d = vals.map(readDate).find((x) => x && x.length === 10); if (d) set('date', d); }
    else if (kind === 'drawn') { const v = vals.find((x) => /^[A-Z]{2,3}$/.test(x)); if (v) set('drawn_by', v); }
    else if (kind === 'drawing_ref') { const v = vals.map((x) => x.match(DREF)).find(Boolean); if (v) set('drawing_ref', v[1].replace(/–/g, '-')); }
    else if (kind === 'revision') { const v = vals.find((x) => /^([A-Z]|\d{1,2}|-|P\d{1,2}|C\d{1,2})$/.test(x)); if (v) set('revision', v); }
  }
  // Company: a firm-like word in the strip. A logo reads as one CamelCase token and is the TALLEST
  // text there (measured: "FireSafetyCo" 33 px; a garbled "PeVe" in the revision table 5 px).
  const firms = strip.map((l) => ({ l, m: l.text.match(/\b([A-Z][a-z]+(?:[A-Z][a-z]+)+(?:Co|Ltd|LLC|Group)?)\b/) }))
    .filter((x) => x.m && !labelOf(x.l.text)).sort((a, b) => b.l.bbox.h - a.l.bbox.h);
  if (firms.length) tb.company = firms[0].m![1];
  return tb;
}

/** Text-only fallback: what can be read without boxes (shape rules and labels in reading order). */
export function titleBlock(text: string, lines?: OcrLine[], sheetW?: number): TitleBlock {
  const tb = lines && sheetW ? titleBlockFromLines(lines, sheetW) : empty();
  const L = textLines(text);
  const all = L.join('\n');
  if (!tb.drawing_title) {
    // A title split over lines ("GROUND FLOOR" / "FIRE ALARM" / "SYSTEM LAYOUT"): consecutive caps
    // lines ending in LAYOUT / PLAN, never a label.
    for (let i = 0; i < L.length; i++) {
      if (!/(LAYOUT|PLAN|SCHEMATIC)$/.test(L[i]) || !/^[A-Z ]+$/.test(L[i])) continue;
      const parts = [L[i]];
      for (let j = i - 1; j >= Math.max(0, i - 3) && /^[A-Z ]{3,30}$/.test(L[j]) && !labelOf(L[j]) && !/\b(TINE|TITLE)\b/.test(L[j]); j--) parts.unshift(L[j]);
      const t = parts.join(' ');
      if (!tb.drawing_title || t.length > tb.drawing_title.length) tb.drawing_title = t;
    }
  }
  if (!tb.drawing_ref) { const ref = [...all.matchAll(new RegExp(DREF.source, 'g'))].map((m) => m[1].replace(/–/g, '-')).sort((a, b) => b.length - a.length)[0]; if (ref) tb.drawing_ref = ref; }
  if (!tb.scale) { const sc = all.match(SCALE); if (sc) tb.scale = sc[1].toUpperCase().replace(/\s/g, '').replace('N.T.S', 'NTS').replace(/\.$/, ''); }
  if (tb.scale === 'NTS' && /SCALE\s*@\s*A([0-4])/i.test(all)) tb.scale = `NTS @ A${all.match(/SCALE\s*@\s*A([0-4])/i)![1]}`;
  if (!tb.date) { const d = L.map(readDate).find((x) => x && x.length === 10); if (d) tb.date = d; }
  const iss = all.match(ISSUE); if (iss) tb.issue = iss[1].toUpperCase().replace(/\s+/g, ' ');
  if (!tb.revision) for (let i = 0; i < L.length; i++) if (labelOf(L[i]) === 'revision') { const v = L.slice(i + 1, i + 4).find((x) => /^([A-Z]|\d{1,2}|-|P\d{1,2}|C\d{1,2})$/.test(x)); if (v) { tb.revision = v; break; } }
  for (const l of L) { const m = l.match(/^(-|[A-Z]|\d{1,2})\s+(\S+)\s+(first issue|issued? for [a-z ]+|as (?:built|installed)|revised [a-z ]+)$/i); const d = m && readDate(m[2]); if (m && d) tb.revision_history.push(`${m[1]} ${d} ${m[3].replace(/\b\w/g, (c) => c.toUpperCase())}`); }
  return tb;
}

// ── LEGEND ─────────────────────────────────────────────────────────────────────────────────────────
// Which printed line names which device is REASONED (legend_vocabulary.ts, decision point
// drawing_boq.vocabulary): a line is a legend entry when the reasoning copied its words for a device type.
// No heading word, no device regex and no "c/w" test decides it any more. Held: no entries.
export type LegendEntry = { text: string; type: string; en: string; unit: 'nos' | 'm' };
export function legend(text: string, lines?: OcrLine[], vocab: Vocab = EMPTY_VOCAB): LegendEntry[] {
  // With boxes, one reading per PRINTED line (the longest); a truncated second reading of the same
  // line ("V/ALL MOUNTED SOUNDER BE") is not a second legend entry. Measured: it became "Sounder".
  const L = lines ? printedLines(lines).sort((a, b) => a.bbox.y - b.bbox.y).map((l) => clean(l.text)) : textLines(text);
  const best = new Map<string, LegendEntry>();
  for (const l of L) {
    const d = deviceTypeIn(l, vocab);
    if (!d || d.type === 'fire_rated_cable' || d.type === 'loop_isolator') continue;
    const cur = best.get(d.type);
    if (!cur || l.length > cur.text.length) best.set(d.type, { text: l, type: d.type, en: d.en, unit: d.unit });
  }
  const order = DEVICE_TYPES.map((d) => d.type);
  return [...best.values()].sort((a, b) => order.indexOf(a.type) - order.indexOf(b.type));
}
/** What the reasoning is shown: every printed line (one reading each) and the title block's title. */
export function drawingTexts(input: string | OcrLine[], sheetW = 0): { texts: string[]; title: string | null } {
  const lines = Array.isArray(input) ? input : undefined;
  const text = lines ? lines.map((l) => l.text).join('\n') : String(input || '');
  const W = sheetW || (lines ? Math.max(1, ...lines.map((l) => l.bbox.x + l.bbox.w)) : 0);
  const L = lines ? printedLines(lines).sort((a, b) => a.bbox.y - b.bbox.y).map((l) => clean(l.text)) : textLines(text);
  return { texts: [...new Set(L)].filter((l) => l.length >= 2).slice(0, 200), title: titleBlock(text, lines, W).drawing_title };
}

// ── NOTES ──────────────────────────────────────────────────────────────────────────────────────────
// The words fire alarm notes are written in. An OCR token within edit distance 2 of one of these (or
// 1 for short words) is read as it. A fixed vocabulary, not a dictionary: it corrects drawing notes
// and nothing else.
const NOTE_WORDS = ['all', 'cable', 'cables', 'installed', 'using', 'enhanced', 'unless', 'otherwise', 'stated', 'break', 'glass', 'units', 'and', 'sounders', 'have', 'loop', 'isolators', 'fitted', 'detectors', 'devices', 'call', 'points', 'fire', 'rated', 'gold', 'plus', 'flex', 'with', 'are', 'to', 'be'];
export function correctNoteWords(s: string): string {
  return s.split(/(\s+)/).map((tok) => {
    const w = tok.toLowerCase().replace(/[0]/g, 'o').replace(/[^a-z]/g, '');
    if (w.length < 3 || /fp\s*200/i.test(tok)) return tok;
    let best = ''; let bd = 99;
    for (const v of NOTE_WORDS) { const d = lev(w, v); if (d < bd) { bd = d; best = v; } }
    return bd <= (w.length >= 5 ? 2 : 1) ? best : tok;
  }).join('');
}
export type Notes = { lines: string[]; cable: string | null; isolators: string | null };
export function notes(text: string): Notes {
  const L = textLines(text);
  const cands = L.filter((l) => /fp\s*200|isol|okalor|glass\s+\w+\s+and|cable/i.test(l)).map(correctNoteWords);
  let cable: string | null = null;
  for (const l of cands) {
    const c = l.match(/(enhanced\s+)?fp\s*200\s*(gold|plus|flex)?\s*(?:(\d)[\s.,](\d)|(\d(?:\.\d)?))?\s*(mm²?|mm2|m\b|sm\b)?/i);
    if (!c) continue;
    const size = c[3] ? `${c[3]}.${c[4]}` : (c[5] || '');
    const v = `${c[1] ? 'Enhanced ' : ''}FP200${c[2] ? ' ' + c[2][0].toUpperCase() + c[2].slice(1).toLowerCase() : ''}${size && (c[6] || c[3]) ? ' ' + size + 'mm' : ''}`;
    if (!cable || v.length > cable.length) cable = v;
  }
  // The isolator statement: a note naming break glass units / call points and sounders as having
  // loop isolators. "break" is often unreadable (measured "Drodk"), "glass" and the rest are not.
  const iso = cands.find((l) => /\b(glass|call\s+points?)\b/i.test(l) && /\bsounders?\b/i.test(l) && /\bloop\b/i.test(l) && /\bhave\b|\bfitted\b/i.test(l));
  return { lines: cands.slice(0, 10), cable, isolators: iso ? 'All break glass units and sounders have loop isolators fitted' : null };
}

// ── ROOMS ── the room names are REASONED (legend_vocabulary.ts Vocab.rooms); no room-word list decides them.

/** The room label nearest the plan's FAP mark (outside the legend strip). Needs boxes. */
export function fapLocation(lines: OcrLine[] | undefined, sheetW: number, roomNames: string[]): string | null {
  if (!lines) return null;
  const fap = lines.find((l) => l.bbox.x < sheetW * 0.75 && /\bf\s?a\s?p\b/i.test(l.text));
  if (!fap) return null;
  const rn = new Set(roomNames.map((r) => r.toLowerCase()));
  let best: OcrLine | null = null; let bd = Infinity;
  for (const l of lines) {
    if (l === fap || l.bbox.x > sheetW * 0.75 || !rn.has(clean(l.text).toLowerCase())) continue;
    const d = Math.hypot(l.bbox.x + l.bbox.w / 2 - (fap.bbox.x + fap.bbox.w / 2), l.bbox.y + l.bbox.h / 2 - (fap.bbox.y + fap.bbox.h / 2));
    if (d < bd) { bd = d; best = l; }
  }
  return best ? `near ${clean(best.text).toUpperCase()}` : null;
}

// ── LOOP ADDRESSES ─────────────────────────────────────────────────────────────────────────────────
const DIGITISH = (s: string) => s.replace(/[Oo]/g, '0').replace(/[Ss]/g, '5').replace(/[Bb]/g, '8').replace(/[lIi|!t]/g, '1').replace(/[Zz]/g, '2').replace(/[G]/g, '6');
const ADDR = /(?<![A-Za-z0-9])[Ll]\s?([1-9lIi|])\s*[\/\\|]\s*([0-9OoSsBlIi|tZG]{2,3})(?![0-9])/g;
export type Loop = { loop: string; read: number[]; highest: number | null; outliers: number[]; unread_below_highest: number[] };
export function addresses(text: string): Loop[] {
  const byLoop = new Map<string, Set<number>>();
  for (const m of String(text || '').matchAll(ADDR)) {
    const loop = DIGITISH(m[1]); const a = DIGITISH(m[2]);
    if (!/^\d$/.test(loop) || !/^\d{2,3}$/.test(a) || +a < 1) continue;
    if (!byLoop.has(loop)) byLoop.set(loop, new Set());
    byLoop.get(loop)!.add(+a);
  }
  const out: Loop[] = [];
  for (const [loop, set] of [...byLoop].sort()) {
    const sorted = [...set].sort((a, b) => a - b);
    // An address more than 10 above the next-highest read is a misread, not the loop's size
    // (measured: "L1/87" was OCR of L1/67 on the fixture).
    const outliers: number[] = [];
    while (sorted.length > 2 && sorted[sorted.length - 1] - sorted[sorted.length - 2] > 10) outliers.unshift(sorted.pop()!);
    const highest = sorted.length ? sorted[sorted.length - 1] : null;
    const unread = highest ? Array.from({ length: highest }, (_, i) => i + 1).filter((n) => !set.has(n)) : [];
    out.push({ loop: `L${loop}`, read: sorted, highest, outliers, unread_below_highest: unread });
  }
  return out;
}

export function soundLevels(text: string): number[] {
  return [...String(text || '').matchAll(/\b(\d{2,3})\s*d\s*B\s*\(?A\)?/gi)].map((m) => Number(m[1])).filter((n) => n >= 40 && n <= 130);
}

// ── THE DRAFT ──────────────────────────────────────────────────────────────────────────────────────
export type Counts = Record<string, { count: number; basis: string }>;
export type DrawingRead = {
  title_block: TitleBlock; legend: LegendEntry[]; notes: Notes; rooms: string[]; loops: Loop[]; sound_levels_dba: number[];
  fap_location: string | null; identity: string[]; boq: Line[]; missing_info: string[]; category: string;
};

/** Loop size is stated as our count only when most of 01..highest was read; below that it is an estimate. */
const LOOP_COVERAGE = 0.75;

export function readDrawing(input: string | OcrLine[], counts: Counts = {}, sheetW = 0, vocab: Vocab = EMPTY_VOCAB): DrawingRead {
  const lines = Array.isArray(input) ? input : undefined;
  const text = lines ? lines.map((l) => l.text).join('\n') : String(input || '');
  const W = sheetW || (lines ? Math.max(1, ...lines.map((l) => l.bbox.x + l.bbox.w)) : 0);
  const tb = titleBlock(text, lines, W); const lg = legend(text, lines, vocab); const nt = notes(text); const rm = vocab.rooms; const loops = addresses(text); const db = soundLevels(text);
  // The drawing type is what the reasoning read the title to say (never a title regex); held, unknown.
  tb.drawing_type = vocab.drawingType;
  const boq: Line[] = []; const missing: string[] = [];
  for (const lp of loops) {
    if (!lp.highest) continue;
    const coverage = lp.read.length / lp.highest;
    const pad = (n: number) => `${lp.loop}/${String(n).padStart(2, '0')}`;
    const unread = lp.unread_below_highest.length ? `; not read: ${lp.unread_below_highest.map(pad).join(', ')}` : '';
    boq.push({
      section: 'Fire alarm — addressable loop', type: `loop_${lp.loop.toLowerCase()}_addresses`,
      description: `Addressable loop ${lp.loop}: device addresses (${pad(1)}–${pad(lp.highest)})`, item: `Loop ${lp.loop} addresses`,
      qty: null, estimate: lp.highest, unit: 'addresses',
      qty_status: coverage >= LOOP_COVERAGE ? 'to_confirm' : 'estimated',
      basis: `${lp.read.length} distinct addresses read on the drawing, highest ${pad(lp.highest)}; a loop is numbered consecutively, so the highest address is its size${unread}. An address is not a device: a detector with a sounder carries two.`,
      confidence: 'low',
    });
    if (lp.outliers.length) missing.push(`Address tags read as ${lp.outliers.map((n) => `${lp.loop}/${n}`).join(', ')} sit far above the rest of the loop and were treated as misreads.`);
  }
  for (const e of lg) {
    const c = counts[e.type];
    boq.push({
      section: 'Fire alarm — devices (from the legend)', type: e.type, description: e.en, item: e.en,
      qty: null, estimate: c ? c.count : null, unit: e.unit, qty_status: 'to_confirm',
      basis: c ? `counted on the drawing: ${c.basis}` : 'the legend shows this device type; its count could not be read from the drawing',
      confidence: 'low',
    });
  }
  if (nt.cable) boq.push({ section: 'Fire alarm — cable', type: 'fire_rated_cable', description: `Fire-rated cable, ${nt.cable}`, item: nt.cable, qty: null, unit: 'm', basis: `named in the drawing notes; ${tb.scale && /NTS/.test(tb.scale) ? 'the sheet is not to scale, so no length can be measured from it' : 'no length is stated'}`, confidence: 'low' });
  if (nt.isolators) {
    const onTypes = DEVICE_TYPES.filter((d) => /manual_call_point|sounder|beacon/.test(d.type)).map((d) => d.type);
    const n = Object.entries(counts).filter(([t]) => onTypes.includes(t)).reduce((s, [, v]) => s + v.count, 0);
    boq.push({ section: 'Fire alarm — devices (from the notes)', type: 'loop_isolator', description: 'Loop isolators (fitted to break glass units and sounders)', item: 'Loop isolators', qty: null, estimate: n || null, unit: 'nos', qty_status: 'to_confirm', basis: `drawing note: "${nt.isolators}"; one per break glass unit and sounder`, confidence: 'low' });
  }
  if (!lg.length) missing.push(vocab.device.length ? 'No legend could be read, so device types are not listed.' : 'The drawing\'s legend was not read into device types this time, so device types are not listed; describe them, or they are asked.');
  if (tb.scale && /NTS/.test(tb.scale)) missing.push('The sheet is marked not to scale: cable and containment lengths cannot be measured from it.');
  if (lg.length) missing.push('Per-type device counts are our estimate from the drawing and are confirmed with the customer or verified by the supplier; nothing here is a certified take-off.');
  const identity = [tb.client, ...tb.site, tb.project, tb.company, tb.drawing_ref, tb.drawn_by].filter((s): s is string => !!s && s.length >= 2);
  return { title_block: tb, legend: lg, notes: nt, rooms: rm, loops, sound_levels_dba: db, fap_location: fapLocation(lines, W, rm), identity, boq, missing_info: missing, category: lg.length || loops.length ? 'safety' : '' };
}
