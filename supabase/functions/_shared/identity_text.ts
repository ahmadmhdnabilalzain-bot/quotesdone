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

/**
 * UAE numbers after +971 / 00971 / 971 — the code in brackets too, "(+971)" — and an optional (0): an area (2-9) or a
 * mobile prefix (5X), then 7 digits. Second review of #1838: "Tel (+971) 50 123 4567" passed every scrubber.
 */
export const PHONE_UAE_INTL = new RegExp(`${NO_GROUP_BEFORE}(?:\\(\\s?)?(?:\\+\\s?|00\\s?)?[9٩۹][7٧۷][1١۱](?:\\s?\\))?${S1}(?:\\(\\s?${Z}\\s?\\)${S1})?(?:[5٥۵]${D}|[2-9٢-٩۲-۹])(?:${S1}${D}){7}${NO_GROUP_AFTER}`, 'g');
/**
 * National numbers in the groupings UAE documents print: 0X XXX XXXX, 0XXXXXXXX, (04) XXX XXXX, 05X XXX XXXX,
 * 05XXXXXXXX, (050) XXX XXXX, 05X.XXX.XXXX, 05 XXXX XXXX. Only real prefixes: landline 02/03/04/06/07/09, mobile
 * 050/052/054/055/056/058. A leading 0 followed by anything else ("01 25 450.00", "075 110 160") is not a phone.
 * Second review of #1838: a 05X mobile in ANY layout — one space, slash or dash allowed between any two of its ten
 * digits ("050 12 34 567", "050/1234567", "0 5 0 1 2 3 4 5 6 7"). Not a dot: "05.06.2026 12" is a date. The ten digits
 * must stand alone (NO_GROUP_*), so "UPVC pipe dia 050 075 110 160" — 050 then eleven more digits — is not a phone.
 */
const LAND = '[2-4٢-٤۲-۴6-7٦-٧۶-۷9٩۹]', MOB = '[5٥۵][0٠۰2٢۲4٤۴5٥۵6٦۶8٨۸]';
const MOB_ANY = `${Z}[\\s/\\-]?[5٥۵][\\s/\\-]?[0٠۰2٢۲4٤۴5٥۵6٦۶8٨۸](?:[\\s/\\-]?${D}){7}`;
export const PHONE_UAE_NATIONAL = new RegExp(`${NO_GROUP_BEFORE}(?:\\(${Z}(?:${MOB}|${LAND})\\)\\s?${D}{3}[\\s.\\-]?${D}{4}|${Z}(?:${MOB}|${LAND})[\\s.\\-]?${D}{3}[\\s.\\-]?${D}{4}|${Z}${MOB}${D}{7}|${Z}[5٥۵][\\s.\\-]${D}{4}[\\s.\\-]${D}{4}|${MOB_ANY})${NO_GROUP_AFTER}`, 'g');
/** IBAN: AE and 21 digits, spaced or dashed in fours or not ("AE07-0331-2345-6789-0123-456"); any other country's after a label. */
export const IBAN = new RegExp(`\\b(?:${ci('iban')}\\s*[:#.]?\\s*)?(?:AE|ae)[\\s\\-]?\\d{2}(?:[\\s\\-]?\\d){19}\\b|\\b${ci('iban')}\\s*[:#.]?\\s*[A-Z]{2}\\d{2}(?:[\\s\\-]?[A-Z0-9]){10,30}\\b`, 'g');
/** Bank account numbers after a label. */
export const ACCOUNT_NO = new RegExp(`\\b(?:${ci('a/c')}|${ci('account')}|${ci('acct')})\\.?\\s*(?:${ci('no')}\\.?|${ci('number')}|#)?\\s*[:#.]?\\s*${D}(?:[\\s\\-]?${D}){7,20}(?!${D})`, 'g');
/** P.O. Box in English ("P.O. Box", "POB", "Post Box", "Post Office Box") and Arabic (ص.ب, صندوق بريد), any digit script. */
export const PO_BOX = new RegExp(`\\b(?:[Pp]\\.?\\s?[Oo]\\.?\\s?${ci('box')}|${ci('pob')}|${ci('post')}\\s+(?:${ci('office')}\\s+)?${ci('box')})\\s*[:#.]?\\s*${D}{3,7}(?!${D})|ص\\s?\\.?\\s?ب\\s*\\.?\\s*[:：]?\\s*${D}{3,7}(?!${D})|صندوق\\s+بريد\\s*[:：]?\\s*${D}{3,7}(?!${D})`, 'g');
/**
 * Licence numbers as UAE documents abbreviate them. "CN-974461", "CN 1234567", "CN1234567": the DED format, six or
 * seven digits — SECOND review of #1838: the first loosening kept six-digit CN numbers because a product code can be
 * "CN-123456", and that reopened the leak this file's header measured ("CN-974461"). A product code is told apart by
 * what comes BEFORE it (code / model / part / ref / item / cat), never by its digit count. "T.L. No. 273158" / "TL#
 * 273158" / "DED No: 273158" / "Lic. No. 1234567" (the abbreviation WITH its number marker); "licence No. 780159"
 * (the word WITH its marker); "Trade licence 780159" / "D.E.D. Licence 780159" (the word after a trade, commercial,
 * business or DED qualifier). A bare "licence" and a number is a price as often as a licence: "BMS software licence
 * 12500.00" and "Annual licence 15000 per year" are kept, and no licence number runs on into ".00".
 */
