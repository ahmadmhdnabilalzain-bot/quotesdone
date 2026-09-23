// seat_deliberation — the runner for a review between two seats on models of DIFFERENT families.
// Seat: it_engineer. 23 Sep 2026, founder_instruction 873 ("they shouldn't be on the same model").
//
// The rules live in the database (scripts/sql/a_seat_is_never_reviewed_by_a_model_of_its_own_family.sql):
// fn_seat_deliberation_step decides the next model step, routes the reviewer to another family through
// fn_ai_route_review, builds the payload (blind first, proposal withheld) and records "held, not run" or
// "no independent reviewer" itself. This file only carries a call_model step to ai_gateway — with
// counterpart_model, so the gateway routes through fn_ai_route_review too — and hands the answer back to
// fn_seat_deliberation_record, whose trigger refuses a same-family turn or an approval with no steelman.
//
// INTERFACE FOR A SEAT'S BUILD (the marketing <-> ceo monthly plan debate, sales_engineer -> ceo, ...):
//   const { data: id } = await admin.rpc('fn_seat_deliberation_open', { p_kind, p_author_seat,
//     p_reviewer_seat, p_question, p_evidence, p_proposal, p_author_model });
//   await advanceDeliberation(admin, id);          // or leave it to the resilience_ping heartbeat
//   ... later, the AUTHOR seat: rpc('fn_seat_deliberation_close', { p_id: id, p_closed_by, p_outcome })
// deno-lint-ignore no-explicit-any
type Admin = any;

export type ReviewOutput = Record<string, unknown> & { verdict?: string };

/** The model's reply as one JSON object, or null. Tolerates a ```json fence; nothing else. */
export function parseReviewOutput(text: string | null): ReviewOutput | null {
  if (!text) return null;
  const m = text.trim().match(/^```(?:json)?\s*([\s\S]*?)\s*```$/);
  try {
    const o = JSON.parse(m ? m[1] : text.trim());
    return o && typeof o === 'object' && !Array.isArray(o) ? o as ReviewOutput : null;
  } catch (_e) { return null; }
}

/**
 * Advance one deliberation by at most `maxSteps` model steps (blind, then compare). Never throws:
 * a refusal by the database (malformed, same family) is recorded as a 'failed' turn with its reason.
 */
export async function advanceDeliberation(admin: Admin, id: number, maxSteps = 2): Promise<unknown[]> {
  const out: unknown[] = [];
  for (let i = 0; i < maxSteps; i++) {
    const { data: step, error } = await admin.rpc('fn_seat_deliberation_step', { p_id: id });
    if (error) { out.push({ ok: false, error: 'fn_seat_deliberation_step: ' + error.message }); break; }
    out.push({ action: step?.action, phase: step?.phase, why: step?.why });
    if (step?.action !== 'call_model') break;

    // Imported here, not at the top: llm.ts opens a client at load, and parseReviewOutput is tested without one.
    const { makeLlmRich } = await import('./llm.ts');
    const llm = makeLlmRich([], {
      fn: 'resilience_ping', taskClass: step.task_class, agent: step.reviewer_seat, dept: step.dept,
      max: step.max_tokens, timeoutMs: 60_000, cacheTtlMin: 0,
    });
    const r = await llm(step.system, JSON.stringify(step.payload), step.max_tokens, '',
      { counterpartModel: step.counterpart_model });
    const record = (status: string, output: Record<string, unknown>, why: string | null) =>
      admin.rpc('fn_seat_deliberation_record', {
        p_id: id, p_phase: step.phase, p_model: r.model ?? step.model, p_output: output,
        p_status: status, p_why: why,
      });

    if (!r.used_llm || r.error || !r.content) {
      const held = /circuit_open|open-circuit|founder_hold/.test(String(r.error ?? ''));
      await record(held ? 'held_not_run' : 'failed', {}, (held ? 'held, not run: ' : 'no answer: ') + (r.error ?? 'empty'));
      break;
    }
    const parsed = parseReviewOutput(r.content);
    const { error: recErr } = parsed
      ? await record('recorded', { ...parsed, _payload_sha256: step.payload_sha256 }, null)
      : { error: { message: 'MALFORMED_REVIEW: the reply is not one JSON object' } };
    if (recErr) {
      await record('failed', { raw: String(r.content).slice(0, 4000) }, String(recErr.message).slice(0, 500));
      out.push({ ok: false, refused: String(recErr.message).slice(0, 200) });
      break;
    }
  }
  return out;
}

/** The heartbeat: open deliberations, least recently attempted first (fn_seat_deliberation_due), bounded. */
export async function advanceOpenDeliberations(admin: Admin, limit = 3): Promise<unknown> {
  const { data, error } = await admin.rpc('fn_seat_deliberation_due', { p_limit: limit });
  if (error) return { ok: false, error: 'fn_seat_deliberation_due: ' + error.message };
  const done: Record<string, unknown> = {};
  for (const id of (data ?? []) as number[]) done[id] = await advanceDeliberation(admin, id);
  return { advanced: Object.keys(done).length, steps: done };
}
