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
//
// REVIEW OF #1838 (3 Nov 2026): the first version also destroyed legitimate text, and supplier_api scrubs AT SAVE, so
// that damage was permanent: "All building materials supplied" lost two words for a firm called "Dubai Building
// Materials Trading", "مكتب خشبي مقاس ١٢٠×٦٠" lost its size, "Project Manager Full Time On Site" lost its words,
// "03 120 4500 54000" (a BOQ row) and "UPVC pipe dia 050 075 110 160" were cut as phones. Every pattern below is now
// held to a MUST-KEEP list (identity_text.test.ts) as well as to the leaks it must catch.
import { LICENCE_NO, TRN_BARE, TRN_LABELLED } from './identity_numbers.ts';

const D = '[0-9٠-٩۰-۹]';
/** No digit, and no further digit GROUP, on either side: a phone is a whole number, never the middle of a BOQ row. */
const NO_GROUP_BEFORE = '(?<![0-9٠-٩۰-۹][\\s.\\-]?)(?<![0-9٠-٩۰-۹])';
const NO_GROUP_AFTER = '(?![\\s.\\-]?[0-9٠-٩۰-۹])';
const S1 = '[\\s.\\-\\u00a0]?';
const Z = '[0٠۰]';
/** A word in either case, for the labels (no (?i) modifier: these regexes are case-sensitive on purpose). */
const ci = (w: string) => w.replace(/[A-Za-z]/g, (c) => `[${c.toUpperCase()}${c.toLowerCase()}]`);

/** UAE numbers after +971 / 00971 / 971 and an optional (0): an area (2-9) or a mobile prefix (5X), then 7 digits. */
export const PHONE_UAE_INTL = new RegExp(`${NO_GROUP_BEFORE}(?:\\+\\s?|00\\s?)?[9٩۹][7٧۷][1١۱]${S1}(?:\\(\\s?${Z}\\s?\\)${S1})?(?:[5٥۵]${D}|[2-9٢-٩۲-۹])(?:${S1}${D}){7}${NO_GROUP_AFTER}`, 'g');
/**
 * National numbers in the groupings UAE documents print: 0X XXX XXXX, 0XXXXXXXX, (04) XXX XXXX, 05X XXX XXXX,
 * 05XXXXXXXX, (050) XXX XXXX, 05X.XXX.XXXX, 05 XXXX XXXX. Only real prefixes: landline 02/03/04/06/07/09, mobile
 * 050/052/054/055/056/058. A leading 0 followed by anything else ("01 25 450.00", "075 110 160") is not a phone.
 */
const LAND = '[2-4٢-٤۲-۴6-7٦-٧۶-۷9٩۹]', MOB = '[5٥۵][0٠۰2٢۲4٤۴5٥۵6٦۶8٨۸]';
export const PHONE_UAE_NATIONAL = new RegExp(`${NO_GROUP_BEFORE}(?:\\(${Z}(?:${MOB}|${LAND})\\)\\s?${D}{3}[\\s.\\-]?${D}{4}|${Z}(?:${MOB}|${LAND})[\\s.\\-]?${D}{3}[\\s.\\-]?${D}{4}|${Z}${MOB}${D}{7}|${Z}[5٥۵][\\s.\\-]${D}{4}[\\s.\\-]${D}{4})${NO_GROUP_AFTER}`, 'g');
/** IBAN: AE and 21 digits, spaced in fours or not; any other country's IBAN after an IBAN label. */
export const IBAN = new RegExp(`\\b(?:${ci('iban')}\\s*[:#.]?\\s*)?(?:AE|ae)\\s?\\d{2}(?:\\s?\\d){19}\\b|\\b${ci('iban')}\\s*[:#.]?\\s*[A-Z]{2}\\d{2}(?:\\s?[A-Z0-9]){10,30}\\b`, 'g');
/** Bank account numbers after a label. */
export const ACCOUNT_NO = new RegExp(`\\b(?:${ci('a/c')}|${ci('account')}|${ci('acct')})\\.?\\s*(?:${ci('no')}\\.?|${ci('number')}|#)?\\s*[:#.]?\\s*${D}(?:[\\s\\-]?${D}){7,20}(?!${D})`, 'g');
/** P.O. Box in English and Arabic (ص.ب), any digit script. */
export const PO_BOX = new RegExp(`\\b(?:[Pp]\\.?\\s?[Oo]\\.?\\s?${ci('box')}|${ci('pob')})\\s*[:#.]?\\s*${D}{3,7}(?!${D})|ص\\s?\\.?\\s?ب\\s*\\.?\\s*[:：]?\\s*${D}{3,7}(?!${D})|صندوق\\s+بريد\\s*[:：]?\\s*${D}{3,7}(?!${D})`, 'g');
/**
 * Licence numbers as UAE documents abbreviate them, never a bare product code: "CN-1234567" (the DED format, exactly
 * seven digits), "T.L. No. 273158" / "TL# 273158" / "DED No: 273158" (the abbreviation WITH its number marker),
 * "Licence 780159". "Inverter model TL-12000", "Product code CN-123456", "Dimmer DED 45000 series" are kept.
 */
