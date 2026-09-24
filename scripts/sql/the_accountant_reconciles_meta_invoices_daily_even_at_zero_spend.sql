-- THE ACCOUNTANT RECONCILES THE META INVOICES AGAINST THE REPORTED AD SPEND EVERY DAY, EVEN AT ZERO SPEND.
--
-- Assigned: accountant. Founder_instruction 327 (14 Sep 2026, "add all for accountant and IT"): duty 2 of the
-- five further accountant duties is "ad spend vs Meta invoices". Ledger 983 (24 Sep 2026) ordered every gap in
-- seats_v3/GAPS.md fixed; this is Accountant gap 3.
--
-- WHAT WAS MEASURED (24 Sep 2026, production, read-only):
--   * fn_accountant_ad_spend_tick, _figures and _snapshot are defined (the_accountant_tells_the_ceo_..., #645)
--     and decision_policy holds both keys the tick requires (accountant_ad_spend_match_tolerance_aed = 1,
--     accountant_ad_spend_invoice_grace_days = 10).
--   * NOTHING CALLS THE TICK. fn_accountant_duties writes {"ad_spend": {"held": "for the marketing seat (founder
--     rule 641)"}} in its place, since 22 Sep 2026. accountant_ad_spend_month holds 0 rows.
--   * Rule 641 held Meta access "until the marketing agent is created". The marketing seat exists (22 Sep 2026)
--     and it, not the accountant, holds the Meta token and writes ad_spend_policy through meta_sync.
--
-- WHY THIS IS NOT A BREACH OF RULE 641: the tick touches no Meta credential and calls no Meta API. It reads two
-- things the books already hold -- Meta invoices booked in expense_entries (read_as 'meta_ads_invoice', reasoned
-- when booked) and the month's spend the marketing seat's meta_sync wrote to ad_spend_policy -- and compares them.
-- Checking an invoice against what was reported is bookkeeping, which is the accountant's.
--
-- WHAT THIS CHANGES: a seat_duty row, accountant.ad_spend_reconcile, daily, routine fn_accountant_ad_spend_tick.
-- At zero spend the tick finds nothing and closes nothing (its figures list what is missing); the first real
-- Meta invoice, or the first reported spend with no invoice, becomes an accountant finding the same day.
-- fn_accountant_duties is deliberately NOT redefined: its canonical file changes under other seats' work, and a
-- separate duty row owns its own clock, last_result and failure count.
--
-- prevented by: scripts/checks/accountant_duties_are_wired.test.mjs (the duty row and its routine are in the
-- schema mirror; removing either fails it).

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('accountant.ad_spend_reconcile', 'accountant', interval '1 day', 'fn_accountant_ad_spend_tick',
   'Meta ads invoices booked in the books reconciled against the spend the marketing seat reported, month by month; runs at zero spend so the first invoice is checked',
   'scripts/sql/the_accountant_reconciles_meta_invoices_daily_even_at_zero_spend.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

-- PROBE (verdict row; nothing written): the routine the duty names exists and the figures it reads answer.
select case
  when not public.fn_seat_duty_routine_exists('fn_accountant_ad_spend_tick') then 'PROBE FAILED: fn_accountant_ad_spend_tick is missing'
  when (public.fn_accountant_ad_spend_figures((now() at time zone 'Asia/Dubai')::date) ? 'missing') is not true
    then 'PROBE FAILED: fn_accountant_ad_spend_figures did not return its missing list'
  else 'PROBE OK' end as verdict;
