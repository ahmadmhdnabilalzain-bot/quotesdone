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
// not finalized ... he is welcomed". So a trade is claimed only when the question names one of its own
// labels or aliases, the reply says a request goes only to suppliers of that exact trade, and every list
// ends by welcoming a trade that is not on it. A question that names nothing we match is NOT answered
// here ("do you do catering" falls through to the FAQ and then the courteous fallback) — guessing that a
// word is a trade we lack would be the same fuzzy match the rule forbids, in the other direction.
//
// Pure: no network, no database. index.ts reads the rows; coverage.test.ts drives this with fixtures.
import { type Lang, newRequestUrl, norm, siteUrl } from './menu.ts';

export type Trade = { code: string; label: string; label_ar: string | null; aliases: string[] | null };
export type CoverageIntent = { kind: 'list' } | { kind: 'trade' };

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

// Written against norm(): lower case, alef/ya/ta-marbuta folded, punctuation collapsed to spaces.
const EN_TOPIC = /\b(sectors?|trades?|categor(?:y|ies)|industr(?:y|ies)|speciali[sz]ations?|specialt(?:y|ies)|fields|services|(?:kinds?|types?) of (?:work|jobs?))\b/;
const EN_ASK = /\b(cover|covers|covered|covering|coverage|offer|support|serve|handle|provide|which|what|list|available)\b/;
const EN_MONEY = /\b(fees?|price|prices|pricing|cost|costs|pay|paid|charges?|commission|subscription)\b/;
const EN_TRADE_ASK = /\b(do|does|can|could|are|is)\s+(you|u|quotesdone|your\s+(?:suppliers?|platform|team))\b|\byou\s+(cover|do|handle|offer|support|serve)\b/;
const AR_TOPIC = /(قطاع|تخصص|فئات|فئه|مجالات|انشطه|نشاطات|خدمات)/;
const AR_ASK = /(تغط|يغط|نغط|تخدم|يخدم|تقدم|تشمل|يشمل|تتعامل|ما هي|ما هو|ماهي|ايش|شو |وش |اي )/;
const AR_MONEY = /(رسوم|سعر|اسعار|تكلف|دفع|عموله|اشتراك)/;
const AR_TRADE_ASK = /(^| )هل /;
const LATIN = /^[a-z0-9]/;

function esc(s: string) { return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }
// The article (and a joined و / ب / ل / ف before it) drops from every Arabic word, on both sides:
// the alias "تنسيق حدائق" must meet "تنسيق الحدائق" as people write it.
function noArticle(s: string) { return s.replace(/(^| )[وبلف]?ال(?=[؀-ۿ]{2})/g, '$1'); }

/** The trade the text names, by its own label or alias — the longest name wins — or null. */
export function tradeNamed(text: string, trades: Trade[]): Trade | null {
  const t = ' ' + noArticle(norm(text)) + ' ';
  let best: Trade | null = null; let bestLen = 0;
  for (const tr of trades) {
    for (const raw of [tr.label, tr.label_ar || '', ...(tr.aliases || [])]) {
      const n = noArticle(norm(raw));
      if (n.length < 3 || n.length <= bestLen) continue;
      // A Latin name must stand as a word ("door" is not in "outdoor"); an Arabic one may carry a prefix
      // (ال, و, ب) and a suffix, as Arabic words do.
      const hit = LATIN.test(n) ? new RegExp('[^a-z0-9]' + esc(n) + '(?:s|es)?[^a-z0-9]').test(t) : t.includes(n);
      if (hit) { best = tr; bestLen = n.length; }
    }
  }
  return best;
}

/** Is this a coverage question? A named trade is asked about ("do you do MEP"); a list is asked for. */
export function coverageIntent(text: string, trades: Trade[] = []): CoverageIntent | null {
  const n = norm(text);
  if (!n) return null;
  const ar = /[؀-ۿ]/.test(n);
  // A fee question that names a trade ("do you charge suppliers for marble") is a fee question.
  if (ar ? AR_MONEY.test(n) : EN_MONEY.test(n)) return null;
  if ((ar ? AR_TRADE_ASK : EN_TRADE_ASK).test(n) && tradeNamed(n, trades)) return { kind: 'trade' };
  if (ar ? (AR_TOPIC.test(n) && AR_ASK.test(n)) : (EN_TOPIC.test(n) && EN_ASK.test(n))) return { kind: 'list' };
  return null;
}

/** True when the text could be a coverage question at all, before any row is read. */
export function mightBeCoverage(text: string): boolean {
  const n = norm(text);
  return EN_TOPIC.test(n) || EN_TRADE_ASK.test(n) || AR_TOPIC.test(n) || AR_TRADE_ASK.test(n);
}

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

/** The reply, or null when the text is not a coverage question (or no trade row could be read). */
export function coverageReply(text: string, trades: Trade[], lang: Lang): string | null {
  if (!trades.length) return null;
  const intent = coverageIntent(text, trades);
  if (!intent) return null;
  const ar = lang === 'ar';
  const newReq = newRequestUrl(lang);
  if (intent.kind === 'trade') {
    const t = tradeNamed(text, trades)!;
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
