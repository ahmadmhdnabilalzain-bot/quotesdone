// ai_gateway — THE single AI router. Every model call in the company should come through here.
//
// WHY THIS EXISTS. Before it, ~68 edge functions called OpenRouter, 37 of them with their own
// hand-rolled fetch. Those 37 are invisible to ai_cost_log, so the company could not even see what
// it was spending, let alone control it. model_policy held 26 carefully written routing rules that
// had never executed once, because _shared/llm.ts only consults them when a caller passes taskClass
// and no caller did. The result: 100% of measured calls went to Sonnet or Opus, there was no cheap
// tier in existence, the cache had zero rows, and the budget halt was unreachable.
//
// This function is where all of that becomes real, in one place, so behaviour can change without
// redeploying 68 functions.
//
// 29 JUL 2026 — MODALITIES. The first migration wave stalled with ~33 functions still calling
// OpenRouter directly, and it was not stubbornness: the gateway could only carry plain text.
// Anything needing eyes (a scanned trade licence), ears (Arabic/English voice notes), the web
// plugin (grounded UAE research) or tool-calling (the Secretary) had nowhere to go. Rather than
// leave a third of the company's spend unmeasured, the gateway now carries all four, and
// CAPABILITY is a routing input: fn_ai_route substitutes a capable model rather than letting the
// provider reject the payload. The caller does not declare its needs - we infer them from what it
// actually sent, because a caller that has to remember a flag will eventually forget it.
//
// ORDER OF OPERATIONS — cheapest possible outcome first, every time:
//   1. rate limit        - refuse abuse before spending anything
//   2. Level 0           - templates and the approved FAQ answer with NO model at all
//   3. routing           - fn_ai_route picks the tier from the calling function or task_class,
//                          then substitutes for capability if the payload needs it
//   4. refusal           - tier='none' means deterministic code is correct; we decline
//   5. budget halt       - department over its ceiling stops non-gated work
//   6. cache             - exact hash, then SEMANTIC similarity on free in-region embeddings
//   7. the call          - with Anthropic prompt caching, a hard token cap, and a model ladder
//   8. log               - real cost from model_registry, including cache-read pricing
//
// dry_run:true runs 1-6 and returns the decision WITHOUT calling a model, so the whole thing can be
// verified for zero spend.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });

async function sec(k: string) {
  const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle();
  return (data?.value as string) || '';
}
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;

// Free, in-region. Module scope on purpose: building the session per request is exactly what killed
// kb_embed with WORKER_RESOURCE_LIMIT on 28 Jul.
// deno-lint-ignore no-explicit-any
let _emb: any = null;
// deno-lint-ignore no-explicit-any
function embedder(): any {
  // deno-lint-ignore no-explicit-any
  if (_emb === null) _emb = new (globalThis as any).Supabase.ai.Session('gte-small');
  return _emb;
}
async function embed(text: string): Promise<string | null> {
  try {
    const v = await embedder().run(String(text).slice(0, 1200), { mean_pool: true, normalize: true }) as number[];
    return '[' + v.join(',') + ']';
  } catch (_e) { return null; }  // embedding is an optimisation; never fail the call for it
}

async function sha256(s: string): Promise<string> {
  const b = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return Array.from(new Uint8Array(b)).map((x) => x.toString(16).padStart(2, '0')).join('');
}

// Anthropic bills a cached prefix at ~10% of the prompt rate but requires a minimum cacheable
// block. Below roughly 1k tokens the cache write costs more than it saves, so only mark long
// system prompts. This is the single biggest lever we have: 94% of spend is input tokens.
const CACHE_MIN_CHARS = 4000;

// supabase-js .rpc() returns a PostgrestFilterBuilder - it is thenable but NOT a Promise, so
// .catch() on it throws "admin.rpc(...).catch is not a function". Caught in dry-run testing.
// Every non-critical call (logging, cache writes) goes through here: telemetry must never be
// able to fail the business call it is describing.
async function rpcSafe(name: string, args: Record<string, unknown>) {
  try { const { data } = await admin.rpc(name, args); return data; } catch (_e) { return null; }
}

