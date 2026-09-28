import { assert, assertEquals } from 'jsr:@std/assert@1';
import { authorizeUrl, checkIdentity, signState, verifyState } from './oauth_connect.ts';

Deno.test('state: verifies, is bound to its key, expires in 10 minutes, and cannot be re-bound to another provider', async () => {
  const s = await signState('k', 'gmail_seed', 1_000_000_000_000);
  assertEquals((await verifyState('k', s, 1_000_000_000_000))?.provider, 'gmail_seed');
  assertEquals(await verifyState('other', s, 1_000_000_000_000), null);
  assertEquals(await verifyState('k', s, 1_000_000_000_000 + 10 * 60_000 + 1), null);
  assertEquals(await verifyState('k', s.replace('gmail_seed', 'ms_graph_seed'), 1_000_000_000_000), null);
});

Deno.test('consent URLs carry the right scope, offline access and PKCE', () => {
  const g = new URL(authorizeUrl('google_postmaster', 'cid', 'https://x/cb', 'st', 'ch'));
  assertEquals(g.searchParams.get('scope'), 'https://www.googleapis.com/auth/postmaster.readonly');
  assertEquals([g.searchParams.get('access_type'), g.searchParams.get('prompt'), g.searchParams.get('code_challenge_method')], ['offline', 'consent', 'S256']);
  const m = new URL(authorizeUrl('ms_graph_seed', 'cid', 'https://x/cb', 'st', 'ch', 'tid'));
  assertEquals(m.origin + m.pathname, 'https://login.microsoftonline.com/tid/oauth2/v2.0/authorize');
  assert(m.searchParams.get('scope')!.includes('Mail.Read') && m.searchParams.get('scope')!.includes('offline_access'));
});

Deno.test('identity: only the allowlisted mailbox / a Postmaster account that lists quotesdone.com passes', async () => {
  const f = (body: unknown) => () => Promise.resolve(new Response(JSON.stringify(body)));
  assert((await checkIdentity(f({ emailAddress: 'AhmadMhdNabilAlzain@gmail.com' }), 'gmail_seed', 't')).ok);
  assert(!(await checkIdentity(f({ emailAddress: 'someone@gmail.com' }), 'gmail_seed', 't')).ok);
  assert((await checkIdentity(f({ userPrincipalName: 'management@doratajewelries.com' }), 'ms_graph_seed', 't')).ok);
  assert(!(await checkIdentity(f({ mail: 'x@doratajewelries.com' }), 'ms_graph_seed', 't')).ok);
  assert((await checkIdentity(f({ domains: [{ name: 'domains/quotesdone.com' }] }), 'google_postmaster', 't')).ok);
  assert(!(await checkIdentity(f({ domains: [{ name: 'domains/quotesdone.ae' }] }), 'google_postmaster', 't')).ok);
});
