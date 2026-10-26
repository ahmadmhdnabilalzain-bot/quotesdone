-- CROSSWALK VALIDATION. The supplied crosswalk maps production department keys to the 24 target
-- departments, but it was written against a description of production rather than against
-- production. Checking both sides against the live tables is the single most useful thing this
-- import can do, because every downstream ownership and authority decision rests on it.
update ops_kb_stage.department_crosswalk x
set production_exists = exists (select 1 from public.org_departments d where d.dept_key = x.production_dept_key),
    target_exists     = exists (select 1 from ops_kb_stage.departments t where t.department_key = x.target_department_key);

-- Production departments the crosswalk never mentions. These are live departments with agents,
-- authority rows and running work that the target model has simply not accounted for - the opposite
-- of the usual gap, and the more dangerous direction: promoting the target model as-is would leave
-- them without a defined owner in the new structure.
insert into ops_kb_stage.department_crosswalk (production_dept_key, target_department_key, mapping_type, note,
                                               production_exists, target_exists, review_status)
select d.dept_key, '(none)', 'UNMAPPED_PRODUCTION_DEPARTMENT',
       'Live production department with ' ||
       (select count(*) from public.org_agents a where a.department = d.dept_key) || ' agent(s) and ' ||
       (select count(*) from public.org_authority au where au.dept_key = d.dept_key) ||
       ' authority row(s), absent from the supplied production-to-target crosswalk. Needs an owner in the target model before any promotion.',
       true, false, 'needs_decision'
from public.org_departments d
where not exists (select 1 from ops_kb_stage.department_crosswalk x where x.production_dept_key = d.dept_key)
on conflict (production_dept_key, target_department_key) do nothing;

-- Target departments that no production department maps to (other than via the catch-all row).
insert into ops_kb_stage.department_crosswalk (production_dept_key, target_department_key, mapping_type, note,
                                               production_exists, target_exists, review_status)
select '(none)', t.department_key, 'TARGET_WITHOUT_PRODUCTION_OWNER',
       'Target department with no production department mapped to it. Implementation assessment in the corpus: ' ||
       coalesce(t.implementation_status, 'unknown') || '.',
       false, true, 'needs_decision'
from ops_kb_stage.departments t
where not exists (
  select 1 from ops_kb_stage.department_crosswalk x
  where x.target_department_key = t.department_key and x.production_dept_key <> '(none)'
)
on conflict (production_dept_key, target_department_key) do nothing;
