// model_reading — THE MODEL READS THE QUOTATION; CODE CHECKS ONLY WHAT MUST BE EXACT (sales_engineer, 12 Nov 2026;
// founder rulings 1663, 1664, 1666; LLM-first audit finding A2, docs/reports/2026-11-12-llm-first-audit.md).
//
// WHAT WAS WRONG. quote_extract read every quotation with code first (doc_read + quote_from_document) and asked the model
// only when code found no total; a priced code reading went back as `extracted_by_model: 'deterministic'`, and the
// e-mail route (resend_inbound/quote_by_email.ts) called a mail a quotation whenever that code reader priced it, an
// e-mail BODY included. The founder, 12 Nov 2026: "Trade license reading, company profile reading, there's no code
// first, 100% ... Otherwise, there are tons of issues that can come up." What a document IS (a quotation or not, for
// which request), its total, its options, its VAT and its terms are what it MEANS: the model reads them, in one call.
//
// WHAT CODE STILL DOES (this module, pure, no I/O):
//   1. the arithmetic, with the shared exact helpers: the price before VAT after the stated discount
//      (_shared/stated_price.ts, rulings 1207/1208), lines against the subtotal, VAT against 5% of the base, subtotal +
//      VAT against the total;
//   2. the code money reader (quote_from_document.ts, held by the 207-case money corpus of #1955) becomes the CHECKER:
//      a total it finds that none of the model's figures matches is put to the supplier, never chosen by code;
//   3. options (two candidate totals) are put to the supplier;
//   4. a figure the model returned that is not in the file's text layer is a NOTE for our own record, never a block and
//      never a question: a PDF text layer is unreliable (the founder's own licence dropped its Arabic letters, 12 Nov).
// A disagreement is never resolved by code. It becomes a plain-English question on the supplier's own form
// (`warnings`, shown by QuoteForm under "Please check before you send"), and on the e-mail route it is put to him in
// the e-mail and in his quotation thread; nothing he has not confirmed reaches a customer (supplier_api/email_quote.ts).
// prevented by: quote_extract/the_model_reads_the_quotation_and_code_checks_it.test.ts
import { statedPrice } from '../_shared/stated_price.ts';
import type { Extracted } from '../_shared/doc_read/types.ts';
import { quoteText, type Proposal, type QuoteLine } from './quote_from_document.ts';

/** What the model returns (quote_extract's SYS asks for exactly this). Every field may be missing or mistyped. */
export type ModelAnswer = {
  is_quotation?: unknown; not_a_quotation_reason?: unknown; request_reference?: unknown; currency?: unknown;
  amount?: unknown; total?: unknown; subtotal?: unknown; vat_amount?: unknown; vat_treatment?: unknown;
  gross_amount?: unknown; discount_amount?: unknown; discount_label?: unknown;
  line_items?: unknown; options?: unknown;
  lead_time?: unknown; validity?: unknown; payment_terms?: unknown; warranty?: unknown; scope?: unknown; conditions?: unknown;
  exclusions?: unknown; notes?: unknown; description_anonymized?: unknown; masked_terms?: unknown; confidence?: unknown;
};
/** The proposal shape every caller already reads, plus what the model decided about the document. */
export type ModelProposal = Proposal & {
  /** false: the model read it and it is not a quotation (an invoice, a site-visit note, a profile...). */
  is_quotation: boolean; not_a_quotation_reason: string; request_reference: string;
  /** The currency as the quotation states it ('' when it states none). */
  currency_stated: string; confidence_stated: string;
  /** For our own record only (never shown to a customer, never a block): figures not found in the file's text layer. */
  check_notes: string[];
};

