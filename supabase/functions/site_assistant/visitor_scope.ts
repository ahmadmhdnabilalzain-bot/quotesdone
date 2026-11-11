// THE HOMEPAGE WIDGET FOR A VISITOR WHO IS NOT SIGNED UP (founder ruling, 18 Oct 2026). Seat: customer_support.
// The widget answers general questions only: what QuotesDone is, what it does, how it works, the fees, and trust.
// Its job is to guide the visitor to registration. It never collects an inquiry (no materials, dimensions, specs or
// design discussion): the moment a visitor shows a real need it tells them to sign up, and the sales engineer carries
// on in the portal. Rulings 1195/1196 stand: the reply is model-written from these rules and the brief; only the
// message cap and the sign-up button are code.
// 27 Oct 2026 (founder_instruction 1339): the reply past the cap is model-written too (capReplyByModel); capReply's
// text is the OpenRouter-outage fallback only, through modelOrOutage in index.ts.
// prevented by: site_assistant/visitor_scope.test.ts; live: scripts/eval/widget_visitor_scope.mjs
import { aiReply, type AiReply } from '../_shared/ai_reply.ts';
import type { ThinkDeps } from '../_shared/think.ts';

export type Lang = 'en' | 'ar';
export type Audience = 'customer' | 'supplier' | 'unknown';

/** Messages a visitor may send before every reply is the sign-up direction. Per conversation (the widget's session
 *  id) per day, and per IP per day at five times that, because one office or a mobile carrier puts many people
 *  behind one address. Both are read from app_secrets (site_assistant_visitor_conv_day / _ip_day) when set. */
export const VISITOR_CAP = { conv: 8, ip: 40 } as const;

/** Where a visitor registers. Suppliers register in the supplier portal (English only); everyone else in /me. */
export function signupAction(audience: Audience, lang: Lang): { url: string; label: string } {
  if (audience === 'supplier') return { url: '/portal', label: 'Register as a supplier (free)' };
  return lang === 'ar'
    ? { url: '/ar/me', label: 'سجّل مجانًا وأرسل طلبك' }
    : { url: '/me', label: 'Sign up free and send your request' };
}

/** The system-prompt rules for a visitor. They replace the expert-follow-up rule that signed-in callers get. */
export function visitorRules(audience: Audience, lang: Lang): string {
  const { url } = signupAction(audience, lang);
  return `THIS IS THE PUBLIC WEBSITE CHAT AND THIS VISITOR IS NOT SIGNED UP (founder rulings 1249 and 18 Oct 2026). Your only job here is general questions and guiding them to sign up:
- Answer only general questions: what QuotesDone is, what it does, how it works, how to register, the fees, and why it can be trusted (anonymity, verified suppliers, refunds as the COMPANY BRIEF states them).
- Never collect or discuss the details of a job: no materials, dimensions, sizes, quantities, specifications, finishes, location, budget, drawings, designs (a wardrobe, a kitchen, a ceiling) and no prices for a specific job. Never ask them a question about their job. Nothing they write here is recorded on a request, so never say a detail was noted on, recorded, saved or updated in their request (conversation-quality run, 3 Nov 2026: "your note has been recorded", then "I cannot take job details here").
- As soon as they show they have an actual job, need or inquiry, or ask for suppliers or quotes, tell them in a sentence or two to sign up free at ${url} and send it there; we then match it to verified suppliers and our sales engineer takes it from there with them. Do not ask anything about the job first. Promise nothing else about what happens after sign-up: they post the request there themselves, so never say they will not need to repeat anything (conversation-quality run, 3 Nov 2026).
- The sign-up link is ${url}. Put it on its own line.`;
}

/** The CODE-WRITTEN reply once a visitor has used their messages: sign-up only, in their language. Since 27 Oct 2026
 *  (founder_instruction 1339) it is sent ONLY when OpenRouter is down (modelOrOutage over capReplyByModel). */
export function capReply(audience: Audience, lang: Lang): string {
  const { url } = signupAction(audience, lang);
  if (lang === 'ar' && audience !== 'supplier') {
    return `لقد استخدمت عدد الرسائل المتاح للزوار. للمتابعة، سجّل مجانًا وسيكمل معك مهندس المبيعات لدينا داخل حسابك:\n${url}`;
  }
  return audience === 'supplier'
    ? `You have used the messages available to visitors. To continue, register free as a supplier and we will carry on with you in the supplier portal:\n${url}`
    : `You have used the messages available to visitors. To continue, sign up free and our sales engineer will carry on with you in your account:\n${url}`;
}

