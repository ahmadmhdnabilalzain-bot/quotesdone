-- AN E-MAIL IS PROVEN ONLY BY A CODE THAT WAS VERIFIED.
-- Seat: customer_support (supplier registration: the e-mail item of the mandatory six, and who may claim an invited listing).
-- 10 Nov 2026, item 7 of the supplier-journey audit's report (#1901), founder ruling 1608.
--
-- MEASURED BEFORE THIS FILE (code on origin/main 8cc16e24b; production read-only 10 Nov): "the e-mail is proven" was decided
-- in two ways, both on email_verifications.used_at, and used_at is not proof:
--   * fn_login_otp_email_issue sets used_at on every earlier live code when a new one is sent (a resend retires it), and
--     fn_login_otp_email_verify sets it when a code is burned at the attempt cap. So asking for two codes, or guessing five
--     times wrong, made an address "proven" (623 rows today, 613 with used_at, across 32 addresses; which were verified
--     cannot be told apart afterwards, so nothing is backfilled);
--   * supplier_api emailProven() (lib/registration.ts) read used_at; create_company's claim path additionally required a
--     session opened by a code, but its insert path and the /portal?t= token claim set owner_email_verified from
--     emailProven() alone, and the derive trigger fn_leads_derive_owner_email_verified read used_at on its own.
--
-- WHAT THIS CHANGES: email_verifications.verified_at, set by fn_login_otp_email_verify on its 'ok' path ONLY (the live body
-- read on 10 Nov, md5 fdff029b..., one line changed). public.fn_email_proven(text) is the one definition: a login or kyc code
-- for that address was verified. fn_leads_derive_owner_email_verified (live body md5 27ca2243..., one test changed),
-- supplier_api emailProven() (all three registration paths) and kyc's own verify use it or write it.
-- WHAT IT DOES NOT CHANGE: used_at keeps its meaning (a code no longer usable), so the resend, the cap and every lookup that
-- filters on it (the live-code select, the race check) are untouched; create_company still also asks that the claim's
-- session was opened by a code (sessionOpenedByCode); no owner_email_verified already granted is revoked.
-- CONSEQUENCE, said plainly: an address whose code was verified before this file has no verified_at, so a supplier signed in
-- before the apply who has not yet registered is asked to sign in with a fresh code once (verify_email_first).
-- Apply BEFORE deploying supplier_api and kyc (supplier_api calls fn_email_proven; until then it reads used_at as before).
-- Prevented by: scripts/checks/an_email_is_proven_only_by_a_code_that_was_verified.test.mjs, and the probe of the same name
-- (rolled back on production): two sends and a burned code do not prove an address, a verified code does.

alter table public.email_verifications add column if not exists verified_at timestamptz;

create or replace function public.fn_email_proven(p_email text)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(btrim(p_email), '') <> ''
     and exists (select 1 from public.email_verifications v
                  where v.email = lower(btrim(p_email))
                    and v.purpose in ('login', 'kyc')
                    and v.verified_at is not null)
$fn$;
revoke execute on function public.fn_email_proven(text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_login_otp_email_verify(p_email text, p_hash text, p_code text, p_max_attempts integer DEFAULT 5)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r record;
begin
  select id, expires_at, attempts, token_hash, token
    into r
    from public.email_verifications
   where email = p_email and purpose = 'login' and used_at is null
   order by created_at desc
   limit 1
   for update;
  if not found then return 'no_code'; end if;
  if r.expires_at < now() then return 'expired'; end if;
  if coalesce(r.attempts, 0) >= p_max_attempts then
    update public.email_verifications set used_at = now() where id = r.id and used_at is null;
    return 'burned';
  end if;
  update public.email_verifications set attempts = coalesce(attempts, 0) + 1 where id = r.id;
  if (r.token_hash is not null and r.token_hash = p_hash)
     or (r.token_hash is null and r.token is not null and r.token = p_code) then
    -- verified_at is set HERE ONLY: a code that was entered right. A resend (fn_login_otp_email_issue) and the attempt cap
    -- (above) also set used_at, which is why used_at is not proof (an_email_is_proven_only_by_a_code_that_was_verified.sql).
    update public.email_verifications set used_at = now(), verified_at = now() where id = r.id and used_at is null;
    if found then return 'ok'; end if;
  end if;
  return 'wrong';
end
$function$;


CREATE OR REPLACE FUNCTION public.fn_leads_derive_owner_email_verified()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  -- Only when an address is newly attached or changed. A later edit of an unrelated column must
  -- not re-run this, and it must never REVOKE a verification an OTP sign-in has already granted.
  if NEW.claimed_by is null then return NEW; end if;
  if TG_OP = 'UPDATE' and NEW.claimed_by is not distinct from OLD.claimed_by then return NEW; end if;
  if coalesce(NEW.owner_email_verified, false) then return NEW; end if;

  -- ONE DEFINITION OF A PROVEN ADDRESS (10 Nov 2026): a code that was verified, never a code that was merely used up.
  if public.fn_email_proven(NEW.claimed_by) then
    NEW.owner_email_verified := true;
  end if;
  return NEW;
end $function$;

