// A gte-small vector that did not come back says WHY, and think() writes it into the step (it_engineer, 27 Oct 2026).
// Measured on production at 20:30Z: embedRemote swallowed every failure, so five held rows' retrieve steps read only
// 'embedding_unavailable' and nobody could tell a timeout from a refusal. The fetch is replaced here; no network.
import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert';
const J = (x: unknown) => JSON.stringify(x);

Deno.env.set('SUPABASE_URL', 'https://zz-demo.example.invalid');
const { embedGteRemote, _resetEmbedClientForTest, EMBED_COOL_MS } = await import('./ml_embed_client.ts');
const { think } = await import('./think.ts');
import type { ThinkDeps } from './think.ts';

const admin = { from: () => ({ select: () => ({ eq: () => ({ maybeSingle: () => Promise.resolve({ data: { value: 'zz-demo-cred' } }) }) }) }) };
async function withFetch<T>(f: () => Response | Promise<Response>, run: () => Promise<T>): Promise<T> {
  const real = globalThis.fetch;
  globalThis.fetch = (() => Promise.resolve().then(f)) as typeof fetch;
  try { return await run(); } finally { globalThis.fetch = real; }
}

for (const [name, answer, expect] of [
  ['a 503 from embed_ml', () => new Response(JSON.stringify({ ok: false, error: 'embed_failed' }), { status: 503 }), 'embed_ml_http_503:embed_failed'],
  ['a 503 no worker served', () => new Response('upstream unavailable', { status: 503 }), 'embed_ml_http_503:no_json_body'],
  ['a fetch that throws', () => { throw new TypeError('error sending request: connection reset'); }, 'embed_ml_error: TypeError: error sending request: connection reset'],
  ['a timeout', () => { throw new DOMException('Signal timed out.', 'TimeoutError'); }, 'embed_ml_timeout_8000ms'],
] as [string, () => Response, string][]) {
  Deno.test(`embedGteRemote says why it returned null: ${name}`, async () => {
    _resetEmbedClientForTest();
    let why = '';
    const v = await withFetch(answer, () => embedGteRemote(admin, 'ZZ DEMO text', 'resilience_ping', 8000, (w) => { why = w; }));
    assertEquals(v, null);
    assertEquals(why, expect);
  });
}

Deno.test('think() stores the embedder\'s reason in the retrieve step', async () => {
  const deps: ThinkDeps = {
    gate: () => Promise.resolve({ allowed: true } as never),
    llm: (phase) => Promise.resolve(phase === 'decompose'
      ? { content: JSON.stringify({ steps: [{ id: 's1', goal: 'g', query: 'ZZ DEMO pool rules' }], facts: [] }), model: 'm' }
      : { content: null, error: 'no mock reply' }),
    embed: () => Promise.resolve(null),
    embedFailure: (_t, sp) => sp === 'gte' ? 'embed_ml_http_503:no_json_body' : null,
    rpc: (fn) => Promise.resolve(fn === 'fn_case_recall' ? { data: { cases: [] }, error: null } : { data: [], error: null }),
  };
  const r = await think(deps, { context: { audience: 'internal' }, seat: 'ceo', surface: 'think.answer', question: 'ZZ DEMO what are the pool rules?' });
  const step = r.steps.find((s) => s.id === 's1' && s.kind === 'retrieve')!;
  assertStringIncludes(String(step.detail), 'embedding_unavailable: embed_ml_http_503:no_json_body');
});

Deno.test('the heartbeat\'s deps carry the reason from embedGteRemote to embedFailure, and clear it on success', async () => {
  const { heartbeatDeps } = await import('./think.ts');
  _resetEmbedClientForTest();
  const d = heartbeatDeps(admin);
  await withFetch(() => new Response('upstream unavailable', { status: 503 }), () => d.embed('ZZ DEMO q', 'gte'));
  assertEquals(d.embedFailure?.('ZZ DEMO q', 'gte'), 'embed_ml_http_503:no_json_body');
  _resetEmbedClientForTest();   // past the cool-off
  const vec = '[' + Array(384).fill(0.01).join(',') + ']';
  await withFetch(() => new Response(JSON.stringify({ ok: true, space: 'gte', embedding: vec }), { status: 200 }), () => d.embed('ZZ DEMO q', 'gte'));
  assertEquals(d.embedFailure?.('ZZ DEMO q', 'gte'), null);
});

Deno.test('a visitor\'s deps (embedTimeoutMs 3000) wait 3 s on embed_ml, not 8, and a timeout is the null path', async () => {
  const { defaultDeps } = await import('./think.ts');
  _resetEmbedClientForTest();
  const d = defaultDeps(admin, 'public_site', { gte: 'remote', embedTimeoutMs: 3000 });
  const v = await withFetch(() => { throw new DOMException('Signal timed out.', 'TimeoutError'); }, () => d.embed('ZZ DEMO price?', 'gte'));
  assertEquals(v, null);
  assertEquals(d.embedFailure?.('ZZ DEMO price?', 'gte'), 'embed_ml_timeout_3000ms');
  _resetEmbedClientForTest();
  const other = defaultDeps(admin, 'resilience_ping', { gte: 'remote' });
  await withFetch(() => { throw new DOMException('Signal timed out.', 'TimeoutError'); }, () => other.embed('ZZ DEMO q', 'gte'));
  assertEquals(other.embedFailure?.('ZZ DEMO q', 'gte'), 'embed_ml_timeout_8000ms', 'every other caller keeps 8 s');
  _resetEmbedClientForTest();
});

Deno.test('embed_ml down costs one timeout per worker, not one per text: the next calls return at once', async () => {
  _resetEmbedClientForTest();
  let hops = 0; const whys: string[] = [];
  const t0 = Date.now();
  await withFetch(async () => { hops++; await new Promise((r) => setTimeout(r, 50)); throw new DOMException('Signal timed out.', 'TimeoutError'); }, async () => {
    // the learning tick's shape: eight lessons embedded one after another
    for (let i = 0; i < 8; i++) await embedGteRemote(admin, 'ZZ DEMO lesson ' + i, 'resilience_ping', 8000, (w) => whys.push(w));
  });
  assertEquals(hops, 1, 'only the first call reached embed_ml');
  assertEquals(whys[0], 'embed_ml_timeout_8000ms');
  assert(whys.slice(1).every((w) => w.startsWith('embed_ml_cooling_off')), J(whys));
  assert(Date.now() - t0 < 1000, 'the seven others cost nothing');
  assert(EMBED_COOL_MS <= 60_000, 'a cool-off shorter than a tick, so the next tick asks again');
});

Deno.test('a per-text refusal from embed_ml opens nothing: the next text is still asked', async () => {
  _resetEmbedClientForTest();
  let hops = 0;
  await withFetch(() => { hops++; return new Response(JSON.stringify({ ok: false, error: 'embed_failed' }), { status: 503 }); }, async () => {
    await embedGteRemote(admin, 'ZZ DEMO a', 'resilience_ping', 8000);
    await embedGteRemote(admin, 'ZZ DEMO b', 'resilience_ping', 8000);
  });
  assertEquals(hops, 2);
});
