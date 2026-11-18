-- NO SUPPLIER IS E-MAILED A SCORECARD; THE PORTAL STILL SHOWS IT.
-- Seat: sales_engineer. 18 Nov 2026. Founder ruling 1730 (ledger row 1730).
--
-- WHAT WAS MEASURED (production, read-only, 18 Nov 2026): seat_duty 'sales_engineer.supplier_scorecard' (enabled, every 1 day,
-- fn_sales_engineer_supplier_scorecard_tick, owner_file a_supplier_sees_its_monthly_scorecard_against_its_trade.sql) last ran
-- 18 Nov 02:00 UTC and sent 1 card for October 2026 ("Your QuotesDone scorecard for October 2026"). Every card so far has read zeros:
-- no request had reached any approved supplier. #2051 (pending) stops a month before approval or without a request; the founder sees
-- no value in the e-mail at all while they are zeros: "stop e-mailing supplier scorecards".
--
-- WHAT THIS CHANGES: the duty's own switch, seat_duty.enabled = false, with the reason in `what`. Nothing is dropped. The supplier
-- portal's Scorecard view (supplier_portal action 'scorecard' -> fn_supplier_scorecard, computed on demand) does not read the duty or
-- supplier_scorecard rows, so it keeps showing any month's card. No routine, table or grant changes; re-running it is harmless.
-- TO TURN THE E-MAIL BACK ON (the founder's word only):
--   update public.seat_duty set enabled = true,
--          what = 'e-mail every approved supplier his last month''s scorecard against his trade, in English, once a month'
--    where duty = 'sales_engineer.supplier_scorecard';
-- (apply #2051's file first, so a month before approval or with no request is still never e-mailed.)
--
-- Pending: scripts/sql/pending/no_supplier_is_e_mailed_a_scorecard_the_portal_still_shows_it.txt
-- Prevented by: scripts/checks/no_supplier_is_e_mailed_a_scorecard.test.mjs

update public.seat_duty set enabled = false,
  what = 'STOPPED 18 Nov 2026 (founder ruling 1730): no supplier is e-mailed his monthly scorecard; the portal''s Scorecard view still '
      || 'shows it. Turn back on only on the founder''s word: see scripts/sql/no_supplier_is_e_mailed_a_scorecard_the_portal_still_shows_it.sql.'
 where duty = 'sales_engineer.supplier_scorecard' and (enabled or what not like 'STOPPED 18 Nov 2026%');

select case
  when not exists (select 1 from public.seat_duty where duty = 'sales_engineer.supplier_scorecard') then 'PROBE FAILED: the duty is missing'
  when exists (select 1 from public.seat_duty where duty = 'sales_engineer.supplier_scorecard' and enabled) then 'PROBE FAILED: the scorecard e-mail is still enabled'
  when not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'fn_supplier_scorecard')
    then 'PROBE FAILED: the portal''s scorecard routine is gone'
  else 'PROBE OK: the scorecard e-mail is switched off; the portal view is kept' end as verdict;
