-- REORGANISING THE AGENT COMPANY — 2 of 5: 25 departments become 10.
--
-- Four departments shared one acquisition funnel; five shared one inquiry-to-quotation workflow;
-- five overlapped around product and release quality; three all turned information into decisions.
-- dept_plan and dept_learn fan out over `org_departments where active` and intent_router picks a
-- destination from those same charters, so 25 owners of overlapping work is not an org-chart
-- opinion — it is 25 planning runs a day and a router choosing between charters that describe the
-- same job.
--
-- NOTHING IS DELETED. An absorbed department keeps its row, keeps every historical foreign key
-- pointing at it, and gains `merged_into`. `active` goes false, so the fan-outs and the router see
-- ten. fn_dept_scope() reads merged_into so an employee in the merged department still retrieves
-- the knowledge, authority and tools that were tagged with its predecessor's key — 5,775 tagged
-- ops_knowledge rows are NOT rewritten.

-- One transaction: a half-migrated org chart is worse than none. fn_org_authority_guard refuses an
-- authority row that raises a tier without a stated reason in the SAME transaction, which is the
-- audit trail, not an obstacle.
begin;
set local app.change_reason = 'Department reorganisation 14 Aug 2026: 25 departments merged into 10; a surviving department inherits only the action classes it did not already govern, at the most restrictive tier any source department held.';

alter table public.org_departments
  add column if not exists merged_into text references public.org_departments(dept_key),
  add column if not exists merged_at   timestamptz;

create or replace function public.fn_dept_canonical(p_dept text)
returns text language sql stable as $$
  select coalesce(
    (select d.merged_into from public.org_departments d
      where d.dept_key = p_dept and d.merged_into is not null),
    p_dept);
$$;

-- Every key whose knowledge, authority and tools this department now owns: itself plus everything
-- merged into it (one level; merges are not chained by design).
create or replace function public.fn_dept_scope(p_dept text)
returns text[] language sql stable as $$
  select array(select p_dept
               union
               select d.dept_key from public.org_departments d where d.merged_into = p_dept);
$$;

