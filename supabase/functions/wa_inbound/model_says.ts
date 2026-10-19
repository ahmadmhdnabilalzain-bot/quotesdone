// model_says — every CONVERSATION reply on WhatsApp is written by a model in that turn. Seat: customer_support.
// Founder rulings 1195/1196/1197 (12 Oct 2026): code decides WHAT happened (a routine's result, a document's read,
// a menu option's own data) and hands it over as facts; the words are the model's (_shared/ai_reply.ts: the company
// brief, the model ladder, the figure + reply guard with a model rewrite, suppliers always in English).
// Code never substitutes text: when no model answers, the reply is '' and NOTHING conversational is sent.
// Notifications (OTP, receipts, case-reference receipts, status notices, the accepted-offer confirmation, the
// founder's FIGURES report) are not conversation and do not come through here.
// prevented by: wa_inbound/model_says.test.ts, wa_inbound/menu_flow_model_written.test.ts,
//               wa_inbound/no_unwritten_send.test.ts
import { aiReply } from '../_shared/ai_reply.ts';
import type { ThinkDeps, Turn } from '../_shared/think.ts';

export type SayAudience = 'customer' | 'supplier' | 'visitor' | 'founder';
export interface SayRequest {
  audience: SayAudience;
  lang: 'en' | 'ar';
  message: string;              // what the person wrote this turn
  situation: string;            // what code decided / the routine returned — the facts the reply must convey
  conversation?: Turn[];
  subject?: Record<string, unknown>;
  rateKey?: string;             // the per-sender ceiling at the gateway (wa:<From>, 20/hour)
  forbidden?: string[];         // another party's identity before a reveal: a hit is rewritten by the model
  budgetMs?: number;            // the reply's wall-clock budget (default WA_REPLY_BUDGET_MS)
}
// A WhatsApp reply is written within this, or the person gets the held notice and the turn is queued (run 5: 73.7 s).
export const WA_REPLY_BUDGET_MS = 45_000;
/** Time kept back from the budget for the send itself and the row write after the model answers. */
export const WA_SEND_MARGIN_MS = 3_000;
/** THE CLOCK STARTS AT ARRIVAL, NOT AT THE MODEL CALL (QA channels run, 19 Oct 2026). Measured on production: two
 *  plain questions spent ~45 s in serial routing/intent calls before modelSays began, then answered at 54-55 s with no
 *  held notice, because the 45 s deadline was counted from t0 inside modelSays. The budget handed to modelSays is what is
 *  left of 45 s since the message arrived; at 0 no call starts, the text is '' and the caller sends the held notice. */
export function budgetLeft(arrivedAtMs: number, nowMs: number = Date.now()): number {
  return Math.max(0, WA_REPLY_BUDGET_MS - WA_SEND_MARGIN_MS - (nowMs - arrivedAtMs));
}
export interface Said { text: string; model: string | null; attempts: string[]; ms: number; escalate: boolean }

export const WA_RULES = 'Plain text for WhatsApp (no markdown), under about 90 words; put each phone number, email or link on its own line, exactly as given in the facts.';

/** The model's words for this turn, or text '' when no model answered (the caller then sends nothing). */
export async function modelSays(deps: ThinkDeps, r: SayRequest): Promise<Said> {
  const t0 = Date.now();
  try {
    const out = await aiReply(deps, {
      seat: 'customer_support', channel: 'whatsapp', audience: r.audience, lang: r.lang,
      message: r.message || '(no text — they pressed a menu option or sent a file)',
      conversation: r.conversation,
      facts: 'WHAT HAS HAPPENED ON THIS TURN (decided by our systems; convey it accurately, do not change or add to it):\n' + r.situation,
      rules: WA_RULES, subject: r.subject, rateKey: r.rateKey, forbidden: r.forbidden, askEscalate: true,
      deadline: t0 + (r.budgetMs ?? WA_REPLY_BUDGET_MS),
    });
    return { text: String(out.reply || '').trim(), model: out.model, attempts: out.attempts, ms: Date.now() - t0, escalate: out.escalate === true };
  } catch (e) {
    return { text: '', model: null, attempts: ['error: ' + String((e as Error)?.message || e).slice(0, 120)], ms: Date.now() - t0, escalate: false };
  }
}

// ---- THE HELD NOTICE (review of #1335) -------------------------------------------------------------------------------
// No model answer (or a guard refusal after aiReply's own rewrites): the person is never left silent. They get this
// fixed receipt — a NOTIFICATION (ruling 1197: "we received your message"), never an answer — and the turn is filed
// for a model retry. Suppliers in English; everyone else in their language.
export const HELD_NOTICE: Record<'en' | 'ar', string> = {
  en: 'Thank you, we have received your message. Our team will reply to you here shortly.',
  ar: 'شكرًا لكم، وصلتنا رسالتكم، وسيرد عليكم فريقنا هنا قريبًا.',
};
export const UNWRITTEN_SURFACE = 'wa_inbound.unwritten_reply';
export interface HoldIO {
  from: string; body: string; messageSid: string | null;
  audience: SayAudience; lang: 'en' | 'ar'; situation: string; why: string;
  enabled(): Promise<boolean>;
  send(text: string): Promise<{ ok: boolean; err?: string }>;
  rpc(fn: string, args: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>;
}
/** Sends the held notice and files the turn in customer_support's queue; resilience_ping replays it through the model
 *  and delivers the written answer on WhatsApp, and escalates it to customer_support after 15 minutes. */
export async function holdUnwritten(io: HoldIO): Promise<{ notice: string; sent: boolean; err: string | null; held_id: number | null }> {
  const lang = io.audience === 'supplier' ? 'en' : io.lang;
  const notice = HELD_NOTICE[lang];
  let sent = false; let err: string | null = null;
  if (await io.enabled()) { const r = await io.send(notice).catch((e) => ({ ok: false, err: String(e) })); sent = r.ok; err = r.err ?? null; }
  else err = 'autoreply_disabled';
  const subject = { channel: 'whatsapp', phone: io.from, message_sid: io.messageSid };
  const question = io.body.slice(0, 4000) || '(no text)';
  let held_id: number | null = null;
  try {
    const { data } = await io.rpc('fn_reason_hold', {
      p_seat: 'customer_support', p_surface: UNWRITTEN_SURFACE, p_question: question,
      p_request: { seat: 'customer_support', surface: UNWRITTEN_SURFACE, subject,
        question: `Reply on WhatsApp to this ${io.audience} message, in ${lang === 'ar' ? 'formal Gulf Arabic' : 'UAE English'}${io.audience === 'supplier' ? ' (suppliers are always answered in English)' : ''}. They were told we received it and will reply shortly.\n\nWHAT HAPPENED ON THAT TURN (facts):\n${io.situation.slice(0, 3000)}\n\nMESSAGE:\n${question}`,
        context: { audience: io.audience === 'founder' ? 'founder' : io.audience, language: lang }, research: false },
      p_plan: {}, p_subject: subject, p_reason: io.why, p_dedupe_key: 'wa_unwritten:' + (io.messageSid || io.from + ':' + question.slice(0, 40)),
    });
    held_id = Number(data) || null;
  } catch (_e) { /* the notice already went out; the 15-minute escalation reads the queue, and the row says unfiled */ }
  return { notice, sent, err, held_id };
}
