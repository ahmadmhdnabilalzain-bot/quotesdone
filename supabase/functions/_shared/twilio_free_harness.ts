// TEST-ONLY: load an edge function's handler with no network, no env and no database, and record
// every request it makes. Used by <fn>/fixture_number.test.ts to prove a fixture number makes zero
// requests to twilio.com, and — the positive control — that a real-looking number does reach the
// (stubbed) Twilio, so a "zero" can never come from a harness that sees nothing.
//
// Deno tests run with NO permissions (scripts/checks/run.mjs), so Deno.env, Deno.serve and fetch are
// replaced before the function module is imported. supabase-js captures fetch when the module's
// client is created, so fetch is one installed dispatcher that reads the current stub at call time.

export type Stub = {
  rows?: Record<string, unknown[]>;      // GET /rest/v1/<table>
  rpc?: Record<string, unknown>;          // POST /rest/v1/rpc/<fn>; anything unlisted answers null
  secrets?: Record<string, string>;       // app_secrets by key; anything unlisted gets a long stub value
  user?: { id: string; email: string };   // GET /auth/v1/user
  // Seen first for every db.invalid request; return a Response to answer it, undefined to fall through.
  handle?: (req: Request, u: URL) => Response | Promise<Response | undefined> | undefined;
};
export type Call = { method: string; url: string; body: string };

let current: Stub = {};
const calls: Call[] = [];
const handlers = new Map<string, (req: Request) => Promise<Response>>();
let installed = false;
const J = (o: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json', ...headers } });

function install() {
  if (installed) return;
  installed = true;
  const env: Record<string, string> = { SUPABASE_URL: 'https://db.invalid', SUPABASE_SERVICE_ROLE_KEY: 'stub-service-role', SUPABASE_ANON_KEY: 'stub-anon' };
  (Deno.env as unknown as { get: (k: string) => string | undefined }).get = (k) => env[k];
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const req = input instanceof Request ? input : new Request(String(input), init);
    const u = new URL(req.url);
    calls.push({ method: req.method, url: req.url, body: req.method === 'GET' || req.method === 'HEAD' ? '' : await req.clone().text() });
    if (u.hostname === 'twilio.com' || u.hostname.endsWith('.twilio.com')) return J({ sid: 'SMstub', status: 'pending' }, 201);
    if (u.hostname !== 'db.invalid') return J({});
    const own = await current.handle?.(req, u); if (own) return own;
    if (u.pathname === '/auth/v1/user') return J({ aud: 'authenticated', role: 'authenticated', ...(current.user ?? { id: 'u-stub', email: 'qd-stub@example.invalid' }) });
    const rpc = u.pathname.match(/^\/rest\/v1\/rpc\/(.+)$/);
    if (rpc) return J(current.rpc?.[rpc[1]] ?? null);
    const table = u.pathname.match(/^\/rest\/v1\/([^/]+)$/)?.[1] ?? '';
    if (req.method === 'HEAD') return new Response(null, { status: 200, headers: { 'content-range': '*/0' } });
    if (req.method !== 'GET') return J([], 201);
    let rows: unknown[] = current.rows?.[table] ?? [];
    if (table === 'app_secrets') {
      const key = (u.searchParams.get('key') || '').replace(/^eq\./, '');
      rows = [{ value: current.secrets?.[key] ?? 'stub-secret-value-0123456789abcdef' }];
    }
    const wantsObject = (req.headers.get('accept') || '').includes('vnd.pgrst.object');
    return wantsObject ? J(rows[0] ?? {}) : J(rows);
  }) as typeof fetch;
}

/**
 * Import a function's index.ts once and return the handler it passed to Deno.serve. The caller
 * passes `() => import('./index.ts')`: a LITERAL specifier is part of the module graph and needs no
 * permission, where a computed one needs --allow-read, which the suite deliberately never grants.
 */
export async function loadFunction(name: string, importer: () => Promise<unknown>): Promise<(req: Request) => Promise<Response>> {
  install();
  const known = handlers.get(name);
  if (known) return known;
  let h: ((req: Request) => Promise<Response>) | undefined;
  (Deno as unknown as { serve: unknown }).serve = (a: unknown, b?: unknown) => {
    h = (typeof a === 'function' ? a : b) as typeof h;
    return { finished: Promise.resolve(), shutdown: () => Promise.resolve(), ref() {}, unref() {} };
  };
  await importer();
  if (!h) throw new Error(name + ' did not call Deno.serve');
  handlers.set(name, h);
  return h;
}

/** Call the handler with a JSON body under `stub`; return the answer and every request it made. */
export async function invoke(handler: (req: Request) => Promise<Response>, stub: Stub, body: unknown, headers: Record<string, string> = {}) {
  current = stub;
  calls.length = 0;
  const res = await handler(new Request('https://fn.invalid/', {
    method: 'POST', headers: { 'content-type': 'application/json', authorization: 'Bearer stub-jwt', ...headers }, body: JSON.stringify(body),
  }));
  const json = await res.json().catch(() => null);
  await new Promise((r) => setTimeout(r, 30));   // let observe()'s background agent_runs write land on the stub
  const made = [...calls];
  return {
    status: res.status, json, calls: made,
    twilio: made.filter((c) => { const h = new URL(c.url).hostname; return h === 'twilio.com' || h.endsWith('.twilio.com'); }),
  };
}

export const FIXTURE = '+971500000042';      // the number texted on 14 Sep
export const REAL_LOOKING = '+971501234567'; // outside the reserved block: must reach (stubbed) Twilio
