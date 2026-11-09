import { LICENCE_NO, TRN_BARE, TRN_LABELLED } from '../identity_numbers.ts';
import { knownNameRe, scrubIdentityText } from '../identity_text.ts';

export type Lang = 'en' | 'ar';
/** The version printed in each document's control line AND carried in its file name. Bump when the
 * layout or wording changes: a cached file whose name lacks the current version is re-rendered
 * (isCurrentDoc). v2.1, 21 Sep 2026: the Arabic fixes of #782/#790/#794 — before this, the cache kept
 * serving documents rendered by v2.0 for as long as the quote was untouched. v2.2, 23 Sep 2026: the Arabic of a
 * person's words is reasoned (decision point trade_glossary_ar), so every glossary-era Arabic file is re-rendered.
 * v2.3, 13 Oct 2026: rulings 1207/1208 — the supplier's discount and VAT as stated, the fee basis line and the
 * not-responsible clause; every v2.2 file said "Prices shown exclude VAT" and is re-rendered. */
export const DOC_VERSION = 'v2.3';
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
/**
 * `parties: false` (a quotation the customer PAID to reveal, review of #1838 item 1): firm and person names are left
 * alone, so the party chip and the supplier's own words name the supplier; contacts and numbers are still masked.
 */
export function maskContacts(s: unknown, names: string[] = [], lang: Lang = 'en', opts: { parties?: boolean } = {}): string {
  let t = String(s == null ? '' : s);
  // The placeholder follows the script of the text it sits in, not the page: an Arabic placeholder
  // inside an English supplier note turned the whole note right-to-left and scrambled its order.
  const H = HIDDEN[/[؀-ۿ]/.test(t) ? 'ar' : /[A-Za-z]/.test(t) ? 'en' : lang];
  // _shared/anonymise paints what it removes as '█'. No brand font carries that glyph: measured 21 Sep 2026
  // (drawing_boq/drawing_chain.test.ts) the inquiry PDF dropped it — 6 characters in English, 5 in Arabic —
  // so a scrubbed BOQ line printed "call  on  or ," with nothing saying something was taken out.
  t = t.replace(/█+/g, H);
  // A match starts only where the token starts (?<!...): without it a 20 KB run with no "@" was retried from every
  // position, quadratic, 1,064 ms in CI on "0-0-0-..." (identity_text.test.ts "no shape backtracks").
  t = t.replace(/(?<![\w.+-])[\w.+-]+@[\w-]+(?:\.[\w-]+)+/g, H);
  t = t.replace(/\b(?:https?:\/\/|www\.)\S+/gi, H);
  // With its path: "instagram.com/alnoortrading" kept the handle (second review of #1838).
  t = t.replace(/(?<![\w-])[\w-]+\.(?:com|ae|net|org|co)(?:\.[a-z]{2})?\b(?:\/[^\s,;)\]]*)?/gi, H);
  // A TRN or licence number finds the company on a public register (founder, 14 Sep 2026). Before
  // the phone patterns, which would otherwise take a 15-digit TRN apart and leave its label behind.
  t = t.replace(TRN_LABELLED, H).replace(TRN_BARE, H).replace(LICENCE_NO, H);
  // UAE numbers are read by the shared list below (3 Nov 2026, review of #1838: "\b0[2-9](?:[\s-]?\d){7,8}" took
  // "03 120 4500" out of a BOQ row and "075 110 160" out of a pipe list). Any other international run of 9+ digits:
  t = t.replace(/\+\d(?:[\s-]?\d){8,13}\b/g, H);
  // 3 Nov 2026 (identity_never_leaks_before_reveal.mjs): every shape in the shared list (_shared/identity_text.ts), and
  // each named supplier by knownNameRe too: its suffix-free core and any two consecutive words of its name.
  // Whole names only here: these documents carry several suppliers' text and a fragment of one supplier's name is
  // another's ordinary scope (review of #1838 item 2). The supplier's own text lost its fragments at save.
  t = scrubIdentityText(t, H, { parties: opts.parties });
  for (const n of names) { const re = knownNameRe(n); if (re && String(n).replace(/[^A-Za-z؀-ۿ]/g, '').length >= 3) t = t.replace(re, H); }
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
function maskDeep(v: any, names: string[], lang: Lang, parties = true): any {
  if (typeof v === 'string') return maskContacts(v, names, lang, { parties });
  if (Array.isArray(v)) return v.map((x) => maskDeep(x, names, lang, parties));
  // deno-lint-ignore no-explicit-any
  if (v && typeof v === 'object') { const o: any = {}; for (const k of Object.keys(v)) o[k] = (k === 'link') ? v[k] : maskDeep(v[k], names, lang, parties); return o; }
  return v;
}

// Names the sibling modules of this folder import (the declarations above are unchanged).
export { PREPARED_BY, maskDeep };
