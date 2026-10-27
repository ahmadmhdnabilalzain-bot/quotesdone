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
import { guardSupportReply, replyViolations, type GuardLang } from './support_reply_guard.ts';
import { policyProblems, revealFeeIncomplete } from './company_brief.ts';
import { aiReply } from './ai_reply.ts';
import { BRIEF_TEXT } from './brief.generated.ts';

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
  widget: 'Plain text for a chat window (no markdown), under about 70 words. Keep the JSON short: at most two brief reasoning items, nothing else extra.',
  whatsapp: 'Plain text for WhatsApp (no markdown), under about 90 words; each phone number, email or link on its own line.',
  email: 'Plain text for an e-mail body, without a greeting or a sign-off (they are added).',
  portal: 'Plain text for the portal chat (no markdown), under about 120 words; the person is signed in.',
};

// THE PORTAL TAKES A JOB BRIEF LIKE A SENIOR ESTIMATOR (ledger 1200, customer_support with sales_engineer, 27 Oct 2026).
// The portal chat reached think() with one generic line ("Reply to this customer message ... under about 120 words"),
// while the founder's standard is an adaptive, expert conversation: the wardrobe from a studio photo is asked its
// dimensions, shelves vs hanging, door type. Measured in the adaptive conversation bank (scripts/e2e/
// adaptive_conversation_bank.mjs, run on the deployed portal 27 Oct; the report names the runs): the failures this
// rule targets. The rule rides in the question of every portal reply (the reasoned path) AND in the rules of the direct
// reply (a photo turn, a held chain), so both roads take the brief the same way. Code writes no reply text here.
export const PORTAL_INTAKE = 'WHEN THEY DESCRIBE A JOB THEY WANT PRICED, take the brief the way a senior UAE estimator does. '
  + '(1) Read the whole conversation first: everything they have already said is known. Never ask again for anything they already stated or answered, in any wording; a question they skipped or were unsure about is noted "to confirm at the supplier\'s site visit" and not repeated. When they change something, the change replaces the earlier choice. '
  + '(2) If a specification they state is wrong, unsafe, or not accepted in the UAE (by code, Civil Defence, the municipality or the building), say so plainly first, then the correct specification and why, in one or two sentences; never go along with it. '
  + '(3) Then ask the two or three missing specifications that most change the price for THIS trade, as short questions, offering concrete choices where that helps (for example sliding, hinged or push-to-open doors): sizes and quantities, material, finish and type or system, the existing condition and removal, site access, permits and approvals, and timing. A must-have the trade cannot be priced without (sizes, the type of system, the approvals) comes before anything optional. '
  + '(4) When the essentials are known, give a short summary of the job as they told it, with every change they made, and ask them to confirm it; once confirmed, tell them to press "New request" (Arabic portal: "طلب جديد") to send it to verified suppliers. '
  + 'Never a robotic yes or no, never "I don\'t know" or "I will check": answer what can be said now. '
  // baseline 1b6b12b6: both glass turns ended on the same fee paragraph nobody asked for
  // after-fix run ab519dba: asked "unsure", the seat argued for the sliding doors the customer had just changed away from
  + 'A choice they made stays made: never reopen it or argue for an option they changed away from. When they say they are unsure, recommend an answer to the question you last asked, then move on. '
  + 'Do not add the fee, "posting is free" or how long quotes take unless they ask. Write short sentences of at most about 20 words.';

// THE TRADE PLAYBOOKS REACH THE PORTAL'S TEXT TURNS (27 Oct 2026). knowledge/brief/conversation/*.md (what a senior
// estimator asks per trade, in order, with the misconceptions to correct) and conversation_style.md are compiled into
// BRIEF_TEXT, which aiReply and the website chat are given. The portal's text turns go through think(), whose outside
// brief is company.md alone (settledFacts), so the founder's own wardrobe playbook never reached the portal chat that
// takes the brief. The same compiled files are now its guide: the intake rule first, then the method, then every trade's
// playbook (about 30k tokens, input-priced; no keyword picks the trade, the model reads the job).
const PLAYBOOK_FILE = /^knowledge\/brief\/(conversation_style\.md|conversation\/[a-z_]+\.md)$/;
/** The compiled files of BRIEF_TEXT whose path matches, in compiled order. */
export function briefFiles(text: string, match: RegExp): string[] {
  const parts = text.split(/<<<FILE ([^>]+)>>>\n?/);
  const out: string[] = [];
  for (let i = 1; i < parts.length; i += 2) if (match.test(parts[i])) out.push(parts[i + 1].trim());
  return out;
}
let guideMemo = '';
export function portalGuide(): string {
  if (!guideMemo) guideMemo = [PORTAL_INTAKE, ...briefFiles(BRIEF_TEXT, PLAYBOOK_FILE)].join('\n\n');
  return guideMemo;
}

