// A look-alike address is not the customer (security audit 17 Nov 2026, finding 1; it_engineer). Drives sales_engineer's
// REAL handler over a stubbed auth server and a stubbed PostgREST that reads `eq` and `ilike` as Postgres does (`_` any
// one character, `%` any run, `*` rewritten to `%` by PostgREST). On origin/main 09e43394c a session for
// `zz_demo_victim@example.invalid` (a supplier-portal login, no customer row of its own) was resolved by `.ilike` to the
// customer `zz.demo.victim@example.invalid` and handed his conversation record. Nothing here reaches anything real: the
// project host is `stub.invalid`, every other host answers 503, and every identity is a ZZ DEMO address.
//   deno test --no-lock --node-modules-dir=none --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY --allow-read=. \
//     supabase/functions/sales_engineer/a_look_alike_address_is_not_the_customer.test.ts
import { assertEquals } from 'jsr:@std/assert@1';

const VICTIM_ROW = { id: '0b0b0b0b-0000-4000-8000-0000000c0201', email: 'zz.demo.victim@example.invalid' };
const USERS = [
  { id: '0b0b0b0b-0000-4000-8000-0000000c0301', email: 'zz_demo_victim@example.invalid' },   // `_` for `.`
  { id: '0b0b0b0b-0000-4000-8000-0000000c0302', email: '%@example.invalid' },
  { id: '0b0b0b0b-0000-4000-8000-0000000c0303', email: 'zz*victim@example.invalid' },        // PostgREST: `*` is `%`
  { id: '0b0b0b0b-0000-4000-8000-0000000c0304', email: 'ZZ.Demo.Victim@Example.Invalid' },   // the victim, any case
];
const CUSTOMERS = [VICTIM_ROW, { id: '0b0b0b0b-0000-4000-8000-0000000c0202', email: 'zz-demo-bystander@example.invalid' }];

function like(pattern: string, value: string): boolean {
  const p = pattern.replace(/\*/g, '%');
  let re = '';
  for (let i = 0; i < p.length; i++) {
    const c = p[i];
    if (c === '\\' && i + 1 < p.length) { re += p[++i].replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); continue; }
    re += c === '%' ? '[\\s\\S]*' : c === '_' ? '[\\s\\S]' : c.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&');
  }
  return new RegExp('^' + re + '$', 'i').test(value);
}

const rpcCalls: { fn: string; args: Record<string, unknown> }[] = [];
const b64u = (o: unknown) => btoa(JSON.stringify(o)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const token = (id: string) => {
  const now = Math.floor(Date.now() / 1000);
  return `${b64u({ alg: 'ES256', typ: 'JWT' })}.${b64u({ sub: id, aal: 'aal1', role: 'authenticated', exp: now + 3600, iat: now })}.zz-demo-signature`;
};
const subOf = (auth: string) => { try { return JSON.parse(atob((auth.replace(/^Bearer\s+/i, '').split('.')[1] || '').replace(/-/g, '+').replace(/_/g, '/'))).sub; } catch (_e) { return null; } };

async function loadHandler() {
  Deno.env.set('SUPABASE_URL', 'http://stub.invalid');
  Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-key');
  globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
    const r = new Request(input, init);
    const u = new URL(r.url);
    if (u.host !== 'stub.invalid') return new Response('{"error":"stubbed"}', { status: 503 });
    const json = (v: unknown, s = 200) => new Response(JSON.stringify(v), { status: s, headers: { 'Content-Type': 'application/json' } });
    if (u.pathname === '/auth/v1/user') {
      const user = USERS.find((x) => x.id === subOf(r.headers.get('Authorization') || ''));
      return user ? json({ ...user, aud: 'authenticated', factors: [] }) : json({ code: 403, msg: 'invalid JWT' }, 403);
    }
    if (u.pathname.startsWith('/rest/v1/rpc/')) {
      const fn = u.pathname.slice('/rest/v1/rpc/'.length);
      const args = await r.json().catch(() => ({}));
      rpcCalls.push({ fn, args });
      return json(fn === 'fn_conversation_record' ? { ok: true, contact: args.p_contact, messages: [] } : null);
    }
    const one = (r.headers.get('accept') || '').includes('vnd.pgrst.object');
    const rows = (v: unknown[]) => (one && v.length > 1 ? json({ code: 'PGRST116' }, 406) : json(one ? (v[0] ?? null) : v));
    if (u.pathname === '/rest/v1/app_secrets') return rows(u.searchParams.get('key') === 'eq.admin_emails' ? [{ value: 'zz-demo-admin@example.invalid' }] : []);
    if (u.pathname === '/rest/v1/customers') {
      const f = u.searchParams.get('email') || '';
      const [op, ...rest] = f.split('.');
      const v = rest.join('.');
      const hit = CUSTOMERS.filter((c) => op === 'eq' ? c.email === v : op === 'ilike' ? like(v, c.email) : false);
      return rows(hit);
    }
    return rows([]);
  }) as typeof fetch;
  let handler!: (req: Request) => Promise<Response>;
  // deno-lint-ignore no-explicit-any
  (Deno as any).serve = (a: unknown, b?: unknown) => { handler = (typeof a === 'function' ? a : b) as typeof handler; return {}; };
  await import(new URL('./index.ts', import.meta.url).href);
  return async (userId: string) => {
    rpcCalls.length = 0;
    const res = await handler(new Request('https://x.invalid/fn', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Origin: 'https://quotesdone.com', Authorization: 'Bearer ' + token(userId) },
      body: JSON.stringify({ action: 'conversations' }),
    }));
    const text = await res.text();
    return { status: res.status, text, record: rpcCalls.find((c) => c.fn === 'fn_conversation_record') };
  };
}

const ready = loadHandler();
const san = { sanitizeOps: false, sanitizeResources: false };

for (const u of USERS.slice(0, 3)) {
  Deno.test({ name: `a session for ${u.email} is nobody's customer: 401 and no conversation record is read`, ...san, fn: async () => {
    const call = await ready;
    const r = await call(u.id);
    assertEquals(r.record, undefined, `the record was read for ${JSON.stringify(r.record?.args)}`);
    assertEquals(r.text.includes(VICTIM_ROW.id), false);
    assertEquals(r.status, 401);
  } });
}

Deno.test({ name: 'the customer himself, whatever the case of his address, still reads his own record', ...san, fn: async () => {
  const call = await ready;
  const r = await call(USERS[3].id);
  assertEquals(r.status, 200, r.text.slice(0, 300));
  assertEquals(r.record?.args.p_contact, 'customer:' + VICTIM_ROW.id);
} });
