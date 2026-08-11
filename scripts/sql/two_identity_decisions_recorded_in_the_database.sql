-- PHASE 3, THE TWO IDENTITY QUESTIONS THAT ARE DECISIONS AND NOT DEFECTS.
--
-- Both were going to be "fixed" by a session that had not asked what reads them. Both turn out to be
-- decisions, and a decision that lives only in a session log gets re-litigated. So it is recorded
-- where the next reader of the table will hit it.
--
-- ================================================================================================
-- 1. model_policy_by_identity — 96 rows with no reader. NOT ALIASED, and here is why.
-- ================================================================================================
-- The audit filed these as instance 5 of "a complete thing addressed to an identity the system does
-- not model" and the fix was going to be org_agent_alias + fn_org_agent_resolve at the write
-- boundary — about a day's work. Measured first:
--
--   fn_ai_route is the only routing reader of this table, and it selects ONE scope:
--       where scope = 'current_agent'
--         and (identity_key = p_agent_key or (identity_key = 'cat:*' and p_agent_key like 'cat:%'))
--
--   scope = 'target_employee' is selected NOWHERE. The other two readers, fn_ops_department_context
--   and the pack scorecard, route no model.
--
-- So the diagnosis was one layer off: it is not a complete thing addressed to an identity nobody
-- models, it is a complete thing addressed to a READER THAT DOES NOT EXIST. Making the 96 keys
-- resolvable would leave them exactly as unread — a bridge to nowhere.
--
-- The remaining question is not a defect to patch. Should per-employee model routing exist at all?
-- Turning these 96 policies on would change which model each of 94 employees uses, with a direct
-- and immediate cost consequence. That belongs with the founder. Deleting them is a destructive
-- production change to imported pack configuration (package_version v2026.07.31), which belongs
-- there too.
--
-- Neither branch is taken here. What IS done is that the table can no longer be read as live
-- routing configuration by anyone who opens it.

comment on table public.model_policy_by_identity is
  'PER-IDENTITY MODEL POLICY. Only scope=''current_agent'' (24 rows) is ever read, by fn_ai_route, '
  'and only when the task class is unmapped. scope=''target_employee'' (96 rows) is selected by NO '
  'query anywhere in this database — verified 11 Aug 2026 against every routine body in public. '
  'Those 96 rows are imported v2026.07.31 pack configuration with no reader, not live routing. '
  'Do not read a number off this table as "the model 94 employees use". Turning them on is a cost '
  'decision for the founder; deleting them is a destructive change to imported config. Until one of '
  'those two happens, they are inert.';

comment on column public.model_policy_by_identity.scope is
  'Discriminator. ''current_agent'' is live and read by fn_ai_route. ''target_employee'' has no '
  'reader — see the table comment. Adding a third value without a reader repeats the defect.';

-- ================================================================================================
-- 2. dept_key = 'knowledge' is named "Administration & Operations". NOT RENAMED, and here is why.
-- ================================================================================================
-- A separate department, dept_key='knowledge_eng', is "Knowledge Engineering". So any code routing
-- on the literal 'knowledge' reaches Admin & Ops, and any human reading dept_key believes it reached
-- Knowledge. That already cost one real misroute: scenario_library.regulatory_change named
-- departments legal, procurement, knowledge — and reached Admin & Ops. That row now reads
-- knowledge_eng, which is the correct fix for a misroute: fix the CALLER, not the key.
--
-- Counted on production 11 Aug 2026 before deciding:
--
--   org_tasks with dept_key='knowledge'      155        org_agents in it       4  (docs, ops_director,
--   org_tasks with dept_key='knowledge_eng'   59        org_agents in it       3   process_improvement_mgr,
--   routines whose body contains 'knowledge'  11                                   project_coordinator)
--
-- A rename is a data migration across 155 task rows, 4 employees, a health_fn mapping and 11 routine
-- bodies carrying the literal — to buy readability, in a system whose recurring defect is a complete
-- thing addressed to an identity nobody models. The risk of a missed string literal is precisely
-- that defect. The key stays; the ambiguity is removed by labelling it where a reader lands.

comment on column public.org_departments.dept_key is
  'Stable routing key. IT DOES NOT MATCH THE NAME IN TWO PLACES AND THAT IS DELIBERATE: '
  'dept_key=''knowledge'' is "Administration & Operations" (docs, ops_director, '
  'process_improvement_mgr, project_coordinator), and Knowledge Engineering is dept_key='
  '''knowledge_eng''. Routing on the literal ''knowledge'' expecting knowledge work is a bug — '
  'scenario_library.regulatory_change had exactly that and was corrected on 11 Aug 2026. '
  'Decided 11 Aug 2026 NOT to rename: 155 org_tasks, 4 employees, a health_fn mapping and 11 '
  'routine bodies carry the literal, and a missed one reintroduces the misroute silently.';
