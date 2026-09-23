// line_specs/legacy_word_readers.ts — the word readers the hold gate no longer uses, kept ONLY for two files
// another batch migrates. Seat: sales_engineer. 23 Sep 2026.
//
// WHY THIS FILE EXISTS. Decision points 29 and 30 (line_specs.vague, line_specs.assess) took every one of
// these out of the hold decision, the comparison and the offer: a quote's line values, installation,
// warranty and delivery are now READ BY REASONING (_shared/reasoned_matching.ts readQuote) or STATED by the
// supplier in keyed portal fields, and model.ts / assess.ts decide nothing from words. Two files outside
// that batch still call these readers to interpret a supplier's chat reply and to derive line fields:
//   * supplier_api/quote_review.ts — decision point 31 (supplier_api.quote_review_match)
//   * line_specs/derive.ts         — decision point 36 (line_specs.options_derive_vat)
// Both are registered pending in supabase/functions/_shared/decision_points.json and migrate in their own
// batch. They are moved here UNCHANGED so those files keep compiling; DELETE THIS FILE when both points are
// migrated. model.ts / assess.ts only RE-EXPORT these names so those two files keep their imports; nothing in
// assess.ts, compare.ts, model.ts, no_exact_spec.ts or workflow.ts CALLS them (the registry's must_not_contain
// fingerprints in decision_points.json hold that).
import { normText } from './model.ts';
import type { Line, Terms } from './assess.ts';

/** A value that is not a specification. (Decision point 36 / 31 own its remaining readers.) */
export const VAGUE = /^(n\/?a|na|nil|none|tbd|tba|tbc|-+|\?+|x+|same|any|standard|std|equivalent|approved equivalent|or equivalent|equal|as per.*|as required|as approved|to be confirmed|to be advised|later|غير محدد|حسب.*|مماثل|ما يعادله|يحدد لاحقا|يحدد لاحقاً|لاحقا|لاحقاً)$/i;

const MONTHS = 'jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?|يناير|فبراير|مارس|أبريل|ابريل|مايو|يونيو|يوليو|أغسطس|اغسطس|سبتمبر|أكتوبر|اكتوبر|نوفمبر|ديسمبر';
const DATE_RE = new RegExp(`\\b(\\d{4}-\\d{2}-\\d{2}|\\d{1,2}[\\/.\\-]\\d{1,2}[\\/.\\-]\\d{2,4}|\\d{1,2}\\s+(?:${MONTHS})\\s*,?\\s*\\d{0,4}|(?:${MONTHS})\\s+\\d{1,2}(?:,\\s*\\d{4})?)`, 'i');
const DUR_RE = /(\d+(?:\.\d+)?)\s*(?:-\s*\d+\s*)?(working\s*days?|business\s*days?|days?|weeks?|months?|wks?|يوم عمل|أيام عمل|يوم|أيام|يوما|يومًا|أسبوع|أسابيع|اسبوع|اسابيع|شهر|أشهر|شهور)/i;
const IMMEDIATE = /\b(ex[\s-]?stock|from\s*stock|immediate(?:ly)?|same\s*day|next\s*day)\b|من المخزون|فوري|فورا|فوراً/i;

export function readDelivery(text: string): { value: string; days: number | null; date: string | null } | null {
  const s = normText(text); if (!s || VAGUE.test(s)) return null;
  const d = s.match(DUR_RE);
  if (d) { const n = Number(d[1]); const u = d[2].toLowerCase(); const days = /week|wk|أسبوع|أسابيع|اسبوع|اسابيع/.test(u) ? n * 7 : /month|شهر|أشهر|شهور/.test(u) ? n * 30 : n; return { value: s.slice(0, 120), days, date: null }; }
  const dt = s.match(DATE_RE); if (dt) return { value: s.slice(0, 120), days: null, date: dt[1] };
  if (IMMEDIATE.test(s)) return { value: s.slice(0, 120), days: 0, date: null };
  return null;
}

