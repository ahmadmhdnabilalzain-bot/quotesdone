-- FINAL ACTION 1 - ONE CONTROL MODE IDENTITY, AND NO SHARED MFA PHONE EVER AGAIN
--
-- Two identities were seeded from app_secrets.admin_emails and BOTH pointed at the same
-- app_secrets.admin_mfa_phone. That is worse than it looks: with a shared destination, the code that
-- arrives on the phone does not say which account it belongs to, so the second factor stops
-- identifying anyone. Whoever holds either console session can request a code, and the person
-- holding the phone cannot tell the two apart. A second factor that cannot distinguish two
-- principals is a shared password with extra steps.
--
-- management@quotesdone.com is kept: it is the first entry in app_secrets.admin_emails and the
-- address fn_subscription_billing_run already treats as the company's primary admin, so "primary"
-- is a fact in the configuration rather than a guess made here.
--
-- The other identity is DEACTIVATED, not deleted. Deleting would cascade its challenge history out
-- of the audit trail, and the record of who could once do this is worth keeping. Reactivating is one
-- update - but it now requires giving that person their own phone_secret_key, because of the index
-- below.

update public.control_mode_identity
   set active = false,
       note = coalesce(note || ' | ', '')
           || 'deactivated 2 Aug 2026 on founder instruction: Control Mode is restricted to the primary admin identity'
 where admin_email <> 'management@quotesdone.com';

update public.control_mode_identity
   set note = coalesce(note || ' | ', '')
           || 'primary Control Mode identity, confirmed 2 Aug 2026'
 where admin_email = 'management@quotesdone.com';

-- Any challenge belonging to a now-inactive identity is void immediately. Leaving a live code for a
-- deactivated account open would mean the deactivation takes up to five minutes to bite.
update public.control_mode_challenge c
   set consumed_at = now(), consumed_why = 'identity deactivated'
  from public.control_mode_identity i
 where i.admin_email = c.admin_email and i.active = false and c.consumed_at is null;

update public.control_mode_session s
   set closed_at = now(), closed_reason = 'identity deactivated'
  from public.control_mode_identity i
 where i.admin_email = s.actor_email and i.active = false and s.closed_at is null;

-- Structural, not procedural. Two ACTIVE identities can no longer point at the same phone secret,
-- so the failure mode above cannot be recreated by someone adding a row in a hurry. Inactive rows
-- are exempt, which is what keeps the history above legal.
create unique index if not exists control_mode_identity_one_active_per_phone
  on public.control_mode_identity (phone_secret_key)
  where active;

comment on index public.control_mode_identity_one_active_per_phone is
  'One active Control Mode identity per MFA phone. A shared destination makes the second factor unable to tell two principals apart, which is the whole point of having one.';

create or replace function public.fn_control_mode_identity_active(p_email text)
returns boolean language sql stable security definer set search_path to 'public' as $fn$
  select exists (select 1 from public.control_mode_identity
                  where admin_email = lower(btrim(p_email)) and active);
$fn$;
revoke all on function public.fn_control_mode_identity_active(text) from public, anon, authenticated;
