// WHILE HIS PROFILE IS BEING READ, THE SERVICES TAB ASKS AGAIN, AND THE LIST IS DRAWN FROM THE ANSWER THAT SAYS IT IS READY
// (12 Nov 2026, sales_engineer; built by it_engineer). Pure, no React, so src/components/portal/supplier/servicesPoll.test.mjs can
// fail it with a fake clock. Node strips the types on import, so nothing here imports an alias.
//
// MEASURED: certification J9 after #1973 (tag in the coordinator's recheck/paid_J9_b.log). The list was STORED 117.1 s after the
// upload and on his screen at 130.3 s, 13.2 s later, against the 120 s bar. Per stub at the live supplier_api's delays (0.3-1 s
// warm, 3-4 s cold or inside the five-minute relay hold), that gap was three waits in a row: the 5 s poll (2.5 s on average, 5 s
// at worst), the poll's services_state, and then a SECOND full services_state (`load({ keepText: true })`) before anything was
// drawn. Two changes, no extra load on the server:
//   1. the poll's own answer is the services_state the list is drawn from, so a finished reading is drawn from it: one request,
//      never two;
//   2. once step A has landed (`reading_progress` on the state: only the mapping is left, 10-30 s), it asks every 2 s instead of 5.
//      Before that (step A takes about 60-90 s) it stays at 5 s.
// It stops after 10 minutes, as the 120 polls of 5 s did, and the moment the reading is finished.

export const POLL_SLOW_MS = 5000;
export const POLL_FAST_MS = 2000;
export const POLL_FOR_MS = 10 * 60_000;

type DocLike = { kind?: string; status?: string } | null | undefined;
type StateLike = { ok?: boolean; reading_progress?: unknown; capability?: { source_docs?: { docs?: DocLike[] } } | null } | null | undefined;

/** A profile document is still being read. */
export const profileReading = (s: StateLike): boolean => !!s?.capability?.source_docs?.docs?.some((x) => !!x && x.kind === 'profile' && x.status === 'reading');
/** Step A has landed: the summary is stored and only the mapping is left. */
export const stepALanded = (s: StateLike): boolean => !!s?.reading_progress;
export const pollDelayMs = (mappingOnly: boolean): number => (mappingOnly ? POLL_FAST_MS : POLL_SLOW_MS);
/** The progress on screen changed: anything else is no new render (and no new status for the dashboard). */
export const sameProgress = (a: unknown, b: unknown): boolean => JSON.stringify(a ?? null) === JSON.stringify(b ?? null);

export type ReadingPollDeps = {
  fetchState: () => Promise<any>;
  /** what is on screen now has step A's summary (read on every arm, so a progress set elsewhere speeds the next ask) */
  mappingOnly: () => boolean;
  /** step A's progress on a poll that is still reading */
  onProgress: (progress: unknown) => void;
  /** the reading has finished: this answer is the whole state, drawn as it is. Returns false when it was NOT drawn (a later-asked
   *  answer is on screen, which may say a new reading started): the poll then keeps asking instead of stopping. */
  onFinished: (state: any) => boolean | void;
  setTimer?: (fn: () => void, ms: number) => unknown;
  clearTimer?: (id: unknown) => void;
  now?: () => number;
};

/** Starts asking; returns the stop function (the effect's cleanup). */
export function startReadingPoll(d: ReadingPollDeps): () => void {
  const setT = d.setTimer ?? ((fn: () => void, ms: number) => setTimeout(fn, ms));
  const clearT = d.clearTimer ?? ((id: unknown) => clearTimeout(id as ReturnType<typeof setTimeout>));
  const now = d.now ?? (() => Date.now());
  const started = now();
  let stopped = false;
  let id: unknown = null;
  // the cadence runs from the START of the previous ask, so a slow answer (3-4 s on a cold start) is not followed by a further full wait;
  // one ask at a time, never two in flight, so it never asks more often than the cadence
  const arm = (fast: boolean, askedAt: number) => { if (stopped || now() - started >= POLL_FOR_MS) return; id = setT(tick, Math.max(0, askedAt + pollDelayMs(fast) - now())); };
  const tick = async () => {
    id = null;
    const askedAt = now();
    const j = await d.fetchState().catch(() => null);
    if (stopped) return;
    // (review of #1976: stopping before the tab decided left the poll dead when the draw was refused and the screen still said "reading")
    if (j && j.ok && !profileReading(j)) { if (d.onFinished(j) !== false) { stopped = true; return; } }
    else if (j && j.ok && stepALanded(j)) d.onProgress(j.reading_progress);
    arm(d.mappingOnly() || !!(j && j.ok && stepALanded(j)), askedAt);
  };
  arm(d.mappingOnly(), now());
  return () => { stopped = true; if (id !== null) clearT(id); };
}

// AN OLDER ANSWER NEVER REDRAWS THE SCREEN (12 Nov 2026, review of #1975, item 1). Every services_state the tab asks for (its load and
// this poll) takes the next number; a full draw is allowed only for an answer asked after the last one drawn, so whichever lands
// last, the screen shows the newest state asked for. A failed load says so only when it was the latest ask.
export function answerOrder() {
  let asked = 0, drawn = 0;
  return {
    ask: (): number => ++asked,
    /** may this answer be drawn in full? (and it is now the one on screen) */
    draw: (n: number): boolean => { if (n <= drawn) return false; drawn = n; return true; },
    /** asked after what is on screen (a partial update, such as step A's progress, that does not replace it) */
    newer: (n: number): boolean => n > drawn,
    latest: (n: number): boolean => n === asked,
  };
}
