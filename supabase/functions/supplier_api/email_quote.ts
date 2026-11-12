// email_quote — A QUOTATION THAT ARRIVES BY E-MAIL IS READ BY THE MODEL AND WAITS FOR THE SUPPLIER TO CONFIRM IT
// (customer_support, 10 Nov 2026, founder ruling 1608, #1909 item 1; sales_engineer, 12 Nov 2026, rulings 1663, 1664,
// 1666 and LLM-first audit A2).
//
// MEASURED on origin/main 4b7091f08 (12 Nov 2026), by running main's own quote_by_email + readQuotationFile (the code
// reader) on the audit's examples (docs/reports/2026-11-12-llm-first-audit.md, A2): a CODE reader decided whether a mail
// was a quotation, and this door then ran extract_quote and submit_quote, whose review rules and hold desk decided whether
// it went to the customer. Nobody confirmed the figures first. Main submitted: a tax invoice for another job attached to
// a reply (as the quotation); a body "Grand Total AED 9,450 including VAT" as AED 9 (doc_read reads a .txt with commas as
// CSV); an Option A 12,000 / Option B 9,500 sheet as options of AED 24,000 and 19,000 (each option's total row counted as
// a line). The audit's call-out example ("minimum call-out charge AED 150, we will visit Sunday") was NOT priced by main's
// reader in any of five wordings tried: that example was wrong.

// WHAT THIS DOES NOW.
//   email_quote_read — resend_inbound asks here, for each candidate file (or the body), what the MODEL reads: is it a
//     quotation, which request it cites, and the proposal. One quote_extract call (the model; the code money reader only
//     checks, quote_extract/model_reading.ts). A model that does not answer leaves it 'unread': never priced by code.
//   email_quote — the reading resend_inbound already has (no second model call) is placed in the supplier's own
//     quotation thread for that request, exactly as if he had attached the file in the portal
//     (quote_review_flow upload: the file stored, the review run, the thread written). Nothing is submitted. The
//     quotation reaches the customer only when the supplier opens it, checks the figures we read and presses Submit, and
//     submit_quote's review and the hold desk then run as for every quotation.
//
// WHO. The supplier is the company whose claimed_by address the mail came from (resend_inbound proves that before it
// calls). The account must be claimed and not sanctioned (the same refusal index.ts gives every signed-in action). The
// job is read through `inbox` for that account, the one door a supplier may see a job through.
// prevented by: supplier_api/email_quote.test.ts
import type { Proposal } from '../quote_extract/quote_from_document.ts';
import type { SafeInquiry } from './quote_review.ts';
import type { ActionCtx } from './context.ts';

// deno-lint-ignore no-explicit-any
type Json = Record<string, any>;
export type EmailFile = { file_b64: string; filename: string; mime: string };
/** What the model read: the proposal (quote_extract's shape) and which model read it. */
export type EmailReading = {
  verdict: 'quotation' | 'not_quotation' | 'unread';
  proposal: (Proposal & { warnings?: string[]; request_reference?: string }) | null;
  extracted_by_model: string | null; reason: string | null; review_reason: string | null;
};
export type EmailReadInput = EmailFile & { lead_id: number; requests?: { job_no: string; category: string | null }[] };
export type EmailQuoteInput = EmailFile & { lead_id: number; inquiry_id: string; reading?: Pick<EmailReading, 'proposal' | 'extracted_by_model'> | null };
export type EmailQuoteDeps = {
  /** The lead row: who the supplier is and the address he signs in with. */
  lead: (id: number) => Promise<{ id: number; claimed_by: string | null; company_name?: string | null } | null>;
  sanctioned: (email: string) => Promise<boolean>;
  /** supplier_api's own inbox action, run in-process with the supplier's context. */
  inboxActions: (c: ActionCtx) => Promise<Response | undefined>;
  safeInquiry: (row: Json) => SafeInquiry;
  /** quote_extract (the model), called with supplier_api's own credential. Answers quote_extract's JSON. */
  extract: (body: Json) => Promise<Json>;
  /** The portal's quotation thread for this supplier and request: quote_review_flow upload with the reading supplied. */
  review: (a: { lead: { id: number; claimed_by: string; company_name: string | null }; inquiry: (id: string) => Promise<SafeInquiry | null>; inquiryId: string;
    file: { b64: string; filename: string; mime: string }; proposal: Proposal }) => Promise<{ ok: true; state: string } | { ok: false; code: string; message: string }>;
};
/** What resend_inbound words for the supplier. `stage` says which step answered. */
export type EmailQuoteResult =
  | { ok: true; stage: 'review'; inquiry_id: string; state: string; amount: number | null; lines: number; options: number; warnings: string[] }
  | { ok: false; stage: 'who' | 'job' | 'extract' | 'review'; code: string; message: string | null; review_reason?: string | null };

const isUuid = (s: string) => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);

async function who(id: unknown, deps: Pick<EmailQuoteDeps, 'lead' | 'sanctioned'>) {
  const lead = Number.isInteger(Number(id)) ? await deps.lead(Number(id)) : null;
  const email = String(lead?.claimed_by || '').trim().toLowerCase();
  if (!lead || !/@/.test(email)) return { ok: false as const, code: 'no_company' };
  if (await deps.sanctioned(email)) return { ok: false as const, code: 'sanctioned' };
  return { ok: true as const, lead: { id: lead.id, claimed_by: email, company_name: lead.company_name ?? null } };
}

