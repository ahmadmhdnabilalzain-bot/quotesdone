// supplier_charge.ts — the arithmetic of the clause 33 non-response charge, and nothing else.
//
// 14 Sep 2026, agent: accountant. Supplier Agreement clause 33 (v10, and v11 with the same numbering): when a supplier never answers a
// customer who paid the reveal fee, QuotesDone refunds the customer and the supplier owes
//   (a) the exact amount refunded (the 3% reveal fee, and any card fee on a reveal paid before 24 Sep
//       2026, when buyers still paid one),
//   (b) from v14 only: the processor fee QuotesDone paid on the refunded reveal and could not recover,
//   (c) an administrative fee — the amount in the version the supplier had accepted when the customer revealed
//       it (see termsAt below), and
//   (d) simple interest on the unpaid total at the clause 31 rate, charged at the 0.09 lawful ceiling for every version (v14 writes 12% "or the maximum
//       permitted by UAE law if lower", and 9% is that maximum) — from the due date (7 days after QuotesDone's notice) until paid.
// Every document in supplier_charge_documents.ts takes its figures from here, so the invoice, the
// reminders, the final demand and the court claim can never disagree by a fils.
//
// Money is held in fils (integers). Interest accrues per calendar day on a 365-day year:
//   interest = round( principal_fils × rate × days / 365 ),  days = whole days after the due date.
// Simple, never compounded: the clause says "simple interest", and the base is the unpaid total of
// (a)+(b)+(c) — interest is never charged on interest. Before v14 the letters were (a) refund, (b) admin fee,
// (c) interest; the documents print the letters of the version the supplier signed (Charge.terms_version).

// SUPPLIER AGREEMENT v13 (23 Sep 2026, ceo; founder instruction B: penalties at the lawful maximum) raised the
// clause 33(b) administrative fee to the amount in src/content/company_facts.json (nonresponse_admin_fee_aed).
// A charge is owed under the version the supplier had accepted WHEN the customer revealed it: a supplier on v12 or
// earlier, or one who accepted v13 only after that reveal, owes that earlier version's fee. Never retroactive; when
// either date is unknown the lower fee applies. fn_accountant_nonresponse_charge applies the same rule in SQL.
export const ADMIN_FEE_AED = 250;
export const ADMIN_FEE_AED_FROM_V13 = 500;
// SUPPLIER AGREEMENT v14 (24 Sep 2026, ceo; founder instruction 990: the maximum UAE law safely allows). For a
// supplier who accepted v14 before the reveal: (b) the processor fee QuotesDone paid on the refunded reveal and could
// not recover (Stripe keeps it on a refund; transactions.stripe_fee_fils) is owed at its recorded amount, and interest
// is the AGREED 12% (Commercial Transactions Law 50/2022 Arts. 72, 73, 84: 9% is only the ceiling where no rate is
// agreed). Earlier versions keep 9% and no processor-fee head. termsAt() is the one rule; fn_accountant_nonresponse_charge
// applies it in SQL. Reasoning: docs/legal/NONRESPONSE_MAX_V14.md.
export const INTEREST_RATE_PA = 0.09;
export const INTEREST_RATE_PA_FROM_V14 = 0.12; // the rate the v14 TEXT writes; never the rate charged (below)
// THE CEILING (30 Sep 2026, accountant; founder ruling: a 0.09 annual rate, simple, the maximum lawful). v14 writes "12% ... or the
// maximum permitted by UAE law if lower", and 9% is that maximum, so no version is ever charged more than 9%.
// fn_accountant_nonresponse_charge applies the same cap (scripts/sql/no_supplier_is_charged_interest_above_nine_percent_a_year.sql).
export const MAX_LAWFUL_RATE_PA = 0.09;
export type Terms = { version: number; admin_fee: number; rate_pa: number; processor_fee_owed: boolean };
/** The clause 33 terms of the version the supplier had accepted WHEN the customer revealed it; unknown dates = the lowest. */
export function termsAt(acceptedVersion?: string | null, acceptedAt?: string | null, revealedAt?: string | null): Terms {
  const v = Number(String(acceptedVersion ?? '').replace(/\D/g, '')) || 0;
  const a = acceptedAt ? Date.parse(acceptedAt) : NaN, r = revealedAt ? Date.parse(revealedAt) : NaN;
  const eff = Number.isFinite(a) && Number.isFinite(r) && a <= r ? v : 0;
  return {
    version: eff,
    admin_fee: eff >= 13 ? ADMIN_FEE_AED_FROM_V13 : ADMIN_FEE_AED,
    rate_pa: Math.min(eff >= 14 ? INTEREST_RATE_PA_FROM_V14 : INTEREST_RATE_PA, MAX_LAWFUL_RATE_PA),
    processor_fee_owed: eff >= 14,
  };
}
export function adminFeeAed(acceptedVersion?: string | null, acceptedAt?: string | null, revealedAt?: string | null): number {
  return termsAt(acceptedVersion, acceptedAt, revealedAt).admin_fee;
}
export const DAYS_IN_YEAR = 365;
export const DUE_AFTER_NOTICE_DAYS = 7;

