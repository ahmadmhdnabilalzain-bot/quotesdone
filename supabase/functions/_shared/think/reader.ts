// think/reader.ts — a reader of the person's own text: one fixed step, no retrieval (moved whole from _shared/think.ts).
import type { ThinkRequest } from './types.ts';

/**
 * A READER OF THE PERSON'S OWN TEXT (13 Oct 2026, measured live on a ZZ DEMO photographed quotation): the quotation's
 * terms and line specs were each planned by a decompose call that wrote to the 900-token cap think() itself set (the
 * routing policy allows 2,000 for routine_employee_reasoning and 4,000 for supplier_communication), and the decision JSON
 * was cut at the same 900, so validity, delivery and warranty the photo stated were asked again, and the retries took
 * the turn past 150 s. A reader has nothing to plan and nothing to look up: one fixed step with no knowledge retrieval,
 * and room for the decision it writes. SYNTH_FOR_READERS stays under supplier_communication's policy cap.
 * prevented by: _shared/think_reader.test.ts
 */
export const SYNTH_FOR_READERS = 3000;
export function readerOfTheirOwnText(goal: string): Pick<ThinkRequest, 'plan' | 'maxTokens' | 'reader'> {
  return { plan: { steps: [{ id: 'read', goal, query: goal, needs_knowledge: false }] }, maxTokens: { synthesise: SYNTH_FOR_READERS }, reader: true };
}
