// resend_inbound: the inbound mail queue (it_engineer, 15 Nov 2026). The database side, and the measurement that moved the
// reading out of the webhook request, is scripts/sql/an_inbound_burst_is_accepted_at_once_and_read_in_turn.sql.
//
// THE WEBHOOK RECORDS, THE READER READS. 18 receipts forwarded in 3 minutes were each read inside their own webhook request
// (the Resend read, the attachments, the PDF and vision reads, the booking): most answered 546 WORKER_RESOURCE_LIMIT, some 504
// after 150 s, and 5 of 18 reached inbound_messages. Now acceptDelivery() records the verified delivery under the provider's
// id and the webhook answers; drainQueue() then claims one message at a time (at most fn_inbound_mail_readers() are read at
// once, estate-wide) and hands it to pipeline.ts, renewing its lease while it reads. A thrown error is a failed attempt, read
// again after a backoff; the fifth failure hands the message to the seat that owns it (fn_inbound_mail_dead_letter).
import { addr } from './mail_parse.ts';
import { FINANCE_BOXES } from './receipt_consts.ts';
import { approvalTokenOf, isCalendarReply, planTokenOf } from '../../_shared/marketing_calendar_mail.ts';

// deno-lint-ignore no-explicit-any
export type Rpc = (fn: string, args: Record<string, unknown>) => PromiseLike<{ data: any; error: { message: string } | null }>;
export type QueueRow = { id: number; provider_email_id: string; svix_id: string | null; payload: string; attempts: number; max_attempts: number };
export type OwnerSeat = 'accountant' | 'marketing' | 'customer_support';

/**
 * ONE MESSAGE PER RUN, THEN HAND ON. The edge limits CPU per invocation, and a reading is CPU-heavy (PDF text layer, image
 * sanitising), so a reader that read message after message in one invocation would add up the CPU of all of them and be killed
 * part-way through a later one. Each run reads one message and then asks fn_inbound_mail_kick to start the next reader (one per
 * free slot), so every message is read in an invocation of its own.
 */
export const READS_PER_RUN = 1;
/** No new message is started after this long; one already started is never cut (the edge's own wall clock is the bound). */
export const READ_BUDGET_MS = 45_000;
/** The lease is 150 s in fn_inbound_mail_claim; a live reader renews it this often, so only a dead reader's lease runs out. */
export const LEASE_RENEW_MS = 30_000;
/**
 * A delivery larger than this is read in the request, as before the queue. Resend's deliveries are metadata (a few KB); only the
 * Microsoft 365 reader inlines attachments (base64, up to 6 x 15 MB), and it hands one message at a time from its own tick, so it
 * is not a burst. The bound keeps a queue row, and the PostgREST call that writes it, small.
 */
export const INLINE_PAYLOAD_MAX = 4 * 1024 * 1024;

/**
 * What the queue row records, read off the verified payload alone (no network): the key a redelivery is matched on (the same
 * email id read_mail.ts reads, else the Svix message id), the envelope, the thread whose order is kept, and the seat a dead
 * letter goes to. The finance mailboxes have no thread: eighteen receipts need no order among themselves.
 */
export function envelopeOf(raw: string, svixId: string) {
  // deno-lint-ignore no-explicit-any
  let p: any = {}; try { p = JSON.parse(raw); } catch (_e) { p = {}; }
  // deno-lint-ignore no-explicit-any
  const d: any = (p?.type === 'email.received' && p?.data) ? p.data : (p?.data || p || {});
  const emailId = String(d?.email_id || d?.id || '');
  const from = addr(d?.from); const to = addr(d?.to); const subject = String(d?.subject || '').slice(0, 300);
  const finance = FINANCE_BOXES.has(to.split('@')[0] || '');
  const marketing = isCalendarReply({ to, subject }) || !!approvalTokenOf({ to, subject }) || !!planTokenOf({ to, subject });
  const ownerSeat: OwnerSeat = finance ? 'accountant' : marketing ? 'marketing' : 'customer_support';
  return { providerEmailId: emailId || (svixId ? 'svix:' + svixId : ''), from, to, subject,
           threadKey: finance || !from || !to ? null : from + '>' + to, ownerSeat };
}

export type Accepted = { ok: true; duplicate: boolean; id: number | null } | { ok: false; error: string };

