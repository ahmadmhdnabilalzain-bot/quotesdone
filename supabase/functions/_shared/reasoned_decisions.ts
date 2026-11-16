// reasoned_decisions — the decision points migrated off word lists onto think(), one function each.
// Seat: it_engineer (shared platform). 23 Sep 2026, founder_instruction 886-903.
//
// Each surface used to decide what a message MEANS by spotting words. Each now asks think() — plan,
// context, knowledge, then a choice among named options, validated — and gets back one of three things:
//   * the reasoned choice                               (models live)
//   * null, with the question filed in the seat's queue  (the hold, or a model that failed or evaded)
// A null is never replaced by a keyword guess; the surface does the safe, non-committal thing and the
// queue replays the question the moment the hold lifts. The registry of every decision point, migrated
// and not yet, is decision_points.json beside this file; scripts/checks/decision_points_are_reasoned.test.mjs
// fails when a migrated one goes back to a word list.
import { readerOfTheirOwnText, think, withDeadline, type ThinkDeps, type ThinkResult, type Turn } from './think.ts';
import { surfaceEffort } from './effort_policy.ts';
import { handFaultToIt, type FaultReport } from './support_fault_handover.ts';
import { COMPLAINT_OPTIONS, isComplaint, registerComplaint, type ComplaintReport, type Ticket } from './complaint_register.ts';
import { isStanding, type Standing, STANDING_OPTIONS } from './escalation_clock.ts';
import { INJECTION_OPTIONS, isInjectionAttempt, type InjectionReport, recordInjectionAttempt } from './injection_attempt.ts';

export type Reasoned<T> = { value: T | null; result: ThinkResult };

export const NEEDS_PERSON_OPTIONS = [
  { id: 'needs_a_person', meaning: 'they ask to speak to a human, OR they complain, dispute, demand a refund, accuse us or a supplier of wrongdoing, threaten legal action, or report a safety danger (an injury, fire, gas, electrical danger or a structural risk) — however it is worded, in any language' },
  // A FAULT IS THE IT ENGINEER'S, AND IT IS HANDED OVER (founder ruling 1705, 15 Nov 2026: "The IT engineer should solve it, not
  // report it"). Chosen by the model, never by a word list (ruling 1663); a surface that sees it hands the fault to the it_engineer
  // through support_fault_handover.ts. A fault reported WITH a complaint, a dispute or a demand for a person stays needs_a_person.
  { id: 'site_fault', meaning: 'they report that something on QuotesDone does not work for them -- the site or app, signing in, a code that never arrived, an upload, the licence step, the agreement or certificate, a page or an error message -- however it is worded, in any language, and they do NOT ask for a human, complain about us, dispute a charge or demand a refund' },
  { id: 'no_person', meaning: 'anything else, including a question that merely mentions law, legality, refunds or complaints as a topic' },
];
/** The reasoned reading chose site_fault: something on QuotesDone does not work for them (it is the it_engineer's to repair). */
export const isSiteFault = (choice: unknown): boolean => choice === 'site_fault';

