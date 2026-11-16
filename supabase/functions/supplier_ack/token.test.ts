// supplier_ack's one-click link (security checklist audit 10 Nov 2026): a wrong token, a token of another length and a
// malformed transaction id are refused; the right token is accepted; the token is compared in constant time. Drives
// the real handler over a stubbed PostgREST. Nothing below is real: ZZ DEMO ids, no write is made (the stubbed row is
// already acknowledged, so the handler neither updates it nor requests a delivery).
import { assert, assertEquals } from 'jsr:@std/assert@1';

const TX = '0b0b0b0b-0000-4000-8000-00000000a001';
const TOKEN = '0b0b0b0b-0000-4000-8000-00000000b001';
// a sale not yet acknowledged (16 Nov 2026): its first click must go to fn_supplier_ack_record, which tells the customer
const TX2 = '0b0b0b0b-0000-4000-8000-00000000a002';
const rpcs: { fn: string; body: unknown }[] = [];
Deno.env.set('SUPABASE_URL', 'http://stub.invalid');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-key');
const writes: string[] = [];
globalThis.fetch = ((input: Request | URL | string, init?: RequestInit) => {
  const r = new Request(input, init);
  if (r.method !== 'GET' && r.method !== 'HEAD') writes.push(`${r.method} ${new URL(r.url).pathname}`);
  const u = new URL(r.url);
  if (u.pathname.includes('/rpc/')) {
    return r.text().then((b) => { rpcs.push({ fn: u.pathname.split('/rpc/')[1], body: JSON.parse(b || '{}') });
      return new Response(JSON.stringify({ recorded: true }), { status: 200, headers: { 'Content-Type': 'application/json' } }); });
  }
  const row = { id: TX, supplier_ack_at: '2026-11-01T00:00:00Z', ack_token: TOKEN, inquiry_id: '0b0b0b0b-0000-4000-8000-00000000c001' };
  const row2 = { id: TX2, supplier_ack_at: null, ack_token: TOKEN, inquiry_id: '0b0b0b0b-0000-4000-8000-00000000c002' };
  const rows = u.pathname.endsWith('/transactions') && u.searchParams.get('id') === `eq.${TX}` ? [row]
    : u.pathname.endsWith('/transactions') && u.searchParams.get('id') === `eq.${TX2}` ? [row2] : [];
  const one = (r.headers.get('accept') || '').includes('vnd.pgrst.object');
  return Promise.resolve(new Response(JSON.stringify(one ? (rows[0] ?? null) : rows), { status: 200, headers: { 'Content-Type': 'application/json' } }));
}) as typeof fetch;

let handler!: (req: Request) => Promise<Response>;
// deno-lint-ignore no-explicit-any
(Deno as any).serve = (h: (req: Request) => Promise<Response>) => { handler = h; return {}; };
await import('./index.ts');
const call = (tx: string, token: string) =>
  handler(new Request(`https://x.invalid/supplier_ack?tx=${encodeURIComponent(tx)}&token=${encodeURIComponent(token)}`));

Deno.test('the right token is accepted', async () => {
  const r = await call(TX, TOKEN);
  assertEquals(r.status, 200);
  assert((await r.text()).includes('Thank you'));
});
Deno.test('a wrong token of the same shape is refused', async () => {
  assertEquals((await call(TX, TOKEN.slice(0, -1) + '2')).status, 404);
  assertEquals((await call(TX, TOKEN.toUpperCase().replace('B001', 'B002'))).status, 404);
});
Deno.test('a malformed token or transaction id is refused before any read', async () => {
  assertEquals((await call(TX, 'short')).status, 400);
  assertEquals((await call('not-a-uuid', TOKEN)).status, 400);
  assertEquals((await call('', TOKEN)).status, 400);
});
Deno.test('nothing was written by any of these calls', () => assertEquals(writes.filter((w) => w.includes('/transactions')), []));
Deno.test('the token is never compared with a plain inequality again', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  assert(/await sameSecret\(token, String\(t\.ack_token \|\| ''\)\)/.test(src), 'supplier_ack must compare the token with sameSecret');
  assert(!/ack_token\) !== token/.test(src), 'a plain !== on the token is a timing oracle');
});

// THE CLICK REACHES THE CUSTOMER, NOT ROLE ADMIN (16 Nov 2026, AFTER_REVEAL; holes CUSTOMER.md items 1 and 12). A first click is one
// call to fn_supplier_ack_record (the write and the customer's "has <supplier> contacted you?" in one transaction); the handler never
// writes the table itself and never queues a delivery to role admin. Fails on v3, which PATCHed transactions and told 'admin'.
Deno.test('a first click goes to fn_supplier_ack_record, never straight to the table and never to role admin', async () => {
  const before = writes.length;
  const r = await call(TX2, TOKEN);
  assertEquals(r.status, 200);
  assertEquals(rpcs.map((x) => x.fn), ['fn_supplier_ack_record']);
  assertEquals((rpcs[0].body as Record<string, unknown>).p_transaction, TX2);
  assertEquals(writes.slice(before).filter((w) => !w.includes('/rpc/fn_supplier_ack_record')), []);
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  assert(!/to_role\s*:\s*'admin'/.test(src), 'the acknowledgement is not addressed to role admin');
});
