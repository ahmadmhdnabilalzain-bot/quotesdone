// THE WIDGET'S STREAM CONTRACT (customer_support, 12 Oct 2026). A caller that sends `Accept: application/x-ndjson`
// gets one JSON object per line:
//   {"t":"status","text":…}   at once, before any read or model call: a fixed placeholder ("looking into it") in their
//                               language. It is an acknowledgement, NOT the answer, and is measured separately from it.
//   {"t":"delta","text":…}    the answer, a few words at a time, sent the moment the approved reply exists
//   {"t":"done", …}           the same object the plain JSON response carries (reply, scope, routed, …)
// WHAT IS NEVER STREAMED: a draft. On the widget the plain-language rewrite runs BEFORE the independent check, and
// support_reply.ts sends a reply only when that check AGREED (not run or disagreed: the deterministic road answers
// instead). The deltas are cut from that final, guarded text, so the visitor never reads words the check did not pass.
// Any caller without that Accept header gets the JSON response exactly as before.
// prevented by: site_assistant/stream_reply.test.ts, _shared/support_reply.test.ts (unchecked replies fall back)
export const STATUS = {
  en: 'Looking into that for you…',
  ar: 'لحظة من فضلك، أتحقق من ذلك…',
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

/** Status now; the deltas and `done` once the finished payload resolves. A failed payload still ends the stream. */
export function streamReply(status: string, payload: Promise<Record<string, unknown>>): ReadableStream<Uint8Array> {
  const enc = new TextEncoder();
  const line = (o: unknown) => enc.encode(JSON.stringify(o) + '\n');
  return new ReadableStream({
    async start(c) {
      c.enqueue(line({ t: 'status', text: status }));
      let done: Record<string, unknown>;
      try { done = await payload; } catch (e) { done = { error: String((e as Error)?.message || e).slice(0, 300) }; }
      if (typeof done.reply === 'string') for (const p of pieces(done.reply)) c.enqueue(line({ t: 'delta', text: p }));
      c.enqueue(line({ t: 'done', ...done }));
      c.close();
    },
  });
}

export const wantsStream = (req: Request) => (req.headers.get('accept') || '').includes('application/x-ndjson');
