-- PHASE 1.5 - explicit authority rows for the eight hard gates that had none.
--
-- On 2 Aug the audit found that org_authority named 33 (department, action_class) pairs but only 2
-- of the corpus's 10 hard gates - ad_spend and money_move - appeared among them. The other eight
-- were safe only because fn_ops_authority_check defaults to gated when no row exists. Any other
-- code path reading org_authority directly found nothing and had to invent a default. Filling them
-- in is itself an authority change, which is hard-gated, so it waited for the founder's instruction.
-- That instruction has been given.
--
-- Every row below is 'gated'. Not one of them widens anything: the effective tier for all eight was
-- already gated by fail-closed default, so this changes what the table SAYS, not what the system
-- ALLOWS. That is the point - a control that only exists as a fallback is a control nobody can audit.
insert into public.org_authority (dept_key, action_class, max_tier, threshold_aed, note)
select d.dept_key, g.action_class, 'gated', g.threshold_aed,
       '2026-08-02 Phase 1.5: explicit hard gate. Approval role: ' || g.approval_role ||
       '. Previously gated only by the fail-closed default in fn_ops_authority_check, i.e. correct behaviour with no auditable statement behind it.'
from public.org_departments d
cross join (values
  ('authentication_identity', 'Authorised security/identity owner', null::numeric),
  ('autonomy_framework',      'Founder / AI Governor',              null),
  ('destructive_data',        'Data owner plus legal/privacy approval where applicable', null),
  ('legal_commitment',        'Founder or authorised legal signatory', null),
  ('production_deploy',       'Engineering owner with tested rollback', null),
  ('public_claim_publish',    'Founder or marketing owner',          null),
  ('secrets_security',        'Authorised security owner',           null),
  ('supplier_enforcement',    'Trust & Safety owner',                null)
) as g(action_class, approval_role, threshold_aed)
on conflict do nothing;

-- PHASE 1.6 - department ownership.
-- The crosswalk validation found three conflicts: production departments hr and sales are live,
-- with agents and authority rows, and the supplied target model does not mention either; and target
-- department ai_model_ops has no production owner. All three are resolved here as instructed.
update public.org_departments
set name = 'HR & People Operations',
    charter = coalesce(nullif(btrim(charter),''),
      'Owns hiring, role definition, onboarding, capability development and the people side of the operating model. Maps to the target department hr_people.')
where dept_key = 'hr';

update public.org_departments
set name = 'Sales & CRM',
    charter = coalesce(nullif(btrim(charter),''),
      'Owns pipeline, outreach, CRM hygiene and conversion from lead to registered supplier or customer. Maps to the target department sales_crm.')
where dept_key = 'sales';

-- ai_model_ops: assigned rather than created. Production already runs it - ai_gateway, fn_ai_route,
-- model_policy, budgets and ai_cost_log all exist and are measured - under dept_key 'it'
-- (Technology). Creating a 15th empty department with no agents and no authority would make the
-- Command Center report a broken department on day one, which is exactly what the corpus import was
-- careful not to do. So the capability is formally assigned to an existing owner, and the crosswalk
-- says so.
update public.org_departments
set charter = coalesce(nullif(btrim(charter),''), 'Technology and platform engineering.') ||
              ' Also formally owns AI Model Operations (target department ai_model_ops): model routing policy, ' ||
              'capability-aware selection, per-department AI budgets, cache policy and cost telemetry, as implemented in ' ||
              'ai_gateway / fn_ai_route / model_policy / ai_cost_log.'
where dept_key = 'it' and coalesce(charter,'') not like '%ai_model_ops%';

update ops_kb_stage.department_crosswalk
set production_dept_key = 'hr', mapping_type = 'direct', review_status = 'resolved',
    production_exists = true, target_exists = true,
    note = '2026-08-02 founder decision: production department hr is HR & People Operations and owns the target department hr_people.'
where target_department_key = 'hr_people';

update ops_kb_stage.department_crosswalk
set production_dept_key = 'sales', mapping_type = 'direct', review_status = 'resolved',
    production_exists = true, target_exists = true,
    note = '2026-08-02 founder decision: production department sales is Sales & CRM and owns the target department sales_crm.'
where target_department_key = 'sales_crm';

insert into ops_kb_stage.department_crosswalk
  (production_dept_key, target_department_key, mapping_type, note, production_exists, target_exists, review_status)
values ('it','ai_model_ops','direct_plus_shared',
        '2026-08-02 founder decision: AI Model Operations is formally assigned to production department it (Technology), which already runs ai_gateway, fn_ai_route, model_policy and ai_cost_log. No new department created - a 15th department with no agents and no authority would read as broken from day one.',
        true, true, 'resolved')
on conflict (production_dept_key, target_department_key) do update
  set mapping_type = excluded.mapping_type, note = excluded.note, review_status = 'resolved';

-- retire the placeholder conflict rows now that all three are answered
delete from ops_kb_stage.department_crosswalk
where mapping_type in ('UNMAPPED_PRODUCTION_DEPARTMENT','TARGET_WITHOUT_PRODUCTION_OWNER')
  and (production_dept_key in ('hr','sales') or target_department_key in ('ai_model_ops','hr_people','sales_crm'));
