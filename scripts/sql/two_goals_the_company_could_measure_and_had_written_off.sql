-- TWO GOALS THE COMPANY COULD MEASURE AND HAD WRITTEN OFF.
--
-- The founder: "34 goals / 14 KPIs lack a measure; each carries a reason — re-read them, two of
-- mine were the wrong kind."
--
-- Re-read. The reasons fall into two families and most of them are RIGHT:
--
--   "NO INSTRUMENT EXISTS"                          nothing in this database records it
--   "THE NUMERATOR AND DENOMINATOR ARE A BUSINESS   the data exists, the definition is the
--    DECISION"                                       founder's to make
--
-- Two carry the first reason and should not. Both have an instrument, both have rows, and both are
-- measurable today with plain SQL.
--
-- I ALSO NEARLY ADDED TWO MEASURES THAT WOULD HAVE BEEN FICTION, and the check that stopped it is
-- worth recording. `data_breaches` and `compliance_violations` look measurable because
-- security_events exists and has 42 rows. It does not record either of those things. Its entire
-- vocabulary is admin_login, anon_exposure_drift, backup_overdue, memory_lint_block and
-- override_spike - operational security signals. Counting them as "data breaches" would have put a
-- confident zero on the founder's screen for a question this database cannot answer, which is the
-- decorative-number defect this codebase keeps producing. Those two keep NO INSTRUMENT EXISTS, and
-- their reason is now specific about why rather than generic.
--
-- WHAT THIS COSTS: attainment goes DOWN, and that is the point. knowledge_modules_complete measures
-- 5.38 against a target of 100. Until now it measured NULL, and least(100.0, NULL) returns 100.0 in
-- Postgres - the defect that once put 97.7% attainment in the founder's email on a zero-revenue day.
-- An unmeasured goal was scoring as a perfect one. This replaces one of those with the truth.

-- ── knowledge_modules_complete ──────────────────────────────────────────────────────────────────
-- "Knowledge bases at the 14-module standard", target 100 (%).
-- MEASURED: 93 active employees, all 93 carry agent_knowledge rows, and 5 of them - 5.38% - hold 14
-- or more. agent_knowledge is the store, org_agents.active is the population, and the 14-module
-- standard is already named in the goal itself.
--
-- Joined to org_agents so a retired agent's knowledge cannot flatter the number: the 44 inactive
-- category agents each carry 7-9 rows of superseded vocabulary and counting them would drag the
-- denominator without ever being work anyone can do.
update public.company_goals
   set measure_sql = $m$
select round(100.0 * count(*) filter (where m >= 14) / nullif(count(*),0), 2)
  from (select a.agent_key, count(*) m
          from public.agent_knowledge a
          join public.org_agents o on o.agent_key = a.agent_key and o.active
         group by 1) per
$m$,
       no_measure_reason = null,
       updated_at = now()
 where key = 'knowledge_modules_complete';

-- ── knowledge_review_cycle ──────────────────────────────────────────────────────────────────────
-- "Knowledge reviewed every 90 days", metric "Days since last review", direction at_most 90.
-- The goal is a CEILING on staleness, so the measure is the WORST case, not the average: one module
-- untouched for a year is the thing this goal exists to catch, and a mean would bury it under 2,041
-- fresh rows. Same active-agent join, same reason.
update public.company_goals
   set measure_sql = $m$
select coalesce(max(current_date - a.updated_at::date), 0)::numeric
  from public.agent_knowledge a
  join public.org_agents o on o.agent_key = a.agent_key and o.active
$m$,
       no_measure_reason = null,
       updated_at = now()
 where key = 'knowledge_review_cycle';

-- ── the two that correctly have no instrument, now saying WHY ───────────────────────────────────
-- Replacing the generic reason with the specific one, so the next reader does not have to re-derive
-- it and does not repeat the mistake of assuming security_events answers this.
update public.company_goals
   set no_measure_reason = 'NO INSTRUMENT EXISTS. security_events looks like the instrument and is '
       'not one: its entire vocabulary is admin_login, anon_exposure_drift, backup_overdue, '
       'memory_lint_block and override_spike - operational signals, not breaches or violations. '
       'Counting them here would put a confident zero on a question this database cannot answer. '
       'A real measure needs an incident register with a declared severity and a regulator-facing '
       'classification, which does not exist yet.',
       updated_at = now()
 where key in ('data_breaches','compliance_violations')
   and coalesce(measure_sql,'') = '';
