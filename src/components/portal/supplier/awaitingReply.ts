// awaitingReply — is the quotation chat waiting for the engineer's answer to the supplier's last message? (3 Nov 2026)
// A turn the model did not answer is re-asked (_shared/reask.ts) and its answer is posted into the thread later, so the
// chat must keep reading the thread while it waits. Bounded: only while the supplier's message is under 5 minutes old.
import type { ThreadView } from './quoteReviewApi';

export const AWAIT_REPLY_MS = 5 * 60_000;
export function awaitingReply(th: Pick<ThreadView, 'state' | 'reviewing' | 'messages'> | null | undefined, now = Date.now()): boolean {
  if (!th || th.reviewing || th.state === 'submitted' || th.state === 'closed') return false;
  const last = th.messages[th.messages.length - 1];
  if (!last || last.role !== 'supplier') return false;
  const age = now - Date.parse(last.created_at);
  return Number.isFinite(age) && age >= 0 && age < AWAIT_REPLY_MS;
}
