// supplier_api — quotations: template_list / template_save / template_delete, extract_quote, spec_hold / spec_fill /
// spec_approve, withdraw_quote, submit_quote.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,116-line index.ts split into modules, a pure move).
import { forSource, forSuppliers, readOwner } from '../what_a_supplier_receives.ts';
import { clearerCopyAsk } from '../../_shared/clearer_copy.ts';
import { timedFetch } from '../../_shared/timed_fetch.ts';
import { supabaseReviewRepo } from '../quote_review_flow.ts';
import { safeFilename, SAFE_DOCS } from '../../_shared/attachment.ts';
import { SUPPLIER_LOCALE } from '../../_shared/registered_locale.ts';
import { sanitizeAndScan } from '../../_shared/malware.ts';
import { defaultDeps } from '../../_shared/think.ts';
// The sales engineer's hold desk (14 Sep 2026): exact specs per line, delivery, installation,
// warranty and the ex-VAT price, or the quote is held; options are separate quotations.
import { approve, deskAssess, deskView, fillIn, formSchema, gate, gateInputKey, readAndAssess, supabaseRepo, type Ctx, type Precheck } from '../../_shared/line_specs/workflow.ts';
import { readQuote } from '../../_shared/reasoned_matching.ts';
import { requirementsOf } from '../../_shared/line_specs/assess.ts';
import { answerStands } from '../../_shared/line_specs/vat.ts';
import { optionAmount, splitOptions } from '../../_shared/line_specs/options.ts';
import { statedPrice, storedPrice } from '../../_shared/stated_price.ts';
import { quotationDateOf } from '../../_shared/quotation_date.ts';
import { findTrn } from '../../_shared/identity_numbers.ts';
import { deriveLineFields, deriveTermsFromScope } from '../../_shared/line_specs/derive.ts';
import { jobNo, readWorking, reviewQuotation, sanitizeSpec, sanitizeTermsSpec } from '../quote_review.ts';
import { carryHeldAnswers, heldAnswersOf, issueAsMissing, optionOfEach, releaseReview, resolvedFrom, withResolved, workingFromSubmit, type HeldAnswers } from '../submit_review.ts';
import { scrubDeep, scrubIdentity, scrubLine } from '../identity_scrub.ts';
import { cleanTemplate } from '../quote_template.ts';
import { newOptionRefusal } from '../new_option.ts';
import { type ActionCtx, J, SUPA_URL, admin, failed, logged, secretVal, tellItSeat } from '../context.ts';
import { maskContact } from '../../_shared/observe.ts';
import type { Recorded } from '../../_shared/recorded_write.ts';
import { CONCLUDED, UUID_RE, clip, numOrNull } from '../lib/fields.ts';
import { isRequestRevealed, REQUEST_REVEALED } from '../lib/request_revealed.ts';
import { NOT_MY_FILE, matchedInquiry, ownQuoteFile, sameVerdict, specChecklist } from '../lib/quote_gate.ts';
import { QUOTE_NOT_SAVED, QUOTE_NOT_SENT, QUOTE_NOT_SENT_APPROVE, type QuoteSnapshot, acceptForRelease, acceptLive, acceptRule, kickDelivery, notifyNewQuote, restoreQuote, snapshotQuote, storeReviewNotes, supersedeQualityHold, supplierOf, writeQuoteLines, writeQuoteRow } from '../lib/quote_acceptance.ts';
import { regenRender } from '../lib/arabic_quotation.ts';

