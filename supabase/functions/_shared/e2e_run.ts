// _shared/e2e_run.ts — the stage-2 sandbox run tag, carried for the life of one request (ledger 1119).
// No jsr: or npm: import, so node tests that load llm_hold.ts can load it too.
import { AsyncLocalStorage } from 'node:async_hooks';

// THE SANDBOX RUN TAG TRAVELS WITH THE REQUEST (ledger 1119, 6 Oct 2026). The stage-2 harness sends
// x-qd-e2e-run: <tag>. Every function is wrapped in observe(), which holds the tag for the life of that
// request. Every fetch the function makes back to THIS project (ai_gateway, another function, or
// PostgREST through supabase-js) carries it on. trg_ai_cost_log_e2e_run_tag and fn_kernel_paid_provider_gate
// read it from request.headers.
//
// THE TAG ALONE IS NOT ENOUGH (review of #1230). Eight hex characters are a name, not a credential: a
// public caller who learned one during an open window must still get the normal hold. So the tag is
// honoured only when the same request proves it is internal, by EITHER of:
//   - the service-role key as its bearer, or
//   - x-qd-e2e-secret equal to app_secrets.cred_db_internal, the shared secret service-to-service
//     calls already present (demo_factory.internalCred).
// Without proof, the request runs exactly as if it had sent no header. The database applies the same
// rule on its side: fn_e2e_run_tag_current reads the header only for a service_role request.
type Run = { tag: string; secret: string | null };
export const E2E_RUN = new AsyncLocalStorage<Run | null>();
export const e2eRunTag = (): string | null => E2E_RUN.getStore()?.tag ?? null;

const TAG = /^[a-z0-9]{4,16}$/;
function same(a: string, b: string): boolean {
  if (!a || !b || a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

/**
 * The run this request may act as, or null. Pure apart from the lookup it is given, so the fence test
 * can prove it: a header with no proof, or with the wrong secret, is null.
 */
export async function resolveE2eRun(
  headers: Headers, serviceKey: string | null, internalSecret: () => Promise<string | null>,
): Promise<Run | null> {
  const tag = headers.get('x-qd-e2e-run') || '';
  if (!TAG.test(tag)) return null;
  const bearer = (headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
  // The service-role hop carries the internal secret on (stage-2 run 4, 13 Oct 2026): customer_api reaches
  // quote_compare with the service bearer, and quote_compare calls ai_gateway with NO bearer, so the tag reached
  // the gateway unproven and the comparison was refused fixture_no_spend - the Opus route was never asked.
  if (serviceKey && same(bearer, serviceKey)) return { tag, secret: await internalSecret().catch(() => null) };
  const presented = headers.get('x-qd-e2e-secret') || '';
  if (!presented) return null;
  const expected = await internalSecret().catch(() => null);
  return expected && same(presented, expected) ? { tag, secret: presented } : null;
}

// THE RUN'S OWN IDENTITY IS PROOF TOO (run 1be65ab2, 12 Oct 2026). The browser walk signs in as the run's own
// customer (qd-<tag>-...@example.invalid) and cannot send x-qd-e2e-secret, so every intake turn was refused
// fixture_no_spend although qd_run:<tag> had models_allowed open; the intake held on turn 1 and the terms step
// never reached "Send to suppliers". The tag is now ALSO honoured when the request's bearer is a user JWT that
// the auth server VERIFIES (verifyEmail) to belong to that run's own address, and only while
// fn_e2e_run_tag_open(tag) (window open, models_allowed, unexpired) says so. A header or a guessed tag still
// gets a public caller nothing: the tag comes from the verified email, never from the request.
const RUN_EMAIL = /^qd-([a-z0-9]{4,16})-[a-z0-9._+-]+@example\.invalid$/;
export const runTagOfEmail = (email: unknown): string | null => {
  const m = RUN_EMAIL.exec(String(email || '').toLowerCase());
  return m ? m[1] : null;
};
/** The unverified JWT payload email, used ONLY to skip the auth round-trip for everyone else. */
function claimedEmail(bearer: string): string | null {
  try {
    const p = bearer.split('.')[1]; if (!p) return null;
    return JSON.parse(atob(p.replace(/-/g, '+').replace(/_/g, '/')))?.email ?? null;
  } catch { return null; }
}
// AN ADDRESS ANYONE CAN TYPE IS NOT PROOF (review of #1361). The user must ALSO carry app_metadata.e2e_run equal
// to that tag: app_metadata is writable only by the service role, and the harness creates its users through the
// admin API with it (scripts/lib/demo_factory.mjs mkAuthUser). user_metadata is user-writable and is never read.
// Every lookup that throws or errs — the auth server included — fails closed.
type AuthUser = { email?: string | null; app_metadata?: Record<string, unknown> | null } | null;
export async function resolveE2eRunByIdentity(
  headers: Headers, verifyUser: (jwt: string) => Promise<AuthUser>,
  isOpen: (tag: string) => Promise<boolean>, internalSecret: () => Promise<string | null>,
): Promise<Run | null> {
  const bearer = (headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
  if (!bearer || !runTagOfEmail(claimedEmail(bearer))) return null;
  const user = await verifyUser(bearer).catch(() => null);     // the auth server's answer, not the payload's
  const tag = runTagOfEmail(user?.email);
  if (!tag || user?.app_metadata?.e2e_run !== tag) return null;
  if ((await isOpen(tag).catch(() => false)) !== true) return null;
  const secret = await internalSecret().catch(() => null);      // so the next hop can prove it too
  return secret ? { tag, secret } : null;
}

// THE SECRET GOES TO THIS PROJECT'S ORIGIN ONLY (security review of #1371). A prefix test against SUPABASE_URL (no
// trailing slash) let "https://<ref>.supabase.co.evil.com/" and "https://<ref>.supabase.co@evil.com/" through. The
// parsed origins must be equal; anything that does not parse is not ours.
export function sameOrigin(url: string, own: string): boolean {
  try { return !!own && new URL(url).origin === new URL(own).origin; } catch { return false; }
}

// try: a unit test importing this module without --allow-env must still load it.
let OWN = '';
try { OWN = (globalThis as { Deno?: { env: { get(k: string): string | undefined } } }).Deno?.env.get('SUPABASE_URL') || ''; } catch { /* no env permission: no forwarding */ }
if (OWN && !(globalThis as { __qdE2eFetch?: boolean }).__qdE2eFetch) {
  (globalThis as { __qdE2eFetch?: boolean }).__qdE2eFetch = true;
  const base = globalThis.fetch.bind(globalThis);
  globalThis.fetch = (input: RequestInfo | URL, init?: RequestInit) => {
    const run = E2E_RUN.getStore();
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
    if (!run || !sameOrigin(url, OWN)) return base(input, init);
    const headers = new Headers(init?.headers ?? (input instanceof Request ? input.headers : undefined));
    headers.set('x-qd-e2e-run', run.tag);
    // The next hop must be able to prove it too. A hop that reaches PostgREST already carries the
    // service-role bearer; a hop to another function carries the secret it was given.
    if (run.secret) headers.set('x-qd-e2e-secret', run.secret);
    return base(input, { ...init, headers });
  };
}
