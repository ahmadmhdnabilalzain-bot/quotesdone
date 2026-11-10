// inbound_email's shared-secret gate (security pass 9 Nov 2026, row 40 / L5): a wrong secret is refused, a
// missing one is refused, either configured secret is accepted. The provider sends the secret only: no
// signature and no timestamp header exists on this webhook, so there is no replay window to test.
// Drives the real handler over a stubbed PostgREST. Nothing below is real: ZZ DEMO, example.invalid.
import { assertEquals } from 'jsr:@std/assert@1';

const WH = 'zz-demo-webhook-secret', IB = 'zz-demo-internal-secret';
Deno.env.set('SUPABASE_URL', 'http://stub.invalid');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-key');
globalThis.fetch = ((input: Request | URL | string, init?: RequestInit) => {
  const u = new URL(new Request(input, init).url);
  const rows = u.pathname.endsWith('/app_secrets')
    ? [{ key: 'inbound_webhook_secret', value: WH }, { key: 'cred_fn_inbound_email', value: IB }] : [];
  return Promise.resolve(new Response(JSON.stringify(rows), { status: 200, headers: { 'Content-Type': 'application/json' } }));
}) as typeof fetch;

let handler!: (req: Request) => Promise<Response>;
// deno-lint-ignore no-explicit-any
(Deno as any).serve = (h: (req: Request) => Promise<Response>) => { handler = h; return {}; };
await import('./index.ts');

const call = (headers: Record<string, string>, body: unknown = {}) =>
  handler(new Request('https://x.invalid/inbound_email', { method: 'POST', headers: { 'content-type': 'application/json', ...headers }, body: JSON.stringify(body) }));

Deno.test('wrong secret is refused', async () => {
  assertEquals((await call({ 'x-webhook-secret': WH + 'x' })).status, 403);
  assertEquals((await call({ 'x-webhook-secret': 'short' })).status, 403);
  assertEquals((await call({}, { __secret: 'nope' })).status, 403);
});
Deno.test('no secret is refused', async () => {
  assertEquals((await call({})).status, 403);
  assertEquals((await call({ 'x-webhook-secret': '' })).status, 403);
});
Deno.test('either configured secret is accepted (gets past auth to the missing-from check)', async () => {
  for (const s of [WH, IB]) {
    const r = await call({ 'x-webhook-secret': s }, {});
    assertEquals(r.status, 400);
    assertEquals((await r.json()).error, 'missing from');
  }
  const viaBody = await call({}, { __secret: WH });
  assertEquals(viaBody.status, 400);
});
