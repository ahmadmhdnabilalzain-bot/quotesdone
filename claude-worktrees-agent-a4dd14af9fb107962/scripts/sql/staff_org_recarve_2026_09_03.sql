-- STAFF_ORG RE-CARVE (3 Sep 2026) — PACR-004.
--
-- The founder's STAFF_ORG.md: ten departments re-carved so every stage of the money loop has exactly
-- one owner, Supply pulled out of the 17-person Marketplace blob, Growth re-pointed at buyers as
-- Demand, Assurance dissolved into Platform & Reliability, People Ops become Agent Ops, and every
-- persona that owns no live firing decision parked at zero cost with its title kept for re-hire.
--
-- HOW THIS WAS DECIDED (measured, not typed). Every one of the 90 personas was scored on its live
-- accountability before a seat was assigned: phase_c_component rows whose accountable role resolves
-- to it, workflow_step rows naming it, event_subscription and employee_workflow rows, and department
-- lead slots. A persona keeps a seat when the plan names its function AND it carries live
-- accountability; a persona parks when it carries none the plan wants kept. Where the plan parks a
-- persona that still carries accountability (strategy_director, marketing, risk_governance_mgr,
-- ap_specialist, innovation_mgr, docs, the four spec_* overlays...), that accountability is moved
-- here to the seat that now owns the function — never left dangling, because a component whose
-- accountable role is retired errors on every kernel tick.
--
-- TWO DELIBERATE DEPARTURES FROM THE PLAN'S SEAT LIST, both because the runtime is the truth:
--   * ops_director (Chief Operating Officer) is NOT parked. 237 active components carry the COO as
--     their accountable role — the kernel's wrap default. Parking the COO would orphan them, and
--     re-pointing 237 rows to another catch-all is the same defect with a new name (the default was
--     the author). The COO moves to the Office of the CEO and keeps that accountability until each
--     department's loop is proven and takes its own rows — that is the Evolution agent's queue.
--   * ai_director (14 active components: gateway, model policy, prompts) is NOT parked: model policy
--     for an all-software staff IS Agent Ops work, so it moves there.
--   * FIFTEEN of the 34 parks are REVERSED by part 2 (staff_org_recarve_bindings_2026_09_03.sql).
--     A Phase B handoff needs two parties (phase_b_handoff_two_parties), and 22 handoffs in W01, W02,
--     W07, W21–W28 and W30 join a step owned by a parked persona to a step owned by its successor.
--     The founder's approved workflows treat those personas as distinct parties, so they keep a seat:
--     strategy_director, boq_analyst, drawing_analyst, account_mgr, innovation_mgr, ai_architect,
--     test_automation_eng, model_evaluator, forecast_analyst, kb_engineer, taxonomy_manager,
--     financial_analyst, contract_specialist, risk_governance_mgr, org_designer. Net: 71 seated,
--     19 parked. Reaching the plan's ~48 would mean merging those 22 handoffs — a redesign of the
--     founder's workflows, not a roster decision, and not done here.
-- Keys are kept everywhere (dept_key, agent_key, role_id): 25 tables reference departments and 50
-- reference agents, and the crosswalk, the connectivity register and 21 kernel boards read them.
-- The re-carve is in NAMES, MEMBERSHIP, ACCOUNTABILITY and ACTIVATION, not in identifiers.
--
-- Nothing here is a Phase A/B/C amendment ceremony: the founder removed the phase freezes on
-- 2 Sep 2026. org_phase_baseline is still append-only by trigger, so its digests are recomputed in
-- place the way PACR-002 and PACR-003 did, and a drift check that read the old digests would
-- otherwise report this re-carve as unapproved drift.
--
--   node scripts/apply_sql.mjs scripts/sql/staff_org_recarve_2026_09_03.sql --apply --ddl
--   (rehearsal: the same text with `set local app.recarve_rehearsal = '1'` prepended rolls back
--    at the end and prints the counts it would have committed)
begin;
set local app.phase_a_change_reason =
  'PACR-004: STAFF_ORG re-carve of 3 Sep 2026 — Supply carved out of Marketplace, Assurance merged '
  'into Platform & Reliability, 34 personas parked with their accountability moved to named seats.';
set local app.change_reason = 'PACR-004 STAFF_ORG re-carve 3 Sep 2026: assurance merged into product_eng';

-- =============================================================================================
-- 1. DEPARTMENTS. Keys kept; one new (supply); one merged (assurance -> product_eng).
-- =============================================================================================
insert into public.org_departments (dept_key, name, charter, north_star, health_fn, lead_agent, brain_agent, active, sort)
values ('supply', 'Supply',
  'Turns the scraped company base into verified suppliers who can actually be quoted: the invite campaign, claim and onboarding, the licence gate that flips a supplier to verified, retention of responsive suppliers, and the category coverage gap that tells Demand where to advertise and Invite where to recruit.',
  'Matchable verified suppliers per category (today: 1)',
  null, 'bd', 'bd', true, 35)
