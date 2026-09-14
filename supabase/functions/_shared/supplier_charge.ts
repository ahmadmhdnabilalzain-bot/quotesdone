// supplier_charge.ts — the arithmetic of the clause 33 non-response charge, and nothing else.
//
// 14 Sep 2026, agent: accountant. Supplier Agreement v10, clause 33: when a supplier never answers a
// customer who paid the reveal fee, QuotesDone refunds the customer and the supplier owes
//   (a) the exact amount refunded (3% reveal fee + the card processing fee charged on it),
//   (b) an administrative fee of AED 250, and
//   (c) simple interest on the unpaid total at the clause 31 rate — 9% per annum, "or the maximum
//       permitted by UAE law if lower" — from the due date (7 days after QuotesDone's notice) until paid.
// Every document in supplier_charge_documents.ts takes its figures from here, so the invoice, the
// reminders, the final demand and the court claim can never disagree by a fils.
//
// Money is held in fils (integers). Interest accrues per calendar day on a 365-day year:
//   interest = round( principal_fils × rate × days / 365 ),  days = whole days after the due date.
// Simple, never compounded: the clause says "simple interest", and the base is the unpaid total of
// (a)+(b) — interest is never charged on interest.

export const ADMIN_FEE_AED = 250;
export const INTEREST_RATE_PA = 0.09;
export const DAYS_IN_YEAR = 365;
export const DUE_AFTER_NOTICE_DAYS = 7;

export type ChargeInput = {
  /** What the customer was refunded, in AED: reveal fee + card processing fee (refunds_api record). */
  refunded_reveal_fee: number;
  refunded_processing_fee: number;
  /** ISO date the charge notice (the invoice) was sent. The due date is 7 days later. */
  notice_date: string;
  /** ISO date the amount is computed to. */
  as_of: string;
  /** Amounts the supplier has already paid, AED. */
  paid?: number;
};

export type Charge = {
  refunded_reveal_fee: number; refunded_processing_fee: number; non_response_charge: number;
  admin_fee: number; principal: number; paid: number; unpaid_principal: number;
  due_date: string; as_of: string; days_overdue: number;
  rate_pa: number; daily_interest: number; interest: number; total_due: number;
};

const fils = (aed: number) => Math.round(Number(aed) * 100);
const aed = (f: number) => f / 100;
const DAY = 86_400_000;
function isoDay(s: string): number {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) throw new Error('not an ISO date: ' + s);
  return Date.parse(s + 'T00:00:00Z');
}
export function addDays(iso: string, n: number): string { return new Date(isoDay(iso) + n * DAY).toISOString().slice(0, 10); }

export function computeCharge(i: ChargeInput): Charge {
  const reveal = fils(i.refunded_reveal_fee), proc = fils(i.refunded_processing_fee);
  if (!(reveal > 0) || proc < 0) throw new Error('a non-response charge needs a positive refunded reveal fee');
  const charge = reveal + proc;
  const principal = charge + fils(ADMIN_FEE_AED);
  const paid = Math.max(0, fils(i.paid ?? 0));
  const unpaid = Math.max(0, principal - paid);
  const due = addDays(i.notice_date, DUE_AFTER_NOTICE_DAYS);
  const days = Math.max(0, Math.floor((isoDay(i.as_of) - isoDay(due)) / DAY));
  // ponytail: payments are netted against principal as one sum on as_of; a part-payment mid-period
  // would need interest split by period. Add a payment schedule when the first part-payment arrives.
  const interest = Math.round(unpaid * INTEREST_RATE_PA * days / DAYS_IN_YEAR);
  return {
    refunded_reveal_fee: aed(reveal), refunded_processing_fee: aed(proc), non_response_charge: aed(charge),
    admin_fee: ADMIN_FEE_AED, principal: aed(principal), paid: aed(paid), unpaid_principal: aed(unpaid),
    due_date: due, as_of: i.as_of, days_overdue: days,
    rate_pa: INTEREST_RATE_PA, daily_interest: Math.round(unpaid * INTEREST_RATE_PA / DAYS_IN_YEAR) / 100,
    interest: aed(interest), total_due: aed(unpaid + interest),
  };
}

/** AED with thousands separators and two decimals, Western digits in both languages. */
export function money(n: number, lang: 'en' | 'ar' = 'en'): string {
  const s = Number(n).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  return lang === 'ar' ? s + ' درهم' : 'AED ' + s;
}