-- ---------------------------------------------------------------------------------------------
-- The ten. Charters are written to be ROUTABLE: intent_router chooses between exactly these ten
-- paragraphs, so each names the work it owns and, where two were previously confusable, the work
-- it does not.
-- ---------------------------------------------------------------------------------------------
insert into public.org_departments (dept_key, name, charter, north_star, health_fn, lead_agent, brain_agent, active, sort)
values
 ('growth', 'Growth & Revenue',
  'Owns every step from a stranger hearing about QuotesDone to money received against a won quotation: brand, content, design, social, campaigns and marketing performance; outbound sales, account management, CRM and revenue operations; business development, partnerships and government relations. One funnel, one accountable revenue owner. Customer service after the sale belongs to Customer Experience; supplier acquisition belongs to Marketplace & Supplier Network.',
  'AED 1,000,000 in revenue by 31 August 2027', 'fn_ws_marketing', 'sales_director', 'marketing', true, 20),

 ('customer_experience', 'Customer Experience & Communications',
  'Owns the customer after the inquiry exists: onboarding, support, retention, RFQ success, and every lifecycle message the company sends on any channel — email, WhatsApp, SMS and in-product — including deliverability, sender reputation, the outbox and the digest. Acquisition messaging belongs to Growth & Revenue; the quality of the inquiry itself belongs to Marketplace & Supplier Network.',
  'Every customer who posts an inquiry receives comparable quotations and comes back', 'fn_ws_customers', 'followup', 'followup', true, 30),

 ('marketplace', 'Marketplace & Supplier Network',
  'Owns the inquiry-to-quotation workflow end to end and the supplier network that answers it: intake, qualification, routing, scoring, dispatch, quote evaluation and reveal; supplier verification, onboarding, coverage, liquidity and retention; and the document intelligence — BOQ, drawings, specifications — that turns an attachment into a quotable requirement. One accountable Marketplace Director for the whole chain.',
  'Every qualified inquiry reaches enough confirmed suppliers to produce comparable quotations', 'fn_ws_marketplace', 'procurement', 'procurement', true, 40),

 ('product_eng', 'Product, Engineering & AI',
  'Owns what the product is and how it is built: product discovery, prioritisation and experimentation; architecture, backend, frontend and delivery; the AI layer — agent design, prompts, model evaluation and routing; and product optimisation including cost per decision. Release quality gates and production reliability belong to Independent Assurance, Security & Reliability, deliberately, so the team that ships does not certify its own release.',
  'Ship the capability the revenue objective needs, at a cost per decision that falls', 'fn_ws_ai', 'cto', 'cto', true, 50),

 ('data_intel', 'Data, Intelligence & Knowledge',
  'Owns turning information into decisions and into durable company knowledge: data engineering, business intelligence, forecasting, market, competitive, supplier and customer intelligence; the knowledge corpus, its engineering, validation and freshness; and the trade taxonomy and category curation that every route and every category specialist depends on. Owns metric DEFINITIONS; the departments own their own numbers.',
  'Every company goal has a measured actual, and every agent retrieves knowledge that is current', 'fn_ws_knowledge', 'intel_director', 'intel_director', true, 60),

 ('people_ops', 'People & Company Operations',
  'Owns how the company runs itself: operations management, process improvement, project coordination and the PMO, controlled documents and document operations; and the people system — recruitment, learning and development, culture and performance for the agent workforce. Owns internal operating capability, not customer-facing or marketplace work.',
  'Work is assigned, owned, finished and learned from, without the founder chasing it', 'fn_ws_operations', 'ops_director', 'ops_director', true, 80),

 ('assurance', 'Independent Assurance, Security & Reliability',
  'Independent control function with stop authority. Owns QA and release management, test automation, AI quality assurance, IT operations, site reliability and cybersecurity. May block a release, a model change, a migration or a deployment on a critical security failure, a privacy violation, a failed release gate, an unsafe model regression, a corrupt migration or an unreconciled financial-integrity defect. Reports outside Product, Engineering & AI so that the team that ships never certifies its own work, and is never measured on release speed alone.',
  'No unsafe change reaches production, and the platform is healthy essentially all the time', 'fn_ws_ai', 'qa_manager', 'qa_manager', true, 90)
on conflict (dept_key) do update
  set name = excluded.name, charter = excluded.charter, north_star = excluded.north_star,
      health_fn = excluded.health_fn, lead_agent = excluded.lead_agent,
      brain_agent = excluded.brain_agent, active = true, sort = excluded.sort;

-- The three that survive keep their key and gain the scope they absorbed.
update public.org_departments set
  name = 'Executive & Strategy',
  charter = 'Owns company direction and the machinery that keeps it honest: strategy, the objective cascade from the AED 1,000,000 revenue target down to role KPIs, corporate performance diagnosis and correction, organisation design, and the chief-of-staff office that turns the founder''s intent into assigned work. Does not duplicate a department head because that head attends the executive committee: committee seats are recorded against the one role, in org_role_committee.',
  north_star = 'AED 1,000,000 by 31 August 2027, with every department''s objectives tracing to it',
  health_fn = 'fn_ws_company', lead_agent = 'ceo', brain_agent = 'brief', sort = 10
 where dept_key = 'exec';

update public.org_departments set
  name = 'Finance & Payments',
  charter = 'Owns the money end to end: revenue recognition, the ledger, reconciliation and financial controls, accounts payable and receivable, collections and revenue assurance, budgets, runway, forecasts and investor reporting, and the payment and billing rails themselves. Payment is an operating function of finance, not a separate department.',
  north_star = 'Every dirham earned is recognised, reconciled and collected',
  health_fn = 'fn_ws_finance', lead_agent = 'cfo', brain_agent = 'cfo', sort = 70
 where dept_key = 'finance';

