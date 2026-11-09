// resend_inbound v15 - inbound emails. Webhook metadata-only; body via GET /emails/inbound/{id}; attachments via
// /attachments/{id} -> download_url. Receipts -> finance. Supplier docs -> store + AI classify + AUTO-EXTRACT
// (trade licence -> licence no/authority/emirate/expiry/TRN; profile/catalogue -> capability) applied to the matched lead.
// v12: agent_runs instrumentation for silently-lost inbound documents.
// v13: Svix signature verification (see PROVENANCE below).
// v14: DUPLICATE-EXPENSE FIX (see DEDUP below).
// v15: RECEIPT ARCHIVE RETRY + BACKFILL (see v15 FIX below). v14's dedup guard returned before any
//      upload was attempted, which silently made "re-forward the email to retry" impossible.
// v16 (6 Sep 2026): DETERMINISTIC RECEIPT EXTRACTION FIRST (_shared/receipt_parse.ts); the model is the
//      fallback. A receipt nobody could book is handed to the BOOKKEEPER (fn_receipt_hand_to_bookkeeper)
//      and its rows carry owner_role, so the founder's Inbox and Reviews never show his own receipts.
//
// v13 SECURITY FIX 19 Jul 2026 -----------------------------------------------------------------
// v12 authenticated ONLY on a shared token in the QUERY STRING (?s=...). The full URL including
// that token is stored in the Resend dashboard, lands in browser history and referrer headers, and
// is written to any proxy or access log that records request lines. Anyone holding it could forge
// inbound email events and, because this function BOOKS EXPENSES and WRITES SUPPLIER RECORDS,
// could inject fabricated expense_entries rows, overwrite a supplier's trade licence number, TRN
// and capability summary, and upload arbitrary files into the supplier-docs bucket.
// v13 verifies the SVIX SIGNATURE Resend signs each delivery with (svix-id, svix-timestamp,
// svix-signature) against app_secrets.resend_inbound_signing_secret. The ?s= token is KEPT as a
// second factor - both must now pass. The body is read ONCE as raw text because the signature is
// over the exact bytes; it is parsed only after verification succeeds.
import { observe } from '../_shared/observe.ts';
import { authenticate } from './steps/authenticate.ts';
import { readMail } from './steps/read_mail.ts';
import { marketingReplies } from './steps/marketing_replies.ts';
import { expenseGate } from './steps/expense_gate.ts';
import { bounceUnsubscribe } from './steps/bounce_unsubscribe.ts';
import { receipts } from './steps/receipts.ts';
import { supplierDocs } from './steps/supplier_docs.ts';
import { J, logRun } from './lib/runtime.ts';
export { useThinkDeps } from './lib/think_deps.ts';
// Exported so its test drives the real handler; the runtime serves it (a test sets RESEND_INBOUND_NO_SERVE).
export const handler = observe('resend_inbound', async (req) => {
  try {
    const c1 = await authenticate({ req }); if (c1 instanceof Response) return c1;
    const c2 = await readMail(c1); if (c2 instanceof Response) return c2;
    const c3 = await marketingReplies(c2); if (c3 instanceof Response) return c3;
    const c4 = await expenseGate(c3); if (c4 instanceof Response) return c4;
    const c5 = await bounceUnsubscribe(c4); if (c5 instanceof Response) return c5;
    const c6 = await receipts(c5); if (c6 instanceof Response) return c6;
    return await supplierDocs(c6);
  } catch (e) { const m = String((e as Error)?.message || e); await logRun('error', {}, 'exception (inbound email dropped): ' + m); return J({ error: m }, 500); }
});
if (!Deno.env.get('RESEND_INBOUND_NO_SERVE')) Deno.serve(handler);
