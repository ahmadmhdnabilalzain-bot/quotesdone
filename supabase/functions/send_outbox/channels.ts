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
// Two .or() calls become two `or=` params, which PostgREST ANDs: (status in queued/pending/null)
// AND (channel owned).
export function selectQueue(admin: SupabaseClient, limit: number) {
  return admin.from('notifications').select('*')
    .or('status.eq.queued,status.eq.pending,status.is.null')
    .or(OWNED_CHANNEL_FILTER)
    .order('created_at', { ascending: true }).limit(limit);
}

export function ownsChannel(channel: unknown): boolean {
  return channel === null || channel === undefined || !(NOT_OWNED_CHANNELS as readonly unknown[]).includes(channel);
}
