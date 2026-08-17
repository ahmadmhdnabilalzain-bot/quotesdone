-- Rollback for K21, cutover increment 2 (supplier, payment and system-health sources).
--
-- Removing the cutover means deleting the marked "-- K20 cutover." block from each of
-- notify_new_quote_sms, trg_reveal_receipt and fn_page_high_agent_action and re-applying. After
-- that a new quotation creates an SMS and no W14 run, a reveal creates a receipt and no W16 run,
-- and a high-risk agent action pages the founder and opens no W29 incident.
--
-- DO NOT REVERT THE CONDITION CHANGE IN fn_page_high_agent_action. K21 replaced
--
--   AND NEW.agent IN ('finance_ai','security_ai','operations_ai')
-- with
--   AND NEW.agent ~ '^(finance|security|operations)'
--
-- because the first can never match a security action: a00_agent_action_resolve_addressee runs
-- BEFORE this trigger and resolves the addressee through org_agents, so a row written as
-- 'security_ai' arrives as 'security'. Measured 17 Aug 2026 — inserting agent='security_ai' reads
-- back as 'security', and notifications holds 0 rows of type 'agent_escalation' across its entire
-- history. Putting the old list back restores a guard that has never fired once, and the founder
-- stops being paged for security incidents again.
--
-- The register correction on dbtrigger:public.company_goals:trg_goal_cascade is also left alone.
-- It records that the trigger fires on a goal RETIREMENT rather than a target miss. That is a
-- measurement of what the deployed body does, and it stays true whether or not this file is run.

select 'K21 rollback: delete the marked "-- K20 cutover." block from notify_new_quote_sms, '
       'trg_reveal_receipt and fn_page_high_agent_action and re-apply. Keep the agent-prefix '
       'condition and the goal_cascade register correction. See the comment block above.' as instruction;
