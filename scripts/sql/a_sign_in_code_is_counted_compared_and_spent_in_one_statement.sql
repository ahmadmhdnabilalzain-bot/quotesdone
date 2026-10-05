-- A SIGN-IN CODE IS COUNTED, COMPARED AND SPENT IN ONE STATEMENT
-- Seat: it_engineer. Pre-launch security pass of 6 Oct 2026, finding H1 (HIGH).
--
-- WHAT WAS WRONG. login_otp's email verify read the newest unused email_verifications row, compared
-- the code in the edge function, then wrote `attempts = <value it had read> + 1` and, on a match,
-- `used_at = now()` with no condition. Three races followed from that read-then-write:
--   * guesses sent at the same moment all read the same `attempts`, so the 5-per-code cap was not a
--     cap: 20 parallel guesses were 20 evaluations;
--   * two requests holding the right code both passed the compare and both minted a session, so a
--     code could be redeemed twice;
--   * the burn at the cap was a separate write, raced the same way.
--
-- WHAT THIS CHANGES. public.fn_login_otp_email_verify does the whole check under a row lock:
-- it locks the newest live code for the address, refuses it when expired, burns it at the cap,
-- increments the counter, compares, and sets used_at only `where used_at is null`, returning one
-- verdict word. Concurrent callers queue on the lock and each re-reads the counter the previous one
-- wrote, so at most p_max_attempts guesses are ever evaluated and a code verifies at most once.
--
-- THE COMPARE. The function receives HMAC-SHA256(code, otp_hmac_key) computed by login_otp, never
-- the bare code (the legacy `token` column, for rows issued before hashing, is the one exception and
-- is compared only when token_hash is null). Text `=` in SQL is not constant-time, but what it compares
-- is the keyed MAC of the caller's own guess: without the key a caller cannot choose MAC bytes, so the
-- timing says nothing about the stored value. That is why the compare moved here rather than staying
-- in the function's constant-time helper.
--
-- WHAT THIS DOES NOT CHANGE. The per-IP and the new per-address verify limits stay in login_otp
-- (rl_check), and they now refuse when the limiter itself fails. Phone codes are checked by Twilio
-- Verify, which enforces its own attempts and expiry; this file does not touch that path.
--
-- PREVENTED BY: scripts/checks/a_sign_in_code_is_counted_and_spent_once.test.mjs replays twenty
-- parallel guesses against this exact function body and fails if more than five are evaluated or if
-- a code verifies twice.

create or replace function public.fn_login_otp_email_verify(
  p_email text, p_hash text, p_code text, p_max_attempts integer default 5)
returns text
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
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
    update public.email_verifications set used_at = now() where id = r.id and used_at is null;
    if found then return 'ok'; end if;
  end if;
  return 'wrong';
end
$fn$;

revoke execute on function public.fn_login_otp_email_verify(text, text, text, integer) from public, anon, authenticated;
