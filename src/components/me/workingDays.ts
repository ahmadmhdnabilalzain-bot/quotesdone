// THE REVEAL GUARANTEE CLOCK.
//
// The refund promise is a working-day ladder (pricing_config, 14 Sep 2026: chase at 3, final call
// at 5, bank 7-14). "Day N of 5" on the customer's own revealed job is only worth showing if it is
// counted the way the sweep counts it, so the rule lives here where it can be executed:
//   node --test src/components/me/workingDays.test.mjs
//
// Working days are Monday to Friday (the founder's definition), counted on the Dubai calendar
// (UTC+4, no daylight saving), and the payment day itself is day 0: the clock starts the next
// working day. A payment on Friday evening is still at day 0 on Sunday.

const DUBAI_OFFSET_MS = 4 * 3600e3;
const DAY_MS = 86400e3;
const dubaiDay = (ms: number) => Math.floor((ms + DUBAI_OFFSET_MS) / DAY_MS);

/** Mon–Fri days strictly after the payment day, up to and including today. null when unparseable. */
export function workingDaysSince(fromIso: string | null | undefined, nowMs: number = Date.now()): number | null {
  const from = Date.parse(String(fromIso || ''));
  if (!Number.isFinite(from)) return null;
  let n = 0;
  const end = dubaiDay(nowMs);
  // ponytail: a day-by-day walk, capped at ~2 years; the ladder only ever reads the first 5.
  for (let d = dubaiDay(from) + 1, i = 0; d <= end && i < 800; d++, i++) {
    const w = new Date(d * DAY_MS).getUTCDay();
    if (w !== 0 && w !== 6) n++;
  }
  return n;
}

export type GuaranteeTerms = { window_days: number | null; chase_after_days: number | null; bank_min_days?: number | null; bank_max_days?: number | null };
export type GuaranteeFacts = { revealed_at: string | null; supplier_ack_at?: string | null; refund_status?: string | null };
export type GuaranteePhase = 'waiting' | 'chased' | 'final_call' | 'acknowledged' | 'refund';
export type GuaranteeClock = { day: number; of: number; elapsed: number; phase: GuaranteePhase };

/** Where the customer's own reveal sits on the ladder, or null when a term was not served. */
export function guaranteeClock(g: GuaranteeFacts | null | undefined, terms: GuaranteeTerms | null | undefined, nowMs: number = Date.now()): GuaranteeClock | null {
  const of = Number(terms && terms.window_days);
  const chase = Number(terms && terms.chase_after_days);
  if (!g || !(of > 0) || !(chase > 0)) return null;
  const elapsed = workingDaysSince(g.revealed_at, nowMs);
  if (elapsed == null) return null;
  const phase: GuaranteePhase = g.refund_status ? 'refund'
    : g.supplier_ack_at ? 'acknowledged'
    : elapsed >= of ? 'final_call'
    : elapsed >= chase ? 'chased'
    : 'waiting';
  return { day: Math.min(elapsed, of), of, elapsed, phase };
}