/** WhatsApp and social: does this message need a person? (surfaces wa_inbound.needs_a_person, marketing_social.needs_a_person) */
export async function needsAPerson(deps: ThinkDeps, o: {
  seat: 'customer_support' | 'marketing'; surface: string; message: string; conversation?: Turn[];
  audience?: 'customer' | 'supplier' | 'visitor'; dedupeKey?: string; subject?: Record<string, unknown>;
  /** What the surface knows to hand a reported fault to the it_engineer (support_fault_handover.ts); absent, nothing is filed. */
  fault?: Omit<FaultReport, 'message'>;
  /** What the surface knows to register a complaint (complaint_register.ts): when given, the SAME call also reads whether the
   *  message is a complaint (COMPLAINT_OPTIONS) and, when the model says so, the ticket is opened once for the message. */
  complaint?: Omit<ComplaintReport, 'message' | 'reading'> & { message?: string };
  /** Who wrote it and which message (injection_attempt.ts): when given, the SAME call also reads whether the message tries to
   *  instruct the assistant, and when the model says so the attempt is kept on that sender's record. Nothing is blocked. */
  attempt?: Omit<InjectionReport, 'surface' | 'reading' | 'model'>;
}): Promise<Reasoned<boolean> & { fault?: boolean; standing?: Standing | null; complaint?: boolean; ticket?: Ticket | null; injection?: boolean }> {
  const result = await think(deps, {
    seat: o.seat, surface: o.surface, question: o.message, dedupeKey: o.dedupeKey, subject: o.subject,
    context: { audience: o.audience ?? 'customer', conversation: o.conversation },
    // A choice among given options needs no planner: its options are the whole of what it needs (think.ts `plan`).
    // Measured 18 Oct 2026: the plan call was 5-8 s of every one of these, and the plan was never used by a decision.
    plan: { steps: [] }, effort: surfaceEffort(o.surface),   // a person needed is a decision (effort_policy.ts, ruling 1630)
    decision: {
      name: 'needs_a_person',
      options: NEEDS_PERSON_OPTIONS,
    },
    // WHO IS WRITING, IN THE SAME CALL (customer_support, 16 Nov 2026; hole hunt item 4): a journalist, a lawyer or a regulator was
    // answered at once as a new customer. The model reads it beside the person question (no second call, ruling 1663: never a word
    // list); a surface that sees press, legal or regulator gives the holding line and hands the case to the CEO (escalation_clock.ts).
    // A COMPLAINT IS READ IN THE SAME CALL too (customer_support, 16 Nov 2026, COO hole H2): no second model call per message
    also: [{ key: 'standing', options: STANDING_OPTIONS }, ...(o.complaint ? [{ key: 'complaint', options: COMPLAINT_OPTIONS }] : []),
           // AN ATTEMPT TO INSTRUCT THE ASSISTANT, in the same call (it_engineer, 16 Nov 2026; FAILURES hunt item 12)
           ...(o.attempt ? [{ key: 'instructs_the_assistant', options: INJECTION_OPTIONS }] : [])],
  });
  const fault = result.status === 'answered' && isSiteFault(result.decision?.choice);
  // the hand-over never stands in the reply's way and never throws (handFaultToIt answers filed:false with the reason)
  if (fault && o.fault) await handFaultToIt((fn, args) => deps.rpc(fn, args), { ...o.fault, message: o.message, conversation: o.fault.conversation ?? o.conversation });
  const standing = result.status === 'answered' && isStanding(result.also?.standing) ? result.also!.standing as Standing : null;
  // a complaint enters the register with its legal clock, whatever the channel (complaint_register.ts; never throws)
  const complaint = !!o.complaint && result.status === 'answered' && isComplaint(result.also?.complaint);
  const opened = complaint && o.complaint
    ? await registerComplaint((fn, args) => deps.rpc(fn, args), { ...o.complaint, message: o.complaint.message ?? o.message, reading: (result.answer || '').slice(0, 600) || 'read as a complaint (' + o.surface + ')' })
    : null;
  // an attempt to instruct the assistant goes onto the sender's record (injection_attempt.ts; never throws, never blocks)
  const injection = !!o.attempt && result.status === 'answered' && isInjectionAttempt(result.also?.instructs_the_assistant);
  if (injection && o.attempt) await recordInjectionAttempt((fn, args) => deps.rpc(fn, args), { ...o.attempt, surface: o.surface, reading: result.answer, model: result.model ?? null });
  return { value: result.status === 'answered' ? result.decision?.choice === 'needs_a_person' : null, result, fault, standing,
           ...(o.complaint ? { complaint, ticket: opened?.ticket ?? null } : {}), ...(o.attempt ? { injection } : {}) };
}

