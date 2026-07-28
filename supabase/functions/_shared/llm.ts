// _shared/llm.ts — canonical OpenRouter client for QuotesDone edge functions.
// One source for the transport + model fallback loop + 25s abort timeout (OS-audit H9, generalised).
// Callers bind a ladder via makeLlm(LADDER); existing call sites `llm(sys, input, max)` keep working.
//
// AI COST GOVERNOR (added 27 Jul 2026). Every call now, without any change to existing call sites:
//   1. asks fn_select_model() which model this task class should use, and whether it should use one at all
//   2. serves from llm_cache when the caller opts in with cacheTtlMin
//   3. records model, why that model, tokens, latency, AED cost and whether something cheaper would have
//      done the job, via fn_llm_log(), which also debits the department budget
// Governance is fail-open BY DESIGN: if logging or routing is unavailable the model call still happens.
// A broken meter must never take the business offline. Missing rows show up as gaps in ai_cost_log.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const _admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

export async function sec(k: string){ const { data } = await _admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }

export const OPUS_FIRST   = ['anthropic/claude-opus-4.8', 'anthropic/claude-sonnet-5'];
export const SONNET_FIRST = ['anthropic/claude-sonnet-5', 'anthropic/claude-opus-4.8'];

export type Msg = { role: string; content: string };
export interface LlmDefaults {
  max?: number;
  timeoutMs?: number;
  temperature?: number;
  // ---- cost governor (all optional; omit and behaviour is exactly as before, plus logging) ----
  fn?: string;          // which edge function is spending. Defaults to the function directory name.
  dept?: string;        // department that owns the spend, e.g. 'knowledge'. Debits department_budget.
  agent?: string;       // employee making the call, e.g. 'cat:hvac-suppliers'.
  taskClass?: string;   // model_policy.task_class. When set, fn_select_model() picks the model.
  confidence?: number;  // caller's confidence; low confidence may escalate the tier.
  cacheTtlMin?: number; // > 0 enables the response cache for this binding. Use for stable lookups only.
}

