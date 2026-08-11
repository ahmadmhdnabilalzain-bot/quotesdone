-- THE ORGANISATION, RECONCILED AGAINST THE SPECIFICATION.
--
-- "quotesdone agents and knowledge.txt" names 22 departments. The live company had 14, one of them
-- switched off, and eight of the spec's departments did not exist at all. This is the build order,
-- not an argument that something similar already covers them:
--
--   spec  1 CEO Office AI ................ exec              LIVE
--   spec  2 Supplier Success ............. supplier_success  LIVE BUT active=false -> REACTIVATED
--   spec  3 Customer Success ............. customer_success  LIVE
--   spec  4 RFQ / Inquiry Intelligence ... rfq_intelligence  CREATED  (the spec marks this the core product)
--   spec  5 Marketplace Operations ....... procurement       LIVE
--   spec  6 Sales ........................ sales             LIVE
--   spec  7 Marketing .................... marketing         LIVE
--   spec  8 Finance ...................... finance           LIVE
--   spec  9 Legal & Compliance ........... legal             LIVE
--   spec 10 HR ........................... hr                LIVE
--   spec 11 Administration & Operations .. knowledge         LIVE (dept_key is a legacy misnomer; name corrected)
--   spec 12 Engineering .................. engineering       CREATED
--   spec 13 AI Department ................ ai_dept           CREATED  ("This is different from Engineering")
--   spec 14 IT & Cybersecurity ........... it                LIVE (name corrected; engineering split out)
--   spec 15 Data & Analytics ............. analytics         RESTORED - deleted 10 Aug 2026 for being empty
--   spec 16 QA & Testing ................. qa                CREATED
--   spec 17 Business Development ......... bizdev            CREATED
--   spec 18 Supplier Knowledge ........... supplier_knowledge CREATED
--   spec 19 Document Intelligence ........ doc_intelligence  CREATED
--   spec 20 Notification & Communication . comms             CREATED
--   spec 21 Payment ...................... payments          CREATED
--   spec 22 Trust & Safety ............... trust_safety      CREATED
--
-- WHY THIS IS NOT DECORATION. dept_plan:252 and dept_learn:72 both fan out over
-- `org_departments where active` — so a department that exists here plans its own work daily,
-- learns from its outcomes nightly, and has those tasks carried out by cos_execute. Adding a row
-- to this table is how the company hires. It is also why supplier_success being active=false
-- mattered: the spec's second department had not planned or learned anything at all.
--
-- THE SPEC FORBIDS A ONE-PERSON DEPARTMENT: "Departments should not consist of a single AI."
-- Every department below therefore lands with a named manager and at least two staff, and every
-- one of them owns something — an objective, an authority grant and a budget — because a
-- department that owns nothing is an org chart entry, not a department.
--
-- dept_key 'knowledge' is NOT renamed. It has been the Operations team under a legacy key since
-- before os_department recorded the misnomer, and the string appears in health functions, budgets,
-- cost telemetry, org_memory scopes and task rows. Renaming a primary key referenced by four
-- foreign keys and an unknown number of bare string literals, to fix a display name, is the kind
-- of change that breaks something nobody is watching. The NAME is corrected; the key stays.

begin;

-- fn_org_authority_guard refuses a new or raised authority grant without a stated reason, and it
-- caught the first attempt at this file. It is right to: eleven new departments arriving with
-- autonomous grants is exactly the change that should have to say why out loud.
set local app.change_reason = 'Eleven departments named in quotesdone agents and knowledge.txt did not exist in org_departments. Each is created with the narrowest grants that let it do its own job and constitutional gates on everything else: money, identity, secrets, destructive data, legal commitment, public claims, supplier enforcement, production deploy and the autonomy framework itself all stay gated for every one of them.';

