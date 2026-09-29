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
//   5. (no budget halt)  - removed 24 Sep 2026, founder_instruction 987: no caps on LLM spend
//   6. cache             - exact hash, then SEMANTIC similarity on free in-region embeddings
//   7. the call          - with Anthropic prompt caching, a hard token cap, and a model ladder
//   8. log               - real cost from model_registry, including cache-read pricing
//
// dry_run:true runs 1-6 and returns the decision WITHOUT calling a model, so the whole thing can be
// verified for zero spend.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { paidProviderGate } from '../_shared/paid_gate.ts';
import { annotate, observe } from '../_shared/observe.ts';
import { attemptPlan, failureKind, fixtureVerdict, nextAttempt, ownWorkByName, subjectOf } from '../_shared/spend_guards.ts';
import { embedAnswer } from '../_shared/embed_answer.ts';
import { shapeRequest } from '../_shared/request_shape.ts';

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
  } catch (e) {
    // Still null, so the semantic cache never fails the call for it -- but no longer silent (22 Sep
    // 2026, instruction 645): the gte-small error reaches the edge log, and the embed action below
    // answers 503 embed_failed instead of ok:true over a missing vector.
    console.error('ai_gateway embed: gte-small failed:', String((e as Error)?.message || e).slice(0, 300));
    return null;
  }
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

// THE QUALITY AXIS. ai_cost_log.confidence was null on all 1,614 model calls in 30 days because
// fn_llm_log had no parameter for it, so "compare models on quality, latency and cost" could only
// ever have two of the three. This reads the model's OWN reported confidence out of its output when
// the output is JSON and carries one, and returns null otherwise.
//
// It does not derive, estimate or default a score. A model that says nothing about its confidence
// keeps a null, and the comparison stays honestly incomplete for it -- which is the point. A number
// invented here would be indistinguishable from a measured one the moment it reached the column.
// deno-lint-ignore no-explicit-any
// IT REQUIRED THE WHOLE OUTPUT TO BE JSON, AND ALMOST NOTHING HERE IS (measured 11 Aug 2026).
// 1,746 model calls in 7 days, SEVEN with a confidence: 6 from knowledge_exam and 1 from
// quality_axis_probe, the only two callers whose entire reply is a JSON document. Every employee
// path — agent_brain 594 calls, exec_agents 262, action_worker 229 — returns PROSE, so `body
// .startsWith('{')` was false and the column stayed null for 99.6% of the company's thinking.
//
// The trailing-object arm below reads the LAST balanced {...} in the reply. That is exactly where
// agent_brain has always put its machine-readable tail (`@@ACTIONS@@ {json}`, stripped from the
// visible text by splitActions), so one parser change gives every prose caller a place to report a
// confidence without inventing a second format for them to get wrong.
//
// It still does not derive, estimate or default a score. A model that says nothing keeps a null.
// deno-lint-ignore no-explicit-any
function selfReportedConfidence(text: any): number | null {
  if (typeof text !== 'string' || text.length === 0 || text.length > 200_000) return null;
  const readFrom = (v: unknown): number | null => {
    const root = Array.isArray(v) ? v[0] : v;
    if (!root || typeof root !== 'object') return null;
    const raw = (root as Record<string, unknown>).confidence;
    const n = typeof raw === 'number' ? raw : (typeof raw === 'string' ? Number(raw) : NaN);
    // fn_llm_log normalises a percentage and discards anything outside 0..100, so the only job here
    // is to reject what is not a number at all.
    return Number.isFinite(n) ? n : null;
  };

  // 1. The whole reply is a JSON document. Models fence JSON in ```json … ``` about as often as
  //    they emit it bare.
  const body = text.replace(/^\s*```(?:json)?\s*/i, '').replace(/\s*```\s*$/, '').trim();
  if (body.startsWith('{') || body.startsWith('[')) {
    try { const hit = readFrom(JSON.parse(body)); if (hit !== null) return hit; } catch { /* fall through */ }
  }

  // 2. A prose reply with a JSON tail. Candidate starts are tried nearest-first against the last
  //    '}', widening until one parses — JSON.parse itself is the validator, so a '{' inside a
  //    quoted value or a nested object costs one failed attempt rather than a hand-rolled scanner
  //    to get subtly wrong. A greedy /\{[\s\S]*\}/ is what NOT to do here: it would start at the
  //    first '{' anywhere in the prose (a code sample, a schema the employee quoted) and fail.
  const end = body.lastIndexOf('}');
  if (end < 0) return null;
  for (let i = body.lastIndexOf('{'); i >= 0; i = body.lastIndexOf('{', i - 1)) {
    if (i > end) continue;
    if (end - i > 20_000) break;      // the tail is a small object, never the whole document
    try { return readFrom(JSON.parse(body.slice(i, end + 1))); } catch { /* widen and retry */ }
  }
  return null;
}

interface Body {
  __secret?: string;
  fn?: string; task_class?: string; dept?: string; agent?: string;
  counterpart_model?: string;   // the model that wrote what this call reviews (fn_ai_route_review)
  sys?: string;
  sys_stable?: string;                    // the byte-stable half of the system prompt; only this is marked cacheable
  input?: string | Msg[];
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
  effort?: string;                        // Claude reasoning effort; request_shape.ts defaults it to medium
  require_caps?: string[];                // override; normally inferred from the payload
  want_message?: boolean;                 // return the whole assistant message (tool_calls included)
}

