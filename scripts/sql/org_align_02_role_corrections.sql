-- ORG ALIGNMENT 02 — the nine role corrections, against the actual QuotesDone workflow.
--
-- The ten-department design and the ~90-role scale are accepted and unchanged. This file corrects
-- WHO OWNS WHAT, not how many rows exist. Nothing is renamed to make a name match an instruction;
-- every change below closes a measured gap or removes a measured conflict.
--
-- WHAT THE MEASUREMENTS SAID, before any of this (production, 15 Aug 2026, zero model cost):
--
--   * workflow_step 'rfq_handling' #5 "Select suppliers" has actor_role = 'domain specialist'.
--     That string resolves to no employee: fn_org_agent_resolve and fn_org_role_resolve both
--     return null. The step that decides which suppliers receive a customer's RFQ has no
--     accountable owner. dispatch_inquiry has been doing the work and recording it against
--     agent_runs.agent = 'dispatch_inquiry' and agent_actions.agent = 'operations_ai' — neither is
--     a canonical role.
--   * rfq_handling has no supplier-safe payload or privacy-review step at all. The redaction and
--     the brief are produced and dispatched with no independent check that the customer's identity
--     left the payload.
--   * workflow_step 'rfq_handling' #6 names 'Procurement Director'. `procurement` is a
--     merged-away department key; the live head is the Marketplace Director.
--   * employee_workflow records TEN owners for rfq_handling and 43 for employee_task. "Every
--     workflow has one accountable owner" is not true today at the workflow level, and
--     employee_workflow has no step granularity to express it at. Step ownership lives in
--     workflow_step, which is where org_align_03 puts it.
--
-- DEPARTMENT KEYS ARE NOT RENAMED.  EXISTING_BETTER_KEEP.
-- The instruction names departments as marketplace_supplier_network, legal_compliance_risk_trust,
-- people_company_operations and independent_assurance_security_reliability. Those are the
-- department NAMES, and org_departments.name already carries them verbatim
-- ("Marketplace & Supplier Network", "Legal, Compliance, Risk & Trust", ...). The keys
-- marketplace / legal / people_ops / assurance are the physical identifiers, referenced by
-- org_agents.department, agent_tool.authorised_departments, org_action_executor.department,
-- delegation_rule, fn_pick_reviewer and 59 executor rows. Renaming them buys a cosmetic match and
-- risks the exact failure recorded on 14 Aug, when a merged-away department key silently emptied a
-- `where dept_key = ...` scope and made the spend meter blind to 64% of the money.
--
-- PHYSICAL agent_key VALUES ARE NOT RENAMED EITHER.  EXISTING_BETTER_KEEP.
-- role_id is the clear name and agent_key is the physical one; fn_org_agent_resolve resolves both,
-- plus every alias and every job title. Renaming agent_key would cascade through seven foreign
-- keys (handoff_contract x3, org_tasks, org_agent_alias, org_role_identity, org_category_identity,
-- agent_remediation, agent_training_attempt) and five tables with no FK at all, to change a string
-- that the resolver already handles. What DOES change is org_agents.title, because that is the arm
-- of the resolver that makes a job title an identifier — and the founder's standing rule is to
-- address employees by title.

begin;

-- =============================================================================================
-- 1. SUPPLIER MATCHING & DISPATCH OPERATOR  (was: Commercial Services Specialist)
-- =============================================================================================
-- The repurpose the instruction asks for, and the reason it is safe: all ten commercial trade
-- families this role carried — accounting, cleaning, facilities management, HR/recruitment, IT,
-- legal, logistics, consulting, marketing, security — each already have their own category
-- overlay. Verified 10/10 on production. So the trade knowledge does not leave the company when
-- this seat changes job; it stays where the instruction wants it, on demand, in the 86 overlays.
--
-- Class O. It executes dispatch policy; it does not set it. The Marketplace Director owns policy.

-- org_role_one_per_agent_ux is UNIQUE on runtime_agent_key: one employee holds exactly one role
-- identity. The old row therefore has to release the agent before the new row can claim it, which
-- is the guard doing its job — two role rows pointing at one employee is precisely the ambiguity
-- fn_agent_tools and fn_pick_reviewer would then have to guess their way through.
create temp table _seat as select * from org_role where role_id = 'spec_commercial';
update org_role set runtime_agent_key = null where role_id = 'spec_commercial';
update _seat set role_id = 'supplier_matching_dispatch_operator';
insert into org_role select * from _seat;

