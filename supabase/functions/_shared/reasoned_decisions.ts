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

export type Reasoned<T> = { value: T | null; result: ThinkResult };

export const NEEDS_PERSON_OPTIONS = [
  { id: 'needs_a_person', meaning: 'they ask to speak to a human, OR they complain, dispute, demand a refund, accuse us or a supplier of wrongdoing, or threaten legal action — however it is worded, in any language' },
  { id: 'no_person', meaning: 'anything else, including a question that merely mentions law, legality, refunds or complaints as a topic' },
];

/** WhatsApp and social: does this message need a person? (surfaces wa_inbound.needs_a_person, marketing_social.needs_a_person) */
export async function needsAPerson(deps: ThinkDeps, o: {
  seat: 'customer_support' | 'marketing'; surface: string; message: string; conversation?: Turn[];
  audience?: 'customer' | 'supplier' | 'visitor'; dedupeKey?: string; subject?: Record<string, unknown>;
}): Promise<Reasoned<boolean>> {
  const result = await think(deps, {
    seat: o.seat, surface: o.surface, question: o.message, dedupeKey: o.dedupeKey, subject: o.subject,
    context: { audience: o.audience ?? 'customer', conversation: o.conversation },
    // A choice among given options needs no planner: its options are the whole of what it needs (think.ts `plan`).
    // Measured 18 Oct 2026: the plan call was 5-8 s of every one of these, and the plan was never used by a decision.
    plan: { steps: [] }, effort: 'low',
    decision: {
      name: 'needs_a_person',
      options: NEEDS_PERSON_OPTIONS,
    },
  });
  return { value: result.status === 'answered' ? result.decision?.choice === 'needs_a_person' : null, result };
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

/** Intake: the model's trade and the checklist evidence disagree — which trade is it? (surface inquiry_intake.trade) */
export async function tradeOf(deps: ThinkDeps, o: {
  conversation: string; candidates: { slug: string; label: string }[]; dedupeKey?: string; subject?: Record<string, unknown>; deadline?: number;
}): Promise<Reasoned<string>> {
  const result = await think(o.deadline ? withDeadline(deps, o.deadline) : deps, {
    seat: 'sales_engineer', surface: 'inquiry_intake.trade', question: o.conversation.slice(0, 4000), dedupeKey: o.dedupeKey, subject: o.subject,
    context: { audience: 'customer' },
    plan: { steps: [] }, effort: 'low',
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
    seat: 'sales_engineer', surface: 'inquiry_intake.exact_spec', question: o.conversation.slice(0, 4000), dedupeKey: o.dedupeKey,
    context: { audience: 'customer', trade: o.category, conversation: [{ role: 'customer', text: o.conversation.slice(0, 4000) }] },
    ...readerOfTheirOwnText('which of the listed specs the customer has already stated, each with their own words as evidence'),
    effort: 'low', queueWhenHeld: false,
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