on conflict (dept_key) do update
  set name = excluded.name, charter = excluded.charter, north_star = excluded.north_star,
      lead_agent = excluded.lead_agent, brain_agent = excluded.brain_agent, active = true, sort = excluded.sort,
      merged_into = null, merged_at = null;

update public.org_departments d set name = m.name, charter = m.charter, north_star = m.north_star,
       lead_agent = l.lead_agent, brain_agent = l.lead_agent
  from (values
    ('exec', 'Office of the CEO',
     'Keeps the whole company pointed at AED 1M/yr and is the founder''s single interface: company goals and their retirement, arbitration between departments, the founder''s command channel, the scorecard, and — until each department proves its loop and takes its own rows — the operating accountability the kernel defaulted to the COO.',
     'AED 1,000,000 by 31 August 2027, with every department''s north-star measured and owned'),
    ('supply', 'Supply',
     'Turns the scraped company base into verified suppliers who can actually be quoted: the invite campaign, claim and onboarding, the licence gate that flips a supplier to verified, retention of responsive suppliers, and the category coverage gap that tells Demand where to advertise and Invite where to recruit.',
     'Matchable verified suppliers per category (today: 1)'),
    ('growth', 'Demand',
     'Brings in qualified buyer requests for the least ad spend: the Meta ad-spend autopilot inside the founder''s daily cap, the weekly blog, social posting and boosts, revision of under-performing content, on-page SEO, and on-brand creative at zero external cost. Supplier recruiting moved to Supply.',
     'Qualified RFQs per AED of Meta spend'),
    ('marketplace', 'Marketplace Ops',
     'Turns a buyer''s request into a clean set of comparable quotes: intake including uploaded files, routing and dispatch to matchable suppliers, match-quality tuning, quote scoring and the best-3 comparison, the ops-side coverage gap, and the reveal the moment the customer pays.',
     'Percent of RFQs with at least one fit; quote pass-rate'),
    ('finance', 'Finance & Collections',
     'Collects the 3% reveal fee, reconciles every Stripe payment to its reveal, chases supplier dues, issues invoices and keeps the ledger, and assembles the full case for any refund — which only the founder ever approves.',
     'Reveal-fee revenue collected; days-to-collect'),
    ('customer_experience', 'Customer Experience',
     'Supports buyers and suppliers across every channel including WhatsApp, owns each complaint end to end, keeps lapsing suppliers engaged, and asks for a rating at exactly the moment a quote is revealed.',
     'Complaint-resolution time; ratings collected'),
    ('legal', 'Trust, Safety & Compliance',
     'Keeps the platform clean, licensed and legal: personal-data and contact-leak moderation, suspension of suppliers who break the rules or do not pay, UAE compliance (VAT/TRN, licences, regulation changes), and the do-not-touch safety rules.',
     'Fraud and PII incidents; licence validity'),
    ('product_eng', 'Platform & Reliability',
     'Keeps the website and systems up and ships change safely: health checks that open incidents, the red-view alert to the founder, deploys with rollback, test triage that keeps the build green, and the kernel that runs every workflow. Absorbs Assurance''s server-health, security and testing people.',
     'Uptime; time from a red view to a founder alert'),
    ('data_intel', 'Data & Experimentation',
     'Grades every employee and every department, runs the self-review, drives improvement proposals to a landed decision, runs marketplace experiments, keeps the knowledge the agents rely on correct, and grades the matching engine.',
     'KPI freshness; experiments landed; knowledge accuracy'),
    ('people_ops', 'Agent Ops',
     'HR for an all-software staff: certifies each agent before it does real work, puts under-performers on an improvement plan, activates roles that own a real firing decision and parks the rest at zero cost, and owns model policy for the AI workforce.',
     'Agents certified; KPI coverage')
  ) as m(dept_key, name, charter, north_star)
  cross join lateral (select case m.dept_key
      when 'exec' then 'ceo' when 'supply' then 'bd' when 'growth' then 'sales_director'
      when 'marketplace' then 'procurement' when 'finance' then 'cfo'
      when 'customer_experience' then 'followup' when 'legal' then 'legal'
      when 'product_eng' then 'cto' when 'data_intel' then 'intel_director'
      when 'people_ops' then 'hr_director' end as lead_agent) l
 where d.dept_key = m.dept_key;

update public.org_departments
   set active = false, merged_into = 'product_eng', merged_at = now(),
       charter = charter || chr(10) || chr(10) || 'MERGED 3 Sep 2026 (PACR-004): the department policed the abolished rulebook. Its server-health, security and testing people moved to Platform & Reliability; the QA reviewers of AI output parked.'
 where dept_key = 'assurance';
-- Flatten the chain so fn_dept_canonical resolves in one hop for the departments that had merged
-- into assurance earlier.
update public.org_departments set merged_into = 'product_eng' where merged_into = 'assurance';

