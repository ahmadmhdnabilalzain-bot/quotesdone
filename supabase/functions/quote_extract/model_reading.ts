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
// the e-mail and, as an open review point ('reading_to_confirm', supplier_api/quote_review/review.ts), in his quotation
// thread, which is not approved for submission until he confirms or corrects it; nothing he has not confirmed reaches a
// customer (supplier_api/email_quote.ts).
// prevented by: quote_extract/the_model_reads_the_quotation_and_code_checks_it.test.ts
import { statedPrice } from '../_shared/stated_price.ts';
import type { Extracted } from '../_shared/doc_read/types.ts';
import { quoteFromExtracted, quoteText, type Proposal, type QuoteLine } from './quote_from_document.ts';
import { scrubIdentityText } from '../_shared/identity_text.ts';
import { generaliseText, type GeneraliseCtx } from '../_shared/quote_generalise.ts';

/** quote_extract's own scrub of whatever the model returned (moved here from index.ts unchanged, 13 Nov 2026, so the
 *  careless-model corpus test drives the code the function runs rather than a copy). */
export function scrubModelText(s: unknown): string {
  let t = String(s == null ? '' : s);
  // A start only where the address starts (13 Nov 2026: 50 KB of "Al-Al-…" with no "@" re-read itself for 2 s).
  t = t.replace(/(?<![\w.+-])[\w.+-]{1,64}@[\w-]+\.[\w.-]+/g, '█');
  t = t.replace(/https?:\/\/\S+|www\.[\w.-]+\.[a-z]{2,}/gi, '█');
  t = t.replace(/(?:\+?\d[\d\s().-]{6,}\d)/g, (m) => (m.replace(/\D/g, '').length >= 7 ? '█' : m));
  // 3 Nov 2026: the shared identity shapes too (_shared/identity_text.ts), whatever the model left in.
  return scrubIdentityText(t, '█').trim();
}
/**
 * THE MODEL'S MASKING IS CHECKED, NOT TRUSTED (10 Nov 2026, ledger 1589): the anonymiser every text field of the model's
 * answer passes (scrubModelText, then the shared generaliser). Each term it takes out is added to `masked` (the answer's
 * masked_terms), for the supplier's own review.
 */
export function modelAnonymiser(ctx: GeneraliseCtx, masked: string[]): (v: unknown) => string {
  return (v: unknown) => { const r = generaliseText(scrubModelText(v), ctx); for (const t of r.replaced) if (!masked.includes(t.term)) masked.push(t.term); return r.text; };
}

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
  /** Figures the model returned that code could not read as one plain positive amount, or absurd ones: put to the supplier. */
  figure_doubts: string[];
  /** The price before VAT was derived as total - VAT (VAT written on top, no subtotal written). */
  vat_derived: boolean;
  /** VAT-inclusive only: the total as written, which the portal form prefills beside "Includes VAT". */
  total?: number;
};

const r2 = (n: number) => Math.round(n * 100) / 100;
/** Above this a quotation figure is absurd for this marketplace and is put to the supplier (never silently accepted). */
export const ABSURD_AED = 100_000_000;
/**
 * A FIGURE THE MODEL RETURNED, read exactly or not at all (review of #1981, 12 Nov 2026). Only exact, unambiguous
 * notations are normalised: a number; thousands separators (12,000 / 12 000 / ١٢٬٠٠٠); Arabic-Indic digits; a leading
 * currency word and a trailing "/-". Anything else ("12.000": twelve or twelve thousand? "1,2", "abc", 0, a negative) is
 * not dropped and not guessed: `doubt` names it and the supplier is asked. Before this, "12.000" became 12, "١٢٬٠٠٠",
 * "12,000/-", 0 and negatives became null silently, and 1e9 was accepted.
 */