const NOT_A_CODE = `(?<!(?:${ci('code')}|${ci('model')}|${ci('part')}|${ci('ref')}|${ci('item')}|${ci('cat')})\\.?\\s*(?:${ci('no')}\\.?\\s*)?[:#]?\\s*)`;
const LIC_END = `(?![.,]?${D})`;
const LIC_QUAL = `(?:${ci('trade')}|${ci('commercial')}|${ci('business')}|${ci('industrial')}|${ci('professional')}|DED|D\\.E\\.D\\.?)\\s*`;
export const LICENCE_SHORT = new RegExp(`${NOT_A_CODE}\\bCN[\\s\\-]?${D}{6,7}(?!${D})|\\b(?:T\\.?L\\.?|DED|D\\.E\\.D\\.?|${ci('lic')}\\.?)\\s*(?:${ci('licen')}[cs]e\\s*)?(?:${ci('no')}\\.?|#|:)\\s*[:#]?\\s*${D}{5,8}${LIC_END}|(?:\\b${LIC_QUAL}${ci('licen')}[cs]e\\s*(?:${ci('no')}\\.?|#|:)?|\\b${ci('licen')}[cs]e\\s*(?:${ci('no')}\\.?|#|:))\\s*(?:(?:CN|T\\.?L\\.?)[\\s\\-]?)?${D}{5,8}${LIC_END}`, 'g');
/**
 * A firm named in Arabic. Three shapes (second review of #1838, each measured passing before):
 *   1. شركة / مؤسسة, its name, and what closes a firm's name — an activity (للمقاولات, للتجارة, للخدمات الفنية …) or a
 *      legal form (ذ.م.م, ش.ذ.م.م, م.م.ح, ش.م.ع, ش.م.خ).
 *   2. A legal form is identity ON ITS OWN, with no شركة: "النور للمقاولات ذ.م.م", and digits are part of a name that
 *      ends in one ("شركة النور ٢٠٠٠ للمقاولات ذ.م.م"). Its words are the name's kind (ال… / لل… / a number / شركة …);
 *      one plain word may lead ("كريم للتجارة ذ.م.م") unless it is a preposition ("من قبل", "عن طريق").
 *   3. شركة / مؤسسة and a proper noun (ال + word) with no activity: "شركة النور الذهبية", "مؤسسة النور". Not when that
 *      noun is generic: "شركة التأمين تتحمل التكاليف" is the insurer, whoever it is.
 * Never after an adjective that says WHAT KIND of firm, not WHICH: "عن طريق شركة معتمدة للصيانة", "بواسطة شركة
 * متخصصة للعزل المائي". Never "الشركة": "الشركة المصنعة" is the manufacturer. "مكتب خشبي مقاس ١٢٠×٦٠" is an office desk.
 */
