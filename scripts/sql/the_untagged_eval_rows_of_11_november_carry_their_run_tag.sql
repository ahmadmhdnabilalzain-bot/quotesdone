-- THE UNTAGGED EVAL ROWS OF 11 NOVEMBER CARRY THEIR RUN TAG (it_engineer, 12 Nov 2026). Data only, applied once.
-- Assigned: it_engineer (cost). Founder ledger 1642; final audit 12 Nov 2026, effort finding 4 and prompt_diet L1 (fix O8).
-- MEASURED (production, read-only, 12 Nov 2026): these seven ai_cost_log rows carry no e2e_run_tag, so they count as
-- production spend. Five are the effort smoke (USD 0.009720; the forwarder was installed after the first import, fixed on
-- its branch); two are prompt-diet eval calls in flight when their windows closed (USD 0.0034, 0.0049). The runs that made
-- them named them by id and tag in their reports (docs/reports/final-audit-2026-11-12/effort.md, prompt_diet.md).
-- ai_cost_log has no update guard (its five triggers are on INSERT only), so the rows are tagged where they stand; each
-- update is held to rows still untagged.
--   node scripts/apply_sql.mjs scripts/sql/the_untagged_eval_rows_of_11_november_carry_their_run_tag.sql --apply

update public.ai_cost_log set e2e_run_tag = 'evaleff86c475004'
 where id in (102237, 102244, 102255, 102265, 102277) and e2e_run_tag is null;
update public.ai_cost_log set e2e_run_tag = 'evaldiet8d0e23a7' where id = 103034 and e2e_run_tag is null;
update public.ai_cost_log set e2e_run_tag = 'evaldietecf2853f' where id = 103037 and e2e_run_tag is null;

select case when (select count(*) from public.ai_cost_log
                   where id in (102237, 102244, 102255, 102265, 102277, 103034, 103037) and e2e_run_tag is null) = 0
            then 'PROBE OK' else 'PROBE FAILED: rows still untagged' end as verdict;
