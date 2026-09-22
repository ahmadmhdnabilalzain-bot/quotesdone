// A question about how big we are is answered with what we do, never with a number
// (customer_support, 22 Sep 2026, founder_instruction 777).
//
// Founder, 22 Sep 2026, after asking "how many suppliers do we have" on WhatsApp and getting "0": "we
// shouldn't be sharing such numbers; instead a professional response such as we are able to handle any
// inquiry perfectly, in professional business language."
//
// One detector and one statement for every surface that answers the public: WhatsApp (wa_inbound,
// every number, the founder's included), the site assistant and the social inbox. Each checks this
// BEFORE its FAQ, library or model, so no row or prompt can answer a size question with a count.
// Measured 22 Sep 2026 before this file: the widget's count route answered "how many suppliers do you
// have" with FAQ 13 ("How many suppliers receive my RFQ?") — no count, but not the question asked.
//
// The statement claims only what the platform does and the site already says (wa_inbound/coverage.ts,
// the qd_new option): exact-trade matching to verified UAE suppliers, identity hidden until a reveal,
// new trades welcome. No "hundreds of suppliers", no "perfectly": nothing measured supports either.
// Pure: size_question.test.ts.
import { portalLink } from './site_origins.ts';

export type Lang = 'en' | 'ar';

// Lower case, Arabic diacritics/tatweel stripped, alef/ya/ta-marbuta folded, punctuation to spaces —
// the same folding as wa_inbound/menu.ts norm().
function norm(s: string): string {
  return String(s || '').toLowerCase()
    .replace(/[ً-ْـ]/g, '')
    .replace(/[آأإ]/g, 'ا').replace(/ى/g, 'ي').replace(/ة/g, 'ه')
    .replace(/[!?.,،؟\s]+/g, ' ').trim();
}

// A size question needs a count word AND a subject AND something that makes it about US ("do you have",
// "registered", "on the platform", «لديكم») — so "how many quotes will I receive" and «كم عدد العروض التي
// سأستلمها» stay product questions the FAQ answers. A bare "how many suppliers" / «كم عدد الموردين» of four
// words or fewer is about us too.
const EN_ASK = /\b(how many|how much|number of|count of|total of|amount of)\b/;
const EN_SUBJECT = /\b(suppliers?|vendors?|contractors?|compan(?:y|ies)|firms?|businesses|customers?|clients?|users?|members?|requests?|rfqs?|inquir(?:y|ies)|enquir(?:y|ies)|jobs?|quotes?|quotations?|orders?|deals?|transactions?|revenue|turnover|sales|income|profits?|earnings|reveals?|registrations?|sign ?ups?)\b/;
const EN_ABOUT_US = new RegExp('\\b(' + [
  '(do|did) (you|we|u) (have|serve|handle|process|get|receive|make|earn|work with)', 'does (quotesdone|it|the platform|the company) have',
  "(you|we)( have|'ve)? got", 'have (you|we) (got|had|served|handled|received|made)', 'you (have|serve|handle|process|receive|made|make|earn)',
  'we (have|serve|handle|process|receive|made|make|earn)', 'quotesdone (has|have|serves?|handles?|gets?|made|makes|earns?)',
  'are (there|registered|listed|verified|onboard|signed up|on|using|with)', 'is there', 'registered', 'signed up', 'onboarded',
  'on (the |your )?(platform|quotesdone|board|books|network|list|database)', 'in (your|the|our) (network|database|system|platform)',
  '(use|using|joined) (quotesdone|you|the platform|your platform)', 'so far', 'to date', 'in total', 'overall', 'altogether',
].join('|') + ')\\b');
const EN_SCALE = /\bhow (big|large) (are you|are u|is (quotesdone|your|the (company|platform|network|business)))\b|\b(size|scale) of (your|quotesdone|the company)\b|\b(your|quotesdone'?s?|the company'?s?) (annual )?(revenue|turnover|sales|income|profits?|earnings|numbers|figures|stats|statistics|volumes?)\b/;
const AR_ASK = /(^| )(كم|عدد|اجمالي)( |$)/;
const AR_SUBJECT = /مورد|عملاء|عميل|زبائن|زبون|مستخدم|شركات|طلبات|عروض|صفقات|مبيعات|ايراد|ارباح|دخل|اعضاء|مشترك|تسجيل/;
const AR_ABOUT_US = /لديكم|عندكم|لدينا|عندنا|لدي المنصه|مسجل|في المنصه|علي المنصه|بالمنصه|في منصتكم|في شبكتكم|تتعاملون|تعملون مع|تخدمون|يستخدمون|حتي الان|الاجمالي|يوجد|هناك|تستقبلون|استقبلتم|تحققون|حققتم|وصلكم/;
const AR_SCALE = /حجم (شركتكم|الشركه|منصتكم|المنصه|شبكتكم|اعمالكم|اعمال الشركه)|ايراداتكم|ارباحكم|مبيعاتكم|دخلكم|ارقامكم|احصائياتكم/;

/** A question about how big we are or how much we do. */
export function isSizeQuestion(text: string): boolean {
  const n = norm(text);
  if (!n) return false;
  const short = n.split(' ').length <= 4;
  if (EN_SCALE.test(n) || AR_SCALE.test(n)) return true;
  if (EN_ASK.test(n) && EN_SUBJECT.test(n) && (EN_ABOUT_US.test(n) || short)) return true;
  if (AR_ASK.test(n) && AR_SUBJECT.test(n) && (AR_ABOUT_US.test(n) || short)) return true;
  return false;
}

/** The new-request link every surface ends the statement with: /me?new=1 (/ar/me for Arabic). */
export const newRequestLink = (lang: Lang): string => portalLink(lang) + '?new=1';

/** What we do, in business language, with the request link. No figures. Each surface adds its own tail. */
export function capabilityStatement(lang: Lang): string {
  return lang === 'ar'
    ? 'نشكركم على اهتمامكم بمنصة QuotesDone. نطابق كل طلب عرض سعر مع موردين موثّقين في مختلف أنحاء الإمارات ضمن التخصص المطلوب نفسه، فلا يصل الطلب إلا إلى المختصين في هذا العمل. وتقارنون العروض وهويتكم محجوبة حتى تختاروا الكشف عن أحد الموردين، ونرحّب بطلباتكم في جميع التخصصات التي نغطيها، كما نرحّب بالتخصصات الجديدة.\nلطلب عرض سعر:\n' + newRequestLink('ar')
    : 'Thank you for your interest in QuotesDone. We match each quotation request to verified suppliers across the UAE in the exact trade it needs, so it reaches only specialists in that work. You compare the quotes with your identity kept private until you choose to reveal a supplier, and we welcome requests in every trade we cover, as well as new trades.\nTo request a quotation: ' + newRequestLink('en');
}