update org_role           set manager_role_id = 'supplier_matching_dispatch_operator' where manager_role_id = 'spec_commercial';
update org_role_alias     set role_id         = 'supplier_matching_dispatch_operator' where role_id         = 'spec_commercial';
update org_role_committee set role_id         = 'supplier_matching_dispatch_operator' where role_id         = 'spec_commercial';
delete from org_role where role_id = 'spec_commercial';
drop table _seat;

update org_role set
  display_name        = 'Supplier Matching & Dispatch Operator',
  primary_department_id = 'marketplace',
  manager_role_id     = 'marketplace_director',
  runtime_mode        = 'event_driven_operator',
  authority_level     = 'execute_low',
  responsibilities    =
    'Executes supplier dispatch for inquiries that are already approved, quote-ready and '
    'supplier-safe. Retrieves eligible suppliers, applies the deterministic capability, location, '
    'approval, availability, fairness and policy rules, proposes the supplier set, re-validates '
    'every supplier immediately before assignment, creates idempotent assignment rows, and causes '
    'exactly one notification per selected supplier. Records the reason for every selection AND '
    'every exclusion. Refuses to dispatch when any eligibility, privacy, completeness, file or '
    'supplier gate fails - a refusal with a named gate is the correct output, not a failure.',
  activation_conditions =
    'An inquiry becomes dispatch-eligible: rfq_ready is true, every active workstream gate is '
    'satisfied (fn_inquiry_dispatch_eligible), and its supplier-safe payload has been approved by '
    'the Marketplace Content & Privacy Reviewer. Runs once per inquiry under an atomic claim; a '
    'run that reached nobody is retried by fn_rfq_redispatch_sweep.',
  owned_decisions     = array[
    'which eligible suppliers are proposed for an approved inquiry',
    'the recorded reason for each selection and each exclusion',
    'refusing to dispatch when a gate fails'],
  forbidden_decisions = array[
    'setting company dispatch policy - that belongs to the Marketplace Director',
    'bypassing RFQ qualification',
    'bypassing supplier-safe review',
    'approving a supplier',
    'changing customer identity policy',
    'overriding a category or regulatory gate'],
  required_inputs     = array[
    'a dispatch-eligible inquiry id',
    'the approved supplier-safe brief snapshot',
    'the live supplier eligibility state at the moment of assignment'],
  output_contracts    = array['dispatch_decision', 'supplier_assignment', 'exclusion_ledger'],
  -- supplier_approve_clean is REMOVED: an operator that can approve a supplier can manufacture its
  -- own eligible set. supplier_verify stays because reading a supplier's standing immediately
  -- before assignment is exactly what the instruction requires.
  tools               = array['match_inquiry', 'invite', 'capability_enrich', 'supplier_verify', 'coordinate'],
  -- The ten cat: scopes go with the overlays. What this seat needs is the matching and dispatch
  -- rulebook, not ten trade encyclopaedias it would pay to load on every run.
  knowledge_scopes    = array['marketplace', 'supplier_mgmt', 'supplier_knowledge', 'supplier_success',
                              'rfq_intelligence', 'procurement', 'operations', 'pdpl', 'legal_uae',
                              'company', 'company_goals', 'constitution', 'priority_hierarchy',
                              'quotesdone_os', 'universal_objectives'],
  handoff_targets     = array['lifecycle_channel_operations', 'supplier_coverage', 'marketplace_director'],
  escalation_targets  = array['marketplace_director', 'chief_of_staff'],
  -- DETERMINISTIC FIRST. Eligibility, capability filtering, fairness and idempotency are code, not
  -- judgement: route_inquiry does the adjudication and fn_match_capability does the scoring. What
  -- is left for a model is summarising a refusal. The cheapest tier is the correct tier here, and
  -- nothing pointed at routine_employee_reasoning before now.
  model_policy        = 'routine_employee_reasoning',
  rationale           =
    'Repurposed from Commercial Services Specialist on 15 Aug 2026. The step that decides which '
    'suppliers receive a customer RFQ had no accountable owner: workflow_step rfq_handling #5 read '
    '"domain specialist", which resolves to nobody, and dispatch_inquiry recorded its work against '
    'agent_runs.agent = ''dispatch_inquiry''. The ten commercial trade families this seat used to '
    'carry each have their own category overlay (verified 10/10), so no category coverage is lost.'
