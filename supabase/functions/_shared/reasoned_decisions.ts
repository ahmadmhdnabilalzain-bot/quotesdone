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
    context: { audience: o.audience ?? 'customer', conversation: o.conversation },
    decision: {
      name: 'needs_a_person',
      options: [
        { id: 'needs_a_person', meaning: 'they ask to speak to a human, OR they complain, dispute, demand a refund, accuse us or a supplier of wrongdoing, or threaten legal action — however it is worded, in any language' },
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