-- ---------------------------------------------------------------------------------------------
-- 1. THE DEPARTMENTS
-- ---------------------------------------------------------------------------------------------
insert into public.org_departments (dept_key, name, charter, north_star, health_fn, lead_agent, active, sort, brain_agent) values
 ('rfq_intelligence','RFQ & Inquiry Intelligence',
  'The core product. Own inquiry intake, qualification, missing-information detection, document and drawing analysis, inquiry scoring and the routing of every RFQ to the right specialist desk.',
  'Qualified inquiries per RFQ, and the share that reach a supplier complete',
  null,'rfq_qualification_mgr',true,31,'rfq_qualification_mgr'),

 ('supplier_knowledge','Supplier Knowledge',
  'Own the supplier taxonomy, category definitions, industry standards and product catalogues. Keep the 84 trade categories and the knowledge behind each of them current, deduplicated and complete.',
  'Categories with all eight mandated knowledge modules present and validated',
  null,'taxonomy_manager',true,33,'taxonomy_manager'),

 ('doc_intelligence','Document Intelligence',
  'Understand every uploaded file: BOQs, drawings, CAD, PDFs, images, specifications, datasheets and contracts. Turn documents into structured requirements the rest of the company can act on.',
  'Documents parsed into structured requirements without a human reading them',
  null,'doc_intel_manager',true,35,'doc_intel_manager'),

 ('trust_safety','Trust & Safety',
  'Fraud detection, spam prevention, fake suppliers and fake RFQs, content moderation and user verification. Own the risk score behind every account on the platform.',
  'Fraudulent registrations stopped before a customer sees them',
  null,'trust_safety_mgr',true,37,'trust_safety_mgr'),

 ('engineering','Engineering',
  'Backend, frontend, mobile, API and the application itself. Build and ship the platform. Distinct from IT & Cybersecurity, which runs it, and from the AI Department, which owns the intelligence.',
  'Change delivered without breaking what already worked',
  null,'eng_manager',true,21,'eng_manager'),

 ('ai_dept','AI Department',
  'AI agents, knowledge base, RAG, prompt engineering, model evaluation, agent testing, AI monitoring and AI improvement. The specification states explicitly that this is NOT Engineering.',
  'Answer quality per AED of model spend',
  null,'ai_director',true,23,'ai_director'),

 ('analytics','Data & Analytics',
  'Dashboards, KPIs, business intelligence, reporting, supplier analytics, customer analytics and predictive analytics. Own the numbers everybody else argues with.',
  'Every company goal has a measured actual, not an aspiration',
  null,'analytics_director',true,15,'analytics_director'),

 ('qa','QA & Testing',
  'Software QA, AI QA, regression testing, RFQ accuracy testing and automation testing. Own the gate that says a change is safe to ship.',
  'Defects caught before production, not after',
  null,'qa_manager',true,81,'qa_manager'),

 ('bizdev','Business Development',
  'Partnerships, enterprise accounts, government relations, new markets and strategic alliances. Grow the company through relationships rather than transactions.',
  'Qualified enterprise and partnership pipeline created',
  null,'bd',true,46,'bd'),

 ('comms','Notification & Communication',
  'Email, SMS, WhatsApp, push notifications, reminders and follow-ups. One customer brain, many channels: own deliverability, identity and cadence across every one of them.',
  'Messages that reach the right person, once, with the right identity on them',
  null,'comms_manager',true,83,'comms_manager'),

 ('payments','Payment',
  'Payment gateway, subscription management, refunds, commission management and reconciliation of money in and out of the platform.',
  'Money collected, reconciled and refundable without a human touching Stripe',
  null,'payments_manager',true,71,'payments_manager')
on conflict (dept_key) do update set
  name = excluded.name, charter = excluded.charter, north_star = excluded.north_star,
  lead_agent = excluded.lead_agent, active = true, sort = excluded.sort,
  brain_agent = excluded.brain_agent;

-- SPEC 2. Supplier Success existed and was switched off, so the second department in the
-- specification had not planned or learned anything since it was deactivated.
update public.org_departments set active = true where dept_key = 'supplier_success';

-- SPEC 11 and 14. Names corrected to the specification's own words. 'knowledge' keeps its key.
update public.org_departments set name = 'Administration & Operations' where dept_key = 'knowledge';
update public.org_departments set name = 'IT & Cybersecurity',
       charter = 'Networks, cloud, security, identity management, disaster recovery, monitoring and compliance. Run the platform and keep it safe. Also formally owns AI Model Operations jointly with the AI Department: routing policy, per-department AI budgets, cache policy and cost telemetry, as implemented in ai_gateway / fn_ai_route / model_policy / ai_cost_log.'
 where dept_key = 'it';

