// The one-tap follow-up page (customer_support, founder_instruction 1013 item 1): "did you hire, and how was the
// supplier?". Pure rendering and form parsing, so page.test.ts can hold it without a database.
//
// GET shows the question and never writes: a mail scanner that opens every link records nothing. Only the POST
// from the form records the answer (fn_customer_followup_answer). The page is in the language the question was
// asked in (customer_followup.lang = the inquiry's language), with dir="rtl" for Arabic.

export type View = {
  ok: boolean; lang?: 'en' | 'ar'; stage?: string; company?: string | null; rfq_no?: number | null;
  trade?: string | null; answered?: boolean; hired?: string | null; stars?: number | null;
};
export type Answer = { hired: 'yes' | 'no' | 'not_yet'; stars: number | null; comment: string | null };

const T = {
  en: {
    title: 'Did you hire them?', q1: 'Did you hire', q2: 'How was the supplier?', yes: 'Yes, I hired them',
    no: 'No, I did not', notYet: 'Not decided yet', none: 'Skip', comment: 'Anything we should know? (optional)',
    send: 'Send', thanks: 'Thank you, your answer is recorded.', thanksBody: 'It helps us match you, and every customer after you, with better suppliers.',
    already: 'You have already answered this question. Thank you.', invalid: 'This link is not valid. Please use the link from your latest QuotesDone e-mail.',
    error: 'We could not record your answer right now. Please try again shortly, or reply to the e-mail.', supplier: 'the supplier',
    request: 'for your request',
  },
  ar: {
    title: 'هل تعاقدتم معه؟', q1: 'هل تعاقدتم مع', q2: 'كيف كانت تجربتكم مع المورّد؟', yes: 'نعم، تعاقدت معه',
    no: 'لا، لم أتعاقد', notYet: 'لم أقرّر بعد', none: 'تخطٍّ', comment: 'هل من ملاحظة تودّون إضافتها؟ (اختياري)',
    send: 'إرسال', thanks: 'شكرًا لكم، سُجّلت إجابتكم.', thanksBody: 'تساعدنا إجابتكم على مطابقتكم، ومطابقة كل عميل بعدكم، مع موردين أفضل.',
    already: 'سبق أن أجبتم عن هذا السؤال. شكرًا لكم.', invalid: 'هذا الرابط غير صالح. يُرجى استخدام الرابط الوارد في أحدث رسالة من QuotesDone.',
    error: 'تعذّر تسجيل إجابتكم الآن. يُرجى المحاولة بعد قليل، أو الرد على الرسالة.', supplier: 'المورّد',
    request: 'لطلبكم رقم',
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

export function messagePage(lang: 'en' | 'ar', key: 'thanks' | 'already' | 'invalid' | 'error'): string {
  const t = T[lang];
  const body = key === 'thanks' ? `<p><strong>${t.thanks}</strong></p><p>${t.thanksBody}</p>` : `<p>${t[key]}</p>`;
  return shell(lang, key === 'thanks' ? t.thanks : t.title, body);
}

export function questionPage(v: View, token: string): string {
  const lang = v.lang === 'ar' ? 'ar' : 'en';
  const t = T[lang];
  if (v.answered && (v.hired === 'yes' || v.hired === 'no')) return messagePage(lang, 'already');
  const who = esc(v.company || t.supplier);
  const ref = v.rfq_no ? ` ${t.request} ${lang === 'ar' ? '' : 'RFQ-'}${esc(v.rfq_no)}${v.trade ? ` (${esc(v.trade)})` : ''}` : '';
  const radio = (name: string, value: string, label: string, req = false) =>
    `<label><input type="radio" name="${name}" value="${value}"${req ? ' required' : ''}> ${label}</label>`;
  const stars = [1, 2, 3, 4, 5].map((n) => radio('stars', String(n), '★'.repeat(n))).join('');
  return shell(lang, t.title, `<form method="post" action="?t=${encodeURIComponent(token)}">`
    + `<fieldset><legend>${t.q1} ${who}${ref}?</legend>${radio('hired', 'yes', t.yes, true)}${radio('hired', 'no', t.no)}${radio('hired', 'not_yet', t.notYet)}</fieldset>`
    + `<fieldset><legend>${t.q2}</legend><div class="stars">${stars}${radio('stars', '', t.none)}</div></fieldset>`
    + `<fieldset><legend><label for="c" style="min-height:0">${t.comment}</label></legend><textarea id="c" name="comment" maxlength="1000"></textarea></fieldset>`
    + `<button type="submit">${t.send}</button></form>`);
}

// The form body, validated. null = not an answer (the page is shown again rather than a guess recorded).
export function parseAnswer(form: URLSearchParams): Answer | null {
  const hired = form.get('hired');
  if (hired !== 'yes' && hired !== 'no' && hired !== 'not_yet') return null;
  const s = form.get('stars');
  const n = s ? Number(s) : NaN;
  const stars = Number.isInteger(n) && n >= 1 && n <= 5 ? n : null;
  const c = (form.get('comment') || '').trim().slice(0, 1000);
  return { hired, stars, comment: c || null };
}

export const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
