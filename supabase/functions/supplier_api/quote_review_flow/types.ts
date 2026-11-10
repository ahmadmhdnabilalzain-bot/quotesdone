import { type AttachmentRead } from '../../_shared/read_every_attachment.ts';
import { type Proposal } from '../../quote_extract/quote_from_document.ts';
import { SEAT, type Issue, type Lang, type Review, type SafeInquiry, type Working } from '../quote_review.ts';

export type ReviewState = 'open' | 'reviewing' | 'changes_requested' | 'awaiting_choice' | 'awaiting_upload' | 'ready_to_submit' | 'submitted' | 'closed';
export type Choice = 'generate' | 'reupload';
export type ReviewRow = {
  id: string; inquiry_id: string; supplier_id: number; owner_email: string | null; status: ReviewState; choice: Choice | null;
  original_file_path: string | null; original_file_name: string | null; extracted: unknown; working: Working | null; last_review: Review | null;
  reviewing_since: string | null; total_amount: number | null; currency: string | null; submitted_quote_ids: string[] | null;
  completed_at: string | null; created_at: string; updated_at: string;
};
export type Attachment = { kind: 'quotation_file' | 'standard_quote' | 'chat_file'; name: string; bucket?: string | null; path?: string | null; quote_id?: string | null; /** standard_quote: which language this print is. */ lang?: Lang };
export type MsgKind = 'text' | 'file' | 'review' | 'choice_prompt' | 'choice' | 'submitted' | 'notice';
export type MessageRow = {
  id: string; review_id: string; role: 'supplier' | typeof SEAT; kind: MsgKind; body: string | null; body_ar: string | null;
  attachments: Attachment[]; issues: Issue[] | null; created_at: string;
};
export type RequestRow = {
  id: number; review_id: string; key: string; code: string; kind: 'adjustment' | 'clarification' | 'choice';
  line_no: number | null; boq_line: number | null; attr: string | null; label_en: string; label_ar: string;
  state: 'open' | 'answered' | 'superseded'; asked_message_id: string | null; answered_message_id: string | null; opened_at: string; answered_at: string | null;
};
export type NewRequest = Pick<RequestRow, 'review_id' | 'key' | 'code' | 'kind' | 'line_no' | 'boq_line' | 'attr' | 'label_en' | 'label_ar' | 'asked_message_id'>;