-- ---------------------------------------------------------------------------------------------
-- 2. THE PEOPLE. Existing staff move first, so the new departments are not empty for an instant.
-- ---------------------------------------------------------------------------------------------
update public.org_agents set department='rfq_intelligence', manager_key='brief', seniority='manager' where agent_key='rfq_qualification_mgr';
update public.org_agents set department='engineering', manager_key='eng_manager' where agent_key in ('backend_engineer','frontend_engineer','solution_architect');
update public.org_agents set department='ai_dept',     manager_key='ai_director'  where agent_key='ai_architect';
update public.org_agents set department='analytics',   manager_key='analytics_director' where agent_key='analytics';
update public.org_agents set department='qa',          manager_key='brief', seniority='manager' where agent_key='qa_manager';
update public.org_agents set department='bizdev',      manager_key='brief' where agent_key='bd';
update public.org_agents set department='bizdev',      manager_key='bd'    where agent_key='partnerships_mgr';

-- Two supplier_success specialists reported to NOBODY. The spec's employee object requires a
-- manager, and fn_agent_context prints "Reports to: nobody — you are the top of the reporting
-- line." for a null, which is false for a specialist.
update public.org_agents set manager_key='onboarding' where agent_key in ('supplier_coverage','supplier_retention') and manager_key is null;

