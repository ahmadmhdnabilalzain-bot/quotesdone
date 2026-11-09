// ai_gateway/caller.ts — who the caller CLAIMS to be, for the run row. Moved verbatim from index.ts (9 Nov 2026).

// THE CALLER IS ON EVERY RUN ROW, REFUSED OR NOT (it_engineer, 5 Oct 2026; LLM burn audit R6). 11,686 runs on
// 28-29 Sep carried only http/method/path, so the burst had no name until the edge logs were read: one Node client on
// a UAE address re-embedding ~6,200 knowledge rows through {action:'embed'}, free and never routed to a model. Each
// run row now says which fn the caller CLAIMS to be, the action and the task class it asked for. Claimed, not proven:
// these keys are for attribution only and decide nothing (observe.statusOf reads only the handler's own 'held').
export const claimedCaller = (b: Record<string, unknown>) => ({
  claimed_fn: String(b?.fn ?? 'unknown').slice(0, 80),
  claimed_action: String(b?.action ?? 'chat').slice(0, 20),
  claimed_task_class: b?.task_class == null ? null : String(b.task_class).slice(0, 60),
});
