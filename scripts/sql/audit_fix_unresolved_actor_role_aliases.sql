-- AUDIT FIX (OA-1, OA-2): two active workflow actor_roles resolved to no agent.
--
-- The 2 Sep connectivity audit found workflow_step.actor_role values that fn_org_agent_resolve()
-- returns NULL for -- an "addressed to an identity nobody models" gap: the workflow step names an
-- accountable role that no live agent answers to, so the step can never dispatch.
--
--   corporate_performance_director  -> NULL   (blocks all 3 goal_retirement_replan steps; the sibling
--                                              chief_performance_officer already aliases to cpo)
--   strategic_partnerships_government_relations_manager -> NULL (blocks a lead_to_customer step;
--                                              gov_relations_mgr is the live agent for that role)
--
-- FIX: one org_agent_alias row each, mirroring how every other role_id resolves. Pure data, no
-- component or frozen-subject change. Verified after: both resolve to a live agent.
--
--   node scripts/apply_sql.mjs scripts/sql/audit_fix_unresolved_actor_role_aliases.sql --apply --ddl

begin;

insert into public.org_agent_alias (alias, agent_key, reason)
values ('corporate_performance_director', 'cpo',
        'Corporate Performance Director is the active exec role; it shares the cpo runtime agent with chief_performance_officer (already aliased). Its workflow_step.actor_role in goal_retirement_replan resolved to no agent until this row. Audit OA-1, 2 Sep 2026.')
on conflict (alias) do nothing;

-- OA-2: gov_relations_mgr is the semantically-closest agent but is INACTIVE, and fn_org_agent_resolve
-- only returns an alias whose target agent is active. partnerships_mgr is the active agent that owns
-- the government/enterprise-counterparty step (lead_to_customer step 8), so the alias points there.
insert into public.org_agent_alias (alias, agent_key, reason)
values ('strategic_partnerships_government_relations_manager', 'partnerships_mgr',
        'The lead_to_customer workflow names this role as its government/enterprise-counterparty step actor (step 8). The specialised gov_relations_mgr agent is inactive, so this resolves to the active partnerships_mgr. Resolved to no agent until this row. Audit OA-2, 2 Sep 2026.')
on conflict (alias) do update set agent_key = excluded.agent_key, reason = excluded.reason;

commit;