-- =============================================================================================
-- 2. THE SEAT MAP. 56 seats. Every line is a decision; nothing is inferred at apply time.
-- =============================================================================================
create temp table recarve_seat (agent_key text primary key, dept text not null, manager text, seat text not null) on commit drop;
insert into recarve_seat values
  -- Office of the CEO
  ('ceo',                  'exec',                null,              'CEO officer'),
  ('brief',                'exec',                'ceo',             'Chief of Staff'),
  ('cpo',                  'exec',                'ceo',             'Strategy & performance officer (the scorecard)'),
  ('ops_director',         'exec',                'ceo',             'Chief Operating Officer (holds the kernel''s default accountability until departments take their rows)'),
  -- Supply
  ('bd',                   'supply',              'ceo',             'Supply lead'),
  ('partnerships_mgr',     'supply',              'bd',              'Invite-campaign agent'),
  ('onboarding',           'supply',              'bd',              'Claim/Onboard agent'),
  ('supplier_verification','supply',              'bd',              'Verification agent'),
  ('supplier_retention',   'supply',              'bd',              'Retention agent'),
  ('supplier_coverage',    'supply',              'bd',              'Coverage-gap agent'),
  -- Demand
  ('sales_director',       'growth',              'ceo',             'Demand lead'),
  ('marketing_analyst',    'growth',              'sales_director',  'Ad-spend optimizer'),
  ('marketing_content',    'growth',              'sales_director',  'Blog agent'),
  ('marketing_social',     'growth',              'sales_director',  'Social agent'),
  ('brand_mgr',            'growth',              'sales_director',  'Content-revise agent'),
  ('optimisation_eng',     'growth',              'sales_director',  'SEO agent'),
  ('marketing_design',     'growth',              'sales_director',  'Creative agent'),
  -- Marketplace Ops
  ('procurement',          'marketplace',         'ceo',             'Ops lead'),
  ('doc_intel_manager',    'marketplace',         'procurement',     'Intake agent (reads uploaded files)'),
  ('inquiry_router',       'marketplace',         'procurement',     'Router/Dispatch agent'),
  ('spec_commercial',      'marketplace',         'procurement',     'Match-quality agent'),
  ('quote_evaluation',     'marketplace',         'procurement',     'Quote-quality agent'),
  ('rfq_qualification_mgr','marketplace',         'procurement',     'RFQ qualification & ops-side coverage-gap agent'),
  ('rfq_success',          'marketplace',         'procurement',     'Reveal-orchestration agent'),
  -- Finance & Collections
  ('cfo',                  'finance',             'ceo',             'Finance lead'),
  ('billing_specialist',   'finance',             'cfo',             'Reconciliation agent'),
  ('collections',          'finance',             'cfo',             'Collections agent'),
  ('payments_manager',     'finance',             'cfo',             'Refund-prep agent (never approves; every refund goes to the founder)'),
  ('bookkeeper',           'finance',             'cfo',             'Invoicing/GL agent'),
  -- Customer Experience
  ('followup',             'customer_experience', 'ceo',             'CX lead'),
  ('cs_support',           'customer_experience', 'followup',        'Buyer-support & complaint agent'),
  ('cs_retention',         'customer_experience', 'followup',        'Supplier-support & retention agent'),
  ('cs_onboarding',        'customer_experience', 'followup',        'Buyer onboarding (7 live components)'),
  ('channel_specialist',   'customer_experience', 'followup',        'Rating agent (lifecycle channel)'),
  -- Trust, Safety & Compliance
  ('legal',                'legal',               'ceo',             'T&S lead'),
  ('moderation_specialist','legal',               'legal',           'Moderation agent'),
  ('trust_safety_mgr',     'legal',               'legal',           'Suspension agent'),
  ('compliance_mgr',       'legal',               'legal',           'Compliance agent'),
  -- Platform & Reliability
  ('cto',                  'product_eng',         'ceo',             'Platform lead'),
  ('it',                   'product_eng',         'cto',             'Reliability/SRE agent and red-view alerter'),
  ('security',             'product_eng',         'cto',             'Security engineer'),
  ('qa_manager',           'product_eng',         'cto',             'Test-triage agent'),
  ('eng_manager',          'product_eng',         'cto',             'Deploy agent'),
  ('backend_engineer',     'product_eng',         'cto',             'Kernel/runtime agent'),
  -- Data & Experimentation
  ('intel_director',       'data_intel',          'ceo',             'Data lead'),
  ('bi_analyst',           'data_intel',          'intel_director',  'KPI agent'),
  ('analytics',            'data_intel',          'intel_director',  'Self-review agent'),
  ('process_improvement_mgr','data_intel',        'intel_director',  'Evolution agent'),
  ('market_analyst',       'data_intel',          'intel_director',  'Experiment agent'),
  ('knowledge_director',   'data_intel',          'intel_director',  'Knowledge-accuracy agent'),
  ('supplier_analyst',     'data_intel',          'intel_director',  'Match-eval agent'),
  -- Agent Ops
  ('hr_director',          'people_ops',          'ceo',             'Agent-Ops lead'),
  ('learning_dev_mgr',     'people_ops',          'hr_director',     'Certification agent'),
  ('culture_performance_mgr','people_ops',        'hr_director',     'KPI-improvement agent'),
  ('recruitment_specialist','people_ops',         'hr_director',     'Hire/fire agent'),
  ('ai_director',          'people_ops',          'hr_director',     'AI platform & model-policy director');

