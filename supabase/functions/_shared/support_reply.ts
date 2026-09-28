// support_reply — every customer-facing reply is COMPOSED by the reasoning path. Seat: customer_support.
// Founder instruction 781 (22 Sep 2026): the LLM answers every reply, at all times, because a canned or
// keyword-picked answer leaks through tricky wording ("what does it cost me if the supplier never replies"
// matched the cost FAQ and got the fee, not the refund rule).
//
// WHAT CHANGED. Before this file every channel CHOSE a stored answer (an approved FAQ, a knowledge passage,
// an intent row) and sent that text as it stood; reasoning only picked which one. Now, whenever a model can
// answer, the reply is written by think() for THIS message, with:
//   1. THE KNOWLEDGE NARROWED FIRST — the caller's retrieval for this message (fn_support_corpus_search on
//      the widget, fn_sales_assist in the portal, the FAQ context on WhatsApp) is handed over as the topic's
//      passages; with none, fn_support_corpus_search is asked here. think() then retrieves per plan step.
//   2. THE OWNING SEAT, named in the same pass (route), so a refund reaches the CEO, a payment the accountant,
//      a spec the sales engineer — the scored suite grades it (scripts/eval/support_reply_suite.mjs).
//   3. THE OUTGOING GUARD (support_reply_guard.ts) on the composed text, as on every other reply.
//
// THE ONLY FALLBACK IS "NO MODEL CAN ANSWER": the founder's hold, the gateway down, or a model that failed
// every pass. Then — and only then — the caller's old deterministic road runs (fallback()). Nothing is
// queued from here: the caller already answered, and a replay would send a second reply and pay for it.
//
// THE PLAIN-LANGUAGE GATE (founder instruction 1013 item 7): the guarded reply is scored by readability.ts
// (sentence length, jargon, the customer's language). A failure is rewritten once through the model; a
// second failure, or the hold, sends the plain canned answer. Every reply's scores are logged for the
// monthly customer_support self-review (fn_customer_support_monthly_self_review).
//
// Tested with a stubbed model (support_reply.test.ts); the model hold is never lifted to test it.
import { taskClassFor, think, type Seat, type ThinkDeps, type Turn } from './think.ts';
import { checkReadability, rewritePrompt, type Readability } from './readability.ts';
import { guardSupportReply, type GuardLang } from './support_reply_guard.ts';

export type Channel = 'widget' | 'whatsapp' | 'email' | 'portal';
export type Passage = { content: string; citation?: string | null };

/** Who owns the matter. The ids are the live seats; the meanings are what the scored suite grades against. */
export const ROUTE_SEATS: { id: Seat; meaning: string }[] = [
  { id: 'customer_support', meaning: 'how the marketplace works, fees, coverage, accounts, general questions' },
  { id: 'ceo', meaning: 'a refund request or a dispute about money already paid; any approval' },
  { id: 'accountant', meaning: 'an invoice, a receipt, a double or wrong charge, a payment record' },
  { id: 'sales_engineer', meaning: 'a specification, a drawing, a quotation, a reveal, a technical question about the work' },
  { id: 'it_engineer', meaning: 'the site or app is broken, an error, a login or upload fault' },
  { id: 'marketing', meaning: 'press, media, social media, partnerships, advertising' },
];

const FORMAT: Record<Channel, string> = {
  widget: 'Plain text for a chat window (no markdown), under about 70 words.',
  whatsapp: 'Plain text for WhatsApp (no markdown), under about 90 words; each phone number, email or link on its own line.',
  email: 'Plain text for an e-mail body, without a greeting or a sign-off (they are added).',
  portal: 'Plain text for the portal chat (no markdown), under about 120 words; the person is signed in.',
};

export interface SupportReplyRequest {
  channel: Channel;
  message: string;
  lang: GuardLang;
  audience: 'customer' | 'supplier' | 'visitor';
  seat?: Seat;                    // the seat that answers on this surface (portal: sales_engineer)
  passages?: Passage[];           // the caller's retrieval for THIS message: the narrowed topic
  conversation?: Turn[];
  profile?: Record<string, unknown>;   // the asker's OWN record only
  facts?: string;                 // the company block / published facts the channel already reads live
  dedupeKey?: string;
  subject?: Record<string, unknown>;
}
export interface SupportReply {
  reply: string;
  path: 'reasoned' | 'fallback';
  seat: Seat | null;              // the owning seat the reasoning named (null on the fallback)
  reason?: string;                // why the fallback ran
  model?: string | null;
  violations?: string[];
  readability?: Readability;      // the plain-language gate's verdict on the reply that went out (1013 item 7)
  rewritten?: boolean;            // the composed reply failed the gate and was rewritten once
  grounded: boolean;              // company knowledge was found for this message, or the reply cited a source
}

