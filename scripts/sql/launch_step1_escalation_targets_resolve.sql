-- LAUNCH STEP 1 — THE DECLARED ESCALATION GRAPH RESOLVES TO REAL, ACTIVE ROLES.
--
-- Measured 2026-08-31 on htdblwldjkcgjvmqkbeh: org_role.escalation_targets is read by fn_role_handoff
-- (as an allow-list note) and folded into agent context by fn_agent_context_v3, so a target that does
-- not resolve to an active role is misinformation an agent may act on. Six edges over the active roles
-- did not resolve:
--   * three HR roles pointed at 'hr_director' — that is the AGENT KEY of the HR head; the ROLE id is
--     'agent_workforce_capability_director'. A role_id was required and an agent_key was written.
--   * chief_of_staff listed itself ('ceo','chief_of_staff') — a self-edge; escalating to yourself is
--     escalating to nobody. It already lists ceo, so the self-entry is dead weight, removed.
--   * organization_designer pointed at 'chief_performance_officer', which is RETIRED. Repointed to its
--     own manager role, agent_workforce_capability_director.
--   * marketplace_director carried ['chief_of_staff','chief_of_staff'] (a duplicate) and omitted its
--     manager ceo. Deduped and its manager added.
--
-- LEFT AS-IS BY DESIGN (not defects): ceo -> 'founder' (the single intended founder pointer), and
-- financial_controller -> 'external UAE tax professional or firm' (a real external-advisor escalation
-- for UAE tax matters; its internal targets cfo and general_counsel resolve fine).
--
-- Data only: escalation_targets carries no count, so the Phase A freeze (which compares
-- department/role/overlay COUNTS) passes without a change reason - this changes no shape.
--
--   node scripts/apply_sql.mjs scripts/sql/launch_step1_escalation_targets_resolve.sql --apply --ddl

-- Three HR roles: agent_key 'hr_director' -> role_id 'agent_workforce_capability_director'.
update public.org_role
   set escalation_targets = array_replace(escalation_targets, 'hr_director', 'agent_workforce_capability_director')
 where role_id in ('culture_and_performance_manager','learning_and_development_manager','recruitment_specialist')
   and 'hr_director' = any(escalation_targets);

-- chief_of_staff: drop the self-edge, keep ceo.
update public.org_role
   set escalation_targets = array['ceo']
 where role_id = 'chief_of_staff'
   and escalation_targets @> array['chief_of_staff'];

-- organization_designer: retired chief_performance_officer -> its manager agent_workforce_capability_director.
update public.org_role
   set escalation_targets = array_replace(escalation_targets, 'chief_performance_officer', 'agent_workforce_capability_director')
 where role_id = 'organization_designer'
   and 'chief_performance_officer' = any(escalation_targets);

-- marketplace_director: dedupe the doubled chief_of_staff and add its manager ceo.
update public.org_role
   set escalation_targets = array['ceo','chief_of_staff']
 where role_id = 'marketplace_director';
