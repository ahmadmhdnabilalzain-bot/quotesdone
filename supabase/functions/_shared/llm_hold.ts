import { e2eRunTag } from './e2e_run.ts';
// llm_hold — "is the founder's OpenRouter hold on right now?", asked BEFORE the gateway is called.
//
// THE HOLD IS A ROW, NOT A FLAG (measured 22 Sep 2026 against production): all 8 rows of
// public.llm_route_health carry open_until = 2126-08-15 and opened_reason 'HELD BY THE FOUNDER
// 15 Aug 2026: no OpenRouter calls until he releases it. Release with: update llm_route_health
// set open_until = null;'. ai_gateway reads the same rows and refuses every call with
// err='circuit_open'.
//
// WHY A CALLER NEEDS TO ASK FIRST. inquiry_intake called ai_gateway on EVERY intake request under
// the hold and logged the deterministic interview — the designed path, running exactly as built —
// as agent_runs status 'error': 592 rows in 72 h (SEATS-08/CP-14, 22 Sep 2026 audit). A run that is
// working as designed must not be logged as a fault, and a call that cannot be answered must not be
// made. Both need the same one-line answer, and nothing in _shared gave it.
//
// IT ASKS THE GATE ITSELF (23 Sep 2026, word-matching audit, part_src_llm). This file used to read
// llm_route_health and call the estate held only when EVERY row was held, while the gate the gateway
// obeys (public.fn_kernel_paid_provider_gate, step 3) refuses on ANY held row. With a partial hold
// this said "available" and every call then failed — the exact false error it was written to stop.
// Two readings of one rule drift; so there is one reading now: the gate's. It is asked with a probe
// model name, and its rule says whether the refusal is the hold (founder_hold, the no_paid_ai switch,
// or no route state at all) or something about that one model (which is not a hold).
//
// COST: one call to a STABLE function, cached per isolate for 60 s. The gateway still enforces the
// hold; this only stops the pointless round trip and the false error.
// ponytail: 60 s cache — a release takes at most a minute to be seen by a warm isolate.

// deno-lint-ignore no-explicit-any
type Admin = any;

export type GateAnswer = { allowed?: unknown; rule?: unknown; [k: string]: unknown } | null | undefined;

/** The gate rules that mean "no model route can answer at all" — the estate-wide hold. */
export const HOLD_RULES = new Set(['founder_hold', 'no_paid_ai_switch', 'empty_route_state']);

/** The name the gate is probed with. It is never registered, so an open estate answers route_not_registered. */
export const HOLD_PROBE_MODEL = 'hold-probe/not-a-model';

/** True when the gate's refusal is the estate-wide hold, not a refusal of one model. */
export function heldFromGate(g: GateAnswer): boolean {
  if (!g || typeof g !== 'object') return false;   // could not tell: the gateway decides
  return g.allowed !== true && HOLD_RULES.has(String(g.rule ?? ''));
}

let _cached: { at: number; held: boolean } | null = null;

/** Is the OpenRouter hold on? Never throws: an unreadable gate answers false and the gateway decides. */
export async function modelHeld(admin: Admin, ttlMs = 60_000): Promise<boolean> {
  // A SANDBOX RUN IS ASKED FRESH AND NEVER CACHED (ledger 1119). Its answer depends on its own window,
  // so it must neither read a real request's cached answer nor leave its own for one.
  const tagged = !!e2eRunTag();
  if (!tagged && _cached && Date.now() - _cached.at < ttlMs) return _cached.held;
  try {
    const { data, error } = await admin.rpc('fn_kernel_paid_provider_gate', { p_model: HOLD_PROBE_MODEL });
    if (error) return false;
    const held = heldFromGate(data as GateAnswer);
    if (!tagged) _cached = { at: Date.now(), held };
    return held;
  } catch (_e) { return false; }
}
