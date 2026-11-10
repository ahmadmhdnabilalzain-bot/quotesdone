import { awaitingUploadSaid, generatedSaid } from '../quote_review.ts';
import { type Choice, type Ctx, type Fail, type ReviewDeps, type ReviewRepo, type ReviewRow, type ThreadView, fail } from './types.ts';
import { type Loaded, effectiveState, isFail, load, say, supplierSays, view, writableOr } from './thread_view.ts';

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

// Names the sibling modules of this folder import (the declarations above are unchanged).
export { decide };
