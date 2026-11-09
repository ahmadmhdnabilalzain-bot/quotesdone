// resend_inbound step: receipts, statements and subscriptions forwarded to finance, and the held-for-review path. Moved out of index.ts's handler unchanged (9 Nov 2026);
// the handler in index.ts calls the steps in the order they ran inline, each handing on what the next one reads.
import type { Out as BounceUnsubscribeOut } from './bounce_unsubscribe.ts';
import { readEveryAttachment, envGatewayVision } from '../../_shared/read_every_attachment.ts';
import { SAFE_UPLOAD } from '../../_shared/attachment.ts';
// MALWARE WATCH, 9 Sep 2026 — see _shared/malware.ts. Inbound mail is the classic malware carrier
// and this function archives what arrives, so the verdict has to be taken before the object is
// written, not after.
import { sanitizeAndScan } from '../../_shared/malware.ts';
import { parseAmount, parseReceipt } from '../../_shared/receipt_parse.ts';
import { pdfText } from '../../_shared/pdf_text.ts';
// A receipt whose email carried no vendor file gets a PDF PRINT of the email, not a .html blob.
import { emailPrintPdf } from '../../_shared/email_print.ts';
import { requestDelivery } from '../../_shared/deliver.ts';
import { statementRowText, takeInStatement } from '../../_shared/bank_statement_intake.ts';
import { defaultDeps } from '../../_shared/think.ts';
import { documentKind, readingOf, receiptVendor, type ExpenseMail } from '../../_shared/reasoned_books.ts';
import { registerRowsFor } from '../../_shared/expense_mailbox.ts';
import { admin, SUPA_URL, J, logRun } from '../lib/runtime.ts';
import { attachmentBytes } from '../lib/inbound_fetch.ts';
import { sha256hex, dbxSafe } from '../lib/receipt_consts.ts';
import { thinkDeps } from '../lib/think_deps.ts';

