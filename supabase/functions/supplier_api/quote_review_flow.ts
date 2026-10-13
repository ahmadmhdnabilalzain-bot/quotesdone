// supplier_api/quote_review_flow.ts — THE QUOTATION CONVERSATION: one supplier, one job, one thread
// with the sales engineer, from the first file to the submitted quote. Assigned: sales_engineer.
//
// The founder, 15 Sep 2026: the supplier attaches their quotation; the sales engineer reviews it
// immediately; if it is fine they reply "Quotation approved for submission", if not they list the
// adjustments and clarifications line by line; the supplier can answer in free text or attach a
// revised file; finally the engineer asks whether they will upload a new version or have it generated
// for them; they reply, and once done the quotation is submitted to the inquiry and the conversation
// ends, kept on record. And: "later this will be a mobile app as well" — so every state, every rule and
// every word lives HERE, on the server, behind actions a native app calls exactly as the portal does.
//
//   open ──upload──▶ reviewing ──▶ changes_requested ◀──text / upload──┐
//                                  │ (every point answered)            │
//                                  ▼                                   │
//                            awaiting_choice ──"generate"──▶ the quotation is PRINTED in the thread ─┐
//                                  │                                                                 ▼
//                                  └──"upload"──▶ awaiting_upload ──upload──▶ ready_to_submit ──submit──▶ submitted
//   the customer chooses before we submit ──▶ closed (read-only)
//
// 22 Sep 2026 (finding SP-F-07): "generate" used to go straight to submit. It now ends in
// ready_to_submit like the other road, so the supplier reads the standardised quotation BEFORE the
// customer does and Submit is the approval — the same shape as the spec-hold's approve step.
//
// WHERE THINGS LIVE. The conversation is public.quote_review_messages, the estate's registered
// conversation store (kept, never purged, archived to PDF and Dropbox — scripts/sql/every_conversation_
// is_kept_backed_up_twice_and_readable_by_the_sales_engineer.sql). One review per (inquiry, supplier) is
// public.quote_reviews. Every point the engineer raises is a row of public.quote_review_request, open
// until the supplier answers it or a new review no longer finds it (founder: "nothing is one-way").
//
// SUBMISSION IS submit_quote. The engineer never writes a quote row itself: the approved quotation is
// handed to supplier_api's own submit_quote (the caller's session, in-process), so the hold gate, the
// accept rule, options, VAT, the customer's notice, the comparison and the reveal all run unchanged.
//
// Written against a repository interface, like line_specs/workflow.ts, so the whole conversation runs
// in memory in the test — no database, no network, and no way to reach a real supplier.
import { readEveryAttachment, untrustedBlock, type AttachmentRead, type Vision } from '../_shared/read_every_attachment.ts';
import { clearerCopyAsk } from '../_shared/clearer_copy.ts';
import { readDocument } from '../_shared/doc_read/index.ts';
import { quoteFromExtracted, quoteText, type Proposal } from '../quote_extract/quote_from_document.ts';
import type { QuoteTermKey } from '../_shared/reasoned_suppliers.ts';
import type { MissingItem } from '../_shared/line_specs/assess.ts';
import {
  answerSaid, applyCorrections, awaitingUploadSaid, carryOver, choiceSaid, closedSaid, fromMissing, generatedSaid, greeting, issueKey, notUnderstoodSaid,
  parseQty, readReply, readyToSubmitSaid, reviewQuotation, reviewSaid, SEAT, submittedSaid, tookSaid, typedUnreadableSaid, unreadableSaid, workingFromProposal,
  type Issue, type Lang, type Review, type SafeInquiry, type Said, type Working,
} from './quote_review.ts';

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
   *  `actions`, it also picks the supplier's next step from their message. text '' = no model answered. */
  voice(v: { kind: MsgKind; situation: string; supplierMessage: string | null; actions?: { id: string; meaning: string }[]; images?: string[] }): Promise<{ text: string; action: string | null }>;
  /** RULING 1177: a photo or document the supplier attaches to a chat message is READ - code first, then the vision
   *  model (_shared/read_every_attachment.ts). Absent: code only. */
  readAttachment?(bytes: Uint8Array, filename: string, mime: string): Promise<AttachmentRead>;
  /** No model answer: the turn is filed in sales_engineer's reasoning queue (fn_reason_hold, surface
   *  supplier_api.quote_review_unwritten); the replayed answer is posted into this thread and a turn still unanswered
   *  after 15 minutes is escalated to the seat. The HELD NOTICE is added by the flow itself. */
  hold(v: { reviewId: string; situation: string; supplierMessage: string | null; why: string }): Promise<void>;
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

/** A review stuck in 'reviewing' this long crashed mid-way; it is treated as not reviewing. */
const STALE_MS = 120_000;
const WRITABLE: ReviewState[] = ['open', 'changes_requested', 'awaiting_choice', 'awaiting_upload', 'ready_to_submit'];

// ---------------------------------------------------------------------------------------------
// Reading a quotation file — doc_read and quote_from_document read the PRICES with no model (the same pair
// quote_extract uses on its deterministic path). The TERMS (validity, lead time, payment, warranty,
// exclusions, installation) are what the file means, so they are REASONED by `readTerms` (quote_review_actions
// passes _shared/reasoned_suppliers.ts quoteTerms; founder_instruction 886-903). Held or absent: the
// terms stay empty and the review asks the supplier for them — never a label guess.
// ---------------------------------------------------------------------------------------------
/**
 * THE VISION MODEL WRITES MARKDOWN (13 Oct 2026, measured live). read_every_attachment's prompt asks for tables "as
 * markdown tables", so a photographed quotation comes back as "| Jotun ... | 450 | m2 | 20.00 | 9,000.00 |". The price
 * reader parses CSV and plain lines, and it read that transcription as NO quotation. Each table row becomes a CSV row
 * (numbers lose their thousands separators), separator rows and **emphasis** / # headings go; every other line stays.
 * prevented by: supplier_api/quote_review.test.ts ('a photographed quotation transcribed as a markdown table is priced')
 */
