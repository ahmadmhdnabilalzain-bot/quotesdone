// quote_documents.ts — what goes ON the customer's quotation PDF and comparison report.
//
// 14 Sep 2026, agent: ceo. Two founder notes on the documents #600/#601 produced:
//   "the format can be more professional and advanced (very simple now)"
//   "what is arabic is not fully in arabic, many english words here and there"
// and a third on the comparison report: it must be technically detailed — the exact material spec
// (type of wood, thickness …) side by side, not only delivery time and installation.
//
// WHAT IT IS NOW. Each document is a cover (title, reference, date, request summary, a key-figures
// strip) and numbered sections, laid out by pdf_native/render.ts. The builders here are pure:
//   • Everything the platform knows the meaning of is written from our own keys (labels, trade codes,
//     emirates, durations, units).
//   • Everything a person wrote — item descriptions, specification values, scope, exclusions, payment
//     terms — is translated natively by reasoning (_shared/reasoned_governance.ts nativeArabic, decision
//     point trade_glossary_ar, 23 Sep 2026) and handed in as `arTexts`. A line without its Arabic is
//     returned in `untranslated` and the caller HOLDS the Arabic document: never printed half-translated,
//     and never a glossary's word-by-word substitution (founder_instruction 890).
//   • The comparison report carries a TECHNICAL COMPARISON: each scope line × each supplier's stated
//     value per attribute, marked matches / differs / not stated against the request (see
//     TechnicalComparison below — the renderer input the spec agent's contract fills).
//   • The founder's four completeness checks (14 Sep 2026) are shown side by side for every quote:
//     material specs per line, delivery / lead time, installation (where it applies: included, scope,
//     timeline) and warranty (where it applies: period and coverage). "N/A" where it does not apply.
//   • Who prepared it: "the QuotesDone sales engineer" (founder rule, 14 Sep 2026: "its always the
//     sales agent. no other agent is involved in customer or supplier portal"). Never an AI, never
//     an assistant, never another agent.
//
// ANONYMITY. The customer pays a reveal fee to learn who quoted. Supplier free text can carry a
// name, a number or an email ("call Ahmed on 050…"), so every string in both documents passes
// maskContacts, which also blanks the supplier names the caller hands in. Links are ids only.
import { arUnit as glossaryUnit, arCount as glossaryCount, arAttr, CATEGORY_AR, CATEGORY_EN, WORKING_FORMS, UNIT_FORMS, type Unit } from './trade_glossary_ar.ts';
import { METHOD_NOTE_AR, METHOD_NOTE_EN } from '../quote_compare/deterministic.ts';

import { LICENCE_NO, TRN_BARE, TRN_LABELLED } from './identity_numbers.ts';
import { assessQuote, requirementsOf, type Line as SpecLine, type TermsSpec } from './line_specs/assess.ts';
export type Lang = 'en' | 'ar';
/** The version printed in each document's control line AND carried in its file name. Bump when the
 * layout or wording changes: a cached file whose name lacks the current version is re-rendered
 * (isCurrentDoc). v2.1, 21 Sep 2026: the Arabic fixes of #782/#790/#794 — before this, the cache kept
 * serving documents rendered by v2.0 for as long as the quote was untouched. v2.2, 23 Sep 2026: the Arabic of a
 * person's words is reasoned (decision point trade_glossary_ar), so every glossary-era Arabic file is re-rendered. */
export const DOC_VERSION = 'v2.2';
/** The file name pdf_native writes: `<ts>_<name>.pdf`, name = `<ref>-<DOC_VERSION>-<kind>-<lang>`. The
 * version sits BEFORE the kind: trg_quote_pdf_cache_register replaces a quote's earlier vault entry by
 * matching a path that ENDS in `-quotation-<lang>.pdf`, and that ending must not move. */
export const docName = (ref: string, kind: string, lang: Lang) => `${ref}-${DOC_VERSION}-${kind}-${lang}`;
/** True only for a stored file rendered by the current layout. */
export const isCurrentDoc = (path: unknown) => String(path ?? '').includes(`-${DOC_VERSION}-`);
const PREPARED_BY = { en: 'Prepared by the QuotesDone sales engineer', ar: 'أعدّه مهندس مبيعات QuotesDone' };

/** A, B … Z, AA, AB … — the anonymous label for the i-th live quote by ascending price. */
export function supplierLabel(i: number): string { let n = Number(i) || 0, out = ''; do { out = String.fromCharCode(65 + (n % 26)) + out; n = Math.floor(n / 26) - 1; } while (n >= 0); return out; }

// ── Anonymity ─────────────────────────────────────────────────────────────────────────────────
const HIDDEN = { en: '[contact hidden until reveal]', ar: '[بيانات التواصل مخفية حتى الكشف]' };
function escapeRe(s: string) { return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }
/** Blank emails, phone numbers, web addresses and the named suppliers out of one string. */
export function maskContacts(s: unknown, names: string[] = [], lang: Lang = 'en'): string {
  let t = String(s == null ? '' : s);
  // The placeholder follows the script of the text it sits in, not the page: an Arabic placeholder
  // inside an English supplier note turned the whole note right-to-left and scrambled its order.
  const H = HIDDEN[/[؀-ۿ]/.test(t) ? 'ar' : /[A-Za-z]/.test(t) ? 'en' : lang];
  // _shared/anonymise paints what it removes as '█'. No brand font carries that glyph: measured 21 Sep 2026
  // (drawing_boq/drawing_chain.test.ts) the inquiry PDF dropped it — 6 characters in English, 5 in Arabic —
  // so a scrubbed BOQ line printed "call  on  or ," with nothing saying something was taken out.
  t = t.replace(/█+/g, H);
  t = t.replace(/[\w.+-]+@[\w-]+(?:\.[\w-]+)+/g, H);
  t = t.replace(/\b(?:https?:\/\/|www\.)\S+/gi, H);
  t = t.replace(/\b[\w-]+\.(?:com|ae|net|org|co)(?:\.[a-z]{2})?\b/gi, H);
  // A TRN or licence number finds the company on a public register (founder, 14 Sep 2026). Before
  // the phone patterns, which would otherwise take a 15-digit TRN apart and leave its label behind.
  t = t.replace(TRN_LABELLED, H).replace(TRN_BARE, H).replace(LICENCE_NO, H);
  // UAE numbers in every usual spelling, then any international-looking run of 9+ digits.
  t = t.replace(/(?:\+|00)?971[\s-]?\(?0?\)?[\s-]?\d(?:[\s-]?\d){6,8}\b/g, H);
  t = t.replace(/\b0[2-9](?:[\s-]?\d){7,8}\b/g, H);
  t = t.replace(/\+\d(?:[\s-]?\d){8,13}\b/g, H);
  for (const n of names) {
    const v = String(n || '').trim();
    if (v.length < 3) continue;
    t = t.replace(new RegExp(escapeRe(v), 'gi'), H);
    // "ZZ DEMO Cooling Services LLC" also appears as "ZZ DEMO Cooling Services".
    const core = v.replace(/\b(?:l\.?l\.?c|fze|fzco|fz-llc|est|establishment|trading|co|company|ltd|limited)\.?\s*$/i, '').trim();
    if (core.length >= 5 && core !== v) t = t.replace(new RegExp(escapeRe(core), 'gi'), H);
  }
  return t;
}
// deno-lint-ignore no-explicit-any
function maskDeep(v: any, names: string[], lang: Lang): any {
  if (typeof v === 'string') return maskContacts(v, names, lang);
  if (Array.isArray(v)) return v.map((x) => maskDeep(x, names, lang));
  // deno-lint-ignore no-explicit-any
  if (v && typeof v === 'object') { const o: any = {}; for (const k of Object.keys(v)) o[k] = (k === 'link') ? v[k] : maskDeep(v[k], names, lang); return o; }
  return v;
}

// ── Deterministic Arabic for what the platform knows ───────────────────────────────────────────────
const hasArabic = (s: unknown) => /[؀-ۿ]/.test(String(s ?? ''));
const norm = (s: unknown) => String(s ?? '').toLowerCase().replace(/[_]+/g, ' ').replace(/\s+/g, ' ').trim();
export const arCount = glossaryCount;
export const arUnit = glossaryUnit;

const EMIRATES: Record<string, string> = {
  'dubai': 'دبي', 'abu dhabi': 'أبوظبي', 'sharjah': 'الشارقة', 'ajman': 'عجمان', 'umm al quwain': 'أم القيوين',
  'umm al-quwain': 'أم القيوين', 'ras al khaimah': 'رأس الخيمة', 'ras al-khaimah': 'رأس الخيمة', 'rak': 'رأس الخيمة',
  'fujairah': 'الفجيرة', 'al ain': 'العين', 'uae': 'الإمارات العربية المتحدة', 'all emirates': 'جميع الإمارات',
};
export function arEmirate(s: unknown): string | null { if (hasArabic(s)) return String(s); return EMIRATES[norm(s)] ?? null; }

/** The English trade name as a person writes it: 'hvac' → 'HVAC', 'fit_out' → 'Fit Out'. */
export function enCategory(s: unknown): string {
  const code = String(s ?? '').toLowerCase().trim();
  if (CATEGORY_EN[code]) return CATEGORY_EN[code];
  const n = norm(s); if (!n) return '';
  if (/^(hvac|mep|cctv|it|ac)$/.test(n)) return n.toUpperCase();
  return n.replace(/\b[a-z]/g, (c) => c.toUpperCase());
}
export function arCategory(s: unknown): string | null {
  if (hasArabic(s)) return String(s);
  const code = String(s ?? '').toLowerCase().trim();
  if (CATEGORY_AR[code]) return CATEGORY_AR[code];
  // A trade that is not one of our category keys is free text: the caller reasons it (k.loc), never a word list.
  return null;
}

const UNIT_OF: Record<string, Unit> = { day: 'day', days: 'day', week: 'week', weeks: 'week', wk: 'week', wks: 'week', month: 'month', months: 'month', mo: 'month', mos: 'month', year: 'year', years: 'year', yr: 'year', yrs: 'year' };
/** A duration that is ONLY a number (or range) and a unit — "2 weeks", "10-14 days", "3 working days" — in Arabic,
 * or null. This is format parsing of a number and its unit and nothing else (decision point
 * documents.quote_duration_emirates, 23 Sep 2026): anything a person wrote around it ("immediate", "from order",
 * "after approval") is their words, and the document reasons it (loc) instead of substituting phrases. */
