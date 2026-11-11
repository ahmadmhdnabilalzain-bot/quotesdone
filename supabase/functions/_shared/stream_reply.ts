// THE CHAT STREAM CONTRACT (customer_support, 12 Oct 2026; founder rulings 1195/1196). Spoken by site_assistant (the
// website widget) and, since 27 Oct 2026, by sales_engineer's portal `assist` (src/lib/portalReply.ts reads it); it moved
// here from site_assistant/ so both functions import one copy. A caller that sends
// `Accept: application/x-ndjson` gets one JSON object per line:
//   {"t":"status","text":…}   at once: a UI status line ("writing your answer"), NOT a reply and never counted as one.
//   {"t":"delta","text":…}    each sentence of the model's answer the moment it is written and has passed the figure
//                               check and the reply guard (brief_answer.ts). Unchecked words are never sent.
//   {"t":"reset"}             the model rewrote its answer (a figure or rule failed): drop what was shown; the
//                               rewritten answer follows as deltas.
//   {"t":"done", …}           the same object the plain JSON response carries; done.reply is the final text.
//   {"t":"working"}           (11 Nov 2026, founder ruling 1636) every STILL_WORKING_MS while no sentence of the answer has
//                               been sent: a keep-alive, so neither the browser nor a proxy reads the long wait as a dead
//                               connection, and the page shows its own "still working" line. It carries no text.
// Any caller without that Accept header gets the JSON response exactly as before.
// THE PERSON MAY LEAVE THE PAGE (ruling 1636: "if the person left the page, it is there when they return"). A write to a
// stream whose reader went away throws; it is caught, and the answer is still written to the conversation by `run`, which
// is held open with EdgeRuntime.waitUntil, so the widget's history read and the portal's assist_history find it later.
// prevented by: _shared/stream_reply.test.ts, _shared/brief_answer.test.ts
import { STILL_WORKING_MS as HOLDING_STILL_WORKING_MS } from './holding_notice.ts';
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
export function streamReply(status: string, run: (emit: (text: string) => void) => Promise<Record<string, unknown>>, workingEveryMs = STILL_WORKING_MS): ReadableStream<Uint8Array> {
  const enc = new TextEncoder();
  const line = (o: unknown) => enc.encode(JSON.stringify(o) + '\n');
  let gone = false;
  return new ReadableStream({
    async start(c) {
      // a reader that went away (the person left the page) makes enqueue throw: the answer is still finished and stored
      const put = (o: unknown) => { if (gone) return; try { c.enqueue(line(o)); } catch (_e) { gone = true; } };
      put({ t: 'status', text: status });
      let live = '';
      const emit = (text: string) => { if (text) { live += text; put({ t: 'delta', text }); } };
      const keepAlive = setInterval(() => { if (!live) put({ t: 'working' }); }, Math.max(1_000, workingEveryMs));
      let done: Record<string, unknown>;
      const running = run(emit);
      keepRunning(running);
      try { done = await running; } catch (e) { done = { error: String((e as Error)?.message || e).slice(0, 300) }; } finally { clearInterval(keepAlive); }
      if (typeof done.reply === 'string' && done.reply !== live.trim()) {
        if (live) put({ t: 'reset' });
        for (const p of pieces(done.reply)) put({ t: 'delta', text: p });
      }
      put({ t: 'done', ...done });
      if (!gone) { try { c.close(); } catch (_e) { /* already closed by the reader */ } }
    },
    cancel() { gone = true; },
  });
}
/** The keep-alive interval: the same "about 8 s" the pages wait before they show "still working" (holding_notice.ts). */
export const STILL_WORKING_MS = HOLDING_STILL_WORKING_MS;
/** Hold the worker open until the answer is written, even when nobody is reading the stream any more. */
function keepRunning(p: Promise<unknown>): void {
  // deno-lint-ignore no-explicit-any
  const er = (globalThis as any).EdgeRuntime;
  if (er && typeof er.waitUntil === 'function') { try { er.waitUntil(p.catch(() => null)); } catch (_e) { /* outside the edge runtime */ } }
}

export const wantsStream = (req: Request) => (req.headers.get('accept') || '').includes('application/x-ndjson');
