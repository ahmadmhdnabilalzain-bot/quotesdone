// T3 — A SUPPLIER'S QUOTE TEMPLATE IS STRUCTURE, NEVER PRICE (sales_engineer, 5 Oct 2026).
// A template carries the parts of a quotation a supplier retypes on every job: line headings, terms,
// warranty, validity, inclusions, exclusions, payment terms. It carries NO price. The founder removed
// reusable price lists; a price belongs to one inquiry and is quoted fresh on it. So:
//   - only the eight keys below are ever kept (no amount, no unit_price, no qty — they are dropped);
//   - a text that states a figure next to a currency ("AED 45", "1,200 dhs", "45/m2") is refused,
//     not trimmed, so the supplier sees why rather than a silently changed template.
// The table enforces the same refusal in a CHECK (scripts/sql/supplier_quote_templates_carry_structure_never_price.sql),
// so a write that bypasses this file still cannot store a price.
export const TEMPLATE_TEXT_KEYS = ['terms', 'warranty', 'validity', 'inclusions', 'exclusions', 'payment_terms'] as const;
export type QuoteTemplate = { name: string; line_headings: string[] } & Record<(typeof TEMPLATE_TEXT_KEYS)[number], string>;

// Kept in step with the CHECK in the SQL file (fn_text_states_a_price). A percentage ("50% advance")
// and a duration ("30 days") are not prices; a figure beside a currency or a per-unit rate is.
const PRICE_RE = /(\b(aed|dhs?|dirhams?|usd|eur|gbp|sar)\b\s*[0-9])|([0-9][0-9,.]*\s*(\/-|\b(aed|dhs?|dirhams?|usd|eur|gbp|sar)\b))|(درهم\s*[0-9]|[0-9][0-9,.]*\s*درهم)|([0-9][0-9,.]*\s*\/\s*(m2|m²|sqm|sq\.?\s*m|lm|m|no|nos|unit|pc|pcs|kg|ton)\b)/i;
export const statesAPrice = (s: string): boolean => PRICE_RE.test(s);

const txt = (v: unknown, max: number) => (typeof v === 'string' ? v : '').replace(/\s+/g, ' ').trim().slice(0, max);

export function cleanTemplate(input: unknown): { ok: true; template: QuoteTemplate } | { ok: false; code: string; message: string } {
  const b = (input && typeof input === 'object' ? input : {}) as Record<string, unknown>;
  const name = txt(b.name, 80);
  if (name.length < 2) return { ok: false, code: 'template_name', message: 'Give the template a name.' };
  const raw = Array.isArray(b.line_headings) ? b.line_headings : [];
  // A heading may arrive as a quote line object; only its description survives.
  const line_headings = raw.map((h) => txt(h && typeof h === 'object' ? (h as Record<string, unknown>).description : h, 200)).filter(Boolean).slice(0, 100);
  const t = { name, line_headings } as QuoteTemplate;
  for (const k of TEMPLATE_TEXT_KEYS) t[k] = txt(b[k], 1000);
  for (const s of [name, ...line_headings, ...TEMPLATE_TEXT_KEYS.map((k) => t[k])]) {
    if (statesAPrice(s)) return { ok: false, code: 'template_has_price', message: `A template cannot carry a price ("${s.slice(0, 60)}"). Prices are quoted fresh on each inquiry; remove the figure and save again.` };
  }
  return { ok: true, template: t };
}
