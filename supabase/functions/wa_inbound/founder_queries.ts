// Internal figures stay internal (customer_support, 22 Sep 2026, founder_instruction 777).
//
// Founder, 22 Sep 2026, after asking "how many suppliers do we have" on WhatsApp and getting "0": "we
// shouldn't be sharing such numbers; instead a professional response such as we are able to handle any
// inquiry perfectly, in professional business language."
//
// TWO RULES, BOTH HERE SO THEY CANNOT DRIFT APART:
//   1. A natural question about our size or volumes (suppliers, customers, requests, quotes, revenue,
//      "how big are you", and the Arabic) gets capabilityAnswer — what we do, never a number — from ANY
//      number, the founder's included. menu_flow.menuTurn applies it before any other handler, so neither
//      the FAQ, fn_wa_route nor the model is ever asked to answer it.
//   2. The internal reading (public.fn_founder_whatsapp_figures, refused for any number that is not his)
//      is sent only when the founder writes the command word FIGURES / «أرقام» as the whole message.
//      A natural question never reaches it. From any other number the command word gets rule 1.
//
// Pure: menu_flow.test.ts drives it with fixtures.
import { type Lang, MENU_HINT, norm } from './menu.ts';
import { capabilityStatement } from '../_shared/size_question.ts';

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

// ---- Rule 2: the command word ---------------------------------------------------------------------
const FIGURES_WORDS = ['figures', 'ارقام', 'الارقام'].map(norm);
/** The whole message is the command word (any case, punctuation ignored). Nothing else counts. */
export function isFiguresCommand(text: string): boolean { return FIGURES_WORDS.includes(norm(text)); }

// ---- Rule 1: a question about our size (the detector and the words are shared with the site
// assistant and the social inbox: _shared/size_question.ts) -------------------------------------------
export { isSizeQuestion } from '../_shared/size_question.ts';

/** The capability statement, with the MENU hint WhatsApp ends every free-text answer with. No figures. */
export function capabilityAnswer(lang: Lang): string { return capabilityStatement(lang) + MENU_HINT[lang]; }

// ---- The founder's reading (rule 2 only) ----------------------------------------------------------
const fmt = (n: number | undefined) => new Intl.NumberFormat('en-US').format(Number(n || 0));

function lines(f: Figures, lang: Lang): string[] {
  return lang === 'ar' ? [
    '• الموردون: ' + fmt(f.suppliers?.registered) + ' مسجّل (' + fmt(f.suppliers?.registered_7d) + ' خلال 7 أيام)، و' + fmt(f.suppliers?.verified) + ' موثّق.',
    '• طلبات العملاء: ' + fmt(f.requests?.today) + ' اليوم، و' + fmt(f.requests?.last_7d) + ' خلال 7 أيام.',
    '• عروض الأسعار: ' + fmt(f.quotes?.total) + ' إجمالًا، و' + fmt(f.quotes?.last_7d) + ' خلال 7 أيام.',
    '• الكشف هذا الشهر: ' + fmt(f.reveals_month?.paid) + ' مدفوع، بقيمة ' + fmt(f.reveals_month?.fee_aed) + ' درهم.',
    '• الدعم: ' + fmt(f.support?.open_cases) + ' بلاغ مفتوح، و' + fmt(f.support?.waiting_for_person) + ' بانتظار رد أحد الموظفين.',
    '• التقنية: ' + fmt(f.it?.open_findings) + ' ملاحظة تقنية مفتوحة لدى مهندس تقنية المعلومات.',
    '• التسويق (7 أيام): ' + fmt(f.marketing_7d?.posts_published) + ' منشور، و' + fmt(f.marketing_7d?.posts_scheduled) + ' مجدول، وإنفاق إعلاني ' + fmt(f.marketing_7d?.ad_spend_aed) + ' درهم.',
  ] : [
    '• Suppliers: ' + fmt(f.suppliers?.registered) + ' registered (' + fmt(f.suppliers?.registered_7d) + ' in the last 7 days), ' + fmt(f.suppliers?.verified) + ' verified.',
    '• Customer requests: ' + fmt(f.requests?.today) + ' today, ' + fmt(f.requests?.last_7d) + ' in the last 7 days.',
    '• Quotes: ' + fmt(f.quotes?.total) + ' in total, ' + fmt(f.quotes?.last_7d) + ' in the last 7 days.',
    '• Reveals this month: ' + fmt(f.reveals_month?.paid) + ' paid, AED ' + fmt(f.reveals_month?.fee_aed) + ' in fees.',
    '• Support: ' + fmt(f.support?.open_cases) + ' open case(s), ' + fmt(f.support?.waiting_for_person) + ' waiting for a person.',
    '• IT: ' + fmt(f.it?.open_findings) + ' open technical finding(s) with the IT engineer.',
    '• Marketing (7 days): ' + fmt(f.marketing_7d?.posts_published) + ' post(s) published, ' + fmt(f.marketing_7d?.posts_scheduled) + ' scheduled, AED ' + fmt(f.marketing_7d?.ad_spend_aed) + ' ad spend.',
  ];
}

/** The internal reading, sent only on the FIGURES command from his number. */
export function figuresText(f: Figures, lang: Lang): string {
  if (!f?.ok) {
    return lang === 'ar' ? 'تعذّرت قراءة الأرقام الداخلية الآن، يُرجى المحاولة بعد قليل.' : 'The internal figures could not be read just now; please try again shortly.';
  }
  const head = lang === 'ar'
    ? 'الأرقام الداخلية (' + (f.read_at_local || '') + ' بتوقيت الإمارات)، للاطلاع الداخلي فقط:'
    : 'Internal figures at ' + (f.read_at_local || '') + ' (UAE time), for internal use only:';
  return head + '\n' + lines(f, lang).join('\n');
}

/** Not recognised: what can be answered without the model, and how to ask for the figures. No reading. */
export function founderHelp(lang: Lang): string {
  return lang === 'ar'
    ? 'تُرسل الأرقام الداخلية فقط عند كتابة كلمة «أرقام» وحدها في الرسالة: الموردون المسجّلون والموثّقون، وطلبات العملاء، وعروض الأسعار، وعمليات الكشف والرسوم هذا الشهر، وبلاغات الدعم، والملاحظات التقنية المفتوحة، وأرقام التسويق. أما غير ذلك فيحتاج إلى النموذج، وهو موقوف حاليًا، وقد سجّلتُ سؤالكم لدى الفريق.'
    : 'Internal figures are sent only when you write FIGURES as the whole message: suppliers registered and verified, customer requests, quotes, reveals and fees this month, support cases, open IT findings and marketing. Anything else needs the model, which is on hold, so I have recorded your question for the team.';
}
