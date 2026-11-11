// A REVIEW ROUTE CACHES BY THE MODEL IT CALLS (it_engineer, 11 Nov 2026; prompt diet, docs/reports/2026-11-11-prompt-diet.md).
// fn_ai_route_review_for builds its answer on fn_ai_route for the class (v_base) and replaces only the MODEL: 'cache' stays
// the base route's, which is its primary's model_registry.supports_cache. A conversation_reply whose primary is Luna Pro
// (supports_cache false) and whose counterpart pick is Sonnet 5.5 (supports_cache true) was therefore sent to Sonnet as one
// plain string. Measured, ai_cost_log, 10 Nov 15:58-16:06 UTC: 20 Sonnet 5.5 calls (fn sales_engineer, counterpart Luna Pro),
// 32.7-36.2k prompt tokens each, the same ~33k-token brief prefix, 0 tokens read from the cache and 0 written; AED 5.45.
// The reverse is wrong too: an Anthropic-primary class whose pick is another family would be sent Anthropic cache_control.
// So, for a counterpart call, the flag is the CALLED model's own supports_cache. Without a counterpart nothing changes, and a
// model_registry read that fails keeps the route's flag (the behaviour before this file).
// Switch: prompt_diet 'review_route_caches_by_the_model_it_calls' (structural, ON; _shared/prompt_diet.ts).
// prevented by: ai_gateway/route_cache.test.ts

export type SupportsCache = (model: string) => Promise<boolean | null>;

/** Whether the provider call is sent with cache breakpoints, given the route, the counterpart and the switch. */
export async function cacheOfTheCalledModel(route: { cache?: unknown; model?: unknown }, counterpart: string | null, on: boolean, supports: SupportsCache): Promise<boolean> {
  const before = route.cache === true;
  if (!on || !counterpart || typeof route.model !== 'string' || !route.model) return before;
  const v = await supports(route.model).catch(() => null);
  return v === null ? before : v;
}

const SUPPORTS_TTL_MS = 10 * 60_000;
const seen = new Map<string, { at: number; v: Promise<boolean | null> }>();
/** model_registry.supports_cache for `model`, kept per worker for 10 minutes; null when it cannot be read. */
// deno-lint-ignore no-explicit-any
export function registrySupportsCache(admin: { from: (t: string) => any }): SupportsCache {
  return (model: string) => {
    const now = Date.now(); const hit = seen.get(model);
    if (hit && now - hit.at < SUPPORTS_TTL_MS) return hit.v;
    const v = (async () => {
      try {
        const { data, error } = await admin.from('model_registry').select('supports_cache').eq('model_id', model).maybeSingle();
        return error || !data || typeof data.supports_cache !== 'boolean' ? null : data.supports_cache as boolean;
      } catch (_e) { return null; }
    })();
    seen.set(model, { at: now, v });
    return v;
  };
}
