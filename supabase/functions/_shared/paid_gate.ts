// ============================================================================================
// THE ONE PAID-PROVIDER GATE, CLIENT SIDE (kernel K12)
//
// Every function that can reach a paid inference provider asks this and nothing else, and treats
// anything other than an explicit `allowed === true` as DENIED.
//
// The shape this replaces, from ai_gateway before K12:
//
//     try {
//       const { data: pf } = await admin.rpc('fn_llm_preflight', { p_model: m });
//       if (pf && pf.allowed === false) { skipped.push(...); continue; }
//     } catch (_e) { /* preflight must never be the reason a call cannot happen */ }
//     ladder.push(m);
//
// Three routes to a paid call with no permission: the RPC throws and the catch falls through to
// push; the RPC returns null and `pf &&` short-circuits to push; the RPC returns a shape without
// `allowed` and the strict `=== false` misses it. A gate that "must never be the reason a call
// cannot happen" is not a gate.
//
// Here the default is refusal and permission is the special case. There is no catch that continues.
// ============================================================================================

export type PaidGate = {
  allowed: boolean;
  rule: string;
  reason: string;
  model?: string | null;
  gate: string;
};

const DENY = (rule: string, reason: string, model?: string | null): PaidGate =>
  ({ allowed: false, rule, reason, model: model ?? null, gate: 'kernel_k12' });

/**
 * Ask the single database authority whether a paid provider call may be made.
 *
 * Returns `{allowed:true}` ONLY when the gate says so in as many words. Every other outcome —
 * a throw, a null, a non-object, a missing or non-boolean `allowed`, an `allowed` that is not
 * literally true — is a denial with a reason naming what went wrong. A caller cannot accidentally
 * treat "I could not tell" as "yes".
 *
 * `admin` is a supabase-js client holding the service-role key.
 */
export async function paidProviderGate(
  // deno-lint-ignore no-explicit-any
  admin: any,
  model: string | null,
): Promise<PaidGate> {
  let data: unknown;
  try {
    const res = await admin.rpc('fn_kernel_paid_provider_gate', { p_model: model });
    if (res?.error) {
      return DENY('gate_rpc_error', `the gate returned an error: ${res.error.message ?? res.error}`, model);
    }
    data = res?.data;
  } catch (e) {
    return DENY('gate_unreachable', `the gate could not be reached: ${(e as Error)?.message ?? e}`, model);
  }
  if (data === null || data === undefined) {
    return DENY('gate_returned_nothing', 'the gate returned no row; absence is not permission', model);
  }
  if (typeof data !== 'object') {
    return DENY('gate_malformed', `the gate returned a ${typeof data}, not an object`, model);
  }
  const g = data as Record<string, unknown>;
  if (g.allowed !== true) {
    return {
      allowed: false,
      rule: String(g.rule ?? 'denied'),
      reason: String(g.reason ?? 'the gate did not answer allowed=true'),
      model: (g.model as string) ?? model,
      gate: String(g.gate ?? 'kernel_k12'),
    };
  }
  return {
    allowed: true,
    rule: String(g.rule ?? 'allowed'),
    reason: String(g.reason ?? ''),
    model: (g.model as string) ?? model,
    gate: String(g.gate ?? 'kernel_k12'),
  };
}

/**
 * The convenience form for a call site that has nothing sensible to do with a refusal except stop.
 * Throws a PaidProviderDenied whose message carries the rule and the reason, so the refusal reaches
 * the log as a decision rather than as a mystery.
 */
export class PaidProviderDenied extends Error {
  readonly gate: PaidGate;
  constructor(gate: PaidGate) {
    super(`paid provider denied (${gate.rule}): ${gate.reason}`);
    this.name = 'PaidProviderDenied';
    this.gate = gate;
  }
}

// deno-lint-ignore no-explicit-any
export async function assertPaidProviderAllowed(admin: any, model: string | null): Promise<PaidGate> {
  const g = await paidProviderGate(admin, model);
  if (!g.allowed) throw new PaidProviderDenied(g);
  return g;
}