const r2 = (n: number) => Math.round(n * 100) / 100;
const pos = (v: unknown): number | null => {
  if (typeof v === 'string') v = v.replace(/[,\s]|AED|Dhs?\.?/gi, '');
  const n = Number(v); return v != null && v !== '' && Number.isFinite(n) && n > 0 ? r2(n) : null;
};
const str = (v: unknown, n = 2000) => (v == null ? '' : String(v)).trim().slice(0, n);
const near = (a: number | null, b: number | null, tol = 1) => a != null && b != null && Math.abs(a - b) <= tol;
export const money = (n: number) => 'AED ' + n.toLocaleString('en-US', { maximumFractionDigits: 2 });
const AED = /^(aed|dhs?|dirhams?|uae\s*dirhams?|د\.?\s?إ\.?|درهم)$/i;
const VAT_TREATMENTS = ['exclusive', 'inclusive', 'not_registered'];

/**
 * The model's answer in the proposal shape. `gen` is quote_extract's own anonymiser (scrub + _shared/quote_generalise.ts),
 * applied to every text the customer could read; figures are never rewritten.
 */
export function proposalFromModel(ai: ModelAnswer, gen: (v: unknown) => string): ModelProposal {
  const lines: QuoteLine[] = (Array.isArray(ai.line_items) ? ai.line_items : []).slice(0, 200).map((raw) => {
    const li = (raw && typeof raw === 'object' ? raw : {}) as Record<string, unknown>;
    const opt = Number(li.option);
    const qtyN = pos(li.quantity ?? li.qty);
    return {
      description: gen(li.description), qty: str(li.qty, 60), amount: pos(li.amount),
      ...(qtyN != null ? { quantity: qtyN } : {}), ...(str(li.unit) ? { unit: str(li.unit, 40) } : {}),
      ...(pos(li.unit_price) != null ? { unit_price: pos(li.unit_price) } : {}),
      ...(Number.isInteger(opt) && opt >= 1 && opt <= 20 ? { option: opt } : {}),
      ...(str(li.country_of_origin) ? { country_of_origin: str(li.country_of_origin, 80) } : {}),
    };
  });
  // OPTIONS: two or more alternatives the quotation offers, each with its own total (founder, 14 Sep 2026: each option is
  // its own quotation; supplier_api's submit_quote splits on option_totals).
  const opts = (Array.isArray(ai.options) ? ai.options : []).map((o) => (o && typeof o === 'object' ? o : {}) as Record<string, unknown>)
    .map((o, i) => ({ option_no: i + 1, label: str(o.label, 80), amount: pos(o.total ?? o.amount) })).filter((o) => o.amount != null).slice(0, 20);
  const options = opts.length > 1 ? opts.map((o) => ({ option_no: o.option_no, amount: o.amount })) : [];
  const option_totals: Record<string, number> = {};
  if (options.length) for (const o of opts) option_totals[String(o.option_no)] = o.amount!;
  const total = pos(ai.total ?? ai.amount);
  const stated = VAT_TREATMENTS.includes(str(ai.vat_treatment)) ? str(ai.vat_treatment) : null;
  // The arithmetic is code's (rulings 1207/1208): the price compared and the fee base is the price after the stated
  // discount, excluding VAT. `text` is empty on purpose: the VAT basis and the discount are what the model read, not a
  // second reading of the file's words by pattern.
  // The model's subtotal is the price before VAT AFTER any discount; statedPrice's `subtotal` is before the discount, so
  // with a discount it is passed as the after-discount `net_amount` (measured: passed as `subtotal`, 2,000 less 300 with
  // a 1,700 subtotal came out 1,400).
  const disc = pos(ai.discount_amount);
  const sp = statedPrice({ amount: total, subtotal: disc ? null : pos(ai.subtotal), net_amount: disc ? pos(ai.subtotal) : null, vat_amount: pos(ai.vat_amount), text: '', stated,
    gross_amount: pos(ai.gross_amount), discount_amount: disc, discount_label: str(ai.discount_label, 80) || null });
  const currency = str(ai.currency, 12);
  return {
    amount: options.length ? options[0].amount : (sp.price_ex_vat ?? total), currency: 'AED', line_items: lines,
    lead_time: gen(ai.lead_time), validity: gen(ai.validity), payment_terms: gen(ai.payment_terms), warranty: gen(ai.warranty),
    scope: gen(ai.scope), conditions: gen(ai.conditions), exclusions: gen(ai.exclusions), notes: gen(ai.notes),
    description_anonymized: gen(ai.description_anonymized), masked_terms: [], confidence: 'low', method: 'document',
    subtotal: pos(ai.subtotal), vat_amount: sp.vat_amount, total_incl_vat: sp.vat_amount && total ? total : null,
    vat_treatment: sp.treatment, price_ex_vat: options.length ? null : sp.price_ex_vat, trn: null,
    gross_amount: options.length ? null : sp.gross_amount, discount_amount: options.length ? null : sp.discount_amount,
    discount_label: options.length ? null : sp.discount_label, options, option_totals,
    ...(currency && !AED.test(currency) ? { review_reason: 'foreign_currency' as const } : {}),
    is_quotation: ai.is_quotation === true || ai.is_quotation === 'true',
    not_a_quotation_reason: str(ai.not_a_quotation_reason, 300), request_reference: str(ai.request_reference, 60),
    currency_stated: currency, confidence_stated: str(ai.confidence, 12).toLowerCase(), check_notes: [],
  };
}

