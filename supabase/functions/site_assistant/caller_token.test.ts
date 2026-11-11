// site_assistant/caller_token.ts: only a token that can be a user session is sent to auth.getUser (it_engineer, 11 Nov 2026).
//   DENO_NO_PACKAGE_JSON=1 deno test --no-lock --allow-read=. supabase/functions/site_assistant/caller_token.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { mayBeUserSession } from './caller_token.ts';

const b64u = (o: unknown) => btoa(JSON.stringify(o)).replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
const jwt = (payload: unknown) => b64u({ alg: 'HS256', typ: 'JWT' }) + '.' + b64u(payload) + '.c2lnbmF0dXJl';

Deno.test('the keys a visitor\'s widget sends are never verified; a session-shaped token always is', () => {
  assertEquals(mayBeUserSession('sb_publishable_ZZZZZZZZZZZZZZZZZZZZZZ_zzzzzzzzzzzzzzzzzzzz'), false, 'the publishable key');
  assertEquals(mayBeUserSession(jwt({ iss: 'supabase', role: 'anon', ref: 'zz' })), false, 'the legacy anon key');
  assertEquals(mayBeUserSession(jwt({ role: 'service_role' })), false);
  assertEquals(mayBeUserSession('not.a.jwt'), false);
  assertEquals(mayBeUserSession(''), false);
  assertEquals(mayBeUserSession(jwt({ sub: '00000000-0000-4000-8000-000000000001', role: 'authenticated', email: 'zz@example.invalid' })), true);
  // URL-safe base64 with the characters plain base64 would write as + and /
  assertEquals(mayBeUserSession(jwt({ role: 'authenticated', n: '>>>???' })), true);
});

Deno.test('identify() asks auth.getUser only for a token that can be a user session', () => {
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  const body = src.slice(src.indexOf('async function identify('), src.indexOf('admin.auth.getUser(jwt)'));
  assert(/if \(!jwt \|\| jwt\.length < 40 \|\| !mayBeUserSession\(jwt\)\) return null;/.test(body), 'getUser is reached by a token that cannot be a session');
});
