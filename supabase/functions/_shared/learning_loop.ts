// THE LEARNING LOOP'S REASONING HALF. Seat: it_engineer (shared platform, for all six seats). 23 Sep 2026.
//
// The database half (scripts/sql/every_judgement_learns_from_its_outcome.sql) records every judgement with
// its recall, writes each real outcome back onto it, measures per-seat accuracy daily, and groups a seat's
// cases with outcomes BY MEANING (vector distance, never words). This file does the one thing SQL cannot:
// it asks think() what each group teaches — at high stakes, so a model of ANOTHER family verifies the
// lesson (think() step f, #877) — and hands the result to fn_reason_apply_learning__distil, where the
// cross-family verdict approves (and promotes into the seat's knowledge), rejects, or leaves it pending.
//
// UNDER THE MODEL HOLD think() files the question in the seat's queue with the group as its subject, and
// replayHeld reasons it when the hold lifts; fn_reason_held_resolve then calls the same apply routine.
// No lesson is ever written from a word list.
import { defaultDeps, think, type Seat, type ThinkDeps } from './think.ts';

export type Cluster = { seat: Seat; cluster_key: string; cases: { case_id: number; case_kind: string; situation: string; decision: string | null; outcome: string | null; finalised: boolean; correction: string | null }[] };

export function distilQuestion(c: Cluster): string {
  return `These ${c.cases.length} past ${c.seat} cases are alike in meaning and each has a real outcome. ` +
    'What single, specific lesson do they teach this seat for the next similar case — what to repeat, what to avoid, and when it applies? ' +
    'State it as guidance the seat can act on, grounded only in these cases; name the case numbers it rests on.';
}

// deno-lint-ignore no-explicit-any
type Admin = any;
export async function distilLessons(admin: Admin, deps?: ThinkDeps, limit = 2): Promise<unknown> {
  const d = deps ?? defaultDeps(admin, 'resilience_ping');
  // Lessons already written get their vector first, so they are retrievable by meaning (gte-small, free).
  let embedded = 0;
  const { data: todo } = await d.rpc('fn_lesson_unembedded', { p_limit: 8 });
  for (const t of (todo ?? []) as { id: number; finding: string }[]) {
    const v = await d.embed(t.finding);
    if (v) { await d.rpc('fn_lesson_embed_write', { p_id: t.id, p_embedding: '[' + v.join(',') + ']' }); embedded++; }
  }
  const { data, error } = await d.rpc('fn_lesson_clusters', { p_limit: limit });
  if (error) return { ok: false, error: error.message, embedded };
  const out: unknown[] = [];
  for (const c of (data ?? []) as Cluster[]) {
    const subject = { cluster_key: c.cluster_key, case_ids: c.cases.map((x) => x.case_id) };
    const r = await think(d, {
      seat: c.seat, surface: 'learning.distil', question: distilQuestion(c), stakes: 'high', research: false,
      context: { audience: 'internal', case: { cases: c.cases } }, subject, dedupeKey: 'lesson:' + c.cluster_key,
    });
    let applied: unknown = null;
    if (r.status === 'answered') {
      const { data: a, error: e } = await d.rpc('fn_reason_apply_learning__distil', { p_id: null, p_result: { ...r, subject } });
      applied = e ? { error: e.message } : a;
    }
    out.push({ cluster: c.cluster_key, seat: c.seat, status: r.status, held_id: r.held_id ?? null, applied });
  }
  return { ok: true, embedded, clusters: out.length, rows: out };
}
