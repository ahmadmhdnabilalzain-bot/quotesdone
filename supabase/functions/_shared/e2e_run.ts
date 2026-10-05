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
  if (serviceKey && same(bearer, serviceKey)) return { tag, secret: null };
  const presented = headers.get('x-qd-e2e-secret') || '';
  if (!presented) return null;
  const expected = await internalSecret().catch(() => null);
  return expected && same(presented, expected) ? { tag, secret: presented } : null;
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
    if (!run || !url.startsWith(OWN)) return base(input, init);
    const headers = new Headers(init?.headers ?? (input instanceof Request ? input.headers : undefined));
    headers.set('x-qd-e2e-run', run.tag);
    // The next hop must be able to prove it too. A hop that reaches PostgREST already carries the
    // service-role bearer; a hop to another function carries the secret it was given.
    if (run.secret) headers.set('x-qd-e2e-secret', run.secret);
    return base(input, { ...init, headers });
  };
}
