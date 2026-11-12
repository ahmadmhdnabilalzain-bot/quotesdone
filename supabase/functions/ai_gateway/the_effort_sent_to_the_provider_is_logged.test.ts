// THE EFFORT SENT TO THE PROVIDER IS THE EFFORT LOGGED (it_engineer, 12 Nov 2026; founder ledger 1642; final audit 2026-11-12
// section 3, E7: "effort is recorded nowhere", and the diagnosis could not confirm the value reaches the provider request).
// Loads ai_gateway/index.ts's own handler (_shared/twilio_free_harness.ts) with a stub where https://openrouter.ai is, and
// reads the request the provider received and the fn_llm_log row the gateway wrote for it: no network, no paid call.
//   - a call that names no effort: its class's (effort_policy.ts EFFORT_BY_CLASS) reaches the provider as reasoning.effort;
//   - a caller's explicit effort on a conversation class reaches it unchanged ('low' on customer_communication);
//   - a 'low' on a class that decides is raised before it is sent (ruling 1630);
//   - every one is on ai_cost_log.model_selected_because as ' | effort sent: <value>', the failed attempt's row included.
//   DENO_NO_PACKAGE_JSON=1 deno test --no-lock --node-modules-dir=auto -A supabase/functions/ai_gateway/the_effort_sent_to_the_provider_is_logged.test.ts
import { assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import { invoke, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';

const J = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });
const MODEL = 'anthropic/claude-sonnet-5.5';
let route: Record<string, unknown> = {};
const logs: Record<string, unknown>[] = [];
const stub: Stub = {
  handle: async (req, u) => {
    const rpc = u.pathname.match(/^\/rest\/v1\/rpc\/(.+)$/)?.[1] ?? null;
    const body = req.method === 'POST' ? await req.clone().json().catch(() => null) : null;
    if (rpc === 'fn_internal_auth') return J({ ok: true, context: 'fn.support_reply', credential_id: 7, legacy: false });
    if (rpc === 'fn_ai_route') return J(route);
    if (rpc === 'fn_kernel_paid_provider_gate') return J({ allowed: true, rule: 'registered_breaker_closed' });
    if (rpc === 'fn_llm_cache_lookup') return J({ hit: false });
    if (rpc === 'fn_model_cost_usd') return J(0.0001);
    if (rpc === 'fn_llm_log') { logs.push(body ?? {}); return J(null); }
    if (u.pathname === '/rest/v1/app_secrets') {
      const value = 'zz-stub-secret-0123456789abcdef0123';
      return (req.headers.get('accept') || '').includes('vnd.pgrst.object') ? J({ value }) : J([{ value }]);
    }
    return undefined;
  },
};
const sent: Record<string, unknown>[] = [];
let fail = false;
const handler = await loadFunction('ai_gateway', () => import('./index.ts'));
const viaHarness = globalThis.fetch;
globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
  const req = input instanceof Request ? input : new Request(String(input), init);
  const u = new URL(req.url);
  if (u.hostname === 'openrouter.ai') {
    if (u.pathname === '/api/v1/models') return J({ data: [] });
    sent.push(JSON.parse(await req.clone().text()));
    if (fail) return J({ error: { code: 400, message: 'ZZ DEMO bad request' } }, 400);
    return J({ id: 'gen-zz', choices: [{ index: 0, message: { role: 'assistant', content: '{"answer":"ZZ DEMO ok"}' }, finish_reason: 'stop' }], usage: { prompt_tokens: 100, completion_tokens: 10, cost: 0.0001 } });
  }
  return viaHarness(input, init);
}) as typeof fetch;

async function call(taskClass: string, effort: string | null, failing = false) {
  route = { model: MODEL, fallback: null, tier: 'mid', task_class: taskClass, use_llm: true, max_tokens: 300, why: 'policy: ' + taskClass, cache: false, cache_ttl_min: 0 };
  sent.length = 0; logs.length = 0; fail = failing;
  await invoke(handler, stub, { __secret: 'zz-cred-0123456789abcdef0123', fn: 'support_reply', task_class: taskClass, sys: 'ZZ DEMO rules', input: 'ZZ DEMO question', max: 300, client_timeout_ms: 30000, ...(effort ? { effort } : {}) });
  return { sentEffort: (sent[0]?.reasoning as { effort?: string } | undefined)?.effort ?? null, because: logs.map((l) => String(l.p_because ?? '')) };
}

Deno.test('a call that names no effort: the class effort reaches the provider and is on the logged row', async () => {
  const r = await call('internal_judgement', null);
  assertEquals(r.sentEffort, 'high');
  assertStringIncludes(r.because.at(-1)!, ' | effort sent: high');
});

Deno.test("a caller's low on a conversation class is sent as low; a low on a deciding class is raised to high", async () => {
  const conv = await call('customer_communication', 'low');
  assertEquals(conv.sentEffort, 'low');
  assertStringIncludes(conv.because.at(-1)!, ' | effort sent: low');
  const dec = await call('quote_comparison', 'low');
  assertEquals(dec.sentEffort, 'high');
  assertStringIncludes(dec.because.at(-1)!, ' | effort sent: high');
});

Deno.test('a failed attempt carries the effort it was sent with', async () => {
  const r = await call('internal_judgement', 'medium', true);
  assertEquals(r.sentEffort, 'medium');
  assertEquals(r.because.length > 0 && r.because.every((b) => b.includes(' | effort sent: medium') || !b.includes('FAILED ATTEMPT')), true, JSON.stringify(r.because));
});
