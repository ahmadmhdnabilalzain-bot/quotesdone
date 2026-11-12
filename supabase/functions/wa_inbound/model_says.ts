// model_says — every CONVERSATION reply on WhatsApp is written by a model in that turn. Seat: customer_support.
// Founder rulings 1195/1196/1197 (12 Oct 2026): code decides WHAT happened (a routine's result, a document's read,
// a menu option's own data) and hands it over as facts; the words are the model's (_shared/ai_reply.ts: the company
// brief, the model ladder, the figure + reply guard with a model rewrite, suppliers always in English).
// Code never substitutes text: when no model answers, the reply is '' and NOTHING conversational is sent.
// Notifications (OTP, receipts, case-reference receipts, status notices, the accepted-offer confirmation, the
// founder's FIGURES report) are not conversation and do not come through here.
// prevented by: wa_inbound/model_says.test.ts, wa_inbound/menu_flow_model_written.test.ts,
//               wa_inbound/no_unwritten_send.test.ts
import { arabicRegister, type Dialect } from '../_shared/inquiry_state.ts';
import { aiReply } from '../_shared/ai_reply.ts';
import type { ThinkDeps, Turn } from '../_shared/think.ts';

export type SayAudience = 'customer' | 'supplier' | 'visitor' | 'founder';
export interface SayRequest {
  audience: SayAudience;
  lang: 'en' | 'ar';
  message: string;              // what the person wrote this turn
  situation: string;            // what code decided / the routine returned — the facts the reply must convey
  /** the classification's needs-a-person reading of this message, read only when a draft is prose (_shared/ai_reply.ts, 10 Nov 2026) */
  escalateReading?: () => Promise<boolean | null>;
  conversation?: Turn[];
  subject?: Record<string, unknown>;
  rateKey?: string;             // the per-sender ceiling at the gateway (wa:<From>, 20/hour)
  forbidden?: string[];         // another party's identity before a reveal: a hit is rewritten by the model
  budgetMs?: number;            // the reply's wall-clock budget (default WA_REPLY_BUDGET_MS)
  must?: string[];              // text the reply must carry exactly (a job number, a case reference)
  signal?: AbortSignal;         // a speculative draft that was discarded: abort it
  extraCheck?: (text: string) => string[];   // the turn's own rule: a draft it names a problem in is rewritten, never sent
  situationAnswers?: boolean;   // the facts alone say what to tell them (a person is needed): the brief-less last chance may run
  dialect?: Dialect | null;     // the customer's register (_shared/inquiry_state.ts dialectOf; never for a supplier, ruling 1008)
  // THE STATUS LANE (status_lane.ts, ruling 1571): its own class (status_reply), no company brief, and its own rules after WA_RULES.
  // THE EXPERT INTERVIEW (say.ts, ledger 1572/1586): a customer's job answers on inquiry_qualification_conversation with its block.
  taskClass?: string;
  briefInPrompt?: boolean;
  laneRules?: string;
  expert?: string;              // the expert interview's block for a customer's job (say.ts; _shared/solution_catalogue.ts ADVISE_RULE)
  effort?: 'low' | 'medium' | 'high';   // the reasoning effort asked of the model (the status lane: status_lane.ts STATUS_EFFORT)
  caseMemory?: { ref: string; summaryText: string } | null;   // ruling 1635: the case this turn continues (support_case_memory.ts)
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
// THE NUMBER THEY ARE ALREADY WRITING TO (final audit 12 Nov 2026, W5). "Talk to a person" was answered "You can speak with a
// person on WhatsApp ... +1 218 316 6814", the number the person was writing to, and the same number was in 7 replies (both
// complaints among them): the brief's line for "a person" (ai_reply.ts) is right on the website and wrong here. What the hand-off
// is today: a typed request for a person, or a complaint, is reported to the CEO seat (general_turn.ts, fn_support_report_to_ceo)
// and filed for review; choosing "Talk to a person" from the menu (MENU, then option 6) alerts the founder with a one-tap reply
// link and pauses the automatic replies until he answers on this number (menu.ts qd_person). So that is what the reply says.
export const OUR_WHATSAPP_DIGITS = '12183166814';
// Re-check of 12 Nov 2026, R3: "passed to our team" was said when nothing was passed. It is said only when the facts say so
// (compose.ts states it when the route needs a person, the turn that files the CEO report; menu.ts when the hand-off returned).
export const WA_PERSON_RULE = 'They are already writing to our WhatsApp number: never give them a phone or WhatsApp number to reach us. When they want a person, '
  + 'never say their message has been passed to anyone unless the facts above say so; for a member of the team to reply to them here, they can send MENU and choose "Talk to a person"; '
  + 'by e-mail: management@quotesdone.com.';
/** A reply that says the message was passed on, when the turn's facts say no hand-off was filed, is rewritten (R3). */
// Review of branch B: only a claim that it went to OUR TEAM (a person) is checked; "forwarded to the suppliers" and "escalated to
// our sales engineer" are true statements of what the database did, and are never rewritten.
const PASSED_CLAIM = /\b(?:passed|forwarded|handed|escalated|referred)\s+(?:on\s+)?(?:your\s+(?:message|request|query|complaint)\s+)?(?:on\s+)?to\s+(?:our|the)\s+(?:support\s+)?team\b|\b(?:your\s+(?:message|request))\s+(?:has\s+been|was)\s+(?:passed|forwarded|handed|escalated)\s+(?:on\s+)?to\s+(?:our|the)\s+(?:support\s+)?team\b|(?:أحلنا|حوّلنا|حولنا|أبلغنا)\s+(?:رسالتكم|رسالتك|طلبكم|طلبك|الفريق)|تم\s+(?:تحويل|إحالة)\s+(?:رسالتكم|رسالتك|طلبكم|طلبك)/i;
const PASSED_FACT = /passed to our team|passed your request to|hand-off (?:was|is) filed|has their message/i;
export function passedProblems(text: string, situation: string): string[] {
  return PASSED_CLAIM.test(String(text || '')) && !PASSED_FACT.test(String(situation || ''))
    ? ['it says their message was passed to the team, but no hand-off was filed on this turn; say instead that for a member of the team to reply here they can send MENU and choose "Talk to a person"']
    : [];
}

// R13 (re-check of 12 Nov 2026): "Reply REGISTER and I will send him the link" (no such keyword exists: only MENU and STOP do), and
// "The portal guide doesn't specify ..." (our own sources named to the person). Our draft is read; a hit is rewritten.
// review of branch B: "Send PDF", "Send DWG", "Send RFQ details" are instructions about a file, not keywords, so only reply, text and
// type introduce one; YES / NO / CANCEL / OK are the confirmations the database itself asks for ("reply yes 1043")
const KEYWORD = /\b(?:[Rr]eply|[Tt]ext|[Tt]ype)\s+["“'‘]?([A-Z]{2,})["”'’]?(?=[\s.,!:;)]|$)/g;
const KEYWORDS_THAT_EXIST = new Set(['MENU', 'STOP', 'YES', 'NO', 'CANCEL', 'OK',
  // not keywords at all: "reply ASAP", "type PDF or DWG", an amount or a place
  'ASAP', 'PDF', 'JPG', 'PNG', 'DWG', 'DXF', 'RFQ', 'AED', 'UAE', 'VAT']);
const INTERNAL = /\b(?:the|our)\s+(?:portal\s+guide|company\s+brief|brief|fact\s+pack|facts|knowledge\s+base|FAQ\s+(?:row|entry))\s+(?:does\s*n[o']t|doesn['’]t|do\s*n[o']t|don['’]t)\s+(?:specify|say|mention|state|cover|show)/i;
export function wordingProblems(text: string): string[] {
  const out: string[] = [];
  const made = [...String(text || '').matchAll(KEYWORD)].map((m) => m[1]).filter((k) => !KEYWORDS_THAT_EXIST.has(k));
  if (made.length) out.push('it asks them to reply a keyword that does not exist (' + [...new Set(made)].join(', ') + '); only MENU and STOP exist');
  if (INTERNAL.test(String(text || ''))) out.push('it names our own internal sources (a guide, the brief, the facts) to the person; say what can be said, or what happens next');
  return out;
}

/** A WhatsApp reply that gives the person the number they are writing to is rewritten by the model, never sent. */
export function ourNumberProblems(text: string): string[] {
  return String(text || '').replace(/[^0-9]/g, '').includes(OUR_WHATSAPP_DIGITS)
    // (review of branch B: this said "say their message has been passed to our team", which passedProblems then refused: 4 calls)
    ? ['it gives the person our own WhatsApp number, which they are already writing to; say instead that, for a member of the team to reply to them here, they can send MENU and choose "Talk to a person"']
    : [];
}

/** outage: no call reached a model (openrouter_down.ts) — the only case the held notice, a code-written line, may go out. */
export interface Said { text: string; model: string | null; attempts: string[]; ms: number; escalate: boolean; outage: boolean; problems?: string[] }

export const WA_RULES = 'Plain text for WhatsApp (no markdown), under about 90 words; put each phone number, email or link on its own line, exactly as given in the facts. '
  + WA_PERSON_RULE;

/** The model's words for this turn, or text '' when no model answered (the caller then sends nothing). */
export async function modelSays(deps: ThinkDeps, r: SayRequest): Promise<Said> {
  const t0 = Date.now();
  try {
    const ask = (deadline: number, o: { briefInPrompt?: boolean; priorProblems?: string[]; rateKey?: string } = {}) => aiReply(deps, {
      seat: 'customer_support', channel: 'whatsapp', audience: r.audience, lang: r.lang,
      message: r.message || '(no text — they pressed a menu option or sent a file)',
      conversation: r.conversation,
      facts: 'WHAT HAS HAPPENED ON THIS TURN (decided by our systems; convey it accurately, do not change or add to it):\n' + r.situation
        + (r.expert && r.audience !== 'supplier' ? '\n\n' + r.expert : ''),
      rules: r.laneRules ? WA_RULES + ' ' + r.laneRules : WA_RULES, subject: r.subject,
      ...(r.taskClass ? { taskClass: r.taskClass } : {}), ...(r.briefInPrompt === false ? { briefInPrompt: false } : {}), rateKey: r.rateKey, forbidden: r.forbidden, askEscalate: true, ...(r.escalateReading ? { escalateReading: r.escalateReading } : {}), must: r.must, ...(r.signal ? { signal: r.signal } : {}),
      extraCheck: (text: string) => [...ourNumberProblems(text), ...wordingProblems(text), ...(r.extraCheck ? r.extraCheck(text) : [])],
      ...(r.dialect && r.audience !== 'supplier' ? { dialect: r.dialect } : {}), ...(r.effort ? { effort: r.effort } : {}), ...(r.caseMemory ? { caseMemory: r.caseMemory } : {}),
      deadline, ...o,
    });
    let out = await ask(t0 + (r.budgetMs ?? WA_REPLY_BUDGET_MS));
    let attempts = out.attempts;
    // "PASSED TO OUR TEAM" ONLY WHEN IT WAS (re-check R3; review of branch B). Read on the draft that came back, because a draft that
    // ESCALATES itself (escalate:true files the CEO report on this turn) makes "escalated to our team" true, and the flag is not
    // visible to a per-text check. Otherwise, with no hand-off in the facts, the draft is asked again once with the problem named.
    const claim = !out.escalate && !r.signal && String(out.reply || '').trim() ? passedProblems(String(out.reply), r.situation) : [];
    if (claim.length) {
      const again = await ask(t0 + (r.budgetMs ?? WA_REPLY_BUDGET_MS), { priorProblems: [...(out.problems ?? []), ...claim] });
      attempts = [...attempts, ...again.attempts.map((a) => 'passed-claim ' + a)];
      if (String(again.reply || '').trim()) out = again;
    }
    // THE LAST CHANCE (customer_support, 3 Nov 2026; "every inbound message gets an answer"). Run 41530397323: the lean "scam"
    // turn's model WAS up, its Sonnet draft could not be used, the other-family call ran into the budget, and the person got
    // nothing for the turn (held for the re-ask). Now, when a model answered but nothing passed, or the budget ran out before
    // one could, it is asked ONCE more, bounded by LAST_CHANCE_MS: the rules and this turn's facts without the ~140k-token
    // brief (a few seconds), the refused drafts' problems named, every check unchanged. Still model-written (1195-1197, 1339).
    // Not for a speculative draft (signal) and not in an outage (the held notice owns that). Prevented by: model_says.test.ts.
    // ONLY WHEN THE FACTS ALONE ANSWER THE TURN (review of #1816): without the brief a company question ("how do you vet
    // suppliers?") could only be answered from memory, so the caller opts in (situationAnswers) for a turn whose facts say what
    // happens, a person being needed above all, and the brief-less prompt says nothing about the company beyond its facts.
    // Never past a spent sender bucket (out.rateLimited): the turn ends as on main, held with no text (re-review of #1816).
    if (r.situationAnswers === true && !String(out.reply || '').trim() && !out.outage && !out.rateLimited && !r.signal) {
      // the same message's reply, so it does not count against the sender's rate bucket again (rateKey left out)
      const last = await ask(Date.now() + LAST_CHANCE_MS, { briefInPrompt: false, priorProblems: out.problems, rateKey: undefined });
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
        question: `Reply on WhatsApp to this ${io.audience} message, in ${lang === 'ar' ? arabicRegister(null) : 'UAE English'}${io.audience === 'supplier' ? ' (suppliers are always answered in English)' : ''}. ${notice ? 'They were told we received it and will reply shortly.' : 'They have not had a reply yet.'}\n\nWHAT HAPPENED ON THAT TURN (facts):\n${io.situation.slice(0, 3000)}\n\nMESSAGE:\n${question}`,
        context: { audience: io.audience === 'founder' ? 'founder' : io.audience, language: lang, turn_id: 'wa:' + (io.messageSid || io.from + ':' + question.slice(0, 40)) }, research: false,
        reask: { message: question, facts: 'WHAT HAS HAPPENED ON THIS TURN (decided by our systems; convey it accurately, do not change or add to it):\n' + io.situation.slice(0, 3000),
          audience: io.audience, lang, channel: 'WhatsApp', problems: (io.problems ?? []).slice(0, 12) } },
      p_plan: {}, p_subject: subject, p_reason: io.why, p_dedupe_key: 'wa_unwritten:' + (io.messageSid || io.from + ':' + question.slice(0, 40)),
    });
    held_id = Number(data) || null;
  } catch (_e) { /* the notice already went out; the 15-minute escalation reads the queue, and the row says unfiled */ }
  return { notice, sent, err, held_id };
}
