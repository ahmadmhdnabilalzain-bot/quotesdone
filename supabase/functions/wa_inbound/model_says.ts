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
  must?: string[];              // text the reply must carry exactly (a job number, a case reference)
  signal?: AbortSignal;         // a speculative draft that was discarded: abort it
  extraCheck?: (text: string) => string[];   // the turn's own rule: a draft it names a problem in is rewritten, never sent
  situationAnswers?: boolean;   // the facts alone say what to tell them (a person is needed): the brief-less last chance may run
}
// A VOICE NOTE REPLY NEVER ASKS FOR A DOCUMENT (customer_support, 3 Nov 2026). Measured on the real exchange on main
// (run 41528725657, after f6dcbe7d): the voice turn came after four licence/file turns in the same chat, the model saw them
// (the whole conversation rides with every turn since #1758) and added "If it is your trade licence, you can also send it
// as a PDF or a clear photo". The situation only told it what to say, not what not to; the reply is now refused and rewritten.
export function voiceReplyProblems(text: string): string[] {
  return /trade licen|\bpdf\b|photo of|upload/i.test(text)
    ? ['it asks for or mentions a document (licence, PDF, photo, upload) in a reply to a voice note that nobody heard'] : [];
}
// A WhatsApp reply is written within this, or the person gets the held notice and the turn is queued (run 5: 73.7 s).
// 2 Nov 2026: 90 s, was 45. The webhook is acknowledged at once (ackThenWork), so the wall is the edge worker's background
// limit (150 s), not Twilio's 15 s. Measured on the real exchange: classification 17-24 s, reply 2-20 s, so 45 s left 2-3 turns
// in 12 with no reply and the queue's answer ~80 s later; a model answer at 50-60 s is sooner and nothing is code-written.
export const WA_REPLY_BUDGET_MS = 90_000;
/** Time kept back from the budget for the send itself and the row write after the model answers. */
export const WA_SEND_MARGIN_MS = 3_000;
/** The one extra, brief-less ask when nothing passed inside the budget (modelSays). 90 + 20 s stays inside the worker's 150 s. */
export const LAST_CHANCE_MS = 20_000;
/** THE CLOCK STARTS AT ARRIVAL, NOT AT THE MODEL CALL (QA channels run, 19 Oct 2026). Measured on production: two
 *  plain questions spent ~45 s in serial routing/intent calls before modelSays began, then answered at 54-55 s with no
 *  held notice, because the 45 s deadline was counted from t0 inside modelSays. The budget handed to modelSays is what is
 *  left of 45 s since the message arrived; at 0 no call starts, the text is '' and the caller sends the held notice. */
export function budgetLeft(arrivedAtMs: number, nowMs: number = Date.now()): number {
  return Math.max(0, WA_REPLY_BUDGET_MS - WA_SEND_MARGIN_MS - (nowMs - arrivedAtMs));
}
/** outage: no call reached a model (openrouter_down.ts) — the only case the held notice, a code-written line, may go out. */
export interface Said { text: string; model: string | null; attempts: string[]; ms: number; escalate: boolean; outage: boolean; problems?: string[] }

export const WA_RULES = 'Plain text for WhatsApp (no markdown), under about 90 words; put each phone number, email or link on its own line, exactly as given in the facts.';

/** The model's words for this turn, or text '' when no model answered (the caller then sends nothing). */
export async function modelSays(deps: ThinkDeps, r: SayRequest): Promise<Said> {
  const t0 = Date.now();
  try {
    const ask = (deadline: number, o: { briefInPrompt?: boolean; priorProblems?: string[] } = {}) => aiReply(deps, {
      seat: 'customer_support', channel: 'whatsapp', audience: r.audience, lang: r.lang,
      message: r.message || '(no text — they pressed a menu option or sent a file)',
      conversation: r.conversation,
      facts: 'WHAT HAS HAPPENED ON THIS TURN (decided by our systems; convey it accurately, do not change or add to it):\n' + r.situation,
      rules: WA_RULES, subject: r.subject, rateKey: r.rateKey, forbidden: r.forbidden, askEscalate: true, must: r.must, ...(r.signal ? { signal: r.signal } : {}), ...(r.extraCheck ? { extraCheck: r.extraCheck } : {}),
      deadline, ...o,
    });
    let out = await ask(t0 + (r.budgetMs ?? WA_REPLY_BUDGET_MS));
    let attempts = out.attempts;
    // THE LAST CHANCE (customer_support, 3 Nov 2026; "every inbound message gets an answer"). Run 41530397323: the lean "scam"
    // turn's model WAS up, its Sonnet draft could not be used, the other-family call ran into the budget, and the person got
    // nothing for the turn (held for the re-ask). Now, when a model answered but nothing passed, or the budget ran out before
    // one could, it is asked ONCE more, bounded by LAST_CHANCE_MS: the rules and this turn's facts without the ~140k-token
    // brief (a few seconds), the refused drafts' problems named, every check unchanged. Still model-written (1195-1197, 1339).
    // Not for a speculative draft (signal) and not in an outage (the held notice owns that). Prevented by: model_says.test.ts.
    // ONLY WHEN THE FACTS ALONE ANSWER THE TURN (review of #1816): without the brief a company question ("how do you vet
    // suppliers?") could only be answered from memory, so the caller opts in (situationAnswers) for a turn whose facts say what
    // happens, a person being needed above all, and the brief-less prompt says nothing about the company beyond its facts.
    if (r.situationAnswers === true && !String(out.reply || '').trim() && !out.outage && !r.signal) {
      const last = await ask(Date.now() + LAST_CHANCE_MS, { briefInPrompt: false, priorProblems: out.problems });
      attempts = [...attempts, ...last.attempts.map((a) => 'last-chance ' + a)];
      if (String(last.reply || '').trim()) out = last;
      else out = { ...out, problems: last.problems?.length ? last.problems : out.problems };
    }
    return { text: String(out.reply || '').trim(), model: out.model, attempts, ms: Date.now() - t0, escalate: out.escalate === true, outage: out.outage === true, problems: out.problems ?? [] };
  } catch (e) {
    // aiReply never throws on a model failure; a throw here is our own fault, not a provider outage
    return { text: '', model: null, attempts: ['error: ' + String((e as Error)?.message || e).slice(0, 120)], ms: Date.now() - t0, escalate: false, outage: false };
  }
}

