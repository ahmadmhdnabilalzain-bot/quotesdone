// say.ts - THE WORDS OF EVERY CONVERSATION REPLY (rulings 1195/1196/1197): askModel asks the model chain (model_says.ts), adopt
// makes a draft THE turn's reply, sayFor/say speak for an audience, heldTurn is the fixed receipt when no model answered.
// Moved out of index.ts's handleInbound (9 Nov 2026, customer_support); the reply state (modelEscalate, sayOutage,
// sayProblems, sayAttempts, factsAnswer, history, forbidden) lives on the turn (turn.ts), so a statement that read or
// wrote one of them as a local now names it as t.<name>. The audience is read at call time, as it was resolved after these were made.
import { turnLang } from '../_shared/chat_answers.ts';
import { isDemoPhone } from '../_shared/demo_identity.ts';
import { preRevealIdentities } from '../_shared/pre_reveal_identities.ts';
import { waConversation } from '../_shared/wa_history.ts';
import { dialectOf, mergeState, readState, registerPatch, whatsappKey } from '../_shared/inquiry_state.ts';
import { ADVISE_RULE, heldProblem, problemsFor, solutionsBlock, solutionStateText } from '../_shared/solution_catalogue.ts';
import { taxonomyOf, tradeBlock, tradeContext } from '../_shared/inquiry_trades.ts';
import { joinIfNotOpen, waPhone } from '../_shared/trade_opening.ts';
import { readInquiry, readingPatch } from '../_shared/inquiry_reading.ts';
import { defaultDeps } from '../_shared/think.ts';
import { budgetLeft, holdUnwritten, modelSays } from './model_says.ts';
import { laneMust, STATUS_CLASS, STATUS_EFFORT, STATUS_HISTORY_TURNS, STATUS_RULES } from './status_lane.ts';
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
  const askModel = async (aud: 'customer' | 'supplier' | 'visitor' | 'founder', situation: string, langGiven?: 'en' | 'ar', must?: string[], signal?: AbortSignal, extraCheck?: (t: string) => string[],
    lane?: { kind: 'status' | 'app'; databaseAnswer: string }) => {
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
    // THE CONVERSATION'S STATE (_shared/inquiry_state.ts, 10 Nov 2026, ledger 1572): the customer's register is read from their
    // own messages and the reply mirrors it; the count, language and dialect are kept on the number's state. Suppliers are
    // always answered in English (ruling 1008), so no register is read for them. The write is never awaited by the reply.
    const theirs = [...conv.filter((x) => x.role !== 'seat').map((x) => x.text), Body];
    const dialect = aud === 'supplier' || aud === 'founder' ? null : dialectOf(theirs)?.dialect ?? null;
    if (!signal && aud !== 'supplier' && aud !== 'founder') void mergeState(admin, whatsappKey(From), 'whatsapp', { turn: theirs.length, message_count: conv.length + 1, ...registerPatch(theirs, lang) });
    // THE EXPERT INTERVIEW ON WHATSAPP (10 Nov 2026, ledger 1572/1586; _shared/solution_catalogue.ts, inquiry_trades.ts). A
    // customer or visitor describing a job is advised the way the portal and the request chat advise: the ADVISE rule always,
    // and once the number's state holds the job's taxonomy trades (the reader below), their packs, the reference options for
    // them and the solution so far, on the interview class. Never for a supplier or the founder. The reader runs after the
    // reply is asked, never awaited by it, and only for the real reply (not a speculative draft).
    const customerSide = aud === 'customer' || aud === 'visitor';
    const expertP = customerSide ? (async () => {
      // the number's state and the taxonomy are read together (two database trips that read nothing of each other; 10 Nov 2026)
      const [st, tax] = await Promise.all([readState(admin, whatsappKey(From)), taxonomyOf(admin)]);
      const ctx = await tradeContext(admin, st?.trade_codes ?? [], lang, tax);
      const problems = problemsFor({ codes: ctx?.codes ?? [], held: heldProblem(st) });
      const job = !!(ctx?.codes.length || problems.length || st?.options_offered?.length);
      // A TRADE THAT IS NOT OPEN YET (ledger 1614, _shared/trade_opening.ts): once the state places the job in its trades, the
      // door asks whether they are open. Not open: the number joins the trade's waiting list (the real reply only, never a
      // speculative draft) and the reply must carry the database's own sentence, in the customer's language, word for word.
      const gate = ctx?.codes.length ? await joinIfNotOpen(admin, { slugs: ctx.codes, channel: 'whatsapp', phone: signal ? null : waPhone(From), lang: lang === 'ar' ? 'ar' : 'en' }) : null;
      const waiting = gate?.state === 'not_open' ? (gate.message ?? null) : null;
      return { st, tax, ctx, problems, job, waiting, text: [ADVISE_RULE, solutionStateText(st, lang),
        waiting ? 'THE TRADE IS NOT OPEN TO CUSTOMERS YET: say so plainly, do not promise a supplier or a date, and carry this sentence exactly: ' + waiting : '',
        tradeBlock(ctx, lang), solutionsBlock(problems, lang)].filter(Boolean).join('\n\n') };
    })().catch(() => null) : Promise.resolve(null);
    const ex = await expertP;
    if (ex && !signal && ex.tax) {
      const deps = defaultDeps(admin, 'wa_inbound');
      const ask = async (sys: string, input: string, ms: number) => (await deps.llm('synthesise', sys, input, { taskClass: 'json_extraction', seat: 'customer_support', max: 400, timeoutMs: ms,
        subject: isDemoPhone(From) ? { fixture: true, phone: From } : { phone: From }, internal: true })).content ?? null;
      void readInquiry(ask, { taxonomy: ex.tax, problems: ex.problems, services: ex.ctx?.services, lastSeat: [...conv].reverse().find((x) => x.role === 'seat')?.text ?? '', message: Body, heldCodes: ex.st?.trade_codes ?? [] }, Date.now() + 25_000)
        .then((r) => r ? mergeState(admin, whatsappKey(From), 'whatsapp', { turn: theirs.length, ...readingPatch(r), ...(r.problem ? { condition: { ...(readingPatch(r).condition ?? {}), problem: r.problem } } : {}) }) : null)
        .catch(() => null);
    }
    // the status and app lanes (status_lane.ts, ruling 1571): status_reply, no brief, the last few turns, the refs or the link as must
    const laneMustCarry = lane ? laneMust(lane.kind, lane.databaseAnswer, aud === 'supplier' ? 'en' : lang) : [];
    if (lane) must = [...new Set([...(must ?? []), ...laneMustCarry])];
    if (ex?.waiting && !lane) must = [...new Set([...(must ?? []), ex.waiting])];
    return await modelSays(defaultDeps(admin, 'wa_inbound'), { audience: aud, lang, message: Body.slice(0, 1500), situation,
      conversation: lane ? conv.slice(-STATUS_HISTORY_TURNS) : conv, forbidden: await t.forbidden,
      ...(lane ? { taskClass: STATUS_CLASS, briefInPrompt: false, laneRules: STATUS_RULES, effort: STATUS_EFFORT } : {}),
      budgetMs: budgetLeft(Date.parse(receivedAt)),   // 45 s from ARRIVAL, not from this call
      // the per-number ceiling (20/hour) the old prompt path had. A speculative draft (signal given) has its OWN bucket, so drafts
      // that are discarded can never use up the real reply's allowance and leave an active sender with no reply.
      rateKey: signal ? 'wa-spec:' + From : 'wa:' + From,
      ...(signal ? { signal } : {}), ...(extraCheck ? { extraCheck } : {}),
      subject: isDemoPhone(From) ? { fixture: true, phone: From } : { phone: From }, ...(must?.length ? { must } : {}),
      ...(t.factsAnswer && !signal ? { situationAnswers: true } : {}), ...(dialect ? { dialect } : {}),
      // the classification's needs-a-person reading (classification.ts), so a finished prose draft is the reply (R4/R5, 10 Nov 2026).
      // Only for a typed message, whose classification is already running: asking it for any other turn would start one.
      ...(t.typedQuestion && t.needsPersonP ? { escalateReading: () => t.needsPersonP() } : {}),
      // a status or app question keeps its own lane (ruling 1571); a job conversation is the expert interview (1572/1586)
      ...(ex && !lane ? { expert: ex.text, ...(ex.job ? { taskClass: 'inquiry_qualification_conversation' } : {}) } : {}) });
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
  const audOf = () => (t.audience === 'supplier' ? 'supplier' : t.audience === 'customer' ? 'customer' : t.audience === 'founder' ? 'founder' : 'visitor') as 'customer' | 'supplier' | 'visitor' | 'founder';
  const sayLane = async (lane: 'status' | 'app', facts: string, databaseAnswer: string) =>
    adopt(await askModel(audOf(), facts, undefined, undefined, undefined, undefined, { kind: lane, databaseAnswer }));
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
  Object.assign(t, { historyUnavailable, askModel, adopt, sayFor, say, sayLane, heldTurn });
}
