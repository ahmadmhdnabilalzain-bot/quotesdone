-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260721075403   name: harden_email_otp_hash_and_attempt_cap
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Email sign-in codes were stored in plaintext AND the verify path had no
-- attempt limit: a 6-digit code with unlimited guesses is brute-forceable by
-- anyone who knows a target's email. Sending was capped (8/hour); verifying
-- was not.

-- attempts counter so verify can be capped per issued code
alter table public.email_verifications
  add column if not exists attempts integer not null default 0;

-- hashed token column; going forward `token` is no longer populated
alter table public.email_verifications
  add column if not exists token_hash text;

-- new rows store only the hash, so plaintext must be nullable
alter table public.email_verifications
  alter column token drop not null;

-- scrub historical plaintext codes: all are used or expired, so they carry
-- no operational value, only risk
update public.email_verifications
   set token = null
 where token is not null
   and (used_at is not null or expires_at < now());

-- verify filters on these columns
create index if not exists email_verifications_lookup_idx
  on public.email_verifications (email, purpose, used_at, created_at desc);
