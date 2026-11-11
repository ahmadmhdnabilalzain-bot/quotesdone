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
// {"t":"working"} (11 Nov 2026, founder ruling 1636): the server's keep-alive while no sentence has been sent; `working` lets the page
// show its own "still working" line (src/lib/stillWorking.ts). It carries no text and is never shown as part of the answer.
export interface ReplyHandlers { status?: (text: string) => void; text?: (soFar: string) => void; working?: () => void }
export interface ReadReply { reply: string; streamed: boolean; done: Record<string, unknown> | null; failed: string | null }

export async function readReply(r: Response, on: ReplyHandlers = {}): Promise<ReadReply> {
  try {
    if (r.body && (r.headers.get('content-type') || '').includes('ndjson')) {
      const rd = r.body.getReader(); const dec = new TextDecoder();
      let buf = '', text = '';
      const end: { done: Record<string, unknown> | null } = { done: null };   // set inside line(); an object so the type is not narrowed to null
      const line = (l: string) => {
        if (!l.trim()) return;
        let e: Record<string, unknown>;
        try { e = JSON.parse(l); } catch (_e) { return; }
        if (e.t === 'status') on.status?.(String(e.text || ''));
        else if (e.t === 'working') on.working?.();
        else if (e.t === 'reset') { text = ''; on.text?.(''); }
        else if (e.t === 'delta') { text += String(e.text || ''); on.status?.(''); on.text?.(text); }
        else if (e.t === 'done') end.done = e;
      };
      try {
        for (;;) {
          const { done: fin, value } = await rd.read();
          if (fin) break;
          buf += dec.decode(value, { stream: true });
          let k: number;
          while ((k = buf.indexOf('\n')) >= 0) { line(buf.slice(0, k)); buf = buf.slice(k + 1); }
        }
        line(buf);
      } catch (e) {
        on.text?.('');
        return { reply: '', streamed: true, done: null, failed: 'stream cut: ' + String((e as Error)?.message || e) };
      }
      const done = end.done;
      const reply = typeof done?.reply === 'string' ? done.reply.trim() : '';
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

// THE "YOUR QUESTION IS SAVED" LINE IS FOR OPENROUTER BEING DOWN, NOT FOR THE MODEL'S WORDS BEING REFUSED (founder_instruction
// 1339, 27 Oct 2026, verbatim: "the engineer and customer support never replies without llm unless the server of open router
// is down"). The line is the panel's own text, so it is shown only when:
//   - the answer never arrived (noVerdict: the connection dropped, a 504 page, a stream with no `done`, or a server error
//     before the model was asked) and the stored answer was not found either; or
//   - the server said OpenRouter was down: done.outage === true (supabase/functions/_shared/openrouter_down.ts).
// When the model was up (done.error 'no_answer' without outage: every draft refused, its passing sentences salvaged where
// any passed, and the model asked once more), the panel shows no code-written text at all. Measured before: the panel
// showed the saved line on every reply-less turn, the model-up case included.
/** The server gave no considered answer: transport failure, or an error before the model ladder ran. */
export function noVerdict(r: ReadReply): boolean {
  return !r.done || String(r.done.error ?? '') !== 'no_answer';
}
/** Whether the panel may show its own "saved" line for this turn. `reply` is what was finally found (the stored answer). */
export function savedLineDue(r: ReadReply, reply: string = r.reply): boolean {
  if (String(reply || '').trim()) return false;
  return noVerdict(r) || r.done?.outage === true;
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

// THE TURN STILL OWED THE MODEL'S ANSWER (27 Oct 2026; supabase/functions/_shared/reask.ts). With the model up and every
// draft refused, the server files the turn for the asynchronous re-ask and says done.pending. The panel then shows
// "still working on your answer" — UI state, never a turn of the conversation and never sent back as history — and polls
// assist_history until the re-asked reply fills that turn (answerRightAfter), or shows that the turn is with the team.
// prevented by: scripts/checks/a_refused_turn_is_asked_again_never_left_silent.test.mjs
/** The server filed this turn for the re-ask: show the pending state and wait for its answer. */
export function pendingDue(r: ReadReply): boolean {
  return !String(r.reply || '').trim() && r.done?.pending === true;
}
/** The reply stored DIRECTLY under the customer's message (before their next message), '' when none yet. A pending turn
 *  is answered in its own row, so a reply to a LATER message is never taken for it (answerAfter would). */
export function answerRightAfter(turns: { role?: string; content?: string }[] | null | undefined, question: string): string {
  if (!Array.isArray(turns)) return '';
  for (let k = turns.length - 1; k >= 0; k--) {
    if (turns[k]?.role !== 'user' || String(turns[k]?.content || '').trim() !== question.trim()) continue;
    const n = turns[k + 1];
    return n && n.role === 'assistant' ? String(n.content || '').trim() : '';
  }
  return '';
}
export type Waiting = { id?: number; message: string; state: 'working' | 'with_team'; since?: string };
/** assist_history's waiting list (newest first), read defensively. */
export function waitingOf(j: unknown): Waiting[] {
  const w = (j as { waiting?: unknown } | null)?.waiting;
  return Array.isArray(w)
    ? w.filter((x) => x && typeof x.message === 'string' && x.message.trim())
      .map((x) => ({ id: x.id, message: String(x.message), state: x.state === 'with_team' ? 'with_team' as const : 'working' as const, since: x.since }))
    : [];
}
/** How often, and for how long, the panel asks while a turn is pending (the re-ask runs each minute, three times). */
export const PENDING_EVERY_MS = 10_000;
export const PENDING_FOR_MS = 20 * 60_000;

// THE STORED ANSWER IS LOOKED FOR, ON THE PORTAL AND ON THE WEBSITE WIDGET (customer_support, 2 Nov 2026).
// The server stores every turn under the conversation even when the connection to the browser drops (a 504 page, a cut
// stream). The portal looked for that answer; the website widget did not and printed its error line over an answer the
// database already held, which reappeared only after a reload. One loop now serves both: readTurns returns the stored
// turns (assist_history on the portal, action 'history' on the widget) or null; the answer is the first assistant turn
// after the LAST copy of the question. '' when none arrives inside waitMs; the caller then says what it says.
// prevented by: scripts/checks/the_widget_finds_a_stored_answer_and_redraws_its_history.test.mjs
export async function lookForStoredAnswer(
  readTurns: () => Promise<{ role?: string; content?: string }[] | null | undefined>,
  question: string,
  o: { waitMs?: number; everyMs?: number; sleep?: (ms: number) => Promise<void>; now?: () => number } = {},
): Promise<string> {
  const { waitMs = 90_000, everyMs = 6_000, sleep = (ms: number) => new Promise<void>((res) => setTimeout(res, ms)), now = Date.now } = o;
  const until = now() + waitMs;
  while (now() < until) {
    await sleep(everyMs);
    try { const a = answerAfter(await readTurns(), question); if (a) return a; } catch (_e) { /* asked again on the next tick */ }
  }
  return '';
}

/** Whether the server holds this question in the stored conversation (a user turn with exactly these words). It looks twice, so
 *  a read that blipped is not reported as a lost question. "Saved" is said of a question only when this is true. */
export async function lookForStoredQuestion(
  readTurns: () => Promise<{ role?: string; content?: string }[] | null | undefined>,
  question: string,
  o: { tries?: number; everyMs?: number; sleep?: (ms: number) => Promise<void> } = {},
): Promise<boolean> {
  const { tries = 2, everyMs = 2_000, sleep = (ms: number) => new Promise<void>((res) => setTimeout(res, ms)) } = o;
  for (let i = 0; i < tries; i++) {
    try {
      const t = await readTurns();
      if (Array.isArray(t) && t.some((x) => x?.role === 'user' && String(x?.content || '').trim() === question.trim())) return true;
    } catch (_e) { /* looked at again */ }
    if (i < tries - 1) await sleep(everyMs);
  }
  return false;
}
