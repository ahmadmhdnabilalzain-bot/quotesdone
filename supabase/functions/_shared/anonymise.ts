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
import { drawingLocation } from './drawing_location.ts';
import { tradeWord } from './drawing_vocabulary.ts';
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
// A surveyor named on the sheet ("Survey by ZZ Demo Surveyors", B1's scale-bar note, 13 Nov 2026): a firm word, and
// "by <Name>" after a survey / prepared / issued verb is a party.
const SURVEY_FIRM = /\bsurveyors?\b|\bsurveying\b|\b(?:survey(?:ed)?|prepared|issued|designed|drawn)\s+by\s+\S/i;
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
// A tilted run is never on another run's line (13 Nov 2026): the 28-degree watermark's box is 42% of the sheet tall, so
// every label within 0.6 of THAT height counted it as its neighbour and boxed the watermark's whole bounding box.
const sameLine = (p: PdfPage, r: TextRun) => p.runs.filter((o) => (o === r || !o.quad) && Math.abs((o.y + o.h) - (r.y + r.h)) <= Math.max(o.h, r.h) * 0.6);
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

// ── 13 Nov 2026 (sales_engineer; anonymity audit B, findings L2, L3, L4) ─────────────────────────────────────────
// L4 A TILTED RUN IS COVERED ALONG ITS OWN LINE. The box around a run is the axis-aligned box of its glyph quad; for the
// auditor's 28-degree watermark that was 66% x 42% of the sheet, and it blacked out Section A-A, the site plan and the
// scale bar. A run with a `quad` (pdf_text_positions: drawn at an angle that is not a quarter turn) is now covered by a
// STAIRCASE of small boxes along its baseline, each the bounding box of one slice of the quad: the same text is under
// solid black, and the sheet around it is not.
const SLICES = 12;
export function runCover(r: TextRun, pad = 0.01): Box[] {
  if (!r.quad || r.quad.length !== 4) return [clamp({ x: r.x - pad, y: r.y - pad, w: r.w * 1.25 + 2 * pad, h: r.h + 2 * pad })];
  const [p0, p1, p2, p3] = r.quad;
  // The run's estimated width (0.6 em a glyph) is padded by a quarter, as around() pads it.
  const L = (a: [number, number], b: [number, number], t: number): [number, number] => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
  const out: Box[] = [];
  const p = pad / 2;
  // Slices about half a text height long: each slice's box overhangs the quad by about its height x sin(angle).
  const len = Math.hypot(p1[0] - p0[0], p1[1] - p0[1]), ht = Math.hypot(p3[0] - p0[0], p3[1] - p0[1]) || 1e-3;
  const n = Math.max(SLICES, Math.min(160, Math.ceil((len * 1.25) / (ht * 0.5))));
  for (let i = 0; i < n; i++) {
    const t0 = (i / n) * 1.25 - 0.01, t1 = ((i + 1) / n) * 1.25 + 0.01;
    const pts = [L(p0, p1, t0), L(p0, p1, t1), L(p3, p2, t1), L(p3, p2, t0)];
    const xs = pts.map((q) => q[0]), ys = pts.map((q) => q[1]);
    // `slice` marks a staircase box: pdf_vector_redact cuts the tilted run itself, never another run that a slice happens to hold.
    out.push(Object.assign(clamp({ x: Math.min(...xs) - p, y: Math.min(...ys) - p, w: Math.max(...xs) - Math.min(...xs) + 2 * p, h: Math.max(...ys) - Math.min(...ys) + 2 * p }), { slice: true }));
  }
  return out;
}
/** Is this run under the boxes? A tilted run is covered when points across its whole quad all are. */
export function runCovered(bx: Box[], r: TextRun): boolean {
  if (bx.some((b) => covers(b, r))) return true;
  if (!r.quad || r.quad.length !== 4) return false;
  const [p0, p1, , p3] = r.quad;
  for (let i = 0; i <= 20; i++) for (let j = 0; j <= 4; j++) {
    const t = i / 20, u = j / 4;
    const x = p0[0] + (p1[0] - p0[0]) * t + (p3[0] - p0[0]) * u, y = p0[1] + (p1[1] - p0[1]) * t + (p3[1] - p0[1]) * u;
    if (!bx.some((b) => x >= b.x - 1e-6 && x <= b.x + b.w + 1e-6 && y >= b.y - 1e-6 && y <= b.y + b.h + 1e-6)) return false;
  }
  return true;
}
// L2 A KEY PLAN, A LOCATION PLAN OR A MAP IS IDENTITY BY ITS NATURE. Measured on B1: a key-plan raster of 15% of the sheet
// ("Villa 15", "Al Barsha 2 - 23B Street", "Umm Suqeim Rd" and a red pin, all pixels, no text layer) reached a supplier
// readable, because (d) below boxed only logo-sized images. Now the label and the region it names are covered whole:
// the picture under or beside it, else the ruled frame under it, else a fixed share of the sheet under it.
export const MAP_LABEL = /\b(?:KEY\s*PLAN|LOCATION\s*(?:PLAN|MAP)|VICINITY\s*(?:PLAN|MAP)|SITE\s*LOCATION(?:\s*(?:PLAN|MAP))?|LOCALITY\s*(?:PLAN|MAP)|LOCATION\s*SKETCH|AREA\s*MAP)\b|\u0645\u062e\u0637\u0637\s*\u0645\u0641\u062a\u0627\u062d\u064a|\u062e\u0631\u064a\u0637\u0629|\u0627\u0644\u0645\u062e\u0637\u0637\s*\u0627\u0644\u0645\u0641\u062a\u0627\u062d\u064a|\u0645\u0648\u0642\u0639\s*\u0627\u0644\u0645\u0634\u0631\u0648\u0639/i;
/** The region a map label names: the image nearest under (or beside) it, else the ruled frame under it, else null.
 *  NO FALLBACK REGION (13 Nov 2026, independent review item 9): a fixed 25% x 20% under a "KEY PLAN" label with nothing
 *  under it blacked out the POOL in the preview and let the vector file cut the pool outline and its levels. With no
 *  picture or frame found, the label alone is covered and the sheet is HELD (titleBlockBoxes: confidence low). */