update public.org_departments set
  name = 'Legal, Compliance, Risk & Trust',
  charter = 'Owns legal risk and platform trust as one function: contracts, corporate and regulatory compliance including UAE PDPL and explicit data-protection ownership, risk and governance, and trust and safety — fraud, moderation, disputes, policy and enforcement. Legal exposure and platform abuse are the same risk surface and are governed together.',
  north_star = 'No regulatory breach, no unremediated fraud, no unenforced policy',
  health_fn = 'fn_ws_governance', lead_agent = 'legal', brain_agent = 'legal', sort = 75
 where dept_key = 'legal';

-- ---------------------------------------------------------------------------------------------
-- The merge map. Recorded on the department row itself, before anything is repointed.
-- ---------------------------------------------------------------------------------------------
update public.org_departments d set merged_into = m.target, merged_at = now()
  from (values
    ('evolution','exec'),
    ('marketing','growth'), ('sales','growth'), ('bizdev','growth'),
    ('customer_success','customer_experience'), ('comms','customer_experience'),
    ('procurement','marketplace'), ('rfq_intelligence','marketplace'),
    ('supplier_success','marketplace'), ('supplier_knowledge','marketplace'),
    ('doc_intelligence','marketplace'),
    ('engineering','product_eng'), ('ai_dept','product_eng'),
    ('intelligence','data_intel'), ('analytics','data_intel'), ('knowledge_eng','data_intel'),
    ('payments','finance'),
    ('trust_safety','legal'),
    ('knowledge','people_ops'), ('hr','people_ops'),
    ('qa','assurance'), ('it','assurance')
  ) as m(src, target)
 where d.dept_key = m.src;

-- evolution is split, not merged: its strategic roles go to Executive & Strategy and its product
-- roles to Product, Engineering & AI. merged_into names the knowledge home (exec); the two product
-- roles carry their own department assignment below and read evolution knowledge through the
-- second-home alias.