export type ChargeInput = {
  /** What the customer was refunded, in AED: the reveal fee, and any card processing fee a pre-24-Sep-2026 reveal carried. */
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
  /** v14 clause 33(b): the processor fee QuotesDone paid on the refunded reveal and could not recover (AED); only when termsAt().processor_fee_owed. */
  unrecovered_processor_fee?: number;
  /** Clause 31 rate of the version the supplier had accepted at the reveal: termsAt().rate_pa. Default: 9%. */
  rate_pa?: number;
  /** termsAt().version: decides the clause 33 lettering the documents print. Default: 0 (pre-v14 lettering). */
  terms_version?: number;
};

export type Charge = {
  refunded_reveal_fee: number; refunded_processing_fee: number; non_response_charge: number;
  unrecovered_processor_fee: number; admin_fee: number; principal: number; paid: number; unpaid_principal: number;
  due_date: string; as_of: string; days_overdue: number;
  rate_pa: number; daily_interest: number; interest: number; total_due: number; terms_version: number;
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
  const asked = i.rate_pa ?? INTEREST_RATE_PA;
  if (asked !== INTEREST_RATE_PA && asked !== INTEREST_RATE_PA_FROM_V14) throw new Error('an interest rate no signed version names: ' + asked);
  const rate = Math.min(asked, MAX_LAWFUL_RATE_PA);
  const unrec = fils(i.unrecovered_processor_fee ?? 0);
  if (unrec < 0) throw new Error('a processor fee cannot be negative');
  const principal = charge + unrec + fils(fee);
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
    if (to > from) { accrued += outstanding * rate * ((to - from) / DAY) / DAYS_IN_YEAR; from = to; }
    const onPrincipal = Math.min(outstanding, p.f);
    outstanding -= onPrincipal; overpay += p.f - onPrincipal; paid += p.f;
  }
  if (asT > from) accrued += outstanding * rate * ((asT - from) / DAY) / DAYS_IN_YEAR;
  const interest = Math.max(0, Math.round(accrued) - overpay);
  const unpaid = outstanding;
  return {
    refunded_reveal_fee: aed(reveal), refunded_processing_fee: aed(proc), non_response_charge: aed(charge), unrecovered_processor_fee: aed(unrec),
    admin_fee: fee, principal: aed(principal), paid: aed(paid), unpaid_principal: aed(unpaid),
    due_date: due, as_of: i.as_of, days_overdue: days,
    terms_version: i.terms_version ?? 0, rate_pa: rate, daily_interest: Math.round(unpaid * rate / DAYS_IN_YEAR) / 100,
    interest: aed(interest), total_due: aed(unpaid + interest),
  };
}

/** AED with thousands separators and two decimals, Western digits in both languages. */
export function money(n: number, lang: 'en' | 'ar' = 'en'): string {
  const s = Number(n).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  return lang === 'ar' ? s + ' درهم' : 'AED ' + s;
}
