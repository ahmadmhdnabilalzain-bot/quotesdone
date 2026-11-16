import { readEveryAttachment, untrustedBlock, type AttachmentRead } from '../../_shared/read_every_attachment.ts';
import { clearerCopyAsk } from '../../_shared/clearer_copy.ts';
import { applyCorrections, readReply, SEAT, tookSaid } from '../quote_review.ts';
import { type Ctx, type Fail, type MessageRow, type RequestRow, type ReviewDeps, type ReviewRepo, type ReviewRow, type Scanned, type ThreadView, fail } from './types.ts';
import { type Loaded, effectiveState, ensure, held, isFail, load, say, supplierSays, view, writableOr } from './thread_view.ts';
import { BUSY, enterReview, leaveReview, offRequest, openIssuesOf, runReview } from './upload.ts';
import { looksTyped, readTyped, stateFacts, typedJob } from './typed.ts';
import { decide } from './choose.ts';
import { doSubmit } from './submit.ts';
import { transcriptAsText } from './reading.ts';
import { figuresIn, readFigure } from '../../quote_extract/model_reading.ts';
import { POINT_CODE } from '../../_shared/comparison_points.ts';

// THE CUSTOMER'S COMPARISON POINTS ARE CLOSED ONLY BY HIS ANSWER (CEO, under founder ruling 1696; final review of 15 Nov 2026,
// FIX 1). quote_compare hands each point a quote leaves open to the sales engineer, and the hand-over records it here as an
// open clarification (code comparison_point). Whether his message answers it is the model's to read, in the same call that
// writes the engineer's reply (1195-1197); code checks the words it cites are his, then closes the points with his message,
// which quote_compare shows the customer on the next view. A submitted conversation takes this text answer and nothing else.
// prevented by: supplier_api/the_comparison_points_are_answered_only_by_the_supplier.test.ts
const POINT_ACTION = { id: 'answer_points', words: true, meaning: 'their message answers the customer\'s points that QuotesDone asked them to confirm (listed in the situation): it states what their quotation includes, a figure, a date or a yes / no to those points; a question back, or a message about anything else, is NOT this' };
const norm = (x: string) => x.toLowerCase().replace(/\s+/g, ' ').trim();
const citedIn = (words: string | null | undefined, t: string) => !!words && norm(words).length >= 2 && norm(t).includes(norm(words));
async function closePoints(repo: ReviewRepo, reviewId: string, points: RequestRow[], messageId: string) {
  await repo.closeRequests(points.map((p) => p.id), 'answered', messageId);
  await repo.pointsAnswered?.(reviewId);
}
async function answerPoints(repo: ReviewRepo, deps: ReviewDeps, l: Loaded, r: ReviewRow, t: string, sm: MessageRow, points: RequestRow[]): Promise<ThreadView> {
  const conversation = (await repo.messages(r.id)).filter((m) => m.id !== sm.id && (m.body ?? '').trim()).map((m) => ({ role: m.role === SEAT ? 'seat' as const : 'supplier' as const, text: String(m.body) }));
  const situation = stateFacts(l.inq, r, 'submitted', [], points.map((p) => p.label_en));
  const v = await deps.voice({ kind: 'text', supplierMessage: t, actions: [POINT_ACTION], situation, conversation })
    .catch(() => ({ text: '', action: null as string | null, action_words: null as string | null, outage: false, problems: [] as string[] }));
  if (v.action === POINT_ACTION.id && citedIn(v.action_words, t)) await closePoints(repo, r.id, points, sm.id);
  if (v.text) await repo.addMessage({ review_id: r.id, role: SEAT, kind: 'text', body: v.text, body_ar: null, attachments: [], issues: null });
  else await held(repo, deps, r.id, situation, t, v.outage === true, undefined, v.problems ?? []);
  return view(repo, deps, l.inq, await repo.review(l.inq.id, r.supplier_id));
}

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
  const t = typeof text === 'string' ? text.trim().slice(0, 2000) : '';
  const hasFile = !!file && typeof file.b64 === 'string' && !!file.b64;
  const points = l.r ? (await repo.requests(l.r.id, true)).filter((x) => x.code === POINT_CODE) : [];
  const bad = writableOr(l, l.r, deps.now(), points.length > 0 && !hasFile); if (bad) return bad;
  if (!t && !hasFile) return fail(400, 'text_required', 'Write a message.');
  if (hasFile) return messageWithFile(repo, deps, ctx, l, t, file!);
  const r = await ensure(repo, deps, ctx, l);
  const sm = await supplierSays(repo, r.id, 'text', t);
  const st = effectiveState(r, deps.now());
  // a submitted conversation: his text answers the comparison points, and nothing re-runs the review or changes the quotation
  if (st === 'submitted') return answerPoints(repo, deps, l, r, t, sm, points);
  const open = await openIssuesOf(repo, r);
  // The FIGURES and terms the supplier states are still PARSED by code (readReply's corrections: a format, not a
  // meaning), and a typed quotation still goes to the same reader. What the message MEANS — a choice, "submit it", a
  // question — is the model's to read, in the same call that writes the answer (1195-1197; no keyword routing).
  const corrections = readReply(t, open).corrections;
  // HE CONFIRMS WHAT WE READ (review of #1981, D5): his words are the model's to understand, in the same call that answers.
  const confirming = open.some((i) => i.code === 'reading_to_confirm') && !!r.working?.to_confirm?.length;
  // A price he states in words answers the reading's question about the price (review of #1981 N4): it is his figure now.
  // A VAT basis alone does not (N5: "9540 incl VAT" was read only as "prices include VAT", the question was cleared and
  // Submit sent 9,000): when he wrote a figure the rule reader did not take as a price, the model reads the message below.
  const priced = corrections.some((c) => ['price_ex_vat', 'total', 'line_price', 'boq_price'].includes(c.field));
  if (corrections.length && r.working && !(confirming && !priced && figuresIn(t).length)) {
    const took = tookSaid(corrections); if (took) await say(repo, deps, r.id, 'text', took, { supplierMessage: t });
    const w0 = priced && r.working.to_confirm?.length ? { ...r.working, to_confirm: [] } : r.working;
    await runReview(repo, deps, l.inq, r, applyCorrections(w0, corrections, l.inq.boq_rows), sm.id);
    return view(repo, deps, l.inq, await repo.review(inquiryId, ctx.supplierId));
  }
  if ((!r.working || st === 'awaiting_upload') && looksTyped(t, 1)) {
    // THE CHAT BOX IS ALSO THE TYPED PATH (finding SP-F-03): the same reader, the same review.
    return readTyped(repo, deps, ctx, l, r, t, sm.id);
  }
  // review of #1981 N4: he may also CORRECT the figure in words ("no, it is 9,540"); and a message about something else ("what
  // time is the site visit?") is neither: the model must cite his words, and code checks they are in his message.
  const stateActions = confirming ? [
    { id: 'confirm_reading', words: true, meaning: 'their message itself clearly says the figures we asked them to check are right, without changing any; a question, a message about anything else, or a "yes, but ..." that adds or changes something is NOT this' },
    { id: 'correct_price', words: true, value: 'amount' as const, meaning: 'their message gives the right price of the whole quotation EXCLUDING VAT, as a figure they wrote ("9540 + VAT", "9,540 before VAT")' },
    { id: 'correct_total_incl_vat', words: true, value: 'amount' as const, meaning: 'their message gives the right total of the whole quotation INCLUDING VAT, as a figure they wrote ("9540 incl VAT")' }]
    : st === 'awaiting_choice'
    ? [{ id: 'generate', meaning: 'they want us to generate the standardised quotation for them from what they sent' },
       { id: 'reupload', meaning: 'they will upload a new version of their own quotation' }]
    : st === 'ready_to_submit' ? [{ id: 'submit', meaning: 'they clearly tell us to submit the quotation to the customer now' }] : [];
  // the customer's comparison points, while any is open: his message may answer them (POINT_ACTION)
  const actions: { id: string; meaning: string; words?: boolean; value?: 'amount' }[] = [...stateActions, ...(points.length ? [POINT_ACTION] : [])];
  const pointLabels = points.map((p) => p.label_en);
  // THE THREAD SO FAR (browser proof, 2 Nov 2026): the model was given the review's state and this one message, never what the
  // supplier had already said, so "what lead time did I tell you?" was answered "nothing has come through". Every earlier
  // message of the thread rides as the conversation; the message just written is the one being answered.
  const conversation = (await repo.messages(r.id)).filter((m) => m.id !== sm.id && (m.body ?? '').trim()).map((m) => ({ role: m.role === SEAT ? 'seat' as const : 'supplier' as const, text: String(m.body) }));
  const v = await deps.voice({ kind: 'text', supplierMessage: t, actions, situation: stateFacts(l.inq, r, st, open, pointLabels), conversation })
    .catch(() => ({ text: '', action: null as string | null, action_words: null as string | null, action_value: null as string | null, outage: false, problems: [] as string[] }));
  // His words, checked by code: the cited words are in his message, and a corrected figure is a plain positive amount he wrote.
  const cited = citedIn(v.action_words, t);
  if (v.action === POINT_ACTION.id && points.length && cited) await closePoints(repo, r.id, points, sm.id);
  if (v.action === 'confirm_reading' && confirming && r.working && cited) {
    const w = { ...r.working, to_confirm: [], corrections: [...r.working.corrections, { field: 'reading_confirmed', value: String(v.action_words).slice(0, 200) }] };
    await runReview(repo, deps, l.inq, r, w, sm.id);
    return view(repo, deps, l.inq, await repo.review(inquiryId, ctx.supplierId));
  }
  const fig = (v.action === 'correct_price' || v.action === 'correct_total_incl_vat') && confirming && r.working && cited ? readFigure(v.action_value) : null;
  if (fig && fig.value != null && !fig.doubt && figuresIn(t).some((n) => Math.abs(n - fig.value!) < 0.005)) {
    // A total INCLUDING VAT (N5) is his figure too: the price before VAT is code's arithmetic at the UAE's 5%, shown back to him.
    const incl = v.action === 'correct_total_incl_vat';
    const ex = incl ? Math.round(fig.value / 1.05 * 100) / 100 : fig.value;
    const corr = [{ field: 'price_ex_vat' as const, value: ex }];
    const fmt = (n: number) => 'AED ' + n.toLocaleString('en-US', { maximumFractionDigits: 2 });
    if (incl) await say(repo, deps, r.id, 'text', { en: `Noted: your total is ${fmt(fig.value)} including VAT, which is ${fmt(ex)} before VAT. That is the price the customer will compare.`, ar: '' }, { supplierMessage: t });
    else { const took = tookSaid(corr); if (took) await say(repo, deps, r.id, 'text', took, { supplierMessage: t }); }
    const w = applyCorrections({ ...r.working!, to_confirm: [] }, corr, l.inq.boq_rows);
    await runReview(repo, deps, l.inq, r, incl ? { ...w, vat_amount: Math.round((fig.value - ex) * 100) / 100 } : w, sm.id);
    return view(repo, deps, l.inq, await repo.review(inquiryId, ctx.supplierId));
  }
  if (v.action === 'generate' || v.action === 'reupload') return decide(repo, deps, ctx, l, r, v.action, sm.id);
  if (v.action === 'submit') return doSubmit(repo, deps, ctx, l.inq, r, sm.id);
  if (v.text) await repo.addMessage({ review_id: r.id, role: SEAT, kind: st === 'awaiting_choice' ? 'choice_prompt' : 'text', body: v.text, body_ar: null, attachments: [], issues: null });
  else await held(repo, deps, r.id, stateFacts(l.inq, r, st, open), t, v.outage === true, undefined, v.problems ?? []);
  return view(repo, deps, l.inq, await repo.review(inquiryId, ctx.supplierId));
}