export function arDuration(s: unknown): string | null {
  if (hasArabic(s)) return String(s);
  const t = norm(s).replace(/\.$/, '');
  if (!t) return null;
  const m = t.match(/^(\d{1,4})(?:\s*(?:-|–)\s*(\d{1,4}))?\s*(working |business )?(days?|weeks?|wks?|months?|mos?|years?|yrs?)$/);
  if (!m) return null;
  const a = Number(m[1]), b = m[2] ? Number(m[2]) : null, unit = UNIT_OF[m[4]], working = !!m[3];
  if (!unit) return null;
  if (b === null) return arCount(a, unit, working);
  const f = working && unit === 'day' ? WORKING_FORMS : UNIT_FORMS[unit];
  return `${a}–${b} ${b >= 3 && b <= 10 ? f[2] : f[3]}`;
}
// ── Types: what the caller hands in ─────────────────────────────────────────────────────────────
export type QuoteRow = {
  id?: string; quote_amount: number | null; lead_time?: string | null; validity?: string | null; warranty?: string | null;
  payment_terms?: string | null; scope?: string | null; conditions?: string | null; exclusions?: string | null; notes?: string | null;
  /** The founder's four completeness checks (14 Sep 2026). All optional: absent means "not stated". */
  installation_applicable?: boolean | null; installation_included?: boolean | null; installation_scope?: string | null; installation_timeline?: string | null;
  warranty_applicable?: boolean | null; warranty_coverage?: string | null;
  /** The price excluding VAT (the spec/hold contract's `price_ex_vat`). Every customer document
   * shows and compares this figure; the 3% fee is taken on it. Absent: quote_amount is ex-VAT. */
  price_ex_vat?: number | null;
};
export type InquiryRow = { id: string; rfq_no?: number | string | null; category?: string | null; summary?: string | null; emirate?: string | null };
/** The one job number (inquiries.rfq_no) as printed on every document; the uuid prefix only for a row read without it. */
export const jobNoOf = (inq: { id?: string | null; rfq_no?: number | string | null } | null | undefined) =>
  inq?.rfq_no != null && String(inq.rfq_no).trim() !== '' ? String(inq.rfq_no) : String(inq?.id || '').slice(0, 8).toUpperCase();

// ── The completeness checks come from the hold desk's own reading ─────────────────────────────
// MEASURED 21 Sep 2026 (audit, finding 4): the generated quotation said "Material specification:
// Missing on 3 of 3 lines", "Installation: Not stated", "Warranty coverage not stated" for a quote the
// sales engineer had just approved as complete. Two causes, both here: (1) both printers read the
// per-line specs from a column named `specs` — the stored column is quote_items.spec — so no line ever
// had a specification; (2) nothing ever wrote quotes.installation_included / warranty_coverage, so the
// four checks were always "Not stated". The document now asks line_specs/assess.ts — the ONE reader
// the review and the hold gate use — so the PDF can never disagree with the approval.
/** quote_items rows as printed lines. The stored column is `spec`; `specs` is accepted for an older row shape. */
// deno-lint-ignore no-explicit-any
export function itemsOfRows(rows: any[] | null | undefined): Item[] {
  return (rows || []).map((b) => ({ desc: String(b.description || ''), qty: b.qty == null ? '' : String(b.qty), unit: String(b.unit || ''),
    unit_price: b.unit_price == null ? null : Number(b.unit_price), amount: b.amount == null ? null : Number(b.amount),
    brand: b.brand ?? null, model: b.model ?? null, specification: b.specification ?? null,
    specs: (b.spec && typeof b.spec === 'object' && !Array.isArray(b.spec)) ? b.spec : ((b.specs && typeof b.specs === 'object' && !Array.isArray(b.specs)) ? b.specs : null) })).filter((x) => x.desc);
}
/**
 * The four checks (material per line, delivery, installation, warranty) as assess.ts reads this quote,
 * and each line's specs completed with what its own words state. Pure.
 */
export function completenessOf(q: QuoteRow & { terms_spec?: unknown; lead_time?: string | null }, items: Item[], category: string | null | undefined, inquirySpec: unknown): { quote: QuoteRow; items: Item[] } {
  const lines: SpecLine[] = items.map((it, i) => ({ line_no: i + 1, description: it.desc, brand: it.brand ?? null, model: it.model ?? null, specification: it.specification ?? null,
    qty: it.qty, unit: it.unit, unit_price: it.unit_price ?? null, amount: it.amount ?? null,
    spec: it.specs ? Object.fromEntries(Object.entries(it.specs).filter(([, v]) => v != null).map(([k, v]) => [k, String(v)])) : null }));
  const a = assessQuote({ category: category ?? null, lines, requirements: requirementsOf(inquirySpec),
    terms: { lead_time: q.lead_time ?? null, warranty: q.warranty ?? null, scope: q.scope ?? null, exclusions: q.exclusions ?? null, conditions: q.conditions ?? null, notes: q.notes ?? null,
      terms_spec: (q.terms_spec && typeof q.terms_spec === 'object' ? q.terms_spec : null) as TermsSpec | null, price_ex_vat: q.price_ex_vat ?? q.quote_amount ?? null } });
  const out = items.map((it, i) => { const r = a.lines[i]; const specs = r && Object.keys(r.spec).length ? { ...(it.specs ?? {}), ...r.spec } : it.specs; return { ...it, specs: specs ?? null }; });
  const inst = a.terms.installation, w = a.terms.warranty;
  const timeline = inst.detail && /^Installation in /.test(inst.detail) ? inst.detail.replace(/^Installation in /, '') : null;
  return {
    items: out,
    quote: { ...q,
      installation_applicable: inst.applies, installation_included: inst.included === 'yes' ? true : inst.included === 'no' ? false : null,
      installation_scope: inst.detail && !timeline ? inst.detail.replace(/^Scope: /, '') : null, installation_timeline: timeline,
      // the cover figure and the terms cell carry the PERIOD; the coverage has its own place in the checks
      warranty_applicable: w.applies, warranty_coverage: w.coverage, warranty: w.period ?? q.warranty ?? null },
  };
}
/** One priced line of the supplier's own breakdown (quote_items). `specs` is attribute → stated value. */
export type Item = {
  desc: string; qty: string; unit: string; unit_price?: number | null; amount?: number | null;
  brand?: string | null; model?: string | null; specification?: string | null; specs?: Record<string, string | null> | null;
};

// THE TECHNICAL COMPARISON — the renderer's input. The spec agent (branch exact-specs-or-hold)
// publishes the contract at docs/contracts/technical_comparison.md; this is the shape described in
// its scope line: each quote's stated value per attribute, per scope line, with a flag against the
// request, plus the three commercial completeness checks with an `applicable` flag. Values are keyed
// by the anonymous label ("Supplier A"). A held quote is never a column: the roster decides.
export type SpecFlag = 'match' | 'differs' | 'missing' | 'optional' | 'na';
export type SpecCell = { value?: string | null; flag: SpecFlag; note?: string | null };
export type TechAttribute = { key: string; label?: string | null; unit?: string | null; requested?: string | null; values: Record<string, SpecCell> };
export type TechLine = { line_no?: number | null; item: string; qty?: string | number | null; unit?: string | null; attributes: TechAttribute[] };
export type TechTerm = { applicable?: boolean | null; requested?: string | null; values: Record<string, SpecCell> };
export type TechnicalComparison = {
  suppliers: string[];
  lines: TechLine[];
  terms?: { lead_time?: TechTerm | null; installation?: TechTerm | null; warranty?: TechTerm | null } | null;
};

/** 'QD-<job number>-<letter>' — the job number is inquiries.rfq_no, the same one both portals print (21 Sep 2026, audit finding 7). */
export function quoteRef(inq: { id?: string | null; rfq_no?: number | string | null }, letter: string) { return 'QD-' + jobNoOf(inq) + '-' + letter; }
export function clipCell(s: unknown, n: number) { const t = String(s == null ? '' : s).replace(/\s+/g, ' ').trim(); return t.length > n ? t.slice(0, n - 1) + '…' : t; }
// deno-lint-ignore no-explicit-any
const arrOf = (x: any) => Array.isArray(x) ? x : [];
/** "Supplier B" → "المورّد B" on an Arabic page; the letter stays the one on the customer's screen. */
// "Option N" takes the same Arabic as labelQuotes' own .ar ("المورّد A – الخيار 2"). Measured 14 Sep
// 2026: only "Supplier" was translated, so the Arabic report read "المورّد A – Option 1" in every table.
export const arLabelWords = (s: string) => s.replace(/\bSupplier ([A-Z]{1,2})\b/g, 'المورّد $1').replace(/\bOption (\d{1,3})\b/g, 'الخيار $1');
export function labelFor(label: unknown, lang: Lang) { const l = String(label ?? ''); return lang === 'ar' ? arLabelWords(l) : l; }

// ── VAT never reaches the customer ─────────────────────────────────────────────────────────────
// Founder, 14 Sep 2026: "our company is not vat registered so for our reveal fee there is no vat.
// and for suppliers quotations, we definetely hide the vat details when sharing the quotes with the
// customer." Every price is shown ex-VAT; the one neutral line below is the only mention; a sentence
// of supplier or analysis text that mentions VAT, tax registration or a TRN is dropped whole.
export const VAT_LINE = { en: 'Prices shown exclude VAT, where applicable.', ar: 'الأسعار المعروضة لا تشمل ضريبة القيمة المضافة حيثما تنطبق.' };
export const VAT_RE = /\b(?:vat|trn|value[- ]added tax|tax registration(?: number)?|tax reg(?:istration)? no)\b|ضريبة القيمة المضافة|الرقم الضريبي|رقم التسجيل الضريبي|\b100\d{12}\b/i;
/** Drop every sentence / clause that mentions VAT or a TRN. */
export function stripVat(s: unknown): string {
  const t = String(s ?? '');
  if (!VAT_RE.test(t)) return t;
  return t.split(/(?<=[.;!؛\n])\s+|\s*[;؛]\s*/).filter((part) => !VAT_RE.test(part)).join(' ').replace(/\s+/g, ' ').trim();
}

// ── Shared helpers for both documents ────────────────────────────────────────────────────────────
type Cell = string | { text: string; sub?: string; flag?: SpecFlag; chip?: 'short' | 'open' | 'hold'; link?: string; bold?: boolean; group?: boolean };
const ORIGINAL = 'النص الأصلي من المورد: ';
/** Native Arabic of a person's own words, by source text — written by reasoning upstream (reasoned_governance.ts
 * nativeArabic), never by substituting glossary words. */