export function mapRegion(p: PdfPage, r: TextRun): Box | null {
  const near = (p.images || []).filter((im) => im.x < r.x + Math.max(r.w, 0.05) + 0.02 && im.x + im.w > r.x - 0.02 && im.y >= r.y - 0.25 && im.y <= r.y + r.h + 0.08);
  if (near.length) {
    const im = near.sort((a, b) => Math.abs(a.y - r.y) - Math.abs(b.y - r.y))[0];
    return clamp({ x: Math.min(im.x, r.x) - 0.005, y: Math.min(im.y, r.y) - 0.005, w: Math.max(im.x + im.w, r.x + r.w * 1.25) - Math.min(im.x, r.x) + 0.01, h: Math.max(im.y + im.h, r.y + r.h) - Math.min(im.y, r.y) + 0.01 });
  }
  const hs = (p.lines || []).filter((l) => l.y2 - l.y1 < 1e-3 && l.y1 >= r.y + r.h - 0.002 && l.y1 <= r.y + r.h + 0.05 && Math.abs(l.x1 - r.x) <= 0.03);
  if (hs.length) {
    const top = hs.sort((a, b) => a.y1 - b.y1)[0];
    const bot = (p.lines || []).filter((l) => l.y2 - l.y1 < 1e-3 && l.y1 > top.y1 + 0.01 && Math.abs(l.x1 - top.x1) <= 0.01 && Math.abs(l.x2 - top.x2) <= 0.01).sort((a, b) => a.y1 - b.y1)[0];
    if (bot) {
      const fr = clamp({ x: Math.min(r.x, top.x1) - 0.005, y: r.y - 0.005, w: Math.max(top.x2, r.x + r.w * 1.25) - Math.min(r.x, top.x1) + 0.01, h: bot.y1 - r.y + 0.01 });
      // A frame that holds the drawing's own measurements is the DRAWING, not a map (review item 9: "KEY PLAN" printed
      // above the pool plan took the pool's outline as its frame): levels, dimensions or a scale inside it - no region.
      const measured = p.runs.some((o) => o !== r && centreIn(fr, o) && /\b(?:FFL|SSL|FGL|NGL|TOC|TOW|IL|WL|DEPTH|THK|DIA|SCALE)\b|(?<![\d.])\d{3,5}(?![\d.])\s*(?:MM)?$/i.test(o.text.trim()));
      if (!measured && fr.w * fr.h <= 0.2) return fr;
    }
  }
  return null;
}
/** Words of a phrase printed in the title strip that are not a label, an initial or a word of the trade. */
const STRIP_WORD_STOP = new Set(['owner', 'client', 'consultant', 'contractor', 'private', 'public', 'checked', 'approved', 'drawn', 'designed',
  'reviewed', 'prepared', 'title', 'permit', 'number', 'scale', 'date', 'revision', 'sheet', 'signature', 'makani', 'plot', 'issued', 'tender',
  'licence', 'license', 'fax', 'tel', 'phone', 'mobile', 'email', 'office', 'main', 'consultants', 'contracting']);
