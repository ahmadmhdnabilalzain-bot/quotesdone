---
name: ceo-break-even-rebuild-10-nov-apply-order
description: "10 Nov 2026 (ledgers 1609, 1614-1616): branch ceo-break-even-rebuild — trade-by-trade opening, the break-even ledger, the CEO approves the January plan, one weekly founder e-mail, exams loaded at merge; six pending SQL files and their apply order"
metadata:
  type: project
  modified: 2026-11-10
---

Branch `ceo-break-even-rebuild` (no PR opened by the building session). Every SQL file is PENDING and was rehearsed rolled
back with its `_probe.sql` (PROBE OK). Nothing was applied, deployed or loaded.

**Apply order at merge (each `--apply --ddl`, then delete its pending note and append it to the END of MANIFEST):**
1. `a_trade_opens_to_customers_as_soon_as_it_has_enough_verified_suppliers.sql` — BEFORE deploying customer_api,
   stripe_checkout, stripe_confirm, wa_inbound: `_shared/reveal_guard.ts` fails closed on a missing `fn_trade_reveal_allowed`.
2. `the_ceo_plans_on_a_break_even_ledger_to_june_2027.sql` (reads trade_opening_rule).
3. `the_ceo_approves_the_january_launch_plan_and_the_founder_reads_it_in_his_brief.sql` (retypes the live fn_founder_brief:
   re-diff against live first).
4. `the_founder_gets_one_weekly_email_and_the_it_session_list_goes_to_the_session.sql` (three live bodies retyped: re-diff).
5. `the_ceo_settles_a_month_plan_that_waits_on_a_revision_nobody_wrote.sql`.
6. `the_accountant_forecast_carries_every_recurring_cost_and_the_break_even_line.sql` (after #2; live body retyped: re-diff).
Then deploy the four functions, then `node scripts/kb/load_verified_packs.mjs --apply` and
`node scripts/eval/seat_qualification_exam.mjs --load` (until then `every_seat_exam_is_loaded_for_the_monthly_self_review`
is red against production, by design: 0 of 636 items loaded).

**Numbers a session should not re-derive (10 Nov):** real verified, matchable suppliers 0 (supply_gap's 4 slots are the
one ZZ DEMO supplier); real reveal revenue 0 (the one paid reveal is ZZ DEMO); measured running cost AED 4,271.70 a month
(2,974.67 recurring + OpenRouter 1,297.03 last 30 days); cost to cover 50,230 at 28 Nov; 770 verified suppliers and
25,000 invitations needed against 7,650 the warm-up guardrail allows: `not_reachable_on_email`.

**The opening rule:** open at 10 verified suppliers (P(>=3 quotes | 10, assumed 40%) = 0.833), floor 5 in a CHECK, the
CEO re-tunes weekly from the measured quote rate after 30 invitations. A demo supplier never counts; the probe uses the
session setting `qd.trade_opening_fixture_counts` because a verified supplier cannot be faked (fn_supplier_mandatory_six).

**The IT session list** now lives in `public.it_session_fix_day` (one row a Dubai day): read it at session start.

Related: [[seat-qualification-audit-10-nov-break-even]].
