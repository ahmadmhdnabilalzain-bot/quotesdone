// pdf_native/render.ts — the QuotesDone PDF renderer, with no I/O of its own.
//
// WHY IT IS SEPARATE FROM index.ts (14 Sep 2026, agent: ceo). The founder asked for the quotation
// and the comparison report to open as real documents, in English AND Arabic, "and make sure the
// format is fine". Nobody could look at the format without deploying: the drawing code sat inside
// Deno.serve next to the auth check, the brand-bucket fetch and the storage upload, so the only
// way to see a page was to POST production. It is now a pure function — body in, bytes out — and
// the caller supplies the two things that need the network: the brand assets (fetchBytes) and the
// letterhead identity. index.ts keeps auth and storage; the tests and the sample renderer call
// this directly with ZZ DEMO data and never touch a real row.
//
// THE DESIGN (v2, 14 Sep 2026: "the format can be more professional and advanced (very simple now)").
// A document that passes `cover` gets the consulting-deliverable layout: a navy cover band with the
// document title, reference, date, request summary and a key-figures strip; numbered sections; tables
// with a navy head, zebra rows, hairlines and end-aligned figures; status chips; ✓ / ≠ / — markers
// drawn as vectors (no font needs the glyph); a compact scoring matrix; a totals block; and a header
// and footer on EVERY page — legal line, contact line, document-control line and "Page X of Y".
// Everything mirrors for Arabic: the start of a line is the right edge, columns run right to left.
// Documents without `cover` (the brief, the finance reports, signed T&C copies) keep the letterhead
// header they had and gain the same footer.
import { PDFDocument, StandardFonts, rgb, PDFArray, PDFName, PDFString } from 'https://esm.sh/pdf-lib@1.17.1';
// The published fontkit.d.ts has no default export (TS1192) even though the CJS module esm.sh
// serves does. Import the namespace and take .default when it is there.
import * as fontkitMod from 'https://esm.sh/@pdf-lib/fontkit@1.1.1';
// deno-lint-ignore no-explicit-any
const fontkit = ((fontkitMod as any).default ?? fontkitMod) as any;
import bidiFactory from 'https://esm.sh/bidi-js@1.0.3';
import { footerLines, footerLinesAr, FALLBACK, licenceLine, LOCKUP, lockupWidthFor, type DocIdentity } from '../_shared/doc_template.ts';
import { BRAND } from '../_shared/brand.ts';
import { shapeArabic } from './arabic_shape.ts';

export type RenderDeps = {
  /** A brand-bucket object by path, or null when it cannot be had (the renderer degrades). */
  fetchBytes: (path: string) => Promise<Uint8Array | null>;
  identity?: DocIdentity;
};
export type RenderMeta = {
  fonts: { latin: boolean; arabic: boolean }; glyphs_dropped: number; links: number;
  glyph_check: 'fontkit' | 'unavailable'; lockup_trimmed: boolean; letterhead_source: string; pages: number; glyphs_dropped_sample: string;
};
export type RenderResult =
  | { ok: true; bytes: Uint8Array; meta: RenderMeta; title: string }
  | { ok: false; status: number; body: Record<string, unknown> };

