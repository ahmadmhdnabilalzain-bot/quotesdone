// The per-trade "how to specify your request" guide shown in the customer's new-request form.
// Table + RLS + read routine: scripts/sql/customer_spec_guide.sql. Only a 'published' row is ever
// readable; the status check here is the second lock, so a draft never renders even if handed in.
export type SpecGuideRow = { trade?: string; body_en?: string | null; body_ar?: string | null; status?: string };

export function specGuideText(row: SpecGuideRow | null | undefined, lang: string): string | null {
  if (!row || (row.status && row.status !== 'published')) return null;
  const body = lang === 'ar' ? row.body_ar : row.body_en;
  return body && body.trim() ? body : null;
}
