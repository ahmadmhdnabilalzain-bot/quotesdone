import { knownNameRe } from '../identity_text.ts';
import { priceStated, vatShort, type PriceRow } from '../stated_price.ts';
import { type SpecFlag, type TechTerm, type TechnicalComparison, arrOf, clipCell } from './rows.ts';
import { type ArTexts, type Cell, type Kit, flagged, kit } from './kit.ts';
import { type Lang } from './base.ts';

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

/** The roster row (all_quotes) for a shortlisted quote, as a PriceRow: the analysis' own `price` is its fallback. */
// deno-lint-ignore no-explicit-any
function statedOf(a: any): (q: any) => PriceRow {
  // deno-lint-ignore no-explicit-any
  const by = new Map<string, any>(arrOf(a?.all_quotes).filter((r: any) => r && r.label).map((r: any) => [String(r.label), r]));
  // deno-lint-ignore no-explicit-any
  return (q: any) => { const r = by.get(String(q.label)) || {}; return { quote_amount: r.price ?? q.price, price_ex_vat: q.price_ex_vat ?? r.price, gross_amount: r.gross_amount, discount_amount: r.discount_amount, vat_treatment: r.vat_treatment, vat_amount: r.vat_amount }; };
}

// IN compare_csv EVERY LIVE QUOTE IS A COLUMN, CHEAPEST FIRST (sandbox run 5, tag 321d13ae, 19 Oct 2026).
// The CSV's columns used to be the model's `quotes`, which quote_compare caps at three: with four
// submitted quotes the AED 131,000 one was in no column of compare_csv. The roster (all_quotes) is every
// live quote; the model's detail fills a column where it has one, the roster's own figures otherwise.
// The PDF keeps its detailed table to the shortlist and lists every quote in "All quotes received".
// deno-lint-ignore no-explicit-any
export function comparedQuotes(a: any): any[] {
  const held = heldLabels(a);
  // deno-lint-ignore no-explicit-any
  const detail = new Map<string, any>(arrOf(a?.quotes).filter((q: any) => q && q.label).map((q: any) => [String(q.label), q]));
  // deno-lint-ignore no-explicit-any
  const roster = arrOf(a?.all_quotes).filter((r: any) => r && r.label);
  // deno-lint-ignore no-explicit-any
  const rows: any[] = roster.length
    // deno-lint-ignore no-explicit-any
    ? roster.map((r: any) => detail.get(String(r.label)) || { label: r.label, price: r.price, lead_time: r.lead_time, warranty: r.warranty })
    : [...detail.values()];
  // deno-lint-ignore no-explicit-any
  const price = (q: any) => { const r = roster.find((x: any) => String(x.label) === String(q.label)); const p = Number(r?.price ?? q.price_ex_vat ?? q.price); return p > 0 ? p : Infinity; };
  // deno-lint-ignore no-explicit-any
  return rows.filter((q: any) => !held.has(String(q.label))).sort((x, y) => price(x) - price(y));
}

// THE SIDE-BY-SIDE COMMERCIAL TABLE, ONCE. The report renders the rich cells and compare_csv
// exports the same rows as text (compareTable) with one column per live quote (`every`), so no quote the page lists is missing from the spreadsheet.
// deno-lint-ignore no-explicit-any
function commercialRows(a: any, lang: Lang, names: string[] = [], arTexts: ArTexts = {}, sink?: Set<string>, every = false): { head: Cell[]; rows: Cell[][]; labels: string[] } | null {
  const k = kit(lang, names, arTexts);
  const out = commercialRowsOf(a, k, every);
  if (sink) for (const t of k.untranslated) sink.add(t);
  return out;
}
// deno-lint-ignore no-explicit-any
function commercialRowsOf(a: any, k: Kit, every = false): { head: Cell[]; rows: Cell[][]; labels: string[] } | null {
  const { T } = k;
  const qs = every ? comparedQuotes(a) : arrOf(a?.quotes).filter((q: any) => !heldLabels(a).has(String(q.label)));
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
  // Ruling 1207: the price as the supplier stated it ("AED 2,000, after discount AED 1,700") and its VAT as stated.
  // The ranking basis is the after-discount ex-VAT figure (stated_price.ts) — the same one our fee is taken on.
  const stated = statedOf(a);
  push(T('Price (excluding VAT)', 'السعر (غير شامل الضريبة)'), (q) => priceStated(stated(q), k.ar ? 'ar' : 'en'));
  push(T('VAT, as stated', 'الضريبة كما ذكرها المورّد'), (q) => vatShort(stated(q), k.ar ? 'ar' : 'en'));
  push(T('Delivery / lead time', 'التسليم / مدة التنفيذ'), (q) => term(terms?.lead_time, q, k.dur(q.lead_time) || '—'));
  if (terms?.installation) push(T('Installation', 'التركيب'), (q) => term(terms.installation, q, '—'));
  push(T('Warranty', 'الضمان'), (q) => term(terms?.warranty, q, k.dur(q.warranty) || '—'));
  push(T('Payment terms', 'شروط الدفع'), (q) => k.pay(q.payment_terms));
  push(T('Valid for', 'مدة الصلاحية'), (q) => k.dur(q.validity) || '—');
  // Masked like every other supplier-written cell (13 Nov 2026: a raw "getting" sentence crossed with the supplier's name).
  push(T('What you get', 'ما ستحصل عليه'), (q) => k.sentence(clipCell(q.getting == null ? q.getting : k.mask(q.getting), 240)) || '—');
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
// 13 Nov 2026 (anonymity audit, REPORT_C L7): the CSV was the comparison's rows WITHOUT the supplier names the PDF masks
// (commercialRows was given []), so "balance on completion - Desert Brush team" crossed in the CSV after the PDF hid it.
// `maskNames` is the same list compareDocument receives (customer_api lib/pdfs.ts compareMaskNames).
export function compareTable(a: any, ar: boolean, arTexts: ArTexts = {}, maskNames: string[] = []): { head: string[]; rows: string[][]; untranslated: string[] } | null {
  const sink = new Set<string>();
  const r = commercialRows(a, ar ? 'ar' : 'en', maskNames, arTexts, sink, true);
  if (!r) return null;
  const txt0 = (c: Cell) => { if (typeof c === 'string') return c; const m = c.flag ? MARK[c.flag] : ''; return (m && c.text !== '—' ? m + ' ' : '') + c.text; };
  // The supplier's name as he writes it ("balance on completion - Desert Brush team", REPORT_C L1), not only whole: the
  // name with its fragments, as quote_compare's last gate already does (second review of 13 Nov 2026).
  const frags = maskNames.map((n) => knownNameRe(n, { fragments: true })).filter(Boolean) as RegExp[];
  const txt = (c: Cell) => { let t = txt0(c); for (const re of frags) t = t.replace(re, ar ? 'المورّد' : 'the supplier'); return t; };
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

// Names the sibling modules of this folder import (the declarations above are unchanged).
export { commercialRows, heldLabels, techOf };
