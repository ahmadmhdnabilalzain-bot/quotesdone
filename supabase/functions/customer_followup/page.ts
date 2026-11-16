// The one-tap follow-up page (customer_support, founder_instruction 1013 item 1): "did you hire, and how was the
// supplier?". Pure rendering and form parsing, so page.test.ts can hold it without a database.
//
// GET shows the question and never writes: a mail scanner that opens every link records nothing. Only the POST
// from the form records the answer (fn_customer_followup_answer). The page is in the language the question was
// asked in (customer_followup.lang = the inquiry's language), with dir="rtl" for Arabic.

export type View = {
  ok: boolean; lang?: 'en' | 'ar'; stage?: string; company?: string | null; rfq_no?: number | null;
  trade?: string | null; answered?: boolean; hired?: string | null; stars?: number | null;
  contacted?: string | null; contact_known?: boolean;
};
type Tri = 'yes' | 'no' | 'not_yet';
export type Answer = { hired: Tri | null; stars: number | null; comment: string | null; contacted: Tri | null };
// THE CONTACT QUESTION (16 Nov 2026, customer_support, AFTER_REVEAL; holes CUSTOMER.md items 1 and 2). Working day 2
// (stage day_two_contact) asks only "has <supplier> contacted you?"; day 3 and day 14 ask it FIRST, unless he already told us
// the supplier did contact him (contact_known). His answer is read by the refund ladder beside the supplier's click, and a
// "never contacted" answer writes no review (fn_customer_followup_answer), so our own survey cannot bar the refund the Terms promise.

const T = {
  en: {
    title: 'Did you hire them?', q1: 'Did you hire', q2: 'How was the supplier?', yes: 'Yes, I hired them',
    no: 'No, I did not', notYet: 'Not decided yet', none: 'Skip', comment: 'Anything we should know? (optional)',
    send: 'Send', thanks: 'Thank you, your answer is recorded.', thanksBody: 'It helps us match you, and every customer after you, with better suppliers.',
    already: 'You have already answered this question. Thank you.', invalid: 'This link is not valid. Please use the link from your latest QuotesDone e-mail.',
    error: 'We could not record your answer right now. Please try again shortly, or reply to the e-mail.', supplier: 'the supplier',
    request: 'for your request',
    cTitle: 'Has the supplier contacted you?', c1: 'Has', c2: 'contacted you yet, by phone, WhatsApp, e-mail or a visit?',
    cYes: 'Yes, they contacted me', cNo: 'No, they have not', cNotYet: 'Not yet, but it is early',
    cThanks: 'Thank you, your answer is recorded.', cThanksBody: 'If the supplier has not contacted you, you do not need to do anything else: we chase them for you, and if they respond neither to you nor to us by the fifth working day after your payment, everything you paid for the reveal is refunded.',
  },
  ar: {
    title: 'هل تعاقدتم معه؟', q1: 'هل تعاقدتم مع', q2: 'كيف كانت تجربتكم مع المورّد؟', yes: 'نعم، تعاقدت معه',
    no: 'لا، لم أتعاقد', notYet: 'لم أقرّر بعد', none: 'تخطٍّ', comment: 'هل من ملاحظة تودّون إضافتها؟ (اختياري)',
    send: 'إرسال', thanks: 'شكرًا لكم، سُجّلت إجابتكم.', thanksBody: 'تساعدنا إجابتكم على مطابقتكم، ومطابقة كل عميل بعدكم، مع موردين أفضل.',
    already: 'سبق أن أجبتم عن هذا السؤال. شكرًا لكم.', invalid: 'هذا الرابط غير صالح. يُرجى استخدام الرابط الوارد في أحدث رسالة من QuotesDone.',
    error: 'تعذّر تسجيل إجابتكم الآن. يُرجى المحاولة بعد قليل، أو الرد على الرسالة.', supplier: 'المورّد',
    request: 'لطلبكم رقم',
    cTitle: 'هل تواصل معكم المورّد؟', c1: 'هل تواصل معكم', c2: 'حتى الآن، هاتفيًا أو عبر واتساب أو البريد الإلكتروني أو بزيارة؟',
    cYes: 'نعم، تواصل معي', cNo: 'لا، لم يتواصل', cNotYet: 'ليس بعد، وما زال الوقت مبكرًا',
    cThanks: 'شكرًا لكم، سُجّلت إجابتكم.', cThanksBody: 'وإن لم يتواصل معكم المورّد، فلا يلزمكم أي إجراء آخر: سنتابعه نيابةً عنكم، وإن لم يردّ عليكم ولا علينا حتى يوم العمل الخامس بعد الدفع، فسيُردّ إليكم كامل ما دفعتموه مقابل الكشف.',
  },
};

const esc = (s: unknown) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!));

