// project_budget.ts — the ONE rule for a project's total budget (projects.budget_total), shared by
// project_api (the trust boundary) and the portal's ProjectForm (which only says it earlier).
//
// MEASURED 21 Sep 2026 (customer-portal journey audit): project_api wrote Number(body.budget_total)
// straight into an unconstrained numeric column. A negative figure was stored as given, a figure of
// any size was stored, and free text became Number('abc') = NaN — which Postgres numeric ACCEPTS as
// the value 'NaN', so a project could carry a budget of "not a number" and every committed-% on the
// page divided by it. The form's min/max attributes were the only bound, and a request does not go
// through a form. Now: empty means "no budget"; otherwise a plain AED amount, more than 0, at most
// AED 1,000,000,000, at most two decimals. Anything else is refused with words in both languages.
// scripts/sql/a_project_budget_is_a_positive_bounded_aed_amount.sql puts the same bound on the column.
export const BUDGET_MAX_AED = 1_000_000_000;

export type BudgetResult = { ok: true; value: number | null } | { ok: false; code: 'budget_invalid'; en: string; ar: string };

const REFUSE = (en: string, ar: string): BudgetResult => ({ ok: false, code: 'budget_invalid', en, ar });

/** undefined → leave unchanged is the caller's concern; '' / null → no budget; else a bounded AED amount. */
export function parseBudget(v: unknown): BudgetResult {
  if (v === null || v === undefined) return { ok: true, value: null };
  // An array or object is not a number even when String() makes it look like one ([1] → '1').
  const s = typeof v === 'string' || typeof v === 'number' ? String(v).replace(/[\s,]/g, '') : 'x';
  if (s === '') return { ok: true, value: null };
  // Digits with an optional two-place fraction (a leading minus is read so it can be refused as
  // not positive). No exponent, no "NaN", no "Infinity", no words.
  if (!/^-?\d+(?:\.\d{1,2})?$/.test(s)) {
    return REFUSE('Enter the budget as a number in AED, for example 250000.', 'أدخل الميزانية رقمًا بالدرهم الإماراتي، مثل 250000.');
  }
  const n = Number(s);
  if (!(n > 0)) return REFUSE('The budget must be more than AED 0. Leave it empty if there is no budget yet.', 'يجب أن تكون الميزانية أكبر من صفر درهم. اترك الحقل فارغًا إن لم تُحدَّد الميزانية بعد.');
  if (n > BUDGET_MAX_AED) return REFUSE('The budget cannot exceed AED 1,000,000,000.', 'لا يمكن أن تتجاوز الميزانية 1,000,000,000 درهم.');
  return { ok: true, value: n };
}