const AL_ = '[\\u0621-\\u063A\\u0641-\\u064A\\u0671-\\u06D3]';
const AW = `${AL_}+`;
const AR_END = `(?!${AL_})`;
const AR_START = `(?<!${AL_})`;
// Its letters always apart (a dot or a space between): written together, ذمم is a word (receivables, "ذمم دائنة").
const AR_LEGAL = `(?:ش[.\\s]\\s?ذ[.\\s]\\s?م[.\\s]\\s?م\\.?|ذ[.\\s]\\s?م[.\\s]\\s?م\\.?|م[.\\s]\\s?م[.\\s]\\s?ح\\.?|ش[.\\s]\\s?م[.\\s]\\s?[عخ]\\.?)${'(?![\\u0621-\\u064A])'}`;
const FIRM_WORD = '(?:شركة|شركه|مؤسسة|مؤسسه)';
const AR_KIND_ADJ = `(?:معتمد[ةه]?|متخصص[ةه]?|مختص[ةه]?|مرخص[ةه]?|مؤهل[ةه]?|محلي[ةه]?|أجنبي[ةه]?|اجنبي[ةه]?|وطني[ةه]?|عالمي[ةه]?|أخرى|اخرى|كبرى|رائد[ةه]?|مسجل[ةه]?)${AR_END}`;
const AR_GENERIC = `(?:التأمين|التامين|الشحن|النقل|الصيانة|الصيانه|المقاولات|الكهرباء|المياه|الاتصالات|الطيران|التوريد|المصنعة|المصنعه|المنفذة|المنفذه|الموردة|المورده|المذكورة|المذكوره|المعنية|المعنيه|المختصة|المعتمدة|المتخصصة|القابضة|الأم|الام|المالكة|الاستشارية|الهندسية|العقارية|التطوير|المقاول|المورد|الحكومية|الخاصة)${AR_END}`;
const AR_PREP = `(?:من|قبل|عن|طريق|بواسطة|في|إلى|الى|على|مع|و|تم|يتم|سيتم|لدى|عند|وفق|حسب|لصالح|باسم|او|أو)${AR_END}`;
const AR_NAME_PART = `(?:${FIRM_WORD}|ال${AW}|لل${AW}|${D}+|بن|ابن|أبو|ابو)`;
export const FIRM_AR = new RegExp(`${AR_START}[وبل]?${FIRM_WORD}\\s+(?!${AR_KIND_ADJ})(?:${AW}\\s+){0,5}?(?:لل${AW}(?:\\s+${AR_LEGAL}|\\s+${AW}(?:\\s+${AR_LEGAL})?)?|${AR_LEGAL})`
  + `|${AR_START}(?:(?!${AR_PREP})${AW}\\s+)?(?:${AR_NAME_PART}\\s+){1,5}${AR_LEGAL}`
  + `|${AR_START}[وبل]?${FIRM_WORD}\\s+(?!${AR_GENERIC}|${AR_KIND_ADJ})ال${AW}(?:\\s+(?!${AR_GENERIC})ال${AW}){0,2}`, 'g');
/**
 * A firm named in Latin letters: capitalised (or ALL-CAPS) words, then a firm suffix ("Al Waha Al Thahabi Trading",
 * "AL NOOR CONTRACTING CO.", "Al Noor & Sons Trading LLC", "Saif bin Darwish Contracting"). The suffix is Title-Case or
 * ALL-CAPS, never lowercase ("Our trading terms apply"). "Consultants" and "Interiors" name a firm only with a legal
 * suffix after them, or after Al / El / ZZ or a word carrying a digit: "Acoustic Consultants approval required",
 * "Kitchen Interiors package" and "Section 5: Hotel Lobby Interiors" are scope (second review of #1838).
 */
