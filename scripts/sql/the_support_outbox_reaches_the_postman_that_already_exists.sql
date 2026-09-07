-- THE SUPPORT OUTBOX REACHES THE POSTMAN THAT ALREADY EXISTS
--
-- The founder, 8 September 2026: "he shouldn't be blocked from viewing or replying at the moment",
-- and "he is not gonna invite -- that is another agent that I will introduce next."
--
-- THE DEFECT, AND IT IS MINE. I built public.support_notification as the support agent's outbox and
-- gave it careful properties: a deduplication key, an anonymity scan it cannot be inserted without
-- passing, and a CHECK forbidding the word "attached" with no attachment. Then I never connected it
-- to anything. Measured: three functions WRITE to that table and NOTHING reads it. Every message
-- the agent composes is correct and none of it leaves the building -- a finished capability with no
-- entry point, which is a shape this estate has paid for before.
--
-- WHAT MAKES IT WORSE IS THAT THE POSTMAN ALREADY EXISTED. supabase/functions/send_outbox has run
-- every two minutes for months against public.notifications, with retry, dead-lettering, suppression
-- lists, a stale-mail guard, a reserved-test-domain refusal and branded templates. I did not need to
-- build a sender. I needed to stop writing into a second table nobody drains.
--
-- So this bridges rather than duplicates. One postman, one set of delivery guarantees, one place
-- where a bounce is recorded. A second sender would have been a second set of rules to keep in step,
-- and they would have drifted.
--
-- WHY THE BULK GATES DO NOT APPLY TO HIM. The channel policy blocks outbound email because 16,167 of
-- 19,896 addresses on the invitation list are unverified and the measured bounce is 10%. That risk
-- belongs to a list he never touches: the founder confirmed the invitations are a different agent's
-- job. Everything support sends is a REPLY or a transactional message to an address that is either
-- on a real account or just wrote to us -- deliverability that is already demonstrated. Holding his
-- mail behind a guard built for cold outreach is the guard firing when the system is working.

alter table public.support_notification
  add column if not exists outbox_id bigint,
  add column if not exists bridged_at timestamptz,
  add column if not exists bridge_note text;

create index if not exists support_notification_unbridged_idx
  on public.support_notification (queued_at) where bridged_at is null;

comment on column public.support_notification.outbox_id is
  'The public.notifications row this was handed to. Null with a bridge_note means it was deliberately not handed over, which is a different fact from not having been tried.';

-- ---------------------------------------------------------------------------------------------
-- THE BRIDGE
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_support_notification_to_outbox()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_role text; v_id bigint; v_kind text;
begin
  -- WHO IS THIS PERSON TO US. send_outbox routes the from-address, the reply-to, the template and
  -- the unsubscribe header off to_role, so getting it wrong sends a supplier a customer-branded
  -- email from the wrong mailbox. Read from the case rather than guessed.
  select case when c.party_kind = 'supplier' then 'supplier' else 'customer' end
    into v_role
    from public.support_case c where c.case_id = new.case_id;
  v_role := coalesce(v_role, 'customer');

  if new.channel = 'email' then
    if coalesce(btrim(new.recipient), '') = '' then
      new.bridge_note := 'no email address on the row; nothing to hand over';
      return new;
    end if;

    -- THE TYPE CARRIES THE PURPOSE, and that is load-bearing rather than cosmetic: send_outbox
    -- exempts anything matching licence/renew/expiry from the supplier bulk gate, because a
    -- document request is transactional. Passing the purpose through means a licence reminder is
    -- recognised as one instead of being held with the marketing.
    v_kind := coalesce(new.purpose, 'support');

    -- KIND CARRIES THE PURPOSE TOO, and this is not cosmetic. a10_notifications_founder_mail_policy
    -- governs anything addressed to the founder by KIND, reading it before type. An earlier version
    -- of this bridge stamped every row 'support_agent', which collapsed every kind of support mail
    -- into one governance decision: allow the label and he gets all of it, refuse it and he gets
    -- none -- and the policy table could not tell a refund decision from a licence reminder. The
    -- provenance that label was carrying is already on the support_notification row it came from,
    -- so nothing is lost by letting the purpose through.
    insert into public.notifications (type, kind, to_email, to_role, subject, body, status, channel)
    values (v_kind, v_kind, btrim(new.recipient), v_role,
            coalesce(new.subject, 'QuotesDone'), new.body, 'queued', 'email')
    returning id into v_id;

    new.outbox_id := v_id;
    new.bridged_at := now();
    new.bridge_note := format('handed to notifications #%s as a %L to a %s', v_id, v_kind, v_role);

  elsif new.channel = 'whatsapp' then
    -- NOT BRIDGED, AND SAYING SO. send_outbox is email only, and a business-initiated WhatsApp
    -- message needs an approved template and recorded opt-in, which no recipient has yet. Writing
    -- it into an email queue would produce a delivery that never happened; leaving it silent would
    -- be indistinguishable from working. It is held, with the reason on the row.
    new.bridge_note := 'not bridged: WhatsApp is business-initiated here and no recipient has recorded opt-in. '
                    || 'This is held deliberately, not lost. An inbound reply inside the 24-hour window goes '
                    || 'through wa_inbound and does not use this table.';
  end if;

  return new;
end $function$;

drop trigger if exists z50_support_notification_to_outbox on public.support_notification;
create trigger z50_support_notification_to_outbox
  before insert on public.support_notification
  for each row execute function public.fn_support_notification_to_outbox();

comment on function public.fn_support_notification_to_outbox is
  'Hands every email the support agent composes to public.notifications, which send_outbox has drained every two minutes for months. Bridges rather than duplicates: a second sender would be a second set of retry, suppression and bounce rules to keep in step with the first.';

-- ---------------------------------------------------------------------------------------------
-- AND THE STATUS COMES BACK. A message marked sent in one table and unknown in the other is two
-- answers to "did the customer hear from us", which is the reason this estate keeps two states
-- apart everywhere else.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_support_notification_sync_state()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  if new.status is distinct from old.status then
    update public.support_notification
       set state = case new.status
             when 'sent'       then 'sent'
             when 'suppressed' then 'suppressed'
             when 'failed'     then 'failed'
             when 'skipped'    then 'suppressed'
             when 'held'       then 'queued'
             else state end,
           sent_at = case when new.status = 'sent' then coalesce(new.sent_at, now()) else sent_at end,
           provider_id = coalesce(new.id::text, provider_id),
           provider_status = new.status,
           attempts = coalesce(new.attempts, attempts),
           -- The provider's own words, kept rather than summarised. A bounce reason is the only
           -- thing that distinguishes "the address is wrong" from "our domain is in trouble".
           failure_reason = case when new.status in ('failed','skipped')
                                 then new.last_error else failure_reason end
     where outbox_id = new.id;
  end if;
  return new;
end $function$;

drop trigger if exists z51_support_notification_sync_state on public.notifications;
create trigger z51_support_notification_sync_state
  after update on public.notifications
  for each row execute function public.fn_support_notification_sync_state();

revoke execute on function public.fn_support_notification_to_outbox() from public;
revoke execute on function public.fn_support_notification_to_outbox() from anon;
revoke execute on function public.fn_support_notification_to_outbox() from authenticated;
revoke execute on function public.fn_support_notification_sync_state() from public;
revoke execute on function public.fn_support_notification_sync_state() from anon;
revoke execute on function public.fn_support_notification_sync_state() from authenticated;
