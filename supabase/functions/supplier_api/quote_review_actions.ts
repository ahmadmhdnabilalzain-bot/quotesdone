// supplier_api/quote_review_actions.ts — the supplier_api actions behind INQUIRIES RECEIVED and
// QUOTATIONS SUBMITTED (founder, 15 Sep 2026). Assigned: sales_engineer.
//
// API-FIRST (founder: "later this will be a mobile app as well. the structure need to be built in
// already"). Every action here is a POST to supplier_api with {action, ...} and the supplier's own
// session, and answers typed JSON (docs/api/supplier_portal_quotations.md); nothing depends on a
// browser. A file arrives as base64 in the JSON body, which any native client can send.
//
// NOTHING HERE READS THE INQUIRY ITSELF. `self` runs supplier_api's own `inbox` in-process with the
// caller's session, so the job, its BOQ and its drawings reach the supplier only through the inbox's
// scrubbers and its reveal gate (the customer's identity never before a reveal), and a job this
// supplier is not matched to does not exist for them. Submission is `self(submit_quote)` for the same
// reason: the hold gate and everything downstream run unchanged.
//
// The caller (index.ts) resolves the supplier from the session and supplies the repository and the
// upload gate, so this module holds no client and no credential of its own.
import { jobNo, type BoqRow, type Lang, type SafeInquiry } from './quote_review.ts';
import * as flow from './quote_review_flow.ts';

export const REVIEW_ACTIONS = new Set(['inquiries_list', 'inquiry_detail', 'inquiry_documents', 'review_thread', 'review_start', 'review_message', 'review_upload', 'review_choose', 'review_submit']);
// deno-lint-ignore no-explicit-any
type Json = any;
export type Self = (body: Record<string, unknown>) => Promise<{ status: number; json: Json }>;
export type Supplier = { id: number; company_name: string | null; locale: string | null };
/** A quotation file is at most 10 MB; base64 makes that about 13.4 MB of JSON. */
export const MAX_FILE = 10 * 1024 * 1024;
export const MAX_B64 = Math.ceil(MAX_FILE / 3) * 4 + 64;

const boqRows = (i: Json): BoqRow[] => (Array.isArray(i?.boq?.boq) ? i.boq.boq : []);
export const safeInquiry = (i: Json): SafeInquiry => ({
  id: String(i.id), job_no: jobNo(i), category: i.category ?? null, emirate: i.emirate ?? null, spec: i.spec ?? null,
  boq_rows: boqRows(i), boq_withheld: !!i.boq_withheld, concluded: !!i.concluded, revealed: !!i.revealed,
});
/**
 * The BOQ as a CSV file (UTF-8 with a byte-order mark, so Excel opens the Arabic). A cell that starts
 * with = + - @ tab or CR is prefixed with ' so Excel shows it as text and never runs it as a formula:
 * BOQ text is customer-authored (security review, 15 Sep 2026: CSV injection, CWE-1236).
 */
export function boqCsv(rows: BoqRow[]): string {
  const esc = (v: unknown) => { let s = v == null ? '' : String(v); if (/^[=+\-@\t\r]/.test(s)) s = "'" + s; return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s; };
  return '﻿' + [['No', 'Section', 'Description', 'Qty', 'Unit'].join(','), ...rows.map((r, k) => [k + 1, r.section, r.description, r.qty, r.unit].map(esc).join(','))].join('\r\n') + '\r\n';
}
const extOf = (url: string) => { const m = String(url).split('?')[0].match(/\.([a-z0-9]{2,4})$/i); return m ? '.' + m[1].toLowerCase() : ''; };

