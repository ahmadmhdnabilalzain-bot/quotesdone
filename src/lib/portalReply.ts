// THE PORTAL ASSISTANT'S ANSWER, READ AS IT IS WRITTEN (customer_support, 27 Oct 2026).
// sales_engineer `assist` streams the same contract as the website widget (supabase/functions/_shared/stream_reply.ts):
//   {"t":"status"} a UI status line at once · {"t":"delta"} each checked sentence · {"t":"reset"} the model rewrote its
//   answer, drop what was shown · {"t":"done", reply, ...} the final, approved text.
// The rules this reader keeps, because each was a way a customer saw something they should not:
//   - only approved words are shown: a reset clears them, and `done` without a reply clears them too (a stream the
//     server's clock cut is never left on screen as if it were the answer);
//   - a transport failure is NEVER thrown to the panel. On 27 Oct a 150 s edge timeout returned a 504 page that is not
//     JSON; `r.json()` threw and the panel printed "Something went wrong" mid-conversation. Here it reads as "no reply
//     yet" ({ reply: '' }) and the panel decides what to do (it looks for the stored answer; it never shows an error).
// prevented by: scripts/checks/the_portal_chat_never_shows_an_error_for_a_slow_turn.test.mjs
export interface ReplyHandlers { status?: (text: string) => void; text?: (soFar: string) => void }
export interface ReadReply { reply: string; streamed: boolean; done: Record<string, unknown> | null; failed: string | null }

export async function readReply(r: Response, on: ReplyHandlers = {}): Promise<ReadReply> {
  try {
    if (r.body && (r.headers.get('content-type') || '').includes('ndjson')) {
      const rd = r.body.getReader(); const dec = new TextDecoder();
      let buf = '', text = '', done: Record<string, unknown> | null = null;
      const line = (l: string) => {
        if (!l.trim()) return;
        let e: Record<string, unknown>;
        try { e = JSON.parse(l); } catch (_e) { return; }
        if (e.t === 'status') on.status?.(String(e.text || ''));
        else if (e.t === 'reset') { text = ''; on.text?.(''); }
        else if (e.t === 'delta') { text += String(e.text || ''); on.status?.(''); on.text?.(text); }
        else if (e.t === 'done') done = e;
      };
      try {
        for (;;) {
          const { done: end, value } = await rd.read();
          if (end) break;
          buf += dec.decode(value, { stream: true });
          let k: number;
          while ((k = buf.indexOf('\n')) >= 0) { line(buf.slice(0, k)); buf = buf.slice(k + 1); }
        }
        line(buf);
      } catch (e) {
        on.text?.('');
        return { reply: '', streamed: true, done: null, failed: 'stream cut: ' + String((e as Error)?.message || e) };
      }
      const reply = typeof (done as Record<string, unknown> | null)?.reply === 'string' ? String((done as Record<string, unknown>).reply).trim() : '';
      if (!reply) on.text?.('');
      return { reply, streamed: true, done, failed: reply ? null : 'no reply in done' };
    }
    const raw = await r.text();
    let j: Record<string, unknown> | null = null;
    try { j = JSON.parse(raw); } catch (_e) { j = null; }
    const reply = typeof j?.reply === 'string' ? j.reply.trim() : '';
    return { reply, streamed: false, done: j, failed: reply ? null : (j ? 'no reply' : 'HTTP ' + r.status + ', not JSON') };
  } catch (e) {
    return { reply: '', streamed: false, done: null, failed: String((e as Error)?.message || e) };
  }
}

/** The newest assistant turn after the customer's message, from assist_history's turns ('' when none yet). */
export function answerAfter(turns: { role?: string; content?: string }[] | null | undefined, question: string): string {
  if (!Array.isArray(turns)) return '';
  let i = -1;
  for (let k = turns.length - 1; k >= 0; k--) if (turns[k]?.role === 'user' && String(turns[k]?.content || '').trim() === question.trim()) { i = k; break; }
  if (i < 0) return '';
  const a = turns.slice(i + 1).find((x) => x?.role === 'assistant' && String(x?.content || '').trim());
  return a ? String(a.content).trim() : '';
}
