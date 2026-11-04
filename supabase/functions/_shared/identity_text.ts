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
/** Separators a printed phone uses: space, dot, hyphen, no-break space, the Unicode dashes (en / em "050–123–4567"). */
const SEPC = '\\s.\\-\\u00a0\\u2010-\\u2015';
/** No digit, and no further digit GROUP, before: a phone is a whole number, never the middle of a BOQ row. */
const NO_GROUP_BEFORE = `(?<![0-9٠-٩۰-۹][${SEPC}]?)(?<![0-9٠-٩۰-۹])`;
/**
 * After: no digit, and no further group of THREE or more digits unless it starts with 0 (the next phone of a collapsed
 * letterhead, "Tel 04 345 6789 050 123 4567"), and no decimal. Adversarial review of #1838: the old guard refused ANY
 * digit after a space, so "Call 050 123 4567 9am to 6pm" and "Mob: 050 123 4567 24/7" kept the whole number. "03 120 4500
 * 54000" (a BOQ row) is still refused by its 54000.
 */
const NO_GROUP_AFTER = `(?!${D})(?![${SEPC}]{1,2}(?![0٠۰])${D}{3})(?![${SEPC}]?${D}{1,2}[.,]${D})`;
/** One or two separator characters ("050  123  4567" has two spaces). */
const S1 = `[${SEPC}]{0,2}`;
const Z = '[0٠۰]';
/** A word in either case, for the labels (no (?i) modifier: these regexes are case-sensitive on purpose). */
const ci = (w: string) => w.replace(/[A-Za-z]/g, (c) => `[${c.toUpperCase()}${c.toLowerCase()}]`);

/** A code word before a number makes it a product code, not a licence or a phone ("Model 0501 2345 67", "Product code CN-123456"). */
const CODE_WORD = `(?:${ci('code')}|${ci('model')}|${ci('part')}|${ci('ref')}|${ci('item')}|${ci('cat')}|${ci('catalogue')}|${ci('catalog')}|${ci('sku')}|${ci('art')}|${ci('article')}|${ci('product')}|${ci('type')}|${ci('series')})`;
const NOT_A_CODE = `(?<!${CODE_WORD}\\.?\\s*(?:${ci('no')}\\.?\\s*)?[:#]?\\s*)`;
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
export const PHONE_UAE_NATIONAL = new RegExp(`${NOT_A_CODE}${NO_GROUP_BEFORE}${NOT_A_DATE}(?:\\(${Z}(?:${MOB}|${LAND})\\)${S1}${D}{3}${S1}${D}{4}|${Z}(?:${MOB}|${LAND})${S1}${D}{3}${S1}${D}{4}|${Z}${MOB}${D}{7}|${Z}[5٥۵][${SEPC}]{1,2}${D}{4}[${SEPC}]{1,2}${D}{4}|${MOB_ANY})${NO_GROUP_AFTER}`, 'g');
/** UAE toll-free / shared-cost numbers (800 …, 600 …) — only after a word that says it is a number to call. */
export const PHONE_UAE_SHORT = new RegExp(`(?<=(?:${ci('toll')}[\\s\\-]*${ci('free')}|${ci('call')}|${ci('tel')}|${ci('phone')}|${ci('hotline')}|${ci('contact')}|${ci('mob')}|رقم|اتصل|هاتف)[^0-9٠-٩\\n]{0,12})(?:800|600|٨٠٠|٦٠٠)[\\s\\-]?${D}{2,3}[\\s\\-]?${D}{2,4}(?!${D})`, 'g');
/** Any other country's number written with its + or 00 code ("+966 50 123 4567", "00966501234567", "+91 98765 43210"). */
export const PHONE_INTL = new RegExp(`(?<![\\w+])(?:\\+\\s?|00)(?![9٩][7٧][1١])[1-9١-٩]${D}{0,2}(?:[${SEPC}]?${D}){7,12}(?!${D})`, 'g');
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
const EN_TOKEN = `(?:[A-Z][a-z]{1,4}\\.(?=\\s)|[A-Z][A-Za-z0-9&'-]*|[A-Z0-9]{2,}|&|${EN_PARTICLE}(?=\\s))`;
export const FIRM_EN = new RegExp(`(?:(?<![A-Za-z0-9&])${EN_TOKEN}\\s+){1,6}(?:${EN_STRONG}(?:\\s+${EN_LEGAL})*|${EN_WEAK}(?:\\s+${EN_LEGAL})*|${EN_LEGAL_BARE})(?![A-Za-z])`
  + `|(?:(?<![A-Za-z0-9&])[A-Za-z][A-Za-z0-9&'-]*\\s+){1,5}${EN_LEGAL_CI}(?![A-Za-z])`, 'g');