/**
 * The document's text, for the model (a file a provider cannot take: a spreadsheet, a Word file, a CSV, an e-mail body)
 * and for the checks. A plain-text file is taken AS WRITTEN: doc_read reads a .txt with commas as CSV, so "Grand Total
 * AED 9,450" became the cells "Grand Total AED 9" and "450" (measured 12 Nov 2026; main's code reader priced such an
 * e-mail body at AED 9 and the e-mail route submitted it). Anything else is doc_read's transcription. Transcription only.
 */
export function documentText(fileB64: string | null | undefined, filename: string, mime: string, rd: { ok: boolean } | null): string {
  if (fileB64 && (/^text\/plain/i.test(mime) || /\.txt$/i.test(filename))) {
    try { return new TextDecoder().decode(Uint8Array.from(atob(String(fileB64).replace(/^data:[^;]+;base64,/, '')), (c) => c.charCodeAt(0))); } catch { /* not base64: the transcription below */ }
  }
  return rd?.ok ? quoteText(rd as unknown as Extracted) : '';
}

/** Every figure written in a text, as numbers ("12,450.00" -> 12450; Arabic-Indic digits read as digits). */
export function figuresIn(text: string): number[] {
  const t = String(text || '').replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x660)).replace(/[۰-۹]/g, (d) => String(d.charCodeAt(0) - 0x6f0));
  const out = new Set<number>();
  for (const m of t.matchAll(/\d[\d,\s]*(?:\.\d+)?/g)) {
    const raw = m[0].trim();
    for (const s of [raw.replace(/[,\s]/g, ''), ...raw.split(/\s+/).map((x) => x.replace(/,/g, ''))]) { const n = Number(s); if (Number.isFinite(n) && n > 0) out.add(n); }
  }
  return [...out];
}

export type CodeReading = Pick<Proposal, 'amount' | 'gross_amount' | 'total_incl_vat' | 'price_ex_vat' | 'subtotal' | 'review_reason'> | null;

/**
 * The code checks. Returns the proposal with `warnings` (plain-English questions for the supplier, shown on his form and
 * put to him on the e-mail route) and `check_notes` (our record only). Nothing here changes a figure the model read.
 *   docText — the file's text as doc_read transcribed it ('' for a photo: no note is made).
 *   code    — what the code money reader (quote_from_document.ts) read from the same file, or null.
 */
