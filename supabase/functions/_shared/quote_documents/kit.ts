import { arAttr } from '../trade_glossary_ar.ts';
import { aed } from '../money.ts';
import { needsArabic } from '../arabic_script.ts';
import { type Item, type SpecCell, type SpecFlag, arLabelWords, clipCell, labelFor } from './rows.ts';
import { type Lang, maskContacts } from './base.ts';
import { arDuration } from './arabic.ts';

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
  const clean = (v: unknown) => maskContacts(v, names, 'en');
  const T = (en: string, arx: string) => (ar ? arx : en);
  // One formatter for both languages (money.ts): the Arabic page differs only in the unit's word.
  const money = (v: unknown, dec = false) => aed(v, lang, dec);
  // Supplier or customer free text in the page's language. On an Arabic page it is the reasoned Arabic handed
  // in as arTexts; a line without it is recorded in `untranslated` and the document is held, never printed.
  const loc = (v: unknown, max = 400): { text: string; sub?: string } => {
    const s = clipCell(clean(v), max);
    if (!s || !ar || !needsArabic(s)) return { text: s };   // Arabic with a label or code kept as written is Arabic (arabic_script.ts)
    if (arTexts[s]) return { text: arTexts[s] };
    untranslated.add(s);
    return { text: s };
  };
  const cell = (v: unknown, max = 400): Cell => { const r = loc(v, max); return r.sub ? r : (r.text || '—'); };
  const dur = (v: unknown) => { const c = clipCell(v, 60); if (!c) return ''; return ar ? (arDuration(c) ?? loc(c).text) : c; };
  const pay = (v: unknown): Cell => { const c = clipCell(clean(v), 90); if (!c) return '—'; return ar ? cell(c) : c; };
  const label = (l: unknown) => labelFor(l, lang);
  // Analysis sentences name suppliers by label and prices in AED: both take the page's language.
  // deno-lint-ignore no-explicit-any
  const sentence = (v: any): any => typeof v === 'string'
    ? (ar ? arLabelWords(v).replace(/\bAED\s?([\d,.]+)/g, '$1 درهم') : v)
    : Array.isArray(v) ? v.map(sentence) : (v && typeof v === 'object') ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, k === 'link' ? x : sentence(x)])) : v;
  const today = () => new Date().toLocaleDateString(ar ? 'ar-AE-u-nu-latn' : 'en-GB', { timeZone: 'Asia/Dubai', day: 'numeric', month: 'long', year: 'numeric' });
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

// Names the sibling modules of this folder import (the declarations above are unchanged).
export { ORIGINAL, flagged, hasSpecs, kit, legendBlock, specText };
export type { Cell, Kit };
