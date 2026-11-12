// _shared/holding_notice.ts — when a reply is taking long, a short holding line goes first (it_engineer, 11 Nov 2026).
//
// Founder ruling 1636 (11 Nov 2026), verbatim: "When a reply is taking long, the agent first sends a short professional
// holding message (for example that it is working on it and will come back shortly) so the customer or supplier does not
// think we disconnected. Then the full reply follows." It pairs with ruling 1630: a complicated question may take 30-40 s.
//
// MEASURED (docs/reports/2026-11-11-history-and-effort.md, wa_inbound timings): the WhatsApp classification alone is
// 11-24 s and the reply 2-20 s, so a typed question is answered 20-40 s after it arrives and, until now, the person saw
// nothing at all in that time.
//
// WHY THIS LINE IS FIXED TEXT AND NOT THE MODEL'S (founder ruling 1339: "the engineer and customer support never replies
// without llm unless the server of open router is down"). The holding line is not a reply. It answers nothing, states no
// fact, promises no time, and is sent only WHILE the model's reply is still being written; the model's reply always
// follows and is the answer. It is a status notice of the same kind as the held notice (ruling 1197) and the chat
// widget's "Still working on your answer…". Writing it with the model would cost a model call that takes seconds,
// which is exactly the wait it exists to cover, and it would be missing when the model is slow, which is when it is
// needed. Ruling 1636 is the founder's own instruction to send it before the reply exists. So it is one fixed,
// reviewed line per language, the only text this module owns, and it is never used as, or in place of, an answer:
//   - it is sent at most ONCE per person per quiet window (HOLDING_QUIET_MIN, wa_inbound/holding.ts reads the person's earlier
//     holding lines first), never when the reply was ready first, and in a wording the person did not get last time;
//   - it never goes on email: mail is answered asynchronously, nobody watches a mail thread for typing (no mail function
//     imports this module; holding_notice.test.ts reads them);
//   - it promises nothing the system cannot keep ("shortly", never "within a minute").
// prevented by: _shared/holding_notice.test.ts, scripts/checks/replies_are_written_by_the_model_unless_openrouter_is_down.test.mjs (R7)

/** The reply is "taking long" when it is not ready this long after the person's (last) message (ruling 1636).
 *  15 s, was 9 s (final audit 12 Nov 2026, W2). Measured on production 11 Nov: at 9 s the line went before 29 of 29 typed
 *  replies, because none was ready by then (p50 30 s); the last WhatsApp reply before the 11 Nov changes took 12.1 s, and
 *  the effort fix of the same round aims ordinary replies at 10-15 s. At 9 s such a reply would be preceded by a line that
 *  says nothing, three to six seconds before the answer; at 15 s it goes only before a reply that really is long (a
 *  complaint: 48-72 s measured), early enough that the person is not left wondering for half a minute. */
export const HOLDING_AFTER_MS = 15_000;
/** At most one holding line to the same person inside this many minutes: in a live conversation they know we answer, and the
 *  same reassurance before every reply reads as a machine (ruling 1631: never repeat). */
export const HOLDING_QUIET_MIN = 30;
/** A web chat shows its own "still working" state after this long (the widget, the portal assistant, the request chat). */
export const STILL_WORKING_MS = 8_000;

/** The holding lines per language, reviewed wordings of the same status notice. Suppliers are always written to in English
 *  (ruling 1008). A person is given a wording they were not given last time (holdingLine `avoid`), so a returning person does
 *  not read the same sentence every time (final audit 12 Nov 2026: one fixed sentence before 29 of 29 replies). */
export const HOLDING_LINE = {
  en: [
    "Thank you for your message. I'm reviewing it now and will reply here shortly.",
    "Thanks, I have your message. I'm checking the details and will come back to you here in a moment.",
    "Thank you for your patience. I'm preparing your answer and will send it here shortly.",
  ],
  ar: [
    'شكرًا لرسالتك. أراجعها الآن، وسأوافيك بالرد هنا بعد قليل.',
    'وصلتني رسالتك، وأتحقق الآن من التفاصيل، وسأعود إليك هنا بعد قليل.',
    'شكرًا لصبرك. أُعدّ لك الرد الآن، وسيصلك هنا بعد قليل.',
  ],
} as const;

/** The line for this person: Arabic only for a customer or visitor writing in Arabic; a supplier always reads English. The
 *  first wording that is not among `avoid` (the lines this person was given recently, newest first); when all were, the one
 *  given longest ago. */
