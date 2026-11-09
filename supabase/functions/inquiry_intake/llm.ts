// inquiry_intake/llm.ts — the one model call, through ai_gateway. Moved verbatim from index.ts (9 Nov 2026).
import { modelHeld } from '../_shared/llm_hold.ts';
import { admin, sec } from './shared.ts';

// `subject` is the verified session email: ai_gateway answers our own ZZ DEMO / @example.invalid harness
// with a no-cost stub instead of a paid call (founder instruction 705, _shared/spend_guards.ts).
// Why the gateway call failed; filled by llm() into the caller's own object, so concurrent requests in one isolate never share it.
export type LlmFailure = { http: number; error: string; detail: string };
export async function llm(messages: any[], subject: { email?: string; customer_id?: string | null } = {}, fail: { v: LlmFailure | null }, deadline: number): Promise<string | null> {
  // THE HOLD IS ASKED BEFORE THE GATEWAY IS CALLED (22 Sep 2026, SEATS-08/CP-14). Under the
  // founder's OpenRouter hold every route in llm_route_health is open until 2126, so this call
  // could only ever come back empty — 592 pointless gateway round trips in 72 h, each logged
  // below as agent_runs status 'error' although the deterministic interview ran exactly as built.
  // The hold and the credential are two independent reads, asked together (turn_clock.ts).
  const [held, key] = await Promise.all([modelHeld(admin), sec('cred_fn_ai')]);
  // Both early exits say why, so the caller can tell "OpenRouter down" (a code-written reply is allowed) from a model
  // that answered (founder_instruction 1339, _shared/openrouter_down.ts).
  if (held) { fail.v = { http: 503, error: 'circuit_open: founder_hold', detail: '' }; return null; }
  if (!key) { fail.v = { http: 0, error: 'no_credential', detail: '' }; return null; }
  // Prompt caching is now applied by ai_gateway on the system prompt it receives.
  const sys = messages.filter((m: any) => m && m.role === 'system').map((m: any) => String(m.content || '')).join('\n\n');
  const input = messages.filter((m: any) => !m || m.role !== 'system');
  {
    try {
      // ON THE TURN'S CLOCK (27 Oct 2026, turn_clock.ts): this fetch had no timeout, so a slow gateway held the whole
      // turn. It is cut at the deadline, and the gateway is told how long we wait (client_timeout_ms) so it finishes
      // inside it. A call cut here fails like any other: the deterministic interview runs instead.
      const waitMs = Math.max(1_000, deadline - Date.now());
      const r = await fetch(Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway', { method: 'POST', signal: AbortSignal.timeout(waitMs), headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: key, fn: 'inquiry_intake', subject, sys, input, response_format: { type: 'json_object' }, max: 4000, temperature: 0.1, client_timeout_ms: waitMs }) });
      // A FAILED TURN SAYS WHY (12 Oct 2026, sales_engineer). Sandbox run 1c94fa6a: the OpenRouter key hit
      // its $200 total limit at 16:39 UTC, every gateway call came back 502, and this function turned each
      // into a 'held' turn with readiness 0 and no reason, so C6-C10 read as 14 turns of nothing.
      if (!r.ok) { const jd = await r.json().catch(() => ({})); fail.v = { http: r.status, error: String(jd?.error ?? ''), detail: String(jd?.detail ?? jd?.why ?? '').slice(0, 300) }; return null; }
      const jd = await r.json(); const c = jd?.content; if (c) return c;
      fail.v = { http: r.status, error: 'empty_content', detail: '' };
    } catch (e) { fail.v = { http: 0, error: 'fetch_failed', detail: String((e as Error)?.message || e).slice(0, 300) }; }
  }
  return null;
}
