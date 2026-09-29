// A HIGH-STAKES DECISION WAITS FOR A SECOND SEAT ON ANOTHER MODEL FAMILY. Seat: it_engineer (shared platform).
// 29 Sep 2026, founder_instruction 1009 upgrade 10. The rule and the verdict live in the database
// (scripts/sql/a_high_stakes_decision_waits_for_a_second_seat_on_another_family.sql, fn_high_stakes_gate); the review is
// the existing seat_deliberation machine (blind first, another family, disagreements stated). A decision path calls:
//
//   const g = await challengeBeforeDeciding(admin, { kind: 'supplier_choice', seat: 'sales_engineer', subject, question,
//     evidence, proposal, authorModel, authorTaskClass });
//   if (!g.proceed) hold the decision;   // agreed = proceed; disagreed = its reason is on record
//
// WHILE THE MODEL HOLD IS ON the gate answers proceed with `owed`: the decision goes ahead and the review runs on the
// heartbeat once the hold lifts; a disagreement then opens a finding for the deciding seat (trg_high_stakes_review).
// After the lift an unreviewed decision is reviewed here, in this call, and blocks until the second seat agrees.
import { advanceDeliberation } from './seat_deliberation.ts';

// deno-lint-ignore no-explicit-any
type Admin = any;
export type HighStakesKind = 'pricing_change' | 'campaign_launch' | 'supplier_choice' | 'refund';
export type Gate = {
  proceed: boolean; owed?: boolean; cleared?: boolean; model_held?: boolean;
  state: 'agreed' | 'disagreed' | 'held' | 'pending' | 'no_independent_reviewer' | 'not_challenged' | 'failed';
  reason: string | null; deliberation_id?: number | null; reviewer_seat?: string; reviewer_model?: string | null; verdict?: string | null;
};

// A SUPPLIER CHOICE IS HIGH STAKES ON A LARGE JOB. ponytail: AED 50,000 on the largest quote is it_engineer's figure, not a
// founder ruling (none exists); change it here, the only place it is read.
export const LARGE_SUPPLIER_CHOICE_AED = 50_000;

export async function challengeBeforeDeciding(admin: Admin, o: {
  kind: HighStakesKind; seat: string; subject: { table: string; id: string }; question: string;
  evidence: Record<string, unknown>; proposal: Record<string, unknown>; authorModel?: string | null; authorTaskClass?: string | null;
  demo?: boolean;
  // deno-lint-ignore no-explicit-any
  makeLlm?: any;   // tests pass a stubbed model; production uses llm.ts through advanceDeliberation
}): Promise<Gate> {
  const gate = async (): Promise<Gate> => {
    const { data, error } = await admin.rpc('fn_high_stakes_gate', {
      p_kind: o.kind, p_author_seat: o.seat, p_subject_table: o.subject.table, p_subject_id: o.subject.id,
      p_question: o.question, p_evidence: o.evidence, p_proposal: o.proposal, p_author_model: o.authorModel ?? null,
      p_author_task_class: o.authorTaskClass ?? null, p_demo: o.demo ?? false,
    });
    // A gate that cannot answer is not a clearance: the decision waits.
    if (error || !data) return { proceed: false, state: 'failed', reason: 'fn_high_stakes_gate: ' + (error?.message ?? 'no answer') };
    return { ...data, proceed: data.proceed === true } as Gate;
  };
  let g = await gate();
  // Not agreed, not owed, and a review that could still run: run it now, then ask again.
  if (!g.proceed && g.deliberation_id && (g.state === 'pending' || g.state === 'held')) {
    await advanceDeliberation(admin, Number(g.deliberation_id), 2, o.makeLlm);
    g = await gate();
  }
  return g;
}