export async function reviewAction(o: { sup: Supplier; email: string; self: Self; body: Json; repo: flow.ReviewRepo; scan: flow.ReviewDeps['scan'] }): Promise<{ status: number; json: unknown }> {
  const { sup, email, self, body, repo } = o;
  const action = String(body.action);
  const lang: Lang = body.lang === 'ar' || (body.lang !== 'en' && String(sup.locale || '').startsWith('ar')) ? 'ar' : 'en';
  const inbox = async (inquiryId?: string) => (await self({ action: 'inbox', ...(inquiryId ? { inquiry_id: inquiryId } : {}) })).json || {};
  const one = async (id: unknown) => {
    if (!/^[0-9a-f-]{36}$/i.test(String(id || ''))) return null;
    const j = await inbox(String(id));
    return (j.inquiries || []).find((x: Json) => String(x.id) === String(id)) || null;
  };
  const stateOf = (reviews: { inquiry_id: string; status: string; updated_at: string }[], id: string) => {
    const r = reviews.find((x) => String(x.inquiry_id) === String(id));
    return r ? { state: r.status, updated_at: r.updated_at } : null;
  };

  if (action === 'inquiries_list') {
    const j = await inbox();
    if (j.error) return { status: 400, json: j };
    const reviews = await repo.reviewsOf(sup.id);
    const inquiries = (j.inquiries || []).map((i: Json) => {
      const qs: Json[] = Array.isArray(i.quotes) ? i.quotes : (i.quote ? [i.quote] : []);
      return {
        id: i.id, job_no: jobNo(i), category: i.category ?? null, emirate: i.emirate ?? null, created_at: i.created_at, status: i.status,
        concluded: !!i.concluded, revealed: !!i.revealed, you_won: !!i.you_won, summary: i.summary ? String(i.summary).slice(0, 220) : null,
        boq_lines: boqRows(i).length, boq_withheld: !!i.boq_withheld, drawing_pages: (i.drawing_pages || []).length,
        // What the inquiry HAS versus what could be signed. Without both, a row reading "2 drawing
        // pages" cannot be told from one that has three and lost one on the way out.
        drawing_pages_expected: Number(i.drawing_pages_expected ?? (i.drawing_pages || []).length),
        drawing_pages_failed: Number(i.drawing_pages_failed || 0),
        quotes: qs.map((q) => ({ id: q.id, option_no: q.option_no || 1, status: q.status, quote_amount: q.quote_amount, on_hold: !!q.spec_hold })),
        review: stateOf(reviews, i.id),
      };
    });
    return { status: 200, json: { ok: true, approval_status: j.approval_status ?? null, inquiries } };
  }

  if (action === 'inquiry_detail') {
    const i = await one(body.inquiry_id); if (!i) return { status: 404, json: { error: 'not_found', code: 'not_found' } };
    return { status: 200, json: { ok: true, inquiry: {
      id: i.id, job_no: jobNo(i), category: i.category ?? null, emirate: i.emirate ?? null, created_at: i.created_at, status: i.status,
      concluded: !!i.concluded, revealed: !!i.revealed, you_won: !!i.you_won, summary: i.summary ?? null, budget: i.budget ?? null,
      scope_type: i.scope_type ?? null, spec: i.spec ?? null, requested: i.spec?.customer_requirements?.display ?? null,
      boq: i.boq ?? null, boq_withheld: !!i.boq_withheld, boq_confidence: i.boq_confidence ?? null, drawing_pages: i.drawing_pages || [],
      drawing_pages_expected: Number(i.drawing_pages_expected ?? (i.drawing_pages || []).length),
      drawing_pages_served: Number(i.drawing_pages_served ?? (i.drawing_pages || []).length),
      drawing_pages_failed: Number(i.drawing_pages_failed || 0),
      quotes: i.quotes || [], review: stateOf(await repo.reviewsOf(sup.id), i.id),
    } } };
  }

  if (action === 'inquiry_documents') {
    const i = await one(body.inquiry_id); if (!i) return { status: 404, json: { error: 'not_found', code: 'not_found' } };
    const job = jobNo(i);
    // Only what the inbox already serves: the REDACTED drawing pages (signed for an hour) and the
    // scrubbed BOQ. The customer's original drawing is never offered.
    const documents: Json[] = (i.drawing_pages || []).map((u: string, k: number) => ({ kind: 'drawing_page', name: `Job_${job}_drawing_p${String(k + 1).padStart(2, '0')}${extOf(u)}`, url: u, expires_in: 3600 }));
    const rows = boqRows(i);
    if (rows.length) documents.push({ kind: 'boq_csv', name: `Job_${job}_BOQ.csv`, mime: 'text/csv', content: boqCsv(rows), lines: rows.length });
    // A page that could not be signed is missing from this list too, so the list says how many.
    return { status: 200, json: { ok: true, job_no: job, boq_withheld: !!i.boq_withheld, documents,
      drawing_pages_expected: Number(i.drawing_pages_expected ?? (i.drawing_pages || []).length),
      drawing_pages_failed: Number(i.drawing_pages_failed || 0) } };
  }

  // ── The conversation ─────────────────────────────────────────────────────────────────────────
  const deps: flow.ReviewDeps = {
    inquiry: async (id) => { const i = await one(id); return i ? safeInquiry(i) : null; },
    async scan(b64, filename, mime) {
      if (b64.length > MAX_B64) return { ok: false, status: 413, code: 'file_too_large', message: 'That file is too large. Please attach a file under 10 MB.' };
      return o.scan(b64, filename, mime);
    },
    read: (bytes, name, mime) => flow.readQuotationFile(bytes, name, mime, [String(sup.company_name || '')].filter((s) => s.length >= 3)),
    submit: (p) => self(p),
    quotePdf: async (quoteId, l) => { const r = await self({ action: 'quote_pdf', quote_id: quoteId, lang: l }); return { url: r.json?.url ?? null, ref: r.json?.ref ?? null }; },
    now: () => new Date(),
  };
  const ctx: flow.Ctx = { supplierId: Number(sup.id), email, lang, companyName: sup.company_name ?? null };
  const id = String(body.inquiry_id || '');
  const res = action === 'review_thread' ? await flow.thread(repo, deps, ctx, id)
    : action === 'review_start' ? await flow.start(repo, deps, ctx, id)
    : action === 'review_upload' ? await flow.upload(repo, deps, ctx, id, body.file || {}, body.text)
    : action === 'review_message' ? await flow.message(repo, deps, ctx, id, body.text)
    : action === 'review_choose' ? await flow.choose(repo, deps, ctx, id, body.choice)
    : await flow.submit(repo, deps, ctx, id);
  if (res.ok === false) return { status: res.status, json: { error: res.code, code: res.code, message: res.message } };
  return { status: 200, json: res };
}