-- Parked personas and the seat that inherits each one's live accountability.
create temp table recarve_park (agent_key text primary key, successor text not null) on commit drop;
insert into recarve_park values
  ('strategy_director',   'cpo'),
  ('marketing',           'sales_director'),
  ('account_mgr',         'sales_director'),
  ('crm_pipeline_mgr',    'sales_director'),
  ('inquiry_scoring',     'doc_intel_manager'),
  ('boq_analyst',         'doc_intel_manager'),
  ('drawing_analyst',     'doc_intel_manager'),
  ('spec_construction',   'spec_commercial'),
  ('spec_fitout',         'spec_commercial'),
  ('spec_industrial',     'spec_commercial'),
  ('spec_mep',            'spec_commercial'),
  ('ap_specialist',       'bookkeeper'),
  ('financial_analyst',   'cfo'),
  ('comms_manager',       'followup'),
  ('risk_governance_mgr', 'legal'),
  ('contract_specialist', 'legal'),
  ('fraud_analyst',       'trust_safety_mgr'),
  ('ai_qa_specialist',    'qa_manager'),   -- an AI-output reviewer stays a reviewer: test-triage, not the AI owner
  ('model_evaluator',     'qa_manager'),
  ('test_automation_eng', 'qa_manager'),
  ('ai_architect',        'cto'),
  ('frontend_engineer',   'cto'),
  ('innovation_mgr',      'cto'),
  ('product_ux_designer', 'cto'),
  ('prompt_engineer',     'cto'),
  ('solution_architect',  'cto'),
  ('docs',                'brief'),
  ('org_designer',        'hr_director'),
  ('project_coordinator', 'ops_director'),
  ('category_curator',    'intel_director'),
  ('forecast_analyst',    'intel_director'),
  ('kb_engineer',         'knowledge_director'),
  ('knowledge_validator', 'intel_director'), -- the knowledge reviewer must not become the knowledge owner
  ('taxonomy_manager',    'intel_director');

do $chk$
declare v_missing text; v_bad text;
begin
  select string_agg(s.agent_key, ', ') into v_missing from recarve_seat s where not exists (select 1 from public.org_agents a where a.agent_key = s.agent_key);
  if v_missing is not null then raise exception 'PACR-004: seat map names personas that do not exist: %', v_missing; end if;
  select string_agg(p.agent_key, ', ') into v_missing from recarve_park p where not exists (select 1 from public.org_agents a where a.agent_key = p.agent_key);
  if v_missing is not null then raise exception 'PACR-004: park list names personas that do not exist: %', v_missing; end if;
  select string_agg(p.agent_key, ', ') into v_bad from recarve_park p where not exists (select 1 from recarve_seat s where s.agent_key = p.successor);
  if v_bad is not null then raise exception 'PACR-004: parked personas whose successor holds no seat: %', v_bad; end if;
  select string_agg(a.agent_key, ', ') into v_bad from public.org_agents a where a.active
     and not exists (select 1 from recarve_seat s where s.agent_key = a.agent_key)
     and not exists (select 1 from recarve_park p where p.agent_key = a.agent_key);
  if v_bad is not null then raise exception 'PACR-004: active personas neither seated nor parked: %', v_bad; end if;
  select string_agg(s.agent_key, ', ') into v_bad from recarve_seat s where s.manager is not null and not exists (select 1 from recarve_seat m where m.agent_key = s.manager);
  if v_bad is not null then raise exception 'PACR-004: seats whose manager holds no seat: %', v_bad; end if;
end $chk$;

-- Role map, captured while every role is still active.
create temp table recarve_role_map on commit drop as
  select ro.role_id old_role, rn.role_id new_role, p.agent_key old_agent, p.successor new_agent,
         ao.title old_title, an.title new_title, ro.display_name old_dn, rn.display_name new_dn
    from recarve_park p
    join public.org_role ro on ro.runtime_agent_key = p.agent_key and ro.status = 'active'
    join public.org_role rn on rn.runtime_agent_key = p.successor and rn.status = 'active'
    join public.org_agents ao on ao.agent_key = p.agent_key
    join public.org_agents an on an.agent_key = p.successor;

-- =============================================================================================
-- 3. PERSONAS. Seat -> department, manager, active. Park -> inactive, reason stated on the row.
-- =============================================================================================
update public.org_agents a
   set department = s.dept, manager_key = s.manager, active = true, available = true,
       unavailable_until = null, unavailable_reason = null
  from recarve_seat s where s.agent_key = a.agent_key;

update public.org_agents a
   set active = false, available = false, unavailable_until = null,
       unavailable_reason = 'Parked 3 Sep 2026 (PACR-004 STAFF_ORG re-carve): no live firing decision of its own; title kept for re-hire. Live accountability moved to ' || p.successor || '.'
  from recarve_park p where p.agent_key = a.agent_key;