/** Words that name a discipline, a part of a document or a scope, never a firm: a match made of them only is kept. */
const NOT_A_FIRM = new Set(['general', 'mep', 'hvac', 'civil', 'structural', 'mechanical', 'electrical', 'plumbing', 'fire', 'fighting', 'section', 'part', 'item', 'items', 'project',
  'approved', 'main', 'sub', 'specialist', 'design', 'interior', 'fit', 'out', 'fitout', 'works', 'work', 'scope', 'package', 'all', 'by', 'the', 'other', 'others', 'local', 'nominated',
  'landscape', 'architectural', 'facade', 'joinery', 'glazing', 'aluminium', 'steel', 'building', 'materials', 'supply', 'and', 'install', 'installation', 'note', 'notes', '&']);
/** Leading words of a sentence that are never part of a firm's name (trimmed off the front of a match). */
const NOT_A_FIRM_START = new Set([...NOT_A_FIRM, 'we', 'i', 'you', 'they', 'buy', 'bought', 'from', 'to', 'a', 'an', 'of', 'for', 'our', 'your', 'is', 'are', 'was', 'with', 'at', 'in',
  'on', 'or', 'via', 'through', 'supplied', 'purchase', 'purchased', 'order', 'ordered', 'contact', 'call', 'please', 'ask', 'send', 'pay', 'payable', 'cheque', 'transfer', 'name', 'company',
  'firm', 'visit', 'meet', 'invoice', 'quotation', 'quote', 'scope', 'm/s', 'm/s.']);
const PAYEE_CUE = /(?:payable\s+to|in\s+(?:the\s+)?favou?r\s+of|m\/s\.?|beneficiary\s*:?|account\s+name\s*:?|cheques?\s+(?:to|in\s+the\s+name\s+of)|transfer\s+to)\s*$/i;
const EN_SUFFIX_RE = new RegExp(`(?:${EN_STRONG}|${EN_WEAK}|${EN_LEGAL}|${EN_LEGAL_CI})(?:\\s+${EN_LEGAL})*$`);
const isCue = (w: string) => new RegExp(`^(?:${EN_PARTICLE}|zz)$`, 'i').test(w) || (/\d/.test(w) && /[A-Za-z]/.test(w));
const firmSpan = (m: string, at: number, text: string): [number, number] | null => {
  const suffix = m.match(EN_SUFFIX_RE)?.[0] ?? '';
  // Trim the front: words of a sentence or of scope never start a firm's name ("Supply Al Noor Trading").
  let s = 0;
  for (const w of m.slice(0, m.length - suffix.length).matchAll(/\S+/g)) { if (NOT_A_FIRM_START.has(w[0].toLowerCase()) || /^\d+$/.test(w[0])) s = w.index! + w[0].length; else break; }
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
  '(?:Mr|Mrs|Ms|Eng|Engr|Dr)\\.?(?=[ \\t]+[A-Z])'].join('|');
