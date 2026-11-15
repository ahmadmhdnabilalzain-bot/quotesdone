import { type MissingItem } from '../../_shared/line_specs/assess.ts';
import { fromMissing, issueKey, parseQty, reviewQuotation, submittedSaid, type Lang, type Review, type SafeInquiry, type Said, type Working } from '../quote_review.ts';
import { type Attachment, type Ctx, type Fail, type Json, type ReviewDeps, type ReviewRepo, type ReviewRow, type ReviewState, type ThreadView, fail } from './types.ts';
import { effectiveState, isFail, load, say, view, writableOr } from './thread_view.ts';
import { runReview } from './upload.ts';

export async function submit(repo: ReviewRepo, deps: ReviewDeps, ctx: Ctx, inquiryId: string): Promise<ThreadView | Fail> {
  const l = await load(repo, deps, ctx, inquiryId); if (isFail(l)) return l;
  const bad = writableOr(l, l.r, deps.now()); if (bad) return bad;
  if (!l.r || effectiveState(l.r, deps.now()) !== 'ready_to_submit') return fail(409, 'not_ready', 'The quotation is not approved for submission yet.');
  return doSubmit(repo, deps, ctx, l.inq, l.r, null);
}

/** What submit_quote receives: the approved quotation, with every detail the chat confirmed. */
export function submitPayload(inq: SafeInquiry, r: Pick<ReviewRow, 'original_file_path' | 'original_file_name'>, w: Working, rv: Review): Record<string, unknown> {
  const vt = ['exclusive', 'inclusive', 'not_registered', 'zero_rated', 'exempt'].includes(String(w.vat_treatment)) ? w.vat_treatment : undefined;
  return {
    action: 'submit_quote', inquiry_id: inq.id, source: 'upload', amount: rv.price_ex_vat ?? w.amount,
    items: w.lines.map((l) => ({ description: l.description, specification: l.specification ?? undefined, qty: parseQty(l.qty).n, unit: l.unit || null, unit_price: l.unit_price, amount: l.amount, spec: l.spec ?? undefined, country_of_origin: l.country_of_origin ?? undefined })),
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
  // WHO READ IT (#880 review, item 3): a file attached in this chat is read with code (doc_read + quote_from_document),
  // so 'deterministic'; a quotation e-mailed to us was read by the MODEL (email_quote.ts, 12 Nov 2026) and its reading,
  // stored as `extracted`, names that model, so quote_compare is routed to another family (instruction ~891).
  const by = (r.extracted as { extracted_by_model?: unknown } | null)?.extracted_by_model;
  await repo.recordReader?.(inq.id, ctx.supplierId, typeof by === 'string' && by ? by : 'deterministic');
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
    const first: Lang = ctx.lang;   // one print, in English (founder ruling 1008); no second-language copy for a supplier
    const pdf = generated && ids[0] ? await deps.quotePdf(ids[0], first).catch(() => ({ url: null, ref: null })) : { url: null, ref: null };
    const atts: Attachment[] = generated && ids[0] ? [first].map((lg) => ({ kind: 'standard_quote' as const, name: `${pdf.ref || 'QuotesDone quotation'}-${lg}.pdf`, quote_id: ids[0], lang: lg })) : [];
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
  // HE READS A SENTENCE, NEVER A CODE (15 Nov 2026, third review of the certificate branch, item 2): submit_quote's 503 carries
  // error 'quote_not_sent' / 'quote_not_saved' and the sentence in `message`; the thread and the banner printed the code. The
  // message first, then an error that is itself a sentence (the older refusals), then the general one.
  const msg = String(j.message || (typeof j.error === 'string' && /\s/.test(j.error) ? j.error : '') || 'The quotation could not be submitted.');
  // the two writes that did not land (quote_not_sent / quote_not_saved) are said with THIS page's button (third review, item 6)
  const lost = j.code === 'quote_not_sent' || j.code === 'quote_not_saved';
  const said = lost ? `Your quotation was NOT sent to the customer: our system could not complete the last step just now. Nothing is lost. Please press "Submit to Job ${inq.job_no}" again in a moment.` : msg;
  await say(repo, deps, r.id, 'notice', { en: lost ? said : `I could not submit the quotation yet: ${msg}`, ar: lost ? said : `تعذّر تقديم العرض حتى الآن: ${msg}` });
  await repo.updateReview(r.id, { status: prior, reviewing_since: null });
  return again({ code: lost ? 'submit_not_sent' : String(j.code || 'submit_refused'), message: said });
}

// Names the sibling modules of this folder import (the declarations above are unchanged).
export { doSubmit };