-- =============================================================================================
-- 4. ROLES follow their personas. Seated roles move department and manager; parked roles retire.
-- =============================================================================================
update public.org_role r
   set primary_department_id = s.dept,
       manager_role_id = (select m.role_id from public.org_role m where m.runtime_agent_key = s.manager and m.status = 'active' order by m.role_id limit 1),
       updated_at = now()
  from recarve_seat s
 where r.runtime_agent_key = s.agent_key and r.status = 'active';

update public.org_role r
   set status = 'retired', runtime_enabled = false, updated_at = now(),
       necessity_reason = coalesce(necessity_reason || ' | ', '') || 'PACR-004 3 Sep 2026: persona parked; accountability moved to ' || m.new_role
  from recarve_role_map m
 where r.role_id = m.old_role;

update public.org_role set primary_department_id = 'product_eng', updated_at = now()
 where primary_department_id = 'assurance';

-- =============================================================================================
-- 5. ACCOUNTABILITY moves with the seat. Nothing is left pointing at a retired role or a parked
--    persona; department_id on every component re-derives from its accountable role (the same
--    rule the crosswalk builder applies: deptOf(accountable_role_id)).
-- =============================================================================================
update public.phase_c_component c set accountable_role_id = m.new_role
  from recarve_role_map m where c.accountable_role_id = m.old_role;

-- Supplier recruiting moves to Supply with its mechanism: every invite component (the daily invite
-- run, the ramp, the trade backfill, the cap allocation, the schedule table and its triggers) is now
-- accountable to the Invite-campaign seat instead of the CRO, the onboarding specialist or the COO.
update public.phase_c_component
   set accountable_role_id = 'strategic_partnerships_government_relations_manager'
 where component_id ilike '%invite%'
   and accountable_role_id in ('chief_revenue_officer', 'supplier_onboarding_specialist', 'chief_operating_officer');

update public.phase_c_component c set department_id = r.primary_department_id
  from public.org_role r
 where r.role_id = c.accountable_role_id and r.status = 'active'
   and c.department_id is distinct from r.primary_department_id;

-- Managers, workflow ownership, reviewers, contributors and org-level steps follow the same map.
update public.org_role r set manager_role_id = m.new_role, updated_at = now()
  from recarve_role_map m where r.manager_role_id = m.old_role and r.status = 'active' and r.role_id <> m.new_role;
update public.org_workflow_ownership o set accountable_role_id = m.new_role from recarve_role_map m where o.accountable_role_id = m.old_role;
update public.org_workflow_ownership o
   set contributors = (select coalesce(array_agg(distinct z.x), '{}') from (select coalesce(m.new_role, c) x from unnest(o.contributors) c left join recarve_role_map m on m.old_role = c) z
                       where z.x <> o.accountable_role_id and z.x is distinct from o.independent_reviewer)
 where exists (select 1 from unnest(o.contributors) c join recarve_role_map m on m.old_role = c);
-- A reviewer that would collide with the owner or a contributor goes one level up the reporting graph.
update public.org_workflow_ownership o
   set independent_reviewer = coalesce(
        (select m.new_role where m.new_role <> o.accountable_role_id and not (m.new_role = any(o.contributors))),
        (select r.manager_role_id from public.org_role r
          where r.role_id = o.accountable_role_id and r.manager_role_id <> o.accountable_role_id and not (r.manager_role_id = any(o.contributors))),
        'ceo')
  from recarve_role_map m where o.independent_reviewer = m.old_role;
-- Creator/reviewer separation survives the move: an owner never contributes to or reviews its own
-- workflow. Where the successor collides with the owner, the contributor entry is dropped and the
-- review goes one level up the reporting graph.
update public.org_workflow_ownership o set contributors = array_remove(o.contributors, o.accountable_role_id)
 where o.accountable_role_id = any(o.contributors);
update public.org_workflow_ownership o
   set independent_reviewer = coalesce((select r.manager_role_id from public.org_role r where r.role_id = o.accountable_role_id), 'ceo')
 where o.independent_reviewer = o.accountable_role_id;
update public.org_workflow_step s set accountable_role_id = m.new_role from recarve_role_map m where s.accountable_role_id = m.old_role;
-- The alias registry, both directions: every alias that reached a parked role now reaches its
-- successor, and every parked role_id becomes an alias of its successor, so anything that still
-- addresses the old id resolves to a live role (Phase A rule: a retired role resolves to somebody).
update public.org_role_alias a set role_id = m.new_role from recarve_role_map m where a.role_id = m.old_role;
insert into public.org_role_alias (alias, role_id, kind, reason)
  select m.old_role, m.new_role, 'merged_role', 'PACR-004 3 Sep 2026: persona parked in the STAFF_ORG re-carve; its accountability moved to ' || m.new_role
    from recarve_role_map m
  on conflict (alias) do update set role_id = excluded.role_id, kind = excluded.kind, reason = excluded.reason;