// deno-lint-ignore no-explicit-any
type Msg = { role: string; content?: any; [k: string]: unknown };

interface Body {
  __secret?: string;
  fn?: string; task_class?: string; dept?: string; agent?: string;
  sys?: string; input?: string | Msg[];
  messages?: Msg[];                       // full OpenAI-shape passthrough (multimodal, tool turns)
  max?: number; temperature?: number; confidence?: number;
  cache_ttl_min?: number; try_faq?: boolean; faq_text?: string;
  rate_key?: string; rate_limit?: number; rate_window_s?: number;
  stream?: boolean; dry_run?: boolean; escalate?: boolean;
  client_timeout_ms?: number;             // how long the caller will actually wait; the gateway finishes inside it
  action?: string; text?: string;
  // --- modalities, added 29 Jul 2026 ---
  // deno-lint-ignore no-explicit-any
  plugins?: any[];                        // OpenRouter plugins: web search, file-parser
  // deno-lint-ignore no-explicit-any
  tools?: any[];                          // OpenAI-style tool definitions
  // deno-lint-ignore no-explicit-any
  tool_choice?: any;
  // deno-lint-ignore no-explicit-any
  response_format?: any;                  // JSON mode / json_schema
  require_caps?: string[];                // override; normally inferred from the payload
  want_message?: boolean;                 // return the whole assistant message (tool_calls included)
}

// What the payload actually needs, read off the payload itself. A caller that has to declare
// "this has an image in it" will eventually forget to, and the failure mode is a provider error
// nobody can trace. Reading it here means vision/audio can never be mis-routed by omission.
// deno-lint-ignore no-explicit-any
function inferCaps(msgs: Msg[], tools?: any[]): { caps: string[]; hasBinary: boolean } {
  const caps = new Set<string>();
  let hasBinary = false;
  for (const m of msgs) {
    const c = m?.content;
    if (!Array.isArray(c)) continue;
    for (const part of c) {
      const t = String((part as Record<string, unknown>)?.type || '');
      if (t === 'image_url' || t === 'image') { caps.add('vision'); hasBinary = true; }
      else if (t === 'input_audio' || t === 'audio') { caps.add('audio'); hasBinary = true; }
      else if (t === 'file') { caps.add('vision'); hasBinary = true; }  // file-parser feeds pages to the vision path
    }
  }
  if (Array.isArray(tools) && tools.length) caps.add('tools');
  return { caps: Array.from(caps), hasBinary };
}