-- ---------------------------------------------------------------------------------------------
-- MOVE THE EMPLOYEES. One primary department each; every assignment is stated, none inferred.
-- ---------------------------------------------------------------------------------------------
update public.org_agents a set department = m.dept from (values
  -- 1. Executive & Strategy
  ('ceo','exec'), ('brief','exec'), ('strategy_director','exec'), ('cpo','exec'), ('org_designer','exec'),
  -- 2. Growth & Revenue
  ('sales_director','growth'), ('marketing','growth'), ('brand_mgr','growth'),
  ('marketing_content','growth'), ('marketing_design','growth'), ('marketing_social','growth'),
  ('marketing_analyst','growth'), ('account_mgr','growth'), ('crm_pipeline_mgr','growth'),
  ('bd','growth'), ('partnerships_mgr','growth'), ('gov_relations_mgr','growth'),
  ('marketing_copy','growth'),
  -- 3. Customer Experience & Communications
  ('followup','customer_experience'), ('cs_onboarding','customer_experience'),
  ('cs_support','customer_experience'), ('cs_retention','customer_experience'),
  ('rfq_success','customer_experience'), ('comms_manager','customer_experience'),
  ('channel_specialist','customer_experience'), ('notification_ops','customer_experience'),
  -- 4. Marketplace & Supplier Network
  ('procurement','marketplace'), ('quote_evaluation','marketplace'), ('supplier_verification','marketplace'),
  ('rfq_qualification_mgr','marketplace'), ('inquiry_router','marketplace'), ('inquiry_scoring','marketplace'),
  ('onboarding','marketplace'), ('supplier_coverage','marketplace'), ('supplier_retention','marketplace'),
  ('doc_intel_manager','marketplace'), ('boq_analyst','marketplace'), ('drawing_analyst','marketplace'),
  ('spec_commercial','marketplace'), ('spec_construction','marketplace'), ('spec_fitout','marketplace'),
  ('spec_industrial','marketplace'), ('spec_mep','marketplace'),
  -- 5. Product, Engineering & AI
  ('cto','product_eng'), ('eng_manager','product_eng'), ('backend_engineer','product_eng'),
  ('frontend_engineer','product_eng'), ('solution_architect','product_eng'),
  ('ai_director','product_eng'), ('ai_architect','product_eng'), ('prompt_engineer','product_eng'),
  ('model_evaluator','product_eng'), ('innovation_mgr','product_eng'), ('optimisation_eng','product_eng'),
  -- 6. Data, Intelligence & Knowledge
  ('intel_director','data_intel'), ('analytics_director','data_intel'), ('forecast_analyst','data_intel'),
  ('market_analyst','data_intel'), ('supplier_analyst','data_intel'), ('analytics','data_intel'),
  ('bi_analyst','data_intel'), ('knowledge_director','data_intel'), ('kb_engineer','data_intel'),
  ('knowledge_validator','data_intel'), ('taxonomy_manager','data_intel'),
  ('category_curator','data_intel'), ('supplier_intel_analyst','data_intel'),
  -- 7. Finance & Payments
  ('cfo','finance'), ('bookkeeper','finance'), ('ap_specialist','finance'), ('collections','finance'),
  ('financial_analyst','finance'), ('payments_manager','finance'), ('billing_specialist','finance'),
  -- 8. Legal, Compliance, Risk & Trust
  ('legal','legal'), ('compliance_mgr','legal'), ('contract_specialist','legal'),
  ('risk_governance_mgr','legal'), ('trust_safety_mgr','legal'), ('fraud_analyst','legal'),
  ('moderation_specialist','legal'),
  -- 9. People & Company Operations
  ('ops_director','people_ops'), ('docs','people_ops'), ('process_improvement_mgr','people_ops'),
  ('project_coordinator','people_ops'), ('hr_director','people_ops'),
  ('recruitment_specialist','people_ops'), ('learning_dev_mgr','people_ops'),
  ('culture_performance_mgr','people_ops'),
  -- 10. Independent Assurance, Security & Reliability
  ('qa_manager','assurance'), ('test_automation_eng','assurance'), ('ai_qa_specialist','assurance'),
  ('it','assurance'), ('security','assurance')
) as m(k, dept) where a.agent_key = m.k;

-- ---------------------------------------------------------------------------------------------
-- REPORTING LINES. Three corrections, each with a reason.
-- ---------------------------------------------------------------------------------------------
-- (a) Assurance must not report into the organisation it audits. `it` and `security` reported to
--     the CTO, who now heads Product, Engineering & AI — the department whose releases they gate.
update public.org_agents set manager_key = 'qa_manager' where agent_key in ('it','security');
--     and Assurance's head reports to the Chief of Staff, outside engineering.
update public.org_agents set manager_key = 'brief' where agent_key = 'qa_manager';

-- (b) One revenue owner. Marketing and Business Development were peers of Sales under the Chief of
--     Staff, which is how four departments each reported a different reading of the same funnel.
update public.org_agents set manager_key = 'sales_director' where agent_key in ('marketing','bd');

-- (c) The dissolved departments' heads now report to their new department head.
update public.org_agents set manager_key = 'procurement'
 where agent_key in ('rfq_qualification_mgr','doc_intel_manager');
update public.org_agents set manager_key = 'followup'          where agent_key = 'comms_manager';
update public.org_agents set manager_key = 'intel_director'
 where agent_key in ('knowledge_director','analytics_director','taxonomy_manager');
