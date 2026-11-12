// resend_inbound step: a supplier's documents: store, classify, auto-extract, apply; then the inbound record and the reply. Moved out of index.ts's handler unchanged (9 Nov 2026);
// the handler in index.ts calls the steps in the order they ran inline, each handing on what the next one reads.
import type { Out as ReceiptsOut } from './receipts.ts';
import { clearerCopyAsk } from '../../_shared/read_every_attachment.ts';
import { timedFetch } from '../../_shared/timed_fetch.ts';
// in the database's region, not Resend's (email_triage measured us-east-1 p50 4.7 s; it_engineer, 10 Nov 2026)
import { inDbRegion } from '../../_shared/db_region.ts';
import { paidProviderGate } from '../../_shared/paid_gate.ts';
import { SAFE_UPLOAD } from '../../_shared/attachment.ts';
import { sanitizeAndScan } from '../../_shared/malware.ts';
import { requestDelivery } from '../../_shared/deliver.ts';
import { exchangeInternal, stampHeaders, senderAuthenticated } from '../../_shared/suppression_policy.ts';
import { classifyPrompt, leadWritable } from '../supplier_doc_gate.ts';
import { licenceNameFromModel } from '../../_shared/document_expiry.ts';
import { type LeadWriter, updateLeadSettingAsideClashingLicence } from '../../_shared/duplicate_company.ts';
import { orSafeEmail } from '../../_shared/or_filter_email.ts';
import { admin, SUPA_URL, J, MODEL, classify, sec, logRun } from '../lib/runtime.ts';
import { parseJson, bytesToB64 } from '../lib/mail_parse.ts';
import { fetchInboundEmail, attachmentBytes, extractDoc } from '../lib/inbound_fetch.ts';
import { SYS } from '../lib/classify_prompt.ts';
import { SAFE_DOCS } from '../../_shared/attachment.ts';
import { isClosedRequest } from '../../_shared/request_closed.ts';
import { quoteByEmail, type MailFile, type OpenRequest } from '../quote_by_email.ts';