const INSTALL_YES = /supply\s*(?:&|and|\+|,)\s*(?:install|fix|apply|lay|erect)|s\s*[&\/]\s*i\b|supply,?\s*install|includ(?:es|ing|ed)?\s*(?:the\s*)?(?:install|fixing)|install(?:ation)?\s*(?:is\s*)?includ|incl\.?\s*install|install(?:ation)?\s*(?:&|and)\s*commission|توريد وتركيب|شامل التركيب|يشمل التركيب|مع التركيب|التركيب مشمول/i;
const INSTALL_NO = /supply\s*only|install(?:ation)?\s*(?:is\s*)?(?:not\s*included|excluded|by\s*others|extra)|exclud(?:es|ing|ed)?\s*(?:the\s*)?install|without\s*install|توريد فقط|بدون تركيب|التركيب غير مشمول|لا يشمل التركيب|غير شامل التركيب/i;
const INSTALL_LINE = /^(?:\d+[.)]\s*)?(?:install|fix|fixing|erect|lay(?:ing)?|تركيب)|\binstall(?:ation)?\s*(?:of|labou?r|charges?)|تركيب/i;
// "Installation included 4 weeks" / "installation included, 5 working days on site" state the timeline
// (audit 21 Sep 2026: the auditor's CSV said the first and was asked the timeline again).
const INSTALL_TIME = /install\w*\s*(?:is\s*)?(?:included\s*|مشمول\s*)?[,:\-]?\s*(?:period|time|duration|within|in)?\s*[:\-]?\s*(\d+\s*(?:working\s*)?(?:days?|weeks?|يوم|أيام|أسبوع|أسابيع))|(\d+\s*(?:working\s*)?(?:days?|weeks?|يوم|أيام|أسبوع|أسابيع))\s*(?:for\s*)?(?:install|تركيب)|(?:مدة التركيب)\s*[:\-]?\s*([^,;.]{2,30})/i;

export function readInstallation(lines: Line[], t: Terms): { included: 'yes' | 'no' | null; detail: string | null } {
  const lineText = lines.map((l) => `${l.description} ${l.specification ?? ''} ${l.notes ?? ''}`).join(' \n ');
  const all = `${lineText}\n${t.scope ?? ''}\n${t.conditions ?? ''}\n${t.notes ?? ''}`;
  const pricedInstall = lines.some((l) => (Number(l.install) || 0) > 0 || (Number(l.labour) || 0) > 0);
  const installLine = lines.find((l) => INSTALL_LINE.test(l.description) || INSTALL_YES.test(l.description));
  const timeM = normText(all).match(INSTALL_TIME);
  const time = timeM ? (timeM[1] || timeM[2] || timeM[3] || '').trim() : '';
  const detail = time ? `Installation in ${time}` : installLine ? `Scope: ${installLine.description.slice(0, 100)}` : pricedInstall ? 'Installation priced per line' : null;
  if (pricedInstall || installLine) return { included: 'yes', detail };
  if (INSTALL_NO.test(all) || INSTALL_NO.test(t.exclusions ?? '')) return { included: 'no', detail: null };
  if (INSTALL_YES.test(all)) {
    // "Supply and installation of the complete joinery package" in the scope IS the installation
    // scope; a bare "installation included" in the notes names no scope and no timeline.
    const src = [t.scope, t.conditions, t.notes].find((x) => x && INSTALL_YES.test(x) && normText(x).length > 25);
    return { included: 'yes', detail: detail ?? (src ? `Scope: ${normText(src).slice(0, 100)}` : null) };
  }
  return { included: null, detail: null };
}

const W_PERIOD = /(\d+(?:\.\d+)?)\s*(years?|yrs?|months?|mos?|سنة|سنوات|سنه|عام|أعوام|اعوام|شهر|أشهر|شهور)|\b(one|two|three|five|ten)\s+years?\b|(سنتين|سنتان|عامين)/i;
const W_COVER = /(manufactur\w*|parts?|spare\s*parts|labou?r|workmanship|compressor|motor|leak\w*|defects?|materials?|installation|panels?|inverters?|performance|replacement|on\s*-?\s*site|structural|finish|mechanical|electrical|hardware|hinges?|مصنعية|المصنعية|الصناعة|قطع(?:\s*الغيار)?|العمالة|عمالة|تسريب|التسريب|العيوب|عيوب|المواد|الضاغط|الكمبروسر|المحرك|التركيب|الأداء|الاستبدال|شامل)/gi;
const WORDNUM: Record<string, number> = { one: 1, two: 2, three: 3, five: 5, ten: 10 };
export function readWarranty(text: string): { period: string | null; months: number | null; coverage: string | null } {
  const s = normText(text);
  if (!s || VAGUE.test(s)) return { period: null, months: null, coverage: null };
  let period: string | null = null, months: number | null = null;
  const m = s.match(W_PERIOD);
  if (m) {
    if (m[1]) { const n = Number(m[1]); const u = m[2].toLowerCase(); const isMonth = /month|mo|شهر|أشهر|شهور/.test(u); months = isMonth ? n : n * 12; period = `${n} ${isMonth ? (n === 1 ? 'month' : 'months') : (n === 1 ? 'year' : 'years')}`; }
    else if (m[3]) { months = WORDNUM[m[3].toLowerCase()] * 12; period = `${months / 12} years`; }
    else if (m[4]) { months = 24; period = '2 years'; }
  }
  const cov = [...new Set([...s.matchAll(W_COVER)].map((x) => x[1].toLowerCase()))];
  return { period, months, coverage: cov.length ? cov.join(', ') : null };
}
