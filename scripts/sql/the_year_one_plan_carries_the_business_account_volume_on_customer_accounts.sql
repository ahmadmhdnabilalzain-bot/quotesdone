-- THE YEAR-ONE PLAN CARRIES THE BUSINESS-ACCOUNT VOLUME ON CUSTOMER ACCOUNTS; THE TOTALS DO NOT MOVE.
-- Seat: ceo. 30 Sep 2026. Founder ledger 1091: "Year-one plan: do not lower the targets. The volume that was planned
-- from [the removed account grouping] is covered by customer accounts. Move those requests, reveals and fees into the
-- customer account targets; totals stay the same." Needs, in this order:
-- the_ceo_runs_the_company_on_the_founders_year_one_targets.sql (#924) and
-- there_are_no_enterprise_accounts_only_customer_and_supplier_accounts.sql (#1169). Reads none of #1169's dropped tables.
--
-- WHAT WAS MEASURED (production, 30 Sep 2026, before this file)
--   * ceo_year_plan: requests, quotes, reveals and fee_aed are already month TOTALS; the removed grouping's share was
--     6 requests, 3 awards and AED 4,500 a month per account, on a column counting 1 account in Jan 2027 to 5 in Sep.
--     Year: 915 requests, 1,647 quotes, 191 reveals, AED 157,740 of fees, 25 account-months, AED 235,176 of ceilings.
--   * The grouping was named by: that column, ceo_mandate reveal_fees_and_... (clause key and statement), the active
--     FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30 objective and one sales_engineer row of ceo_plan_action. No target path
--     metric, no routine and no seat directive names it; target_path b2b_active_accounts already measures business
--     CUSTOMERS (customers.industry set, a real request in 30 days: fn_ambition_measure), never the dropped tables.
--   * ceo_knowledge: 5 rows use the word only in its general sense (COSO risk management, a competitor's offering,
--     the Khalifa Fund's name); none is a target or an account type. Not touched.
--
-- WHAT THIS DOES: relabels, never re-derives. The same volume, month by month, is attributed to customer accounts:
-- the column becomes business_accounts (repeat business customer accounts), the mandate, the contract objective and the
-- seat action say customer accounts. Every number is left as it is; the probe below proves it per metric and month.
-- prevented by: scripts/checks/the_year_one_plan_names_customer_accounts_and_keeps_its_totals.test.mjs

do $$ begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'ceo_year_plan' and column_name = 'enterprise') then
    alter table public.ceo_year_plan rename column enterprise to business_accounts;
  end if;
  if exists (select 1 from pg_constraint where conrelid = 'public.ceo_year_plan'::regclass and conname = 'ceo_year_plan_enterprise_check') then
    alter table public.ceo_year_plan rename constraint ceo_year_plan_enterprise_check to ceo_year_plan_business_accounts_check;
  end if;
end $$;
comment on column public.ceo_year_plan.business_accounts is
  'Repeat business customer accounts in the month: each posts about 6 requests and awards 3 jobs of about AED 50,000 (founder ledger 1091, 30 Sep 2026). Counted in requests, reveals and fee_aed.';

update public.ceo_year_plan
   set basis = 'founder targets 24 Sep 2026 (ledger 971); repeat business-account volume on customer accounts, totals unchanged (ledger 1091, 30 Sep 2026)';

update public.ceo_mandate
   set clause_key = 'reveal_fees_from_customer_accounts',
       statement = 'Reveal fees at 3 %, from the customer accounts that post their requests through QuotesDone, repeat business accounts included.',
       source = 'founder, 24 Sep 2026; ledger 1091, 30 Sep 2026'
 where clause_key = 'reveal_fees_and_enterprise'
   and not exists (select 1 from public.ceo_mandate where clause_key = 'reveal_fees_from_customer_accounts');
delete from public.ceo_mandate where clause_key = 'reveal_fees_and_enterprise';

update public.target_contract
   set objective = replace(objective, 'enterprise accounts', 'customer accounts')
 where contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30' and objective ilike '%enterprise accounts%';

update public.ceo_plan_action
   set action = 'Business customer accounts through consented channels only: one new repeat business account every two months, each posting about six requests and awarding three jobs a month.'
 where seat = 'sales_engineer' and action ilike 'Enterprise procurement accounts%'
   and not exists (select 1 from public.ceo_plan_action a where a.seat = 'sales_engineer' and a.action like 'Business customer accounts through consented channels only%');
delete from public.ceo_plan_action where seat = 'sales_engineer' and action ilike 'Enterprise procurement accounts%';

-- Verdict: the totals are the founder's (ledger 971 numbers) and nothing in the plan names the removed grouping.
select case when t.ok and n.names = 0 then 'PROBE OK' else 'PROBE FAILED: ' || t.got || ' names=' || n.names end as verdict
  from (select (count(*), sum(requests), sum(quotes), sum(reveals), sum(fee_aed), sum(business_accounts), sum(cost_ceiling_aed))
               = (12::bigint, 915::bigint, 1647::bigint, 191::bigint, 157740::numeric, 25::bigint, 235176::numeric) as ok,
               (count(*), sum(requests), sum(quotes), sum(reveals), sum(fee_aed), sum(business_accounts), sum(cost_ceiling_aed))::text as got
          from public.ceo_year_plan) t,
       (select (select count(*) from public.ceo_mandate where clause_key ilike '%enterpr%' or statement ilike '%enterpr%')
             + (select count(*) from public.ceo_plan_action where action ilike '%enterpr%')
             + (select count(*) from public.ceo_year_plan where basis ilike '%enterpr%')
             + (select count(*) from public.target_contract where status = 'active' and objective ilike '%enterpr%')
             + (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'ceo_year_plan' and column_name ilike '%enterpr%') as names) n;
