// say.ts - THE WORDS OF EVERY CONVERSATION REPLY (rulings 1195/1196/1197): askModel asks the model chain (model_says.ts), adopt
// makes a draft THE turn's reply, sayFor/say speak for an audience, heldTurn is the fixed receipt when no model answered.
// Moved out of index.ts's handleInbound (9 Nov 2026, customer_support); the reply state (modelEscalate, sayOutage,
// sayProblems, sayAttempts, factsAnswer, history, forbidden) lives on the turn (turn.ts), so a statement that read or
// wrote one of them as a local now names it as t.<name>. The audience is read at call time, as it was resolved after these were made.
import { turnLang } from '../_shared/chat_answers.ts';
import { isDemoPhone } from '../_shared/demo_identity.ts';
import { preRevealIdentities } from '../_shared/pre_reveal_identities.ts';
import { waConversation } from '../_shared/wa_history.ts';
import { dialectOf, MESSAGE_CAP, mergeState, readState, registerPatch, whatsappKey, type InquiryState } from '../_shared/inquiry_state.ts';
import { ADVISE_RULE, heldProblem, problemsFor, solutionsBlock, solutionStateText } from '../_shared/solution_catalogue.ts';
import { taxonomyOf, tradeBlock, tradeContext } from '../_shared/inquiry_trades.ts';
import { joinIfNotOpen, waPhone } from '../_shared/trade_opening.ts';
import { readInquiry, readingPatch, siteVisitsOf } from '../_shared/inquiry_reading.ts';
import { photoAskDraft, shotsFor } from '../_shared/site_photos.ts';
import { defaultDeps } from '../_shared/think.ts';
import { budgetLeft, holdUnwritten, modelSays } from './model_says.ts';
import { laneMust, STATUS_CLASS, STATUS_EFFORT, STATUS_HISTORY_TURNS, STATUS_RULES } from './status_lane.ts';
import { admin, itFinding, sec } from './shared.ts';
import { onDelivered, sendWa } from './replies.ts';
import type { WaTurn } from './turn.ts';
import { recordWaExchange, startWaCase, waCaseMemory } from './case_memory.ts';
import { hasCaseBlock, worksFromOneCase } from '../_shared/support_case_memory.ts';
import { armWaHolding } from './holding.ts';

/** The key on the number's state (inquiry_state.asked) that records the trade-not-open sentence was said. ONE mark per
 *  conversation (re-check of 12 Nov 2026, R4): it was per trade, so a second trade read from the conversation (a cousin's
 *  cleaning company) said the sentence again. The codes are kept for the record only. */
export const tradeSaidKey = (_codes: readonly string[]) => 'said:trade_not_open';
/** Whether this conversation was already told that a trade is not open yet (W4; one mark, or an older per-trade one). */
export const tradeAlreadySaid = (st: Pick<InquiryState, 'asked'> | null | undefined, codes: readonly string[]) =>
  !!codes.length && Object.keys(st?.asked ?? {}).some((k) => k === 'said:trade_not_open' || k.startsWith('said:trade_not_open:'));
/** The database's sentence without a leading courtesy: it sat mid-reply as "...For your cousin: Thank you. We are..." (R4). */
export const withoutLeadingThanks = (s: string) => String(s).replace(/^\s*(?:thank you|thanks)[.!,]?\s+|^\s*(?:شكرًا|شكرا)(?:\s+لكم|\s+لك)?[.،!]?\s+/i, '').trim();
/** THE APP LANE BEFORE THE TRADE IS KNOWN (W4): the first reply to a new job promised "matched suppliers", and the next one said
 *  the trade was not open. Until the number's state places the job in its trades, the app lane promises neither. */
export const TRADE_SAID_FACT = 'EARLIER IN THIS CONVERSATION they were told this trade is not open to customers yet. Do not repeat it; mention it only if they ask about suppliers, quotes or timing, and never promise a supplier or a date.';
/** The mark on the number's state that this conversation was asked for site photos (ONCE, ledger 1704). */
export const PHOTO_SAID_KEY = 'said:photo_ask';
/** THE PHOTO ASK ON WHATSAPP (15 Nov 2026, sales_engineer; founder ledger 1704; review of bf8b9ea45, item 8). The request chat asks
 *  once for the shots a site visit would check (inquiry_intake/handle.ts, _shared/site_photos.ts). A customer's job on WhatsApp is
 *  read by the state reader (_shared/inquiry_reading.ts), which now also says which held trades' site-visit condition the job
 *  meets (a 'visit:<code>' mark). On the next reply, a REGISTERED customer whose conversation has such a mark and was never asked
 *  is asked once: the same draft the request chat uses, carried word for word (as the trade-not-open sentence is), and the
 *  conversation is marked said when the reply that carries it is delivered. Photos sent in the thread are checked and recorded on
 *  the request (customer_files.ts). null = nothing to ask. */