export interface ReviewRepo {
  review(inquiryId: string, supplierId: number): Promise<ReviewRow | null>;
  /** Every review this supplier has, for the list views: which job, what state. */
  reviewsOf(supplierId: number): Promise<{ inquiry_id: string; status: ReviewState; updated_at: string }[]>;
  createReview(r: { inquiry_id: string; supplier_id: number; owner_email: string }): Promise<ReviewRow>;
  updateReview(id: string, patch: Partial<ReviewRow>): Promise<void>;
  /** Move the review to `to` only if it is in one of `from` — the guard against a double submission. */
  claim(id: string, from: ReviewState[], to: ReviewState): Promise<boolean>;
  addMessage(m: Omit<MessageRow, 'id' | 'created_at'>): Promise<MessageRow>;
  messages(reviewId: string): Promise<MessageRow[]>;
  requests(reviewId: string, onlyOpen?: boolean): Promise<RequestRow[]>;
  addRequests(rows: NewRequest[]): Promise<void>;
  closeRequests(ids: number[], state: 'answered' | 'superseded', messageId: string | null): Promise<void>;
  storeFile(path: string, bytes: Uint8Array, mime: string): Promise<boolean>;
  signFile(bucket: string, path: string): Promise<string | null>;
  log(counts: Record<string, unknown>, note: string): Promise<void>;
  /** Which reader wrote this supplier's quotation for this inquiry (quote_extraction_model); quote_compare names it. */
  recordReader?(inquiryId: string, supplierId: number, model: string): Promise<void>;
}
export type Scanned = { ok: true; bytes: Uint8Array; mime: string; name: string } | { ok: false; status: number; code: string; message: string };
export type FileRead = { proposal: Proposal | null; text: string; kind: string };
// deno-lint-ignore no-explicit-any
export type Json = any;
export interface ReviewDeps {
  /** The inquiry exactly as this supplier's inbox serves it (scrubbed), or null when not matched to them. */
  inquiry(inquiryId: string): Promise<SafeInquiry | null>;
  /** The upload gate: type by bytes, size, malware lookup. */
  scan(b64: string, filename: string, mime: string): Promise<Scanned>;
  read(bytes: Uint8Array, filename: string, mime: string): Promise<FileRead>;
  /** supplier_api submit_quote, as the calling supplier. */
  submit(payload: Record<string, unknown>): Promise<{ status: number; json: Json }>;
  /** supplier_api quote_pdf: the standardised quotation the customer receives, for this supplier's own quote. */
  quotePdf(quoteId: string, lang: Lang): Promise<{ url: string | null; ref: string | null }>;
  now(): Date;
  /** What reasoning reads from the working quotation (quote_review.ts readWorking), before the review; absent or held: nothing is read. */
  readWorking?(inq: SafeInquiry, w: Working): Promise<Working>;
  /** THE WORDS (1195-1197): the model writes the engineer's message from `situation` (what code decided); with
   *  `actions`, it also picks the supplier's next step from their message. text '' = no usable model answer; outage =
   *  no call reached a model (OpenRouter down, _shared/openrouter_down.ts) — only then does the fixed notice go out (1339). */
  voice(v: { kind: MsgKind; situation: string; supplierMessage: string | null; actions?: { id: string; meaning: string }[]; images?: string[]; conversation?: { role: 'supplier' | 'seat'; text: string }[] }): Promise<{ text: string; action: string | null; outage?: boolean; problems?: string[] }>;
  /** RULING 1177: a photo or document the supplier attaches to a chat message is READ - code first, then the vision
   *  model (_shared/read_every_attachment.ts). Absent: code only. */
  readAttachment?(bytes: Uint8Array, filename: string, mime: string): Promise<AttachmentRead>;
  /** Keep a job running after the response is sent (EdgeRuntime.waitUntil). Absent: the job runs inline (tests). */
  background?(job: Promise<void>): void;
  /** No model answer: the turn is filed in sales_engineer's reasoning queue (fn_reason_hold, surface
   *  supplier_api.quote_review_unwritten); the re-ask (_shared/reask.ts) asks the model again within about a minute with
   *  `problems` named, posts its answer into this thread, and hands the turn to the seat after its last refused attempt.
   *  The HELD NOTICE is added by the flow itself, on an outage only. */
  hold(v: { reviewId: string; situation: string; supplierMessage: string | null; why: string; outage?: boolean; problems?: string[] }): Promise<void>;
}
export type Ctx = { supplierId: number; email: string; lang: Lang; companyName?: string | null };

// ---------------------------------------------------------------------------------------------
// The typed response every action returns (docs/api/supplier_portal_quotations.md).
// ---------------------------------------------------------------------------------------------
export type MessageView = {
  id: string; role: 'supplier' | 'sales_engineer'; kind: MsgKind;
  /** The engineer's words in both languages; null on a supplier's message. */
  body_en: string | null; body_ar: string | null;
  /** The supplier's own words, as they typed them; null on the engineer's message. */
  text: string | null;
  attachments: { kind: Attachment['kind']; name: string; url: string | null; quote_id: string | null; lang: Lang | null }[];
  issues: Issue[] | null; created_at: string;
};
export type RequestView = { id: number; key: string; code: string; kind: RequestRow['kind']; line_no: number | null; boq_line: number | null; label_en: string; label_ar: string; opened_at: string };
export type ThreadView = {
  ok: true; inquiry_id: string; job_no: string; state: ReviewState | 'none'; choice: Choice | null;
  can_write: boolean; can_upload: boolean; can_choose: boolean; can_submit: boolean; reviewing: boolean;
  file: { name: string } | null; total_ex_vat: number | null; submitted_quote_ids: string[];
  messages: MessageView[]; open_requests: RequestView[]; updated_at: string | null;
  /** Set when the action itself could not complete (e.g. registration due); the thread is still returned. */
  notice?: { code: string; message: string } | null;
};
export type Fail = { ok: false; status: number; code: string; message: string };
const fail = (status: number, code: string, message: string): Fail => ({ ok: false, status, code, message });

// Names the sibling modules of this folder import (the declarations above are unchanged).
export { fail };