Deno.serve(async (req) => {
  const t0 = Date.now();
  try {
    const body = (await req.json().catch(() => ({}))) as Body;
    const inbound = await sec('inbound_secret');
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'ai_gateway');
    if (!__auth.ok) return J({ error: 'forbidden' }, 403);

    // Utility path: embed text for callers that need a vector (FAQ backfill, semantic search).
    // Free, so it never touches routing or budget.
    if (body.action === 'embed') {
      const v = await embed(String(body.text || ''));
      return J({ ok: true, embedding: v });
    }

    const fnName = String(body.fn || 'unknown');
    const dry = body.dry_run === true;

    // ---- 1. RATE LIMIT ------------------------------------------------------------------
    // Public surfaces (wa_inbound had none) must be capped before anything is spent.
    if (body.rate_key) {
      const { data: rl } = await admin.rpc('fn_rate_limit', {
        p_bucket: String(body.rate_key),
        p_limit: Number(body.rate_limit ?? 20),
        p_window_seconds: Number(body.rate_window_s ?? 3600),
      });
      if (rl && rl.allowed === false) {
        return J({ ok: true, used_llm: false, outcome: 'rate_limited', detail: rl });
      }
    }

    // ---- 2. LEVEL 0 — answer with no model at all ---------------------------------------
    // The plan's "70% should never reach AI". Templates and the 151 approved public FAQs.
    // Semantic matching included, because keyword search missed 2 of 5 realistic questions.
    if (body.try_faq) {
      const q = String(body.faq_text ?? (typeof body.input === 'string' ? body.input : '') ?? '');
      const qEmb = q.length > 2 ? await embed(q) : null;
      const { data: faq } = await admin.rpc('fn_faq_answer', {
        p_text: q, p_min_rank: 0.15, p_embedding: qEmb, p_min_similarity: 0.86,
      });
      if (faq && faq.answered === true) {
        await rpcSafe('fn_llm_log', {
          p_fn: fnName, p_dept: body.dept ?? null, p_agent: body.agent ?? null,
          p_task_class: 'level0_' + String(faq.source), p_model: 'none',
          p_because: 'Answered with no model: ' + faq.source + ' (confidence ' + faq.confidence + ')',
          p_tier: 'none', p_prompt_tokens: 0, p_output_tokens: 0, p_cached: true,
          p_cache_key: null, p_latency_ms: Date.now() - t0, p_ok: true,
        });
        return J({ ok: true, used_llm: false, outcome: 'level0', source: faq.source,
                   content: faq.answer, confidence: faq.confidence, cost_usd: 0 });
      }
    }

    // ---- MESSAGES ------------------------------------------------------------------------
    // Two shapes, one path. `messages` is the full OpenAI array and wins when present - that is
    // what a tool-calling loop needs, because it must replay assistant tool_calls and tool
    // results verbatim. `sys` + `input` remains the shorthand the 32 migrated callers use.
    const sys = String(body.sys || '');
    const explicit = Array.isArray(body.messages) ? body.messages : null;
    const convo: Msg[] = explicit
      ? explicit
      : (typeof body.input === 'string'
          ? [{ role: 'user', content: body.input }]
          : (Array.isArray(body.input) ? body.input as Msg[] : []));

    const { caps: inferred, hasBinary } = inferCaps(convo, body.tools);
    const caps = Array.isArray(body.require_caps) && body.require_caps.length
      ? Array.from(new Set([...body.require_caps, ...inferred]))
      : inferred;

    // ---- 3. ROUTE -----------------------------------------------------------------------
    const { data: route, error: rErr } = await admin.rpc('fn_ai_route', {
      p_task_class: body.task_class ?? null,
      p_dept_key: body.dept ?? null,
      p_confidence: body.confidence ?? null,
      p_fn: fnName,
      p_escalate: body.escalate === true,
      p_require_caps: caps.length ? caps : null,
    });
    if (rErr || !route) {
      return J({ ok: false, error: 'route_failed', detail: String(rErr?.message || 'no route') }, 500);
    }

    // ---- 4 & 5. REFUSALS: deterministic work, a department over budget, or no capable model ---
    if (route.use_llm === false) {
      await rpcSafe('fn_llm_log', {
        p_fn: fnName, p_dept: body.dept ?? null, p_agent: body.agent ?? null,
        p_task_class: route.task_class ?? null, p_model: 'none', p_because: route.why,
        p_tier: route.tier ?? 'none', p_prompt_tokens: 0, p_output_tokens: 0, p_cached: false,
        p_cache_key: null, p_latency_ms: Date.now() - t0, p_ok: true,
      });
      return J({ ok: true, used_llm: false,
                 outcome: route.halted ? 'budget_halted' : 'refused_deterministic',
                 why: route.why, deterministic_alternative: route.deterministic_alternative ?? null,
                 caps, cost_usd: 0 });
    }

    const model: string = route.model;
    const fallback: string | null = route.fallback ?? null;
    const maxTok = Math.min(Number(body.max ?? route.max_tokens ?? 700), Number(route.max_tokens ?? 4000));

    // ---- 6. CACHE — exact, then semantic ------------------------------------------------
    // Two things are deliberately NOT cacheable:
    //   * tool-calling turns - the stored value is text, but the useful part of the reply is the
    //     tool_calls array, and replaying a stale tool call would act on stale state;
    //   * anything with a base64 image or audio blob - the exact hash can never hit (every scan is
    //     a different blob), and the SEMANTIC path is actively dangerous, because embedding a
    //     truncated base64 string produces near-identical vectors for two unrelated documents.
    //     A 0.95 "hit" there would return another supplier's invoice. Off, on purpose.
    const cacheable = Number(body.cache_ttl_min ?? 0) > 0 && !hasBinary && !(body.tools && body.tools.length);
    let cacheKey: string | null = null;
    let promptEmb: string | null = null;
    if (cacheable) {
      cacheKey = await sha256([
        model, String(maxTok), sys, JSON.stringify(convo),
        JSON.stringify(body.plugins ?? null), JSON.stringify(body.response_format ?? null),
      ].join(' '));
      promptEmb = await embed(sys.slice(0, 400) + ' ' + JSON.stringify(convo).slice(0, 800));
      const { data: hit } = await admin.rpc('fn_llm_cache_lookup', {
        p_key: cacheKey, p_embedding: promptEmb,
        p_task_class: route.task_class ?? null, p_min_similarity: 0.95,
      });
      if (hit && hit.hit === true) {
        await rpcSafe('fn_llm_log', {
          p_fn: fnName, p_dept: body.dept ?? null, p_agent: body.agent ?? null,
          p_task_class: route.task_class ?? null, p_model: hit.model ?? model,
          p_because: hit.kind + ' cache hit (similarity ' + hit.similarity + ')',
          p_tier: route.tier ?? null, p_prompt_tokens: 0, p_output_tokens: 0, p_cached: true,
          p_cache_key: cacheKey, p_latency_ms: Date.now() - t0, p_ok: true,
        });
        return J({ ok: true, used_llm: false, outcome: 'cache_' + hit.kind,
                   content: hit.response, similarity: hit.similarity, cost_usd: 0 });
      }
    }

    // ---- DRY RUN: everything decided, nothing spent -------------------------------------
    if (dry) {
      return J({ ok: true, dry_run: true, used_llm: false, outcome: 'would_call',
                 model, fallback, tier: route.tier, task_class: route.task_class,
                 max_tokens: maxTok, prompt_cache: route.cache === true && sys.length >= CACHE_MIN_CHARS,
                 stream_ok: route.stream === true, budget_pct: route.budget_pct,
                 caps, cacheable, has_binary: hasBinary,
                 plugins: body.plugins ?? null, tools: (body.tools || []).length || 0,
                 why: route.why });
    }

    // ---- 7. THE CALL --------------------------------------------------------------------
    const key = await sec('openrouter_api_key');
    if (!key) return J({ ok: false, error: 'openrouter_api_key missing' }, 500);

    // Mark the system prompt cacheable when the model supports it and the block is big enough
    // to be worth a cache write. agent_brain's ~30k-char prefix is the target here.
    const useCache = route.cache === true && sys.length >= CACHE_MIN_CHARS;
    const sysMsg = useCache
      ? { role: 'system', content: [{ type: 'text', text: sys, cache_control: { type: 'ephemeral' } }] }
      : { role: 'system', content: sys };
    // An empty system message is not free - it is a message the provider still tokenises, and on
    // the transcribe path there is no system prompt at all. Only prepend one when it says something,
    // and never when the caller already supplied its own system turn inside `messages`.
    const hasOwnSystem = convo.some((m) => m?.role === 'system');
    const outbound: Msg[] = (sys && !hasOwnSystem) ? [sysMsg as Msg, ...convo] : convo;

    // 29 Jul 2026 - WALL DEADLINE. The ladder could run two models x two attempts x 25s, up to
    // about 100 seconds, while _shared/llm.ts abandons a plain call after 30. On 29 Jul five
    // cos_execute analyses completed at 50-60s with ok=true and 1200 output tokens each, were
    // billed, and were thrown away by a caller that had already stopped listening - then escalated
    // to the founder as "produced nothing". Paying for work and discarding it is worse than failing
    // fast, so the gateway now finishes inside the caller's patience and never starts an attempt
    // that cannot land in time. Binary and web-plugin calls get the longer budget because
    // _shared/llm.ts waits 70s for those.
    // 29 Jul 2026 (revised, same day). The first version of this hardcoded 26s for plain text and
    // immediately broke agent_brain, which legitimately takes 22-23s on a 24k-token prompt: routing
    // and embedding eat 3-4s first, so the attempt was clamped to ~22s and aborted mid-generation.
    // Guessing the caller's patience is the mistake. The caller knows it, so the caller declares it
    // via client_timeout_ms and the gateway finishes inside that, keeping a 3s margin for the reply
    // to travel back. Without a declared value we keep the previous generous behaviour rather than
    // a guess that can strand a working call.
    const declared = Number(body.client_timeout_ms || 0);
    const wallBudgetMs = declared > 5000
      ? Math.max(declared - 3000, 8000)
      : ((hasBinary || (body.plugins && body.plugins.length)) ? 55000 : 55000);
    const deadlineAt = t0 + wallBudgetMs;
    let deadlineHit = false;
    const ladder = [model, ...(fallback && fallback !== model ? [fallback] : [])];
    const wantStream = body.stream === true && route.stream === true;

    let out: string | null = null;
    // deno-lint-ignore no-explicit-any
    let outMsg: any = null;
    let used = model, usage: Record<string, number> = {}, lastErr = '';
    for (const m of ladder) {
      for (let attempt = 0; attempt < 2; attempt++) {
        // An attempt needs a few seconds to be worth starting at all.
        const msLeft = deadlineAt - Date.now();
        if (msLeft < 4000) { deadlineHit = true; break; }
        const ac = new AbortController();
        // Vision and audio payloads are large and slow; 25s is right for chat and far too tight
        // for a three-page scanned licence. Give the modality paths room rather than logging a
        // timeout that looks like a model failure.
        // 29 Jul 2026: the plain-text per-attempt cap was 25000ms while the wall budget is 55000ms,
        // so no single attempt could ever use the wall. Agent reasoning over a 14k-24k token context
        // takes 24s+ and was being aborted mid-generation every time - billed, discarded, and logged
        // as a model failure. 45s lets one attempt actually finish inside the 55s wall. The ladder
        // gets fewer retries on slow calls, which is the right trade: one complete answer beats two
        // truncated ones.
        const budgetMs = (hasBinary || (body.plugins && body.plugins.length)) ? 55000 : 45000;
        const to = setTimeout(() => ac.abort(), Math.min(budgetMs, deadlineAt - Date.now()));
        try {
          const payload: Record<string, unknown> = {
            model: m, max_tokens: maxTok, messages: outbound,
          };
          if (body.temperature != null) payload.temperature = body.temperature;
          if (wantStream) payload.stream = true;
          if (body.plugins && body.plugins.length) payload.plugins = body.plugins;
          if (body.tools && body.tools.length) payload.tools = body.tools;
          if (body.tool_choice != null) payload.tool_choice = body.tool_choice;
          if (body.response_format != null) payload.response_format = body.response_format;

          const r = await fetch('https://openrouter.ai/api/v1/chat/completions', {
            method: 'POST',
            headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
            body: JSON.stringify(payload), signal: ac.signal,
          });

          if (wantStream) {
            // Hand the stream straight back. The caller can abandon it, which stops generation
            // and stops billing - that is the whole point of streaming for cost.
            clearTimeout(to);
            if (r.ok && r.body) {
              await rpcSafe('fn_llm_log', {
                p_fn: fnName, p_dept: body.dept ?? null, p_agent: body.agent ?? null,
                p_task_class: route.task_class ?? null, p_model: m,
                p_because: route.why + ' | streamed (token counts not available on the stream path)',
                p_tier: route.tier ?? null, p_prompt_tokens: 0, p_output_tokens: 0, p_cached: false,
                p_cache_key: null, p_latency_ms: Date.now() - t0, p_ok: true,
              });
              return new Response(r.body, {
                headers: { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache',
                           'X-QD-Model': m, 'X-QD-Tier': String(route.tier) },
              });
            }
            lastErr = 'stream not available: HTTP ' + r.status;
            continue;
          }

          const j = await r.json();
          const msg = j?.choices?.[0]?.message;
          const c = msg?.content;
          // A tool-calling reply is a SUCCESS with empty content - the answer is in tool_calls.
          // Treating it as "no content" is what would make the Secretary look broken.
          const hasCalls = Array.isArray(msg?.tool_calls) && msg.tool_calls.length > 0;
          if (c || hasCalls) {
            // Some models return content as an array of parts; callers expect a string.
            out = typeof c === 'string'
              ? c
              // deno-lint-ignore no-explicit-any
              : (Array.isArray(c) ? c.map((p: any) => p?.text || '').join('') : '');
            outMsg = msg; used = m; usage = j?.usage || {};
            break;
          }
          lastErr = JSON.stringify(j?.error || j).slice(0, 200);
        } catch (e) {
          lastErr = String((e as Error)?.message || e).slice(0, 200);
        } finally { clearTimeout(to); }
      }
      if (outMsg || deadlineHit) break;
    }

    // ---- 8. LOG with real money ---------------------------------------------------------
    const inTok = Number(usage.prompt_tokens ?? 0);
    const outTok = Number(usage.completion_tokens ?? 0);
    // OpenRouter reports the cached portion under a few different names depending on provider.
    const cachedIn = Number(
      (usage as Record<string, number>).cache_read_input_tokens ??
      (usage as Record<string, number>).cached_tokens ?? 0);

    let costUsd: number | null = null;
    try {
      const { data } = await admin.rpc('fn_model_cost_usd', {
        p_model: used, p_in_tokens: inTok, p_out_tokens: outTok, p_cached_in_tokens: cachedIn,
      });
      costUsd = data == null ? null : Number(data);
    } catch (_e) { /* pricing is reporting, not a gate */ }

    await rpcSafe('fn_llm_log', {
      p_fn: fnName, p_dept: body.dept ?? null, p_agent: body.agent ?? null,
      p_task_class: route.task_class ?? null, p_model: used,
      p_because: route.why + (used !== model ? ' [fell back from ' + model + ']' : '')
                 + (caps.length ? ' | caps: ' + caps.join('+') : '')
                 + (useCache ? ' | prompt cache on, ' + cachedIn + ' input tokens read from cache' : ''),
      p_tier: route.tier ?? null, p_prompt_tokens: inTok, p_output_tokens: outTok,
      p_cached: cachedIn > 0, p_cache_key: cacheKey, p_latency_ms: Date.now() - t0, p_ok: !!outMsg,
    });

    if (!outMsg) return J({ ok: false, error: deadlineHit ? 'gateway_deadline' : 'all_models_failed',
                            detail: deadlineHit ? ('no model answered within the ' + wallBudgetMs + 'ms budget the caller waits for; last error: ' + lastErr) : lastErr,
                            ladder, caps }, 502);

    if (cacheable && cacheKey && out) {
      await rpcSafe('fn_llm_cache_store', {
        p_key: cacheKey, p_fn: fnName, p_task_class: route.task_class ?? null, p_model: used,
        p_response: out, p_ttl_minutes: Number(body.cache_ttl_min), p_embedding: promptEmb,
        p_saved_usd: costUsd ?? 0,
      });
    }

    return J({ ok: true, used_llm: true, outcome: 'generated', content: out, model: used,
               // The whole message when asked for: tool_calls for the agent loops, annotations for
               // the web plugin's source citations (kb_research reports sources, not just prose).
               message: body.want_message === true ? outMsg : undefined,
               tool_calls: outMsg?.tool_calls ?? undefined,
               annotations: outMsg?.annotations ?? undefined,
               tier: route.tier, task_class: route.task_class, caps,
               prompt_tokens: inTok, output_tokens: outTok, cached_input_tokens: cachedIn,
               cost_usd: costUsd, latency_ms: Date.now() - t0 });
  } catch (e) {
    return J({ ok: false, error: String((e as Error)?.message || e) }, 500);
  }
});
