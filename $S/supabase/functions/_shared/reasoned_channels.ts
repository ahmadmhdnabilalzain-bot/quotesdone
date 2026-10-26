// reasoned_channels — what a message on a customer channel ASKS, decided by reasoning (think()), never by
// a word list. Seat: it_engineer (shared platform); the decisions belong to customer_support (WhatsApp, the
// website widget) and marketing (Instagram / Facebook DMs). 23 Sep 2026, founder_instruction 886-903.
//
// WHAT THIS REPLACES (decision_points.json 7-14):
//   * fn_wa_answer matched wa_reply_intent.match_patterns against the body          (wa_inbound.intent_table)
//   * coverage.ts EN/AR regexes decided a coverage question, and the longest label
//     substring decided which trade was named                                         (wa_inbound.coverage_intent, .trade_named)
//   * size_question.ts regexes decided "how big are you"                             (shared.size_question)
//   * chat_answers.ts COST/COUNT/TIMELINE regexes picked a canned FAQ                (shared.route_question)
//   * reply.ts match_words substrings picked a standard social reply, and one shared
//     word decided a knowledge passage answered the question                         (marketing_social.library_match, .on_topic)
//   * site_assistant SUP_RE/CUS_RE decided customer vs supplier                      (site_assistant.audience)
//   * site_assistant tok() FAQ scoring and a one-shared-word passage gate             (site_assistant.passage_and_faq_scoring)
//   * chat_answers quoteAnswer FIELD_RE / QUOTE_RE / ABOVE_RE / a shared-word score   (shared.quote_answer)
//   * sales_engineer onTopic passage filter                                           (sales_engineer.on_topic)
//
// ONE DECISION PER MESSAGE PER CHANNEL. The WhatsApp question is ONE choice among everything the database
// can answer (an intent row, our size, the trade list, one trade), and the social DM is ONE choice among the
// standard replies, the three FAQ questions, our size and the retrieved passages. One reasoning, one held row,
// one replay — so a message held under the hold is answered once when it lifts, never three times.
//
// UNDER THE HOLD every function returns value null. Nobody is answered on a guess:
//   * WhatsApp: the question takes the deterministic road that needs no meaning (the approved FAQ, then the
//     courteous line + menu, the question filed as a knowledge gap). Only then is the meaning filed in
//     customer_support's queue (queueWhatsAppMeaning), and the replay sends the reasoned answer on WhatsApp
//     (reasoned_delivery.ts, surface wa_inbound.intent_table).
//   * social: the honest 'unknown' library reply goes (a gap is recorded, a person offered) and the meaning
//     waits in the marketing queue; the replay sends the grounded reply on the platform (surface
//     marketing_social.library_match).
//   * portal chat (sales_engineer): nothing is queued; the honest notYet answer files a task with the question.
//   * website widget: an anonymous visitor has no channel to be answered on later, so nothing is queued; the
//     widget's own path answers (gateway, price guide, corpus) or files the question as a knowledge gap.
import { think, type ThinkDeps, type ThinkRequest, type ThinkResult } from './think.ts';
import { FIELD_LABEL, FIELDS, figures, type QuoteForAnswer } from './chat_answers.ts';
import type { Reasoned } from './reasoned_decisions.ts';

export type Option = { id: string; meaning: string };

/** Shared option: a question about how big we are is answered with what we do, never a number (instruction 777). */
export const SIZE: Option = {
  id: 'size',
  meaning: 'they ask how big QuotesDone is or how much it does — how many suppliers, customers, requests, quotes or deals we have or have handled, or our revenue, volumes or figures — however it is worded, in any language. NOT a question about how many quotes THEIR request will receive',
};
const NONE: Option = { id: 'none', meaning: 'none of the above: anything else' };

async function choose(deps: ThinkDeps, req: ThinkRequest): Promise<Reasoned<string>> {
  const result = await think(deps, req);
  return { value: result.status === 'answered' ? result.decision?.choice ?? null : null, result };
}

