-- THE IT DIGEST HAS ONE SIGNATURE AGAIN.
-- Assigned: it_engineer. 23 September 2026.
--
-- ══ WHAT HAPPENED, MEASURED ══════════════════════════════════════════════════════════════════════
-- the_founder_hears_from_it_once_a_day.sql (MANIFEST 1568, so the canonical winner) deliberately DROPS
-- fn_customer_support_sends_the_it_digest(interval) and defines
-- fn_customer_support_sends_the_it_digest(p_now timestamptz default now()) in its place: the digest is
-- decided by the instant it judges, not by an interval floor.
-- On 22 Sep 2026 the_founder_gets_one_it_digest_per_tick.sql (MANIFEST 1434, superseded) was re-applied as
-- part of PR #848, and its `create or replace` RE-CREATED the dropped overload. pg_proc then held both:
--   fn_customer_support_sends_the_it_digest(timestamp with time zone)   -- p_now  DEFAULT now()
--   fn_customer_support_sends_the_it_digest(interval)                   -- p_floor DEFAULT '01:00:00'
-- BOTH carry a default, and the one call the estate makes is the no-argument
-- `public.fn_customer_support_sends_the_it_digest()` inside fn_it_loop_tick. Two candidates, no way to
-- choose: agent_runs 2026-09-22 20:01:27.553953Z, status error, counts {"job":"it_loop","stage":"digest"},
-- note "function public.fn_customer_support_sends_the_it_digest() is not unique". The founder got NO IT
-- digest from that tick on — a resurrection took a live delivery path down, which is why the definition has
-- also been REMOVED from the superseded file rather than left there for the next re-apply to find.
-- fn_customer_support_acts_on_handoff(bigint) mentions the routine only in prose, so no caller needs it.
--
-- ══ WHAT THIS DOES ═══════════════════════════════════════════════════════════════════════════════
-- Drops the (interval) overload by its exact signature. Nothing else: the (timestamptz) definition is not
-- touched, and its ACL (postgres, service_role) is already closed — measured before this file was written.
-- No revoke is needed for a routine that is being dropped, and none is written for the survivor because
-- the_founder_hears_from_it_once_a_day.sql already revokes `(timestamptz)` from public, anon, authenticated.
--
-- ══ NOT CHANGED ══════════════════════════════════════════════════════════════════════════════════
-- fn_it_loop_tick's body (owned by the_ceo_decides_every_sales_engineer_report_and_every_sender_closes_its_
-- handoff.sql, re-applied in the same follow-up so production carries its nine steps again), the digest's
-- own logic, the 60-minute floor question — the survivor decides cadence by the founder's local 19:00.
--
--   node scripts/apply_sql.mjs scripts/sql/the_it_digest_has_one_signature_again.sql --apply --ddl

drop function if exists public.fn_customer_support_sends_the_it_digest(interval);

-- ══ VERDICT ══════════════════════════════════════════════════════════════════════════════════════
-- Reads the live catalogue back: exactly one overload, and it is the one the winner defines.
select case
  when (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'fn_customer_support_sends_the_it_digest') = 1
   and exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'public' and p.proname = 'fn_customer_support_sends_the_it_digest'
                  and pg_get_function_identity_arguments(p.oid) = 'p_now timestamp with time zone')
  then 'PROBE OK: one fn_customer_support_sends_the_it_digest, taking the instant it judges; the no-argument call inside fn_it_loop_tick resolves again'
  else 'PROBE FAILED: fn_customer_support_sends_the_it_digest is not a single (timestamptz) routine' end as verdict;