// ---- THE HELD NOTICE (review of #1335; founder_instruction 1339, 27 Oct 2026) ------------------------------------------
// No model answer: the turn is filed for a model retry (resilience_ping replays it and sends the model's words). The
// fixed receipt below goes out ONLY when OpenRouter is down (Said.outage — no call reached a model): "the engineer and
// customer support never replies without llm unless the server of open router is down". When a model answered and
// every draft was refused, nothing code-written is sent: the replay answers. Suppliers in English; others in their language.
export const HELD_NOTICE: Record<'en' | 'ar', string> = {
  en: 'Thank you, we have received your message. Our team will reply to you here shortly.',
  ar: 'شكرًا لكم، وصلتنا رسالتكم، وسيرد عليكم فريقنا هنا قريبًا.',
};
export const UNWRITTEN_SURFACE = 'wa_inbound.unwritten_reply';
export interface HoldIO {
  from: string; body: string; messageSid: string | null;
  audience: SayAudience; lang: 'en' | 'ar'; situation: string; why: string;
  /** OpenRouter was down for this turn (Said.outage): only then is the fixed notice sent. */
  outage: boolean;
  /** Why the model's drafts were refused (aiReply.problems): the re-ask names them to the model (_shared/reask.ts). */
  problems?: string[];
  enabled(): Promise<boolean>;
  send(text: string): Promise<{ ok: boolean; err?: string }>;
  rpc(fn: string, args: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>;
}
/** Sends the held notice (outage only) and files the turn in customer_support's queue. The re-ask (_shared/reask.ts, a
 *  pg_cron check every minute) asks the model again within about a minute, on another family with the refused drafts'
 *  problems named, and delivers the written answer here; after REASK_MAX_ATTEMPTS refusals the turn is handed to
 *  customer_support. request.reask carries the turn as data; context.turn_id makes each turn its own question (two
 *  people sending the same words were one qhash, and a failed one swallowed the other's turn in fn_reason_hold). */
export async function holdUnwritten(io: HoldIO): Promise<{ notice: string; sent: boolean; err: string | null; held_id: number | null }> {
  const lang = io.audience === 'supplier' ? 'en' : io.lang;
  const notice = io.outage ? HELD_NOTICE[lang] : '';
  let sent = false; let err: string | null = null;
  if (!notice) err = 'model_up_no_safe_reply: queued for the model, no code-written notice (1339)';
  else if (await io.enabled()) { const r = await io.send(notice).catch((e) => ({ ok: false, err: String(e) })); sent = r.ok; err = r.err ?? null; }
  else err = 'autoreply_disabled';
  const subject = { channel: 'whatsapp', phone: io.from, message_sid: io.messageSid };
  const question = io.body.slice(0, 4000) || '(no text)';
  let held_id: number | null = null;
  try {
    const { data } = await io.rpc('fn_reason_hold', {
      p_seat: 'customer_support', p_surface: UNWRITTEN_SURFACE, p_question: question,
      p_request: { seat: 'customer_support', surface: UNWRITTEN_SURFACE, subject,
        question: `Reply on WhatsApp to this ${io.audience} message, in ${lang === 'ar' ? 'formal Gulf Arabic' : 'UAE English'}${io.audience === 'supplier' ? ' (suppliers are always answered in English)' : ''}. ${notice ? 'They were told we received it and will reply shortly.' : 'They have not had a reply yet.'}\n\nWHAT HAPPENED ON THAT TURN (facts):\n${io.situation.slice(0, 3000)}\n\nMESSAGE:\n${question}`,
        context: { audience: io.audience === 'founder' ? 'founder' : io.audience, language: lang, turn_id: 'wa:' + (io.messageSid || io.from + ':' + question.slice(0, 40)) }, research: false,
        reask: { message: question, facts: 'WHAT HAS HAPPENED ON THIS TURN (decided by our systems; convey it accurately, do not change or add to it):\n' + io.situation.slice(0, 3000),
          audience: io.audience, lang, channel: 'WhatsApp', problems: (io.problems ?? []).slice(0, 12) } },
      p_plan: {}, p_subject: subject, p_reason: io.why, p_dedupe_key: 'wa_unwritten:' + (io.messageSid || io.from + ':' + question.slice(0, 40)),
    });
    held_id = Number(data) || null;
  } catch (_e) { /* the notice already went out; the 15-minute escalation reads the queue, and the row says unfiled */ }
  return { notice, sent, err, held_id };
}
