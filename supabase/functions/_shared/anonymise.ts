// anonymise — the deterministic gate every drawing and BOQ passes before a supplier sees it (14 Sep 2026).
//
// WHY. The founder: "any info related to the client name / project details contact info or anything
// that could let the supplier know who is the customer need to be removed before sharing the
// drawings" and "the same applies for boq's". Every model route is held, so the gate is rules only.
//
// WHAT IT REMOVES.
//  * SEED TERMS — what we know about THIS customer (customers.full_name/email/phone, projects.name,
//    the address, plot, Makani, anything extra): full values plus meaningful tokens (>= 4 chars, not
//    generic words like villa/dubai/llc, not BOQ vocabulary like tile/marble), matched case-,
//    diacritic- and Arabic-letter-insensitively (alef variants, taa marbuta, tashkeel). Phone,
//    Makani and plot seeds are matched as DIGITS across any separators.
//  * GENERIC IDENTIFIERS any customer's document carries: emails, URLs, UAE phones, company-suffix
//    names (all via scrubIdentity in drawing_boq, reused not copied), plot/parcel numbers, Makani,
//    P.O. Box, villa/building/street numbers and named roads, DEWA/permit/project/drawing numbers,
//    and the value after a person/party label (Client:, Owner:, Drawn by:, المالك:, العميل: ...).
//  * On PDF pages: boxes (normalised 0..1, drawing_redact manual_boxes shape) over every run that
//    hits the above, over the title block (a cluster of title-block labels on the right or bottom
//    edge, grown to the sheet edge so logos, stamps and QR codes inside it are covered) and over
//    revision tables.
//
// FAIL CLOSED. Redaction matches seeds on word boundaries; the residual scan matches them as bare
// substrings, so "AlMansouriGroup" survives redaction but is caught by the scan and the BOQ is HELD.
// No seeds at all also holds: we cannot prove the customer's name is absent without knowing it.
//
// WHAT IT NEVER DOES, and cannot: read pixels. A page with no text layer (a scan) or a title block
// drawn as vectors (pdf_text_positions follows Form XObjects since 21 Sep 2026, so a CAD block is read)
// yields confidence 'low' — the caller must HOLD. Logos outside the title strip are boxed only when
// logo-sized; a drawing-sized raster is not read here (see titleBlockBoxes (d)). Logos outside a detected title block,
// handwriting, and identity in file metadata or CAD layers are not detected. Glyph widths are
// estimated (0.6 em), so boxes are padded. Seed tokens under 4 characters ("Ali") are only removed
// as part of the full value. It never deletes BOQ quantities, units or ordinary trade words.
import type { PdfPage, TextRun } from './pdf_text_positions.ts';
import { scrubIdentity } from '../drawing_boq/boq_from_text.ts';

import { LICENCE_NO, TRN_BARE, TRN_LABELLED } from './identity_numbers.ts';
import { CONTACT_PATTERNS } from './identity_contacts.ts';
import { IBAN, identityShapesIn, LICENCE_SHORT, PHONE_UAE_INTL, PHONE_UAE_NATIONAL, PO_BOX } from './identity_text.ts';
export type Box = { x: number; y: number; w: number; h: number };
export type SeedSource = { name?: string; company?: string; email?: string; phone?: string; project?: string; address?: string; plot?: string; makani?: string; extra?: string[] };

const R = '█';

// ── normalisation: one output char per input char position, so matches map back to the original ──
const DROP = /[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED\u0640\u200C-\u200F]/; // tashkeel, tatweel, joiners
function normChar(ch: string): string {
  if (DROP.test(ch)) return '';
  let c = ch.normalize('NFKD').replace(/\p{M}/gu, '').toLowerCase(); // أ إ آ -> ا via NFKD
  c = c.replace(/ٱ/g, 'ا').replace(/ة/g, 'ه').replace(/ى/g, 'ي')
    .replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x660)).replace(/[۰-۹]/g, (d) => String(d.charCodeAt(0) - 0x6f0));
  return c.replace(/[^\p{L}\p{N}@]/gu, ' ');
}
function normMap(s: string): { n: string; idx: number[] } {
  let n = ''; const idx: number[] = [];
  for (let i = 0; i < s.length;) {
    const ch = String.fromCodePoint(s.codePointAt(i)!);
    for (const k of normChar(ch)) {
      if (k === ' ' && (n === '' || n.endsWith(' '))) continue;
      n += k; for (let j = 0; j < k.length; j++) idx.push(i);
    }
    i += ch.length;
  }
  return { n, idx };
}
export const norm = (s: string) => normMap(String(s ?? '')).n.trim();