/** The founder's command: which intent in ceo_command_intent does it carry? (surface ceo.command_intent) */
export async function commandIntent(deps: ThinkDeps, o: {
  body: string; intents: { intent_id: string; meaning: string }[]; commandId: number;
}): Promise<Reasoned<string>> {
  const result = await think(deps, {
    seat: 'ceo', surface: 'ceo.command_intent', question: o.body, subject: { command_id: o.commandId },
    dedupeKey: 'ceo_command:' + o.commandId,
    context: { audience: 'founder' },
    decision: { name: 'intent', options: o.intents.filter((i) => i.intent_id !== 'ambiguous').map((i) => ({ id: i.intent_id, meaning: i.meaning })) },
  });
  return { value: result.status === 'answered' ? result.decision?.choice ?? null : null, result };
}

// THE TWO INTAKE DECISIONS RUN INSIDE THE TURN (sales_engineer, 27 Oct 2026; inquiry_intake/turn_clock.ts has the
// measurements). Both ran the whole think() chain inside a customer's interview turn: a plan on gpt-6-luna-pro (p50
// 20.0 s, p95 29.8 s) and an answer pass on a ~51k-token prompt (p50 25.3 s, p95 41.9 s), sometimes twice, for turns of
// 88-130 s against a portal that waits 30 s. Neither decision has anything to plan or look up:
//   - the trade is a choice among given options, which needs no planner (needsAPerson, the same measurement);
//   - the stated specs are a READER of the customer's own words (think.ts readerOfTheirOwnText): one fixed step, no
//     retrieval, and the evidence guard per field, so a field whose value is not inside the customer's own words,
//     copied verbatim, is dropped and asked, while the proven ones are kept (exact specs or nothing, unchanged).
// `deadline` (epoch ms) cuts every model call at the turn's clock (turn_clock.ts withDeadline). A decision cut there is
// held like any model that did not answer: nothing is chosen and nothing is filled.

// THE WHOLE CONVERSATION, NOT ITS FIRST 4,000 CHARACTERS (10 Nov 2026, sales_engineer; founder ledger 1572). Both intake
// readings sent the opening 4,000 characters of the customer's text as the question (and the spec reader the same slice
// again as the conversation), so in a long chat an answer given late never reached them: the reader could not prove a spec
// the customer had stated, and the field was asked again. The customer's whole text (the intake passes only their own
// messages, at most 100 per inquiry by the cap) now rides as the conversation, which is also what the evidence guard
// reads, and the question carries its newest part. Nothing is cut for length below chat_history's ~2M-character budget.
// prevented by: _shared/reasoned_decisions_whole_conversation.test.ts
export const QUESTION_TAIL = 4000;
/** The newest part of the customer's text, for the question line; the whole text rides in the context. */
export const newest = (conversation: string) => conversation.length <= QUESTION_TAIL ? conversation : conversation.slice(-QUESTION_TAIL);

/** Intake: the model's trade and the checklist evidence disagree — which trade is it? (surface inquiry_intake.trade) */
export async function tradeOf(deps: ThinkDeps, o: {
  conversation: string; candidates: { slug: string; label: string }[]; dedupeKey?: string; subject?: Record<string, unknown>; deadline?: number;
}): Promise<Reasoned<string>> {
  const result = await think(o.deadline ? withDeadline(deps, o.deadline) : deps, {
    seat: 'sales_engineer', surface: 'inquiry_intake.trade', question: newest(o.conversation), dedupeKey: o.dedupeKey, subject: o.subject,
    context: { audience: 'customer', conversation: [{ role: 'customer', text: o.conversation }] },
    plan: { steps: [] }, effort: surfaceEffort('inquiry_intake.trade'),   // inside the chat turn: the effort that fits it (effort_policy.ts clock, ledger 1642)
    decision: { name: 'trade', options: o.candidates.map((c) => ({ id: c.slug, meaning: `the job is ${c.label} work` })) },
  });
  return { value: result.status === 'answered' ? result.decision?.choice ?? null : null, result };
}

