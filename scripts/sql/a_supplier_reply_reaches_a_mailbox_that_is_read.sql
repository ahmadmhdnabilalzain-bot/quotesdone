-- customer_support, 22 Sep 2026. Founder instruction 633 (our mail must land in the inbox).
--
-- MEASURED (22 Sep 2026, production, read-only):
--   * app_secrets.email_reply_supplier = supplier@quotesdone.com. quotesdone.com's MX is
--     quotesdone-com.mail.protection.outlook.com — a Microsoft 365 mailbox that no code reads. Every supplier
--     invitation, reminder and RFQ notice carries that Reply-To, and the invitation says "simply reply and we
--     will remove you". A supplier's question, or a "remove us", reached nobody; the day-2 and day-6 reminders
--     then went to someone who had asked to stop, which is how a sender earns spam complaints.
--   * mail.quotesdone.com is Resend inbound (MX inbound-smtp.us-east-1.amazonaws.com, verified, receiving
--     enabled). Every address on it reaches resend_inbound, which since #804 honours an unsubscribe reply to
--     ANY of its addresses (isUnsubscribeRequest + the authenticated-sender gates in
--     _shared/suppression_policy.ts) and stores every other message in inbound_messages.
--
-- WHAT THIS CHANGES
--   1. email_reply_supplier -> suppliers@mail.quotesdone.com. Replies land in resend_inbound: an unsubscribe is
--      honoured there under its existing gates; everything else is kept in inbound_messages, matched to the
--      lead and shown on the contact timeline.
--   2. trg_inbound_supplier_reply (BEFORE INSERT on inbound_messages): a message to that mailbox is always
--      needs_review, so it appears in the OS inbox (fn_inbox_list). resend_inbound only flags a message that
--      carried an attachment it could not apply, so a plain-text reply would otherwise be stored and unseen.
--
-- NOT CHANGED: the From address (supplier@quotesdone.com, DKIM-signed and DMARC-aligned), resend_inbound, and
-- the unsubscribe rules (they have one owner: _shared/unsubscribe_mailbox.ts and suppression_policy.ts).
--
-- Prevented by: scripts/sql/a_supplier_reply_reaches_a_mailbox_that_is_read_probe.sql (verdict row).

update public.app_secrets set value = 'suppliers@mail.quotesdone.com' where key = 'email_reply_supplier';

create or replace function public.trg_inbound_supplier_reply()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_box text;
begin
  v_box := lower(btrim(coalesce((select value from public.app_secrets where key = 'email_reply_supplier'), '')));
  if v_box like '%@mail.quotesdone.com' and position(v_box in lower(coalesce(new.to_email, ''))) > 0 then
    new.needs_review := true;
  end if;
  return new;
end
$fn$;
revoke execute on function public.trg_inbound_supplier_reply() from public, anon, authenticated;

drop trigger if exists trg_inbound_supplier_reply on public.inbound_messages;
create trigger trg_inbound_supplier_reply before insert on public.inbound_messages
  for each row execute function public.trg_inbound_supplier_reply();
