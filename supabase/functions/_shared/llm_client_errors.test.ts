// llm.ts keeps WHY a model call failed, and asks again once when no worker served it (it_engineer, 27 Oct 2026).
// Measured on production at 20:30Z: five held rows failed with the synthesise step reading only 'client_error' (the
// thrown message was dropped), beside an ai_gateway 503 with no execution_id. The fetch is replaced here; no network.
import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert';

Deno.env.set('SUPABASE_URL', 'https://zz-demo.example.invalid');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-key');
const { makeLlmRich, noWorkerServed } = await import('./llm.ts');

type Hop = (url: string, init?: RequestInit) => Response | Promise<Response>;
async function withFetch<T>(gateway: Hop, run: () => Promise<T>): Promise<{ out: T; gatewayCalls: number }> {
  const real = globalThis.fetch; let gatewayCalls = 0;
  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
    const url = String(input instanceof Request ? input.url : input);
    if (url.includes('/functions/v1/ai_gateway')) { gatewayCalls++; return Promise.resolve().then(() => gateway(url, init)); }
    // app_secrets reads and agent_runs writes (supabase-js): a credential row, and an accepted insert
    if (url.includes('/rest/v1/app_secrets')) return Promise.resolve(new Response(JSON.stringify({ value: 'zz-demo-cred' }), { status: 200, headers: { 'Content-Type': 'application/json' } }));
    return Promise.resolve(new Response('[]', { status: 201, headers: { 'Content-Type': 'application/json' } }));
  }) as typeof fetch;
  try { return { out: await run(), gatewayCalls }; } finally { globalThis.fetch = real; }
}
const call = () => makeLlmRich([], { fn: 'resilience_ping', timeoutMs: 5000 })('sys', 'ZZ DEMO question');

Deno.test('a fetch that throws keeps its message in the error, not a bare client_error', async () => {
  const { out } = await withFetch(() => { throw new TypeError('error sending request for url: connection reset by peer'); }, call);
  assertEquals(out.content, null);
  assertStringIncludes(String(out.error), 'client_error: TypeError: error sending request for url: connection reset by peer');
});

Deno.test('the kept message never carries the credential', async () => {
  const { out } = await withFetch(() => { throw new Error('refused secret=zz-demo-cred-0123456789abcdef0123456789abcdef'); }, call);
  assert(!String(out.error).includes('0123456789abcdef0123'), String(out.error));
  assertStringIncludes(String(out.error), 'client_error');
});

Deno.test('a 503 no worker served is asked once more, and the second answer is used', async () => {
  let n = 0;
  const { out, gatewayCalls } = await withFetch(() => (++n === 1
    ? new Response(JSON.stringify({ code: 'WORKER_LIMIT', message: 'no worker' }), { status: 503, headers: { 'Content-Type': 'application/json' } })
    : new Response(JSON.stringify({ ok: true, content: 'ZZ DEMO answer', model: 'm' }), { status: 200, headers: { 'Content-Type': 'application/json' } })), call);
  assertEquals(gatewayCalls, 2);
  assertEquals(out.content, 'ZZ DEMO answer');
});

Deno.test('a 503 the gateway wrote itself (a hold, an open circuit) is never retried', async () => {
  const { out, gatewayCalls } = await withFetch(() => new Response(JSON.stringify({ ok: false, used_llm: false, outcome: 'circuit_open', error: 'every model route for this task class is open-circuit' }), { status: 503, headers: { 'Content-Type': 'application/json' } }), call);
  assertEquals(gatewayCalls, 1);
  assertEquals(out.content, null);
});

Deno.test('only a 503 without the gateway envelope, or a relay 5xx no runtime served, counts as no worker', () => {
  assert(noWorkerServed(503, null));
  assert(noWorkerServed(503, { code: 'WORKER_LIMIT' }));
  assert(!noWorkerServed(503, { ok: false, outcome: 'fixture_no_spend' }));
  // 2 Nov 2026: Cloudflare's own 502 page carries no x-served-by; the gateway's own 502 does.
  assert(noWorkerServed(502, null, null));
  assert(!noWorkerServed(502, { ok: false, error: 'provider' }, 'supabase-edge-runtime'));
  assert(!noWorkerServed(546, null, 'supabase-edge-runtime'));
  assert(!noWorkerServed(200, null));
});

Deno.test('a Cloudflare 502 with no worker behind it is asked once more (2 Nov 2026: 18 such 502s on ai_gateway)', async () => {
  let n = 0;
  const { out, gatewayCalls } = await withFetch(() => (++n === 1
    ? new Response('<html>502 Bad Gateway</html>', { status: 502, headers: { 'Content-Type': 'text/html', server: 'cloudflare' } })
    : new Response(JSON.stringify({ ok: true, content: 'ZZ DEMO answer', model: 'm' }), { status: 200, headers: { 'Content-Type': 'application/json' } })), call);
  assertEquals(gatewayCalls, 2);
  assertEquals(out.content, 'ZZ DEMO answer');
});

Deno.test('a 502 the gateway itself wrote is never retried', async () => {
  const { gatewayCalls } = await withFetch(() => new Response(JSON.stringify({ ok: false, error: 'provider failed' }), { status: 502, headers: { 'Content-Type': 'application/json', 'x-served-by': 'supabase-edge-runtime' } }), call);
  assertEquals(gatewayCalls, 1);
});
