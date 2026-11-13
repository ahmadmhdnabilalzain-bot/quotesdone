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
import { capBlanks, placeSpans, reducePlaces } from './identity_places.ts';
// ONE source of places for text and drawings (coordinator, 13 Nov 2026): the sibling branches import these from here.
export { placeSpans, reducePlaces, reducibleSeed } from './identity_places.ts';
/** The texts of every place below the emirate found in `text` (a thin wrapper over placeSpans, for the drawings gate). */
export function locationBelowEmirate(text: string, opts: { drawing?: boolean } = {}): string[] { const t = String(text ?? ''); return placeSpans(t, opts).map((s) => t.slice(s.s, s.e)); }

const D = '[0-9٠-٩۰-۹]';
/** Separators a printed phone uses: space, dot, hyphen, no-break space, the Unicode dashes (en / em "050–123–4567"). */
const SEPC = '\\s.\\-\\u00a0\\u2010-\\u2015';
/**
 * A separator INSIDE a number, which a tab never is. FINAL REVIEW of the combined release, 13 Nov 2026 (item 3): a tab is a
 * cell boundary of a pasted table. It ends a number ("Sales contact<tab>050 123 4567<tab>12,500.00" kept the phone, because the
 * price in the next cell read as the number's next group) and it never joins one ("03<tab>120<tab>4500<tab>54000", an item
 * number, a quantity, a rate and an amount, read as the landline 03 120 4500 once a tab could end it).
 */
const SEP_IN = `(?:(?!\\t)[${SEPC}])`;
/** No digit, and no further digit GROUP, before: a phone is a whole number, never the middle of a BOQ row. */
const NO_GROUP_BEFORE = `(?<![0-9٠-٩۰-۹]${SEP_IN}?)(?<![0-9٠-٩۰-۹])`;
/**
 * After: no digit, and no further group of THREE or more digits unless it starts with 0 (the next phone of a collapsed
 * letterhead, "Tel 04 345 6789 050 123 4567"), and no decimal. Adversarial review of #1838: the old guard refused ANY
 * digit after a space, so "Call 050 123 4567 9am to 6pm" and "Mob: 050 123 4567 24/7" kept the whole number. "03 120 4500
 * 54000" (a BOQ row) is still refused by its 54000.
 */
const NO_GROUP_AFTER = `(?!${D})(?:(?=\\t)|(?![${SEPC}]{1,2}(?![0٠۰])${D}{3})(?![${SEPC}]?${D}{1,2}[.,]${D}))`;
/** One or two separator characters ("050  123  4567" has two spaces). */
const S1 = `${SEP_IN}{0,2}`;
const Z = '[0٠۰]';
/** A word in either case, for the labels (no (?i) modifier: these regexes are case-sensitive on purpose). */
const ci = (w: string) => w.replace(/[A-Za-z]/g, (c) => `[${c.toUpperCase()}${c.toLowerCase()}]`);

/** A code word before a number makes it a product code, not a licence or a phone ("Model 0501 2345 67", "Product code CN-123456"). */
const CODE_WORD = `(?:${ci('code')}|${ci('model')}|${ci('part')}|${ci('ref')}|${ci('item')}|${ci('cat')}|${ci('catalogue')}|${ci('catalog')}|${ci('sku')}|${ci('art')}|${ci('article')}|${ci('product')}|${ci('type')}|${ci('series')})`;
// Bounded (second review of 13 Nov 2026): with \s* this look-behind re-read every space before each position, and a run
// of 1,000 spaces took 1.9 s in PHONE_UAE_INTL alone (2,000 spaces: more than 60 s through scrubIdentityText).
const NOT_A_CODE = `(?<!${CODE_WORD}\\.?[ \\t]{0,3}(?:${ci('no')}\\.?[ \\t]{0,3})?[:#]?[ \\t]{0,3})`;
/**
 * UAE numbers after +971 / 00971 / 971 — the code in brackets too, "(+971)" — and an optional (0): an area (2-9) or a
 * mobile prefix (5X), then 7 digits. Second review of #1838: "Tel (+971) 50 123 4567" passed every scrubber.
 */
export const PHONE_UAE_INTL = new RegExp(`${NOT_A_CODE}${NO_GROUP_BEFORE}(?:\\(\\s?)?(?:\\+\\s?|00\\s?)?[9٩۹][7٧۷][1١۱](?:\\s?\\))?${S1}(?:\\(\\s?${Z}\\s?\\)${S1})?(?:[5٥۵]${D}|[2-9٢-٩۲-۹])(?:${S1}${D}){7}${NO_GROUP_AFTER}`, 'g');
/**
 * National numbers in the groupings UAE documents print: 0X XXX XXXX, 0XXXXXXXX, (04) XXX XXXX, 05X XXX XXXX,
 * 05XXXXXXXX, (050) XXX XXXX, 05X.XXX.XXXX, 05 XXXX XXXX. Only real prefixes: landline 02/03/04/06/07/09, mobile
 * 050/052/054/055/056/058. A leading 0 followed by anything else ("01 25 450.00", "075 110 160") is not a phone.
 * Second review of #1838: a 05X mobile in ANY layout — one space or dash between any two of its ten digits ("050 12 34
 * 567", "0 5 0 1 2 3 4 5 6 7"), or one slash straight after its prefix ("050/1234567"). Never a slash anywhere else
 * (adversarial review: "05/03/2026 09:00" and "DN 050/065/080" read as phones) and never a dot ("05.06.2026 12" is a
 * date). "UPVC pipe dia 050 075 110 160" — 050 and then eleven more digits — is not a phone.
 */
const LAND = '[2-4٢-٤۲-۴6-7٦-٧۶-۷9٩۹]', MOB = '[5٥۵][0٠۰2٢۲4٤۴5٥۵6٦۶8٨۸]';
const SP = '[\\s\\-\\u2010-\\u2015]';
const MOB_ANY = `${Z}${SP}?[5٥۵]${SP}?[0٠۰2٢۲4٤۴5٥۵6٦۶8٨۸](?:\\/|${SP})?(?:${SP}?${D}){7}`;
const NOT_A_DATE = `(?!${Z}?[0-9٠-٩][\\-\\/.][0-3٠-٣]?[0-9٠-٩][\\-\\/.](?:19|20|١٩|٢٠)${D}{2})`;
export const PHONE_UAE_NATIONAL = new RegExp(`${NOT_A_CODE}${NO_GROUP_BEFORE}${NOT_A_DATE}(?:\\(${Z}(?:${MOB}|${LAND})\\)${S1}${D}{3}${S1}${D}{4}|${Z}(?:${MOB}|${LAND})${S1}${D}{3}${S1}${D}{4}|${Z}${MOB}${D}{7}|${Z}[5٥۵]${SEP_IN}{1,2}${D}{4}${SEP_IN}{1,2}${D}{4}|${MOB_ANY})${NO_GROUP_AFTER}`, 'g');
/** UAE toll-free / shared-cost numbers (800 …, 600 …) — only after a word that says it is a number to call. */
export const PHONE_UAE_SHORT = new RegExp(`(?<=(?:${ci('toll')}[\\s\\-]*${ci('free')}|${ci('call')}|${ci('tel')}|${ci('phone')}|${ci('hotline')}|${ci('contact')}|${ci('mob')}|رقم|اتصل|هاتف)[^0-9٠-٩\\n]{0,12})(?:800|600|٨٠٠|٦٠٠)[\\s\\-]?${D}{2,3}[\\s\\-]?${D}{2,4}(?!${D})`, 'g');
/** Any other country's number written with its + or 00 code ("+966 50 123 4567", "00966501234567", "+91 98765 43210"). */
export const PHONE_INTL = new RegExp(`(?<![\\w+])(?:\\+\\s?|00)(?![9٩][7٧][1١])[1-9١-٩]${D}{0,2}(?:${SEP_IN}?${D}){7,12}(?!${D})`, 'g');
/** IBAN: AE and 21 digits in any digit script, spaced or dashed or not; any other country's after a label. */
export const IBAN = new RegExp(`\\b(?:${ci('iban')}\\s*[:#.]?\\s*)?(?:AE|ae)[\\s\\-]?${D}{2}(?:[\\s\\-]?${D}){19}(?![0-9٠-٩۰-۹A-Za-z])|\\b${ci('iban')}\\s*[:#.]?\\s*[A-Z]{2}${D}{2}(?:[\\s\\-]?[A-Z0-9٠-٩۰-۹]){10,30}(?![0-9٠-٩۰-۹A-Za-z])`, 'g');
/** Bank account numbers after a label, English ("A/C", "Account", "Acct", "Acc No.") and Arabic (رقم الحساب, حساب رقم). */
export const ACCOUNT_NO = new RegExp(`(?:\\b(?:${ci('a/c')}|${ci('account')}|${ci('acct')}|${ci('acc')})\\.?\\s*(?:${ci('no')}\\.?|${ci('number')}|#)?|رقم\\s*(?:ال)?حساب|(?:ال)?حساب\\s*رقم)\\s*[:#.：]?\\s*${D}(?:[\\s\\-]?${D}){7,20}(?!${D})`, 'g');
/**
 * A UAE emirate as an address ends: what makes "Box 12345, Dubai" an address and "Box 12 nos" a count.
 */
const EMIRATE_EN = '(?:Dubai|Sharjah|Abu\\s+Dhabi|Ajman|Fujairah|Ras\\s+Al\\s+Khaimah|Umm\\s+Al\\s+Quwain|Al\\s+Ain|UAE|DUBAI|SHARJAH|ABU\\s+DHABI|AJMAN)';
/**
 * P.O. Box in English ("P.O. Box", "P.O. Box No.", "POB", "Post Box", "Post Office Box", "P.B.", and "PB" / "Box" with an
 * emirate after them) and Arabic (ص.ب, ص.ب. رقم, صندوق بريد, صندوق البريد), any digit script. "PB" alone is a push
 * button and "Box 12" a count, so those need the emirate.
 */
export const PO_BOX = new RegExp(`\\b(?:[Pp]\\.?\\s?[Oo]\\.?\\s?${ci('box')}|${ci('pob')}|${ci('post')}\\s+(?:${ci('office')}\\s+)?${ci('box')}|P\\.B\\.)\\s*(?:${ci('no')}\\.?|#)?\\s*[:#.]?\\s*${D}{3,7}(?!${D})`
  + `|\\b(?:PB|${ci('box')})\\s*${D}{4,6}(?=\\s*,?\\s*${EMIRATE_EN})`
  + `|ص\\s?\\.\\s?ب\\s*\\.?\\s*(?:رقم\\s*)?[:：]?\\s*${D}{3,7}(?!${D})|ص\\s?ب\\s*(?:رقم\\s*)?[:：]?\\s*${D}{4,7}(?!${D})|صندوق\\s+(?:ال)?بريد\\s*(?:رقم\\s*)?[:：]?\\s*${D}{3,7}(?!${D})`, 'g');