insert into public.org_agents (agent_key, department, role, kind, active, title, manager_key, seniority, responsibilities, max_open_tasks) values
 -- RFQ & Inquiry Intelligence -------------------------------------------------------------------
 ('inquiry_router','rfq_intelligence','Inquiry Router','brain',true,'AI Inquiry Router','rfq_qualification_mgr','specialist',
  'Classify every incoming inquiry to a trade category and route it to the owning specialist desk. Detect multi-trade scope and split it. Refuse to guess: an unroutable inquiry is escalated with the reason, never routed to the nearest thing.',6),
 ('inquiry_scoring','rfq_intelligence','Inquiry Scoring Analyst','brain',true,'Inquiry Scoring & Validation Analyst','rfq_qualification_mgr','specialist',
  'Score inquiry completeness and buyer seriousness, detect the mandatory information that is missing for the category, and validate attachments against what the category actually needs before any supplier is invited.',6),

 -- Supplier Knowledge ---------------------------------------------------------------------------
 ('taxonomy_manager','supplier_knowledge','Supplier Taxonomy Manager','brain',true,'Supplier Taxonomy Manager','brief','manager',
  'Own the trade taxonomy end to end: category definitions, aliases, merges and retirements. Nothing enters or leaves the category list without this desk. Keep the live category set reconciled to the specification.',6),
 ('category_curator','supplier_knowledge','Category Knowledge Curator','brain',true,'Category Knowledge Curator','taxonomy_manager','specialist',
  'For every category, keep all eight mandated knowledge modules present and current: Industry, Products & Services, Technical, Supplier, Quotation, Documents, UAE Regulations & Authorities, Inquiry Qualification Logic.',6),
 ('supplier_intel_analyst','supplier_knowledge','Supplier Intelligence Analyst','brain',true,'Supplier Intelligence Analyst','taxonomy_manager','specialist',
  'Track manufacturers, local and international brands, UAE standards and product catalogues. Feed supplier capability data the matching engine can act on.',6),

 -- Document Intelligence ------------------------------------------------------------------------
 ('doc_intel_manager','doc_intelligence','Document Intelligence Manager','brain',true,'Document Intelligence Manager','brief','manager',
  'Own document understanding across the platform: classification, extraction, comparison and validation. Every uploaded file leaves this department as structured data or as a named reason it could not.',6),
 ('drawing_analyst','doc_intelligence','Drawing Analyst','brain',true,'Drawing & CAD Analyst','doc_intel_manager','specialist',
  'Read shop drawings, IFC and as-built drawings, elevations, sections and MEP layouts. Identify rooms, equipment and counts, link drawing elements to RFQ items, and flag what the drawing does not show.',6),
 ('boq_analyst','doc_intelligence','BOQ Analyst','brain',true,'BOQ & Specification Analyst','doc_intel_manager','specialist',
  'Read bills of quantities, technical specifications and datasheets. Extract items, quantities and units, detect missing or contradictory lines, and produce the requirement list an RFQ is built from.',6),

 -- Trust & Safety -------------------------------------------------------------------------------
 ('trust_safety_mgr','trust_safety','Trust & Safety Manager','brain',true,'Trust & Safety Manager','brief','manager',
  'Own platform integrity: fraud, spam, fake suppliers, fake RFQs, moderation and verification. Set the risk thresholds and escalate anything that would cost a real customer money.',6),
 ('fraud_analyst','trust_safety','Fraud Analyst','brain',true,'Fraud & Risk Analyst','trust_safety_mgr','specialist',
  'Investigate flagged registrations, duplicate identities, licence anomalies and abusive quoting patterns. Score risk and recommend suspension with evidence, never on suspicion alone.',6),
 ('moderation_specialist','trust_safety','Content Moderation Specialist','brain',true,'Content Moderation Specialist','trust_safety_mgr','specialist',
  'Moderate supplier profiles, quotations and messages for contact-detail leakage, abuse and misrepresentation. The marketplace is anonymous: enforcing that is this desk.',6),

 -- Engineering ----------------------------------------------------------------------------------
 ('eng_manager','engineering','Engineering Manager','brain',true,'Engineering Manager','cto','manager',
  'Own delivery of the application: backend, frontend, API and mobile. Review work, hold the change-safety line, and never let a deploy through without the check that would have caught the last incident.',6),

 -- AI Department --------------------------------------------------------------------------------
 ('ai_director','ai_dept','AI Director','brain',true,'AI Director','brief','director',
  'Own the intelligence layer: agents, knowledge base, RAG, prompt engineering, model evaluation, guardrails and AI monitoring. Answer for answer quality and for what the models cost.',6),
 ('prompt_engineer','ai_dept','Prompt Engineer','brain',true,'Prompt Engineer','ai_director','specialist',
  'Own the system prompts and their token budgets. Compress context, keep the stable half of a prompt stable so it can be cached, and prove every change against measured quality, not taste.',6),
 ('model_evaluator','ai_dept','Model Evaluation Specialist','brain',true,'Model Evaluation & Guardrails Specialist','ai_director','specialist',
  'Benchmark models on quality, latency and cost for each task class. Run the eval harness, watch for drift and hallucination, and recommend routing changes with the numbers behind them.',6),

 -- Data & Analytics -----------------------------------------------------------------------------
 ('analytics_director','analytics','Analytics Director','brain',true,'Data & Analytics Director','brief','director',
  'Own the company''s numbers: dashboards, KPI definitions, BI and reporting. Every company goal must have a measured actual and a named owner, and disagreements about a number end here.',6),
 ('bi_analyst','analytics','Business Intelligence Analyst','brain',true,'Business Intelligence Analyst','analytics_director','specialist',
  'Build and maintain the reporting the founder and the executive team read. Explain variance against target with a root cause, not a restatement of the number.',6),

 -- QA & Testing ---------------------------------------------------------------------------------
 ('test_automation_eng','qa','Test Automation Engineer','brain',true,'Test Automation Engineer','qa_manager','specialist',
  'Own the automated suites: regression, smoke, money tests and end-to-end. A check that passes when the thing it checks is broken is worse than no check, so prove each one fails on the defect it claims to catch.',6),
 ('ai_qa_specialist','qa','AI QA Specialist','brain',true,'AI Quality Assurance Specialist','qa_manager','specialist',
  'Test the AI itself: RFQ qualification accuracy, routing correctness, extraction fidelity and answer grounding. Maintain the fixtures and the holdout sets.',6),

 -- Business Development -------------------------------------------------------------------------
 ('gov_relations_mgr','bizdev','Government Relations Manager','brain',true,'Government & Enterprise Relations Manager','bd','manager',
  'Own government entities, tenders, prequalification and enterprise procurement relationships in the UAE. Track opportunities the marketplace cannot reach through self-service.',5),

 -- Notification & Communication -----------------------------------------------------------------
 ('comms_manager','comms','Communications Manager','brain',true,'Notification & Communication Manager','brief','manager',
  'Own every outbound channel: email, SMS, WhatsApp, push, reminders and follow-ups. One identity per audience, one cadence policy, and a single answer to "did this actually reach them".',6),
 ('channel_specialist','comms','Channel Specialist','brain',true,'Channel & Deliverability Specialist','comms_manager','specialist',
  'Own deliverability and sender reputation: bounces, suppressions, opt-outs, template approval and per-recipient caps. A message that lands in spam did not reach anybody.',6),
 ('notification_ops','comms','Notification Operations Specialist','brain',true,'Notification Operations Specialist','comms_manager','specialist',
  'Run the outbox: queue depth, retries, dead letters and the digest. An alert that is raised and never sent is the failure this desk exists to prevent.',6),

 -- Payment --------------------------------------------------------------------------------------
 ('payments_manager','payments','Payments Manager','brain',true,'Payments Manager','cfo','manager',
  'Own the payment gateway, subscriptions, commissions and the refund path. Money movement is gated by the constitution: prepare and route it, never execute it unapproved.',6),
 ('billing_specialist','payments','Billing Specialist','brain',true,'Billing & Reconciliation Specialist','payments_manager','specialist',
  'Reconcile Stripe events against the ledger, chase failed charges, and make sure every reveal invoice and subscription line has a matching payment record.',6)
