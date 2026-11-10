// email_quote — A QUOTATION THAT ARRIVES BY E-MAIL TAKES THE PORTAL'S OWN ROAD (customer_support, 10 Nov 2026; founder
// ruling 1608, supplier follow-up #1909 item 1).
//
// MEASURED on origin/main: resend_inbound read every supplier attachment as a PROFILE document. A matched supplier who
// e-mailed his quotation in reply to a request was answered "we received 1 document(s) and our team will add them to
// your profile"; the file went to the supplier-docs bucket and doc_reviews, and no quote ever reached the request.
//
// WHAT THIS DOES. resend_inbound decides (resend_inbound/quote_by_email.ts) that the mail is a quotation, from a
// verified sender, for ONE request he was matched to. It then calls this internal door, which runs the two portal
// actions in order, as the supplier, in-process:
//   1. extract_quote — the file is scanned and stored under quote-files, read by quote_extract (code first, the model
//      only where code found no total), with the read-every-attachment fallback, and its reader is recorded;
//   2. submit_quote — with the payload the quotation-review chat hands it (quote_review_flow/submit.ts submitPayload):
//      the review's rules 1-7 and the hold desk's ONE evaluator (line_specs/workflow.ts gate, #1898) decide whether
//      the quote is sent to the customer, held with the exact details listed, or kept as a draft.
// Nothing here judges a quotation: no second reader, no second review, no second hold. The answer is the portal's
// answer, which resend_inbound words to the supplier in English with the portal link.
//
// WHO. The supplier is the company whose claimed_by address the mail came from (resend_inbound proves that before it
// calls). The account must be claimed (both actions key on claimed_by) and not sanctioned (the same refusal index.ts
// gives every signed-in action). The job is read through `inbox` for that account, the one door a supplier may see a
// job through, exactly as safeInquiryOf does for a signed-in caller.
// prevented by: supplier_api/email_quote.test.ts
import { submitPayload } from './quote_review_flow/submit.ts';
import { workingFromProposal } from './quote_review/working.ts';
import { reviewQuotation, type SafeInquiry } from './quote_review.ts';
import type { Proposal } from '../quote_extract/quote_from_document.ts';
import type { ActionCtx } from './context.ts';

// deno-lint-ignore no-explicit-any
type Json = Record<string, any>;
export type EmailQuoteInput = { lead_id: number; inquiry_id: string; file_b64: string; filename: string; mime: string };
export type EmailQuoteDeps = {
  /** The lead row: who the supplier is and the address he signs in with. */
  lead: (id: number) => Promise<{ id: number; claimed_by: string | null } | null>;
  sanctioned: (email: string) => Promise<boolean>;
  /** supplier_api's own action groups, run in-process with the supplier's context. */
  quoteActions: (c: ActionCtx) => Promise<Response | undefined>;
  inboxActions: (c: ActionCtx) => Promise<Response | undefined>;
  safeInquiry: (row: Json) => SafeInquiry;
};
/** What resend_inbound words for the supplier. `stage` says which portal step answered. */
export type EmailQuoteResult =
  | { ok: true; stage: 'submit'; inquiry_id: string; accepted: boolean; held: boolean; missing: Json[]; message: string | null; code: string | null; amount: number | null; lines: number; options: number }
  | { ok: false; stage: 'who' | 'job' | 'extract' | 'submit'; code: string; message: string | null; review_reason?: string | null };

const isUuid = (s: string) => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);

export async function emailQuote(input: EmailQuoteInput, deps: EmailQuoteDeps): Promise<EmailQuoteResult> {
  const lead = Number.isInteger(Number(input.lead_id)) ? await deps.lead(Number(input.lead_id)) : null;
  const email = String(lead?.claimed_by || '').trim().toLowerCase();
  if (!lead || !/@/.test(email)) return { ok: false, stage: 'who', code: 'no_company', message: null };
  if (await deps.sanctioned(email)) return { ok: false, stage: 'who', code: 'sanctioned', message: null };
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
  const inq = await jobOf(inquiryId);
  if (!inq) return { ok: false, stage: 'job', code: 'not_found', message: null };

  // 1. The portal's reading of the file, stored as the portal stores it.
  const ex = await deps.quoteActions(ctxOf({ action: 'extract_quote', inquiry_id: inquiryId, images: [],
    original: { b64: input.file_b64, filename: input.filename, mime: input.mime } }));
  const exj: Json = ex ? await ex.json().catch(() => ({})) : {};
  if (!exj.ok || !exj.proposal) return { ok: false, stage: 'extract', code: String(exj.code || exj.error || 'quote_read_failed'), message: exj.message ?? null, review_reason: exj.review_reason ?? null };

  // 2. The payload the quotation-review chat hands submit_quote, from the same reading.
  const p = exj.proposal as Proposal;
  const working = workingFromProposal(p);
  const body = { ...submitPayload(inq, { original_file_path: exj.original_file_path ?? null, original_file_name: exj.original_file_name ?? null }, working, reviewQuotation(inq, working)) };
  const sb = await deps.quoteActions(ctxOf(body));
  const sj: Json = sb ? await sb.json().catch(() => ({})) : {};
  if (!sj.ok) return { ok: false, stage: 'submit', code: String(sj.code || sj.error || 'submit_failed'), message: typeof sj.error === 'string' && sj.error !== sj.code ? sj.error : (sj.message ?? null) };
  const opts: Json[] = Array.isArray(sj.options) ? sj.options : [];
  const accepted = opts.length ? opts.some((o) => o.accepted) : !!sj.accepted;
  const held = opts.length ? opts.some((o) => o.held) : !!sj.held;
  const missing = (opts.length ? opts.flatMap((o) => (Array.isArray(o.missing) ? o.missing : [])) : (Array.isArray(sj.missing) ? sj.missing : [])) as Json[];
  return { ok: true, stage: 'submit', inquiry_id: inquiryId, accepted, held, missing, message: sj.message ?? null, code: sj.code ?? null,
    amount: Number(body.amount) > 0 ? Number(body.amount) : null, lines: working.lines.length, options: Math.max(1, opts.length) };
}
