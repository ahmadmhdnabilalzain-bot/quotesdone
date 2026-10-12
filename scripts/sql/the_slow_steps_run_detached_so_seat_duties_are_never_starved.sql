-- THE SLOW STEPS RUN DETACHED SO SEAT DUTIES ARE NEVER STARVED (12 Oct 2026, it_engineer).
-- resilience_ping now only KICKS `marketing` and `itlater` (index.ts, DETACHED): each runs in its own
-- invocation with its own 140 s timeout and the tick's cost for it is one ~1 s POST. The plan still reads
-- these two rows' ewma_ms, which was MEASURED under the old inline runs (marketing 54,485 ms, itlater
-- 74,639 ms on 12 Oct 10:35 UTC). Left alone the ewma would take hours to decay and the plan would keep
-- spending 55-75 s of its 70 s budget on a 1 s kick, deferring seatDuties exactly as before. So the two
-- estimates are set to what the kick costs; fn_resilience_step_record measures them from the next tick on.
-- Data only: no routine, no table, no grant.
update public.resilience_step
   set ewma_ms = 1500,
       note = case step
         when 'marketing' then 'KICKED, not run inline (12 Oct 2026): resilience_ping posts {detached:"marketing"} to itself; the marketing seat''s duties (supabase/functions/marketing/duties.ts) and fn_marketing_tick run in that invocation with a 140 s timeout and settle failures as duty:detached_marketing:*'
         else 'KICKED, not run inline (12 Oct 2026): IT duties 19-24 run in resilience_ping''s own detached invocation with a 140 s timeout; failures settle as duty:detached_itlater:<sub-step>'
       end
 where step in ('marketing', 'itlater');

select case when (select count(*) from public.resilience_step where step in ('marketing','itlater') and ewma_ms = 1500) = 2
            then 'PROBE OK' else 'PROBE FAILED: the two rows were not reset' end as verdict;