/** THE CODE-WRITTEN LINE FOR A TURN NO MODEL ANSWERED IN TIME (it_engineer, 11 Nov 2026, load test, ruling 1622). Sent
 *  ONLY when no call reached a model (founder_instruction 1339: OpenRouter down, our turn's deadline, an open circuit),
 *  through modelOrOutage in turn_outcome.ts. Before it, such a turn ended in HTTP 503 {error:'no_answer'} and the widget
 *  showed "something went wrong". It says what happened and what to do, and gives the published contact (FACTS_SHARED). */
export function busyReply(audience: Audience, lang: Lang): string {
  if (lang === 'ar' && audience !== 'supplier') {
    return `عذرًا، لم أتمكن من إكمال إجابتك الآن لأن المحادثة مزدحمة جدًا. يُرجى إرسال سؤالك مرة أخرى بعد دقيقة.\nللتواصل مع أحد أعضاء الفريق:\n+1 218 316 6814 (واتساب، من الاثنين إلى الجمعة، 9 صباحًا حتى 6 مساءً بتوقيت الخليج)\nmanagement@quotesdone.com`;
  }
  return `Sorry, I could not finish your answer just now because the chat is very busy. Please send your question again in a minute.\nTo reach a person:\n+1 218 316 6814 (WhatsApp, Mon-Fri 9am-6pm GST)\nmanagement@quotesdone.com`;
}

/** True when this visitor message is past the cap. `hit` is the rate limiter (it counts the message and answers
 *  whether it is still within the limit). The conversation is counted first; the IP only when the conversation
 *  is within its cap, so a stopped conversation does not use up the rest of an office's allowance. */
export async function pastVisitorCap(
  hit: (key: string, limit: number, seconds: number) => Promise<boolean>,
  o: { ip: string; conv: string; cap?: { conv: number; ip: number } },
): Promise<boolean> {
  const cap = o.cap ?? VISITOR_CAP;
  if (o.conv && !(await hit('site_assistant_visitor_conv_day:' + o.conv, cap.conv, 86400))) return true;
  return !(await hit('site_assistant_visitor_ip_day:' + o.ip, cap.ip, 86400));
}

/** What the model is told to write past the cap. Code decides WHAT (sign-up only, no answer); the words are the model's.
 *  Nothing internal is given to it (ledger 1338): the cap's number, the counting and the reason stay out. */
export function capRules(audience: Audience, lang: Lang): string {
  const { url } = signupAction(audience, lang);
  return `THIS VISITOR HAS USED THE MESSAGES AVAILABLE TO VISITORS WHO ARE NOT SIGNED UP. Do not answer or discuss their message. In one or two short sentences, thank them, say that to continue they ${audience === 'supplier' ? 'register free as a supplier and we carry on with them in the supplier portal' : 'sign up free and our sales engineer carries on with them in their account'}, and put the link ${url} on its own line at the end. If they ask for a person, a human or someone to call, also give the published contact, each on its own line: ${PERSON_CONTACT}. Ask nothing, give no price, count or any other number, and never mention a limit's number, a system or anything internal.`;
}
// The published contact (site_assistant FACTS_SHARED, /contact/). A capped visitor who asked for a person was given the
// sign-up line alone in 4 of 5 live runs (3 Nov 2026): the rule said "give no number" and the facts held only the link.
// prevented by: site_assistant/a_capped_visitor_who_asks_for_a_person_gets_the_contact.test.ts
export const PERSON_CONTACT = 'WhatsApp +1 218 316 6814 (Mon-Fri 9am-6pm GST) and management@quotesdone.com';

/** The cap reply WRITTEN BY THE MODEL: one bounded aiReply (at most 20 s; MAX_CALLS calls), the sign-up link a
 *  must-carry. Returns aiReply's reply and outage for modelOrOutage. A throw before any model call is not an outage. */
export async function capReplyByModel(deps: ThinkDeps, o: { audience: Audience; lang: Lang; message: string; subject?: Record<string, unknown> },
  write: typeof aiReply = aiReply): Promise<Pick<AiReply, 'reply' | 'outage' | 'attempts'>> {
  const { url } = signupAction(o.audience, o.lang);
  try {
    return await write(deps, { seat: 'customer_support', channel: 'the quotesdone.com website chat', audience: o.audience === 'supplier' ? 'supplier' : 'visitor',
      lang: o.lang, message: o.message.slice(0, 1000), rules: capRules(o.audience, o.lang), facts: 'THE SIGN-UP LINK: ' + url + '\nTHE PUBLISHED CONTACT FOR A PERSON: ' + PERSON_CONTACT, must: [url],
      deadline: Date.now() + 20_000, ...(o.subject ? { subject: o.subject } : {}) });
  } catch (e) {
    return { reply: '', outage: false, attempts: ['threw: ' + String((e as Error)?.message || e).slice(0, 120)] };
  }
}