where role_id = 'supplier_matching_dispatch_operator';

update org_agents set
  title            = 'Supplier Matching & Dispatch Operator',
  responsibilities = 'Executes supplier dispatch for approved, quote-ready, supplier-safe inquiries: '
                     'eligibility, matching, idempotent assignment, one notification per supplier, '
                     'and a recorded reason for every selection and exclusion.'
where agent_key = 'spec_commercial';

-- Both old names stay addressable, and both new ones become addressable. The title arm of
-- fn_org_agent_resolve reads org_agents.title, so the OLD title must be preserved as an alias or
-- every historical reference to it stops resolving.
insert into org_agent_alias (alias, agent_key, reason) values
  ('Commercial Services Specialist',      'spec_commercial', 'previous job title, kept addressable by the 15 Aug 2026 workflow alignment'),
  ('spec_commercial',                     'spec_commercial', 'previous canonical role id, kept addressable by the 15 Aug 2026 workflow alignment'),
  ('supplier_matching_dispatch_operator', 'spec_commercial', 'canonical role id for Supplier Matching & Dispatch Operator')
on conflict (alias) do nothing;

insert into org_role_alias (alias, role_id, kind, reason) values
  ('spec_commercial',                'supplier_matching_dispatch_operator', 'legacy_role_id', 'repurposed 15 Aug 2026'),
  ('Commercial Services Specialist', 'supplier_matching_dispatch_operator', 'title',          'previous title, repurposed 15 Aug 2026')
on conflict (alias) do nothing;

-- =============================================================================================
-- 2. MARKETPLACE CONTENT & PRIVACY REVIEWER  (was: Content Moderation Reviewer)
-- =============================================================================================
-- PLACEMENT: legal, not assurance.  The instruction asks for whichever preserves TRUE reviewer
-- independence in the current code, so this is decided on how the code actually picks reviewers.
--
-- fn_pick_reviewer(p_dept_key, p_author) returns the HEAD of the department it is given. The
-- supplier-safe payload is authored inside `marketplace` (RFQ Qualification Manager, Inquiry
-- Router, Document Intelligence Manager). Placing this reviewer in marketplace would make its own
-- department head - the Marketplace Director, who owns dispatch policy and whose operator consumes
-- this approval - the fallback reviewer of the privacy decision. Both legal and assurance avoid
-- that. Legal wins on two further measurements:
--
--   * assurance's every role reports to quality_and_release_director, who holds release go/no-go.
--     Routing per-artifact privacy approval through the release gate couples two decisions the
--     instruction deliberately separates in item 9.
--   * legal already holds compliance_and_privacy_officer and the pdpl_action executor, and
--     trust_and_safety_manager - which the instruction says retains general moderation policy,
--     disputes and enforcement - is this role's manager today. Keeping the reporting line intact
--     preserves the split the instruction asks for rather than inventing a new one.
--
-- Reviewer independence is then structural, not procedural: the payload's authors are in
-- marketplace, the reviewer is in legal, and no fn_pick_reviewer path can return one for the other.

create temp table _seat as select * from org_role where role_id = 'moderation_specialist';
update org_role set runtime_agent_key = null where role_id = 'moderation_specialist';
update _seat set role_id = 'marketplace_content_privacy_reviewer';
insert into org_role select * from _seat;

update org_role           set manager_role_id = 'marketplace_content_privacy_reviewer' where manager_role_id = 'moderation_specialist';
update org_role_alias     set role_id         = 'marketplace_content_privacy_reviewer' where role_id         = 'moderation_specialist';
update org_role_committee set role_id         = 'marketplace_content_privacy_reviewer' where role_id         = 'moderation_specialist';
delete from org_role where role_id = 'moderation_specialist';
drop table _seat;

