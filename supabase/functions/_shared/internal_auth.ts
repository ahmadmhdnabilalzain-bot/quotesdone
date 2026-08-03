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
 */
export async function requireInternal(admin: Admin, secret: unknown, fnName: string): Promise<InternalAuthResult> {
  const presented = typeof secret === 'string' ? secret : '';
  if (!presented) {
    return { ok: false, status: 403, error: 'forbidden', message: 'No internal credential was presented.' };
  }
  try {
    const { data, error } = await admin.rpc('fn_internal_auth', { p_secret: presented, p_function: fnName });
    if (error) throw new Error(error.message);
    const r = data as any;
    if (r?.ok === true) {
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
