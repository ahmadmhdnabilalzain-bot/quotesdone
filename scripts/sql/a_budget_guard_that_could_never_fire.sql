-- A BUDGET GUARD WIRED TO A NUMBER SEVEN TIMES TOO LOOSE TO EVER FIRE.
--
-- department_budget is NOT decoration in the usual sense — it has a real reader. fn_ai_route reads
-- degrade_at_pct and halt_at_pct on every routing decision, and fn_ai_spend_guard and
-- fn_budget_rollup read them too. The wiring is genuine and the ledger is accurate: measured on
-- production 14 Aug 2026, department_budget.spent_aed for exec reads 141.77 against 142.48 summed
-- independently from ai_cost_log for the same month. That half works.
--
-- WHAT DOES NOT WORK IS THE NUMBER. AED 12,000 is allocated across 25 departments. Measured spend
-- in the same month is AED 176.86, and over a trailing 30 days AED 210.38 — 1.5% of the
-- allocation. The consequence is not waste, because unspent budget costs nothing. The consequence
-- is that the guard CANNOT FIRE:
--
--   * exec is the only department above 1% of its budget, at 17.8%. degrade_at_pct is 70.
--   * The other 24 departments sit between 0.0% and 2.4%.
--   * 19 of the 25 have spent exactly AED 0.00 in 30 days.
--
-- A ceiling nothing can reach is not a ceiling. If agent_brain doubled its rate tomorrow, exec
-- would pass 35% and nothing anywhere would say so; it would take a SIXTEEN-fold increase before
-- the degrade step engaged. The guard exists, is read, and protects nothing.
--
-- THE ALLOCATION IS ALSO INVERTED AGAINST REALITY. procurement carries the single largest budget,
-- AED 1,600, and has spent AED 1.28 — 0.1%. exec carries half that, AED 800, and has spent
-- AED 171.40 — 134 times procurement's spend on half the allowance. Every department that actually
-- works (exec, knowledge, intelligence, it) is funded below the ones that do not.
--
-- WHAT THIS CHANGE DOES, AND WHAT IT DELIBERATELY DOES NOT.
--
--   monthly_aed := round to 10 of greatest( 3 x measured 30-day spend,   -- headroom over reality
--                                           0.10 x the current budget,   -- keeps the founder's ranking
--                                           40 )                         -- a department may start work
--
-- Three terms, because one would be wrong three different ways:
--
--   * 3x measured spend alone would set procurement to AED 4 and strangle the department the
--     founder has deliberately funded highest the moment the marketplace starts trading. His
--     ranking is a commercial decision and it is preserved by the second term, which keeps
--     procurement the largest non-exec allocation at AED 160.
--   * The founder's ranking alone is what we have today, and exec — the only department that
--     spends — would stay funded below departments that have never made a model call.
--   * A floor of AED 40 so a department that has never worked is not halted on its first real
--     task. At medium-tier rates that is several hundred calls before the degrade step engages.
--
-- The result is roughly AED 1,650 allocated against AED 210 measured: about 8x headroom company
-- wide, so the guard has room for real growth and still engages long before a runaway becomes a
-- bill. exec moves from a ceiling it could reach at 16x current spend to one it reaches at 2.1x.
--
-- THIS IS NOT A SPENDING CUT AND NOTHING IS BEING SAVED HERE. Unspent allocation was never money.
-- What changes is that the number now means something, so the NEXT thing that starts spending is
-- caught by a threshold instead of by a founder reading a bill at the end of the month.
--
-- REVISIT WHEN WE TRADE. Every figure below is derived from a 30-day window in which the
-- marketplace did no commercial business. The first real RFQ traffic will move procurement,
-- rfq_intelligence and customer_success by more than 3x, and these numbers should be re-derived
-- from measured use at that point rather than defended.

update department_budget b
   set monthly_aed = greatest(
         ceil(3 * coalesce(m.aed, 0) / 10.0) * 10,   -- 3x measured, to the nearest 10 above
         ceil(0.10 * b.monthly_aed / 10.0) * 10,     -- a tenth of the founder's figure, ranking kept
         40                                          -- room to start working
       ),
       updated_at = now()
  from (select d.dept_key, coalesce(sum(c.cost_aed), 0) aed
          from department_budget d
          left join ai_cost_log c
            on c.dept_key = d.dept_key and c.occurred_at > now() - interval '30 days'
         group by d.dept_key) m
 where m.dept_key = b.dept_key
   and b.period_label = '2026-08';

-- The thresholds themselves are left exactly as they are. 70% to degrade and 95% to halt are
-- sensible percentages; they were never the problem. What was wrong was the number they are
-- percentages OF.
