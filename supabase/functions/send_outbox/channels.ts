import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';

// Which notification rows send_outbox owns. It sends email; a NULL channel has always meant email.
// SMS and WhatsApp rows belong to their own senders (send_whatsapp drains channel='whatsapp').
//
// THE QUEUE WAS STARVED BY ROWS IT WOULD NEVER SEND (15 Sep 2026, measured). The select used to take the
// oldest N queued rows of EVERY channel and skip WhatsApp/SMS in the loop, leaving them queued. When
// 20+ undeliverable WhatsApp rows were the oldest (template not approved, 1-per-recipient-per-24h cap),
// every run from 01:04Z to 05:31Z returned sent:0, skipped:20 and never reached the email rows behind
// them. The filter now runs in the query so a row of another channel can never take a slot.
export const NOT_OWNED_CHANNELS = ['sms', 'whatsapp'] as const;

// PostgREST or-filter. `not.in` alone drops NULL rows (NULL NOT IN (...) is NULL), so the NULL branch is
// required or every legacy email row with no channel would be silently abandoned.
export const OWNED_CHANNEL_FILTER = `channel.is.null,channel.not.in.(${NOT_OWNED_CHANNELS.join(',')})`;

// The queue query itself lives here so channels.test.ts builds the exact request the function sends.
// Each .or() call becomes its own `or=` param, which PostgREST ANDs: (status in queued/pending/null)
// AND (channel owned) AND (due).
// NOT BEFORE ITS TIME (22 Sep 2026, customer_support). enqueue_supplier_invites spreads a day's supplier
// invitations across the Dubai working window by setting notifications.not_before; a row is not
// selected until it is due, so the queue never drains a new domain's whole day in one burst. NULL (every
// other row) means now. This needs the column: apply
// the_invitations_warm_up_on_measured_health_and_leave_across_the_working_day.sql BEFORE deploying.
export function dueFilter(now: Date): string {
  return `not_before.is.null,not_before.lte.${now.toISOString()}`;
}

// STALE FROM WHEN IT FELL DUE, NOT FROM WHEN IT WAS WRITTEN (2 Nov 2026, sales_engineer, ledger 1486). The stale guard
// (email_stale_hours, 72) read created_at, so a row deliberately moved on by not_before (the bounce brake, a lane or cap hold)
// aged out while it waited. 18 Google-hosted invitations queued 28 Oct and released for 2 Nov 11:07 Dubai were claimed at
// 11:16 and held for good, with no last_error, so the founder's resume sent nothing. A row is stale only once it has been
// DUE for longer than the bar; a row with no not_before is measured from created_at, exactly as before.
// Review of #1787: only the invitation lane's types (whose holds move not_before on purpose) are measured from not_before,
// and every row is stale STALE_CEILING_H after it was written, so a row re-held every 30 minutes cannot go out weeks late.
export const STALE_CEILING_H = 14 * 24;
export function isStale(createdAt: string, notBefore: string | null | undefined, laneType: boolean, staleH: number, now: Date): { stale: boolean; hours: number } {
  const created = new Date(createdAt).getTime();
  const due = laneType && notBefore ? Math.max(created, new Date(notBefore).getTime()) : created;
  const hours = (now.getTime() - due) / 3.6e6;
  return { stale: hours > staleH || (now.getTime() - created) / 3.6e6 > STALE_CEILING_H, hours };
}

export function selectQueue(admin: SupabaseClient, limit: number, now: Date = new Date()) {
  return admin.from('notifications').select('*')
    .or('status.eq.queued,status.eq.pending,status.is.null')
    .or(OWNED_CHANNEL_FILTER)
    .or(dueFilter(now))
    .order('created_at', { ascending: true }).limit(limit);
}

// READING THE QUEUE IS NOT TAKING IT (22 Sep 2026, it_engineer, CONN-03). selectQueue above is a plain
// SELECT: two overlapping runs — and this function is driven every 2 minutes AND from the resilience
// tick AND from email_cron — see the same rows, both build the message, both POST it, and the second
// UPDATE to 'sent' hides the first. fn_notifications_claim takes the rows with FOR UPDATE SKIP LOCKED
// and moves them to 'sending' in the same statement, so a second caller cannot see them at all, and
// requeues any claim older than 5 minutes so a sender that died costs 5 minutes and not the message.
//
// selectQueue is KEPT, not deleted: it is what channels.test.ts builds the exact PostgREST request
// from, and it is the readable statement of which rows this sender owns. The claim's SQL carries the
// same rule; the two are checked against each other by that test.
export function claimQueue(admin: SupabaseClient, limit: number) {
  return admin.rpc('fn_notifications_claim', { p_channel: 'email', p_limit: limit });
}

export function ownsChannel(channel: unknown): boolean {
  return channel === null || channel === undefined || !(NOT_OWNED_CHANNELS as readonly unknown[]).includes(channel);
}
