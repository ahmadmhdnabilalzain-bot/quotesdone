// The retired shared inbound_secret no longer opens resend_inbound or resend_webhook (security audit 17 Nov 2026,
// finding 6). resend_inbound's own authenticate step is driven over a stubbed PostgREST with a correctly
// Svix-signed delivery: carrying ?s=<inbound_secret> it is refused at the token, carrying resend_inbound_token it
// passes. resend_webhook serves at import, so its door is read from source. No value below is real.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';

const SECRET_RAW = new Uint8Array(32).map((_, i) => i + 7);
const SECRETS: Record<string, string> = {
  resend_inbound_token: 'zz-demo-inbound-token',
  inbound_secret: 'zz-demo-retired-shared-secret',
  resend_inbound_signing_secret: 'whsec_' + btoa(String.fromCharCode(...SECRET_RAW)),
};

Deno.env.set('SUPABASE_URL', 'http://stub.invalid');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-key');
const runs: Record<string, unknown>[] = [];
globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
  const req = new Request(input, init);
  const u = new URL(req.url);
  const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
  if (u.pathname === '/rest/v1/agent_runs') { runs.push(JSON.parse(await req.text())); return json([{ id: 1 }], 201); }
  if (u.pathname === '/rest/v1/app_secrets') {
    const v = SECRETS[(u.searchParams.get('key') || '').replace(/^eq\./, '')];
    return v === undefined ? json({ message: 'none' }, 406) : json({ value: v });
  }
  return json({ id: 1 });
}) as typeof fetch;

const { authenticate } = await import('./steps/authenticate.ts');

async function signed(token: string): Promise<Request> {
  const raw = JSON.stringify({ type: 'email.received', data: { email_id: 'zz-demo-0001', from: 'zz@example.invalid', to: ['docs@mail.quotesdone.com'], subject: 'ZZ DEMO', text: '' } });
  const id = 'msg_zz_demo', ts = String(Math.floor(Date.now() / 1000));
  const key = await crypto.subtle.importKey('raw', SECRET_RAW, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(id + '.' + ts + '.' + raw)))));
  return new Request('http://stub.invalid/functions/v1/resend_inbound?s=' + encodeURIComponent(token),
    { method: 'POST', body: raw, headers: { 'svix-id': id, 'svix-timestamp': ts, 'svix-signature': 'v1,' + sig } });
}

Deno.test({ name: 'a signed delivery carrying the retired shared secret is refused at the token', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  runs.length = 0;
  const out = await authenticate({ req: await signed(SECRETS.inbound_secret) });
  assert(out instanceof Response, 'the retired shared secret still authorises resend_inbound');
  assertEquals(out.status, 403);
  assertEquals((runs[0]?.counts as Record<string, unknown>)?.stage, 'query_token');
}});

Deno.test({ name: 'the same delivery carrying resend_inbound_token passes to the reader', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  const out = await authenticate({ req: await signed(SECRETS.resend_inbound_token) });
  assert(!(out instanceof Response), 'resend_inbound_token no longer authorises: ' + (out instanceof Response ? out.status : ''));
  assertMatch(out.raw, /zz-demo-0001/);
}});

Deno.test('neither Resend door reads inbound_secret', async () => {
  for (const f of ['supabase/functions/resend_inbound/steps/authenticate.ts', 'supabase/functions/resend_webhook/index.ts']) {
    const src = await Deno.readTextFile(f);
    assertEquals(/sec\('inbound_secret'\)/.test(src), false, f + ' reads the retired shared secret again');
  }
});