// What the payload actually needs, read off the payload itself. A caller that has to declare
// "this has an image in it" will eventually forget to, and the failure mode is a provider error
// nobody can trace. Reading it here means vision/audio can never be mis-routed by omission.
// deno-lint-ignore no-explicit-any
// OpenRouter's supported_parameters per model. response_format FAILS a request on a model that lacks
// it, so "unknown" means "do not send". The list is loaded once per isolate, refreshed hourly, and
// started BEFORE the attempt loop with a short timeout: an attempt never waits on it, and a list
// that has not arrived yet reads as unknown for that attempt (the caller's own parser is the fallback).
const PARAMS_TTL_MS = 60 * 60 * 1000;
let _params: Map<string, Set<string>> | null = null;
let _paramsAt = 0;
let _paramsLoading: Promise<void> | null = null;
function loadSupportedParams(): void {
  if (_paramsLoading || (_params && Date.now() - _paramsAt < PARAMS_TTL_MS)) return;
  _paramsLoading = fetch('https://openrouter.ai/api/v1/models', { signal: AbortSignal.timeout(1500) })
    .then((r) => r.ok ? r.json() : null)
    .then((j) => {
      if (!j?.data) return;
      // deno-lint-ignore no-explicit-any
      _params = new Map(j.data.map((d: any) => [String(d.id), new Set<string>((d.supported_parameters ?? []).map(String))]));
      _paramsAt = Date.now();
    })
    .catch(() => {})
    .finally(() => { _paramsLoading = null; });
}
function supportedParams(model: string): Set<string> | null {
  return _params?.get(model) ?? null;
}

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

