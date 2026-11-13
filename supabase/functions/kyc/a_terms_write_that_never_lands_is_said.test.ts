// kyc's HANDLER, end to end in memory: an acceptance write that is cancelled three times (13 Nov 2026, 08:47: a rehearsal's
// lock, the 8 s statement_timeout) answers 503 terms_not_recorded, never ok, and asks compliance_archive for NO certificate
// (there is no acceptance to certify). Review of 13 Nov, the test that was missing: acceptance_write.test.ts read the source.
//
// Incapable of reaching anything: Deno.serve, fetch, the environment and EdgeRuntime are stubbed before kyc/index.ts is imported;
// every request it makes is answered here from a table, and the party is a ZZ DEMO address on @example.invalid.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';

type Call = { method: string; url: string; body: string };
const calls: Call[] = [];
const waited: Promise<unknown>[] = [];
const EMAIL = 'zz-demo-terms@example.invalid';
const CUSTOMER = { id: '00000000-0000-4000-8000-000000000001', full_name: 'ZZ DEMO Terms', phone: null, date_of_birth: '1990-01-01', email_verified: true,
  phone_verified: false, tos_accepted_at: '2026-01-01T00:00:00Z', tos_version: 'v1', signed_terms_url: null };
const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { 'content-type': 'application/json' } });

function answer(method: string, url: URL, accept: string): Response {
  const p = url.pathname; const one = /vnd\.pgrst\.object/.test(accept);
  const rows = (r: unknown[]) => (one ? (r.length ? json(r[0]) : json({ code: 'PGRST116', message: 'no rows' }, 406)) : json(r));
  if (p === '/auth/v1/user') return json({ id: 'u-zz', aud: 'authenticated', email: EMAIL, app_metadata: {}, user_metadata: {}, created_at: '2026-01-01T00:00:00Z' });
  if (p === '/functions/v1/compliance_archive') return json({ ok: true, signed_url: 'https://example.invalid/cert.pdf' });
  if (p === '/rest/v1/customers' && method === 'PATCH') return json({ code: '57014', message: 'canceling statement due to statement timeout' }, 500);
  if (p === '/rest/v1/customers' && method === 'GET') return rows(url.searchParams.get('select')?.startsWith('whatsapp') ? [{ whatsapp_opt: 'same' }] : [CUSTOMER]);
  if (p === '/rest/v1/app_secrets') return rows(url.searchParams.get('key') === 'eq.customer_terms_version' ? [{ value: 'v3' }] : []);
  if (method === 'GET') return rows([]);
  return json([], 201);
}

Deno.test('kyc accept_terms: a write cancelled three times answers 503 terms_not_recorded and asks for no certificate', async () => {
  const env: Record<string, string> = { SUPABASE_URL: 'http://127.0.0.1:9', SUPABASE_SERVICE_ROLE_KEY: 'not-a-key' };
  (Deno.env as { get: (k: string) => string | undefined }).get = (k: string) => env[k];
  const box: { handler?: (req: Request) => Promise<Response> } = {};
  (Deno as unknown as { serve: unknown }).serve = (h: (req: Request) => Promise<Response>) => { box.handler = h; return { finished: Promise.resolve(), shutdown: () => Promise.resolve() }; };
  (globalThis as { EdgeRuntime?: unknown }).EdgeRuntime = { waitUntil: (p: Promise<unknown>) => { waited.push(p); } };
  globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
    const req = input instanceof Request ? input : new Request(String(input), init);
    const url = new URL(req.url);
    if (url.hostname !== '127.0.0.1') throw new Error('the test reached ' + url.host);
    calls.push({ method: req.method, url: url.pathname + url.search, body: req.method === 'GET' ? '' : await req.clone().text() });
    return answer(req.method, url, req.headers.get('accept') ?? '');
  }) as typeof fetch;
  const quiet = console.error; console.error = () => {};
  try {
    await import('./index.ts');
    const handler = box.handler;
    assert(handler, 'kyc registered its handler');
    const t0 = Date.now();
    const res = await handler(new Request('http://127.0.0.1:9/functions/v1/kyc', { method: 'POST', headers: { Authorization: 'Bearer zz', 'content-type': 'application/json', origin: 'https://quotesdone.com' }, body: JSON.stringify({ action: 'accept_terms' }) }));
    const ms = Date.now() - t0;
    const body = await res.json();
    assertEquals(res.status, 503);
    assertEquals(body.code, 'terms_not_recorded');
    assertMatch(body.message, /not complete yet/);
    assert(!body.ok, 'never ok');
    const writes = calls.filter((c) => c.method === 'PATCH' && c.url.startsWith('/rest/v1/customers'));
    assertEquals(writes.length, 3, 'three tries of the same write');
    assert(writes.every((w) => w.body === writes[0].body), 'the same values each time, so a retry cannot record a second acceptance');
    assertEquals(calls.filter((c) => c.url.startsWith('/functions/v1/compliance_archive')).length, 0, 'no certificate is asked for an acceptance that is not on record');
    assert(ms < 18_000, `answered within the page's budget: ${ms} ms`);
    // the it_engineer finding is filed in the background, after the answer (review item 8)
    await Promise.all(waited);
    const finding = calls.find((c) => c.url.startsWith('/rest/v1/rpc/fn_it_engineer_finding_upsert'));
    assert(finding, 'the IT seat is told');
    assertMatch(finding!.body, /terms_not_recorded:customer/);
    assert(!finding!.body.includes(EMAIL), 'the finding carries no e-mail address');
  } finally { console.error = quiet; }
});
