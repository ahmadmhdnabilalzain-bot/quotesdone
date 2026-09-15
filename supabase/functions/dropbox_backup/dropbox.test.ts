// deno test supabase/functions/dropbox_backup/dropbox.test.ts
// The shared access token is reused across runs, one run refreshes at a time, a throttled or failed
// token call is retried and never becomes 'no_dropbox_auth', a refusal is 'no_dropbox_auth' at once;
// a 401 gets one new token and one repeat; non-ASCII names are escaped for the header.
import { assert, assertEquals, assertRejects } from 'jsr:@std/assert@1';
import { classifyDropboxFailure } from './health.ts';
import { apiArg, AuthUnavailable, DropboxClient, memoryStore, refreshAccessToken, TokenCache, type Refreshed } from './dropbox.ts';

const HOUR = 3600_000;
// a fake clock that advances only when a run sleeps
function clock() { let t = 1_000_000; return { now: () => t, sleep: (ms: number) => { t += ms; return Promise.resolve(); } }; }
const tok = (token: string, expiresIn = 14400): Promise<Refreshed> => Promise.resolve({ token, expiresIn });

Deno.test('a still-valid token is reused across runs: one refresh for many runs', async () => {
  const store = memoryStore(); let n = 0; const c = clock();
  const refresh = () => tok('T' + (++n));
  const runs = Array.from({ length: 5 }, () => new TokenCache(store, refresh, c));
  for (const r of runs) assertEquals(await r.token(), 'T1');
  assertEquals(n, 1);
  assertEquals(runs[0].refreshes + runs.slice(1).reduce((s, r) => s + r.reused, 0), 5);
});

Deno.test('a token within 10 minutes of expiry is refreshed, not reused', async () => {
  const store = memoryStore(); let n = 0; const c = clock();
  await new TokenCache(store, () => tok('T' + (++n)), c).token();
  await c.sleep(4 * HOUR - 5 * 60_000);                       // 5 minutes left
  assertEquals(await new TokenCache(store, () => tok('T' + (++n)), c).token(), 'T2');
  assertEquals(n, 2);
});

Deno.test('single flight: twenty concurrent runs cause one refresh and all get its token', async () => {
  const store = memoryStore(); let n = 0; let release!: () => void;
  const gate = new Promise<void>((r) => release = r);
  const refresh = async () => { n++; await gate; return { token: 'SHARED', expiresIn: 14400 }; };
  const sleep = () => new Promise<void>((r) => setTimeout(r, 1));
  const got = Promise.all(Array.from({ length: 20 }, () => new TokenCache(store, refresh, { sleep }).token()));
  await new Promise((r) => setTimeout(r, 20)); release();
  assertEquals(new Set(await got), new Set(['SHARED']));
  assertEquals(n, 1);
});

Deno.test('a run that died holding the lease does not block the others past the lease', async () => {
  const store = memoryStore(); const c = clock();
  await store.cas(null, `0|${c.now() + 20_000}|`);             // a lease nobody will ever finish
  assertEquals(await new TokenCache(store, () => tok('NEW'), c).token(), 'NEW');
});

Deno.test('a 429 from the token endpoint is retried with backoff and succeeds without failing anything', async () => {
  const c = clock(); let calls = 0;
  const f = () => Promise.resolve(++calls < 3 ? new Response('', { status: 429 })
    : new Response(JSON.stringify({ access_token: 'OK', expires_in: 14400 }), { status: 200 }));
  const cache = new TokenCache(memoryStore(), () => refreshAccessToken('rt', 'k', 's', f), c);
  assertEquals(await cache.token(), 'OK');
  assertEquals([calls, cache.refreshes], [3, 3]);
});

Deno.test('a token endpoint still failing past the budget is AuthUnavailable, never no_dropbox_auth', async () => {
  const c = clock();
  const cache = new TokenCache(memoryStore(), () => refreshAccessToken('rt', 'k', 's', () => Promise.resolve(new Response('', { status: 503 }))), { ...c, budgetMs: 20_000 });
  const e = await assertRejects(() => cache.token(), AuthUnavailable);
  assert(e.message.startsWith('oauth2/token 503'), e.message);
  assert(!e.message.includes('no_dropbox_auth'));
});

Deno.test('the retry budget never runs past the run deadline', async () => {
  const c = clock();
  const cache = new TokenCache(memoryStore(), () => Promise.reject(new AuthUnavailable('oauth2/token 429')), { ...c, deadline: c.now() + 3000 });
  await assertRejects(() => cache.token(), AuthUnavailable);
  assert(c.now() < 1_000_000 + 3000 + 1);
});