const tc = (w: string) => `(?:${w}|${w.toUpperCase()})`;
const EN_LEGAL = '(?:L\\.?L\\.?C\\.?|FZ-?LLC|FZE|FZCO|Est\\.|EST\\.|Co\\.|CO\\.?|Ltd\\.?|LTD\\.?)';
const EN_STRONG = `(?:${tc('Contracting')}|${tc('Trading')}|${tc('Technical')}\\s+${tc('Services')}|${tc('Establishment')})`;
const EN_WEAK = `(?:${tc('Engineering')}\\s+${tc('Consultants')}|${tc('Consultants')}|${tc('Interiors')})`;
const EN_PARTICLE = '(?:al|el|bin|bint|ibn|abu|bu)';
const EN_TOKEN = `(?:[A-Z][A-Za-z0-9&'-]*|[A-Z0-9]{2,}|&|${EN_PARTICLE}(?=\\s))`;
export const FIRM_EN = new RegExp(`(?:(?<![A-Za-z0-9&])${EN_TOKEN}\\s+){1,6}(?:${EN_STRONG}(?:\\s+${EN_LEGAL})?|${EN_WEAK}(?:\\s+${EN_LEGAL})?|(?:L\\.?L\\.?C\\.?|FZ-?LLC|FZE|FZCO))(?![A-Za-z])`, 'g');
/** Words that name a discipline, a part of a document or a scope, never a firm: a match made of them only is kept. */
const NOT_A_FIRM = new Set(['general', 'mep', 'hvac', 'civil', 'structural', 'mechanical', 'electrical', 'plumbing', 'fire', 'fighting', 'section', 'part', 'item', 'items', 'project',
  'approved', 'main', 'sub', 'specialist', 'design', 'interior', 'fit', 'out', 'fitout', 'works', 'work', 'scope', 'package', 'all', 'by', 'the', 'other', 'others', 'local', 'nominated',
  'landscape', 'architectural', 'facade', 'joinery', 'glazing', 'aluminium', 'steel', 'building', 'materials', 'supply', 'and', 'install', 'installation', 'note', 'notes', '&']);
const EN_SUFFIX_WORDS = new RegExp(`(?:${EN_STRONG}|${EN_WEAK}|${EN_LEGAL}|L\\.?L\\.?C\\.?|FZ-?LLC|FZE|FZCO)(?![A-Za-z])`, 'g');
const firmSpan = (m: string): string | null => {
  const words = m.replace(EN_SUFFIX_WORDS, ' ').trim().split(/\s+/).filter(Boolean);
  if (!words.some((w) => !/^\d+$/.test(w) && !NOT_A_FIRM.has(w.toLowerCase()) && !new RegExp(`^${EN_PARTICLE}$`).test(w))) return null;
  // A "Consultants" / "Interiors" with no legal form after it names a firm only after Al / El / ZZ or a coded word.
  if (new RegExp(`${EN_WEAK}$`).test(m) && !words.some((w) => /^(?:al|el|zz)$/i.test(w) || (/\d/.test(w) && /[A-Za-z]/.test(w)))) return null;
  return m;
};
/**
 * A street / building address: "Office 735, ZZ Palm IU8 Tower, Al Quoz Industrial Area 3, Dubai", "Building 5, Al
 * Quoz, Dubai", "Villa 23, Street 14, Jumeirah 1, Dubai" (a premises word, its number, a comma, up to four parts, an
 * emirate), and the Arabic "مكتب ١٢، برج الخليج، دبي". "Unit 12, Block B, Dubai" is a part of a project, kept.
 */
const EMIRATE_AR = '(?:دبي|الشارقة|الشارقه|أبوظبي|ابوظبي|أبو\\s+ظبي|ابو\\s+ظبي|عجمان|الفجيرة|الفجيره|رأس\\s+الخيمة|راس\\s+الخيمة|أم\\s+القيوين|ام\\s+القيوين|العين|الإمارات|الامارات)';
export const ADDRESS = new RegExp(`\\b(?:Office|Shop|Showroom|Warehouse|Suite|Flat|Building|Bldg\\.?|Villa|Tower)\\s*(?:No\\.?\\s*)?\\d{1,5}[A-Z]?\\s*,\\s*(?:[^,;\\n]{1,40},\\s*){0,4}(?:Dubai|Sharjah|Abu\\s+Dhabi|Ajman|Fujairah|Ras\\s+Al\\s+Khaimah|Umm\\s+Al\\s+Quwain|UAE)\\b|\\bAl\\s+[A-Z][a-z]+\\s+Industrial\\s+Area\\s*\\d*`
  + `|${AR_START}(?:مكتب|محل|معرض|مستودع|شقة|شقه|فيلا|مبنى|بناية|بنايه|برج)\\s*(?:رقم\\s*)?${D}{1,5}\\s*[،,]\\s*(?:[^،,;\\n]{1,40}[،,]\\s*){0,4}${EMIRATE_AR}${AR_END}`, 'g');
