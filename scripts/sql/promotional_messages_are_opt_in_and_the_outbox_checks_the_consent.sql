-- PROMOTIONAL MESSAGES ARE OPT-IN, AND THE OUTBOX CHECKS THE CONSENT (19 Oct 2026, founder decision on
-- legal finding 2; seat: ceo).
--
-- What was wrong: nothing recorded whether a customer or a registered supplier had agreed to receive
-- offers and news, so nothing could refuse a promotional message to someone who never asked for one.
-- What this file does:
--   1. customers and leads (a registered supplier is a leads row with claimed_by) get
--      marketing_consent boolean NOT NULL DEFAULT false, marketing_consent_at timestamptz and
--      marketing_consent_source text. NO BACKFILL: until a person ticks the separate, unticked box at
--      sign-up (customer: kyc accept_terms; supplier: supplier_api save_profile), nobody is opted in.
--   2. THE CLASSIFICATION. A notification is promotional when its type starts with 'promo_'
--      (fn_notification_is_promotional). No type of that shape exists today (measured on the schema
--      mirror and supabase/functions, 19 Oct 2026); every future offer/news message must use one. The
--      supplier B2B invitation lane (supplier_invite, supplier_invite_nudge, supplier_registration_reminder,
--      supplier_rfq_widened_invite) is NOT in this class: it goes to role addresses of companies not yet
--      registered and is governed separately (email_suppressions + fn_opt_out_types). Every other type is
--      transactional/service and is untouched.
--   3. THE GATE. A BEFORE INSERT OR UPDATE OF status trigger on notifications (one place, so email, SMS
--      and WhatsApp senders are all covered) turns a queued promotional row into status 'suppressed' with
--      last_error naming the reason, unless the recipient (matched by email, else by phone) holds
--      marketing_consent = true and has no 'unsubscribe' row in email_suppressions.
--   4. THE WITHDRAWAL. An 'unsubscribe' row in email_suppressions (the signed link and the reply path both
--      write one) sets marketing_consent false on the matching customer and supplier, and suppresses any
--      promotional row still queued for that address.
-- Not done here: a toggle in the account settings pages; withdrawal today is the unsubscribe link/reply.
-- Prevented by: scripts/checks/promotional_messages_are_opt_in.test.mjs

alter table public.customers add column if not exists marketing_consent boolean not null default false;
alter table public.customers add column if not exists marketing_consent_at timestamptz;
alter table public.customers add column if not exists marketing_consent_source text;
alter table public.leads add column if not exists marketing_consent boolean not null default false;
alter table public.leads add column if not exists marketing_consent_at timestamptz;
alter table public.leads add column if not exists marketing_consent_source text;

create or replace function public.fn_notification_is_promotional(p_type text)
returns boolean language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$ select coalesce(p_type, '') like 'promo\_%' $fn$;
revoke execute on function public.fn_notification_is_promotional(text) from public, anon, authenticated;

-- Consent of the person behind an address or a phone. Unknown person = no consent.
create or replace function public.fn_promotional_consent(p_email text, p_phone text)
returns boolean language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select case
    when nullif(btrim(p_email), '') is not null and exists (
      select 1 from public.email_suppressions s where lower(s.email) = lower(btrim(p_email)) and lower(s.reason) = 'unsubscribe') then false
    else exists (
      select 1 from public.customers c
       where c.marketing_consent
         and ((nullif(btrim(p_email), '') is not null and lower(c.email) = lower(btrim(p_email)))
           or (nullif(btrim(p_phone), '') is not null and (c.phone = btrim(p_phone) or c.whatsapp_phone = btrim(p_phone))))
      union all
      select 1 from public.leads l
       where l.marketing_consent and l.claimed_by is not null
         and ((nullif(btrim(p_email), '') is not null and lower(l.claimed_by) = lower(btrim(p_email)))
           or (nullif(btrim(p_phone), '') is not null and (l.phone_e164 = btrim(p_phone) or l.whatsapp_phone = btrim(p_phone)))))
  end
$fn$;
revoke execute on function public.fn_promotional_consent(text, text) from public, anon, authenticated;

create or replace function public.fn_notifications_promotional_consent_gate()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if new.status in ('queued', 'pending') and public.fn_notification_is_promotional(new.type)
     and not public.fn_promotional_consent(new.to_email, new.to_phone) then
    new.status := 'suppressed';
    new.last_error := 'no promotional consent: the recipient has not opted in to offers and news (or withdrew)';
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_notifications_promotional_consent_gate() from public, anon, authenticated;

drop trigger if exists a20_notifications_promotional_consent_gate on public.notifications;
create trigger a20_notifications_promotional_consent_gate
  before insert or update of status on public.notifications
  for each row execute function public.fn_notifications_promotional_consent_gate();

create or replace function public.fn_unsubscribe_withdraws_promotional_consent()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if lower(coalesce(new.reason, '')) = 'unsubscribe' and nullif(btrim(new.email), '') is not null then
    update public.customers set marketing_consent = false, marketing_consent_at = now(), marketing_consent_source = 'unsubscribe'
     where lower(email) = lower(btrim(new.email)) and marketing_consent;
    update public.leads set marketing_consent = false, marketing_consent_at = now(), marketing_consent_source = 'unsubscribe'
     where lower(claimed_by) = lower(btrim(new.email)) and marketing_consent;
    update public.notifications set status = 'suppressed', last_error = 'no promotional consent: withdrawn by unsubscribe'
     where status in ('queued', 'pending') and public.fn_notification_is_promotional(type) and lower(to_email) = lower(btrim(new.email));
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_unsubscribe_withdraws_promotional_consent() from public, anon, authenticated;

drop trigger if exists z50_unsubscribe_withdraws_promotional_consent on public.email_suppressions;
create trigger z50_unsubscribe_withdraws_promotional_consent
  after insert or update of reason on public.email_suppressions
  for each row execute function public.fn_unsubscribe_withdraws_promotional_consent();

-- VERDICT. Reads only; touches no real row.
select case
  when exists (select 1 from public.customers where marketing_consent and marketing_consent_at is null) then 'PROBE FAILED: a customer is opted in without ticking the box'
  when exists (select 1 from public.leads where marketing_consent and marketing_consent_at is null) then 'PROBE FAILED: a supplier is opted in without ticking the box'
  when not public.fn_notification_is_promotional('promo_offer') then 'PROBE FAILED: promo_offer is not classified promotional'
  when public.fn_notification_is_promotional('supplier_invite') or public.fn_notification_is_promotional('quote_received') then 'PROBE FAILED: a non-promotional type is classified promotional'
  when public.fn_promotional_consent('zz-probe-nobody@example.invalid', null) then 'PROBE FAILED: an unknown address counts as consent'
  when not exists (select 1 from pg_trigger where tgname = 'a20_notifications_promotional_consent_gate' and not tgisinternal) then 'PROBE FAILED: the outbox gate trigger is missing'
  else 'PROBE OK'
end as verdict;