export function waPhotoAsk(ctx: Parameters<typeof shotsFor>[0], asked: Record<string, unknown> | null | undefined, aud: string, lang: 'en' | 'ar'): string | null {
  if (aud !== 'customer' || Object.keys(asked ?? {}).includes(PHOTO_SAID_KEY)) return null;
  const visits = siteVisitsOf(asked);
  const shots = visits.length ? shotsFor(ctx, [], visits) : [];
  return shots.length ? photoAskDraft(shots, lang) + (lang === 'ar' ? ' يمكنك إرسالها هنا في المحادثة، ونفحص كل صورة قبل أن يراها أي مورّد.' : ' You can send them here in this chat; every photo is checked before any supplier sees it.') : null;
}
export const TRADE_UNKNOWN_FACT = 'Whether suppliers in this trade are taking requests on QuotesDone yet is checked once the job is described: do not say the request will be sent to suppliers or that quotes will come; say they can post the request free through the link and we will tell them what happens next.';

export function makeSay(t: WaTurn): void {
  const { From, Body, receivedAt, MessageSid } = t;
  // THE CASE READ STARTS NOW (case_memory.ts): one database call, so it is ready long before the reply is asked
  void startWaCase(t);
  // THE CASE STEP RUNS ONCE, FOR THE REPLY THAT WAS DELIVERED (review of 12 Nov 2026). adopt() makes a draft THE turn's reply
  // and leaves its case step on the turn (t.caseAfter; a later adopt, the full path after a lane that could not answer,
  // replaces it); the step runs at the turn's end (index.ts finally) only if a reply was delivered after that adopt
  // (replies.ts onDelivered), with the words really sent. A discarded draft, a guard-refused reply and a failed send record
  // nothing, and no promise of an unsent reply reaches the ledger.
  const recordOnAdopt = new WeakMap<object, (sent: string) => void>();
  t.stopListening = onDelivered(From, (body) => { if (t.holdingWent) t.repliedAfterHolding = true; if (t.caseAfter) t.deliveredReply = body; });
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
    armWaHolding(t, aud, lang);   // ruling 1636 (holding.ts): the typing indicator now, the holding line if no reply has left 9 s after the message
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
      const waiting = gate?.state === 'not_open' && gate.message ? withoutLeadingThanks(gate.message) : null;
      const waitingSaid = !!waiting && tradeAlreadySaid(st, ctx?.codes ?? []);
      // the photo ask (ledger 1704): never while the trade is not open (no request can be sent there yet)
      const photoAsk = waiting ? null : waPhotoAsk(ctx, st?.asked, aud, lang === 'ar' ? 'ar' : 'en');
      return { st, tax, ctx, problems, job, waiting, waitingSaid, photoAsk, text: [ADVISE_RULE, solutionStateText(st, lang),
        waiting && !waitingSaid ? 'THE TRADE IS NOT OPEN TO CUSTOMERS YET: say so plainly, do not promise a supplier or a date, and carry this sentence exactly: ' + waiting : '',
        waitingSaid ? TRADE_SAID_FACT : '',
        tradeBlock(ctx, lang), solutionsBlock(problems, lang)].filter(Boolean).join('\n\n') };
    })().catch(() => null) : Promise.resolve(null);
    const ex = await expertP;
    if (ex && !signal && ex.tax) {
      const deps = defaultDeps(admin, 'wa_inbound');
      const ask = async (sys: string, input: string, ms: number) => (await deps.llm('synthesise', sys, input, { taskClass: 'json_extraction', seat: 'customer_support', max: 400, timeoutMs: ms,
        subject: isDemoPhone(From) ? { fixture: true, phone: From } : { phone: From }, internal: true })).content ?? null;
      // each held trade's site-visit condition, so the reading can mark the ones this job meets (the photo ask, waPhotoAsk)
      const siteVisits = Object.entries(ex.ctx?.checklists ?? {}).flatMap(([code, cs]) => (cs ?? []).filter((c) => c.site_visit_required_when && (c.photos ?? []).length).slice(0, 1).map((c) => ({ code, when: String(c.site_visit_required_when) })));
      void readInquiry(ask, { taxonomy: ex.tax, problems: ex.problems, services: ex.ctx?.services, lastSeat: [...conv].reverse().find((x) => x.role === 'seat')?.text ?? '', message: Body, heldCodes: ex.st?.trade_codes ?? [], siteVisits }, Date.now() + 25_000)
        .then((r) => r ? mergeState(admin, whatsappKey(From), 'whatsapp', { turn: theirs.length, ...readingPatch(r), ...(r.problem ? { condition: { ...(readingPatch(r).condition ?? {}), problem: r.problem } } : {}) }) : null)
        .catch(() => null);
    }
    // the status and app lanes (status_lane.ts, ruling 1571): status_reply, no brief, the last few turns, the refs or the link as must
    const laneMustCarry = lane ? laneMust(lane.kind, lane.databaseAnswer, aud === 'supplier' ? 'en' : lang) : [];
    if (lane) must = [...new Set([...(must ?? []), ...laneMustCarry])];
    // THE TRADE IS NOT OPEN: SAID ONCE (final audit 12 Nov 2026, W4). It was added to `must` on EVERY later turn while the
    // number's state held the trade: 7 replies to 4 people carried the same paragraph, including one about a cousin's cleaning
    // company and an Arabic refund complaint, and 7 of 26 turns paid for a rewrite to put it back. It is carried word for word
    // the first time (any lane that answers a job: the conversation and the app lane), recorded on the number's state, and
    // after that it is a fact the reply may use when they ask about suppliers, quotes or timing, never a sentence it must repeat.
    const codes = ex?.ctx?.codes ?? [];
    let tradeSaid: string[] | null = null;
    if (ex?.waiting && (!lane || lane.kind === 'app')) {
      if (!ex.waitingSaid) { must = [...new Set([...(must ?? []), ex.waiting])]; tradeSaid = codes; }
      else if (lane) situation += '\n\n' + TRADE_SAID_FACT;   // the conversation lane has it in the expert block
    }
    if (lane?.kind === 'app' && ex && !codes.length) situation += '\n\n' + TRADE_UNKNOWN_FACT;
    // THE PHOTO ASK, ONCE (waPhotoAsk): carried word for word on the conversation lane, marked said when delivered (below)
    const photoAsk = ex?.photoAsk && !lane ? ex.photoAsk : null;
    if (photoAsk) must = [...new Set([...(must ?? []), photoAsk])];
    // THE CASE (ruling 1635, case_memory.ts): the case this message belongs to, its summary for the cached prefix. A status or app
    // lane does not read it (a status ask is about now); every lane's reply is recorded on the case after it is adopted.
    const caseMem = lane ? null : await waCaseMemory(t, aud);
    const said = await modelSays(defaultDeps(admin, 'wa_inbound'), { audience: aud, lang, message: Body.slice(0, 1500), situation,
      // one case with a summary, or several open cases with their promises (support_case_memory.ts hasCaseBlock)
      ...(hasCaseBlock(caseMem) ? { caseMemory: caseMem } : {}),
      // with no case summary the reply reads the conversation, at most the estate's 100-message cap (inquiry_state.ts MESSAGE_CAP;
      // review round 2: it was the 500-row history read, so one long chat made every reply slow and expensive)
      conversation: lane ? conv.slice(-STATUS_HISTORY_TURNS) : worksFromOneCase(caseMem) ? conv : conv.slice(-MESSAGE_CAP), forbidden: await t.forbidden,
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
    // THE STEP AFTER THE REPLY, once this reply is THE turn's reply (adopt): the case (decision, routing, summary; a speculative
    // draft that is adopted is recorded too, a discarded one never), and the trade sentence marked said.
    if (said?.text) recordOnAdopt.set(said, (sent: string) => {
      recordWaExchange(t, aud, lang, sent, conv);
      // matched on the reply as WRITTEN (review round 2): the words sent have their links and numbers bidi-wrapped in an Arabic
      // reply (replies.ts toContact), so the sentence was never found there and repeated in every Arabic conversation
      if (tradeSaid && said.text.includes(String(ex?.waiting))) void mergeState(admin, whatsappKey(From), 'whatsapp', { asked: [tradeSaidKey(tradeSaid)] });
      if (photoAsk && said.text.includes(photoAsk)) void mergeState(admin, whatsappKey(From), 'whatsapp', { asked: [PHOTO_SAID_KEY] });
    });
    return said;
  };
  const adopt = (r: Awaited<ReturnType<typeof askModel>>) => {
    // the reply is ready: a holding line not sent yet never goes now (ruling 1636: never on a reply that is about to leave)
    if (r.text) void t.holding?.settle();
    const after = recordOnAdopt.get(r);
    if (after) { recordOnAdopt.delete(r); t.caseAfter = after; t.deliveredReply = undefined; }
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
  const heldTurn = (aud: 'customer' | 'supplier' | 'visitor' | 'founder', lang: 'en' | 'ar', situation: string, why: string) => {
    t.heldFiled = true;   // the re-ask answers this turn: the holding line, if it went, is not left unanswered (holding.ts)
    return holdUnwritten({ from: From, body: Body, messageSid: MessageSid || null, audience: aud, lang, situation, why, outage: t.sayOutage, problems: t.sayProblems,
      enabled: async () => (await sec('wa_autoreply_enabled')) === 'true', send: (t) => sendWa(From, t),
      rpc: async (f, a) => { const r = await admin.rpc(f, a); return { data: r.data, error: r.error }; } });
  };
  Object.assign(t, { historyUnavailable, askModel, adopt, sayFor, say, sayLane, heldTurn });
}
