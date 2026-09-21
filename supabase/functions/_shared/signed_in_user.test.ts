// Replays the 21 Sep 2026 input: the auth server hangs, and a token that cannot be a session.
// Fails if an invalid token reaches the network again, or if an auth outage becomes a 401 or
// waits longer than its bound. Run: deno test supabase/functions/_shared/signed_in_user.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { localRefusal, signedInUser } from './signed_in_user.ts';

const b64u = (o: unknown) => btoa(JSON.stringify(o)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const tok = (p: Record<string, unknown>) => `${b64u({ alg: 'ES256' })}.${b64u(p)}.sig`;
const now = Math.floor(Date.now() / 1000);
const live = tok({ sub: 'u1', exp: now + 3600 });

function fake(getUser: () => Promise<any>) {
  const f = { calls: 0, auth: { getUser: () => { f.calls++; return getUser(); } } };
  return f;
}
const never = () => new Promise<any>(() => {});

Deno.test('a token that cannot be a session is refused with no network call', async () => {
  for (const [h, why] of [['', 'malformed'], ['Bearer abc', 'malformed'], ['Bearer a.!!!.c', 'malformed'],
    ['Bearer ' + tok({ role: 'anon', exp: now + 1e8 }), 'no_subject'], ['Bearer ' + tok({ sub: 'u1', exp: now - 1 }), 'expired']]) {
    const f = fake(never);
    const r = await signedInUser(f, h, 50);
    assertEquals(r, { ok: false, status: 401, reason: why });
    assertEquals(f.calls, 0, `${why} must not reach the auth server`);
  }
});

Deno.test('an auth server that hangs is a 503 within the bound, not a 401 after 35 s', async () => {
  const f = fake(never);
  const t0 = Date.now();
  const r = await signedInUser(f, 'Bearer ' + live, 50);
  assert(Date.now() - t0 < 1000, 'refusal must respect the bound');
  assertEquals(r, { ok: false, status: 503, reason: 'auth_timeout' });
});

Deno.test('an auth 5xx or network failure is 503; an auth 4xx is 401', async () => {
  assertEquals(await signedInUser(fake(async () => ({ data: { user: null }, error: { status: 504 } })), live, 50), { ok: false, status: 503, reason: 'auth_unavailable_504' });
  assertEquals(await signedInUser(fake(() => Promise.reject(new Error('reset'))), live, 50), { ok: false, status: 503, reason: 'auth_network' });
  assertEquals(await signedInUser(fake(async () => ({ data: { user: null }, error: { status: 403 } })), live, 50), { ok: false, status: 401, reason: 'no_user' });
});

Deno.test('a live session still resolves to its user, email lower-cased', async () => {
  const r = await signedInUser(fake(async () => ({ data: { user: { id: 'u1', email: 'A@B.example' } }, error: null })), 'Bearer ' + live, 50);
  assert(r.ok);
  assertEquals(r.email, 'a@b.example');
  assertEquals(localRefusal(live), null);
});
