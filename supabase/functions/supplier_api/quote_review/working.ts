import { normText } from '../../_shared/line_specs/model.ts';
import { type Proposal } from '../../quote_extract/quote_from_document.ts';
import { type WLine, type Working } from './types.ts';

// ---------------------------------------------------------------------------------------------
// Reading a quotation file's proposal (quote_extract/quote_from_document.ts) into the working quote.
// ---------------------------------------------------------------------------------------------
const num = (v: unknown): number | null => { const n = Number(v); return Number.isFinite(n) && String(v ?? '').trim() !== '' ? n : null; };
export function parseQty(q: unknown): { n: number | null; unit: string } {
  const s = normText(String(q ?? ''));
  const m = s.match(/-?\d[\d,]*(?:\.\d+)?/);
  const n = m ? Number(m[0].replace(/,/g, '')) : null;
  return { n: n != null && Number.isFinite(n) ? n : null, unit: (m ? s.replace(m[0], '') : s).trim() };
}
const FOREIGN = /\b(USD|US\$|EUR|GBP|SAR|QAR|OMR|KWD|BHD|INR|CNY|RMB)\b|[€£]/;
export function foreignCurrency(text: string): string | null { const m = String(text || '').match(FOREIGN); return m ? m[0] : null; }

export function workingFromProposal(p: Proposal, fileText = ''): Working {
  const lines: WLine[] = (p.line_items || []).map((l) => {
    const { n, unit } = parseQty(l.qty);
    const amount = l.amount == null ? null : Number(l.amount);
    // The file's own rate and unit when the reader found them (final audit 12 Nov 2026, H3); else derived as before.
    return { description: String(l.description || ''), qty: n == null ? '' : String(n), unit: l.unit || unit, amount,
      unit_price: l.unit_price != null && l.unit_price > 0 ? l.unit_price : (n && amount ? Math.round((amount / n) * 100) / 100 : null), ...(l.option != null ? { option: l.option } : {}),
      ...(l.specification ? { specification: String(l.specification) } : {}), ...(l.country_of_origin ? { country_of_origin: String(l.country_of_origin) } : {}) };
  });
  return {
    lines, amount: p.amount, subtotal: p.subtotal, vat_amount: p.vat_amount, vat_treatment: p.vat_treatment ?? null,
    price_ex_vat: p.price_ex_vat, trn: p.trn, gross_amount: p.gross_amount ?? null, discount_amount: p.discount_amount ?? null, discount_label: p.discount_label ?? null, lead_time: p.lead_time || '', validity: p.validity || '', payment_terms: p.payment_terms || '',
    warranty: p.warranty || '', scope: p.scope || '', conditions: p.conditions || '', exclusions: p.exclusions || '', notes: '',
    terms_spec: {}, masked_terms: p.masked_terms || [], option_totals: p.option_totals || {},
    foreign_currency: foreignCurrency(fileText), boq_excluded: {}, qty_explained: {}, corrections: [],
    // A MODEL's reading (it carries is_quotation; the code reader's own `warnings` are notes on the form, unchanged) brings
    // its questions into the thread: the review is not approved while they are open (review of #1981, D5).
    ...((p as { is_quotation?: unknown }).is_quotation === true && Array.isArray(p.warnings) && p.warnings.length ? { to_confirm: p.warnings.map(String).slice(0, 8) } : {}),
  };
}

// Names the sibling modules of this folder import (the declarations above are unchanged).
export { num };