export function readFigure(v: unknown): { value: number | null; doubt: string | null } {
  if (v == null || v === '') return { value: null, doubt: null };
  const raw = String(v).trim().slice(0, 40);
  let n: number | null = null;
  if (typeof v === 'number') n = Number.isFinite(v) ? v : null;
  else {
    const s = raw.replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x660)).replace(/[۰-۹]/g, (d) => String(d.charCodeAt(0) - 0x6f0))
      .replace(/٬/g, ',').replace(/٫/g, '.')
      .replace(/^(?:AED|Dhs?\.?|د\.?\s?إ\.?|درهم)\s*/i, '').replace(/\s*(?:AED|Dhs?\.?|د\.?\s?إ\.?|درهم)$/i, '').replace(/\s*\/-$/, '').trim();
    if (/^\d{1,3}(?:,\d{3})+(?:\.\d+)?$/.test(s)) n = Number(s.replace(/,/g, ''));
    else if (/^\d{1,3}(?: \d{3})+(?:\.\d+)?$/.test(s)) n = Number(s.replace(/ /g, ''));
    else if (/^\d{1,3}\.\d{3}$/.test(s)) return { value: null, doubt: raw };   // 12.000: twelve, or twelve thousand?
    else if (/^-?\d+(?:\.\d+)?$/.test(s)) n = Number(s);
    else return { value: null, doubt: raw };
  }
  // A plain zero is a figure that is absent (zero-rated VAT, a free line, no discount), not a doubt (review of #1981 N1:
  // "We could not read the VAT ("0")" blocked the e-mailed thread). A TOTAL of zero is asked by proposalFromModel itself.
  if (n === 0) return { value: null, doubt: null };
  if (n == null || !(n > 0)) return { value: null, doubt: raw };
  if (n >= ABSURD_AED) return { value: r2(n), doubt: raw };
  return { value: r2(n), doubt: null };
}
const str = (v: unknown, n = 2000) => (v == null ? '' : String(v)).trim().slice(0, n);
// TOLERANCES (12 Nov 2026). Sums (lines against the subtotal, subtotal + VAT against the total, a total the file prints)
// must agree to 5 fils: printed figures carry two decimals and add exactly, so a larger gap is a reading or a printing
// error (the review proved a 0.99 AED gap went unasked at the old 1 AED). VAT against 5% of the base allows 1 AED, because
// VAT computed and rounded line by line legitimately drifts by a few fils per line.
const SUM_TOL = 0.05; const VAT_TOL = 1;
const near = (a: number | null, b: number | null, tol = SUM_TOL) => a != null && b != null && Math.abs(a - b) <= tol;
export const money = (n: number) => 'AED ' + n.toLocaleString('en-US', { maximumFractionDigits: 2 });
const AED = /^(aed|dhs?|dirhams?|uae\s*dirhams?|د\.?\s?إ\.?|درهم)$/i;
// zero_rated / exempt are stated answers (line_specs/vat.ts, 13 Nov 2026): no VAT is added, the price as written is ex-VAT
const VAT_TREATMENTS = ['exclusive', 'inclusive', 'not_registered', 'zero_rated', 'exempt'];

/**
 * The model's answer in the proposal shape. `gen` is quote_extract's own anonymiser (scrub + _shared/quote_generalise.ts),
 * applied to every text the customer could read; figures are never rewritten.
 */