/** The webhook's record (fn_inbound_mail_accept). Not ok: nothing was recorded, and the caller must not answer 2xx. */
export async function acceptDelivery(rpc: Rpc, raw: string, svixId: string): Promise<Accepted> {
  const env = envelopeOf(raw, svixId);
  if (!env.providerEmailId) return { ok: false, error: 'the delivery carries neither an email id nor a Svix message id' };
  try {
    const { data, error } = await rpc('fn_inbound_mail_accept', {
      p_provider_email_id: env.providerEmailId, p_svix_id: svixId || null, p_payload: raw, p_from: env.from, p_to: env.to,
      p_subject: env.subject, p_thread_key: env.threadKey, p_owner_seat: env.ownerSeat });
    if (error || !data) return { ok: false, error: String(error?.message || 'fn_inbound_mail_accept answered nothing').slice(0, 300) };
    return { ok: true, duplicate: data.duplicate === true, id: Number(data.id) || null };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e).slice(0, 300) }; }
}

export type ReaderDeps = {
  rpc: Rpc;
  /** Reads one claimed message; a Response is its outcome, a throw a failed attempt. */
  read: (row: QueueRow) => Promise<Response>;
  log?: (status: string, counts: Record<string, unknown>, note: string) => Promise<void>;
  now?: () => number;
  budgetMs?: number;
  maxReads?: number;
  renewMs?: number;
  worker?: string;
};
export type Tally = { read: number; done: number; retried: number; dead: number; lost: number; finish_failed: number; handed_on: number; claim_error?: string };

/** Claim, read, finish (READS_PER_RUN messages, or fewer when nothing is due or the budget is spent), then hand on. */
export async function drainQueue(deps: ReaderDeps): Promise<Tally> {
  const now = deps.now || Date.now;
  const worker = deps.worker || crypto.randomUUID();
  const budget = deps.budgetMs ?? READ_BUDGET_MS;
  const t0 = now();
  const tally: Tally = { read: 0, done: 0, retried: 0, dead: 0, lost: 0, finish_failed: 0, handed_on: 0 };
  while (tally.read < (deps.maxReads ?? READS_PER_RUN) && now() - t0 < budget) {
    let row: QueueRow | null = null;
    try {
      const { data, error } = await deps.rpc('fn_inbound_mail_claim', { p_worker: worker, p_limit: 1 });
      if (error) { tally.claim_error = String(error.message).slice(0, 300); break; }
      row = Array.isArray(data) && data.length ? data[0] as QueueRow : null;
    } catch (e) { tally.claim_error = String((e as Error)?.message || e).slice(0, 300); break; }
    if (!row) break;
    tally.read++;
    const claimed = row;
    const renew = setInterval(() => {
      Promise.resolve(deps.rpc('fn_inbound_mail_touch', { p_id: claimed.id, p_worker: worker })).catch(() => {});
    }, deps.renewMs ?? LEASE_RENEW_MS);
    let ok = false; let outcome: Record<string, unknown> | null = null; let err: string | null = null;
    try {
      const res = await deps.read(claimed);
      const text = await res.text().catch(() => '');
      // Every Response is the pipeline's own verdict, recorded where it belongs (inbound_messages, the books, a handover);
      // reading it again would only meet "already on file". So it is done, with the status kept for whoever looks.
      ok = true; outcome = { status: res.status, body: text.slice(0, 2000) };
    } catch (e) { err = String((e as Error)?.message || e).slice(0, 900); }
    finally { clearInterval(renew); }
    try {
      const { data, error } = await deps.rpc('fn_inbound_mail_finish', { p_id: claimed.id, p_worker: worker, p_ok: ok, p_outcome: outcome, p_error: err });
      if (error) tally.finish_failed++;
      else if (data?.finished === false) tally.lost++;
      else if (data?.status === 'done') tally.done++;
      else if (data?.status === 'dead') tally.dead++;
      else tally.retried++;
    } catch (_e) { tally.finish_failed++; }   // the lease runs out and the message is read again: "already on file" ends it
  }
  // This reader's slot is free again: start the next reader for whatever is due. The minute kick is the net under it.
  if (tally.read) {
    try { const { data } = await deps.rpc('fn_inbound_mail_kick', {}); tally.handed_on = Number(data?.kicked) || 0; } catch (_e) { /* the minute kick reads it */ }
  }
  if (deps.log && (tally.read || tally.claim_error)) {
    const bad = tally.dead || tally.claim_error || tally.finish_failed;
    await deps.log(bad ? 'error' : 'ok', { inbound_queue: 1, ...tally },
      'inbound mail reader: ' + tally.read + ' read, ' + tally.done + ' done, ' + tally.retried + ' to be read again later, ' + tally.dead
      + ' handed to their seat as unreadable' + (tally.lost ? ', ' + tally.lost + ' taken back from this reader' : '')
      + (tally.finish_failed ? ', ' + tally.finish_failed + ' verdict(s) not recorded (the lease runs out and the message is read again)' : '')
      + (tally.claim_error ? '; the claim failed: ' + tally.claim_error : ''));
  }
  return tally;
}