function shell(lang: 'en' | 'ar', title: string, inner: string): string {
  return `<!doctype html><html lang="${lang}" dir="${lang === 'ar' ? 'rtl' : 'ltr'}"><head><meta charset="utf-8">`
    + `<meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex"><title>${esc(title)} · QuotesDone</title>`
    + `<style>body{margin:0;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,Tahoma,sans-serif;background:#0a1a24;color:#eaf2f6;display:flex;min-height:100vh;align-items:center;justify-content:center}`
    + `.card{max-width:480px;width:100%;margin:16px;background:#0f2735;border:1px solid #1d3a4a;border-radius:16px;overflow:hidden}`
    + `.hd{background:#0c2330;padding:20px 24px;border-bottom:2px solid #17b3a6;font-weight:700}.bd{padding:22px 24px;line-height:1.6}`
    + `fieldset{border:0;padding:0;margin:0 0 18px}legend{font-weight:600;margin-bottom:8px}label{display:flex;gap:10px;align-items:center;min-height:44px}`
    + `textarea{width:100%;box-sizing:border-box;min-height:80px;border-radius:10px;border:1px solid #1d3a4a;background:#0a1a24;color:#eaf2f6;padding:10px;font:inherit}`
    + `button{min-height:44px;padding:10px 22px;border:0;border-radius:10px;background:#17b3a6;color:#04151c;font-weight:700;font-size:15px;cursor:pointer}`
    + `.stars{display:flex;flex-wrap:wrap;gap:6px}.stars label{border:1px solid #1d3a4a;border-radius:10px;padding:0 12px}</style></head>`
    + `<body><main class="card"><div class="hd">QuotesDone</div><div class="bd">${inner}</div></main></body></html>`;
}

export function messagePage(lang: 'en' | 'ar', key: 'thanks' | 'contact_thanks' | 'already' | 'invalid' | 'error'): string {
  const t = T[lang];
  const body = key === 'thanks' ? `<p><strong>${t.thanks}</strong></p><p>${t.thanksBody}</p>`
    : key === 'contact_thanks' ? `<p><strong>${t.cThanks}</strong></p><p>${t.cThanksBody}</p>` : `<p>${t[key]}</p>`;
  return shell(lang, key === 'thanks' ? t.thanks : key === 'contact_thanks' ? t.cThanks : t.title, body);
}

export function questionPage(v: View, token: string): string {
  const lang = v.lang === 'ar' ? 'ar' : 'en';
  const t = T[lang];
  const who = esc(v.company || t.supplier);
  const ref = v.rfq_no ? ` ${t.request} ${lang === 'ar' ? '' : 'RFQ-'}${esc(v.rfq_no)}${v.trade ? ` (${esc(v.trade)})` : ''}` : '';
  const radio = (name: string, value: string, label: string, req = false) =>
    `<label><input type="radio" name="${name}" value="${value}"${req ? ' required' : ''}> ${label}</label>`;
  const contact = `<fieldset><legend>${t.c1} ${who} ${t.c2}</legend>${radio('contacted', 'yes', t.cYes, true)}${radio('contacted', 'no', t.cNo)}${radio('contacted', 'not_yet', t.cNotYet)}</fieldset>`;
  if (v.stage === 'day_two_contact') {
    // a "yes" stands; a "no" or "not yet" may be given again (the supplier's click sends this same link)
    if (v.contacted === 'yes' || v.contact_known) return messagePage(lang, 'already');
    return shell(lang, t.cTitle, `<form method="post" action="?t=${encodeURIComponent(token)}">${contact}`
      + `<fieldset><legend><label for="c" style="min-height:0">${t.comment}</label></legend><textarea id="c" name="comment" maxlength="1000"></textarea></fieldset>`
      + `<button type="submit">${t.send}</button></form>`);
  }
  if (v.answered && (v.hired === 'yes' || v.hired === 'no')) return messagePage(lang, 'already');
  const stars = [1, 2, 3, 4, 5].map((n) => radio('stars', String(n), '★'.repeat(n))).join('');
  return shell(lang, t.title, `<form method="post" action="?t=${encodeURIComponent(token)}">`
    + (v.contact_known ? '' : contact)
    + `<fieldset><legend>${t.q1} ${who}${ref}?</legend>${radio('hired', 'yes', t.yes, true)}${radio('hired', 'no', t.no)}${radio('hired', 'not_yet', t.notYet)}</fieldset>`
    + `<fieldset><legend>${t.q2}</legend><div class="stars">${stars}${radio('stars', '', t.none)}</div></fieldset>`
    + `<fieldset><legend><label for="c" style="min-height:0">${t.comment}</label></legend><textarea id="c" name="comment" maxlength="1000"></textarea></fieldset>`
    + `<button type="submit">${t.send}</button></form>`);
}

const tri = (x: string | null): Tri | null => (x === 'yes' || x === 'no' || x === 'not_yet' ? x : null);
// The form body, validated. null = not an answer (the page is shown again rather than a guess recorded). Working day 2 is answered
// by the contact word alone; day 3 and day 14 by "hired", with the contact word when it was asked.
export function parseAnswer(form: URLSearchParams, stage?: string): Answer | null {
  const contacted = tri(form.get('contacted'));
  const c = (form.get('comment') || '').trim().slice(0, 1000);
  if (stage === 'day_two_contact') return contacted ? { hired: null, stars: null, comment: c || null, contacted } : null;
  const hired = tri(form.get('hired'));
  if (!hired) return null;
  const s = form.get('stars');
  const n = s ? Number(s) : NaN;
  const stars = Number.isInteger(n) && n >= 1 && n <= 5 ? n : null;
  return { hired, stars, comment: c || null, contacted };
}

export const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
