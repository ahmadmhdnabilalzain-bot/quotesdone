// accountant — the document doors: document(s), refund_document(s), revenue_document(s).
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (the 1,715-line index.ts split into modules, a pure move).
import { type ActionCtx, J, admin, run } from '../context.ts';

export async function documentActions(c: ActionCtx): Promise<Response | undefined> {
  const { body, action } = c;
    // ── DOCUMENT ───────────────────────────────────────────────────────────────────────────────
    // THE OS'S WAY FROM AN EXPENSE ROW TO SOMETHING IT CAN OPEN. The founder, 9 Sep 2026: "later
    // when we build the OS i wanna be able to click any record and see the actual invoice or receipt
    // or email print pdf if none exist".
    //
    // receipt-files is a PRIVATE bucket, so a path is not a link — it has to be signed. That signing
    // needs the service role, which no browser may hold, and Postgres cannot mint one (there is no
    // pgjwt in this project; `sign` in pg_catalog is the arithmetic sign function). So the door is
    // here, and it is a door rather than a directory: the caller names an ENTRY, never a path, and
    // fn_expense_document decides what that entry's document is. A caller who could name its own
    // path could read any object in the bucket.
    //
    // A row with no document is answered, not 404'd: ok:false with `state` and the reason in words,
    // so the OS can render "no document" instead of a broken link. `action: 'documents'` lists the
    // whole book's coverage in one call for the same reason.
    if (action === 'document' || action === 'documents') {
      if (action === 'documents') {
        const { data: cov } = await admin.rpc('fn_expense_document_coverage');
        const { data: rows } = await admin.from('v_expense_documents')
          .select('id,vendor,charged_on,amount,currency,source_channel,document_state,doc_kind,doc_name,doc_note')
          .order('id');
        await run('documents', 'ok', (cov || {}) as Record<string, unknown>);
        return J({ ok: true, seat: 'accountant', coverage: cov, entries: rows || [],
          basis: 'public.v_expense_documents, read at call time. document_state is vendor_document, '
            + 'email_print, unclassified or missing — never inferred from a filename.' });
      }
      const entryId = Number(body.entry_id);
      if (!Number.isFinite(entryId) || entryId <= 0) return J({ ok: false, error: 'entry_id is required' }, 400);
      const { data: doc, error: docErr } = await admin.rpc('fn_expense_document', { p_entry_id: entryId });
      if (docErr) return J({ ok: false, error: docErr.message }, 500);
      const d0 = (doc || {}) as Record<string, unknown>;
      if (d0.ok !== true) { await run('document', 'ok', { entry_id: entryId, state: d0.state }); return J({ ok: false, ...d0 }); }
      const ttl = Math.min(Math.max(Number(body.expires_in) || 3600, 60), 7 * 24 * 3600);
      const { data: signed, error: sErr } = await admin.storage
        .from(String(d0.bucket)).createSignedUrl(String(d0.path), ttl);
      if (sErr || !signed?.signedUrl) {
        // A path that will not sign is a path pointing at nothing. Say that, rather than handing
        // back a dead link — a broken document is worse than a declared absence.
        await run('document', 'error', { entry_id: entryId, path: d0.path },
          'expense #' + entryId + ' names a document that could not be signed: ' + String(sErr?.message || 'no url returned')
          + '. The object is missing from receipt-files or the path is wrong.');
        return J({ ok: false, ...d0, state: 'object_unreachable',
          reason: 'The record names a document but the object could not be signed: ' + String(sErr?.message || 'no url returned') }, 502);
      }
      await run('document', 'ok', { entry_id: entryId, kind: d0.kind });
      return J({ ok: true, ...d0, url: signed.signedUrl, expires_in: ttl });
    }

    // ── THE SAME DOOR, FOR A REFUND (9 Sep 2026) ───────────────────────────────────────────────
    // The founder: "when a refund is issued, it's issued against that exact invoice reference ...
    // which also should be available with the accountant and the CEO as a PDF as it is from Stripe."
    // finance-docs is private, so the path has to be signed, and signing needs the service role
    // that no browser may hold. Identical shape to the expense door above and for the same reason:
    // the caller names a REFUND, never a path — a caller who could name its own path could read any
    // object in finance-docs.
    //
    // A refund with no stored file is ANSWERED, not 404'd. `state` distinguishes three real things:
    // 'reference_only' (Stripe's own hosted receipt for the payment is known but has not been
    // fetched into the bucket), 'missing' (nothing at all), and a doc_kind (a file is held). The
    // reply also carries `stripe_binding`, which says whether the refund names the exact Stripe
    // payment of the transaction it reverses.
    if (action === 'refund_document' || action === 'refund_documents') {
      if (action === 'refund_documents') {
        const { data: cov } = await admin.rpc('fn_refund_document_coverage');
        const { data: rows } = await admin.from('v_refund_documents')
          .select('id,transaction_id,status,amount_fils,currency,stripe_payment_intent,stripe_refund_id,stripe_binding,document_state,doc_kind,doc_name,doc_note')
          .order('id');
        await run('refund_documents', 'ok', (cov || {}) as Record<string, unknown>);
        return J({ ok: true, seat: 'accountant', coverage: cov, refunds: rows || [],
          basis: 'public.v_refund_documents, read at call time. document_state is the doc_kind, '
            + '\'unclassified\', \'reference_only\' or \'missing\' — never inferred from a filename. '
            + 'stripe_binding is measured against transactions.payment_ref, never asserted.' });
      }
      const refundId = Number(body.refund_id);
      if (!Number.isFinite(refundId) || refundId <= 0) return J({ ok: false, error: 'refund_id is required' }, 400);
      const { data: doc, error: docErr } = await admin.rpc('fn_refund_document', { p_refund_id: refundId });
      if (docErr) return J({ ok: false, error: docErr.message }, 500);
      const r0 = (doc || {}) as Record<string, unknown>;
      if (r0.ok !== true) { await run('refund_document', 'ok', { refund_id: refundId, state: r0.state }); return J({ ok: false, ...r0 }); }
      const rTtl = Math.min(Math.max(Number(body.expires_in) || 3600, 60), 7 * 24 * 3600);
      const { data: rSigned, error: rErr } = await admin.storage
        .from(String(r0.bucket)).createSignedUrl(String(r0.path), rTtl);
      if (rErr || !rSigned?.signedUrl) {
        // A path that will not sign is a path pointing at nothing. Say so rather than hand back a
        // dead link — a broken document is worse than a declared absence.
        await run('refund_document', 'error', { refund_id: refundId, path: r0.path },
          'refund #' + refundId + ' names a document that could not be signed: ' + String(rErr?.message || 'no url returned')
          + '. The object is missing from finance-docs or the path is wrong.');
        return J({ ok: false, ...r0, state: 'object_unreachable',
          reason: 'The record names a document but the object could not be signed: ' + String(rErr?.message || 'no url returned') }, 502);
      }
      await run('refund_document', 'ok', { refund_id: refundId, kind: r0.kind });
      return J({ ok: true, ...r0, url: rSigned.signedUrl, expires_in: rTtl });
    }

    // ── THE SAME DOOR, FOR THE REVENUE SIDE (9 Sep 2026) ───────────────────────────────────────
    // The founder, instruction 28: "stripe automatically generates an invoice as far as i know, our
    // accountant need to retrieve that and be connected, then add it to his records."
    //
    // Retrieval is stripe_webhook's job and the record is public.transactions; THIS is the part
    // where the accountant can actually open what was filed. Without it the invoices would be a
    // finished capability with no entry point - stored, mirrored to Dropbox, and unreachable from
    // the seat whose books cite them.
    //
    // Identical shape to the expense and refund doors above, for the identical reason: finance-docs
    // is private, signing needs the service role no browser may hold, and the caller names a SALE
    // rather than a path. A sale with no stored file is ANSWERED, not 404'd - 'reference_only' says
    // Stripe issued the invoice and the PDF has not been fetched, which is a different fact from
    // 'missing', which is a different fact again from a reveal that was never charged.
    if (action === 'revenue_document' || action === 'revenue_documents') {
      if (action === 'revenue_documents') {
        const { data: cov } = await admin.rpc('fn_revenue_document_coverage');
        const { data: rows } = await admin.from('v_revenue_documents')
          .select('id,quote_id,revealed_at,fee_status,reveal_fee,payment_ref,stripe_invoice_id,stripe_invoice_number,stripe_invoice_status,stripe_invoice_total_fils,stripe_invoice_currency,invoice_agrees_with_fee,document_state,doc_kind,doc_name,doc_note')
          .eq('fee_was_taken', true).order('revealed_at');
        await run('revenue_documents', 'ok', (cov || {}) as Record<string, unknown>);
        return J({ ok: true, seat: 'accountant', coverage: cov, sales: rows || [],
          basis: 'public.v_revenue_documents, read at call time, restricted to sales that actually '
            + 'took a fee. document_state is the doc_kind, \'unclassified\', \'reference_only\' '
            + '(Stripe issued the invoice, the PDF is not in finance-docs) or \'missing\'. '
            + 'invoice_agrees_with_fee compares Stripe\'s own total against reveal_fee rather than '
            + 'assuming they match.' });
      }
      const txId = String(body.transaction_id || '').trim();
      if (!txId) return J({ ok: false, error: 'transaction_id is required' }, 400);
      const { data: doc, error: docErr } = await admin.rpc('fn_revenue_document', { p_transaction_id: txId });
      if (docErr) return J({ ok: false, error: docErr.message }, 500);
      const t0 = (doc || {}) as Record<string, unknown>;
      if (t0.ok !== true) { await run('revenue_document', 'ok', { transaction_id: txId, state: t0.state }); return J({ ok: false, ...t0 }); }
      const tTtl = Math.min(Math.max(Number(body.expires_in) || 3600, 60), 7 * 24 * 3600);
      const { data: tSigned, error: tErr } = await admin.storage
        .from(String(t0.bucket)).createSignedUrl(String(t0.path), tTtl);
      if (tErr || !tSigned?.signedUrl) {
        // A path that will not sign is a path pointing at nothing. Say so rather than hand back a
        // dead link — a broken document is worse than a declared absence.
        await run('revenue_document', 'error', { transaction_id: txId, path: t0.path },
          'sale ' + txId + ' names an invoice that could not be signed: ' + String(tErr?.message || 'no url returned')
          + '. The object is missing from finance-docs or the path is wrong.');
        return J({ ok: false, ...t0, state: 'object_unreachable',
          reason: 'The record names a document but the object could not be signed: ' + String(tErr?.message || 'no url returned') }, 502);
      }
      await run('revenue_document', 'ok', { transaction_id: txId, kind: t0.kind });
      return J({ ok: true, ...t0, url: tSigned.signedUrl, expires_in: tTtl });
    }
}