/** Intake: which required spec fields has the customer ALREADY stated, in their own words? (surface inquiry_intake.exact_spec)
 *  Not queued when held: nothing replays it (fn_reason_held_resolve has no case for this surface), and the field is
 *  asked of the customer on this very turn instead.
 *  MEASURED through production's gateway on 6 ZZ DEMO readings each way (27 Oct 2026, run 57a34ffb): as a reader, one
 *  answer pass on customer_communication (gpt-6-luna-pro, ~20k prompt tokens) took 13.3-17.4 s and kept up to 4 proven
 *  fields; routed instead as the interview's own class (claude-sonnet-5.5) it took 8.8-13.4 s and kept 1-2, the rest
 *  failing the evidence guard. So the class stays, and inquiry_intake starts this reading ALONGSIDE its interview call
 *  rather than after it (index.ts specRead): the turn costs the longer of the two, not their sum. */
export async function statedSpecs(deps: ThinkDeps, o: {
  conversation: string; fields: { key: string; question: string }[]; category: string; dedupeKey?: string; deadline?: number;
}): Promise<Reasoned<Record<string, { value: string; evidence: string }>>> {
  const result = await think(o.deadline ? withDeadline(deps, o.deadline) : deps, {
    seat: 'sales_engineer', surface: 'inquiry_intake.exact_spec', question: newest(o.conversation), dedupeKey: o.dedupeKey,
    context: { audience: 'customer', trade: o.category, conversation: [{ role: 'customer', text: o.conversation }] },
    ...readerOfTheirOwnText('which of the listed specs the customer has already stated, each with their own words as evidence'),
    effort: surfaceEffort('inquiry_intake.exact_spec'), queueWhenHeld: false,   // inside the chat turn: the effort that fits it (effort_policy.ts clock, ledger 1642)
    decision: { name: 'stated_specs', fields: o.fields },
  });
  return { value: result.status === 'answered' ? result.decision?.fields ?? {} : null, result };
}

/** Social: the public or private reply, reasoned over the knowledge and checked by a model of another family.
 *  Only an answer the independent reviewer AGREED with is returned; anything else is null (the caller escalates).
 *  Its surfaces (marketing_social.comment_reply, marketing_social.dm_reply) deliberately have NO case in
 *  reasoned_delivery.deliverReasoned: when think() holds, the person has ALREADY been answered on the spot (the comment
 *  with the fixed acknowledgement and an escalation to customer_support, since an empty draft fails guard(); the DM with the honest "unknown" and its
 *  knowledge gap). A late model answer released from the hold would be a second, unasked reply, so it is dropped. */
export async function socialReply(deps: ThinkDeps, o: {
  surface: string; platform: string; message: string; language: 'en' | 'ar'; dedupeKey?: string; subject?: Record<string, unknown>;
  /** How this seat answered cases like it before (case_recall precedentBlock), recalled by the caller. */
  precedent?: string;
}): Promise<Reasoned<string>> {
  const result = await think(deps, {
    seat: 'marketing', surface: o.surface, dedupeKey: o.dedupeKey, subject: o.subject, stakes: 'high',
    question: `Reply as QuotesDone on ${o.platform} to: ${o.message}\nIn ${o.language === 'ar' ? 'native formal Gulf Arabic (formal plural)' : 'UAE English'}, one or two short sentences, plain text, no hashtags. Never name a customer or supplier, never quote an unpublished price, never promise, never give a legal view.`
      + (o.precedent ? o.precedent + '\nNever mention another person, a case number or this block in the reply.' : ''),
    context: { audience: 'visitor', language: o.language },
  });
  const ok = result.status === 'answered' && result.verified?.status === 'agreed' && result.answer.trim();
  return { value: ok ? result.answer.trim() : null, result };
}