const CO_AR = { city: 'دبي، الإمارات العربية المتحدة', signer: 'أحمد الزين', title: 'المؤسس والمدير الإداري' };
// The brand hues come from ONE place, _shared/brand.ts BRAND, the edge-side copy of public.company_brand's
// colour.* rows (the same file mail uses). 22 Sep 2026 (audit finding 6): this file drew navy #0A1720 while the brand table says
// #0C2330, and the brand guide calls an off-table colour a defect. The greys below are neutral tints for
// hairlines, zebra rows and body text on white, not brand colours.
const C = (r: number, g: number, b: number) => rgb(r / 255, g / 255, b / 255);
const H = (hex: string) => C(parseInt(hex.slice(1, 3), 16), parseInt(hex.slice(3, 5), 16), parseInt(hex.slice(5, 7), 16));
const NAVY = H(BRAND.navy), TEAL = H(BRAND.teal), TEAL_L = H(BRAND.tealLight), TEAL_D = H(BRAND.tealDeep), GOLD = H(BRAND.gold);
const INK = C(22, 29, 37), MUT = C(88, 99, 113), HAIR = C(222, 227, 233), ZEBRA = C(246, 248, 250), WHITE = rgb(1, 1, 1), BANDTXT = C(196, 211, 220);
const TINT_T = C(230, 247, 244), TINT_G = C(251, 244, 224), TINT_N = C(237, 241, 245), AMBER_D = C(128, 96, 10), MISS = C(160, 170, 182), LINE = HAIR;
export function isArCode(c: number) { return (c >= 0x600 && c <= 0x6FF) || (c >= 0x750 && c <= 0x77F) || (c >= 0x8A0 && c <= 0x8FF) || (c >= 0xFB50 && c <= 0xFDFF) || (c >= 0xFE70 && c <= 0xFEFF); }
// deno-lint-ignore no-explicit-any
export function hasAr(s: any) { const t = String(s == null ? '' : s); for (const ch of t) { if (isArCode(ch.codePointAt(0) || 0)) return true; } return false; }
// deno-lint-ignore no-explicit-any
const bidi: any = bidiFactory();
const MIRROR: Record<string, string> = { '(': ')', ')': '(', '[': ']', ']': '[', '{': '}', '}': '{', '<': '>', '>': '<' };
// deno-lint-ignore no-explicit-any
function bidiRuns(s: string) { const str = String(s == null ? '' : s); if (!str) return [] as { t: string; rtl: boolean }[]; let levels: any; try { levels = bidi.getEmbeddingLevels(str, 'rtl').levels; } catch (_e) { return [{ t: str, rtl: true }]; } for (let i = 0; i < str.length; i++) { if ('%٪#'.includes(str[i])) { const d = /[0-9]/.test(str[i + 1] || '') ? i + 1 : /[0-9]/.test(str[i - 1] || '') ? i - 1 : -1; if (d >= 0) levels[i] = levels[d]; } } const segs: { t: string; lv: number }[] = []; let st = 0; for (let i = 1; i <= str.length; i++) { if (i === str.length || levels[i] !== levels[st]) { segs.push({ t: str.slice(st, i), lv: levels[st] }); st = i; } } if (!segs.length) return [{ t: str, rtl: true }]; let maxL = 0; for (const sg of segs) if (sg.lv > maxL) maxL = sg.lv; const order = segs.map((_, i) => i); for (let L2 = maxL; L2 >= 1; L2--) { let i = 0; while (i < order.length) { if (segs[order[i]].lv >= L2) { let j = i; while (j < order.length && segs[order[j]].lv >= L2) j++; const sl = order.slice(i, j).reverse(); for (let k = i; k < j; k++) order[k] = sl[k - i]; i = j; } else i++; } } return order.map(i => { const rtl = segs[i].lv % 2 === 1; let t = segs[i].t; if (rtl) { let o = ''; for (const ch of t) o += (MIRROR[ch] || ch); t = o; } return { t, rtl }; }); }
function decodeEnt(s: string) { return String(s || '').replace(/<br\s*\/?>/gi, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;|&rsquo;|&lsquo;/g, "'").replace(/&mdash;/g, '—').replace(/&ndash;/g, '–'); }
function stripTags(s: string) { return decodeEnt(String(s || '').replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim(); }
// deno-lint-ignore no-explicit-any
function parseHtml(frag: string) { const blocks: any[] = []; const re = /<(h2|h3|p|ul|ol|table)\b[^>]*>([\s\S]*?)<\/\1>/gi; let m: any; while ((m = re.exec(frag))) { const tag = m[1].toLowerCase(); const inner = m[2]; if (tag === 'h2') blocks.push({ t: 'h2', text: stripTags(inner) }); else if (tag === 'h3') blocks.push({ t: 'h3', text: stripTags(inner) }); else if (tag === 'p') { const tx = stripTags(inner); if (tx) blocks.push({ t: 'p', text: tx }); } else if (tag === 'ul' || tag === 'ol') { const lis = inner.match(/<li\b[^>]*>([\s\S]*?)<\/li>/gi) || []; lis.forEach((li: string) => { const tx = stripTags(li.replace(/<\/?li[^>]*>/gi, '')); if (tx) blocks.push({ t: 'li', text: tx }); }); } else if (tag === 'table') { const trs = inner.match(/<tr\b[^>]*>([\s\S]*?)<\/tr>/gi) || []; let head: string[] = []; const rows: string[][] = []; trs.forEach((tr: string, ri: number) => { const cells = (tr.match(/<(th|td)\b[^>]*>([\s\S]*?)<\/(?:th|td)>/gi) || []).map((c: string) => stripTags(c.replace(/<\/?(th|td)[^>]*>/gi, ''))); if (ri === 0 && /<th\b/i.test(tr)) head = cells; else rows.push(cells); }); if (!head.length && rows.length) head = rows.shift() as string[]; if (head.length || rows.length) blocks.push({ t: 'table', head, rows, widths: head.map(() => 1 / Math.max(1, head.length)) }); } } return blocks; }

// 5 Aug 2026. Typographic characters are routine in model- and supplier-written prose. Each is kept
// when every font in force has its glyph (the brand faces carry — – · × …) and replaced by its ASCII
// form only when one does not; anything else a font cannot encode is dropped and COUNTED.
const NORM: Record<string, string> = { '≠': '!=', '≈': '~', '≥': '>=', '≤': '<=', '±': '+/-', '—': '-', '–': '-', '−': '-', '‑': '-', '→': '->', '←': '<-', '×': 'x', '÷': '/', '·': '-', '•': '-', '…': '...', '“': '"', '”': '"', '„': '"', '‘': "'", '’': "'", '′': "'", '″': '"', '‚': ',', '€': 'EUR', '£': 'GBP', '™': '(TM)', '®': '(R)', '©': '(C)', '½': '1/2', '¼': '1/4', '¾': '3/4', ' ': ' ', '​': '', '‎': '', '‏': '', '‪': '', '‫': '', '‬': '', '﻿': '' };
const INVISIBLE = new Set(['​', '‎', '‏', '‪', '‫', '‬', '﻿']);

// Subsetting is NOT why Arabic went missing (it was the first suspect, and embedding the face whole
// changed nothing); fontkit's Arabic shaper is — see arabic_shape.ts. Subset stays on.
const AR_SUBSET = true;
type Flag = 'match' | 'differs' | 'missing' | 'na';
type TC = { text: string; sub?: string; flag?: Flag; chip?: 'short' | 'open' | 'hold'; link?: string; bold?: boolean; group?: boolean };
// deno-lint-ignore no-explicit-any
const toCell = (c: any): TC => (c && typeof c === 'object' && !Array.isArray(c)) ? { ...c, text: String(c.text ?? '') } : { text: String(c ?? '') };

// deno-lint-ignore no-explicit-any
// Word wrap to a width. A single word wider than the line is broken by character, never drawn past
// the edge (21 Sep 2026): the signed-terms certificate's 64-character SHA-256 fingerprint ran off the
// page, so the one value that lets the acceptance be verified was printed cut short. Prevented by
// render.test.ts.
export function wrapWords(t: unknown, meas: (s: string) => number, w: number): string[] {
  const lines: string[] = []; let cur = '';
  for (const wd of String(t == null ? '' : t).split(/\s+/)) {
    if (meas(wd) > w) {
      if (cur) { lines.push(cur); cur = ''; }
      for (const ch of wd) { if (cur && meas(cur + ch) > w) { lines.push(cur); cur = ch; } else cur += ch; }
      continue;
    }
    const test = cur ? cur + ' ' + wd : wd;
    if (meas(test) > w && cur) { lines.push(cur); cur = wd; } else cur = test;
  }
  if (cur) lines.push(cur);
  return lines.length ? lines : [''];
}
export async function renderPdf(input: any, deps: RenderDeps): Promise<RenderResult> {
  const CO: DocIdentity = deps.identity ?? FALLBACK;
  const fetchBytes = deps.fetchBytes;
  let body = input ?? {};
  const lang = ['en', 'ar', 'bi'].includes(String(body.lang)) ? String(body.lang) : 'en';
  const L = lang === 'ar' ? 'ar' : 'en';
  const RTL = L === 'ar';
  const pdf = await PDFDocument.create(); pdf.registerFontkit(fontkit);
  let font = await pdf.embedFont(StandardFonts.Helvetica);
  let bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  let latinFull = false, arFull = false;
  try { const sr = await fetchBytes('qd_sora_regular.ttf'); const sb = await fetchBytes('qd_sora_bold.ttf'); if (sr) { font = await pdf.embedFont(sr, { subset: true }); latinFull = true; } if (sb) bold = await pdf.embedFont(sb, { subset: true }); } catch (_e) { /* Helvetica stands */ }
  const PW = 595.28, PH = 841.89, M = 46; const CW = PW - 2 * M; const BOTTOM = 78;
  const opt = body.options || {};
  // THE LETTERHEAD IS THE DEFAULT (22 Sep 2026, audit of every document we issue, finding 5). It was
  // opt-in, and the IT incident record and the conversation archive never opted in, so they went out
  // with no issuer and no licence line. Every document now wears it; only an explicit false removes it.
  const letterhead = opt.letterhead !== false, doSign = !!opt.sign, doStamp = !!opt.stamp;
  const needAr = lang !== 'en' || hasAr(JSON.stringify(body));
  let arReg = font, arBold = bold;
  if (needAr) { const rb = await fetchBytes('qd_ar_regular.ttf'); const bb = await fetchBytes('qd_ar_bold.ttf'); if (rb) { arReg = await pdf.embedFont(rb, { subset: AR_SUBSET }); arFull = true; } if (bb) arBold = await pdf.embedFont(bb, { subset: AR_SUBSET }); if (arFull) { plainLayout(arReg); plainLayout(arBold); } }

  // 9 Sep 2026. safeText DROPS a character it cannot encode; count what is dropped, report it on
  // every response, and refuse outright when the document carries the signature or stamp. A
  // subsetted TrueType maps an absent code point to .notdef (drawn as nothing), so ask the face.
  let dropped = 0; const droppedSample = new Set<string>();
  // deno-lint-ignore no-explicit-any
  function faceOf(f: any) { try { return f?.embedder?.font ?? null; } catch (_e) { return null; } }
  // One glyph per code point, no script engine. The Arabic face gets this because fontkit's Arabic
  // shaper throws (arabic_shape.ts); the text reaching it is already shaped and in visual order.
  // deno-lint-ignore no-explicit-any
  function plainLayout(f: any) { const face = faceOf(f); if (!face || typeof face.glyphForCodePoint !== 'function') return; face.layout = (text: string) => { const glyphs = [...String(text)].map((ch) => face.glyphForCodePoint(ch.codePointAt(0) || 0)); return { glyphs, positions: glyphs.map((g: any) => ({ xAdvance: g.advanceWidth, yAdvance: 0, xOffset: 0, yOffset: 0 })) }; }; }
  let glyphCheck = false;
  // deno-lint-ignore no-explicit-any
  function hasGlyph(f: any, cp: number): boolean {
    const face = faceOf(f);
    if (!face || typeof face.hasGlyphForCodePoint !== 'function') return true;
    glyphCheck = true;
    try { return !!face.hasGlyphForCodePoint(cp); } catch (_e) { return true; }
  }
  function drop(ch: string) { dropped++; if (droppedSample.size < 12) droppedSample.add(ch); }
  function safeText(s: string): string {
    let out = '';
    for (const ch of String(s == null ? '' : s)) {
      const cp = ch.codePointAt(0) || 0;
      const rep = NORM[ch];
      if (rep !== undefined) {
        const everyFontHasIt = !INVISIBLE.has(ch) && latinFull && hasGlyph(font, cp) && (!needAr || (arFull && hasGlyph(arReg, cp)));
        out += everyFontHasIt ? ch : rep; continue;
      }
      if (cp > 0xff) {
        if (isArCode(cp)) { if (arFull && hasGlyph(arReg, cp)) out += ch; else drop(ch); continue; }
        if (latinFull && hasGlyph(font, cp)) out += ch; else drop(ch);
        continue;
      }
      out += ch;
    }
    return out;
  }
  // deno-lint-ignore no-explicit-any
  function safeDeep(v: any, key = ''): any {
    if (typeof v === 'string') return key === 'link' ? v : safeText(v);
    if (Array.isArray(v)) return v.map((x) => safeDeep(x));
    // deno-lint-ignore no-explicit-any
    if (v && typeof v === 'object') { const o: any = {}; for (const k of Object.keys(v)) o[k] = safeDeep(v[k], k); return o; }
    return v;
  }
  body = safeDeep(body);

  const strict = opt.strict_glyphs === undefined ? (doSign || doStamp) : !!opt.strict_glyphs;
  if (strict && dropped > 0) {
    return { ok: false, status: 502, body: { error: 'glyphs_unrenderable', dropped, sample: [...droppedSample].join(''),
      fonts: { latin: latinFull, arabic: arFull }, glyph_check: glyphCheck ? 'fontkit' : 'unavailable',
      detail: 'The brand fonts needed for this text are not embedded, so ' + dropped + ' character(s) would be '
        + 'silently missing from a document that carries the QuotesDone signature or stamp. Refusing rather than '
        + 'issuing an incomplete signed document. Check the brand bucket for qd_sora_*.ttf / qd_ar_*.ttf.' } };
  }

  // Our own constants never pass through safeDeep, so on the fallback font they could throw and
  // lose the whole PDF. Losing one glyph is acceptable; losing the customer's document is not.
  // A draw that fails twice loses the WHOLE string, and until 14 Sep 2026 that loss was silent:
  // every Arabic run died here while the response reported glyphs_dropped 0. It is counted now.
  // deno-lint-ignore no-explicit-any
  function armPage(p: any) { const orig = p.drawText.bind(p);
    // deno-lint-ignore no-explicit-any
    p.drawText = (t: any, o: any) => { try { orig(String(t), o); } catch (_e) { try { orig(safeText(String(t)), o); } catch (_e2) { for (const ch of String(t)) { if (ch.trim()) drop(ch); } } } };
    return p; }

  const title = String(body.title || 'Document');
  const refText = body.ref ? String(body.ref) : '';
  const dateEn = body.date ? String(body.date) : new Date().toLocaleDateString('en-GB', { day: '2-digit', month: 'long', year: 'numeric' });
  // Western digits in the Arabic date too: the amounts, references and quantities on the same
  // page are Western, and a page mixing ٢٠٢٦ with 2026 reads as two documents stapled together.
  const dateAr = body.date_ar ? String(body.date_ar) : new Date().toLocaleDateString('ar-AE-u-nu-latn', { day: '2-digit', month: 'long', year: 'numeric' });
  const dateFor = () => RTL ? dateAr : dateEn;
  const control = body.control ? String(body.control) : '';
  let lockupTrimmed = true;
  const logoLightImg = await (async () => { const b = await fetchBytes(LOCKUP.dark); return b ? await pdf.embedPng(b) : null; })();
  const logoImg = await (async () => { const b = await fetchBytes(LOCKUP.light); return b ? await pdf.embedPng(b) : null; })();
  const logoMaster = logoLightImg ? null : await (async () => { lockupTrimmed = false; const b = await fetchBytes('qd_lockup_dark.png'); return b ? await pdf.embedPng(b) : null; })();
  const sig = doSign ? await (async () => { const b = await fetchBytes('qd_signature.png'); return b ? await pdf.embedPng(b) : null; })() : null;
  const stamp = doStamp ? await (async () => { const b = await fetchBytes('qd_stamp.png'); return b ? await pdf.embedPng(b) : null; })() : null;

  // deno-lint-ignore no-explicit-any
  const pages: any[] = [];
  // deno-lint-ignore no-explicit-any
  let page: any = armPage(pdf.addPage([PW, PH])); pages.push(page); let y = PH - M;
  // deno-lint-ignore no-explicit-any
  function fontFor(s: any, b: boolean) { return hasAr(s) ? (b ? arBold : arReg) : (b ? bold : font); }
  // deno-lint-ignore no-explicit-any
  function W(text: string, f: any, s: number) { try { return f.widthOfTextAtSize(text, s); } catch (_e) { return text.length * s * 0.5; } }
  // ── LINKS (9 Sep 2026). A PDF link is a /Annot dictionary on the page whose /Rect must be
  // computed from the same x, baseline, width and size the draw used. http(s) only.
  let linkCount = 0;
  // deno-lint-ignore no-explicit-any
  function linkAt(p: any, x: number, baseline: number, w: number, size: number, uri: unknown) {
    const u = String(uri == null ? '' : uri).trim();
    if (!/^https?:\/\/\S+$/i.test(u) || !(w > 0) || !(size > 0)) return;
    try {
      const ctx = pdf.context;
      const ref = ctx.register(ctx.obj({
        Type: 'Annot', Subtype: 'Link', Border: ctx.obj([0, 0, 0]),
        Rect: ctx.obj([x, baseline - size * 0.25, x + w, baseline + size * 0.9]),
        A: ctx.obj({ Type: 'Action', S: 'URI', URI: PDFString.of(u) }),
      }));
      const arr = p.node.lookupMaybe(PDFName.of('Annots'), PDFArray);
      if (arr) arr.push(ref); else p.node.set(PDFName.of('Annots'), ctx.obj([ref]));
      linkCount++;
    } catch (_e) { /* a link is never worth losing the document over */ }
  }
  // A right-to-left run is shaped in logical order, then reversed into the order it is drawn in.
  const visual = (r: { t: string; rtl: boolean }) => r.rtl ? [...shapeArabic(r.t)].reverse().join('') : r.t;
  // deno-lint-ignore no-explicit-any
  function measRTL(s: string, f: any, size: number) { let w = 0; for (const r of bidiRuns(s)) w += W(visual(r), f, size); return w; }
  // deno-lint-ignore no-explicit-any
  function drawRTL(s: string, size: number, f: any, color: any, yy: number, xRight: number) { const runs = bidiRuns(s).map((r) => ({ t: visual(r), rtl: r.rtl })); let tot = 0; const ws = runs.map(r => { const w = W(r.t, f, size); tot += w; return w; }); let x = xRight - tot; for (let i = 0; i < runs.length; i++) { if (runs[i].t.trim() !== '') page.drawText(runs[i].t, { x, y: yy, size, font: f, color }); x += ws[i]; } }
  // deno-lint-ignore no-explicit-any
  const meas = (t: string, f: any, s: number) => hasAr(t) ? measRTL(t, f, s) : W(t, f, s);
  // deno-lint-ignore no-explicit-any
  function wrap(t: string, f: any, s: number, w: number) { return wrapWords(t, (x) => meas(x, f, s), w); }
  const lines = (t: unknown, size: number, b: boolean, w: number) => { const s = String(t ?? ''); return s ? wrap(s, fontFor(s, b), size, w) : []; };
  /** A key-figure value as at most two lines that each fit the cell width; a third line is folded into an ellipsis. */
  const figureLines = (s: string, size: number, w: number): string[] => {
    const f = fontFor(s, true); const ls = wrap(s, f, size, w);
    if (ls.length <= 2) return ls;
    let last = ls[1]; while (last.length > 1 && meas(last + '…', f, size) > w) last = last.slice(0, -1);
    return [ls[0], last + '…'];
  };

  // ── Direction-aware primitives. `sx` is a logical offset from the START margin (left in English,
  // right in Arabic); px turns a logical box into its physical left edge. Align 's' | 'e' | 'c' is
  // logical too: 's' hugs the start edge of the box, 'e' the end edge (figures in a column).
  const px = (sx: number, w: number) => RTL ? PW - M - sx - w : M + sx;
  // deno-lint-ignore no-explicit-any
  function txt(t: unknown, x: number, w: number, yy: number, size: number, o: { bold?: boolean; color?: any; align?: string; link?: unknown } = {}) {
    const s = String(t ?? ''); if (!s.trim()) return 0;
    const f = fontFor(s, !!o.bold); const tw = meas(s, f, size);
    const a = o.align || 's'; const phys = a === 'c' ? 'c' : ((a === 's') !== RTL ? 'l' : 'r');
    const xl = phys === 'l' ? x : phys === 'r' ? x + w - tw : x + (w - tw) / 2;
    const color = o.color ?? INK;
    if (hasAr(s)) drawRTL(s, size, f, color, yy, xl + tw); else page.drawText(s, { x: xl, y: yy, size, font: f, color });
    if (o.link) linkAt(page, xl, yy, tw, size, o.link);
    return tw;
  }
  // deno-lint-ignore no-explicit-any
  function para(t: unknown, o: { size?: number; bold?: boolean; color?: any; lh?: number; sx?: number; w?: number; link?: unknown; align?: string } = {}) {
    const size = o.size ?? 9.6, lh = o.lh ?? 1.5, sx = o.sx ?? 0, w = o.w ?? CW;
    for (const ln of lines(t, size, !!o.bold, w)) { ensure(size * lh); txt(ln, px(sx, w), w, y - size, size, { bold: o.bold, color: o.color, link: o.link, align: o.align }); y -= size * lh; }
  }
  // deno-lint-ignore no-explicit-any
  function hline(yy: number, color: any = HAIR, t = 0.5, x0 = M, x1 = PW - M) { page.drawLine({ start: { x: x0, y: yy }, end: { x: x1, y: yy }, thickness: t, color }); }
  function rule(yy: number) { hline(yy, HAIR, 0.6); const gx = px(0, 40); page.drawLine({ start: { x: gx, y: yy }, end: { x: gx + 40, y: yy }, thickness: 1.8, color: GOLD }); }
  // deno-lint-ignore no-explicit-any
  function pill(x: number, yb: number, w: number, h: number, color: any) { const r = h / 2; page.drawRectangle({ x: x + r, y: yb, width: Math.max(0, w - 2 * r), height: h, color }); page.drawEllipse({ x: x + r, y: yb + r, xScale: r, yScale: r, color }); page.drawEllipse({ x: x + w - r, y: yb + r, xScale: r, yScale: r, color }); }
  // ✓ matches · ≠ differs · — not stated · ○ N/A — drawn, so no font has to carry the glyph.
  function marker(flag: Flag, cx: number, cy: number, r = 4.3) {
    if (flag === 'na') { page.drawEllipse({ x: cx, y: cy, xScale: r, yScale: r, borderColor: MISS, borderWidth: 0.8 }); return; }
    page.drawEllipse({ x: cx, y: cy, xScale: r, yScale: r, color: flag === 'match' ? TEAL : flag === 'differs' ? GOLD : MISS });
    // deno-lint-ignore no-explicit-any
    const ln = (a: number, b: number, c: number, d: number, col: any = WHITE, t = 1.15) => page.drawLine({ start: { x: cx + a, y: cy + b }, end: { x: cx + c, y: cy + d }, thickness: t, color: col });
    if (flag === 'match') { ln(-2.1, 0.1, -0.6, -1.5); ln(-0.6, -1.5, 2.2, 1.7); }
    else if (flag === 'differs') { ln(-2.2, 1.1, 2.2, 1.1, NAVY, 0.9); ln(-2.2, -1.1, 2.2, -1.1, NAVY, 0.9); ln(-1.0, -2.6, 1.0, 2.6, NAVY, 0.9); }
    else ln(-2.1, 0, 2.1, 0);
  }
  function chip(text: string, kind: string, x: number, w: number, baseY: number, align = 's') {
    const s = 7.4; const f = fontFor(text, true); const tw = meas(text, f, s); const cw = tw + 14, ch = 13;
    const phys = align === 'c' ? 'c' : ((align !== 'e') !== RTL ? 'l' : 'r');
    const x0 = phys === 'l' ? x : phys === 'r' ? x + w - cw : x + (w - cw) / 2;
    const [bg, fg] = kind === 'short' ? [TINT_T, TEAL_D] : kind === 'hold' ? [TINT_G, AMBER_D] : [TINT_N, NAVY];
    const yb = baseY - 3.4; pill(x0, yb, cw, ch, bg); txt(text, x0, cw, yb + 4.1, s, { bold: true, color: fg, align: 'c' });
  }

  // ── Page furniture ─────────────────────────────────────────────────────────────────────────
  const lockupImg = () => logoLightImg || logoImg || logoMaster;
  function drawLockup(hh: number, yb: number) { const lg = lockupImg(); if (!lg) return; const w = lockupTrimmed ? lockupWidthFor(hh) : 110; const h = lockupTrimmed ? hh : lg.height * (110 / lg.width); page.drawImage(lg, { x: px(0, w), y: yb, width: w, height: h }); }
  function slimHeader() {
    const h = 38; page.drawRectangle({ x: 0, y: PH - h, width: PW, height: h, color: NAVY }); page.drawRectangle({ x: 0, y: PH - h, width: PW, height: 1.8, color: GOLD });
    drawLockup(13, PH - h / 2 - 5.5);
    txt(refText ? `${title}  ·  ${refText}` : title, M, CW, PH - h / 2 - 2.6, 7.6, { color: BANDTXT, align: 'e' });
    y = PH - h - 24;
  }
  function newPage() { page = armPage(pdf.addPage([PW, PH])); pages.push(page); slimHeader(); }
  function ensure(h: number) { if (y - h < BOTTOM) newPage(); }
  function footers() {
    const [fl1, fl2] = (RTL ? footerLinesAr(CO) : footerLines(CO)).map((s) => safeText(s));
    const ctl = safeText(control);
    pages.forEach((p, i) => {
      page = p;
      hline(64, HAIR, 0.5); const gx = px(0, 34); page.drawLine({ start: { x: gx, y: 64 }, end: { x: gx + 34, y: 64 }, thickness: 1.6, color: GOLD });
      const pn = RTL ? `صفحة ${i + 1} من ${pages.length}` : `Page ${i + 1} of ${pages.length}`; const pw = 74;
      txt(pn, px(CW - pw, pw), pw, 51, 7.4, { bold: true, color: NAVY, align: 'e' });
      txt(letterhead ? fl1 : 'QuotesDone · quotesdone.com', px(0, CW - pw - 8), CW - pw - 8, 51, 6.6, { color: MUT });
      if (letterhead) txt(fl2, px(0, CW - pw - 8), CW - pw - 8, 41, 6.6, { color: MUT });
      if (ctl) txt(ctl, px(0, CW), CW, 31, 6.3, { color: MISS });
    });
  }
  // The cover band: lockup and issuer, kicker, title, request summary, a meta row, then the
  // key-figures strip on white beneath it.
  // deno-lint-ignore no-explicit-any
  function cover(cv: any) {
    // cover.compact (14 Sep 2026, agent: accountant): a band 58pt shorter — smaller title, one subtitle line —
    // for letters and indexes, so a signed one-page letter keeps its signature on page 1 instead of sending
    // it alone to an 83%-empty page 2. Opt-in; every other document keeps the full band.
    const K = !!cv.compact;
    const H = K ? 180 : 238;
    page.drawRectangle({ x: 0, y: PH - H, width: PW, height: H, color: NAVY });
    page.drawRectangle({ x: 0, y: PH - H, width: PW, height: 2.6, color: GOLD }); page.drawRectangle({ x: 0, y: PH - H + 2.6, width: PW, height: 1, color: TEAL });
    drawLockup(CO.logoPt, PH - 30 - CO.logoPt);
    const issuer = [CO.name, licenceLine(CO, L)];
    txt(safeText(issuer[0]), M, CW, PH - 36, 9.5, { bold: true, color: WHITE, align: 'e' });
    txt(safeText(issuer[1]), M, CW, PH - 48, 7, { color: BANDTXT, align: 'e' });
    txt(cv.kicker, M, CW, PH - (K ? 80 : 94), 9, { bold: true, color: TEAL_L });
    const kx = px(0, 30); page.drawLine({ start: { x: kx, y: PH - (K ? 87 : 101) }, end: { x: kx + 30, y: PH - (K ? 87 : 101) }, thickness: 1.6, color: GOLD });
    txt(cv.title, M, CW, PH - (K ? 110 : 132), K ? 21 : 27, { bold: true, color: WHITE });
    let sy = PH - (K ? 128 : 154); for (const ln of lines(cv.subtitle, 9.8, false, CW * 0.9).slice(0, K ? 1 : 2)) { txt(ln, px(0, CW * 0.9), CW * 0.9, sy, 9.8, { color: BANDTXT }); sy -= 14; }
    const meta = Array.isArray(cv.meta) ? cv.meta.slice(0, 4) : []; const mw = CW / Math.max(1, meta.length);
    meta.forEach(([k, v]: [string, string], i: number) => { const x = px(i * mw, mw); txt(k, x, mw - 10, PH - H + (K ? 30 : 42), 6.8, { color: TEAL_L }); txt((lines(v, 9.2, true, mw - 10)[0] || ''), x, mw - 10, PH - H + (K ? 14 : 26), 9.2, { bold: true, color: WHITE }); });
    y = PH - H - 14;
    const figs = Array.isArray(cv.figures) ? cv.figures.slice(0, 4) : [];
    if (figs.length) {
      const h = 58, fw = CW / figs.length;
      page.drawRectangle({ x: M, y: y - h, width: CW, height: h, color: ZEBRA });
      page.drawRectangle({ x: M, y: y - 2, width: CW, height: 2, color: TEAL_D });
      figs.forEach(([k, v]: [string, string], i: number) => {
        const x = px(i * fw, fw);
        if (i > 0) { const sepX = RTL ? x + fw : x; page.drawLine({ start: { x: sepX, y: y - 12 }, end: { x: sepX, y: y - h + 10 }, thickness: 0.5, color: HAIR }); }
        txt(k, x + 12, fw - 24, y - 19, 7.2, { color: MUT });
        // A value the cell cannot hold at 9pt on one line wraps onto a second line inside its own cell
        // (58pt strip: label at 19, value at 42, second line at 42+s+1 stays above 58). Until 21 Sep 2026
        // it was drawn unwrapped and ran across the separator: "2 years materials and workmanship" sat on
        // top of "Valid for 30 days" (customer audit, finding 12). Anything past two lines is cut with …
        let s = 15; const vs = String(v ?? ''); while (s > 9 && meas(vs, fontFor(vs, true), s) > fw - 24) s -= 0.5;
        const vl = figureLines(vs, s, fw - 24);
        vl.forEach((ln, li) => txt(ln, x + 12, fw - 24, y - 42 - li * (s + 1), s, { bold: true, color: NAVY }));
      });
      y -= h + 26;
    }
  }
  // The letterhead header documents without a cover keep (brief, finance reports, signed copies).
  function legacyHeader() {
    const h = 92; page.drawRectangle({ x: 0, y: PH - h, width: PW, height: h, color: NAVY }); page.drawRectangle({ x: 0, y: PH - h, width: PW, height: 2.6, color: GOLD }); page.drawRectangle({ x: 0, y: PH - h + 2.6, width: PW, height: 1, color: TEAL });
    const lg = lockupImg(); if (lg) { const hh = lockupTrimmed ? CO.logoPt : lg.height * (128 / lg.width); const w = lockupTrimmed ? lockupWidthFor(hh) : 128; page.drawImage(lg, { x: M, y: PH - h / 2 - hh / 2 + 2, width: w, height: hh }); }
    // The licence line in the document's language (22 Sep 2026, audit finding 4: every Arabic page
    // without a cover printed the English "DET Trader License No. 1633275 · TDRA…"). Drawn at the right
    // edge in both languages, away from the lockup on the left: 'e' is the right edge in English, 's' in Arabic.
    if (letterhead) { const ls = [CO.name, licenceLine(CO, L), CO.email + ' · ' + CO.phone]; let ly = PH - 26; ls.forEach((ln, i) => { const s = i === 0 ? 11 : 8; txt(safeText(ln), M, CW, ly - s, s, { bold: i === 0, color: i === 0 ? WHITE : BANDTXT, align: RTL ? 's' : 'e' }); ly -= (i === 0 ? 15 : 11); }); }
    y = PH - h - 24;
    txt(title, M, CW, y - 18, 20, { bold: true, color: NAVY }); y -= 24;
    const meta = (refText ? (RTL ? 'الرقم المرجعي: ' + refText : 'Ref: ' + refText) + ' · ' : '') + (RTL ? CO_AR.city : CO.city) + ' · ' + dateFor();
    txt(meta, M, CW, y - 10, 10, { color: MUT }); y -= 24;
  }

  // ── Blocks ─────────────────────────────────────────────────────────────────────────────────
  // Keep with next (14 Sep 2026): a section heading starts only where at least two lines of what follows fit
  // too; the Arabic invoice left "الأساس والاستحقاق" alone at the foot of page 1 with its text on page 2.
  function section(n: unknown, t: string) {
    ensure(52 + 30); y -= 12; const box = 17;
    if (n != null && n !== '') { const bx = px(0, box); page.drawRectangle({ x: bx, y: y - box, width: box, height: box, color: NAVY }); txt(String(n), bx, box, y - box + 5.2, 9, { bold: true, color: WHITE, align: 'c' }); }
    const off = n != null && n !== '' ? box + 9 : 0;
    txt(t, px(off, CW - off), CW - off, y - box + 4, 13, { bold: true, color: NAVY });
    y -= box + 7; rule(y); y -= 13;
  }
  function h3(t: string, link?: unknown) { ensure(30); y -= 4; txt(t, px(0, CW), CW, y - 10, 10.2, { bold: true, color: NAVY, link }); y -= 19; }
  // deno-lint-ignore no-explicit-any
  function kv(pairs: any[]) {
    const cw = CW / 2;
    for (let r = 0; r < Math.ceil(pairs.length / 2); r++) {
      const pr = [pairs[r * 2], pairs[r * 2 + 1]].filter(Boolean);
      const ls = pr.map((p) => lines(toCell(p[1]).text, 10, true, cw - 14)); const h = 16 + Math.max(...ls.map((l) => l.length)) * 13 + 8;
      ensure(h);
      pr.forEach((p, c) => { const x = px(c * cw, cw); txt(p[0], x, cw - 14, y - 9, 7.4, { color: MUT }); let vy = y - 23; for (const ln of ls[c]) { txt(ln, x, cw - 14, vy, 10, { bold: true, color: NAVY }); vy -= 13; } });
      y -= h;
    }
  }
  // deno-lint-ignore no-explicit-any
  function callout(b: any) {
    const tone = b.tone || 'teal'; const fill = tone === 'gold' ? TINT_G : tone === 'grey' ? TINT_N : TINT_T; const edge = tone === 'gold' ? GOLD : tone === 'grey' ? HAIR : TEAL; const dark = tone === 'gold' ? AMBER_D : tone === 'grey' ? NAVY : TEAL_D;
    const pad = 13, iw = CW - 2 * pad; const tl = lines(b.title, 10.2, true, iw); const bl = lines(b.text, 9, false, iw);
    const h = pad * 2 + tl.length * 13.5 + (bl.length ? 5 + bl.length * 13 : 0) - 3;
    ensure(h + 10); y -= 4;
    page.drawRectangle({ x: M, y: y - h, width: CW, height: h, color: fill, borderColor: edge, borderWidth: 0.8 });
    let yy = y - pad - 8; for (const ln of tl) { txt(ln, M + pad, iw, yy, 10.2, { bold: true, color: dark, link: b.link }); yy -= 13.5; }
    yy -= 5; for (const ln of bl) { txt(ln, M + pad, iw, yy + 1, 9, { color: INK }); yy -= 13; }
    y -= h + 12;
  }
  // deno-lint-ignore no-explicit-any
  function party(b: any) {
    ensure(56); txt(b.label, px(0, CW), CW, y - 8, 7.4, { color: MUT });
    const s = 11.5; const tw = meas(String(b.chip), fontFor(b.chip, true), s); const cw = tw + 26, ch = 22; const x = px(0, cw);
    pill(x, y - 40, cw, ch, NAVY); txt(b.chip, x, cw, y - 32.5, s, { bold: true, color: WHITE, align: 'c' });
    const sw = CW - cw - 16; let yy = y - 24; for (const ln of lines(b.note, 8.2, false, sw).slice(0, 3)) { txt(ln, px(cw + 16, sw), sw, yy, 8.2, { color: MUT }); yy -= 11; }
    y -= 52;
  }
  // deno-lint-ignore no-explicit-any
  function table(b: any) {
    // deno-lint-ignore no-explicit-any
    const head: TC[] = (b.head || []).map(toCell); const n = head.length || ((b.rows || [])[0] || []).length || 1;
    const widths: number[] = (Array.isArray(b.widths) && b.widths.length === n) ? b.widths : Array(n).fill(1 / n);
    const colW = widths.map((w) => w * CW); const sxs: number[] = []; let acc = 0; for (const w of colW) { sxs.push(acc); acc += w; }
    const align: string[] = b.align || [];
    // A wide table (five suppliers side by side) may ask for a smaller face with b.fs.
    const FS = Number(b.fs) > 0 ? Number(b.fs) : 8.5, LH = FS * 1.34, SFS = 7, SLH = 9.2, PX = 6, PY = 5.5, MK = 12;
    const drawHead = () => {
      ensure(22 + 26); page.drawRectangle({ x: M, y: y - 20, width: CW, height: 20, color: NAVY });
      head.forEach((h, i) => { const x = px(sxs[i], colW[i]); txt(lines(h.text, 7.6, true, colW[i] - 2 * PX)[0] || '', x + PX, colW[i] - 2 * PX, y - 13.2, 7.6, { bold: true, color: WHITE, align: align[i] || 's' }); });
      y -= 20; hline(y, GOLD, 1.2);
    };
    if (head.length) drawHead();
    // deno-lint-ignore no-explicit-any
    (b.rows || []).forEach((r0: any[], ri: number) => {
      const r = r0.map(toCell);
      if (r.length === 1 && r[0].group) {
        const gl = lines(r[0].text, 8.6, true, CW - 2 * PX); const h = gl.length * LH + 2 * PY;
        if (y - h - LH * 2 < BOTTOM) { newPage(); if (head.length) drawHead(); }
        page.drawRectangle({ x: M, y: y - h, width: CW, height: h, color: TINT_N });
        let yy = y - PY - 8; for (const ln of gl) { txt(ln, M + PX, CW - 2 * PX, yy, 8.6, { bold: true, color: NAVY }); yy -= LH; }
        y -= h; hline(y); return;
      }
      const cells = r.map((c, i) => ({ c, main: c.chip ? [c.text] : lines(c.text || '', FS, !!c.bold, colW[i] - 2 * PX - (c.flag ? MK : 0)), sub: c.sub ? lines(c.sub, SFS, false, colW[i] - 2 * PX) : [] }));
      const h = Math.max(LH, ...cells.map((x) => x.main.length * LH + (x.sub.length ? 3 + x.sub.length * SLH : 0))) + 2 * PY - 2;
      if (y - h < BOTTOM) { newPage(); if (head.length) drawHead(); }
      if (b.zebra && ri % 2 === 1) page.drawRectangle({ x: M, y: y - h, width: CW, height: h, color: ZEBRA });
      cells.forEach(({ c, main, sub }, i) => {
        const x = px(sxs[i], colW[i]); const a = align[i] || 's';
        let yy = y - PY - FS + 1;
        if (c.chip) { chip(c.text, c.chip, x + PX, colW[i] - 2 * PX, yy, a); return; }
        let tx = x + PX; let tw = colW[i] - 2 * PX;
        if (c.flag) { marker(c.flag, RTL ? x + colW[i] - PX - 4.3 : x + PX + 4.3, yy + 2.9); if (!RTL) tx += MK; tw -= MK; }
        const color = c.link ? TEAL_D : (c.bold ? NAVY : INK);
        for (const ln of main) { txt(ln, tx, tw, yy, FS, { bold: !!c.bold, color, link: c.link, align: a }); yy -= LH; }
        if (sub.length) { yy -= 1; for (const ln of sub) { txt(ln, x + PX, colW[i] - 2 * PX, yy + (FS - SFS), SFS, { color: MUT, align: a }); yy -= SLH; } }
      });
      y -= h; hline(y);
    });
    y -= 10;
  }
  // deno-lint-ignore no-explicit-any
  function scores(b: any) {
    const head: string[] = b.head || []; const rows = b.rows || [];
    const labelW = CW * 0.25; const dw = (CW - labelW) / 4; const rowH = 22;
    ensure(18 + rows.length * rowH + 24);
    head.forEach((h, i) => txt(h, px(labelW + i * dw, dw), dw, y - 9, 7.4, { bold: true, color: MUT }));
    y -= 14; hline(y);
    // deno-lint-ignore no-explicit-any
    rows.forEach((r: any) => {
      const cy = y - rowH / 2;
      txt(`#${r.rank}`, px(0, 22), 22, cy - 3, 8, { bold: true, color: TEAL_D });
      txt(r.label, px(24, labelW - 24), labelW - 24, cy - 3.2, 9, { bold: true, color: NAVY });
      (r.scores || []).forEach((s: number, i: number) => {
        const bx = px(labelW + i * dw, dw); const sw = 9.5, gap = 2;
        for (let k = 0; k < 5; k++) { const x = RTL ? bx + dw - (k + 1) * sw - k * gap : bx + k * (sw + gap); page.drawRectangle({ x, y: cy - 3, width: sw, height: 6, color: k < s ? TEAL : HAIR }); }
        const nx = RTL ? bx + dw - 5 * (sw + gap) - 22 : bx + 5 * (sw + gap) + 3; txt(String(s), nx, 18, cy - 3, 8, { bold: true, color: NAVY, align: RTL ? 'e' : 's' });
      });
      const ox = px(labelW + 3 * dw, dw); const tw = dw - 30; const tx = RTL ? ox + dw - tw : ox;
      page.drawRectangle({ x: tx, y: cy - 3.5, width: tw, height: 7, color: HAIR });
      const fw = tw * Math.max(0, Math.min(5, Number(r.overall) || 0)) / 5; page.drawRectangle({ x: RTL ? tx + tw - fw : tx, y: cy - 3.5, width: fw, height: 7, color: TEAL_D });
      txt(String(r.overall), RTL ? ox : ox + tw + 4, 24, cy - 3.2, 8.4, { bold: true, color: NAVY, align: RTL ? 'e' : 's' });
      y -= rowH; hline(y);
    });
    y -= 4; if (b.note) para(b.note, { size: 7.4, color: MUT, lh: 1.4 }); y -= 6;
  }
  // deno-lint-ignore no-explicit-any
  function totals(b: any) {
    const bw = 262; const x = px(CW - bw, bw); const rows = b.rows || [];
    ensure(rows.length * 24 + 30); y -= 2;
    // deno-lint-ignore no-explicit-any
    // 14 Sep 2026 (agent: accountant). The label and the value shared one line with nothing between
    // them, so a long label ran under the figure: "Interest (c) at 9% p.a. for 32 days to 17 November
    // 2026" overlapped "AED 21.35" by 36pt in six of the fourteen legal samples (measured with
    // scripts/legal/pdf_text_overlaps.mjs). The value keeps its line at the end edge; the label wraps
    // in the width the value leaves, and the row grows with it.
    const inner = bw - 24, GAP = 10;
    rows.forEach(([l, v, strong]: any[]) => {
      const ls = strong ? 9.4 : 8.4, vs = strong ? 12.5 : 9, vStr = String(v ?? '');
      const vw = meas(vStr, fontFor(vStr, true), vs);
      const ll = lines(l, ls, !!strong, Math.max(40, inner - vw - GAP)); const lh = ls * 1.3;
      const h = Math.max(strong ? 28 : 20, (strong ? 12 : 8) + ll.length * lh + (strong ? 4 : 2));
      ensure(h);
      if (strong) { page.drawRectangle({ x, y: y - h, width: bw, height: h, color: NAVY }); page.drawRectangle({ x, y: y - 2, width: bw, height: 2, color: GOLD }); }
      let ly = y - (strong ? 18.5 : 13.5);
      const lx = RTL ? x + 12 + vw + GAP : x + 12; // the label box lies on the start side of the value
      for (const ln of ll) { txt(ln, lx, inner - vw - GAP, ly, ls, { bold: !!strong, color: strong ? WHITE : MUT }); ly -= lh; }
      const vx = RTL ? x + 12 : x + 12 + inner - vw;
      txt(vStr, vx, vw, y - (strong ? 19 : 13.5), vs, { bold: true, color: strong ? WHITE : INK, align: 'e' });
      y -= h; if (!strong) hline(y, HAIR, 0.5, x, x + bw);
    });
    y -= 8; if (b.note) para(b.note, { size: 8, color: AMBER_D }); y -= 4;
  }
  // deno-lint-ignore no-explicit-any
  function checks(b: any) {
    const items = b.items || []; const cw = (CW - 8) / 2;
    for (let r = 0; r < Math.ceil(items.length / 2); r++) {
      const pr = [items[r * 2], items[r * 2 + 1]].filter(Boolean);
      // deno-lint-ignore no-explicit-any
      const ls = pr.map((p: any) => lines(toCell(p[1]).text, 9, true, cw - 40)); const h = 30 + Math.max(...ls.map((l: string[]) => l.length)) * 12;
      ensure(h + 8);
      // deno-lint-ignore no-explicit-any
      pr.forEach((p: any, c: number) => {
        const cc = toCell(p[1]); const x = px(c * (cw + 8), cw);
        page.drawRectangle({ x, y: y - h, width: cw, height: h, color: WHITE, borderColor: HAIR, borderWidth: 0.8 });
        marker(cc.flag || 'missing', RTL ? x + cw - 15 : x + 15, y - 14.5, 5);
        txt(p[0], x + 28, cw - 40, y - 17, 7.4, { color: MUT, align: RTL ? 'e' : 's' });
        let vy = y - 31; for (const ln of ls[c]) { txt(ln, RTL ? x + 12 : x + 28, cw - 40, vy, 9, { bold: true, color: NAVY }); vy -= 12; }
      });
      y -= h + 8;
    }
    y -= 4;
  }
  // deno-lint-ignore no-explicit-any
  function terms(b: any) {
    const cols = b.cols || 3; const cells = b.cells || []; const cw = CW / cols;
    hline(y, NAVY, 1);
    for (let r = 0; r < Math.ceil(cells.length / cols); r++) {
      const row = cells.slice(r * cols, r * cols + cols);
      // deno-lint-ignore no-explicit-any
      const ls = row.map((p: any) => ({ main: lines(toCell(p[1]).text, 9.4, true, cw - 20), sub: toCell(p[1]).sub ? lines(toCell(p[1]).sub, 6.8, false, cw - 20) : [] }));
      // deno-lint-ignore no-explicit-any
      const h = 30 + Math.max(...ls.map((l: any) => l.main.length * 12.5 + l.sub.length * 9)) - 4;
      ensure(h);
      // deno-lint-ignore no-explicit-any
      row.forEach((p: any, c: number) => {
        const x = px(c * cw, cw);
        if (c > 0) { const sepX = RTL ? x + cw : x; page.drawLine({ start: { x: sepX, y: y - 6 }, end: { x: sepX, y: y - h + 6 }, thickness: 0.5, color: HAIR }); }
        txt(p[0], x + 10, cw - 20, y - 13, 7.2, { color: MUT });
        let vy = y - 27; for (const ln of ls[c].main) { txt(ln, x + 10, cw - 20, vy, 9.4, { bold: true, color: NAVY }); vy -= 12.5; }
        for (const ln of ls[c].sub) { txt(ln, x + 10, cw - 20, vy + 3, 6.8, { color: MUT }); vy -= 9; }
      });
      y -= h; hline(y);
    }
    y -= 12;
  }
  // deno-lint-ignore no-explicit-any
  function legend(b: any) {
    ensure(22); let sx = 0;
    for (const [flag, label] of (b.items || [])) {
      const tw = meas(String(label), fontFor(label, false), 7.6); const w = tw + 15;
      if (sx + w > CW) { y -= 14; sx = 0; }
      const x = px(sx, w); marker(flag, RTL ? x + w - 4.5 : x + 4.5, y - 6.2);
      txt(label, RTL ? x : x + 13, w - 13, y - 9, 7.6, { color: MUT, align: RTL ? 'e' : 's' });
      sx += w + 16;
    }
    y -= 20;
  }
  function bullet(t: string, link?: unknown) { ensure(14); page.drawRectangle({ x: RTL ? PW - M - 4 : M + 1, y: y - 7.2, width: 3.2, height: 3.2, color: TEAL }); para(t, { sx: 12, w: CW - 12, link }); }
  // deno-lint-ignore no-explicit-any
  function renderBlocks(blocks: any[]) {
    for (const b of blocks) {
      const t = b.t || b.type;
      if (t === 'section') section(b.n, b.text || '');
      else if (t === 'h2' || t === 'heading') section(null, b.text || '');
      else if (t === 'h3') h3(b.text || '', b.link);
      else if (t === 'p' || t === 'para') {
        if (b.label) { ensure(28); txt(b.label, px(0, CW), CW, y - 8, 7.4, { bold: true, color: MUT }); y -= 13; }
        para(b.text || '', { size: b.size || 9.6, bold: !!b.bold, color: b.muted ? MUT : INK, link: b.link });
        if (b.sub) para(b.sub, { size: 7.2, color: MUT, lh: 1.4 });
        y -= 5;
      }
      else if (t === 'li') bullet(b.text || '', b.link);
      else if (t === 'kv') kv(b.pairs || []);
      else if (t === 'table') table(b);
      else if (t === 'total') totals({ rows: [[RTL ? 'الإجمالي' : 'Total', b.value || '', true]] });
      else if (t === 'totals') totals(b);
      else if (t === 'note') { para(b.text || '', { size: 8, color: MUT, link: b.link, lh: 1.45 }); y -= 3; }
      else if (t === 'link') { para(b.text || '', { size: 9.2, bold: true, color: TEAL_D, link: b.link }); y -= 4; }
      else if (t === 'callout') callout(b);
      else if (t === 'party') party(b);
      else if (t === 'scores') scores(b);
      else if (t === 'checks') checks(b);
      else if (t === 'terms') terms(b);
      else if (t === 'legend') legend(b);
      else if (t === 'space') { ensure(b.h || 10); y -= b.h || 10; }
      // An embedded picture (the marketing calendar's key frames, 23 Sep 2026): bytes are embedded before drawing.
      else if (t === 'image' && b._img) { const w = Math.min(Number(b.w) || 160, CW); const h = b._img.height * (w / b._img.width); ensure(h + 10); page.drawImage(b._img, { x: px(0, w), y: y - h, width: w, height: h }); y -= h + 10; }
    }
  }
  // The legacy putLine the signature block uses (plain left/right placement).
  // deno-lint-ignore no-explicit-any
  function putLine(text: string, size: number, b: boolean, color: any, align: 'l' | 'r', yy: number) { txt(text, M, CW, yy, size, { bold: b, color, align: (align === 'r') !== RTL ? 'e' : 's' }); }

  if (body.cover) cover(body.cover); else legacyHeader();
  if (body.body_html) renderBlocks(parseHtml(String(body.body_html)));
  else if (Array.isArray(body.blocks)) {
    // deno-lint-ignore no-explicit-any
    for (const b of body.blocks as any[]) if ((b?.t || b?.type) === 'image' && b.bytes) { try { b._img = b.kind === 'png' ? await pdf.embedPng(b.bytes) : await pdf.embedJpg(b.bytes); } catch (_e) { b._img = null; } }
    renderBlocks(body.blocks);
  }
  // 14 Sep 2026 (agent: accountant): the signature image rose ~40pt above the space reserved for it and sat on the
  // last line of text (Reminder 2). The drop below the preceding content now fits the tallest of the signature,
  // the rotated stamp and the signatory lines, and the page break reserves exactly that.
  if (doSign || doStamp) { const sigH = sig ? sig.height * (150 / sig.width) : 0, stH = stamp ? stamp.height * (110 / stamp.width) : 0; const drop = Math.max(58, sigH + 4, stH - 26 + 8); ensure(20 + drop + 50); y -= 20; const baseY = y - drop; if (sig) { const w = 150, h = sig.height * (w / sig.width); page.drawImage(sig, { x: M + 90, y: baseY + 4, width: w, height: h }); } putLine(RTL ? 'الموقّع المعتمد' : 'AUTHORISED SIGNATORY', 8, false, MUT, 'l', baseY + 50); page.drawLine({ start: { x: M, y: baseY }, end: { x: M + 230, y: baseY }, thickness: 0.8, color: LINE }); putLine(RTL ? CO_AR.signer : CO.signer, 11, true, NAVY, 'l', baseY - 14); putLine(RTL ? CO_AR.title : CO.title, 9.5, false, MUT, 'l', baseY - 27); putLine(CO.name, 9.5, false, MUT, 'l', baseY - 39); if (stamp) { const w = 110, h = stamp.height * (w / stamp.width); // deno-lint-ignore no-explicit-any
    page.drawImage(stamp, { x: PW - M - 140, y: baseY - 26, width: w, height: h, opacity: 0.9, rotate: { type: 'degrees', angle: -8 } as any }); } y = baseY - 50; }
  footers();

  pdf.setTitle(refText ? refText + ' — ' + title : title);
  pdf.setAuthor(CO.name); pdf.setCreator('QuotesDone pdf_native');
  const bytes = await pdf.save();
  return { ok: true, bytes, title,
    meta: { fonts: { latin: latinFull, arabic: arFull }, glyphs_dropped: dropped, links: linkCount,
      glyph_check: glyphCheck ? 'fontkit' : 'unavailable', lockup_trimmed: lockupTrimmed,
      letterhead_source: CO.source, pages: pdf.getPageCount(), glyphs_dropped_sample: [...droppedSample].join('') } };
}