on conflict (agent_key) do update set
  department = excluded.department, title = excluded.title, manager_key = excluded.manager_key,
  seniority = excluded.seniority, responsibilities = excluded.responsibilities, active = true;

-- ---------------------------------------------------------------------------------------------
-- 3. EVERY DEPARTMENT OWNS SOMETHING. Objective + authority + budget, or it is an org chart entry.
-- ---------------------------------------------------------------------------------------------
insert into public.department_objective (dept_key, objective, horizon, sort, active) values
 ('rfq_intelligence','Every inquiry that reaches a supplier carries the mandatory information its category requires','quarterly',1,true),
 ('rfq_intelligence','No inquiry sits unrouted for more than six hours','weekly',2,true),
 ('supplier_knowledge','All eight mandated knowledge modules present and validated for every live trade category','quarterly',1,true),
 ('supplier_knowledge','The live category list matches the specification exactly, with no duplicates','quarterly',2,true),
 ('doc_intelligence','Every uploaded BOQ and drawing leaves as structured requirements or a named reason it could not','quarterly',1,true),
 ('trust_safety','No fraudulent supplier registration reaches a customer-visible state','quarterly',1,true),
 ('engineering','Every production change ships behind a check that fails on the defect it claims to catch','quarterly',1,true),
 ('ai_dept','Answer quality holds while cost per reasoning call falls','quarterly',1,true),
 ('ai_dept','Every model call is classified, budgeted and attributable to an employee','weekly',2,true),
 ('analytics','Every active company goal has a measured actual, refreshed on its own period','quarterly',1,true),
 ('qa','No regression reaches production that an existing suite could have caught','quarterly',1,true),
 ('bizdev','A named, qualified enterprise or government pipeline exists and moves each month','quarterly',1,true),
 ('comms','Every alert raised for the founder is either sent or provably folded into a digest he receives','weekly',1,true),
 ('payments','Every Stripe event reconciles to a ledger row within 24 hours','weekly',1,true)
on conflict do nothing;

