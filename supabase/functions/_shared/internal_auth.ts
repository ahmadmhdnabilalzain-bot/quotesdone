// AUDIT 9.5 / WI-001 - scoped credentials for server-to-server calls.
//
// The thing being removed: ONE string in app_secrets.inbound_secret authenticates 43 cron jobs,
// 42 distinct edge functions, 20 database functions and every other internal hop. It is not a
// credential, it is THE credential - one disclosure is total, it cannot be rotated without
// changing every caller in the same instant, and every call it authenticates is identical in the
// logs, so a leak could not be scoped, only guessed at.
//
// Every internal function should call requireInternal() instead of comparing a string. The
// decision is made in the database by fn_internal_auth, so scope, rotation and attribution live in
// one place rather than in 137 copies of `body.__secret !== inbound`.
//
// MIGRATION SAFETY. fn_internal_auth accepts BOTH the new per-context credentials and the existing
// shared secret, the latter registered as an explicit legacy credential with scope '*'. So moving a
// function to this module changes NOTHING about who can call it today - it only starts recording
// which credential did. Callers move to scoped credentials one context at a time afterwards, and
// the shared secret is withdrawn only once v_internal_credential_health shows its use_count has
// stopped rising.
//
// FAIL CLOSED. If the verifier cannot be reached, the call is refused. A monitoring function that
// silently runs unauthenticated because the database hiccuped is the failure this whole item is
// about.

// THE STORED SECRET MUST BE A REAL VALUE BEFORE ANY PRESENTED VALUE CAN EQUAL IT (fail-closed, 27 Jul 2026).
// A function that still compares a presented secret with one read from app_secrets reads `undefined` or '' when that
// read fails or the row is missing; compared strictly, a caller posting {} then matched and gained service-role
// authority on a function that requires no JWT. secretOk() is the guard in front of every such comparison. It was
// written out identically in 13 functions until 10 Nov 2026 (docs/engineering/duplicated-helpers.md); they import it.
export const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;

// deno-lint-ignore no-explicit-any
type Admin = any;

export type InternalAuthResult =
  | { ok: true; context: string; credentialId: number; legacy: boolean }
  | { ok: false; status: number; error: string; message: string };

/**
 * Authenticate a server-to-server call.
 *
 * @param admin     a service-role Supabase client
 * @param secret    the presented credential (conventionally body.__secret)
 * @param fnName    THIS function's slug, e.g. 'uptime_check'. Scope is checked against it, so it
 *                  must be the real slug - passing something else silently widens the check.
 * @param declaredCaller
 *                  What the CALLER says it is, when the payload carries it — ai_gateway's `body.fn`,
 *                  for example. Recorded only when the credential that authenticated is the legacy
 *                  shared one, and only as a CLAIM (see below).
 *
 * WHY THE FOURTH ARGUMENT EXISTS.
 *
 * fn_internal_auth records `function_name`, and that is the CALLEE — the function being invoked.
 * Every legacy_secret_used row therefore reads 'ai_gateway', which is the one thing already known.
 * Asked on 13 Aug 2026 to find who is still presenting the shared secret, the answer was:
 *
 *   * llm.ts's gatewayCredential fallback is NOT it. It logs agent 'llm_gateway_auth' to agent_runs
 *     on every fallback, and that table holds ZERO rows — no importer of the shared module is on it.
 *   * social_stage's 6 Aug uses are historical; it reads cred_fn_social_stage now.
 *   * capability_agent's header still says it presents inbound_secret; the code reads cred_fn_ai.
 *   * The five remaining uses (most recently 12 Aug 07:38:57, callee ai_gateway) correlate with NO
 *     cron run, NO llm_calls row and NO net._http_response within the minute — so the caller is
 *     outside the database, and nothing on either side of the hop wrote down which one.
 *
 * ai_gateway already knows: it reads `body.fn` ten lines after it authenticates. The claim was
 * simply never carried across. Now it is, so the NEXT legacy use names itself instead of adding one
 * more row to a count nobody can attribute.
 *
 * IT IS A CLAIM, NOT AN IDENTITY, and the reason it is safe to record is that it is only written
 * for a credential that has ALREADY authenticated and is stored under a reason that says so. It
 * never widens scope, and it is never read as authorisation.
 */
export async function requireInternal(admin: Admin, secret: unknown, fnName: string, declaredCaller?: unknown): Promise<InternalAuthResult> {
  const presented = typeof secret === 'string' ? secret : '';
  if (!presented) {
    return { ok: false, status: 403, error: 'forbidden', message: 'No internal credential was presented.' };
  }
  try {
    const { data, error } = await admin.rpc('fn_internal_auth', { p_secret: presented, p_function: fnName });
    if (error) throw new Error(error.message);
    const r = data as any;
    if (r?.ok === true) {
      // Legacy only. A scoped credential IS the attribution, so writing this for one would be a
      // second row saying what internal_credential.context already says.
      if (r.legacy === true) {
        const claim = typeof declaredCaller === 'string' ? declaredCaller.trim().slice(0, 120) : '';
        try {
          await admin.from('internal_credential_audit').insert({
            credential_id: Number(r.credential_id), context: String(r.context), function_name: fnName,
            allowed: true, reason: 'legacy_caller_declared',
            detail: { declared_caller: claim || null, note: claim ? 'Claimed by the caller in its own payload; not verified.' : 'The caller declared nothing, so the payload carries no self-identification either.' },
          });
        } catch (_e) { /* attribution must never fail an authenticated call */ }
      }
      return { ok: true, context: String(r.context), credentialId: Number(r.credential_id), legacy: r.legacy === true };
    }
    // out_of_scope is deliberately NOT distinguished from unknown_credential in the response. The
    // caller does not need to learn which of the two it was, and telling it turns the endpoint into
    // a scope-discovery oracle. The real reason is in internal_credential_audit.
    return { ok: false, status: 403, error: 'forbidden', message: 'This credential is not accepted for this function.' };
  } catch (_e) {
    return {
      ok: false, status: 503, error: 'credential_check_unavailable',
      message: 'The credential could not be verified, so the call was refused rather than allowed.',
    };
  }
}

/** Convenience wrapper for the common `return J(...)` shape. */
export function internalAuthResponse(r: Extract<InternalAuthResult, { ok: false }>, headers: Record<string, string> = {}) {
  return new Response(JSON.stringify({ error: r.error, message: r.message }), {
    status: r.status,
    headers: { 'Content-Type': 'application/json', ...headers },
  });
}
