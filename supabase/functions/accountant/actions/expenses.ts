// accountant — the expenses mailbox: expense_sweep.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (the 1,715-line index.ts split into modules, a pure move).
import { readEveryAttachment, envGatewayVision } from '../../_shared/read_every_attachment.ts';
// The sweep runs the SAME code the live webhook runs. Nothing about reading a receipt is
// reimplemented here: receipt_parse reads the text, pdf_text reads the PDF's text layer,
// attachment.ts sanitises by magic bytes, safe_url refuses an SSRF target, and the ledger posting
// is fn_expense_post_to_gl. This file only walks the history and hands each message to them.
import { parseAmount, parseReceipt } from '../../_shared/receipt_parse.ts';
import { defaultDeps } from '../../_shared/think.ts';
import { documentKind, readingOf, receiptVendor, type ExpenseMail } from '../../_shared/reasoned_books.ts';
import { pdfText } from '../../_shared/pdf_text.ts';
import { sanitizeUpload, SAFE_UPLOAD } from '../../_shared/attachment.ts';
// MALWARE WATCH, 9 Sep 2026 — see _shared/malware.ts. The historical sweep pulls attachments out of
// a mailbox anybody can send to, so the same verdict applies here as on the live inbound path.
import { sanitizeAndScan } from '../../_shared/malware.ts';
import { safeFetch } from '../../_shared/safe_url.ts';
import { timedFetch } from '../../_shared/timed_fetch.ts';
// A receipt whose email carried no vendor file gets a PDF PRINT of the email, not a .html blob.
import { emailPrintPdf } from '../../_shared/email_print.ts';
import { decideJudgement, recallCases } from '../../_shared/case_recall.ts';
import { statementRowText, takeInStatement } from '../../_shared/bank_statement_intake.ts';
import { registerRowsFor, survivingEntryId } from '../../_shared/expense_mailbox.ts';
import { type ActionCtx, EXPENSE_MAILBOX, J, SUPA_URL, admin, run, sec } from '../context.ts';
import { embed } from '../lib/embed.ts';
import { dbxSafe, pickBody } from '../lib/mail_text.ts';