insert into public.org_authority (dept_key, action_class, max_tier, threshold_aed, note) values
 ('rfq_intelligence','qualify_inquiry','autonomous',null,'Qualification is the department''s own product.'),
 ('rfq_intelligence','route_category','autonomous',null,'Routing an inquiry to the owning desk is this department''s job.'),
 ('rfq_intelligence','analysis','autonomous',null,null),
 ('rfq_intelligence','recommend','autonomous',null,null),
 ('supplier_knowledge','knowledge_fill','autonomous',null,'Filling a category knowledge gap is the whole point of the department.'),
 ('supplier_knowledge','knowledge_acquire','autonomous',null,null),
 ('supplier_knowledge','analysis','autonomous',null,null),
 ('supplier_knowledge','route_category','gated',null,'Changing the taxonomy itself changes what the marketplace sells. Propose it.'),
 ('doc_intelligence','analysis','autonomous',null,null),
 ('doc_intelligence','recommend','autonomous',null,null),
 ('doc_intelligence','destructive_data','gated',null,'Redaction and deletion of a customer document is gated.'),
 ('trust_safety','investigate','autonomous',null,'Investigating a flag is not the same as acting on it.'),
 ('trust_safety','security_review','autonomous',null,null),
 ('trust_safety','supplier_ban','gated',null,'Banning a supplier is a commercial decision with a founder gate.'),
 ('trust_safety','supplier_enforcement','gated',null,null),
 ('engineering','code_selfheal','supervised',null,null),
 ('engineering','production_deploy','gated',null,'Branch protection and CI are the gate; this records it.'),
 ('engineering','incident_fix','supervised',null,null),
 ('engineering','analysis','autonomous',null,null),
 ('ai_dept','analysis','autonomous',null,null),
 ('ai_dept','recommend','autonomous',null,null),
 ('ai_dept','knowledge_fill','autonomous',null,null),
 ('ai_dept','autonomy_framework','gated',null,'The AI department does not get to widen its own autonomy.'),
 ('analytics','analysis','autonomous',null,null),
 ('analytics','bi_snapshot','autonomous',null,null),
 ('analytics','forecast','autonomous',null,null),
 ('analytics','metric_alerts','autonomous',null,null),
 ('qa','qa_gate','autonomous',null,'Holding the gate IS the department.'),
 ('qa','analysis','autonomous',null,null),
 ('qa','production_deploy','gated',null,null),
 ('bizdev','outreach_draft','autonomous',null,null),
 ('bizdev','outreach_send','gated',null,'Anything that reaches a real company is gated.'),
 ('bizdev','recommend','autonomous',null,null),
 ('comms','nudge','autonomous',null,null),
 ('comms','outreach_draft','autonomous',null,null),
 ('comms','outreach_send','gated',null,'Sending on the company''s behalf stays gated.'),
 ('comms','analysis','autonomous',null,null),
 ('payments','money_verify','autonomous',null,'Verifying money is not moving money.'),
 ('payments','invoice_review','autonomous',null,null),
 ('payments','money_move','gated',null,'Constitutional gate. Prepare and route; never execute.'),
 ('payments','refund_within_window','gated',null,'The founder''s standing rule: Stripe refunds need him.')
on conflict do nothing;

-- Constitutional gates apply to every department, including the new ones. These are the five
-- classes org_authority already carries on all 14 existing departments.
insert into public.org_authority (dept_key, action_class, max_tier, threshold_aed, note)
select d.dept_key, c.action_class, 'gated', null,
       'Constitutional gate: applies to every department without exception.'
  from public.org_departments d
  cross join (values ('authentication_identity'),('autonomy_framework'),('destructive_data'),
                     ('legal_commitment'),('production_deploy'),('public_claim_publish'),
                     ('secrets_security'),('supplier_enforcement')) as c(action_class)
 where not exists (select 1 from public.org_authority o
                    where o.dept_key = d.dept_key and o.action_class = c.action_class);

-- A department with no budget row cannot be degraded or halted by fn_ai_route: the budget branch
-- is skipped entirely when the row is missing, so it spends without a ceiling. supplier_success
-- has been in exactly that position.
insert into public.department_budget (dept_key, monthly_aed, degrade_at_pct, halt_at_pct, period_label)
select d.dept_key,
       case d.dept_key
         when 'rfq_intelligence' then 800 when 'doc_intelligence' then 480
         when 'supplier_knowledge' then 480 when 'ai_dept' then 480
         when 'analytics' then 320 when 'engineering' then 320
         when 'trust_safety' then 240 when 'qa' then 240
         when 'comms' then 200 when 'payments' then 200
         when 'bizdev' then 200 when 'supplier_success' then 400
         else 200 end,
       70, 95, to_char(now(), 'YYYY-MM')
  from public.org_departments d
 where d.active
   and not exists (select 1 from public.department_budget b where b.dept_key = d.dept_key);

