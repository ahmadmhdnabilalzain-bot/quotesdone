-- The supplier verified their e-mail before the company existed
-- =============================================================
--
-- MEASURED ON THE REAL PATH, 12 Aug 2026. I registered a supplier end to end through the live
-- invite link — OTP to a real mailbox, claim, licence upload — and the portal greeted the new
-- owner with "e-mail not yet verified" twenty seconds after they had typed a code out of that
-- very mailbox. 0 of 7 claimed leads had owner_email_verified = true.
--
-- login_otp is the only place a supplier's e-mail is ever proved, and it records the fact like
-- this (login_otp/index.ts:173):
--
--     update leads set owner_email_verified = true where claimed_by = <email>
--
-- On the invitation path that UPDATE can never match a row. The order of events is fixed by the
-- portal itself: SupplierPortal captures ?t= into sessionStorage, the supplier signs in, and only
-- THEN does onAuth() -> claimIfInvited() call supplier_api.claim to set claimed_by. At the instant
-- the code is verified there is no lead anywhere in the table carrying that address, so the
-- statement reports UPDATE 0 and the strongest proof we will ever have that the mailbox is real is
-- thrown away. Nothing errors. Nobody is paged. The supplier is simply told, forever, that we do
-- not believe their e-mail.
--
-- I proved the mechanism rather than inferring it. Same account, same function, twice:
--   11:30:57 UTC  code verified 28 s BEFORE the claim  -> owner_email_verified stayed false
--   11:36:35 UTC  code verified after the claim        -> owner_email_verified became true
-- Identical code path. The only variable is whether claimed_by existed yet.
--
-- THE FIX IS NOT A SECOND UPDATE IN claim. Three call sites already bind an address to a company
-- (supplier_api.claim, supplier_api.create_company, and any future one), and patching the one the
-- invite happens to use leaves the others exactly as broken — the mistake that created this defect
-- in the first place. "This mailbox answered an OTP" is a fact about the ADDRESS, not about the
-- lead row, and it is already durably recorded in email_verifications.used_at. So the row derives
-- it at the moment an address is attached to it, wherever that happens.
--
-- The backfill below is a derivation, not a fabrication: every row it flips has a real, used,
-- purpose='login' verification on file for its own owner's address.

create or replace function public.fn_leads_derive_owner_email_verified()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  -- Only when an address is newly attached or changed. A later edit of an unrelated column must
  -- not re-run this, and it must never REVOKE a verification an OTP sign-in has already granted.
  if NEW.claimed_by is null then return NEW; end if;
  if TG_OP = 'UPDATE' and NEW.claimed_by is not distinct from OLD.claimed_by then return NEW; end if;
  if coalesce(NEW.owner_email_verified, false) then return NEW; end if;

  if exists (
    select 1 from email_verifications
    where email = lower(NEW.claimed_by)
      and purpose = 'login'
      and used_at is not null
  ) then
    NEW.owner_email_verified := true;
  end if;
  return NEW;
end $$;

revoke all on function public.fn_leads_derive_owner_email_verified() from public;

drop trigger if exists trg_leads_derive_owner_email_verified on public.leads;
create trigger trg_leads_derive_owner_email_verified
  before insert or update of claimed_by on public.leads
  for each row execute function public.fn_leads_derive_owner_email_verified();

-- Backfill: every already-claimed company whose owner has a used login code on file.
update public.leads l
   set owner_email_verified = true
 where l.claimed_by is not null
   and coalesce(l.owner_email_verified, false) = false
   and exists (
     select 1 from public.email_verifications ev
     where ev.email = lower(l.claimed_by)
       and ev.purpose = 'login'
       and ev.used_at is not null
   );
