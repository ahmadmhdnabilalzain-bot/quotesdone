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

// V3 REMEDIATION (14 Aug 2026) — WHY THIS FILE GREW A SECOND ENTRY POINT.
//
// The first independent certification (V3-COR-0A782DA90B10) recorded two runtime facts that both
// terminate in this module, and neither is a model weakness:
//
//   TOOL_NOT_CONNECTED, 2,284 of 2,284 questions. ai_gateway has supported OpenAI-shape tool
//   calling since it was written - it accepts `tools`/`tool_choice`, forwards them to OpenRouter,
//   routes to a tools-capable model, and returns `tool_calls` on the way back. Exactly one edge
//   function ever used it. Every other caller reaches the gateway THROUGH THIS FILE, and this file
//   had no `tools` field in its request body and ended with
//       return typeof j.content === 'string' ? j.content : null;
//   which discards `tool_calls` even when the gateway returns them. The agents were not failing to
//   use tools; they were structurally unable to hold one.
//
//   OUTPUT_CONTRACT_ERROR, 135 truncations, 100% of them on the large tier used for consequential
//   work. The gateway detects truncation precisely - it returns `finish_reason` and
//   `truncated: finishReason === 'length'` - and the same one-line return above threw both away.
//   A truncated answer arrived at 31 call sites as an ordinary string with its ending missing, and
//   nothing downstream could tell it apart from a complete one.
//
// The public 3-arg contract is deliberately UNCHANGED: makeLlm still returns string | null and not
// one of the existing call sites needs editing. makeLlmRich exposes the envelope the gateway was
// always sending, so a caller that needs tools or needs to fail closed on truncation can have both.
export type ToolCall = { id: string; type?: string; function: { name: string; arguments: string } };
export interface LlmResult {
  content: string | null;
  message: any | null;         // full assistant message, for tool-loop replay
  tool_calls: ToolCall[];
  finish_reason: string | null;
  truncated: boolean;          // finish_reason === 'length' — the answer LOST ITS ENDING
  used_llm: boolean;
  http_status: number;
  error: string | null;        // set when the call failed; distinguishes refusal from breakage
}
export interface LlmCallOpts {
  tools?: any[];               // OpenAI-shape function definitions
  toolChoice?: any;
  messages?: any[];            // full OpenAI array; required to replay assistant tool_calls verbatim
}
const EMPTY = (e: string | null, status = 0, used = true): LlmResult =>
  ({ content: null, message: null, tool_calls: [], finish_reason: null, truncated: false, used_llm: used, http_status: status, error: e });

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

/**
 * Rich client. Returns the whole gateway envelope: content, the assistant message (so a tool loop
 * can replay it), tool_calls, finish_reason and truncated. Never throws.
 *
 * Callers that need tools or truncation-awareness use this. Everything else keeps using makeLlm,
 * which is a narrowing wrapper around it and is byte-compatible with the old contract.
 */
