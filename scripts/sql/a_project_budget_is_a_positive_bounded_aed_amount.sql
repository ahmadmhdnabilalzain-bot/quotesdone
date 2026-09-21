-- a_project_budget_is_a_positive_bounded_aed_amount.sql — sales_engineer, 21 Sep 2026.
--
-- MEASURED (production htdblwldjkcgjvmqkbeh, 21 Sep 2026, read-only):
--   public.projects.budget_total is `numeric` with NO precision and NO check constraint on the
--   table (pg_constraint contype='c' for public.projects: none). 1 project, budget 180000; 0 rows
--   outside (0, 1e9] and 0 NaN — so this constraint validates against the data as it stands.
--
-- WHAT WAS WRONG (customer-portal journey audit, 21 Sep 2026):
--   project_api wrote Number(body.budget_total) straight into the column. A negative budget was
--   stored, a budget of any size was stored, and free text became NaN — which Postgres numeric
--   ACCEPTS as the value 'NaN'. The only bound was the form's min/max attributes, which a direct
--   request never passes through.
--
-- WHAT THIS CHANGES:
--   One CHECK constraint: budget_total is NULL (no budget set) or a positive AED amount of at most
--   AED 1,000,000,000. NaN is excluded too: in Postgres NaN sorts above every number, so
--   `<= 1000000000` is false for it. The same bound lives in supabase/functions/_shared/project_budget.ts,
--   which project_api (the trust boundary) and the portal form both call; this makes it true for
--   EVERY writer of the table, not only that function.
--
-- WHAT THIS DOES NOT CHANGE:
--   inquiries.budget — the per-request budget from intake — is free text by design ("AED 50–80k",
--   "open"), clipped to 80 characters by customer_api, and is not touched here.
--   No routine, no grant, no policy is created or altered.
--
-- ENDS WITH a verdict row: PROBE OK when the constraint exists, PROBE FAILED otherwise.

alter table public.projects drop constraint if exists projects_budget_total_positive_bounded;
alter table public.projects add constraint projects_budget_total_positive_bounded
  check (budget_total is null or (budget_total > 0 and budget_total <= 1000000000));

select case when exists (
  select 1 from pg_constraint
   where conrelid = 'public.projects'::regclass and conname = 'projects_budget_total_positive_bounded' and contype = 'c'
) then 'PROBE OK' else 'PROBE FAILED' end as verdict;
