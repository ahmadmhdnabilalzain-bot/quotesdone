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

// AUDIT 9.5 / WI-001 (4 Aug 2026) ----------------------------------------------------------------
// This module was the shared secret's largest consumer and it was in neither the D3 nor the D5 hop
// inventory. Both inventories were built by reading each function's own fetch() calls; this hop is
// inside a shared module, so all 32 importers authenticated to ai_gateway with sec('inbound_secret')
// and none of them ever presented a scoped credential. legacy.shared's use_count was 379 and still
// rising when this was found.
//
// It also made the pencilled 10 Aug withdrawal of inbound_secret a platform-wide outage that would
// have produced no error anywhere. A withdrawn credential returns 403; the code below reads the
// body, finds no `content`, and returns `null` - which is this module's documented contract for
// "the model legitimately declined". Every one of the 32 callers handles null by moving on. No
// exception, no agent_runs row, no page from fn_watch_failed_runs. The whole AI layer would have
// gone quiet and every monitor would have reported normal.
//
// Two changes, and the second matters more than the first:
//   1. Present cred_fn_<caller>, scoped to ai_gateway alone (migration
//      audit_95_llm_path_scoped_credentials issues one per importer).
//   2. Make an authentication refusal LOUD. A 403 or a 503 from the verifier is now written to
//      agent_runs as an error before null is returned, so the failure that would otherwise be
//      indistinguishable from a policy refusal has its own signal.
//
// The legacy fallback is deliberately KEPT. internal_auth.ts's own doctrine is that callers move
// one context at a time and the shared secret is withdrawn only once its use_count stops rising - a
// hard cutover on a path this wide, where failure is a `null`, is the exact shape of defect this
// comment describes. The fallback is recorded (below) rather than silent, because
// v_legacy_secret_users records the CALLEE (always 'ai_gateway') and so cannot name which importer
// is still on it. Without this row the watch that gates the withdrawal would be blind.
const AUTH_SIGNAL_MIN = 30;   // one agent_runs row per signal per caller per 30 minutes
async function logAuth(signal: string, fnName: string, status: string, note: string) {
  try {
    const since = new Date(Date.now() - AUTH_SIGNAL_MIN * 60000).toISOString();
    const { data } = await _admin.from('agent_runs').select('id').eq('agent', 'llm_gateway_auth')
      .gte('started_at', since).eq('counts->>signal', signal).eq('counts->>fn', fnName).limit(1);
    if (data && data.length) return;
    await _admin.from('agent_runs').insert({
      agent: 'llm_gateway_auth', status, counts: { signal, fn: fnName },
      note: note.slice(0, 500), started_at: new Date().toISOString(), finished_at: new Date().toISOString(),
    });
  } catch (_e) { /* never let logging block a model call */ }
}

/** The credential this caller should present to ai_gateway, scoped first, legacy fallback second. */
async function gatewayCredential(fnName: string): Promise<string> {
  const scoped = fnName && fnName !== 'unknown' ? await sec('cred_fn_' + fnName) : '';
  if (scoped) return scoped;
  const legacy = await sec('inbound_secret');
  if (legacy) {
    await logAuth('legacy_fallback', fnName, 'error',
      'llm.ts fell back to the shared inbound_secret for ' + fnName + ' because app_secrets.cred_fn_' +
      fnName + ' is missing or empty. The shared secret cannot be withdrawn while this row keeps appearing, ' +
      'and v_legacy_secret_users cannot name this caller because it records the callee (ai_gateway).');
  }
  return legacy;
}

export function makeLlm(models: string[] = SONNET_FIRST, def: LlmDefaults = {}) {
  const dMax = def.max ?? 700;
  const dTo = def.timeoutMs ?? 25000;
  const fnName = def.fn || guessFn();

  // sysStable is the fourth argument on purpose: the three-argument signature is what 31 call
  // sites use and none of them need editing. A caller that knows which half of its system prompt
  // is byte-stable between calls passes it here, and ai_gateway marks ONLY that half cacheable.
  // Passing a prefix that is not actually stable is worse than passing none: a cache write costs
  // 1.25x the input rate and a prefix that never repeats never earns it back.
  return async function llm(sys: string, input: string | Msg[], max: number = dMax, sysStable = ''): Promise<string | null> {
    const ac = new AbortController();
    const to = setTimeout(() => ac.abort(), dTo + 5000); // gateway has its own 25s per attempt
    try {
      const secret = await gatewayCredential(fnName);
      if (!secret) {
        await logAuth('no_credential', fnName, 'error',
          fnName + ' has neither app_secrets.cred_fn_' + fnName + ' nor inbound_secret, so it cannot ' +
          'authenticate to ai_gateway and every model call from it returns null.');
        return null;
      }

      const r = await fetch(GATEWAY, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          __secret: secret,
          fn: fnName,
          task_class: def.taskClass ?? null,
          dept: def.dept ?? null,
          agent: def.agent ?? null,
          sys, sys_stable: sysStable, input, max,
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

      // AUDIT 9.5. THE FAILURE THAT LOOKED LIKE A POLICY DECISION. Everything below still returns
      // null, because 32 call sites depend on that contract and changing it is a separate job. What
      // changes is that a refusal to AUTHENTICATE now leaves a row. Before this, revoking the
      // credential returned 403, fell through to `typeof j.content === 'string'` -> null, and was
      // indistinguishable from the gateway deciding not to call a model. Both counted as "the model
      // said nothing" and neither reached a monitor.
      if (r.status === 403 || r.status === 401) {
        await logAuth('gateway_forbidden', fnName, 'error',
          'ai_gateway REFUSED the credential presented by ' + fnName + ' (HTTP ' + r.status + ', ' +
          String(j?.error || 'forbidden') + '). Every model call from this function is returning null and its ' +
          'callers cannot tell that apart from a deliberate refusal. Check internal_credential_audit for the reason.');
        return null;
      }
      if (r.status === 503 && j?.error === 'credential_check_unavailable') {
        await logAuth('verifier_unavailable', fnName, 'error',
          'ai_gateway could not reach the credential verifier for ' + fnName + ', so the call was refused ' +
          'rather than allowed. Model calls are failing closed - correct, but silent to the caller.');
        return null;
      }
      if (!r.ok && !j) {
        await logAuth('gateway_error', fnName, 'error',
          'ai_gateway returned HTTP ' + r.status + ' with no JSON body for ' + fnName + '.');
        return null;
      }
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
