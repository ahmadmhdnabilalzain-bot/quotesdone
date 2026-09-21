// line_specs/derive.ts — what a quote form's own text already states, read into the columns the
// scorer counts. Assigned: sales_engineer.
//
// MEASURED 21 Sep 2026 (audit, finding 15): a supplier typed "Brand: Jotun – Product: Fenomastic …"
// into a line's description and "Installation included … Exclusions: …" into the scope, pressed
// "Check before sending", and was told brand/model, labour-or-installation and exclusions were all
// missing. fn_quote_structured_score counts the COLUMNS quote_items.brand / model / labour / install
// and quotes.exclusions; the form sends description, qty, unit and unit price only, so what the
// supplier wrote could never reach the count. submit_quote accepts items from any caller (the form,
// the review, a native app), so the reading happens THERE, once, for every caller — nothing is
// inferred that the text does not say, and a column the caller filled is never overwritten.
import { normText, VAGUE } from './model.ts';

const label = (names: string) => new RegExp(`(?:^|[\\s,;|(–-])(?:${names})\\s*[:\\-–=]\\s*([^,;|()\\n–]{2,80})`, 'i');
const BRAND = label('brand|make|manufacturer|mfr|ماركة|الماركة|العلامة التجارية|الشركة المصنعة');
const MODEL = label('model(?:\\s*no\\.?)?|model number|product|range|series|موديل|الموديل|رقم الموديل|المنتج|اسم المنتج');
const SPEC = label('spec(?:ification)?s?|المواصفات|مواصفات');
const clean = (v: string | null | undefined) => { const s = normText(String(v ?? '')).replace(/[\s.،]+$/, ''); return s && !VAGUE.test(s) ? s : null; };
const has = (v: unknown) => v != null && String(v).trim() !== '';

/** brand / model / specification for one line, from its own words, only where the caller left them empty. */
export function deriveLineFields(it: { description?: unknown; brand?: unknown; model?: unknown; specification?: unknown }): { brand?: string; model?: string; specification?: string } {
  const d = String(it.description ?? '');
  const out: { brand?: string; model?: string; specification?: string } = {};
  if (!has(it.brand)) { const m = d.match(BRAND); const v = m && clean(m[1]); if (v) out.brand = v; }
  if (!has(it.model)) { const m = d.match(MODEL); const v = m && clean(m[1]); if (v) out.model = v; }
  if (!has(it.specification)) { const m = d.match(SPEC); const v = m && clean(m[1]); if (v) out.specification = v; }
  return out;
}

const EXCL = /(?:^|\n|[.;]\s*)\s*(?:exclusions?|excluded|not\s+included|الاستثناءات|غير\s+مشمول)\s*[:\-–]\s*([^\n]{2,600})/i;
const INSTALL_INCLUDED = /supply\s*(?:&|and|\+|,)\s*(?:install|fix|apply|lay|erect)|install(?:ation)?\s*(?:is\s*)?includ|includ(?:es|ing|ed)?\s*(?:the\s*)?install|توريد وتركيب|شامل التركيب|يشمل التركيب|التركيب مشمول|مع التركيب/i;
/** Exclusions written inside the scope, and whether the scope says installation is included. */
export function deriveTermsFromScope(scope: unknown, exclusions: unknown): { exclusions?: string; installation_included: boolean } {
  const s = String(scope ?? '');
  const out: { exclusions?: string; installation_included: boolean } = { installation_included: INSTALL_INCLUDED.test(s) };
  if (!has(exclusions)) { const m = s.match(EXCL); const v = m && clean(m[1]); if (v) out.exclusions = v; }
  return out;
}
