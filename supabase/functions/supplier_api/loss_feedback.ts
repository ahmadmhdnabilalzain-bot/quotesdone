// WIN/LOSS FEEDBACK, PER QUOTE (T3, 5 Oct 2026, sales_engineer). SupplierAdvisor shows the AGGREGATE
// ("Rejected after quoting: N"); a supplier who lost a job was never told why THAT quotation lost. This
// classifies one losing quote against the chosen one, deterministically, no model.
//
// The rival's figures enter this function and NEVER leave it: the output is a fixed code plus a fixed
// English sentence from REASONS below (suppliers are English only). No amount, no day count, no ratio,
// no name. loss_feedback.test.ts asserts the rival's amount, lead time and exclusions text appear
// nowhere in the output, for every branch.

export type QuoteFacts = { quote_amount?: number | string | null; lead_time?: string | null; exclusions?: string | null; submittable?: boolean | null };
export type LossReason = { code: string; text: string };

const REASONS: Record<string, string> = {
  price_above: "Your price was above the chosen quotation's price band.",
  price_close: "Your price was close to the chosen quotation's; it was decided on other terms.",
  lead_time_longer: "Your lead time was longer than the chosen quotation's.",
  scope_incomplete: 'Your quotation covered less of the requested scope than the chosen one.',
  overall_value: 'The customer chose another quotation on overall value.',
  closed_no_exact_spec: 'No quotation matched the exact specification, and the customer did not accept an alternative.',
  closed_no_award: 'The customer closed the request without choosing a supplier.',
};
const r = (code: string): LossReason => ({ code, text: REASONS[code] });

const num = (v: unknown): number | null => { const n = Number(v); return v != null && v !== '' && Number.isFinite(n) && n > 0 ? n : null; };

/** Days from free-text lead time ("10 days", "2 weeks", "1 month"). null when it cannot be read. */
export function leadDays(t: string | null | undefined): number | null {
  const m = String(t ?? '').toLowerCase().match(/(\d+(?:\.\d+)?)\s*(day|working day|business day|week|wk|month)?/);
  if (!m) return null;
  const n = Number(m[1]); const u = m[2] || 'day';
  return u.startsWith('week') || u === 'wk' ? n * 7 : u.startsWith('month') ? n * 30 : n;
}

const incomplete = (q: QuoteFacts) => q.submittable === false || !!String(q.exclusions ?? '').trim();

/**
 * Why `mine` lost. `chosen` is the hired supplier's quote on the same inquiry (null when nobody was
 * hired); `lostReason` is the inquiry's own lost_reason code. Free-text reasons are never echoed.
 */
export function lossFeedback(mine: QuoteFacts, chosen: QuoteFacts | null, lostReason?: string | null): LossReason[] {
  if (!chosen) {
    if (String(lostReason ?? '').startsWith('no_exact_spec')) return [r('closed_no_exact_spec')];
    return [r('closed_no_award')];
  }
  const out: LossReason[] = [];
  const a = num(mine.quote_amount), b = num(chosen.quote_amount);
  // ponytail: a fixed 5% band; tune here if suppliers read "close" too often.
  if (a != null && b != null) out.push(r(a > b * 1.05 ? 'price_above' : a >= b * 0.95 ? 'price_close' : 'overall_value'));
  const da = leadDays(mine.lead_time), db = leadDays(chosen.lead_time);
  if (da != null && db != null && da > db) out.push(r('lead_time_longer'));
  if (incomplete(mine) && !incomplete(chosen)) out.push(r('scope_incomplete'));
  // Cheaper but still lost with nothing else to say: overall value, said once.
  const codes = new Set(out.map((x) => x.code));
  const meaningful = out.filter((x) => x.code !== 'overall_value' && x.code !== 'price_close');
  if (!meaningful.length && !codes.has('price_close')) return [r('overall_value')];
  return codes.has('overall_value') ? out.filter((x) => x.code !== 'overall_value') : out;
}
