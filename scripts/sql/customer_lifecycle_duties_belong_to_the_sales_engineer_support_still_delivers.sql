-- CUSTOMER LIFECYCLE DUTIES BELONG TO THE SALES ENGINEER; SUPPORT STILL DELIVERS (30 Sep 2026; seat: ceo, ledger 1063).
--
-- Founder, 29 Sep 2026 (founder_instruction 1063): "make sure no task, duty, job or routine is left without a
-- specific agent, and that no task sits under the wrong agent (checked against the 24 Sep seat ownership map).
-- Fix every one found." The 24 Sep map: the sales_engineer owns "BOTH suppliers and customers ... inquiries,
-- specs, matching, quotes ... reveals"; customer_support "is the COMMUNICATION seat ... It does NOT own reveals."
-- Instruction 898 (23 Sep) left the choice of seat for activation/retention to Claude; the map is the later ruling.
--
-- WHAT WAS MEASURED (29 Sep 2026, production, read-only): 83 seat_duty rows, 14 it_duty_schedule rows, 78
-- function_owner rows = 78 deployed edge functions = 78 repo directories, 105 seat_handoff_kind rows, 2 cron jobs.
-- Every row names an active seat. Five sat on the wrong seat per the map:
--   customer_support.followup   day-3/day-14 "did you hire?" after a REVEAL, the answer written as the outcome
--   customer_support.concierge  a first request's guidance and a held request's missing SPECS
--   customer_support.activation no request after 3 days, a REQUEST with no QUOTE after 5 and 10
--   customer_support.winback    the customer account's 60-day re-engagement
--   function_owner customer_followup  the edge function behind followup and the 60-day nudge (PR #1074)
-- The same move was made for the 7-day reveal outcome check and the dispute clock on 24 Sep
-- (reveal_follow_up_and_dispute_findings_belong_to_the_sales_engineer.sql); #1074 then added a new reveal
-- follow-up under support, which is how the map was broken again.
--
-- WHAT THIS CHANGES: the OWNER only. seat_duty_check requires the duty key's prefix to equal owner_seat, so the
-- key is renamed in the same statement; routine, every, enabled and the last_* run state are kept, so the next
-- tick is exactly when it would have been. No routine is edited: the routines keep their fn_customer_support_*
-- names and still send through fn_customer_support_duty_send, i.e. customer_support still DELIVERS every message.
-- No FK references seat_duty and no live routine names these four keys (measured).
--
-- WHAT THIS DOES NOT CHANGE: renaming the routines, the seat_handoff_kind row deliberation.review
-- customer_support -> ceo (still named in its meaning after the dispute finding moved), and the knowledge pack
-- text that cites the old keys. Those are on docs/audits/2026-09-30_senior_hire_audit.md.
--
--   node scripts/apply_sql.mjs scripts/sql/customer_lifecycle_duties_belong_to_the_sales_engineer_support_still_delivers.sql --apply

-- No begin/commit: the duties check replays this file inside its aborted probe while it is pending.
update public.seat_duty
   set duty = 'sales_engineer.' || split_part(duty, '.', 2), owner_seat = 'sales_engineer'
 where duty in ('customer_support.followup', 'customer_support.concierge',
                'customer_support.activation', 'customer_support.winback');

update public.function_owner
   set owner = 'sales_engineer',
       note = coalesce(note, '') ||' Owner moved from customer_support 30 Sep 2026 (ledger 1063): reveal outcomes are the sales_engineer''s; support delivers.'
 where function_slug = 'customer_followup' and owner = 'customer_support';

select case
  when (select count(*) from public.seat_duty where duty in ('sales_engineer.followup', 'sales_engineer.concierge',
          'sales_engineer.activation', 'sales_engineer.winback') and owner_seat = 'sales_engineer' and enabled) = 4
   and not exists (select 1 from public.seat_duty where duty in ('customer_support.followup', 'customer_support.concierge',
          'customer_support.activation', 'customer_support.winback'))
   and (select owner from public.function_owner where function_slug = 'customer_followup') = 'sales_engineer'
  then 'PROBE OK' else 'PROBE FAILED: owners did not move' end as verdict;
