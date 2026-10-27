-- A RATE LIMIT CHECK HOLDS A LOCK PER KEY (it_engineer, 18 Oct 2026, review of #1432).
--
-- rl_check counted the key's hits and then inserted one, with nothing between the two. Two requests
-- for the same key at the same instant both counted n < limit and both inserted, so a limit of 1 let
-- 2 through. The sign-in code's 30-second resend gap (login_otp, kyc: rl('otp_gap:<phone>', 1, 30))
-- is a limit of 1, so a double click could pay Twilio twice. Every other rl_check caller (sign-in
-- send and verify ceilings) had the same race, by one or more hits.
--
-- A transaction-scoped advisory lock on the key serialises callers of the SAME key only; different
-- keys never wait on each other, and the lock is released when the calling statement's transaction ends.
-- CREATE OR REPLACE keeps the existing ACL, so no grant or revoke changes here.
create or replace function public.rl_check(p_key text, p_limit integer, p_seconds integer)
 returns boolean
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare n int;
begin
  perform pg_advisory_xact_lock(hashtextextended('rl_check:' || p_key, 0));
  delete from rl_hits where at < now() - (p_seconds || ' seconds')::interval and k = p_key;
  select count(*) into n from rl_hits where k = p_key and at > now() - (p_seconds || ' seconds')::interval;
  if n >= p_limit then return false; end if;
  insert into rl_hits(k) values (p_key);
  return true;
end $function$;

-- Probe (this file has DDL, so it cleans up and returns a verdict row instead of raising).
-- The key is unique to this run and touches no real caller's key.
create temp table _rl_probe on commit drop as select 'probe:rl_check_lock:' || gen_random_uuid()::text as key;
alter table _rl_probe add column first boolean, add column second boolean;
update _rl_probe set first = public.rl_check(key, 1, 30);
update _rl_probe set second = public.rl_check(key, 1, 30);
delete from public.rl_hits where k = (select key from _rl_probe);
select case when p.first and not p.second and not exists (select 1 from public.rl_hits h where h.k = p.key)
            then 'PROBE OK' else 'PROBE FAILED: a limit of 1 did not refuse the second hit, or the probe left a row' end as verdict
  from _rl_probe p;
