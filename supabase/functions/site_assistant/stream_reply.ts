// THE WIDGET'S STREAM CONTRACT (customer_support, 12 Oct 2026; founder rulings 1195/1196). A caller that sends
// `Accept: application/x-ndjson` gets one JSON object per line:
//   {"t":"status","text":…}   at once: a UI status line ("writing your answer"), NOT a reply and never counted as one.
//   {"t":"delta","text":…}    each sentence of the model's answer the moment it is written and has passed the figure
//                               check and the reply guard (brief_answer.ts). Unchecked words are never sent.
//   {"t":"reset"}             the model rewrote its answer (a figure or rule failed): drop what was shown; the
//                               rewritten answer follows as deltas.
//   {"t":"done", …}           the same object the plain JSON response carries; done.reply is the final text.
// Any caller without that Accept header gets the JSON response exactly as before.
// prevented by: site_assistant/stream_reply.test.ts, _shared/brief_answer.test.ts
export const STATUS = {
  en: 'Writing your answer…',
  ar: 'جارٍ كتابة الإجابة…',
} as const;

/** The reply in pieces of a few words, whitespace kept, so the pieces join back to exactly the reply. */
export function pieces(text: string, words = 4): string[] {
  const parts = String(text || '').match(/\S+\s*/g) ?? [];
  const lead = String(text || '').match(/^\s*/)?.[0] ?? '';
  const out: string[] = [];
  for (let i = 0; i < parts.length; i += words) out.push(parts.slice(i, i + words).join(''));
  if (lead && out.length) out[0] = lead + out[0];
  return out;
}

/** Status now; checked sentences as the answer is written (emit); then `done`. A reply that was not emitted live (a
 *  rewrite, a retry on another model) is sent in pieces before done, and done.reply is always the final text, so the
 *  widget shows exactly what was approved. A failed run still ends the stream. */
export function streamReply(status: string, run: (emit: (text: string) => void) => Promise<Record<string, unknown>>): ReadableStream<Uint8Array> {
  const enc = new TextEncoder();
  const line = (o: unknown) => enc.encode(JSON.stringify(o) + '\n');
  return new ReadableStream({
    async start(c) {
      c.enqueue(line({ t: 'status', text: status }));
      let live = '';
      const emit = (text: string) => { if (text) { live += text; c.enqueue(line({ t: 'delta', text })); } };
      let done: Record<string, unknown>;
      try { done = await run(emit); } catch (e) { done = { error: String((e as Error)?.message || e).slice(0, 300) }; }
      if (typeof done.reply === 'string' && done.reply !== live.trim()) {
        if (live) c.enqueue(line({ t: 'reset' }));
        for (const p of pieces(done.reply)) c.enqueue(line({ t: 'delta', text: p }));
      }
      c.enqueue(line({ t: 'done', ...done }));
      c.close();
    },
  });
}

export const wantsStream = (req: Request) => (req.headers.get('accept') || '').includes('application/x-ndjson');
