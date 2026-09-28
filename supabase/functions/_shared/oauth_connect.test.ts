import { assert, assertEquals } from 'jsr:@std/assert@1';
import { authorizeUrl, checkIdentity, isPublicClient, pkceChallenge, pkceVerifier, signState, tokenBody, verifyState } from './oauth_connect.ts';

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

Deno.test('PKCE round trip: the challenge on the authorize call is S256 of the verifier the callback re-derives from the state', async () => {
  const t = 1_000_000_000_000, s = await signState('k', 'ms_graph_seed', t);
  const sent = new URL(authorizeUrl('ms_graph_seed', 'cid', 'https://x/cb', s, await pkceChallenge(await pkceVerifier('k', s.split('.')[2])), 'tid'));
  const v = await verifyState('k', sent.searchParams.get('state')!, t + 60_000);
  const verifier = await pkceVerifier('k', v!.nonce);
  assert(verifier.length >= 43 && verifier.length <= 128 && /^[A-Za-z0-9_-]+$/.test(verifier));
  assertEquals(await pkceChallenge(verifier), sent.searchParams.get('code_challenge'));
  assertEquals(sent.searchParams.get('code_challenge_method'), 'S256');
  assert(!sent.toString().includes(verifier));
  assert(verifier !== await pkceVerifier('other', v!.nonce));
});

Deno.test('tampered state is rejected: nonce, expiry or signature changed', async () => {
  const t = 1_000_000_000_000, s = await signState('k', 'ms_graph_seed', t), [p, exp, n, sig] = s.split('.');
  const flip = (x: string) => (x[0] === 'A' ? 'B' : 'A') + x.slice(1);
  assertEquals(await verifyState('k', [p, exp, flip(n), sig].join('.'), t), null);
  assertEquals(await verifyState('k', [p, String(Number(exp) + 1000), n, sig].join('.'), t), null);
  assertEquals(await verifyState('k', [p, exp, n, flip(sig)].join('.'), t), null);
  assertEquals(await verifyState('k', s + 'x', t), null);
});

Deno.test('missing Microsoft secret leads to PKCE-only exchange; a secret keeps the confidential path', () => {
  assert(isPublicClient('ms_graph_seed', ''));
  assert(!isPublicClient('ms_graph_seed', 'sec'));
  assert(!isPublicClient('gmail_seed', ''));
  const pub = tokenBody('c', 'https://x/cb', 'cid', '', 'ver');
  assertEquals([pub.get('client_secret'), pub.get('code_verifier'), pub.get('grant_type')], [null, 'ver', 'authorization_code']);
  assert(!pub.toString().includes('client_secret'));
  const conf = tokenBody('c', 'https://x/cb', 'cid', 'sec', 'ver');
  assertEquals([conf.get('client_secret'), conf.get('code_verifier')], ['sec', 'ver']);
});