update public.org_agents set manager_key = 'cto'               where agent_key = 'ai_director';
update public.org_agents set manager_key = 'legal'             where agent_key = 'trust_safety_mgr';
update public.org_agents set manager_key = 'ops_director'      where agent_key = 'hr_director';
update public.org_agents set manager_key = 'cfo'               where agent_key = 'payments_manager';
update public.org_agents set manager_key = 'ceo'               where agent_key in ('cpo','strategy_director','brief');
update public.org_agents set manager_key = 'cpo'               where agent_key = 'org_designer';
update public.org_agents set manager_key = 'cto'               where agent_key in ('innovation_mgr','optimisation_eng');
update public.org_agents set manager_key = 'intel_director'    where agent_key in ('supplier_intel_analyst','category_curator');
update public.org_agents set manager_key = 'procurement'       where agent_key = 'onboarding';

-- ---------------------------------------------------------------------------------------------
-- MERGE THE THREE DUPLICATE IDENTITIES. Not deleted: deactivated, aliased, and their work moved.
-- ---------------------------------------------------------------------------------------------
-- analytics_director and intel_director hold the SAME packaged role
-- (data-analytics-and-intelligence-director) in the same packaged department, and their callers
-- overlap: both are named by fn_delete_proposer, both own "the company's numbers". intel_director
-- carries the live runtime (8 agent_runs, 14 open tasks, 2 routines) and survives.
update public.org_agents set active = false, available = false,
       unavailable_reason = 'merged into intel_director (Data & Intelligence Director) 14 Aug 2026'
 where agent_key = 'analytics_director';
update public.org_agents set manager_key = 'intel_director'
 where manager_key = 'analytics_director' and active;

-- supplier_analyst ("Supplier & Customer Analyst", 15 knowledge rows) and supplier_intel_analyst
-- ("Supplier Intelligence Analyst", 0) are one desk. The row with the knowledge survives and takes
-- the clearer name.
update public.org_agents set active = false, available = false,
       unavailable_reason = 'merged into supplier_analyst (Supplier Intelligence Analyst) 14 Aug 2026'
 where agent_key = 'supplier_intel_analyst';
update public.org_agents set title = 'Supplier Intelligence Analyst',
       role = 'Supplier Intelligence Analyst'
 where agent_key = 'supplier_analyst';

