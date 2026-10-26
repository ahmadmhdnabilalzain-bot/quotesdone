-- Follow-up to org_departments_against_the_spec.sql: four departments that already existed were
-- measured, not assumed, and three of them owned nothing while a fourth belonged to no Operating
-- System at all.
--
--   supplier_success  os_department rows: 0   department_objective rows: 0
--   knowledge_eng     os_department rows: 1   department_objective rows: 0
--   intelligence      os_department rows: 1   department_objective rows: 0
--   evolution         os_department rows: 1   department_objective rows: 0
--
-- An employee whose department has no os_department row gets NO "# YOUR OPERATING SYSTEM" block
-- from fn_agent_context at all — no purpose, no mission, no owner to escalate to, and none of its
-- OS objectives. Supplier Success is the specification's second department and its three staff
-- have been working without any of that.
begin;

insert into public.os_department (os_key, dept_key, note) values
 ('marketplace','supplier_success','Supplier acquisition, onboarding, verification and retention are the Marketplace OS''s own mandate. The row was simply missing.')
on conflict do nothing;

insert into public.department_objective (dept_key, objective, horizon, sort, active) values
 ('supplier_success','Activated suppliers per week rises without the invite bounce rate rising with it','quarterly',1,true),
 ('supplier_success','No approved supplier sits with an expired trade licence','weekly',2,true),
 ('knowledge_eng','Every employee answers from current, cited, validated knowledge','quarterly',1,true),
 ('knowledge_eng','Knowledge whose confidence has decayed is re-validated or quarantined, never quietly served','weekly',2,true),
 ('intelligence','Every decision the executive team takes is made against a number somebody trusts','quarterly',1,true),
 ('intelligence','Forecasts are graded against what actually happened','monthly',2,true),
 ('evolution','The company is measurably better than it was last week, and the evidence is in the outcome ledger','quarterly',1,true),
 ('evolution','Anything that made the company worse is reversed rather than absorbed','weekly',2,true)
on conflict do nothing;

commit;
