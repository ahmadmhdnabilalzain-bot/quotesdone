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
import { think, type ThinkDeps, type ThinkResult, type Turn } from './think.ts';

export type Reasoned<T> = { value: T | null; result: ThinkResult };

/** WhatsApp and social: does this message need a person? (surfaces wa_inbound.needs_a_person, marketing_social.needs_a_person) */
export async function needsAPerson(deps: ThinkDeps, o: {
  seat: 'customer_support' | 'marketing'; surface: string; message: string; conversation?: Turn[];
  audience?: 'customer' | 'supplier' | 'visitor'; dedupeKey?: string; subject?: Record<string, unknown>;
}): Promise<Reasoned<boolean>> {
  const result = await think(deps, {
    seat: o.seat, surface: o.surface, question: o.message, dedupeKey: o.dedupeKey, subject: o.subject,
    // THE TWO OPTIONS ARE THE WHOLE OF WHAT THIS NEEDS: nothing to plan, nothing to retrieve (customer_support, 13 Oct 2026).
    // Measured on production (ai_cost_log 02:20-02:21Z): after every widget reply this ran a decompose call
    // (routine_employee_reasoning, Luna) and then a synthesis whose payload carried up to 5 x 6 retrieved knowledge rows,
    // 14,614 and 15,658 prompt tokens, both cut off at the 900-token cap (Luna, then Gemini) and so held. The same
    // shape as priceQuestion. reasoned_decisions.test.ts fails if a decompose or a retrieval comes back.
    plan: { steps: [] },
    context: { audience: o.audience ?? 'customer', conversation: o.conversation },
    decision: {
      name: 'needs_a_person',
      options: [
        { id: 'needs_a_person', meaning: 'they ask to speak to a human, OR they complain, dispute, demand a refund, accuse us or a supplier of wrongdoing, threaten legal action, or report a safety danger (an injury, fire, gas, electrical danger or a structural risk) — however it is worded, in any language' },
        { id: 'no_person', meaning: 'anything else, including a question that merely mentions law, legality, refunds or complaints as a topic' },
      ],
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

/** Intake: the model's trade and the checklist evidence disagree — which trade is it? (surface inquiry_intake.trade) */
export async function tradeOf(deps: ThinkDeps, o: {
  conversation: string; candidates: { slug: string; label: string }[]; dedupeKey?: string; subject?: Record<string, unknown>;
}): Promise<Reasoned<string>> {
  const result = await think(deps, {
    seat: 'sales_engineer', surface: 'inquiry_intake.trade', question: o.conversation.slice(0, 4000), dedupeKey: o.dedupeKey, subject: o.subject,
    context: { audience: 'customer' },
    decision: { name: 'trade', options: o.candidates.map((c) => ({ id: c.slug, meaning: `the job is ${c.label} work` })) },
  });
  return { value: result.status === 'answered' ? result.decision?.choice ?? null : null, result };
}

/** Intake: which required spec fields has the customer ALREADY stated, in their own words? (surface inquiry_intake.exact_spec) */
export async function statedSpecs(deps: ThinkDeps, o: {
  conversation: string; fields: { key: string; question: string }[]; category: string; dedupeKey?: string;
}): Promise<Reasoned<Record<string, { value: string; evidence: string }>>> {
  const result = await think(deps, {
    seat: 'sales_engineer', surface: 'inquiry_intake.exact_spec', question: o.conversation.slice(0, 4000), dedupeKey: o.dedupeKey,
    context: { audience: 'customer', trade: o.category, conversation: [{ role: 'customer', text: o.conversation.slice(0, 4000) }] },
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