update org_role set
  display_name        = 'Marketplace Content & Privacy Reviewer',
  primary_department_id = 'legal',
  manager_role_id     = 'trust_and_safety_manager',
  runtime_mode        = 'independent_reviewer',
  authority_level     = 'stop_authority',
  responsibilities    =
    'Inspects the ACTUAL supplier-facing artefacts before any supplier sees them: the final '
    'supplier-safe payload, the supplier-facing files, and the redacted drawings. Verifies removal '
    'of customer name, email, phone, URLs, messenger identifiers, document metadata and hidden '
    'identifiers; verifies that only approved file revisions are included; verifies that the '
    'portal and the notification carry the same approved snapshot. Approves, rejects, or returns '
    'for correction, and records the evidence, the file revisions seen, the checks performed and '
    'the reason. Inspects the artefact itself - approving from the brief is approving the brief.',
  activation_conditions =
    'A supplier-safe payload is frozen for an inquiry, a supplier-facing file revision is proposed, '
    'or a redacted drawing is produced. Runs per artefact, not on a schedule.',
  owned_decisions     = array[
    'approving, rejecting or returning a supplier-facing payload',
    'approving the specific file revisions a supplier may see',
    'blocking dispatch on an unremoved customer identifier'],
  forbidden_decisions = array[
    'authoring the inquiry brief or the redaction it then approves',
    'approving its own work under any alias',
    'general moderation policy, disputes and enforcement - those belong to the Trust & Safety Manager',
    'dispatching to suppliers',
    'overriding a regulatory or category gate'],
  required_inputs     = array[
    'the frozen supplier-safe brief snapshot',
    'the supplier-facing file revisions',
    'the redacted drawing artefacts',
    'the identity of the agent that authored each of them'],
  output_contracts    = array['content_privacy_verdict', 'redaction_evidence'],
  tools               = array['compliance_check', 'legal_review', 'pdpl_action', 'artifact.review', 'brand_scan'],
  knowledge_scopes    = array['legal', 'trust_safety', 'pdpl', 'legal_uae', 'marketplace',
                              'doc_intelligence', 'supplier_mgmt', 'company', 'constitution',
                              'priority_hierarchy', 'quotesdone_os'],
  handoff_targets     = array['supplier_matching_dispatch_operator', 'trust_and_safety_manager', 'document_intelligence_manager'],
  escalation_targets  = array['trust_and_safety_manager', 'compliance_and_privacy_officer'],
  model_policy        = 'reviewer_auditor',
  rationale           =
    'Repurposed from Content Moderation Reviewer on 15 Aug 2026. rfq_handling had no supplier-safe '
    'payload or privacy review step at all: the brief and the redaction were dispatched with no '
    'independent check that the customer identity had left the payload. Placed in legal rather '
    'than assurance because fn_pick_reviewer returns a department head, and assurance''s head holds '
    'release go/no-go - coupling artefact privacy approval to the release gate.'
where role_id = 'marketplace_content_privacy_reviewer';

update org_agents set
  title            = 'Marketplace Content & Privacy Reviewer',
  responsibilities = 'Inspects the actual supplier-facing payload, files and redacted drawings for '
                     'customer identifiers and unapproved revisions before any supplier sees them.'
where agent_key = 'moderation_specialist';

insert into org_agent_alias (alias, agent_key, reason) values
  ('Content Moderation Reviewer',           'moderation_specialist', 'previous job title, kept addressable by the 15 Aug 2026 workflow alignment'),
  ('marketplace_content_privacy_reviewer',  'moderation_specialist', 'canonical role id for Marketplace Content & Privacy Reviewer')
on conflict (alias) do nothing;

insert into org_role_alias (alias, role_id, kind, reason) values
  ('moderation_specialist',       'marketplace_content_privacy_reviewer', 'legacy_role_id', 'repurposed 15 Aug 2026'),
  ('Content Moderation Reviewer', 'marketplace_content_privacy_reviewer', 'title',          'previous title, repurposed 15 Aug 2026')
on conflict (alias) do nothing;

