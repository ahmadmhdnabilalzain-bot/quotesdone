-- THE BEST-AND-FINAL ROUND AND THE FRAMEWORK RATES STAY OFF, AS THE FOUNDER REMOVED THEM.
--
-- Seat: sales_engineer. 16 Nov 2026 (main session; supplier hole hunt, holes/SUPPLIER.md item 1; founder ledgers 1706, 1713).
-- The founder removed "negotiation / best-and-final rounds" and "reusable price lists" (.claude/memory/
-- upgrade-backlog-after-queue-zero.md:57-58) and the brief says we never ask a supplier for a better price
-- (knowledge/brief/company.md:127). Measured on production 16 Nov 01:20 UTC (SELECT): both duties were enabled —
--   sales_engineer.negotiation_round  every 1 h, last ok 16 Nov 00:35, result {"best_and_final_sent": 0, "clarify_sent": 0}
--   sales_engineer.framework_proposal every 7 days, last ok 9 Nov, result {"drafted": 0}
-- Nothing has been sent only because no real request has yet had two complete quotes. The first one would have
-- e-mailed every bidder "submit your best and final offer ... within 48 hours".
--
-- WHAT THIS FILE DOES: switches both duties off (seat_duty.enabled = false). Nothing is dropped: the routines and their
-- tables stay, so a later, reviewed change can bring back round 1 (asking an incomplete quote to complete) on its own,
-- without round 2. No routine, no table, no grant changes. Re-running it is harmless.
-- Rollback: update public.seat_duty set enabled = true where duty in (the two below).

update public.seat_duty set enabled = false
 where duty in ('sales_engineer.negotiation_round', 'sales_engineer.framework_proposal')
   and enabled;

select case when (select count(*) from public.seat_duty
                   where duty in ('sales_engineer.negotiation_round', 'sales_engineer.framework_proposal') and not enabled) = 2
            then 'PROBE OK: the best-and-final round and the framework rates are switched off'
            else 'PROBE FAILED: ' || coalesce((select string_agg(duty || '=' || enabled::text, ', ') from public.seat_duty
                   where duty in ('sales_engineer.negotiation_round', 'sales_engineer.framework_proposal')), 'duties missing') end as verdict;