// ── WhatsApp (surface wa_inbound.intent_table; also wa_inbound.coverage_intent, wa_inbound.trade_named,
//    shared.size_question) ────────────────────────────────────────────────────────────────────────
export type WaIntent = { intent_key: string; label: string };
export type WaTrade = { code: string; label: string; label_ar?: string | null };
export const COVERAGE_LIST = 'coverage:list';
export const COVERAGE_OTHER = 'coverage:other';

/** Every answer the WhatsApp database road holds, as options. intent:<key> is a wa_reply_intent row. */
export function whatsappOptions(intents: WaIntent[], trades: WaTrade[]): Option[] {
  return [
    ...intents.map((i) => ({ id: 'intent:' + i.intent_key, meaning: i.label })),
    SIZE,
    { id: COVERAGE_LIST, meaning: 'they ask which trades, sectors, categories or services QuotesDone covers, in general' },
    // ponytail: one option per live trade (195 on 23 Sep 2026); a two-stage choice if the list outgrows a prompt.
    ...trades.map((t) => ({ id: 'trade:' + t.code, meaning: `they ask whether we cover or handle ${t.label}${t.label_ar ? ' (' + t.label_ar + ')' : ''} work specifically` })),
    { id: COVERAGE_OTHER, meaning: 'they ask whether we cover a specific trade or service that is NOT one of the trades listed above' },
    NONE,
  ];
}

export interface WaMeaningInput {
  message: string; intents: WaIntent[]; trades: WaTrade[]; phone: string; messageSid?: string | null;
  audience?: 'customer' | 'supplier' | 'founder' | 'unknown';
}
function waRequest(o: WaMeaningInput, queue: boolean): ThinkRequest {
  return {
    seat: 'customer_support', surface: 'wa_inbound.intent_table', question: o.message.slice(0, 4000),
    dedupeKey: 'wa_meaning:' + (o.messageSid || o.phone + ':' + o.message.slice(0, 40)),
    subject: { channel: 'whatsapp', phone: o.phone, message_sid: o.messageSid ?? null },
    context: { audience: o.audience === 'supplier' ? 'supplier' : o.audience === 'founder' ? 'founder' : 'customer' },
    decision: { name: 'whatsapp_question', options: whatsappOptions(o.intents, o.trades) },
    queueWhenHeld: queue,
  };
}
/** What the WhatsApp message asks. Not queued when held: the caller files it only if nothing else answered. */
export const whatsappMeaning = (deps: ThinkDeps, o: WaMeaningInput) => choose(deps, waRequest(o, false));
/** The meaning, filed in customer_support's queue for replay when nothing else answered the message — WITHOUT a
 *  second think(): the request the first ask built, filed with the reason it was not answered (the hold, or a
 *  reasoning that failed), so no model is ever called twice for one message. */
export async function queueWhatsAppMeaning(deps: ThinkDeps, o: WaMeaningInput, reason: string): Promise<number | null> {
  const req = waRequest(o, true);
  const { data, error } = await deps.rpc('fn_reason_hold', {
    p_seat: req.seat, p_surface: req.surface, p_question: req.question, p_request: JSON.parse(JSON.stringify(req)),
    p_plan: {}, p_subject: req.subject ?? null, p_reason: reason, p_dedupe_key: req.dedupeKey ?? null,
  });
  // A filing that fails must be seen: the caller turns this throw into an IT finding (never a silent loss).
  if (error) throw new Error('fn_reason_hold: ' + error.message);
  return Number(data) || null;
}

