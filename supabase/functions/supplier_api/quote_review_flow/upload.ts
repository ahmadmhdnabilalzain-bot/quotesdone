import { applyCorrections, carryOver, choiceSaid, issueKey, readReply, readyToSubmitSaid, reviewQuotation, reviewSaid, unreadableSaid, workingFromProposal, type Issue, type SafeInquiry, type Working } from '../quote_review.ts';
import { type Choice, type Ctx, type Fail, type FileRead, type ReviewDeps, type ReviewRepo, type ReviewRow, type ReviewState, type Scanned, type ThreadView, fail } from './types.ts';
import { effectiveState, ensure, isFail, load, say, supplierSays, view, writableOr } from './thread_view.ts';

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
  const prior = await enterReview(repo, deps, r0); if (prior == null) return BUSY;
  const path = `review/${ctx.supplierId}/${inquiryId}/${deps.now().getTime()}_${sc.name}`;
  if (!(await repo.storeFile(path, sc.bytes, sc.mime))) { await leaveReview(repo, r0.id, prior); return fail(502, 'upload_failed', 'We could not store your file. Please try again.'); }
  const note = typeof text === 'string' && text.trim() ? text.trim().slice(0, 2000) : null;
  const fm = await supplierSays(repo, r0.id, 'file', note, [{ kind: 'quotation_file', name: sc.name, bucket: 'quote-files', path }]);
  await repo.updateReview(r0.id, { original_file_path: path, original_file_name: sc.name });
  await offRequest(repo, deps, r0.id, prior, async () => {
    let read: FileRead;
    try { read = await deps.read(sc.bytes, sc.name, sc.mime); } catch (_e) { read = { proposal: null, text: '', kind: 'error' }; }
    const r = (await repo.review(inquiryId, ctx.supplierId))!;
    if (!read.proposal) {
      await say(repo, deps, r.id, 'notice', unreadableSaid(read.kind));
      await repo.updateReview(r.id, { status: prior, reviewing_since: null });
      return;
    }
    // A new version replaces what the last file said, and keeps what the CHAT settled (carryOver: the
    // audit of 21 Sep 2026 saw a revised CSV re-open validity, installation and warranty answered in text).
    let w = carryOver(r.working, workingFromProposal(read.proposal, read.text), l.inq.boq_rows);
    if (note) w = applyCorrections(w, readReply(note, await openIssuesOf(repo, r)).corrections, l.inq.boq_rows);
    await repo.updateReview(r.id, { extracted: read.proposal });
    await runReview(repo, deps, l.inq, r, w, fm.id);
  });
  return view(repo, deps, l.inq, await repo.review(inquiryId, ctx.supplierId));
}

/**
 * ONE REVIEW AT A TIME (review of #1413). Entering 'reviewing' is a CLAIM (status moves only from the state just read), so
 * two turns sent at the same moment cannot both start a job: the second is refused 409 'reviewing' and nothing it sent is
 * stored. Returns the state the review came from, or null when one is already running.
 */
async function enterReview(repo: ReviewRepo, deps: ReviewDeps, r: ReviewRow): Promise<ReviewState | null> {
  const prior = effectiveState(r, deps.now());
  if (prior === 'reviewing' || !(await repo.claim(r.id, [r.status], 'reviewing'))) return null;
  await repo.updateReview(r.id, { reviewing_since: deps.now().toISOString() });
  return prior;
}
const leaveReview = (repo: ReviewRepo, id: string, prior: ReviewState) => repo.updateReview(id, { status: prior, reviewing_since: null }).catch(() => {});
const BUSY = fail(409, 'reviewing', 'Your quotation is being reviewed; please wait for the result.');

/**
 * THE REVIEW RUNS OFF THE REQUEST (13 Oct 2026, measured live: a photographed quotation's review made 7 sequential model
 * calls and the request hit the edge runtime's 150 s limit, HTTP 504, while the server finished a minute later). With
 * deps.background (supplier_api passes EdgeRuntime.waitUntil) the turn answers at once in 'reviewing' and the portal polls
 * until it is not; without it (the tests) the job runs inline. A job that FAILS never leaves the turn 'reviewing': the
 * state goes back, the held notice is added and the turn is queued for the sales_engineer seat (held()). A job the
 * runtime KILLS cannot run its catch; load() resolves that one the same way once it is older than STALE_MS.
 * prevented by: supplier_api/quote_review.test.ts ('a review runs off the request ...')
 */
async function offRequest(repo: ReviewRepo, deps: ReviewDeps, reviewId: string, prior: ReviewState, job: () => Promise<void>): Promise<void> {
  const guarded = async () => {
    try { await job(); }
    catch (e) {
      const why = String((e as Error)?.message || e).slice(0, 200);
      await repo.updateReview(reviewId, { status: prior, reviewing_since: null }).catch(() => {});
      // the model writes it (1339); the fixed notice only if OpenRouter is down (say → held). `why` stays out of the facts.
      await say(repo, deps, reviewId, 'notice', { en: 'The review of their last message or file failed before it finished. Tell them it is being looked at and what happens next.', ar: '' }).catch(() => {});
      await repo.log({ signal: 'quote_review_background_failed' }, 'The quotation review failed off the request; the turn went back to ' + prior + ' and was queued for sales_engineer: ' + why).catch(() => {});
      if (!deps.background) throw e;
    }
  };
  if (deps.background) deps.background(guarded()); else await guarded();
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

// Names the sibling modules of this folder import (the declarations above are unchanged).
export { BUSY, enterReview, leaveReview, offRequest, openIssuesOf, runReview };
