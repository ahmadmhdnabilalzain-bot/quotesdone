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
//   - it is sent at most ONCE per turn (armHolding), and never when the reply was ready first;
//   - it never goes on email (holdingChannel): mail is answered asynchronously, nobody watches a mail thread for typing;
//   - it promises nothing the system cannot keep ("shortly", never "within a minute").
// prevented by: _shared/holding_notice.test.ts, scripts/checks/replies_are_written_by_the_model_unless_openrouter_is_down.test.mjs (R7)

/** The reply is "taking long" when it is not ready this long after the person's (last) message: ruling 1636, "about 8-10 s". */
export const HOLDING_AFTER_MS = 9_000;
/** A web chat shows its own "still working" state after this long (the widget, the portal assistant, the request chat). */
export const STILL_WORKING_MS = 8_000;

/** The one holding line per language. Suppliers are always written to in English (ruling 1008). */
export const HOLDING_LINE = {
  en: "Thank you for your message. I'm reviewing it now and will reply here shortly.",
  ar: 'شكرًا لرسالتك. أراجعها الآن، وسأوافيك بالرد هنا بعد قليل.',
} as const;

export type HoldingChannel = 'whatsapp' | 'widget' | 'portal' | 'intake' | 'email' | 'sms';
/** Which channels get a holding message at all. Email never: it is answered asynchronously. */
export function holdingChannel(channel: HoldingChannel | string): boolean {
  return channel === 'whatsapp' || channel === 'widget' || channel === 'portal' || channel === 'intake';
}

/** The line for this person: Arabic only for a customer or visitor writing in Arabic; a supplier always reads English. */
export function holdingLine(lang: string | null | undefined, audience: string | null | undefined): string {
  return lang === 'ar' && audience !== 'supplier' ? HOLDING_LINE.ar : HOLDING_LINE.en;
}

/** How long from now until the holding line is due: HOLDING_AFTER_MS after the message arrived (0 when already past). */
export function holdingDelay(arrivedAtMs: number, nowMs: number = Date.now(), afterMs = HOLDING_AFTER_MS): number {
  return Math.max(0, arrivedAtMs + afterMs - nowMs);
}

export interface Holding {
  /** The reply is ready (or the turn is over): the holding line is never sent after this. Resolves once a send in flight ends. */
  settle(): Promise<void>;
  /** Whether the holding line was sent (or is being sent) on this turn. */
  readonly fired: boolean;
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
  return {
    async settle() { if (!settled) { settled = true; clock.clearTimeout(timer); } await inFlight; },
    get fired() { return fired; },
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
  return {
    async settle() { set.delete(h); if (!set.size) armed.delete(k); await h.settle(); },
    get fired() { return h.fired; },
  };
}

/** A reply is leaving for this recipient: every holding line armed for them is settled (not sent if it has not gone yet). */
export function settleHoldingFor(to: string): void {
  const k = keyOf(to);
  const set = armed.get(k);
  if (!set) return;
  armed.delete(k);
  for (const h of set) void h.settle();
}
