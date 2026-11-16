// resilience_ping step caseCatchup, its e-mail half (no client of its own: the caller passes the deps).
import type { ThinkDeps } from '../../_shared/think.ts';

// THE E-MAIL CASE SUMMARY A REPLY OWES (customer_support, 16 Nov 2026). email_triage writes it after the reply, past the response
// (recordCaseExchange, never awaited), so a worker ended first leaves it owed exactly as on WhatsApp, and the beat read only
// WhatsApp. public.fn_support_case_email_summaries_owed lists the owed e-mail cases with the exchange itself (their last answered
// mail and the reply that went); the same summariseExchange writes it (the WhatsApp half: customer_support.ts caseCatchupTick). At most `limit` a beat, one case_summary call each.
// prevented by: resilience_ping/email_case_catchup.test.ts
type Summarise = (deps: ThinkDeps, o: { memory: { ref: string; summaryText: string; version: number; profile: number }; theirMessage: string; ourReply: string; seat?: string }) => Promise<{ ok: boolean; reason?: string }>;
export async function emailCaseCatchup(deps: ThinkDeps, limit = 3, summarise?: Summarise): Promise<{ ok: boolean; owed: number; written: number; failed: number; reason?: string }> {
  try {
    const write = summarise ?? (await import('../../_shared/support_case_memory.ts')).summariseExchange;
    const { data, error } = await deps.rpc('fn_support_case_email_summaries_owed', { p_limit: limit });
    if (error) return { ok: false, owed: 0, written: 0, failed: 0, reason: String(error.message ?? error).slice(0, 200) };
    // deno-lint-ignore no-explicit-any
    const owed = (Array.isArray(data) ? data : []) as any[];
    let written = 0, failed = 0;
    for (const c of owed) {
      const their = String(c.their_message ?? '').trim(), ours = String(c.our_reply ?? '').trim();
      if (!their || !ours) continue;
      const r = await write(deps, { memory: { ref: String(c.case_ref), summaryText: String(c.summary_text ?? ''), version: Number(c.summary_version ?? 0), profile: Number(c.profile ?? 0) },
        theirMessage: their, ourReply: ours, seat: 'customer_support' });
      if (r.ok) written++; else failed++;
    }
    return { ok: failed === 0, owed: owed.length, written, failed };
  } catch (e) { return { ok: false, owed: 0, written: 0, failed: 0, reason: 'threw: ' + String((e as Error)?.message || e).slice(0, 200) }; }
}
