// The seats' web search (Serper), offline. Fails if: the key is sent without being set, a search runs without the
// claim, a refused or over-cap claim still searches, gl/hl are wrong, a non-official source survives, a key or
// billing refusal does not tell the founder's flag, or an outage / missing key does.
//   deno test supabase/functions/_shared/web_search.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { officialUaeSource, parseSerper, serperBody, serperSearch, type SearchDeps } from './web_search.ts';

type Call = [string, Record<string, unknown>];
function deps(o: { key?: string; claim?: unknown; claimError?: string; status?: number; body?: unknown; throws?: boolean }) {
  const rpcs: Call[] = [];
  const fetches: { url: string; init: RequestInit }[] = [];
  const d: SearchDeps = {
    key: o.key,
    rpc: (fn, args) => {
      rpcs.push([fn, args]);
      if (fn === 'fn_web_search_claim') return Promise.resolve({ data: o.claim ?? { allowed: true, used: 1 }, error: o.claimError ? { message: o.claimError } : null });
      return Promise.resolve({ data: { raised: true }, error: null });
    },
    fetch: (url, init) => {
      fetches.push({ url, init });
      if (o.throws) return Promise.reject(new Error('connection reset'));
      return Promise.resolve(new Response(JSON.stringify(o.body ?? { organic: [] }), { status: o.status ?? 200 }));
    },
  };
  return { d, rpcs, fetches };
}
const degraded = (rpcs: Call[]) => rpcs.find(([f]) => f === 'fn_web_search_degraded')?.[1];

Deno.test('no key: no claim, no request, one it_engineer finding that never reaches the founder', async () => {
  const m = deps({});
  assertEquals(await serperSearch('pool permit', m.d), []);
  assertEquals(m.fetches.length, 0);
  assertEquals(m.rpcs.some(([f]) => f === 'fn_web_search_claim'), false);
  assertEquals(degraded(m.rpcs), { p_reason: 'no_key', p_notify: false, p_detail: 'the edge secret SERPER_API_KEY is not set' });
});

Deno.test('a refused claim (a private name) or the cap never searches', async () => {
  for (const reason of ['names_a_private_party', 'daily_cap']) {
    const m = deps({ key: 'k', claim: { allowed: false, reason } });
    assertEquals(await serperSearch('x', m.d), []);
    assertEquals(m.fetches.length, 0);
    assertEquals(degraded(m.rpcs), undefined); // the cap's finding is raised inside fn_web_search_claim
  }
});

Deno.test('a failed claim degrades without searching', async () => {
  const m = deps({ key: 'k', claimError: 'boom' });
  assertEquals(await serperSearch('x', m.d), []);
  assertEquals(m.fetches.length, 0);
  assertEquals(degraded(m.rpcs)?.p_notify, false);
});

Deno.test('the request: POST, X-API-KEY header, gl=ae, hl=en or ar, official sources only', async () => {
  const m = deps({ key: 'secret-k', body: { organic: [
    { link: 'https://www.dm.gov.ae/pools', title: 'DM' },
    { link: 'https://uaelegislation.gov.ae/en/law', title: 'Law' },
    { link: 'https://www.tax.gov.ae/x', title: 'FTA' },
    { link: 'http://www.dm.gov.ae/insecure', title: 'http' },
    { link: 'https://dm.gov.ae.evil.com/x', title: 'evil' },
    { link: 'https://u.ae/en', title: 'portal' },
    { link: 'https://www.khaleejtimes.com/x', title: 'news' },
  ] } });
  const hits = await serperSearch('pool permit', m.d);
  assertEquals(hits.map((h) => h.url), ['https://www.dm.gov.ae/pools', 'https://uaelegislation.gov.ae/en/law', 'https://www.tax.gov.ae/x']);
  const { url, init } = m.fetches[0];
  assertEquals(url, 'https://google.serper.dev/search');
  assertEquals(init.method, 'POST');
  assertEquals((init.headers as Record<string, string>)['X-API-KEY'], 'secret-k');
  const body = JSON.parse(String(init.body));
  assertEquals([body.gl, body.hl], ['ae', 'en']);
  assertEquals(JSON.parse(JSON.stringify(serperBody('رخصة مسبح دبي'))).hl, 'ar');
  assertEquals(degraded(m.rpcs), undefined);
});

Deno.test('a key or billing refusal may tell the founder; an outage never does; the key is never in a finding', async () => {
  for (const status of [401, 402, 403]) {
    const m = deps({ key: 'secret-k', status });
    assertEquals(await serperSearch('x', m.d), []);
    assertEquals(degraded(m.rpcs)?.p_reason, 'key_or_billing');
    assertEquals(degraded(m.rpcs)?.p_notify, true);
    assert(!JSON.stringify(m.rpcs).includes('secret-k'));
  }
  for (const o of [{ status: 500 }, { status: 429 }, { throws: true }]) {
    const m = deps({ key: 'secret-k', ...o });
    assertEquals(await serperSearch('x', m.d), []);
    assertEquals(degraded(m.rpcs)?.p_reason, 'outage');
    assertEquals(degraded(m.rpcs)?.p_notify, false);
    assert(!JSON.stringify(m.rpcs).includes('secret-k'));
  }
});

Deno.test('official UAE sources: https on gov.ae only; a malformed body yields nothing', () => {
  assert(officialUaeSource('https://tdra.gov.ae/a'));
  assert(officialUaeSource('https://moec.gov.ae/a'));
  assert(!officialUaeSource('https://gov.ae.example.com/'));
  assert(!officialUaeSource('not a url'));
  assertEquals(parseSerper(null), []);
  assertEquals(parseSerper({ organic: 'x' }), []);
});
