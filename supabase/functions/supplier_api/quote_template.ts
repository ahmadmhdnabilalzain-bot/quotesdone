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

// THE ONE PRICE PATTERN, byte-identical to the one in fn_text_states_a_price (the SQL file). The deno
// test reads the SQL literal and asserts it equals PRICE_PATTERN character for character, and that
// it uses no construct the two engines read differently, so the two cannot drift. It uses only
// syntax JavaScript (flag i) and Postgres ARE (~*) read the same way. A word boundary (\b, \y) let
// "AED45", "45AED" and "Dh45" through, so the letter boundary is written out: (^|[^a-z]) on the left,
// (?![a-z]) on the right. Refused: a figure beside a currency in either order, with or without a space
// (AED 45, AED45, 45AED, Dh45, $45, €45, 45 dirhams, 500/-), and a per-unit rate (45/m2, 45 per sqm).
// Not refused: "50% advance", "30 days", "12 mm", "width 5".
// The next line holds the Arabic word for dirham. It is on nothing_a_supplier_reads_can_be_arabic's
// gated list: a detector, never shown.
export const PRICE_PATTERN = String.raw`(^|[^a-z])(aed|dhs?|dirhams?|usd|euros?|eur|gbp|sar)\s*[0-9٠-٩۰-۹]|[$€£]\s*[0-9٠-٩۰-۹]|درهم\s*[0-9٠-٩۰-۹]|[0-9٠-٩۰-۹][0-9٠-٩۰-۹,.]*\s*(/-|[$€£]|درهم)|[0-9٠-٩۰-۹][0-9٠-٩۰-۹,.]*\s*(aed|dhs?|dirhams?|usd|euros?|eur|gbp|sar)(?![a-z])|[0-9٠-٩۰-۹][0-9٠-٩۰-۹,.]*\s*(/|per)\s*(m2|m²|sqm|sq\.?\s*m|lm|m|no|nos|unit|pc|pcs|kg|ton)(?![a-z])`;
const PRICE_RE = new RegExp(PRICE_PATTERN, 'i');
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
