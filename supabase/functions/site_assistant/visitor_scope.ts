// THE HOMEPAGE WIDGET FOR A VISITOR WHO IS NOT SIGNED UP (founder ruling, 18 Oct 2026). Seat: customer_support.
// The widget answers general questions only: what QuotesDone is, what it does, how it works, the fees, and trust.
// Its job is to guide the visitor to registration. It never collects an inquiry (no materials, dimensions, specs or
// design discussion): the moment a visitor shows a real need it tells them to sign up, and the sales engineer carries
// on in the portal. Rulings 1195/1196 stand: the reply is model-written from these rules and the brief; only the
// message cap and the sign-up button are code.
// prevented by: site_assistant/visitor_scope.test.ts; live: scripts/eval/widget_visitor_scope.mjs

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
- Never collect or discuss the details of a job: no materials, dimensions, sizes, quantities, specifications, finishes, location, budget, drawings, designs (a wardrobe, a kitchen, a ceiling) and no prices for a specific job. Never ask them a question about their job.
- As soon as they show they have an actual job, need or inquiry, or ask for suppliers or quotes, tell them in a sentence or two to sign up free at ${url} and send it there; we then match it to verified suppliers and our sales engineer takes it from there with them. Do not ask anything about the job first.
- The sign-up link is ${url}. Put it on its own line.`;
}

/** The reply once a visitor has used their messages: sign-up only, in their language. No model is called past the
 *  cap; that is the point of the cap. */
export function capReply(audience: Audience, lang: Lang): string {
  const { url } = signupAction(audience, lang);
  if (lang === 'ar' && audience !== 'supplier') {
    return `لقد استخدمت عدد الرسائل المتاح للزوار. للمتابعة، سجّل مجانًا وسيكمل معك مهندس المبيعات لدينا داخل حسابك:\n${url}`;
  }
  return audience === 'supplier'
    ? `You have used the messages available to visitors. To continue, register free as a supplier and we will carry on with you in the supplier portal:\n${url}`
    : `You have used the messages available to visitors. To continue, sign up free and our sales engineer will carry on with you in your account:\n${url}`;
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