-- =============================================================================================
-- 3. THE FOUR BROAD TECHNICAL SPECIALISTS — kept, and fenced off from the 86 overlays
-- =============================================================================================
-- EXISTING_BETTER_KEEP on the runtime mode: all four are already on_demand_specialist with
-- advisory authority, which is exactly what the instruction asks for. What was missing is the
-- fence. Their forbidden_decisions did not stop them duplicating a category question bank or
-- standing in for the category specialist, so nothing but convention kept a broad specialist from
-- becoming a second, contradictory answer to a question an overlay already owns.
update org_role set
  responsibilities = responsibilities
    || ' Purpose is CROSS-CATEGORY and MULTI-TRADE analysis: the question that spans two or more '
       'of the 86 categories, or that no single category overlay owns. Supplements the overlays; '
       'never replaces one.',
  forbidden_decisions = array[
    'duplicating a category question bank that an overlay already owns',
    'replacing the category specialist for a single-category question',
    'dispatching to suppliers',
    'overriding an authoritative category rule',
    'silently activating a route'],
  activation_conditions =
    'An inquiry spans more than one of the 86 categories, or raises a multi-trade technical '
    'conflict that no single category overlay owns. Invoked as a tool by the Inquiry Router or the '
    'RFQ Qualification Manager - never on a schedule, never continuously.'
where role_id in ('spec_mep', 'spec_construction', 'spec_fitout', 'spec_industrial');

-- =============================================================================================
-- 4. ORGANISATION DESIGN LEAD → People & Company Operations
-- =============================================================================================
-- Already on_demand_specialist. Only the department and the reporting line move: organisation
-- design is a workforce function, and it now sits beside the workforce director that commissions
-- it. It stays invocable by the CEO, Chief of Staff, COO and Chief Performance Officer.
update org_role set
  primary_department_id = 'people_ops',
  -- Named as hr_director here on purpose: section 7 renames that role_id and repoints every
  -- manager_role_id that references it, so this line lands on the workforce director either way.
  -- Naming the new id before section 7 creates it would violate org_role_manager_role_id_fkey.
  manager_role_id       = 'hr_director',
  activation_conditions =
    'Invoked on demand by the CEO, the Chief of Staff, the COO, the Chief Performance Officer or '
    'the Agent Workforce & Capability Director - a monthly organisation review, a department '
    'saturating its task ceiling, or a capability gap that needs a structural answer. Never '
    'continuously active.'
where role_id = 'organization_designer';

update org_agents set department = 'people_ops', manager_key = 'hr_director'
where agent_key = 'org_designer';

-- =============================================================================================
-- 5. VISUAL DESIGN SPECIALIST  (was: Visual Design Director)
-- =============================================================================================
-- It creates. It does not hold final approval over its own work. Two concrete changes beyond the
-- title: authority drops from execute_low to advisory, and artifact.review is REMOVED from its
-- tools. The second is the one that matters — on 15 Aug the artifact review path defaulted its
-- reviewer to this agent's own runtime key, so the designer was the default reviewer of its own
-- artifact. org_align_01 fixed the guard; removing the tool removes the capability.
update org_role set
  display_name    = 'Visual Design Specialist',
  authority_level = 'advisory',
  responsibilities =
    'Produces creatives from brand_assets and holds visual direction for an APPROVED brief: logo, '
    'colour, typography, composition. Creates; does not approve. Every asset it produces leaves '
    'through someone else''s approval.',
  owned_decisions = array[
    'visual direction within an approved brief',
    'rejecting an asset on design grounds'],
  forbidden_decisions = array[
    'approving the rendered artifact it produced, under any alias',
    'publishing without artifact review',
    'brand, campaign, audience or message approval - that is the Brand & Creative Manager',
    'privacy or supplier/customer safety approval - that is the Marketplace Content & Privacy Reviewer',
    'approving the rendered artifact''s alignment, crop, text, logo, dimensions or safe zones - '
      'that is the AI Quality Assurance Reviewer or the approved artifact-QA path'],
  tools = array['boost_recommend', 'content_calendar', 'content_draft', 'content_revise',
                'outreach_draft', 'seo_produce', 'video.produce'],
  rationale =
    'Redefined from Visual Design Director on 15 Aug 2026. artifact_review defaulted reviewer_agent '
    'to ''marketing_design'', this agent''s own runtime key, and both self-review guards compared '
    'identities raw - so ''visual_design'' reviewing ''marketing_design'' read as independent. The '
    'guards now resolve; this removes the tool as well as the loophole.'