/**
 * Licence numbers as UAE documents abbreviate them. "CN-974461", "CN 1234567", "CN1234567": the DED format, six to eight
 * digits — SECOND review of #1838: the first loosening kept six-digit CN numbers because a product code can be
 * "CN-123456", and that reopened the leak this file's header measured ("CN-974461"). "TL 273158", "TL-273158", "DED
 * 1234567": six or seven digits. A product code is told apart by what comes BEFORE it (code / model / part / ref / item
 * / cat / catalogue / SKU / article / product / type / series), never by its digit count. With a number marker: "T.L.
 * No. 273158" / "TL# 273158" / "DED No: 273158" / "Lic. No. 1234567" / "licence No. 780159"; after a qualifier: "Trade
 * licence 780159" / "D.E.D. Licence 780159". A bare "licence" and a number is a price as often as a licence: "BMS
 * software licence 12500.00" and "Annual licence 15000 per year" are kept, and no licence number runs on into ".00".
 * "Inverter model TL-12000" and "Dimmer DED 45000 series" (five digits, or a code word before) are kept.
 */
const LIC_END = `(?![.,]?${D})`;
const LIC_QUAL = `(?:${ci('trade')}|${ci('commercial')}|${ci('business')}|${ci('industrial')}|${ci('professional')}|DED|D\\.E\\.D\\.?)\\s*`;
export const LICENCE_SHORT = new RegExp(`${NOT_A_CODE}\\bCN[\\s\\-]?${D}{6,8}(?!${D})|${NOT_A_CODE}\\b(?:TL|DED)[\\s\\-#:]*${D}{6,7}(?!${D})`
  + `|\\b(?:T\\.?L\\.?|DED|D\\.E\\.D\\.?|${ci('lic')}\\.?)\\s*(?:${ci('licen')}[cs]e\\s*)?(?:${ci('no')}\\.?|#|:)\\s*[:#]?\\s*${D}{5,8}${LIC_END}`
  + `|(?:\\b${LIC_QUAL}${ci('licen')}[cs]e\\s*(?:${ci('no')}\\.?|#|:)?|\\b${ci('licen')}[cs]e\\s*(?:${ci('no')}\\.?|#|:))\\s*(?:(?:CN|T\\.?L\\.?)[\\s\\-]?)?${D}{5,8}${LIC_END}`, 'g');
/**
 * A firm named in Arabic. Five shapes (second review of #1838 and its adversarial re-review, each measured passing
 * before):
 *   1. شركة / مؤسسة, its name, and what closes a firm's name — an activity (للمقاولات, للتجارة, للخدمات الفنية …) or a
 *      legal form (ذ.م.م, ش.ذ.م.م, م.م.ح, ش.م.ع, ش.م.خ). مكتب / مصنع / ورشة too, but only before an ACTIVITY from the
 *      closed list ("مكتب النور للاستشارات الهندسية"): "مكتب الموقع للمهندس المشرف" is the site office.
 *   2. A legal form is identity ON ITS OWN, with no شركة: "النور للمقاولات ذ.م.م", and digits are part of a name that
 *      ends in one ("شركة النور ٢٠٠٠ للمقاولات ذ.م.م"); a Latin legal form closes it as well ("النور للمقاولات LLC").
 *   3. شركة / مؤسسة and a proper noun (ال + word) with no activity: "شركة النور الذهبية", "مؤسسة النور"; or a plain word
 *      and an ال-word ("مؤسسة نور الهدى"). Not when the noun is a trade or a service: "شركة التأمين تتحمل التكاليف",
 *      "شركة المصاعد", "شركة الغاز", "شركة تأمين الموقع" are whoever does that job.
 *   4. A name and an activity from the closed list with no firm word: "النور للمقاولات العامة", "أحمد المنصوري
 *      للمقاولات". Not after a document noun: "تم تسليم المخطط للمقاولات العامة".
 * Never after an adjective that says WHAT KIND of firm, not WHICH ("عن طريق شركة معتمدة للصيانة", "شركة واحدة للضمان",
 * "شركة فحص للمعدات"). Never "الشركة": "الشركة المصنعة" is the manufacturer. "مكتب خشبي مقاس ١٢٠×٦٠" is an office desk.
 * Not "مجموعة": "مجموعة المضخات" is a pump set, and a firm called "مجموعة النور" is the one shape left to its own name.
 */
const AL_ = '[\\u0621-\\u063A\\u0641-\\u064A\\u0671-\\u06D3]';
const AW = `${AL_}+`;
const AR_END = `(?!${AL_})`;
const AR_START = `(?<!${AL_})`;
// Its letters always apart (a dot or a space between): written together, ذمم is a word (receivables, "ذمم دائنة").
const AR_LEGAL = `(?:ش[.\\s]\\s?ذ[.\\s]\\s?م[.\\s]\\s?م\\.?|ذ[.\\s]\\s?م[.\\s]\\s?م\\.?|م[.\\s]\\s?م[.\\s]\\s?ح\\.?|ش[.\\s]\\s?م[.\\s]\\s?[عخ]\\.?)${'(?![\\u0621-\\u064A])'}`;
const LATIN_LEGAL = '(?:L\\.?L\\.?C\\.?|FZ-?LLC|FZE|FZCO|FZC|W\\.?L\\.?L\\.?|DMCC)(?![A-Za-z])';
const FIRM_WORD = '(?:شركة|شركه|مؤسسة|مؤسسه)';
const AR_ACT = `(?:للمقاولات|للمقاولات|للتجارة|للتجاره|للخدمات|للاستشارات|للديكور|للتكييف|للألمنيوم|للالمنيوم|للزجاج|للحدادة|للنجارة|للكهرباء|للأعمال|للاعمال|للهندسة|للإنشاءات|للانشاءات|للتعهدات|للتوريدات|للمواد|للتطوير|للعقارات)${AR_END}(?:\\s+(?:العامة|العامه|الفنية|الفنيه|الهندسية|الهندسيه|الكهربائية|الميكانيكية|الكهروميكانيكية)${AR_END})?`;
const AR_KIND_ADJ = `(?:معتمد[ةه]?|متخصص[ةه]?|مختص[ةه]?|مرخص[ةه]?|مؤهل[ةه]?|محلي[ةه]?|أجنبي[ةه]?|اجنبي[ةه]?|وطني[ةه]?|عالمي[ةه]?|أخرى|اخرى|كبرى|رائد[ةه]?|مسجل[ةه]?|واحد[ةه]?|صغير[ةه]?|كبير[ةه]?|جديد[ةه]?|قديم[ةه]?|مناسب[ةه]?)${AR_END}`;
/** A trade or service named without ال after شركة: "شركة فحص للمعدات", "شركة تأمين الموقع" are whoever does it. */
const AR_TRADE_BARE = `(?:تأمين|تامين|فحص|صيانة|صيانه|تنظيف|حراسة|أمن|امن|بناء|تكييف|تبريد|عزل|مصاعد|غاز|شحن|نقل|توريد|خدمات|مقاولات|استشارات|كهرباء|اتصالات|طلاء|دهانات|تركيب|إنشاءات|انشاءات|هندسة)${AR_END}`;
const AR_GENERIC = `(?:التأمين|التامين|الشحن|النقل|الصيانة|الصيانه|المقاولات|الكهرباء|المياه|الاتصالات|الطيران|التوريد|المصنعة|المصنعه|المنفذة|المنفذه|الموردة|المورده|المذكورة|المذكوره|المعنية|المعنيه|المختصة|المعتمدة|المتخصصة|القابضة|الأم|الام|المالكة|الاستشارية|الهندسية|العقارية|التطوير|المقاول|المورد|الحكومية|الخاصة|المصاعد|الغاز|الحراسة|الأمن|الامن|التنظيف|النظافة|البناء|التبريد|التكييف|العزل|الفحص|الإنشاءات|الانشاءات|الطلاء|الدهانات|الاستشارات|البلدية|الهاتف|الإنترنت|الانترنت|التركيب)${AR_END}`;
/** Nouns of a document or a job, never the start of a firm's name ("تسليم المخطط للمقاولات"). */
const AR_COMMON = `(?:المخطط|المخططات|الموقع|المشروع|الأعمال|الاعمال|العقد|العرض|الطلب|الملف|المستندات|الوثائق|المواد|التصميم|الرسومات|الجدول|الكميات|الأسعار|الاسعار|العينات|الطلبات|المناقصة|التسليم|المهندس|المقاول|العميل|الاستشاري|الكهرباء)${AR_END}`;
// The word for "by" is written as escapes: the Arabic register check reads it as the passive calque it forbids in copy.
const AR_PREP = `(?:من|قبل|عن|طريق|\\u0628\\u0648\\u0627\\u0633\\u0637\\u0629|في|إلى|الى|على|مع|و|تم|يتم|سيتم|لدى|عند|وفق|حسب|لصالح|باسم|او|أو|تسليم|تقديم)${AR_END}`;
const AR_NAME_PART = `(?:${FIRM_WORD}|ال${AW}|لل${AW}|${D}+|بن|ابن|أبو|ابو)`;
export const FIRM_AR = new RegExp(`${AR_START}[وبل]?${FIRM_WORD}\\s+(?!${AR_KIND_ADJ}|${AR_TRADE_BARE})(?:${AW}\\s+){0,5}?(?:لل${AW}(?:\\s+${AR_LEGAL}|\\s+${AW}(?:\\s+${AR_LEGAL})?)?|${AR_LEGAL})`
  + `|${AR_START}[وبل]?(?:مكتب|مصنع|ورشة|ورشه)\\s+(?:${AW}\\s+){1,3}?${AR_ACT}`
  + `|${AR_START}(?:(?!${AR_PREP})${AW}\\s+)?(?:${AR_NAME_PART}\\s+){1,5}(?:${AR_LEGAL}|${LATIN_LEGAL})`
  + `|${AR_START}[وبل]?${FIRM_WORD}\\s+(?!${AR_GENERIC}|${AR_KIND_ADJ})ال${AW}(?:\\s+(?!${AR_GENERIC})ال${AW}){0,2}`
  + `|${AR_START}[وبل]?${FIRM_WORD}\\s+(?!${AR_KIND_ADJ}|${AR_TRADE_BARE}|${AR_PREP}|ال)${AW}\\s+(?!${AR_GENERIC})ال${AW}`
  + `|${AR_START}(?:(?!${AR_PREP}|${AR_COMMON})${AW}\\s+)?(?!${AR_COMMON}|${AR_GENERIC})ال${AW}\\s+${AR_ACT}`, 'g');
/**
 * A firm named in Latin letters: capitalised (or ALL-CAPS) words, then a firm word. Three strengths (second review of
 * #1838 and its adversarial re-review):
 *   * a LEGAL form names a firm on its own: "Gulf Pipes FZC / W.L.L. / DMCC / PJSC", "Dubai Building Materials Trading
 *     LLC", "AL NOOR CONTRACTING CO.", "Al Noor Trdg. LLC"; in any case when it is a registered form ("al noor trading
 *     llc", "Al Noor trading LLC", as typed on WhatsApp);
 *   * "Contracting" / "Trading" name a firm after Al / El / ZZ, a particle (bin, abu …) or a coded word, or after a payee
 *     cue ("payable to", "M/s", "in favour of"): "Al Waha Al Thahabi Trading", "Saif bin Darwish Contracting";
 *     "Scope: Waterproofing Contracting for roof" and "Kitchen Equipment Trading terms apply" are scope;
 *   * "Consultants", "Interiors", "Establishment", "Est.", "Technical Services", "Group", "Industries", "Works",
 *     "General Maintenance" name a firm only after Al / El / ZZ, a particle or a coded word: "Al Noor Group", "Al Noor
 *     Est"; "Site Establishment and Mobilisation", "Testing & Commissioning Technical Services", "Kitchen Interiors
 *     package", "Project Duration Est. 6 Weeks" are scope.
 * The suffix is Title-Case or ALL-CAPS outside a registered form ("Our trading terms apply"). Leading words of scope or
 * of a sentence are trimmed off a match ("Supply Al Noor Trading" loses "Al Noor Trading" only).
 */
