import { assessQuote, requirementsOf, type Line as SpecLine, type TermsSpec } from '../line_specs/assess.ts';
import { type Lang } from './base.ts';

// ── Types: what the caller hands in ─────────────────────────────────────────────────────────────
export type QuoteRow = {
  id?: string; quote_amount: number | null; lead_time?: string | null; validity?: string | null; warranty?: string | null;
  payment_terms?: string | null; scope?: string | null; conditions?: string | null; exclusions?: string | null; notes?: string | null;
  /** The founder's four completeness checks (14 Sep 2026). All optional: absent means "not stated". */
  installation_applicable?: boolean | null; installation_included?: boolean | null; installation_scope?: string | null; installation_timeline?: string | null;
  warranty_applicable?: boolean | null; warranty_coverage?: string | null;
  /** The price excluding VAT (the spec/hold contract's `price_ex_vat`). Every customer document
   * shows and compares this figure; the 3% fee is taken on it. Absent: quote_amount is ex-VAT. */
  price_ex_vat?: number | null;
  /** Ruling 1207: the supplier's discount and VAT exactly as stated (quotes.gross_amount / discount_amount /
   * discount_label / vat_treatment / vat_amount / amount_as_stated). Shown as written; never the TRN. */
  gross_amount?: number | null; discount_amount?: number | null; discount_label?: string | null;
  vat_treatment?: string | null; vat_amount?: number | null; amount_as_stated?: number | null;
};
export type InquiryRow = { id: string; rfq_no?: number | string | null; category?: string | null; summary?: string | null; emirate?: string | null };
/** The one job number (inquiries.rfq_no) as printed on every document; the uuid prefix only for a row read without it. */
export const jobNoOf = (inq: { id?: string | null; rfq_no?: number | string | null } | null | undefined) =>
  inq?.rfq_no != null && String(inq.rfq_no).trim() !== '' ? String(inq.rfq_no) : String(inq?.id || '').slice(0, 8).toUpperCase();

// ── The completeness checks come from the hold desk's own reading ─────────────────────────────
// MEASURED 21 Sep 2026 (audit, finding 4): the generated quotation said "Material specification:
// Missing on 3 of 3 lines", "Installation: Not stated", "Warranty coverage not stated" for a quote the
// sales engineer had just approved as complete. Two causes, both here: (1) both printers read the
// per-line specs from a column named `specs` — the stored column is quote_items.spec — so no line ever
// had a specification; (2) nothing ever wrote quotes.installation_included / warranty_coverage, so the
// four checks were always "Not stated". The document now asks line_specs/assess.ts — the ONE reader
// the review and the hold gate use — so the PDF can never disagree with the approval.
/** quote_items rows as printed lines. The stored column is `spec`; `specs` is accepted for an older row shape. */
// deno-lint-ignore no-explicit-any
export function itemsOfRows(rows: any[] | null | undefined): Item[] {
  return (rows || []).map((b) => ({ desc: String(b.description || ''), qty: b.qty == null ? '' : String(b.qty), unit: String(b.unit || ''),
    unit_price: b.unit_price == null ? null : Number(b.unit_price), amount: b.amount == null ? null : Number(b.amount),
    brand: b.brand ?? null, model: b.model ?? null, specification: b.specification ?? null,
    specs: (b.spec && typeof b.spec === 'object' && !Array.isArray(b.spec)) ? b.spec : ((b.specs && typeof b.specs === 'object' && !Array.isArray(b.specs)) ? b.specs : null) })).filter((x) => x.desc);
}
/**
 * The four checks (material per line, delivery, installation, warranty) as assess.ts reads this quote,
 * and each line's specs completed with what its own words state. Pure.
 */
export function completenessOf(q: QuoteRow & { terms_spec?: unknown; lead_time?: string | null }, items: Item[], category: string | null | undefined, inquirySpec: unknown): { quote: QuoteRow; items: Item[] } {
  const lines: SpecLine[] = items.map((it, i) => ({ line_no: i + 1, description: it.desc, brand: it.brand ?? null, model: it.model ?? null, specification: it.specification ?? null,
    qty: it.qty, unit: it.unit, unit_price: it.unit_price ?? null, amount: it.amount ?? null,
    spec: it.specs ? Object.fromEntries(Object.entries(it.specs).filter(([, v]) => v != null).map(([k, v]) => [k, String(v)])) : null }));
  const a = assessQuote({ category: category ?? null, lines, requirements: requirementsOf(inquirySpec),
    terms: { lead_time: q.lead_time ?? null, warranty: q.warranty ?? null, scope: q.scope ?? null, exclusions: q.exclusions ?? null, conditions: q.conditions ?? null, notes: q.notes ?? null,
      terms_spec: (q.terms_spec && typeof q.terms_spec === 'object' ? q.terms_spec : null) as TermsSpec | null, price_ex_vat: q.price_ex_vat ?? q.quote_amount ?? null } });
  const out = items.map((it, i) => { const r = a.lines[i]; const specs = r && Object.keys(r.spec).length ? { ...(it.specs ?? {}), ...r.spec } : it.specs; return { ...it, specs: specs ?? null }; });
  const inst = a.terms.installation, w = a.terms.warranty;
  const timeline = inst.detail && /^Installation in /.test(inst.detail) ? inst.detail.replace(/^Installation in /, '') : null;
  return {
    items: out,
    quote: { ...q,
      installation_applicable: inst.applies, installation_included: inst.included === 'yes' ? true : inst.included === 'no' ? false : null,
      installation_scope: inst.detail && !timeline ? inst.detail.replace(/^Scope: /, '') : null, installation_timeline: timeline,
      // the cover figure and the terms cell carry the PERIOD; the coverage has its own place in the checks
      warranty_applicable: w.applies, warranty_coverage: w.coverage, warranty: w.period ?? q.warranty ?? null },
  };
}
/** One priced line of the supplier's own breakdown (quote_items). `specs` is attribute → stated value. */
export type Item = {
  desc: string; qty: string; unit: string; unit_price?: number | null; amount?: number | null;
  brand?: string | null; model?: string | null; specification?: string | null; specs?: Record<string, string | null> | null;
};

