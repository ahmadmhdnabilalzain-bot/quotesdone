// submit_review — THE QUOTATION UNDER REVIEW, BUILT FROM WHAT A DOOR ACTUALLY SENT.
// Seat: sales_engineer. Audit of 22 Sep 2026, finding SP-F-02.
//
// reviewQuotation (quote_review.ts) is the founder's own rule set — "the most important part in the
// whole supplier portal" — and until this change it ran ONLY inside the quotation-review chat. Three
// other doors reach a customer without it: submit_quote from the portal's quote form, submit_quote from
// the Quote Builder's one-click accept, and spec_approve, which releases a held quote.
//
// This module is the pure half: it turns what a door sent (or what is already stored on a quote row)
// into the `Working` shape the review reads, so index.ts holds no second copy of that mapping and the
// two payload shapes can be tested without a database (submit_review.test.ts).
//
// WHAT IT DELIBERATELY DOES NOT TAKE FROM THE CALLER. `boq_excluded` and `qty_explained` are the
// supplier's recorded explanations — "BOQ line 3 excluded, by others" — and they SILENCE a rule. They
// are therefore passed in from public.quote_reviews.working, which only the sales engineer writes, and
// never read off the request body: otherwise a supplier posting straight to the endpoint could declare
// every BOQ line excluded and walk past the whole review.
import type { MissingItem, TermsSpec } from '../_shared/line_specs/assess.ts';
import { foreignCurrency, parseQty, sanitizeSpec, type Issue, type WLine, type Working } from './quote_review.ts';

const num = (v: unknown): number | null => { const n = Number(v); return Number.isFinite(n) && String(v ?? '').trim() !== '' ? n : null; };
const str = (v: unknown): string => (v == null ? '' : String(v));

/** The supplier's explanations, as the engineer recorded them. Never the caller's. */
export type Resolved = { boq_excluded: Record<string, string>; qty_explained: Record<string, string> };
export const NOTHING_EXPLAINED: Resolved = { boq_excluded: {}, qty_explained: {} };
/** Whatever carries the explanations (a quote_reviews row's `working`), read defensively. */
// deno-lint-ignore no-explicit-any
export function resolvedFrom(working: any): Resolved {
  const o = (v: unknown) => (v && typeof v === 'object' && !Array.isArray(v) ? v as Record<string, string> : {});
  return { boq_excluded: o(working?.boq_excluded), qty_explained: o(working?.qty_explained) };
}

// deno-lint-ignore no-explicit-any
export type SubmitBody = Record<string, any>;

/**
 * The quotation as submit_quote received it. `scrubbed` is the free text AFTER scrubIdentity, because
 * that is what will be stored and what the customer would read — reviewing the raw text would review
 * something that never exists.
 */
export function workingFromSubmit(body: SubmitBody, scrubbed: { notes: string; scope: string; conditions: string; exclusions: string }, terms_spec: TermsSpec, masked_terms: string[], trn: string | null): Working {
  // deno-lint-ignore no-explicit-any
  const items: any[] = Array.isArray(body.items) ? body.items : [];
  const lines: WLine[] = items.map((it) => ({
    description: str(it?.description),
    qty: it?.qty == null ? '' : String(it.qty),
    unit: str(it?.unit),
    unit_price: num(it?.unit_price),
    amount: num(it?.amount) ?? (((num(it?.qty) || 0) * (num(it?.unit_price) || 0)) || null),
    ...(it?.specification ? { specification: String(it.specification) } : {}),
    // The same cleaning the stored rows get (sanitizeSpec), so the review and the hold gate judge one set of values.
    ...(it?.spec && typeof it.spec === 'object' ? { spec: sanitizeSpec(it.spec).spec } : {}),
  }));
  const lead_time = str(body.lead_time), validity = str(body.validity), payment_terms = str(body.payment_terms), warranty = str(body.warranty);
  return {
    lines, amount: num(body.amount), subtotal: num(body.subtotal), vat_amount: num(body.vat_amount),
    vat_treatment: body.vat_treatment ? String(body.vat_treatment) : null, price_ex_vat: num(body.price_ex_vat), trn,
    lead_time, validity, payment_terms, warranty,
    scope: scrubbed.scope, conditions: scrubbed.conditions, exclusions: scrubbed.exclusions, notes: scrubbed.notes,
    terms_spec, masked_terms, option_totals: body.option_totals && typeof body.option_totals === 'object' ? body.option_totals : {},
    // A currency other than AED anywhere in the free text the supplier typed (rule 5). The chat reads
    // this off the uploaded file; a typed quotation has no file, so its own words are the text.
    foreign_currency: foreignCurrency([scrubbed.notes, scrubbed.scope, scrubbed.conditions, scrubbed.exclusions, payment_terms, ...lines.map((l) => l.description)].join('\n')),
    boq_excluded: {}, qty_explained: {}, corrections: [],
  };
}

/**
 * The quotation as it is already STORED — the shape spec_approve needs, because by then the supplier
 * filled the missing details in through the hold desk and the row, not the request, is the quotation.
 */
// deno-lint-ignore no-explicit-any
export function workingFromStoredQuote(q: any, rows: any[]): Working {
  const lines: WLine[] = (rows || []).map((r) => ({
    description: str(r?.description),
    qty: r?.qty == null ? '' : String(r.qty),
    unit: str(r?.unit),
    unit_price: num(r?.unit_price),
    amount: num(r?.amount) ?? (((num(r?.qty) || 0) * (num(r?.unit_price) || 0)) || null),
    ...(r?.specification ? { specification: String(r.specification) } : {}),
    ...(r?.spec && typeof r.spec === 'object' ? { spec: r.spec as Record<string, string> } : {}),
  }));
  return {
    lines, amount: num(q?.quote_amount) ?? num(q?.amount_as_stated), subtotal: null, vat_amount: num(q?.vat_amount),
    vat_treatment: q?.vat_treatment ? String(q.vat_treatment) : null, price_ex_vat: num(q?.price_ex_vat), trn: q?.supplier_trn ?? null,
    lead_time: str(q?.lead_time), validity: str(q?.validity), payment_terms: str(q?.payment_terms), warranty: str(q?.warranty),
    scope: str(q?.scope), conditions: str(q?.conditions), exclusions: str(q?.exclusions), notes: str(q?.notes),
    terms_spec: (q?.terms_spec ?? {}) as TermsSpec, masked_terms: Array.isArray(q?.masked_terms) ? q.masked_terms : [],
    option_totals: {},
    // Stored text has already been through the review or the hold desk; a currency it still names is read.
    foreign_currency: foreignCurrency([q?.notes, q?.scope, q?.conditions, q?.exclusions, q?.payment_terms].filter(Boolean).map(String).join('\n')),
    boq_excluded: {}, qty_explained: {}, corrections: [],
  };
}

/** Apply the engineer's recorded explanations to a working quote. */
export function withResolved(w: Working, r: Resolved): Working {
  return { ...w, boq_excluded: r.boq_excluded, qty_explained: r.qty_explained };
}

/**
 * One review issue in the shape the HOLD DESK stores and renders (assess.ts MissingItem), so a quote
 * held by the review shows the same card as a quote held for a missing spec. The engineer's sentence
 * is the label, in both languages; there is nothing to convert because both carry the same thing —
 * one detail, named, with what to do about it.
 */
export function issueAsMissing(i: Issue): MissingItem {
  return { scope: i.line_no ? 'line' : 'quote', line_no: i.line_no, description: null, attr: i.attr || i.code, type: 'text', label_en: i.en, label_ar: i.ar };
}

/** One quantity reader, so a caller need not import quote_review.ts for it. */
export { parseQty };
