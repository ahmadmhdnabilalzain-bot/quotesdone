-- REORGANISING THE AGENT COMPANY - 17: every packaged identity points at somebody who exists.
--
-- Section 1 asserts that "all 96 packaged role identities resolve to an active canonical role".
-- Measured on production, 14 Aug 2026: 90 of 96 do. Six org_role_identity rows name an employee
-- that the merge deactivated. All six are readiness='blocked', and all six resolve correctly
-- through fn_org_agent_resolve - which is why nothing has failed and no watcher has seen them.
--
--   agent_key              packaged_role_id                                    successor
--   analytics_director     data-analytics-and-intelligence-director            intel_director
--   analytics_director     data-analytics-and-intelligence-operations-...      intel_director
--   analytics_director     data-analytics-and-intelligence-reviewer-auditor    intel_director
--   marketing_copy         marketing-operations-specialist                     marketing_content
--   notification_ops       notification-and-communications-operations-...      channel_specialist
--   supplier_intel_analyst supplier-knowledge-analyst-controller               supplier_analyst
--
-- THIS EXPLAINS THE 133. org_role_identity is (employee, packaged role), not one row per packaged
-- role, so its count is not comparable to 96 and never was:
--
--   133 rows = 94 distinct employees holding 96 distinct packaged roles
--    -  37 rows are the second and later holders of a packaged archetype held by several desks
--    -   6 of the 133 are these dead rows
--    -   3 were added earlier today transferring identities off merged-away employees
--
-- FIVE OF THE SIX ARE DELETED, NOT TRANSFERRED, because the successor ALREADY holds that packaged
-- role - marketing_content is one of five desks on marketing-operations-specialist, and so on. A
-- transfer would write a duplicate of a row that is already there.
--
-- THE SIXTH IS DELETED FOR A DIFFERENT AND STRONGER REASON. intel_director does NOT hold
-- data-analytics-and-intelligence-reviewer-auditor; knowledge_validator does, and knowledge_validator
-- is data_intel's independent reviewer. Transferring analytics_director's claim to intel_director
-- would hand the DEPARTMENT HEAD the reviewer-auditor identity for its own department - the
-- creator/reviewer conflict that section 1 requires to be zero, created by the very act of tidying
-- up. Deleting it leaves knowledge_validator as the sole holder, which is the correct org.
--
-- No alias is lost: org_agent_alias already resolves all six old keys, and that is where the
-- history of a name belongs. org_role_identity answers "who holds this role NOW".

begin;

-- Guarded: only ever removes a row whose employee is inactive AND whose packaged role still has
-- another holder. If either stops being true this deletes nothing rather than orphaning a role.
delete from org_role_identity i
 where not exists (select 1 from org_agents a where a.agent_key = i.agent_key and a.active)
   and exists (select 1 from org_role_identity j
                where j.packaged_role_id = i.packaged_role_id
                  and j.agent_key <> i.agent_key
                  and exists (select 1 from org_agents b where b.agent_key = j.agent_key and b.active));

commit;
