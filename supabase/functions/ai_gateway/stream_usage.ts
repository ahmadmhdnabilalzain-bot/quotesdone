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

/** The cache numbers where OpenRouter actually puts them (nested), with the flat names as a fallback. */
export function cacheTokens(u: Usage | null): { cachedIn: number; cacheWrite: number } {
  const det = (u?.prompt_tokens_details || {}) as Record<string, number>;
  return {
    cachedIn: Number(det.cached_tokens ?? u?.cache_read_input_tokens ?? u?.cached_tokens ?? 0),
    cacheWrite: Number(det.cache_write_tokens ?? u?.cache_creation_input_tokens ?? 0),
  };
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