export async function expenseActions(c: ActionCtx): Promise<Response | undefined> {
  const { body, action, caller } = c;
    // ── EXPENSE_SWEEP ──────────────────────────────────────────────────────────────────────────
    // THE HISTORICAL SWEEP. Deterministic end to end: not one model call on this path.
    //
    // It is IDEMPOTENT on the same key the live webhook uses. expense_entries.source_msg_id is
    // 'resend:<email_id>' and carries a plain unique index, and the lookup below is UNFILTERED BY
    // STATUS — a row holding the key wins outright whatever state it is in, which is the
    // fn_agent_action_work_sweep trap avoided (a status-filtered guard over a unique key says "go
    // ahead", the insert then violates the index, and the work is lost with no record of why).
    // Run it twice and the second run books nothing; run it against a mailbox the webhook has
    // already drained and it books nothing either.
    //
    // NOTHING IS EVER GUESSED. A message whose amount cannot be read is archived, recorded as an
    // inbound_messages row, and handed to this seat as a task by fn_receipt_hand_to_bookkeeper,
    // with the reason in words. It is never booked at zero, never estimated from a sibling receipt,
    // and never quietly dropped — spend_report counts it as HELD so the total says it is short.
    if (action === 'expense_sweep') {
      const rkey = await sec('resend_api_key');
      if (!rkey) {
        await run('expense_sweep', 'error', {}, 'app_secrets.resend_api_key is unreadable, so the mailbox history could not be listed. Nothing was swept.');
        return J({ ok: false, error: 'resend_api_key_unavailable' }, 503);
      }
      const dryRun = body.dry_run === true;
      const maxPages = Math.min(Number(body.max_pages) || 20, 50);

      // THE ALLOWLIST IS THE WEBHOOK'S, READ FROM THE SAME PLACE. Widening it here would create a
      // second policy to keep in step with resend_inbound, and the one that drifted would be this.
      const adminList = String(await sec('admin_emails') || 'management@quotesdone.com').toLowerCase().split(',').map((x) => x.trim()).filter(Boolean);
      const fwdList = String(await sec('expense_forwarders') || '').toLowerCase().split(',').map((x) => x.trim()).filter(Boolean);
      const allowed = new Set([...adminList, ...fwdList]);

      const R = (u: string) => timedFetch(u, { headers: { Authorization: 'Bearer ' + rkey } });

      // 1. THE WHOLE HISTORY, PAGED. `has_more` is Resend's own answer, not an inference from a
      //    short page; the loop stops on it, and pages_capped says so when the cap stopped it instead.
      const history: Record<string, unknown>[] = [];
      let after: string | null = null; let pages = 0; let capped = false; let listError = '';
      for (;;) {
        const u = new URL('https://api.resend.com/emails/inbound');
        u.searchParams.set('limit', '100');
        if (after) u.searchParams.set('after', after);
        const r = await R(u.toString());
        // deno-lint-ignore no-explicit-any
        const j: any = await r.json().catch(() => ({}));
        pages++;
        if (!r.ok) { listError = 'HTTP ' + r.status + ' ' + JSON.stringify(j).slice(0, 200); break; }
        const items = (j.data || j.items || []) as Record<string, unknown>[];
        history.push(...items);
        if (!j.has_more || !items.length) break;
        after = String(items[items.length - 1].id);
        if (pages >= maxPages) { capped = true; break; }
      }
      if (listError && !history.length) {
        await run('expense_sweep', 'error', { pages }, 'the Resend inbound history could not be listed (' + listError + '). Nothing was swept, and no total may be read as complete.');
        return J({ ok: false, error: 'history_unreadable', detail: listError }, 502);
      }

      const toList = (v: unknown): string[] => (Array.isArray(v) ? v : [v]).map((x) => String(x || '').toLowerCase().trim()).filter(Boolean);
      // body.email_id narrows the sweep to ONE message (reprocessing a single email after a fix).
      const only = String(body.email_id || '').trim();
      const mine = history.filter((m) => toList(m.to).some((a) => a === EXPENSE_MAILBOX || a.split('@')[0] === 'expenses'))
        .filter((m) => !only || String(m.id) === only);

      // The reasoning's context, once per sweep: the vendors and register the books carry, and the renewals.
      const booksDeps = defaultDeps(admin, 'accountant');
      const { data: booksCtx } = await admin.rpc('fn_accountant_reading_context');
      const booksVendors: string[] = Array.isArray(booksCtx?.vendors) ? booksCtx.vendors : [];
      const booksRegister = Array.isArray(booksCtx?.register) ? booksCtx.register : [];
      const booksRenewals = Array.isArray(booksCtx?.renewals) ? booksCtx.renewals : [];

      const results: Record<string, unknown>[] = [];
      let booked = 0, already = 0, held = 0, refused = 0, failed = 0;

      for (const h of mine) {
        const emailId = String(h.id || '');
        const msgKey = 'resend:' + emailId;
        const from = String(h.from || '').toLowerCase().trim();
        const to = toList(h.to)[0] || EXPENSE_MAILBOX;
        const subject = String(h.subject || '').slice(0, 300);
        const seenAt = String(h.created_at || '');
        const say = (verdict: string, extra: Record<string, unknown> = {}) =>
          results.push({ email_id: emailId, received_at: seenAt, from, subject, verdict, ...extra });

        // ALREADY BOOKED wins before anything else is fetched. Unfiltered by status, deliberately.
        const { data: prior } = await admin.from('expense_entries')
          .select('id,vendor,amount,currency,charged_on,doc_path').eq('source_msg_id', msgKey).limit(1);
        if (prior && prior.length) {
          already++;
          say('already_booked', { entry_id: prior[0].id, vendor: prior[0].vendor, amount: prior[0].amount, currency: prior[0].currency, charged_on: prior[0].charged_on });
          continue;
        }

        // THE SENDER GATE, BEFORE ANY EXTRACTION. Same rule, same source, same reason as the
        // webhook: mail to the expenses mailbox from someone who is not a permitted forwarder is a
        // decision somebody should see, not silence — so it is RECORDED and handed over, not dropped.
        if (!allowed.has(from)) {
          refused++;
          if (!dryRun) {
            const { data: refusedRow } = await admin.from('inbound_messages').insert({
              from_email: from, to_email: to, subject,
              body: '[REFUSED — sender is not on app_secrets.expense_forwarders] found by the accountant historical sweep; nothing was booked and no document was stored. Resend inbound id ' + emailId,
              attachments_count: 0, matched_existing: false, needs_review: true,
            }).select('id').maybeSingle();
            if (refusedRow?.id) {
              await admin.rpc('fn_receipt_hand_to_bookkeeper', { p_inbound_id: refusedRow.id, p_review_ids: [], p_reason: ('Historical sweep: mail to ' + to + ' from ' + from + ' on ' + seenAt + ' was REFUSED because that address is not on app_secrets.expense_forwarders. Nothing was booked. Decide whether this sender should be added; if it is a company expense, add them and re-run the sweep.').slice(0, 600) });
            }
          }
          say('refused_sender_not_allowlisted');
          continue;
        }

        // 2. THE MESSAGE ITSELF. The list endpoint carries no body, so the full message is fetched
        //    for its text and its attachments.
        const fr = await R('https://api.resend.com/emails/inbound/' + emailId);
        if (!fr.ok) {
          failed++;
          say('unreadable_message', { detail: 'GET /emails/inbound/' + emailId + ' returned HTTP ' + fr.status });
          continue;
        }
        // deno-lint-ignore no-explicit-any
        const fj: any = await fr.json().catch(() => ({}));
        // deno-lint-ignore no-explicit-any
        const d: any = fj.data || fj;
        const text = String(pickBody(d) || '').slice(0, 8000);

        // 3. THE DOCUMENT. Fetched through safeFetch (the download URL comes out of a response
        //    body, and this runs on the service-role network), sanitised by magic bytes, and read
        //    with pdf_text — which returns '' rather than glyph noise, so a scanned receipt is
        //    honestly unreadable instead of confidently wrong.
        const atts: Record<string, unknown>[] = Array.isArray(d.attachments) ? d.attachments : (Array.isArray(h.attachments) ? h.attachments as Record<string, unknown>[] : []);
        let att: { bytes: Uint8Array; name: string; mime: string; ext: string } | null = null;
        const fileNotes: string[] = [];
        // A BANK STATEMENT IS NOT A RECEIPT (14 Sep 2026, duty 1). It is read into bank_statement_line
        // for the payout reconciliation and never booked as an expense. A CSV export (the .csv extension is a
        // file-format fact) is read as text only (it is parsed, not stored) and used only if the message is
        // REASONED to be a statement; the PDF goes through the same sanitiser as any receipt.
        let csvText = '';
        for (const a of atts.slice(0, 8)) {
          const fn = String(a.filename || a.name || '');
          const mm = String(a.content_type || a.contentType || '');
          if (/\.csv$/i.test(fn) && !csvText) {
            const car = await R('https://api.resend.com/emails/inbound/' + emailId + '/attachments/' + a.id);
            // deno-lint-ignore no-explicit-any
            const caj: any = car.ok ? await car.json().catch(() => ({})) : {};
            const curl = String((caj.data || caj).download_url || (caj.data || caj).url || '');
            const cgot = curl ? await safeFetch(curl, { timeoutMs: 15_000, maxBytes: 5 * 1024 * 1024 }) : null;
            if (cgot && cgot.ok) csvText = new TextDecoder().decode(cgot.bytes);
            else fileNotes.push(fn + ': statement CSV could not be fetched');
            continue;
          }
          if (!(/pdf|^image\//i.test(mm) || /\.(pdf|jpe?g|png|webp)$/i.test(fn))) continue;
          const ar = await R('https://api.resend.com/emails/inbound/' + emailId + '/attachments/' + a.id);
          if (!ar.ok) { fileNotes.push(fn + ': attachment endpoint returned HTTP ' + ar.status); continue; }
          // deno-lint-ignore no-explicit-any
          const aj: any = await ar.json().catch(() => ({}));
          const ao = aj.data || aj;
          const url = String(ao.download_url || ao.url || '');
          if (!url) { fileNotes.push(fn + ': no download url'); continue; }
          const got = await safeFetch(url, { timeoutMs: 15_000, maxBytes: 25 * 1024 * 1024 });
          if (!got.ok) { fileNotes.push(fn + ': ' + got.error + ' ' + String(got.detail || '')); continue; }
          const sc = await sanitizeAndScan({ input: got.bytes, declaredMime: mm, filename: fn, allow: SAFE_UPLOAD,
                                             scan: { source: 'accountant.receipt_sweep', subject: String(from || ''), filename: fn, bucket: 'receipt-files' } });
          if (!sc.ok) { fileNotes.push(fn + ': refused (' + sc.body.error + ': ' + sc.body.detail + ')'); continue; }
          const san = sc.result;
          fileNotes.push(fn + ': ' + san.bytes.length + ' bytes');
          att = { bytes: san.bytes, name: fn || ('receipt.' + san.ext), mime: san.mime, ext: san.ext };
          if (san.mime === 'application/pdf') break;   // the PDF is the receipt; an image is a fallback
        }
        let docText = '';
        let readNote = '';
        if (att && att.mime === 'application/pdf') {
          docText = await pdfText(att.bytes);
          if (!docText) readNote = 'The attached PDF carries no text layer we can trust — scanned, or a font we cannot map — so nothing was read from the file. ';
        } else if (att) {
          readNote = 'The receipt is an image, which has no text layer. ';
        }
        // RULING 1177 (12 Oct 2026): a scanned PDF or a photographed receipt is READ by the vision model (_shared/
        // read_every_attachment: one more asking, the gateway's second model). Held only when both askings fail.
        if (att && !docText) {
          const seen = await readEveryAttachment(att.bytes, att.name, att.mime, envGatewayVision());
          if (seen.status === 'read') { docText = seen.text.slice(0, 8000); readNote = ''; }
          else readNote += 'The vision model could not read it either (' + String(seen.reason || 'no answer').slice(0, 80) + '), so it is held for a clearer copy. ';
        }
        // THE STATEMENT'S TABLE NEEDS ITS ROWS (14 Sep 2026). Measured on the founder's real Mashreq
        // e-statement: pdf_text returns '' for it (its Arabic captions are glyph noise, correctly refused by
        // looksLikeText), and its filename and forwarder name no bank. The positioned reader rebuilds the rows;
        // that text is used ONLY to recognise and read a statement — a receipt keeps pdf_text's guard.
        // One recogniser and one intake for this sweep AND the live webhook (_shared/bank_statement_intake.ts).
        // WHAT IS IT (23 Sep 2026, founder_instruction 886-903): reasoned over the envelope, the note and the
        // document's rows (_shared/reasoned_books.ts documentKind), never a word test. Held: not booked, held.
        const rowText = att && att.mime === 'application/pdf' ? await statementRowText(att) : '';
        const mail: ExpenseMail = { emailId, from, to, subject, text, docText: [rowText || docText, csvText.slice(0, 2000)].filter(Boolean).join('\n').slice(0, 4000),
          filenames: atts.map((a) => String(a.filename || a.name || '')), mailbox: 'expenses', providerEmailId: emailId, dryRun };
        const kind = (await documentKind(booksDeps, mail, booksRenewals, booksRegister)).value;
        if (kind === 'bank_statement') {
          const stIn = await takeInStatement(admin, {
            from, subject, filenames: mail.filenames,
            pdf: att && att.mime === 'application/pdf' ? att : null, csvText, docText, rowText, readNote,
            sourceRef: msgKey, archivePath: 'bank/' + seenAt.slice(0, 10) + '/' + emailId, dryRun });
          say(stIn.error ? 'bank_statement_failed' : 'bank_statement', { ...stIn, files: fileNotes });
          continue;
        }
        // Waiting for reasoning: the accountant's queue owns it (expense_kind:<email id>) and replays this sweep for it.
        // Nothing is recorded or handed over twice meanwhile, however often the sweep runs.
        if (kind === null) { held++; say('awaiting_reasoning', { files: fileNotes }); continue; }
        else if (kind === 'other') readNote += "Reasoned: this is not a document of the company's own spending. ";
        // The PDF text is APPENDED, so the forwarded "From:" header still names the original vendor
        // and a figure in the covering note still wins over one in the file.
        const parseBody = docText ? (text + '\n' + docText) : text;

        // Who issued it and how often it bills are REASONED; the figures are parsed. No amount: no model call.
        const reading = kind ? readingOf(kind) : null;
        let det: ReturnType<typeof parseReceipt> = null;
        if (reading && (parseAmount(parseBody) || parseAmount(subject))) {
          const vendor = (await receiptVendor(booksDeps, { ...mail, docText: docText.slice(0, 4000) }, booksVendors)).value;
          if (vendor) det = parseReceipt({ subject, body: parseBody, vendor, period: reading.period });
          else { held++; say('awaiting_reasoning', { files: fileNotes }); continue; }
        } else if (reading) {
          readNote += 'No amount could be read beside a currency mark. ';
        }

        // 4a. HELD. Named, archived, owned. Never a number.
        if (!det) {
          held++;
          const why = readNote + 'It is NOT booked and NOT estimated.';
          if (dryRun) { say('held', { reason: why, files: fileNotes }); continue; }
          let heldPath: string | null = null;
          if (att) {
            const hp = 'held/' + seenAt.slice(0, 10) + '/' + Date.now() + '_' + (subject || 'receipt').replace(/[^A-Za-z0-9._-]/g, '_').slice(0, 60) + '.' + att.ext;
            const up = await admin.storage.from('receipt-files').upload(hp, att.bytes, { contentType: att.mime, upsert: true });
            if (!up.error) heldPath = hp;
          }
          const { data: heldRow } = await admin.from('inbound_messages').insert({
            from_email: from, to_email: to, subject,
            body: '[HELD — nothing booked: ' + readNote.slice(0, 200) + '] accountant historical sweep, Resend inbound id ' + emailId + (heldPath ? ', document: receipt-files/' + heldPath : ' (no readable attachment)') + '\n\n' + text.slice(0, 8000),
            attachments_count: heldPath ? 1 : 0, matched_existing: false, needs_review: true,
          }).select('id').maybeSingle();
          if (heldRow?.id) {
            await admin.rpc('fn_receipt_hand_to_bookkeeper', { p_inbound_id: heldRow.id, p_review_ids: [], p_reason: (why + (heldPath ? ' The document is archived at receipt-files/' + heldPath + '. Read it, then book the expense in expense_entries with source_msg_id ' + msgKey + ' and post it with fn_expense_post_to_gl.' : ' No attachment could be read, so ask for a re-forward.')).slice(0, 600) });
          }
          say('held', { reason: why, document: heldPath, files: fileNotes, inbound_id: heldRow?.id ?? null });
          continue;
        }

        // 4b. BOOKED.
        const vendor = String(det.vendor).slice(0, 120);
        const amount = Number(det.amount);
        const currency = String(det.currency).toUpperCase().replace(/[^A-Z]/g, '').slice(0, 3) || 'USD';
        const charged = det.date;
        const cad = det.period === 'annual' ? 'annual' : (det.period === 'one_off' ? 'one_off' : 'monthly');
        const recurring = det.recurring;
        const vatAmt = det.vat !== null && det.vat > 0 && det.vat < amount ? det.vat : null;
        const trn = /^\d{15}$/.test(String(det.trn || '')) ? String(det.trn) : null;

        if (dryRun) {
          booked++;
          say('would_book', { vendor, amount, currency, charged_on: charged, period: cad, vat: vatAmt, trn, basis: det.basis, files: fileNotes });
          continue;
        }

        // The evidence, archived where the accountant looks for it. A booking is NOT blocked by a
        // failed archive — an expense with no document is a VAT-record gap, an unbooked expense is
        // a hole in the accounts — but the failure is said out loud rather than swallowed.
        // 9 SEP 2026 — AND IT IS A DOCUMENT, NOT A .HTML BLOB. The founder: "i wanna be able to
        // click any record and see the actual invoice or receipt or email print pdf if none exist".
        // The vendor's own attachment is the document when there is one; when there is not, the
        // email is PRINTED TO PDF rather than dumped as raw HTML, and doc_kind records which of the
        // two this row holds so the OS never has to infer provenance from a filename. The HTML
        // upload survives only as the fallback-of-the-fallback: a pdf_native outage must degrade
        // the document, never lose the email.
        let docPath: string | null = null; let upErr = '';
        let docName = att ? att.name : 'receipt.html';
        let docType = att ? att.mime : 'text/html';
        let docKind: 'vendor_document' | 'email_print' = att ? 'vendor_document' : 'email_print';
        let docNote: string | null = att
          ? "The vendor's own file, taken off the source email (Resend inbound " + emailId + ').'
          : null;
        let printBytes: Uint8Array | null = null;
        if (!att) {
          const printed = await emailPrintPdf(admin, SUPA_URL, {
            entryId: null, vendor, amount, currency, chargedOn: charged,
            sourceMsgId: msgKey, subject, from, to, date: seenAt,
            text, html: String(d.html || ''), attachmentNames: [],
          });
          if (printed.ok) {
            docPath = printed.path;            // pdf_native NAMED this path; used exactly as returned
            docName = printed.name; docType = 'application/pdf';
            docNote = 'The source email carried no vendor file, so this is a PDF print of the email itself.';
          } else {
            const html = String(d.html || text || subject);
            printBytes = new TextEncoder().encode('<meta charset="utf-8"><pre style="font:14px/1.5 monospace;white-space:pre-wrap">' + html.replace(/</g, '&lt;') + '</pre>');
            docNote = 'The source email carried no vendor file, and the email could not be printed to PDF ('
              + printed.reason + '), so the message body is archived as HTML instead.';
          }
        }
        const uploadBytes = att ? att.bytes : printBytes;
        const ext = att ? att.ext : 'html';
        if (uploadBytes && !docPath) {
          for (let attempt = 1; attempt <= 3 && !docPath; attempt++) {
            const rp = 'receipts/' + charged + '/' + Date.now() + '_' + vendor.replace(/[^A-Za-z0-9._-]/g, '_') + '.' + ext;
            try {
              const up = await admin.storage.from('receipt-files').upload(rp, uploadBytes, { contentType: docType, upsert: true });
              if (!up.error) docPath = rp; else upErr = String(up.error.message || '').slice(0, 150);
            } catch (e) { upErr = String((e as Error)?.message || e).slice(0, 150); }
            if (!docPath && attempt < 3) await new Promise((r) => setTimeout(r, 400 * attempt));
          }
        }

        // HOW WAS A RECEIPT LIKE THIS CLASSIFIED BEFORE? (23 Sep 2026.) By meaning, this seat's own
        // finalised classifications only. A precedent that was CORRECTED (re-classified by hand) wins
        // over the default rule, and the entry says which case it followed.
        const situation = `vendor ${vendor} | ${currency} ${amount} | ${subject}`;
        const memory = await recallCases(admin, { seat: 'accountant', path: 'expense_classification', caseKind: 'expense_classification',
          otherSeats: false, situation, embedding: await embed(situation) });
        const precedentCase = memory.cases.find((c) => c.finalised && c.correction && c.outcome);
        const category = precedentCase?.outcome ?? (recurring ? 'Subscription' : 'Usage');
        const { data: insRow } = await admin.from('expense_entries')
          .upsert({
            vendor, category, amount, currency, charged_on: charged,
            note: ('accountant historical sweep of the expenses mailbox: ' + subject + ' [' + det.basis + (docText ? ' src=pdf_text' : '')
              + (precedentCase ? ' precedent=#' + precedentCase.case_id : '') + ']').slice(0, 300),
            source: 'receipt', doc_path: docPath, doc_name: docName.slice(0, 180), doc_content_type: docType,
            doc_kind: docPath ? docKind : null, doc_note: docPath ? docNote : null,
            source_msg_id: msgKey, vat_amount: vatAmt, vendor_trn: trn, read_as: reading?.readAs ?? null, renews_item: reading?.renewsItem ?? null,
          }, { onConflict: 'source_msg_id', ignoreDuplicates: true })
          .select('id').maybeSingle();
        let entryId: number | null = (insRow?.id as number | undefined) ?? null;
        if (!entryId) {
          // a concurrent webhook delivery won the unique key between the lookup and this insert;
          // read its row rather than inventing a second expense
          const { data: won } = await admin.from('expense_entries').select('id').eq('source_msg_id', msgKey).limit(1);
          entryId = (won?.[0]?.id as number | undefined) ?? null;
        }
        if (!entryId) { failed++; say('book_failed', { vendor, amount, currency, charged_on: charged }); continue; }
        // The classification's judgement names the corrected precedent it followed (or none), in the trace
        // rather than only in the note text.
        await decideJudgement(admin, memory, `expense ${entryId} classified ${category}`, precedentCase ? [precedentCase.case_id] : []);

        // THE LEDGER. Nothing calls fn_gl_sync_business on a schedule, so the entry is posted here
        // under source='expense'/source_ref — the same key the bulk routine uses, so neither can
        // double-post the other. A currency with no rate is NOT booked at 1:1: the routine returns
        // null and raises a founder_alert, and this sweep reports the null rather than hiding it.
        const { data: jid, error: glErr } = await admin.rpc('fn_expense_post_to_gl', { p_entry_id: entryId });
        // 15 Nov 2026 (review item 6): a receipt for a cost held on the founder's word is folded into that entry (this
        // row deleted, its key moved); the evidence is filed against the row that survives, read back by the key.
        const survivor = await survivingEntryId(admin, entryId, msgKey);
        if (docPath && survivor) {
          // doc_backups is the Sales Engineer's existing filing contract and dropbox_backup reads
          // it by status, not by entity; dedupe_key makes a re-sweep a no-op.
          await admin.from('doc_backups').insert({
            entity: 'expense', entity_id: String(survivor), doc_type: 'Receipt',
            bucket: 'receipt-files', path: docPath, file_name: docName.slice(0, 180),
            dropbox_path: '/QuotesDone Backup/Finance/Receipts/' + charged.slice(0, 7) + '/' + dbxSafe(vendor) + ' ' + charged + ' - ' + dbxSafe(docName),
            source: 'storage', dedupe_key: 'E:' + survivor + ':receipt:' + docPath,
          });
        }
        if (recurring) {
          const erow = { vendor, category: 'Subscription', description: subject.slice(0, 300), amount, currency, cadence: cad, expense_date: charged, active: true, source: 'email_forward', confidence: 'medium', note: 'from the accountant historical sweep of the expenses mailbox' };
          // The register row is the SAME vendor (identity of the reasoned name), never a LIKE pattern (instr 890).
          const ex0 = await registerRowsFor(admin, vendor);
          // The register holds the CURRENT schedule, so only a LATER receipt may move it. The
          // history arrives newest-first, so without this an August receipt would overwrite September.
          if (ex0 && ex0.length) { if (!ex0[0].expense_date || String(ex0[0].expense_date) <= charged) await admin.from('expenses').update(erow).eq('id', ex0[0].id); }
          else await admin.from('expenses').insert(erow);
        }
        await admin.from('inbound_messages').insert({
          from_email: from, to_email: to, subject,
          body: '[expense ' + (recurring ? 'subscription' : 'one-off') + '] ' + vendor + ' ' + amount + ' ' + currency + ' on ' + charged + (docPath ? ' +' + ext : '') + ' — accountant historical sweep, Resend inbound id ' + emailId,
          attachments_count: docPath ? 1 : 0, matched_existing: false, needs_review: false,
        });
        booked++;
        say('booked', {
          entry_id: survivor ?? entryId, vendor, amount, currency, charged_on: charged, period: cad,
          vat: vatAmt, trn, gl_journal: (jid as number | null) ?? null,
          gl_error: glErr ? String(glErr.message).slice(0, 200) : null,
          document: docPath, document_error: docPath ? null : upErr, basis: det.basis, files: fileNotes,
        });
      }

      const counts = {
        history_messages: history.length, to_expense_mailbox: mine.length,
        booked, already_booked: already, held, refused, failed,
        pages, pages_capped: capped, list_error: listError || null, dry_run: dryRun,
      };
      // agent_runs IS the coverage record spend_report quotes. Without it the report could say how
      // much was booked but not how much was LOOKED AT, and a total nobody can bound is not a total.
      await run('expense_sweep', (failed || listError) ? 'error' : 'ok', counts,
        'Swept the Resend inbound history: ' + history.length + ' messages in total, ' + mine.length + ' addressed to ' + EXPENSE_MAILBOX + '. Booked ' + booked + ', already booked ' + already + ', held ' + held + ', refused ' + refused + ', failed ' + failed + '.' + (capped ? ' PAGING WAS CAPPED, so the history may be incomplete.' : '') + (listError ? ' Listing error: ' + listError : ''));

      return J({
        ok: true, seat: 'accountant', caller: caller.kind, mailbox: EXPENSE_MAILBOX, ...counts, messages: results,
        // body.email_id that matched no message to the mailbox is said, so a replay never reads "delivered" for nothing
        found: only ? mine.length > 0 : undefined,
        basis: 'What each message is and who issued it were reasoned (supabase/functions/_shared/reasoned_books.ts, through think()); every figure was read from the message by supabase/functions/_shared/receipt_parse.ts and, where a PDF carried a text layer, supabase/functions/_shared/pdf_text.ts. A message whose meaning waits for reasoning, or whose amount could not be read, is counted as held and named in `messages`; it is never booked at zero and never estimated.',
      });
    }
}
