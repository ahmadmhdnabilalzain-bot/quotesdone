// deno test supabase/functions/_shared/marketing_social_oauth.test.ts
// The founder's connect links (instructions 919-920): company scopes only, sealed tokens, QuotesDone's account only.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { accessToken, authorizeUrl, open, pickYoutube, sameString, scopesAreCompanyOnly, SCOPES, seal, verifyLinkedinOrg, type TokenSet } from './marketing_social_oauth.ts';

const MASTER = 'x'.repeat(40);

Deno.test('only company scopes are requested; a personal one is refused', () => {
  assert(scopesAreCompanyOnly(SCOPES.youtube) && scopesAreCompanyOnly(SCOPES.linkedin));
  for (const s of ['openid', 'profile', 'email', 'r_liteprofile', 'w_member_social', 'r_emailaddress']) assert(!scopesAreCompanyOnly(['r_organization_social', s]), s);
  const li = new URL(authorizeUrl('linkedin', 'cid', 'https://x/cb', 'st', 'ch'));
  assertEquals(li.searchParams.get('scope'), 'r_organization_social w_organization_social');
  const yt = new URL(authorizeUrl('youtube', 'cid', 'https://x/cb', 'st', 'ch'));
  assertEquals(yt.searchParams.get('scope'), 'https://www.googleapis.com/auth/youtube.force-ssl');
  assertEquals(yt.searchParams.get('code_challenge_method'), 'S256');
  assertEquals(yt.searchParams.get('access_type'), 'offline');
});

Deno.test('tokens are sealed: unreadable without the key, tamper-evident', async () => {
  const s = await seal(MASTER, { refresh_token: 'RT-secret' });
  assert(!s.includes('RT-secret'));
  assertEquals((await open(MASTER, s))?.refresh_token, 'RT-secret');
  assertEquals(await open('y'.repeat(40), s), null);
  const flipped = s.slice(0, -4) + (s.slice(-4, -3) === 'A' ? 'B' : 'A') + s.slice(-3);
  assertEquals(await open(MASTER, flipped), null);
});

Deno.test('only the QuotesDone channel / page is accepted, and a pinned id wins over the name', async () => {
  assert(pickYoutube([{ id: 'UC1', snippet: { title: 'QuotesDone' } }], null).ok);
  assert(!pickYoutube([{ id: 'UC2', snippet: { title: 'Ahmad personal' } }], null).ok);
  assert(!pickYoutube([{ id: 'UC3', snippet: { title: 'QuotesDone (fake)' } }], 'UC1').ok, 'the pin refuses a look-alike name');
  assert(!pickYoutube([], null).ok);
  const seen: string[] = [];
  const li = (status: number) => async (u: string) => { seen.push(u); return new Response('{}', { status }); };
  assert((await verifyLinkedinOrg(li(200), 'T', '123')).ok);
  assert(seen[0].includes('author=urn%3Ali%3Aorganization%3A123'), 'the pinned page, and only it, is probed');
  assert(!(await verifyLinkedinOrg(li(403), 'T', '123')).ok, 'no admin role on our page: refused');
  assert(!(await verifyLinkedinOrg(li(200), 'T', null)).ok, 'no pinned page id: refused, never discovered');
  assert(!(await verifyLinkedinOrg(li(200), 'T', '12 OR 1')).ok);
});

Deno.test('state comparison is exact', () => {
  assert(sameString('abc', 'abc')); assert(!sameString('abc', 'abd')); assert(!sameString('', '')); assert(!sameString('abc', 'abcd'));
});

Deno.test('an expired access token is refreshed and re-sealed; with no refresh token it is "not connected"', async () => {
  const store = new Map<string, string>([['google_oauth_client_id', 'id'], ['google_oauth_client_secret', 'sec']]);
  const t: TokenSet = { platform: 'youtube', account_id: 'UC1', access_token: 'old', expires_at: 0, refresh_token: 'RT', connected_at: '' };
  store.set('youtube_oauth', await seal(MASTER, t));
  const f = async (_u: string, init?: RequestInit) => { assert(String(init?.body).includes('grant_type=refresh_token')); return new Response(JSON.stringify({ access_token: 'new', expires_in: 3600 })); };
  const got = await accessToken(f, 'youtube', MASTER, async (k) => store.get(k), async (k, v) => { store.set(k, v); }, 1_000_000);
  assertEquals(got?.access_token, 'new');
  assertEquals((await open<TokenSet>(MASTER, store.get('youtube_oauth')!))?.access_token, 'new');
  store.set('linkedin_oauth', await seal(MASTER, { ...t, platform: 'linkedin', refresh_token: null }));
  assertEquals(await accessToken(f, 'linkedin', MASTER, async (k) => store.get(k), async () => {}, 1_000_000), null);
});