// Generic words and BOQ vocabulary never become a seed on their own (a company called "Marble Tech"
// must not erase every marble line); the full phrase "marble tech" still does.
// 22 SEP 2026 — DRAWING VOCABULARY. The customer's FILE NAME is a seed (customer_api passes it as
// `extra`), and a file name is mostly drawing words. MEASURED on the real Weld mechanical set with the
// name "M-101 Mechanical Drawings Rev2.pdf": "mechanical" and "drawings" became seeds and 111 runs of
// drawing content outside the title block were blacked out on the cover sheet (18.1% of the sheet,
// against 7 runs / 8.6% under a neutral name) — the drawing index, the design data, the legend and
// every general note that says "drawings". A ZZ DEMO customer's "demo" did the same to every
// "DEMO AND REMOVE" demolition note. These words name what is drawn, never who it is for.
const GENERIC = new Set(norm(`villa villas project projects residence residential building buildings tower towers house home
  office company group trading contracting contractor contractors consult consulting consultant consultants consultancy engineering
  engineer engineers architect architects interior interiors design designs general services solutions systems works
  supply supplies technical tech llc fzco fzllc establishment dubai sharjah ajman abudhabi abu dhabi fujairah umm quwain
  khaimah emirates emirate uae united arab street road avenue phase block unit floor ground first plot area community city
  apartment flat plaza mall centre center park garden gardens heights view views sheikh mister madam
  tile tiles porcelain ceramic marble granite stone wall walls ceiling paint door doors window windows glass steel wood
  timber gypsum kitchen bath bathroom room rooms living bedroom concrete aluminium aluminum light lights lighting
  electrical plumbing water pool
  drawing drawings plan plans layout layouts mechanical hvac permit tender issued construction revision revised
  final draft sheet sheets section sections elevation elevations detail details schedule schedules notes spec specs
  specification specifications diagram diagrams riser scan scanned copy architectural structural civil landscape
  fire fighting alarm drainage sanitary ductwork demo demolition existing proposed typical level basement roof
  mezzanine page document documents file files photo image proposal quotation tender package bill quantities
  فيلا مشروع دبي الشارقة عجمان ابوظبي الامارات امارات شركة مؤسسة شارع منطقة مبنى برج السيد السيدة المهندس الشيخ`).split(' '));
const PUBLIC_MAIL = /^(?:gmail|googlemail|hotmail|outlook|live|yahoo|icloud|me|msn|aol|proton|protonmail)$/;
const isArabic = (t: string) => /[؀-ۿ]/.test(t);

export function seedTerms(src: SeedSource): string[] {
  const out = new Set<string>();
  const tok = (t: string) => {
    if (/^\d+$/.test(t)) { if (t.length >= 5) out.add(t); return; }
    if (t.length >= 4 && !GENERIC.has(t)) out.add(t);
    if (isArabic(t) && t.startsWith('ال') && t.length >= 6 && !GENERIC.has(t.slice(2))) out.add(t.slice(2));
  };
  const text = (v?: string) => {
    const n = norm(v || ''); if (!n) return;
    if (/^[\d ]+$/.test(n)) { tok(n.replace(/ /g, '')); return; }
    if (n.length >= 4 && !GENERIC.has(n)) out.add(n);
    n.split(' ').forEach(tok);
  };
  text(src.name); text(src.company); text(src.project); text(src.address); text(src.plot); text(src.makani);
  (src.extra || []).forEach((e) => text(e));
  const email = String(src.email || '').trim().toLowerCase();
  if (email.includes('@')) {
    const [local, domain] = email.split('@');
    out.add(norm(email)); text(local);
    const label = domain.split('.')[0];
    if (label && !PUBLIC_MAIL.test(label)) text(label);
  }
  const d = norm(src.phone || '').replace(/\D/g, '').replace(/^(?:00971|971|0)/, '');
  if (d.length >= 7) out.add(d); // national number; matched inside any +971 / 00971 / 0 format
  return [...out].sort((a, b) => b.length - a.length);
}

