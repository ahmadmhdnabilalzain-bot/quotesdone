// supplier_charge.ts — the arithmetic of the clause 33 non-response charge, and nothing else.
//
// 14 Sep 2026, agent: accountant. Supplier Agreement clause 33 (v10, and v11 with the same numbering): when a supplier never answers a
// customer who paid the reveal fee, QuotesDone refunds the customer and the supplier owes
//   (a) the exact amount refunded (3% reveal fee + the card processing fee charged on it),
//   (b) an administrative fee — the amount in the version the supplier had accepted when the customer revealed
//       it (see adminFeeAed below), and
//   (c) simple interest on the unpaid total at the clause 31 rate — 9% per annum, "or the maximum
//       permitted by UAE law if lower" — from the due date (7 days after QuotesDone's notice) until paid.
// Every document in supplier_charge_documents.ts takes its figures from here, so the invoice, the
// reminders, the final demand and the court claim can never disagree by a fils.
//
// Money is held in fils (integers). Interest accrues per calendar day on a 365-day year:
//   interest = round( principal_fils × rate × days / 365 ),  days = whole days after the due date.
// Simple, never compounded: the clause says "simple interest", and the base is the unpaid total of
// (a)+(b) — interest is never charged on interest.

// SUPPLIER AGREEMENT v13 (23 Sep 2026, ceo; founder instruction B: penalties at the lawful maximum) raised the
// clause 33(b) administrative fee to the amount in src/content/company_facts.json (nonresponse_admin_fee_aed).
// A charge is owed under the version the supplier had accepted WHEN the customer revealed it: a supplier on v12 or
// earlier, or one who accepted v13 only after that reveal, owes that earlier version's fee. Never retroactive; when
// either date is unknown the lower fee applies. fn_accountant_nonresponse_charge applies the same rule in SQL.
export const ADMIN_FEE_AED = 250;
export const ADMIN_FEE_AED_FROM_V13 = 500;
export function adminFeeAed(acceptedVersion?: string | null, acceptedAt?: string | null, revealedAt?: string | null): number {
  const v = Number(String(acceptedVersion ?? '').replace(/\D/g, '')) || 0;
  const a = acceptedAt ? Date.parse(acceptedAt) : NaN, r = revealedAt ? Date.parse(revealedAt) : NaN;
  return v >= 13 && Number.isFinite(a) && Number.isFinite(r) && a <= r ? ADMIN_FEE_AED_FROM_V13 : ADMIN_FEE_AED;
}
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
  /** Payments received, each reducing the principal from its own date (AED, ISO date). */
  payments?: { date: string; amount: number }[];
  /** Clause 33(b) fee of the version the supplier had accepted at the reveal: adminFeeAed(). Default: the lower fee. */
  admin_fee_aed?: number;
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
  const fee = i.admin_fee_aed ?? ADMIN_FEE_AED;
  if (fee !== ADMIN_FEE_AED && fee !== ADMIN_FEE_AED_FROM_V13) throw new Error('an administrative fee no signed version names: ' + fee);
  const principal = charge + fils(fee);
  const due = addDays(i.notice_date, DUE_AFTER_NOTICE_DAYS);
  const dueT = isoDay(due), asT = isoDay(i.as_of);
  const days = Math.max(0, Math.floor((asT - dueT) / DAY));
  // A day-by-day ledger: interest on each period's outstanding principal, from the due date (or the
  // later payment date) to the next payment or as_of. A payment reduces principal from ITS date only;
  // anything beyond the principal settles accrued interest. Calendar days (UTC dates), so a span over
  // 29 February counts that day; the year stays 365 days, as the formula in the documents states.
  const pays = (i.payments ?? []).filter((p) => isoDay(p.date) <= asT && fils(p.amount) > 0)
    .map((p) => ({ t: isoDay(p.date), f: fils(p.amount) })).sort((a, b) => a.t - b.t);
  let outstanding = principal, accrued = 0, from = dueT, paid = 0, overpay = 0;
  for (const p of pays) {
    const to = Math.max(dueT, p.t);
    if (to > from) { accrued += outstanding * INTEREST_RATE_PA * ((to - from) / DAY) / DAYS_IN_YEAR; from = to; }
    const onPrincipal = Math.min(outstanding, p.f);
    outstanding -= onPrincipal; overpay += p.f - onPrincipal; paid += p.f;
  }
  if (asT > from) accrued += outstanding * INTEREST_RATE_PA * ((asT - from) / DAY) / DAYS_IN_YEAR;
  const interest = Math.max(0, Math.round(accrued) - overpay);
  const unpaid = outstanding;
  return {
    refunded_reveal_fee: aed(reveal), refunded_processing_fee: aed(proc), non_response_charge: aed(charge),
    admin_fee: fee, principal: aed(principal), paid: aed(paid), unpaid_principal: aed(unpaid),
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