export type ArTexts = Record<string, string>;
function kit(lang: Lang, names: string[] = [], arTexts: ArTexts = {}) {
  const ar = lang === 'ar';
  // Every free-text line this Arabic page needs and was not handed the Arabic of. A document with any is
  // not served: nativeArabic() reasons them and rebuilds, or holds the document.
  const untranslated = new Set<string>();
  // Contacts are masked and VAT dropped BEFORE translation, so neither can survive in the Arabic
  // primary text or in the "original wording" line under it.
  const clean = (v: unknown) => maskContacts(stripVat(v), names, 'en');
  const T = (en: string, arx: string) => (ar ? arx : en);
  const money = (v: unknown, dec = false) => {
    if (v == null || v === '' || !(Number(v) > 0)) return '—';
    const n = Number(v).toLocaleString('en-AE', { minimumFractionDigits: dec ? 2 : 0, maximumFractionDigits: dec ? 2 : 0 });
    return ar ? `${n} درهم` : `AED ${n}`;
  };
  // Supplier or customer free text in the page's language. On an Arabic page it is the reasoned Arabic handed
  // in as arTexts; a line without it is recorded in `untranslated` and the document is held, never printed.
  const loc = (v: unknown, max = 400): { text: string; sub?: string } => {
    const s = clipCell(clean(v), max);
    if (!s || !ar || !/[A-Za-z]/.test(s)) return { text: s };
    if (arTexts[s]) return { text: arTexts[s] };
    untranslated.add(s);
    return { text: s };
  };
  const cell = (v: unknown, max = 400): Cell => { const r = loc(v, max); return r.sub ? r : (r.text || '—'); };
  const dur = (v: unknown) => { const c = clipCell(v, 60); if (!c) return ''; return ar ? (arDuration(c) ?? loc(c).text) : c; };
  const pay = (v: unknown): Cell => { const c = clipCell(clean(v), 90); if (!c) return '—'; return ar ? cell(c) : c; };
  const label = (l: unknown) => labelFor(l, lang);
  // Analysis sentences name suppliers by label and prices in AED: both take the page's language.
  // Any sentence about VAT is dropped in both languages.
  // deno-lint-ignore no-explicit-any
  const sentence = (v: any): any => typeof v === 'string'
    ? (ar ? arLabelWords(stripVat(v)).replace(/\bAED\s?([\d,.]+)/g, '$1 درهم') : stripVat(v))
    : Array.isArray(v) ? v.map(sentence) : (v && typeof v === 'object') ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, k === 'link' ? x : sentence(x)])) : v;
  const today = () => new Date().toLocaleDateString(ar ? 'ar-AE-u-nu-latn' : 'en-GB', { day: 'numeric', month: 'long', year: 'numeric' });
  return { ar, T, money, loc, cell, dur, pay, label, sentence, today, untranslated };
}
type Kit = ReturnType<typeof kit>;
const FLAG_WORD: Record<SpecFlag, [string, string]> = { match: ['Matches', 'مطابق'], differs: ['Differs', 'مختلف'], missing: ['Not stated', 'غير مذكور'], optional: ['Not stated (optional)', 'غير مذكورة (اختيارية)'], na: ['N/A', 'لا ينطبق'] };
/** A spec or term value with its marker. An empty value takes the flag's own word. */
function flagged(k: Kit, c: SpecCell | null | undefined): Cell {
  const flag: SpecFlag = c?.flag ?? 'missing';
  const raw = c?.value == null ? '' : String(c.value);
  if (flag === 'na') return { text: k.T('N/A', 'لا ينطبق'), flag };
  if (!raw.trim()) return { text: k.T(FLAG_WORD[flag][0], FLAG_WORD[flag][1]), flag };
  const d = k.ar ? (arDuration(raw) ? { text: arDuration(raw)! } as { text: string; sub?: string } : k.loc(raw, 120)) : { text: clipCell(raw, 120) } as { text: string; sub?: string };
  const note = c?.note ? (k.ar ? k.loc(c.note, 120).text : clipCell(c.note, 120)) : '';
  return { text: d.text + (note ? ` (${note})` : ''), ...(d.sub ? { sub: d.sub } : {}), flag };
}
function legendBlock(k: Kit) {
  return { t: 'legend', items: [['match', k.T('Matches your request', 'مطابق لطلبك')], ['differs', k.T('Differs from your request', 'مختلف عن طلبك')], ['missing', k.T('Not stated by the supplier', 'لم يذكره المورّد')], ['optional', k.T('Not stated (optional detail)', 'غير مذكورة (تفصيل اختياري)')], ['na', k.T('N/A — does not apply', 'لا ينطبق')]] };
}
function specText(k: Kit, it: Item): Cell {
  const parts: Array<{ text: string; sub?: string }> = [];
  const specs = it.specs && typeof it.specs === 'object' ? Object.entries(it.specs).filter(([, v]) => v != null && String(v).trim() !== '') : [];
  for (const [key, v] of specs) {
    const name = k.ar ? (arAttr(key) ?? k.loc(key.replace(/_/g, ' ')).text) : key.replace(/_/g, ' ').replace(/^\w/, (c) => c.toUpperCase());
    const val = k.loc(v, 120);
    parts.push({ text: `${name}: ${val.text}`, sub: val.sub });
  }
  if (it.brand) parts.push({ text: `${k.T('Brand', 'العلامة التجارية')}: ${it.brand}` });
  if (it.model) parts.push({ text: `${k.T('Model', 'الطراز')}: ${it.model}` });
  if (it.specification) parts.push(k.loc(it.specification, 200));
  if (!parts.length) return { text: k.T('Not stated', 'غير مذكور'), flag: 'missing' };
  const subs = parts.filter((p) => p.sub).map((p) => p.sub!.replace(ORIGINAL, ''));
  return { text: parts.map((p) => p.text).join(' · '), ...(subs.length ? { sub: ORIGINAL + subs.join(' · ') } : {}) };
}
const hasSpecs = (it: Item) => !!((it.specs && Object.values(it.specs).some((v) => v != null && String(v).trim() !== '')) || it.brand || it.model || it.specification);

