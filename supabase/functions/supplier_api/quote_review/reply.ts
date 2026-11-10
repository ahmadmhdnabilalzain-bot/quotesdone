import { readInstallation, readWarranty } from '../../_shared/line_specs/assess.ts';
import { normText, VAGUE } from '../../_shared/line_specs/model.ts';
import { readVat, type VatTreatment } from '../../_shared/line_specs/vat.ts';
import { maskIdentityNumbers } from '../../_shared/identity_numbers.ts';
import { scrubIdentity } from '../../drawing_boq/boq_from_text.ts';
import { type Issue, type IssueCode } from './types.ts';

// ---------------------------------------------------------------------------------------------
// The supplier's reply, read by rule: the details they state, the choice they make, the question they ask.
// ---------------------------------------------------------------------------------------------
export type Correction =
  | { field: 'validity' | 'lead_time' | 'warranty'; value: string }
  // The treatment is the one readVat returns, never free text — 'not_stated' is not a correction.
  | { field: 'vat_treatment'; value: Exclude<VatTreatment, 'not_stated'> }
  | { field: 'price_ex_vat'; value: number }
  | { field: 'installation'; included: 'yes' | 'no'; detail: string | null }
  | { field: 'warranty_terms'; period: string | null; coverage: string | null }
  | { field: 'aed' }
  | { field: 'boq_excluded' | 'qty_explained'; boq_line: number; value: string; what?: 'qty' | 'unit' }
  | { field: 'line_spec'; line_no: number; attr: string; value: string }
  /** A price typed for a BOQ line: the rate, the amount, or both (at least one). */
  | { field: 'boq_price'; boq_line: number; unit_price: number | null; amount: number | null }
  // EVERY OPEN POINT CAN BE CLOSED FROM THE CHAT (audit 21 Sep 2026, finding 2). Before these, a
  // supplier's own unpriced line, a total that did not add up and a customer's material had no reply
  // that closed them — the only way out was a new file.
  /** A price typed for the supplier's OWN line N (a line_unpriced point, not a BOQ line). */
  | { field: 'line_price'; line_no: number; unit_price: number | null; amount: number | null }
  /** "total AED 65,960": the quotation's total, re-stated. */
  | { field: 'total'; value: number }
  /** "discount AED 500": why the lines and the total differ. */
  | { field: 'total_explained'; value: string }
  /** "glass: 6mm clear tempered" for a material the customer named (terms_spec.components). */
  | { field: 'component'; key: string; value: string; label_en: string; label_ar: string };
export type Topic = 'vat' | 'validity' | 'currency' | 'boq' | 'customer' | 'delivery' | 'warranty' | 'installation' | 'missing' | 'general';
export type ReplyRead = { corrections: Correction[]; choice: 'generate' | 'reupload' | null; submit: boolean; topic: Topic | null };