// ── The website widget (surface shared.route_question; also shared.size_question, site_assistant.audience,
//    site_assistant.passage_and_faq_scoring) — ONE reasoned decision per message ────────────────────────
export const SITE_OPTIONS: Option[] = [
  SIZE,
  { id: 'cost', meaning: 'they ask what USING QuotesDone costs them — its fees, charges or commission, or whether it is free. NOT what a job, a material or a trade costs, and not a fee charged by anyone else' },
  { id: 'count', meaning: 'they ask how many quotes their own request will receive, or how many suppliers receive it' },
  { id: 'timeline', meaning: 'they ask how long the QuotesDone process takes — until quotes arrive, or until a supplier is verified. NOT how long anything else takes' },
  NONE,
];
const SIDES: Option[] = [
  { id: 'supplier', meaning: 'and they write as a business that wants to SELL or quote through QuotesDone (registering as a supplier, a trade licence, receiving jobs or leads)' },
  { id: 'customer', meaning: 'and they write as someone who wants to BUY (a job done, products priced, quotes for their project)' },
  { id: 'unknown', meaning: 'and it does not say which side of the marketplace they are on' },
];
/** The widget's options: the canned questions, each retrieved passage (kb:<n>), none — crossed with the visitor's
 *  side (…|supplier / …|customer / …|unknown) only when neither the session nor the page path already says it. */
export function widgetOptions(passages: Passage[], askSide: boolean): Option[] {
  const base = [
    ...SITE_OPTIONS.filter((x) => x.id !== 'none'),
    ...passages.map((p, n) => ({ id: 'kb:' + n, meaning: `this passage of company knowledge answers what they asked: "${String(p.content || '').slice(0, 400)}"` })),
    NONE,
  ];
  return askSide ? base.flatMap((b) => SIDES.map((s) => ({ id: b.id + '|' + s.id, meaning: b.meaning + ' — ' + s.meaning }))) : base;
}
/** What the visitor asks, which passage (if any) answers it, and which side they are on — one think() call.
 *  Never queued: an anonymous visitor cannot be answered later; held, every value is null. */
export async function widgetMeaning(deps: ThinkDeps, o: { message: string; conversation?: string; passages: Passage[]; askSide: boolean }):
  Promise<{ question: string | null; side: 'customer' | 'supplier' | null; result: ThinkResult }> {
  const r = await choose(deps, {
    seat: 'customer_support', surface: 'shared.route_question', question: o.message.slice(0, 4000), queueWhenHeld: false,
    context: { audience: 'visitor', ...(o.conversation ? { conversation: [{ role: 'visitor', text: o.conversation.slice(0, 3000) }] } : {}) },
    decision: { name: 'widget_question', options: widgetOptions(o.passages, o.askSide) },
  });
  const [question, side] = (r.value ?? '').split('|');
  return { question: question || null, side: side === 'customer' || side === 'supplier' ? side : null, result: r.result };
}

// ── The portal chat (sales_engineer; surfaces shared.quote_answer and sales_engineer.on_topic) ────────────
/** Which of the customer's own quotes, which field, and — where the line and the question each carry one metre
 *  figure — whether the line applies to their case. ponytail: the first 15 quotes (by price) are offered. */