where role_id = 'visual_design';

update org_agents set title = 'Visual Design Specialist' where agent_key = 'marketing_design';

insert into org_agent_alias (alias, agent_key, reason) values
  ('Visual Design Director',    'marketing_design', 'previous job title, kept addressable by the 15 Aug 2026 workflow alignment'),
  ('Visual Design Specialist',  'marketing_design', 'current job title')
on conflict (alias) do nothing;

-- =============================================================================================
-- 6. TEST AUTOMATION ENGINEER  (was titled: Test Automation Reviewer)
-- =============================================================================================
-- The role_id was already test_automation_engineer; the title, the class and the authority still
-- said reviewer. It held stop_authority and owned "blocking a release on failing or missing tests"
-- — the same decision quality_and_release_director owns. A test author holding the release veto is
-- the author reviewing its own evidence. It builds and runs the suites; the director decides.
update org_role set
  display_name    = 'Test Automation Engineer',
  runtime_mode    = 'event_driven_operator',
  authority_level = 'execute_low',
  responsibilities =
    'Builds and runs the automated suites: regression, smoke, money tests and end-to-end. A check '
    'that passes when the thing it checks is broken is worse than no check, so each one is proven '
    'to fail on the defect it claims to catch. Produces the quality evidence; does not rule on it.',
  owned_decisions = array[
    'test coverage adequacy',
    'the pass/fail result a suite reports',
    'refusing to weaken a check to make it pass'],
  forbidden_decisions = array[
    'release go/no-go - that belongs to the QA & Release Management Director',
    'being the only reviewer of the quality evidence it produced',
    'writing the feature it tests and then passing it',
    'weakening a check to make it pass'],
  output_contracts = array['test_verdict', 'coverage_evidence'],
  rationale =
    'Reclassified 15 Aug 2026. Held stop_authority as an independent_reviewer and owned "blocking '
    'a release", which is the QA & Release Management Director''s decision. Test authors cannot be '
    'the only final reviewers of the quality evidence they produce.'
where role_id = 'test_automation_engineer';

update org_agents set title = 'Test Automation Engineer' where agent_key = 'test_automation_eng';

insert into org_agent_alias (alias, agent_key, reason) values
  ('Test Automation Reviewer', 'test_automation_eng', 'previous job title, kept addressable by the 15 Aug 2026 workflow alignment')
on conflict (alias) do nothing;

-- =============================================================================================
-- 7. AGENT WORKFORCE & CAPABILITY DIRECTOR  (was: HR Director)
-- =============================================================================================
-- This seat manages an AI workforce, and "HR Director" described a human-resources function that
-- is a small part of what it actually does. Culture & Performance, Learning & Development and
-- Recruitment are retained under it, on scheduled or on-demand modes rather than continuously.
create temp table _seat as select * from org_role where role_id = 'hr_director';
update org_role set runtime_agent_key = null where role_id = 'hr_director';
update _seat set role_id = 'agent_workforce_capability_director';
insert into org_role select * from _seat;

update org_role           set manager_role_id = 'agent_workforce_capability_director' where manager_role_id = 'hr_director';
update org_role_alias     set role_id         = 'agent_workforce_capability_director' where role_id         = 'hr_director';
update org_role_committee set role_id         = 'agent_workforce_capability_director' where role_id         = 'hr_director';
delete from org_role where role_id = 'hr_director';
drop table _seat;

update org_role set
  display_name    = 'Agent Workforce & Capability Director',
  primary_department_id = 'people_ops',
  manager_role_id = 'chief_operating_officer',
  responsibilities =
    'Owns the canonical role capabilities and the shape of the workforce: workforce planning, the '
    'performance framework, role lifecycle, capability gaps and their remediation, restriction and '
    'reactivation of an underperforming role, agent-role creation where the work needs a seat that '
    'does not exist, and human recruitment where a human is genuinely required.',
  activation_conditions =
    'A capability gap is measured, a role fails its evaluation suite, a department saturates its '
    'task ceiling, a new seat is proposed, or the monthly workforce review falls due. On demand '
    'and on cadence - not continuously active.',
  owned_decisions = array[
    'canonical role capabilities and the role lifecycle',
    'workforce planning and the performance framework',
    'restricting or reactivating a role on measured capability',
    'commissioning a new agent role'],
  forbidden_decisions = array[
    'approving its own capability assessment',
    'changing founder-reserved commercial policy',
    'spending above the approved budget',
    'release or deployment decisions'],
  rationale =
    'Renamed from HR Director on 15 Aug 2026. The seat governs an AI workforce - role capabilities, '
    'lifecycle, capability gaps and remediation - and the old title described the smallest part of '
    'that. Culture & Performance, Learning & Development and Recruitment are retained under it.'