/** Supplier text that becomes part of a quotation is scrubbed of contact details and identity numbers. */
const clean = (s: string, n = 160) => maskIdentityNumbers(scrubIdentity(normText(s))).slice(0, n).trim();
const DUR = String.raw`\d+(?:\.\d+)?\s*(?:-\s*\d+\s*)?(?:working\s*|business\s*)?(?:days?|weeks?|months?|يوم(?:ا|اً)?|أيام|يوم عمل|أيام عمل|أسبوع|أسابيع|اسبوع|اسابيع|شهر|أشهر|شهور)`;
const DATE = String.raw`\d{4}-\d{2}-\d{2}|\d{1,2}[\/.\-]\d{1,2}[\/.\-]\d{2,4}|\d{1,2}\s+[A-Za-z؀-ۿ]{3,9}\s*,?\s*\d{4}`;
const RE_VALIDITY = new RegExp(String.raw`(?:validity|valid(?:\s+for|\s+until|\s+till)?|offer\s+valid|صلاحية(?:\s+العرض)?|الصلاحية|ساري(?:ة)?(?:\s+لمدة)?)\s*[:\-–]?\s*(?:is\s+|of\s+|for\s+|لمدة\s+)?(${DUR}|${DATE})`, 'i');
const RE_LEAD = new RegExp(String.raw`(?:lead\s*time|delivery(?:\s+(?:time|period|date))?|deliver(?:ed|y)?\s+(?:in|within|by|on)|مدة\s+التسليم|مدة\s+التنفيذ|التسليم|تسليم)\s*[:\-–]?\s*(?:is\s+|in\s+|within\s+|by\s+|on\s+|خلال\s+)?(${DUR}|${DATE})`, 'i');
const RE_EXVAT = /(?:ex(?:cl(?:uding|usive|\.)?)?\.?\s*(?:of\s*)?vat|before\s*vat|غير\s*شامل\s*(?:ال)?ضريبة(?:\s*القيمة\s*المضافة)?|قبل\s*(?:ال)?ضريبة)[^\d\n]{0,25}([\d][\d,]*(?:\.\d+)?)|([\d][\d,]*(?:\.\d+)?)\s*(?:aed|درهم)?\s*(?:ex(?:cl(?:uding|\.)?)?\.?\s*vat|before\s*vat|غير\s*شامل\s*(?:ال)?ضريبة)/i;
const LINE = String.raw`(?:line|item|بند|البند|بندي)\s*#?\s*(\d{1,3})`;
// SEVERAL ANSWERS IN ONE MESSAGE (audit 21 Sep 2026, finding 14): "line 1 board: Knauf. line 2
// thickness: 15mm. line 2 frame: …" — a value that ran to the end of the line swallowed every answer
// after the first, and the acknowledgement echoed the lot. A value now ends where the next "line N"
// begins, at a sentence end before it, at ";" or at the end of the line.
const NEXT_LINE = String.raw`\s*[.;,]?\s*(?:boq\s*|جدول\s*الكميات\s*)?(?:line|item|بند|البند|بندي)\s*#?\s*\d`;
const VAL = (min: number, max: number) => String.raw`((?:(?!${NEXT_LINE}|[.;؛]\s+\S)[^\n;؛]){${min},${max}})`;
const RE_EXCLUDED = new RegExp(String.raw`(boq\s*|جدول\s*الكميات\s*)?${LINE}[^.\n;]{0,40}?(excluded|not\s+included|by\s+others|not\s+in\s+(?:our|my)\s+scope|مستثنى|غير\s+مشمول|خارج\s+النطاق|من\s+قبل\s+الغير)${VAL(0, 100)}`, 'gi');
const RE_QTYWHY = new RegExp(String.raw`(boq\s*|جدول\s*الكميات\s*)?${LINE}[^.\n;]{0,30}?(quantity|qty|unit|الكمية|الوحدة)\s*[:\-–]?\s*${VAL(3, 140)}`, 'gi');
// The attribute name never runs across the next "line N" either: "line 3 excluded — by others. line 1
// thickness: 12.5mm" read "excluded — by others. line 1 thickness" as line 3's attribute.
const RE_SPEC = new RegExp(String.raw`${LINE}\s*[,:\-–]?\s*((?:(?!${NEXT_LINE})[^\n:=;]){2,40}?)\s*[:=]\s*${VAL(1, 120)}`, 'gi');
// THE PRICE GRAMMAR (audit 21 Sep 2026, finding 2: "BOQ line 1: AED 95.00 per m2 … = AED 30,400" and
// the review's own "BOQ line 1 AED 30,400" both answered "I could not match that to an open point").
// A clause is the text from "line N" to the next "line N" (or ";" / end). Inside it, a figure is:
//   a RATE when it is followed by "per <unit>", "/<unit>", "لكل", "each", or preceded by "@", "rate", "unit price", "سعر الوحدة";
//   an AMOUNT when it is preceded by "=", "total", "amount", "المبلغ", "الإجمالي", or when it is the only figure with no rate marker;
//   two bare figures are rate then amount (the order every quotation writes them in).
// Arabic-Indic digits are normalised first (normText). Nothing is guessed from an unmarked single
// figure beyond that rule, which the review states in its own words to the supplier.
const MONEY = String.raw`(?:AED|Dhs?\.?|درهم|د\.إ\.?)?\s*(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)\s*(?:AED|Dhs?\.?|درهم|د\.إ\.?)?`;
const RE_PRICE_CLAUSE = new RegExp(String.raw`(boq\s*|جدول\s*الكميات\s*)?${LINE}\s*[,:\-–]?\s*${VAL(1, 200)}`, 'gi');
const RE_FIG = new RegExp(MONEY, 'g');
// A total re-stated at the start of a sentence ("Total AED 65,960", "الإجمالي 65960 درهم") — never the
// "= total" inside a "line N" price clause. A discount states why the lines and the total differ.
const RE_TOTAL = new RegExp(String.raw`(?:^|[.;؛\n]\s*)(?:the\s+)?(?:grand\s+|net\s+)?(?:total|الإجمالي|المجموع)(?:\s+(?:is|should\s+be|excluding\s+vat|ex\.?\s*vat))?\s*[:=]?\s*${MONEY}`, 'i');
const RE_DISCOUNT = new RegExp(String.raw`(?:discount|rebate|خصم)[^\d\n]{0,20}${MONEY}`, 'i');
// "each" / "للوحدة" may end the message ("line 4 AED 150 each"); "per" / "/" / "لكل" name a unit after them.
const RATE_AFTER = /^\s*(?:(?:per|\/|لكل|لل|a\s)\s*\S|each\b|للوحدة)/i;
const RATE_BEFORE = /(?:@|rate|unit\s*price|price\s*per|سعر\s*الوحدة|السعر\s*لكل|بسعر)\s*[:=]?\s*$/i;
const AMOUNT_BEFORE = /(?:=|total|amount|المبلغ|الإجمالي|المجموع|بمبلغ|إجمالي)\s*[:=]?\s*$/i;
/** The rate and amount a clause states for one BOQ line, or null when it states no figure. */
export function readPriceClause(clause: string): { unit_price: number | null; amount: number | null } | null {
  const c = normText(clause);
  // a quantity restated ("320 m2") and a percentage are not prices
  const figs: { n: number; rate: boolean; amount: boolean }[] = [];
  for (const m of c.matchAll(RE_FIG)) {
    const n = Number(m[1].replace(/,/g, '')); if (!(n > 0)) continue;
    const before = c.slice(0, m.index!), after = c.slice(m.index! + m[0].length);
    if (/^\s*%/.test(after) || /^\s*(?:m2|m²|sqm|m3|m|lm|rm|nos?|nr|pcs?|ls|kg|set|متر|م2|م²|عدد|قطعة)\b(?!\s*(?:@|=|at|rate))/i.test(after) && !/(?:@|=|per|\/|لكل|rate|price|بسعر)\s*$/i.test(before)) continue;
    const money = /(?:AED|Dhs?\.?|درهم|د\.إ)/i.test(m[0]);
    const rate = RATE_AFTER.test(after) || RATE_BEFORE.test(before);
    const amount = AMOUNT_BEFORE.test(before);
    if (!money && !rate && !amount) continue;   // a bare number with no dirham sign and no marker is not a price
    figs.push({ n, rate, amount });
  }
  if (!figs.length) return null;
  const r = figs.find((f) => f.rate), a = figs.find((f) => f.amount && !f.rate);
  if (r || a) return { unit_price: r?.n ?? null, amount: a?.n ?? null };
  if (figs.length >= 2) return { unit_price: figs[0].n, amount: figs[1].n };
  return { unit_price: null, amount: figs[0].n };
}
const RE_AED = /\b(?:all\s+)?(?:prices?\s+|amounts?\s+)?(?:are\s+)?in\s+aed\b|\ball\s+(?:prices?\s+)?(?:are\s+)?aed\b|\baed\s+only\b|بالدرهم/i;
const RE_GENERATE = /\bgenerate\b|\b(?:prepare|create|make)\s+(?:it|the\s+quot\w*|a\s+quot\w*)?\s*for\s+me\b|\byou\s+(?:do|prepare|generate)\s+it\b|إعداد|أعدّه|اعده|أعدها|أنشئ|انشئ|ولّد|جهّز/i;
const RE_REUPLOAD = /\bre-?upload\b|\bupload\b|\bnew\s+version\b|\brevised\s+(?:file|quot\w*)\b|\bi\s*(?:will|'ll)\s+(?:attach|send)\b|رفع|ارفع|سأرفع|نسخة\s+جديدة|نسخة\s+معدلة/i;
const RE_SUBMIT = /^\s*(?:please\s+)?submit\b|\bsubmit\s+(?:it|now|the\s+quot\w*)\b|^\s*قدّم|^\s*قدم|^\s*أرسله/i;
const RE_QUESTION = /[?؟]|^\s*(?:what|why|how|which|when|where|can|could|do|does|is|are|should|will|ماذا|لماذا|كيف|هل|ما|متى|أين|أي)\b/i;

export function readReply(text: string, open: Issue[]): ReplyRead {
  const t = normText(text);
  const out: Correction[] = [];
  const has = (code: IssueCode) => open.some((i) => i.code === code);
  const v = t.match(RE_VALIDITY); if (v) out.push({ field: 'validity', value: clean(v[1], 60) });
  const d = t.match(RE_LEAD); if (d) out.push({ field: 'lead_time', value: clean(d[1], 60) });
  const ex = t.match(RE_EXVAT); if (ex) { const n = Number(String(ex[1] || ex[2]).replace(/,/g, '')); if (n > 0) out.push({ field: 'price_ex_vat', value: n }); }
  if (!ex) {
    const vr = readVat({ amount: null, text: t });
    if (vr.treatment !== 'not_stated') out.push({ field: 'vat_treatment', value: vr.treatment });
  }
  // The warranty is read from ITS sentence only. Measured 21 Sep 2026 (audit, finding 4): a message
  // "Installation included 4 weeks. Warranty 2 years parts and labour" read as coverage "installation,
  // on site, parts, labour", because the whole message was scanned for coverage words.
  const wSentence = t.split(/(?<=[.;؛])\s+|\n/).find((s) => /warrant|guarant|ضمان/i.test(s));
  if (wSentence) {
    const w = readWarranty(wSentence);
    if (w.period || w.coverage) out.push({ field: 'warranty_terms', period: w.period, coverage: w.coverage });
  }
  if (/install|تركيب|supply\s*only|توريد\s*فقط/i.test(t)) {
    const ri = readInstallation([], { scope: t });
    if (ri.included) out.push({ field: 'installation', included: ri.included, detail: ri.detail ? clean(ri.detail, 120) : null });
  }
  if (RE_AED.test(t) && has('currency_not_aed')) out.push({ field: 'aed' });
  const excluded = new Set<number>();
  for (const m of t.matchAll(RE_EXCLUDED)) {
    const n = Number(m[2]);
    if (m[1] || open.some((i) => i.boq_line === n)) { excluded.add(n); out.push({ field: 'boq_excluded', boq_line: n, value: clean(`${m[3]}${m[4] || ''}`, 120) }); }
  }
  for (const m of t.matchAll(RE_QTYWHY)) {
    const n = Number(m[2]); const what: 'qty' | 'unit' = /unit|الوحدة/i.test(m[3]) ? 'unit' : 'qty';
    const code = what === 'unit' ? 'unit_mismatch' : 'qty_mismatch';
    if (!excluded.has(n) && open.some((i) => i.boq_line === n && i.code === code)) out.push({ field: 'qty_explained', boq_line: n, value: clean(m[4], 140), what });
  }
  for (const m of t.matchAll(RE_SPEC)) {
    const n = Number(m[1]); const key = normText(m[2]).toLowerCase(); const val = clean(m[3], 120).replace(/[.،]+$/, '').trim();
    if (!val || VAGUE.test(val)) continue;
    // "line 2 thickness: 15mm" names the attribute by its label ("thickness"), its code ("thickness_mm"),
    // the code's first word, or its Arabic label — the review's own example wording, in either language.
    const hit = open.find((i) => i.code === 'spec' && i.line_no === n && i.attr && (key.includes(String(i.attr).replace(/_/g, ' ')) || key.includes(String(i.attr).split('_')[0]) || i.en.toLowerCase().includes(`exact ${key}`) || i.ar.includes(key)));
    if (hit) out.push({ field: 'line_spec', line_no: n, attr: String(hit.attr), value: val });
  }
  // Prices typed for BOQ lines. A clause that also states an exclusion or a quantity reason is not a
  // price ("BOQ line 3 excluded — by others" carries no dirham figure and reads as none).
  for (const m of t.matchAll(RE_PRICE_CLAUSE)) {
    const n = Number(m[2]); if (excluded.has(n)) continue;
    // "line N" alone is the supplier's own line unless a BOQ point is open for N
    const own = !m[1] && !open.some((i) => i.boq_line === n) && open.some((i) => i.code === 'line_unpriced' && i.line_no === n);
    if (!m[1] && !own && !open.some((i) => i.boq_line === n)) continue;
    const p = readPriceClause(m[3]); if (!p) continue;
    out.push(own ? { field: 'line_price', line_no: n, unit_price: p.unit_price, amount: p.amount } : { field: 'boq_price', boq_line: n, unit_price: p.unit_price, amount: p.amount });
  }
  if (has('total_mismatch')) {
    const tot = t.match(RE_TOTAL); const tv = tot ? Number(tot[1].replace(/,/g, '')) : 0;
    if (tv > 0) out.push({ field: 'total', value: tv });
    const dis = t.match(RE_DISCOUNT);
    if (dis) out.push({ field: 'total_explained', value: clean(dis[0], 120) });
  }
  // A material the customer named: "<its name or key>: <value>", in either language.
  for (const i of open.filter((x) => x.code === 'component' && x.attr)) {
    const key = String(i.attr).slice('component:'.length);
    const names = [key.replace(/_/g, ' '), ...[i.en.match(/Material — ([^.(:]+)/)?.[1], i.ar.match(/المادة — ([^.(:]+)/)?.[1]].filter(Boolean).map((s) => s!.trim())]
      .filter((s) => s.length >= 2).map((s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
    const m = t.match(new RegExp(String.raw`(?:^|[\s,.;؛])(?:${names.join('|')})\s*[:=\-–]\s*${VAL(2, 120)}`, 'i'));
    const val = m ? clean(m[1], 120).replace(/[.،]+$/, '').trim() : '';
    if (val && !VAGUE.test(val)) out.push({ field: 'component', key, value: val, label_en: i.en.match(/Material — ([^.(:]+)/)?.[1]?.trim() || key.replace(/_/g, ' '), label_ar: i.ar.match(/المادة — ([^.(:]+)/)?.[1]?.trim() || 'المادة' });
  }
  const choice = RE_GENERATE.test(t) ? 'generate' : RE_REUPLOAD.test(t) ? 'reupload' : null;
  const q = RE_QUESTION.test(t);
  const topic: Topic | null = !q ? null
    : /vat|tax|trn|ضريب/i.test(t) ? 'vat'
    : /missing|remain|left|else|still|outstanding|ناقص|متبق|تبق|المطلوب/i.test(t) ? 'missing'
    : /customer|client|who is|name|contact|phone|العميل|اسم|رقم/i.test(t) ? 'customer'
    : /valid|صلاحي/i.test(t) ? 'validity'
    : /currenc|aed|usd|dirham|عملة|درهم/i.test(t) ? 'currency'
    : /boq|quantit|qty|unit|كمي|جدول|وحد/i.test(t) ? 'boq'
    : /deliver|lead|تسليم/i.test(t) ? 'delivery'
    : /warrant|ضمان/i.test(t) ? 'warranty'
    : /install|تركيب/i.test(t) ? 'installation'
    : 'general';
  return { corrections: out, choice, submit: RE_SUBMIT.test(t), topic };
}

// Names the sibling modules of this folder import (the declarations above are unchanged).
export { clean };