export function makeLlmRich(models: string[] = SONNET_FIRST, def: LlmDefaults = {}) {
  const dMax = def.max ?? 700;
  const dTo = def.timeoutMs ?? 25000;
  const fnName = def.fn || guessFn();

  // sysStable is the fourth argument on purpose: the three-argument signature is what 31 call
  // sites use and none of them need editing. A caller that knows which half of its system prompt
  // is byte-stable between calls passes it here, and ai_gateway marks ONLY that half cacheable.
  // Passing a prefix that is not actually stable is worse than passing none: a cache write costs
  // 1.25x the input rate and a prefix that never repeats never earns it back.
  return async function llmRich(sys: string, input: string | Msg[], max: number = dMax, sysStable = '', opts: LlmCallOpts = {}): Promise<LlmResult> {
    const ac = new AbortController();
    const to = setTimeout(() => ac.abort(), dTo + 5000); // gateway has its own 25s per attempt
    try {
      const secret = await gatewayCredential(fnName);
      if (!secret) {
        await logAuth('no_credential', fnName, 'error',
          fnName + ' has neither app_secrets.cred_fn_' + fnName + ' nor inbound_secret, so it cannot ' +
          'authenticate to ai_gateway and every model call from it returns null.');
        return EMPTY('no_credential');
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
          // THE GATEWAY ASKED FOR THIS AND NOBODY THROUGH THIS MODULE EVER SENT IT (11 Aug 2026).
          //
          // ai_gateway computes its wall as `declared > 5000 ? max(declared - 3000, 8000) : 55000`
          // and its own comment states the design: "Guessing the caller's patience is the mistake.
          // The caller knows it, so the caller declares it via client_timeout_ms." Only
          // quote_compare and quote_extract ever declared it. Every one of the 31 call sites that
          // goes through makeLlm got the 55,000 ms default instead of its own timeoutMs.
          //
          // agent_brain sets timeoutMs: 70000 and says why in its own header - "70s sits above the
          // gateway's 55s wall and below cos_execute's 75s patience". It was above a wall the
          // gateway never raised. Measured on production: 28 agent_brain calls failed with 0 prompt
          // tokens, 0 output tokens and latency 50,523-55,596 ms across ceo, it, brief, followup and
          // rfq_qualification_mgr - the gateway aborting at 55s while the caller would have waited
          // 70 and cos_execute 75. A successful call on the same path took 34,675 ms.
          //
          // IT DECLARES dTo + 5000, NOT dTo, AND THE 5000 IS THE POINT. This module aborts at
          // `dTo + 5000` (see the setTimeout above), so that - not dTo - is the caller's real
          // patience. Declaring dTo would set the gateway's wall to dTo-3000 = 22s on the 25s
          // default while this module still waits 30s, and every call that currently lands between
          // 22s and 30s would start failing. Declaring the true abort point makes the wall 27s
          // there: strictly inside the client, strictly longer than anything that works today, so
          // no existing successful call is cut. agent_brain goes from a 55s wall to 72s.
          client_timeout_ms: dTo + 5000,
          temperature: def.temperature ?? null,
          confidence: def.confidence ?? null,
          // THE SAME `?? 0` BUG, ONE LAYER UP (fixed 11 Aug 2026).
          //
          // ai_gateway was corrected on 9 Aug to fall back to model_policy.cache_ttl_min when the
          // caller supplies nothing, and its comment records the intent: "the caller keeps the
          // override and keeps precedence, which is what lets a call site that knows its own
          // request is unrepeatable pass 0 and opt out."
          //
          // This line then sent an explicit 0 for EVERY caller. `0 ?? route.cache_ttl_min` is 0 —
          // ?? only falls through on null/undefined, and 0 is neither. So every call through this
          // module took the deliberate opt-out path without any binding asking for it, and the
          // policy default it was supposed to inherit never applied. Measured 11 Aug: llm_cache
          // held 1 row and 2 hits against 1,642 calls in seven days, with a cache_ttl_min set on
          // all 61 model_policy rows.
          //
          // Omitting the key is the whole fix. A binding that genuinely wants to opt out still
          // sets cacheTtlMin: 0 and still wins, because undefined is now the only thing that
          // defers to policy.
          ...(def.cacheTtlMin === undefined ? {} : { cache_ttl_min: def.cacheTtlMin }),
          try_faq: def.tryFaq === true,
          rate_key: def.rateKey ?? null,
          rate_limit: def.rateLimit ?? null,
          rate_window_s: def.rateWindowS ?? null,
          // The caller's ladder is recorded for audit but does not override policy.
          caller_ladder: models,
          // TOOLS. The gateway has always accepted these three; nothing that reached it through
          // this module ever sent them. `tools` makes fn_ai_route require a tools-capable model
          // (inferCaps), and want_message asks for the assistant message back intact so a loop can
          // replay `assistant(tool_calls)` -> `tool(result)` verbatim on the next turn. `messages`
          // is how that replay is delivered: the gateway prefers it over sys+input.
          ...(opts.tools && opts.tools.length ? { tools: opts.tools, want_message: true } : {}),
          ...(opts.toolChoice != null ? { tool_choice: opts.toolChoice } : {}),
          ...(opts.messages && opts.messages.length ? { messages: opts.messages } : {}),
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
        return EMPTY('gateway_forbidden', r.status);
      }
      if (r.status === 503 && j?.error === 'credential_check_unavailable') {
        await logAuth('verifier_unavailable', fnName, 'error',
          'ai_gateway could not reach the credential verifier for ' + fnName + ', so the call was refused ' +
          'rather than allowed. Model calls are failing closed - correct, but silent to the caller.');
        return EMPTY('credential_check_unavailable', r.status);
      }
      if (!r.ok && !j) {
        await logAuth('gateway_error', fnName, 'error',
          'ai_gateway returned HTTP ' + r.status + ' with no JSON body for ' + fnName + '.');
        return EMPTY('gateway_http_' + r.status, r.status);
      }
      if (!j) return EMPTY('no_body', r.status);

      // A deterministic refusal or a budget halt is a legitimate "no", and it is NOT an error.
      // used_llm:false with no content means policy answered instead of a model. But WHICH "no" it is
      // matters to the sole caller (agent_brain, the only makeLlmRich user): a held provider
      // (paidProviderGate) fails closed HERE, with outcome 'circuit_open' and used_llm:false — the
      // exact shape that flattened to a null error, so agent_brain logged a deliberately-held model as
      // an employee error and tripped the errored-agent gate. Carry the gateway's own outcome/error
      // through so the caller can tell a hold apart from a genuine empty and record it as 'skipped'.
      if (j.used_llm === false && !j.content)
        return EMPTY(j?.outcome ? String(j.outcome) : (j?.error ? String(j.error).slice(0, 140) : null), r.status, false);

      // The envelope the gateway has always returned and this module used to throw away.
      const calls: ToolCall[] = Array.isArray(j.tool_calls) ? j.tool_calls : [];
      const fr = typeof j.finish_reason === 'string' ? j.finish_reason : null;
      return {
        content: typeof j.content === 'string' ? j.content : null,
        message: j.message ?? null,
        tool_calls: calls,
        finish_reason: fr,
        // Trust the gateway's own flag first; fall back to the reason it derives it from.
        truncated: j.truncated === true || fr === 'length',
        used_llm: j.used_llm !== false,
        http_status: r.status,
        // Preserve the gateway's own outcome/error text, not just the HTTP code. A held provider
        // (paidProviderGate) fails closed as 503 with outcome 'circuit_open' / 'every model route ...
        // is open-circuit'; flattening that to 'gateway_http_503' hid the ONE fact a caller needs to
        // tell a deliberate hold from a real breakage — so callers logged a held model as an error
        // and tripped the errored-agent gate. Appending is backward-compatible: the string still
        // starts with 'gateway_http_<status>'.
        error: !r.ok
          ? ('gateway_http_' + r.status
             + (j?.outcome ? ':' + String(j.outcome) : '')
             + (j?.error ? ':' + String(j.error).slice(0, 140) : ''))
          : null,
      };
    } catch (e) {
      // An abort here is OUR client timeout, not the model declining. Naming it matters: a prior
      // incident spent hours on "the model returned nothing" that was an 8-of-10 client abort.
      const aborted = (e as any)?.name === 'AbortError';
      return EMPTY(aborted ? 'client_timeout_' + (dTo + 5000) + 'ms' : 'client_error');
    } finally {
      clearTimeout(to);
    }
  };
}