const tc = (w: string) => `(?:${w}|${w.toUpperCase()})`;
const EN_LEGAL = '(?:L\\.?L\\.?C\\.?|FZ-?LLC|FZE|FZCO|FZC|W\\.?L\\.?L\\.?|DMCC|P\\.?J\\.?S\\.?C\\.?|SPC|Est\\.|EST\\.|Co\\.|CO\\.?|Ltd\\.?|LTD\\.?)';
const EN_LEGAL_BARE = '(?:L\\.?L\\.?C\\.?|FZ-?LLC|FZE|FZCO|FZC|W\\.?L\\.?L\\.?|DMCC|P\\.?J\\.?S\\.?C\\.?|SPC)';
const EN_LEGAL_CI = '(?:[Ll]\\.?[Ll]\\.?[Cc]\\.?|[Ff][Zz]-?[Ll][Ll][Cc]|[Ff][Zz][Ee]|[Ff][Zz][Cc][Oo]|[Ff][Zz][Cc]|[Ww]\\.?[Ll]\\.?[Ll]\\.?|[Dd][Mm][Cc][Cc])';
const EN_STRONG = `(?:${tc('Contracting')}|${tc('Trading')}|Trdg\\.?|TRDG\\.?|Cont\\.|CONT\\.)`;
const EN_WEAK = `(?:${tc('Engineering')}\\s+${tc('Consultants')}|${tc('Consultants')}|${tc('Consultancy')}|${tc('Interiors')}|${tc('Establishment')}|Est\\.?|EST\\.?|${tc('Technical')}\\s+${tc('Services')}|${tc('Group')}|${tc('Industries')}|(?:${tc('Technical')}\\s+|${tc('Electromechanical')}\\s+)?${tc('Works')}|${tc('General')}\\s+${tc('Maintenance')})`;
const EN_PARTICLE = '(?:al|el|bin|bint|ibn|abu|bu)';
// Tokens bounded to 40 characters: 50 KB of "Al-Al-Al-…" is one token, and each start position re-read it (3.2 s).
const EN_TOKEN = `(?:[A-Z][a-z]{1,4}\\.(?=\\s)|[A-Z][A-Za-z0-9&'-]{0,40}(?![A-Za-z0-9&'-])|[A-Z0-9]{2,}|&|${EN_PARTICLE}(?=\\s))`;
export const FIRM_EN = new RegExp(`(?:(?<![A-Za-z0-9&])${EN_TOKEN}\\s+){1,6}(?:${EN_STRONG}(?:\\s+${EN_LEGAL})*|${EN_WEAK}(?:\\s+${EN_LEGAL})*|${EN_LEGAL_BARE})(?![A-Za-z])`
  + `|(?:(?<![A-Za-z0-9&])[A-Za-z][A-Za-z0-9&'-]{0,40}(?![A-Za-z0-9&'-])\\s+){1,5}${EN_LEGAL_CI}(?![A-Za-z])`, 'g');
/** Words that name a discipline, a part of a document or a scope, never a firm: a match made of them only is kept. */
const NOT_A_FIRM = new Set(['general', 'mep', 'hvac', 'civil', 'structural', 'mechanical', 'electrical', 'plumbing', 'fire', 'fighting', 'section', 'part', 'item', 'items', 'project',
  'approved', 'main', 'sub', 'specialist', 'design', 'interior', 'fit', 'out', 'fitout', 'works', 'work', 'scope', 'package', 'all', 'by', 'the', 'other', 'others', 'local', 'nominated',
  'landscape', 'architectural', 'facade', 'joinery', 'glazing', 'aluminium', 'steel', 'building', 'materials', 'supply', 'and', 'install', 'installation', 'note', 'notes', '&']);
/** Leading words of a sentence that are never part of a firm's name (trimmed off the front of a match). */
const NOT_A_FIRM_START = new Set([...NOT_A_FIRM, 'we', 'i', 'you', 'they', 'buy', 'bought', 'from', 'to', 'a', 'an', 'of', 'for', 'our', 'your', 'is', 'are', 'was', 'with', 'at', 'in',
  'on', 'or', 'via', 'through', 'supplied', 'purchase', 'purchased', 'order', 'ordered', 'contact', 'call', 'please', 'ask', 'send', 'pay', 'payable', 'cheque', 'transfer', 'name', 'company',
  'firm', 'visit', 'meet', 'invoice', 'quotation', 'quote', 'scope', 'm/s', 'm/s.']);
/** Words that introduce a firm's name and are never inside it: the name starts after the last of them. */
const CUT_BEFORE_FIRM = new Set(['by', 'from', 'to', 'of', 'for', 'with', 'at', 'in', 'on', 'via', 'through', 'is', 'are', 'was', 'were', 'warranty', 'guarantee', 'guaranteed', 'supplied',
  'provided', 'installed', 'manufactured', 'made', 'issued', 'offered', 'quoted', 'contact', 'call', 'payable', 'favour', 'favor', 'transfer', 'cheque', 'cheques', 'beneficiary']);
// 13 Nov 2026 (anonymity audit REPORT_A L4): "I already have a quote from Falcon Trading for AED 32,816" named the
// customer's current supplier to every matched supplier; a quotation, an offer or a purchase FROM a "… Trading" names a firm.
const PAYEE_CUE = /(?:payable\s+to|in\s+(?:the\s+)?favou?r\s+of|m\/s\.?|beneficiary\s*:?|account\s+name\s*:?|cheques?\s+(?:to|in\s+the\s+name\s+of)|transfer\s+to|(?:quot(?:e|ation|ed)|offer|proposal|price|prices|invoice|bill|estimate)\s+(?:from|by)|(?:supplier|contractor|vendor|subcontractor|company|firm)\s+(?:is|was|called|named)|(?:bought|purchased|ordered|got)\s+(?:it\s+)?from|(?:supplied|installed|done)\s+by)\s*$/i;
const EN_SUFFIX_RE = new RegExp(`(?:${EN_STRONG}|${EN_WEAK}|${EN_LEGAL}|${EN_LEGAL_CI})(?:\\s+${EN_LEGAL})*$`);
const isCue = (w: string) => new RegExp(`^(?:${EN_PARTICLE}|zz)$`, 'i').test(w) || (/\d/.test(w) && /[A-Za-z]/.test(w));
const firmSpan = (m: string, at: number, text: string): [number, number] | null => {
  const suffix = m.match(EN_SUFFIX_RE)?.[0] ?? '';
  // Trim the front: words of a sentence or of scope never start a firm's name ("Supply Al Noor Trading").
  let s = 0;
  const lead = [...m.slice(0, m.length - suffix.length).matchAll(/\S+/g)];
  for (const w of lead) { if (NOT_A_FIRM_START.has(w[0].toLowerCase()) || /^\d+$/.test(w[0])) s = w.index! + w[0].length; else break; }
  // 13 Nov 2026 (anonymity audit, REPORT_C L4): "5 years warranty by Falcon Trading LLC" was saved as "5 █ on
  // workmanship" — the lower-case form of this pattern took "years warranty by" as the firm's first words, and the checker
  // then printed the manufacturer's 10 years on the customer's cover. A firm's name starts AFTER the last word that
  // introduces it (by / from / to / of / for / with …), and a lower-case word before a Title-Case name is never part of it.
  for (const w of lead) if (w.index! >= s && CUT_BEFORE_FIRM.has(w[0].toLowerCase())) s = w.index! + w[0].length;
  if (/[A-Z]/.test(m.slice(s))) for (const w of lead) { if (w.index! < s) continue; if (/^[a-z]/.test(w[0]) && !new RegExp(`^${EN_PARTICLE}$`).test(w[0])) s = w.index! + w[0].length; else break; }
  while (/\s/.test(m[s] ?? '')) s++;
  const words = m.slice(s, m.length - suffix.length).trim().split(/\s+/).filter(Boolean);
  if (!words.some((w) => !/^\d+$/.test(w) && !NOT_A_FIRM.has(w.toLowerCase()) && !new RegExp(`^${EN_PARTICLE}$`, 'i').test(w))) return null;
  const legal = new RegExp(`(?:${EN_LEGAL_BARE}|${EN_LEGAL_CI})$`).test(m);
  const cue = words.some(isCue);
  if (!legal) {
    const strong = new RegExp(`${EN_STRONG}$`).test(m);
    if (!cue && !(strong && PAYEE_CUE.test(text.slice(Math.max(0, at + s - 40), at + s)))) return null;
  }
  return [s, m.length];
};
/**
 * A street / building address: "Office 735, ZZ Palm IU8 Tower, Al Quoz Industrial Area 3, Dubai", "Building 5, Al
 * Quoz, Dubai", "Villa 23, Street 14, Jumeirah 1, Dubai", "Shop # 5, Al Quoz, Dubai", "Office 12 - Al Garhoud - Dubai"
 * (a premises word, its number, a comma or a dash, up to four parts, an emirate), and the Arabic "مكتب ١٢، برج الخليج،
 * دبي" / "مكتب رقم ١٢ - بناية النور - الشارقة". "Unit 12, Block B, Dubai" is a part of a project, kept.
 */
const EMIRATE_AR = '(?:دبي|الشارقة|الشارقه|أبوظبي|ابوظبي|أبو\\s+ظبي|ابو\\s+ظبي|عجمان|الفجيرة|الفجيره|رأس\\s+الخيمة|راس\\s+الخيمة|أم\\s+القيوين|ام\\s+القيوين|العين|الإمارات|الامارات)';
export const ADDRESS = new RegExp(`\\b(?:Office|Shop|Showroom|Warehouse|Suite|Flat|Building|Bldg\\.?|Villa|Tower|Plot)\\s*(?:No\\.?|#)?\\s*\\d{1,5}(?:-\\d{1,5})?[A-Z]?\\s*[,\\-\\u2013]\\s*(?:[^,;\\n\\-\\u2013]{1,40}[,\\-\\u2013]\\s*){0,4}${EMIRATE_EN}\\b|\\bAl\\s+[A-Z][a-z]+\\s+Industrial\\s+Area\\s*\\d*`
  + `|${AR_START}(?:مكتب|محل|معرض|مستودع|شقة|شقه|فيلا|مبنى|بناية|بنايه|برج)\\s*(?:رقم\\s*)?${D}{1,5}\\s*[،,\\-\\u2013]\\s*(?:[^،,;\\n\\-\\u2013]{1,40}[،,\\-\\u2013]\\s*){0,4}${EMIRATE_AR}${AR_END}`, 'g');