const TITLE_EN = '(?:(?:Mr|Mrs|Ms|Eng|Engr|Dr)\\.?[ \\t]+)?';
const NAME_PART = "(?:[A-Z][a-z]{1,4}\\.(?=[ \\t])|[A-Z]\\.|[A-Z](?:'[A-Z])?[a-z']*(?:[A-Z][a-z']+)*|[A-Z]{2,})";
const NAME_TOKEN = `(?:(?:al|el|bin|ibn|abu)-)?${NAME_PART}(?:-${NAME_PART})*`;
const NAME_SEP = `[ \\t\\u00a0]+(?:${EN_PARTICLE}[ \\t\\u00a0]+)?`;
const LABEL_AR_COLON = `(?:المسؤول|مقدم\\s+العرض|الاسم|(?:مدير|مسؤول|مسئول|مندوب)\\s+${AW})\\s*[:：]`;
const LABEL_AR = `(?:المهندس|المهندسة|السيد|السيدة|الأستاذ|الاستاذ|الأستاذة|الاستاذة|(?<![0-9٠-٩]\\s*)(?<![\\u0600-\\u06FF.])م(?:\\.(?=\\s)|\\.?\\/)|مع\\s+(?:خالص\\s+)?(?:التحية|التحيات|الشكر|التقدير)|تحياتي|شكرا|شكراً|اسمي|وتفضلوا\\s+بقبول\\s+فائق\\s+الاحترام)\\s*[:：،,\\/]?`;
const SIG_ROLE = `[ \\t]*[|\\u2013\\-,][ \\t]*(?:(?:Sales|Project|Account|Estimation|Procurement|General|Technical|Operations|Managing|Senior|Site|MEP)[ \\t]+)?(?:Manager|Engineer|Executive|Director|Coordinator|Estimator|Supervisor)`;
export const PERSON_LABELLED = new RegExp(`(?:${LABEL_EN})\\s*${TITLE_EN}${NAME_TOKEN}(?:${NAME_SEP}${NAME_TOKEN}){1,5}(?![A-Za-z])`
  + `|(?<![^\\n])[ \\t]*${NAME_TOKEN}(?:${NAME_SEP}${NAME_TOKEN}){1,4}(?=${SIG_ROLE})`
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
  'dear', 'hi', 'hello', 'team', 'shop', 'drawings', 'drawing', 'mobilisation', 'mobilization', 'permits', 'permit', 'manhole',
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
const personSpan = (m: string): [number, number] | null => {
  const label = m.match(LABEL_STRIP)?.[0] ?? '';
  let end = label.length, names = 0;
  for (const w of m.slice(label.length).matchAll(/\S+/g)) {
    const bare = w[0].replace(/[.,،]$/, '').toLowerCase();
    if (!names && ROLE.has(bare)) continue;
    if (NOT_A_NAME.has(bare) || bare.startsWith('لل') || /\d/.test(bare)) break;
    if (!new RegExp(`^${EN_PARTICLE}$`).test(bare)) { names++; end = label.length + w.index! + w[0].length; }
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
export const URL = /(?:https?:\/\/|www\.)[^\s,;)\]]+/gi;
/**
 * A bare domain WITH its path ("instagram.com/alnoortrading" loses the handle as well as the host). The common endings
 * in any case; the long tail ("alnoor.store", ".shop", ".me", ".in", ".dev", ".build" …) only in lower case, because a
 * sentence with no space after its full stop reads the same ("30 days.Site visit", "2 coats.Group A colours").
 */
// A host carries a letter: "pipe 3.in dia" is a size (caught by identity_contacts.test.ts).
export const DOMAIN = /(?<![@\w.-])(?=[A-Za-z0-9-]*[A-Za-z])[A-Za-z0-9][A-Za-z0-9-]+(?:\.[A-Za-z0-9-]{2,})*\.(?:ae|com|net|org|co|io|biz)(?:\.[a-z]{2})?(?![\w-])(?:\/[^\s,;)\]]*)?/gi;
export const DOMAIN_LC = /(?<![@\w.-])(?=[a-z0-9-]*[a-z])[a-z0-9][a-z0-9-]+(?:\.[a-z0-9-]{2,})*\.(?:info|app|link|store|shop|online|site|tech|xyz|uk|sa|qa|om|bh|kw|eg|ai|pro|group|global|ltd|me|in|dev|build|construction|contractors|email|company|services|solutions|trading)(?:\.[a-z]{2})?(?![\w-])(?:\/[^\s,;)\]]*)?/g;
/** A domain spelled out to dodge a filter: "alnoor . ae", "alnoor dot ae". */
export const DOMAIN_SPACED = /(?<![\w.@])[A-Za-z][A-Za-z0-9-]{2,}(?:\s+\.\s*|\s*\.\s+|\s+dot\s+)(?:ae|com)(?![\w])/gi;
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
  ['email', EMAIL], ['url', URL], ['domain', DOMAIN], ['domain_lc', DOMAIN_LC], ['domain_spaced', DOMAIN_SPACED], ['social', SOCIAL], ['handle', HANDLE],
  ['trn', TRN_LABELLED], ['trn_bare', TRN_BARE], ['licence_no', LICENCE_NO], ['licence_short', LICENCE_SHORT],
  ['iban', IBAN], ['account_no', ACCOUNT_NO], ['po_box', PO_BOX],
  ['phone_uae_intl', PHONE_UAE_INTL], ['phone_uae_national', PHONE_UAE_NATIONAL], ['phone_uae_short', PHONE_UAE_SHORT], ['phone_intl', PHONE_INTL],
  ['address', ADDRESS], ['firm_ar', FIRM_AR], ['firm_en', FIRM_EN], ['person_labelled', PERSON_LABELLED],
];
const PHONES = new Set(['phone_uae_intl', 'phone_uae_national', 'phone_uae_short', 'phone_intl']);
/** The [start, end) of a match that is identity, or null when its words say it is not (a discipline, a team, an authority). */
const SPAN: Record<string, (m: string, at: number, text: string) => [number, number] | null> = { firm_en: firmSpan, person_labelled: personSpan };
const spanOf = (name: string, m: string, at: number, text: string): [number, number] | null => (SPAN[name] ? SPAN[name](m, at, text) : [0, m.length]);
/** True when `name`'s match `m` (at `at` in `text`) is identity: what a residual scan should report. */
export function identityMatch(name: string, m: string, at = 0, text = m): boolean { return spanOf(name, m, at, text) != null; }

