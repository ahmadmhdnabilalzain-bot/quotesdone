// QUOTE EXPIRY, the customer-facing half of it.
//
// customer_api action=my_inquiries computes BOTH `expires_at` and a server-side `expired` verdict
// for every quote it serves (supabase/functions/customer_api/index.ts, the my_inquiries row mapper)
// and the portal warned about neither. A customer could pay a non-refundable reveal fee on a price
// that lapsed days ago and find that out from the supplier.
//
// WHICH CLOCK DECIDES WHAT. `expired` is the server comparing expires_at against its own clock, so
// it — never the browser — decides the past/not-past question. A device with a wrong date therefore
// cannot invent an expiry or hide one. The browser clock is used only to phrase how much time a
// still-valid quote has left, where being a few hours out changes nothing the customer would act on.
//
// This lives in its own file rather than in CustomerPortal.tsx so it can be executed:
//   node --test src/components/me/quoteExpiry.test.mjs

export type ExpiryTone = 'expired' | 'soon' | 'ok';

export type ExpiryNotice = { tone: ExpiryTone; text: string };

/** The quote fields this reads, exactly as my_inquiries emits them. */
export type ExpiringQuote = {
  expires_at?: string | null;
  /** The server's verdict, not a re-derivation. Authoritative for expired/not-expired. */
  expired?: boolean | null;
};

export function expiryOf(
  q: ExpiringQuote | null | undefined,
  lang: string,
  now: number = Date.now(),
): ExpiryNotice | null {
  if (!q || !q.expires_at) return null;
  const ms = new Date(q.expires_at).getTime();
  if (!Number.isFinite(ms)) return null;
  const ar = lang === 'ar';
  const d = new Date(ms).toLocaleDateString(ar ? 'ar-AE' : 'en-GB', { day: 'numeric', month: 'short', year: 'numeric' });

  if (q.expired) {
    return {
      tone: 'expired',
      text: ar
        ? `انتهت صلاحية هذا العرض في ${d} — اطلب من المورّد تأكيده من جديد قبل أن تدفع لكشفه.`
        : `This quote expired on ${d} — ask the supplier to re-confirm the price before you pay to reveal them.`,
    };
  }

  // CALENDAR days, not fractions of one. Math.ceil((ms - now) / 86400e3) reads 1 for a quote six
  // hours away, which printed "expires on 6 Aug 2026 — 1 day left" on 6 Aug: the countdown and the
  // date in the same sentence contradicted each other, and the customer with hours to act was told
  // they had a day. Comparing midnights makes the number agree with the date being printed beside
  // it, and both use local time, as toLocaleDateString above does.
  const dayStart = (t: number) => { const x = new Date(t); x.setHours(0, 0, 0, 0); return x.getTime(); };
  const days = Math.round((dayStart(ms) - dayStart(now)) / 86400e3);
  // days <= 0 without the server calling it expired means the deadline is inside today, or the two
  // clocks disagree by a few hours. Either way "today" is the honest phrasing; claiming it has
  // expired would contradict the only authority on that question.
  if (days <= 0) {
    return { tone: 'soon', text: ar ? 'تنتهي صلاحية هذا العرض اليوم.' : 'This quote expires today.' };
  }
  if (days <= 3) {
    return {
      tone: 'soon',
      text: ar
        ? `تنتهي صلاحية هذا العرض في ${d} — بقي ${days} يوم.`
        : `This quote expires on ${d} — ${days} day${days === 1 ? '' : 's'} left.`,
    };
  }
  return { tone: 'ok', text: ar ? `صالح حتى ${d}` : `Valid until ${d}` };
}
