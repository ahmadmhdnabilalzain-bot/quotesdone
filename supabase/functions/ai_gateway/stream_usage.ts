// THE STREAMED CALL'S REAL USAGE (sales_engineer, 13 Oct 2026). The streaming path handed OpenRouter's SSE body
// straight back and logged 0 input, 0 output and 0 cost "because token counts are not available on the stream
// path". They are: OpenRouter's final chunk carries `usage` (prompt, completion, prompt_tokens_details.cached_tokens
// and cache_write_tokens, cost) and the generation `id`. Measured live on 13 Oct: every widget reply on
// anthropic/claude-sonnet-5.5 (ruling 1219) was booked at AED 0, so the cost per 1,000 replies and the share read
// from the prompt cache could not be measured at all.
//
// tapUsage passes every byte through unchanged and reads the SSE lines as they go by. When the stream ends it calls
// `done` once with what it saw; when the caller abandons the stream (brief_answer stops a sentence that fails the
// figure check) the upstream read is cancelled, so generation and billing still stop, and `done` is called with
// cancelled = true and whatever usage had arrived (usually none: it comes in the last chunk).
// prevented by: ai_gateway/stream_usage.test.ts

// deno-lint-ignore no-explicit-any
export type Usage = Record<string, any>;
export interface StreamSeen { usage: Usage | null; id: string | null; finish: string | null; cancelled: boolean; error: string | null }

/** Feed SSE text; returns the unfinished tail. Fills `seen` from every `data:` JSON line. */
export function readSse(buf: string, seen: StreamSeen): string {
  let k: number;
  while ((k = buf.indexOf('\n')) >= 0) {
    const line = buf.slice(0, k).trim(); buf = buf.slice(k + 1);
    if (!line.startsWith('data:')) continue;              // ': OPENROUTER PROCESSING' keep-alives and blanks
    const data = line.slice(5).trim();
    if (!data || data === '[DONE]') continue;
    try {
      const j = JSON.parse(data);
      if (j?.usage && typeof j.usage === 'object') seen.usage = j.usage;
      if (typeof j?.id === 'string' && j.id) seen.id = j.id;
      const fr = j?.choices?.[0]?.finish_reason ?? j?.choices?.[0]?.native_finish_reason;
      if (fr) seen.finish = String(fr);
      if (j?.error) seen.error = JSON.stringify(j.error).slice(0, 300);
    } catch (_e) { /* a partial or foreign line is not usage */ }
  }
  return buf;
}

/** The cache numbers where OpenRouter actually puts them (nested), with the flat names as a fallback.
 *  No usage block = unknown (null), never 0: an unmeasured call must not read as a free one. */
export function cacheTokens(u: Usage | null): { cachedIn: number | null; cacheWrite: number | null } {
  if (!u) return { cachedIn: null, cacheWrite: null };
  const det = (u?.prompt_tokens_details || {}) as Record<string, number>;
  return {
    cachedIn: Number(det.cached_tokens ?? u?.cache_read_input_tokens ?? u?.cached_tokens ?? 0),
    cacheWrite: Number(det.cache_write_tokens ?? u?.cache_creation_input_tokens ?? 0),
  };
}

/**
 * A STREAM THAT ENDED WITHOUT ITS USAGE CHUNK IS PRICED FROM OPENROUTER'S OWN RECORD (it_engineer, 3 Nov 2026). Measured:
 * USD 11.79 billed in 7 days that ai_cost_log never saw; streamed replies abandoned or cut before the last chunk were
 * part of it ("NO USAGE CHUNK: tokens and cost unknown"). The generation id is kept, and GET /api/v1/generation?id=
 * answers the tokens and the charge once OpenRouter has written it (a second or two after the stream ends, so it is
 * asked up to `tries` times). Null when it never answers: unknown stays unknown, never zero.
 */
export async function generationUsage(
  id: string, key: string, f: typeof fetch = fetch, tries = 3, pauseMs = 1500,
): Promise<Usage | null> {
  for (let i = 0; i < tries; i++) {
    if (i) await new Promise((r) => setTimeout(r, pauseMs));
    try {
      const r = await f('https://openrouter.ai/api/v1/generation?id=' + encodeURIComponent(id), { headers: { Authorization: 'Bearer ' + key }, signal: AbortSignal.timeout(5000) });
      if (!r.ok) continue;
      const d = (await r.json().catch(() => null))?.data;
      if (!d) continue;
      const pt = Number(d.native_tokens_prompt ?? d.tokens_prompt), ct = Number(d.native_tokens_completion ?? d.tokens_completion);
      if (!Number.isFinite(pt) && !Number.isFinite(Number(d.total_cost))) continue;
      return { prompt_tokens: Number.isFinite(pt) ? pt : null, completion_tokens: Number.isFinite(ct) ? ct : null,
        cost: Number.isFinite(Number(d.total_cost)) ? Number(d.total_cost) : null,
        prompt_tokens_details: { cached_tokens: Number(d.native_tokens_cached ?? 0) || 0, cache_write_tokens: 0 }, from_generation: true };
    } catch (_e) { /* try again */ }
  }
  return null;
}

export function tapUsage(body: ReadableStream<Uint8Array>, done: (s: StreamSeen) => Promise<void> | void): ReadableStream<Uint8Array> {
  const src = body.getReader(); const dec = new TextDecoder();
  const seen: StreamSeen = { usage: null, id: null, finish: null, cancelled: false, error: null };
  let buf = ''; let finished = false;
  const finish = () => {
    if (finished) return; finished = true;
    const p = Promise.resolve().then(() => done(seen)).catch(() => { /* logging never breaks the reply */ });
    // keep the worker alive until the ledger is written
    // deno-lint-ignore no-explicit-any
    try { (globalThis as any).EdgeRuntime?.waitUntil?.(p); } catch (_e) { /* not on the edge runtime */ }
  };
  return new ReadableStream<Uint8Array>({
    async pull(c) {
      try {
        const { done: end, value } = await src.read();
        if (end) { buf = readSse(buf + '\n', seen); c.close(); finish(); return; }
        buf = readSse(buf + dec.decode(value, { stream: true }), seen);
        c.enqueue(value);
      } catch (e) { seen.error = String((e as Error)?.message || e).slice(0, 300); c.error(e); finish(); }
    },
    async cancel(reason) {
      seen.cancelled = true;
      try { await src.cancel(reason); } catch (_e) { /* already closed */ }
      finish();
    },
  });
}
