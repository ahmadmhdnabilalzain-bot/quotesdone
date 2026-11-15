import { closedSaid, greeting, SEAT, type Issue, type SafeInquiry, type Said } from '../quote_review.ts';
import { type Attachment, type Ctx, type Fail, type MessageRow, type MessageView, type MsgKind, type ReviewDeps, type ReviewRepo, type ReviewRow, type ReviewState, type ThreadView, fail } from './types.ts';
import { POINT_CODE } from '../../_shared/comparison_points.ts';


/** A review stuck in 'reviewing' this long crashed mid-way; it is treated as not reviewing. 8 minutes: a review now runs
 *  off the request (offRequest), and the runtime's background wall clock is 400 s, so a job older than 480 s cannot still
 *  be running. Below 400 s a LIVE job would be declared dead and a second one could start (review of #1413). */
const STALE_MS = 480_000;
const WRITABLE: ReviewState[] = ['open', 'changes_requested', 'awaiting_choice', 'awaiting_upload', 'ready_to_submit'];

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
  // A SUBMITTED CONVERSATION TAKES HIS ANSWER WHILE A COMPARISON POINT IS OPEN (final review of 15 Nov 2026, FIX 1 i): he can
  // write, not upload or submit; nothing else reopens it, and the points close only with his answer (message.ts).
  const answering = st === 'submitted' && !closedInq && open.some((q) => q.code === POINT_CODE);
  return {
    ...base, state: st, choice: r.choice, can_write: writable || answering, can_upload: writable, can_choose: writable && st === 'awaiting_choice',
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
/** NOBODY IS LEFT SILENT (review of #1335): no model answer → the turn is queued for the model and escalated to the
 *  seat after 15 minutes. The fixed HELD NOTICE is added ONLY when OpenRouter was down for the call (voice().outage;
 *  founder_instruction 1339, 27 Oct 2026: "the engineer and customer support never replies without llm unless the server
 *  of open router is down"). A model that answered and was refused leaves no code-written message: the replay answers. */
export const QR_HELD_NOTICE = 'Thank you, we have received your message. The sales engineer will reply here shortly.';
/** Nothing was added to the thread (the model is up; its answer comes from the queue). */
const NOTHING_ADDED = { id: null } as unknown as MessageRow;
async function held(repo: ReviewRepo, deps: ReviewDeps, reviewId: string, situation: string, supplierMessage: string | null, outage: boolean, issues?: Issue[], problems: string[] = []): Promise<MessageRow> {
  const r = outage ? await repo.addMessage({ review_id: reviewId, role: SEAT, kind: 'notice', body: QR_HELD_NOTICE, body_ar: null, attachments: [], issues: issues ?? null }) : NOTHING_ADDED;
  await deps.hold({ reviewId, situation, supplierMessage, why: outage ? 'no_model_answer' : 'model_up_no_safe_reply', outage, problems }).catch(() => {});
  await repo.log({ signal: outage ? 'quote_review_held_notice' : 'quote_review_queued_for_model' }, outage
    ? 'OpenRouter was down: the held notice was added and the turn queued for the model (1339).'
    : 'The model answered but nothing it wrote could be sent: no code-written message was added; the turn is queued for the model (1339).');
  return r;
}
async function say(repo: ReviewRepo, deps: ReviewDeps, reviewId: string, kind: MsgKind, s: Said,
                   extra: { issues?: Issue[]; attachments?: Attachment[]; notification?: boolean; supplierMessage?: string | null } = {}): Promise<MessageRow> {
  const add = (body: string, body_ar: string | null) =>
    repo.addMessage({ review_id: reviewId, role: SEAT, kind, body, body_ar, attachments: extra.attachments ?? [], issues: extra.issues ?? null });
  if (extra.notification || NOTIFICATION_KINDS.includes(kind)) return add(s.en, s.ar);
  const v = await deps.voice({ kind, situation: s.en, supplierMessage: extra.supplierMessage ?? null }).catch(() => ({ text: '', action: null, outage: false, problems: [] as string[] }));
  if (!v.text) return held(repo, deps, reviewId, s.en, extra.supplierMessage ?? null, v.outage === true, extra.issues, v.problems ?? []);
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
  // A REVIEW THE RUNTIME KILLED (offRequest cannot run its catch) never stays 'reviewing': once stale it goes back and is
  // queued for the sales_engineer seat with the held notice, exactly as a failed one is. The claim makes it happen once.
  if (r && r.status === 'reviewing' && effectiveState(r, deps.now()) !== 'reviewing' && await repo.claim(r.id, ['reviewing'], effectiveState(r, deps.now()))) {
    await repo.updateReview(r.id, { reviewing_since: null });
    // the model writes it (1339); the fixed notice only if OpenRouter is down (say → held)
    await say(repo, deps, r.id, 'notice', { en: 'The review of their last message or file stopped before it finished (it ran longer than ' + Math.round(STALE_MS / 60000) + ' minutes). Tell them it is being looked at and what happens next.', ar: '' }).catch(() => {});
    await repo.log({ signal: 'quote_review_stale_resolved' }, 'A review left in reviewing past STALE_MS was resolved and queued for sales_engineer.').catch(() => {});
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
/** `answeringPoints`: a text message to a submitted conversation that has an open comparison point is his answer to it. */
function writableOr(l: Loaded, r: ReviewRow | null, now: Date, answeringPoints = false): Fail | null {
  if (l.inq.concluded || l.inq.revealed) return fail(409, 'inquiry_closed', 'This job is closed; the customer has already chosen.');
  if (!r) return null;
  const st = effectiveState(r, now);
  if (st === 'reviewing') return fail(409, 'reviewing', 'Your quotation is being reviewed; please wait for the result.');
  if (st === 'submitted' && answeringPoints) return null;
  if (st === 'submitted' || st === 'closed') return fail(409, 'review_closed', 'This conversation is closed.');
  return null;
}

// Names the sibling modules of this folder import (the declarations above are unchanged).
export { effectiveState, ensure, held, isFail, load, say, supplierSays, view, writableOr };
export type { Loaded };
