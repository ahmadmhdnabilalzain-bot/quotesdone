// email_triage's classification never reads another mail's verdict from ai_gateway's cache (28 Oct 2026, supplier-journey
// audit). Replays what the binding sends: the gateway request must carry cache_ttl_min 0, the per-call opt-out ai_gateway
// honours before model_policy's 1440 minutes for intent_detection. The fetch is replaced; no network.
import { assertEquals } from 'jsr:@std/assert';

Deno.env.set('SUPABASE_URL', 'https://zz-demo.example.invalid');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-key');
const { makeLlm, SONNET_FIRST } = await import('../_shared/llm.ts');
const { TRIAGE_LLM } = await import('./triage_llm.ts');

async function gatewayBody(run: () => Promise<unknown>): Promise<Record<string, unknown>> {
  const real = globalThis.fetch; let body: Record<string, unknown> = {};
  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
    const url = String(input instanceof Request ? input.url : input);
    if (url.includes('/functions/v1/ai_gateway')) {
      body = JSON.parse(String(init?.body || '{}'));
      return Promise.resolve(new Response(JSON.stringify({ ok: true, content: '{"category":"other","summary":"ZZ DEMO","reply":""}', model: 'm' }), { status: 200, headers: { 'Content-Type': 'application/json' } }));
    }
    if (url.includes('/rest/v1/app_secrets')) return Promise.resolve(new Response(JSON.stringify({ value: 'zz-demo-cred' }), { status: 200, headers: { 'Content-Type': 'application/json' } }));
    return Promise.resolve(new Response('[]', { status: 201, headers: { 'Content-Type': 'application/json' } }));
  }) as typeof fetch;
  try { await run(); return body; } finally { globalThis.fetch = real; }
}

Deno.test('the triage binding opts out of the cache: every mail is classified on its own words', async () => {
  assertEquals(TRIAGE_LLM.cacheTtlMin, 0);
  const sent = await gatewayBody(() => makeLlm(SONNET_FIRST, TRIAGE_LLM)('triage system prompt', 'From: delivered+qd-zzdemo-sup0@resend.dev\nSubject: Re: A question about your aluminium work\n\nPlease remove me / stop', 800));
  assertEquals(sent.cache_ttl_min, 0);
});

Deno.test('control: without the opt-out the request defers to model_policy (no cache_ttl_min key), which is what replayed the verdicts', async () => {
  const sent = await gatewayBody(() => makeLlm(SONNET_FIRST, { max: 700 })('triage system prompt', 'ZZ DEMO mail', 800));
  assertEquals('cache_ttl_min' in sent, false);
});

Deno.test('index.ts binds its triage call to TRIAGE_LLM', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  assertEquals(src.includes('makeLlm(SONNET_FIRST, TRIAGE_LLM)'), true);
});
