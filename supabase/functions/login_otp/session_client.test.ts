// Sign-in never borrows the system's database client. verifyOtp stores the session on the client it
// runs on; on 14 Sep it ran on login_otp's module-level service-role client, so every later database
// call from it spoke as the user who had just signed in (72 x 403 on fn_registered_locale). These
// prove every /rest/v1 call carries the service key after a sign-in, and that two sign-ins in flight
// together each get their own token and never lend it to the database client.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invoke, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';

const fn = () => loadFunction('login_otp', () => import('./index.ts'));
const SERVICE = 'Bearer stub-service-role';
const b64 = (o: unknown) => btoa(JSON.stringify(o)).replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
const jwt = (sub: string) => `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64({ sub, role: 'authenticated', exp: 4102444800 })}.sig`;

// The harness answers app_secrets with this value, so it is the otp_hmac_key the function uses.
async function hmac(code: string) {
  const k = await crypto.subtle.importKey('raw', new TextEncoder().encode('stub-secret-value-0123456789abcdef'), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return Array.from(new Uint8Array(await crypto.subtle.sign('HMAC', k, new TextEncoder().encode(code)))).map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** A stub where each email signs in as its own user; records the Authorization of every /rest/v1 call. */
async function world(delayVerifyFor?: string) {
  const rest: { path: string; auth: string }[] = [];
  const stub: Stub = {
    rows: { email_verifications: [{ id: 1, token_hash: await hmac('123456'), attempts: 0, expires_at: new Date(Date.now() + 600e3).toISOString() }] },
    rpc: { auth_uid_by_email: 'uid-existing' },
    handle: async (req, u) => {
      if (u.pathname.startsWith('/rest/v1/')) { rest.push({ path: u.pathname, auth: req.headers.get('authorization') || '' }); return undefined; }
      const body = await req.clone().json().catch(() => ({}));
      if (u.pathname === '/auth/v1/admin/generate_link') {
        return new Response(JSON.stringify({ id: 'u-' + body.email, email: body.email, hashed_token: 'th:' + body.email }), { headers: { 'content-type': 'application/json' } });
      }
      if (u.pathname === '/auth/v1/verify') {
        const email = String(body.token_hash || '').slice(3);
        if (email === delayVerifyFor) await new Promise((r) => setTimeout(r, 40)); // the other sign-in runs meanwhile
        const session = { access_token: jwt('sub-' + email), refresh_token: 'rt-' + email, token_type: 'bearer', expires_in: 3600, expires_at: 4102444800, user: { id: 'sub-' + email, email, aud: 'authenticated' } };
        return new Response(JSON.stringify(session), { headers: { 'content-type': 'application/json' } });
      }
      return undefined;
    },
  };
  return { stub, rest };
}
const verify = (email: string) => ({ action: 'verify', user_kind: 'customer', identifier: email, code: '123456' });

Deno.test('login_otp: after a sign-in, the next database call still carries the service-role key', async () => {
  const h = await fn();
  const { stub, rest } = await world();
  const a = await invoke(h, stub, verify('qd-stub-a@example.invalid'));
  assertEquals(a.status, 200, JSON.stringify(a.json));
  assertEquals(a.json.access_token, jwt('sub-qd-stub-a@example.invalid'), 'the caller gets their own session');
  const locale = rest.filter((c) => c.path === '/rest/v1/rpc/fn_registered_locale');
  assertEquals(locale.length, 1, 'the registered language is looked up once, after the session is minted');
  // A second request in the same (warm) isolate must not inherit the first person's session either.
  const b = await invoke(h, stub, verify('qd-stub-b@example.invalid'));
  assertEquals(b.status, 200, JSON.stringify(b.json));
  assert(rest.length > 4, 'the harness saw the database calls');
  for (const c of rest) assertEquals(c.auth, SERVICE, c.path + ' was sent with a user token');
});

Deno.test('login_otp: two sign-ins in flight together never carry each other\'s token', async () => {
  const h = await fn();
  const A = 'qd-stub-c@example.invalid', B = 'qd-stub-d@example.invalid';
  const { stub, rest } = await world(A);
  const call = (email: string) => h(new Request('https://fn.invalid/', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(verify(email)) })).then((r) => r.json());
  await invoke(h, stub, { action: 'noop' }); // install this stub as current
  const [ra, rb] = await Promise.all([call(A), call(B)]);
  assertEquals(ra.access_token, jwt('sub-' + A));
  assertEquals(rb.access_token, jwt('sub-' + B));
  assertEquals(rest.filter((c) => c.path === '/rest/v1/rpc/fn_registered_locale').length, 2);
  for (const c of rest) assertEquals(c.auth, SERVICE, c.path + ' was sent with a user token');
});
