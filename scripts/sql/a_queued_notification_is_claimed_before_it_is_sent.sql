-- A QUEUED NOTIFICATION IS CLAIMED BEFORE IT IS SENT (22 Sep 2026, it_engineer, CONN-03).
--
-- WHAT WAS THERE. Both senders read their work with a plain SELECT and no claim:
--   supabase/functions/send_outbox/channels.ts:29   selectQueue(...)  status in (queued|pending|null)
--   supabase/functions/send_whatsapp/index.ts:299   .eq('status','queued').limit(25)
-- Each runs every 2 minutes AND is also driven from the resilience tick and from email_cron, so two
-- copies overlapping is not a hypothesis. Two readers see the same row, both build the message, both
-- POST it, and the second UPDATE to 'sent' simply overwrites the first. The estate's own evidence that
-- this class of thing happens: send_outbox and send_whatsapp raced over WhatsApp rows on 27 Jul 2026
-- and the poller destroyed the message; the fix then was a channel filter, which stops the two senders
-- colliding and does nothing at all about one sender colliding with itself.
--
-- WHAT THIS ADDS. One claim, the same shape as fn_doc_backups_next and fn_cad_read_claim, which is the
-- pattern this estate already uses for exactly this:
--   * FOR UPDATE SKIP LOCKED over the candidate ids, so two callers take disjoint slices;
--   * the claimed rows move to 'sending' with claimed_at stamped, so no later reader sees them;
--   * a claim older than 5 minutes is requeued first — a sender that died mid-run costs 5 minutes,
--     not the message. 5 minutes because the senders' own callers time out far inside it
--     (email_cron waits 60 s for send_outbox; the resilience tick's ceiling is 120 s).
--
-- 'sending' IS NOT A NEW WORD THE READERS HAVE TO LEARN. It was checked, routine by routine, against
-- every function whose body mentions notifications and status (74 of them):
--   * fn_customer_support_delivery_watch ends its status chain with `else v_waiting := v_waiting + 1`,
--     so a row in flight counts as still in flight — which is what 'sending' means;
--   * fn_notifications_release_held only ever reads 'held';
--   * fn_wa_founder_alert_fallback reads ('queued','held') — a row is in 'sending' for at most the few
--     seconds of one send, or 5 minutes if the sender died, and is 'queued' again after that;
--   * notifications has NO check constraint on status (measured: only lang, provider_status, sender are
--     constrained), so nothing refuses the value.
--
-- AND 'sent_unconfirmed' IS NOT ADDED AS A STATUS, deliberately. The audit asked for one. This estate
-- already encodes it: fn_customer_support_delivery_watch returns 'sent_unconfirmed' for a row that is
-- 'sent' with no provider_message_id, and fn_originator_checks_delivery reads that result and refuses
-- to re-send. A send whose POST timed out is therefore written as 'sent' with provider_message_id NULL
-- and the reason in last_error — which is true (the request left), is never drained again, and reads as
-- unconfirmed in the two routines that judge delivery. A new literal would have needed edits inside two
-- routines another seat owns to mean the same thing.

alter table public.notifications add column if not exists claimed_at timestamptz;
comment on column public.notifications.claimed_at is
  'When a sender claimed this row (status = sending). A claim older than 5 minutes is requeued by fn_notifications_claim.';

-- The claim scan: the oldest claimable rows of one channel. notifications_status_idx is (status,
-- created_at), which already serves it; this partial index keeps the requeue of expired claims off a
-- full scan as the table grows.
create index if not exists notifications_sending_claimed_at_idx
  on public.notifications (claimed_at) where status = 'sending';

create or replace function public.fn_notifications_claim(p_channel text, p_limit integer default 25)
returns setof public.notifications
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_lim int := greatest(1, least(coalesce(p_limit, 25), 200));
begin
  -- A sender that died holding a claim must not hold it forever.
  update public.notifications n
     set status = 'queued', claimed_at = null,
         last_error = left('a send claim expired after 5 minutes without an outcome; requeued', 500)
   where n.status = 'sending' and n.claimed_at < now() - interval '5 minutes';

  return query
    update public.notifications n
       set status = 'sending', claimed_at = now()
     where n.id in (
       select c.id from public.notifications c
        where (c.status in ('queued', 'pending') or c.status is null)
          -- THE SAME OWNERSHIP RULE AS channels.ts, in one place. 'email' owns a NULL channel and
          -- anything that is not sms or whatsapp; any other value is that channel exactly.
          and (case when p_channel = 'email' then (c.channel is null or c.channel not in ('sms', 'whatsapp'))
                    else c.channel = p_channel end)
          -- NOT BEFORE ITS TIME: enqueue_supplier_invites spreads a day's invitations across the Dubai
          -- working window with not_before. NULL means now.
          and (c.not_before is null or c.not_before <= now())
          -- A channel that addresses a handset cannot send a row with no handset on it.
          and (p_channel <> 'whatsapp' or c.to_phone is not null)
        order by c.created_at
        limit v_lim
        for update skip locked)
    returning n.*;
end
$fn$;

revoke execute on function public.fn_notifications_claim(text, integer) from public, anon, authenticated;

comment on function public.fn_notifications_claim(text, integer) is
  'Claims the oldest due, unsent notifications of one channel (FOR UPDATE SKIP LOCKED -> status sending), '
  'and requeues any claim older than 5 minutes. The only way a sender may take work. CONN-03, 22 Sep 2026.';