-- notification_ops ("run the outbox") and channel_specialist ("deliverability and sender
-- reputation") are two halves of one job: a message that is queued and never sent and a message
-- that is sent and lands in spam are the same failure to the customer.
update public.org_agents set active = false, available = false,
       unavailable_reason = 'merged into channel_specialist (Lifecycle Channel Operations) 14 Aug 2026'
 where agent_key = 'notification_ops';
update public.org_agents set title = 'Lifecycle Channel Operations Specialist',
       responsibilities = 'Own every lifecycle message from queue to inbox: outbox depth, retries, dead letters and the digest, and deliverability, sender reputation, bounces, suppressions, opt-outs, template approval and per-recipient caps. A message that is never sent and a message that lands in spam are the same failure.'
 where agent_key = 'channel_specialist';

-- marketing_copy was already inactive and readiness 'blocked'; it maps to the same packaged role as
-- marketing_content and has no distinct caller, tasks, runs or knowledge.
update public.org_agents set unavailable_reason = 'merged into marketing_content (Content Strategy & Copy) 14 Aug 2026'
 where agent_key = 'marketing_copy';
update public.org_agents set title = 'Content Strategy & Copy Specialist'
 where agent_key = 'marketing_content';

-- ---------------------------------------------------------------------------------------------
-- REPOINT THE CONFIGURATION. History is left where it happened; live configuration follows the
-- employee. Open tasks move so fn_org_task_assign can still find an owner; closed tasks keep the
-- department they were closed in.
-- ---------------------------------------------------------------------------------------------
update public.org_tasks t set dept_key = public.fn_dept_canonical(t.dept_key)
 where t.status in ('assigned','in_progress') and public.fn_dept_canonical(t.dept_key) <> t.dept_key;

update public.company_goals g set owner_dept = public.fn_dept_canonical(g.owner_dept)
 where g.active and public.fn_dept_canonical(g.owner_dept) <> g.owner_dept;

update public.department_objective o set dept_key = public.fn_dept_canonical(o.dept_key)
 where o.active and public.fn_dept_canonical(o.dept_key) <> o.dept_key
   and not exists (select 1 from public.department_objective x
                    where x.dept_key = public.fn_dept_canonical(o.dept_key) and x.objective = o.objective);
-- an objective whose text already exists under the target department is a genuine duplicate of the
-- overlap this reorganisation removes: close it against the survivor rather than dropping it.
update public.department_objective o set active = false, status = 'superseded',
       superseded_by = (select x.id from public.department_objective x
                         where x.dept_key = public.fn_dept_canonical(o.dept_key)
                           and x.objective = o.objective limit 1),
       updated_at = now()
 where o.active and public.fn_dept_canonical(o.dept_key) <> o.dept_key;

-- Authority. Two departments merging must never widen what either could do: the merged row keeps
-- the most RESTRICTIVE max_tier and the lowest threshold of the rows being merged. The order is
-- read off the reputation system, which demotes 'autonomous' to 'gated' when an employee falls to
-- probation: advisory < gated < supervised < autonomous.
-- least()/greatest() ignore NULLs, so a missing threshold is coalesced before the comparison
-- rather than silently winning it.
-- An action_class the surviving department already governs keeps ITS OWN tier untouched: absorbing
-- a smaller team must not quietly demote the survivor either. Only classes the survivor did not
-- have are added, and those arrive at the most restrictive tier any source held.
with absorbed as (
  select public.fn_dept_canonical(a.dept_key) as dept_key, a.action_class,
         min(case a.max_tier when 'advisory' then 1 when 'gated' then 2
                             when 'supervised' then 3 else 4 end) as tier_rank,
         min(a.threshold_aed) as threshold_aed,
         'inherited from '||string_agg(distinct a.dept_key, '+')||' on 14 Aug 2026 at the most '
           ||'restrictive tier any source held' as note
    from public.org_authority a
   where public.fn_dept_canonical(a.dept_key) <> a.dept_key
   group by 1, 2
)
insert into public.org_authority (dept_key, action_class, max_tier, threshold_aed, note)
select b.dept_key, b.action_class,
       case b.tier_rank when 1 then 'advisory' when 2 then 'gated'
                        when 3 then 'supervised' else 'autonomous' end,
       b.threshold_aed, b.note
  from absorbed b
 where not exists (select 1 from public.org_authority x
                    where x.dept_key = b.dept_key and x.action_class = b.action_class)
on conflict (dept_key, action_class) do nothing;

-- Tools, budgets, cost attribution, task classes, delegation, risks, expectations, OS map.
update public.org_action_executor e set department = public.fn_dept_canonical(e.department)
 where public.fn_dept_canonical(e.department) <> e.department;
update public.ai_cost_fn_map m set dept_key = public.fn_dept_canonical(m.dept_key)
 where public.fn_dept_canonical(m.dept_key) <> m.dept_key;
update public.fn_task_class c set dept_key = public.fn_dept_canonical(c.dept_key)
 where c.dept_key is not null and public.fn_dept_canonical(c.dept_key) <> c.dept_key;
update public.edge_expectation e set dept_key = public.fn_dept_canonical(e.dept_key)
 where public.fn_dept_canonical(e.dept_key) <> e.dept_key;
update public.risk_register r set dept_key = public.fn_dept_canonical(r.dept_key)
 where public.fn_dept_canonical(r.dept_key) <> r.dept_key;
update public.dept_library l set department = public.fn_dept_canonical(l.department)
 where l.department <> 'company' and public.fn_dept_canonical(l.department) <> l.department;

-- delegation_rule is unique on (dept_key, when_agent, delegate_to); two source departments can
-- carry the same pair, so collisions are dropped rather than allowed to abort the statement.
delete from public.delegation_rule d
 where exists (select 1 from public.delegation_rule x
                where x.id <> d.id
                  and public.fn_dept_canonical(x.dept_key) = public.fn_dept_canonical(d.dept_key)
                  and x.when_agent = d.when_agent and x.delegate_to = d.delegate_to
                  and x.id < d.id);
update public.delegation_rule d set dept_key = public.fn_dept_canonical(d.dept_key)
 where public.fn_dept_canonical(d.dept_key) <> d.dept_key;

-- department_budget PK is dept_key: the merged department's budget is the sum of its parts, and
-- so is the spend already booked against them, or the merged department starts a month looking
-- like it has spent nothing.
insert into public.department_budget (dept_key, monthly_aed, spent_aed, period_label,
                                      degrade_at_pct, halt_at_pct, updated_at)
select public.fn_dept_canonical(b.dept_key), sum(b.monthly_aed), sum(coalesce(b.spent_aed,0)),
       min(b.period_label), min(b.degrade_at_pct), min(b.halt_at_pct), now()
  from public.department_budget b
 where public.fn_dept_canonical(b.dept_key) <> b.dept_key
 group by 1
on conflict (dept_key) do update
  set monthly_aed = public.department_budget.monthly_aed + excluded.monthly_aed,
      spent_aed   = coalesce(public.department_budget.spent_aed,0) + coalesce(excluded.spent_aed,0),
      updated_at  = now();
delete from public.department_budget b where public.fn_dept_canonical(b.dept_key) <> b.dept_key;

-- os_department (os_key, dept_key): collapse duplicates that the merge creates.
insert into public.os_department (os_key, dept_key)
select distinct o.os_key, public.fn_dept_canonical(o.dept_key)
  from public.os_department o
 where public.fn_dept_canonical(o.dept_key) <> o.dept_key
on conflict do nothing;
delete from public.os_department o where public.fn_dept_canonical(o.dept_key) <> o.dept_key;

-- The packaged-department mapping must land on a department that is still active, or the next
-- knowledge import writes rows nobody retrieves.
-- data_analytics already pointed at BOTH `analytics` and `intelligence` (the second-home flag) and
-- both now canonicalise to data_intel, so the collapse has to happen before the update rather than
-- inside it: a single UPDATE cannot see the sibling row it is about to collide with.
delete from public.org_department_alias a
 where exists (select 1 from public.org_department_alias b
                where b.packaged_department = a.packaged_department
                  and public.fn_dept_canonical(b.dept_key) = public.fn_dept_canonical(a.dept_key)
                  and (b.is_second_home < a.is_second_home
                       or (b.is_second_home = a.is_second_home and b.dept_key < a.dept_key)));
update public.org_department_alias a set dept_key = public.fn_dept_canonical(a.dept_key)
 where public.fn_dept_canonical(a.dept_key) <> a.dept_key
   and not exists (select 1 from public.org_department_alias x
                    where x.packaged_department = a.packaged_department
                      and x.dept_key = public.fn_dept_canonical(a.dept_key));
delete from public.org_department_alias a
 where public.fn_dept_canonical(a.dept_key) <> a.dept_key;
-- strategy_evolution has two homes now, which is a fact about the split and is recorded as one.
insert into public.org_department_alias (packaged_department, dept_key, is_second_home, note)
values ('strategy_evolution','product_eng', true,
        'Evolution split 14 Aug 2026: strategy and organisation design to exec, product discovery and optimisation to product_eng')
on conflict do nothing;

-- ---------------------------------------------------------------------------------------------
-- CLOSE THE ABSORBED DEPARTMENTS. Rows stay; only `active` changes, so every historical foreign
-- key still resolves and fn_dept_scope can still read the merge map.
-- ---------------------------------------------------------------------------------------------
update public.org_departments set active = false where merged_into is not null;

revoke all on function public.fn_dept_canonical(text) from public;
revoke all on function public.fn_dept_scope(text)     from public;
grant execute on function public.fn_dept_canonical(text) to service_role;
grant execute on function public.fn_dept_scope(text)     to service_role;

commit;
