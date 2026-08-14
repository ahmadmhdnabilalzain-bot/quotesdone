-- REORGANISING THE AGENT COMPANY — the target-operating-model crosswalk, found by the pack
-- scorecard.
--
-- `ops_kb_stage.department_crosswalk` maps a PRODUCTION department key onto the packaged target
-- departments. It is the only table outside `public` keyed on a production department key, and the
-- migration did not touch it — so `fn_ops_department_context('marketplace')` returned 0 target
-- departments and 0 decision rules where `procurement` returned 3 and 30, and the block that
-- `fn_agent_context` emits as "# THE TARGET OPERATING MODEL" vanished for every employee in a
-- merged department.
--
-- Measured by the pack scorecard, which is exactly what it is for: IN USE fell from 37/37 to 36/37
-- with "2 · COMPANY_OPERATIONS · decision rules enabled + in decider context — probe returned 0".
--
-- The mapping is not invented here. `public.org_department_alias` already holds the authoritative
-- packaged-department -> runtime-department map, and the migration repointed it to the canonical
-- ten. This file inverts it. Four packaged departments — admin_operations, business_development,
-- communications, qa_testing — were `production_dept_key = 'unmapped_target'` because no single
-- production department owned them; each now has one.

begin;

insert into ops_kb_stage.department_crosswalk
  (production_dept_key, target_department_key, mapping_type, note,
   production_exists, target_exists, review_status)
select a.dept_key, a.packaged_department,
       case when a.is_second_home then 'second_home' else 'merged_owner' end,
       'derived from org_department_alias on 14 Aug 2026, after 25 departments merged into 10',
       true, true, 'reviewed'
  from public.org_department_alias a
  join public.org_departments d on d.dept_key = a.dept_key and d.active
 where not exists (select 1 from ops_kb_stage.department_crosswalk c
                    where c.production_dept_key = a.dept_key
                      and c.target_department_key = a.packaged_department);

-- The historical rows stay: those production keys still exist as inactive departments, still carry
-- history, and fn_ops_department_context is still asked about them by name in older traces.

commit;
