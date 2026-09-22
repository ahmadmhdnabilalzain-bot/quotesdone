// The founder asks the numbers on WhatsApp and gets them, without a model (customer_support, 22 Sep 2026).
//
// Until 7 Sep his free-text questions went to agent_brain with fn_wa_context's figures in the prompt;
// agent_brain was deleted that day, so "how many suppliers" had no answer and wa_messages 271 carried
// its 404. The readings now come from public.fn_founder_whatsapp_figures (each from the routine that
// owns it, and refused for any number that is not his); this file only recognises the question and
// says the numbers, with the time of the reading. Pure: menu_flow.test.ts drives it with fixtures.
//
// WHAT IT DOES NOT DO: it never runs for any other number (index.ts calls it only inside the founder
// branch, and the routine refuses a stranger), it never guesses a topic from a single word (a count or
// status word must be there too), and it never promises a remedy that does not exist — there is no OS
// page to send him to (https://quotesdone.com/os answers 404) and it does not ask him to lift the hold.
import { type Lang, norm } from './menu.ts';

export type Topic = 'suppliers' | 'requests' | 'quotes' | 'money' | 'support' | 'it' | 'marketing' | 'snapshot' | 'report';
export type Figures = {
  ok: boolean; read_at_local?: string;
  suppliers?: { registered: number; registered_7d: number; verified: number };
  requests?: { today: number; last_7d: number };
  quotes?: { total: number; last_7d: number };
  reveals_month?: { paid: number; fee_aed: number };
  support?: { open_cases: number; waiting_for_person: number };
  it?: { open_findings: number };
  marketing_7d?: { posts_published: number; posts_scheduled: number; ad_spend_aed: number };
  brief?: { local_time: string; sent_today: boolean };
};

// Written against norm(): lower case, alef/ya/ta-marbuta folded, punctuation collapsed to spaces.
const ASK = /\b(how many|how much|number of|count|total|any|status|today|this week|this month|so far|figures?|numbers?)\b|كم|عدد|اليوم|هذا الاسبوع|هذا الشهر|حتي الان|وضع|حاله|ارقام/;
const TOPICS: Array<[Topic, RegExp]> = [
  ['report', /\b(report|brief|summary|pdf)\b|تقرير|ملخص/],
  ['money', /\b(revenue|reveals?|payments?|paid|income|sales|money|earn\w*|fees? collected)\b|ايراد|مدفوع|دفعات|مبيعات|كشف/],
  ['quotes', /\b(quotes?|quotations?)\b|عروض|عرض سعر/],
  ['support', /\b(support|cases?|complaints?|tickets?)\b|waiting for a person|بلاغ|شكوي|شكاوي|الدعم/],
  ['it', /\b(technical|incidents?|findings?|errors?|bugs?|outages?)\b|\bit (issues?|problems?)\b|تقني|اعطال/],
  ['marketing', /\b(marketing|ads?|campaigns?|posts?|social)\b|تسويق|اعلان|حمل|منشور/],
  ['suppliers', /\b(suppliers?|vendors?|registrations?)\b|مورد/],
  ['requests', /\b(requests?|inquir(?:y|ies)|rfqs?|jobs?|demand)\b|طلب|استفسار/],
  ['snapshot', /\b(snapshot|dashboard|how are we doing|overview|kpis?)\b|الوضع العام|نظره عامه/],
];

/** The topics a founder message asks about, in reply order; empty when none is recognised. */
export function founderTopics(text: string): Topic[] {
  const n = norm(text);
  const hits = TOPICS.filter(([, re]) => re.test(n)).map(([t]) => t);
  if (hits.includes('report')) return ['report'];              // "send me the report": the brief, not a count
  if (hits.includes('snapshot')) return ['snapshot'];
  // A topic word alone is not a question about the numbers ("what do suppliers pay" is a fee question
  // the FAQ answers): a count or status word must be there too.
  return ASK.test(n) ? hits : [];
}

const fmt = (n: number | undefined) => new Intl.NumberFormat('en-US').format(Number(n || 0));