export async function receipts(ctx: BounceUnsubscribeOut) {
    const { req, emailId, from, to, subject, text, atts, isExpenseMailbox, providerEmailId, tenantHanded, expenseSenderOk, rkey, fullHtml, fullText, handToBookkeeper, d, owner } = ctx;
    let { receiptish, receiptReason } = ctx;
    const booksDeps = thinkDeps ?? defaultDeps(admin, 'resend_inbound');
    const svixKey = req.headers.get('svix-id') || req.headers.get('webhook-id') || '';
    const mail: ExpenseMail = { emailId: emailId || ('svix:' + svixKey), from, to, subject, text,
      filenames: atts.map((a) => String(a.filename || a.name || '')), mailbox: isExpenseMailbox ? 'expenses' : 'other', providerEmailId };
    const { data: booksCtx } = await admin.rpc('fn_accountant_reading_context');
    const renewals = Array.isArray(booksCtx?.renewals) ? booksCtx.renewals : [];
    const register = Array.isArray(booksCtx?.register) ? booksCtx.register : [];
    // An email to any OTHER mailbox: is it the company's own spending at all? Reasoned over the envelope and
    // the note. Held: it takes the supplier-document path below, which stores and classifies nothing on a guess,
    // and the replay hands it to the bookkeeper if it is reasoned to be an expense document.
    // Only mail that could carry a document of our spending is asked at all: it has an attachment, or it comes from
    // a permitted expense forwarder (structured facts, no word read). Anything else is plain correspondence.
    let kind: string | null = null;
    // true while what the email is, or who issued it, waits for reasoning: the accountant's queue owns it then, and
    // it is NOT also handed to the bookkeeper (one owner, no double path); the replay re-runs the sweep for it.
    let reasoningHeld = false;
    if (!tenantHanded && !receiptish && (atts.length > 0 || expenseSenderOk)) {
      kind = (await documentKind(booksDeps, mail, renewals, register)).value;
      receiptish = kind !== null && kind !== 'other';
      reasoningHeld = kind === null;
    }

    let att: { bytes: Uint8Array; name: string; mime: string; ext: string } | null = null;
    if (receiptish) {
      try {
        // 9 SEP 2026 — READ THE DOCUMENT, NOT JUST THE COVERING NOTE.
        // A receipt forwarded to this mailbox is usually a PDF with an empty note, so parsing only
        // `text` read nothing and every such receipt went to review. The attachment is fetched
        // FIRST now, sanitised by the shared sanitiser (_shared/attachment.ts, by magic bytes — the
        // receipt path was the one upload site that skipped it and wrote the sender's declared
        // content-type onto the storage object), and its text layer is read deterministically by
        // _shared/pdf_text.ts. No model is involved and none is required.
        for (const a of atts.slice(0, 8)) {
          const fn = String(a.filename || a.name || '');
          const mm = String(a.content_type || a.contentType || '');
          if (!(/pdf|^image\//i.test(mm) || /\.(pdf|jpe?g|png|webp)$/i.test(fn))) continue;
          const by = await attachmentBytes(a, emailId, rkey);
          if (!by || !by.length) continue;
          const sc = await sanitizeAndScan({ input: by, declaredMime: mm, filename: fn, allow: SAFE_UPLOAD,
                                             scan: { source: 'resend_inbound.receipt', subject: String(from || ''), filename: fn, bucket: 'receipt-files' } });
          if (!sc.ok) { await logRun('ok', { receipt: true, attachment_refused: sc.body.error, file: fn.slice(0, 80) }, 'a receipt attachment was refused (' + sc.body.error + ': ' + sc.body.detail + '); it was not archived and its text was not read'); continue; }
          const san = sc.result;
          att = { bytes: san.bytes, name: fn || ('receipt.' + san.ext), mime: san.mime, ext: san.ext };
          if (san.mime === 'application/pdf') break;   // a PDF is the receipt; an image is a fallback
        }
        let docText = '';
        if (att && att.mime === 'application/pdf') {
          docText = await pdfText(att.bytes);
          if (!docText) receiptReason = 'The attached PDF carries no text layer we can trust — it is scanned, or uses a font we cannot map — so nothing was read from it. ';
        } else if (att) {
          receiptReason = 'The receipt is an image, which has no text layer. ';
        }
        // RULING 1177 (12 Oct 2026): a scanned PDF or a photographed receipt is READ by the vision model (_shared/
        // read_every_attachment: one more asking, the gateway's second model). Held only when both askings fail.
        if (att && !docText) {
          const seen = await readEveryAttachment(att.bytes, att.name, att.mime, envGatewayVision());
          if (seen.status === 'read') { docText = seen.text.slice(0, 8000); receiptReason = ''; }
          else receiptReason += 'The vision model could not read it either (' + String(seen.reason || 'no answer').slice(0, 80) + '), so it is held for a clearer copy. ';
        }
        // A CSV export (the .csv extension is a file-format fact) is read as text; it is used only if the message is
        // reasoned to be a statement, and the reasoning reads it too.
        let csvText = '';
        for (const a of atts.slice(0, 8)) {
          if (!/\.csv$/i.test(String(a.filename || a.name || ''))) continue;
          const by = await attachmentBytes(a, emailId, rkey);
          if (by && by.length <= 5 * 1024 * 1024) { csvText = new TextDecoder().decode(by); break; }
        }
        // WHAT IS IT, read with the document: the real Mashreq statement names its bank only inside the PDF, so
        // the reasoning reads the rows statementRowText rebuilds from it (or pdf_text's text layer, or the CSV).
        const rowText = att && att.mime === 'application/pdf' ? await statementRowText(att) : '';
        if (kind === null) {
          kind = (await documentKind(booksDeps, { ...mail, docText: [rowText || docText, csvText.slice(0, 2000)].filter(Boolean).join('\n').slice(0, 4000) }, renewals, register)).value;
          reasoningHeld = kind === null;
          if (kind === null) receiptReason += 'What this document is waits for reasoning: the model is held, so it is not booked on a guess; the accountant\x27s queue replays it. ';
          else if (kind === 'other') receiptReason += 'Reasoned: this is not a document of the company\x27s own spending, so nothing was booked. ';
        }
        // 15 SEP 2026 — A BANK STATEMENT IS NOT A RECEIPT. Taken in by the SAME routine the accountant's
        // expense_sweep uses (_shared/bank_statement_intake.ts), before any receipt handling.
        if (kind === 'bank_statement' && isExpenseMailbox && expenseSenderOk) {
          const stRef = emailId ? 'resend:' + emailId : 'svix:' + svixKey;
          const stIn = await takeInStatement(admin, {
            from, subject, filenames: atts.map((a) => String(a.filename || a.name || '')),
            pdf: att && att.mime === 'application/pdf' ? att : null, csvText, docText, rowText, readNote: receiptReason,
            sourceRef: stRef, archivePath: 'bank/' + new Date().toISOString().slice(0, 10) + '/' + (emailId || svixKey || Date.now()) });
          {
            await admin.from('inbound_messages').insert({ from_email: from, to_email: to, subject, html: fullHtml, provider_email_id: providerEmailId,
              body: `[BANK STATEMENT — taken in as ${stRef}, ${stIn.lines} line(s)${stIn.problem ? ', does NOT add up, recorded unreadable' : ''}]${stIn.doc_path ? ' document: ' + stIn.doc_path : ''}\n\n` + fullText,
              attachments_count: stIn.doc_path ? 1 : 0, matched_existing: false, needs_review: !!stIn.error });
            await logRun(stIn.error ? 'error' : 'ok', { expenses_mailbox: 1, bank_statement: true, source_ref: stRef, lines: stIn.lines, adds_up: stIn.adds_up },
              stIn.error ? 'bank statement recognised but fn_accountant_bank_statement_ingest failed: ' + stIn.error
                         : 'bank statement taken in as ' + stRef + (stIn.problem ? ' — it does not add up: ' + stIn.problem : ''));
            return J({ ok: true, receipt: false, bank_statement: true, source_ref: stRef, ...stIn }, stIn.error ? 500 : 200);
          }
        }
        // the PDF text is APPENDED, so the forwarded "From:" header at the top of the note still
        // identifies the original vendor and a figure in the note still wins over one in the file
        const parseBody = docText ? (text + '\n' + docText) : text;

        let ex: any = {};
        const reading = kind ? readingOf(kind) : null;
        if (reading && !parseAmount(parseBody) && !parseAmount(subject)) {
          receiptReason += 'No amount could be read beside a currency mark, so nothing was booked and nothing was estimated. ';
        } else if (reading) {
          // Who issued it: one of the vendors the books already carry, else the name as the document writes it.
          const vendor = (await receiptVendor(booksDeps, { ...mail, docText: docText.slice(0, 4000) }, Array.isArray(booksCtx?.vendors) ? booksCtx.vendors : [])).value;
          const det = vendor ? parseReceipt({ subject, body: parseBody, vendor, period: reading.period }) : null;
          if (det) {
            ex = { is_receipt: true, vendor: det.vendor, amount: det.amount, currency: det.currency, date: det.date, period: det.period, recurring: det.recurring, vat: det.vat, trn: det.trn,
                   read_as: reading.readAs, renews_item: reading.renewsItem, note: subject + ' [reasoned: ' + kind + '; ' + det.basis + (docText ? ' src=pdf_text' : '') + ']' };
          } else if (!vendor) {
            reasoningHeld = true;
            receiptReason += 'Who issued this waits for reasoning: the model is held, so it is not booked on a guess; the accountant\x27s queue replays it. ';
          }
        }
        if (ex && ex.is_receipt === true && ex.vendor && Number(ex.amount) > 0) {
          const amount = Number(ex.amount);
          const currency = String(ex.currency||'USD').toUpperCase().replace(/[^A-Z]/g,'').slice(0,3) || 'USD';
          const charged = /^\d{4}-\d{2}-\d{2}$/.test(String(ex.date)) ? String(ex.date) : new Date().toISOString().slice(0,10);
          const vendor = String(ex.vendor).slice(0,120);
          const cad = String(ex.period)==='annual' ? 'annual' : (String(ex.period)==='one_off' ? 'one_off' : 'monthly');
          const recurring = ex.recurring === true || cad === 'monthly' || cad === 'annual';
          if (!expenseSenderOk) {
            const { data: heldRow } = await admin.from('inbound_messages').insert({ from_email: from, to_email: to, subject, provider_email_id: providerEmailId, body: `[receipt received but NOT booked — sender not allowlisted] ${vendor} ${amount} ${currency}`, attachments_count: 0, matched_existing: false, needs_review: true }).select('id').maybeSingle();
            // 6 Sep 2026: the bookkeeper decides whether an unknown sender's receipt is ours; the founder is not paged
            await handToBookkeeper(heldRow?.id, [], `Receipt from ${from} for ${vendor} ${amount} ${currency} was NOT booked: the sender is not on app_secrets.expense_forwarders. Decide whether it is a company expense; if so add the sender to the allowlist and book it.`);
            await logRun('ok', { receipt: true, booked: false, vendor, amount, currency }, 'receipt not booked: sender ' + from + ' is not on the expense allowlist');
            return J({ ok:true, receipt:true, booked:false, reason:'sender_not_allowlisted' });
          }

          // IDEMPOTENCY 9 Sep 2026 — KEYED ON THE MESSAGE, NOT ON WHAT WE READ FROM IT ---------
          // The guard below this one keys on vendor+date, which is derived from the extraction and
          // therefore cannot tell a redelivery that parsed differently from a genuine second
          // same-day charge. Resend's inbound email_id is stable across its own retries, so it is
          // the honest key; expense_entries.source_msg_id is unique on it.
          // THE LOOKUP IS UNFILTERED BY STATUS, deliberately. A status-filtered guard over a unique
          // key is the fn_agent_action_work_sweep trap: a previously failed row occupies the key
          // without satisfying the guard, so the guard says "go ahead", the insert then violates
          // the index, and the work is lost with no record of why. Here ANY row holding the key is
          // found, and the redelivery becomes an evidence backfill onto it.
          // It cannot deadlock: one row, one index, no second table in the statement, and the
          // storage upload finishes before the insert opens — no transaction ever waits on a fetch.
          const svixId = req.headers.get('svix-id') || req.headers.get('webhook-id') || '';
          const msgKey = emailId ? ('resend:' + emailId)
            : (svixId ? 'svix:' + svixId
                      : 'digest:' + (await sha256hex([from, to, subject, vendor, charged, amount, currency].join('|'))).slice(0, 32));
          const { data: priorRows } = await admin.from('expense_entries').select('id,doc_path,amount,currency').eq('source_msg_id', msgKey).limit(1);
          const priorRow: any = priorRows?.[0] || null;

          // DEDUP FIX 19 Jul 2026 -------------------------------------------------------------
          // This used to match vendor + charged_on + AMOUNT. Resend RETRIES a delivery that timed
          // out or errored, and the extractor does not always read an identical amount from the
          // same email twice (one pass read a Resend renewal as 20 USD, a re-delivery of the very
          // same receipt read it as 76.39 AED). Because the amounts differed, the old guard let a
          // SECOND expense through and the same real cost was counted twice.
          // Now ANY existing entry for the same vendor on the same date blocks the booking. If the
          // amount differs it is flagged for review rather than silently booked - a genuine second
          // same-day charge from one vendor is possible, but rare enough to deserve a human look,
          // and under-booking with an alert is far safer than silently double-counting costs.
          const { data: sameDay } = await admin.from('expense_entries').select('id,amount,currency,doc_path').eq('vendor', vendor).eq('charged_on', charged).limit(5);
          // v15 FIX 3 Aug 2026 - RECEIPT ARCHIVE BACKFILL --------------------------------------
          // v14 returned from this guard BEFORE any upload was attempted. That made the remedy
          // printed by v_expense_receipt_gap - "re-forward the vendor email to the inbound address
          // to retry" - a no-op: the re-forward was discarded as a duplicate and the entry kept
          // doc_path NULL for ever. Returning non-200 on a failed archive would not help either,
          // because Resend's own redelivery lands on this same guard. A receipt whose expense
          // entry is missing its document is not a duplicate to discard, it IS the retry - so fall
          // through and archive it against the EXISTING row instead of inserting a second one.
          // Restricted to an exact vendor+date+amount+currency match, because a same-day entry
          // with a DIFFERENT amount may be a genuine second charge and attaching this document to
          // it would file the wrong evidence against a real expense.
          // 9 Sep 2026: the row holding this message's key wins outright. It IS this receipt, so a
          // redelivery repairs it (missing document, missing GL posting) rather than being reported
          // as somebody else's duplicate.
          const gapRow: any = priorRow || (sameDay || []).find((x:any) => !x.doc_path && Number(x.amount) === amount && String(x.currency||'').toUpperCase() === currency) || null;
          if (!priorRow && sameDay && sameDay.length && !gapRow) {
            const exact = sameDay.some((x:any) => Number(x.amount) === amount && String(x.currency||'').toUpperCase() === currency);
            const { data: dupRow } = await admin.from('inbound_messages').insert({ from_email: from, to_email: to, subject, provider_email_id: providerEmailId, body: `[receipt dup] ${vendor} ${amount} ${currency} ${charged}${exact?'':' (amount differs from existing entry - flagged)'}`, attachments_count: 0, matched_existing: false, needs_review: !exact }).select('id').maybeSingle();
            // 6 Sep 2026: a same-day different-amount receipt is the bookkeeper's call (second charge or re-read), not the founder's
            if (!exact) await handToBookkeeper(dupRow?.id, [], `A receipt for ${vendor} dated ${charged} showing ${amount} ${currency} was NOT booked: an expense from that vendor already exists on that date (${sameDay.map((x:any)=>x.amount+' '+x.currency).join(', ')}). Usually the same receipt read twice; if it is a genuine second charge, book it.`);
            await logRun('ok', { receipt: true, deduped: true, vendor, amount, currency, exact_match: exact }, exact ? 'duplicate receipt ignored - an identical expense was already booked for this vendor and date.' : ('receipt NOT booked: an expense from ' + vendor + ' already exists on ' + charged + ' with a DIFFERENT amount (' + sameDay.map((x:any)=>x.amount+' '+x.currency).join(', ') + ' vs ' + amount + ' ' + currency + '). Flagged for review - most likely a redelivery read differently by the extractor, but could be a real second charge.'));
            return J({ ok:true, receipt:true, deduped:true, vendor, amount, currency });
          }

          // 9 Sep 2026: the attachment was already fetched and SANITISED above (magic bytes, EXIF
          // stripped). Re-fetching it here was a second download of the same file and, worse, the
          // old loop wrote the SENDER'S declared content-type onto the storage object — this was
          // the one upload site in the function that did not go through _shared/attachment.ts.
          // 9 SEP 2026 — EVERY EXPENSE RECORD CARRIES A DOCUMENT YOU CAN OPEN, AND THE RECORD SAYS
          // WHICH KIND IT IS. The founder: "i wanna be able to click any record and see the actual
          // invoice or receipt or email print pdf if none exist".
          //
          // Until today the no-attachment branch stored `receipt.html`, text/html — the raw message
          // body in a <pre>. Five of the nine receipts booked through this function held exactly
          // that. It is not a document anyone can hand to an auditor, and nothing in the schema
          // could tell it apart from the vendor's real invoice: both were just "the doc_path".
          // Now the fallback is a PDF PRINT of the email, rendered by pdf_native, and doc_kind
          // records WHICH of the two classes of evidence this row holds. The HTML upload survives
          // only as the fallback-of-the-fallback, so a pdf_native outage degrades the document
          // rather than losing the email.
          let docPath: string | null = null;
          let docName = 'receipt.html';
          let docType = 'text/html';
          let docKind: 'vendor_document' | 'email_print' = 'email_print';
          let docNote: string | null = null;
          let upErr = ''; let upAttempts = 0;

          if (att) {
            docName = att.name; docType = att.mime; docKind = 'vendor_document';
            docNote = "The vendor's own file, taken off the source email (Resend inbound " + (emailId || 'delivery') + ').';
            // v15: three attempts. A refused archive is usually transient, and a receipt that is
            // separated from the expense it evidences is a VAT-record gap, not a cosmetic one.
            for (let attempt = 1; attempt <= 3 && !docPath; attempt++) {
              upAttempts = attempt;
              const rpN = `receipts/${charged}/${Date.now()}_${vendor.replace(/[^A-Za-z0-9._-]/g,'_')}.${att.ext}`;
              try { const up = await admin.storage.from('receipt-files').upload(rpN, att.bytes, { contentType: docType, upsert: true }); if (!up.error) docPath = rpN; else upErr = String(up.error.message||'').slice(0,150); }
              catch (e) { upErr = String((e as Error)?.message||e).slice(0,150); }
              if (!docPath && attempt < 3) await new Promise((r) => setTimeout(r, 400 * attempt));
            }
          } else {
            upAttempts = 1;
            const printed = await emailPrintPdf(admin, SUPA_URL, {
              entryId: gapRow?.id ?? null, vendor, amount, currency, chargedOn: charged,
              sourceMsgId: msgKey, subject, from, to, date: new Date().toISOString(),
              text, html: String(d.html || ''), attachmentNames: [],
            });
            if (printed.ok) {
              // pdf_native NAMED this path; it is used exactly as returned.
              docPath = printed.path; docName = printed.name; docType = 'application/pdf';
              docNote = 'The source email carried no vendor file, so this is a PDF print of the email itself.';
              if (printed.glyphsDropped) await logRun('error', { receipt: true, glyphs_dropped: printed.glyphsDropped, entry: msgKey }, 'the email print for ' + vendor + ' dropped ' + printed.glyphsDropped + ' character(s) the brand fonts could not render; the invisible inbox padding is stripped before rendering, so this count is real content missing from the printed document.');
            } else {
              const html = String((d.html)|| text || subject);
              const bytes = new TextEncoder().encode('<meta charset=\"utf-8\"><pre style=\"font:14px/1.5 monospace;white-space:pre-wrap\">'+html.replace(/</g,'&lt;')+'</pre>');
              docNote = 'The source email carried no vendor file, and the email could not be printed to PDF ('
                + printed.reason + '), so the message body is archived as HTML instead.';
              for (let attempt = 1; attempt <= 3 && !docPath; attempt++) {
                upAttempts = attempt;
                const rpN = `receipts/${charged}/${Date.now()}_${vendor.replace(/[^A-Za-z0-9._-]/g,'_')}.html`;
                try { const up = await admin.storage.from('receipt-files').upload(rpN, bytes, { contentType: 'text/html', upsert: true }); if (!up.error) docPath = rpN; else upErr = String(up.error.message||'').slice(0,150); }
                catch (e) { upErr = String((e as Error)?.message||e).slice(0,150); }
                if (!docPath && attempt < 3) await new Promise((r) => setTimeout(r, 400 * attempt));
              }
            }
          }
          const ext = docType === 'application/pdf' ? 'pdf' : (att ? att.ext : 'html');
          // ---- The two things every booked receipt owes the company ----
          // 1. THE LEDGER. fn_gl_sync_business() already knows how to post an expense_entries row
          //    (gl_expense_map -> account, 6300 fallback, USD at gl_settings.usd_to_aed) — but
          //    cron.job holds exactly one job in this project and it is not that one, so nothing
          //    ever calls it and a booked expense would never reach gl_journal. fn_expense_post_to_gl
          //    posts THIS entry under the same source/source_ref the bulk routine uses, so the two
          //    can never double-post, and it splits stated VAT to 1150 (VAT Recoverable), which
          //    nothing in the estate had ever debited.
          //    ponytail: posting inline is the entry point that exists; if the ledger ever grows
          //    enough that this matters, schedule fn_gl_sync_business and delete the call.
          // 2. THE EVIDENCE OFF-SITE. doc_backups is the Sales Engineer's existing filing contract
          //    and dropbox_backup reads it by status, not by entity, so an 'expense' row needs no
          //    change there. dedupe_key makes a redelivery a no-op.
          const fileAndPost = async (entryId: number | null | undefined, dPath: string | null, dName: string, dType: string) => {
            if (!entryId) return { journal: null as number | null, filed: false };
            const { data: jid, error: glErr } = await admin.rpc('fn_expense_post_to_gl', { p_entry_id: entryId });
            if (glErr) await logRun('error', { entry_id: entryId }, 'expense #' + entryId + ' was booked but did NOT reach the ledger: fn_expense_post_to_gl failed with ' + String(glErr.message || '').slice(0, 200) + '. gl_journal understates costs until it is posted.');
            let filed = false;
            if (dPath) {
              const { error: bkErr } = await admin.from('doc_backups').insert({
                entity: 'expense', entity_id: String(entryId), doc_type: 'Receipt',
                bucket: 'receipt-files', path: dPath, file_name: dName.slice(0, 180),
                dropbox_path: `/QuotesDone Backup/Finance/Receipts/${charged.slice(0, 7)}/${dbxSafe(vendor)} ${charged} - ${dbxSafe(dName)}`,
                source: 'storage', dedupe_key: 'E:' + entryId + ':receipt:' + dPath,
              });
              filed = !bkErr;   // a unique-key conflict on a redelivery is the guard working
            }
            return { journal: (jid as number | null) ?? null, filed };
          };

          if (gapRow) {
            // BACKFILL ONLY. The expense is already booked and the subscription row already
            // exists; attaching the evidence must not book it a second time and must not re-run
            // the subscription upsert. Nothing below this branch runs.
            if (docPath && !gapRow.doc_path) await admin.from('expense_entries').update({ doc_path: docPath, doc_name: docName.slice(0,180), doc_content_type: docType, doc_kind: docKind, doc_note: docNote, source_msg_id: msgKey }).eq('id', gapRow.id);
            // idempotent: posts only if this entry has no journal yet, files only if not filed yet
            const rep = await fileAndPost(gapRow.id, docPath || gapRow.doc_path || null, docName, docType);
            await admin.from('inbound_messages').insert({ from_email: from, to_email: to, subject, provider_email_id: providerEmailId, body: `[receipt archive ${docPath?'backfilled':'RETRY FAILED'}] entry #${gapRow.id} ${vendor} ${amount} ${currency} on ${charged}${rep.journal?` journal #${rep.journal}`:''}`, attachments_count: docPath?1:0, matched_existing: true, needs_review: !docPath });
            await logRun(docPath ? 'ok' : 'error', { receipt: true, booked: false, archive_backfill: true, entry_id: gapRow.id, vendor, amount, currency, doc_archived: !!docPath, upload_attempts: upAttempts },
              docPath ? ('receipt archive backfilled onto expense_entries#' + gapRow.id + ' - no second expense was booked')
                      : ('receipt archive retry FAILED for expense_entries#' + gapRow.id + ' after ' + upAttempts + ' attempt(s): ' + upErr + '. The expense is still booked without its document; v_expense_receipt_gap will keep reporting it.'));
            return J({ ok: true, receipt: true, archive_backfill: true, entry_id: gapRow.id, vendor, amount, currency, doc: docPath });
          }
          // The category is what files this against the chart of accounts: 'Subscription' and
          // 'Usage' are both rows in gl_expense_map (-> 6000 Software & AI). Nothing here invents
          // an account code; the mapping table decides, with 6300 General & Administrative as the
          // fallback for a category the table does not carry.
          const vatAmt = Number(ex.vat) > 0 && Number(ex.vat) < amount ? Number(ex.vat) : null;
          const trn = /^\d{15}$/.test(String(ex.trn||'')) ? String(ex.trn) : null;
          const { data: insRow } = await admin.from('expense_entries')
            .upsert({ vendor, category: recurring ? 'Subscription' : 'Usage', amount, currency, charged_on: charged,
              note: ('auto from forwarded ' + (recurring?'subscription':'receipt') + ': ' + String(ex.note||subject)).slice(0,300),
              source: 'receipt', doc_path: docPath, doc_name: docName.slice(0,180), doc_content_type: docType,
              doc_kind: docPath ? docKind : null, doc_note: docPath ? docNote : null,
              source_msg_id: msgKey, vat_amount: vatAmt, vendor_trn: trn, read_as: ex.read_as ?? null, renews_item: ex.renews_item ?? null },
              { onConflict: 'source_msg_id', ignoreDuplicates: true })
            .select('id').maybeSingle();
          let entryId: number | null = (insRow?.id as number | undefined) ?? null;
          if (!entryId) {
            // a concurrent redelivery won the unique key between the lookup and this insert; read
            // its row rather than inventing a second expense
            const { data: won } = await admin.from('expense_entries').select('id').eq('source_msg_id', msgKey).limit(1);
            entryId = (won?.[0]?.id as number | undefined) ?? null;
          }
          const posted = await fileAndPost(entryId, docPath, docName, docType);
          let bookedSub = false;
          if (recurring) {
            const erow = { vendor, category: 'Subscription', description: String(ex.note||subject).slice(0,300), amount, currency, cadence: cad, expense_date: charged, active: true, source: 'email_forward', confidence: 'medium', note: ('auto from forwarded subscription receipt' + (docPath?' (document archived)':'')) };
            // the SAME vendor by identity, never a LIKE pattern (founder_instruction 890; _shared/expense_mailbox.ts)
            const ex0 = await registerRowsFor(admin, vendor);
            if (ex0 && ex0.length) await admin.from('expenses').update(erow).eq('id', ex0[0].id);
            else await admin.from('expenses').insert(erow);
            bookedSub = true;
          }
          await admin.from('inbound_messages').insert({ from_email: from, to_email: to, subject, body: `[expense ${recurring?'subscription':'one-off'}] ${vendor} ${amount} ${currency} on ${charged}${docPath?' +'+ext:''}` + '\n\n' + fullText, html: fullHtml, provider_email_id: providerEmailId, attachments_count: docPath?1:0, matched_existing: false, needs_review: false });
          try{ await requestDelivery(admin, { type:'expense_logged', to_email: owner, to_role:'admin', channel:'email', subject:`Expense logged: ${vendor} ${amount} ${currency}`, body:`Logged from your forwarded email.\n\nVendor: ${vendor}\nAmount: ${amount} ${currency}\nDate: ${charged}\nType: ${recurring?(cad+' subscription'):'one-off'}` }); }catch(_e){}
          // v15: keyed on docPath, not upErr. upErr now holds the LAST error of up to three
          // attempts, so a retry that eventually succeeded would otherwise be reported as failed -
          // and fn_watch_failed_runs pages on any error row.
          await logRun(docPath ? 'ok' : 'error', { receipt: true, booked: true, entry_id: entryId, vendor, amount, currency, vat: vatAmt, trn: !!trn, recurring, cadence: cad, doc_archived: !!docPath, dropbox_queued: posted.filed, gl_journal: posted.journal, upload_attempts: upAttempts, msg_key: msgKey }, docPath ? '' : ('expense booked but the receipt document failed to archive after ' + upAttempts + ' attempt(s): ' + upErr + '. Re-forward the vendor email to the inbound address - v15 will archive it onto the existing entry without booking a second expense.'));
          return J({ ok: true, receipt: true, entry_id: entryId, vendor, amount, currency, vat: vatAmt, trn, charged_on: charged, recurring, cadence: cad, booked_subscription: bookedSub, doc: docPath, gl_journal: posted.journal });
        }
      } catch (e) { await logRun('error', { from, subject }, 'receipt handling threw, fell through to document handling: ' + String((e as Error)?.message||e).slice(0,200)); }
    }

    // ---- HELD FOR REVIEW: a receipt we could not read is never guessed at ----
    // Reaching here from the expenses mailbox means no amount could be read with confidence. The
    // seat's own grant says "A receipt that cannot be read is held for review, never guessed at":
    // nothing is defaulted, nothing is estimated, nothing is booked at zero. It must ALSO stop
    // here rather than fall through to the supplier-document branch below — mail to the expenses
    // mailbox has nothing to do with a supplier record, and that fall-through is exactly how four
    // of the founder's own receipts became "Reviews pending" on his screen in early September.
    // The document is still archived, in receipt-files where the accountant will look for it.
    if (isExpenseMailbox) {
      let heldPath: string | null = null;
      if (att) {
        const hp = `receipts/held/${new Date().toISOString().slice(0,10)}/${Date.now()}_${att.name.replace(/[^A-Za-z0-9._-]/g,'_')}`;
        const up = await admin.storage.from('receipt-files').upload(hp, att.bytes, { contentType: att.mime, upsert: true });
        if (!up.error) heldPath = hp;
      }
      const { data: heldRow } = await admin.from('inbound_messages').insert({
        from_email: from, to_email: to, subject, html: fullHtml, provider_email_id: providerEmailId,
        body: `[HELD — nothing booked: ${(receiptReason || 'no amount could be read').slice(0, 200)}]${heldPath ? ' document: receipt-files/' + heldPath : ' (no readable attachment)'}\n\n` + fullText,
        attachments_count: heldPath ? 1 : 0, matched_existing: false, needs_review: true,
        // Held for the accountant's reasoning (the model hold): the row is the accountant's while it waits, so it never
        // reads as the founder's (receipts_never_wait_on_the_founder, 24 Sep 2026: the Anthropic receipt, row 161).
        ...(reasoningHeld ? { owner_role: 'accountant' } : {}),
      }).select('id').maybeSingle();
      if (!reasoningHeld) await handToBookkeeper(heldRow?.id, [], (receiptReason || 'No amount could be read from this email.') + (heldPath ? ' The document is archived at receipt-files/' + heldPath + '. Read it, then book the expense in expense_entries (source \'receipt\') and post it with fn_expense_post_to_gl.' : ' No attachment could be read, so ask for a re-forward.'));
      await logRun('ok', { expenses_mailbox: 1, receipt: true, booked: false, held: true, doc_archived: !!heldPath, from, subject }, 'receipt HELD for review, not guessed at: ' + (receiptReason || 'no amount could be read').slice(0, 300));
      return J({ ok: true, receipt: true, booked: false, held: true, reason: kind === null ? 'awaiting_reasoning' : kind === 'other' ? 'not_an_expense_document' : 'amount_unreadable', doc: heldPath });
    }
    return { ...ctx, reasoningHeld, receiptish, receiptReason };
}
export type Out = Exclude<Awaited<ReturnType<typeof receipts>>, Response>;
