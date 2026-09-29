-- CUSTOMER_FOLLOWUP IS OWNED BY CUSTOMER SUPPORT (29 Sep 2026; seat: customer_support).
--
-- customer_support_asks_whether_the_customer_hired_and_nudges_a_quiet_one_by_their_trades.sql (PR #1074) added
-- the edge function customer_followup (day-3/day-14 hired follow-up, 60-day nudge). The release train deployed it
-- without a function_owner row, and every_deployed_function_has_an_owner went red on every open PR. The follow-up
-- is customer_support's conversation with its own customers, so customer_support owns it.
-- Prevented by: scripts/checks/every_deployed_function_has_an_owner.mjs

begin;

insert into public.function_owner (function_slug, owner, note)
values ('customer_followup', 'customer_support',
        'Day-3/day-14 "did you hire?" follow-up as an outcome and the 60-day nudge about the customer''s own trades (PR #1074).')
on conflict (function_slug) do update set owner = excluded.owner, note = excluded.note;

commit;