/**
 * A PERSON after a label. A label is "… by" (prepared / issued / signed / submitted / arranged by), a sign-off
 * ("Regards", "Best Regards", "Kind regards", "Thanks & Regards" — with a comma, a line break or nothing; "Thanks",
 * "Thank you", "Rgds", "Br", "Cheers", "Sincerely" WITH a comma or a line break, so "Thanks for the opportunity" names
 * nobody), an address line WITH its colon ("Attn:", "Attention:", "Contact:", "Contact person:", "Name:" at the start of
 * a line or after Contact / Customer, "From:" at the start of a line), "My name is", a role WITH a colon or a dash
 * ("Sales Engineer: …", "Sales Engineer - …"), or a title with or without its dot ("Mr.", "Mr", "Eng", "Dr.") before a
 * capital. The name: Title-Case, ALL-CAPS, hyphenated ("Al-Mansoori"), apostrophe or camel-case ("D'Souza", "McDonald",
 * "DSouza"), an abbreviation ("Mohd."), initials, with the lowercase particles of Arabic names between them (al / el /
 * bin / bint / ibn / abu), up to six words. It runs on ONE line ("Best Regards\nAhmed Khan\nSales Manager").
 * personSpan then reads the words: roles before the name are skipped ("Regards, Sales Manager Ahmed Khan"), the name
 * stops at the first ordinary word or code, and fewer than two name words is nobody — "Regards, Supply Chain Team",
 * "Attention: Please note", "Mr. Client to provide", "Permit issued by Dubai Municipality", "Signed by Authorised
 * Signatory", "Prepared by Quantity Surveyor", "From: Existing Manhole MH-3" name nobody.
 * Arabic: المسؤول / مقدم العرض / الاسم / مدير … / مسؤول … / مندوب … WITH a colon; المهندس / المهندسة / السيد / السيدة /
 * الأستاذ / م. / م/ and a sign-off (مع التحية، تحياتي، شكرا) with or without punctuation ("المهندس/ أحمد المنصوري", "م.
 * أحمد المنصوري"), and "اسمي", then up to six words.
 */
const LABEL_EN = [`(?:${ci('prepared')}|${ci('issued')}|${ci('signed')}|${ci('submitted')}|${ci('arranged')})\\s+${ci('by')}\\s*[:,]?`,
  `(?:(?:${ci('best')}|${ci('kind')}|${ci('warm')}|${ci('warmest')}|${ci('with')})\\s+)?${ci('regards')}\\s*,?`,
  `(?:${ci('rgds')}|${ci('br')}|${ci('cheers')}|${ci('thank')}\\s+${ci('you')}|${ci('thanks')}|${ci('sincerely')}|${ci('yours')}\\s+(?:${ci('faithfully')}|${ci('truly')}|${ci('sincerely')}))\\s*(?:,|(?=[ \\t]*\\r?\\n))`,
  `(?:${ci('attn')}\\.?|${ci('attention')}|${ci('contact')}(?:\\s+${ci('person')})?|(?:${ci('contact')}|${ci('customer')}|${ci('supplier')}|${ci('engineer')})\\s+${ci('name')})\\s*:`,
  `(?<![^\\n])[ \\t]*(?:${ci('from')}|${ci('name')})\\s*:`, `${ci('my')}\\s+${ci('name')}\\s+${ci('is')}`, `${ci('ask')}\\s+${ci('for')}`,
  `(?:${ci('sales')}\\s+(?:${ci('engineer')}|${ci('manager')}|${ci('executive')})|${ci('project')}\\s+${ci('manager')}|${ci('account')}\\s+${ci('manager')}|${ci('estimation')}\\s+${ci('engineer')})\\s*[:\\-\\u2013]`,
  '(?:Mr|Mrs|Ms|Eng|Engr|Dr)\\.?(?=[ \\t]+[A-Z])'
  // 13 Nov 2026: "Contact / call / reach <Word>" was a label for one round and took "Manual Call Point", "Contact Adhesive",
  // "Reach Truck" (independent review): an unlabelled person is the second reader's, not a rule's.
].join('|');
const TITLE_EN = '(?:(?:Mr|Mrs|Ms|Eng|Engr|Dr)\\.?[ \\t]+)?';
const NAME_PART = "(?:[A-Z][a-z]{1,4}\\.(?=[ \\t])|[A-Z]\\.|[A-Z](?:'[A-Z])?[a-z']*(?:[A-Z][a-z']+)*|[A-Z]{2,})";
const NAME_TOKEN = `(?:(?:al|el|bin|ibn|abu)-)?${NAME_PART}(?:-${NAME_PART}){0,3}`;
const NAME_SEP = `[ \\t\\u00a0]+(?:${EN_PARTICLE}[ \\t\\u00a0]+)?`;
const LABEL_AR_COLON = `(?:المسؤول|مقدم\\s+العرض|الاسم|(?:مدير|مسؤول|مسئول|مندوب)\\s+${AW})\\s*[:：]`;
const LABEL_AR = `(?:المهندس|المهندسة|السيد|السيدة|الأستاذ|الاستاذ|الأستاذة|الاستاذة|(?<![0-9٠-٩]\\s*)(?<![\\u0600-\\u06FF.])م(?:\\.(?=\\s)|\\.?\\/)|مع\\s+(?:خالص\\s+)?(?:التحية|التحيات|الشكر|التقدير)|تحياتي|شكرا|شكراً|اسمي|وتفضلوا\\s+بقبول\\s+فائق\\s+الاحترام)\\s*[:：،,\\/]?`;
const SIG_ROLE = `[ \\t]*[|\\u2013\\-,][ \\t]*(?:(?:Sales|Project|Account|Estimation|Procurement|General|Technical|Operations|Managing|Senior|Site|MEP)[ \\t]+)?(?:Manager|Engineer|Executive|Director|Coordinator|Estimator|Supervisor)`;
// 13 Nov 2026 (REPORT_C L2): "Regards, Rashid" and "Eng. Rami" — ONE name word after a label is a person too (personSpan
// still refuses a team, a place, an authority or an instruction: "Regards, Team", "Mr. Client", "Contact Site Office").
export const PERSON_LABELLED = new RegExp(`(?:${LABEL_EN})\\s*${TITLE_EN}${NAME_TOKEN}(?:${NAME_SEP}${NAME_TOKEN}){0,5}(?![A-Za-z])`
  + `|(?<![^\\n])[ \\t]*${NAME_TOKEN}(?:${NAME_SEP}${NAME_TOKEN}){1,4}(?=${SIG_ROLE})`
  // Arabic keeps its two words: "يسأل المهندس الخبير" (the expert engineer) and "اسمياً" (nominally) are not names.
  + `|${AR_START}(?:${LABEL_AR_COLON}|${LABEL_AR})\\s*${AW}(?:[ \\t]+${AW}){1,5}${AR_END}`, 'g');
/** Roles that may stand between a label and the name ("Regards, Sales Manager Ahmed Khan"): skipped, never a name. */
const ROLE = new Set(['sales', 'manager', 'engineer', 'project', 'procurement', 'estimation', 'estimator', 'account', 'accounts', 'executive', 'coordinator', 'director', 'qs', 'senior',
  'junior', 'assistant', 'general', 'technical', 'operations', 'site', 'mep', 'hvac', 'design', 'eng', 'engr', 'mr', 'mrs', 'ms', 'dr']);
/** Words that are not names (a sign-off to a team, a place, an authority, a party to a contract, an instruction). */
const NOT_A_NAME = new Set(['supply', 'chain', 'team', 'department', 'dept', 'office', 'site', 'please', 'note', 'client', 'contractor', 'consultant', 'consultants', 'engineer', 'manager',
  'ground', 'floor', 'first', 'second', 'roof', 'level', 'to', 'the', 'all', 'our', 'your', 'main', 'sales', 'project', 'procurement', 'accounts', 'management', 'customer', 'service',
  'services', 'support', 'technical', 'estimation', 'tender', 'tendering', 'mep', 'hvac', 'civil', 'design', 'operations', 'quality', 'safety', 'store', 'stores', 'warehouse', 'admin',
  // second review of #1838: places, authorities and the parties to a contract ("Permit issued by Dubai Municipality")
  'dubai', 'dhabi', 'sharjah', 'ajman', 'fujairah', 'ras', 'khaimah', 'umm', 'quwain', 'ain', 'uae', 'emirates', 'municipality', 'authority', 'electricity', 'water', 'defence', 'defense',
  'police', 'ministry', 'government', 'dewa', 'sewa', 'fewa', 'addc', 'aadc', 'rta', 'both', 'parties', 'party', 'tenderer', 'tenderers', 'bidder', 'bidders', 'owner', 'employer',
  'developer', 'before', 'after', 'closing', 'date', 'approval', 'works', 'board', 'committee', 'qs', 'hr', 'it', 'finance', 'legal', 'purchasing', 'logistics', 'and', 'or', 'of', 'for',
  // adversarial re-review: roles, an instruction or a thing after a label ("Prepared by Quantity Surveyor", "Thanks, Will Confirm")
  'quantity', 'surveyor', 'signatory', 'authorised', 'authorized', 'existing', 'security', 'mall', 'will', 'confirm', 'tomorrow', 'today', 'best', 'kind', 'regards', 'thanks', 'find',
  'attached', 'fit', 'out', 'be', 'is', 'are', 'we', 'you', 'from', 'with', 'by', 'at', 'in', 'on', 'as', 'per', 'this', 'that', 'these', 'those', 'an', 'no', 'yes', 'ok', 'sir', 'madam',
  'dear', 'hi', 'hello', 'team', 'shop', 'drawings', 'drawing', 'fixit', 'mobilisation', 'mobilization', 'permits', 'permit', 'manhole',
  // 13 Nov 2026: a single word after "Contact" / "call" / a sign-off is now a name, so the words that follow those verbs
  // in trade text are named here ("Call Centre", "Contact Details", "call Monday", "Contact: Reception").
  'details', 'detail', 'information', 'info', 'number', 'numbers', 'person', 'persons', 'centre', 'center', 'desk', 'reception', 'helpdesk', 'hotline', 'us', 'me',
  'him', 'her', 'them', 'back', 'later', 'now', 'soon', 'asap', 'immediately', 'directly', 'anytime', 'here', 'there', 'below', 'above', 'whatsapp', 'email', 'mail', 'phone', 'mobile',
  'tel', 'landline', 'form', 'page', 'list', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday', 'january', 'february', 'march', 'april', 'may', 'june',
  'july', 'august', 'september', 'october', 'november', 'december', 'trakhees', 'dda', 'dm', 'dcd', 'adcd', 'tdra', 'etisalat', 'du', 'civil', 'defence', 'sir/madam', 'gentlemen',
  'concerned', 'whom', 'everyone', 'all,', 'guys', 'sales', 'gate', 'lobby', 'guard', 'watchman', 'foreman', 'supervisor', 'operator', 'driver', 'technician', 'electrician', 'plumber',
  'painter', 'mason', 'labour', 'labor', 'manpower', 'staff', 'crew', 'company', 'firm', 'supplier', 'vendor', 'agent', 'dealer', 'distributor', 'manufacturer', 'factory', 'brand',
  'helpline', 'care', 'emergency', 'police', 'ambulance', 'it', 'its', 'confirmation', 'approval', 'order', 'orders', 'delivery', 'pricing', 'price', 'quotation', 'quote', 'more',
  'المشرف', 'المقاول', 'الرئيسي', 'المشروع', 'التركيب', 'الموقع', 'عن', 'على', 'من', 'في', 'المسؤول', 'الاستشاري', 'العميل', 'المقيم', 'المختص', 'المصمم', 'المنفذ', 'المعماري',
  'الإنشائي', 'الانشائي', 'الكهربائي', 'الميكانيكي', 'المدني', 'المراقب', 'المدير', 'مدير', 'الإدارة', 'الادارة', 'قسم', 'فريق', 'شركة', 'مؤسسة', 'إلى', 'الى', 'مع', 'أو', 'او',
  'تم', 'يتم', 'سيتم', 'يقوم', 'سيقوم', 'حسب', 'طول', 'عرض', 'ارتفاع', 'المخطط', 'التعاون', 'الجميع',
  'قبل', 'بعد', 'طوال', 'خلال', 'أثناء', 'اثناء', 'فترة', 'فتره', 'والتقدير', 'والاحترام', 'لكم', 'لك', 'جزيلا', 'جزيلاً', 'حتى', 'عند', 'لدى', 'التنفيذ', 'البدء', 'بالأعمال',
  'بالاعمال', 'الأعمال', 'الاعمال', 'على', 'هذا', 'هذه', 'التي', 'الذي']);