/**
 * A PERSON after a label. A label is "… by" (prepared / issued / signed / submitted / arranged by), a sign-off
 * ("Regards", "Best Regards", "Kind regards", "Thanks & Regards" — with a comma, a line break or nothing; "Thanks," /
 * "Sincerely," WITH their comma, so "Thanks for the opportunity" names nobody), an address line WITH its colon
 * ("Attn:", "Attention:", "Contact:", "Contact person:", "From:"), a role WITH its colon ("Sales Engineer:"), or a title
 * ("Mr.", "Eng.", "Dr."). The name: Title-Case, ALL-CAPS, hyphenated ("Al-Mansoori") or initials, with the lowercase
 * particles of Arabic names between them (al / el / bin / bint / ibn / abu: "Ahmed al Mansoori", "Ahmed bin Rashid").
 * The name runs on ONE line ("Best Regards\nAhmed Khan\nSales Manager" names Ahmed Khan, not "Ahmed Khan Sales").
 * personSpan then reads the words: the name stops at the first ordinary word, and fewer than two name words is nobody
 * — "Regards, Supply Chain Team", "Attention: Please note", "Mr. Client to provide", "Permit issued by Dubai
 * Municipality", "Signed by Both Parties", "Submitted by Tenderer Before Closing Date" name nobody.
 * Arabic: المسؤول: / مقدم العرض: WITH the colon; المهندس / المهندسة / السيد / السيدة / م. and a sign-off (مع التحية،)
 * with or without one ("المهندس أحمد المنصوري", "م. أحمد المنصوري", "مع التحية، أحمد المنصوري"), then 2-3 words.
 */
const LABEL_EN = [`(?:${ci('prepared')}|${ci('issued')}|${ci('signed')}|${ci('submitted')}|${ci('arranged')})\\s+${ci('by')}\\s*[:,]?`,
  `(?:(?:${ci('best')}|${ci('kind')}|${ci('warm')}|${ci('warmest')}|${ci('with')})\\s+)?${ci('regards')}\\s*,?`, `(?:${ci('thanks')}|${ci('sincerely')}|${ci('yours')}\\s+(?:${ci('faithfully')}|${ci('truly')}|${ci('sincerely')}))\\s*,`,
  `(?:${ci('attn')}\\.?|${ci('attention')}|${ci('contact')}(?:\\s+${ci('person')})?|[Ff]rom)\\s*:`,
  `(?:${ci('sales')}\\s+(?:${ci('engineer')}|${ci('manager')}|${ci('executive')})|${ci('project')}\\s+${ci('manager')})\\s*:`, '(?:Mr|Mrs|Ms|Eng|Engr|Dr)\\.'].join('|');