// ── The quotation ──────────────────────────────────────────────────────────────────────────────
/** The pdf_native body for ONE quote in ONE language. Pure: the caller fetches the rows. */
// requestUrl: the portal deep link back to this quote on its request (site_origins portalLink).
/** `partyName`: the supplier's company name once the customer has paid to reveal it; the letter still names the reference. */
export function quoteDocument(args: { quote: QuoteRow; inquiry: InquiryRow; items: Item[]; letter: string; lang: Lang; partyName?: string | null; maskNames?: string[]; requestUrl?: string; date?: string; date_ar?: string; arTexts?: ArTexts }) {
  const { quote: q, inquiry: inq, letter, lang } = args;
  // A line that is itself VAT ("VAT 5%") is not scope; it never reaches the page.
  const items = (args.items || []).filter((it) => !VAT_RE.test(String(it.desc || '')));
  const exVat = Number(q.price_ex_vat) > 0 ? Number(q.price_ex_vat) : Number(q.quote_amount) || 0;
  const k = kit(lang, args.maskNames || [], args.arTexts); const { T, ar } = k;
  const ref = quoteRef(inq, letter);
  const date = (ar ? args.date_ar : args.date) || k.today();
  const party = args.partyName || k.label('Supplier ' + letter);
  const trade = ar ? (arCategory(inq.category) ?? k.loc(inq.category).text) : enCategory(inq.category);
  const emirate = ar ? (arEmirate(inq.emirate) ?? k.loc(inq.emirate).text) : String(inq.emirate || '');
  const lead = k.dur(q.lead_time), validity = k.dur(q.validity), warranty = k.dur(q.warranty);
  const summary = k.loc(inq.summary, 600);
  // deno-lint-ignore no-explicit-any
  const blocks: any[] = [];
  let n = 0; const section = (en: string, arx: string) => blocks.push({ t: 'section', n: ++n, text: T(en, arx) });

  section('Request and quoting party', 'الطلب والجهة مقدّمة العرض');
  // `note`, not `sub`: in these blocks `sub` means one thing only — the supplier's original wording.
  blocks.push({ t: 'party', label: T('Quoting party', 'الجهة مقدّمة العرض'), chip: party, note: T('Anonymous until you reveal it. The supplier\'s name and contact details are released only after the reveal fee is paid.', 'هوية المورّد مخفية حتى الكشف، ولا تُعرض بيانات التواصل إلا بعد سداد رسوم الكشف.') });
  blocks.push({ t: 'kv', pairs: [[T('Trade', 'التخصص'), trade || '—'], [T('Emirate', 'الإمارة'), emirate || '—']] });
  if (summary.text) blocks.push({ t: 'p', text: summary.text, sub: summary.sub, label: T('Your request', 'طلبك') });

  section('Scope and technical specification', 'نطاق العمل والمواصفات الفنية');
  const priced = items.some((it) => Number(it.amount) > 0 || Number(it.unit_price) > 0);
  const specCol = items.some(hasSpecs);
  if (items.length) {
    const head: Cell[] = ['#', T('Description', 'الوصف')];
    const widths = [0.05]; const align = ['c', 's'];
    if (specCol) head.push(T('Specification', 'المواصفات'));
    head.push(T('Qty', 'الكمية'), T('Unit', 'الوحدة'));
    if (priced) head.push(T('Rate (AED)', 'سعر الوحدة (درهم)'), T('Amount (AED)', 'المبلغ (درهم)'));
    widths.push(specCol ? (priced ? 0.22 : 0.33) : (priced ? 0.49 : 0.69));
    if (specCol) { widths.push(priced ? 0.31 : 0.40); align.push('s'); }
    widths.push(0.07, 0.08); align.push('e', 'c');
    if (priced) { widths.push(0.12, 0.15); align.push('e', 'e'); }
    const total = widths.reduce((a, b) => a + b, 0); const W = widths.map((w) => w / total);
    const rows = items.map((it, i) => {
      const r: Cell[] = [String(i + 1), k.cell(it.desc, 200)];
      if (specCol) r.push(specText(k, it));
      r.push(String(it.qty ?? ''), (ar ? (arUnit(it.unit) ?? k.loc(it.unit).text) : String(it.unit || '')) || '—');
      // The currency sits in the column head, so each cell is the figure alone and stays on one line.
      const num = (x: unknown) => Number(x) > 0 ? Number(x).toLocaleString('en-AE', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) : '—';
      if (priced) r.push(num(it.unit_price), num(it.amount));
      return r;
    });
    blocks.push({ t: 'table', head, rows, widths: W, align, zebra: true });
  } else {
    blocks.push({ t: 'callout', tone: 'gold', title: T('Lump-sum quote', 'عرض بسعر إجمالي'), text: T('The supplier priced this job as one sum with no line breakdown, so it cannot be checked item by item. Ask for an itemised breakdown before you commit.', 'سعّر المورّد العمل بمبلغ إجمالي واحد دون تفصيل بالبنود، لذا لا يمكن التحقق منه بندًا بندًا. اطلب تفصيلًا بالبنود قبل الالتزام.') });
  }
  // Totals: the lines' own sum where they carry amounts, then the total — both excluding VAT. No VAT
  // line, amount, rate or TRN ever reaches the customer (founder, 14 Sep 2026: "we definetely hide
  // the vat details when sharing the quotes with the customer"; a TRN would also name the supplier).
  const sum = items.reduce((a, it) => a + (Number(it.amount) > 0 ? Number(it.amount) : 0), 0);
  const trows: Array<[string, string, boolean?]> = [];
  if (sum > 0) trows.push([T('Lines subtotal', 'مجموع البنود'), k.money(sum, true)]);
  trows.push([T('Total quoted', 'إجمالي العرض'), k.money(exVat, true), true]);
  const diff = sum > 0 && exVat > 0 && Math.abs(sum - exVat) > 1;
  blocks.push({ t: 'totals', rows: trows, note: diff ? T(`The line amounts add up to ${k.money(sum, true)}; the quoted total is ${k.money(exVat, true)}. The quoted total is the price this supplier offered.`, `مجموع مبالغ البنود ${k.money(sum, true)} بينما إجمالي العرض ${k.money(exVat, true)}. إجمالي العرض هو السعر الذي قدّمه هذا المورّد.`) : '' });
  blocks.push({ t: 'note', text: T(VAT_LINE.en, VAT_LINE.ar) });

  section('Completeness check', 'فحص اكتمال العرض');
  blocks.push({ t: 'p', text: T('A quote is complete when it states all four of these. Each is marked as the supplier stated it.', 'يكون العرض مكتملًا عندما يذكر هذه البنود الأربعة كلها. كل بند معلّم كما ذكره المورّد.'), muted: true });
  const specN = items.filter(hasSpecs).length;
  const checks: Array<[string, Cell]> = [];
  checks.push([T('Material specification, per line', 'مواصفات المواد لكل بند'), !items.length ? { text: T('No line breakdown', 'لا يوجد تفصيل بالبنود'), flag: 'missing' }
    : specN === items.length ? { text: T(`Stated on all ${items.length} lines`, `مذكورة في جميع البنود (${items.length})`), flag: 'match' }
    : { text: T(`Missing on ${items.length - specN} of ${items.length} lines`, `ناقصة في ${items.length - specN} من ${items.length} بنود`), flag: 'missing' }]);
  checks.push([T('Delivery / lead time', 'التسليم / مدة التنفيذ'), lead ? { text: lead, flag: 'match' } : { text: T('Not stated', 'غير مذكورة'), flag: 'missing' }]);
  const instScope = [q.installation_scope ? k.loc(q.installation_scope, 120).text : '', q.installation_timeline ? k.dur(q.installation_timeline) : ''].filter(Boolean).join(' · ');
  checks.push([T('Installation', 'التركيب'), q.installation_applicable === false ? { text: T('N/A', 'لا ينطبق'), flag: 'na' }
    : q.installation_included === true ? { text: T('Included', 'مشمول') + (instScope ? ' — ' + instScope : ''), flag: instScope ? 'match' : 'missing' }
    : q.installation_included === false ? { text: T('Not included', 'غير مشمول'), flag: 'differs' } : { text: T('Not stated', 'غير مذكور'), flag: 'missing' }]);
  const coverage = q.warranty_coverage ? k.loc(q.warranty_coverage, 120).text : '';
  checks.push([T('Warranty — period and coverage', 'الضمان — المدة والتغطية'), q.warranty_applicable === false ? { text: T('N/A', 'لا ينطبق'), flag: 'na' }
    : warranty && coverage ? { text: `${warranty} — ${coverage}`, flag: 'match' }
    : warranty ? { text: `${warranty} — ${T('coverage not stated', 'التغطية غير مذكورة')}`, flag: 'missing' } : { text: T('Not stated', 'غير مذكور'), flag: 'missing' }]);
  blocks.push({ t: 'checks', items: checks });

  section('Commercial terms', 'الشروط التجارية');
  blocks.push({ t: 'terms', cols: 3, cells: [
    [T('Lead time', 'مدة التنفيذ'), lead || '—'], [T('Quote validity', 'صلاحية العرض'), validity || '—'], [T('Warranty', 'الضمان'), warranty || '—'],
    [T('Payment terms', 'شروط الدفع'), k.pay(q.payment_terms)],
    [T('Installation', 'التركيب'), q.installation_applicable === false ? T('N/A', 'لا ينطبق') : q.installation_included === true ? T('Included', 'مشمول') : q.installation_included === false ? T('Not included', 'غير مشمول') : T('Not stated', 'غير مذكور')],
    [T('Delivery to', 'التسليم إلى'), emirate || '—'],
  ] });

  const notes: Array<[string, string, unknown]> = [['Scope as stated by the supplier', 'نطاق العمل كما ذكره المورّد', q.scope], ['Assumptions and conditions', 'الافتراضات والشروط', q.conditions], ['Exclusions', 'الاستثناءات', q.exclusions], ['Supplier notes', 'ملاحظات المورّد', q.notes]];
  if (notes.some(([, , v]) => v != null && String(v).trim() !== '')) {
    section('Scope notes, assumptions and exclusions', 'ملاحظات النطاق والافتراضات والاستثناءات');
    for (const [en, arx, v] of notes) { if (v == null || String(v).trim() === '') continue; const r = k.loc(v, 800); blocks.push({ t: 'p', label: T(en, arx), text: r.text, sub: r.sub }); }
  }

  blocks.push({ t: 'callout', tone: 'grey', title: T('Standardised by QuotesDone from the supplier\'s submission', 'وحّدته QuotesDone من العرض الذي قدّمه المورّد'),
    text: T(`${PREPARED_BY.en}. This is QuotesDone's standard layout of the supplier's quote, not the supplier's own document, and it carries no signature. Figures, specifications and scope are as the supplier stated them; verify final details before ordering. QuotesDone charges the customer a 3% facilitation fee on the quoted value at the point of contact reveal.`,
      `${PREPARED_BY.ar}. هذا هو التنسيق الموحّد لعرض المورّد لدى QuotesDone وليس مستند المورّد نفسه، ولا يحمل توقيعًا. القيم والمواصفات والنطاق كما ذكرها المورّد؛ يُرجى التحقق من التفاصيل النهائية قبل الطلب. تتقاضى QuotesDone من العميل رسوم تيسير بنسبة 3% من قيمة العرض عند كشف بيانات التواصل.`) });
  if (args.requestUrl) blocks.push({ t: 'link', text: T('Open this quote on your request in the QuotesDone portal', 'افتح هذا العرض في طلبك على بوابة QuotesDone'), link: args.requestUrl });

  const cover0 = {
    kicker: T('Standardised quotation', 'عرض أسعار موحّد'), title: T('Quotation', 'عرض أسعار'),
    subtitle: clipCell(summary.text, 170),
    meta: [[T('Reference', 'الرقم المرجعي'), ref], [T('Date', 'التاريخ'), date], [T('Quoting party', 'مقدّم العرض'), party], [T('Trade', 'التخصص'), trade || '—']],
    figures: [[T('Total quoted', 'إجمالي العرض'), k.money(exVat)], [T('Lead time', 'مدة التنفيذ'), lead || '—'], [T('Warranty', 'الضمان'), warranty || '—'], [T('Valid for', 'صالح لمدة'), validity || '—']],
  };
  const control = `${ref} · ${DOC_VERSION} · ${T('Generated', 'أُنشئ في')} ${date} · ${ar ? PREPARED_BY.ar : PREPARED_BY.en}`;
  const names = args.maskNames || [];
  const body: Record<string, unknown> = {
    lang, ref, name: docName(ref, 'quotation', lang), title: T('Quotation', 'عرض أسعار'),
    cover: maskDeep(cover0, names, lang), control, blocks: maskDeep(blocks, names, lang), options: { letterhead: true },
  };
  if (args.date) body.date = args.date; if (args.date_ar) body.date_ar = args.date_ar;
  return { body, ref, untranslated: [...k.untranslated] };
}

// ── The comparison report ───────────────────────────────────────────────────────────────────────
// deno-lint-ignore no-explicit-any
function techOf(a: any): TechnicalComparison | null {
  const t = a?.technical;
  return t && Array.isArray(t.suppliers) && Array.isArray(t.lines) ? t as TechnicalComparison : null;
}
// deno-lint-ignore no-explicit-any
function heldLabels(a: any): Set<string> { return new Set(arrOf(a?.all_quotes).filter((r: any) => r && r.status === 'held').map((r: any) => String(r.label))); }
const cellText = (c: Cell) => typeof c === 'string' ? c : c.text;
// 'a.; b.' read as a typo: each item loses its own full stop before the list is joined.
// deno-lint-ignore no-explicit-any
const joinList = (x: any, ar = false) => arrOf(x).map((s: unknown) => String(s ?? '').trim().replace(/[.。]+$/, '')).filter(Boolean).join(ar ? '؛ ' : '; ');