// ── finding seeds in text ───────────────────────────────────────────────────────────────────────
type Range = { s: number; e: number; what: string };
const DIGSEQ = /[+\d٠-٩۰-۹][\d٠-٩۰-۹\s\-().\/]{3,}[\d٠-٩۰-۹]/g;
const isWord = (c: string | undefined) => !!c && /[\p{L}\p{N}]/u.test(c);

function seedRanges(s: string, seeds: string[], loose: boolean): Range[] {
  const out: Range[] = [];
  const { n, idx } = normMap(s);
  const endOf = (p: number) => { let e = idx[p] + (s.codePointAt(idx[p])! > 0xffff ? 2 : 1); while (e < s.length && normChar(s[e]) === '') e++; return e; };
  for (const seed of seeds) {
    if (!seed) continue;
    if (/^\d+$/.test(seed)) {
      for (const m of s.matchAll(DIGSEQ)) if (norm(m[0]).replace(/\D/g, '').includes(seed)) out.push({ s: m.index!, e: m.index! + m[0].length, what: seed });
      continue;
    }
    for (let p = n.indexOf(seed); p >= 0; p = n.indexOf(seed, p + 1)) {
      const q = p + seed.length;
      // Arabic attaches prefixes (ال، و، ب، ل) to the name, so only the right edge is a boundary there.
      if (!loose && ((!isArabic(seed) && isWord(n[p - 1])) || isWord(n[q]))) continue;
      out.push({ s: idx[p], e: endOf(q - 1), what: seed });
    }
  }
  return out;
}

