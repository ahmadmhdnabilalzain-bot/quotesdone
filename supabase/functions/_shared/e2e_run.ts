// _shared/e2e_run.ts — the stage-2 sandbox run tag, carried for the life of one request (ledger 1119).
// No jsr: or npm: import, so node tests that load llm_hold.ts can load it too.
import { AsyncLocalStorage } from 'node:async_hooks';

// THE SANDBOX RUN TAG TRAVELS WITH THE REQUEST (ledger 1119, 6 Oct 2026). The stage-2 harness sends
// x-qd-e2e-run: <tag> on its calls. Every function is wrapped in observe(), so the tag is held here for
// the life of that request, and every fetch the function makes back to THIS project (ai_gateway, another
// function, PostgREST through supabase-js) carries it on. trg_ai_cost_log_e2e_run_tag reads it from
// request.headers and stamps the cost row, and only for a run with an open rehearsal_window. With no
// header, nothing is added to any request.
export const E2E_RUN = new AsyncLocalStorage<string | null>();
export const e2eRunTag = (): string | null => E2E_RUN.getStore() ?? null;
// try: a unit test importing this module without --allow-env must still load it.
let OWN = '';
try { OWN = (globalThis as { Deno?: { env: { get(k: string): string | undefined } } }).Deno?.env.get('SUPABASE_URL') || ''; } catch { /* no env permission: no forwarding */ }
if (OWN && !(globalThis as { __qdE2eFetch?: boolean }).__qdE2eFetch) {
  (globalThis as { __qdE2eFetch?: boolean }).__qdE2eFetch = true;
  const base = globalThis.fetch.bind(globalThis);
  globalThis.fetch = (input: RequestInfo | URL, init?: RequestInit) => {
    const tag = E2E_RUN.getStore();
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
    if (!tag || !url.startsWith(OWN)) return base(input, init);
    const headers = new Headers(init?.headers ?? (input instanceof Request ? input.headers : undefined));
    headers.set('x-qd-e2e-run', tag);
    return base(input, { ...init, headers });
  };
}