Deno.test('classification of the refresh: transient vs refused', async () => {
  const r = (status: number, body = '') => () => Promise.resolve(new Response(body, { status }));
  await assertRejects(() => refreshAccessToken('rt', 'k', 's', r(429)), AuthUnavailable, 'oauth2/token 429');
  await assertRejects(() => refreshAccessToken('rt', 'k', 's', r(500)), AuthUnavailable, 'oauth2/token 500');
  await assertRejects(() => refreshAccessToken('rt', 'k', 's', () => Promise.reject(new TypeError('fetch failed'))), AuthUnavailable, 'oauth2/token network');
  const refused = async (f: () => Promise<Response>) => {
    const e = await assertRejects(() => refreshAccessToken('rt', 'k', 's', f));
    assert(!(e instanceof AuthUnavailable)); assertEquals((e as Error).message, 'no_dropbox_auth');
  };
  await refused(r(400, JSON.stringify({ error: 'invalid_grant', error_description: 'refresh token is invalid or revoked' })));
  await refused(r(400, JSON.stringify({ error: 'invalid_client' })));
  await refused(r(401));
  await assertRejects(() => refreshAccessToken('', 'k', 's', r(200)), Error, 'no_dropbox_auth');
  assertEquals(await refreshAccessToken('rt', 'k', 's', r(200, JSON.stringify({ access_token: 'A', expires_in: 100 }))), { token: 'A', expiresIn: 100 });
});

Deno.test('the IT engineer classes an unavailable token endpoint as provider-side, never as auth', () => {
  assertEquals(classifyDropboxFailure('oauth2/token 429 (token refresh failed 5 time(s))'), 'rate_limit');
  assertEquals(classifyDropboxFailure('oauth2/token 503'), 'provider_outage');
  assertEquals(classifyDropboxFailure('oauth2/token network TimeoutError'), 'network');
  assertEquals(classifyDropboxFailure('no_dropbox_auth'), 'auth');
});

Deno.test('a refused refresh is thrown at once, not retried', async () => {
  let n = 0;
  const cache = new TokenCache(memoryStore(), () => { n++; return Promise.reject(new Error('no_dropbox_auth')); }, clock());
  await assertRejects(() => cache.token(), Error, 'no_dropbox_auth');
  assertEquals(n, 1);
});

Deno.test('a 401 on the shared token gets a new token and one repeat; the rejected token is never reused', async () => {
  const seen: string[] = []; let n = 0; const store = memoryStore(); const c = clock();
  await new TokenCache(store, () => tok('OLD'), c).token();   // another run stored OLD
  const f = (_u: string, init: RequestInit) => {
    seen.push((init.headers as Record<string, string>).Authorization);
    return Promise.resolve(new Response('{}', { status: seen.length === 1 ? 401 : 200 }));
  };
  const dbx = new DropboxClient(new TokenCache(store, () => tok('NEW' + (++n)), c), f);
  assertEquals((await dbx.call('api', 'files/get_metadata', { path: '/a' })).status, 200);
  assertEquals(seen, ['Bearer OLD', 'Bearer NEW1']);
  assertEquals(dbx.refreshes, 1);
  assertEquals(await new TokenCache(store, () => tok('X'), c).token(), 'NEW1');   // the next run reuses the new one
});

Deno.test('a second 401 is returned, not looped on', async () => {
  const dbx = new DropboxClient(new TokenCache(memoryStore(), () => tok('T'), clock()), () => Promise.resolve(new Response('', { status: 401 })));
  assertEquals((await dbx.call('api', 'users/get_space_usage', null)).status, 401);
});

Deno.test('a refresh that is refused is no_dropbox_auth', async () => {
  const dbx = new DropboxClient(new TokenCache(memoryStore(), () => refreshAccessToken('', '', '')), () => Promise.resolve(new Response('')));
  await assertRejects(() => dbx.call('api', 'users/get_space_usage', null), Error, 'no_dropbox_auth');
});

Deno.test('Arabic and emoji are escaped in Dropbox-API-Arg', () => {
  const a = apiArg({ path: '/مستند 🏗️' });
  assertEquals(/^[\x00-\x7e]*$/.test(a), true);
  assertEquals(JSON.parse(a).path, '/مستند 🏗️');
});