const TITLE_EN = '(?:(?:Mr|Mrs|Ms|Eng|Engr|Dr)\\.\\s*)?';
const NAME_PART = "(?:[A-Z][a-z']+|[A-Z]{2,}|[A-Z]\\.?)";
const NAME_TOKEN = `(?:(?:al|el|bin|ibn|abu)-)?${NAME_PART}(?:-${NAME_PART})*`;
const NAME_SEP = `[ \\t\\u00a0]+(?:${EN_PARTICLE}[ \\t\\u00a0]+)?`;
const LABEL_AR_COLON = '(?:المسؤول|مقدم\\s+العرض)\\s*[:：]';
const LABEL_AR = `(?:المهندس|المهندسة|السيد|السيدة|(?<![0-9٠-٩]\\s*)(?<![\\u0600-\\u06FF.])م\\.(?=\\s)|مع\\s+(?:خالص\\s+)?(?:التحية|التحيات|الشكر|التقدير)|وتفضلوا\\s+بقبول\\s+فائق\\s+الاحترام)\\s*[:：،,]?`;
export const PERSON_LABELLED = new RegExp(`(?:${LABEL_EN})\\s*${TITLE_EN}${NAME_TOKEN}(?:${NAME_SEP}${NAME_TOKEN}){1,3}(?![A-Za-z])`
  + `|${AR_START}(?:${LABEL_AR_COLON}|${LABEL_AR})\\s*${AW}(?:[ \\t]+${AW}){1,3}${AR_END}`, 'g');
/** Words that are not names (a sign-off to a team, a place, an authority, a party to a contract, an instruction). */
const NOT_A_NAME = new Set(['supply', 'chain', 'team', 'department', 'dept', 'office', 'site', 'please', 'note', 'client', 'contractor', 'consultant', 'consultants', 'engineer', 'manager',
  'ground', 'floor', 'first', 'second', 'roof', 'level', 'to', 'the', 'all', 'our', 'your', 'main', 'sales', 'project', 'procurement', 'accounts', 'management', 'customer', 'service',
  'services', 'support', 'technical', 'estimation', 'tender', 'tendering', 'mep', 'hvac', 'civil', 'design', 'operations', 'quality', 'safety', 'store', 'stores', 'warehouse', 'admin',
  // second review of #1838: places, authorities and the parties to a contract ("Permit issued by Dubai Municipality")
  'dubai', 'dhabi', 'sharjah', 'ajman', 'fujairah', 'ras', 'khaimah', 'umm', 'quwain', 'ain', 'uae', 'emirates', 'municipality', 'authority', 'electricity', 'water', 'defence', 'defense',
  'police', 'ministry', 'government', 'dewa', 'sewa', 'fewa', 'addc', 'aadc', 'rta', 'both', 'parties', 'party', 'tenderer', 'tenderers', 'bidder', 'bidders', 'owner', 'employer',
  'developer', 'before', 'after', 'closing', 'date', 'approval', 'works', 'board', 'committee', 'qs', 'hr', 'it', 'finance', 'legal', 'purchasing', 'logistics', 'and', 'or', 'of', 'for',
  'المشرف', 'المقاول', 'الرئيسي', 'المشروع', 'التركيب', 'الموقع', 'عن', 'على', 'من', 'في', 'المسؤول', 'الاستشاري', 'العميل', 'المقيم', 'المختص', 'المصمم', 'المنفذ', 'المعماري',
  'الإنشائي', 'الانشائي', 'الكهربائي', 'الميكانيكي', 'المدني', 'المراقب', 'المدير', 'مدير', 'الإدارة', 'الادارة', 'قسم', 'فريق', 'شركة', 'مؤسسة', 'إلى', 'الى', 'مع', 'أو', 'او',
  'تم', 'يتم', 'سيتم', 'يقوم', 'سيقوم', 'حسب', 'طول', 'عرض', 'ارتفاع', 'المخطط', 'التعاون', 'الجميع']);
const LABEL_STRIP = new RegExp(`^(?:(?:${LABEL_EN})\\s*${TITLE_EN}|(?:${LABEL_AR_COLON}|${LABEL_AR})\\s*)`);
/**
 * The part of a labelled match that names a person, or null when it names nobody: the label and the words up to the
 * first ordinary word (NOT_A_NAME, or an Arabic word starting لل — "for the …" is never part of a name), when at least
 * two name words are left. Particles (al / bin / …) ride along and never count.
 */
