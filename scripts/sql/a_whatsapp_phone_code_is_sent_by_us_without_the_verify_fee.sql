-- A WHATSAPP PHONE CODE IS SENT BY US, WITHOUT THE VERIFY FEE
-- Seat: it_engineer. Founder ledger 1252 (18 Oct 2026): "USD 0.17 per OTP is way too much (about 1 dirham per two
-- registrations)".
--
-- WHAT THE MONEY IS. #1432 (merged 19 Oct, deployed: login_otp v313 / kyc v308) moved a UAE mobile code to WhatsApp
-- first and measured the prices on this account (_shared/whatsapp_choice.ts header): a Verify SMS to +971 is
-- USD 0.1176, a WhatsApp Authentication-template send USD 0.0157, and Twilio Verify adds USD 0.05 to EVERY approved
-- code on either channel. So a WhatsApp code still cost USD 0.0657, and three quarters of it was Verify's fee, not
-- the message. The estate already owns an approved Authentication template for exactly this (wa_template_sids
-- login_code en HX1748.. / ar HXec99.., messaging_template status approved, last read 27 Oct 2026), so a WhatsApp
-- code can be generated here, sent through the Messages API with that template, and checked here: USD 0.0157 a
-- code. SMS (and the voice fallback) stay on Verify, which is what carries them reliably to a number with no
-- WhatsApp.
--
-- WHAT THIS ADDS. public.phone_code holds the HMAC of the code (never the code), the purpose it was sent for, the
-- WhatsApp message SID (for the SMS failover's delivery read), a guess counter and an expiry. The two routines are
-- the email ones (a_sign_in_code_is_counted_compared_and_spent_in_one_statement.sql) for a phone:
--   fn_phone_code_issue   retires every earlier unused code for (phone, purpose) and inserts the new one, under a
--                         per-key advisory lock, so a resend never leaves two live codes;
--   fn_phone_code_verify  locks the newest live code, refuses it expired, burns it at the cap, counts the guess,
--                         compares the MAC and spends it only where unspent: one verdict word, a code verifies once.
-- message_sid is set by fn_phone_code_sent once Twilio accepted the send (the row is written BEFORE the send, so a
-- code that reaches a phone always has a row to be checked against).
--
-- PREVENTED BY: supabase/functions/_shared/wa_code.test.ts (the edge half) and
-- supabase/functions/login_otp/verify_race.check.ts (these bodies, twenty parallel guesses, on a throwaway Postgres).

create table if not exists public.phone_code (
  id          bigserial primary key,
  phone       text        not null,
  purpose     text        not null check (purpose in ('login', 'kyc_phone', 'kyc_whatsapp')),
  user_kind   text,
  email       text,
  code_hash   text        not null,
  message_sid text,
  attempts    integer     not null default 0,
  expires_at  timestamptz not null,
  used_at     timestamptz,
  created_at  timestamptz not null default now()
);
comment on table public.phone_code is
  'A WhatsApp phone code QuotesDone generated and sent itself (ledger 1252): HMAC only, never the code. Read and spent only by fn_phone_code_verify. _shared/wa_code.ts.';
create index if not exists phone_code_live on public.phone_code (phone, purpose, created_at desc) where used_at is null;

alter table public.phone_code enable row level security;
drop policy if exists phone_code_service_role_only on public.phone_code;
create policy phone_code_service_role_only on public.phone_code
  as permissive for all to public using (false) with check (false);
revoke all on public.phone_code from anon, authenticated;

create or replace function public.fn_phone_code_issue(
  p_phone text, p_purpose text, p_hash text, p_kind text, p_email text, p_ttl_seconds integer default 600)
returns bigint
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_id bigint;
begin
  perform pg_advisory_xact_lock(hashtext('phone_code:' || p_purpose || ':' || p_phone));
  update public.phone_code set used_at = now()
   where phone = p_phone and purpose = p_purpose and used_at is null;
  insert into public.phone_code (phone, purpose, user_kind, email, code_hash, expires_at)
  values (p_phone, p_purpose, p_kind, p_email, p_hash, now() + make_interval(secs => p_ttl_seconds))
  returning id into v_id;
  return v_id;
end
$fn$;

revoke execute on function public.fn_phone_code_issue(text, text, text, text, text, integer) from public, anon, authenticated;

-- p_accepted false = Twilio refused the send: the stored code reached nobody, so it is spent at once and nothing can
-- ever be guessed against it.
create or replace function public.fn_phone_code_sent(p_id bigint, p_message_sid text, p_accepted boolean)
returns void
language sql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  update public.phone_code
     set message_sid = p_message_sid,
         used_at = case when p_accepted then used_at else coalesce(used_at, now()) end
   where id = p_id;
$fn$;

revoke execute on function public.fn_phone_code_sent(bigint, text, boolean) from public, anon, authenticated;

create or replace function public.fn_phone_code_verify(
  p_phone text, p_purpose text, p_hash text, p_max_attempts integer default 5)
returns text
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  r record;
begin
  select id, expires_at, attempts, code_hash
    into r
    from public.phone_code
   where phone = p_phone and purpose = p_purpose and used_at is null
   order by created_at desc, id desc
   limit 1
   for update;
  if not found then return 'no_code'; end if;
  if r.expires_at < now() then return 'expired'; end if;
  if r.attempts >= p_max_attempts then
    update public.phone_code set used_at = now() where id = r.id and used_at is null;
    return 'burned';
  end if;
  update public.phone_code set attempts = attempts + 1 where id = r.id;
  if r.code_hash = p_hash then
    update public.phone_code set used_at = now() where id = r.id and used_at is null;
    if found then return 'ok'; end if;
  end if;
  return 'wrong';
end
$fn$;

revoke execute on function public.fn_phone_code_verify(text, text, text, integer) from public, anon, authenticated;
