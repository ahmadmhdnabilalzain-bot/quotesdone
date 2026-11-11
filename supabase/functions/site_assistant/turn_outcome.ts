// THE WIDGET TURN HAS A CLOCK, AND IT NEVER ENDS IN A RAW 5xx (it_engineer, 11 Nov 2026, load test, founder ruling 1622:
// "100 customers chatting at the same time must not crash the company").
//
// Measured on production, 11 Nov 2026 01:26-01:30 UTC, 10 then 50 concurrent website chats with the model stubbed
// (_shared/load_stub.ts, a 6-10 s canned reply): 14 of 139 turns came back HTTP 503 after 35-54 s in-region. Every one was
// site_assistant's OWN `no_answer` (agent_runs, 14 rows, the same ladder each time: "stream:figures it is not in Arabic ... |
// rewrite:ok | rewrite:ok | retry:ok | third:failed ... | again:ok"). The stub wrote English into an Arabic conversation, the
// language check refused each draft, and answerFromBrief walked its whole ladder — six model calls one after another — because
// site_assistant, unlike the portal (sales_engineer/portal_turn.ts PORTAL_TURN_MS), gave it NO deadline. Those six-call turns
// are the run's p95 of 41-46 s against a stub that never takes more than 10 s, and they kept their worker's requests in
// flight four times longer, which is how worker 0a9a57bc held ten turns when it crossed its 2 s CPU budget (HTTP 546 x 10).
//
// So: (1) the turn is given SITE_TURN_MS. answerFromBrief bounds every call by what is left and starts none with less than
// MIN_CALL_MS left, so the worst turn is about SITE_TURN_MS instead of six model calls. (2) A turn with no reply is answered
// HTTP 200: the polite busy line when no model was reached (founder_instruction 1339's outage, which includes our own
// deadline; through modelOrOutage, never otherwise), or no text and error 'no_answer' when the model was up and every draft
// was refused (the widget shows its own line; code writes no reply while the model is up). The failure is still recorded:
// index.ts writes agent_runs status 'error' for it, the row fn_watch_failed_runs pages on.
// prevented by: site_assistant/turn_outcome.test.ts
import { MIN_CALL_MS, PER_CALL_MS, RESERVE_MS } from '../_shared/brief_answer.ts';
import { modelOrOutage } from '../_shared/openrouter_down.ts';

/** The whole widget turn, from the request to the last model call's end. The streamed first call gets up to
 *  SITE_TURN_MS - RESERVE_MS (a Sonnet visitor answer of <= 700 tokens is written in 10-25 s), and one more rung still has
 *  room after it. The load driver waits 60 s and the edge's idle wall is 150 s; the portal, which reads records, has 70 s. */
export const SITE_TURN_MS = 35_000;

/** The body of a turn that produced no reply. Always HTTP 200 (see the header). `busy` is visitor_scope.busyReply. */
export function unansweredTurn(a: { reply?: string | null; outage?: boolean; attempts: string[] }, busy: string): Record<string, unknown> {
  const notice = modelOrOutage({ reply: '', outage: a.outage }, busy);
  return { reply: notice, error: 'no_answer', outage: a.outage === true, degraded: true, attempts: a.attempts };
}

// The clock's own arithmetic, pinned by turn_outcome.test.ts: the first call can run longer than a stub turn and a slow real
// answer, and the reserve it keeps back is enough to start one more call.
export const CLOCK = { SITE_TURN_MS, PER_CALL_MS, RESERVE_MS, MIN_CALL_MS } as const;