export function quoteOptions(quotes: QuoteForAnswer[], message: string): Option[] {
  const out: Option[] = [];
  quotes.slice(0, 15).forEach((q, i) => {
    const who = `the quote${q.rfq_no ? ' for request ' + q.rfq_no : ''}${q.inquiry_summary ? ' ("' + String(q.inquiry_summary).slice(0, 80) + '")' : ''} from ${q.supplier_label}`;
    for (const f of FIELDS) {
      const line = q[f] ? String(q[f]).slice(0, 300) : '';
      const what = `they ask about the ${FIELD_LABEL[f].en} of ${who}` + (line ? `, which reads: "${line}"` : ' (the supplier left it blank)');
      if (line && figures(line, message)) {
        out.push({ id: `q:${i}:${f}:applies`, meaning: what + ' — and as written that line APPLIES to the case they describe' });
        out.push({ id: `q:${i}:${f}:does_not_apply`, meaning: what + ' — and as written that line does NOT apply to the case they describe' });
      } else out.push({ id: `q:${i}:${f}`, meaning: what });
    }
  });
  return [...out, { id: 'none', meaning: 'the question is not about any of these quotes' }];
}
export function quoteQuestion(deps: ThinkDeps, o: { message: string; quotes: QuoteForAnswer[] }): Promise<Reasoned<string>> {
  return choose(deps, {
    seat: 'sales_engineer', surface: 'shared.quote_answer', question: o.message.slice(0, 4000), queueWhenHeld: false,
    context: { audience: 'customer' }, decision: { name: 'quote_question', options: quoteOptions(o.quotes, o.message) },
  });
}
/** Which retrieved passage answers the portal question (kb:<n>), or none. */
export function portalPassage(deps: ThinkDeps, o: { message: string; passages: Passage[] }): Promise<Reasoned<string>> {
  return choose(deps, {
    seat: 'sales_engineer', surface: 'sales_engineer.on_topic', question: o.message.slice(0, 4000), queueWhenHeld: false,
    context: { audience: 'customer' },
    decision: { name: 'portal_passage', options: [
      ...o.passages.map((p, n) => ({ id: 'kb:' + n, meaning: `this passage answers what they asked: "${String(p.content || '').slice(0, 400)}"` })),
      { id: 'none', meaning: 'none of these passages answers what they asked' },
    ] },
  });
}

// ── Social DMs (surface marketing_social.library_match; also marketing_social.on_topic, shared.size_question,
//    shared.route_question) ───────────────────────────────────────────────────────────────────────
export type SocialLibraryRow = { key: string; priority: number | null; reply_en: string; active: boolean };
export type Passage = { content: string; citation?: string | null };
export const FAQ_TYPES = ['cost', 'count', 'timeline'] as const;

/** A standard reply is a library row with a priority (the utility rows — handoff, unknown, suffix, comment
 *  replies — carry none). Each is offered by what it SAYS; its match_words are no longer read. */
export function socialOptions(library: SocialLibraryRow[], passages: Passage[]): Option[] {
  return [
    ...library.filter((r) => r.active && r.priority != null)
      .map((r) => ({ id: 'lib:' + r.key, meaning: `the standard "${r.key}" reply answers it: "${String(r.reply_en || '').slice(0, 240)}"` })),
    SIZE,
    ...SITE_OPTIONS.filter((x) => (FAQ_TYPES as readonly string[]).includes(x.id)).map((x) => ({ id: 'faq:' + x.id, meaning: x.meaning })),
    ...passages.map((p, n) => ({ id: 'kb:' + n, meaning: `this passage of company knowledge answers what they asked: "${String(p.content || '').slice(0, 400)}"` })),
    NONE,
  ];
}
/** Which grounded reply answers the DM. Held: queued in the marketing seat; the replay replies on the platform.
 *  The passages ride on the held row, so the replay sends exactly the passage that was reasoned over.
 *  A PUBLIC COMMENT (comment: true) is not queued: a DM reply is not how a comment is answered, and the comment
 *  policy (marketing_social_comments.ts processComment) owns what a held comment gets. */
export function socialMeaning(deps: ThinkDeps, o: {
  message: string; library: SocialLibraryRow[]; passages: Passage[]; platform: string; messageId: string; userId: string; comment?: boolean;
}): Promise<Reasoned<string>> {
  return choose(deps, {
    seat: 'marketing', surface: 'marketing_social.library_match', question: o.message.slice(0, 4000),
    dedupeKey: (o.comment ? 'social_comment_meaning:' : 'social_meaning:') + o.platform + ':' + o.messageId, queueWhenHeld: !o.comment,
    subject: { platform: o.platform, message_id: o.messageId, user_id: o.userId, passages: o.passages.map((p) => ({ content: String(p.content || '').slice(0, 700), citation: p.citation ?? null })) },
    context: { audience: 'visitor' },
    decision: { name: 'social_reply', options: socialOptions(o.library, o.passages) },
  });
}