/** An image this large is the drawing itself (a scanned sheet in a PDF wrapper): the page goes the scan route. */
export const SHEET_IMAGE = 0.5;

export function titleBlockBoxes(pages: PdfPage[], seeds: string[]): { boxes: Box[][]; confidence: 'low' | 'medium'; residual: string[]; strips: (Box | null)[]; regions: Box[][]; setSeeds: string[] } {
  let low = !seeds.length || !pages.length;
  const residual: string[] = [];
  const strips = pages.map((p) => (p.runs.length ? titleStrip(p) : null));
  // Seeds from every sheet's strip apply to the whole set: the project name is the same on every sheet.
  const setSeeds = [...new Set(pages.flatMap((p, i) => (strips[i] ? stripSeeds(p, strips[i]!) : [])))];
  // L3 (13 Nov 2026): the strip's phrases are ALSO split into their words, as scan_redact does (seedTerms({extra})).
  // Whole phrases only ("villa 15 al barsha 2 dubai") missed the site plan's "AL BARSHA 2" and the scale-bar note
  // "(Survey by ZZ Demo Surveyors, Al Barsha 2)" whenever the file name did not happen to say "Barsha". A word that is
  // a label or a word of the trade ("owner", "swimming") is not a seed: it would black out the drawing's own notes.
  const setWords = seedTerms({ extra: setSeeds }).filter((w) => !w.includes(' ') && !/^\d+$/.test(w) && !tradeWord(w) && !STRIP_WORD_STOP.has(w));
  const allSeeds = [...new Set([...seeds, ...setSeeds, ...setWords])].sort((a, b) => b.length - a.length);
  // A label written as its own run ("LOCATION:" with "GREELEY, CO" as the next run, measured on the
  // mechanical cover sheet's design-data table) never matched LABEL_TEST, which wants the value on the
  // same run. Either shape now takes the values to its right.
  const isLabel = (t: string) => LABEL_TEST.test(t) || LABEL_ONLY.test(t);
  // A place below the emirate is identity wherever it stands (ruling 1683): "AL BARSHA 2", "STREET 23B", "VILLA 15".
  const hitsOutside = (t: string) => residualScan(t, allSeeds).length > 0 || isLabel(t) || FIRM.test(t) || SURVEY_FIRM.test(t) || !!drawingLocation(t);
  // REGIONS: the boxes whose GRAPHICS are identity too (the strip, a label-cluster block, a revision table, a key plan,
  // a picture). pdf_vector_redact cuts paths and images only there; a run's own box (a staircase along a watermark)
  // removes the run, never the linework under it.
  const regions: Box[][] = pages.map(() => []);
  const boxes = pages.map((p, pi) => {
    // No text at all (a scan): nothing here can see it.
    if (!p.runs.length) { low = true; return []; }
    const bx: Box[] = [];
    const strip = strips[pi];
    if (strip) { bx.push(clamp({ ...strip })); regions[pi].push(clamp({ ...strip })); }
    const outside = strip ? p.runs.filter((r) => !centreIn(strip, r)) : p.runs;
    // (a) every identifying run outside the strip; a label also takes the values to its right on the same line.
    const hit = outside.filter((r) => hitsOutside(r.text) || (!strip && TB_LABEL.test(r.text) && isEvidence(r.text)));
    for (const r of hit) { if (isLabel(r.text)) bx.push(around(sameLine(p, r).filter((o) => o.x >= r.x && o.x <= r.x + r.w + 0.25))); else bx.push(...runCover(r, 0.01)); }
    // (a2) a key plan, a location plan, a vicinity map: the label and the region it names (L2).
    for (const r of outside) if (MAP_LABEL.test(r.text) && r.text.replace(/\s+/g, ' ').trim().length <= 40) { const m = mapRegion(p, r); bx.push(clamp({ x: r.x - 0.005, y: r.y - 0.005, w: r.w * 1.25 + 0.01, h: r.h + 0.01 })); if (m) { bx.push(m); regions[pi].push(m); } else { low = true; residual.push(`page ${pi + 1}: a map label with no picture or frame under it`); } }
    // (b) no strip found: the older label cluster (>= 2 title-block labels hard against the right or bottom edge).
    let block = !!strip;
    if (!strip) {
      const labels = p.runs.filter((r) => TB_LABEL.test(r.text));
      for (const [zone, edge] of [[labels.filter((r) => r.x >= 0.6), 'right'], [labels.filter((r) => r.y + r.h >= 0.75), 'bottom']] as const) {
        if (zone.length < 2) continue;
        const y1 = Math.min(...zone.map((r) => r.y)), y2 = Math.max(...zone.map((r) => r.y + r.h)), x1 = Math.min(...zone.map((r) => r.x));
        const rows = p.runs.filter((r) => r.y + r.h / 2 >= y1 - M && r.y + r.h / 2 <= y2 + M && r.x + r.w >= x1 - M);
        const b = around(rows, M * 1.5);
        const cb = clamp(edge === 'right' ? { ...b, w: 1 - b.x } : { ...b, h: 1 - b.y });
        bx.push(cb); regions[pi].push(cb);
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
      const rb = clamp({ x: x1 - M, y: y1 - M, w: x2 - x1 + 2 * M, h: y2 - y1 + 2 * M });
      bx.push(rb); regions[pi].push(rb);
      block = true;
    }
    // (d) images outside the strip (a firm's logo, a stamp, a key-plan screenshot placed on the drawing).
    let sheetImage = false;
    for (const im of p.images || []) {
      // WHOLLY inside the strip is covered by it; one laid across the strip's edge gets its own box (3 Nov 2026: a
      // logo at 0.80..0.90 against a strip from 0.816 kept its left edge in the preview, and its whole self in the PDF).
      if (strip && covers(strip, im)) continue;
      // L2 (13 Nov 2026): EVERY picture outside the strip is covered, not only a logo-sized one: a map screenshot, a
      // photo of the plot, a pasted location sketch carry their words in pixels no rule here can read. Only a picture
      // that is the drawing itself (SHEET_IMAGE of the page, a scanned sheet) is not boxed: the page is then held below
      // and goes the scan route, where OCR reads it.
      if (im.w * im.h >= SHEET_IMAGE) { sheetImage = true; continue; }
      const ib = clamp({ x: im.x - 0.005, y: im.y - 0.005, w: im.w + 0.01, h: im.h + 0.01 });
      bx.push(ib); regions[pi].push(ib);
    }
    if (sheetImage) low = true;
    // TEXT NO RULE CAN READ (review item 2): a font this reader cannot decode (Type3, no ToUnicode), or rows of small
    // filled shapes outside the strip (outlined text, a pixel font, a QR code). Whatever they say, code cannot prove it
    // is not identity: the sheet is not confident, so no file is cut from it and its preview goes to the models.
    if (p.undecodable) { low = true; residual.push(`page ${pi + 1}: ${p.undecodable} run(s) in a font with no readable text`); }
    const shapes = (p.glyphRows || []).filter((g) => !strip || !centreIn(strip, g));
    if (shapes.length) { low = true; residual.push(`page ${pi + 1}: ${shapes.length} row(s) of text drawn as shapes`); }
    // A sheet with text but no findable title block most likely has it as vectors or in an image.
    if (!block) low = true;
    // RESIDUAL: every run not covered by a box is scanned again, with the strip's seeds.
    for (const r of p.runs) {
      if (runCovered(bx, r)) continue;
      if (hitsOutside(r.text) || contactHit(r.text)) residual.push(`page ${pi + 1}: ${r.text.slice(0, 60)}`);
    }
    return bx;
  });
  // setSeeds: what every sheet's strip names, for a caller that sends one page at a time (review item 14: drawing_redact's
  // code floor read one page alone, so a name on sheet 2 printed only in sheet 1's strip was the model's alone). The
  // caller passes them on as seed_terms.
  return { boxes, confidence: low || residual.length ? 'low' : 'medium', residual, strips, regions, setSeeds: [...setSeeds, ...setWords] };
}


/** A file name that carries nothing of the customer's: rfq-<8 hex of the id>-drawing-01.jpg */
export function neutralName(ext: string, id: string, n = 1): string {
  let h = 0x811c9dc5; // FNV-1a: the id is hashed, never echoed
  for (const c of String(id ?? '')) h = Math.imul(h ^ c.codePointAt(0)!, 0x01000193) >>> 0;
  const e = String(ext || '').toLowerCase().replace(/^\./, '').replace(/[^a-z0-9]/g, '').slice(0, 5) || 'bin';
  return `rfq-${h.toString(16).padStart(8, '0')}-drawing-${String(n).padStart(2, '0')}.${e}`;
}