/** The model's reading of one candidate (a file, or the body as text). Never priced by code. */
export async function emailQuoteRead(input: EmailReadInput, deps: Pick<EmailQuoteDeps, 'lead' | 'sanctioned' | 'extract'>): Promise<EmailReading | { verdict: 'refused'; code: string }> {
  const w = await who(input.lead_id, deps);
  if (!w.ok) return { verdict: 'refused', code: w.code };
  const jd = await deps.extract({ file_b64: String(input.file_b64 || ''), filename: String(input.filename || 'quotation'), mime: String(input.mime || ''),
    supplier_terms: [String(w.lead.company_name || '')].filter(Boolean), requests: Array.isArray(input.requests) ? input.requests.slice(0, 10) : [],
    subject: { supplier_id: w.lead.id, email: w.lead.claimed_by } }).catch((): Json => ({ ok: false, error: 'model_unavailable' }));
  const by = typeof jd?.extracted_by_model === 'string' && jd.extracted_by_model ? jd.extracted_by_model : null;
  const proposal = jd?.proposal && typeof jd.proposal === 'object' ? jd.proposal : null;
  // The model said it is a quotation: priced (ok), priced in another currency, or with no total it could state.
  if (jd?.ok || (jd?.is_quotation === true && proposal)) return { verdict: 'quotation', proposal, extracted_by_model: by, reason: null, review_reason: jd?.review_reason ?? proposal?.review_reason ?? null };
  if (jd?.error === 'not_a_quotation') return { verdict: 'not_quotation', proposal: null, extracted_by_model: by, reason: jd?.reason ?? null, review_reason: null };
  // No answer, or an answer that could not be parsed: unread, and retryable. Nothing is decided by code.
  return { verdict: 'unread', proposal: null, extracted_by_model: by, reason: String(jd?.error || 'model_unavailable'), review_reason: null };
}

export async function emailQuote(input: EmailQuoteInput, deps: EmailQuoteDeps): Promise<EmailQuoteResult> {
  const w = await who(input.lead_id, deps);
  if (!w.ok) return { ok: false, stage: 'who', code: w.code, message: null };
  const email = w.lead.claimed_by;
  const inquiryId = String(input.inquiry_id || '').toLowerCase();
  if (!isUuid(inquiryId)) return { ok: false, stage: 'job', code: 'not_found', message: null };
  const req = new Request('http://supplier_api.internal/email_quote', { method: 'POST' });
  const ctxOf = (body: Json): ActionCtx => ({ req, jwt: '', user: null as unknown as ActionCtx['user'], email, body, action: body.action,
    handle: () => Promise.reject(new Error('email_quote runs the actions directly')), safeInquiryOf: (_r, _j, id) => jobOf(id) });
  const jobOf = async (id: string): Promise<SafeInquiry | null> => {
    const r = await deps.inboxActions(ctxOf({ action: 'inbox', inquiry_id: id }));
    const j = r ? await r.json().catch(() => ({})) : {};
    const row = (j.inquiries || []).find((x: Json) => String(x.id) === id);
    return row ? deps.safeInquiry(row) : null;
  };
  if (!(await jobOf(inquiryId))) return { ok: false, stage: 'job', code: 'not_found', message: null };

  // 1. The model's reading: the one resend_inbound already has, else read now (one call either way).
  let reading = input.reading?.proposal ? input.reading : null;
  if (!reading) {
    const r = await emailQuoteRead({ lead_id: w.lead.id, file_b64: input.file_b64, filename: input.filename, mime: input.mime }, deps);
    if (r.verdict !== 'quotation' || !r.proposal) return { ok: false, stage: 'extract', code: r.verdict === 'refused' ? r.code : r.verdict === 'not_quotation' ? 'not_a_quotation' : 'quote_read_delayed', message: null, review_reason: null };
    reading = r;
  }
  // ANOTHER CURRENCY STOPS HERE (review of #1981, D1): placed in the thread, a USD reading was reviewed as AED and one Submit
  // sent it as AED 9,000. As on main, the supplier is asked to type his AED total; nothing is placed.
  if (reading.proposal?.review_reason === 'foreign_currency') return { ok: false, stage: 'extract', code: 'quote_total_ambiguous', message: null, review_reason: 'foreign_currency' };
  const proposal = { ...reading.proposal!, extracted_by_model: reading.extracted_by_model || 'unknown' } as Proposal;

  // 2. Into his quotation thread, as an upload: stored, reviewed, waiting for HIS Submit. Nothing is sent from here.
  const rv = await deps.review({ lead: w.lead, inquiry: jobOf, inquiryId, file: { b64: input.file_b64, filename: input.filename, mime: input.mime }, proposal });
  if (!rv.ok) return { ok: false, stage: 'review', code: rv.code, message: rv.message };
  const p = reading.proposal!;
  return { ok: true, stage: 'review', inquiry_id: inquiryId, state: rv.state, amount: Number(p.amount) > 0 ? Number(p.amount) : null,
    lines: Array.isArray(p.line_items) ? p.line_items.length : 0, options: Math.max(1, Array.isArray(p.options) ? p.options.length : 0),
    warnings: Array.isArray(p.warnings) ? p.warnings.map(String).slice(0, 8) : [] };
}