async function messageWithFile(repo: ReviewRepo, deps: ReviewDeps, ctx: Ctx, l: Loaded, t: string, file: { b64?: unknown; filename?: unknown; mime?: unknown }): Promise<ThreadView | Fail> {
  let sc: Scanned;
  try { sc = await deps.scan(String(file.b64), String(file.filename || 'attachment'), String(file.mime || '')); }
  catch (_e) { return fail(400, 'file_unreadable', 'We could not accept that file. Please attach it again.'); }
  if (!sc.ok) return fail(sc.status, sc.code, sc.message);
  const r = await ensure(repo, deps, ctx, l);
  // Reading a photo can take the vision model two askings; the read and what follows run off the request.
  const prior = await enterReview(repo, deps, r); if (prior == null) return BUSY;
  const path = `review/${ctx.supplierId}/${l.inq.id}/${deps.now().getTime()}_chat_${sc.name}`;
  if (!(await repo.storeFile(path, sc.bytes, sc.mime))) { await leaveReview(repo, r.id, prior); return fail(502, 'upload_failed', 'We could not store your file. Please try again.'); }
  const sm = await supplierSays(repo, r.id, 'file', t || null, [{ kind: 'chat_file', name: sc.name, bucket: 'quote-files', path }]);
  await offRequest(repo, deps, r.id, prior, async () => {
    const back = () => repo.updateReview(r.id, { status: prior, reviewing_since: null });
    let a: AttachmentRead;
    try { a = deps.readAttachment ? await deps.readAttachment(sc.bytes, sc.name, sc.mime) : await readEveryAttachment(sc.bytes, sc.name, sc.mime, null); }
    catch (e) { a = { status: 'unreadable', by: null, text: '', kind: 'error', model_attempts: 0, reason: String((e as Error)?.message || e).slice(0, 160), doc: null }; }
    await repo.log({ signal: 'quote_review_chat_file', status: a.status, by: a.by, model_attempts: a.model_attempts }, `Chat attachment ${a.status}${a.reason ? ': ' + a.reason : ''}.`);
    if (a.status !== 'read') {
      // HELD, never guessed: the file stays in the thread and the supplier is asked for a clearer copy, in English.
      await back();
      await say(repo, deps, r.id, 'notice', { en: clearerCopyAsk('supplier', 'en', sc.name), ar: '' }, { supplierMessage: t || null });
      return;
    }
    // A quotation photographed into the chat with nothing read yet goes to the review — only when the price reader finds
    // prices in it (a site photo's "2.4 m wide" is a number, not a quotation). That ONE reading is the review's reading:
    // before, it was read here and again in readTyped, two terms askings for one photo (measured live, 13 Oct 2026).
    const asText = transcriptAsText(a.text).slice(0, 20000);
    if ((!r.working || prior === 'awaiting_upload') && looksTyped(asText, 1)) {
      const q = await deps.read(new TextEncoder().encode(asText), 'chat_attachment.txt', 'text/plain').catch(() => null);
      if (q?.proposal) return typedJob(repo, deps, ctx, l, asText, sm.id, prior, q);
    }
    await back();
    const r1 = (await repo.review(l.inq.id, ctx.supplierId)) ?? r;
    const open = await openIssuesOf(repo, r1);
    const said = (t || '(they sent this file with no message)') + `\n\nThey attached "${sc.name}". What it says:` + untrustedBlock(a.text.slice(0, 6000));
    const pts = (await repo.requests(r1.id, true)).filter((x) => x.code === POINT_CODE).map((x) => x.label_en);
    const situation = stateFacts(l.inq, r1, prior, open, pts) + '\nThey attached a file with this message; what it says is in their message. Use it in your answer.';
    const v = await deps.voice({ kind: 'text', supplierMessage: said, situation, images: seenImage(sc.bytes, sc.mime) })
      .catch(() => ({ text: '', action: null as string | null, outage: false, problems: [] as string[] }));
    if (v.text) await repo.addMessage({ review_id: r.id, role: SEAT, kind: 'text', body: v.text, body_ar: null, attachments: [], issues: null });
    else await held(repo, deps, r.id, situation, said, v.outage === true, undefined, v.problems ?? []);
  });
  return view(repo, deps, l.inq, await repo.review(l.inq.id, ctx.supplierId));
}