const LABEL_STRIP = new RegExp(`^(?:(?:${LABEL_EN})\\s*${TITLE_EN}|(?:${LABEL_AR_COLON}|${LABEL_AR})\\s*)`);
/**
 * The span of a labelled match that names a person, or null when it names nobody: the label, any roles, and the words up
 * to the first ordinary word (NOT_A_NAME, a word with a digit, or an Arabic word starting لل — "for the …" is never part of
 * a name), when at least two name words are left. Particles (al / bin / …) ride along and never count.
 */
/** Words written like a name after "Dr." / "Eng." that are a product or a document ("Dr. Fixit", "Eng. Drawings"). */
const ONE_WORD_NOT_A_NAME = new Set(['fixit', 'drawings', 'drawing', 'approval', 'approved', 'submittal', 'specs', 'specification', 'department', 'team', 'office', 'dept']);
let rest = '';
const personSpan = (m: string, at = 0, text = m): [number, number] | null => {
  rest = text.slice(at + m.length);
  const label = m.match(LABEL_STRIP)?.[0] ?? '';
  let end = label.length, names = 0, first = '';
  for (const w of m.slice(label.length).matchAll(/\S+/g)) {
    const bare = w[0].replace(/[.,،]$/, '').toLowerCase();
    if (!names && ROLE.has(bare)) continue;
    if (NOT_A_NAME.has(bare) || bare.startsWith('لل') || /\d/.test(bare)) break;
    if (!new RegExp(`^${EN_PARTICLE}$`).test(bare)) { if (!names) first = w[0]; names++; end = label.length + w.index! + w[0].length; }
  }
  // ONE name word only after a title ("Eng. Rami", "Mr Rashid") or a sign-off that ends its line ("Regards, Rashid"),
  // written as a name: never an acronym or a code ("Eng. drawings", "Dr. Fixit" stay: a lower-case or a product word).
  if (names === 1 && /^[A-Z][a-z]{2,}[.,]?$/.test(first) && !ONE_WORD_NOT_A_NAME.has(first.replace(/[.,]$/, '').toLowerCase())) {
    const tail = m.slice(end);
    if (/^(?:Mr|Mrs|Ms|Eng|Engr|Dr)\.?[ \t]/.test(label) || (/regards|rgds|cheers|thanks|thank\s+you|sincerely|yours/i.test(label) && /^[ \t.,]*$/.test(tail) && /^[ \t.,]*(?:\r?\n|$)/.test(rest))) return [0, end];
  }
  return names >= 2 ? [0, end] : null;
};
/**
 * E-mail. Written plainly ("info@acme.ae") its domain carries a letter; obfuscated ("ahmed @ gmail . com", "ahmed[at]
 * gmail[dot]com", "ahmed(at)gmail(dot)com", "ahmed at gmail dot com" — moved here from messages_api's stripContact,
 * second review of #1838) it must also END in a mail domain (com / ae / net / org / co): the adversarial re-review
 * measured "Supply 10 nos @ 450. Total 4500" and "We can meet @ site. Send the drawings" read as addresses.
 */
// A bracketed (at) / [at] is never a price or a meeting place, so any ending goes with it ("info [at] host.example.invalid":
// the final leak run found the shared list stricter than the Q&A copy it replaced, 1 of 180 messages).
export const EMAIL = /[A-Za-z0-9._%+-]{1,64}@(?=[A-Za-z0-9-]*[A-Za-z])[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,24}(?![A-Za-z])|[A-Za-z0-9._%+-]{1,64}\s*(?:\(at\)|\[at\])\s*[A-Za-z0-9-]+(?:\s*(?:\(dot\)|\[dot\]|\.)\s*[A-Za-z0-9-]+){0,4}\s*(?:\(dot\)|\[dot\]|\.)\s*[A-Za-z]{2,24}(?![A-Za-z])|[A-Za-z0-9._%+-]{1,64}(?:\s+@\s*|\s*@\s+|\s+at\s+)(?=[A-Za-z0-9-]*[A-Za-z])[A-Za-z0-9-]+(?:\s*(?:\(dot\)|\[dot\])\s*|\s*\.\s*|\s+dot\s+)(?:com|ae|net|org|co)(?![A-Za-z])/gi;
/**
 * An address with spaces around its "@" and an ending of any length (13 Nov 2026, anonymity audit REPORT_A L4: "omar.haddad
 * @ zz-mail.example.invalid" was only half-masked on the e-mail and answer paths). Case-sensitive on purpose: the dotted
 * host is lower-case, so "meet @ site.Send the drawings" and "10 nos @ 450. Total" are not addresses.
 */
export const EMAIL_SPACED = /(?<![\w.+-])[A-Za-z0-9][A-Za-z0-9._%+-]{0,63}\s*@\s*(?=[a-z0-9-]*[a-z])[a-z0-9-]+(?:\.[a-z0-9-]+)*\.[a-z]{2,24}(?![A-Za-z])/g;
export const URL = /(?:https?:\/\/|www\.)[^\s,;)\]]+/gi;
/**
 * The supplier's OWN document number (13 Nov 2026, REPORT_C L2: "Quotation No. FT-Q-2026-0457" reached the customer on
 * every layer, and its prefix is the firm's initials). After a quotation / offer / invoice label any code with a digit;
 * anywhere, a code shaped like a document register ("FT/Q/2026/0412", "AN-QTN-2026-118"): letters, a year, a serial.
 * Our own numbers (RFQ-…, QD-…) stay. "Ref TL 273158 luminaire" and "Ref CT-1" are product references, not here.
 */
export const DOC_NO = new RegExp(`(?<![A-Za-z])(?:${ci('quotation')}|${ci('quote')}|Qtn\\.?|QTN\\.?|Q\\.\\s?No\\.?|${ci('invoice')}|${ci('proforma')}|${ci('offer')}|${ci('proposal')}|${ci('our')}\\s+${ci('ref')}(?:${ci('erence')})?\\.?)\\s*(?:${ci('no')}\\.?|${ci('number')}|#|${ci('ref')}\\.?)?\\s*[:.#]?\\s*(?!(?:RFQ|QD|rfq|qd)[\\-\\s/]?\\d)(?=[A-Za-z0-9/\\-]*(?:\\d|█))[A-Z]{1,6}(?:[\\-/](?:[A-Z0-9]{1,8}|█)){1,5}(?![A-Za-z0-9])`
  // Anywhere, only a QUOTATION register shape ("FT-Q-2026-0457", "AN/QTN/2026/118"): "Drawing A-2026-101", "DWG-2025-0034",
  // "Approval ref DM-2024-0123" are drawings and permits (independent review of 13 Nov 2026).
  + `|(?<![A-Za-z0-9\\-/])(?!(?:RFQ|QD)[\\-/])[A-Z]{1,5}[\\-/](?:Q|QT|QTN|QUO|QUOT|INV|PI|OFR|OFFER)[\\-/](?:(?:19|20)\\d{2}[\\-/]\\d{2,6}(?![A-Za-z0-9])|█)`, 'g');
/**
 * A UAE bank by name (13 Nov 2026, REPORT_C L2: "IBAN … (Emirates NBD)" kept the bank after the IBAN went). A full name
 * always; an acronym (FAB, CBD, DIB, ADIB, NBF, UAB, ENBD) only beside a bank word, a payment word or an IBAN, so "FAB
 * shop" and "CBD area" are left alone (bankSpan).
 */
const BANKS_FULL = ['Emirates NBD', 'Emirates Islamic', 'Mashreq(?:\\s+Neo)?', 'Abu Dhabi Commercial Bank', 'First Abu Dhabi Bank', 'Dubai Islamic Bank', 'Abu Dhabi Islamic Bank',
  'RAK\\s?BANK', 'RAKBANK', 'National Bank of Ras Al Khaimah', 'Commercial Bank of Dubai', 'Sharjah Islamic Bank', 'Bank of Sharjah', 'Ajman Bank', 'National Bank of Fujairah',
  'National Bank of Umm Al Qaiwain', 'United Arab Bank', 'Invest Bank', 'Al Hilal Bank', 'Noor Bank', 'Emirates Investment Bank', 'HSBC(?:\\s+Bank)?(?:\\s+Middle\\s+East)?',
  'Citi\\s?bank', 'Standard Chartered(?:\\s+Bank)?', 'Arab Bank', 'Habib Bank(?:\\s+AG\\s+Zurich)?', 'Bank of Baroda', 'State Bank of India', 'Banque Misr', 'Al Masraf', 'Wio Bank'];
// "EI 60" is a fire rating, "FAB shop", "CBD board", "HBL cable tray", "ADCB approved valuer" are not payment details.
const BANKS_ACR = ['FAB', 'CBD', 'DIB', 'ADIB', 'ADCB', 'NBF', 'UAB', 'NBQ', 'HBL', 'ENBD'];
const BANKS_AR = ['بنك الإمارات دبي الوطني', 'بنك الامارات دبي الوطني', 'الإمارات الإسلامي', 'بنك المشرق', 'المشرق', 'مصرف أبوظبي الإسلامي', 'مصرف ابوظبي الاسلامي', 'بنك دبي الإسلامي',
  'بنك دبي الاسلامي', 'بنك أبوظبي الأول', 'بنك ابوظبي الاول', 'بنك أبوظبي التجاري', 'بنك ابوظبي التجاري', 'بنك رأس الخيمة الوطني', 'بنك دبي التجاري', 'مصرف الشارقة الإسلامي', 'بنك الشارقة',
  'بنك عجمان', 'بنك الفجيرة الوطني', 'بنك الاستثمار', 'مصرف الهلال', 'مصرف عجمان'];