where role_id = 'agent_workforce_capability_director';

update org_agents set title = 'Agent Workforce & Capability Director' where agent_key = 'hr_director';

insert into org_agent_alias (alias, agent_key, reason) values
  ('HR Director',                          'hr_director', 'previous job title, kept addressable by the 15 Aug 2026 workflow alignment'),
  ('agent_workforce_capability_director',  'hr_director', 'canonical role id for Agent Workforce & Capability Director')
on conflict (alias) do nothing;

insert into org_role_alias (alias, role_id, kind, reason) values
  ('hr_director', 'agent_workforce_capability_director', 'legacy_role_id', 'renamed 15 Aug 2026'),
  ('HR Director', 'agent_workforce_capability_director', 'title',          'previous title, renamed 15 Aug 2026')
on conflict (alias) do nothing;

-- =============================================================================================
-- 8. UAE TAX — an extension of the Financial Controller's scope, not a new employee
-- =============================================================================================
-- The instruction is explicit: do not create another persistent agent merely to increase the role
-- count. The overlay architecture already exists - runtime_mode = 'knowledge_overlay', no runtime
-- agent, invoked on demand - and 86 rows use it. This adds one functional overlay in that same
-- shape and points the Financial Controller at it.
update org_role set
  responsibilities = responsibilities ||
    ' UAE tax is within approved scope: VAT, corporate-tax coordination, invoice tax compliance, '
    'revenue recognition, taxable-supply treatment, statutory reconciliation, the filing calendar '
    'and supporting-document controls. Where a question turns on current law or a filing position, '
    'escalate to a current authoritative source or an external professional rather than answering '
    'from memory.',
  knowledge_scopes = (select array(select distinct unnest(knowledge_scopes || array['tax_uae'])))
where role_id = 'financial_controller';

insert into org_role (
  role_id, display_name, primary_department_id, manager_role_id, runtime_mode, runtime_agent_key,
  responsibilities, owned_decisions, forbidden_decisions, activation_conditions,
  required_inputs, output_contracts, tools, knowledge_scopes, authority_level,
  handoff_targets, escalation_targets, model_policy, status, rationale)
values (
  'tax_overlay_uae', 'UAE Tax Overlay', 'finance', 'financial_controller',
  'knowledge_overlay', null,
  'On-demand UAE tax knowledge: VAT registration and rates, corporate tax, invoice tax compliance, '
  'taxable-supply treatment, revenue recognition, statutory reconciliation, the filing calendar and '
  'the supporting-document controls each filing needs. Advisory only - it informs a decision the '
  'Financial Controller or the CFO makes.',
  array['the tax treatment recommended for a transaction or filing question'],
  array['filing a return', 'committing the company to a tax position without the CFO',
        'answering from memory where the answer turns on current law - escalate to an authoritative '
        'source or an external professional'],
  'A finance routine, the Financial Controller or the CFO raises a UAE VAT, corporate tax, invoice '
  'compliance, revenue recognition or statutory reconciliation question. Never scheduled.',
  array['the transaction, invoice or filing question in scope'],
  array['tax_position_note'],
  array['compliance_check', 'money_verify', 'legal_review'],
  array['tax_uae', 'finance', 'legal_uae', 'uae_authorities', 'company', 'constitution'],
  'advisory',
  array['financial_controller'], array['cfo', 'general_counsel'],
  'routine_employee_reasoning', 'active',
  'Added 15 Aug 2026 as an overlay, not an employee: the instruction asks for UAE tax responsibility '
  'to be explicit without another persistent agent. Uses the same knowledge_overlay shape as the 86 '
  'category overlays - no runtime agent, invoked on demand.')
on conflict (role_id) do nothing;

commit;
