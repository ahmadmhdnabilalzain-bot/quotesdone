// The typed client for Inquiries received and Quotations submitted (15 Sep 2026).
//
// Every shape here mirrors supabase/functions/supplier_api/quote_review_flow.ts and
// quote_review_actions.ts, and both are documented in docs/api/supplier_portal_quotations.md — the
// contract a mobile app calls too (founder: "later this will be a mobile app as well"). This file only
// calls the server; the conversation's state and the review rules live there, never here.
import { call } from './api';

export type Lang = 'en' | 'ar';
export type ReviewState = 'none' | 'open' | 'reviewing' | 'changes_requested' | 'awaiting_choice' | 'awaiting_upload' | 'ready_to_submit' | 'submitted' | 'closed';
export type Issue = { code: string; kind: 'adjustment' | 'clarification'; line_no: number | null; boq_line: number | null; attr: string | null; en: string; ar: string };
export type QuoteSummary = { id: string; option_no: number; status: string; quote_amount: number | null; on_hold: boolean;
  /** Why this quote lost (concluded, not won): fixed English reasons, never a rival's identity or figure. */
  loss_feedback?: { code: string; text: string }[] | null };

export type InquiryListItem = {
  id: string; job_no: string; category: string | null; emirate: string | null; created_at: string; status: string;
  concluded: boolean; revealed: boolean; you_won: boolean; summary: string | null;
  boq_lines: number; boq_withheld: boolean; drawing_pages: number; quotes: QuoteSummary[];
  /** What the inquiry HAS, and how many of them could not be signed. drawing_pages is what arrived. */
  drawing_pages_expected: number; drawing_pages_failed: number;
  review: { state: ReviewState; updated_at: string } | null;
};
export type InquiriesList = { ok: true; approval_status: string | null; inquiries: InquiryListItem[] };
export type InquiryDetail = {
  ok: true;
  inquiry: {
    id: string; job_no: string; category: string | null; emirate: string | null; created_at: string; status: string;
    concluded: boolean; revealed: boolean; you_won: boolean; summary: string | null; summary_ar?: string | null; budget: string | null; scope_type: string | null;
    spec: unknown; requested: { en?: { key: string; label: string; value: string }[]; ar?: { key: string; label: string; value: string }[] } | null;
    boq: { boq?: unknown[] } | null; boq_withheld: boolean; boq_confidence: string | null; drawing_pages: string[];
    /** expected = on the inquiry, served = signed and in drawing_pages, failed = missing from this view. */
    drawing_pages_expected: number; drawing_pages_served: number; drawing_pages_failed: number;
    /** The customer attached a file that cannot be shown without identifying them (held drawing, any CAD file). */
    drawing_withheld?: boolean;
    quotes: { id: string; option_no?: number; status: string; quote_amount: number | null; spec_hold?: unknown }[];
    review: { state: ReviewState; updated_at: string } | null;
  };
};
export type InquiryDocument =
  | { kind: 'drawing_page'; name: string; url: string; expires_in: number }
  | { kind: 'boq_csv'; name: string; mime: 'text/csv'; content: string; lines: number };
export type InquiryDocuments = { ok: true; job_no: string; boq_withheld: boolean; documents: InquiryDocument[];
  drawing_pages_expected: number; drawing_pages_failed: number };

export type MessageView = {
  id: string; role: 'supplier' | 'sales_engineer'; kind: 'text' | 'file' | 'review' | 'choice_prompt' | 'choice' | 'submitted' | 'notice';
  body_en: string | null; body_ar: string | null; text: string | null;
  attachments: { kind: 'quotation_file' | 'standard_quote'; name: string; url: string | null; quote_id: string | null; /** standard_quote: which language this print is. */ lang?: Lang | null }[];
  issues: Issue[] | null; created_at: string;
};
export type RequestView = { id: number; key: string; code: string; kind: 'adjustment' | 'clarification' | 'choice'; line_no: number | null; boq_line: number | null; label_en: string; label_ar: string; opened_at: string };
export type ThreadView = {
  ok: true; inquiry_id: string; job_no: string; state: ReviewState; choice: 'generate' | 'reupload' | null;
  can_write: boolean; can_upload: boolean; can_choose: boolean; can_submit: boolean; reviewing: boolean;
  file: { name: string } | null; total_ex_vat: number | null; submitted_quote_ids: string[];
  messages: MessageView[]; open_requests: RequestView[]; updated_at: string | null;
  notice?: { code: string; message: string } | null;
};
export type Failure = { ok?: false; error: string; code?: string; message?: string; _http?: number };
export type Result<T> = T | Failure;
export const failed = <T extends { ok: true }>(r: Result<T> | null | undefined): r is Failure | null | undefined => !r || (r as { ok?: boolean }).ok !== true;