function line(t: Exclude<Topic, 'report' | 'snapshot'>, f: Figures, lang: Lang): string {
  const ar = lang === 'ar';
  switch (t) {
    case 'suppliers': return ar
      ? '• الموردون: ' + fmt(f.suppliers?.registered) + ' مسجّل (' + fmt(f.suppliers?.registered_7d) + ' خلال 7 أيام)، و' + fmt(f.suppliers?.verified) + ' موثّق.'
      : '• Suppliers: ' + fmt(f.suppliers?.registered) + ' registered (' + fmt(f.suppliers?.registered_7d) + ' in the last 7 days), ' + fmt(f.suppliers?.verified) + ' verified.';
    case 'requests': return ar
      ? '• طلبات العملاء: ' + fmt(f.requests?.today) + ' اليوم، و' + fmt(f.requests?.last_7d) + ' خلال 7 أيام.'
      : '• Customer requests: ' + fmt(f.requests?.today) + ' today, ' + fmt(f.requests?.last_7d) + ' in the last 7 days.';
    case 'quotes': return ar
      ? '• عروض الأسعار: ' + fmt(f.quotes?.total) + ' إجمالًا، و' + fmt(f.quotes?.last_7d) + ' خلال 7 أيام.'
      : '• Quotes: ' + fmt(f.quotes?.total) + ' in total, ' + fmt(f.quotes?.last_7d) + ' in the last 7 days.';
    case 'money': return ar
      ? '• الكشف هذا الشهر: ' + fmt(f.reveals_month?.paid) + ' مدفوع، بقيمة ' + fmt(f.reveals_month?.fee_aed) + ' درهم.'
      : '• Reveals this month: ' + fmt(f.reveals_month?.paid) + ' paid, AED ' + fmt(f.reveals_month?.fee_aed) + ' in fees.';
    case 'support': return ar
      ? '• الدعم: ' + fmt(f.support?.open_cases) + ' بلاغ مفتوح، و' + fmt(f.support?.waiting_for_person) + ' بانتظار رد أحد الموظفين.'
      : '• Support: ' + fmt(f.support?.open_cases) + ' open case(s), ' + fmt(f.support?.waiting_for_person) + ' waiting for a person.';
    case 'it': return ar
      ? '• التقنية: ' + fmt(f.it?.open_findings) + ' ملاحظة تقنية مفتوحة لدى مهندس تقنية المعلومات.'
      : '• IT: ' + fmt(f.it?.open_findings) + ' open technical finding(s) with the IT engineer.';
    case 'marketing': return ar
      ? '• التسويق (7 أيام): ' + fmt(f.marketing_7d?.posts_published) + ' منشور، و' + fmt(f.marketing_7d?.posts_scheduled) + ' مجدول، وإنفاق إعلاني ' + fmt(f.marketing_7d?.ad_spend_aed) + ' درهم.'
      : '• Marketing (7 days): ' + fmt(f.marketing_7d?.posts_published) + ' post(s) published, ' + fmt(f.marketing_7d?.posts_scheduled) + ' scheduled, AED ' + fmt(f.marketing_7d?.ad_spend_aed) + ' ad spend.';
  }
}

const ALL: Array<Exclude<Topic, 'report' | 'snapshot'>> = ['suppliers', 'requests', 'quotes', 'money', 'support', 'it', 'marketing'];

function heading(f: Figures, lang: Lang) {
  return lang === 'ar' ? 'القراءة الحالية (' + (f.read_at_local || '') + ' بتوقيت الإمارات):' : 'Reading at ' + (f.read_at_local || '') + ' (UAE time):';
}

export function snapshotText(f: Figures, lang: Lang): string {
  return heading(f, lang) + '\n' + ALL.map((t) => line(t, f, lang)).join('\n');
}

/** The answer to a recognised question, or null when the readings could not be had. */
export function founderAnswer(topics: Topic[], f: Figures, lang: Lang): string | null {
  if (!f?.ok || !topics.length) return null;
  if (topics[0] === 'report') {
    const at = f.brief?.local_time || '20:00';
    const when = lang === 'ar'
      ? (f.brief?.sent_today ? 'أُرسل ملخص اليوم، والملخص التالي غدًا الساعة ' + at + ' بتوقيت الإمارات.' : 'يصلكم الملخص اليومي الكامل اليوم الساعة ' + at + ' بتوقيت الإمارات.')
      : (f.brief?.sent_today ? "Today's brief has been sent; the next one comes tomorrow at " + at + ' (UAE time).' : 'The full daily brief comes today at ' + at + ' (UAE time).');
    return when + '\n\n' + snapshotText(f, lang);
  }
  if (topics[0] === 'snapshot') return snapshotText(f, lang);
  return heading(f, lang) + '\n' + topics.filter((t): t is Exclude<Topic, 'report' | 'snapshot'> => t !== 'report' && t !== 'snapshot')
    .map((t) => line(t, f, lang)).join('\n');
}

/** Not recognised: say plainly what can be answered without the model, and give today's reading. */
export function founderHelp(f: Figures, lang: Lang): string {
  const list = lang === 'ar'
    ? 'يمكنني الإجابة دون الذكاء الاصطناعي عن: عدد الموردين المسجّلين والموثّقين، وطلبات العملاء اليوم وهذا الأسبوع، وعروض الأسعار، وعمليات الكشف والرسوم هذا الشهر، وبلاغات الدعم ومن ينتظر أحد الموظفين، والملاحظات التقنية المفتوحة، وأرقام التسويق، وموعد الملخص اليومي. أما غير ذلك فيحتاج إلى النموذج، وهو موقوف حاليًا، وقد سجّلتُ سؤالكم لدى الفريق.'
    : 'I can answer these without AI: suppliers registered and verified, customer requests today and this week, quotes, reveals and fees this month, support cases and people waiting for a person, open IT findings, marketing figures, and when the daily brief arrives. Anything else needs the model, which is on hold, so I have recorded your question for the team.';
  return f?.ok ? list + '\n\n' + snapshotText(f, lang) : list;
}