// THE SIDE-BY-SIDE COMMERCIAL TABLE, ONCE. The report renders the rich cells and compare_csv
// exports the same rows as text (compareTable), so the spreadsheet can never disagree with the page.
// deno-lint-ignore no-explicit-any
function commercialRows(a: any, lang: Lang, names: string[] = [], arTexts: ArTexts = {}, sink?: Set<string>): { head: Cell[]; rows: Cell[][]; labels: string[] } | null {
  const k = kit(lang, names, arTexts);
  const out = commercialRowsOf(a, k);
  if (sink) for (const t of k.untranslated) sink.add(t);
  return out;
}
// deno-lint-ignore no-explicit-any
function commercialRowsOf(a: any, k: Kit): { head: Cell[]; rows: Cell[][]; labels: string[] } | null {
  const { T } = k;
  const held = heldLabels(a);
  // deno-lint-ignore no-explicit-any
  const qs = arrOf(a?.quotes).filter((q: any) => !held.has(String(q.label)));
  if (!qs.length) return null;
  const terms = techOf(a)?.terms || null;
  const rows: Cell[][] = [];
  // deno-lint-ignore no-explicit-any
  const push = (label: string, get: (q: any) => Cell) => { const vals = qs.map(get); if (vals.some((v: Cell) => cellText(v) && cellText(v) !== '—')) rows.push([{ text: label, bold: true }, ...vals]); };
  // deno-lint-ignore no-explicit-any
  const term = (t: TechTerm | null | undefined, q: any, fallback: Cell): Cell => {
    if (t && t.applicable === false) return { text: T('N/A', 'لا ينطبق'), flag: 'na' };
    const c = t?.values?.[String(q.label)];
    return c ? flagged(k, c) : fallback;
  };
  // deno-lint-ignore no-explicit-any
  const list = (x: any, n: number): Cell => { const s = clipCell(joinList(x, k.ar), n); return s ? k.cell(k.sentence(s), n) : '—'; };
  push(T('Price', 'السعر'), (q) => k.money(Number(q.price_ex_vat) > 0 ? q.price_ex_vat : q.price));
  push(T('Delivery / lead time', 'التسليم / مدة التنفيذ'), (q) => term(terms?.lead_time, q, k.dur(q.lead_time) || '—'));
  if (terms?.installation) push(T('Installation', 'التركيب'), (q) => term(terms.installation, q, '—'));
  push(T('Warranty', 'الضمان'), (q) => term(terms?.warranty, q, k.dur(q.warranty) || '—'));
  push(T('Payment terms', 'شروط الدفع'), (q) => k.pay(q.payment_terms));
  push(T('Valid for', 'مدة الصلاحية'), (q) => k.dur(q.validity) || '—');
  push(T('What you get', 'ما ستحصل عليه'), (q) => k.sentence(clipCell(q.getting, 240)) || '—');
  push(T('Included', 'مشمول'), (q) => list(q.includes, 240));
  push(T('Not included', 'غير مشمول'), (q) => list(q.excludes, 200));
  push(T('Missing from your request', 'ناقص مما طلبت'), (q) => list(q.missing_from_request, 200));
  push(T('Differs from your spec', 'اختلاف عن مواصفاتك'), (q) => list(q.spec_deviation, 200));
  push(T('Track record', 'سجل الأداء'), (q) => q.track_record_note ? k.cell(k.sentence(q.track_record_note), 180) : '—');
  push(T('Watch out', 'تنبيهات'), (q) => k.sentence(clipCell(joinList(q.flags, k.ar), 200)) || '—');
  // deno-lint-ignore no-explicit-any
  // The FULL label, never clipped: a label is the only thing that tells two options of one supplier
  // apart. Clipped to 20 characters, "Supplier A – Option 1" and "Supplier A – Option 2" both became
  // "Supplier A – Option…" in the report's commercial table and in compare_csv (measured 14 Sep 2026,
  // e2e journey c). Labels are system-made ("Supplier X – Option N"), so their length is bounded.
  return { head: [T('Compare', 'المقارنة'), ...qs.map((q: any) => k.label(q.label))], rows, labels: qs.map((q: any) => String(q.label)) };
}
const MARK: Record<SpecFlag, string> = { match: '✓', differs: '≠', missing: '—', optional: '○', na: '' };
/** The commercial comparison as text rows: what compare_csv exports. Same rows as the report. */
// deno-lint-ignore no-explicit-any
export function compareTable(a: any, ar: boolean, arTexts: ArTexts = {}): { head: string[]; rows: string[][]; untranslated: string[] } | null {
  const sink = new Set<string>();
  const r = commercialRows(a, ar ? 'ar' : 'en', [], arTexts, sink);
  if (!r) return null;
  const txt = (c: Cell) => { if (typeof c === 'string') return c; const m = c.flag ? MARK[c.flag] : ''; return (m && c.text !== '—' ? m + ' ' : '') + c.text; };
  return { head: r.head.map(cellText), rows: r.rows.map((row) => row.map(txt)), untranslated: [...sink] };
}
/** RFC 4180 cells, plus a leading apostrophe on anything a spreadsheet would run as a formula. */
// The trigger set is = + - @ AND a leading tab or carriage return (OWASP CSV injection): cells carry
// supplier-written text (flags, inclusions, exclusions), and a spreadsheet trims a leading tab/CR
// and then evaluates what follows. Until 14 Sep 2026 only the first four were escaped.
export function toCsv(head: string[], rows: string[][]): string {
  const cell = (v: unknown) => { let s = String(v ?? ''); if (/^[=+\-@\t\r]/.test(s)) s = "'" + s; return /[",\r\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
  // The BOM is what makes Excel read the file as UTF-8; without it Arabic opens as mojibake.
  return '﻿' + [head, ...rows].map((r) => r.map(cell).join(',')).join('\r\n') + '\r\n';
}

/** The pdf_native body for the comparison report in ONE language. `a` is quote_compare's analysis;
 * `a.technical` (optional) is the TechnicalComparison. */
// linkFor: a quote id → the portal deep link that opens that quote (site_origins portalLink). With
// it, every supplier cell in "Recommended" and "All quotes received" links to its own quote rather
// than to the portal in general. The link carries ids only; the label beside it is the anonymous one.
// deno-lint-ignore no-explicit-any
export function compareDocument(args: { analysis: any; inquiry: InquiryRow; lang: Lang; maskNames?: string[]; portalUrl?: string; linkFor?: (quoteId: string) => string; date?: string; date_ar?: string; arTexts?: ArTexts }) {
  const { analysis: a, inquiry: inq, lang } = args;
  const k = kit(lang, args.maskNames || [], args.arTexts); const { T, ar } = k;
  const ref = 'QD-' + jobNoOf(inq) + '-CMP';
  const date = (ar ? args.date_ar : args.date) || k.today();
  const roster = arrOf(a.all_quotes);
  const held = heldLabels(a);
  // deno-lint-ignore no-explicit-any
  const qs = arrOf(a.quotes).filter((q: any) => !held.has(String(q.label)));
  const received = roster.length || Number(a.total_quotes) || Number(a.considered) || qs.length;
  const tech = techOf(a);
  // top3 names quotes by label only; the roster carries each label's quote_id.
  // deno-lint-ignore no-explicit-any
  const idOf = new Map<string, string>(roster.filter((r: any) => r && r.label && r.quote_id).map((r: any) => [String(r.label), String(r.quote_id)]));
  const linked = (text: string, quoteId: unknown, extra: Record<string, unknown> = {}): Cell => (args.linkFor && quoteId ? { text, link: args.linkFor(String(quoteId)), ...extra } : (Object.keys(extra).length ? { text, ...extra } : text));
  const trade = ar ? (arCategory(inq?.category) ?? k.loc(inq?.category).text) : enCategory(inq?.category);
  const emirate = ar ? (arEmirate(inq?.emirate) ?? k.loc(inq?.emirate).text) : String(inq?.emirate || '');
  const summary = k.loc(inq?.summary, 600);
  // deno-lint-ignore no-explicit-any
  const prices = roster.filter((r: any) => r.status !== 'held' && Number(r.price_ex_vat ?? r.price) > 0).map((r: any) => Number(r.price_ex_vat ?? r.price));
  const top = arrOf(a.top3);
  // deno-lint-ignore no-explicit-any
  const blocks: any[] = [];
  let n = 0; const section = (en: string, arx: string) => blocks.push({ t: 'section', n: ++n, text: T(en, arx) });
  // The report states its method once, in its own section; the rules ranking's bottom line repeats it.
  const strip = (s: unknown) => String(s ?? '').replace(METHOD_NOTE_EN, '').replace(METHOD_NOTE_AR, '').replace(/\s+/g, ' ').trim();

  // 1 — Executive summary
  section('Executive summary', 'الملخص التنفيذي');
  if (strip(a.bottom_line)) blocks.push({ t: 'p', text: k.sentence(strip(a.bottom_line)), size: 11 });
  if (a.overview) blocks.push({ t: 'p', text: k.sentence(String(a.overview)) });
  if (top.length) {
    const t1 = top[0]; const id1 = idOf.get(String(t1.label));
    blocks.push({ t: 'callout', tone: 'teal', title: T('Recommended: ', 'التوصية: ') + k.label(t1.label), text: k.sentence(String(t1.why || '')) + (t1.tradeoff ? ' ' + T('Catch: ', 'الاعتبار: ') + k.sentence(String(t1.tradeoff)) : ''), ...(id1 && args.linkFor ? { link: args.linkFor(id1) } : {}) });
  }
  if (a.shortlist_reason) blocks.push({ t: 'note', text: k.sentence(String(a.shortlist_reason)) });
  if (top.length) {
    blocks.push({ t: 'h3', text: T('Recommended', 'التوصية') });
    blocks.push({ t: 'table', head: ['#', T('Supplier', 'المورّد'), T('Why', 'السبب'), T('Catch', 'الاعتبار')],
      // deno-lint-ignore no-explicit-any
      rows: top.map((r: any, i: number) => [String(r.rank ?? i + 1), linked(clipCell(k.label(r.label), 24), idOf.get(String(r.label)), { bold: true }), k.sentence(clipCell(r.why, 220)), k.sentence(clipCell(r.tradeoff, 160)) || '—']),
      widths: [0.06, 0.17, 0.47, 0.30], align: ['c', 's', 's', 's'], zebra: true });
    // deno-lint-ignore no-explicit-any
    const scored = top.map((t: any) => arrOf(a.quotes).find((q: any) => q.label === t.label)).filter((q: any) => q && [q.price_score, q.quality_score, q.delivery_score].every((x: unknown) => Number(x) > 0));
    if (scored.length) {
      blocks.push({ t: 'scores', head: [T('Price', 'السعر'), T('Completeness', 'الاكتمال'), T('Delivery', 'التسليم'), T('Overall', 'الإجمالي')],
        // deno-lint-ignore no-explicit-any
        rows: scored.map((q: any, i: number) => ({ label: k.label(q.label), rank: i + 1, scores: [Number(q.price_score), Number(q.quality_score), Number(q.delivery_score)], overall: Math.round((q.price_score * 0.4 + q.quality_score * 0.4 + q.delivery_score * 0.2) * 10) / 10 })),
        note: T('Scores run from 1 (weakest) to 5 (strongest), relative to the other quotes on this request. Overall weights price 40%, completeness 40% and delivery 20%.', 'الدرجات من 1 (الأضعف) إلى 5 (الأقوى) مقارنةً ببقية العروض على هذا الطلب. الإجمالي: السعر 40%، والاكتمال 40%، والتسليم 20%.') });
    }
  }

  // 2 — Method and what is assessed
  section('Method and scope of assessment', 'المنهجية ونطاق التقييم');
  blocks.push({ t: 'p', text: T(`${PREPARED_BY.en} from the ${received} quotes submitted on your request. Quotes are ranked on the figures each supplier stated: price, completeness, lead time, warranty and payment terms.`,
    `${PREPARED_BY.ar} استنادًا إلى العروض الـ${received} المقدّمة على طلبك. رُتّبت العروض وفق الأرقام التي ذكرها كل مورّد: السعر، واكتمال العرض، ومدة التنفيذ، والضمان، وشروط الدفع.`) });
  blocks.push({ t: 'p', text: tech
    ? T('Material specifications are compared line by line with your request, exactly as each supplier stated them: each value is marked as matching your request, differing from it, or not stated.', 'تُقارن مواصفات المواد بندًا بندًا مع طلبك، كما ذكرها كل مورّد تمامًا: كل قيمة معلّمة بأنها مطابقة لطلبك أو مختلفة عنه أو غير مذكورة.')
    : T('Specifications are not assessed; check them before you pay.', 'لم تُقيَّم المواصفات؛ يُرجى التحقق منها قبل الدفع.') });
  blocks.push({ t: 'kv', pairs: [
    [T('Assessed', 'ما تم تقييمه'), T(`Price, completeness, lead time, installation, warranty, payment terms${tech ? ', line-by-line material specification' : ''}`, `السعر، والاكتمال، ومدة التنفيذ، والتركيب، والضمان، وشروط الدفع${tech ? '، ومواصفات المواد بندًا بندًا' : ''}`)],
    [T('Not assessed', 'ما لم يتم تقييمه'), T('Workmanship, supplier capacity, site conditions, and anything a supplier did not state in writing', 'جودة التنفيذ، وقدرة المورّد، وظروف الموقع، وأي أمر لم يذكره المورّد كتابيًا')],
  ] });

  // 3 — Technical comparison
  const cols = tech ? tech.suppliers.filter((l) => !held.has(String(l))) : [];
  section('Technical comparison', 'المقارنة الفنية');
  if (tech && cols.length) {
    blocks.push(legendBlock(k));
    blocks.push({ t: 'h3', text: T('Completeness: the four checks, side by side', 'الاكتمال: البنود الأربعة جنبًا إلى جنب') });
    const matFor = (l: string): Cell => {
      const flags = tech.lines.flatMap((ln) => ln.attributes.map((at) => at.values?.[l]?.flag ?? 'missing')).filter((f) => f !== 'na');
      const miss = flags.filter((f) => f === 'missing').length, dif = flags.filter((f) => f === 'differs').length;
      if (!flags.length) return { text: T('N/A', 'لا ينطبق'), flag: 'na' };
      if (miss) return { text: T(`${miss} not stated`, `${miss} غير مذكورة`), flag: 'missing' };
      if (dif) return { text: T(`${dif} of ${flags.length} differ`, `${dif} من ${flags.length} مختلفة`), flag: 'differs' };
      return { text: T(`All ${flags.length} match`, `جميعها مطابقة (${flags.length})`), flag: 'match' };
    };
    const termRow = (en: string, arx: string, t: TechTerm | null | undefined): Cell[] => [{ text: T(en, arx), bold: true }, ...cols.map((l): Cell => t?.applicable === false ? { text: T('N/A', 'لا ينطبق'), flag: 'na' } : flagged(k, t?.values?.[l]))];
    const cw = 0.72 / cols.length;
    blocks.push({ t: 'table', head: [T('Check', 'البند'), ...cols.map((l) => k.label(l))], widths: [0.28, ...cols.map(() => cw)], zebra: true, rows: [
      [{ text: T('Material specification, per line', 'مواصفات المواد لكل بند'), bold: true }, ...cols.map(matFor)],
      termRow('Delivery / lead time', 'التسليم / مدة التنفيذ', tech.terms?.lead_time),
      termRow('Installation', 'التركيب', tech.terms?.installation),
      termRow('Warranty — period and coverage', 'الضمان — المدة والتغطية', tech.terms?.warranty),
    ] });
    blocks.push({ t: 'h3', text: T('Line by line: stated specification against your request', 'بندًا بندًا: المواصفات المذكورة مقابل طلبك') });
    const rows: Cell[][] = [];
    tech.lines.forEach((ln, i) => {
      const qty = [ln.qty, ln.unit ? (ar ? (arUnit(ln.unit) ?? k.loc(ln.unit).text) : ln.unit) : ''].filter((x) => x != null && String(x) !== '').join(' ');
      rows.push([{ text: `${ln.line_no ?? i + 1}. ${k.loc(ln.item, 120).text}${qty ? ' — ' + qty : ''}`, group: true }]);
      for (const at of ln.attributes) {
        const name = ar ? (arAttr(at.key) ?? arAttr(at.label) ?? k.loc(at.label || at.key).text) : String(at.label || at.key).replace(/_/g, ' ').replace(/^\w/, (c) => c.toUpperCase());
        rows.push([{ text: name, bold: true }, at.requested ? k.cell(at.requested, 120) : '—', ...cols.map((l) => flagged(k, at.values?.[l]))]);
      }
    });
    blocks.push({ t: 'table', head: [T('Specification', 'المواصفة'), T('You asked for', 'طلبك'), ...cols.map((l) => k.label(l))], widths: [0.16, 0.18, ...cols.map(() => (0.66 / cols.length))], rows, zebra: true, fs: cols.length >= 4 ? 7.8 : 8.5 });
  } else {
    blocks.push({ t: 'p', text: T('The suppliers\' line specifications for this request are not in a comparable form yet, so no line-by-line specification table is shown. The commercial comparison below still applies, and each quotation shows its specification exactly as the supplier stated it.', 'لم تصل مواصفات البنود من المورّدين لهذا الطلب بصيغة قابلة للمقارنة بعد، لذا لا يظهر جدول المواصفات بندًا بندًا. المقارنة التجارية أدناه سارية، وكل عرض يعرض مواصفاته كما ذكرها المورّد تمامًا.'), muted: true });
  }
  if (tech) for (const l of held) blocks.push({ t: 'note', text: T(`${l} is on hold and is not compared here: its quote does not yet state everything a complete quote must.`, `${k.label(l)} معلّق ولا يُقارن هنا: عرضه لا يذكر بعد كل ما يجب أن يتضمنه العرض المكتمل.`) });
  if (arrOf(a.line_findings).length) {
    blocks.push({ t: 'h3', text: T('Line findings', 'ملاحظات البنود') });
    // deno-lint-ignore no-explicit-any
    blocks.push({ t: 'table', head: [T('Item', 'البند'), T('Finding', 'الملاحظة')], rows: arrOf(a.line_findings).map((f: any) => [k.cell(k.sentence(clipCell(f.item, 60))), k.cell(k.sentence(clipCell(f.finding, 300)))]), widths: [0.28, 0.72], zebra: true });
  }

  // 4 — Commercial comparison
  const side = commercialRows(a, lang, args.maskNames || [], args.arTexts, k.untranslated);
  if (side) {
    section('Commercial comparison', 'المقارنة التجارية');
    const colW = 0.76 / Math.max(1, side.labels.length);
    blocks.push({ t: 'table', head: side.head, rows: side.rows, widths: [0.24, ...side.labels.map(() => colW)], zebra: true });
    blocks.push({ t: 'note', text: T(VAT_LINE.en, VAT_LINE.ar) });
  }

  // 5 — Every quote received
  if (roster.length) {
    section(`All quotes received (${roster.length})`, `جميع العروض المستلمة (${roster.length})`);
    blocks.push({ t: 'p', text: T(`All ${roster.length} quotes on your request are listed here, and each one stays open to you: you can view or reveal any of them from your portal.`, `جميع العروض الـ${roster.length} على طلبك مدرجة هنا، وكلها تبقى متاحة لك: يمكنك عرض أي منها أو كشفه من بوابتك.`), muted: true });
    // deno-lint-ignore no-explicit-any
    const chip = (r: any): Cell => r.status === 'shortlisted' ? { text: T(`Shortlisted #${r.rank}`, `ضمن القائمة المختصرة #${r.rank}`), chip: 'short' }
      : r.status === 'held' ? { text: T('On hold', 'معلّق'), chip: 'hold' } : { text: T('Open to reveal', 'متاح للكشف'), chip: 'open' };
    blocks.push({ t: 'table', head: [T('Supplier', 'المورّد'), T('Price', 'السعر'), T('Lead time', 'مدة التنفيذ'), T('Status', 'الحالة')],
      // A held quote is counted, never detailed: no price and no lead time on the page.
      // deno-lint-ignore no-explicit-any
      rows: roster.map((r: any) => r.status === 'held'
        ? [linked(k.label(r.label), r.quote_id, { bold: true }), '—', '—', chip(r)]
        : [linked(k.label(r.label) + (r.expired ? T(' (expired)', ' (منتهي الصلاحية)') : ''), r.quote_id, { bold: true }), k.money(Number(r.price_ex_vat) > 0 ? r.price_ex_vat : r.price), k.dur(r.lead_time) || '—', chip(r)]),
      widths: [0.26, 0.22, 0.22, 0.30], align: ['s', 'e', 's', 's'], zebra: true });
    // deno-lint-ignore no-explicit-any
    for (const r of roster.filter((x: any) => x.status === 'held')) {
      const miss = typeof r.missing_mandatory === 'number' && r.missing_mandatory > 0 ? r.missing_mandatory : null;
      const why = r.price == null ? T('no price stated', 'لا يوجد سعر مذكور')
        : miss ? T(`${miss} mandatory detail(s) missing`, `${miss} من التفاصيل الإلزامية ناقصة`) : T('it does not pass our completeness check', 'لم يجتز فحص الاكتمال');
      blocks.push({ t: 'note', text: T(`${r.label} is on hold: ${why}. It is counted here but not ranked or detailed until the supplier completes it.`, `${k.label(r.label)} معلّق: ${why}. يُحتسب هنا لكنه لا يدخل الترتيب ولا تُعرض تفاصيله حتى يستكمله المورّد.`) });
    }
    blocks.push({ t: 'link', text: T('Every quote above stays open to you — the shortlist is advice, not a limit. You can choose any of them: open your QuotesDone portal to view or reveal it.',
      'كل العروض أعلاه تبقى متاحة لك، فالقائمة المختصرة نصيحة وليست قيدًا. يمكنك اختيار أي منها: افتح بوابتك في QuotesDone لعرضه أو كشفه.'), link: args.portalUrl });
  }

  // 6 — Risks and clarifications, per supplier
  const risk: Cell[][] = [];
  for (const q of qs) {
    const pts: string[] = [...arrOf(q.flags), ...arrOf(q.missing_from_request), ...arrOf(q.spec_deviation)].map(String);
    if (tech && cols.includes(String(q.label))) {
      tech.lines.forEach((ln, i) => ln.attributes.forEach((at) => {
        const c = at.values?.[String(q.label)]; if (!c || (c.flag !== 'differs' && c.flag !== 'missing')) return;
        const name = ar ? (arAttr(at.key) ?? k.loc(at.label || at.key).text) : String(at.label || at.key).replace(/_/g, ' ').toLowerCase();
        const item = k.loc(ln.item, 60).text; const no = ln.line_no ?? i + 1;
        // Only differs and missing reach this list; an optional detail not stated is shown in the table
        // as "Not stated (optional)" and is never chased. The missing branch is a SAFETY NET: the hold
        // gate keeps a quote with an unstated mandatory detail out of the comparison altogether.
        // Before the reveal the customer cannot reach a supplier; QuotesDone chases a missing detail
        // (founder, 14 Sep 2026). A mandatory detail left unstated holds the quote, and the hold desk
        // asks the supplier through customer_support (WhatsApp and email) until it is filled — so the
        // sentence says that, never "ask for it". A difference is stated as the supplier quoted it.
        pts.push(c.flag === 'missing'
          ? T(`Line ${no} (${item}): ${name} not stated — we have asked the supplier; this report updates when they answer.`, `البند ${no} (${item}): ${name} غير مذكورة — طلبناها من المورّد، وسيُحدَّث التقرير عند الرد.`)
          : T(`Line ${no} (${item}): ${name} is ${c.value ?? '—'}; you asked for ${at.requested ?? '—'}. This is what the supplier quoted in writing.`, `البند ${no} (${item}): ${name} ${k.loc(c.value ?? '—', 60).text} بينما طلبت ${k.loc(at.requested ?? '—', 60).text}. هذا ما قدّمه المورّد كتابيًا في عرضه.`));
      }));
    }
    const uniq = [...new Set(pts.map((p) => p.trim()).filter(Boolean))];
    uniq.forEach((p, i) => risk.push([i === 0 ? { text: k.label(q.label), bold: true } : '', k.cell(k.sentence(p), 240)]));
    if (!uniq.length) risk.push([{ text: k.label(q.label), bold: true }, T('Nothing flagged from what the supplier stated.', 'لا توجد ملاحظات مما ذكره المورّد.')]);
  }
  if (risk.length) {
    section('Risks and clarifications by supplier', 'المخاطر والاستيضاحات لكل مورّد');
    blocks.push({ t: 'table', head: [T('Supplier', 'المورّد'), T('What to know before you choose', 'ما يجب معرفته قبل الاختيار')], rows: risk, widths: [0.2, 0.8] });
  }

  // 7 — Advice and next steps
  if (a.best_value_reason || a.advice || arrOf(a.watch_outs).length) {
    section('Advice and next steps', 'النصيحة والخطوات التالية');
    if (a.best_value_reason) blocks.push({ t: 'p', text: k.sentence(String(a.best_value_reason)) });
    if (a.advice) blocks.push({ t: 'p', text: k.sentence(String(a.advice)) });
    for (const w of arrOf(a.watch_outs)) blocks.push({ t: 'li', text: k.sentence(String(w)) });
  }
  if (a.disclaimer) { blocks.push({ t: 'space', h: 4 }); blocks.push({ t: 'note', text: k.sentence(String(a.disclaimer)) }); }

  const lo = prices.length ? Math.min(...prices) : 0, hi = prices.length ? Math.max(...prices) : 0;
  const range = !prices.length ? '—' : lo === hi ? k.money(lo) : ar ? `${lo.toLocaleString('en-AE')}–${hi.toLocaleString('en-AE')} درهم` : `AED ${lo.toLocaleString('en-AE')}–${hi.toLocaleString('en-AE')}`;
  const cover0 = {
    kicker: T('Bid tabulation and technical comparison', 'جدول مقارنة العروض والمقارنة الفنية'), title: T('Quote comparison report', 'تقرير مقارنة العروض'),
    subtitle: clipCell(summary.text, 170),
    meta: [[T('Reference', 'الرقم المرجعي'), ref], [T('Date', 'التاريخ'), date], [T('Trade', 'التخصص'), trade || '—'], [T('Emirate', 'الإمارة'), emirate || '—']],
    figures: [[T('Quotes received', 'العروض المستلمة'), String(received)], [T('Compared in detail', 'قورنت بالتفصيل'), T(`${qs.length} of ${received}`, `${qs.length} من ${received}`)],
      [T('Price range', 'نطاق الأسعار'), range], [T('Recommended', 'الموصى به'), top.length ? k.label(top[0].label) : '—']],
  };
  const control = `${ref} · ${DOC_VERSION} · ${T('Generated', 'أُنشئ في')} ${date} · ${ar ? PREPARED_BY.ar : PREPARED_BY.en}`;
  const names = args.maskNames || [];
  const body: Record<string, unknown> = {
    title: T('Quote comparison report', 'تقرير مقارنة العروض'), ref, name: docName(ref, 'comparison', lang), lang,
    cover: maskDeep(cover0, names, lang), control, blocks: maskDeep(blocks, names, lang), options: { letterhead: true },
  };
  if (args.date) body.date = args.date; if (args.date_ar) body.date_ar = args.date_ar;
  return { body, ref, untranslated: [...k.untranslated] };
}

// ── The inquiry, as the supplier receives it ───────────────────────────────────────────────────
// 21 Sep 2026, sales_engineer. Founder instruction 435 (15 Sep 2026): each inquiry opens the sales
// engineer's template with all requirements, and the BOQ and drawings are downloadable, redacted.
// Measured 21 Sep 2026: the "Inquiries received" screen drew that template as a web page only; no
// document existed, while the customer had three (quotation, comparison, brief). This is the fourth,
// on the same renderer. The caller hands in the inbox's row — already through the inbox's scrubbers
// and its reveal gate — so nothing here reads the inquiry itself; contacts are masked once more on
// the way to the page, the way every other document does it.
/** One customer-authored BOQ line as the inbox serves it (quote_review.ts BoqRow). */
export type RequestLine = { section?: string | null; description?: string | null; section_ar?: string | null; description_ar?: string | null; qty?: number | string | null; unit?: string | null; qty_status?: string | null };
// WHERE A QUANTITY CAME FROM, as the supplier must read it (21 Sep 2026, sales_engineer; founder instruction
// 580: the BOQ PDF we send suppliers must be perfect). MEASURED on drawing_boq/drawing_chain.test.ts: a
// reader line with qty_status 'to_confirm' reached this page as a bare "12 nos", indistinguishable from a
// quantity printed on the drawing — the supplier could not tell OUR take-off estimate from the customer's
// own number, and the CSV beside it dropped the status too. Every status the chain writes
// (drawing_boq readers, boq_open_lines.settleLines, drawing_boq/confirm.ts) now prints as words, EN + AR.
// An unknown status is shown as "to confirm": a quantity whose origin we cannot state is never presented as read.
export function qtyBasis(l: RequestLine): { en: string; ar: string; open: boolean } | null {
  const st = String(l.qty_status ?? '').trim();
  if (l.qty == null || l.qty === '') return { en: 'Not counted: take off from the drawing', ar: 'لم تُعدّ: احسبها من المخطط', open: true };
  if (!st) return null;
  if (st === 'read') return { en: 'Read from the drawing', ar: 'مقروءة من المخطط', open: false };
  if (st === 'check_confirmed') return { en: 'Counted from the drawing, cross-checked', ar: 'معدودة من المخطط ومُتحقَّق منها', open: false };
  if (st === 'customer_confirmed') return { en: 'Our count, confirmed by the customer', ar: 'عددنا، وأكّده العميل', open: false };
  if (st === 'customer_stated') return { en: 'Stated by the customer', ar: 'حدّدها العميل', open: false };
  // to_confirm, estimated, estimated_supplier_to_verify — and any status this list does not know.
  return { en: 'To confirm: our estimate, verify the take-off', ar: 'للتأكيد: تقديرنا، يُرجى التحقق من الحصر', open: true };
}
export type InquiryDocRow = {
  id: string; rfq_no?: number | string | null; category?: string | null; emirate?: string | null; summary?: string | null; budget?: string | null;
  scope_type?: string | null; urgency?: string | null; created_at?: string | null;
  /** inquiries.spec after the inbox scrub; `customer_requirements` carries the four intake answers and `required_by`. */
  // deno-lint-ignore no-explicit-any
  spec?: any;
  boq?: { boq?: RequestLine[] } | null; boq_withheld?: boolean | null;
  /** What inquiry_documents offers for download, by name: the redacted drawing pages and the BOQ CSV. */
  documents: Array<{ kind: 'drawing_page' | 'boq_csv'; name: string; lines?: number }>;
  drawing_pages_failed?: number | null;
};
const URGENCY: Record<string, [string, string]> = { urgent: ['Urgent', 'عاجل'], high: ['Urgent', 'عاجل'], normal: ['Standard', 'عادي'], standard: ['Standard', 'عادي'], low: ['Not urgent', 'غير عاجل'], flexible: ['Flexible', 'مرن'] };
export function inquiryDocument(args: { inquiry: InquiryDocRow; lang: Lang; portalUrl?: string; date?: string; date_ar?: string; arTexts?: ArTexts }) {
  const { inquiry: i, lang } = args;
  const k = kit(lang, [], args.arTexts); const { T, ar } = k;
  const job = jobNoOf(i);
  const ref = quoteRef(i, 'RFQ');
  const date = (ar ? args.date_ar : args.date) || k.today();
  const trade = ar ? (arCategory(i.category) ?? k.loc(i.category).text) : enCategory(i.category);
  const emirate = ar ? (arEmirate(i.emirate) ?? k.loc(i.emirate).text) : String(i.emirate || '');
  const received = i.created_at ? new Date(i.created_at).toLocaleDateString(ar ? 'ar-AE-u-nu-latn' : 'en-GB', { day: 'numeric', month: 'long', year: 'numeric' }) : '—';
  // Customer free text: the reasoned Arabic, like the supplier's (see loc).
  const cust = (v: unknown, max: number): { text: string; sub?: string } => k.loc(v, max);
  const summary = cust(i.summary, 800);
  const req = i.spec && typeof i.spec === 'object' ? i.spec.customer_requirements : null;
  // The deadline: the intake's `required_by` (docs/contracts/intake_answers.md) — a date, or flexible,
  // or the customer's words. Never assumed: absent means "not stated".
  const rb = req && typeof req === 'object' ? req.required_by : null;
  const deadline = rb?.flexible === true ? T('Flexible', 'مرن')
    : rb?.date && /^\d{4}-\d{2}-\d{2}/.test(String(rb.date)) ? new Date(String(rb.date).slice(0, 10) + 'T00:00:00Z').toLocaleDateString(ar ? 'ar-AE-u-nu-latn' : 'en-GB', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' })
    : rb?.text ? cust(rb.text, 80).text : T('Not stated', 'غير مذكور');
  const urgency = i.urgency ? (URGENCY[norm(i.urgency)] ? T(URGENCY[norm(i.urgency)][0], URGENCY[norm(i.urgency)][1]) : k.loc(i.urgency, 40).text) : '';
  const rows: RequestLine[] = Array.isArray(i.boq?.boq) ? i.boq!.boq!.filter((r) => r && String(r.description || '').trim()) : [];
  const drawings = i.documents.filter((d) => d.kind === 'drawing_page').length;
  const failed = Number(i.drawing_pages_failed || 0);
  // deno-lint-ignore no-explicit-any
  const blocks: any[] = [];
  let n = 0; const section = (en: string, arx: string) => blocks.push({ t: 'section', n: ++n, text: T(en, arx) });

  section('The request', 'الطلب');
  blocks.push({ t: 'party', label: T('Requesting party', 'الجهة الطالبة'), chip: T('Customer', 'العميل'), note: T('Anonymous until the customer reveals your quotation. The customer\'s name and contact details reach you only after the reveal, through the portal.', 'هوية العميل مخفية حتى يكشف عن عرضك. لا تصلك بيانات التواصل إلا بعد الكشف، عبر البوابة.') });
  const kv: Array<[string, string]> = [[T('Job No.', 'رقم الطلب'), job], [T('Received', 'تاريخ الاستلام'), received], [T('Trade', 'التخصص'), trade || '—'], [T('Site', 'الموقع'), emirate || '—'], [T('Required by', 'مطلوب بحلول'), deadline]];
  if (urgency) kv.push([T('Urgency', 'الأولوية'), urgency]);
  if (i.scope_type) kv.push([T('Scope type', 'نوع النطاق'), k.loc(i.scope_type, 40).text]);
  blocks.push({ t: 'kv', pairs: kv });
  if (summary.text) blocks.push({ t: 'p', text: summary.text, sub: summary.sub, label: T('Scope', 'النطاق') });
  if (i.budget) { const b = cust(i.budget, 80); blocks.push({ t: 'p', text: b.text, sub: b.sub, label: T('Budget', 'الميزانية') }); }

  section('What the customer asked for', 'ما طلبه العميل');
  // The derived `display` rows are the one vocabulary every surface renders (the request card, the
  // supplier RFQ, the brief PDF); this document reads them in its own language and never re-derives.
  const disp = req && typeof req === 'object' && req.display && typeof req.display === 'object' ? req.display[lang] : null;
  const reqRows: Array<{ label?: unknown; value?: unknown }> = Array.isArray(disp) ? disp : [];
  if (reqRows.length) blocks.push({ t: 'table', head: [T('Requirement', 'المتطلب'), T('Requested', 'المطلوب')], rows: reqRows.map((r) => [clipCell(maskContacts(r.label, [], lang), 60), k.cell(r.value, 160)]), widths: [0.32, 0.68], align: ['s', 's'], zebra: true });
  else blocks.push({ t: 'note', text: T('The customer\'s answers on materials, installation, warranty and the required date were not recorded on this request. Quote as the scope and the bill of quantities state, and note any assumption.', 'لم تُسجَّل إجابات العميل عن المواد والتركيب والضمان والتاريخ المطلوب في هذا الطلب. سعّر وفق النطاق وجدول الكميات، ودوّن أي افتراض.') });

  section('Bill of quantities', 'جدول الكميات');
  if (i.boq_withheld) blocks.push({ t: 'callout', tone: 'grey', title: T('Held back', 'محجوب'), text: T('The bill of quantities is held back because it could not be proved free of the customer\'s details. Price from the drawings and the scope.', 'حُجب جدول الكميات لأنه لم يمكن إثبات خلوّه من بيانات العميل. سعّر من المخططات والنطاق.') });
  else if (rows.length) {
    const hasSection = rows.some((r) => r.section && String(r.section).trim());
    const head: Cell[] = ['#']; const widths = [0.05]; const align = ['c'];
    if (hasSection) { head.push(T('Section', 'القسم')); widths.push(0.16); align.push('s'); }
    // The basis column appears whenever any line carries a status (or has no quantity); a BOQ the customer
    // typed with plain numbers keeps the four columns it always had.
    const bases = rows.map(qtyBasis); const hasBasis = bases.some(Boolean);
    head.push(T('Description', 'الوصف'), T('Qty', 'الكمية'), T('Unit', 'الوحدة')); widths.push(hasSection ? (hasBasis ? 0.39 : 0.59) : (hasBasis ? 0.55 : 0.75), 0.10, 0.10); align.push('s', 'e', 'c');
    if (hasBasis) { head.push(T('Quantity basis', 'أساس الكمية')); widths.push(0.20); align.push('s'); }
    const body = rows.slice(0, 120).map((r, idx) => {
      const c: Cell[] = [String(idx + 1)];
      // Arabic page: the section and the description are the REASONED Arabic of the customer's words, like every
      // other line (decision point trade_glossary_ar). The word-matched section_ar / description_ar labels
      // (_shared/boq_arabic.ts) are not printed on a document.
      if (hasSection) c.push(k.cell(r.section, 60));
      c.push(k.cell(r.description, 240), r.qty == null || r.qty === '' ? '—' : String(r.qty), (ar ? (arUnit(r.unit) ?? k.loc(r.unit).text) : String(r.unit || '')) || '—');
      if (hasBasis) { const b = bases[idx]; c.push(b ? { text: T(b.en, b.ar), ...(b.open ? { flag: 'missing' as const } : {}) } : '—'); }
      return c;
    });
    blocks.push({ t: 'table', head, rows: body, widths, align, zebra: true });
    const open = bases.filter((b) => b?.open).length;
    if (open) blocks.push({ t: 'note', text: T(`${open} line${open === 1 ? ' is' : 's are'} marked "To confirm" or "Not counted": the quantity is our take-off estimate from the drawing, not the customer's figure. Measure it, and state the quantity you priced on your quotation.`, `${open} من البنود معلّمة «للتأكيد» أو «لم تُعدّ»: الكمية تقديرنا من المخطط وليست رقم العميل. تحقّق منها واذكر الكمية التي سعّرتها في عرضك.`) });
    if (rows.length > 120) blocks.push({ t: 'note', text: T(`${rows.length - 120} further lines are in the BOQ file.`, `يوجد ${rows.length - 120} بندًا إضافيًا في ملف جدول الكميات.`) });
  } else blocks.push({ t: 'note', text: T('No bill of quantities was attached. Price from the scope and the drawings.', 'لم يُرفق جدول كميات. سعّر من النطاق والمخططات.') });

  section('Documents attached', 'المستندات المرفقة');
  if (i.documents.length) {
    blocks.push({ t: 'table', head: ['#', T('Document', 'المستند'), T('File', 'الملف')], widths: [0.06, 0.5, 0.44], align: ['c', 's', 's'], zebra: true,
      rows: i.documents.map((d, idx) => [String(idx + 1), d.kind === 'boq_csv' ? T(`Bill of quantities (${d.lines || rows.length} lines, CSV)`, `جدول الكميات (${d.lines || rows.length} بندًا، ملف جدول بيانات)`) : T(`Drawing page (identity removed)`, `صفحة مخطط (بعد إخفاء الهوية)`), d.name]) });
  } else blocks.push({ t: 'note', text: T('No documents were attached to this inquiry.', 'لم تُرفق مستندات بهذا الطلب.') });
  if (failed) blocks.push({ t: 'note', text: T(`${failed} drawing page${failed === 1 ? '' : 's'} could not be served at the time of writing; the portal offers ${failed === 1 ? 'it' : 'them'} again when available.`, `تعذّر تقديم ${failed} من صفحات المخطط وقت الإعداد؛ تعرضها البوابة مجددًا عند توفرها.`) });

  blocks.push({ t: 'callout', tone: 'grey', title: T('Prepared by the QuotesDone sales engineer', 'أعدّه مهندس مبيعات QuotesDone'),
    text: T(`${PREPARED_BY.en}. This is the request as our sales engineer prepared it for you, with the customer's identity removed. Quote every line with its exact specification, the delivery date, installation and warranty, and the price excluding VAT; a quotation missing any of these is held until it is complete. Send it through the QuotesDone portal, where our sales engineer reviews it with you before it reaches the customer.`,
      `${PREPARED_BY.ar}. هذا هو الطلب كما أعدّه لك مهندس المبيعات لدينا، بعد إزالة هوية العميل. سعّر كل بند بمواصفاته الدقيقة، وتاريخ التسليم، والتركيب، والضمان، والسعر دون ضريبة القيمة المضافة؛ يُحجز أي عرض ينقصه شيء من ذلك حتى يكتمل. أرسله عبر بوابة QuotesDone حيث يراجعه معك مهندس المبيعات قبل وصوله إلى العميل.`) });
  if (args.portalUrl) blocks.push({ t: 'link', text: T('Open this inquiry in the QuotesDone supplier portal', 'افتح هذا الطلب في بوابة المورّدين على QuotesDone'), link: args.portalUrl });

  const inst = req?.installation?.required, warr = req?.warranty?.required;
  const instTxt = inst === 'yes' ? T('Required', 'مطلوب') : inst === 'supply_only' ? T('Supply only', 'توريد فقط') : inst === 'not_needed' ? T('Not needed', 'غير مطلوب') : inst === 'not_sure' ? T('To be stated', 'يُذكر في العرض') : '—';
  const warrTxt = warr === 'yes' ? (Number(req?.warranty?.min_months) > 0 ? (ar ? arCount(Number(req.warranty.min_months), 'month') + ' على الأقل' : `${Number(req.warranty.min_months)} months minimum`) : T('Required', 'مطلوب')) : warr === 'not_needed' ? T('Not needed', 'غير مطلوب') : warr === 'not_sure' ? T('To be stated', 'يُذكر في العرض') : '—';
  const cover0 = {
    kicker: T('Request for quotation', 'طلب عرض أسعار'), title: T('Inquiry', 'استفسار'),
    subtitle: clipCell(summary.text, 170),
    meta: [[T('Job No.', 'رقم الطلب'), job], [T('Date', 'التاريخ'), date], [T('Trade', 'التخصص'), trade || '—'], [T('Site', 'الموقع'), emirate || '—']],
    figures: [[T('Required by', 'مطلوب بحلول'), deadline], [T('BOQ lines', 'بنود الكميات'), i.boq_withheld ? T('Held', 'محجوب') : String(rows.length)], [T('Installation', 'التركيب'), instTxt], [T('Warranty', 'الضمان'), warrTxt]],
  };
  const control = `${ref} · ${DOC_VERSION} · ${T('Generated', 'أُنشئ في')} ${date} · ${ar ? PREPARED_BY.ar : PREPARED_BY.en}`;
  // Every secondary line on this document is the customer's wording, so it is labelled as such.
  const CUSTOMER_ORIGINAL = 'النص الأصلي من العميل: ';
  // deno-lint-ignore no-explicit-any
  const relabel = (v: any): any => typeof v === 'string' ? (v.startsWith(ORIGINAL) ? CUSTOMER_ORIGINAL + v.slice(ORIGINAL.length) : v) : Array.isArray(v) ? v.map(relabel) : v && typeof v === 'object' ? Object.fromEntries(Object.entries(v).map(([kk, x]) => [kk, kk === 'sub' ? relabel(x) : relabel(x)])) : v;
  const body: Record<string, unknown> = {
    title: T('Inquiry', 'استفسار'), ref, name: docName(ref, 'inquiry', lang), lang,
    cover: relabel(maskDeep(cover0, [], lang)), control, blocks: relabel(maskDeep(blocks, [], lang)), options: { letterhead: true },
  };
  if (args.date) body.date = args.date; if (args.date_ar) body.date_ar = args.date_ar;
  return { body, ref, job, drawings, untranslated: [...k.untranslated] };
}