export async function quoteActions(c: ActionCtx): Promise<Response | undefined> {
  const { req, jwt, email, body, action, safeInquiryOf } = c;
    // T3 QUOTE TEMPLATES (sales_engineer, 5 Oct 2026): structure a supplier reuses, never a price
    // (quote_template.ts refuses one; the table's CHECK refuses one again). Scoped to the caller's company.
    if (action === 'template_list' || action === 'template_save' || action === 'template_delete') {
      const { data: sup } = await admin.from('leads').select('id').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      const tbl = () => admin.from('supplier_quote_template');
      const unavailable = (e: { code?: string; message?: string } | null) => e && (e.code === '42P01' || /supplier_quote_template/.test(String(e.message || '')) && /does not exist|schema cache/.test(String(e.message || '')));
      if (action === 'template_save') {
        const c = cleanTemplate(body.template);
        if (!c.ok) return J({ error: c.message, code: c.code, message: c.message }, 400);
        const { data, error } = await tbl().upsert({ supplier_id: sup.id, ...c.template, updated_at: new Date().toISOString() }, { onConflict: 'supplier_id,name' }).select('id').maybeSingle();
        if (unavailable(error)) return J({ error: 'Templates are not available yet.', code: 'templates_unavailable' }, 503);
        if (error) return J({ error: error.code === '23514' ? 'A template cannot carry a price.' : 'Could not save the template.', code: error.code === '23514' ? 'template_has_price' : 'template_save_failed' }, 400);
        return J({ ok: true, id: data?.id });
      }
      if (action === 'template_delete') {
        const id = Number(body.id); if (!Number.isInteger(id)) return J({ error: 'not found', code: 'not_found' }, 404);
        const { error } = await tbl().delete().eq('id', id).eq('supplier_id', sup.id);
        if (unavailable(error)) return J({ error: 'Templates are not available yet.', code: 'templates_unavailable' }, 503);
        return error ? J({ error: 'Could not delete the template.', code: 'template_delete_failed' }, 500) : J({ ok: true });
      }
      const { data, error } = await tbl().select('id,name,line_headings,terms,warranty,validity,inclusions,exclusions,payment_terms,updated_at').eq('supplier_id', sup.id).order('name');
      if (unavailable(error)) return J({ ok: true, templates: [], unavailable: true });
      return error ? J({ error: 'Could not load templates.', code: 'template_list_failed' }, 500) : J({ ok: true, templates: data || [] });
    }
    if (action === 'extract_quote') {
      const { data: sup } = await admin.from('leads').select('id,company_name,approval_status,accepted_terms_at').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      // The enquiry must be one this supplier was matched to (finding SP-N-03). This also makes
      // inquiry_id a validated uuid before it is put into the storage path below, which it was not.
      const inquiry_id = await matchedInquiry(Number(sup.id), body.inquiry_id);
      if (!inquiry_id) return J({ error: 'not_found', code: 'not_found' }, 404);
      const images = Array.isArray(body.images) ? body.images : [];
      const orig = body.original || {};
      // 14 Sep 2026: a Word, Excel, email or zip quotation has no page images, but quote_extract can
      // now read the original itself (doc_read, no model). Only a request with neither is unreadable.
      if (!images.length && !orig.b64) return J({ error: 'Could not read the file pages. Please attach a clear PDF or photo.', code: 'quote_no_pages' }, 400);
      let original_file_path: string | null = null, original_file_name: string | null = null;
      // AUDIT 9.1 (3 Aug 2026). The supplier's original quotation document. It is stored and later
      // served back to admins and, on some paths, referenced to the customer. It had no type check
      // and defaulted to application/octet-stream, and the failure was swallowed - so a rejected or
      // failed upload silently produced a quote with no attached document.
      if (orig.path) {
        // Finding SP-N-04: a path the caller supplies is accepted only under this supplier's own prefix.
        if (!ownQuoteFile(orig.path, Number(sup.id))) return J(NOT_MY_FILE, 400);
        original_file_path = String(orig.path);
        original_file_name = safeFilename(orig.filename || 'quotation', 'application/pdf');
      } else if (orig.b64) {
        const sc = await sanitizeAndScan({ input: String(orig.b64), declaredMime: orig.mime, filename: orig.filename || 'quotation', allow: SAFE_DOCS,
                                           scan: { source: 'supplier_api.quotation', subject: String(sup.id), filename: orig.filename, bucket: 'quote-files' } });
        if (!sc.ok) return J({ ...sc.body, message: sc.body.error === 'malware_detected' ? sc.body.message : 'That quotation file cannot be accepted. Please attach a PDF, photo, Word, Excel or email file.' }, sc.status);
        const s = sc.result;
        original_file_name = safeFilename(orig.filename || 'quotation', s.mime);
        original_file_path = `quotes/${sup.id}/${inquiry_id}/${Date.now()}_${original_file_name}`;
        const up = await admin.storage.from('quote-files').upload(original_file_path, s.bytes, { contentType: s.mime, upsert: true });
        if (up.error) return J({ error: 'upload_failed', code: 'upload_failed', message: 'We could not store your quotation file. Please try again.' }, 502);
      }
      // The customer's summary reaches the quotation reader as context, and what that model writes is shown to THIS supplier
      // before any reveal: the supplier copy goes, never the raw column (13 Nov 2026, review of F2; what_a_supplier_receives.ts).
      const { data: inq0 } = await admin.from('inquiries').select('category,summary').eq('id', inquiry_id).maybeSingle();
      const owner = inq0?.summary ? await readOwner(admin, inquiry_id) : null;
      const inq = inq0 ? { category: inq0.category, summary: owner ? forSuppliers(String(forSource(String(inq0.summary), owner.resolved ? owner.briefSource : null)), owner) : null } : null;
      const secret = await secretVal('cred_fn_supplier_api');
      let jd: any = {};
      try { const r = await fetch(`${SUPA_URL}/functions/v1/quote_extract`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, subject: { supplier_id: (sup as any).id, email }, images, inquiry: inq || {}, ...(orig.b64 ? { file_b64: String(orig.b64), mime: String(orig.mime || ''), filename: String(orig.filename || 'quotation') } : {}), supplier_terms: [String((sup as any).company_name || '')].filter(Boolean) }) }); jd = await r.json(); } catch (e) { logged('quote_extract call', e); return J({ error: 'Reading failed, please try again or fill the form.', code: 'quote_read_failed' }, 502); }
      // Under the OpenRouter hold quote_extract has no model to call, so this is the expected path:
      // the code tells the portal to say "fill in the form", which is a complete way to quote.
      // RULING 1177 (12 Oct 2026): 'fill the form instead' was the answer to every quotation quote_extract could not price.
      // The original now goes through the read-every-attachment helper (the vision model transcribes it, the quotation
      // parser prices it, one more asking); only when that fails too is the supplier asked for a clearer copy, in English.
      // A total quote_extract held as ambiguous is the supplier's to state; no other reader is asked to guess it (#1562).
      if (jd?.error === 'total_ambiguous') return J({ error: 'total_ambiguous', code: 'quote_total_ambiguous', review_reason: jd.review_reason ?? null, proposal: jd.proposal ?? null, original_file_path, original_file_name, message: jd.review_reason === 'foreign_currency'
        // audit 10 Nov 2026: a quotation priced in USD/EUR/... is never read as AED and never converted on a guess
        ? 'Your quotation is priced in a currency other than AED. Customers compare quotations in AED: please type your AED total in the form.'
        : 'We read your quotation but could not be sure of its total (' + String(jd.review_reason || '').replace(/_/g, ' ') + '). Please type the total in the form.' }, 422);
      // THE MODEL READ IT, OR IT IS NOT READ YET (sales_engineer, 12 Nov 2026; founder rulings 1663/1664, LLM-first audit A2).
      // A quotation quote_extract's model could not read used to go through read_every_attachment here, where the vision
      // model transcribed it and the CODE parser priced it (ruling 1177, 12 Oct 2026). quote_extract now asks the model
      // first and gives it the file itself, so that second door only ever priced by code what the model had just declined:
      // a document it read as no quotation at all, or a file it could not be asked about. Neither is priced by code now.
      if (jd?.error === 'not_a_quotation') return J({ error: 'not_a_quotation', code: 'quote_not_a_quotation', proposal: null, message: 'This file does not look like a quotation for this request' + (jd.reason ? ' (' + String(jd.reason).slice(0, 160) + ')' : '') + '. Please attach your quotation, or type your total in the form.' }, 422);
      if (jd?.error === 'model_unavailable') { logged('quote_extract answer', `model_unavailable ${jd?.detail ?? ''}`); return J({ error: 'quote_reading_delayed', code: 'quote_read_delayed', retryable: true, message: 'We could not read your quotation just now. Please try again in a minute, or type your total in the form. Nothing has been sent to the customer.' }, 503); }
      if (!jd?.ok) { logged('quote_extract answer', `${jd?.error ?? 'no error'} ${jd?.detail ?? ''}`); return J({ error: 'quote_unreadable', code: 'quote_read_failed', message: clearerCopyAsk('supplier', 'en', String(orig.filename || 'your quotation'), false) }, 502); }
      // WHO READ IT (founder instruction ~891). The model quote_extract read this quotation with, kept per supplier and
      // inquiry so the quote submitted from it carries its author and quote_compare can be routed to another family.
      const readBy = typeof jd.extracted_by_model === 'string' && jd.extracted_by_model ? jd.extracted_by_model : 'unknown';
      const { error: xmErr } = await admin.from('quote_extraction_model').upsert({ subject_key: `${sup.id}:${inquiry_id}`, model: readBy, extracted_at: new Date().toISOString() });
      if (xmErr) console.error('quote_extraction_model: ' + xmErr.message);
      return J({ ok: true, proposal: jd.proposal, original_file_path, original_file_name });
    }
    // THE TWO WAYS OUT OF A HOLD (founder, 14 Sep 2026). (a) fill in the missing details here: the
    // sales engineer regenerates the standardised quotation and the supplier approves it, and only
    // then is it released; (b) upload a revised quote, which is submit_quote again and supersedes the
    // hold. Every step is the sales_engineer seat's (_shared/line_specs/workflow.ts).
    if (action === 'spec_hold' || action === 'spec_fill' || action === 'spec_approve') {
      const { data: sup } = await admin.from('leads').select('id,company_name,locale,whatsapp,phone').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      const qid = String(body.quote_id || '');
      if (!UUID_RE.test(qid)) return J({ error: 'not found', code: 'not_found' }, 404);
      const repo = supabaseRepo(admin, { dispatch: kickDelivery });
      const q = await repo.quote(qid);
      if (!q || Number(q.supplier_id) !== Number(sup.id)) return J({ error: 'not found', code: 'not_found' }, 404);
      const { data: inqRow } = await admin.from('inquiries').select('category,spec,rfq_no').eq('id', q.inquiry_id).maybeSingle();
      const { count: optCount } = await admin.from('quotes').select('id', { count: 'exact', head: true }).eq('inquiry_id', q.inquiry_id).eq('supplier_id', sup.id);
      // deno-lint-ignore no-explicit-any
      const spec: any = inqRow?.spec;
      const ctx = { category: inqRow?.category ?? null, requirements: requirementsOf(spec), ref: jobNo({ id: String(q.inquiry_id), rfq_no: inqRow?.rfq_no }), multiOption: (optCount || 0) > 1,
                    ...(await specChecklist(inqRow?.category ?? null, String(q.id), 'stored')) };
      const signed = async (b?: string | null, p?: string | null) => { if (!b || !p) return null; try { const { data } = await admin.storage.from(b).createSignedUrl(p, 3600); return data?.signedUrl || null; } catch (_e) { return null; } };
      // THE RELEASE CHECK, ONE FUNCTION FOR EVERY DOOR OF THE DESK (finding a of 10 Nov 2026; live re-run ea40c830).
      // spec_hold builds the form from it, spec_fill asks it before it says complete and spec_approve before it releases,
      // all through workflow.ts deskView. It reviews the STORED row with the supplier's desk answers (review of #854,
      // finding SP-F-02: by then the row, not any request, is the quotation), and it judges the exact specs with the
      // DESK's own inputs — the customer's requirements as the inquiry stores them and the trade's checklist — never the
      // supplier inbox's view of them, which the inbox withholds or scrubs (submit_review.ts releaseReview says why).
      const releaseCheck: Precheck = async (row, answers) => {
        const inqSafe = await safeInquiryOf(req, jwt, String(row.inquiry_id));
        // A transient inbox failure is NOT an approval and NOT a silent stranding: the desk stays
        // open with something the supplier can act on (try again), rather than closing on them.
        if (!inqSafe) return { missing: [{ scope: 'quote' as const, line_no: null, description: null, attr: 'review_unavailable', type: 'text' as const,
          label_en: 'We could not read this job just now, so we have not sent your quotation. Please confirm your approval again in a moment.',
          label_ar: 'تعذّر علينا قراءة هذا الطلب الآن، ولذلك لم نرسل عرضكم. يُرجى تأكيد الموافقة مرة أخرى بعد قليل.' }] };
        const rrow = await supabaseReviewRepo(admin).review(String(row.inquiry_id), Number(sup.id)).catch(() => null);
        return releaseReview(inqSafe, row, await repo.lines(String(row.id)), answers, { requirements: ctx.requirements, checklist: ctx.checklist }, resolvedFrom(rrow?.working));
      };
      if (action === 'spec_hold') {
        const { data: hs } = await admin.from('quote_spec_hold').select('id,state,missing,supplier_values,note_en,note_ar,regenerated,regenerated_at,pdf_bucket,pdf_path,opened_at,approved_at,released_at').eq('quote_id', qid).order('id', { ascending: false }).limit(1);
        const hold = hs?.[0] || null;
        const lines = await repo.lines(qid);
        // The form IS the release's question list: deskView asks the release check now, on the stored quote.
        const schema = hold && hold.state === 'open'
          ? (await deskView(q, lines, hold, ctx, releaseCheck)).schema
          : formSchema(deskAssess({ category: ctx.category, lines, terms: q, requirements: ctx.requirements, checklist: ctx.checklist }, q.validity), lines);
        const { supplier_values: _sv, ...shown } = hold || {};
        return J({ ok: true, quote_id: qid, option_no: q.option_no, hold: hold ? { ...shown, pdf_url: await signed(hold.pdf_bucket, hold.pdf_path) } : null, schema });
      }
      if (action === 'spec_fill') {
        // The regenerated quotation is the standard quotation (quoteDocument, via workflow.ts pdfBody) in
        // the supplier's own language, under the one alias this supplier carries on this job (the rule
        // quote_pdf above uses). Audit 22 Sep 2026, finding 1: it was a blank page.
        const render = regenRender(q, sup, inqRow);
        const out = await fillIn(repo, qid, supplierOf(sup, email), body.values && typeof body.values === 'object' ? scrubDeep(body.values, sup.company_name, []) as typeof body.values : {}, ctx, render, releaseCheck);
        if (!out.ok) return J({ ...out, error: out.code }, out.code === 'not_found' ? 404 : 400);
        if (out.complete) return J({ ...out, pdf_url: await signed(out.pdf?.bucket, out.pdf?.path) });
        return J(out);
      }
      // spec_approve RELEASES a held quote to the customer through approve() -> acceptLive(), so the review runs at
      // this door too (review of #854, finding SP-F-02). IT RUNS AS THE PRECHECK, NOT INSIDE accept (re-review of
      // #854). approve() marks the hold released before it calls accept, and liveHold() reads only 'open' and
      // 'awaiting_approval', so a refusal from inside accept left the quote unsent AND the hold desk shut. As a
      // precheck the hold goes back to 'open' carrying the review's own issues, which spec_hold now shows (finding a).
      // the write that sends it did not land (acceptLive, item A): approve() puts the hold back awaiting his approval and sends no
      // notice (third review, item 1), and he reads that it was not sent; pressing "Approve and send" again sends it
      const out = await approve(repo, qid, supplierOf(sup, email), email, body.confirm, ctx,
        acceptForRelease,
        releaseCheck);
      if (!out.ok && out.code === 'quote_not_sent') return J({ ok: false, error: 'quote_not_sent', ...QUOTE_NOT_SENT_APPROVE }, 503);
      if (!out.ok) return J({ ...out, error: out.code }, out.code === 'not_found' ? 404 : 409);
      return J(out);
    }
    // WITHDRAW BEFORE THE REVEAL (QA walk, 19 Oct 2026: the portal showed a "Withdrawn" status but gave the
    // supplier no way to reach it, and this function had no action for it). Only this supplier's own option,
    // only on an enquiry we sent them, only while it is a draft or with the customer and nobody has revealed
    // it. A revealed quote is the customer's paid decision and is never withdrawn from here.
    if (action === 'withdraw_quote') {
      const { data: sup } = await admin.from('leads').select('id').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      const { data: qt } = await admin.from('quotes').select('id,inquiry_id,status').eq('id', String(body.quote_id || '')).eq('supplier_id', sup.id).maybeSingle();
      if (!qt || !(await matchedInquiry(Number(sup.id), qt.inquiry_id))) return J({ error: 'not_found', code: 'not_found' }, 404);
      const { count: revealed } = await admin.from('transactions').select('id', { count: 'exact', head: true }).eq('quote_id', qt.id);
      if (revealed) return J({ error: 'This quotation was already revealed to the customer, so it can no longer be withdrawn.', code: 'already_revealed' }, 409);
      if (!['draft', 'submitted'].includes(String(qt.status))) return J({ error: 'This quotation cannot be withdrawn now.', code: 'not_withdrawable' }, 409);
      const { data: done, error: wErr } = await admin.from('quotes').update({ status: 'withdrawn' }).eq('id', qt.id).in('status', ['draft', 'submitted']).select('id');
      if (wErr) return J({ error: 'could_not_withdraw', code: 'could_not_withdraw' }, 500);
      return done?.length ? J({ ok: true, status: 'withdrawn' }) : J({ error: 'This quotation cannot be withdrawn now.', code: 'not_withdrawable' }, 409);
    }
    if (action === 'submit_quote') {
      // THE TYPED FORM NAMES ITS CURRENCY (sales_engineer, 13 Nov 2026, workflow audit build item 10): AED or nothing. The estate
      // has no FX source, so a non-AED total is refused with one plain sentence rather than converted or stored as if it were AED.
      // A caller that sends no currency (the upload chat, older pages) is unchanged: its file's currency is checked as before.
      if (body.currency != null && String(body.currency).trim().toUpperCase() !== 'AED') {
        return J({ error: 'QuotesDone compares and charges in UAE dirhams and does not convert currencies: please type your total in AED.', code: 'currency_not_aed' }, 400);
      }
      const { data: sup } = await admin.from('leads').select('id,company_name,locale,whatsapp,phone,accepted_terms_at,registration_status,approval_status,licence_gate_reason,rejection_reason').eq('claimed_by', email).maybeSingle();
      if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
      // FIRST, AND BEFORE ANYTHING ELSE IS SAID ABOUT THIS ACCOUNT: is this enquiry one we sent them?
      // (finding SP-N-03 — this door never asked.) Every read below is keyed on this id, not on the body's.
      const inquiryId = await matchedInquiry(Number(sup.id), body.inquiry_id);
      if (!inquiryId) return J({ error: 'not_found', code: 'not_found' }, 404);
      if (!sup.accepted_terms_at) return J({ error: 'accept the supplier terms first', code: 'terms_not_accepted' }, 400);
      // 3 SEP 2026 (MASTER_PLAN #11): there is no admin queue and never was - approval is the automatic
      // licence gate on save. Say what actually blocked it and what unblocks it, instead of promising a
      // human decision "within 3 working days" that nobody would ever make.
      if (sup.approval_status !== 'approved') {
        const why = String(sup.licence_gate_reason || sup.rejection_reason || '').trim();
        // 10 Nov 2026 (customer_support): the hold's reason is a code (licence_number_unread, services_unconfirmed, ...), never
        // a sentence, and only some of them are a licence to upload (the licence is in Documents, not Profile). The portal words
        // it from params.reason (serverCopy not_verified); this fallback says where to look instead of printing the code.
        return J({ error: why ? 'Your registration is not verified yet, so quotations cannot be sent. What is holding it, and what to do about it, is shown at the top of your supplier portal.' : 'Your registration is not verified yet. Upload a clear, in-date trade licence in the Documents tab - it is re-checked automatically the moment it is saved, with no admin step.', code: 'not_verified', params: { reason: why || null }, reason: why || null }, 403);
      }
      // AUDIT 4.2. This gate used to read the stored registration_status, which setRegistration()
      // set to 'due' on every supplier past the (off-by-one) free count regardless of the date -
      // blocking suppliers from quoting a year before the fee is contractually charged. It now
      // asks the single source of truth, and fails CLOSED on an unavailable answer rather than
      // silently opening the paywall.
      {
        const { data: regSt, error: regErr } = await admin.rpc('fn_supplier_registration_state', { p_lead_id: sup.id });
        const reg = regSt as any;
        if (regErr || !reg?.ok) { logged('submit_quote registration state', regErr ?? 'lead_not_found'); return J({ error: 'registration_state_unavailable', code: 'registration_state_unavailable', hint: 'We could not confirm your registration status. Please try again shortly.' }, 503); }
        if (reg.may_quote === false) return J({ error: 'Your ' + String(reg.currency || 'AED') + ' ' + Number(reg.fee_due || 0) + ' annual Subscription Fee is due. Please pay it in Billing to send quotes.', code: 'registration_due', params: { fee: Number(reg.fee_due || 0), currency: String(reg.currency || 'AED') }, registration: { status: reg.status, fee_due: reg.fee_due, currency: reg.currency, reason: reg.reason } }, 402);
      }
      const { data: inqStat } = await admin.from('inquiries').select('status').eq('id', inquiryId).maybeSingle();
      // FROM THE FIRST PAID REVEAL THE REQUEST TAKES NO NEW QUOTATIONS (sales_engineer, 13 Nov 2026): a supplier who already
      // quoted may revise or add an option; a new one is told plainly. The database holds every other door (trigger a05 on
      // quotes, a_paid_reveal_closes_the_request_and_everyone_on_it_is_told.sql).
      {
        const { data: paid } = await admin.from('transactions').select('id,refund_status').eq('inquiry_id', inquiryId).eq('fee_status', 'paid');
        const standing = ((paid || []) as { refund_status: string | null }[]).some((t) => !['refunded', 'succeeded'].includes(String(t.refund_status ?? '')));
        if (standing) {
          const { count: mine } = await admin.from('quotes').select('id', { count: 'exact', head: true }).eq('inquiry_id', inquiryId).eq('supplier_id', sup.id);
          if (!mine) return J(REQUEST_REVEALED, 409);
        }
      }
      if (inqStat && CONCLUDED.includes(String(inqStat.status))) return J({ error: 'This request has been concluded — the customer has already selected a supplier. Thank you for your interest, and best of luck on the next one.', code: 'inquiry_concluded' }, 409);
      const amt = Number(body.amount); if (!(amt > 0)) return J({ error: 'invalid amount', code: 'invalid_amount' }, 400);
      const isUpload = body.source === 'upload';
      const items = Array.isArray(body.items) ? body.items : [];
      // Free text the supplier typed. On the FORM path it goes through scrubIdentity (see the
      // helper's note, 27 Jul 2026) before it is ever stored, because these four columns are read
      // straight back out to the buyer pre-payment. The UPLOAD path is left as-is: quote_extract
      // already anonymised it and supplies its own masked_terms, so scrubbing twice would only
      // mangle text a model has already cleaned.
      // 15 Sep 2026 (security review): the UPLOAD path is scrubbed too. submit_quote is callable
      // directly, so "source: upload" was a way past scrubIdentity for text typed by hand, and under the
      // model hold the quotation review sends every upload down this path. scrubIdentity leaves text
      // that is already clean unchanged, so a quotation quote_extract anonymised is unaffected.
      const maskHits: string[] = [];
      const scrub = (v: unknown, n: number) => scrubIdentity(clip(v, n), sup.company_name, maskHits);
      // What the scope itself states is read into its columns (line_specs/derive.ts — audit 21 Sep
      // 2026, finding 15): "Exclusions: …" typed inside the scope, and "installation included".
      const fromScope = deriveTermsFromScope(body.scope, body.exclusions);
      const sNotes = scrub(body.notes, 1000), sScope = scrub(body.scope, 2000), sCond = scrub(body.conditions, 2000), sExcl = scrub(body.exclusions || fromScope.exclusions || '', 2000);
      const priorMasked: string[] = Array.isArray(body.masked_terms) ? body.masked_terms.map((x: unknown) => String(x)) : [];
      const allMasked = [...priorMasked, ...maskHits.filter((h) => !priorMasked.includes(h))];
      const { data: inqRow } = await admin.from('inquiries').select('category,spec,rfq_no').eq('id', inquiryId).maybeSingle();
      // deno-lint-ignore no-explicit-any
      const requirements = requirementsOf(inqRow?.spec);
      const category = inqRow?.category ?? null;

      // VAT (founder, 14 Sep 2026: supplier VAT details are hidden from the customer). The price the
      // customer compares and the 3% is taken on is the price EXCLUDING VAT; the supplier's VAT
      // treatment, VAT amount and TRN are kept on the quote for the record only (vat.ts).
      const vatText = [body.notes, body.scope, body.conditions, body.exclusions, body.payment_terms, body.vat_note, ...items.map((it: any) => it?.description)].filter(Boolean).map(String).join('\n');
      const trn = findTrn(vatText) || (/^100\d{12}$/.test(String(body.trn || '')) ? String(body.trn) : null);

      // OPTIONS (founder, 14 Sep 2026: "if a supplier wanted to share 2 options on his quote, they will
      // be considered two different quotations ... each will have its own ID in the system"). A
      // submission whose lines carry option headings becomes one quote row per option, sharing the
      // submission's commercial terms; a single-option submission targets option_no (1, the one it
      // is editing, or a new one when the supplier adds another option).
      const normItems = items.map((it: any) => ({ ...it, description: String(it?.description ?? ''), amount: numOrNull(it?.amount) ?? (((numOrNull(it?.qty) || 0) * (numOrNull(it?.unit_price) || 0)) || null) }));
      const opts = splitOptions(normItems, body.option_totals && typeof body.option_totals === 'object' ? body.option_totals : {});
      const multi = opts.length > 1;
      const { data: mine } = await admin.from('quotes').select('id,option_no,status').eq('inquiry_id', inquiryId).eq('supplier_id', sup.id);
      const maxOpt = Math.max(0, ...(mine || []).map((r: any) => Number(r.option_no) || 1));
      if (body.new_option === true) {
        const { count: revealedQuotes } = await admin.from('transactions').select('id', { count: 'exact', head: true }).eq('fee_status', 'paid').in('quote_id', (mine || []).map((r: any) => r.id).concat(['00000000-0000-0000-0000-000000000000']));   // only a PAID reveal counts: a failed or unpaid checkout never blocks an option
        const refusal = newOptionRefusal(body.new_option, revealedQuotes || 0);
        if (refusal) return J(refusal.body, refusal.status);
      }
      const single = Number(body.option_no) >= 1 ? Math.floor(Number(body.option_no)) : (body.new_option === true ? maxOpt + 1 : 1);
      const plan = multi ? opts.map((o) => ({ option_no: o.option_no, lines: o.lines, amount: optionAmount(o) })) : [{ option_no: single, lines: opts[0]?.lines ?? normItems, amount: amt as number | null }];
      if (plan.some((p) => p.option_no > 20)) return J({ error: 'A quote can carry at most 20 options.', code: 'too_many_options' }, 400);
      const noTotal = plan.find((p) => !(Number(p.amount) > 0));
      if (noTotal) return J({ error: 'Enter the total for option ' + noTotal.option_no + '.', code: 'option_total_missing', params: { option: noTotal.option_no } }, 400);
      // Finding SP-N-04: the attached quotation file must be one of this supplier's own objects.
      const origPath = body.original_file_path == null || String(body.original_file_path) === '' ? null : String(body.original_file_path);
      if (origPath && !ownQuoteFile(origPath, Number(sup.id))) return J(NOT_MY_FILE, 400);

      // AN ANSWERED HOLD ITEM IS NEVER ASKED AGAIN (defect F5, production walk of 10 Nov 2026). What the supplier
      // answered in the hold panel lives on the quote row this submission overwrites (its terms_spec, its lines'
      // spec, its validity). A price refresh from the form carries none of it, so the review below asked
      // `installation_included` again with no panel to answer it on. Read only from THIS supplier's rows on THIS
      // job for the options being written (submit_review.ts heldAnswersOf / carryHeldAnswers). A read that fails
      // carries nothing: the review then asks, as it did before.
      const priorIds = ((mine || []) as { id: unknown; option_no: unknown }[]).filter((r) => plan.some((p) => p.option_no === (Number(r.option_no) || 1))).map((r) => String(r.id));
      const held: HeldAnswers[] = [];
      if (priorIds.length) {
        try {
          const [hq, hl, hh] = await Promise.all([
            admin.from('quotes').select('id,inquiry_id,supplier_id,option_no,validity,terms_spec').in('id', priorIds).eq('supplier_id', sup.id),
            admin.from('quote_items').select('quote_id,description,spec,spec_source').in('quote_id', priorIds),
            admin.from('quote_spec_hold').select('quote_id,supplier_values').in('quote_id', priorIds),
          ]);
          if (!hq.error && !hl.error && !hh.error) for (const q of hq.data || []) { const h = heldAnswersOf({ inquiry_id: String(inquiryId), supplier_id: Number(sup.id) }, q, hl.data || [], hh.data || []); if (h) held.push(h); }
          else logged('submit_quote held answers', hq.error ?? hl.error ?? hh.error);
        } catch (e) { logged('submit_quote held answers', e); }
      }
      const carry = carryHeldAnswers(body, held, optionOfEach(normItems, plan), plan.map((p) => p.option_no));
      const sent = carry.body;
      // The stored lines get the carried specs too (plan's lines are these same objects), so the gate reads what the review read.
      (Array.isArray(sent.items) ? sent.items as ({ spec?: unknown } | null)[] : []).forEach((it, i) => { if (normItems[i] && it && it.spec !== items[i]?.spec) normItems[i].spec = it.spec; });

      // ── THE QUOTATION REVIEW RUNS AT EVERY DOOR (audit 22 Sep 2026, finding SP-F-02) ────────────
      // The founder, 15 Sep 2026: the review is "the most important part in the whole supplier portal".
      // Its rules live in quote_review.ts reviewQuotation — every BOQ line priced, quantities and units
      // matching the BOQ, prices in AED, the VAT basis stated, the lines adding up to the total, a
      // concrete validity, and the hold desk's own exact-specs assessment — and until now they ran ONLY
      // inside the chat. Two portal doors post to submit_quote directly (InquiriesTab -> QuoteForm, and
      // the Quote Builder's one-click accept), so a quotation that failed any of rules 1-7 reached the
      // customer through them.
      //
      // IT IS A HOLD, NOT A REFUSAL, and that correction matters (review of #854): a hard 400 would have
      // taken both quoting doors offline, because neither form has a field for several of the details
      // the review asks for. The quote is still written and still recoverable — exactly what the hold
      // desk already does — it simply never reaches the customer until the review passes. QuoteForm
      // already renders `held`, and the two ways out (spec_fill here, or a revised quotation through the
      // chat) are unchanged.
      //
      // WHAT THE SUPPLIER ALREADY EXPLAINED STILL COUNTS. A BOQ line the chat recorded as excluded, or a
      // quantity the supplier explained, lives in quote_reviews.working — written by the engineer, not by
      // the caller — so it is read from the row and never from the request body. A supplier posting
      // straight to this endpoint has no such row, and every rule applies to them in full.
      const confirmedTerms = (() => { const t = sanitizeTermsSpec(sent.terms_spec); return t ? scrubDeep(t, sup.company_name, maskHits) as typeof t : t; })();
      const reviewRow = await supabaseReviewRepo(admin).review(inquiryId, Number(sup.id)).catch(() => null);
      // His VAT answer, never the caller's: the hold desk's on an earlier submission of these options (carryHeldAnswers), else
      // the chat's (quote_reviews.working). It settles the basis for the review AND for the price stored below, but only while
      // this submission states that same basis (vat.ts answerStands): the chat's "before VAT" was otherwise asked again here.
      const resolved0 = resolvedFrom(reviewRow?.working);
      const resolved = { ...resolved0, vat_answered: carry.vat_answered ?? resolved0.vat_answered ?? null };
      const vatAnswered = answerStands(resolved.vat_answered, body.vat_treatment ? String(body.vat_treatment) : null);
      const safeInq = await safeInquiryOf(req, jwt, inquiryId);
      if (!safeInq) return J({ error: 'not_found', code: 'not_found' }, 404);
      // Read as the hold gate reads it (reasoned_matching.ts); held: nothing is read and every detail is asked. Its exact
      // specs are judged with the requirements the gate judges them with (the inquiry's own, not the inbox's view of them):
      // the review hold and the spec hold of one submission ask the same (live re-run ea40c830, 10 Nov 2026).
      const rv = reviewQuotation(safeInq, await readWorking(defaultDeps(admin, 'supplier_api'), safeInq, withResolved(
        workingFromSubmit(sent, { notes: String(sNotes ?? ''), scope: String(sScope ?? ''), conditions: String(sCond ?? ''), exclusions: String(sExcl ?? '') }, confirmedTerms || {}, allMasked, trn),
        resolved), 'review:' + safeInq.id + ':' + sup.id), new Date(), { requirements });
      const lang: 'en' | 'ar' = SUPPLIER_LOCALE;
      const reviewIssues = rv.approved ? null : rv.issues.map((i) => ({ code: i.code, kind: i.kind, line_no: i.line_no, boq_line: i.boq_line, attr: i.attr, en: i.en, ar: i.ar }));
      const reviewMissing = rv.approved ? [] : rv.issues.map(issueAsMissing);
      const reviewMessage = reviewIssues ? rv.issues.slice(0, 3).map((i) => (lang === 'ar' ? i.ar : i.en)).join(' ') : null;

      // The quote's author for quote_compare's independence routing: a typed quote has no model author; an uploaded one
      // carries the model quote_extract read it with (recorded at 'extract'), or 'unknown', which fails closed.
      // body.source is the client's word, so it never decides this (#880 review, item 2): the server's own extraction
      // record does. A record => its model; an upload with no record => 'unknown' (fails closed); otherwise typed by a person.
      const { data: xm } = await admin.from('quote_extraction_model').select('model').eq('subject_key', `${sup.id}:${inquiryId}`).maybeSingle();
      const quoteAuthor = typeof xm?.model === 'string' && xm.model ? xm.model : (isUpload ? 'unknown' : 'deterministic');
      const submission_id = crypto.randomUUID();
      const repo = supabaseRepo(admin, { dispatch: kickDelivery });
      const supplier = supplierOf(sup, email);
      const ref = jobNo({ id: String(inquiryId), rfq_no: inqRow?.rfq_no });
      const multiOption = multi || single > 1 || (mine || []).length > 1;
      const results: any[] = [];
      let anyAccepted: string | false = false;   // the first live quote of this submission, or false
      for (const p of plan) {
        // Rulings 1207/1208: the supplier's discount and VAT exactly as stated; price_ex_vat (and quote_amount, which the
        // reveal fee reads) is the price AFTER the stated discount, excluding VAT — never the gross (_shared/stated_price.ts).
        const vat = statedPrice({ amount: p.amount, subtotal: multi ? null : numOrNull(body.subtotal), vat_amount: multi ? null : numOrNull(body.vat_amount), text: vatText,
          stated: body.vat_treatment ? String(body.vat_treatment) : null, price_ex_vat: multi ? null : numOrNull(body.price_ex_vat),
          gross_amount: multi ? null : numOrNull(body.gross_amount), discount_amount: multi ? null : numOrNull(body.discount_amount),
          discount_label: multi ? null : clip(body.discount_label, 80), net_amount: multi ? null : numOrNull(body.net_amount),
          // The supplier's own lines and TRN are evidence of the VAT basis (line_specs/vat.ts, accountant 15 Nov 2026): a total
          // that is exactly his lines plus 5% has VAT in it, whatever the form's basis said, so the review asks before any fee.
          lines_sum: multi ? null : (p.lines as { amount?: unknown }[]).reduce((a, l) => a + (Number(l?.amount) > 0 ? Number(l.amount) : 0), 0),
          lines_count: multi ? null : (p.lines as { amount?: unknown }[]).filter((l) => Number(l?.amount) > 0).length, trn, answered: vatAnswered });
        const qDate = quotationDateOf(body.quotation_date);
        const det = { inquiry_id: inquiryId, supplier_id: sup.id, option_no: p.option_no, submission_id, ...storedPrice(vat, p.amount), supplier_trn: trn,
          discount_label: vat.discount_label ? scrub(vat.discount_label, 80) : null,
          notes: sNotes, lead_time: scrub(body.lead_time, 200), validity: scrub(body.validity, 200),
          // Ledger 1697: the date printed on his quotation, when it was read for certain; his stated validity counts from it
          // (fn_quote_validity_until), else from the day received. No validity of ours is ever written here. The key is written
          // only with a date, and writeQuoteRow drops it once if the column is not applied yet (deploy before the SQL).
          ...(qDate ? { quotation_date: qDate } : {}), payment_terms: scrub(body.payment_terms, 400), warranty: scrub(body.warranty, 200), scope: sScope, conditions: sCond, exclusions: sExcl, source: isUpload ? 'upload' : 'form', extracted_by_model: quoteAuthor, anonymized: true, original_file_path: origPath, original_file_name: body.original_file_name || null, masked_terms: (() => { const m = [...allMasked, ...maskHits.filter((h) => !allMasked.includes(h))]; return m.length ? m : null; })(), structured: p.lines.length > 0 };
        // Delivery / installation / warranty the supplier confirmed in the quotation review, cleaned
        // (quote_review.ts) — the hold gate reads them exactly as it reads the portal's fill-in.
        if (confirmedTerms) (det as Record<string, unknown>).terms_spec = confirmedTerms;
        // A row whose answers were read is written with exactly what this submission states plus the answers carried
        // (F5): the hold gate reads the row, so it must hold what the review read — no more, no less.
        const own = carry.options[String(p.option_no)];
        if (own?.held) { const t = sanitizeTermsSpec(own.terms_spec); (det as Record<string, unknown>).terms_spec = t ? scrubDeep(t, sup.company_name, maskHits) : null; }
        if (own?.held && !String(body.validity ?? '').trim() && own.validity) det.validity = scrub(own.validity, 200);
        // Capture the status BEFORE the write. A new row is created as a draft, never in the
        // 'submitted' column default: a dry_run preflight or a held quote must not be visible to the
        // customer even for a moment (caught by a demo walkthrough on 21 Jul 2026).
        const prior = (mine || []).find((r: any) => (Number(r.option_no) || 1) === p.option_no) || null;
        // A DRY RUN LEAVES THE ESTATE AS IT FOUND IT (audit 22 Sep 2026, finding SP-C-02). "Check before
        // sending" reached the dry-run branch AFTER the writes below: it updated the prior quote row with
        // whatever was on screen, deleted its lines and re-inserted the new ones, and then restored only
        // `status`. A check run on a reopened quote that had already been sent therefore REWROTE the sent
        // quotation — amount, terms and every line — and a check on a new option left a draft behind. The
        // scorer, the accept rule and the hold assessment all read the row by id, so the row must exist
        // while they run; what must not survive is the change. The row and its lines are snapshotted here
        // and put back below, and a snapshot we could not take refuses the check rather than risking it.
        const dryRun = body.dry_run === true;
        const snapCols = [...Object.keys(det), 'status', 'submittable'].join(',');
        // EVERY prior quotation is snapshotted, not only a check's (third review, item 4): a re-sent quotation whose new lines cannot be
        // written is put back as it stood, so the customer never sees its new header over no lines.
        let snap: QuoteSnapshot | null = null;
        if (prior) {
          snap = await snapshotQuote(String(prior.id), snapCols);
          for (const c of snap?.dropped || []) delete (det as Record<string, unknown>)[c];   // its column is not applied yet
          if (!snap && dryRun) return J({ error: 'preflight_unavailable', code: 'preflight_unavailable', message: 'We could not run the check just now. Please try again in a moment.' }, 503);
          if (!snap) return J({ ok: false, error: 'quote_not_saved', ...QUOTE_NOT_SAVED }, 503);   // nothing written yet
        }
        let qid: string;
        if (prior) { const { error } = await writeQuoteRow(det, (d) => admin.from('quotes').update(d).eq('id', prior.id)); if (error) return failed(String(action), error); qid = String(prior.id); }
        else { const { data: ins, error } = await writeQuoteRow(det, (d) => admin.from('quotes').insert({ ...d, status: 'draft' }).select('id').single()); if (error && (error as { code?: string }).code === '23505') return J({ error: 'This option was just saved from another click or tab. Refresh to see it.', code: 'option_exists' }, 409); if (error && isRequestRevealed(error)) return J(REQUEST_REVEALED, 409); if (error) return failed(String(action), error); qid = String(ins.id); }
        let linesW: Recorded;
        try {
          // A line's own words fill brand / model / specification where the caller sent none; a scope
          // that says installation is included, with no line carrying a labour or install figure, marks
          // the first line install = 0 — "included in the rate" — so the scorer's labour-or-installation
          // count reads what the supplier wrote (derive.ts, finding 15).
          const anyInstall = p.lines.some((it: any) => numOrNull(it.labour) != null || numOrNull(it.install) != null);
          const rows = p.lines.slice(0, 80).map((raw: any, i: number) => { const it = scrubLine(raw, sup.company_name, maskHits); const dv = deriveLineFields(it); return { quote_id: qid, line_no: i + 1, description: clip(it.description, 300), brand: clip(it.brand || dv.brand, 120), model: clip(it.model || dv.model, 120), specification: clip(it.specification || dv.specification, 800), qty: it.quantity != null ? numOrNull(it.quantity) : (it.qty == null ? null : numOrNull(it.qty)), unit: clip(it.unit, 40), unit_price: it.unit_price == null ? null : numOrNull(it.unit_price), labour: numOrNull(it.labour), install: numOrNull(it.install) ?? (i === 0 && !anyInstall && fromScope.installation_included ? 0 : null), commissioning: numOrNull(it.commissioning), amount: numOrNull(it.amount) ?? ((numOrNull(it.qty) || 0) * (numOrNull(it.unit_price) || 0) || null), country_of_origin: clip(it.country_of_origin, 80), notes: clip(it.notes, 300), ...(() => { const s = sanitizeSpec(it.spec); return Object.keys(s.spec).length ? { spec: s.spec, spec_source: s.source } : {}; })() }; });
          // A line item with no description is dropped, not stored blank - a quote line the buyer
          // cannot read is worse than one that is absent.
          const clean = rows.filter((r: { description: string | null }) => r.description);
          // THE LINES ARE SAVED, OR HE IS TOLD THEY WERE NOT (15 Nov 2026, review 2 of the certificate branch, item B). This delete and
          // insert sat in a try/catch that supabase-js never enters, so a lock or a timeout left the quotation with its old lines or none
          // and the submission answered ok. writeQuoteLines checks both, and tries the pair again on a blip (delete then insert, so a
          // retry after an insert whose answer was lost never doubles a line).
          linesW = await writeQuoteLines(qid, clean);
        } catch (e) { linesW = { ok: false, attempts: 1, reason: String((e as Error)?.message ?? e).slice(0, 300), blip: false }; }
        // Put the row back exactly as it was (restoreQuote: the snapshotted columns and lines, with their own ids, so anything that
        // references a line still does). A row a check CREATED is removed.
        const restore = async (): Promise<boolean> => {
          if (snap) return await restoreQuote(qid, snap);
          try {
            const d = await admin.from('quote_items').delete().eq('quote_id', qid);
            const dq = await admin.from('quotes').delete().eq('id', qid);
            return !d.error && !dq.error;
          } catch (_e) { return false; }
        };
        if (!linesW.ok) {
          // a check is always undone; a submission over a prior quotation puts it back as it stood (its first submission stays a draft)
          const restored = dryRun || snap ? await restore() : null;
          tellItSeat('quote_lines_not_saved', "supplier_api could not save a supplier's quotation lines, so the submission was refused",
            'edge function supplier_api, action submit_quote', { quote_id: qid, inquiry_id: inquiryId, option_no: p.option_no, prior_status: prior?.status ?? null,
              dry_run: dryRun, restored, attempts: linesW.attempts, reason: maskContact(linesW.reason).slice(0, 300),
              told: dryRun ? 'the check was refused (preflight_unavailable)' : 'the supplier was told his quotation was not sent (quote_not_saved); nothing was let through'
                + (snap && !dryRun ? (restored ? '; the prior quotation was put back as it stood' : '; the prior quotation could NOT be put back: restore it from snapshot by hand') : '') });
          if (dryRun && !restored) return J({ error: 'preflight_restore_failed', code: 'preflight_restore_failed', quote_id: qid, message: 'The check could not be undone cleanly and we have raised it. Please do not resend until we confirm.' }, 500);
          if (dryRun) return J({ error: 'preflight_unavailable', code: 'preflight_unavailable', message: 'We could not run the check just now. Please try again in a moment.' }, 503);
          if (anyAccepted) await notifyNewQuote(String(inquiryId), anyAccepted);   // an earlier option of this submission did go live
          return J({ ok: false, error: 'quote_not_saved', ...QUOTE_NOT_SAVED, quote_id: qid, options: results.length ? results : undefined }, 503);
        }
        // Preflight (dry_run). Runs the real scorer, the real accept rule and the real hold gate's
        // assessment, then stops: the status is put back as it was, nothing is notified, no hold opens.
        // The gate's own context: the same checklist, the same settled readings, the same assessment (workflow.ts
        // readAndAssess), so "check before sending" and the submission give one verdict for one quotation.
        const gctx: Ctx = { category, requirements, ref, multiOption, ...(await specChecklist(category, qid)),
          // His quotation is READ by reasoning before the check (decision points 29-30); held: nothing is read and he is asked.
          read: (qr, ls) => readQuote(defaultDeps(admin, 'supplier_api'), { quoteId: qid, category, lines: ls, terms: qr, requirements }) };
        const gkey = await gateInputKey((await repo.quote(qid))!, await repo.lines(qid), gctx);
        if (dryRun) {
          const acc = await acceptRule(qid);
          const { a, settled } = await readAndAssess(repo, qid, gctx);
          await sameVerdict(gkey, a, settled, qid, 'preflight');
          // Put it back exactly as it was (restore, above).
          const restored = await restore();
          // A FAILED RESTORE IS AN INCIDENT, NOT A FIELD ON A 200 (review of #854). Until this line it
          // answered ok:true with restored:false and a console line nobody reads, so a SENT quotation
          // could be left with its lines deleted and its terms overwritten and nothing would page. It
          // now writes an agent_runs error row — observe() pages those — and answers 500.
          if (!restored) {
            console.error('submit_quote dry_run: could not restore quote', qid);
            try {
              await admin.from('agent_runs').insert({ agent: 'supplier_api', status: 'error', started_at: new Date().toISOString(), finished_at: new Date().toISOString(),
                counts: { signal: 'dry_run_restore_failed', quote_id: qid, supplier_id: sup.id, inquiry_id: inquiryId, had_prior: !!prior, lines: snap?.lines.length ?? 0 },
                note: ('submit_quote dry_run could not restore quote ' + qid + ' after the preflight. The row may hold the checked figures instead of the ones the supplier sent. Restore it from this row.').slice(0, 500) });
            } catch (_e) { /* the page must not be what breaks the response */ }
            return J({ error: 'preflight_restore_failed', code: 'preflight_restore_failed', quote_id: qid, message: 'The check could not be undone cleanly and we have raised it. Please do not resend until we confirm.' }, 500);
          }
          results.push({ quote_id: qid, option_no: p.option_no, dry_run: true, accepted: false, restored, submittable: acc.submittable, would_accept: acc.accept && !a.held && !reviewIssues, review_issues: reviewIssues, status_after: prior?.status ?? null,
            accept_via: acc.submittable ? 'structured_score' : (acc.formComplete ? 'form_complete' : (!acc.requireStructured ? 'structured_not_required' : null)),
            require_structured: acc.requireStructured, priced_items: acc.priced, total_items: p.lines.length, score: acc.score,
            // The preflight card reads spec_missing, so the review's own issues belong in it for the
            // same reason (re-review of #854) — otherwise "Check before sending" calls a quote that
            // will be held a complete one.
            spec_missing: [...a.missing, ...reviewMissing], would_hold: a.held || !!reviewIssues });
          continue;
        }
        // THE HOLD GATE (founder, 14 Sep 2026). The sales engineer holds a quote that does not state
        // every required detail exactly, records which line and which detail, and tells the supplier.
        const g = await gate(repo, qid, supplier, gctx);
        await sameVerdict(gkey, g.assessment, g.settled, qid, 'submission');
        // a submission the door did not accept never inherits the wait of an earlier accepted one (review of #1108)
        if (g.held) { await supersedeQualityHold(qid); results.push({ quote_id: qid, option_no: p.option_no, accepted: false, held: true, missing: g.missing, code: 'spec_hold' }); continue; }
        // THE REVIEW'S OWN RULES, held the same way (finding SP-F-02). The gate above is the exact-specs
        // assessment; these are rules 1-7 — the BOQ priced line by line, quantities and units, prices in
        // AED, the VAT basis, the lines adding up, a concrete validity — which no door but the chat ran.
        // The quote stays a draft the supplier can complete or replace; it does not reach the customer.
        if (reviewIssues) {
          try { await admin.from('quotes').update({ status: 'draft' }).eq('id', qid); } catch (_e) { /* the result below already says it was not accepted */ }
          await supersedeQualityHold(qid);
          // THE CARD ALREADY KNOWS HOW TO SHOW THIS (re-review of #854). The portal renders a held
          // quote from `missing` / `spec_missing` — assess.ts MissingItem — and a review hold carried
          // neither, so QuoteCheck printed "Nothing missing — this is a complete quote." over a quote
          // that had just been held. The issues now go out in BOTH shapes: `missing` for every surface
          // that already reads it, `review_issues` for a client that wants the codes.
          results.push({ quote_id: qid, option_no: p.option_no, accepted: false, held: true, code: 'quote_review_changes', missing: reviewMissing, review_issues: reviewIssues, message: reviewMessage });
          continue;
        }
        const live = await acceptLive(qid, String(inquiryId), false);
        if (live.accepted) { anyAccepted = anyAccepted || qid; await storeReviewNotes(qid, String(inquiryId)); }
        results.push({ quote_id: qid, option_no: p.option_no, held: false, ...live });
      }
      if (anyAccepted) await notifyNewQuote(String(inquiryId), anyAccepted);   // one notice per submission, named by its first live quote
      // an option whose sending write did not land (acceptLive, item A) is said, never answered ok
      if (body.dry_run !== true && results.some((r) => r.not_sent)) return J({ ok: false, error: 'quote_not_sent', ...QUOTE_NOT_SENT, options: multi ? results : undefined, quote_id: multi ? undefined : results[0]?.quote_id }, 503);
      if (multi) return J({ ok: true, options: results, submission_id, accepted: results.some((r) => r.accepted), held: results.some((r) => r.held), dry_run: body.dry_run === true, code: 'options_split', params: { count: results.length } });
      const r0 = results[0];
      const q = { id: r0.quote_id, option_no: r0.option_no, status: r0.accepted ? 'submitted' : 'draft' };
      if (body.dry_run === true) return J({ ok: true, ...r0 });
      if (r0.held) return J({ ok: true, quote: q, accepted: false, held: true, missing: r0.missing ?? null, review_issues: r0.review_issues ?? null, code: r0.code || 'spec_hold',
        message: r0.message || 'Your quote is on hold until the exact details listed are stated. Fill them in here or upload a revised quote.' });
      if (r0.accepted) return J({ ok: true, quote: q, submittable: r0.submittable, accepted: true, coaching: r0.coaching, score: r0.score });
      return J({ ok: true, quote: q, submittable: false, accepted: false, coaching: r0.coaching, score: r0.score, code: 'draft_saved', message: 'Your quote was saved as a draft. Add the missing details so we can send it to the customer.' });
    }
}

/** The e-mailed quotation's reading is cut here (inside resend_inbound's 100 s bound). */
export const QUOTE_READ_DEADLINE_MS = 95_000;
/** quote_extract (the model) with supplier_api's own credential: the e-mailed quotation's reading (email_quote.ts,
 *  12 Nov 2026). A call that fails is 'model_unavailable': the quotation stays unread, never priced by code. */
export async function askQuoteExtract(body: Record<string, unknown>): Promise<Record<string, unknown>> {
  try {
    const secret = await secretVal('cred_fn_supplier_api');
    // A deadline inside resend_inbound's 100 s read bound (resend_inbound/steps/supplier_docs.ts): a slow model is 'model_unavailable'
    // (the e-mail is 'unread'), never a hang; quote_extract p90 30 s (ai_cost_log, 30 days to 12 Nov 2026).
    const r = await timedFetch(`${SUPA_URL}/functions/v1/quote_extract`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ ...body, __secret: secret }) }, QUOTE_READ_DEADLINE_MS);
    return await r.json().catch(() => ({ ok: false, error: 'model_unavailable', detail: 'http ' + r.status }));
  } catch (e) { logged('quote_extract call (e-mail)', e); return { ok: false, error: 'model_unavailable' }; }
}