const personSpan = (m: string): string | null => {
  const label = m.match(LABEL_STRIP)?.[0] ?? '';
  let end = label.length, names = 0;
  for (const w of m.slice(label.length).matchAll(/\S+/g)) {
    const bare = w[0].replace(/[.,،]$/, '').toLowerCase();
    if (NOT_A_NAME.has(bare) || bare.startsWith('لل')) break;
    if (!new RegExp(`^${EN_PARTICLE}$`).test(bare)) { names++; end = label.length + w.index! + w[0].length; }
  }
  return names >= 2 ? m.slice(0, end) : null;
};
/**
 * E-mail (obfuscated too: "ahmed @ gmail . com", "ahmed[at]gmail[dot]com", "ahmed(at)gmail(dot)com" — moved here
 * from messages_api's stripContact, second review of #1838, so the quotation and BOQ scrubbers read it as well), a web
 * address, and a bare domain on a wider list of endings ("alnoor.store", "alnoor.shop") WITH its path, so
 * "instagram.com/alnoortrading" loses the handle as well as the host.
 */
export const EMAIL = /[A-Za-z0-9._%+-]+\s*(?:@|\(at\)|\[at\])\s*[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\s*(?:\.|\(dot\)|\[dot\])\s*[A-Za-z]{2,6}(?![A-Za-z])/gi;
export const URL = /(?:https?:\/\/|www\.)[^\s,;)\]]+/gi;
export const DOMAIN = /(?<![@\w.-])[A-Za-z0-9][A-Za-z0-9-]*(?:\.[A-Za-z0-9-]{2,})*\.(?:ae|com|net|org|co|io|biz|info|app|link|store|shop|online|site|tech|xyz|uk|sa|qa|om|bh|kw|eg|ai|pro|group|global|ltd)(?:\.[a-z]{2})?(?![\w-])(?:\/[^\s,;)\]]*)?/gi;

/** Named, so a residual scan can say which one it found. Order matters: mail before hosts, registration numbers before phones. */
export const IDENTITY_TEXT_PATTERNS: [string, RegExp][] = [
  ['email', EMAIL], ['url', URL], ['domain', DOMAIN],
  ['trn', TRN_LABELLED], ['trn_bare', TRN_BARE], ['licence_no', LICENCE_NO], ['licence_short', LICENCE_SHORT],
  ['iban', IBAN], ['account_no', ACCOUNT_NO], ['po_box', PO_BOX],
  ['phone_uae_intl', PHONE_UAE_INTL], ['phone_uae_national', PHONE_UAE_NATIONAL],
  ['address', ADDRESS], ['firm_ar', FIRM_AR], ['firm_en', FIRM_EN], ['person_labelled', PERSON_LABELLED],
];
/** The part of a match that is identity, or null when its words say it is not (a discipline, a team, an authority). */
const SPAN: Record<string, (m: string) => string | null> = { firm_en: firmSpan, person_labelled: personSpan };
/** True when `name`'s match `m` is identity (the validator agrees): what a residual scan should report. */
export function identityMatch(name: string, m: string): boolean { return (SPAN[name] ? SPAN[name](m) : m) != null; }

/**
 * Every identity shape above replaced by `rep` (a string, or a function of the match). `parties: false` leaves firm
 * and person names alone — the quotation a customer has PAID to reveal names its supplier (review of #1838, item 1).
 */
export function scrubIdentityText(text: unknown, rep: string | ((m: string) => string) = '', opts: { parties?: boolean } = {}): string {
  let t = String(text ?? '');
  for (const [name, re] of IDENTITY_TEXT_PATTERNS) {
    if (opts.parties === false && (name === 'firm_ar' || name === 'firm_en' || name === 'person_labelled')) continue;
    t = t.replace(re, (m: string) => {
      const span = SPAN[name] ? SPAN[name](m) : m;
      return span == null ? m : (typeof rep === 'string' ? rep : rep(span)) + m.slice(span.length);
    });
  }
  return t;
}
/** Every identity shape in `text`, by name (the residual scan's half of the list). */
export function identityShapesIn(text: unknown): string[] {
  const s = String(text ?? ''), found = new Set<string>();
  for (const [name, re] of IDENTITY_TEXT_PATTERNS) for (const m of s.matchAll(new RegExp(re.source, re.flags))) if (identityMatch(name, m[0])) { found.add(name); break; }
  return [...found];
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