export async function supplierDocs(ctx: ReceiptsOut) {
    const { hdrs, resendEmailId, rkey, providerEmailId, from, atts, emailId, key, subject, text, inbSecret, d, to, fullText, fullHtml, receiptish, reasoningHeld, handToBookkeeper, receiptReason, owner } = ctx;
    // WHO SENT IT IS PROVEN, NOT READ OFF THE FROM HEADER (customer_support, 19 Oct 2026, review of #1498): email_triage
    // gives a reply the sender's own account only when the receiving server authenticated the From domain (aligned
    // DMARC, DKIM or SPF pass, fromDomainAuthenticated). The webhook is metadata-only, so the headers are read when absent.
    // Read here, before the documents, since 3 Nov 2026: a licence is written only for an authenticated sender (supplier_doc_gate.ts).
    const authHdrs = hdrs?.['authentication-results'] ? hdrs : ((resendEmailId && rkey) ? await (async () => { const f: any = await fetchInboundEmail(resendEmailId, rkey); return (f?.data || f)?.headers; })() : null);
    const senderAuth = senderAuthenticated(providerEmailId, authHdrs?.['authentication-results'], from);

    // ---- Supplier document handling (store + classify + AUTO-EXTRACT + apply) ----
    let lead: any = null;
    if (orSafeEmail(from)) { const { data } = await admin.from('leads').select('id,company_name,claimed_by,email,emirate,trn,services,products,capability_summary,service_emirates,catalog_doc_paths,verified').or(`email.eq.${from},claimed_by.eq.${from}`).limit(1).maybeSingle(); lead = data; }
    let stored = 0; const reviews: number[] = []; const appliedSummary: string[] = []; const unreadDocs: string[] = [];
    let lostAttachments = 0; let uploadFailures = 0; let classifyFailures = 0; let refusedAttachments = 0; let classifySkipped = 0;
    const hv = (k: string) => { const v = hdrs?.[k] ?? hdrs?.[k.toLowerCase()]; return v == null ? null : String(Array.isArray(v) ? v[0] : v); };
    // Each attachment is fetched ONCE: the quotation route below and the profile path read the same bytes.
    const raws: (Uint8Array | null)[] = [];
    for (const a of atts.slice(0, 6)) raws.push(await attachmentBytes(a, emailId, rkey));

    // ---- A QUOTATION BY E-MAIL (10 Nov 2026, customer_support; ../quote_by_email.ts says what it decides) ----
    // Decided by content before the profile path sees the mail. A quotation from a verified sender for one of his open
    // requests goes to the portal's own extract_quote + submit_quote (supplier_api email_quote); the attachments it took
    // are not stored as profile documents.
    let quoteRoute: Awaited<ReturnType<typeof quoteByEmail>> = { taken: [], outcome: null, inquiry_id: null };
    if (lead?.id && lead.claimed_by) {
      const files: MailFile[] = [];
      for (let i = 0; i < raws.length; i++) {
        const a = atts[i]; const rb = raws[i]; if (!rb) continue;
        const fname = String(a.filename || a.name || 'document').slice(0, 180);
        // A picture embedded in the mail's signature (a logo: inline, or under 15 KB) is not offered to the model as a
        // possible quotation (12 Nov 2026): each candidate is one model call. It still takes the profile path as before.
        if (/^image\//i.test(String(a.content_type || a.contentType || '')) && (a.content_id || a.contentId || rb.length < 15_000)) continue;
        // A quotation is often a spreadsheet or a Word file, which the profile path (PDF and images) refuses.
        const sc = await sanitizeAndScan({ input: rb, declaredMime: String(a.content_type || a.contentType || 'application/octet-stream'), filename: fname, allow: SAFE_DOCS,
                                           scan: { source: 'resend_inbound.quotation', subject: String(from || ''), filename: fname, bucket: 'supplier-docs' } });
        if (sc.ok) files.push({ index: i, filename: fname, mime: sc.result.mime, bytes: sc.result.bytes });
      }
      try {
        quoteRoute = await quoteByEmail({ from, subject, text: fullText.slice(0, 20000), inReplyTo: hv('in-reply-to'), references: hv('references'), senderAuth: senderAuth }, lead, files, {
          openRequests: async (leadId) => {
            const { data: ms } = await admin.from('inquiry_matches').select('inquiry_id').eq('supplier_id', leadId);
            const ids = [...new Set((ms || []).map((m: { inquiry_id: string }) => String(m.inquiry_id)).filter(Boolean))];
            if (!ids.length) return [];
            const { data: rs } = await admin.from('inquiries').select('id,rfq_no,category,emirate,status').in('id', ids.slice(0, 200));
            return ((rs || []) as (OpenRequest & { status: string | null })[]).filter((r) => r.status !== 'split' && !isClosedRequest(r.status));
          },
          threaded: async (leadId, nids, mids) => {
            if (!nids.length && !mids.length) return [];
            const q = admin.from('notifications').select('inquiry_id').eq('lead_id', leadId).not('inquiry_id', 'is', null);
            const { data } = nids.length && mids.length ? await q.or(`id.in.(${nids.join(',')}),provider_message_id.in.(${mids.map((m) => '"' + m.replace(/["\\]/g, '') + '"').join(',')})`)
              : nids.length ? await q.in('id', nids) : await q.in('provider_message_id', mids);
            return [...new Set((data || []).map((r: { inquiry_id: string }) => String(r.inquiry_id)))];
          },
          listedProven: async (e) => { const { data } = await admin.rpc('fn_email_proven', { p_email: e }); return data === true; },
          // THE MODEL READS IT (12 Nov 2026, LLM-first audit A2): supplier_api email_quote_read asks quote_extract's model
          // whether each candidate is a quotation and reads it; a failed call is 'unread', never priced by code.
          read: async (f, requests) => {
            const r = await timedFetch(inDbRegion(`${SUPA_URL}/functions/v1/supplier_api`), { method: 'POST', headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ __secret: key, action: 'email_quote_read', lead_id: lead.id, file_b64: bytesToB64(f.bytes), filename: f.filename, mime: f.mime,
                requests: requests.map((q) => ({ job_no: String(q.rfq_no ?? ''), category: q.category })) }) }, 120_000);
            const j = await r.json().catch(() => ({}));
            return ['quotation', 'not_quotation'].includes(j?.verdict) ? { verdict: j.verdict, proposal: j.proposal ?? null, extracted_by_model: j.extracted_by_model ?? null } : { verdict: 'unread', proposal: null };
          },
          submit: async (input) => {
            const r = await timedFetch(inDbRegion(`${SUPA_URL}/functions/v1/supplier_api`), { method: 'POST', headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ __secret: key, action: 'email_quote', ...input }) }, 120_000);
            return await r.json().catch(() => ({ ok: false, stage: 'review', code: 'supplier_api_http_' + r.status, message: null }));
          },
          reply: async (l, toAddr, inquiryId, msg) => {
            await requestDelivery(admin, { type: 'quote_by_email', to_email: toAddr, to_role: 'supplier', lead_id: l.id, inquiry_id: inquiryId, channel: 'email', lang: 'en',
              subject: msg.subject, body: msg.body, status: 'queued', dedupe_key: 'quote_by_email:' + (providerEmailId || subject) });
          },
        });
      } catch (e) { await logRun('error', { from, quote_route: 'failed' }, 'resend_inbound could not route an e-mailed quotation: ' + String((e as Error)?.message || e).slice(0, 200)); }
    }
    const takenByQuote = new Set(quoteRoute.taken);

    for (const [ai_, a] of atts.slice(0,6).entries()) {
      if (takenByQuote.has(ai_)) continue;
      const fname = String(a.filename || a.name || 'document').slice(0,180);
      const mime = String(a.content_type || a.contentType || 'application/octet-stream');
      const rawBytes = raws[ai_];
      // previously a silent 'continue' - a supplier's trade licence could vanish with no record
      if (!rawBytes) { lostAttachments++; continue; }
      // AUDIT 9.1 (3 Aug 2026): mime came from the sender's content_type header and was written
      // onto the storage object and into the model prompt unexamined. Sniff the bytes, refuse
      // anything that is not a PDF or a real image, strip EXIF/GPS from photographed documents.
      // A refusal is counted separately from a LOST attachment: they are different failures and an
      // operator needs to tell "we would not accept it" from "we could not fetch it".
      const __sc = await sanitizeAndScan({ input: rawBytes, declaredMime: mime, filename: fname, allow: SAFE_UPLOAD,
                                           scan: { source: 'resend_inbound.supplier_doc', subject: String(from || ''), filename: fname, bucket: 'supplier-docs' } });
      if (!__sc.ok) { refusedAttachments++; continue; }
      const __san = __sc.result;
      const bytes = __san.bytes;
      const sniffedMime = __san.mime;
      const path = `inbound/${lead?.id||'unknown'}/${Date.now()}_${fname.replace(/[^A-Za-z0-9._-]/g,'_')}`;
      const up = await admin.storage.from('supplier-docs').upload(path, bytes, { contentType: sniffedMime, upsert: true });
      // the upload result was never checked: a failed upload still counted as stored
      if (up && (up as any).error) { uploadFailures++; continue; }
      stored++;
      let ai:any = { relevant:null, category:'other', summary:'', suggested_field:null, confidence:'low' };
      if (key) {
        const content:any[] = [{ type:'text', text: classifyPrompt(String(lead?.company_name||from), subject, text, fname, mime) }];
        if (/^image\//.test(sniffedMime)) { try { content.push({ type:'image_url', image_url:{ url:`data:${sniffedMime};base64,${bytesToB64(bytes)}` } }); } catch {} }
        // ZERO-COST GUARD (16 Aug 2026). This is the estate's only direct
        // POST to OpenRouter's /chat/completions - real paid inference, on a path an inbound
        // supplier email triggers, and it consulted nothing. Every other caller reaches the
        // provider through ai_gateway, which calls fn_llm_preflight. This one asks the same
        // question the gateway asks, and a gate it cannot read is CLOSED.
        let paidAllowed = false;
        { const g = await paidProviderGate(admin, MODEL); paidAllowed = g.allowed; }
        if (['1', 'true', 'yes', 'on'].includes(String(Deno.env.get('NO_PAID_AI') ?? Deno.env.get('OPENROUTER_DISABLED') ?? '').toLowerCase())) paidAllowed = false;
        if (!paidAllowed) {
          // Not a failure: the document is stored and the lead is recorded either way. The
          // classification is simply absent, and says so, rather than being guessed for free.
          ai = { ...ai, summary: 'skipped_due_to_zero_cost_mode: attachment stored and linked; no classification, because every paid inference route is held.' };
          classifySkipped++;
        } else try {
          // 6 SEP 2026 (MASTER_PLAN A6): through the one door. The gateway has taken a full OpenAI
          // `messages` array, image parts included, since 11 Aug (inferCaps marks vision); the
          // "does not proxy image payloads" comment that kept this call direct was stale. The
          // gateway runs fn_llm_preflight, the hold, the budget and the cost ledger; the direct
          // POST above ran none of them and was the estate's last inference call outside it.
          const r = await classify(SYS, '', 500, '', { messages: [{ role: 'system', content: SYS }, { role: 'user', content }] });
          if (r.content) ai = { ...ai, ...parseJson(r.content) }; else classifyFailures++;
        } catch { classifyFailures++; }
      }
      const cat = String(ai.category||'other');
      let extracted:any = null; const fields:string[] = [];
      if (lead && inbSecret) {
        if (cat === 'trade_license' && leadWritable(lead, senderAuth)) {
          const ex = await extractDoc('license', bytes, mime, fname, inbSecret);
          if (!ex?.doc) unreadDocs.push(fname);   // ruling 1177: nothing read at all -> ask for a clearer copy (a low-confidence read WAS read; it goes to review)
          if (ex && ex.doc) { extracted = ex.doc; const dc = ex.doc; const u:any = { license_doc_path: path, license_doc_name: fname, doc_extracted_at: new Date().toISOString(),
              // What the old licence printed never judges a new one (2 Nov 2026, ledger 1442).
              trade_license_no: null, license_authority: null, license_expiry: null,
              // The name printed on this licence (a scan is read by the vision model); null = not read, and the
              // sales engineer's review then holds the registration for a human (licence_name_unread).
              licence_legal_name: licenceNameFromModel(dc) };
            if (dc.confidence !== 'low') {
              if (dc.license_number) { u.trade_license_no = dc.license_number; fields.push('licence no '+dc.license_number); }
              if (dc.license_authority) { u.license_authority = dc.license_authority; fields.push('authority'); }
              if (dc.expiry_date) { u.license_expiry = dc.expiry_date; fields.push('expiry '+dc.expiry_date); }
              if (dc.city) u.license_city = dc.city;
              if (dc.emirate && !lead.emirate) u.emirate = dc.emirate;
              if (dc.trn && !lead.trn) { u.trn = dc.trn; fields.push('TRN'); }
            }
            // Review of #962: this write's result was discarded. A licence number another claimed company
            // holds is now set aside (the document path and expiry are still written) and sent to a human.
            const w = await updateLeadSettingAsideClashingLicence(admin as unknown as LeadWriter, lead.id, u, 'resend_inbound');
            if (w.licenceSetAside) { const i = fields.findIndex((f) => f.startsWith('licence no ')); if (i >= 0) fields[i] = 'licence no set aside for review (held by another claimed company)'; }
            if (w.error) { console.error('resend_inbound: licence readings not saved —', String(w.error.message ?? '')); fields.length = 0; }
          }
        } else if ((cat === 'company_profile' || cat === 'catalogue') && leadWritable(lead, senderAuth)) {
          const ex = await extractDoc('profile', bytes, mime, fname, inbSecret);
          if (!ex?.profile) unreadDocs.push(fname);
          const u:any = { doc_extracted_at: new Date().toISOString() };
          if (cat === 'company_profile') u.company_profile_doc_path = path;
          if (cat === 'catalogue') { const cur = Array.isArray(lead.catalog_doc_paths)?lead.catalog_doc_paths:[]; u.catalog_doc_paths = [...cur, path]; }
          if (ex && ex.profile) { extracted = ex.profile; const pr = ex.profile;
            if (pr.confidence !== 'low') {
              if (pr.summary && !lead.capability_summary) { u.capability_summary = pr.summary; fields.push('capability'); }
              if (Array.isArray(pr.services) && pr.services.length && !lead.services) u.services = pr.services;
              if (Array.isArray(pr.products) && pr.products.length && !lead.products) u.products = pr.products;
              if (Array.isArray(pr.emirates) && pr.emirates.length && !(Array.isArray(lead.service_emirates)&&lead.service_emirates.length)) u.service_emirates = pr.emirates;
            }
          }
          await admin.from('leads').update(u).eq('id', lead.id);
        }
        if (fields.length) appliedSummary.push(fname + ' → ' + fields.join(', '));
      }
      const { data: rev } = await admin.from('doc_reviews').insert({ lead_id: lead?.id||null, from_email: from, subject, file_name: fname, file_path: path, mime, ai_relevant: ai.relevant, ai_category: ai.category, ai_summary: String(ai.summary||'').slice(0,1000), ai_suggested_field: ai.suggested_field, ai_confidence: ai.confidence, status: 'pending', auto_applied: fields.length>0, extracted: extracted }).select('id').maybeSingle();
      if (rev?.id) reviews.push(rev.id);
    }
    // 28 SEP 2026 (customer_support): a mail with no document to apply is correspondence, and email_triage answers
    // it. It was needs_review=false, which email_triage's selection excludes, so a customer's question was stored
    // and never read. raw keeps what the reply and noAutoReply need (_shared/customer_mail.ts).
    // sender_authenticated: read above, before the documents (senderAuth)
    const rawFacts = { message_id: String(d.message_id || hv('message-id') || '') || null, auto_submitted: hv('auto-submitted'),
      // 27 Oct 2026 (marketing): the other auto-reply marks, so an out-of-office never takes an invited lead's one
      // invite.reply handoff (fn_marketing_files_invite_reply reads them)
      x_auto_response_suppress: hv('x-auto-response-suppress'), precedence: hv('precedence'), x_autoreply: hv('x-autoreply') ?? hv('x-autorespond'), list_unsubscribe: hv('list-unsubscribe') ?? hv('list-id'),
      in_reply_to: hv('in-reply-to'), references: hv('references'),
      content_type: hv('content-type'), sender_authenticated: senderAuth,
      // 2 Nov 2026: our own tenant's Exchange wrote it (its NDRs carry no DMARC result); read by fn_mail_bounce_marks_its_send
      exchange_internal: exchangeInternal(providerEmailId, stampHeaders(hv), from), calendar: atts.some((a: any) => /text\/calendar|application\/ics/i.test(String(a.content_type || a.contentType || '')) || /\.ics$/i.test(String(a.filename || ''))) };
    const { data: inbRow } = await admin.from('inbound_messages').insert({ lead_id: lead?.id||null, from_email: from, to_email: to, subject, body: fullText, html: fullHtml, provider_email_id: providerEmailId, attachments_count: stored, matched_existing: !!lead, needs_review: quoteRoute.outcome === 'unread' || (!quoteRoute.outcome && appliedSummary.length===0 && (stored>0 || !receiptish)), raw: { ...rawFacts, quote_by_email: quoteRoute.outcome, quote_inquiry_id: quoteRoute.inquiry_id } }).select('id').maybeSingle();
    // Answered within the minute, not on the 15-minute tick: email_triage is woken for this one message.
    if (inbRow?.id && !quoteRoute.outcome && appliedSummary.length === 0 && !receiptish && (await sec('email_triage_enabled')) === 'true') {
      const wake = timedFetch(inDbRegion(`${SUPA_URL}/functions/v1/email_triage`), { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ __secret: await sec('cred_fn_resend_inbound'), message_id: inbRow.id }) }, 55_000).then((r) => r.body?.cancel()).catch(() => {});
      (globalThis as any).EdgeRuntime?.waitUntil?.(wake);
    }
    // 6 Sep 2026: a receipt-ish email that reached this path was NOT booked. It is finance's work from here —
    // one org_task for the bookkeeper, and the rows carry that owner so neither OS surface shows them to the founder.
    if (receiptish && !lead && !reasoningHeld) await handToBookkeeper(inbRow?.id, reviews, receiptReason || 'The receipt path did not book this email.');
    if (lead && appliedSummary.length) {
      try{ await requestDelivery(admin, { type:'supplier_doc_applied', to_email: owner, to_role:'admin', lead_id: lead.id, channel:'email', subject:`Supplier record auto-updated: ${lead.company_name||('Lead #'+lead.id)}`, body:`A document from ${from} was read and applied to ${lead.company_name||('Lead #'+lead.id)}:\n\n${appliedSummary.join('\n')}\n\nReview it in the CRM if needed.` }); }catch(_e){}
    }
    // An e-mail the quotation route could not read was already answered by it (quote_by_email.ts 'unread'): one reply, not two.
    if (from && from !== 'onboarding@resend.dev' && stored>0 && lead && quoteRoute.outcome !== 'unread') await requestDelivery(admin, { type:'doc_received', to_email: from, to_role:'supplier', lead_id: lead?.id||null, subject:'We received your document', body: unreadDocs.length
      // RULING 1177 (12 Oct 2026): this said 'updated your records' even when nothing could be read. A document both the
      // code and the model could not read is now answered with a clearer-copy request (suppliers: always English), and
      // the clearer copy, sent to the same address, is read by this same path when it arrives.
      ? `Thank you${lead?.company_name?' '+lead.company_name:''} — we received ${stored} document(s). ` + unreadDocs.map((n) => clearerCopyAsk('supplier', 'en', n)).join(' ')
      : `Thank you${lead?.company_name?' '+lead.company_name:''} — we received ${stored} document(s) and ${appliedSummary.length ? 'updated your records' : 'our team will add them to your profile'}.`, status:'queued' });
    const counts = { from, matched_lead: lead?.id||null, attachments: atts.length, stored, quote_by_email: quoteRoute.outcome, quotation_files: quoteRoute.taken.length, refused_attachments: refusedAttachments, lost_attachments: lostAttachments, upload_failures: uploadFailures, classify_failures: classifyFailures, classify_skipped_zero_cost: classifySkipped, applied: appliedSummary.length, signature_verified: 1 };
    if (lostAttachments || uploadFailures) await logRun('error', counts, 'INBOUND DOCUMENTS LOST - ' + lostAttachments + ' attachment(s) could not be downloaded from Resend and ' + uploadFailures + ' failed to upload to storage. Sender: ' + from + ', subject: ' + subject.slice(0, 120));
    else if (atts.length || stored) await logRun('ok', counts, appliedSummary.length ? ('applied: ' + appliedSummary.join('; ').slice(0, 300)) : (lead ? '' : 'no matching lead for sender'));
    return J({ ok: true, matched_lead: lead?.id||null, stored, reviews, applied: appliedSummary, quote_by_email: quoteRoute.outcome, quote_inquiry_id: quoteRoute.inquiry_id });
}
export type Out = Exclude<Awaited<ReturnType<typeof supplierDocs>>, Response>;