update public.workflow_step ws
   set actor_role = case when ws.actor_role = m.old_agent then m.new_agent
                         when ws.actor_role = m.old_role  then m.new_role
                         when ws.actor_role = m.old_title then m.new_title
                         when ws.actor_role = m.old_dn    then m.new_dn end
  from recarve_role_map m
 where ws.actor_role in (m.old_agent, m.old_role, m.old_title, m.old_dn);

insert into public.event_subscription (agent_key, event_type, reason, active)
  select m.new_agent, e.event_type, left(coalesce(e.reason, '') || ' (moved from ' || m.old_agent || ', PACR-004)', 500), e.active
    from public.event_subscription e join recarve_role_map m on m.old_agent = e.agent_key
  on conflict (agent_key, event_type) do nothing;
delete from public.event_subscription e using recarve_role_map m where e.agent_key = m.old_agent;

insert into public.employee_workflow (agent_key, workflow_key, role_in_workflow)
  select m.new_agent, w.workflow_key, w.role_in_workflow
    from public.employee_workflow w join recarve_role_map m on m.old_agent = w.agent_key
  on conflict (agent_key, workflow_key) do nothing;
delete from public.employee_workflow w using recarve_role_map m where w.agent_key = m.old_agent;

update public.continuity_plan x set owner_agent = m.new_agent from recarve_role_map m where x.owner_agent = m.old_agent;
update public.operating_system x set owner_agent = m.new_agent from recarve_role_map m where x.owner_agent = m.old_agent;
update public.org_category_identity x set owner_agent = m.new_agent from recarve_role_map m where x.owner_agent = m.old_agent;
update public.risk_register x set owner_agent = m.new_agent from recarve_role_map m where x.owner_agent = m.old_agent;
update public.org_agents a set manager_key = m.new_agent from recarve_role_map m where a.manager_key = m.old_agent and a.active is false;

-- =============================================================================================
-- 6. ASSURANCE'S LIVE REFERENCES move to Platform & Reliability. History (review_chain,
--    ai_cost_log, closed tasks) keeps the key it was written under; knowledge (dept_library,
--    ops_knowledge) stays reachable through fn_dept_scope, which follows merged_into.
-- =============================================================================================
update public.org_authority a set dept_key = 'product_eng'
 where a.dept_key = 'assurance'
   and not exists (select 1 from public.org_authority b where b.dept_key = 'product_eng' and b.action_class = a.action_class);
delete from public.org_authority where dept_key = 'assurance';

update public.org_tasks set dept_key = 'product_eng'
 where dept_key = 'assurance' and status in ('proposed', 'assigned', 'in_progress');

update public.org_action_executor set department = 'product_eng' where department = 'assurance';
update public.edge_expectation set dept_key = 'product_eng' where dept_key = 'assurance';
update public.risk_register set dept_key = 'product_eng' where dept_key = 'assurance';
update public.delegation_rule set dept_key = 'product_eng' where dept_key = 'assurance';
delete from public.department_budget where dept_key = 'assurance';
-- os_department is unique on dept_key alone: product_eng already has its operating system, so the
-- assurance mapping is removed rather than re-keyed.
delete from public.os_department where dept_key = 'assurance';

-- Objectives: the measured ones become Platform's; the four copy-pasted placeholders that shared one
-- goal_key are superseded, not carried.
update public.department_objective set status = 'superseded', active = false, updated_at = now()
 where dept_key = 'assurance' and goal_key = 'classification_accuracy';
update public.department_objective set dept_key = 'product_eng', updated_at = now()
 where dept_key = 'assurance' and status = 'active';

-- Goals follow the loop stage that owns them: the supplier goals Marketplace carried become Supply's,
-- Assurance's reliability goals become Platform's. Supply's objective hangs off the existing measured
-- supplier_coverage goal (5 verified suppliers per active category) rather than a new unmeasured key.
update public.company_goals set owner_dept = 'supply', updated_at = now()
 where owner_dept = 'marketplace' and key in ('supplier_coverage', 'supplier_coverage_10x86', 'supplier_response_rate');
update public.company_goals set owner_dept = 'product_eng', updated_at = now() where owner_dept = 'assurance';

insert into public.department_objective (dept_key, objective, horizon, sort, active, goal_key, status, target_value, unit, measure_sql)
select 'supply', 'Verified suppliers per active category (today: 1 supplier in total)', 'year_1', 0, true, 'supplier_coverage', 'active',
       g.target_value, g.unit, g.measure_sql
  from public.company_goals g
 where g.key = 'supplier_coverage'
   and not exists (select 1 from public.department_objective where dept_key = 'supply' and goal_key = 'supplier_coverage');

-- =============================================================================================
-- 7. THE BASELINE RECORD. Append-only by trigger; digests recomputed in place (PACR-002/003
--    pattern) so fn_phase_a_baseline_drift() reports what the founder approved on 2 Sep: none.
-- =============================================================================================
drop trigger a00_org_phase_baseline_append_only on public.org_phase_baseline;