export function checkReading(p: ModelProposal, docText: string, code: CodeReading): ModelProposal & { warnings?: string[] } {
  const warnings: string[] = [];
  const notes: string[] = [];
  const out = { ...p };
  if (!p.is_quotation) return out;
  const base = p.price_ex_vat ?? p.amount;
  // 1. Options: two candidate totals are the supplier's to confirm.
  if (p.options.length > 1) {
    warnings.push(`We read ${p.options.length} options: ${p.options.map((o) => `option ${o.option_no} ${money(o.amount!)}`).join(' and ')}. Each is sent to the customer as its own quotation. Is that right?`);
  }
  // 2. The lines add up to the price before VAT (and before the stated discount). Per option when there are options.
  const priced = p.line_items.filter((l) => l.amount != null);
  if (priced.length && priced.length === p.line_items.filter((l) => l.amount != null || String(l.qty || '').trim()).length) {
    if (p.options.length > 1) {
      for (const o of p.options) {
        const s = r2(priced.filter((l) => l.option === o.option_no).reduce((x, l) => x + (l.amount || 0), 0));
        if (s > 0 && !near(s, o.amount)) warnings.push(`The lines of option ${o.option_no} add up to ${money(s)}, but we read its total as ${money(o.amount!)}. Which is right?`);
      }
    } else if (base != null) {
      const s = r2(priced.reduce((x, l) => x + (l.amount || 0), 0));
      const before = p.gross_amount ?? p.subtotal ?? base;
      if (!near(s, before) && !near(s, base) && !near(s, p.total_incl_vat)) warnings.push(`Your lines add up to ${money(s)}, but we read your total before VAT as ${money(base)}. Which is right?`);
    }
  }
  // 3. VAT: 5% of the price before VAT, and subtotal + VAT = the total.
  if (p.vat_amount != null && base != null && !near(p.vat_amount, r2(base * 0.05))) {
    warnings.push(`We read VAT as ${money(p.vat_amount)}, which is not 5% of ${money(base)}. Please check the VAT.`);
  } else if (p.vat_amount != null && base != null && p.total_incl_vat != null && !near(r2(base + p.vat_amount), p.total_incl_vat)) {
    warnings.push(`${money(base)} plus VAT of ${money(p.vat_amount)} is not the total of ${money(p.total_incl_vat)} we read. Please check the total.`);
  }
  // 4. The code money reader as the checker: a total it found that none of the model's figures is.
  if (code && base != null) {
    const ours = [p.amount, p.price_ex_vat, p.gross_amount, p.subtotal, p.total_incl_vat, ...p.options.map((o) => o.amount)];
    // Only a figure the file actually prints is put to the supplier: the code reader can misread a plain-text body (measured
    // 12 Nov 2026 on main's reader: "Grand Total AED 9,450" in a .txt was read as AED 9, the thousands comma taken for a
    // CSV separator), and a question about a figure he never wrote would be noise.
    const printed = String(docText || '').trim() ? figuresIn(docText) : null;
    const theirs = [code.amount, code.price_ex_vat, code.gross_amount, code.total_incl_vat, code.subtotal]
      .filter((x): x is number => x != null && x > 0 && (!printed || printed.some((f) => near(f, x, 0.005))));
    const other = theirs.find((c) => !ours.some((m) => near(m, c)));
    if (code.review_reason === 'conflicting_totals' || code.review_reason === 'option_total_mismatch') warnings.push(`Your file shows more than one total. We read your total as ${money(base)} excluding VAT. Is that right?`);
    else if (theirs.length && other != null && p.options.length < 2) warnings.push(`We read your total as ${money(base)} excluding VAT, but your file also shows ${money(other)}. Is ${money(base)} right?`);
  }
  // 5. The model itself was unsure.
  if (p.confidence_stated === 'low' && base != null && !warnings.length) warnings.push(`We were not sure of your total. We read it as ${money(base)} excluding VAT. Is that right?`);
  // 6. A NOTE, never a question and never a block: a figure the model returned that the file's text layer does not show.
  if (String(docText || '').trim()) {
    const seen = figuresIn(docText);
    const named: [string, number | null][] = [['total', p.total_incl_vat ?? p.gross_amount ?? p.amount], ['subtotal', p.subtotal], ['VAT', p.vat_amount]];
    for (const [k, v] of named) if (v != null && !seen.some((s) => near(s, v, 0.005))) notes.push(`The ${k} ${money(v)} the model read is not in the file's text layer (a text layer can drop characters; this is a note, not a block).`);
  }
  out.check_notes = notes;
  return warnings.length ? { ...out, warnings } : out;
}