/**
 * The original contract, unchanged: returns the response string or null, never throws.
 * 31 call sites depend on exactly this and none of them need editing.
 *
 * NOTE ON TRUNCATION. This wrapper still returns the string even when the gateway reports the
 * answer was cut at the token ceiling, because silently turning a truncated answer into null would
 * change behaviour under 31 callers that have never had to handle it. What it no longer does is
 * hide the fact: the truncation is recorded against the caller so it is visible, and any caller
 * that must fail closed on an incomplete answer uses makeLlmRich and reads `truncated`.
 */
export function makeLlm(models: string[] = SONNET_FIRST, def: LlmDefaults = {}) {
  const rich = makeLlmRich(models, def);
  const fnName = def.fn || guessFn();
  return async function llm(sys: string, input: string | Msg[], max?: number, sysStable = ''): Promise<string | null> {
    let res = await rich(sys, input, max as number, sysStable);

    // ONE CONTROLLED REPAIR, THEN FAIL CLOSED (14 Aug 2026).
    //
    // This used to log the truncation and RETURN THE TRUNCATED STRING anyway - as its own comment
    // said: "nothing downstream can detect it". Measured under Gate B of the Agent Runtime
    // Connection Blueprint: 12 of 60 routed employee calls (20%) finished with
    // finish_reason=length, and every one of those half-sentences was handed to a caller that
    // believed it had a complete answer. Raising the ceiling from 1000 to 2000 took it to 4 of 33
    // (12%) - better, and still not zero, because the p90 stays pinned at whatever the ceiling is.
    // A censored distribution cannot be fixed by moving the censor.
    //
    // OUTPUT_AND_TRUNCATION_POLICY.md is explicit: never execute a truncated consequential output,
    // and permit at most one controlled repair call by default. So: ask once more, explicitly for
    // a shorter answer, and if that is still cut off return null rather than a fragment.
    if (res.truncated) {
      await logAuth('output_truncated', fnName, 'warn',
        fnName + ' received a TRUNCATED model answer (finish_reason=length); retrying once with an '
        + 'explicit brevity instruction before failing closed.');
      const brief = sys
        + '\n\nIMPORTANT: your previous answer was cut off by the output limit. Answer the same '
        + 'question again, complete, and materially shorter. Lead with the decision or the refusal. '
        + 'Omit preamble, restatement and worked reasoning.';
      res = await rich(brief, input, max as number, sysStable);
    }

    if (res.truncated) {
      // Deliberately distinct from "the model declined": a refusal is a decision, a fragment is
      // not. The caller still receives null on the string contract, but the ledger says which.
      await logAuth('output_truncated_failed_closed', fnName, 'error',
        fnName + ' returned NO ANSWER: the model answer was still truncated after one repair '
        + 'attempt, so the fragment was withheld rather than passed off as a complete answer. '
        + 'Reduce the prompt/context for this caller, or move it to makeLlmRich and handle '
        + 'result.truncated explicitly.');
      return null;
    }

    return res.content;
  };
}
