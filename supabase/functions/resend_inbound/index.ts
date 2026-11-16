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
// v17 (15 Nov 2026, it_engineer): THE WEBHOOK RECORDS, THE READER READS (see below and lib/queue.ts). The steps run unchanged,
//      in pipeline.ts, after the delivery is recorded in public.inbound_mail_queue and answered.
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
import { ackThenWork, runtimeWaitUntil } from '../_shared/async_webhook.ts';
import { requireInternal } from '../_shared/internal_auth.ts';
import { authenticate } from './steps/authenticate.ts';
import { readDelivery } from './pipeline.ts';
import { acceptDelivery, drainQueue, INLINE_PAYLOAD_MAX, type QueueRow, type ReaderDeps } from './lib/queue.ts';
import { admin, J, logRun } from './lib/runtime.ts';
export { useThinkDeps } from './lib/think_deps.ts';

// THE WEBHOOK RECORDS, THE READER READS (it_engineer, 15 Nov 2026; scripts/sql/an_inbound_burst_is_accepted_at_once_and_read_in_turn.sql).
// 18 receipts in 3 minutes, each read inside its own request: 546 and 504, 5 of 18 recorded. A delivery is now verified, recorded
// in public.inbound_mail_queue under the provider's id and answered at once; the reading (pipeline.ts, unchanged) runs after the
// answer, one message at a time per reader and at most two readers at once. ?drain=1 is the minute kick (pg_cron
// inbound_mail_drain, db.internal credential): it answers 202 and reads whatever is due.
const rpc = (fn: string, args: Record<string, unknown>) => admin.rpc(fn, args);
/** One claimed message, read as the webhook read it: its body exactly as verified, its svix-id (the receipt key's fallback). */
export function readQueued(row: QueueRow): Promise<Response> {
  const headers = new Headers(); if (row.svix_id) headers.set('svix-id', row.svix_id);
  return readDelivery({ req: new Request('http://resend_inbound.queue/' + row.id, { method: 'POST', headers }), raw: row.payload });
}
// The reader's dependencies and the runtime's waitUntil. A test injects stand-ins; nothing else does.
let readerOver: Partial<ReaderDeps> & { waitUntil?: (p: Promise<unknown>) => void } = {};
export function useReader(o: Partial<ReaderDeps> & { waitUntil?: (p: Promise<unknown>) => void } | null) { readerOver = o || {}; }
const readInBackground = (ack: Response, label: string) =>
  ackThenWork(ack, () => drainQueue({ rpc, read: readQueued, log: logRun, ...readerOver }), label, readerOver.waitUntil ?? runtimeWaitUntil());

// Exported so its test drives the real handler; the runtime serves it (a test sets RESEND_INBOUND_NO_SERVE).
export const handler = observe('resend_inbound', async (req) => {
  try {
    if (new URL(req.url).searchParams.get('drain') === '1') {
      const body = await req.json().catch(() => ({}));
      const auth = await requireInternal(admin, body?.__secret, 'resend_inbound');
      if (!auth.ok) return J({ error: 'forbidden' }, 403);
      return readInBackground(J({ ok: true, reading: true }, 202), 'resend_inbound reader');
    }
    const c1 = await authenticate({ req }); if (c1 instanceof Response) return c1;
    if (c1.raw.length > INLINE_PAYLOAD_MAX) {
      await logRun('ok', { inbound_queue: 0, inline: 1, bytes: c1.raw.length }, 'a ' + Math.round(c1.raw.length / 1048576) + ' MB delivery (attachments inlined) is read in the request, as before the queue: it is larger than a queue row should hold.');
      return await readDelivery(c1);
    }
    const acc = await acceptDelivery(rpc, c1.raw, req.headers.get('svix-id') || req.headers.get('webhook-id') || '');
    if (!acc.ok) {
      await logRun('error', { inbound_queue: 1, stage: 'accept' }, 'resend_inbound could not record an inbound e-mail in inbound_mail_queue (' + acc.error + '). It answered 503, so the sender delivers it again; nothing was read and nothing was lost.');
      return J({ error: 'inbound queue unavailable' }, 503);
    }
    return readInBackground(J({ ok: true, queued: !acc.duplicate, duplicate: acc.duplicate, queue_id: acc.id }), 'resend_inbound');
  } catch (e) { const m = String((e as Error)?.message || e); await logRun('error', {}, 'exception (inbound email dropped): ' + m); return J({ error: m }, 500); }
});
if (!Deno.env.get('RESEND_INBOUND_NO_SERVE')) Deno.serve(handler);