// THE TECHNICAL COMPARISON — the renderer's input. The spec agent (branch exact-specs-or-hold)
// publishes the contract at docs/contracts/technical_comparison.md; this is the shape described in
// its scope line: each quote's stated value per attribute, per scope line, with a flag against the
// request, plus the three commercial completeness checks with an `applicable` flag. Values are keyed
// by the anonymous label ("Supplier A"). A held quote is never a column: the roster decides.
export type SpecFlag = 'match' | 'differs' | 'missing' | 'optional' | 'na';
export type SpecCell = { value?: string | null; flag: SpecFlag; note?: string | null };
export type TechAttribute = { key: string; label?: string | null; unit?: string | null; requested?: string | null; values: Record<string, SpecCell> };
export type TechLine = { line_no?: number | null; item: string; qty?: string | number | null; unit?: string | null; attributes: TechAttribute[] };
export type TechTerm = { applicable?: boolean | null; requested?: string | null; values: Record<string, SpecCell> };
export type TechnicalComparison = {
  suppliers: string[];
  lines: TechLine[];
  terms?: { lead_time?: TechTerm | null; installation?: TechTerm | null; warranty?: TechTerm | null } | null;
};

/** 'QD-<job number>-<letter>' — the job number is inquiries.rfq_no, the same one both portals print (21 Sep 2026, audit finding 7). */
export function quoteRef(inq: { id?: string | null; rfq_no?: number | string | null }, letter: string) { return 'QD-' + jobNoOf(inq) + '-' + letter; }
export function clipCell(s: unknown, n: number) { const t = String(s == null ? '' : s).replace(/\s+/g, ' ').trim(); return t.length > n ? t.slice(0, n - 1) + '…' : t; }
// deno-lint-ignore no-explicit-any
const arrOf = (x: any) => Array.isArray(x) ? x : [];
/** "Supplier B" → "المورّد B" on an Arabic page; the letter stays the one on the customer's screen. */
// "Option N" takes the same Arabic as labelQuotes' own .ar ("المورّد A – الخيار 2"). Measured 14 Sep
// 2026: only "Supplier" was translated, so the Arabic report read "المورّد A – Option 1" in every table.
export const arLabelWords = (s: string) => s.replace(/\bSupplier ([A-Z]{1,2})\b/g, 'المورّد $1').replace(/\bOption (\d{1,3})\b/g, 'الخيار $1');
export function labelFor(label: unknown, lang: Lang) { const l = String(label ?? ''); return lang === 'ar' ? arLabelWords(l) : l; }

// ── The supplier's VAT is shown as stated (ruling 1207, 13 Oct 2026) ─────────────────────────────
// SUPERSEDED: the 14 Sep 2026 ruling hid the supplier's VAT from the customer ("we definetely hide the vat details").
// Ruling 1207: QuotesDone shows the customer EXACTLY what the supplier stated, VAT included, and "no VAT" is said
// only beside OUR fee (stated_price.ts). Supplier and analysis text is no longer stripped of VAT sentences; a TRN is
// still blanked by maskContacts (it names the company). VAT_LINE and stripVat are kept only so the test can prove
// no customer page prints VAT_LINE any more.
export const VAT_LINE = { en: 'Prices shown exclude VAT, where applicable.', ar: 'الأسعار المعروضة لا تشمل ضريبة القيمة المضافة حيثما تنطبق.' };
export const VAT_RE = /\b(?:vat|trn|value[- ]added tax|tax registration(?: number)?|tax reg(?:istration)? no)\b|ضريبة القيمة المضافة|الرقم الضريبي|رقم التسجيل الضريبي|\b100\d{12}\b/i;
/** Drop every sentence / clause that mentions VAT or a TRN. */
export function stripVat(s: unknown): string {
  const t = String(s ?? '');
  if (!VAT_RE.test(t)) return t;
  return t.split(/(?<=[.;!؛\n])\s+|\s*[;؛]\s*/).filter((part) => !VAT_RE.test(part)).join(' ').replace(/\s+/g, ' ').trim();
}

// Names the sibling modules of this folder import (the declarations above are unchanged).
export { arrOf };
