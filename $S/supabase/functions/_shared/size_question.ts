// A question about how big we are is answered with what we do, never with a number
// (customer_support, 22 Sep 2026, founder_instruction 777).
//
// Founder, 22 Sep 2026, after asking "how many suppliers do we have" on WhatsApp and getting "0": "we
// shouldn't be sharing such numbers; instead a professional response such as we are able to handle any
// inquiry perfectly, in professional business language."
//
// One statement for every surface that answers the public: WhatsApp (wa_inbound, every number, the
// founder's included), the site assistant and the social inbox. WHETHER a message is a size question is
// REASONED (23 Sep 2026, founder_instruction 886-903): the 'size' option of _shared/reasoned_channels.ts,
// in each surface's one decision, taken BEFORE its FAQ, library or model. The EN/AR regexes that decided it
// here are gone; held, a message is not guessed to be one (each surface says what it does instead).
// Measured 22 Sep 2026 before this file: the widget's count route answered "how many suppliers do you
// have" with FAQ 13 ("How many suppliers receive my RFQ?") — no count, but not the question asked.
//
// The statement claims only what the platform does and the site already says (wa_inbound/coverage.ts,
// the qd_new option): exact-trade matching to verified UAE suppliers, identity hidden until a reveal,
// new trades welcome. No "hundreds of suppliers", no "perfectly": nothing measured supports either.
// Pure: size_question.test.ts.
import { portalLink } from './site_origins.ts';

export type Lang = 'en' | 'ar';

/** The new-request link every surface ends the statement with: /me?new=1 (/ar/me for Arabic). */
export const newRequestLink = (lang: Lang): string => portalLink(lang) + '?new=1';

/** What we do, in business language, with the request link. No figures. Each surface adds its own tail. */
export function capabilityStatement(lang: Lang): string {
  return lang === 'ar'
    ? 'نشكركم على اهتمامكم بمنصة QuotesDone. نطابق كل طلب عرض سعر مع موردين موثّقين في مختلف أنحاء الإمارات ضمن التخصص المطلوب نفسه، فلا يصل الطلب إلا إلى المختصين في هذا العمل. وتقارنون العروض وهويتكم محجوبة حتى تختاروا الكشف عن أحد الموردين، ونرحّب بطلباتكم في جميع التخصصات التي نغطيها، كما نرحّب بالتخصصات الجديدة.\nلطلب عرض سعر:\n' + newRequestLink('ar')
    : 'Thank you for your interest in QuotesDone. We match each quotation request to verified suppliers across the UAE in the exact trade it needs, so it reaches only specialists in that work. You compare the quotes with your identity kept private until you choose to reveal a supplier, and we welcome requests in every trade we cover, as well as new trades.\nTo request a quotation: ' + newRequestLink('en');
}
