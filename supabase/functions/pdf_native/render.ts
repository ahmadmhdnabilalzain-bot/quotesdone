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
import { PDFDocument, StandardFonts, rgb, PDFArray, PDFName, PDFString } from 'https://esm.sh/pdf-lib@1.17.1';
// The published fontkit.d.ts has no default export (TS1192) even though the CJS module esm.sh
// serves does. Import the namespace and take .default when it is there.
import * as fontkitMod from 'https://esm.sh/@pdf-lib/fontkit@1.1.1';
// deno-lint-ignore no-explicit-any
const fontkit = ((fontkitMod as any).default ?? fontkitMod) as any;
import bidiFactory from 'https://esm.sh/bidi-js@1.0.3';
import { footerLines, FALLBACK, LOCKUP, lockupWidthFor, type DocIdentity } from '../_shared/doc_template.ts';
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
const NAVY = rgb(0.047, 0.137, 0.188), TEAL = rgb(0.078, 0.722, 0.651), GOLD = rgb(0.906, 0.71, 0.235), INK = rgb(0.08, 0.094, 0.11), MUT = rgb(0.4, 0.44, 0.52), LINE = rgb(0.9, 0.91, 0.93), WHITE = rgb(1, 1, 1), BANDTXT = rgb(0.82, 0.87, 0.9);
export function isArCode(c: number) { return (c >= 0x600 && c <= 0x6FF) || (c >= 0x750 && c <= 0x77F) || (c >= 0x8A0 && c <= 0x8FF) || (c >= 0xFB50 && c <= 0xFDFF) || (c >= 0xFE70 && c <= 0xFEFF); }
// deno-lint-ignore no-explicit-any
export function hasAr(s: any) { const t = String(s == null ? '' : s); for (const ch of t) { if (isArCode(ch.codePointAt(0) || 0)) return true; } return false; }
// deno-lint-ignore no-explicit-any
const bidi: any = bidiFactory();
const MIRROR: Record<string, string> = { '(': ')', ')': '(', '[': ']', ']': '[', '{': '}', '}': '{', '<': '>', '>': '<' };
function bidiRuns(s: string) { const str = String(s == null ? '' : s); if (!str) return [] as { t: string; rtl: boolean }[]; let levels: any; try { levels = bidi.getEmbeddingLevels(str, 'rtl').levels; } catch (_e) { return [{ t: str, rtl: true }]; } for (let i = 0; i < str.length; i++) { if ('%٪#'.includes(str[i])) { const d = /[0-9]/.test(str[i + 1] || '') ? i + 1 : /[0-9]/.test(str[i - 1] || '') ? i - 1 : -1; if (d >= 0) levels[i] = levels[d]; } } const segs: { t: string; lv: number }[] = []; let st = 0; for (let i = 1; i <= str.length; i++) { if (i === str.length || levels[i] !== levels[st]) { segs.push({ t: str.slice(st, i), lv: levels[st] }); st = i; } } if (!segs.length) return [{ t: str, rtl: true }]; let maxL = 0; for (const sg of segs) if (sg.lv > maxL) maxL = sg.lv; const order = segs.map((_, i) => i); for (let L2 = maxL; L2 >= 1; L2--) { let i = 0; while (i < order.length) { if (segs[order[i]].lv >= L2) { let j = i; while (j < order.length && segs[order[j]].lv >= L2) j++; const sl = order.slice(i, j).reverse(); for (let k = i; k < j; k++) order[k] = sl[k - i]; i = j; } else i++; } } return order.map(i => { const rtl = segs[i].lv % 2 === 1; let t = segs[i].t; if (rtl) { let o = ''; for (const ch of t) o += (MIRROR[ch] || ch); t = o; } return { t, rtl }; }); }
function decodeEnt(s: string) { return String(s || '').replace(/<br\s*\/?>/gi, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;|&rsquo;|&lsquo;/g, "'").replace(/&mdash;/g, '—').replace(/&ndash;/g, '–'); }
function stripTags(s: string) { return decodeEnt(String(s || '').replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim(); }
// deno-lint-ignore no-explicit-any
function parseHtml(frag: string) { const blocks: any[] = []; const re = /<(h2|h3|p|ul|ol|table)\b[^>]*>([\s\S]*?)<\/\1>/gi; let m: any; while ((m = re.exec(frag))) { const tag = m[1].toLowerCase(); const inner = m[2]; if (tag === 'h2') blocks.push({ t: 'h2', text: stripTags(inner) }); else if (tag === 'h3') blocks.push({ t: 'h3', text: stripTags(inner) }); else if (tag === 'p') { const tx = stripTags(inner); if (tx) blocks.push({ t: 'p', text: tx }); } else if (tag === 'ul' || tag === 'ol') { const lis = inner.match(/<li\b[^>]*>([\s\S]*?)<\/li>/gi) || []; lis.forEach((li: string) => { const tx = stripTags(li.replace(/<\/?li[^>]*>/gi, '')); if (tx) blocks.push({ t: 'li', text: tx }); }); } else if (tag === 'table') { const trs = inner.match(/<tr\b[^>]*>([\s\S]*?)<\/tr>/gi) || []; let head: string[] = []; const rows: string[][] = []; trs.forEach((tr: string, ri: number) => { const cells = (tr.match(/<(th|td)\b[^>]*>([\s\S]*?)<\/(?:th|td)>/gi) || []).map((c: string) => stripTags(c.replace(/<\/?(th|td)[^>]*>/gi, ''))); if (ri === 0 && /<th\b/i.test(tr)) head = cells; else rows.push(cells); }); if (!head.length && rows.length) head = rows.shift() as string[]; if (head.length || rows.length) blocks.push({ t: 'table', head, rows, widths: head.map(() => 1 / Math.max(1, head.length)) }); } } return blocks; }

// 5 Aug 2026. Typographic characters are routine in model- and supplier-written prose; normalise
// them to ASCII always, and drop only what the font actually in force cannot encode.
const NORM: Record<string, string> = { '≠': '!=', '≈': '~', '≥': '>=', '≤': '<=', '±': '+/-', '—': '-', '–': '-', '−': '-', '‑': '-', '→': '->', '←': '<-', '×': 'x', '÷': '/', '·': '-', '•': '-', '…': '...', '“': '"', '”': '"', '„': '"', '‘': "'", '’': "'", '′': "'", '″': '"', '‚': ',', '€': 'EUR', '£': 'GBP', '™': '(TM)', '®': '(R)', '©': '(C)', '½': '1/2', '¼': '1/4', '¾': '3/4', '\u00a0': ' ', '\u200b': '', '\u200e': '', '\u200f': '', '\u202a': '', '\u202b': '', '\u202c': '' };

// Subsetting is NOT why Arabic went missing (it was the first suspect, and embedding the face whole
// changed nothing); fontkit's Arabic shaper is — see arabic_shape.ts. Subset stays on.
const AR_SUBSET = true;
// deno-lint-ignore no-explicit-any
export async function renderPdf(input: any, deps: RenderDeps): Promise<RenderResult> {
  const CO: DocIdentity = deps.identity ?? FALLBACK;
  const fetchBytes = deps.fetchBytes;
  let body = input ?? {};
  const lang = ['en', 'ar', 'bi'].includes(String(body.lang)) ? String(body.lang) : 'en';
  let L = lang === 'bi' ? 'en' : lang;
  const pdf = await PDFDocument.create(); pdf.registerFontkit(fontkit);
  let font = await pdf.embedFont(StandardFonts.Helvetica);
  let bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  let latinFull = false, arFull = false;
  try { const sr = await fetchBytes('qd_sora_regular.ttf'); const sb = await fetchBytes('qd_sora_bold.ttf'); if (sr) { font = await pdf.embedFont(sr, { subset: true }); latinFull = true; } if (sb) bold = await pdf.embedFont(sb, { subset: true }); } catch (_e) { /* Helvetica stands */ }
  const PW = 595.28, PH = 841.89, M = 48; const CW = PW - 2 * M; const BAND = 92, BANDSLIM = 42;
  const opt = body.options || {};
  const letterhead = !!opt.letterhead, doSign = !!opt.sign, doStamp = !!opt.stamp;
  const isQuote = !!body.quote;
  const probe = JSON.stringify(body.quote || '') + JSON.stringify(body.quote_ar || '') + String(body.body_html || '') + JSON.stringify(body.blocks || '') + String(body.title || '');
  const needAr = lang !== 'en' || hasAr(probe);
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
      const rep = NORM[ch];
      if (rep !== undefined) { out += rep; continue; }
      const cp = ch.codePointAt(0) || 0;
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
  function safeDeep(v: any): any {
    if (typeof v === 'string') return safeText(v);
    if (Array.isArray(v)) return v.map(safeDeep);
    // deno-lint-ignore no-explicit-any
    if (v && typeof v === 'object') { const o: any = {}; for (const k of Object.keys(v)) o[k] = safeDeep(v[k]); return o; }
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
  // deno-lint-ignore no-explicit-any
  function armPage(p: any) { const orig = p.drawText.bind(p);
    // deno-lint-ignore no-explicit-any
    // A draw that fails twice loses the WHOLE string, and until 14 Sep 2026 that loss was silent:
    // every Arabic run died here while the response reported glyphs_dropped 0. It is counted now.
    p.drawText = (t: any, o: any) => { try { orig(String(t), o); } catch (_e) { try { orig(safeText(String(t)), o); } catch (_e2) { for (const ch of String(t)) { if (ch.trim()) drop(ch); } } } };
    return p; }

  const title = String(body.title || 'Document');
  const refText = body.ref ? String(body.ref) : '';
  const dateEn = body.date ? String(body.date) : new Date().toLocaleDateString('en-GB', { day: '2-digit', month: 'long', year: 'numeric' });
  // Western digits in the Arabic date too: the amounts, references and quantities on the same
  // page are Western, and a page mixing ٢٠٢٦ with 2026 reads as two documents stapled together.
  const dateAr = body.date_ar ? String(body.date_ar) : new Date().toLocaleDateString('ar-AE-u-nu-latn', { day: '2-digit', month: 'long', year: 'numeric' });
  function dateFor() { return L === 'ar' ? dateAr : dateEn; }
  let lockupTrimmed = true;
  const logoLightImg = await (async () => { const b = await fetchBytes(LOCKUP.dark); return b ? await pdf.embedPng(b) : null; })();
  const logoImg = await (async () => { const b = await fetchBytes(LOCKUP.light); return b ? await pdf.embedPng(b) : null; })();
  const logoMaster = logoLightImg ? null : await (async () => { lockupTrimmed = false; const b = await fetchBytes('qd_lockup_dark.png'); return b ? await pdf.embedPng(b) : null; })();
  const sig = doSign ? await (async () => { const b = await fetchBytes('qd_signature.png'); return b ? await pdf.embedPng(b) : null; })() : null;
  const stamp = doStamp ? await (async () => { const b = await fetchBytes('qd_stamp.png'); return b ? await pdf.embedPng(b) : null; })() : null;

  let page = armPage(pdf.addPage([PW, PH])); let y = PH - M; let pageNo = 1;
  function fontFor(s: any, b: boolean) { return hasAr(s) ? (b ? arBold : arReg) : (b ? bold : font); }
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
  function measRTL(s: string, f: any, size: number) { let w = 0; for (const r of bidiRuns(s)) w += W(visual(r), f, size); return w; }
  function drawRTL(s: string, size: number, f: any, color: any, yy: number, xRight: number) { const runs = bidiRuns(s).map((r) => ({ t: visual(r), rtl: r.rtl })); let tot = 0; const ws = runs.map(r => { const w = W(r.t, f, size); tot += w; return w; }); let x = xRight - tot; for (let i = 0; i < runs.length; i++) { if (runs[i].t.trim() !== '') page.drawText(runs[i].t, { x, y: yy, size, font: f, color }); x += ws[i]; } }
  function putLine(text: string, size: number, b: boolean, color: any, align: 'l' | 'r', yy: number, x0 = M, w = CW, link?: unknown) { const f = fontFor(text, b); if (hasAr(text)) { const wr = measRTL(text, f, size); const xr = align === 'r' ? x0 + w : x0 + wr; drawRTL(text, size, f, color, yy, xr); if (link) linkAt(page, xr - wr, yy, wr, size, link); return wr; } const ww = W(text, f, size); const x = align === 'r' ? (x0 + w - ww) : x0; page.drawText(text, { x, y: yy, size, font: f, color }); if (link) linkAt(page, x, yy, ww, size, link); return ww; }
  const [fl1, fl2] = footerLines(CO);
  const footerEn = letterhead ? fl1 : 'QuotesDone · quotesdone.com';
  const footerEn2 = letterhead ? fl2 : '';
  // The page number is right-aligned by its own width; it sat at a fixed x and a long legal line
  // ran underneath it.
  function drawFooter() { page.drawLine({ start: { x: M, y: 54 }, end: { x: PW - M, y: 54 }, thickness: 0.5, color: LINE }); page.drawLine({ start: { x: M, y: 54 }, end: { x: M + 34, y: 54 }, thickness: 1.6, color: GOLD }); page.drawText(footerEn, { x: M, y: 42, size: 7, font, color: MUT }); if (footerEn2) page.drawText(footerEn2, { x: M, y: 32, size: 7, font, color: MUT }); const pn = (L === 'ar' ? 'Page ' : 'Page ') + pageNo; page.drawText(pn, { x: PW - M - W(pn, font, 7), y: 32, size: 7, font, color: MUT }); }
  function headerBand(slim: boolean) { const h = slim ? BANDSLIM : BAND; page.drawRectangle({ x: 0, y: PH - h, width: PW, height: h, color: NAVY }); page.drawRectangle({ x: 0, y: PH - h, width: PW, height: 2.6, color: GOLD }); page.drawRectangle({ x: 0, y: PH - h + 2.6, width: PW, height: 1, color: TEAL }); const lg = logoLightImg || logoImg || logoMaster; if (lg) { const hh = lockupTrimmed ? (slim ? CO.logoPt * 0.8 : CO.logoPt) : lg.height * ((slim ? 92 : 128) / lg.width); const w = lockupTrimmed ? lockupWidthFor(hh) : (slim ? 92 : 128); page.drawImage(lg, { x: M, y: PH - (h / 2) - (hh / 2) + (slim ? 0 : 2), width: w, height: hh }); } if (!slim && letterhead) { const lines = [CO.name, CO.licence + ' · ' + CO.permit, CO.email + ' · ' + CO.phone]; let ly = PH - 26; lines.forEach((ln, i) => { const f = i === 0 ? bold : font; const s = i === 0 ? 11 : 8; page.drawText(ln, { x: PW - M - W(ln, f, s), y: ly - s, size: s, font: f, color: i === 0 ? WHITE : BANDTXT }); ly -= (i === 0 ? 15 : 11); }); } return PH - h; }
  function quoteHeader() { const by = headerBand(false); y = by - 22; if (L === 'ar') { putLine('عرض أسعار', 22, true, NAVY, 'r', y - 16, M, CW); if (refText) putLine('الرقم المرجعي: ' + refText, 10, false, MUT, 'r', y - 32, M, CW); putLine('التاريخ: ' + dateFor(), 10, false, MUT, 'r', y - 46, M, CW); } else { page.drawText('QUOTATION', { x: M, y: y - 16, size: 22, font: bold, color: NAVY }); if (refText) page.drawText('Ref: ' + refText, { x: M, y: y - 32, size: 10, font, color: MUT }); page.drawText('Date: ' + dateFor(), { x: M, y: y - 46, size: 10, font, color: MUT }); } y = y - 64; drawFooter(); }
  // The reference is printed under the title now: a report the customer takes to a meeting has to
  // be citable, and the ref was passed in and silently never drawn on non-quote documents.
  function docHeader() { const by = headerBand(false); y = by - 24; const ar = L === 'ar'; putLine(title, 20, true, NAVY, (ar || hasAr(title)) ? 'r' : 'l', y - 18); y -= 24; const meta = (refText ? (ar ? 'الرقم المرجعي: ' + refText : 'Ref: ' + refText) + ' · ' : '') + (ar ? CO_AR.city : CO.city) + ' · ' + dateFor(); putLine(meta, 10, false, MUT, ar ? 'r' : 'l', y - 10); y -= 22; drawFooter(); }
  function newSection() { page = armPage(pdf.addPage([PW, PH])); pageNo++; y = PH - M; }
  function ensure(h: number) { if (y - h < 70) { page = armPage(pdf.addPage([PW, PH])); pageNo++; const by = headerBand(true); drawFooter(); y = by - 18; } }
  function wrap(t: string, f: any, s: number, w: number) { const isAr = hasAr(t); const meas = (str: string) => isAr ? measRTL(str, f, s) : W(str, f, s); const words = String(t == null ? '' : t).split(/\s+/); const lines: string[] = []; let cur = ''; for (const wd0 of words) { const test = cur ? cur + ' ' + wd0 : wd0; if (meas(test) > w && cur) { lines.push(cur); cur = wd0; } else cur = test; } if (cur) lines.push(cur); return lines.length ? lines : ['']; }
  function para(t: string, s = 11, b = false, color = INK, lh = 1.45, x0 = M, w = CW, link?: unknown) { const isAr = hasAr(t); const f = fontFor(t, b); for (const ln of wrap(t, f, s, w)) { ensure(s * lh); if (isAr) { const wr = measRTL(ln, f, s); drawRTL(ln, s, f, color, y - s, x0 + w); if (link) linkAt(page, x0 + w - wr, y - s, wr, s, link); } else { page.drawText(ln, { x: x0, y: y - s, size: s, font: f, color }); if (link) linkAt(page, x0, y - s, W(ln, f, s), s, link); } y -= s * lh; } }
  function bullet(t: string, s = 11, link?: unknown) { const isAr = hasAr(t); if (isAr) { para('•  ' + t, s, false, INK, 1.4, M, CW - 10, link); } else { para('•  ' + t, s, false, INK, 1.4, M + 10, CW - 12, link); } }
  function headingBi(en: string, ar: string) { ensure(28); y -= 8; if (L === 'ar') { putLine(ar || en, 11, true, TEAL, 'r', y - 11); } else { page.drawText(String(en).toUpperCase(), { x: M, y: y - 11, size: 11, font: bold, color: TEAL }); } y -= 13; page.drawLine({ start: { x: M, y }, end: { x: PW - M, y }, thickness: 0.6, color: LINE }); if (L === 'ar') page.drawLine({ start: { x: PW - M - 34, y }, end: { x: PW - M, y }, thickness: 1.6, color: GOLD }); else page.drawLine({ start: { x: M, y }, end: { x: M + 34, y }, thickness: 1.6, color: GOLD }); y -= 10; }
  function headingAuto(t: string, link?: unknown) { const isAr = hasAr(t); ensure(28); y -= 8; putLine(t, 11, true, TEAL, isAr ? 'r' : 'l', y - 11, M, CW, link); y -= 13; page.drawLine({ start: { x: M, y }, end: { x: PW - M, y }, thickness: 0.6, color: LINE }); if (isAr) page.drawLine({ start: { x: PW - M - 34, y }, end: { x: PW - M, y }, thickness: 1.6, color: GOLD }); else page.drawLine({ start: { x: M, y }, end: { x: M + 34, y }, thickness: 1.6, color: GOLD }); y -= 10; }
  function h3(t: string, link?: unknown) { ensure(20); putLine(t, 13, true, NAVY, hasAr(t) ? 'r' : 'l', y - 12, M, CW, link); y -= 20; }
  function space(h = 8) { ensure(h); y -= h; }
  // deno-lint-ignore no-explicit-any
  const cellText = (c: any) => (c && typeof c === 'object' && !Array.isArray(c)) ? String(c.text == null ? '' : c.text) : String(c == null ? '' : c);
  // deno-lint-ignore no-explicit-any
  const cellLink = (c: any) => (c && typeof c === 'object' && !Array.isArray(c) && typeof c.link === 'string') ? c.link : null;
  // A table row taller than a page used to be drawn from `y` downward straight through the footer
  // and off the paper: ensure() can only start a fresh page, it cannot make one taller. Such a row
  // is now split across pages, carrying the remaining lines of every cell, with the header redrawn.
  // deno-lint-ignore no-explicit-any
  function blockTable(head: string[], rows: any[][], widths: number[], rtl = false) {
    let H = head.slice(), R = rows.map(r => r.slice()), Wd = widths.slice();
    if (rtl) { H.reverse(); R = R.map(r => r.slice().reverse()); Wd = Wd.slice().reverse(); }
    const colW = Wd.map(w => w * CW);
    const drawHead = () => { ensure(22); page.drawRectangle({ x: M, y: y - 20, width: CW, height: 20, color: NAVY }); let cx = M; H.forEach((h, i) => { const isAr = hasAr(h); const f = isAr ? arBold : bold; if (isAr || rtl) { if (isAr) drawRTL(String(h), 9, f, WHITE, y - 14, cx + colW[i] - 8); else page.drawText(String(h), { x: cx + colW[i] - 8 - W(String(h), f, 9), y: y - 14, size: 9, font: f, color: WHITE }); } else page.drawText(String(h), { x: cx + 8, y: y - 14, size: 9, font: f, color: WHITE }); cx += colW[i]; }); y -= 20; page.drawLine({ start: { x: M, y }, end: { x: M + CW, y }, thickness: 1.4, color: GOLD }); };
    drawHead();
    const LH = 13, maxLinesPerPage = Math.floor((PH - 70 - BANDSLIM - 18 - 22 - 8) / LH);
    R.forEach((r) => {
      const cl = r.map((c, i) => { const tx = cellText(c); const isAr = hasAr(tx); const f = isAr ? arReg : font; return { isAr, f, link: cellLink(c), lines: wrap(tx, f, 10, colW[i] - 14) }; });
      let from = 0; const total = Math.max(1, ...cl.map(c => c.lines.length));
      while (from < total) {
        const fit = Math.max(1, Math.min(total - from, Math.floor((y - 70 - 8) / LH)));
        if ((y - 70 - 8) / LH < 1 || (fit < total - from && fit < 3 && total - from <= maxLinesPerPage)) { page = armPage(pdf.addPage([PW, PH])); pageNo++; const by = headerBand(true); drawFooter(); y = by - 18; drawHead(); continue; }
        const n = Math.min(fit, total - from); const rh = n * LH + 8;
        let cx = M;
        r.forEach((_c, i) => { const cell = cl[i]; const col = cell.link ? TEAL : INK; let ly = y - 14; for (const ln of cell.lines.slice(from, from + n)) { if (cell.isAr) { const wr = measRTL(ln, cell.f, 10); drawRTL(ln, 10, cell.f, col, ly, cx + colW[i] - 8); if (cell.link) linkAt(page, cx + colW[i] - 8 - wr, ly, wr, 10, cell.link); } else if (rtl) { const wl = W(ln, cell.f, 10); page.drawText(ln, { x: cx + colW[i] - 8 - wl, y: ly, size: 10, font: cell.f, color: col }); if (cell.link) linkAt(page, cx + colW[i] - 8 - wl, ly, wl, 10, cell.link); } else { page.drawText(ln, { x: cx + 8, y: ly, size: 10, font: cell.f, color: col }); if (cell.link) linkAt(page, cx + 8, ly, W(ln, cell.f, 10), 10, cell.link); } ly -= LH; } cx += colW[i]; });
        y -= rh; from += n;
        page.drawLine({ start: { x: M, y }, end: { x: PW - M, y }, thickness: 0.5, color: LINE });
        if (from < total) { page = armPage(pdf.addPage([PW, PH])); pageNo++; const by = headerBand(true); drawFooter(); y = by - 18; drawHead(); }
      }
    });
    y -= 2;
  }
  // In an Arabic document the first pair sits in the RIGHT column and every value right-aligns,
  // Arabic or not: a Latin value ("AED 18,500", "2 weeks") hanging off the left edge of an
  // otherwise right-to-left grid is what made the Arabic quotation look like a broken English one.
  function blockKV(pairs: [string, string][]) { const rtlDoc = L === 'ar'; const colW = CW / 2; const rows = Math.ceil(pairs.length / 2); for (let r = 0; r < rows; r++) { let maxLines = 1; for (let c = 0; c < 2; c++) { const idx = r * 2 + c; if (idx >= pairs.length) continue; const vv = String(pairs[idx][1]); const vfm = hasAr(vv) ? arBold : bold; const n = wrap(vv, vfm, 11, colW - 12).length; if (n > maxLines) maxLines = n; } const rowH = 29 + maxLines * 13; ensure(rowH); for (let c = 0; c < 2; c++) { const idx = r * 2 + c; if (idx >= pairs.length) continue; const x = rtlDoc ? (M + (1 - c) * colW) : (M + c * colW); const [k, v] = pairs[idx]; putLine(String(k), 8, false, MUT, (rtlDoc || hasAr(k)) ? 'r' : 'l', y - 12, x + 4, colW - 8); const vAr = hasAr(v); const vf = vAr ? arBold : bold; const vlines = wrap(String(v), vf, 11, colW - 12); let vy = y - 26; for (const ln of vlines) { if (vAr) drawRTL(ln, 11, vf, NAVY, vy, x + colW - 8); else if (rtlDoc) page.drawText(ln, { x: x + colW - 8 - W(ln, vf, 11), y: vy, size: 11, font: vf, color: NAVY }); else page.drawText(ln, { x: x + 4, y: vy, size: 11, font: vf, color: NAVY }); vy -= 13; } } y -= rowH; } }
  function blockTotal(value: string) { ensure(64); const bw = 270, bx = PW - M - bw; const qt = L === 'ar' ? 'القيمة المعروضة' : 'Quoted total'; const lab = L === 'ar' ? 'الإجمالي' : 'TOTAL'; page.drawRectangle({ x: bx, y: y - 58, width: bw, height: 58, borderColor: TEAL, borderWidth: 2 }); page.drawRectangle({ x: bx, y: y - 4, width: bw, height: 4, color: GOLD }); const qf = hasAr(qt) ? arReg : font; if (hasAr(qt)) drawRTL(qt, 11, qf, INK, y - 22, bx + bw - 14); else page.drawText(qt, { x: bx + 14, y: y - 22, size: 11, font: qf, color: INK }); page.drawText(value, { x: hasAr(qt) ? (bx + 14) : (bx + bw - 14 - W(value, font, 11)), y: y - 22, size: 11, font, color: INK }); page.drawRectangle({ x: bx, y: y - 58, width: bw, height: 30, color: NAVY }); const lf = hasAr(lab) ? arBold : bold; if (hasAr(lab)) drawRTL(lab, 13, lf, WHITE, y - 49, bx + bw - 14); else page.drawText(lab, { x: bx + 14, y: y - 49, size: 13, font: lf, color: WHITE }); page.drawText(value, { x: hasAr(lab) ? (bx + 14) : (bx + bw - 14 - W(value, bold, 15)), y: y - 50, size: 15, font: bold, color: WHITE }); y -= 66; }
  function blockBadge(en: string, ar: string, subEn: string, subAr: string) { ensure(46); const lab = L === 'ar' ? ('الجهة مقدّمة العرض') : 'QUOTING PARTY'; putLine(lab, 8, false, MUT, L === 'ar' ? 'r' : 'l', y - 10); const txt = L === 'ar' ? ar : en; const tAr = hasAr(txt); const f = tAr ? arBold : bold; const bw = (tAr ? measRTL(txt, f, 12) : W(txt, f, 12)) + 24; const bx = L === 'ar' ? (PW - M - bw) : M; page.drawRectangle({ x: bx, y: y - 34, width: bw, height: 22, color: NAVY }); if (tAr) drawRTL(txt, 12, f, WHITE, y - 29, bx + bw - 12); else page.drawText(txt, { x: bx + 12, y: y - 29, size: 12, font: f, color: WHITE }); const sub = L === 'ar' ? subAr : subEn; if (sub) { putLine(sub, 9, false, MUT, L === 'ar' ? 'r' : 'l', y - 28, L === 'ar' ? M : (bx + bw + 14), L === 'ar' ? (PW - 2 * M - bw - 14) : (CW - bw - 14)); } y -= 46; }
  // deno-lint-ignore no-explicit-any
  function renderBlocks(blocks: any[]) { for (const b of blocks) { const t = b.t || b.type; if (t === 'h2' || t === 'heading') headingAuto(b.text || '', b.link); else if (t === 'h3') h3(b.text || '', b.link); else if (t === 'p' || t === 'para') para(b.text || '', b.size || 11, !!b.bold, INK, 1.45, M, CW, b.link); else if (t === 'li') bullet(b.text || '', 11, b.link); else if (t === 'kv') blockKV(b.pairs || []); else if (t === 'table') { const rtl = L === 'ar' || hasAr((b.head || []).join(' ') + ' ' + (b.rows || []).flat().map(cellText).join(' ')); blockTable(b.head || [], b.rows || [], b.widths || (b.head || []).map(() => 1 / Math.max(1, (b.head || []).length)), rtl); } else if (t === 'total') blockTotal(b.value || ''); else if (t === 'note') para(b.text || '', 9, false, MUT, 1.45, M, CW, b.link); else if (t === 'space') space(b.h || 10); } }
  const disEn = "This quotation is presented in QuotesDone's standardized format from the supplier's submitted quote. Figures and scope are as quoted by the supplier; verify final details before ordering. QuotesDone charges the customer a 3% facilitation fee on the quoted value at the point of contact reveal.";
  const disAr = 'هذا العرض مقدّم بصيغة QuotesDone الموحّدة استناداً إلى عرض المورّد. القيم والنطاق كما وردت من المورّد؛ يُرجى التحقق من التفاصيل النهائية قبل الطلب. تتقاضى QuotesDone رسوم تيسير بنسبة 3% من قيمة العرض عند كشف بيانات التواصل.';
  // deno-lint-ignore no-explicit-any
  function renderQuote(q: any) { const rtlT = L === 'ar';
    blockBadge('Supplier ' + (q.supplier_label || '1'), 'المورّد ' + (q.supplier_label || '1'), 'Identity revealed only after the customer pays the reveal fee.', 'تُكشف هوية المورّد فقط بعد سداد العميل رسوم الكشف.');
    // Trade and emirate on one line, the request on the next. As one line, an Arabic trade name
    // followed by an English request was re-ordered by the bidi algorithm across the wrap and its
    // brackets landed on the wrong line (first Arabic sample, 14 Sep 2026).
    headingBi('Job', 'بيان العمل');
    const jobMeta = [q.job_category, q.emirate].filter((v: unknown) => v != null && String(v).trim() !== '').join(' · ');
    if (jobMeta) para(jobMeta, 11, true, NAVY);
    if (q.job_summary) para(String(q.job_summary));
    space(2); headingBi('Scope of supply', 'نطاق التوريد');
    const items = Array.isArray(q.items) ? q.items : [];
    if (items.length) { const head = L === 'ar' ? ['#', 'الوصف', 'الكمية', 'الوحدة'] : ['#', 'Description', 'Qty', 'Unit']; blockTable(head, items.map((it: any, i: number) => [String(i + 1), String(it.desc || ''), String(it.qty || ''), String(it.unit || '')]), [0.07, 0.69, 0.11, 0.13], rtlT); }
    else if (q.scope) para(String(q.scope));
    if (items.length && q.scope) { space(3); para(String(q.scope), 10, false, rgb(0.2, 0.25, 0.33)); }
    headingBi('Commercial terms', 'الشروط التجارية');
    const TL = (en: string, ar: string) => L === 'ar' ? ar : en;
    blockKV([[TL('Lead time', 'مدة التنفيذ'), q.lead_time || '—'], [TL('Quote validity', 'صلاحية العرض'), q.validity || '—'], [TL('Warranty', 'الضمان'), q.warranty || '—'], [TL('Payment terms', 'شروط الدفع'), q.payment_terms || '—']]);
    if (q.conditions) { headingBi('Conditions', 'الشروط'); para(String(q.conditions)); }
    if (q.exclusions) { headingBi('Exclusions', 'الاستثناءات'); para(String(q.exclusions)); }
    if (q.notes) { headingBi('Notes', 'ملاحظات'); para(String(q.notes)); }
    space(6); blockTotal('AED ' + Number(q.total || 0).toLocaleString('en-AE', { minimumFractionDigits: 2, maximumFractionDigits: 2 }));
    space(8); para(L === 'ar' ? disAr : disEn, 9, false, MUT);
    if (q.source_note) { space(2); para(String(q.source_note), 9, false, MUT); }
    // Back to this quote on its request in the portal (quote_documents.ts sets q.link).
    if (q.link) { space(4); para(L === 'ar' ? 'افتح هذا العرض في طلبك على بوابة QuotesDone' : 'Open this quote on your request in the QuotesDone portal', 10, true, TEAL, 1.45, M, CW, q.link); }
  }

  if (isQuote) {
    if (lang === 'bi') { const qEn = body.quote; const qAr = body.quote_ar || body.quote; L = 'en'; quoteHeader(); renderQuote(qEn); newSection(); L = 'ar'; quoteHeader(); renderQuote(qAr); }
    else { L = lang; quoteHeader(); renderQuote(body.quote); }
  } else {
    L = lang === 'bi' ? 'en' : lang; docHeader();
    if (body.body_html) renderBlocks(parseHtml(String(body.body_html)));
    else if (Array.isArray(body.blocks)) renderBlocks(body.blocks);
    if (doSign || doStamp) { ensure(120); y -= 20; const baseY = y - 58; if (sig) { const w = 150, h = sig.height * (w / sig.width); page.drawImage(sig, { x: M + 90, y: baseY + 4, width: w, height: h }); } const sLabel = lang === 'ar' ? 'الموقّع المعتمد' : 'AUTHORISED SIGNATORY'; putLine(sLabel, 8, false, MUT, 'l', baseY + 50); page.drawLine({ start: { x: M, y: baseY }, end: { x: M + 230, y: baseY }, thickness: 0.8, color: rgb(0.2, 0.25, 0.33) }); const nm = lang === 'ar' ? CO_AR.signer : CO.signer; const tt = lang === 'ar' ? CO_AR.title : CO.title; putLine(nm, 11, true, NAVY, 'l', baseY - 14); putLine(tt, 9.5, false, MUT, 'l', baseY - 27); putLine(CO.name, 9.5, false, MUT, 'l', baseY - 39); if (stamp) { const w = 110, h = stamp.height * (w / stamp.width); page.drawImage(stamp, { x: PW - M - 140, y: baseY - 26, width: w, height: h, opacity: 0.9, rotate: { type: 'degrees', angle: -8 } as any }); } y = baseY - 50; }
  }

  pdf.setTitle(refText ? refText + ' — ' + title : title);
  pdf.setAuthor(CO.name); pdf.setCreator('QuotesDone pdf_native');
  const bytes = await pdf.save();
  return { ok: true, bytes, title,
    meta: { fonts: { latin: latinFull, arabic: arFull }, glyphs_dropped: dropped, links: linkCount,
      glyph_check: glyphCheck ? 'fontkit' : 'unavailable', lockup_trimmed: lockupTrimmed,
      letterhead_source: CO.source, pages: pdf.getPageCount(), glyphs_dropped_sample: [...droppedSample].join('') } };
}
