// A WEB CHAT SAYS IT IS STILL WORKING (it_engineer, 11 Nov 2026, founder ruling 1636: "When a reply is taking long, the agent
// first sends a short professional holding message ... so the customer or supplier does not think we disconnected").
// The website widget and the portal assistant show the server's status line at once ("Writing your answer…"); when no word
// of the answer has arrived STILL_WORKING_MS after the message was sent, or the server's stream says {"t":"working"}
// (supabase/functions/_shared/stream_reply.ts), the page's own fixed "still working" line replaces it. It is the page's
// status, never a message in the conversation, and the answer still arrives in the same chat (or is read back from the
// stored conversation when the person comes back). The request chat uses the same STILL_WORKING_MS for its nr_slow line.
// 8 s is the same "about 8-10 s" the WhatsApp holding line waits (holding_notice.ts STILL_WORKING_MS).
// prevented by: src/lib/stillWorking.test.mjs
export const STILL_WORKING_MS = 8_000;

export interface StillWorking {
  /** The reader's status handler: a server status line before the late line, '' when answer text arrives. */
  status: (text: string) => void;
  /** The server's keep-alive: the late line now, if no answer text has arrived. */
  working: () => void;
  /** The turn is over: the timer is cleared. */
  stop: () => void;
}

/** Wrap a page's status setter so the fixed late line shows once the answer is slow, and never over the answer itself. */
export function stillWorking(set: (text: string) => void, late: string, ms: number = STILL_WORKING_MS,
  timers: { set: (f: () => void, ms: number) => unknown; clear: (h: unknown) => void } = { set: (f, n) => setTimeout(f, n), clear: (h) => clearTimeout(h as ReturnType<typeof setTimeout>) }): StillWorking {
  let shown = false, answering = false;
  const showLate = () => { if (!answering && !shown) { shown = true; set(late); } };
  const h = timers.set(showLate, ms);
  return {
    status: (text) => { if (text) { if (!shown) set(text); } else { answering = true; set(''); } },
    working: showLate,
    stop: () => timers.clear(h),
  };
}
