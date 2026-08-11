-- =================================================================================================
-- A REGULATORY CHANGE WAS BEING ROUTED TO ADMINISTRATION & OPERATIONS.
--
-- org_departments carries a key whose name describes a different department:
--     dept_key = 'knowledge'      name = 'Administration & Operations'   -> operations OS
--     dept_key = 'knowledge_eng'  name = 'Knowledge Engineering'         -> knowledge OS
--
-- The OS mapping is right; the key is the misnomer, and it is load-bearing because scenarios name
-- departments BY KEY. scenario_library.regulatory_change ("Regulatory change lands") names
-- legal, procurement, knowledge - and 'knowledge' resolves to Admin & Ops, so the one department
-- whose job is to revise what the company knows after a regulation changes was never named.
--
-- fn_scenario_run reported ORG READINESS READY on it, correctly: Admin & Ops exists, is active, is
-- staffed and has a lead. Everything the check measured was true. It simply was not the department
-- the scenario meant, which is the same defect class as the rest of this session - an instrument
-- answering a question next to the one being asked.
--
-- Renaming dept_key is NOT the fix: 155 org_tasks reference 'knowledge' and it is mapped into the
-- operations OS, so the key is doing real work under a bad name. The scenario is what is wrong.
-- The confusing key is left in place and recorded in the audit rather than renamed under time
-- pressure - that is a migration, not a one-row correction.
-- =================================================================================================

update public.scenario_library
   set departments = array_replace(departments, 'knowledge', 'knowledge_eng')
 where scenario_key = 'regulatory_change'
   and 'knowledge' = any(departments);

comment on column public.org_departments.dept_key is
  'Stable routing key. NOTE: dept_key ''knowledge'' is Administration & Operations (operations OS); '
  'Knowledge Engineering is ''knowledge_eng'' (knowledge OS). Check the name before naming a key.';