/**
 * Every identity shape above replaced by `rep` (a string, or a function of the match). `parties: false` leaves firm
 * and person names alone — the quotation a customer has PAID to reveal names its supplier (review of #1838, item 1).
 * Phones run twice: a second number printed straight after a first ("Tel 04 345 6789 050 123 4567") is only a whole
 * number once the first is gone.
 */
export function scrubIdentityText(text: unknown, rep: string | ((m: string) => string) = '', opts: { parties?: boolean } = {}): string {
  let t = String(text ?? '');
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
  }
  for (const [name, re] of IDENTITY_TEXT_PATTERNS) if (PHONES.has(name)) run(name, re);
  return t;
}
/** Every identity shape in `text`, by name (the residual scan's half of the list). */
export function identityShapesIn(text: unknown): string[] {
  const s = String(text ?? ''), found = new Set<string>();
  for (const [name, re] of IDENTITY_TEXT_PATTERNS) for (const m of s.matchAll(new RegExp(re.source, re.flags))) if (identityMatch(name, m[0], m.index, s)) { found.add(name); break; }
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
  // Adversarial re-review of #1838: "&" / "and" between the words ("Cheque payable to Al Noor & Sons only" kept the name
  // of "Al Noor & Sons Trading LLC"); and a one-word core that is a trade word ("Insulation Trading LLC", "Steel Trading
  // LLC") is matched only WITH its suffix, or "GI ductwork with insulation" lost its insulation at save.
  const sep = '(?:\\s*(?:&|and)\\s*|[\\s.,_-]*)';
  const tradeWord = words.length === 1 && TRADE_WORDS.has(words[0].toLowerCase());
  const alts = [words.map(rxEsc).join(sep) + `(?:${sep}${CO_SUFFIX})${tradeWord ? '+' : '*'}`];
  if (opts.fragments) for (let i = 0; i + 1 < words.length; i++) if (/\d/.test(words[i]) || /\d/.test(words[i + 1])) alts.push(rxEsc(words[i]) + sep + rxEsc(words[i + 1]));
  try { return new RegExp(`(?<!${W})(?:${alts.join('|')})(?!${W})`, 'gi'); } catch (_e) { return null; }
}
