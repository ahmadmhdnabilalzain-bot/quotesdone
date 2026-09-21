-- customer_support, 22 Sep 2026. Founder instruction 633 (our mail must land in the inbox).
--
-- MEASURED (22 Sep 2026, production, read-only):
--   * app_secrets.email_reply_supplier = supplier@quotesdone.com. quotesdone.com's MX is
--     quotesdone-com.mail.protection.outlook.com — a Microsoft 365 mailbox that no code reads. Every
--     supplier invitation says "simply reply and we will remove you", and every reminder and RFQ notice
--     to a supplier carries the same Reply-To. A supplier who replies "remove us" is never removed, and
--     the day-2 and day-6 reminders then go to someone who asked to stop — which is how a sender earns
--     spam complaints, the one number Gmail and Microsoft will not forgive.
--   * mail.quotesdone.com is Resend inbound (MX inbound-smtp.us-east-1.amazonaws.com, domain verified,
--     receiving enabled; expenses@ and docs@ already arrive through resend_inbound into inbound_messages).
--
-- WHAT THIS CHANGES
--   1. email_reply_supplier -> suppliers@mail.quotesdone.com, so replies land in inbound_messages (kept,
--      matched to the lead, shown on the contact timeline as customer_support's).
--   2. trg_inbound_supplier_reply (BEFORE INSERT on inbound_messages): a message to that mailbox is always
--      needs_review (it is in the OS inbox, fn_inbox_list), and when the reply's OWN text — the part
--      before the quoted invitation, which itself contains "unsubscribe" and "remove you" — asks to stop,
--      the sender is suppressed at once (reason 'unsubscribe_reply', source 'reply'; an existing bounce
--      or complaint record is never relabelled). send_outbox honours email_suppressions on every row.
--
-- NOT CHANGED: the From address (supplier@quotesdone.com, DKIM-signed and DMARC-aligned) and the founder's
-- copy. resend_inbound is not edited. A reply that does not ask to stop is only flagged for review.
--
-- Prevented by: scripts/sql/a_supplier_reply_reaches_a_mailbox_that_is_read_probe.sql (verdict row).

update public.app_secrets set value = 'suppliers@mail.quotesdone.com' where key = 'email_reply_supplier';

-- The part of a reply its author wrote: everything before the first quote marker, at most 600 chars.
create or replace function public.fn_reply_own_text(p_body text)
returns text
language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select left(split_part(regexp_replace(coalesce(p_body, ''),
           '(\n\s*>|\nOn [^\n]{0,200}wrote:|\n-+ ?Original Message ?-+|\nFrom: |\n________________|\nفي [^\n]{0,200}كتب)', E''),
         E'', 1), 600)
$fn$;
revoke execute on function public.fn_reply_own_text(text) from public, anon, authenticated;

create or replace function public.fn_reply_asks_to_stop(p_subject text, p_body text)
returns boolean
language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select (coalesce(p_subject, '') || E'\n' || public.fn_reply_own_text(p_body)) ~*
    ('(\munsubscribe\M|\mremove (me|us|our|my)\M|\mtake (me|us) off\M|\mstop (sending|emailing|contacting)\M'
     || '|\mnot interested\M|\mdo not (contact|email)\M|\mdon''t (contact|email)\M|\mopt[ -]?out\M'
     || '|إلغاء الاشتراك|الغاء الاشتراك|أزيلوا|ازيلوا|إزالة (عنواني|عنواننا|بريدي)|لا نرغب|لا أرغب|لا ارغب|توقفوا عن)')
$fn$;
revoke execute on function public.fn_reply_asks_to_stop(text, text) from public, anon, authenticated;

create or replace function public.trg_inbound_supplier_reply()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_box text; v_from text;
begin
  v_box := lower(btrim(coalesce((select value from public.app_secrets where key = 'email_reply_supplier'), '')));
  if v_box = '' or v_box not like '%@mail.quotesdone.com' or position(v_box in lower(coalesce(new.to_email, ''))) = 0 then
    return new;
  end if;
  new.needs_review := true;
  v_from := lower(btrim(coalesce(substring(new.from_email from '<([^>]+)>'), new.from_email, '')));
  if v_from ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' and public.fn_reply_asks_to_stop(new.subject, new.body) then
    insert into public.email_suppressions (email, reason, source)
    values (v_from, 'unsubscribe_reply', 'reply')
    on conflict (email) do nothing;
  end if;
  return new;
end
$fn$;
revoke execute on function public.trg_inbound_supplier_reply() from public, anon, authenticated;

drop trigger if exists trg_inbound_supplier_reply on public.inbound_messages;
create trigger trg_inbound_supplier_reply before insert on public.inbound_messages
  for each row execute function public.trg_inbound_supplier_reply();