/** The composed reply, or the caller's deterministic road when no model can answer. Never throws. */
export async function supportReply(deps: ThinkDeps, req: SupportReplyRequest, fallback: () => Promise<string | null>): Promise<SupportReply> {
  // Every reply's readability is recorded for the monthly self-review. A failed write never blocks the reply.
  const logged = async (out: SupportReply): Promise<SupportReply> => {
    if (out.readability) {
      try {
        await deps.rpc('fn_support_reply_readability_log', { p_channel: req.channel, p_lang: req.lang, p_path: out.path,
          p_rewritten: !!out.rewritten, p_score: out.readability.score, p_tone: out.readability.tone, p_issues: out.readability.issues,
          p_reason: out.reason ?? null, p_demo: /^ZZ DEMO/.test(req.message) });
      } catch (_e) { /* the reply matters more than its score */ }
    }
    return out;
  };
  const fall = async (reason: string): Promise<SupportReply> => {
    let text: string | null = null;
    try { text = await fallback(); } catch (_e) { text = null; }
    const reply = text ? guardSupportReply(text, req.lang).text : '';
    return await logged({ reply, path: 'fallback', seat: null, reason, grounded: false, readability: reply ? checkReadability(reply, req.lang) : undefined });
  };
  try {
    let passages = (req.passages ?? []).filter((p) => p && String(p.content || '').trim());
    if (!passages.length) {
      const { data } = await deps.rpc('fn_support_corpus_search', { p_query: req.message, p_public: req.channel !== 'portal', p_limit: 5 });
      passages = Array.isArray(data) ? data.map((r: { content?: string; citation?: string }) => ({ content: String(r.content || ''), citation: r.citation ?? null })) : [];
    }
    const r = await think(deps, {
      seat: req.seat ?? 'customer_support', surface: `support_reply.${req.channel}`, route: ROUTE_SEATS,
      question: `Reply to this ${req.audience} message to QuotesDone as its ${req.seat ?? 'customer_support'} seat, in ${req.lang === 'ar' ? 'formal Gulf Arabic' : 'UAE English'}. ${FORMAT[req.channel]} `
        + 'Take every fee, rule and figure from the TOPIC KNOWLEDGE and FACTS in the context and nowhere else. Never promise a refund (management decides it), never name another customer or supplier, never state how many suppliers or customers we have, never say "AI" (say "Smart Engine"), never give a licence number. '
        + 'If the matter belongs to another seat, say you have passed it to that team and still answer what can be said.\n\nMESSAGE:\n' + req.message.slice(0, 4000),
      context: { audience: req.audience === 'visitor' ? 'visitor' : req.audience, language: req.lang, conversation: req.conversation, profile: req.profile,
        case: { channel: req.channel, topic_knowledge: passages.slice(0, 6).map((p) => (p.citation ? p.citation + '\n' : '') + p.content.slice(0, 1500)), facts: req.facts ? req.facts.slice(0, 6000) : null } },
      research: false, queueWhenHeld: false, dedupeKey: req.dedupeKey, subject: req.subject,
    });
    if (r.status !== 'answered' || !r.answer.trim()) return await fall(r.reason || 'not_answered');
    let g = guardSupportReply(r.answer.trim(), req.lang);
    let rd = checkReadability(g.text, req.lang);
    let rewritten = false;
    if (!rd.ok) {
      // THE PLAIN-LANGUAGE GATE (1013 item 7): one rewrite through the reasoning path; if that still fails,
      // the approved canned answer goes out instead of a reply the customer cannot read.
      const rw = await deps.llm('synthesise', rewritePrompt(req.lang), JSON.stringify({ reply: g.text, problems: rd.issues }),
        { taskClass: taskClassFor('synthesise', req.audience, false, req.lang), seat: req.seat ?? 'customer_support', max: 600 });
      let answer = '';
      try { answer = String(JSON.parse(String(rw.content ?? '').replace(/^```(json)?|```$/g, '').trim())?.answer ?? ''); } catch (_e) { answer = ''; }
      if (answer.trim()) {
        const g2 = guardSupportReply(answer.trim(), req.lang);
        const rd2 = checkReadability(g2.text, req.lang);
        if (rd2.ok) { g = g2; rd = rd2; rewritten = true; }
      }
      if (!rewritten) return await fall('readability: ' + rd.issues.join(' '));
    }
    return await logged({ reply: g.text, path: 'reasoned', seat: (r.route as Seat | null) ?? null, model: r.model ?? null, violations: g.violations, readability: rd, rewritten,
      grounded: passages.length > 0 || r.sources.length > 0 });
  } catch (e) {
    return await fall('error: ' + String((e as Error)?.message || e).slice(0, 200));
  }
}