export const BANK = new RegExp(`(?<![A-Za-z])(?:${BANKS_FULL.join('|')})(?![A-Za-z])|(?<![A-Za-z])(?:${BANKS_ACR.join('|')})(?![A-Za-z])|${AR_START}(?:${BANKS_AR.join('|')})${AR_END}`, 'g');
const BANK_CONTEXT = /\b(?:bank|banking|iban|a\/c|account\s+(?:no|number|name|#)|acct|swift|beneficiary)\b|cheques?\s+(?:in\s+favou?r\s+of|payable\s+to)|بنك|مصرف|حساب|آيبان|ايبان/i;
/** An acronym is a bank only beside a bank word, an IBAN or an account on its own line. */
const bankSpan = (m: string, at: number, text: string): [number, number] | null => {
  // "Mashreq" is also "the East" ("Mashreq tower fit-out"): like an acronym, a bank only beside a bank word.
  if (!new RegExp(`^(?:${BANKS_ACR.join('|')}|Mashreq)$`).test(m)) return [0, m.length];
  const a = text.lastIndexOf('\n', at) + 1, b = text.indexOf('\n', at + m.length);
  const line = text.slice(a, b < 0 ? text.length : b).replace(m, '');
  return BANK_CONTEXT.test(line) ? [0, m.length] : null;
};
/**
 * A signature block's words (13 Nov 2026, REPORT_C L2: "Sales Manager. Signed and stamped" reached the customer): "Signed
 * and stamped", "Authorised signature", "[company stamp: …]", and a seller's job title standing as its own line or
 * sentence or after a comma ("[removed], Sales Manager."). "Project Manager Full Time On Site" is scope (a person provided), so Project / Site roles are not here.
 */
// A signature BLOCK only (independent review of 13 Nov 2026): the phrase as its own line or sentence, or followed by a
// bracket or "by <name>"; "Quotation must be signed and stamped", "Company stamp required" are the customer's instruction.
export const SIGNATURE = new RegExp(`(?<=(?:^|[.\\n;|])[ \\t]{0,3})(?:${ci('signed')}\\s+(?:${ci('and')}|&)\\s+${ci('stamped')}|${ci('authori')}[sz]ed\\s+${ci('signature')}(?:\\s+(?:${ci('and')}|&)\\s+${ci('stamp')})?|${ci('company')}\\s+${ci('stamp')}|${ci('signature')}\\s+(?:${ci('and')}|&)\\s+${ci('stamp')})(?:\\s*[:\\-]?\\s*\\[[^\\]\\n]{0,80}\\])?(?=[ \\t]*(?:[.\\n;|]|$|${ci('by')}\\s|:))`
  + `|\\[\\s*(?:${ci('signature')}|${ci('stamp')}|${ci('company')}\\s+${ci('stamp')}|${ci('seal')})[^\\]\\n]{0,80}\\]`
  + `|(?<=(?:^|[.\\n;|,])[ \\t]{0,3})(?:Sales|General|Managing|Area|Regional|Branch|Showroom|SALES|GENERAL|MANAGING)[ \\t]+(?:Manager|Director|Executive|MANAGER|DIRECTOR|EXECUTIVE)(?=[ \\t]*(?:[.\\n;|]|$))`
  + `|(?<=(?:^|[.\\n;|،])[ \\t]{0,3})(?:الختم\\s+والتوقيع|التوقيع\\s+والختم|ختم\\s+الشركة|مختوم\\s+وموقع|موقع\\s+ومختوم)${AR_END}(?=[ \\t]*(?:[.\\n;|،]|$))`, 'g');
/**
 * A bare domain WITH its path ("instagram.com/alnoortrading" loses the handle as well as the host). The common endings
 * in any case; the long tail ("alnoor.store", ".shop", ".me", ".in", ".dev", ".build" …) only in lower case, because a
 * sentence with no space after its full stop reads the same ("30 days.Site visit", "2 coats.Group A colours").
 */
// A host carries a letter: "pipe 3.in dia" is a size (caught by identity_contacts.test.ts).
export const DOMAIN = /(?<![@\w.-])(?=[A-Za-z0-9-]*[A-Za-z])[A-Za-z0-9][A-Za-z0-9-]+(?:\.[A-Za-z0-9-]{2,})*\.(?:ae|com|net|org|co|io|biz)(?:\.[a-z]{2})?(?![\w-])(?:\/[^\s,;)\]]*)?/gi;
export const DOMAIN_LC = /(?<![@\w.-])(?=[a-z0-9-]*[a-z])[a-z0-9][a-z0-9-]+(?:\.[a-z0-9-]{2,})*\.(?:info|app|link|store|shop|online|site|tech|xyz|uk|sa|qa|om|bh|kw|eg|ai|pro|group|global|ltd|me|in|dev|build|construction|contractors|email|company|services|solutions|trading)(?:\.[a-z]{2})?(?![\w-])(?:\/[^\s,;)\]]*)?/g;
/** A domain spelled out to dodge a filter: "alnoor . ae", "alnoor dot ae". */
// No start inside a hyphenated run and a bounded label (second review: 50 KB of "Al-Al-…" took 813 ms here).
export const DOMAIN_SPACED = /(?<![\w.@-])[A-Za-z][A-Za-z0-9-]{2,62}(?:\s+\.\s*|\s*\.\s+|\s+dot\s+)(?:ae|com)(?![\w])/gi;
/**
 * A social handle: after a platform's name ("Instagram: @alnoor_trading", "facebook /alnoortrading", "IG alnoor.trading")
 * when it looks like a handle (an @, a slash, or a dot / underscore / digit in it — "WhatsApp group for site updates" is
 * not one), or any @handle with a lowercase letter in it ("@AED50" is a price).
 */
export const SOCIAL = /\b(?:instagram|insta|ig|facebook|fb|linkedin|tiktok|twitter|snapchat|snap|telegram|whats\s*app|viber|botim|skype|youtube)\b[ \t]*[:\-]?[ \t]*(?:[@\/][\w.]{2,}|(?=[A-Za-z][\w]*[._\d])[A-Za-z][\w.]{2,})/gi;
/** Case-sensitive on purpose: the lowercase letter is what tells "@alnoor_trading" from a price "@AED50". */
export const HANDLE = /(?<![\w@])@(?=[\w.]*[a-z])[A-Za-z][\w.]{2,}/g;

/** Named, so a residual scan can say which one it found. Order matters: mail before hosts, registration numbers before phones. */
export const IDENTITY_TEXT_PATTERNS: [string, RegExp][] = [
  ['email', EMAIL], ['email_spaced', EMAIL_SPACED], ['url', URL], ['domain', DOMAIN], ['domain_lc', DOMAIN_LC], ['domain_spaced', DOMAIN_SPACED], ['social', SOCIAL], ['handle', HANDLE],
  ['trn', TRN_LABELLED], ['trn_bare', TRN_BARE], ['licence_no', LICENCE_NO], ['licence_short', LICENCE_SHORT],
  ['iban', IBAN], ['account_no', ACCOUNT_NO], ['po_box', PO_BOX], ['doc_no', DOC_NO], ['bank', BANK],
  ['phone_uae_intl', PHONE_UAE_INTL], ['phone_uae_national', PHONE_UAE_NATIONAL], ['phone_uae_short', PHONE_UAE_SHORT], ['phone_intl', PHONE_INTL],
  ['address', ADDRESS], ['firm_ar', FIRM_AR], ['firm_en', FIRM_EN], ['person_labelled', PERSON_LABELLED],
  // After the person: "Ahmed Khan | Sales Manager" is a name because of the title beside it.
  ['signature', SIGNATURE],
];
const PHONES = new Set(['phone_uae_intl', 'phone_uae_national', 'phone_uae_short', 'phone_intl']);
/** The [start, end) of a match that is identity, or null when its words say it is not (a discipline, a team, an authority). */
/** The founder, 13 Nov 2026 (ledger 1683): "Dubai in general is okay". An address loses everything but its emirate. */
const addressSpan = (m: string): [number, number] | null => { const e = m.match(new RegExp(`[\\s,،\\-\\u2013]*(?:${EMIRATE_EN}|${EMIRATE_AR})$`)); return [0, e ? m.length - e[0].length : m.length]; };
const SPAN: Record<string, (m: string, at: number, text: string) => [number, number] | null> = { firm_en: firmSpan, person_labelled: personSpan, address: addressSpan, bank: bankSpan };
const spanOf = (name: string, m: string, at: number, text: string): [number, number] | null => (SPAN[name] ? SPAN[name](m, at, text) : [0, m.length]);
/** True when `name`'s match `m` (at `at` in `text`) is identity: what a residual scan should report. */
export function identityMatch(name: string, m: string, at = 0, text = m): boolean { return spanOf(name, m, at, text) != null; }

// ── a phone written in words or split to dodge a filter (13 Nov 2026, REPORT_A L4 / REPORT_C L2) ──────────────────────
// "zero five five, zero zero zero, zero four nine nine", "zero five zero one two three four five six seven", "055 000 then
// 0499", "050 123 / then 4567" passed every scrubber. A run of digit words and digit groups is read as the number it
// spells, and taken only when that number IS a UAE phone (05X + 7 digits, a landline, or with 971 / 00971): "two coats then
// one coat" spells 21, and a BOQ row's figures joined by commas are never read (a run of bare digit groups needs a "then"
// between them: "05/03/2026 09:00" and "DN 050/065/080" are a date and a list).
const DIGIT_WORD: Record<string, string> = { zero: '0', oh: '0', one: '1', two: '2', three: '3', four: '4', five: '5', six: '6', seven: '7', eight: '8', nine: '9',
  'صفر': '0', 'واحد': '1', 'اثنان': '2', 'اثنين': '2', 'ثلاثة': '3', 'ثلاثه': '3', 'أربعة': '4', 'اربعة': '4', 'اربعه': '4', 'خمسة': '5', 'خمسه': '5', 'ستة': '6', 'سته': '6', 'سبعة': '7', 'سبعه': '7',
  'ثمانية': '8', 'ثمانيه': '8', 'تسعة': '9', 'تسعه': '9' };