// No `.catch` here: since 22 Sep 2026 ./api.ts's `call` RESOLVES every failure as
// `{ ok: false, code: 'network' | 'timeout' | 'bad_response' | 'load_failed' }` and never rejects,
// so a catch on it is unreachable. `failed()` above is the test; do not add one back.
const post = <T>(body: Record<string, unknown>, token: string): Promise<Result<T>> =>
  call('supplier_api', body, token);

export const qr = {
  inquiries: (token: string) => post<InquiriesList>({ action: 'inquiries_list' }, token),
  inquiry: (token: string, id: string) => post<InquiryDetail>({ action: 'inquiry_detail', inquiry_id: id }, token),
  documents: (token: string, id: string) => post<InquiryDocuments>({ action: 'inquiry_documents', inquiry_id: id }, token),
  thread: (token: string, id: string, lang: Lang) => post<ThreadView>({ action: 'review_thread', inquiry_id: id, lang }, token),
  start: (token: string, id: string, lang: Lang) => post<ThreadView>({ action: 'review_start', inquiry_id: id, lang }, token),
  message: (token: string, id: string, text: string, lang: Lang) => post<ThreadView>({ action: 'review_message', inquiry_id: id, text, lang }, token),
  upload: (token: string, id: string, file: { b64: string; filename: string; mime: string }, lang: Lang, text?: string) =>
    post<ThreadView>({ action: 'review_upload', inquiry_id: id, file, text, lang }, token),
  choose: (token: string, id: string, choice: 'generate' | 'reupload', lang: Lang) => post<ThreadView>({ action: 'review_choose', inquiry_id: id, choice, lang }, token),
  submit: (token: string, id: string, lang: Lang) => post<ThreadView>({ action: 'review_submit', inquiry_id: id, lang }, token),
  quotePdf: (token: string, quoteId: string, lang: Lang) => call('supplier_api', { action: 'quote_pdf', quote_id: quoteId, lang }, token),
  /** The inquiry as the sales engineer's document (PDF, one language per file), cached server-side. */
  inquiryPdf: (token: string, inquiryId: string, lang: Lang) => call('supplier_api', { action: 'inquiry_pdf', inquiry_id: inquiryId, lang }, token),
};
export type PdfResult = { ok: true; url: string; ref: string; lang: Lang; cached?: boolean } | Failure;
/** Open a document the server signed. Only https URLs are opened; anything else is treated as a failure. */
// 'held': the Arabic version is still being written (supplier_api answers 202 code arabic_held). That is
// not a failure, and "could not be prepared, try again" told the supplier the opposite (e2e, 23 Sep 2026).
export async function openPdf(fetchIt: () => Promise<unknown>): Promise<boolean | 'held'> {
  const j = (await fetchIt().catch(() => null)) as PdfResult | null;
  const u = j && (j as { url?: unknown }).url; const url = typeof u === 'string' && /^https:\/\//i.test(u) ? u : null;
  if (!url) return (j as { code?: unknown } | null)?.code === 'arabic_held' ? 'held' : false;
  window.open(url, '_blank', 'noopener');
  return true;
}

/** A File as the base64 the upload action takes — the same body a native app sends. */
export function fileToBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result || '').replace(/^data:[^;]*;base64,/, ''));
    r.onerror = () => reject(r.error);
    r.readAsDataURL(file);
  });
}
/** Save a document the server returned inline (the BOQ CSV). A native app writes the same content to a file. */
export function saveInline(name: string, content: string, mime: string) {
  const url = URL.createObjectURL(new Blob([content], { type: mime + ';charset=utf-8' }));
  const a = document.createElement('a'); a.href = url; a.download = name; document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
// `aedIn(lang, n)` lived here until 22 Sep 2026 (audit SP-I-10). It was the second of three money
// formatters on the same supplier's screen; ./money.ts `aed(lang, n, decimals)` is now the only one,
// and its two importers here (InquiriesTab, QuotationsTab) call that instead.
export const REVIEW_STATE: Record<ReviewState, { en: string; ar: string; tone: 'ok' | 'warn' | 'secondary' | 'outline' }> = {
  none: { en: 'Not started', ar: 'لم يبدأ', tone: 'outline' },
  open: { en: 'Waiting for your file', ar: 'بانتظار ملفكم', tone: 'outline' },
  reviewing: { en: 'Being reviewed', ar: 'قيد المراجعة', tone: 'secondary' },
  changes_requested: { en: 'Changes requested', ar: 'تعديلات مطلوبة', tone: 'warn' },
  awaiting_choice: { en: 'Approved — your choice', ar: 'معتمد — بانتظار اختياركم', tone: 'ok' },
  awaiting_upload: { en: 'Waiting for your new version', ar: 'بانتظار نسختكم الجديدة', tone: 'warn' },
  ready_to_submit: { en: 'Approved — ready to submit', ar: 'معتمد — جاهز للتقديم', tone: 'ok' },
  submitted: { en: 'Submitted', ar: 'تم التقديم', tone: 'ok' },
  closed: { en: 'Closed', ar: 'مغلق', tone: 'secondary' },
};
