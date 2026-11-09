import { answerSaid, awaitingUploadSaid, carryOver, choiceSaid, notUnderstoodSaid, readyToSubmitSaid, typedUnreadableSaid, workingFromProposal, type Issue, type SafeInquiry } from '../quote_review.ts';
import { type Ctx, type Fail, type FileRead, type ReviewDeps, type ReviewRepo, type ReviewRow, type ReviewState, type ThreadView, fail } from './types.ts';
import { type Loaded, ensure, isFail, load, say, supplierSays, view, writableOr } from './thread_view.ts';
import { BUSY, enterReview, offRequest, runReview } from './upload.ts';

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

async function readTyped(repo: ReviewRepo, deps: ReviewDeps, ctx: Ctx, l: Loaded, r0: ReviewRow, t: string, trigger: string): Promise<ThreadView | Fail> {
  const prior = await enterReview(repo, deps, r0); if (prior == null) return BUSY;
  await offRequest(repo, deps, r0.id, prior, () => typedJob(repo, deps, ctx, l, t, trigger, prior));
  return view(repo, deps, l.inq, await repo.review(l.inq.id, ctx.supplierId));
}
/** The typed (or photographed) quotation's review itself; the caller has already set 'reviewing'. */
async function typedJob(repo: ReviewRepo, deps: ReviewDeps, ctx: Ctx, l: Loaded, t: string, trigger: string, prior: ReviewState, already?: FileRead): Promise<void> {
  let read: FileRead;
  if (already) read = already;
  else try { read = await deps.read(new TextEncoder().encode(t), 'typed_quotation.txt', 'text/plain'); }
  catch (_e) { read = { proposal: null, text: '', kind: 'error' }; }
  const r = (await repo.review(l.inq.id, ctx.supplierId))!;
  if (!read.proposal) {
    await say(repo, deps, r.id, 'notice', typedUnreadableSaid());
    await repo.updateReview(r.id, { status: prior, reviewing_since: null });
    return;
  }
  const w = carryOver(r.working, workingFromProposal(read.proposal, t), l.inq.boq_rows);
  await repo.updateReview(r.id, { extracted: read.proposal });
  await runReview(repo, deps, l.inq, r, w, trigger);
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

// Names the sibling modules of this folder import (the declarations above are unchanged).
export { readTyped, stateFacts, typedJob };