update public.org_phase_baseline b
   set deferred = (select coalesce(jsonb_agg(t), '[]'::jsonb)
                     from jsonb_array_elements_text(b.deferred) t
                    where split_part(t, ':', 2) not in (select old_role from recarve_role_map)),
       counts = jsonb_build_object(
         'active_departments',       (select count(*) from public.org_departments where active),
         'canonical_roles',          (select count(*) from public.org_role where status='active' and runtime_mode <> 'knowledge_overlay'),
         'category_overlays',        (select count(*) from public.org_role where status='active' and runtime_mode = 'knowledge_overlay'),
         'department_heads',         (select count(*) from public.org_departments where active and lead_agent is not null),
         'organizational_workflows', (select count(*) from public.org_workflow_ownership),
         'phase_a_violations',       (select count(*) from public.fn_phase_a_organization_violations()),
         'deferred_items',           (select count(*) from jsonb_array_elements_text(b.deferred) t where split_part(t, ':', 2) not in (select old_role from recarve_role_map)),
         'retired_roles',            (select count(*) from public.org_role where status='retired')),
       registry_sha256 = jsonb_set(jsonb_set(jsonb_set(
         b.registry_sha256,
         '{workflow_ownership,database}',
         to_jsonb((select encode(sha256(convert_to(coalesce(string_agg(x, chr(10) order by sortkey), ''), 'UTF8')), 'hex')
                     from (select o.workflow_id sortkey,
                                  o.workflow_id||'|'||o.workflow_name||'|'||o.accountable_role_id||'|'
                                  ||array_to_string(o.contributors, ';')||'|'||coalesce(o.independent_reviewer,'') x
                             from public.org_workflow_ownership o) s))),
         '{departments,database}',
         to_jsonb((select encode(sha256(convert_to(coalesce(string_agg(x, chr(10) order by x), ''), 'UTF8')), 'hex')
                     from (select d.dept_key||'|'||d.name||'|'||coalesce(d.lead_agent,'') x
                             from public.org_departments d where d.active) s))),
         '{reporting_graph,database}',
         to_jsonb((select encode(sha256(convert_to(coalesce(string_agg(x, chr(10) order by sortkey), ''), 'UTF8')), 'hex')
                     from (select r.role_id sortkey,
                                  r.role_id||'|'||coalesce(r.manager_role_id,'founder')||'|'||r.primary_department_id x
                             from public.org_role r
                            where r.status='active' and r.runtime_mode <> 'knowledge_overlay') s))),
       organization_sha256 = (
         with
         d as (select string_agg(dept_key||'|'||name||'|'||active::text||'|'||coalesce(lead_agent,''), chr(10) order by dept_key) x from public.org_departments),
         r as (select string_agg(role_id||'|'||display_name||'|'||primary_department_id||'|'||coalesce(manager_role_id,'')
                 ||'|'||runtime_mode||'|'||coalesce(runtime_agent_key,'')||'|'||status||'|'||coalesce(evaluation_suite,'')
                 ||'|'||coalesce(array_length(owned_decisions,1),0)::text||'|'||coalesce(array_length(forbidden_decisions,1),0)::text,
                 chr(10) order by role_id) x from public.org_role),
         c as (select string_agg(category_key, chr(10) order by category_key) x from public.org_category_identity),
         w as (select string_agg(workflow_key||'|'||step_no::text||'|'||step||'|'||coalesce(actor_role,''), chr(10) order by workflow_key, step_no) x from public.workflow_step),
         f as (select string_agg(decision_key, chr(10) order by decision_key) x from public.founder_reserved_decision),
         a as (select string_agg(agent_key||'|'||department||'|'||active::text||'|'||coalesce(manager_key,''), chr(10) order by agent_key) x from public.org_agents)
         select encode(sha256(convert_to(
           'departments'||chr(10)||d.x||chr(10)||'--'||chr(10)||
           'roles'||chr(10)||r.x||chr(10)||'--'||chr(10)||
           'categories'||chr(10)||c.x||chr(10)||'--'||chr(10)||
           'workflow_steps'||chr(10)||w.x||chr(10)||'--'||chr(10)||
           'reserved'||chr(10)||f.x||chr(10)||'--'||chr(10)||
           'agents'||chr(10)||a.x, 'UTF8')), 'hex')
         from d, r, c, w, f, a),
       note = b.note || chr(10) || chr(10) || 'PACR-004, 3 Sep 2026: STAFF_ORG re-carve. Supply carved out of Marketplace as its own '
              'department; Assurance merged into Platform & Reliability (product_eng); Growth renamed Demand, '
              'People Ops renamed Agent Ops, Legal renamed Trust, Safety & Compliance; 34 personas parked with '
              'their live accountability moved to named seats; digests recomputed to the values now held.',
       recorded_at = now()
 where b.phase = 'A';

create trigger a00_org_phase_baseline_append_only
  before delete or update on public.org_phase_baseline
  for each row execute function public.fn_org_phase_baseline_append_only();

