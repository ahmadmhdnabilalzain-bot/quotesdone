// A HIGH-STAKES DECISION WAITS FOR A SECOND SEAT ON ANOTHER MODEL FAMILY. Seat: it_engineer (shared platform).
// 29 Sep 2026, founder_instruction 1009 upgrade 10. The rule and the verdict live in the database
// (scripts/sql/a_high_stakes_decision_waits_for_a_second_seat_on_another_family.sql); the review itself is the
// existing seat_deliberation machine (blind first, another family, disagreements stated). A decision path calls:
//
//   const c = await challengeBeforeDeciding(admin, { kind: 'refund', seat: 'customer_support', subject, question,
//     evidence, proposal, authorModel, authorTaskClass });
//   if (!c.cleared) return hold(c);   // agreed, or the disagreement (c.reason) is on record and the decision waits
//
// While the model hold is on, the review is held and c.state is 'held': the decision waits, it is never waved through.
import { advanceDeliberation } from './seat_deliberation.ts';

// deno-lint-ignore no-explicit-any
type Admin = any;
export type HighStakesKind = 'pricing_change' | 'campaign_launch' | 'supplier_choice' | 'refund';
export type Clearance = {
  cleared: boolean; state: 'agreed' | 'disagreed' | 'held' | 'pending' | 'no_independent_reviewer' | 'not_challenged' | 'failed';
  reason: string | null; deliberation_id?: number | null; reviewer_seat?: string; reviewer_model?: string | null; verdict?: string | null;
};

export async function challengeBeforeDeciding(admin: Admin, o: {
  kind: HighStakesKind; seat: string; subject: { table: string; id: string }; question: string;
  evidence: Record<string, unknown>; proposal: Record<string, unknown>; authorModel: string; authorTaskClass?: string | null;
  demo?: boolean;
  // deno-lint-ignore no-explicit-any
  makeLlm?: any;   // tests pass a stubbed model; production uses llm.ts through advanceDeliberation
}): Promise<Clearance> {
  const { data: id, error } = await admin.rpc('fn_high_stakes_challenge', {
    p_kind: o.kind, p_author_seat: o.seat, p_subject_table: o.subject.table, p_subject_id: o.subject.id,
    p_question: o.question, p_evidence: o.evidence, p_proposal: o.proposal, p_author_model: o.authorModel,
    p_author_task_class: o.authorTaskClass ?? null, p_demo: o.demo ?? false,
  });
  // A challenge that cannot open is not a clearance: the decision waits.
  if (error || id == null) return { cleared: false, state: 'failed', reason: 'fn_high_stakes_challenge: ' + (error?.message ?? 'no id') };
  await advanceDeliberation(admin, Number(id), 2, o.makeLlm);
  return await clearance(admin, o.kind, o.subject);
}

export async function clearance(admin: Admin, kind: HighStakesKind, subject: { table: string; id: string }): Promise<Clearance> {
  const { data, error } = await admin.rpc('fn_high_stakes_clearance', { p_kind: kind, p_subject_table: subject.table, p_subject_id: subject.id });
  if (error || !data) return { cleared: false, state: 'failed', reason: 'fn_high_stakes_clearance: ' + (error?.message ?? 'no answer') };
  return { ...data, cleared: data.cleared === true } as Clearance;
}
