// THE PORTAL CHAT TURN'S CLOCK, RULES AND FACTS (customer_support owns the conversation, it_engineer the latency;
// 27 Oct 2026). The pure half of sales_engineer's `assist` action, kept apart so it is tested without a network.
//
// WHY A CLOCK. The edge runtime answers 504 when a function has sent nothing for 150 s, and the portal then prints its
// error line in the middle of a customer's conversation. Measured on production (ZZ DEMO wardrobe replay, 27 Oct
// 07:41-08:13Z): the old turn took 58-150 s and one hit the wall. The new turn is one streamed model call, so a normal
// answer starts in a few seconds; PORTAL_TURN_MS bounds the WORST case (the model ladder: stream, rewrites, retry,
// another family) so even a caller that does not stream gets its JSON well inside the wall.
// prevented by: sales_engineer/portal_turn.test.ts, _shared/brief_answer.test.ts

/** Every model call of one portal turn starts and ends inside this, counted from the request's arrival. Under half the
 *  150 s edge wall, so a non-streaming caller also has its answer (or its notice) long before a 504 could happen. */
export const PORTAL_TURN_MS = 70_000;

/** The portal's format, added to the shared conversation rules (ai_reply.aiSystem). */
export function portalRules(): string {
  return 'Plain text for the portal chat window: no markdown, no bullets, no headings, under about 120 words. The person is signed in to their own account: never tell them to log in or to sign up.';
}

/** A reply wrapped as data is refused sentence by sentence and rewritten by the model, never shown (27 Oct 2026: the first
 *  streamed portal turns read {"answer":"..."} because the shared rules asked for JSON; aiSystem's plainText now says
 *  otherwise, and this keeps a model that answers in JSON anyway off the customer's screen). */
export function wrappedReply(text: string): string[] {
  return /^\s*(```|\{\s*"|\[\s*\{)/.test(text) || /"answer"\s*:/.test(text)
    ? ['it wraps the reply in JSON or a code fence; write only the plain reply text'] : [];
}

/** One retrieved record, as fn_sales_assist returns it. */
export interface Record_ { title?: unknown; content?: unknown; corpus?: unknown; record_id?: unknown }

/** At most this many retrieved records, each at most RECORD_CHARS, ride with the message. The old turn sent the plan's
 *  per-step retrieval as well (up to 36 sources of 2,400 characters); the answer prompt reached 62k tokens. */
export const MAX_RECORDS = 5;
export const RECORD_CHARS = 1200;
export const FACTS_CHARS = 6000;

/** The facts block for this turn: the customer's own quotes first, then this seat's retrieved records. '' when neither. */
export function portalFacts(o: { facts?: string | null; passages?: Record_[] | null }): string {
  const recs = (o.passages ?? [])
    .map((x) => [String(x.title ?? '').trim(), String(x.content ?? '').trim()].filter(Boolean).join('\n').slice(0, RECORD_CHARS))
    .filter(Boolean).slice(0, MAX_RECORDS);
  const parts = [
    o.facts && o.facts.trim() ? o.facts.trim() : '',
    recs.length ? "THE SALES ENGINEER'S RECORDS FOR THIS QUESTION (use what answers it; ignore the rest):\n" + recs.map((r, i) => `[${i + 1}] ${r}`).join('\n\n') : '',
  ].filter(Boolean);
  return parts.length ? ("THIS CONVERSATION'S FACTS:\n" + parts.join('\n\n')).slice(0, FACTS_CHARS) : '';
}
