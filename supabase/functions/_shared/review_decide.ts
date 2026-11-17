// review_decide — the open requests to review an automated decision are DECIDED, never left waiting (ledger 1152, 19 Oct 2026).
// Seat: ceo (the heartbeat that drives it); the reviewer is the seat that owns the decision.
//
// For each request fn_review_request_due hands over: the owning seat's reviewing model is asked, through ai_gateway,
// with counterpart_model = the model that made the original decision (or 'deterministic'). The gateway routes that
// through fn_ai_route_review, so the answer comes from ANOTHER family; fn_review_request_conclude records it with the
// model that actually answered, and the table's CHECK refuses a same-family verdict whatever this file does. The seat
// acts on an overturn (decision_log) and customer_support replies to the requester (delivery.request), both in SQL.
//
// No import here: the live wiring (ceo_agent) and the sandbox proof (scripts/e2e/...) pass their own IO, so the one
// decision path is the one that is proved.

import { parseJson } from './model_json.ts';
export type DueReview = {
  id: number; owner_seat: string; decision_type: string; meaning: string; channel: string; requester: string;
  request_text: string; original_seat: string | null; original_family: string; counterpart_model: string;
  reviewer_model_hint: string | null; subject_table: string | null; subject_id: string | null;
  evidence: unknown; original_decision: unknown;
};
export type Verdict = { verdict: 'upheld' | 'overturned' | 'amended'; reasons: string; reply: string };
export type ReviewIO = {
  due(limit: number, id?: number): Promise<DueReview[]>;
  ask(r: DueReview, system: string, input: string): Promise<{ content: string | null; model: string | null; error?: string | null }>;
  conclude(id: number, v: Verdict, model: string): Promise<Record<string, unknown>>;
  failed(id: number, error: string): Promise<unknown>;
};

export const REVIEW_TASK_CLASS = 'ceo_judgement';   // an existing review class (reviews internal_judgement, support_ai, ...)

export function reviewPrompt(r: DueReview): { system: string; input: string } {
  const system = `You are the ${r.owner_seat} of QuotesDone, a UAE procurement marketplace. A ${r.channel} contact asked for a person to `
    + `review an automated decision about ${r.meaning}. You are the independent reviewer: you did not make that decision. `
    + 'Weigh the original decision, its evidence and the requester\'s words. Uphold it when it was right, overturn it when it was wrong, '
    + 'amend it when part of it stands. Never invent a fact that is not in the input; when the evidence is missing, say what is missing and uphold. '
    + 'Return STRICT JSON ONLY: {"verdict":"upheld|overturned|amended","reasons":"two to four factual sentences",'
    + '"reply":"a short, courteous reply to the requester in the language they wrote in, with the outcome and the reason, signed QuotesDone Customer Support"}';
  const input = JSON.stringify({
    decision_type: r.decision_type, original_decision: r.original_decision ?? 'not linked: the requester\'s account is the only record',
    original_seat: r.original_seat, evidence: r.evidence ?? {}, requester_words: r.request_text,
    subject: r.subject_table ? { table: r.subject_table, id: r.subject_id } : null,
  });
  return { system, input };
}

/** The model's reply as a verdict, or null. Tolerates a ```json fence; nothing else. */
export function parseVerdict(text: string | null): Verdict | null {
  try {
    // deno-lint-ignore no-explicit-any
    const o = parseJson<any>(text, { exact: true });
    if (!o || !['upheld', 'overturned', 'amended'].includes(o.verdict)) return null;
    const reasons = String(o.reasons ?? '').trim(); const reply = String(o.reply ?? '').trim();
    return reasons ? { verdict: o.verdict, reasons, reply } : null;
  } catch (_e) { return null; }
}

/** Decide up to `limit` open requests (or the one named). Never throws; each outcome is returned. */
export async function decideOpenReviews(io: ReviewIO, limit = 3, id?: number): Promise<Record<string, unknown>[]> {
  const out: Record<string, unknown>[] = [];
  let due: DueReview[] = [];
  try { due = await io.due(limit, id); } catch (e) { return [{ ok: false, error: 'due: ' + String((e as Error)?.message ?? e) }]; }
  for (const r of due) {
    try {
      const { system, input } = reviewPrompt(r);
      const a = await io.ask(r, system, input);
      const v = parseVerdict(a.content);
      if (!a.model || !v) {
        const why = a.error ? 'no answer: ' + a.error : !a.content ? 'no answer' : 'MALFORMED_VERDICT: the reply is not one verdict object';
        await io.failed(r.id, why);
        out.push({ id: r.id, ok: false, error: why });
        continue;
      }
      out.push({ id: r.id, model: a.model, ...(await io.conclude(r.id, v, a.model)) });
    } catch (e) {
      const why = String((e as Error)?.message ?? e).slice(0, 500);
      try { await io.failed(r.id, why); } catch (_e) { /* recorded next tick */ }
      out.push({ id: r.id, ok: false, error: why });
    }
  }
  return out;
}
