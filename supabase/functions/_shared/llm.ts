// _shared/llm.ts — thin client for ai_gateway.
//
// The public API is UNCHANGED on purpose: makeLlm(ladder, defaults) still returns
// llm(sys, input, max), so not one of the 31 call sites needs editing. What changed is where
// the decision is made.
//
// BEFORE: this file talked to OpenRouter directly and asked fn_select_model for a model only
// when the caller passed taskClass. No caller ever did, so across 143 logged calls task_class
// was null 100% of the time. That meant no policy, no token caps, no cheap tier, no cache, and
// a budget halt that could never fire. The model was whatever ladder each function hardcoded,
// which is why everything ran on Sonnet or Opus.
//
// NOW: every call goes to ai_gateway, which classifies by CALLING FUNCTION NAME via
// fn_task_class, then applies in order: rate limit, Level 0 (template/FAQ, no model at all),
// routing, deterministic refusal, budget halt, exact + semantic cache, and only then a model —
// with Anthropic prompt caching on long system prompts, which is where the money actually is
// (94% of our token spend is input).
//
// Behaviour that callers can rely on is preserved:
//   * returns the response string, or null on failure - same as before
//   * never throws
//   * the model ladder passed by the caller is now a HINT, not a command. Policy wins. That is
//     the entire point; a function should not get to pick Opus for a classification task.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const _admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const GATEWAY = Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway';

export async function sec(k: string) {
  const { data } = await _admin.from('app_secrets').select('value').eq('key', k).maybeSingle();
  return (data?.value as string) || '';
}

// Kept so existing imports keep compiling. These are now hints only - see the header.
export const OPUS_FIRST = ['anthropic/claude-opus-4.8', 'anthropic/claude-sonnet-5'];
export const SONNET_FIRST = ['anthropic/claude-sonnet-5', 'anthropic/claude-opus-4.8'];

export type Msg = { role: string; content: string };
export interface LlmDefaults {
  max?: number;
  timeoutMs?: number;
  temperature?: number;
  fn?: string;
  dept?: string;
  agent?: string;
  taskClass?: string;   // explicit class still wins over the fn -> class map
  confidence?: number;
  cacheTtlMin?: number; // > 0 enables exact + semantic caching for this binding
  tryFaq?: boolean;     // customer-facing callers: try to answer with no model first
  rateKey?: string;     // public surfaces: bucket to rate-limit on
  rateLimit?: number;
  rateWindowS?: number;
}

// Best-effort calling-function name. This is what the gateway classifies on, so it is now
// load-bearing rather than decorative.
function guessFn(): string {
  try {
    const m = (new Error().stack || '').match(/functions\/([A-Za-z0-9_-]+)\//g) || [];
    for (const seg of m) {
      const name = seg.split('/')[1];
      if (name && name !== '_shared') return name;
    }
  } catch (_e) { /* attribution is best-effort */ }
  return 'unknown';
}

export function makeLlm(models: string[] = SONNET_FIRST, def: LlmDefaults = {}) {
  const dMax = def.max ?? 700;
  const dTo = def.timeoutMs ?? 25000;
  const fnName = def.fn || guessFn();

  return async function llm(sys: string, input: string | Msg[], max: number = dMax): Promise<string | null> {
    const ac = new AbortController();
    const to = setTimeout(() => ac.abort(), dTo + 5000); // gateway has its own 25s per attempt
    try {
      const secret = await sec('inbound_secret');
      if (!secret) return null;

      const r = await fetch(GATEWAY, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          __secret: secret,
          fn: fnName,
          task_class: def.taskClass ?? null,
          dept: def.dept ?? null,
          agent: def.agent ?? null,
          sys, input, max,
          temperature: def.temperature ?? null,
          confidence: def.confidence ?? null,
          cache_ttl_min: def.cacheTtlMin ?? 0,
          try_faq: def.tryFaq === true,
          rate_key: def.rateKey ?? null,
          rate_limit: def.rateLimit ?? null,
          rate_window_s: def.rateWindowS ?? null,
          // The caller's ladder is recorded for audit but does not override policy.
          caller_ladder: models,
        }),
        signal: ac.signal,
      });

      const j = await r.json().catch(() => null);
      if (!j) return null;

      // A deterministic refusal or a budget halt is a legitimate "no". Returning null here is
      // correct and matches the old contract: callers already handle a null model response.
      if (j.used_llm === false && !j.content) return null;

      return typeof j.content === 'string' ? j.content : null;
    } catch (_e) {
      return null;
    } finally {
      clearTimeout(to);
    }
  };
}
