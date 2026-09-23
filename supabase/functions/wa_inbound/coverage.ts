// "What sectors do you cover?" answered from the LIVE trade list (customer_support, 22 Sep 2026).
//
// Measured 22 Sep 2026, wa_messages 271: the founder asked "What sectors you cover" on WhatsApp. No FAQ
// matched (fn_faq_answer's keyword rank for that sentence against "What industries does QuotesDone
// support?" is 0.085, under its 0.15 floor), and the message fell through to a function that no longer
// exists. A coverage question has an exact, free answer: public.taxonomy_trade, the table
// fn_match_capability gates on (sc.trades && p_trades, codes from fn_taxonomy_trades_for). So the answer
// is built from that table on every message, never from a copy of it.
//
// THE EXACT-TRADE RULE (founder, 14 Sep 2026): "either exact match or no match", and "our categories are
// not finalized ... he is welcomed". A trade is claimed only when the REASONED meaning names it
// (trade:<code>, one of the live rows), the reply says a request goes only to suppliers of that exact trade,
// and every list ends by welcoming a trade that is not on it.
//
// WHAT THE QUESTION ASKS IS REASONED, NOT MATCHED (23 Sep 2026, founder_instruction 886-903). Until today
// EN/AR regexes decided "is this a coverage question" and the longest label substring decided which trade
// was named ("do you do outdoor events" had to be kept away from "doors" by hand). The meaning now arrives
// from think() (_shared/reasoned_channels.ts whatsappOptions); a trade we do not list (coverage:other) gets
// the list and the welcome, which a word match could never tell apart from a word that is not a trade.
//
// Pure: no network, no database. index.ts reads the rows; menu_flow.test.ts drives this with fixtures.
import { type Lang, newRequestUrl, siteUrl } from './menu.ts';
import { COVERAGE_LIST, COVERAGE_OTHER } from '../_shared/reasoned_channels.ts';

export type Trade = { code: string; label: string; label_ar: string | null; aliases: string[] | null };

// Grouping is presentation only. A code not named here (a trade a supplier registered tomorrow) is still
// listed, under "other trades", so the answer can never fall behind the table.
const GROUPS: Array<{ en: string; ar: string; codes: string[] }> = [
  { en: 'MEP', ar: 'الأعمال الكهروميكانيكية',
    codes: ['mep_general', 'hvac', 'electrical', 'plumbing', 'fire_fighting', 'elevators', 'power_generators', 'solar',
            'home_automation', 'security_systems', 'av_it'] },
  { en: 'Construction & outdoor', ar: 'الإنشاءات والأعمال الخارجية',
    codes: ['civil_works', 'engineering_consultancy', 'steel', 'scaffolding', 'waterproofing', 'landscaping',
            'heavy_equipment', 'labour_supply'] },
  { en: 'Fit-out & finishes', ar: 'التشطيبات الداخلية',
    codes: ['interior_fitout', 'joinery', 'flooring', 'painting', 'gypsum', 'wallpaper', 'glazing', 'aluminium', 'doors',
            'upholstery', 'signage'] },
  { en: 'Materials & supplies', ar: 'المواد والتوريدات',
    codes: ['building_materials', 'chemicals', 'plastics_pipes', 'safety_equipment', 'oilfield', 'marine', 'packaging'] },
  { en: 'Services & tech', ar: 'الخدمات والتقنية',
    codes: ['cleaning', 'logistics_moving', 'it_services', 'office_equipment', 'pos_retail'] },
];
const OTHER = { en: 'Other trades', ar: 'تخصصات أخرى' };

function label(t: Trade, lang: Lang) { return lang === 'ar' ? (t.label_ar || t.label) : t.label; }

/** The grouped list, in the table's own order within each group. */
export function groupedTrades(trades: Trade[], lang: Lang): Array<{ title: string; labels: string[] }> {
  const out: Array<{ title: string; labels: string[] }> = [];
  const seen = new Set<string>();
  for (const g of GROUPS) {
    const labels = trades.filter((t) => g.codes.includes(t.code)).map((t) => { seen.add(t.code); return label(t, lang); });
    if (labels.length) out.push({ title: lang === 'ar' ? g.ar : g.en, labels });
  }
  const rest = trades.filter((t) => !seen.has(t.code)).map((t) => label(t, lang));
  if (rest.length) out.push({ title: lang === 'ar' ? OTHER.ar : OTHER.en, labels: rest });
  return out;
}

/** The reply to a REASONED coverage question (_shared/reasoned_channels.ts whatsappOptions): the list for
 *  coverage:list / coverage:other, the one trade for trade:<code>. Null for any other meaning, or no trade row. */
export function coverageReply(meaning: string, trades: Trade[], lang: Lang): string | null {
  if (!trades.length) return null;
  const named = meaning.startsWith('trade:') ? trades.find((t) => 'trade:' + t.code === meaning) ?? null : null;
  if (!named && meaning !== COVERAGE_LIST && meaning !== COVERAGE_OTHER && !meaning.startsWith('trade:')) return null;
  const ar = lang === 'ar';
  const newReq = newRequestUrl(lang);
  if (named) {
    const t = named;
    return ar
      ? 'نعم، ' + label(t, 'ar') + ' من التخصصات التي نطابق طلبات عروض الأسعار معها. تفضلوا بوصف العمل المطلوب عبر الرابط التالي، وسنرسل طلبكم إلى موردي هذا التخصص وحدهم:\n' + newReq
      : 'Yes, ' + t.label + ' is one of the trades we match quotation requests to. Describe the job here and it will go only to suppliers of that trade:\n' + newReq;
  }
  const groups = groupedTrades(trades, lang);
  const join = siteUrl(lang, '/supplier');
  // Tight on purpose: all 42 live trades (22 Sep 2026), the rule, both links and the MENU hint fit the
  // 1,500 characters wa_inbound sends in one message (Twilio refuses a body over 1,600). As the table
  // grows, each group shows fewer names and says how many more, so the links are never cut off.
  const most = Math.max(...groups.map((g) => g.labels.length));
  let reply = '';
  for (let k = most; k >= 1; k--) {
    const lines = groups.map((g) => '• ' + g.title + ': ' + g.labels.slice(0, k).join(ar ? '، ' : ', ') +
      (g.labels.length > k ? (ar ? ' و' + (g.labels.length - k) + ' أخرى' : ' and ' + (g.labels.length - k) + ' more') : ''));
    reply = listReply(ar, lines, join, newReq);
    if (reply.length <= BUDGET) break;
  }
  return reply;
}

// 1,430 + the Arabic MENU hint (55) + four bidi isolates around the two links stays under 1,500.
const BUDGET = 1430;
function listReply(ar: boolean, lines: string[], join: string, newReq: string): string {
  return ar
    ? 'نطابق طلبات عروض الأسعار مع موردين موثّقين في الإمارات ضمن التخصصات التالية:\n' + lines.join('\n') +
      '\nيُرسل كل طلب إلى موردي التخصص نفسه فقط، ونرحّب بالتخصصات الجديدة:\n' + join +
      '\nلطلب عرض سعر:\n' + newReq
    : 'We match quotation requests to verified UAE suppliers in these trades:\n' + lines.join('\n') +
      '\nEach request goes only to suppliers of that exact trade. New trades are welcome: ' + join +
      '\nRequest a quotation: ' + newReq;
}
