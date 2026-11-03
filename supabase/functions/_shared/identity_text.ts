// identity_text.ts — the identity shapes EVERY scrubber between the two sides must remove, in one place
// (3 Nov 2026, sales_engineer; qualification matrix gap #3, P0).
//
// MEASURED BEFORE (scripts/e2e/identity_never_leaks_before_reveal.mjs, seed 20261103, 1 repeat = 160 trials):
// 140 of 160 drawing + quotation trials leaked, and 60 of 60 pre-reveal Q&A messages. The quotation path alone
// handed the customer, before any reveal: IBANs (102 hits), transliterated company names (93), addresses (87),
// the supplier's own company name (68), English and Arabic person names (66 / 58), Arabic company names (56),
// P.O. Boxes (56), licence numbers written "TL 273158" / "CN-974461" (34), and phones written "(050) 000 0076",
// "971500000064" or in Arabic-Indic digits "+٩٧١ ٥٠ ٠٠٠ ٠٠٦١" (37). Five scrubbers stood between the sides
// (supplier_api identity_scrub, drawing_boq scrubIdentity, quote_documents maskContacts, messages_api stripContact,
// customer_api's copy) and each carried its own partial list: none knew an IBAN or a P.O. Box, none read an
// Arabic-Indic digit except stripContact, none removed a name after "Prepared by:" or an Arabic firm name.
//
// So the list lives here and each scrubber runs it. Every pattern is written so the ordinary words and figures of
// a BOQ and a quotation do not trip it: a phone needs its own digit count and a leading 0 / 971 with no decimal
// point after the 0; a firm needs Title-Case words before a firm suffix; a person needs a label before it.
import { LICENCE_NO, TRN_BARE, TRN_LABELLED } from './identity_numbers.ts';

const D = '[0-9٠-٩۰-۹]';
const NOT_D = '(?<![0-9٠-٩۰-۹])';
const END_D = '(?![0-9٠-٩۰-۹])';
const SEP = '[\\s.\\-\\u00a0]?';
/** A word in either case, for the labels (no (?i) modifier: these regexes are case-sensitive on purpose). */
const ci = (w: string) => w.replace(/[A-Za-z]/g, (c) => `[${c.toUpperCase()}${c.toLowerCase()}]`);