/** The portal's retrieval query: the customer's first message (the job) and this one, when they differ; at most 500 chars. */
export function jobQuery(req: Pick<SupportReplyRequest, 'message' | 'conversation'>): string {
  const first = (req.conversation ?? []).find((t) => t.role !== 'seat')?.text?.trim() ?? '';
  const msg = req.message.trim();
  const q = first && first !== msg ? first.slice(0, 300) + '\n' + msg : msg;
  return q.slice(0, 500);
}

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
  images?: string[];             // photos or drawings with the message (chat_images.acceptImages): answered by a vision model (ruling 1200)
  priceTrades?: string[];         // widget: the published trades; the answering call says which one (if any) is asked the price of
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
  verified?: string | null;       // the independent check's verdict on the reply that went out ('agreed' on every widget reply)
  priceTrade?: string | null;     // the published trade the visitor asks the price of, chosen in the answering call (widget)
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
  // NO CANNED FALLBACK (founder rulings 1195/1196/1197, 12 Oct 2026). When the reasoned chain cannot send its reply
  // (held, failed, unchecked, unreadable), the reply is still written BY A MODEL — aiReply: the company brief given,
  // one call, the figure check and the reply guard with a model rewrite, the model ladder. The caller's `fallback`
  // (its old stored/canned road) is no longer called. Only when no model answers at all is the reply '' (path
  // 'fallback'), and the caller sends nothing.
  void fallback;
  const fall = async (reason: string): Promise<SupportReply> => {
    const a = await aiReply(deps, { seat: req.seat ?? 'customer_support', channel: req.channel, audience: req.audience, lang: req.lang,
      message: req.message, conversation: req.conversation, facts: [req.profile ? 'THEIR OWN RECORD: ' + JSON.stringify(req.profile) : '', req.facts ?? ''].filter(Boolean).join('\n\n'),
      rules: FORMAT[req.channel] + (req.channel === 'portal' ? '\n- ' + PORTAL_INTAKE : ''), images: req.images }).catch(() => ({ reply: '', model: null, attempts: ['threw'] }));
    if (a.reply) return await logged({ reply: a.reply, path: 'reasoned', seat: null, reason: 'direct: ' + reason, model: a.model, grounded: true, readability: checkReadability(a.reply, req.lang) });
    return await logged({ reply: '', path: 'fallback', seat: null, reason: reason + ' | no model answered: ' + a.attempts.join(', '), grounded: false });
  };
  try {
    let passages = (req.passages ?? []).filter((p) => p && String(p.content || '').trim());
    if (!passages.length) {
      const { data } = await deps.rpc('fn_support_corpus_search', { p_query: req.message, p_public: req.channel !== 'portal', p_limit: 5 });
      passages = Array.isArray(data) ? data.map((r: { content?: string; citation?: string }) => ({ content: String(r.content || ''), citation: r.citation ?? null })) : [];
    }
    // THE WIDGET'S REPLY IS CHECKED, AND ONLY CHECKED TEXT LEAVES (12 Oct 2026). The independent check runs on every widget
    // answer; a reply the reviewer did not AGREE with (not run, or disagreed and redrafted) is never sent or cached: the
    // caller's road answers instead. The plain-language rewrite happens before the check (think.polish), never after.
    // A PHOTO OR DRAWING (ruling 1200): the reasoning chain reads text only, so a message with images is answered by the
    // direct model reply, which sends them as image parts to a vision model under the same checks.
    if (req.images?.length) return await fall('photo');
    const checked = req.channel === 'widget';
    const plain = async (text: string): Promise<string | null> => {
      const g0 = guardSupportReply(text.trim(), req.lang);
      const rd0 = checkReadability(g0.text, req.lang);
      if (rd0.ok) return null;
      const rw = await deps.llm('synthesise', rewritePrompt(req.lang), JSON.stringify({ reply: g0.text, problems: rd0.issues }),
        { taskClass: taskClassFor('synthesise', req.audience, false, req.lang), seat: req.seat ?? 'customer_support', max: 600 });
      let a = '';
      try { a = String(JSON.parse(String(rw.content ?? '').replace(/^```(json)?|```$/g, '').trim())?.answer ?? ''); } catch (_e) { a = ''; }
      return a.trim() || null;
    };
    const r = await think(deps, {
      seat: req.seat ?? 'customer_support', surface: `support_reply.${req.channel}`, route: ROUTE_SEATS,
      question: `Reply to this ${req.audience} message to QuotesDone as its ${req.seat ?? 'customer_support'} seat, in ${req.lang === 'ar' ? 'formal Gulf Arabic' : 'UAE English'}. ${FORMAT[req.channel]} `
        + 'Take every fee, rule and figure from the TOPIC KNOWLEDGE and FACTS in the context and nowhere else. When you state a fee, state with it what the facts say is and is not added on top of it (for example a card fee or VAT). Never promise a refund (management decides it), never name another customer or supplier, never state how many suppliers or customers we have, never say "AI" (say "Smart Engine"), never give a licence number. '
        + 'If the matter belongs to another seat, say you have passed it to that team and still answer what can be said.'
        + '\n\nMESSAGE:\n' + req.message.slice(0, 4000),
      context: { audience: req.audience === 'visitor' ? 'visitor' : req.audience, language: req.lang, conversation: req.conversation, profile: req.profile,
        case: { channel: req.channel, topic_knowledge: passages.slice(0, 6).map((p) => (p.citation ? p.citation + '\n' : '') + p.content.slice(0, 1500)), facts: req.facts ? req.facts.slice(0, 6000) : null } },
      research: false, queueWhenHeld: false, dedupeKey: req.dedupeKey, subject: req.subject,
      // THE WIDGET HANDS OVER ITS PLAN (12 Oct 2026, customer_support): it has already searched the corpus for this
      // message (the passages above), so the planning call — 5-9 s of a 20-30 s reply, measured — is skipped, and the
      // independent check runs on EVERY widget answer instead of only when a planner called it high-stakes.
      // Its plain-language rewrite runs BEFORE that check, so the checked text is the text sent; and which published
      // trade (if any) they ask the price of is chosen in the same answering call, not by a second chain (546, #1327).
      ...(checked ? { plan: { steps: [{ id: 's1', goal: 'answer the visitor from company knowledge', query: req.message.slice(0, 500) }] }, stakes: 'high' as const, polish: plain,
        // short outputs on the fastest cross-family pair (writer and reviewer routed by task class; 12 Oct 2026)
        maxTokens: { synthesise: 600, verify: 300 },
        ...(req.priceTrades?.length ? { ask: { key: 'price_trade', options: [...req.priceTrades.map((t) => ({ id: t, meaning: `they ask what ${t.replace(/-/g, ' ')} work or material costs` })),
          { id: 'none', meaning: 'they do not ask the price of one of these trades (platform fees, how it works, anything else)' }] } } : {}) } : {}),
      // THE PORTAL HANDS OVER ITS PLAN TOO (27 Oct 2026, customer_support with sales_engineer). Measured on the deployed portal
      // (run a91b68b7, ai_cost_log): a text turn was plan 26-33 s + answer 27-31 s + check 5-8 s, and under load the 150 s
      // request limit cut turns off (the customer got nothing). sales_engineer already retrieved for this message
      // (fn_sales_assist, the passages above), so the plan is handed over. Its query is the JOB plus this message: a turn
      // like "Sliding doors, handle-less." retrieves nothing about wardrobes on its own. The independent check runs on every
      // portal answer (stakes high), because a wrong spec accepted is the failure the founder named zero tolerance for.
      // The intake rule and the trade playbooks ride in the answering call's system prompt (think's guide), never in the
      // question: think() embeds and retrieves on the question, and a page of rules there pulls retrieval off the job.
      ...(req.channel === 'portal' ? { plan: { steps: [{ id: 's1', goal: 'answer the customer and take their job brief', query: jobQuery(req) }] }, stakes: 'high' as const, guide: portalGuide(), effort: 'low' as const } : {}),
      // a short refusal of a manipulation or an out-of-scope ask may be the reply here, and nowhere else (think.ts)
      allowDecline: true,
    });
    if (r.status !== 'answered' || !r.answer.trim()) return await fall(r.reason || 'not_answered');
    if (checked && r.verified?.status !== 'agreed') return await fall('unchecked: the independent check ' + (r.verified?.status ?? 'did not run'));
    // A reply the guard refuses (or that affirms a false policy claim) goes BACK TO A MODEL — aiReply rewrites it with the
    // problems checked — never to a substituted canned line (review of #1330, 12 Oct 2026).
    const refused = [...replyViolations(r.answer), ...policyProblems(r.answer), ...revealFeeIncomplete(r.answer)];
    if (refused.length) return await fall('guard: ' + refused.join(', '));
    let g = guardSupportReply(r.answer.trim(), req.lang);
    let rd = checkReadability(g.text, req.lang);
    let rewritten = r.steps.some((s) => s.id === 'polish');
    if (!rd.ok && checked) return await fall('readability: ' + rd.issues.join(' '));
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
      verified: r.verified?.status ?? null, priceTrade: r.extra && r.extra !== 'none' ? r.extra : null,
      grounded: passages.length > 0 || r.sources.length > 0 });
  } catch (e) {
    return await fall('error: ' + String((e as Error)?.message || e).slice(0, 200));
  }
}