// ONLY TABLE ROWS ARE TOUCHED (review of #1396): a line outside a pipe table passes through byte for byte. Inside a
// cell, a comma goes only when it is a THOUSANDS separator (9,000.00 -> 9000.00; "1,5" and "12,50" are decimal commas
// and stay as written, CSV-quoted); Arabic-Indic digits and the Arabic separators (U+066C thousands, U+066B decimal)
// are read the same way; an escaped \| stays inside its cell; a short or merged row keeps the cells it has.
const ESC_PIPE = '\u0000';
const AR_DIGIT = /[٠-٩۰-۹]/g;
const THOUSANDS = /(^|[^\d,.])(-?\d{1,3}(?:,\d{3})+)(?=\.\d+(?![\d,])|(?![\d,.]))/g;
function tableCell(raw: string): string {
  let c = raw.replace(new RegExp(ESC_PIPE, 'g'), '|').trim().replace(/^(\*\*|__)(.*)\1$/, '$2').trim();
  c = c.replace(AR_DIGIT, (d) => String((d.charCodeAt(0) & 0xf) % 10)).replace(/٬/g, ',').replace(/٫/g, '.');
  c = c.replace(THOUSANDS, (_m, pre: string, n: string) => pre + n.replace(/,/g, ''));
  return /[",]/.test(c) ? '"' + c.replace(/"/g, '""') + '"' : c;
}
export function transcriptAsText(md: string): string {
  const isRow = (l: string) => /^\s*\|.*\|\s*$/.test(l);
  const isSep = (l: string) => /^\s*\|[\s:|-]*-{2,}[\s:|-]*\|\s*$/.test(l);
  return String(md ?? '').split(/\r?\n/).flatMap((l) => {
    if (!isRow(l)) return [l];
    if (isSep(l)) return [];
    const cells = l.replace(/\\\|/g, ESC_PIPE).trim().replace(/^\|/, '').replace(/\|$/, '').split('|');
    return [cells.map(tableCell).join(',')];
  }).join('\n');
}

export async function readQuotationFile(bytes: Uint8Array, filename: string, mime: string, supplierTerms: string[] = [],
  readTerms?: (text: string) => Promise<Partial<Record<QuoteTermKey, string>> | null>, vision?: Vision | null): Promise<FileRead> {
  const rd = await readDocument(bytes, filename, mime);
  if (!rd.ok && rd.error !== 'unreadable_document') return { proposal: null, text: '', kind: 'refused' };
  // RULING 1177 (12 Oct 2026): a photo or a scan of a quotation is READ — the vision model transcribes it (one more
  // asking, the gateway's second model) and the transcription goes through the SAME parser as typed lines. Before,
  // a scan got 'image' and a request for a text PDF. Unreadable only when both askings fail.
  if (vision && (!rd.ok || (!rd.text.trim() && !rd.tables.length && !rd.children.length))) {
    const a = await readEveryAttachment(bytes, filename, mime, vision);
    if (a.status === 'read' && a.by === 'model') return readQuotationFile(new TextEncoder().encode(transcriptAsText(a.text)), 'quotation.txt', 'text/plain', supplierTerms, readTerms, null);
    return { proposal: null, text: '', kind: rd.ok ? rd.kind : 'image' };
  }
  if (!rd.ok) return { proposal: null, text: '', kind: 'refused' };
  const texts: string[] = [];
  // deno-lint-ignore no-explicit-any
  const visit = (e: any) => { if (e.text) texts.push(e.text); for (const t of e.tables || []) texts.push(t.map((r: unknown[]) => (r || []).join(' ')).join('\n')); for (const c of e.children || []) visit(c.doc); };
  visit(rd);
  const priced = quoteFromExtracted(rd, supplierTerms);
  const empty = priced.amount == null && !priced.line_items.some((l) => l.amount != null);
  // No model is asked about a file with no price.
  const terms = !empty && readTerms ? await readTerms(quoteText(rd)).catch(() => null) : null;
  const p = terms ? quoteFromExtracted(rd, supplierTerms, terms) : priced;
  return { proposal: empty ? null : p, text: texts.join('\n'), kind: rd.kind };
}

// ---------------------------------------------------------------------------------------------
// The view.
// ---------------------------------------------------------------------------------------------
function effectiveState(r: ReviewRow, now: Date): ReviewState {
  if (r.status === 'reviewing' && r.reviewing_since && now.getTime() - new Date(r.reviewing_since).getTime() > STALE_MS) return r.working ? 'changes_requested' : 'open';
  return r.status;
}
async function view(repo: ReviewRepo, deps: ReviewDeps, inq: SafeInquiry, r: ReviewRow | null, notice: ThreadView['notice'] = null): Promise<ThreadView> {
  const base = { ok: true as const, inquiry_id: inq.id, job_no: inq.job_no, notice };
  const closedInq = inq.concluded || inq.revealed;
  if (!r) return { ...base, state: 'none', choice: null, can_write: !closedInq, can_upload: !closedInq, can_choose: false, can_submit: false, reviewing: false, file: null, total_ex_vat: null, submitted_quote_ids: [], messages: [], open_requests: [], updated_at: null };
  const st = effectiveState(r, deps.now());
  const [msgs, open] = await Promise.all([repo.messages(r.id), repo.requests(r.id, true)]);
  const messages: MessageView[] = [];
  for (const m of msgs) {
    const atts: MessageView['attachments'] = [];
    for (const a of m.attachments || []) atts.push({ kind: a.kind, name: a.name, quote_id: a.quote_id ?? null, lang: a.lang ?? null, url: a.bucket && a.path ? await repo.signFile(a.bucket, a.path) : null });
    const eng = m.role === SEAT;
    messages.push({ id: m.id, role: eng ? 'sales_engineer' : 'supplier', kind: m.kind, body_en: eng ? m.body : null, body_ar: eng ? m.body_ar : null, text: eng ? null : m.body, attachments: atts, issues: m.issues, created_at: m.created_at });
  }
  const writable = WRITABLE.includes(st) && !closedInq;
  return {
    ...base, state: st, choice: r.choice, can_write: writable, can_upload: writable, can_choose: writable && st === 'awaiting_choice',
    can_submit: writable && st === 'ready_to_submit', reviewing: st === 'reviewing',
    file: r.original_file_name ? { name: r.original_file_name } : null, total_ex_vat: r.last_review?.price_ex_vat ?? null,
    submitted_quote_ids: r.submitted_quote_ids || [], messages,
    open_requests: open.map((q) => ({ id: q.id, key: q.key, code: q.code, kind: q.kind, line_no: q.line_no, boq_line: q.boq_line, label_en: q.label_en, label_ar: q.label_ar, opened_at: q.opened_at })),
    updated_at: r.updated_at,
  };
}

// THE ENGINEER'S WORDS ARE THE MODEL'S (rulings 1195/1196/1197, 12 Oct 2026). Code runs the state machine and
// decides what happened (the review's points, the state, what the supplier can do next); those decisions — the Said
// below — are handed to the model as FACTS, and the model writes the message in this turn (deps.voice →
// _shared/ai_reply.ts; suppliers always in English). Two kinds stay templated because they are NOTIFICATIONS, not
// conversation: the submission receipt ('submitted') and the closed-thread status notice (closedSaid).
// No model answer → no engineer message is added (never a canned one); the turn is logged.
// prevented by: supplier_api/quote_review.test.ts (the 1195-1197 test)
const NOTIFICATION_KINDS: MsgKind[] = ['submitted'];
/** NOBODY IS LEFT SILENT (review of #1335): no model answer → the HELD NOTICE (a fixed receipt — a notification under
 *  ruling 1197, never an answer) is added, and the turn is queued for the model; escalated to the seat after 15 minutes. */
export const QR_HELD_NOTICE = 'Thank you, we have received your message. The sales engineer will reply here shortly.';
async function held(repo: ReviewRepo, deps: ReviewDeps, reviewId: string, situation: string, supplierMessage: string | null, issues?: Issue[]): Promise<MessageRow> {
  const r = await repo.addMessage({ review_id: reviewId, role: SEAT, kind: 'notice', body: QR_HELD_NOTICE, body_ar: null, attachments: [], issues: issues ?? null });
  await deps.hold({ reviewId, situation, supplierMessage, why: 'no_model_answer' }).catch(() => {});
  await repo.log({ signal: 'quote_review_held_notice' }, 'No model answered: the held notice was added and the turn queued for the model (rulings 1195-1197).');
  return r;
}
async function say(repo: ReviewRepo, deps: ReviewDeps, reviewId: string, kind: MsgKind, s: Said,
                   extra: { issues?: Issue[]; attachments?: Attachment[]; notification?: boolean; supplierMessage?: string | null } = {}): Promise<MessageRow> {
  const add = (body: string, body_ar: string | null) =>
    repo.addMessage({ review_id: reviewId, role: SEAT, kind, body, body_ar, attachments: extra.attachments ?? [], issues: extra.issues ?? null });
  if (extra.notification || NOTIFICATION_KINDS.includes(kind)) return add(s.en, s.ar);
  const v = await deps.voice({ kind, situation: s.en, supplierMessage: extra.supplierMessage ?? null }).catch(() => ({ text: '', action: null }));
  if (!v.text) return held(repo, deps, reviewId, s.en, extra.supplierMessage ?? null, extra.issues);
  return add(v.text, null);
}
const supplierSays = (repo: ReviewRepo, reviewId: string, kind: MsgKind, text: string | null, attachments: Attachment[] = []) =>
  repo.addMessage({ review_id: reviewId, role: 'supplier', kind, body: text, body_ar: null, attachments, issues: null });

type Loaded = { inq: SafeInquiry; r: ReviewRow | null };
async function load(repo: ReviewRepo, deps: ReviewDeps, ctx: Ctx, inquiryId: string): Promise<Loaded | Fail> {
  if (!/^[0-9a-f-]{36}$/i.test(String(inquiryId || ''))) return fail(404, 'not_found', 'Inquiry not found.');
  const inq = await deps.inquiry(inquiryId);
  if (!inq) return fail(404, 'not_found', 'Inquiry not found.');
  let r = await repo.review(inquiryId, ctx.supplierId);
  // The customer chose before this quotation was submitted: the thread closes, and says why, once.
  if (r && (inq.concluded || inq.revealed) && !['submitted', 'closed'].includes(r.status)) {
    await say(repo, deps, r.id, 'notice', closedSaid(), { notification: true });
    await repo.updateReview(r.id, { status: 'closed', reviewing_since: null });
    r = await repo.review(inquiryId, ctx.supplierId);
  }
  // The address the supplier's own-row policy reads follows whoever owns the company now.
  if (r && r.owner_email !== ctx.email) { await repo.updateReview(r.id, { owner_email: ctx.email }); r = { ...r, owner_email: ctx.email }; }
  return { inq, r };
}
const isFail = (x: unknown): x is Fail => !!x && (x as Fail).ok === false;
async function ensure(repo: ReviewRepo, deps: ReviewDeps, ctx: Ctx, l: Loaded): Promise<ReviewRow> {
  if (l.r) return l.r;
  const r = await repo.createReview({ inquiry_id: l.inq.id, supplier_id: ctx.supplierId, owner_email: ctx.email });
  await say(repo, deps, r.id, 'notice', greeting(l.inq.job_no));
  return r;
}
function writableOr(l: Loaded, r: ReviewRow | null, now: Date): Fail | null {
  if (l.inq.concluded || l.inq.revealed) return fail(409, 'inquiry_closed', 'This job is closed; the customer has already chosen.');
  if (!r) return null;
  const st = effectiveState(r, now);
  if (st === 'reviewing') return fail(409, 'reviewing', 'Your quotation is being reviewed; please wait for the result.');
  if (st === 'submitted' || st === 'closed') return fail(409, 'review_closed', 'This conversation is closed.');
  return null;
}

// ---------------------------------------------------------------------------------------------
// The review, and the requests it opens and closes.
// ---------------------------------------------------------------------------------------------
async function runReview(repo: ReviewRepo, deps: ReviewDeps, inq: SafeInquiry, r: ReviewRow, w: Working, trigger: string | null) {
  if (deps.readWorking) w = await deps.readWorking(inq, w);
  const rv = reviewQuotation(inq, w);
  const open = await repo.requests(r.id, true);
  const openIssues = open.filter((x) => x.kind !== 'choice');
  const keys = new Set(rv.issues.map(issueKey));
  const answered = openIssues.filter((x) => !keys.has(x.key)).map((x) => x.id);
  if (answered.length) await repo.closeRequests(answered, 'answered', trigger);
  const msg = await say(repo, deps, r.id, 'review', reviewSaid(inq.job_no, rv), { issues: rv.issues });
  const have = new Set(openIssues.map((x) => x.key));
  const fresh = rv.issues.filter((i) => !have.has(issueKey(i)));
  if (fresh.length) await repo.addRequests(fresh.map((i) => ({ review_id: r.id, key: issueKey(i), code: i.code, kind: i.kind, line_no: i.line_no, boq_line: i.boq_line, attr: i.attr, label_en: i.en, label_ar: i.ar, asked_message_id: msg.id || null })));
  let status: ReviewState; let choice: Choice | null = r.choice;
  if (!rv.approved) status = 'changes_requested';
  else if (r.choice === 'reupload') { status = 'ready_to_submit'; await say(repo, deps, r.id, 'notice', readyToSubmitSaid(inq.job_no)); }
  else {
    status = 'awaiting_choice'; choice = null;
    const cm = await say(repo, deps, r.id, 'choice_prompt', choiceSaid());
    if (!open.some((x) => x.kind === 'choice')) {
      const c = choiceSaid();
      await repo.addRequests([{ review_id: r.id, key: 'choice', code: 'choice', kind: 'choice', line_no: null, boq_line: null, attr: null, label_en: c.en, label_ar: c.ar, asked_message_id: cm.id || null }]);
    }
  }
  await repo.updateReview(r.id, { status, choice, working: w, last_review: rv, reviewing_since: null, total_amount: rv.price_ex_vat ?? w.amount, currency: 'AED' });
  await repo.log({ signal: 'quote_review', inquiry_id: inq.id, approved: rv.approved ? 1 : 0, issues: rv.issues.length, answered: answered.length },
    `Reviewed the quotation for job ${inq.job_no}: ${rv.approved ? 'approved for submission' : `${rv.issues.length} point(s) raised — ${rv.issues.map((i) => i.code).join(', ')}`}.`);
  return rv;
}
const openIssuesOf = async (repo: ReviewRepo, r: ReviewRow): Promise<Issue[]> => {
  const keys = new Set((await repo.requests(r.id, true)).filter((x) => x.kind !== 'choice').map((x) => x.key));
  return (r.last_review?.issues || []).filter((i) => keys.has(issueKey(i)));
};

// ---------------------------------------------------------------------------------------------
// The actions.
// ---------------------------------------------------------------------------------------------
export async function thread(repo: ReviewRepo, deps: ReviewDeps, ctx: Ctx, inquiryId: string): Promise<ThreadView | Fail> {
  const l = await load(repo, deps, ctx, inquiryId); if (isFail(l)) return l;
  return view(repo, deps, l.inq, l.r);
}

export async function start(repo: ReviewRepo, deps: ReviewDeps, ctx: Ctx, inquiryId: string): Promise<ThreadView | Fail> {
  const l = await load(repo, deps, ctx, inquiryId); if (isFail(l)) return l;
  if (!l.r && (l.inq.concluded || l.inq.revealed)) return fail(409, 'inquiry_closed', 'This job is closed; the customer has already chosen.');
  const r = await ensure(repo, deps, ctx, l);
  return view(repo, deps, l.inq, await repo.review(inquiryId, ctx.supplierId) ?? r);
}

export async function upload(repo: ReviewRepo, deps: ReviewDeps, ctx: Ctx, inquiryId: string, file: { b64?: unknown; filename?: unknown; mime?: unknown }, text?: unknown): Promise<ThreadView | Fail> {
  const l = await load(repo, deps, ctx, inquiryId); if (isFail(l)) return l;
  const bad = writableOr(l, l.r, deps.now()); if (bad) return bad;
  if (!file || typeof file.b64 !== 'string' || !file.b64) return fail(400, 'file_required', 'Attach the quotation file.');
  // The scan reads attacker-supplied bytes and calls out to the malware lookup, so it is treated the
  // same way as the parser below: a throw becomes a refusal in this flow's own shape, never a bare 500.
  let sc: Scanned;
  try { sc = await deps.scan(file.b64, String(file.filename || 'quotation'), String(file.mime || '')); }
  catch (_e) { return fail(400, 'file_unreadable', 'We could not read that file. Please attach it again, or send it as a PDF.'); }
  if (!sc.ok) return fail(sc.status, sc.code, sc.message);
  const r0 = await ensure(repo, deps, ctx, l);
  const path = `review/${ctx.supplierId}/${inquiryId}/${deps.now().getTime()}_${sc.name}`;
  if (!(await repo.storeFile(path, sc.bytes, sc.mime))) return fail(502, 'upload_failed', 'We could not store your file. Please try again.');
  const note = typeof text === 'string' && text.trim() ? text.trim().slice(0, 2000) : null;
  const fm = await supplierSays(repo, r0.id, 'file', note, [{ kind: 'quotation_file', name: sc.name, bucket: 'quote-files', path }]);
  const prior = effectiveState(r0, deps.now());
  await repo.updateReview(r0.id, { status: 'reviewing', reviewing_since: deps.now().toISOString(), original_file_path: path, original_file_name: sc.name });
  // A failed write below must not leave the thread "reviewing": it goes back to where it was.
  try {
  let read: FileRead;
  try { read = await deps.read(sc.bytes, sc.name, sc.mime); } catch (_e) { read = { proposal: null, text: '', kind: 'error' }; }
  const r = (await repo.review(inquiryId, ctx.supplierId))!;
  if (!read.proposal) {
    await say(repo, deps, r.id, 'notice', unreadableSaid(read.kind));
    await repo.updateReview(r.id, { status: prior, reviewing_since: null });
    return view(repo, deps, l.inq, await repo.review(inquiryId, ctx.supplierId));
  }
  // A new version replaces what the last file said, and keeps what the CHAT settled (carryOver: the
  // audit of 21 Sep 2026 saw a revised CSV re-open validity, installation and warranty answered in text).
  let w = carryOver(r.working, workingFromProposal(read.proposal, read.text), l.inq.boq_rows);
  if (note) w = applyCorrections(w, readReply(note, await openIssuesOf(repo, r)).corrections, l.inq.boq_rows);
  await repo.updateReview(r.id, { extracted: read.proposal });
  await runReview(repo, deps, l.inq, r, w, fm.id);
  } catch (e) {
    await repo.updateReview(r0.id, { status: prior, reviewing_since: null }).catch(() => {});
    throw e;
  }
  return view(repo, deps, l.inq, await repo.review(inquiryId, ctx.supplierId));
}

/**
 * THE SUPPLIER TYPES THE QUOTATION INTO THE CHAT (22 Sep 2026, finding SP-F-03).
 *
 * WHAT WAS WRONG. The reader works on a document's TEXT, so a scanned or photographed quotation —
 * the ordinary case for a small UAE contractor who prints, signs, stamps and photographs — got
 * unreadableSaid('image') and a request for a text PDF. Under the LLM hold there is no OCR to fall
 * back on, so the conversation had no way forward at all and the supplier's only remaining door was
 * the bypass: the standalone quote form outside the chat, which skips this review entirely. A
 * supplier pushed out of the reviewed path is a quotation the customer compares unreviewed.
 *
 * WHAT THIS IS. The same pipeline, with the supplier's own typed lines standing in for the file:
 * the text is handed to deps.read as a text/plain document, so doc_read's readTxt and
 * quote_from_document parse it exactly as they parse an attached CSV or text PDF — one parser, one
 * set of rules, one review. Nothing is stored in the quote-files bucket because there is no file,
 * and the typed text itself is the supplier's message in the thread, kept like every other.
 */
export async function typed(repo: ReviewRepo, deps: ReviewDeps, ctx: Ctx, inquiryId: string, text: unknown): Promise<ThreadView | Fail> {
  const l = await load(repo, deps, ctx, inquiryId); if (isFail(l)) return l;
  const bad = writableOr(l, l.r, deps.now()); if (bad) return bad;
  const t = typeof text === 'string' ? text.trim().slice(0, 20000) : '';
  if (!t) return fail(400, 'text_required', 'Type your quotation — one line per item, with the quantity and the price.');
  const r0 = await ensure(repo, deps, ctx, l);
  const sm = await supplierSays(repo, r0.id, 'text', t.slice(0, 2000));
  return readTyped(repo, deps, ctx, l, r0, t, sm.id);
}

/** Does this message look like a quotation someone typed out, rather than a sentence? Two or more
 *  lines that each carry a number: the cheapest test that separates "Gypsum partition 120 sqm 95"
 *  from "validity 30 days", and it only ever decides which READER runs — the review is the same. */
const PRICED_LINES = 2;
// A ONE-LINE QUOTATION IS STILL A QUOTATION (23 Sep 2026, re-review of SP-F-03). Two priced lines is
// the right test in the middle of a review, where most messages are sentences and a false positive
// would hijack a real reply. It is the WRONG test in the one state SP-F-03 exists to close: nothing
// read yet, or awaiting_upload, the supplier has just been told "type it here", and a single-line
// "Supply and install aluminium louvres, 60 sqm, 240 = 14400" fell through to "attach the new
// version" — the dead end itself. There, one priced line is enough. A false positive there is cheap:
// readTyped answers with typedUnreadableSaid, which tells the supplier how to type it AND that a file
// is welcome, so it says strictly more than the awaitingUploadSaid it replaces.
export const looksTyped = (text: string, minLines = PRICED_LINES): boolean =>
  String(text || '').split(/\r?\n/).filter((l) => /\d/.test(l) && l.trim().length > 6).length >= minLines;

async function readTyped(repo: ReviewRepo, deps: ReviewDeps, ctx: Ctx, l: Loaded, r0: ReviewRow, t: string, trigger: string): Promise<ThreadView> {
  const prior = effectiveState(r0, deps.now());
  await repo.updateReview(r0.id, { status: 'reviewing', reviewing_since: deps.now().toISOString() });
  try {
    let read: FileRead;
    try { read = await deps.read(new TextEncoder().encode(t), 'typed_quotation.txt', 'text/plain'); }
    catch (_e) { read = { proposal: null, text: '', kind: 'error' }; }
    const r = (await repo.review(l.inq.id, ctx.supplierId))!;
    if (!read.proposal) {
      await say(repo, deps, r.id, 'notice', typedUnreadableSaid());
      await repo.updateReview(r.id, { status: prior, reviewing_since: null });
      return view(repo, deps, l.inq, await repo.review(l.inq.id, ctx.supplierId));
    }
    const w = carryOver(r.working, workingFromProposal(read.proposal, t), l.inq.boq_rows);
    await repo.updateReview(r.id, { extracted: read.proposal });
    await runReview(repo, deps, l.inq, r, w, trigger);
  } catch (e) {
    await repo.updateReview(r0.id, { status: prior, reviewing_since: null }).catch(() => {});
    throw e;
  }
  return view(repo, deps, l.inq, await repo.review(l.inq.id, ctx.supplierId));
}

/** What the engineer knows at this point of the thread, for the model to answer from: the state, the open points,
 *  what the supplier can do next, and the review's standing rules. Facts only; the words are the model's. */
function stateFacts(inq: SafeInquiry, r: ReviewRow, st: ReviewState, open: Issue[]): string {
  const boq = r.last_review?.boq_lines ?? inq.boq_rows.length;
  const now = !r.working || st === 'awaiting_upload' ? awaitingUploadSaid().en
    : st === 'awaiting_choice' ? choiceSaid().en
    : st === 'ready_to_submit' ? readyToSubmitSaid(inq.job_no).en
    : notUnderstoodSaid(inq.job_no, open).en;
  const rules = (['vat', 'currency', 'boq', 'validity', 'delivery', 'warranty', 'installation', 'customer'] as const)
    .map((tp) => '- ' + answerSaid(tp, inq.job_no, open, boq).en).join('\n');
  return `You are the sales engineer reviewing this supplier's quotation for Job ${inq.job_no} on QuotesDone, in one conversation thread.
STATE: ${st}. ${r.working ? 'A quotation has been read' + (r.last_review?.price_ex_vat != null ? ' (AED ' + r.last_review.price_ex_vat + ' excluding VAT)' : '') + '.' : 'No quotation has been read yet.'}
OPEN POINTS (${open.length}): ${open.map((x, i) => (i + 1) + '. ' + x.en).join(' ') || 'none'}
WHERE THE THREAD STANDS AND WHAT THEY CAN DO NEXT: ${now}
THE REVIEW'S RULES (answer their question from these and your own trade expertise):
${rules}
Answer what they wrote directly; if it is not a question, guide them to the next step above.`;
}

/** A photo the model may SEE as well as read (chat_images.ts limits: JPEG/PNG/WebP, a data URL under its cap). */
const MAX_SEEN_IMAGE_BYTES = 1_150_000;
const seenImage = (bytes: Uint8Array, mime: string): string[] => {
  if (!/^image\/(jpeg|png|webp)$/.test(mime) || bytes.length > MAX_SEEN_IMAGE_BYTES) return [];
  let s = ''; for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return [`data:${mime};base64,${btoa(s)}`];
};

/**
 * A MESSAGE, optionally with a photo or document (13 Oct 2026, the supplier side of #1342). The file passes the same
 * upload gate as a quotation, is stored beside it, and is READ (ruling 1177): code first, then the vision model with
 * one more asking. Read: its text goes to the model as fenced DATA (untrustedBlock), a photo also as an image, and a
 * quotation photographed into the chat with nothing read yet is reviewed like typed lines. Unreadable only when both
 * askings fail: the file is kept and the supplier is asked, in English, for a clearer copy (clearer_copy.ts).
 * prevented by: supplier_api/quote_review.test.ts ('a photo or document sent in the chat is read')
 */
export async function message(repo: ReviewRepo, deps: ReviewDeps, ctx: Ctx, inquiryId: string, text: unknown,
                              file?: { b64?: unknown; filename?: unknown; mime?: unknown } | null): Promise<ThreadView | Fail> {
  const l = await load(repo, deps, ctx, inquiryId); if (isFail(l)) return l;
  const bad = writableOr(l, l.r, deps.now()); if (bad) return bad;
  const t = typeof text === 'string' ? text.trim().slice(0, 2000) : '';
  const hasFile = !!file && typeof file.b64 === 'string' && !!file.b64;
  if (!t && !hasFile) return fail(400, 'text_required', 'Write a message.');
  if (hasFile) return messageWithFile(repo, deps, ctx, l, t, file!);
  const r = await ensure(repo, deps, ctx, l);
  const sm = await supplierSays(repo, r.id, 'text', t);
  const st = effectiveState(r, deps.now());
  const open = await openIssuesOf(repo, r);
  // The FIGURES and terms the supplier states are still PARSED by code (readReply's corrections: a format, not a
  // meaning), and a typed quotation still goes to the same reader. What the message MEANS — a choice, "submit it", a
  // question — is the model's to read, in the same call that writes the answer (1195-1197; no keyword routing).
  const corrections = readReply(t, open).corrections;
  if (corrections.length && r.working) {
    const took = tookSaid(corrections); if (took) await say(repo, deps, r.id, 'text', took, { supplierMessage: t });
    await runReview(repo, deps, l.inq, r, applyCorrections(r.working, corrections, l.inq.boq_rows), sm.id);
    return view(repo, deps, l.inq, await repo.review(inquiryId, ctx.supplierId));
  }
  if ((!r.working || st === 'awaiting_upload') && looksTyped(t, 1)) {
    // THE CHAT BOX IS ALSO THE TYPED PATH (finding SP-F-03): the same reader, the same review.
    return readTyped(repo, deps, ctx, l, r, t, sm.id);
  }
  const actions = st === 'awaiting_choice'
    ? [{ id: 'generate', meaning: 'they want us to generate the standardised quotation for them from what they sent' },
       { id: 'reupload', meaning: 'they will upload a new version of their own quotation' }]
    : st === 'ready_to_submit' ? [{ id: 'submit', meaning: 'they clearly tell us to submit the quotation to the customer now' }] : [];
  const v = await deps.voice({ kind: 'text', supplierMessage: t, actions, situation: stateFacts(l.inq, r, st, open) })
    .catch(() => ({ text: '', action: null as string | null }));
  if (v.action === 'generate' || v.action === 'reupload') return decide(repo, deps, ctx, l, r, v.action, sm.id);
  if (v.action === 'submit') return doSubmit(repo, deps, ctx, l.inq, r, sm.id);
  if (v.text) await repo.addMessage({ review_id: r.id, role: SEAT, kind: st === 'awaiting_choice' ? 'choice_prompt' : 'text', body: v.text, body_ar: null, attachments: [], issues: null });
  else await held(repo, deps, r.id, stateFacts(l.inq, r, st, open), t);
  return view(repo, deps, l.inq, await repo.review(inquiryId, ctx.supplierId));
}

async function messageWithFile(repo: ReviewRepo, deps: ReviewDeps, ctx: Ctx, l: Loaded, t: string, file: { b64?: unknown; filename?: unknown; mime?: unknown }): Promise<ThreadView | Fail> {
  let sc: Scanned;
  try { sc = await deps.scan(String(file.b64), String(file.filename || 'attachment'), String(file.mime || '')); }
  catch (_e) { return fail(400, 'file_unreadable', 'We could not accept that file. Please attach it again.'); }
  if (!sc.ok) return fail(sc.status, sc.code, sc.message);
  const r = await ensure(repo, deps, ctx, l);
  const path = `review/${ctx.supplierId}/${l.inq.id}/${deps.now().getTime()}_chat_${sc.name}`;
  if (!(await repo.storeFile(path, sc.bytes, sc.mime))) return fail(502, 'upload_failed', 'We could not store your file. Please try again.');
  const sm = await supplierSays(repo, r.id, 'file', t || null, [{ kind: 'chat_file', name: sc.name, bucket: 'quote-files', path }]);
  let a: AttachmentRead;
  try { a = deps.readAttachment ? await deps.readAttachment(sc.bytes, sc.name, sc.mime) : await readEveryAttachment(sc.bytes, sc.name, sc.mime, null); }
  catch (e) { a = { status: 'unreadable', by: null, text: '', kind: 'error', model_attempts: 0, reason: String((e as Error)?.message || e).slice(0, 160), doc: null }; }
  await repo.log({ signal: 'quote_review_chat_file', status: a.status, by: a.by, model_attempts: a.model_attempts }, `Chat attachment ${a.status}${a.reason ? ': ' + a.reason : ''}.`);
  if (a.status !== 'read') {
    // HELD, never guessed: the file stays in the thread and the supplier is asked for a clearer copy, in English.
    await say(repo, deps, r.id, 'notice', { en: clearerCopyAsk('supplier', 'en', sc.name), ar: '' }, { supplierMessage: t || null });
    return view(repo, deps, l.inq, await repo.review(l.inq.id, ctx.supplierId));
  }
  const st = effectiveState(r, deps.now());
  // A quotation photographed into the chat with nothing read yet goes to the review — only when the price reader finds
  // prices in it (a site photo's "2.4 m wide" is a number, not a quotation; caught by the test below).
  const asText = transcriptAsText(a.text).slice(0, 20000);
  if ((!r.working || st === 'awaiting_upload') && looksTyped(asText, 1)) {
    const q = await deps.read(new TextEncoder().encode(asText), 'chat_attachment.txt', 'text/plain').catch(() => null);
    if (q?.proposal) return readTyped(repo, deps, ctx, l, r, asText, sm.id);
  }
  const open = await openIssuesOf(repo, r);
  const said = (t || '(they sent this file with no message)') + `\n\nThey attached "${sc.name}". What it says:` + untrustedBlock(a.text.slice(0, 6000));
  const situation = stateFacts(l.inq, r, st, open) + '\nThey attached a file with this message; what it says is in their message. Use it in your answer.';
  const v = await deps.voice({ kind: 'text', supplierMessage: said, situation, images: seenImage(sc.bytes, sc.mime) })
    .catch(() => ({ text: '', action: null as string | null }));
  if (v.text) await repo.addMessage({ review_id: r.id, role: SEAT, kind: 'text', body: v.text, body_ar: null, attachments: [], issues: null });
  else await held(repo, deps, r.id, situation, said);
  return view(repo, deps, l.inq, await repo.review(l.inq.id, ctx.supplierId));
}

export async function choose(repo: ReviewRepo, deps: ReviewDeps, ctx: Ctx, inquiryId: string, choice: unknown): Promise<ThreadView | Fail> {
  const l = await load(repo, deps, ctx, inquiryId); if (isFail(l)) return l;
  const bad = writableOr(l, l.r, deps.now()); if (bad) return bad;
  if (choice !== 'generate' && choice !== 'reupload') return fail(400, 'invalid_choice', 'Choose "generate" or "reupload".');
  const r = l.r;
  if (!r || effectiveState(r, deps.now()) !== 'awaiting_choice') return fail(409, 'not_awaiting_choice', 'There is no choice to make yet.');
  const sm = await supplierSays(repo, r.id, 'choice', choice === 'generate' ? 'Generate the standardised quotation for me.' : 'I will upload a new version.');
  return decide(repo, deps, ctx, l, r, choice, sm.id);
}
async function decide(repo: ReviewRepo, deps: ReviewDeps, ctx: Ctx, l: Loaded, r: ReviewRow, choice: Choice, trigger: string) {
  const ch = (await repo.requests(r.id, true)).filter((x) => x.kind === 'choice').map((x) => x.id);
  if (ch.length) await repo.closeRequests(ch, 'answered', trigger);
  await repo.updateReview(r.id, { choice });
  if (choice === 'reupload') {
    await repo.updateReview(r.id, { status: 'awaiting_upload' });
    await say(repo, deps, r.id, 'text', awaitingUploadSaid());
    return view(repo, deps, l.inq, await repo.review(l.inq.id, ctx.supplierId));
  }
  // THE SUPPLIER SEES WHAT GOES OUT IN ITS NAME, FIRST (22 Sep 2026, finding SP-F-07). "Generate it
  // for me" used to call doSubmit here: the quotation reached the customer's comparison and the PDF
  // was printed afterwards, so the supplier's first sight of its own standardised quotation was
  // after the customer already had it. Both roads now end at the same door — reupload goes through
  // awaiting_upload, generate goes through this preview, and BOTH wait in ready_to_submit for the
  // supplier's Submit. Nothing is sent from here.
  if (!r.working) { await say(repo, deps, r.id, 'text', awaitingUploadSaid()); return view(repo, deps, l.inq, await repo.review(l.inq.id, ctx.supplierId)); }
  // r.last_review IS the review runReview stored for this same Working, and submitPayload sends
  // `rv.price_ex_vat ?? w.amount` — so the total printed here is the total that will be submitted,
  // from one expression rather than two that can drift.
  await say(repo, deps, r.id, 'review', generatedSaid(l.inq.job_no, r.working, r.last_review?.price_ex_vat ?? null));
  await repo.updateReview(r.id, { status: 'ready_to_submit' });
  return view(repo, deps, l.inq, await repo.review(l.inq.id, ctx.supplierId));
}

export async function submit(repo: ReviewRepo, deps: ReviewDeps, ctx: Ctx, inquiryId: string): Promise<ThreadView | Fail> {
  const l = await load(repo, deps, ctx, inquiryId); if (isFail(l)) return l;
  const bad = writableOr(l, l.r, deps.now()); if (bad) return bad;
  if (!l.r || effectiveState(l.r, deps.now()) !== 'ready_to_submit') return fail(409, 'not_ready', 'The quotation is not approved for submission yet.');
  return doSubmit(repo, deps, ctx, l.inq, l.r, null);
}

/** What submit_quote receives: the approved quotation, with every detail the chat confirmed. */
export function submitPayload(inq: SafeInquiry, r: Pick<ReviewRow, 'original_file_path' | 'original_file_name'>, w: Working, rv: Review): Record<string, unknown> {
  const vt = ['exclusive', 'inclusive', 'not_registered'].includes(String(w.vat_treatment)) ? w.vat_treatment : undefined;
  return {
    action: 'submit_quote', inquiry_id: inq.id, source: 'upload', amount: rv.price_ex_vat ?? w.amount,
    items: w.lines.map((l) => ({ description: l.description, specification: l.specification ?? undefined, qty: parseQty(l.qty).n, unit: l.unit || null, unit_price: l.unit_price, amount: l.amount, spec: l.spec ?? undefined })),
    lead_time: w.lead_time, validity: w.validity, payment_terms: w.payment_terms, warranty: w.warranty,
    scope: w.scope, conditions: w.conditions, exclusions: w.exclusions, notes: w.notes, terms_spec: w.terms_spec,
    original_file_path: r.original_file_path, original_file_name: r.original_file_name, masked_terms: w.masked_terms,
    vat_treatment: vt, price_ex_vat: rv.price_ex_vat ?? undefined, subtotal: w.subtotal ?? undefined, vat_amount: w.vat_amount ?? undefined, trn: w.trn ?? undefined,
    gross_amount: w.gross_amount ?? undefined, discount_amount: w.discount_amount ?? undefined, discount_label: w.discount_label ?? undefined,
    option_totals: Object.keys(w.option_totals || {}).length > 1 ? w.option_totals : undefined,
  };
}

async function doSubmit(repo: ReviewRepo, deps: ReviewDeps, ctx: Ctx, inq: SafeInquiry, r: ReviewRow, trigger: string | null): Promise<ThreadView> {
  const again = async (notice: ThreadView['notice'] = null) => view(repo, deps, inq, await repo.review(inq.id, ctx.supplierId), notice);
  if (!r.working) return again({ code: 'no_quotation', message: 'Attach your quotation first.' });
  // The rules are read once more at the moment of submission: nothing unreviewed is submitted.
  const rv = reviewQuotation(inq, r.working);
  if (!rv.approved) { await runReview(repo, deps, inq, r, r.working, trigger); return again(); }
  const prior = effectiveState(r, deps.now());
  // One submission at a time: a double click or a retry finds the review already moved, and stops.
  if (!(await repo.claim(r.id, ['awaiting_choice', 'ready_to_submit'], 'reviewing'))) return again({ code: 'already_submitting', message: 'This quotation is already being submitted.' });
  try {
    return await submitClaimed(repo, deps, ctx, inq, r, rv, prior, again);
  } catch (e) {
    await repo.updateReview(r.id, { status: prior, reviewing_since: null }).catch(() => {});
    throw e;
  }
}
async function submitClaimed(repo: ReviewRepo, deps: ReviewDeps, ctx: Ctx, inq: SafeInquiry, r: ReviewRow, rv: Review, prior: ReviewState, again: (notice?: ThreadView['notice']) => Promise<ThreadView>): Promise<ThreadView> {
  const generated = r.choice === 'generate';
  // This flow reads the file with code (doc_read + quote_from_document), never a model: say so, so the comparison is
  // routed normally instead of failing closed on 'unknown' (#880 review, item 3).
  await repo.recordReader?.(inq.id, ctx.supplierId, 'deterministic');
  const res = await deps.submit(submitPayload(inq, r, r.working!, rv));
  const j = res.json || {};
  const opts: Json[] = Array.isArray(j.options) ? j.options : [];
  const acceptedIds: string[] = opts.length ? opts.filter((o) => o.accepted).map((o) => String(o.quote_id)) : (j.ok && j.accepted && j.quote?.id ? [String(j.quote.id)] : []);
  // A multi-option submission can come back with one option accepted and another held
  // (TypeScript review, 15 Sep 2026): the accepted one is submitted, the held one is named.
  const heldOpts = opts.filter((o) => o.held);
  if (j.ok && acceptedIds.length) {
    const ids = acceptedIds;
    // BOTH LANGUAGES (audit 21 Sep 2026, finding 28: an Arabic-UI supplier got an English-only
    // quotation). The supplier's own language is printed first and named in the message; the other
    // is attached beside it. A print that fails still leaves the attachment, which the portal prints
    // on demand through quote_pdf.
    const first: Lang = ctx.lang, second: Lang = first === 'ar' ? 'en' : 'ar';
    const pdf = generated && ids[0] ? await deps.quotePdf(ids[0], first).catch(() => ({ url: null, ref: null })) : { url: null, ref: null };
    if (generated && ids[0]) await deps.quotePdf(ids[0], second).catch(() => null);
    const atts: Attachment[] = generated && ids[0] ? [first, second].map((lg) => ({ kind: 'standard_quote' as const, name: `${pdf.ref || 'QuotesDone quotation'}-${lg}.pdf`, quote_id: ids[0], lang: lg })) : [];
    const heldIssues = heldOpts.flatMap((o) => (Array.isArray(o.missing) ? o.missing : []) as MissingItem[]).map(fromMissing);
    const base = submittedSaid(inq.job_no, pdf.ref, generated);
    const said: Said = heldOpts.length ? {
      en: `${base.en}\n\n${heldOpts.map((o) => `Option ${o.option_no}`).join(', ')} is still held by the hold desk for these exact details — complete them in the hold panel on this job, and it is released when you confirm:\n\n${heldIssues.map((x, i) => `${i + 1}. ${x.en}`).join('\n')}`,
      ar: `${base.ar}\n\n${heldOpts.map((o) => `الخيار ${o.option_no}`).join('، ')} ما زال معلّقًا إلى حين استكمال التفاصيل الدقيقة التالية — يُرجى استكمالها في بطاقة العرض المعلّق ضمن هذا الطلب، ويُرسل إلى العميل فور تأكيدكم:\n\n${heldIssues.map((x, i) => `${i + 1}. ${x.ar}`).join('\n')}`,
    } : base;
    const sm = await say(repo, deps, r.id, 'submitted', said, { attachments: atts, issues: heldIssues.length ? heldIssues : undefined });
    const left = (await repo.requests(r.id, true)).map((x) => x.id);
    if (left.length) await repo.closeRequests(left, 'answered', sm.id);
    await repo.updateReview(r.id, { status: 'submitted', submitted_quote_ids: ids, completed_at: deps.now().toISOString(), reviewing_since: null });
    await repo.log({ signal: 'quote_review_submitted', inquiry_id: inq.id, quotes: ids.length, generated: generated ? 1 : 0 }, `Submitted the approved quotation for job ${inq.job_no} through submit_quote (${ids.length} quote row(s))${generated ? '; the standardised quotation was generated' : ''}.`);
    return again();
  }
  if (j.ok && (j.held || (Array.isArray(j.options) && j.options.some((o: Json) => o.held)))) {
    // The hold gate disagreed with the review. Its words win: the missing details become requests.
    const missing: MissingItem[] = Array.isArray(j.missing) ? j.missing : (j.options || []).flatMap((o: Json) => o.missing || []);
    const issues = missing.map(fromMissing);
    const said: Said = {
      en: `The hold desk still needs these exact details before the quotation for Job ${inq.job_no} can reach the customer:\n\n${issues.map((x, i) => `${i + 1}. ${x.en}`).join('\n')}\n\nReply here with them, or attach a revised file.`,
      ar: `لا تزال التفاصيل الدقيقة التالية مطلوبة قبل أن يصل عرضكم للطلب ${inq.job_no} إلى العميل:\n\n${issues.map((x, i) => `${i + 1}. ${x.ar}`).join('\n')}\n\nيُرجى كتابتها هنا، أو إرفاق ملف معدّل.`,
    };
    const hm = await say(repo, deps, r.id, 'review', said, { issues });
    const have = new Set((await repo.requests(r.id, true)).map((x) => x.key));
    const fresh = issues.filter((i) => !have.has(issueKey(i)));
    if (fresh.length) await repo.addRequests(fresh.map((i) => ({ review_id: r.id, key: issueKey(i), code: i.code, kind: i.kind, line_no: i.line_no, boq_line: i.boq_line, attr: i.attr, label_en: i.en, label_ar: i.ar, asked_message_id: hm.id || null })));
    await repo.updateReview(r.id, { status: 'changes_requested', choice: null, reviewing_since: null, last_review: { ...rv, approved: false, issues } });
    return again();
  }
  if (j.ok) {
    // Saved as a draft by the commercial accept rule — say what it said, and keep the conversation open.
    await say(repo, deps, r.id, 'notice', { en: `Your quotation was saved but not yet accepted: ${String(j.message || 'some commercial terms are missing')}. Tell me the missing terms, or attach a revised file.`, ar: `حُفظ عرضكم، لكنه لم يُقبل بعد لنقص بعض الشروط التجارية. يُرجى كتابة الشروط الناقصة هنا، أو إرفاق ملف معدّل.` });
    await repo.updateReview(r.id, { status: 'changes_requested', choice: null, reviewing_since: null });
    return again();
  }
  // Refused before anything was written (terms, verification, registration due, a concluded job).
  const msg = String(j.error || 'The quotation could not be submitted.');
  await say(repo, deps, r.id, 'notice', { en: `I could not submit the quotation yet: ${msg}`, ar: `تعذّر تقديم العرض حتى الآن: ${msg}` });
  await repo.updateReview(r.id, { status: prior, reviewing_since: null });
  return again({ code: String(j.code || 'submit_refused'), message: msg });
}

// ---------------------------------------------------------------------------------------------
// The production repository: the service-role client. It never deletes: the thread is a
// conversation store (founder, 14 Sep 2026: "all conversations need to be saved").
// ---------------------------------------------------------------------------------------------
// deno-lint-ignore no-explicit-any
export function supabaseReviewRepo(admin: any): ReviewRepo {
  // deno-lint-ignore no-explicit-any
  const must = <T = any>(r: { data?: T; error?: { message: string } | null }): T => { if (r.error) throw new Error(r.error.message); return r.data as T; };
  const COLS = 'id,inquiry_id,supplier_id,owner_email,status,choice,original_file_path,original_file_name,extracted,working,last_review,reviewing_since,total_amount,currency,submitted_quote_ids,completed_at,created_at,updated_at';
  return {
    async review(inquiryId, supplierId) { return must(await admin.from('quote_reviews').select(COLS).eq('inquiry_id', inquiryId).eq('supplier_id', supplierId).maybeSingle()) ?? null; },
    async reviewsOf(supplierId) { return must(await admin.from('quote_reviews').select('inquiry_id,status,updated_at').eq('supplier_id', supplierId).limit(200)) ?? []; },
    async createReview(r) {
      // Two tabs opening the same job at once: the unique (inquiry, supplier) pair decides, and the loser reads the winner.
      const ins = await admin.from('quote_reviews').insert({ ...r, status: 'open', owner_seat: SEAT }).select(COLS).single();
      if (!ins.error) return ins.data;
      const got = must(await admin.from('quote_reviews').select(COLS).eq('inquiry_id', r.inquiry_id).eq('supplier_id', r.supplier_id).maybeSingle());
      if (!got) throw new Error(ins.error.message);
      return got;
    },
    async updateReview(id, patch) { must(await admin.from('quote_reviews').update({ ...patch, updated_at: new Date().toISOString() }).eq('id', id)); },
    async claim(id, from, to) {
      const now = new Date().toISOString();
      const rows = must<{ id: string }[]>(await admin.from('quote_reviews').update({ status: to, reviewing_since: now, updated_at: now }).eq('id', id).in('status', from).select('id'));
      return Array.isArray(rows) && rows.length > 0;
    },
    async addMessage(m) { return must(await admin.from('quote_review_messages').insert(m).select('id,review_id,role,kind,body,body_ar,attachments,issues,created_at').single()); },
    async messages(reviewId) { return must(await admin.from('quote_review_messages').select('id,review_id,role,kind,body,body_ar,attachments,issues,created_at').eq('review_id', reviewId).order('created_at', { ascending: true }).order('id', { ascending: true }).limit(500)) ?? []; },
    async requests(reviewId, onlyOpen) { let q = admin.from('quote_review_request').select('*').eq('review_id', reviewId); if (onlyOpen) q = q.eq('state', 'open'); return must(await q.order('id', { ascending: true })) ?? []; },
    async addRequests(rows) { if (rows.length) must(await admin.from('quote_review_request').insert(rows)); },
    async closeRequests(ids, state, messageId) { if (ids.length) must(await admin.from('quote_review_request').update({ state, answered_message_id: messageId, answered_at: new Date().toISOString() }).in('id', ids).eq('state', 'open')); },
    async storeFile(path, bytes, mime) { const up = await admin.storage.from('quote-files').upload(path, bytes, { contentType: mime, upsert: false }); return !up.error; },
    async signFile(bucket, path) { try { const { data } = await admin.storage.from(bucket).createSignedUrl(path, 3600); return data?.signedUrl || null; } catch (_e) { return null; } },
    async recordReader(inquiryId, supplierId, model) {
      const { error } = await admin.from('quote_extraction_model').upsert({ subject_key: `${supplierId}:${inquiryId}`, model, extracted_at: new Date().toISOString() });
      if (error) console.error('quote_extraction_model: ' + error.message);
    },
    async log(counts, note) { try { await admin.from('agent_runs').insert({ agent: SEAT, status: 'ok', started_at: new Date().toISOString(), finished_at: new Date().toISOString(), counts, note: note.slice(0, 500) }); } catch (_e) { /* the trail never blocks the conversation */ } },
  };
}