Deno.serve(observe('ai_gateway', async (req) => {
  const t0 = Date.now();
  try {
    const body = (await req.json().catch(() => ({}))) as Body;
      // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    // body.fn — what the caller says it is — is passed so that a call authenticated by the LEGACY
    // shared secret records who claimed to make it. It is read again at fnName below for routing;
    // the audit could not see it, which is why five legacy uses have no attributable caller.
    const __auth = await requireInternal(admin, body?.__secret, 'ai_gateway', body?.fn);
    if (!__auth.ok) return J({ error: 'forbidden' }, 403);

    // Utility path: embed text for callers that need a vector (FAQ backfill, semantic search).
    // Free, so it never touches routing or budget. A missing vector is 503 embed_failed, never
    // ok:true (embed_answer.ts; guarded by scripts/checks/a_failed_embedding_is_never_answered_as_ok.test.mjs).
    if (body.action === 'embed') {
      // One in-process second try before a 503. Measured 22 Sep 2026: the catalogue check met a null
      // vector in 2 of 3 full runs, each run many embeds, and passed alone -- intermittent, not constant.
      // Every 503 is an agent_runs 'error' row the failed-runs watcher reads, so a blip is retried here.
      const text = String(body.text || '');
      const a = embedAnswer((await embed(text)) ?? (await embed(text)));
      return J(a.body, a.status);
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
          // The retrieval confidence was already measured on this path and was being formatted into
          // p_because as prose. It goes in the numeric column it belongs in as well.
          p_confidence: typeof faq.confidence === 'number' ? faq.confidence : null,
        });
        return J({ ok: true, used_llm: false, outcome: 'level0', source: faq.source,
                   content: faq.answer, confidence: faq.confidence, cost_usd: 0 });
      }
    }

    // ---- MESSAGES ------------------------------------------------------------------------
    // Two shapes, one path. `messages` is the full OpenAI array and wins when present - that is
    // what a tool-calling loop needs, because it must replay assistant tool_calls and tool
    // results verbatim. `sys` + `input` remains the shorthand the 32 migrated callers use.
    // THE STABLE HALF AND THE VOLATILE HALF (11 Aug 2026).
    // A provider cache only pays when the marked block is BYTE-IDENTICAL between calls. agent_brain
    // was handing us one 40,000-character string whose tail carried "LIVE DATA SNAPSHOT ... captured
    // just now" — so cache_control was being stamped on a prefix that changed every single call.
    // Every call was a cache WRITE at 1.25x and no call was ever a read. That is not caching being
    // off, it is caching pointed at the wrong thing and charged a premium for it.
    //
    // Callers that know which half of their prompt is stable now say so. sys_stable is prepended to
    // sys and is the ONLY block marked cacheable; sys keeps whatever changes per call.
    const sysStable = String(body.sys_stable || '');
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
    // A REVIEW IS ROUTED AWAY FROM ITS AUTHOR'S FAMILY (founder_instruction 873, 23 Sep 2026). A request
    // that names counterpart_model — the model that wrote what is being reviewed — goes through
    // fn_ai_route_review, which returns a model AND a fallback from another provider family, or
    // use_llm:false with no_independent_reviewer. It never falls back to the author's family. A
    // seat_deliberation_* class without counterpart_model is refused: independence cannot be proved.
    // (scripts/sql/a_seat_is_never_reviewed_by_a_model_of_its_own_family.sql)
    // One set of authors is one string everywhere (route, log tag, hold): trimmed, de-duplicated, sorted.
    const counterpart = typeof body.counterpart_model === 'string' && body.counterpart_model.trim()
      ? [...new Set(body.counterpart_model.split(',').map((x) => x.trim()).filter(Boolean))].sort().join(',') || null : null;
    if (!counterpart && /^seat_deliberation_/.test(String(body.task_class ?? ''))) {
      return J({ ok: false, used_llm: false, outcome: 'review_needs_counterpart',
                 error: 'a seat_deliberation review must name counterpart_model, the model the author wrote on', cost_usd: 0 }, 400);
    }
    const { data: route, error: rErr } = counterpart ? await admin.rpc('fn_ai_route_review_for', {
      p_task_class: body.task_class ?? null,
      p_counterpart_model: counterpart,
      p_agent_key: body.agent ?? null,
      p_fn: fnName,
      p_dept_key: body.dept ?? null,
      // a vision review must land on a reviewer that can see (a_review_is_held_rather_than_skipped_...sql)
      p_require_caps: caps.length ? caps : null,
    }) : await admin.rpc('fn_ai_route', {
      p_task_class: body.task_class ?? null,
      p_dept_key: body.dept ?? null,
      p_confidence: body.confidence ?? null,
      p_fn: fnName,
      p_escalate: body.escalate === true,
      p_require_caps: caps.length ? caps : null,
      // THE ROUTER NEVER KNEW WHO WAS ASKING (fixed 11 Aug 2026). body.agent was already passed to
      // fn_llm_log in five places on this path, so the identity was in hand the whole time and was
      // simply not given to fn_ai_route. Both role-default branches inside it - the pack's
      // current_agent rows and org_agents.routing_tier - key off p_agent_key, so without this line
      // neither could ever fire through the gateway, which is how every call reaches a model.
      p_agent_key: body.agent ?? null,
    });
    if (rErr || !route) {
      return J({ ok: false, error: 'route_failed', detail: String(rErr?.message || 'no route') }, 500);
    }
    // EVERY REVIEW CLASS, NOT ONLY seat_deliberation_ (founder instruction ~891, 23 Sep 2026). A class whose
    // model_policy.reviews_class is non-empty judges another class's output; without the author's model its
    // independence cannot be proved, so it is refused before any model is chosen. With one, the route came from
    // fn_ai_route_review, and the counterpart is written into the log line the DB backstop reads
    // (trg_ai_cost_log_review_family). scripts/sql/every_review_class_is_judged_by_another_family_than_its_author.sql
    if (!counterpart && route.task_class) {
      const { data: rc } = await admin.from('model_policy').select('reviews_class').eq('task_class', route.task_class).maybeSingle();
      if (Array.isArray(rc?.reviews_class) && rc.reviews_class.length) {
        return J({ ok: false, used_llm: false, outcome: 'review_needs_counterpart',
                   error: `${route.task_class} reviews ${rc.reviews_class.join(', ')}: name counterpart_model, the model (or 'deterministic') that wrote what it reviews`,
                   cost_usd: 0 }, 400);
      }
    }
    if (counterpart) route.why = String(route.why ?? '') + ' | counterpart_model=' + counterpart.replace(/[\s|]+/g, '')
      + (route.reviewer_tier ? ' | reviewer_tier=' + route.reviewer_tier : '');
    // NEVER UNREVIEWED (coordinator ruling on #880). No reviewer outside the authors' families, not even the third-family
    // last resort: the call is HELD — no model runs — and the hold is recorded; the CEO owns the finding
    // (fn_it_review_independence_watch). The caller gets used_llm:false and must not act on an answer it did not get.
    // An UNKNOWN author is a data defect in what the caller recorded, not a missing reviewer: no hold; the refusal row
    // (because 'AUTHOR UNKNOWN: ...') is reported by the watch as its own it_engineer finding.
    if (counterpart && route.no_independent_reviewer && !route.unknown_author) {
      await rpcSafe('fn_review_hold_record', { p_task_class: route.task_class ?? body.task_class ?? null, p_fn: fnName,
        p_agent_key: body.agent ?? null, p_counterpart_model: counterpart, p_why: route.why ?? null });
    }

    // ---- 4. REFUSALS: deterministic work, or no capable model (no budget halt: founder_instruction 987) ---
    if (route.use_llm === false) {
      await rpcSafe('fn_llm_log', {
        p_fn: fnName, p_dept: body.dept ?? null, p_agent: body.agent ?? null,
        p_task_class: route.task_class ?? null, p_model: 'none', p_because: route.why,
        p_tier: route.tier ?? 'none', p_prompt_tokens: 0, p_output_tokens: 0, p_cached: false,
        p_cache_key: null, p_latency_ms: Date.now() - t0, p_ok: true,
      });
      return J({ ok: true, used_llm: false,
                 outcome: route.unknown_author ? 'review_author_unknown' : route.no_independent_reviewer ? 'review_held_no_independent_reviewer'
                        : 'refused_deterministic',
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
    //
    // ── THE TTL COMES FROM THE ROUTE WHEN THE CALLER DOES NOT SUPPLY ONE ──────────────────────
    // This read `Number(body.cache_ttl_min ?? 0) > 0` — a CALLER-supplied field with no default
    // and, measured on production 2026-08-09, no caller anywhere that supplied it. So `cacheable`
    // was false on every single request: the lookup below never fired, the store at the bottom
    // never fired, and llm_cache held 0 rows against 1,021 logged calls. Everything in this
    // section worked. It was switched off by a `?? 0`.
    //
    // Whether a response may be REPLAYED is a property of the task class, not of the call site —
    // asking every caller to know it is how it ended up being answered by nobody. model_policy
    // now carries cache_ttl_min per task class and fn_ai_route hands it back, so the default is
    // made once, deliberately, next to the tier and token ceilings it belongs with.
    //
    // The caller keeps the override and keeps precedence, which is what lets a call site that
    // knows its own request is unrepeatable pass 0 and opt out.
    // A review is never replayed from cache: a replayed review was not judged by the model now routed to it.
    const ttlMin = counterpart ? 0 : Number(body.cache_ttl_min ?? route.cache_ttl_min ?? 0);
    const cacheable = ttlMin > 0 && !hasBinary && !(body.tools && body.tools.length);
    let cacheKey: string | null = null;
    let promptEmb: string | null = null;
    if (cacheable) {
      cacheKey = await sha256([
        model, String(maxTok), sysStable, sys, JSON.stringify(convo),
        JSON.stringify(body.plugins ?? null), JSON.stringify(body.response_format ?? null),
      ].join(' '));
      promptEmb = await embed((sysStable + sys).slice(0, 400) + ' ' + JSON.stringify(convo).slice(0, 800));
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
          p_confidence: selfReportedConfidence(hit.response),
        });
        return J({ ok: true, used_llm: false, outcome: 'cache_' + hit.kind, model: hit.model ?? model,
                   content: hit.response, similarity: hit.similarity, cost_usd: 0 });
      }
    }

    // ---- DRY RUN: everything decided, nothing spent -------------------------------------
    if (dry) {
      return J({ ok: true, dry_run: true, used_llm: false, outcome: 'would_call',
                 model, fallback, tier: route.tier, task_class: route.task_class,
                 max_tokens: maxTok,
                 prompt_cache: route.cache === true && (sysStable || sys).length >= CACHE_MIN_CHARS,
                 stable_chars: sysStable.length, volatile_chars: sys.length,
                 stream_ok: route.stream === true, budget_pct: route.budget_pct,
                 caps, cacheable, has_binary: hasBinary,
                 plugins: body.plugins ?? null, tools: (body.tools || []).length || 0,
                 why: route.why });
    }

    // ---- OUR OWN TRAFFIC NEVER SPENDS (22 Sep 2026, founder instruction 705) ------------------
    // Nearly all measured demand on the paid routes was our own harness: the post-merge E2E smoke
    // (94 runs in 30 days) and the nightly journey drive ZZ DEMO / @example.invalid fixtures
    // through inquiry_intake, quote_compare and the extractors exactly as a customer would. Once
    // the hold lifts, every merge would have bought model answers for a test.
    //
    // The marker is never a flag a client can set. A caller names the SUBJECT it is working on
    // (inquiry, customer, supplier, verified email or phone) and the DATABASE decides whether that
    // subject is an identity the E2E harness itself created (public.fn_ai_subject_is_fixture: the
    // harness address shape AND a rehearsal_window row for its run tag, a table only the harness can
    // write). A ZZ DEMO name, an @example.invalid address or a +9715000000xx number are typed at
    // sign-up and are deliberately NOT enough. Only this gateway's internal callers can reach it,
    // and they take the subject from rows they already loaded. Anything short of an explicit "not a
    // fixture" answers with the stub; so does a calling function that names itself as a probe,
    // rehearsal, smoke or eval. The stub is the same 503 shape as the founder's hold, so every
    // caller takes the deterministic path it already takes today — the harness keeps testing
    // exactly what it tests now, for nothing. Placed after the dry run on purpose: routing and
    // caching are still verified for free; only the paid call is replaced.
    {
      const subject = subjectOf((body as { subject?: unknown }).subject);
      let ownWork = ownWorkByName(fnName)
        ? 'the calling function "' + fnName + '" is our own automated work (probe, rehearsal, smoke or eval)' : '';
      if (!ownWork && subject) {
        let fx: unknown = null; let fxErr: unknown = null;
        try { const res = await admin.rpc('fn_ai_subject_is_fixture', { p_subject: subject }); fx = res.data; fxErr = res.error; }
        catch (e) { fxErr = e; }
        const v = fixtureVerdict(fx, fxErr);
        if (v.stub) ownWork = v.why;
      }
      if (ownWork) {
        await rpcSafe('fn_llm_log', {
          p_fn: fnName, p_dept: body.dept ?? null, p_agent: body.agent ?? null,
          p_task_class: route.task_class ?? null, p_model: 'none',
          p_because: route.why + ' | FIXTURE: ' + ownWork + ' — answered with the no-cost stub, no provider call was made',
          p_tier: route.tier ?? null, p_prompt_tokens: 0, p_output_tokens: 0, p_cached: false,
          p_cache_key: null, p_latency_ms: Date.now() - t0, p_ok: true,
        });
        // held: the run row reads 'held', not 'error' - refusing our own test traffic is the design (observe.statusOf).
        return annotate(J({ ok: false, used_llm: false, outcome: 'fixture_no_spend',
          error: 'our own test traffic is never sent to a paid model', why: ownWork,
          task_class: route.task_class, cost_usd: 0 }, 503), { held: true, outcome: 'fixture_no_spend' });
      }
    }

    // ---- 7. THE CALL --------------------------------------------------------------------
    const key = await sec('openrouter_api_key');
    if (!key) return J({ ok: false, error: 'openrouter_api_key missing' }, 500);

    // One row, so switching prompt caching off is a policy change and not a deploy. It exists
    // because the decision is arithmetic over a hit rate that can move: below a 22% same-prefix
    // hit rate the 1.25x write premium costs more than the 10x read discount saves.
    let promptCacheOn = true;
    try {
      const { data: pc } = await admin.from('decision_policy').select('value')
        .eq('key', 'prompt_cache_enabled').maybeSingle();
      if (pc && (pc.value === false || pc.value === 'false')) promptCacheOn = false;
    } catch (_e) { /* a missing policy row means the default, not a failed call */ }

    // Mark the STABLE block cacheable when the model supports it, the estate has not switched it
    // off, and the block is big enough to be worth a cache write. Without sys_stable the caller has
    // not told us which part is stable, so we fall back to the old whole-prompt behaviour — which
    // is right for a caller whose whole prompt genuinely is stable and wrong only for one that
    // silently mixes, which is exactly what sys_stable exists to fix.
    //
    // NO ttl FIELD. The 1-hour tier works (probe 11 Aug 2026 returned 200) and loses money on this
    // workload: it bills 2x to write against 1.25x for the default, and the hourly loop repeats at
    // ~65 minutes — just outside the window. See scripts/sql/prompt_cache_accounting.sql for the
    // arithmetic and the measured hit rates.
    const cacheBlock = sysStable || sys;
    const useCache = route.cache === true && promptCacheOn && cacheBlock.length >= CACHE_MIN_CHARS;
    const sysText = sysStable ? (sysStable + sys) : sys;
    const sysMsg = useCache
      ? { role: 'system', content: sysStable
            ? [{ type: 'text', text: sysStable, cache_control: { type: 'ephemeral' } },
               ...(sys ? [{ type: 'text', text: sys }] : [])]
            : [{ type: 'text', text: sys, cache_control: { type: 'ephemeral' } }] }
      : { role: 'system', content: sysText };
    // An empty system message is not free - it is a message the provider still tokenises, and on
    // the transcribe path there is no system prompt at all. Only prepend one when it says something,
    // and never when the caller already supplied its own system turn inside `messages`.
    const hasOwnSystem = convo.some((m) => m?.role === 'system');
    const outbound: Msg[] = (sysText && !hasOwnSystem) ? [sysMsg as Msg, ...convo] : convo;

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
    // V3 REMEDIATION (14 Aug 2026) — THE BREAKER GETS ITS ENTRY POINT.
    //
    // v3_repair_10_infra_reliability.sql built a working failure taxonomy, an append-only attempt
    // ledger and a circuit breaker, and an adversarial re-verification then found the thing that
    // makes all of it worthless: NOTHING CALLED IT. fn_llm_preflight, fn_record_llm_attempt and
    // fn_llm_retry_allowed matched only the .sql file itself; llm_attempt and llm_route_health both
    // held 0 rows while qwen/qwen3.7-plus continued failing 152 times out of 152. A breaker no
    // caller consults cannot fail anything closed. It is the same defect shape the certification
    // was measuring, one layer down.
    //
    // This is the seam it belongs at: the gateway is the only place that knows the resolved route,
    // owns the ladder, and runs the attempts. Everything below records THE FIRST ATTEMPT SEPARATELY
    // from the retries, which is the property the certification insisted on — a retry must never
    // mask an unreliable first attempt.
    const requestId = crypto.randomUUID();
    let attemptNo = 0;
    const fullLadder = [model, ...(fallback && fallback !== model ? [fallback] : [])];
    // KERNEL K12 — THE GATE IS FAIL-CLOSED, AND THERE IS ONLY ONE OF IT.
    //
    // This loop used to read:
    //
    //     try {
    //       const { data: pf } = await admin.rpc('fn_llm_preflight', { p_model: m });
    //       if (pf && pf.allowed === false) { skipped.push(...); continue; }
    //     } catch (_e) { /* preflight must never be the reason a call cannot happen */ }
    //     ladder.push(m);
    //
    // Three ways that reached a paid provider with no permission: the RPC throws and the catch
    // falls through to push; the RPC returns null and `pf &&` short-circuits to push; the RPC
    // returns a shape without `allowed` and the strict `=== false` misses it. The comment said the
    // quiet part out loud — the gate "must never be the reason a call cannot happen" — which is the
    // definition of fail-open on the estate's largest door to OpenRouter.
    //
    // paidProviderGate defaults to refusal. Only an explicit allowed===true puts a route on the
    // ladder, and every refusal carries the rule that refused it, so a denial is never mistaken for
    // an outage.
    const ladder: string[] = [];
    const skipped: { route: string; reason: string }[] = [];
    for (const m of fullLadder) {
      const gate = await paidProviderGate(admin, m);
      if (!gate.allowed) {
        // THE ONE NAMED EXCEPTION TO THE HOLD (14 Sep 2026, founder_instruction 216: "in the case of
        // the boq and drawing, i dont mind using LLM to confirm the result"). Consulted ONLY when the
        // kernel refused for the founder's hold AND the caller's task_class names an excepted route;
        // public.fn_paid_route_exception answers from a row that ships DISABLED, pins the model, and
        // enforces a daily spend cap. Any error or odd shape stays a refusal.
        let excepted = false;
        if (gate.rule === 'founder_hold' && body.task_class === 'drawing_boq_confirm') {
          try {
            const { data: ex } = await admin.rpc('fn_paid_route_exception', { p_route: body.task_class, p_model: m });
            excepted = !!ex && (ex as { allowed?: unknown }).allowed === true;
            if (!excepted) skipped.push({ route: m, reason: `exception: ${(ex as { rule?: string })?.rule ?? 'no answer'}` });
          } catch (_e) { excepted = false; }
        }
        if (!excepted) { skipped.push({ route: m, reason: `${gate.rule}: ${gate.reason}` }); continue; }
      }
      ladder.push(m);
    }
    // Every route on the ladder is open-circuit: fail CLOSED and say so, rather than retrying into
    // a wall and reporting it as a model failure.
    // A REVIEW WHOSE REVIEWER CANNOT BE CALLED IS HELD, NOT SKIPPED (#880 review, item 6). Every route open-circuit for a
    // reason other than the founder's hold (which holds everything, reviewed or not) is recorded as a review_hold.
    if (counterpart && !ladder.length && fullLadder.length && skipped.some((x) => !/^(founder_hold|exception):/.test(x.reason))) {
      await rpcSafe('fn_review_hold_record', { p_task_class: route.task_class ?? null, p_fn: fnName, p_agent_key: body.agent ?? null,
        p_counterpart_model: counterpart, p_why: 'reviewer unreachable: ' + skipped.map((x) => x.route + ' (' + x.reason + ')').join('; ') });
    }
    if (!ladder.length && fullLadder.length) {
      // A HELD ROUTE IS STILL A ROUTING DECISION, AND THE ROUTER MUST SAY SO (3 Sep 2026). The
      // policy chose a model for this task class and the kernel gate refused every route on the
      // ladder; nothing was called and nothing was spent. Before this line, that decision left no
      // row at all: with the founder's hold open, ai_cost_log recorded zero routed requests for
      // nineteen days while callers reached this branch dozens of times a week, so the router
      // read as dead when it was refusing exactly as instructed. Logged the way the deterministic
      // refusal above is logged — model 'none', zero tokens, the rationale in words — so spend,
      // failure and confidence instruments see a policy answer, not a call, and the routing
      // rationale names the model it would have used and the rule that held it.
      await rpcSafe('fn_llm_log', {
        p_fn: fnName, p_dept: body.dept ?? null, p_agent: body.agent ?? null,
        p_task_class: route.task_class ?? null, p_model: 'none',
        p_because: route.why + ' | HELD: routed to ' + model + ' by policy, no provider call was made — '
                   + skipped.map(s => s.route + ' (' + s.reason + ')').join('; '),
        p_tier: route.tier ?? null, p_prompt_tokens: 0, p_output_tokens: 0, p_cached: false,
        p_cache_key: null, p_latency_ms: Date.now() - t0, p_ok: true,
      });
      return J({ ok: false, used_llm: false, outcome: 'circuit_open',
        error: 'every model route for this task class is open-circuit',
        routes: skipped, task_class: route.task_class, cost_usd: 0 }, 503);
    }
    // attempt_no is assigned SERVER-SIDE by fn_record_llm_attempt and cannot be set by this caller.
    // That is deliberate: it is what makes first-attempt success un-fakeable from up here.
    // A RETRY'S COST WAS REAL MONEY THAT NOTHING RECORDED (15 Aug 2026). llm_attempt has
    // prompt_tokens, output_tokens and cost_aed, fn_record_llm_attempt already accepts and inserts
    // all three — and this caller sent nine fields, none of them among the three. Measured: 666
    // llm_attempt rows, 0 with a cost. The money itself is not missing (ai_cost_log holds 4,336
    // priced rows), but it is recorded once per REQUEST, against the model that finally answered.
    // When a request climbs the fallback ladder, the tokens burned by the attempts that failed
    // first are attributable to nothing at all. `u` is the usage block from the attempt being
    // recorded; the AED is derived in the database from the same pricing source ai_cost_log uses,
    // so there is no second pricing implementation up here to drift.
    // deno-lint-ignore no-explicit-any
    const recordAttempt = async (routeUsed: string, ok: boolean, latencyMs: number, errText: string, fr?: string, u?: any) => {
      attemptNo++;
      const det = (u?.prompt_tokens_details || {}) as Record<string, number>;
      try {
        await admin.rpc('fn_record_llm_attempt', { p: {
          request_id: requestId, model_route: routeUsed, ok,
          latency_ms: latencyMs, err_excerpt: ok ? null : String(errText || '').slice(0, 400),
          fn: String(body.fn ?? 'unknown'), agent_key: body.agent ?? null,
          task_class: route.task_class ?? null, tier: route.tier ?? null,
          finish_reason: fr ?? null,
          // Left absent rather than zeroed when the provider returned no usage block: 0 would make
          // "this attempt was free" indistinguishable from "nobody recorded what it cost".
          prompt_tokens: u?.prompt_tokens ?? null,
          output_tokens: u?.completion_tokens ?? null,
          cached_in_tokens: det.cached_tokens ?? u?.cache_read_input_tokens ?? u?.cached_tokens ?? 0,
        }});
      } catch (_e) { /* the ledger must not take down the call; its absence shows in the report */ }
    };
    const wantStream = body.stream === true && route.stream === true;

    let out: string | null = null;
    // deno-lint-ignore no-explicit-any
    let outMsg: any = null;
    let used = model, usage: Record<string, number> = {}, lastErr = '';
    // THE TWO FACTS THE COMPLETION CARRIED AND THIS FUNCTION THREW AWAY (9 Sep 2026).
    //   genId       - OpenRouter's own id for the generation. It is the ONLY key to their
    //                 per-generation record at GET /api/v1/generation?id=, so without it a row in
    //                 our ledger can never be reconciled against a line on their side.
    //   reportedUsd - what OpenRouter says the call cost, from usage.cost (requested above).
    // Both go onto the ai_cost_log row. Both stay null when no provider call was made, which is
    // exactly right: a policy answer has no generation and no charge.
    let genId: string | null = null;
    let reportedUsd: number | null = null;
    // 5 Aug 2026. The gateway read choices[0].message and threw away choices[0].finish_reason, so a
    // reply cut off at max_tokens arrived at the caller as ordinary content. Every caller that
    // expects JSON then reports "unparseable output" and the real cause - the budget in
    // model_policy is smaller than the output contract the caller asked for - is invisible. That
    // misdiagnosis has now cost three separate investigations: quote_comparison at haiku/1500,
    // rfq_routing at 300 with 12 candidates, and quote_comparison again at sonnet/3000. Carry the
    // reason out so a too-small budget says so instead of looking like a bad model.
    let finishReason = '';
    // AT MOST TWO PAID CALLS PER REQUEST, AND NONE THAT CANNOT CHANGE THE ANSWER (22 Sep 2026).
    // This was `for (m of ladder) for (attempt < 2)`: four provider calls per request on a
    // two-model ladder, the same model retried after a 401/402/400 that no second asking can
    // change, and a fall-back to the next model after a 402 (no credit) on the same account.
    // quote_compare wrapped that in its own two-attempt loop, so one card view could make eight.
    // attemptPlan bounds the whole ladder at MAX_PAID_CALLS_PER_REQUEST; failureKind decides from
    // the provider's status whether another attempt is worth money (_shared/spend_guards.ts).
    const plan = attemptPlan(ladder);
    if (body.response_format != null) loadSupportedParams();
    let sentMaxTok = maxTok;   // what the provider was actually given (Claude adds thinking headroom)
    let pi = 0;
    attempts: while (pi >= 0 && pi < plan.length) {
      const m = plan[pi];
      let failStatus: number | null = null;
      {
        // An attempt needs a few seconds to be worth starting at all.
        const msLeft = deadlineAt - Date.now();
        if (msLeft < 4000) { deadlineHit = true; break; }
        const attemptStartedAt = Date.now();   // per-attempt clock, for the reliability ledger
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
        // 5 Aug 2026. This per-attempt cap was tuned on 29 Jul against the then-fixed 55s wall and
        // stayed hardcoded when the wall became caller-declared. So a caller that declared
        // client_timeout_ms=100000 still had EVERY attempt aborted at 45s: raising the wall only
        // bought more doomed retries, never one attempt that could finish. quote_compare generating
        // ~4000 tokens needs 45-90s and failed every time with "The signal has been aborted", which
        // reads as a model error rather than our own stopwatch. Derive the cap from the wall that is
        // actually in force - the wall already guarantees we never exceed the caller's patience, and
        // as the 29 Jul note itself says, one complete answer beats two truncated ones.
        const floorMs = (hasBinary || (body.plugins && body.plugins.length)) ? 55000 : 45000;
        const budgetMs = Math.max(floorMs, deadlineAt - Date.now());
        const to = setTimeout(() => ac.abort(), Math.min(budgetMs, deadlineAt - Date.now()));
        try {
          const payload: Record<string, unknown> = {
            model: m, max_tokens: maxTok, messages: outbound,
            // ASK OPENROUTER WHAT IT ACTUALLY CHARGED (9 Sep 2026).
            //
            // Everything in ai_cost_log.cost_aed is DERIVED: fn_llm_log multiplies the token
            // counts by public.model_rate, which is OUR price list, not OpenRouter's invoice. The
            // two can differ - provider surcharges, BYOK routing, a mid-flight price change - and
            // nothing recorded the difference, so the accountant had no way to tell a pricing
            // drift from an unattributed call.
            //
            // `usage: { include: true }` makes OpenRouter return usage.cost on the completion
            // itself, so the authoritative per-call figure arrives with the answer and costs no
            // second round trip. GET /api/v1/generation?id= remains the fallback for a call whose
            // cost has to be re-read later, which is why j.id is now kept below.
            usage: { include: true },
          };
          // Per-model request shape (_shared/request_shape.ts): no sampling params on Claude, an
          // explicit reasoning effort plus thinking headroom on Claude, and response_format only
          // where OpenRouter lists it for this model.
          Object.assign(payload, shapeRequest({
            model: m, maxTokens: maxTok, temperature: body.temperature ?? null,
            effort: body.effort ?? null, responseFormat: body.response_format ?? null,
            supported: supportedParams(m),
          }));
          sentMaxTok = Number(payload.max_tokens);
          if (wantStream) payload.stream = true;
          if (body.plugins && body.plugins.length) payload.plugins = body.plugins;
          if (body.tools && body.tools.length) payload.tools = body.tools;
          if (body.tool_choice != null) payload.tool_choice = body.tool_choice;

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
            failStatus = r.ok ? null : r.status;
            throw new Error(lastErr);
          }

          failStatus = r.ok ? null : r.status;
          const j = await r.json().catch(() => null);
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
            genId = typeof j?.id === 'string' && j.id ? j.id : null;
            reportedUsd = Number.isFinite(Number(j?.usage?.cost)) ? Number(j.usage.cost) : null;
            finishReason = String(j?.choices?.[0]?.finish_reason
                                  || j?.choices?.[0]?.native_finish_reason || '');
            await recordAttempt(m, true, Date.now() - attemptStartedAt, '', finishReason, j?.usage);
            break attempts;
          }
          lastErr = JSON.stringify(j?.error || j).slice(0, 200);
          // An empty completion IS a failure even though the HTTP call succeeded. This is exactly
          // the 220-of-228 case: a valid chat.completion body carrying no content, which every
          // monitor read as a healthy response.
          await recordAttempt(m, false, Date.now() - attemptStartedAt, lastErr);
        } catch (e) {
          lastErr = String((e as Error)?.message || e).slice(0, 200);
          await recordAttempt(m, false, Date.now() - attemptStartedAt, lastErr);
        } finally { clearTimeout(to); }
      }
      pi = nextAttempt(plan, pi, failureKind(failStatus));
    }

    // ---- 8. LOG with real money ---------------------------------------------------------
    const inTok = Number(usage.prompt_tokens ?? 0);
    const outTok = Number(usage.completion_tokens ?? 0);
    // WHERE THE CACHE NUMBERS ACTUALLY LIVE. This looked for usage.cache_read_input_tokens and
    // usage.cached_tokens. OpenRouter reports NEITHER at the top level — measured 11 Aug 2026 on a
    // live sonnet-5 call, the response is:
    //   "usage":{"prompt_tokens":2697,...,"prompt_tokens_details":{"cached_tokens":2683,
    //             "cache_write_tokens":0,"audio_tokens":0,"video_tokens":0}}
    // so cachedIn read 0 on every call the company has ever made, fn_llm_log was told p_cached=false
    // every time, and "prompt caching is off: 4 of 2,141 cached" was a meter pointed at a field that
    // does not exist. The nested read goes first; the two flat names are kept because a different
    // provider may still use them.
    // deno-lint-ignore no-explicit-any
    const det = ((usage as any).prompt_tokens_details || {}) as Record<string, number>;
    const cachedIn = Number(
      det.cached_tokens ??
      (usage as Record<string, number>).cache_read_input_tokens ??
      (usage as Record<string, number>).cached_tokens ?? 0);
    const cacheWrite = Number(
      det.cache_write_tokens ??
      (usage as Record<string, number>).cache_creation_input_tokens ?? 0);

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
                 + (useCache ? ' | prompt cache on (' + cacheBlock.length + ' stable chars): '
                               + cachedIn + ' tokens read from cache, ' + cacheWrite + ' written' : '')
                 + (finishReason === 'length'
                    ? ' | TRUNCATED: the model stopped at the ' + sentMaxTok + '-token ceiling for task_class '
                      + String(route.task_class) + ', so the reply is cut off mid-output. A caller that '
                      + 'expects JSON will report unparseable output; raise max_tokens in model_policy.'
                    : '')
                 // WHY IT FAILED WAS RETURNED TO THE CALLER AND NEVER WRITTEN DOWN (12 Aug 2026).
                 // A failed call logged ok=false, 0 tokens and the ordinary routing rationale, so
                 // ai_cost_log could say THAT the AI layer failed and never WHY. Measured the day
                 // this was added: 25 of 86 sonnet-5 calls failed in six hours across exec_agents,
                 // action_worker and agent_brain, each in 258-698ms with 0 output tokens, and the
                 // reason was unrecoverable from the database - lastErr existed, was returned in
                 // the HTTP body, and was discarded.
                 //
                 // It also cost a wrong conclusion. "0 rows carry 'fell back from' in 24h" was read
                 // as "the fallback ladder never engages", but that string is only written when a
                 // fallback SUCCEEDS: `used !== model` above. A ladder that tried every model and
                 // had them all fail looks identical to one that was never tried. Recording the
                 // error tells the two apart.
                 + (!outMsg && lastErr ? ' | ALL MODELS FAILED after the full ladder: ' + lastErr : ''),
      p_confidence: selfReportedConfidence(out),
      p_tier: route.tier ?? null, p_prompt_tokens: inTok, p_output_tokens: outTok,
      // p_cached is NOT "some of the prompt came from cache". It means "no model was called", and
      // fn_llm_log skips costing entirely when it is true. A prompt-cache read IS a model call and
      // it does cost money — at the cache-read rate, which is what the two new arguments carry.
      // Setting p_cached true here booked 90%-off prompts at exactly zero.
      p_cached: false, p_cached_in: cachedIn, p_cache_write: cacheWrite,
      p_cache_key: cacheKey, p_latency_ms: Date.now() - t0, p_ok: !!outMsg,
      // The generation id and OpenRouter's own charge. fn_llm_log stores both and treats the
      // generation id as unique, so a retried write of the same provider charge cannot be counted
      // twice by the accountant's daily reconciliation.
      p_generation_id: genId, p_cost_usd_reported: reportedUsd,
    });

    if (!outMsg && counterpart) {
      // the chosen reviewer (and its fallback) failed: the review is held and recorded, never silently skipped
      await rpcSafe('fn_review_hold_record', { p_task_class: route.task_class ?? null, p_fn: fnName, p_agent_key: body.agent ?? null,
        p_counterpart_model: counterpart, p_why: 'reviewer call failed: ' + String(lastErr ?? (deadlineHit ? 'deadline' : 'unknown')).slice(0, 500) });
    }
    if (!outMsg) return J({ ok: false, error: deadlineHit ? 'gateway_deadline' : 'all_models_failed',
                            detail: deadlineHit ? ('no model answered within the ' + wallBudgetMs + 'ms budget the caller waits for; last error: ' + lastErr) : lastErr,
                            ladder, caps }, 502);

    if (cacheable && cacheKey && out) {
      await rpcSafe('fn_llm_cache_store', {
        p_key: cacheKey, p_fn: fnName, p_task_class: route.task_class ?? null, p_model: used,
        // ttlMin, not body.cache_ttl_min: with the route now supplying the default, reading the
        // caller's field here would store NaN as the TTL on every route-defaulted entry.
        p_response: out, p_ttl_minutes: ttlMin, p_embedding: promptEmb,
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
               finish_reason: finishReason || undefined,
               truncated: finishReason === 'length', max_tokens: sentMaxTok,
               prompt_tokens: inTok, output_tokens: outTok, cached_input_tokens: cachedIn,
               cache_write_tokens: cacheWrite, prompt_cache: useCache,
               cost_usd: costUsd, latency_ms: Date.now() - t0 });
  } catch (e) {
    return J({ ok: false, error: String((e as Error)?.message || e) }, 500);
  }
}));