export const LICENCE_SHORT = new RegExp(`\\bCN-${D}{7}(?!${D})|\\b(?:T\\.?L\\.?|DED|D\\.E\\.D\\.?)\\s*(?:${ci('licen')}[cs]e\\s*)?(?:${ci('no')}\\.?|#|:)\\s*[:#]?\\s*${D}{5,8}(?!${D})|\\b${ci('licen')}[cs]e\\s*(?:${ci('no')}\\.?|#|:)?\\s*(?:(?:CN|T\\.?L\\.?)[\\s\\-]?)?${D}{5,8}(?!${D})`, 'g');
/**
 * A firm named in Arabic: شركة / مؤسسة, its name, and what closes a firm's name — an activity (للمقاولات, للتجارة,
 * للخدمات الفنية …) or a legal form (ذ.م.م, ش.ذ.م.م, م.م.ح, ش.م.ع, ش.م.خ). Letters only, never a digit: "شركة التأمين
 * تتحمل التكاليف" and "مكتب خشبي مقاس ١٢٠×٦٠" are ordinary words (مكتب and مصنع are an office and a factory).
 */
const AW = '[\\u0621-\\u063A\\u0641-\\u064A\\u0671-\\u06D3]+';
const AR_LEGAL = '(?:ش\\.?\\s?ذ\\.?\\s?م\\.?\\s?م\\.?|ذ\\.?\\s?م\\.?\\s?م\\.?|م\\.?\\s?م\\.?\\s?ح\\.?|ش\\.?\\s?م\\.?\\s?[عخ]\\.?)';
export const FIRM_AR = new RegExp(`(?:شركة|شركه|مؤسسة|مؤسسه)\\s+(?:${AW}\\s+){0,5}?(?:لل${AW}(?:\\s+${AR_LEGAL}|\\s+${AW}(?:\\s+${AR_LEGAL})?)?|${AR_LEGAL})`, 'g');
/** A firm named in Latin letters: Title-Case words, then a firm suffix ("Al Waha Al Thahabi Trading", "... L.L.C."). */
export const FIRM_EN = /(?:\b(?:[A-Z][A-Za-z0-9&'-]*|[A-Z0-9]{2,})\s+){1,6}(?:Contracting|Trading|Technical\s+Services|Interiors|Engineering\s+Consultants|Consultants|Establishment|L\.?L\.?C\.?|FZ-?LLC|FZE|FZCO)(?:\s+(?:L\.?L\.?C\.?|FZ-?LLC|FZE|FZCO|Est\.))?(?![A-Za-z])/g;
/** Words that name a discipline, a part of a document or a scope, never a firm: a match made of them only is kept. */
const NOT_A_FIRM = new Set(['general', 'mep', 'hvac', 'civil', 'structural', 'mechanical', 'electrical', 'plumbing', 'fire', 'fighting', 'section', 'part', 'item', 'items', 'project',
  'approved', 'main', 'sub', 'specialist', 'design', 'interior', 'fit', 'out', 'fitout', 'works', 'work', 'scope', 'package', 'all', 'by', 'the', 'other', 'others', 'local', 'nominated',
  'landscape', 'architectural', 'facade', 'joinery', 'glazing', 'aluminium', 'steel', 'building', 'materials', 'supply', 'and', 'install', 'installation', 'note', 'notes']);
const firmOk = (m: string) => {
  const words = m.replace(/(?:Contracting|Trading|Technical\s+Services|Interiors|Engineering\s+Consultants|Consultants|Establishment|L\.?L\.?C\.?|FZ-?LLC|FZE|FZCO|Est\.)\s*/g, ' ').trim().split(/\s+/).filter(Boolean);
  return words.some((w) => !/^\d+$/.test(w) && !NOT_A_FIRM.has(w.toLowerCase()));
};
/** A street / building address: "Office 735, ZZ Palm IU8 Tower, Al Quoz Industrial Area 3, Dubai". */
export const ADDRESS = /\b(?:Office|Shop|Showroom|Warehouse|Suite|Flat)\s*(?:No\.?\s*)?\d{1,5}[A-Z]?\s*,\s*(?:[^,;\n]{1,40},\s*){0,4}(?:Dubai|Sharjah|Abu\s+Dhabi|Ajman|Fujairah|Ras\s+Al\s+Khaimah|Umm\s+Al\s+Quwain|UAE)\b|\bAl\s+[A-Z][a-z]+\s+Industrial\s+Area\s*\d*/g;
/**
 * A PERSON after a label. A label is "… by" (prepared / issued / signed / submitted / arranged by), a sign-off or
 * address line WITH its punctuation ("Regards,", "Thanks,", "Attn:", "Attention:", "Contact:", "Contact person:",
 * "From:"), a role WITH its colon ("Sales Engineer:", "Project Manager:"), or a title ("Mr.", "Eng.", "Dr."). The
 * name is 2-3 capitalised words (or initials) none of which is an ordinary word: "Regards, Supply Chain Team",
 * "Attention: Please note", "Mr. Client to provide", "From: Ground Floor To Roof" name nobody. Arabic: the label WITH
 * its colon (المسؤول: / المهندس: / السيد: / مقدم العرض:), then 2-4 words that are not roles.
 */
const LABEL_EN = [`(?:${ci('prepared')}|${ci('issued')}|${ci('signed')}|${ci('submitted')}|${ci('arranged')})\\s+${ci('by')}\\s*[:,]?`,
  `(?:${ci('regards')}|${ci('thanks')}|${ci('sincerely')})\\s*,`, `(?:${ci('attn')}\\.?|${ci('attention')}|${ci('contact')}(?:\\s+${ci('person')})?|[Ff]rom)\\s*:`,
  `(?:${ci('sales')}\\s+(?:${ci('engineer')}|${ci('manager')}|${ci('executive')})|${ci('project')}\\s+${ci('manager')})\\s*:`, '(?:Mr|Mrs|Ms|Eng|Engr|Dr)\\.'].join('|');
const NAME_TOKEN = "(?:[A-Z][a-z'-]+|[A-Z]{1,2}\\.?)";
export const PERSON_LABELLED = new RegExp(`(?:${LABEL_EN})\\s*${NAME_TOKEN}(?:\\s+${NAME_TOKEN}){1,2}(?![A-Za-z])|(?:المسؤول|المهندس|المهندسة|السيد|السيدة|مقدم\\s+العرض)\\s*[:：]\\s*${AW}(?:\\s+${AW}){1,3}`, 'g');
/** Capitalised words that are not names (a sign-off to a team, a place in a building, an instruction). */
const NOT_A_NAME = new Set(['supply', 'chain', 'team', 'department', 'dept', 'office', 'site', 'please', 'note', 'client', 'contractor', 'consultant', 'consultants', 'engineer', 'manager',
  'ground', 'floor', 'first', 'second', 'roof', 'level', 'to', 'the', 'all', 'our', 'your', 'main', 'sales', 'project', 'procurement', 'accounts', 'management', 'customer', 'service',
  'services', 'support', 'technical', 'estimation', 'tender', 'tendering', 'mep', 'hvac', 'civil', 'design', 'operations', 'quality', 'safety', 'store', 'stores', 'warehouse', 'admin',
  'المشرف', 'المقاول', 'الرئيسي', 'المشروع', 'التركيب', 'الموقع', 'عن', 'على', 'من', 'في', 'المسؤول', 'الاستشاري', 'العميل']);
const personOk = (m: string) => {
  const name = m.replace(new RegExp(`^(?:${LABEL_EN}|المسؤول|المهندس|المهندسة|السيد|السيدة|مقدم\\s+العرض)\\s*[:：]?\\s*`), '');
  return name.split(/\s+/).filter(Boolean).every((w) => !NOT_A_NAME.has(w.replace(/[.,]$/, '').toLowerCase()));
};

/** Named, so a residual scan can say which one it found. Order matters: registration numbers before phones. */
export const IDENTITY_TEXT_PATTERNS: [string, RegExp][] = [
  ['trn', TRN_LABELLED], ['trn_bare', TRN_BARE], ['licence_no', LICENCE_NO], ['licence_short', LICENCE_SHORT],
  ['iban', IBAN], ['account_no', ACCOUNT_NO], ['po_box', PO_BOX],
  ['phone_uae_intl', PHONE_UAE_INTL], ['phone_uae_national', PHONE_UAE_NATIONAL],
  ['address', ADDRESS], ['firm_ar', FIRM_AR], ['firm_en', FIRM_EN], ['person_labelled', PERSON_LABELLED],
];
/** A match a pattern makes that is NOT identity (its words are a discipline, a team, an instruction): kept. */
const KEEP_IF: Record<string, (m: string) => boolean> = { firm_en: (m) => !firmOk(m), person_labelled: (m) => !personOk(m) };
/** True when `name`'s match in `text` is identity (the validator agrees): what a residual scan should report. */
export function identityMatch(name: string, m: string): boolean { return !(KEEP_IF[name]?.(m)); }

/**
 * Every identity shape above replaced by `rep` (a string, or a function of the match). `parties: false` leaves firm
 * and person names alone — the quotation a customer has PAID to reveal names its supplier (review of #1838, item 1).
 */
export function scrubIdentityText(text: unknown, rep: string | ((m: string) => string) = '', opts: { parties?: boolean } = {}): string {
  let t = String(text ?? '');
  for (const [name, re] of IDENTITY_TEXT_PATTERNS) {
    if (opts.parties === false && (name === 'firm_ar' || name === 'firm_en' || name === 'person_labelled')) continue;
    t = t.replace(re, (m: string) => (KEEP_IF[name]?.(m) ? m : typeof rep === 'string' ? rep : rep(m)));
  }
  return t;
}

// ── a KNOWN name (the supplier's own company, the buyer's own name, a project's name) ───────────────────────
const CO_SUFFIX = '(?:l\\.?\\s?l\\.?\\s?c\\.?|fz-?llc|fzc|fze|fzco|trading|contracting|establishment|est\\.?|general|co\\.?|company|group)(?![A-Za-z])';
const rxEsc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
/** Latin or Arabic letter/digit: \b does not see Arabic, so word edges are written out. */
const W = '[A-Za-z0-9؀-ۿ]';
/**
 * A known name, matched whole with any separators and suffix. With `fragments` (only for a party's OWN text, never
 * for other suppliers' quotes), also by two consecutive words of it when one of them carries a DIGIT — a code no
 * trade wording has ("Oasis Golden UP8 series"). Review of #1838, item 2: fragments of ordinary words ("Building
 * Materials", "Ready Mix", "Air Conditioning", "Fire Safety") stripped 8 of 10 trade-named firms' own scope.
 * 3 Nov 2026: the old companyRe stripped `co` with no word end, so "Consultants" became "nsultants" and "ZZ …
 * Engineering Consultants LLC" was never matched; and its `\b` never fired before an Arabic letter.
 */
export function knownNameRe(name: unknown, opts: { fragments?: boolean } = {}): RegExp | null {
  const base = String(name || '').replace(new RegExp('(?<![A-Za-z])' + CO_SUFFIX, 'gi'), ' ').replace(/[^A-Za-z0-9؀-ۿ ]+/g, ' ').trim();
  const words = base.split(/\s+/).filter((w) => w.length > 1);
  if (!words.length || base.replace(/\s+/g, '').length < 3) return null;
  const sep = '[\\s.,_-]*';
  const alts = [words.map(rxEsc).join(sep) + `(?:${sep}${CO_SUFFIX})*`];
  if (opts.fragments) for (let i = 0; i + 1 < words.length; i++) if (/\d/.test(words[i]) || /\d/.test(words[i + 1])) alts.push(rxEsc(words[i]) + sep + rxEsc(words[i + 1]));
  try { return new RegExp(`(?<!${W})(?:${alts.join('|')})(?!${W})`, 'gi'); } catch (_e) { return null; }
}
