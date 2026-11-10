// say.ts - THE WORDS OF EVERY CONVERSATION REPLY (rulings 1195/1196/1197): askModel asks the model chain (model_says.ts), adopt
// makes a draft THE turn's reply, sayFor/say speak for an audience, heldTurn is the fixed receipt when no model answered.
// Moved out of index.ts's handleInbound (9 Nov 2026, customer_support); the reply state (modelEscalate, sayOutage,
// sayProblems, sayAttempts, factsAnswer, history, forbidden) lives on the turn (turn.ts), so a statement that read or
// wrote one of them as a local now names it as t.<name>. The audience is read at call time, as it was resolved after these were made.
import { turnLang } from '../_shared/chat_answers.ts';
import { isDemoPhone } from '../_shared/demo_identity.ts';
import { preRevealIdentities } from '../_shared/pre_reveal_identities.ts';
import { waConversation } from '../_shared/wa_history.ts';
import { defaultDeps } from '../_shared/think.ts';
import { budgetLeft, holdUnwritten, modelSays } from './model_says.ts';
import { admin, itFinding, sec } from './shared.ts';
import { sendWa } from './replies.ts';
import type { WaTurn } from './turn.ts';

export function makeSay(t: WaTurn): void {
  const { From, Body, receivedAt, MessageSid } = t;
  // A failed history read is the it_engineer's finding (_shared/wa_history.ts, failure drill D10): the reply still goes, thinner.
  const historyUnavailable = (error: string) => itFinding('wa_inbound:history_unavailable',
    'the WhatsApp conversation history could not be read, so the model answered this turn without it',
    { message_sid: MessageSid || null, error });
  // askModel writes nothing the turn keeps; adopt() is what makes a draft THE turn's reply (its escalate flag, outage and problems).
  // They are apart so a reply started speculatively (below) that is then discarded can never escalate or flag the turn.
  const askModel = async (aud: 'customer' | 'supplier' | 'visitor' | 'founder', situation: string, langGiven?: 'en' | 'ar', must?: string[], signal?: AbortSignal, extraCheck?: (t: string) => string[]) => {
    t.history ??= waConversation(admin, From, receivedAt, isDemoPhone(From), historyUnavailable);
    t.forbidden ??= (async () => {
      const { data } = await admin.rpc('fn_whatsapp_owner', { p_phone: From });
      const o = (Array.isArray(data) ? data[0] : data) as { party_kind?: string; lead_id?: number | null; customer_id?: string | null } | null;
      return o?.party_kind === 'supplier' && o.lead_id ? preRevealIdentities(admin, { leadId: Number(o.lead_id) })
        : o?.party_kind === 'customer' && o.customer_id ? preRevealIdentities(admin, { customerId: String(o.customer_id) }) : [];
    })().catch(() => []);
    // A MIXED MESSAGE KEEPS THE CONVERSATION'S LANGUAGE (chat_answers.turnLang, 3 Nov 2026): this was "any Arabic letter
    // in the message = Arabic", the rule the widget's live run measured flipping an English conversation into Arabic.
    const conv = await t.history;
    const lang = langGiven ?? turnLang(Body, '', conv.filter((t) => t.role !== 'seat').map((t) => ({ role: 'user', content: t.text })));
    return await modelSays(defaultDeps(admin, 'wa_inbound'), { audience: aud, lang, message: Body.slice(0, 1500), situation, conversation: conv, forbidden: await t.forbidden,
      budgetMs: budgetLeft(Date.parse(receivedAt)),   // 45 s from ARRIVAL, not from this call
      // the per-number ceiling (20/hour) the old prompt path had. A speculative draft (signal given) has its OWN bucket, so drafts
      // that are discarded can never use up the real reply's allowance and leave an active sender with no reply.
      rateKey: signal ? 'wa-spec:' + From : 'wa:' + From,
      ...(signal ? { signal } : {}), ...(extraCheck ? { extraCheck } : {}),
      subject: isDemoPhone(From) ? { fixture: true, phone: From } : { phone: From }, ...(must?.length ? { must } : {}),
      ...(t.factsAnswer && !signal ? { situationAnswers: true } : {}) });
  };
  const adopt = (r: Awaited<ReturnType<typeof askModel>>) => {
    t.modelEscalate = t.modelEscalate || r.escalate;
    t.sayOutage = !r.text && r.outage;
    t.sayProblems = r.text ? [] : (r.problems ?? []);
    const att = (r.attempts ?? []).map((x) => String(x).slice(0, 400));
    t.sayAttempts = att.length > 8 ? [...att.slice(0, 4), ...att.slice(-4)] : att;   // the head and the tail (the last chance is at the end)
    return r.text;
  };
  const sayFor = (aud: 'customer' | 'supplier' | 'visitor' | 'founder') => async (situation: string, lang?: 'en' | 'ar', must?: string[], extraCheck?: (t: string) => string[]) =>
    adopt(await askModel(aud, situation, lang, must, undefined, extraCheck));
  // `audience` is resolved further down; `say` is only called after that (the spec-offer branch uses sayFor('customer')).
  const say = (situation: string, lang?: 'en' | 'ar') => sayFor(t.audience === 'supplier' ? 'supplier' : t.audience === 'customer' ? 'customer' : t.audience === 'founder' ? 'founder' : 'visitor')(situation, lang);
  // NOBODY IS LEFT SILENT (review of #1335). When no model wrote the reply, or the guard refused what it wrote, the
  // person gets the HELD NOTICE — a fixed receipt, a notification under ruling 1197, not an answer — and the turn is
  // filed in customer_support's reasoning queue (fn_reason_hold). resilience_ping replays it through the model and
  // sends the written answer here (reasoned_delivery.ts); still unanswered after 15 minutes it is escalated to
  // customer_support (fn_reason_held_escalate, scripts/sql/an_unwritten_conversation_reply_reaches_its_seat_in_fifteen_minutes.sql).
  const heldTurn = (aud: 'customer' | 'supplier' | 'visitor' | 'founder', lang: 'en' | 'ar', situation: string, why: string) =>
    holdUnwritten({ from: From, body: Body, messageSid: MessageSid || null, audience: aud, lang, situation, why, outage: t.sayOutage, problems: t.sayProblems,
      enabled: async () => (await sec('wa_autoreply_enabled')) === 'true', send: (t) => sendWa(From, t),
      rpc: async (f, a) => { const r = await admin.rpc(f, a); return { data: r.data, error: r.error }; } });
  Object.assign(t, { historyUnavailable, askModel, adopt, sayFor, say, heldTurn });
}