-- ---------------------------------------------------------------------------------------------
-- 4. WHICH OPERATING SYSTEM EACH DEPARTMENT BELONGS TO. Without this row fn_agent_context emits
--    no OS block at all, so the employee cannot name their purpose, mission, owner or objectives.
-- ---------------------------------------------------------------------------------------------
insert into public.os_department (os_key, dept_key, note) values
 ('marketplace','rfq_intelligence','Inquiry qualification is the Marketplace OS''s own mandate.'),
 ('knowledge','supplier_knowledge','Supplier taxonomy and category knowledge are knowledge assets.'),
 ('operations','doc_intelligence','Document control sits with Operations.'),
 ('legal_gov','trust_safety','Platform integrity is governance, not marketing.'),
 ('technology','engineering',null),
 ('technology','ai_dept','The AI runtime is Technology''s mandate; the department owns the intelligence in it.'),
 ('intelligence','analytics','Analytics and KPI instrumentation are the Intelligence OS''s own words.'),
 ('operations','qa','Quality gates sit with Operations.'),
 ('commercial','bizdev',null),
 ('operations','comms','Service delivery includes telling people things.'),
 ('finance','payments',null)
on conflict do nothing;

-- ---------------------------------------------------------------------------------------------
-- 5. KPIs. The spec's employee object requires them, and fn_agent_context prints them to the
--    employee as "this is how your work is measured".
-- ---------------------------------------------------------------------------------------------
insert into public.employee_kpi (agent_key, kpi, metric, target_value, unit, cadence, active) values
 ('inquiry_router','Inquiries routed without escalation','share of inquiries routed to a live desk first time',90,'%','weekly',true),
 ('inquiry_scoring','Inquiries complete before a supplier is invited','share with all mandatory fields present',85,'%','weekly',true),
 ('taxonomy_manager','Category list matches the specification','categories differing from the spec',0,'count','monthly',true),
 ('category_curator','Categories with all eight knowledge modules','share of live categories fully covered',100,'%','monthly',true),
 ('supplier_intel_analyst','Supplier capability records enriched','suppliers with structured capability data',80,'%','monthly',true),
 ('doc_intel_manager','Documents parsed to structured output','share of uploads that produce requirements',85,'%','weekly',true),
 ('drawing_analyst','Drawings linked to RFQ items','share of drawings with linked line items',70,'%','monthly',true),
 ('boq_analyst','BOQ lines extracted correctly','extraction accuracy against the fixture set',95,'%','monthly',true),
 ('trust_safety_mgr','Fraudulent registrations reaching a customer','count per month',0,'count','monthly',true),
 ('fraud_analyst','Flagged accounts investigated within SLA','share closed within 48 hours',90,'%','weekly',true),
 ('moderation_specialist','Contact-detail leakage in anonymous quotes','incidents per month',0,'count','monthly',true),
 ('eng_manager','Production changes behind a failing-first check','share of changes with a proving check',100,'%','monthly',true),
 ('ai_director','Cost per reasoning call','AED per agent_reasoning call',0.15,'AED','weekly',true),
 ('prompt_engineer','Prompt tokens per reasoning call','average prompt_tokens on agent_reasoning',18000,'tokens','weekly',true),
 ('model_evaluator','Task classes with a measured benchmark','share of active task classes benchmarked',80,'%','monthly',true),
 ('analytics_director','Company goals with a measured actual','share of active goals carrying a real number',100,'%','weekly',true),
 ('bi_analyst','Variance explained with a root cause','share of missed KPIs with a named cause',90,'%','monthly',true),
 ('test_automation_eng','Regressions caught before production','share caught by a suite rather than in the wild',90,'%','monthly',true),
 ('ai_qa_specialist','RFQ qualification accuracy','accuracy against the holdout set',90,'%','monthly',true),
 ('gov_relations_mgr','Government and enterprise opportunities tracked','open qualified opportunities',5,'count','monthly',true),
 ('comms_manager','Alerts raised that reach the founder','share sent or provably digested',100,'%','weekly',true),
 ('channel_specialist','Hard bounce rate','share of sends that hard bounce',2,'%','weekly',true),
 ('notification_ops','Notifications older than 24h still unsent','count',0,'count','weekly',true),
 ('payments_manager','Stripe events reconciled to the ledger','share reconciled within 24 hours',100,'%','weekly',true),
 ('billing_specialist','Reveal invoices without a payment record','count',0,'count','weekly',true)
on conflict do nothing;

commit;