const DW = `(?:zero|oh|one|two|three|four|five|six|seven|eight|nine|صفر|واحد|اثنان|اثنين|ثلاث[ةه]|[أا]ربع[ةه]|خمس[ةه]|ست[ةه]|سبع[ةه]|ثماني[ةه]|تسع[ةه])`;
// A digit token ENDS at a non-digit (independent review of 13 Nov 2026: with `[0-9]{1,4}` and an empty joiner, a run of
// 104 digits split every way and scrubIdentityText ran past 60 s; a serial number stalled every inbox).
const DTOK = `(?:(?:double|triple)\\s+${DW}|${DW}|(?:\\+|00)?[0-9٠-٩]{1,4}(?![0-9٠-٩]))`;
const DJOIN = `(?:[\\s,،./\\-–]|\\bthen\\b|\\band\\b|\\bfollowed\\s+by\\b|ثم|و){0,6}`;
const PHONE_WORDS_RE = new RegExp(`(?<![\\w\\u0600-\\u06FF])${DTOK}(?:${DJOIN}${DTOK}){2,24}(?![\\w\\u0600-\\u06FF])`, 'gi');
const UAE_PHONE_DIGITS = /^(?:(?:00|\+)?971|0)?(?:5[0245689]\d{7}|[2-4679]\d{7})$/;
function spelled(run: string): string {
  return run.toLowerCase().replace(new RegExp(`(double|triple)\\s+(${DW})`, 'gi'), (_m, k: string, w: string) => (DIGIT_WORD[w.toLowerCase()] ?? DIGIT_WORD[w] ?? '').repeat(k.toLowerCase() === 'double' ? 2 : 3))
    .replace(new RegExp(DW, 'gi'), (w) => DIGIT_WORD[w.toLowerCase()] ?? DIGIT_WORD[w] ?? DIGIT_WORD[w.replace(/ه$/, 'ة')] ?? '')
    .replace(/[٠-٩]/g, (c) => String(c.charCodeAt(0) - 0x660)).replace(/[^0-9+]/g, '');
}
function phoneWordSpans(text: string): [number, number][] {
  const out: [number, number][] = [];
  for (const m of text.matchAll(PHONE_WORDS_RE)) {
    const run = m[0];
    const words = new RegExp(DW, 'i').test(run), joined = /\bthen\b|followed\s+by|ثم/i.test(run);
    if (!words && !joined) continue;
    const d = spelled(run);
    if (UAE_PHONE_DIGITS.test(d.replace(/^\+/, ''))) out.push([m.index!, m.index! + run.length]);
  }
  return out;
}
function scrubPhoneWords(t: string, rep: string | ((m: string) => string)): string {
  const spans = phoneWordSpans(t);
  for (let i = spans.length - 1; i >= 0; i--) { const [a, b] = spans[i]; t = t.slice(0, a) + (typeof rep === 'string' ? rep : rep(t.slice(a, b))) + t.slice(b); }
  return t;
}

/**
 * Every identity shape above replaced by `rep` (a string, or a function of the match). `parties: false` leaves firm
 * and person names alone — the quotation a customer has PAID to reveal names its supplier (review of #1838, item 1).
 * Phones run twice: a second number printed straight after a first ("Tel 04 345 6789 050 123 4567") is only a whole
 * number once the first is gone.
 */
/** Runs of blanks are capped at two before any pattern runs (a pasted BOQ with wide blank columns was a run of 1,000+
 *  spaces: 2,000 took more than 60 s). See capBlanks: a line's indent stays, an inner gap prints as two spaces. */
export const collapseSpaces = (s: string) => capBlanks(s);
export function scrubIdentityText(text: unknown, rep: string | ((m: string) => string) = '', opts: { parties?: boolean } = {}): string {
  let t = collapseSpaces(String(text ?? ''));
  const run = (name: string, re: RegExp) => {
    t = t.replace(re, (m: string, ...rest: unknown[]) => {
      const at = rest.find((x) => typeof x === 'number') as number, whole = rest.find((x) => typeof x === 'string') as string;
      const sp = spanOf(name, m, at, whole);
      return sp == null ? m : m.slice(0, sp[0]) + (typeof rep === 'string' ? rep : rep(m.slice(sp[0], sp[1]))) + m.slice(sp[1]);
    });
  };
  for (const [name, re] of IDENTITY_TEXT_PATTERNS) {
    if (opts.parties === false && (name === 'firm_ar' || name === 'firm_en' || name === 'person_labelled')) continue;
    run(name, re);
    // Places right after the contacts (13 Nov 2026, ledger 1683): before the numbers, so "Villa 15" and "Makani 12345
    // 67890" go as places, and before the firm and address shapes, so the emirate of "Shop 5, Al Quoz, Dubai" stays.
    if (name === 'handle') t = reducePlaces(t, rep);
  }
  for (const [name, re] of IDENTITY_TEXT_PATTERNS) if (PHONES.has(name)) run(name, re);
  t = scrubPhoneWords(t, rep);
  return t;
}
/** Only the addresses one can write to (e-mail, web, social): run FIRST where a known name is replaced by words, so
 *  "rashid@falcontrading.example.invalid" is removed whole instead of reading "rashid@the supplier.example.invalid". */
export function scrubAddresses(text: unknown, rep: string | ((m: string) => string) = ''): string {
  let t = String(text ?? '');
  for (const [name, re] of IDENTITY_TEXT_PATTERNS) {
    if (!['email', 'email_spaced', 'url', 'domain', 'domain_lc', 'domain_spaced', 'social', 'handle'].includes(name)) continue;
    t = t.replace(re, (m: string) => (typeof rep === 'string' ? rep : rep(m)));
  }
  return t;
}
/** Every identity shape in `text`, by name (the residual scan's half of the list). */
export function identityShapesIn(text: unknown): string[] {
  const s = collapseSpaces(String(text ?? '')), found = new Set<string>();
  for (const [name, re] of IDENTITY_TEXT_PATTERNS) for (const m of s.matchAll(new RegExp(re.source, re.flags))) if (identityMatch(name, m[0], m.index, s)) { found.add(name); break; }
  if (placeSpans(s).length) found.add('place');
  if (phoneWordSpans(s).length) found.add('phone_words');
  return [...found];
}


// ── a KNOWN name (the supplier's own company, the buyer's own name, a project's name) ───────────────────────
const CO_SUFFIX = '(?:l\\.?\\s?l\\.?\\s?c\\.?|fz-?llc|fzc|fze|fzco|trading|contracting|establishment|est\\.?|general|co\\.?|company|group)(?![A-Za-z])';
const rxEsc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
/** Words a trade uses for its scope: a firm named by one of these alone is matched only with its suffix. */
const TRADE_WORDS = new Set([...NOT_A_FIRM, 'insulation', 'glass', 'concrete', 'timber', 'wood', 'paint', 'paints', 'tiles', 'tile', 'marble', 'granite', 'cable', 'cables', 'pipe',
  'pipes', 'electric', 'cooling', 'lighting', 'light', 'safety', 'security', 'cleaning', 'gypsum', 'ceiling', 'doors', 'windows', 'furniture', 'kitchen', 'carpentry', 'solar', 'power',
  'water', 'energy', 'elevator', 'elevators', 'lifts', 'scaffolding', 'waterproofing', 'flooring', 'interiors', 'decor', 'mirror', 'metal', 'metals', 'cement', 'sand', 'blocks']);
/** Latin or Arabic letter/digit: \b does not see Arabic, so word edges are written out. */
const W = '[A-Za-z0-9؀-ۿ]';
/** A regex source with its letters made case-blind and its escapes (\s, \.) left alone: these names are built without the
 *  `i` flag so that the initials and a house brand below can be matched in their own case. */
const ciSrc = (src: string) => src.replace(/\\.|[A-Za-z]/g, (m) => (m.length === 2 ? m : `[${m.toUpperCase()}${m.toLowerCase()}]`));
/** A demo account's prefix: "ZZ DEMO Falcon Trading LLC" is tested as "Falcon Trading LLC" (REPORT_C L3, 13 Nov 2026: the
 *  name was matched only with its "ZZ DEMO", so "Falcon premium paint" reached the PDF while a real-shaped name was caught). */
const DEMO_PREFIX = /^\s*ZZ(?:[\s_-]+DEMO)?[\s_-]+/i;
const LEGAL_WORD = /^(?:l\.?l\.?c\.?|llc|fz-?llc|fzc|fze|fzco|co\.?|company|est\.?|establishment|ltd\.?|limited|w\.?l\.?l\.?|dmcc|pjsc|spc|l\.l\.c)$/i;
/** The trade words a supplier drops when it writes its own name ("Desert Brush team" for Desert Brush Painting LLC). */
const SHORT_TRADE = new Set([...TRADE_WORDS, 'painting', 'painters', 'fabrication', 'fabricators', 'equipment', 'decoration', 'solutions', 'systems', 'services', 'service', 'technical',
  'maintenance', 'engineering', 'electromechanical', 'trading', 'contracting', 'general', 'industries', 'industry', 'enterprises', 'supplies', 'construction', 'constructions', 'air',
  'conditioning', 'landscaping', 'pools', 'pool', 'swimming', 'renovation', 'renovations', 'kitchens', 'curtains', 'blinds', 'pest', 'control', 'technologies', 'technology', 'projects',
  'developers', 'real', 'estate', 'properties', 'transport', 'logistics', 'cargo', 'shipping', 'consultancy', 'engineers', 'designs', 'studio', 'ready', 'mix', 'fencing', 'shades',
  'parking', 'tents', 'signs', 'signage', 'advertising', 'printing', 'events', 'management', 'facilities', 'facility', 'trucks', 'transport']);
/** A word that names a firm and nothing else: not a trade, material or common business word ("Falcon", "Haddad", "Shield"). */
const distinctive = (w: string) => w.length >= 4 && /^[A-Za-z\u0621-\u064A]/.test(w) && !SHORT_TRADE.has(w.toLowerCase()) && !NOT_A_ROOT.has(w.toLowerCase()) && !COMMON_NAME_WORD.has(w.toLowerCase());
const COMMON_NAME_WORD = new Set(['gulf', 'best', 'fast', 'home', 'power', 'unique', 'plus', 'tech', 'world', 'house', 'concept', 'precision', 'construct', 'star', 'stars', 'city', 'line',
  'link', 'point', 'zone', 'land', 'sea', 'sky', 'sun', 'blue', 'green', 'white', 'black', 'gold', 'golden', 'new', 'east', 'west', 'north', 'south', 'top', 'one', 'pro', 'max', 'mega',
  'trust', 'hope', 'vision', 'future', 'value', 'care', 'safe', 'safety', 'secure', 'quick', 'easy', 'clean', 'pure', 'fresh', 'bright', 'light', 'brightway', 'unity', 'union',
  'stone', 'marble', 'granite', 'ceramic', 'stainless', 'thermo', 'hydro', 'electra', 'standard', 'fixings', 'fix']);
/** Words too common to make a house brand's root ("Emirates…", "Premium…"). */
const NOT_A_ROOT = new Set(['emirates', 'emirati', 'arabian', 'national', 'international', 'global', 'united', 'royal', 'golden', 'modern', 'premium', 'prime', 'smart', 'first', 'standard',
  'dubai', 'sharjah', 'middle', 'eastern', 'western', 'northern', 'southern', 'quality', 'perfect', 'master', 'super', 'classic', 'crystal', 'diamond', 'silver', 'future', 'creative',
  'professional', 'advanced', 'superior', 'excellent', 'elite', 'supreme', 'universal', 'continental', 'oriental', 'regional', 'technical']);