// ── generic identifiers (named, so a residual says what it found) ──────────────────────────────
const GENERIC_ID: [string, RegExp][] = [
  ['plot', /\b(?:plot|parcel)(?:\s*(?:no|number|#)\.?)?\s*[:#.]?\s*[A-Z]?[\d٠-٩][\d٠-٩\-\/]*/gi],
  ['plot_ar', /(?:رقم\s*)?(?:ال)?قطع[ةه](?:\s*(?:رقم|الأرض|الارض))*\s*[:：]?\s*[\d٠-٩][\d٠-٩\-\/]*/g],
  ['makani', /(?:\bmakani\b|مكاني)[^\d٠-٩\n]{0,12}[\d٠-٩]{5}\s?[\d٠-٩]{5}|\b\d{5}\s?\d{5}\b/gi],
  ['po_box', /\bP\.?\s?O\.?\s?Box\s*[:#.]?\s*\d+|\bPOB\s*[:#.]?\s*\d+|ص\s*\.?\s*ب\s*\.?\s*[:：]?\s*[\d٠-٩]+/gi],
  ['premises_no', /\b(?:villa|building|bldg|street|road|house|apartment|apt|flat)\s*(?:no\.?|number|#)?\s*[:.]?\s*\d+[A-Z]?\b/gi],
  ['named_road', /\b(?:[A-Z][A-Za-z'-]+\s){1,3}(?:Street|Road|Rd\.?|St\.)(?=\W|$)/g],
  ['street_ar', /شارع\s+\S+(?:\s+\S+)?/g],
  ['reference_no', /\b(?:(?:project|drawing|dwg|job|file|contract|tender|ref(?:erence)?|premises?|account|plan)\s*(?:no\.?|number|#|ref\.?)|DEWA(?:\s*(?:no\.?|number|#|account|premises?))?|permit(?:\s*(?:no\.?|number|#))?|dwg\.?)\s*[:.#]?\s*(?=[\w\-\/.]*\d)[A-Z0-9][\w\-\/.]*/gi],
  ['reference_no_ar', /رقم\s*(?:المشروع|المخطط|اللوحة|اللوحه|الرخصة|الرخصه|التصريح)\s*[:：]?\s*\S+/g],
  // Non-UAE contacts (identity_contacts.ts, 21 Sep 2026): US phones, bare web hosts, street addresses, city/ZIP.
  ...CONTACT_PATTERNS,
  // Residual-only mirrors of what scrubIdentity removes, so the scan can prove they are gone.
  ['email', /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g],
  ['url', /\b(?:https?:\/\/|www\.)\S+/gi],
  ['phone', /(?:\+?971|00971|\b0)[\s-]?\d{1,2}[\s-]?\d{3}[\s-]?\d{4}\b/g],
  ['trn', TRN_LABELLED], ['trn_bare', TRN_BARE], ['licence_no', LICENCE_NO],
  // 3 Nov 2026 (identity_never_leaks_before_reveal.mjs): an Arabic-Indic "٠٤ ٠٠٠ ٠٠١٤" in a drawing's header stayed in the
  // anonymised vector PDF, and "TL 614867" / "(04) 000 0019" in the anonymised DXF. A residual of these now boxes or holds.
  ['phone_uae_intl', PHONE_UAE_INTL], ['phone_uae_national', PHONE_UAE_NATIONAL], ['iban', IBAN], ['po_box_any', PO_BOX], ['licence_short', LICENCE_SHORT],
];
const REDACT_ONLY_BEFORE_SCRUB = GENERIC_ID.slice(0, GENERIC_ID.findIndex(([n]) => n === 'email'));

// A person or party named after a label: the rest of the line is the value.
const LABEL_LINE = /(\b(?:client|owner|employer|customer|consultant|contractor|architect|engineer|developer|project\s*(?:name|title)?|location|site\s*address|address|attn|attention|contact)\s*[:：]|\b(?:drawn|checked|approved|designed|prepared|reviewed)(?:\s+by)?\s*[:：]|\b(?:drawn|checked|approved|designed|prepared|reviewed)\s+by\b|(?:المالك|العميل|الاستشاري|المقاول|المشروع|اسم\s*المشروع|الموقع|العنوان|المصمم|رسم\s*بواسطة|تدقيق|اعتماد)\s*[:：])[^\n]*\S/gi;
const LABEL_TEST = new RegExp(LABEL_LINE.source, 'i');

function paint(s: string, ranges: Range[]): string {
  if (!ranges.length) return s;
  const rs = [...ranges].sort((a, b) => a.s - b.s);
  let out = '', at = 0;
  for (const r of rs) { if (r.e <= at) continue; out += s.slice(at, Math.max(at, r.s)) + R; at = r.e; }
  return out + s.slice(at);
}

/** The customer's seed terms painted out and nothing else (13 Nov 2026): run before any scrub that rewrites words, so a
 *  project named after its area ("ZZ DEMO Barsha Garden Villa") is matched whole before "Barsha" is reduced to "Dubai". */
export function redactSeeds(s: string, seeds: string[]): string {
  return String(s ?? '').split(/\r?\n/).map((line) => paint(line, seedRanges(line, seeds, false))).join('\n');
}

export function redactText(s: string, seeds: string[]): { text: string; hits: number } {
  let hits = 0;
  const text = String(s ?? '').split(/\r?\n/).map((line) => {
    let t = line.replace(LABEL_LINE, (_m, lab: string) => { hits++; return lab.trim() + ' ' + R; });
    const sr = seedRanges(t, seeds, false); hits += sr.length; t = paint(t, sr);
    for (const [, re] of REDACT_ONLY_BEFORE_SCRUB) t = t.replace(re, () => { hits++; return R; });
    const before = t.replace(/\s{2,}/g, ' ').trim();
    t = scrubIdentity(t);
    if (t !== before) hits++;
    return t;
  }).join('\n');
  return { text, hits };
}

/** What is still identifying: seed terms as bare substrings (looser than redaction) and patterns. */
export function residualScan(text: string, seeds: string[]): string[] {
  const s = String(text ?? '');
  const found = new Set(seedRanges(s, seeds, true).map((r) => 'seed:' + r.what));
  for (const [name, re] of GENERIC_ID) if (new RegExp(re.source, re.flags.replace('g', '')).test(s)) found.add('pattern:' + name);
  // 3 Nov 2026 (second review of #1838): the residual read the shared list's NUMBERS only, so a page left with "Best
  // Regards Ahmed Khan", "شركة النور الذهبية" or "alnoor.store" was not held. Every shape the scrubbers remove is read
  // here through the same validator, so a residual never holds a page for "Approved by MEP Consultants".
  for (const name of identityShapesIn(s)) found.add('pattern:' + name);
  return [...found];
}

export function redactBoq<T>(boq: T, seeds: string[]): { boq: T; held: boolean; reasons: string[] } {
  const strings: string[] = [];
  const walk = (v: unknown): unknown => {
    if (typeof v === 'string') { const r = redactText(v, seeds).text; strings.push(r); return r; }
    if (Array.isArray(v)) return v.map(walk);
    if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v as Record<string, unknown>).map(([k, x]) => [k, walk(x)]));
    return v;
  };
  const out = walk(boq) as T;
  const reasons = [...new Set(strings.flatMap((x) => residualScan(x, seeds)))];
  if (!seeds.length) reasons.push('no_seed_terms: the customer is unknown, so their name cannot be proved absent');
  return { boq: out, held: reasons.length > 0, reasons };
}

// ── PDF pages ───────────────────────────────────────────────────────────────────────────────────
// 21 SEP 2026 (founder instruction 580: "He's able to remove any contact details or anything that would
// refer to the project details"). MEASURED on two real US bid sets (13 sheets, every one /Rotate 270):
// every page was HELD — a rotated page returned low confidence here — so a supplier received no drawing
// at all; and had they not been rotated, the labels below would have boxed 11 and 18 runs per sheet,
// mostly general-note text ("…ON THIS PROJECT"), and none of the real identity (a US phone, a bare web
// host, a street address, the project name printed without a "Project:" label, the engineer's stamp).
// What changed, and why each piece exists:
//  * Coordinates are in the display frame now (pdf_text_positions), so a rotated page is boxed like any
//    other instead of held.
//  * THE TITLE STRIP (titleStrip). CAD sheets put the title block in a strip along the right or bottom
//    edge, drawn inside a long border line. The strip is found from strong identity evidence (phones,
//    web hosts, emails, addresses, "PROJECT NO", "DRAWN BY", "REVISIONS", "SEAL") and snapped outward to
//    the nearest long border line; the WHOLE strip is covered, so a logo, a stamp or a project name with
//    no label inside it goes with it. It never grows past 35% of the sheet — beyond that it is not a
//    title block and the page is held instead.
//  * SEEDS FROM THE STRIP. Names printed in the strip (the project name, the firm) are looked for on the
//    rest of the sheet, so the same name in a general note is boxed too. A view title ("WASTE AND VENT
//    PLAN"), a date, a sheet number or a scale is drawing content and is never a seed.
//  * Images outside the strip that are logo-sized are covered; drawing-sized rasters are left alone and
//    reported (their pixels are not read here — the portal's OCR proof on the output is what checks them).
//  * Outside the strip only CONTACT-shaped text is boxed (patterns, seeds, "Client:" labels): a keynote
//    that says "COORDINATE WITH ARCHITECT" is scope a supplier must read, not an identity.
const TB_LABEL = /\b(?:client|owner|employer|project|consultant|architect|engineer|contractor|developer|drawn|checked|approved|designed|drawing\s*(?:no|title)|dwg|rev|revision|date|sheet|scale|plot|makani|location|address|title|stamp|seal|key\s*plan)\b|المالك|العميل|المشروع|الاستشاري|المقاول|المهندس|رسم|تدقيق|اعتماد|التاريخ|المقياس|اللوحة|اللوحه|قطعة|قطعه|مكاني|الموقع|العنوان|ختم/i;
/** Evidence that a region IS a title block: contact shapes and the labels only a title block carries. */
const TB_STRONG = /\b(?:project\s*(?:no|number|#)|job\s*(?:no|number|#)|drawn\s*by|checked\s*by|approved\s*by|designed\s*by|revisions?|seal|licen[cs]e|sheet\s*(?:no|number|title))\b|رقم\s*المشروع|رسم\s*بواسطة|المالك|العميل|الاستشاري/i;
// Company suffixes that name a firm on their own. "Architect", "Consultants", "Contracting" are left to
// the strip: outside it they are usually a keynote talking about a trade ("PROVIDED BY ARCHITECT").
const FIRM = /\b[\w&.' -]{2,40}\s(?:L\.?L\.?C|FZ-?LLC|FZE|FZCO|Inc\.?|Corp\.?|Ltd\.?|Establishment|Est\.)(?=\W|$)|شركة|مؤسسة|ذ\.م\.م/i;
// What makes a strip text DRAWING content: the name of a view or of the sheet, or its issue status. A
// discipline word alone does not ("DEMO" is in a project called "ZZ DEMO CRIME LAB", a "FLOOR" can be in
// a building's name), so only the words that name a drawing are here.
const VIEW_WORDS = /\b(?:PLANS?|SCHEDULES?|DETAILS?|DIAGRAMS?|SECTIONS?|ELEVATIONS?|LEGEND|NOTES|INDEX|SPECIFICATIONS?|ISSUED\s+FOR|PERMIT\s+SET|BID\s+SET|SCALE|SHEET|REVISIONS?|NORTH)\b/i;
const M = 0.02; // margin, normalised
const clamp = (b: Box): Box => { const x = Math.max(0, b.x), y = Math.max(0, b.y); return { x, y, w: Math.max(0, Math.min(1, b.x + b.w) - x), h: Math.max(0, Math.min(1, b.y + b.h) - y) }; };
const around = (rs: TextRun[], pad = M): Box => {
  const x1 = Math.min(...rs.map((r) => r.x)), y1 = Math.min(...rs.map((r) => r.y));
  const x2 = Math.max(...rs.map((r) => r.x + r.w * 1.25)), y2 = Math.max(...rs.map((r) => r.y + r.h));
  return clamp({ x: x1 - pad, y: y1 - pad, w: x2 - x1 + 2 * pad, h: y2 - y1 + 2 * pad });
};
const sameLine = (p: PdfPage, r: TextRun) => p.runs.filter((o) => Math.abs((o.y + o.h) - (r.y + r.h)) <= Math.max(o.h, r.h) * 0.6);
const covers = (b: Box, r: { x: number; y: number; w: number; h: number }) => r.x >= b.x - 1e-6 && r.y >= b.y - 1e-6 && r.x + r.w <= b.x + b.w + 1e-6 && r.y + r.h <= b.y + b.h + 1e-6;
const centreIn = (b: Box, r: { x: number; y: number; w: number; h: number }) => r.x + r.w / 2 >= b.x && r.x + r.w / 2 <= b.x + b.w && r.y + r.h / 2 >= b.y && r.y + r.h / 2 <= b.y + b.h;
const contactHit = (t: string) => GENERIC_ID.some(([, re]) => new RegExp(re.source, re.flags.replace('g', '')).test(t));
const isEvidence = (t: string) => contactHit(t) || TB_STRONG.test(t) || FIRM.test(t);
export const MAX_STRIP = 0.35;
/** A party / place label standing alone as its own run: "LOCATION:", "CLIENT", "المالك:". */
const LABEL_ONLY = /^\s*(?:client|owner|employer|customer|consultant|contractor|developer|project(?:\s*(?:name|title|location|address))?|location|site(?:\s*address)?|address|attn|attention|contact|(?:drawn|checked|approved|designed|prepared|reviewed)\s*by|المالك|العميل|الاستشاري|المقاول|المشروع|اسم\s*المشروع|الموقع|العنوان)\s*[:：]?\s*$/i;

/** The title-block strip of one sheet (display frame), or null when none is evident. */
export function titleStrip(p: PdfPage): Box | null {
  const ev = p.runs.filter((r) => isEvidence(r.text));
  if (ev.length < 2) return null;
  const lines = p.lines || [];
  const cands: Box[] = [];
  // The evidence hard against the edge, grown inward only while the next piece is within 6% of the
  // last: a spec sheet's note that happens to say "SEAL" or "REVISIONS" in mid-sheet must not drag
  // the strip across the drawing (measured 21 Sep 2026: M0.0 and M0.4 of the mechanical set did).
  const cluster = (vals: number[]) => { const s = [...vals].sort((a, b) => b - a); let edge = s[0]; for (const v of s.slice(1)) { if (edge - v > 0.06) break; edge = v; } return { edge, n: s.filter((v) => v >= edge).length }; };
  const right = ev.filter((r) => r.x >= 0.6);
  const rc = right.length ? cluster(right.map((r) => r.x)) : null;
  if (rc && rc.n >= 2) {
    const xr = rc.edge;
    const border = lines.filter((l) => l.x2 - l.x1 < 1e-3 && l.y2 - l.y1 >= 0.5 && l.x1 <= xr + 0.002 && l.x1 >= xr - 0.1).map((l) => l.x1);
    const x = border.length ? Math.max(...border) - 0.004 : xr - 0.01;
    if (1 - x <= MAX_STRIP) cands.push({ x, y: 0, w: 1 - x, h: 1 });
  }
  const bottom = ev.filter((r) => r.y >= 0.6);
  const bc = bottom.length ? cluster(bottom.map((r) => r.y)) : null;
  if (bc && bc.n >= 2) {
    const yb = bc.edge;
    const border = lines.filter((l) => l.y2 - l.y1 < 1e-3 && l.x2 - l.x1 >= 0.5 && l.y1 <= yb + 0.002 && l.y1 >= yb - 0.1).map((l) => l.y1);
    const y = border.length ? Math.max(...border) - 0.004 : yb - 0.01;
    if (1 - y <= MAX_STRIP) cands.push({ x: 0, y, w: 1, h: 1 - y });
  }
  if (!cands.length) return null;
  // The strip that holds the most evidence; on a tie, the smaller one.
  const score = (b: Box) => ev.filter((r) => centreIn(b, r)).length;
  return cands.sort((a, b) => score(b) - score(a) || a.w * a.h - b.w * b.h)[0];
}

/** Names printed in the strip that are not drawing content: looked for everywhere else on the set. */
export function stripSeeds(p: PdfPage, strip: Box): string[] {
  const out = new Set<string>();
  for (const r of p.runs) {
    if (!centreIn(strip, r)) continue;
    const t = r.text.replace(/\s+/g, ' ').trim();
    if (VIEW_WORDS.test(t) || /^\d{1,2}[\/.-]\d{1,2}[\/.-]\d{2,4}$/.test(t) || /^[A-Z]{1,2}-?\d{1,2}\.\d{1,2}[A-Z]?$/.test(t)) continue;
    const n = norm(t);
    if (/^[\d ]+$/.test(n)) { if (n.replace(/ /g, '').length >= 6) out.add(n.replace(/ /g, '')); continue; }
    if (n.length >= 8 && n.includes(' ') && !GENERIC.has(n)) out.add(n);
  }
  return [...out];
}

export function titleBlockBoxes(pages: PdfPage[], seeds: string[]): { boxes: Box[][]; confidence: 'low' | 'medium'; residual: string[]; strips: (Box | null)[] } {
  let low = !seeds.length || !pages.length;
  const residual: string[] = [];
  const strips = pages.map((p) => (p.runs.length ? titleStrip(p) : null));
  // Seeds from every sheet's strip apply to the whole set: the project name is the same on every sheet.
  const setSeeds = [...new Set(pages.flatMap((p, i) => (strips[i] ? stripSeeds(p, strips[i]!) : [])))];
  const allSeeds = [...seeds, ...setSeeds].sort((a, b) => b.length - a.length);
  // A label written as its own run ("LOCATION:" with "GREELEY, CO" as the next run, measured on the
  // mechanical cover sheet's design-data table) never matched LABEL_TEST, which wants the value on the
  // same run. Either shape now takes the values to its right.
  const isLabel = (t: string) => LABEL_TEST.test(t) || LABEL_ONLY.test(t);
  const hitsOutside = (t: string) => residualScan(t, allSeeds).length > 0 || isLabel(t) || FIRM.test(t);
  const boxes = pages.map((p, pi) => {
    // No text at all (a scan): nothing here can see it.
    if (!p.runs.length) { low = true; return []; }
    const bx: Box[] = [];
    const strip = strips[pi];
    if (strip) bx.push(clamp({ ...strip }));
    const outside = strip ? p.runs.filter((r) => !centreIn(strip, r)) : p.runs;
    // (a) every identifying run outside the strip; a label also takes the values to its right on the same line.
    const hit = outside.filter((r) => hitsOutside(r.text) || (!strip && TB_LABEL.test(r.text) && isEvidence(r.text)));
    for (const r of hit) bx.push(isLabel(r.text) ? around(sameLine(p, r).filter((o) => o.x >= r.x && o.x <= r.x + r.w + 0.25)) : around([r], 0.01));
    // (b) no strip found: the older label cluster (>= 2 title-block labels hard against the right or bottom edge).
    let block = !!strip;
    if (!strip) {
      const labels = p.runs.filter((r) => TB_LABEL.test(r.text));
      for (const [zone, edge] of [[labels.filter((r) => r.x >= 0.6), 'right'], [labels.filter((r) => r.y + r.h >= 0.75), 'bottom']] as const) {
        if (zone.length < 2) continue;
        const y1 = Math.min(...zone.map((r) => r.y)), y2 = Math.max(...zone.map((r) => r.y + r.h)), x1 = Math.min(...zone.map((r) => r.x));
        const rows = p.runs.filter((r) => r.y + r.h / 2 >= y1 - M && r.y + r.h / 2 <= y2 + M && r.x + r.w >= x1 - M);
        const b = around(rows, M * 1.5);
        bx.push(clamp(edge === 'right' ? { ...b, w: 1 - b.x } : { ...b, h: 1 - b.y }));
        block = true;
      }
    }
    // (c) revision tables: a REV header with DATE/DESCRIPTION beside it, grown over the rows stacked on it.
    for (const r of outside) {
      if (!/\brev(?:ision)?\b/i.test(r.text)) continue;
      const line = sameLine(p, r);
      if (!line.some((o) => /\bdate\b|desc/i.test(o.text))) continue;
      let x1 = Math.min(...line.map((o) => o.x)), x2 = Math.max(...line.map((o) => o.x + o.w)), y1 = r.y, y2 = r.y + r.h;
      const col = p.runs.filter((o) => o.x + o.w >= x1 - M && o.x <= x2 + M);
      for (let grew = true; grew;) {
        grew = false;
        for (const o of col) if (o.y <= y2 + 2.5 * r.h && o.y + o.h >= y1 - 2.5 * r.h && (o.y < y1 || o.y + o.h > y2)) { y1 = Math.min(y1, o.y); y2 = Math.max(y2, o.y + o.h); x1 = Math.min(x1, o.x); x2 = Math.max(x2, o.x + o.w); grew = true; }
      }
      bx.push(clamp({ x: x1 - M, y: y1 - M, w: x2 - x1 + 2 * M, h: y2 - y1 + 2 * M }));
      block = true;
    }
    // (d) logo-sized images outside the strip (a firm's logo or a stamp placed on the drawing).
    for (const im of p.images || []) {
      // WHOLLY inside the strip is covered by it; one laid across the strip's edge gets its own box (3 Nov 2026: a
      // logo at 0.80..0.90 against a strip from 0.816 kept its left edge in the preview, and its whole self in the PDF).
      if (strip && covers(strip, im)) continue;
      if (im.w * im.h <= 0.03 && im.px * im.py <= 1_500_000) bx.push(clamp({ x: im.x - 0.005, y: im.y - 0.005, w: im.w + 0.01, h: im.h + 0.01 }));
    }
    // A sheet with text but no findable title block most likely has it as vectors or in an image.
    if (!block) low = true;
    // RESIDUAL: every run not covered by a box is scanned again, with the strip's seeds.
    for (const r of p.runs) {
      if (bx.some((b) => covers(b, r))) continue;
      if (hitsOutside(r.text) || contactHit(r.text)) residual.push(`page ${pi + 1}: ${r.text.slice(0, 60)}`);
    }
    return bx;
  });
  return { boxes, confidence: low || residual.length ? 'low' : 'medium', residual, strips };
}


/** A file name that carries nothing of the customer's: rfq-<8 hex of the id>-drawing-01.jpg */
export function neutralName(ext: string, id: string, n = 1): string {
  let h = 0x811c9dc5; // FNV-1a: the id is hashed, never echoed
  for (const c of String(id ?? '')) h = Math.imul(h ^ c.codePointAt(0)!, 0x01000193) >>> 0;
  const e = String(ext || '').toLowerCase().replace(/^\./, '').replace(/[^a-z0-9]/g, '').slice(0, 5) || 'bin';
  return `rfq-${h.toString(16).padStart(8, '0')}-drawing-${String(n).padStart(2, '0')}.${e}`;
}
