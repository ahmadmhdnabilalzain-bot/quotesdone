// THE SIGN-IN AND THE BAN AT THE DOOR, TOGETHER (15 Nov 2026, customer_support; lib/door.ts). Every supplier_api request waited on
// auth.getUser, then on the sanctions read: two round trips in series. These prove the read now overlaps getUser AND that the
// refusal is still decided for the address getUser verified, whatever the token claims.
//   deno test --no-lock --node-modules-dir=none supabase/functions/supplier_api/door.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import type { User } from 'jsr:@supabase/supabase-js@2';
import { atTheDoor, emailClaimOf } from './lib/door.ts';

const b64u = (o: unknown) => btoa(JSON.stringify(o)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const jwtFor = (claims: Record<string, unknown>) => `${b64u({ alg: 'HS256', typ: 'JWT' })}.${b64u(claims)}.sig`;
const user = (email: string | null) => ({ id: 'u1', email } as unknown as User);
const BANNED = 'qd-door-banned@example.invalid', CLEAN = 'qd-door-clean@example.invalid';

/** getUser and the ban read, each taking `ms`, with a log of what was asked and how many were in flight at once. */
function deps(verified: User | null, o: { ms?: number; banFails?: boolean } = {}) {
  const asked: string[] = []; let now = 0, most = 0;
  const slow = async <T>(f: () => T): Promise<T> => { now++; most = Math.max(most, now); await new Promise((r) => setTimeout(r, o.ms ?? 10)); try { return f(); } finally { now--; } };
  return {
    asked, most: () => most,
    d: {
      getUser: () => slow(() => verified),
      sanctioned: (e: string) => { asked.push(e); return slow(() => { if (o.banFails) throw new Error('sanctions_ban lookup failed'); return e === BANNED; }); },
    },
  };
}

Deno.test('the ban read leaves beside getUser when the token names the address getUser verifies', async () => {
  const x = deps(user(CLEAN));
  const v = await atTheDoor(jwtFor({ email: CLEAN.toUpperCase() }), x.d);
  assertEquals(v.kind, 'in');
  assertEquals(x.most(), 2, 'getUser and the ban read were asked one after the other');
  assertEquals(x.asked, [CLEAN], 'the ban was read once, for the verified address');
  const t0 = Date.now(); await atTheDoor(jwtFor({ email: CLEAN }), deps(user(CLEAN), { ms: 60 }).d);
  assert(Date.now() - t0 < 110, 'two 60 ms reads took a full round trip each: still in series');
});

Deno.test('a banned verified address is refused, together or after (the token naming it, another address, or none)', async () => {
  for (const claims of [{ email: BANNED }, { email: CLEAN }, {}, { email: 42 }]) {
    const x = deps(user(BANNED));
    const v = await atTheDoor(jwtFor(claims), x.d);
    assertEquals(v.kind, 'sanctioned', 'refused for claims ' + JSON.stringify(claims));
    assertEquals(x.asked.at(-1), BANNED, 'the verdict came from the verified address');
  }
  assertEquals((await atTheDoor('not-a-jwt', deps(user(BANNED)).d)).kind, 'sanctioned');
});

Deno.test('a token that claims a banned address but verifies as a clean one is let in: the claim is never the verdict', async () => {
  const x = deps(user(CLEAN));
  const v = await atTheDoor(jwtFor({ email: BANNED }), x.d);
  assertEquals(v.kind, 'in');
  assertEquals(x.asked, [BANNED, CLEAN], 'the early read for the claimed address was not used; the verified one was asked');
});

Deno.test('no verified user is unauthorized, and an unused early read that fails never surfaces', async () => {
  let unhandled = 0; const on = (e: PromiseRejectionEvent) => { unhandled++; e.preventDefault(); };
  globalThis.addEventListener('unhandledrejection', on);
  try {
    assertEquals((await atTheDoor(jwtFor({ email: CLEAN }), deps(null, { banFails: true }).d)).kind, 'unauthorized');
    assertEquals((await atTheDoor(jwtFor({ email: CLEAN }), deps(user(null)).d)).kind, 'unauthorized');
    await new Promise((r) => setTimeout(r, 30));
    assertEquals(unhandled, 0);
  } finally { globalThis.removeEventListener('unhandledrejection', on); }
});

Deno.test('a ban read that fails still fails closed: it throws to the handler (unexpected_error), never "not sanctioned"', async () => {
  let threw = false;
  try { await atTheDoor(jwtFor({ email: CLEAN }), deps(user(CLEAN), { banFails: true }).d); } catch { threw = true; }
  assert(threw, 'a failed ban read let the request in');
  threw = false;
  try { await atTheDoor(jwtFor({}), deps(user(CLEAN), { banFails: true }).d); } catch { threw = true; }
  assert(threw, 'a failed ban read after getUser let the request in');
});

Deno.test('emailClaimOf reads the claim and nothing else', () => {
  assertEquals(emailClaimOf(jwtFor({ email: ' A@B.ae ' })), 'a@b.ae');
  assertEquals([emailClaimOf(''), emailClaimOf('a.b'), emailClaimOf('a.%%%.c'), emailClaimOf(jwtFor({ sub: 'x' }))], ['', '', '', '']);
});