/** UAE numbers: +971 / 00971 / 971, an optional (0), then 8-9 digits; national 0X / 05X / (04) / (050); any digit script. */
export const PHONE_UAE_INTL = new RegExp(`${NOT_D}(?:\\+\\s?|00\\s?)?[9٩۹][7٧۷][1١۱]${SEP}(?:\\(\\s?[0٠۰]\\s?\\)${SEP})?\\(?${D}\\)?(?:${SEP}${D}){7,8}${END_D}`, 'g');
export const PHONE_UAE_NATIONAL = new RegExp(`(?<![0-9٠-٩۰-۹+.,])\\(?[0٠۰]${D}{1,2}\\)?(?:${SEP}${D}){7,8}${END_D}`, 'g');
/** IBAN: AE and 21 digits, spaced in fours or not; any other country's IBAN after an IBAN label. */
export const IBAN = new RegExp(`\\b(?:${ci('iban')}\\s*[:#.]?\\s*)?(?:AE|ae)\\s?\\d{2}(?:\\s?\\d){19}\\b|\\b${ci('iban')}\\s*[:#.]?\\s*[A-Z]{2}\\d{2}(?:\\s?[A-Z0-9]){10,30}\\b`, 'g');
/** Bank account numbers after a label. */
export const ACCOUNT_NO = new RegExp(`\\b(?:${ci('a/c')}|${ci('account')}|${ci('acct')})\\.?\\s*(?:${ci('no')}\\.?|${ci('number')}|#)?\\s*[:#.]?\\s*${D}(?:[\\s\\-]?${D}){7,20}${END_D}`, 'g');
/** P.O. Box in English and Arabic (ص.ب), any digit script. */
export const PO_BOX = new RegExp(`\\b(?:[Pp]\\.?\\s?[Oo]\\.?\\s?${ci('box')}|${ci('pob')})\\s*[:#.]?\\s*${D}{3,7}${END_D}|ص\\s?\\.?\\s?ب\\s*\\.?\\s*[:：]?\\s*${D}{3,7}${END_D}|صندوق\\s+بريد\\s*[:：]?\\s*${D}{3,7}${END_D}`, 'g');
/** Licence numbers as UAE documents abbreviate them: "TL 273158", "CN-974461", "D.E.D. Licence 780159". */
export const LICENCE_SHORT = new RegExp(`\\b(?:CN|TL|DED|D\\.E\\.D\\.?)\\s*(?:${ci('licen')}[cs]e)?\\s*(?:${ci('no')}\\.?)?\\s*[\\-#:]?\\s*${D}{5,8}${END_D}|\\b${ci('licen')}[cs]e\\s+${D}{5,8}${END_D}`, 'g');
/** A firm named in Arabic: شركة / مؤسسة / مكتب and the words of its name (up to the end of the phrase). */
export const FIRM_AR = /(?:شركة|شركه|مؤسسة|مؤسسه|مكتب|مصنع)\s+(?:[؀-ۿ.]+\s*){1,7}/g;
/** A firm named in Latin letters: Title-Case words, then a firm suffix ("Al Waha Al Thahabi Trading", "... L.L.C."). */
export const FIRM_EN = /(?:\b(?:[A-Z][A-Za-z0-9&'-]*|[A-Z0-9]{2,})\s+){1,6}(?:Contracting|Trading|Technical\s+Services|Interiors|Engineering\s+Consultants|Consultants|Establishment|Est\.|L\.?L\.?C\.?|FZ-?LLC|FZE|FZCO)(?:\s+(?:L\.?L\.?C\.?|FZ-?LLC|FZE|FZCO|Est\.))?(?![A-Za-z])/g;
/** A street / building address: "Office 735, ZZ Palm IU8 Tower, Al Quoz Industrial Area 3, Dubai". */
export const ADDRESS = /\b(?:Office|Shop|Showroom|Warehouse|Suite|Flat|Unit)\s*(?:No\.?\s*)?\d{1,5}[A-Z]?\s*,?\s*(?:[^,;\n]{1,40},\s*){0,4}(?:Dubai|Sharjah|Abu\s+Dhabi|Ajman|Fujairah|Ras\s+Al\s+Khaimah|Umm\s+Al\s+Quwain|UAE)\b|\b(?:Al\s+)?[A-Z][a-z]+\s+Industrial\s+Area\s*\d*/g;
/** A person named after a label: "Prepared by: ZZ Omar Qasimi", "Regards, ...", "المسؤول: ...", "Eng. ...". */
const LABEL = [ci('prepared') + '\\s+' + ci('by'), ci('issued') + '\\s+' + ci('by'), ci('signed') + '\\s+' + ci('by'), ci('submitted') + '\\s+' + ci('by'), ci('arranged') + '\\s+' + ci('by'),
  // Weak labels ("from", "contact") only with their colon: "14 days from PO" names nobody.
  ci('contact') + '\\s+' + ci('person'), ci('contact') + ':', ci('attn') + '\\.?', ci('attention'), ci('regards'), ci('thanks'), ci('sincerely'), '[Ff]rom:',
  ci('sales') + '\\s+(?:' + ci('engineer') + '|' + ci('manager') + '|' + ci('executive') + ')', ci('project') + '\\s+' + ci('manager'),
  ci('on') + '\\s+' + ci('behalf') + '\\s+' + ci('of'), ci('in') + '\\s+' + ci('favou') + '?[Rr]\\s+' + ci('of'),
  '(?:Mr|Mrs|Ms|Eng|Engr|Dr)\\.', 'المسؤول', 'المهندس', 'السيد', 'السيدة', 'مقدم\\s+العرض', 'مع\\s+تحيات'].join('|');
export const PERSON_LABELLED = new RegExp(`(?:${LABEL})\\s*[:：,\\-]?\\s*(?:"?(?:(?:Mr|Mrs|Ms|Eng|Engr|Dr)\\.?\\s+)?(?:[A-Z][A-Za-z'.-]*(?![A-Za-z])[ \\t]*){1,6}|(?:[؀-ۿ]+[ \\t]*){1,4})`, 'g');

/** Named, so a residual scan can say which one it found. Order matters: registration numbers before phones. */
export const IDENTITY_TEXT_PATTERNS: [string, RegExp][] = [
  ['trn', TRN_LABELLED], ['trn_bare', TRN_BARE], ['licence_no', LICENCE_NO], ['licence_short', LICENCE_SHORT],
  ['iban', IBAN], ['account_no', ACCOUNT_NO], ['po_box', PO_BOX],
  ['phone_uae_intl', PHONE_UAE_INTL], ['phone_uae_national', PHONE_UAE_NATIONAL],
  ['address', ADDRESS], ['firm_ar', FIRM_AR], ['firm_en', FIRM_EN], ['person_labelled', PERSON_LABELLED],
];

/** Every identity shape above replaced by `rep` (a string, or a function of the match). */
export function scrubIdentityText(text: unknown, rep: string | ((m: string) => string) = ''): string {
  let t = String(text ?? '');
  for (const [, re] of IDENTITY_TEXT_PATTERNS) t = t.replace(re, typeof rep === 'string' ? () => rep : rep);
  return t;
}

// ── a KNOWN name (the supplier's own company, the buyer's own name) ─────────────────────────────────────
const CO_SUFFIX = '(?:l\\.?\\s?l\\.?\\s?c\\.?|fz-?llc|fzc|fze|fzco|trading|contracting|establishment|est\\.?|general|co\\.?|company|group)(?![A-Za-z])';
// Words that name a trade, not a firm: never matched on their own as part of a name fragment.
const GENERIC_WORDS = new Set(['zz', 'demo', 'al', 'the', 'and', 'of', 'technical', 'services', 'engineering', 'consultants', 'consultant', 'interiors', 'interior', 'contracting', 'trading',
  'general', 'company', 'group', 'llc', 'est', 'establishment', 'fze', 'fzco', 'co', 'electromechanical', 'electrical', 'mechanical', 'works', 'solutions', 'systems', 'supplies', 'supply']);
const rxEsc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
/** Latin or Arabic letter/digit: \b does not see Arabic, so word edges are written out. */
const W = '[A-Za-z0-9؀-ۿ]';
/**
 * A known name, matched with any separators and suffix, AND by any two consecutive distinctive words of it — a
 * supplier who calls a product line after the firm ("Oasis Golden UP8 series") names the firm. 3 Nov 2026: the old
 * companyRe stripped `co` with no word end, so "Consultants" became "nsultants" and "ZZ … Engineering Consultants
 * LLC" was never matched; and its `\b` never fired before an Arabic letter, so an Arabic name was never matched.
 */
export function knownNameRe(name: unknown): RegExp | null {
  const base = String(name || '').replace(new RegExp('(?<![A-Za-z])' + CO_SUFFIX, 'gi'), ' ').replace(/[^A-Za-z0-9؀-ۿ ]+/g, ' ').trim();
  const words = base.split(/\s+/).filter((w) => w.length > 1);
  if (!words.length || base.replace(/\s+/g, '').length < 3) return null;
  const sep = '[\\s.,_-]*';
  const alts = [words.map(rxEsc).join(sep) + `(?:${sep}${CO_SUFFIX})*`];
  const dist = words.map((w) => !GENERIC_WORDS.has(w.toLowerCase()));
  for (let i = 0; i + 1 < words.length; i++) if (dist[i] && dist[i + 1]) alts.push(rxEsc(words[i]) + sep + rxEsc(words[i + 1]));
  try { return new RegExp(`(?<!${W})(?:${alts.join('|')})(?!${W})`, 'gi'); } catch (_e) { return null; }
}