// ── a name written in the other script (13 Nov 2026, REPORT_A L4 / REPORT_C L2): "أنا عمر حداد" for a customer stored as
// "Omar Haddad", and "فالكون للدهانات" for Falcon Trading, passed every scrubber. A name is matched by its CONSONANTS, the
// way the two scripts write it: vowels and the Arabic long vowels / ain / hamza are optional, doubled letters are one.
const AR_V = '[اأإآءئؤعوىيةه]*';
const LAT2AR: [RegExp, string][] = [[/^sh/, 'ش'], [/^kh/, 'خ'], [/^gh/, '[غق]'], [/^th/, '[ثذتط]'], [/^dh/, '[ذضظد]'], [/^ch/, '[شتك]'], [/^ph/, 'ف'], [/^ck/, '[كق]'],
  [/^b/, 'ب'], [/^p/, 'ب'], [/^t/, '[تط]'], [/^j/, '[جغ]'], [/^g/, '[جغق]'], [/^d/, '[دض]'], [/^r/, 'ر'], [/^z/, '[زظذ]'], [/^s/, '[سصث]'], [/^f/, 'ف'], [/^v/, '[فڤ]'],
  [/^q/, '[قك]'], [/^k/, '[كق]'], [/^c/, '[كقس]'], [/^x/, '[كق][سص]'], [/^l/, 'ل'], [/^m/, 'م'], [/^n/, 'ن'], [/^h/, '[هح]'], [/^w/, 'و'], [/^y/, 'ي']];
/** Latin word -> its consonants as Arabic classes, or null when it carries fewer than `min`. */
function latinToArabic(word: string): { re: string; n: number } | null {
  let w = word.toLowerCase().replace(/[^a-z]/g, '').replace(/(.)\1+/g, '$1');
  if (!w) return null;
  const al = /^(?:al|el)$/.test(w);
  if (al) return { re: '', n: 0 };
  let re = AR_V, n = 0;
  while (w) {
    if (/^[aeiouy]/.test(w) && !(n === 0 && /^y[aeiou]/.test(w))) { w = w.slice(1); continue; }
    const hit = LAT2AR.find(([r]) => r.test(w));
    if (!hit) { w = w.slice(1); continue; }
    re += `${hit[1]}+${AR_V}`; n++; w = w.replace(hit[0], '');
  }
  return n ? { re, n } : null;
}
const AR2LAT: Record<string, string> = { 'ب': 'b', 'ت': 't', 'ث': '(?:th|s|t)', 'ج': '(?:j|g|dj)', 'ح': 'h', 'خ': '(?:kh|h|k)', 'د': 'd', 'ذ': '(?:dh|z|th|d)', 'ر': 'r', 'ز': 'z',
  'س': 's', 'ش': '(?:sh|ch)', 'ص': 's', 'ض': '(?:dh|d)', 'ط': 't', 'ظ': '(?:dh|z|d)', 'غ': '(?:gh|g)', 'ف': '(?:f|ph)', 'ق': '(?:q|k|g)', 'ك': '(?:k|c|ck)', 'ل': 'l', 'م': 'm',
  'ن': 'n', 'ه': 'h', 'و': 'w', 'ي': 'y' };
const LAT_V = "[aeiouyAEIOUY'’]*";
/** Arabic word -> a case-blind Latin pattern of its consonants (و / ي between letters are vowels too). */
function arabicToLatin(word: string): { re: string; n: number } | null {
  let w = word.replace(/[ً-ٟـ]/g, '');
  let pre = '';
  if (/^ال/.test(w) && w.length > 3) { pre = "(?:[Aa][Ll]|[Ee][Ll])?[\\s'’-]?"; w = w.slice(2); }
  let re = LAT_V, n = 0;
  for (const [i, c] of [...w].entries()) {
    if (/[اأإآءئؤعىة]/.test(c) || (c === 'ه' && i === [...w].length - 1)) continue;
    if ((c === 'و' || c === 'ي') && i > 0) { re += `(?:${c === 'و' ? '[OoUuWw]' : '[IiYyEe]'})*${LAT_V}`; continue; }
    const m = AR2LAT[c]; if (!m) continue;
    re += `(?:${ciSrc(m)})+${LAT_V}`; n++;
  }
  return n ? { re: pre + re, n } : null;
}
/** The name as the other script writes it: all its words in order; one word only with four consonants or more. */
function otherScriptRe(words: string[]): string | null {
  if (!words.length || words.length > 5 || words.some((w) => /\d/.test(w))) return null;
  const ar = words.every((w) => /[ء-ي]/.test(w)), lat = words.every((w) => /^[A-Za-z'’-]+$/.test(w));
  if (!ar && !lat) return null;
  const parts = words.map((w) => (ar ? arabicToLatin(w) : latinToArabic(w)));
  if (parts.some((p) => p == null)) return null;
  const real = parts.filter((p) => p!.n > 0);
  const cons = real.reduce((a, p) => a + p!.n, 0);
  if (!real.length || (real.length === 1 && cons < 4)) return null;
  // "Al Mansoori" is one Arabic word, "المنصوري": an "Al" is an optional ال joined to the next word.
  let src = ''; let joinAl = false;
  for (const p of parts) {
    if (p!.n === 0) { joinAl = true; continue; }
    src += (src ? (ar ? "[\\s-]+" : '\\s+') : '') + (joinAl && !ar ? '(?:ال)?' : '') + p!.re; joinAl = false;
  }
  return src;
}

/**
 * A known name, matched whole with any separators and suffix. With `fragments` (only for a party's OWN text, never
 * for other suppliers' quotes), also by two consecutive words of it when one of them carries a DIGIT — a code no
 * trade wording has ("Oasis Golden UP8 series"). Review of #1838, item 2: fragments of ordinary words ("Building
 * Materials", "Ready Mix", "Air Conditioning", "Fire Safety") stripped 8 of 10 trade-named firms' own scope.
 * 3 Nov 2026: the old companyRe stripped `co` with no word end, so "Consultants" became "nsultants" and "ZZ …
 * Engineering Consultants LLC" was never matched; and its `\b` never fired before an Arabic letter.
 * 13 Nov 2026 (anonymity audit, REPORT_C L1 / L2 / L3; narrowed by the independent review the same day, which measured 14
 * of 24 supplier names damaging their own quotation): also, always, the full name written in the other script when it
 * holds a distinctive word; a demo account's name without its "ZZ DEMO". With `fragments`, also: the name without the
 * trade words it ends in, only in Title Case or capitals and only when a distinctive word is left ("Desert Brush" of
 * Desert Brush Painting LLC; "gulf steel sections" is scope), and the firm's initials only as its quotation register
 * ("FT-Q-2026-0457"). Initials elsewhere ("UPS", "ST-37") and house brands ("Falcolux") are the second reader's.
 */
const NAME_CACHE = new Map<string, RegExp | null>();
/** Cached per name (independent review of 13 Nov 2026: rebuilt per BOQ cell, 38 ms per 1,200 cells). The regex is global:
 *  callers use it with String.replace, which resets lastIndex. */
export function knownNameRe(name: unknown, opts: { fragments?: boolean } = {}): RegExp | null {
  const k = (opts.fragments ? 'f:' : 'w:') + String(name || '');
  if (NAME_CACHE.has(k)) { const re = NAME_CACHE.get(k)!; if (re) re.lastIndex = 0; return re; }
  if (NAME_CACHE.size > 2000) NAME_CACHE.clear();
  const re = buildNameRe(name, opts); NAME_CACHE.set(k, re); return re;
}
function buildNameRe(name: unknown, opts: { fragments?: boolean }): RegExp | null {
  const raw = String(name || '');
  const variants = [raw];
  const undemo = raw.replace(DEMO_PREFIX, '');
  if (undemo !== raw && undemo.trim()) variants.push(undemo);
  const alts: string[] = [];
  // Adversarial re-review of #1838: "&" / "and" between the words ("Cheque payable to Al Noor & Sons only" kept the name
  // of "Al Noor & Sons Trading LLC"); and a core made only of trade words ("Insulation Trading LLC", "Steel Trading
  // LLC") is matched only WITH its suffix, or "GI ductwork with insulation" lost its insulation at save.
  const sep = `(?:\\s*(?:&|${ciSrc('and')})\\s*|[\\s.,_-]*)`;
  const suffix = ciSrc(CO_SUFFIX);
  for (const v of variants) {
    const base = v.replace(new RegExp('(?<![A-Za-z])' + CO_SUFFIX, 'gi'), ' ').replace(/[^A-Za-z0-9؀-ۿ ]+/g, ' ').trim();
    const words = base.split(/\s+/).filter((w) => w.length > 1);
    if (!words.length || base.replace(/\s+/g, '').length < 3) continue;
    const tradeOnly = words.every((w) => TRADE_WORDS.has(w.toLowerCase()));
    alts.push(words.map((w) => ciSrc(rxEsc(w))).join(sep) + `(?:${sep}${suffix})${tradeOnly ? '+' : '*'}`);
    if (opts.fragments) for (let i = 0; i + 1 < words.length; i++) if (/\d/.test(words[i]) || /\d/.test(words[i + 1])) alts.push(ciSrc(rxEsc(words[i])) + sep + ciSrc(rxEsc(words[i + 1])));
    // The other script only for a name with a distinctive word ("Falcon", "Haddad"), never a trade or a common word.
    const core = words.filter((w) => !/^(?:zz|demo)$/i.test(w));
    const other = core.some(distinctive) ? otherScriptRe(core) : null;
    if (other) alts.push(other);
  }
  if (opts.fragments) {
    const own = (variants[variants.length - 1]).replace(/[^A-Za-z0-9؀-ۿ&'’ ]+/g, ' ').split(/\s+/).filter((w) => w && w !== '&' && !/^and$/i.test(w) && !LEGAL_WORD.test(w));
    // The name without the trade words it ends in: two words at least, not all of them trade words, in its own case.
    const short = [...own];
    while (short.length > 2 && SHORT_TRADE.has(short[short.length - 1].toLowerCase())) short.pop();
    if (short.length >= 2 && short.length < own.length && /^[A-Za-z]/.test(short[0]) && short.some(distinctive)) {
      const title = short.map((w) => w[0].toUpperCase() + w.slice(1)).map(rxEsc).join('[\\s-]+');
      alts.push(title, short.map((w) => rxEsc(w.toUpperCase())).join('[\\s-]+'));
    }
    // The firm's initials only as its own quotation register ("FT-Q-2026-0457", "FT/QTN/2026/12"): never "ST-37", "UPS",
    // "DC-12V". A house brand built on the name ("Falcolux") is the second reader's (independent review of 13 Nov 2026).
    const initials = own.filter((w) => /^[A-Za-z]/.test(w) && !/^(?:al|el|bin|the|of)$/i.test(w)).map((w) => w[0].toUpperCase()).join('');
    if (initials.length >= 2 && initials.length <= 4) alts.push(`${initials}[\\-/](?:[A-Z]{1,4}[\\-/])?(?:(?:19|20)\\d{2}[\\-/]\\d{1,6}|█)`);
  }
  if (!alts.length) return null;
  // A demo prefix in front of any form goes with it ("ZZ DEMO Cedar Line signature profile" -> "the supplier signature profile").
  const demo = `(?:${ciSrc('zz')}[\\s_-]+(?:${ciSrc('demo')}[\\s_-]+)?)?`;
  try { return new RegExp(`(?<!${W})${demo}(?:${alts.join('|')})(?!${W})`, 'g'); } catch (_e) { return null; }
}
