import { type TermsSpec } from '../../_shared/line_specs/assess.ts';
import { jobNoOf } from '../../_shared/quote_documents.ts';

export const SEAT = 'sales_engineer' as const;
export type Lang = 'en' | 'ar';

// ---------------------------------------------------------------------------------------------
// The shapes the review reads.
// ---------------------------------------------------------------------------------------------
/** One row of the job's bill of quantities, as the supplier inbox serves it (already scrubbed). */
export type BoqRow = { section?: string | null; description?: string | null; qty?: number | string | null; unit?: string | null; qty_status?: string | null };
/** The inquiry as this supplier may see it — the output of supplier_api `inbox`, never the raw row. */
export type SafeInquiry = {
  id: string; job_no: string; category: string | null; emirate: string | null; spec: unknown;
  boq_rows: BoqRow[]; boq_withheld: boolean; concluded: boolean; revealed: boolean;
};
export type WLine = {
  description: string; qty: string; unit: string; unit_price: number | null; amount: number | null; option?: number;
  /** The file's own "Specification" column for this line, read with the description by every spec reader. */
  specification?: string;
  spec?: Record<string, string>; spec_source?: Record<string, 'extracted' | 'supplier_portal' | 'reasoned'>;
};
/** The quotation under review: what the file said, plus every detail the supplier confirmed in the chat. */
export type Working = {
  lines: WLine[]; amount: number | null; subtotal: number | null; vat_amount: number | null;
  vat_treatment: string | null; price_ex_vat: number | null; trn: string | null;
  /** Ruling 1207: the supplier's discount, as stated — a price field, never folded into the conditions. */
  gross_amount?: number | null; discount_amount?: number | null; discount_label?: string | null;
  lead_time: string; validity: string; payment_terms: string; warranty: string;
  scope: string; conditions: string; exclusions: string; notes: string;
  terms_spec: TermsSpec; masked_terms: string[]; option_totals: Record<string, number>;
  /** A currency other than AED seen in the file, until the supplier confirms the prices are AED. */
  foreign_currency: string | null;
  /** BOQ line number → the supplier's reason it is excluded. */
  boq_excluded: Record<string, string>;
  /** BOQ line number → the supplier's explanation of a quantity that differs on purpose; "<n>:unit" → of a unit. */
  qty_explained: Record<string, string>;
  /** Every detail changed in the chat, in order — the audit trail of what the engineer was told. */
  corrections: { field: string; value: string; line?: number | null }[];
};

export type IssueCode =
  | 'boq_line_not_priced' | 'qty_mismatch' | 'unit_mismatch' | 'line_unpriced' | 'total_mismatch'
  | 'currency_not_aed' | 'vat_basis' | 'vat_ex_price' | 'validity'
  | 'spec' | 'line_items' | 'delivery' | 'installation_included' | 'installation_detail'
  | 'warranty_period' | 'warranty_coverage' | 'price_ex_vat' | 'component';
/** The quotation-level attributes assess.ts can report missing, as issue codes. */
const TERM_CODES = new Set<IssueCode>(['delivery', 'installation_included', 'installation_detail',
  'warranty_period', 'warranty_coverage', 'price_ex_vat', 'line_items']);
export type Issue = {
  code: IssueCode; kind: 'adjustment' | 'clarification';
  /** The supplier's own line (1-based, in the order of their quotation). */
  line_no: number | null;
  /** The job's BOQ line (1-based, as the inquiry shows it). */
  boq_line: number | null;
  attr: string | null; en: string; ar: string;
};
export type Review = { approved: boolean; issues: Issue[]; price_ex_vat: number | null; boq_lines: number; matched: number };

/** The key that tracks one request across reviews: the same missing detail is the same request. */
export const issueKey = (i: Pick<Issue, 'code' | 'line_no' | 'boq_line' | 'attr'>) => `${i.code}|${i.line_no ?? ''}|${i.boq_line ?? ''}|${i.attr ?? ''}`;
/**
 * The job number every surface prints: inquiries.rfq_no, the same number the customer portal shows
 * and every notice carries ('RFQ-151767'). Measured 21 Sep 2026 (audit finding 7): this printed the
 * first 8 characters of the uuid (D958E1EA) while the customer read 151767 for the same job, so
 * neither side could quote the other's number. The uuid prefix remains only as a fallback for a row
 * read without rfq_no, which the column's NOT NULL makes a caller's omission rather than a state.
 */
export const jobNo = (inq: { rfq_no?: number | string | null; id?: string | null } | string) =>
  jobNoOf(typeof inq === 'string' ? { id: inq } : inq);

// Names the sibling modules of this folder import (the declarations above are unchanged).
export { TERM_CODES };