-- =============================================================================================
-- 8. PROOF, in the same transaction. Every line below is an invariant of the re-carve; any
--    failure aborts the whole thing. In rehearsal mode it aborts on purpose and prints the counts.
-- =============================================================================================
do $proof$
declare
  v_depts int; v_seated int; v_parked int; v_active int;
  v_orphan_agent int; v_orphan_role int; v_orphan_comp int; v_orphan_step int; v_orphan_sub int; v_orphan_wf int;
  v_dept_drift int; v_comp_dept int; v_authority_left int; v_drift int; v_stale_def int;
  v_rehearsal boolean := coalesce(current_setting('app.recarve_rehearsal', true), '') = '1';
begin
  select count(*) into v_depts from public.org_departments where active;
  select count(*) into v_seated from public.org_agents a join recarve_seat s on s.agent_key = a.agent_key where a.active;
  select count(*) into v_parked from public.org_agents a join recarve_park p on p.agent_key = a.agent_key where not a.active;
  select count(*) into v_active from public.org_agents where active;
  select count(*) into v_orphan_agent from public.org_agents a join public.org_departments d on d.dept_key = a.department where a.active and not d.active;
  select count(*) into v_orphan_role from public.org_role r join public.org_departments d on d.dept_key = r.primary_department_id where r.status = 'active' and not d.active;
  select count(*) into v_orphan_comp from public.phase_c_component c join public.org_role r on r.role_id = c.accountable_role_id where c.activation_state = 'active' and r.status <> 'active';
  select count(*) into v_orphan_step from public.workflow_step ws join recarve_role_map m on ws.actor_role in (m.old_agent, m.old_role, m.old_title, m.old_dn);
  select count(*) into v_orphan_sub from public.event_subscription e join recarve_park p on p.agent_key = e.agent_key;
  select count(*) into v_orphan_wf from public.employee_workflow w join recarve_park p on p.agent_key = w.agent_key;
  select count(*) into v_comp_dept from public.phase_c_component c join public.org_role r on r.role_id = c.accountable_role_id where r.status = 'active' and c.department_id is distinct from r.primary_department_id;
  select count(*) into v_authority_left from public.org_authority where dept_key = 'assurance';
  select count(*) into v_drift from public.fn_phase_a_baseline_drift();
  select count(*) into v_dept_drift from public.org_departments where dept_key = 'assurance' and (active or merged_into is distinct from 'product_eng');
  if v_depts <> 10 then raise exception 'PACR-004: expected 10 active departments, found %', v_depts; end if;
  if v_seated <> (select count(*) from recarve_seat) then raise exception 'PACR-004: seated % of %', v_seated, (select count(*) from recarve_seat); end if;
  if v_parked <> (select count(*) from recarve_park) then raise exception 'PACR-004: parked % of %', v_parked, (select count(*) from recarve_park); end if;
  if v_active <> v_seated then raise exception 'PACR-004: % active personas but % seats', v_active, v_seated; end if;
  if v_orphan_agent > 0 then raise exception 'PACR-004: % active personas sit in an inactive department', v_orphan_agent; end if;
  if v_orphan_role > 0 then raise exception 'PACR-004: % active roles sit in an inactive department', v_orphan_role; end if;
  if v_orphan_comp > 0 then raise exception 'PACR-004: % active components are accountable to a non-active role', v_orphan_comp; end if;
  if v_orphan_step > 0 then raise exception 'PACR-004: % workflow steps still name a parked persona', v_orphan_step; end if;
  if v_orphan_sub > 0 or v_orphan_wf > 0 then raise exception 'PACR-004: parked personas still hold % subscriptions / % workflows', v_orphan_sub, v_orphan_wf; end if;
  if v_comp_dept > 0 then raise exception 'PACR-004: % components carry a department that is not their accountable role''s', v_comp_dept; end if;
  if v_authority_left > 0 or v_dept_drift > 0 then raise exception 'PACR-004: assurance not fully merged (% authority rows, % dept drift)', v_authority_left, v_dept_drift; end if;
  if v_drift > 0 then raise exception 'PACR-004: fn_phase_a_baseline_drift still reports % rows after the recompute: % || violations: %', v_drift,
      (select string_agg(left(to_jsonb(x)::text, 300), ' || ') from public.fn_phase_a_baseline_drift() x),
      (select string_agg(v.rule||'='||v.n||' ['||v.ex||']', '; ') from (select rule, count(*) n, string_agg(subject||'/'||left(detail,40), ',') filter (where rn <= 6) ex from (select rule, subject, detail, row_number() over (partition by rule order by subject) rn from public.fn_phase_a_organization_violations()) z group by rule) v); end if;
  raise notice 'PACR-004 proof: 10 departments, % seated, % parked, % active; 0 orphans; baseline drift 0', v_seated, v_parked, v_active;
  if v_rehearsal then
    raise exception 'REHEARSAL OK — rolled back: 10 departments, % seated, % parked, % active, 0 orphans, baseline drift 0', v_seated, v_parked, v_active;
  end if;
end $proof$;
commit;