export function proposalFromModel(ai: ModelAnswer, gen: (v: unknown) => string): ModelProposal {
  const doubts: string[] = [];
  const fig = (v: unknown, what: string) => { const f = readFigure(v); if (f.doubt) doubts.push(f.value != null
    ? `We read ${what} as ${money(f.value)}, which is unusually large for a quotation. Is that right?`
    : `We could not read ${what} ("${f.doubt}") as an amount. Please type it.`); return f.value; };
  const lines: QuoteLine[] = (Array.isArray(ai.line_items) ? ai.line_items : []).slice(0, 200).map((raw, i) => {
    const li = (raw && typeof raw === 'object' ? raw : {}) as Record<string, unknown>;
    const opt = Number(li.option);
    const qtyN = readFigure(li.quantity ?? li.qty).value;
    const unitPrice = fig(li.unit_price, `the rate of line ${i + 1}`);
    return {
      description: gen(li.description), qty: str(li.qty, 60), amount: fig(li.amount, `the amount of line ${i + 1}`),
      // 13 Nov 2026 (anonymity audit, REPORT_C L8): the unit bypassed `gen` and is printed raw on the customer's document,
      // so a careless reading's "m2 (Falcon spec)" crossed. It is text the customer reads: it passes the anonymiser. The
      // country of origin stays a country (the customer door cuts it to the country, countryOnly) and qty is a figure.
      ...(qtyN != null ? { quantity: qtyN } : {}), ...(str(li.unit) ? { unit: gen(str(li.unit, 40)).slice(0, 40) } : {}),
      ...(unitPrice != null ? { unit_price: unitPrice } : {}),
      ...(Number.isInteger(opt) && opt >= 1 && opt <= 20 ? { option: opt } : {}),
      ...(str(li.country_of_origin) ? { country_of_origin: str(li.country_of_origin, 80) } : {}),
    };
  });
  // OPTIONS: two or more alternatives the quotation offers, each with its own total (founder, 14 Sep 2026: each option is
  // its own quotation; supplier_api's submit_quote splits on option_totals).
  const opts = (Array.isArray(ai.options) ? ai.options : []).map((o) => (o && typeof o === 'object' ? o : {}) as Record<string, unknown>)
    .map((o, i) => ({ option_no: i + 1, label: str(o.label, 80), amount: fig(o.total ?? o.amount, `the total of option ${i + 1}`) })).filter((o) => o.amount != null).slice(0, 20);
  const options = opts.length > 1 ? opts.map((o) => ({ option_no: o.option_no, amount: o.amount })) : [];
  const option_totals: Record<string, number> = {};
  if (options.length) for (const o of opts) option_totals[String(o.option_no)] = o.amount!;
  const total = fig(ai.total ?? ai.amount, 'your total');
  if (total == null && readFigure(ai.total ?? ai.amount).doubt == null && /^\s*(?:AED|Dhs?\.?)?\s*0+(?:\.0+)?\s*$/i.test(String(ai.total ?? ai.amount ?? ''))) doubts.push('We read your total as AED 0. Please type your total.');
  const subtotal = fig(ai.subtotal, 'your subtotal');
  const vat = fig(ai.vat_amount, 'the VAT');
  const stated = VAT_TREATMENTS.includes(str(ai.vat_treatment)) ? str(ai.vat_treatment) : null;
  // The arithmetic is code's (rulings 1207/1208): the price compared and the fee base is the price after the stated
  // discount, excluding VAT. `text` is empty on purpose: the VAT basis and the discount are what the model read, not a
  // second reading of the file's words by pattern.
  // The model's subtotal is the price before VAT AFTER any discount; statedPrice's `subtotal` is before the discount, so
  // with a discount it is passed as the after-discount `net_amount` (measured: passed as `subtotal`, 2,000 less 300 with
  // a 1,700 subtotal came out 1,400).
  const disc = fig(ai.discount_amount, 'the discount');
  // VAT WRITTEN WITH A TOTAL AND NO SUBTOTAL (review D4, then N2): which figure is the price before VAT is decided by the
  // arithmetic, never by the layout. If 5% of (total - VAT) is the VAT, the total includes it (9,450 with VAT 450 -> 9,000);
  // if 5% of the total is the VAT, the total is the price before VAT ("Total 9,000 + VAT 450" -> 9,000, 9,450 with VAT);
  // if neither, nothing is prefilled and he is asked which figure is his price before VAT. (D4 alone priced the second at
  // 8,550, one tap from stored.) Inclusive already subtracts the VAT itself.
  // THE LAYOUT TOLERANCE IS PROPORTIONATE (review of #1981 N6): at the flat 1 AED both tests passed whenever the VAT was 20 AED
  // or less, and "includes VAT" won ("Total 400 + VAT 20" became 380). VAT rounded to the fils line by line drifts by at most
  // 5 fils a line, so that is the tolerance (5 fils for one figure). If both layouts still fit, nothing is guessed: he is asked.
  const layoutTol = 0.005 * Math.max(1, lines.length) + 1e-9;
  const fitsIncl = vat != null && total != null && Math.abs((total - vat) * 0.05 - vat) <= layoutTol;
  const fitsExcl = vat != null && total != null && Math.abs(total * 0.05 - vat) <= layoutTol;
  const layout = !disc && subtotal == null && vat != null && total != null && stated !== 'inclusive' && vat < total
    ? (fitsIncl && !fitsExcl ? 'incl' : fitsExcl && !fitsIncl ? 'excl' : 'unknown') : null;
  const derivedSub = layout === 'incl' ? r2(total! - vat!) : layout === 'excl' ? total : null;
  const totalWithVat = layout === 'excl' ? r2(total! + vat!) : total;
  if (layout === 'unknown') doubts.push(`We read a total of ${money(total!)} and VAT of ${money(vat!)}, and cannot tell which is your price before VAT: is it ${money(total!)}, or ${money(r2(total! - vat!))}? Please type your price before VAT.`);
  const sub = subtotal ?? derivedSub;
  const sp = statedPrice({ amount: layout === 'unknown' ? null : totalWithVat, subtotal: disc ? null : sub, net_amount: disc ? subtotal : null, vat_amount: vat, text: '', stated,
    gross_amount: fig(ai.gross_amount, 'the price before the discount'), discount_amount: disc, discount_label: str(ai.discount_label, 80) || null });
  const currency = str(ai.currency, 12);
  const foreign = !!currency && !AED.test(currency);
  const p: ModelProposal = {
    amount: options.length ? options[0].amount : layout === 'unknown' ? null : (sp.price_ex_vat ?? total), currency: 'AED', line_items: lines,
    lead_time: gen(ai.lead_time), validity: gen(ai.validity), payment_terms: gen(ai.payment_terms), warranty: gen(ai.warranty),
    scope: gen(ai.scope), conditions: gen(ai.conditions), exclusions: gen(ai.exclusions), notes: gen(ai.notes),
    description_anonymized: gen(ai.description_anonymized), masked_terms: [], confidence: 'low', method: 'document',
    subtotal: sub, vat_amount: sp.vat_amount, total_incl_vat: layout === 'unknown' ? null : sp.vat_amount && totalWithVat ? totalWithVat : null,
    vat_treatment: sp.treatment, price_ex_vat: options.length ? null : sp.price_ex_vat, trn: null,
    gross_amount: options.length ? null : sp.gross_amount, discount_amount: options.length ? null : sp.discount_amount,
    discount_label: options.length ? null : sp.discount_label, options, option_totals,
    // VAT-INCLUSIVE (review D2): the portal form prefills `total ?? amount` beside the stated treatment, and submit_quote
    // takes VAT out of an inclusive figure itself; given the ex-VAT `amount` it stored 9,000 - 450 = 8,550.
    ...(!options.length && sp.treatment === 'inclusive' && total != null ? { total } : {}),
    is_quotation: ai.is_quotation === true || ai.is_quotation === 'true',
    not_a_quotation_reason: str(ai.not_a_quotation_reason, 300), request_reference: str(ai.request_reference, 60),
    currency_stated: currency, confidence_stated: str(ai.confidence, 12).toLowerCase(), check_notes: [],
    figure_doubts: doubts, vat_derived: layout === 'incl',
  };
  // ANOTHER CURRENCY (review D1): no figure leaves this function as if it were AED. Every price is withheld, exactly as the
  // code reader does (quote_from_document.ts 'foreign_currency'); the supplier types his AED total.
  if (foreign) Object.assign(p, { review_reason: 'foreign_currency' as const, amount: null, price_ex_vat: null, subtotal: null, vat_amount: null,
    total_incl_vat: null, gross_amount: null, discount_amount: null, options: [], option_totals: {}, total: undefined,
    line_items: lines.map((l) => ({ ...l, amount: null, unit_price: undefined })) });
  return p;
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

/**
 * The code money reader's reading, for the CHECKER only. A plain-text body is given to it AS WRITTEN (review of #1981 D7: read
 * through doc_read it was CSV cells, the 'printed' filter dropped every figure, and a body's total was never checked);
 * any other file as doc_read opened it.
 */
export function checkerReading(fileB64: string | null | undefined, filename: string, mime: string, docText: string, rd: { ok: boolean } | null, masks: string[] = []): CodeReading {
  if (fileB64 && (/^text\/plain/i.test(mime) || /\.txt$/i.test(filename))) return quoteFromExtracted({ kind: 'txt', text: docText, tables: [], children: [] } as unknown as Extracted, masks);
  return rd?.ok ? quoteFromExtracted(rd as unknown as Extracted, masks) : null;
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
  // 0. A figure code could not read as one plain positive amount, or an absurd one (readFigure): asked, never dropped.
  warnings.push(...(p.figure_doubts ?? []));
  if (p.review_reason === 'foreign_currency') {
    warnings.push(`Your quotation is priced in ${p.currency_stated}. Customers compare quotations in AED: please type your AED total.`);
    return { ...out, warnings };
  }
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
  // 3. VAT: 5% of the price before VAT, and subtotal + VAT = the total. Not on options: an option's total may include its
  // VAT, and one VAT figure against option 1 is no test (review D7: a false "VAT is not 5% of AED 12,600").
  if (p.options.length < 2 && p.vat_amount != null && base != null && !near(p.vat_amount, r2(base * 0.05), VAT_TOL)) {
    // Name the figure in doubt (review D4): when the price before VAT was derived as total - VAT, it is the total or the
    // VAT that is wrong, not "the VAT" alone.
    warnings.push(p.vat_derived && p.total_incl_vat != null
      ? `We read your total including VAT as ${money(p.total_incl_vat)} and the VAT as ${money(p.vat_amount)}. That makes your price before VAT ${money(base)}, but 5% of ${money(base)} is ${money(r2(base * 0.05))}. Which is right: the total or the VAT?`
      : `We read VAT as ${money(p.vat_amount)}, which is not 5% of your price before VAT of ${money(base)}. Which is right: the VAT or the price?`);
  } else if (p.options.length < 2 && p.vat_amount != null && base != null && p.total_incl_vat != null && !near(r2(base + p.vat_amount), p.total_incl_vat)) {
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
