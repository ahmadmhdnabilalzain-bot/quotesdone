-- A HELD ARABIC COMPARISON REPORT IS OFFERED HOURLY, SO IT NEVER WAITS FOREVER
-- Seat: sales_engineer. 2 Nov 2026 (PR #1807, journey run 41459344864 step 43).
--
-- MEASURED 2 Nov 2026 on production: 3 arabic_compare_waiter rows open, the oldest since 1 Nov 22:27Z with
-- last_offered_at null, and 0 compare_report_ar notices in 14 days. fn_arabic_compare_waiters_ready offered a waiter
-- ONLY once every one of its lines had Arabic, so a waiter with a line that was never filed (or never could be: 9 of
-- the oldest one's 15 lines were already Arabic, fixed in _shared/arabic_script.ts) was never offered again, and its
-- inquiry did not even exist any more (removed demo requests) - nothing ever looked at it.
--
-- WHAT THIS CHANGES. A waiter is offered when its lines are all translated (as before), OR - the clock - at least
-- hourly from its first hour. The finisher (customer_api/compare_arabic.ts) then renders it: a line still missing is
-- FILED again for the sales engineer's reasoning queue (deduplicated), at 6 h the report is put in the sales
-- engineer's queue once (agent_actions arabic_comparison_overdue), and a waiter whose inquiry is gone is closed. The
-- report is still never sent half-translated (founder, 14 Sep 2026: the Arabic version is Arabic throughout).
--
-- CREATE OR REPLACE keeps the routine's ACL (EXECUTE for service_role only, set by the file that created it); the
-- revoke below is repeated by signature so the ACL is asserted here too.

create or replace function public.fn_arabic_compare_waiters_ready(p_limit integer default 10)
returns jsonb
language sql security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with ready as (
    select d.inquiry_id from public.arabic_compare_waiter d
     where d.attempts < 5   -- a render that keeps failing stops costing replays (customer_api tells the sales engineer)
       and (d.last_offered_at is null or d.last_offered_at < now() - interval '2 minutes')
       and (
         not exists (select 1 from unnest(d.texts) t
                      where not exists (select 1 from public.arabic_translation a where a.source_md5 = md5(t)))
         -- the clock: a waiter that is still incomplete is looked at again at least hourly from its first hour
         or (d.created_at < now() - interval '1 hour' and (d.last_offered_at is null or d.last_offered_at < now() - interval '1 hour'))
       )
     order by d.attempts, d.last_offered_at nulls first, d.created_at
     limit greatest(1, least(coalesce(p_limit, 10), 100))
     for update skip locked
  ), offered as (
    update public.arabic_compare_waiter w set last_offered_at = now()
      from ready where w.inquiry_id = ready.inquiry_id
    returning w.inquiry_id
  )
  select coalesce(jsonb_agg(inquiry_id), '[]'::jsonb) from offered
$fn$;
revoke execute on function public.fn_arabic_compare_waiters_ready(integer) from public, anon, authenticated;
grant execute on function public.fn_arabic_compare_waiters_ready(integer) to service_role;
-- The probe is its own file (a_held_arabic_comparison_is_offered_hourly_so_it_never_waits_forever_probe.sql): it calls
-- the routine, which stamps every waiter it offers, so it must roll back rather than touch a real waiter.