// Best-effort function name for attribution when the caller does not pass one.
function guessFn(): string {
  try {
    const m = (new Error().stack || '').match(/functions\/([A-Za-z0-9_-]+)\//g) || [];
    for (const seg of m) { const name = seg.split('/')[1]; if (name && name !== '_shared') return name; }
  } catch (_e) { /* attribution is optional */ }
  return 'unknown';
}

async function sha256(s: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

// Bind a model ladder → returns llm(sys, input, max?) with the QuotesDone fallback loop + abort timeout.
export function makeLlm(models: string[] = SONNET_FIRST, def: LlmDefaults = {}){
  const dMax = def.max ?? 700, dTo = def.timeoutMs ?? 25000;
  const fnName = def.fn || guessFn();

  return async function llm(sys: string, input: string | Msg[], max: number = dMax): Promise<string | null> {
    const started = Date.now();
    const key = await sec('openrouter_api_key'); if (!key) return null;
    const msgs: Msg[] = typeof input === 'string' ? [{ role: 'user', content: input }] : input;

    // ---- 1. ROUTING: does this task class need a model at all, and which one? ----
    let ladder = models, tier: string | null = null, because = 'caller ladder (no task_class supplied)';
    if (def.taskClass) {
      try {
        const { data: pick } = await _admin.rpc('fn_select_model', {
          p_task_class: def.taskClass, p_dept_key: def.dept ?? null, p_confidence: def.confidence ?? null });
        if (pick) {
          because = String(pick.why || '');
          tier = pick.tier ?? null;
          if (pick.use_llm === false) {
            // The policy says code should decide this, not a model. Refuse and say so in the log.
            try { await _admin.rpc('fn_llm_log', {
              p_fn: fnName, p_dept: def.dept ?? null, p_agent: def.agent ?? null, p_task_class: def.taskClass,
              p_model: 'none', p_because: because, p_tier: 'none', p_prompt_tokens: 0, p_output_tokens: 0,
              p_cached: false, p_cache_key: null, p_latency_ms: Date.now() - started, p_ok: true }); } catch (_e) { /* meter is optional */ }
            return null;
          }
          if (pick.model) ladder = [pick.model, ...models.filter((m) => m !== pick.model)];
          if (pick.max_tokens && pick.max_tokens > 0) max = Math.min(max, Number(pick.max_tokens));
        }
      } catch (_e) { /* routing unavailable → fall through to the caller's ladder */ }
    }

    // ---- 2. CACHE: identical prompt on the same model, inside the TTL, costs nothing ----
    let cacheKey: string | null = null;
    if (def.cacheTtlMin && def.cacheTtlMin > 0) {
      try {
        cacheKey = await sha256([ladder[0], String(max), sys, JSON.stringify(msgs)].join(' '));
        const { data: hit } = await _admin.rpc('fn_llm_cache_get', { p_key: cacheKey });
        if (hit) {
          try { await _admin.rpc('fn_llm_log', {
            p_fn: fnName, p_dept: def.dept ?? null, p_agent: def.agent ?? null, p_task_class: def.taskClass ?? null,
            p_model: ladder[0], p_because: 'cache hit', p_tier: tier, p_prompt_tokens: 0, p_output_tokens: 0,
            p_cached: true, p_cache_key: cacheKey, p_latency_ms: Date.now() - started, p_ok: true }); } catch (_e) { /* meter is optional */ }
          return String(hit);
        }
      } catch (_e) { cacheKey = null; }
    }

    // ---- 3. THE CALL (unchanged transport: ladder, two attempts each, hard abort) ----
    const base: Record<string, unknown> = { max_tokens: max, messages: [{ role: 'system', content: sys }, ...msgs] };
    if (def.temperature != null) base.temperature = def.temperature;

    for (const model of ladder){
      for (let at = 0; at < 2; at++){
        const ac = new AbortController(); const to = setTimeout(() => ac.abort(), dTo);
        const t0 = Date.now();
        try {
          const r = await fetch('https://openrouter.ai/api/v1/chat/completions', {
            method: 'POST', headers: { 'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json' },
            body: JSON.stringify({ ...base, model }), signal: ac.signal });
          const j = await r.json(); const c = j?.choices?.[0]?.message?.content;
          if (c) {
            const u = j?.usage || {};
            try { await _admin.rpc('fn_llm_log', {
              p_fn: fnName, p_dept: def.dept ?? null, p_agent: def.agent ?? null, p_task_class: def.taskClass ?? null,
              p_model: model, p_because: because + (model !== ladder[0] ? ' [fell back from ' + ladder[0] + ']' : ''),
              p_tier: tier, p_prompt_tokens: Number(u.prompt_tokens ?? 0), p_output_tokens: Number(u.completion_tokens ?? 0),
              p_cached: false, p_cache_key: cacheKey, p_latency_ms: Date.now() - t0, p_ok: true }); } catch (_e) { /* meter is optional */ }
            if (cacheKey) { try { await _admin.rpc('fn_llm_cache_put', {
              p_key: cacheKey, p_fn: fnName, p_task_class: def.taskClass ?? null, p_model: model,
              p_response: c, p_ttl_minutes: def.cacheTtlMin }); } catch (_e) { /* cache is optional */ } }
            return c;
          }
        } catch (_e) { /* try next attempt / model */ } finally { clearTimeout(to); }
      }
    }

    // Every model on the ladder failed. Record it: silent LLM failure is how 68% failure rates hide.
    try { await _admin.rpc('fn_llm_log', {
      p_fn: fnName, p_dept: def.dept ?? null, p_agent: def.agent ?? null, p_task_class: def.taskClass ?? null,
      p_model: ladder[0], p_because: because + ' [all models on the ladder failed]', p_tier: tier,
      p_prompt_tokens: 0, p_output_tokens: 0, p_cached: false, p_cache_key: cacheKey,
      p_latency_ms: Date.now() - started, p_ok: false }); } catch (_e) { /* meter is optional */ }
    return null;
  };
}
