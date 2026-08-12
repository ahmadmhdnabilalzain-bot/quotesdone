-- SEVEN EMPTY OFFICER REPORTS I CREATED WHILE PROBING DURING A PROVIDER OUTAGE.
--
-- Verifying the exec_review timeout fix meant invoking exec_agents on production three times
-- (run_all twice, run once). anthropic/claude-sonnet-5 happened to be failing at that moment -
-- 25 of 86 calls in six hours across exec_agents, action_worker AND agent_brain, each dying in
-- 258-698ms with 0 output tokens, while haiku ran 63/68 and gemini 11/11 - so every officer fell
-- through to its own honest fallback and filed:
--
--   summary          "Metrics captured; AI synthesis unavailable this run."
--   findings         []
--   recommendations  []
--
-- exec_reports 289-295, all between 07:23:23 and 07:25:36 on 2026-08-12.
--
-- THAT TURNED A GREEN CHECK RED, AND THE CHECK WAS RIGHT TO GO RED.
-- s36's sibling exec-intel-quantified-recommendation reads the NEWEST report per officer and went
-- from MET to "1 of 7 officer(s) with a report in 14d carry a numeric recommendation; 6 filed an
-- empty recommendation". Six of those seven officers are mine. The company's last REAL run did
-- produce quantified recommendations; my probe displaced it.
--
-- These rows are not company work and they are not a record of anything the company did. They are
-- residue from a manual probe fired into a provider outage, and exec_agents itself already recorded
-- each one as status='error' in agent_runs with the reason - that record stays, and it is the
-- honest one. Deleting the reports restores the check to reading the last real reports rather than
-- my probe.
--
-- THE GUARD IS DELIBERATELY NARROW: the exact fallback summary, zero findings AND zero
-- recommendations, and only rows from this window. A real officer report can carry an empty
-- recommendation list for real reasons, and none of those is being touched. On staging the
-- predicate matches nothing and this is a no-op.

delete from public.exec_reports
 where summary = 'Metrics captured; AI synthesis unavailable this run.'
   and coalesce(jsonb_array_length(recommendations), 0) = 0
   and coalesce(jsonb_array_length(findings), 0) = 0
   and created_at >= timestamptz '2026-08-12 07:20:00+00'
   and created_at <  timestamptz '2026-08-12 07:30:00+00';
