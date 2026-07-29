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
//
// 29 JUL 2026 — llmCall(). makeLlm covers "system prompt in, text out", which is most of the
// company but not all of it. The ~33 functions that stayed on hand-rolled fetches needed
// something makeLlm cannot express: an image, an audio blob, the OpenRouter web plugin, a
// tool-calling loop, or a JSON schema. llmCall is that shape - one request object, the gateway's
// full reply back (content, tool_calls, annotations, cost). makeLlm is now a wrapper over it, so
// there is exactly one place that knows how to talk to the gateway.
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

// deno-lint-ignore no-explicit-any
export type Msg = { role: string; content?: any; [k: string]: unknown };

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

// Everything makeLlm can express, plus the modalities it cannot.
export interface LlmRequest extends LlmDefaults {
  sys?: string;
  input?: string | Msg[];
  messages?: Msg[];              // full OpenAI array; required for a tool-calling loop
  // deno-lint-ignore no-explicit-any
  plugins?: any[];               // [{ id:'web', max_results:5 }] or the file-parser plugin
  // deno-lint-ignore no-explicit-any
  tools?: any[];
  // deno-lint-ignore no-explicit-any
  toolChoice?: any;
  // deno-lint-ignore no-explicit-any
  responseFormat?: any;          // { type:'json_object' } or a json_schema
  requireCaps?: string[];        // normally inferred by the gateway from the payload
  wantMessage?: boolean;         // return the assistant message verbatim (tool_calls included)
  dryRun?: boolean;              // decide and report, spend nothing
  escalate?: boolean;
}

export interface LlmResult {
  ok: boolean;
  used_llm?: boolean;
  outcome?: string;              // level0 | cache_exact | cache_semantic | generated | refused_* | budget_halted
  content?: string | null;
  // deno-lint-ignore no-explicit-any
  message?: any;
  // deno-lint-ignore no-explicit-any
  tool_calls?: any[];
  // deno-lint-ignore no-explicit-any
  annotations?: any[];           // web-plugin source citations
  model?: string;
  tier?: string;
  task_class?: string;
  caps?: string[];
  cost_usd?: number | null;
  why?: string;
  error?: string;
  [k: string]: unknown;
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

// Vision and web-plugin turns are genuinely slower than chat. The gateway allows itself 55s on
// those paths, so a 30s client timeout here would abort a call the company has already paid for.
function defaultTimeout(r: LlmRequest): number {
  if (r.timeoutMs) return r.timeoutMs;
  const heavy = (r.plugins && r.plugins.length) || JSON.stringify(r.messages ?? r.input ?? '').includes('"image_url"')
             || JSON.stringify(r.messages ?? r.input ?? '').includes('"input_audio"');
  return heavy ? 70000 : 25000;
}

// The one place that knows the gateway's wire format. Never throws; returns null only when the
// gateway itself was unreachable or refused the secret.
export async function llmCall(r: LlmRequest): Promise<LlmResult | null> {
  const ac = new AbortController();
  const to = setTimeout(() => ac.abort(), defaultTimeout(r) + 5000);
  try {
    const secret = await sec('inbound_secret');
    if (!secret) return null;

    const res = await fetch(GATEWAY, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        __secret: secret,
        fn: r.fn || guessFn(),
        task_class: r.taskClass ?? null,
        dept: r.dept ?? null,
        agent: r.agent ?? null,
        sys: r.sys ?? '',
        input: r.input ?? null,
        messages: r.messages ?? null,
        max: r.max ?? null,
        temperature: r.temperature ?? null,
        confidence: r.confidence ?? null,
        cache_ttl_min: r.cacheTtlMin ?? 0,
        try_faq: r.tryFaq === true,
        rate_key: r.rateKey ?? null,
        rate_limit: r.rateLimit ?? null,
        rate_window_s: r.rateWindowS ?? null,
        plugins: r.plugins ?? null,
        tools: r.tools ?? null,
        tool_choice: r.toolChoice ?? null,
        response_format: r.responseFormat ?? null,
        require_caps: r.requireCaps ?? null,
        want_message: r.wantMessage === true,
        dry_run: r.dryRun === true,
        escalate: r.escalate === true,
      }),
      signal: ac.signal,
    });
    return (await res.json().catch(() => null)) as LlmResult | null;
  } catch (_e) {
    return null;
  } finally {
    clearTimeout(to);
  }
}

export function makeLlm(models: string[] = SONNET_FIRST, def: LlmDefaults = {}) {
  const dMax = def.max ?? 700;
  const fnName = def.fn || guessFn();

  return async function llm(sys: string, input: string | Msg[], max: number = dMax): Promise<string | null> {
    const j = await llmCall({ ...def, fn: fnName, sys, input, max });
    if (!j) return null;

    // A deterministic refusal or a budget halt is a legitimate "no". Returning null here is
    // correct and matches the old contract: callers already handle a null model response.
    if (j.used_llm === false && !j.content) return null;

    return typeof j.content === 'string' ? j.content : null;
  };
}

// Convenience for the document functions: a prompt plus one or more images or files, back as text.
// Written once here rather than eleven times across the extraction functions, all of which had
// their own slightly different retry ladder.
export async function llmVision(
  prompt: string,
  parts: Array<{ imageUrl?: string; fileName?: string; fileData?: string }>,
  opts: LlmRequest = {},
): Promise<LlmResult | null> {
  // deno-lint-ignore no-explicit-any
  const content: any[] = [{ type: 'text', text: prompt }];
  // deno-lint-ignore no-explicit-any
  const plugins: any[] = [];
  for (const p of parts) {
    if (p.imageUrl) content.push({ type: 'image_url', image_url: { url: p.imageUrl } });
    else if (p.fileData) {
      content.push({ type: 'file', file: { filename: p.fileName || 'document.pdf', file_data: p.fileData } });
      // The file-parser plugin is what turns a PDF into something the model can read. Requested
      // once even when several files are attached; OpenRouter applies it per request, not per file.
      if (!plugins.length) plugins.push({ id: 'file-parser', pdf: { engine: 'pdf-text' } });
    }
  }
  return await llmCall({
    ...opts,
    fn: opts.fn || guessFn(),
    messages: [{ role: 'user', content }],
    plugins: opts.plugins ?? (plugins.length ? plugins : undefined),
  });
}

// Grounded research through OpenRouter's web plugin, with the source URLs the citation-checkers
// need. kb_deepen, kb_fill_gap and learn_gaps all hand-rolled this; they disagreed on max_results.
export async function llmWeb(
  sys: string,
  input: string,
  opts: LlmRequest & { maxResults?: number } = {},
): Promise<LlmResult | null> {
  const j = await llmCall({
    ...opts,
    fn: opts.fn || guessFn(),
    sys, input,
    plugins: [{ id: 'web', max_results: opts.maxResults ?? 5 }],
  });
  if (!j) return null;
  // deno-lint-ignore no-explicit-any
  const urls = (j.annotations || []).map((a: any) => a?.url_citation?.url || a?.url).filter(Boolean);
  return { ...j, sources: urls };
}
