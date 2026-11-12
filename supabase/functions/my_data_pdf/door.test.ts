// deno test --no-lock --node-modules-dir=none -A supabase/functions/my_data_pdf/door.test.ts
// Who can reach a person's data copy, and what is kept of it: the door answers only a signed-in session, reads the
// export AS that person (never with the service key), stores nothing, and answers a PDF the browser saves, not caches.
// Every network call is answered by a stub; nothing leaves the test.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { SUPPLIER_EXPORT } from './fixtures.ts';

Deno.env.set('SUPABASE_URL', 'https://stub.invalid');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'service-key');
// The suite runner (scripts/checks/run.mjs) grants only SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY and one more name.
let ANON = 'anon-key';
try { Deno.env.set('SUPABASE_ANON_KEY', ANON); } catch { ANON = ''; }

const FONTS = new URL('../pdf_native/fixtures/brand/', import.meta.url);
type Seen = { url: string; method: string; auth: string | null; apikey: string | null };
let seen: Seen[] = [];
let rpcAnswer: unknown = { ok: true, request_id: 'zz', export: SUPPLIER_EXPORT };
const realFetch = globalThis.fetch;
globalThis.fetch = (async (input: string | URL | Request, init: RequestInit = {}) => {
  const url = String(input instanceof Request ? input.url : input);
  const h = new Headers(init.headers ?? (input instanceof Request ? input.headers : undefined));
  seen.push({ url, method: String(init.method || 'GET'), auth: h.get('Authorization'), apikey: h.get('apikey') });
  if (url.includes('/auth/v1/user')) return new Response(JSON.stringify({ id: 'zz-user', email: 'zz-demo-supplier@example.invalid', aud: 'authenticated' }), { status: 200 });
  if (url.includes('/rest/v1/rpc/pdpl_request_me')) return new Response(JSON.stringify(rpcAnswer), { status: 200 });
  if (url.includes('/storage/v1/object/public/brand/')) {
    const name = url.split('/brand/')[1];
    try { return new Response(await Deno.readFile(new URL(name, FONTS))); } catch { return new Response('no', { status: 404 }); }
  }
  if (url.includes('/rest/v1/')) return new Response('[]', { status: 200, headers: { 'Content-Type': 'application/json' } });
  return new Response('unexpected ' + url, { status: 599 });
}) as typeof fetch;

const { handle, roleFor } = await import('./door.ts');
const b64 = (o: unknown) => btoa(JSON.stringify(o)).replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
const JWT = `${b64({ alg: 'HS256' })}.${b64({ sub: 'zz-user', email: 'zz-demo-supplier@example.invalid', exp: Math.floor(Date.now() / 1000) + 3600 })}.sig`;
const post = (auth: string | null, body: unknown = { lang: 'en', role: 'supplier' }) =>
  handle(new Request('https://stub.invalid/functions/v1/my_data_pdf', { method: 'POST', headers: { ...(auth ? { Authorization: auth } : {}), 'Content-Type': 'application/json' }, body: JSON.stringify(body) }));

Deno.test('a signed-in person gets his own copy as a PDF to save, read as himself, with nothing stored', async () => {
  seen = []; rpcAnswer = { ok: true, request_id: 'zz', export: SUPPLIER_EXPORT };
  const r = await post('Bearer ' + JWT);
  assertEquals(r.status, 200, await r.clone().text());
  assertEquals(r.headers.get('Content-Type'), 'application/pdf');
  assert(/^attachment; filename="QuotesDone-my-data-\d{4}-\d{2}-\d{2}\.pdf"$/.test(String(r.headers.get('Content-Disposition'))));
  assert(String(r.headers.get('Cache-Control')).includes('no-store'));
  const bytes = new Uint8Array(await r.arrayBuffer());
  assertEquals(new TextDecoder().decode(bytes.slice(0, 5)), '%PDF-');
  const rpc = seen.filter((s) => s.url.includes('pdpl_request_me'));
  assertEquals(rpc.length, 1);
  assertEquals(rpc[0].auth, 'Bearer ' + JWT, 'the export is read with the caller\'s own token');
  assertEquals(rpc[0].apikey, ANON, 'the public key, never the service key');
  assert(rpc[0].apikey !== 'service-key' && !String(rpc[0].auth).includes('service-key'));
  assert(!seen.some((s) => s.url.includes('/storage/v1/object/') && !s.url.includes('/object/public/brand/')), 'nothing is uploaded or signed');
  assert(!seen.some((s) => s.method !== 'GET' && !s.url.includes('pdpl_request_me') && !s.url.includes('/auth/v1/')), 'no write besides the export routine');
});

Deno.test('no session, no copy: the routine is never called', async () => {
  seen = [];
  for (const a of [null, 'Bearer not-a-jwt', 'Bearer anon-key']) {
    const r = await post(a);
    assertEquals(r.status, 401, String(a));
  }
  assert(!seen.some((s) => s.url.includes('pdpl_request_me')));
});

Deno.test('an unverified e-mail is refused in words the portal maps, never a PDF', async () => {
  rpcAnswer = { ok: false, code: 'email_not_verified' };
  const r = await post('Bearer ' + JWT);
  assertEquals(r.status, 403);
  assertEquals((await r.json()).code, 'email_not_verified');
  rpcAnswer = { ok: true, request_id: 'zz', export: SUPPLIER_EXPORT };
});

Deno.test('the portal names the role; the export must agree', () => {
  assertEquals(roleFor('customer', { customer_accounts: [], supplier_records: [{}] }), 'supplier');
  assertEquals(roleFor('supplier', { customer_accounts: [{}], supplier_records: [] }), 'customer');
  assertEquals(roleFor('supplier', { customer_accounts: [{}], supplier_records: [{}] }), 'supplier');
});

addEventListener('unload', () => { globalThis.fetch = realFetch; });
