// marketing, 15 Nov 2026: the Search Console duty is inert without its secrets, signs a valid RS256 assertion, writes the
// rows it reads, and is not re-run the same Dubai day. No network: fetch and the database are stubs; the key is generated here.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { pullSearchConsole, readServiceAccount, readWindow, signedAssertion, toSearchRows, toSitemapRows, SC_SCOPE } from './search_console.ts';
import { DUTIES } from './registry.ts';

async function testKey(): Promise<{ sa: string; pub: CryptoKey }> {
  const kp = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
  const der = new Uint8Array(await crypto.subtle.exportKey('pkcs8', kp.privateKey));
  let s = ''; for (const b of der) s += String.fromCharCode(b);
  const pem = '-----BEGIN PRIVATE KEY-----\n' + btoa(s).replace(/(.{64})/g, '$1\n') + '\n-----END PRIVATE KEY-----\n';
  return { sa: JSON.stringify({ client_email: 'reader@probe-project.iam.gserviceaccount.com', private_key: pem }), pub: kp.publicKey };
}

function stubAdmin(lastFetched: string | null) {
  const writes: Record<string, unknown[]> = {};
  const admin = {
    from: (t: string) => ({
      select: () => ({ order: () => ({ limit: () => ({ maybeSingle: () => Promise.resolve({ data: lastFetched ? { fetched_at: lastFetched } : null }) }) }) }),
      upsert: (rows: unknown[]) => { (writes[t] ||= []).push(...rows); return Promise.resolve({ error: null }); },
    }),
  };
  return { admin, writes };
}

Deno.test('the duty is registered', () => { assert(DUTIES.some((d) => d.name === 'search_console')); });

Deno.test('without both secrets the duty is inert and calls nothing', async () => {
  let called = 0;
  const f = (() => { called++; return Promise.resolve(new Response('{}')); }) as typeof fetch;
  const { admin } = stubAdmin(null);
  const r = await pullSearchConsole({ admin, sec: () => Promise.resolve(undefined), now: new Date('2026-11-15T10:00:00Z') }, f);
  assertEquals(r.inert, true); assertEquals(r.due, false); assertEquals(called, 0);
  assertEquals(readServiceAccount('{"client_email":"x"}'), null);
  assertEquals(readServiceAccount('not json'), null);
});

Deno.test('the assertion is RS256, read-only scope, and verifies with the key', async () => {
  const { sa, pub } = await testKey();
  const jwt = await signedAssertion(readServiceAccount(sa)!, new Date('2026-11-15T10:00:00Z'));
  const [h, c, s] = jwt.split('.');
  const dec = (x: string) => JSON.parse(atob(x.replace(/-/g, '+').replace(/_/g, '/')));
  assertEquals(dec(h).alg, 'RS256');
  assertEquals(dec(c).scope, SC_SCOPE);
  assertEquals(dec(c).exp - dec(c).iat, 3600);
  const sig = Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((s.length + 3) % 4)), (ch) => ch.charCodeAt(0));
  assert(await crypto.subtle.verify('RSASSA-PKCS1-v1_5', pub, sig, new TextEncoder().encode(h + '.' + c)));
});

Deno.test('rows and sitemaps are read into the table shapes; bad rows are dropped', () => {
  assertEquals(toSearchRows('query', [{ keys: ['2026-11-12', 'aluminium supplier dubai'], clicks: 2, impressions: 40, ctr: 0.05, position: 8.4 },
                                      { keys: ['bad', 'x'], clicks: 1 }, { keys: ['2026-11-12'] }]),
    [{ day: '2026-11-12', dim: 'query', key: 'aluminium supplier dubai', clicks: 2, impressions: 40, ctr: 0.05, position: 8.4 }]);
  assertEquals(toSearchRows('total', [{ keys: ['2026-11-12'], clicks: 3, impressions: 90 }])[0].key, '');
  assertEquals(toSitemapRows({ sitemap: [{ path: 'https://quotesdone.com/sitemap.xml', errors: '0', warnings: '1',
                                           contents: [{ type: 'web', submitted: '120', indexed: '45' }] }] })[0],
    { path: 'https://quotesdone.com/sitemap.xml', submitted: 120, indexed: 45, last_downloaded: null, errors: 0, warnings: 1 });
  assertEquals(readWindow(new Date('2026-11-15T21:30:00Z')), { startDate: '2026-11-12', endDate: '2026-11-14' });
});

Deno.test('with its secrets it reads, writes the rows, and is not due again the same Dubai day', async () => {
  const { sa } = await testKey();
  const secrets: Record<string, string> = { google_search_console_sa: sa, google_search_console_site: 'sc-domain:quotesdone.com' };
  const seen: string[] = [];
  const f = ((url: string, init?: RequestInit) => {
    seen.push(String(url));
    if (String(url).includes('oauth2')) {
      assert(String(init?.body).includes('jwt-bearer'));
      return Promise.resolve(new Response(JSON.stringify({ access_token: 'stub-token' })));
    }
    assertEquals((init?.headers as Record<string, string>).authorization, 'Bearer stub-token');
    if (String(url).endsWith('/sitemaps')) return Promise.resolve(new Response(JSON.stringify({ sitemap: [{ path: 'https://quotesdone.com/sitemap.xml', contents: [{ submitted: 10, indexed: 4 }] }] })));
    const dims = JSON.parse(String(init?.body)).dimensions as string[];
    const rows = dims.length === 1 ? [{ keys: ['2026-11-12'], clicks: 1, impressions: 30, ctr: 0.03, position: 12 }]
      : [{ keys: ['2026-11-12', dims[1] === 'query' ? 'steel supplier uae' : 'https://quotesdone.com/blog/x'], clicks: 1, impressions: 10, ctr: 0.1, position: 9 }];
    return Promise.resolve(new Response(JSON.stringify({ rows })));
  }) as typeof fetch;
  const { admin, writes } = stubAdmin(null);
  const r = await pullSearchConsole({ admin, sec: (k) => Promise.resolve(secrets[k]), now: new Date('2026-11-15T10:00:00Z') }, f);
  assertEquals(r.ok, true); assertEquals(r.rows, 3); assertEquals(r.sitemaps, 1);
  assertEquals((writes.marketing_search_day || []).length, 3);
  assertEquals((writes.marketing_search_sitemap as Array<{ indexed: number }>)[0].indexed, 4);
  assert(seen.some((u) => u.includes(encodeURIComponent('sc-domain:quotesdone.com') + '/searchAnalytics/query')));
  assert(!JSON.stringify(r).includes('PRIVATE KEY'), 'the result never carries the key');

  const again = stubAdmin('2026-11-15T09:00:00Z');
  const r2 = await pullSearchConsole({ admin: again.admin, sec: (k) => Promise.resolve(secrets[k]), now: new Date('2026-11-15T10:00:00Z') }, f);
  assertEquals(r2.due, false);
});
