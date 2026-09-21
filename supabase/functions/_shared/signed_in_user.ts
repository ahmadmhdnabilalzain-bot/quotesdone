// WHO IS CALLING — answered fast, and never "signed out" when the answer is "auth is down".
//
// Measured 21 Sep 2026. agent_runs showed 401s in supplier_portal and messages_api with a p50 of
// 35,108 ms (7 days), and the same ~35 s refusals in twelve other functions at the same moments
// (18 Sep 01:00-04:50 UTC, 21 Sep 10:04-10:05 UTC). The tokens were NOT invalid. auth_logs for
// 21 Sep 10:04:23-10:05:33: GET /user returned `context deadline exceeded` (request_timeout) three
// times at 10.0 s each on one request id, then `timeout: context canceled` (5xx) — ~35 s — while the
// database was contended. `admin.auth.getUser(jwt)` then returned no user, and every caller turned
// that into 401 "unauthorized": a signed-in customer (Chrome on Windows, ap-south-1, 35,827 ms) was
// told they were not signed in, after waiting 35 s to hear it.
//
// So, in this order:
//   1. a token that cannot be anyone's session is refused LOCALLY, with no network call: not three
//      JWT segments, an unreadable payload, no `sub` (the anon key), or `exp` in the past;
//   2. the auth server is asked with a bound (AUTH_TIMEOUT_MS), not the platform's ~35 s;
//   3. a timeout, a network failure or a 5xx from the auth server is 503 auth_unavailable —
//      retryable, and paged as an error by observe() — never 401, which clients read as signed out.
// Semantics for a real session are unchanged: getUser still decides (revoked/deleted users are
// still refused), so nothing that getUser refused before is accepted now.

export const AUTH_TIMEOUT_MS = 5_000;

type AuthUser = { id: string; email?: string | null };
type AuthLike = {
  auth: { getUser: (jwt: string) => Promise<{ data: { user: AuthUser | null }; error: { status?: number; name?: string } | null }> };
};

export type SignedIn =
  | { ok: true; user: AuthUser & { email: string }; email: string }
  | { ok: false; status: 401 | 503; reason: string };

function b64urlJson(seg: string): Record<string, unknown> | null {
  try {
    const b64 = seg.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(seg.length / 4) * 4, '=');
    const v = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))));
    return v && typeof v === 'object' ? v as Record<string, unknown> : null;
  } catch (_e) { return null; }
}

/** Why this token cannot be a live session, decided without the network — or null if it might be. */
export function localRefusal(jwt: string, nowSec = Math.floor(Date.now() / 1000)): string | null {
  const parts = jwt.split('.');
  if (parts.length !== 3 || parts.some((p) => !p)) return 'malformed';
  const payload = b64urlJson(parts[1]);
  if (!payload) return 'malformed';
  if (typeof payload.sub !== 'string' || !payload.sub) return 'no_subject';
  if (typeof payload.exp === 'number' && payload.exp <= nowSec) return 'expired';
  return null;
}

/** Resolve the Authorization header to a signed-in user with an email, or a status to refuse with. */
export async function signedInUser(admin: AuthLike, authHeader: string | null, timeoutMs = AUTH_TIMEOUT_MS): Promise<SignedIn> {
  const jwt = String(authHeader || '').replace(/^Bearer\s+/i, '').trim();
  const local = localRefusal(jwt);
  if (local) return { ok: false, status: 401, reason: local };
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<'timeout'>((res) => { timer = setTimeout(() => res('timeout'), timeoutMs); });
  try {
    const r = await Promise.race([admin.auth.getUser(jwt).catch(() => 'network' as const), timeout]);
    if (r === 'timeout') return { ok: false, status: 503, reason: 'auth_timeout' };
    if (r === 'network') return { ok: false, status: 503, reason: 'auth_network' };
    const st = Number(r.error?.status ?? 0);
    if (r.error && (st === 0 || st >= 500 || r.error.name === 'AuthRetryableFetchError')) {
      return { ok: false, status: 503, reason: 'auth_unavailable_' + (st || 'network') };
    }
    const user = r.data?.user;
    if (!user || !user.email) return { ok: false, status: 401, reason: 'no_user' };
    return { ok: true, user: user as AuthUser & { email: string }, email: user.email.toLowerCase() };
  } finally { clearTimeout(timer); }
}

/** The body each refusal carries: 401 stays the word clients already handle; 503 says retry. */
export function refusalBody(s: { status: 401 | 503 }) {
  return s.status === 503 ? { error: 'auth_unavailable', retry: true } : { error: 'unauthorized' };
}
