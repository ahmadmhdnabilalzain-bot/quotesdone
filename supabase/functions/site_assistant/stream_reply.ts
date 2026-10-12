// THE WIDGET'S STREAM CONTRACT (customer_support, 12 Oct 2026). The reply chain is ~6 model calls (33-66 s measured),
// and the visitor stared at "Typing…" for all of it. A caller that sends `Accept: application/x-ndjson` now gets one
// JSON object per line:
//   {"t":"status","text":…}   at once, before any read or model call: an honest "looking into it", in their language
//   {"t":"delta","text":…}    the reply, a few words at a time
//   {"t":"done", …}           the same object the plain JSON response carries (reply, scope, routed, …)
// WHAT IS NEVER STREAMED: a draft. The deltas are cut from the FINAL reply — after think()'s independent check, the
// plain-language gate and guardSupportReply — so the visitor can never read text the check would have rejected. The
// first visible words are the status line, which is fixed text and carries no claim.
// Any caller without that Accept header gets the JSON response exactly as before.
// prevented by: site_assistant/stream_reply.test.ts
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
