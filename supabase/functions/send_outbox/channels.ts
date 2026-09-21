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

export function selectQueue(admin: SupabaseClient, limit: number, now: Date = new Date()) {
  return admin.from('notifications').select('*')
    .or('status.eq.queued,status.eq.pending,status.is.null')
    .or(OWNED_CHANNEL_FILTER)
    .or(dueFilter(now))
    .order('created_at', { ascending: true }).limit(limit);
}

export function ownsChannel(channel: unknown): boolean {
  return channel === null || channel === undefined || !(NOT_OWNED_CHANNELS as readonly unknown[]).includes(channel);
}