export function holdingLine(lang: string | null | undefined, audience: string | null | undefined, avoid: readonly string[] = []): string {
  const lines: readonly string[] = lang === 'ar' && audience !== 'supplier' ? HOLDING_LINE.ar : HOLDING_LINE.en;
  const fresh = lines.find((l) => !avoid.includes(l));
  if (fresh) return fresh;
  return [...lines].sort((a, b) => avoid.indexOf(b) - avoid.indexOf(a))[0];
}

/** How long from now until the holding line is due: HOLDING_AFTER_MS after the message arrived (0 when already past). */
export function holdingDelay(arrivedAtMs: number, nowMs: number = Date.now(), afterMs = HOLDING_AFTER_MS): number {
  return Math.max(0, arrivedAtMs + afterMs - nowMs);
}

export interface Holding {
  /** The reply is ready (or the turn is over): the holding line is never sent after this. Resolves once a send in flight ends. */
  settle(): Promise<void>;
  /** A reply LEFT for this person (sendWa): settles, and records that the holding line, if it went, was followed by an answer. */
  answer(): Promise<void>;
  /** Whether the holding line was sent (or is being sent) on this turn. */
  readonly fired: boolean;
  /** Whether a reply left for this person after the line was armed. */
  readonly answered: boolean;
}
export interface HoldingClock {
  setTimeout: (f: () => void, ms: number) => unknown;
  clearTimeout: (h: unknown) => void;
}
const realClock: HoldingClock = {
  setTimeout: (f, ms) => setTimeout(f, ms),
  clearTimeout: (h) => clearTimeout(h as number),
};

/** Arm the holding line for one turn. `send` runs at most once, only if `settle` has not been called by then; it is handed
 *  `stillDue`, which turns false the moment the reply is ready, so a send that first reads something can still stand down. */
export function armHolding(o: { delayMs: number; send: (stillDue: () => boolean) => Promise<unknown>; clock?: HoldingClock }): Holding {
  const clock = o.clock ?? realClock;
  let settled = false, fired = false;
  let inFlight: Promise<unknown> = Promise.resolve();
  const timer = clock.setTimeout(() => {
    if (settled || fired) return;
    fired = true;
    inFlight = o.send(() => !settled).catch(() => null);   // a failed holding line never costs the turn its reply
  }, Math.max(0, o.delayMs));
  let answered = false;
  const settle = async () => { if (!settled) { settled = true; clock.clearTimeout(timer); } await inFlight; };
  return {
    settle,
    async answer() { answered = true; await settle(); },
    get fired() { return fired; },
    get answered() { return answered; },
  };
}

// ---- per-recipient registry: any reply that leaves for a person settles the holding line armed for them ----------------
// The holding line is armed where the model is asked (wa_inbound/say.ts) and settled at the one door every WhatsApp text
// leaves through (wa_inbound/replies.ts sendWa), so whichever branch of the turn answers, the line can never follow it.
const armed = new Map<string, Set<Holding>>();
const keyOf = (to: string) => String(to || '').replace(/[^0-9]/g, '').slice(-9);

/** Remember a holding line armed for this recipient, so `settleHoldingFor` reaches it. */
export function registerHolding(to: string, h: Holding): Holding {
  const k = keyOf(to);
  if (!k) return h;
  const set = armed.get(k) ?? new Set<Holding>();
  set.add(h);
  armed.set(k, set);
  const forget = () => { set.delete(h); if (!set.size && armed.get(k) === set) armed.delete(k); };
  return {
    async settle() { forget(); await h.settle(); },
    async answer() { forget(); await h.answer(); },
    get fired() { return h.fired; },
    get answered() { return h.answered; },
  };
}

/** A reply is LEAVING for this recipient: every holding line armed for them is settled (not sent if it has not gone yet).
 *  It stays armed-and-known until the send's outcome: only a delivered reply answers it (answeredHoldingFor). */
export function settleHoldingFor(to: string): void {
  const set = armed.get(keyOf(to));
  if (!set) return;
  for (const h of set) void h.settle();
}

/** A reply was DELIVERED to this recipient (the send succeeded, or a fixture number captured it): the holding line armed for
 *  them was followed by an answer. A failed send answers nothing, so the turn's end files the re-ask (12 Nov 2026 review). */
export function answeredHoldingFor(to: string): void {
  const k = keyOf(to);
  const set = armed.get(k);
  if (!set) return;
  armed.delete(k);
  for (const h of set) void h.answer();
}
