-- ORG ALIGNMENT 03 — one accountable owner per step, six distinct reviewer scopes, and a
-- founder-reserved list a future role cannot be handed by accident.
--
-- MEASURED BEFORE THIS FILE (production, 15 Aug 2026, zero model cost):
--
--   * workflow_step has 165 steps over 19 workflows. 61 of 66 distinct actor_role values resolve
--     to an employee. The five that do not are 'owner' and 'Director' (deliberate per-run
--     placeholders in employee_task), 'Content Strategist', 'Supplier & Customer Analyst', and
--     'domain specialist'.
--   * 'domain specialist' is the actor on rfq_handling #3 and #5. #5 is "Select suppliers" — the
--     step that decides which suppliers receive a customer's RFQ. It has never had an owner.
--   * rfq_handling #6 names 'Procurement Director'. `procurement` is a merged-away department key.
--   * rfq_handling has no document-processing step, no readiness-scoring step, no supplier-safe
--     payload approval step and no message-delivery step, so four of the founder's named owners —
--     Document Intelligence Manager, Inquiry Quality & Scoring Analyst, Marketplace Content &
--     Privacy Reviewer, Lifecycle Channel Operations Specialist — appeared in no workflow at all.
--     The role caller census found them among 20 roles with zero callers on any of six surfaces.
--   * rfq_handling has 0 runs (workflow_run), so rewriting its steps cannot orphan a step run.
--
-- WHAT AN actor_role MEANS HERE. It is the ACCOUNTABLE OWNER of the step — always a real,
-- resolvable employee, never an overlay and never a placeholder. Where the founder's chain names a
-- category overlay or a broad specialist, the overlay is the knowledge the owner invokes, and the
-- step text says so. An overlay has no runtime agent and cannot be accountable for anything;
-- pretending otherwise is how "domain specialist" came to own supplier selection.

begin;

-- =============================================================================================
-- A. FOUNDER-RESERVED DECISIONS — a list, and a guard that no role can be handed one
-- =============================================================================================
-- The settings channel is already correct and stays as it is. EXISTING_BETTER_KEEP:
-- fn_founder_apply_setting only accepts keys returned by fn_founder_settings(), and those 16 keys
-- are operational caps and switches — invite_daily_cap, match_max_fanout, wa_daily_cap and so on.
-- Not one commercial reserved item is on that list, and the refusal text says so out loud.
--
-- What did NOT exist is the list itself, in a form anything can test against. Without it,
-- "founder-reserved policies are enforced" is a sentence in a document, and a future role can be
-- given `owned_decisions = array['set the reveal fee']` with nothing objecting.
create table if not exists public.founder_reserved_decision (
  decision_key text primary key,
  description  text not null,
  match_any    text[] not null,   -- lowercase substrings that identify this decision in free text
  created_at   timestamptz not null default now()
);

comment on table public.founder_reserved_decision is
  'Decisions the founder reserves to himself. Agents may optimise within these boundaries and may '
  'never make the decision. Enforced by trg_org_role_no_reserved_decision on org_role.owned_decisions.';

insert into public.founder_reserved_decision (decision_key, description, match_any) values
  ('reveal_fee_pct',            'The reveal-fee percentage charged to a customer.',
      array['reveal fee', 'reveal-fee']),
  ('supplier_subscription_price','The price of a supplier subscription.',
      array['subscription price', 'subscription fee', 'price of a supplier subscription']),
  ('subscription_start_date',   'The date supplier subscriptions begin to be charged.',
      array['subscription start', 'start date for subscription', 'subscription commencement']),
  ('founding_supplier_exemption','Which suppliers are exempt as founding suppliers, and for how long.',
      array['founding supplier', 'founding-supplier']),
  ('ownership_and_equity',      'Ownership and equity in the company.',
      array['equity', 'ownership stake', 'shareholding', 'cap table']),
  ('fundraising',               'Raising capital, and on what terms.',
      array['fundraising', 'raise capital', 'investment round', 'term sheet']),
  ('market_expansion',          'Entering a new market or country.',
      array['market expansion', 'country expansion', 'enter a new market', 'new country']),
  ('material_policy_change',    'A material change to company policy.',
      array['material company policy', 'material policy change', 'change company policy']),
  ('spend_above_budget',        'Spending above an approved budget.',
      array['above the approved budget', 'above approved budget', 'exceed the budget', 'overspend']),
  ('unapproved_legal_commitment','Committing the company legally without approval.',
      array['unapproved legal commitment', 'commit the company legally', 'sign on behalf of the company']),
  ('founder_commercial_rules',  'Permanent changes to founder-defined commercial rules.',
      array['founder-defined commercial', 'permanent change to commercial', 'founder commercial rule'])
on conflict (decision_key) do update
  set description = excluded.description, match_any = excluded.match_any;

create or replace function public.trg_org_role_no_reserved_decision()
returns trigger
language plpgsql
as $function$
declare v_owned text; v_hit record;
begin
  if new.owned_decisions is null then return new; end if;
  v_owned := lower(array_to_string(new.owned_decisions, ' | '));

  for v_hit in
    select d.decision_key, d.description, m.needle
      from public.founder_reserved_decision d, unnest(d.match_any) m(needle)
     where position(m.needle in v_owned) > 0
  loop
    raise exception
      'role "%" cannot OWN a founder-reserved decision: % (matched "%" in owned_decisions). %',
      new.role_id, v_hit.description, v_hit.needle,
      'Agents optimise within founder-reserved boundaries; they do not set them. Put it in '
      'forbidden_decisions, or escalate to the founder.'
      using errcode = 'check_violation';
  end loop;
  return new;
end $function$;

-- a00_ prefix: Postgres fires BEFORE triggers in NAME order, and this one must reject before any
-- later trigger normalises the array it is reading.
drop trigger if exists a00_org_role_no_reserved_decision on public.org_role;
create trigger a00_org_role_no_reserved_decision
  before insert or update of owned_decisions on public.org_role
  for each row execute function public.trg_org_role_no_reserved_decision();

-- =============================================================================================
-- B. SIX REVIEWERS, SIX SCOPES THAT DO NOT OVERLAP
-- =============================================================================================
-- The instruction names six review scopes and asks that they be distinct. Before this, four of the
-- six described themselves in words broad enough to cover another's territory, and the Test
-- Automation seat held a fifth (release go/no-go) that org_align_02 has already returned to the
-- QA & Release Management Director.
update org_role set
  responsibilities =
    'Evaluates a proposed model, prompt, retrieval or routing change OFFLINE, against a held-out '
    'set, before it reaches a workflow. Judges the change, not the company.',
  owned_decisions = array[
    'whether a model, prompt, retrieval or routing change is better than what it replaces',
    'blocking a change whose offline evaluation regresses'],
  forbidden_decisions = array[
    'agent behaviour inside a live QuotesDone workflow - that is the AI Quality Assurance Reviewer',
    'release go/no-go - that is the QA & Release Management Director',
    'authoring the change it evaluates',
    'approving its own evaluation']
where role_id = 'model_evaluator';

update org_role set
  responsibilities =
    'Judges how agents actually BEHAVE inside complete QuotesDone workflows: did the right '
    'specialist get invoked, was knowledge retrieved, was the decision trace filled, was the '
    'handoff explicit, was the output truncated. Also the approved artifact-QA path for a rendered '
    'artifact: alignment, crop, text, logo, dimensions, safe zones and technical quality.',
  owned_decisions = array[
    'whether an agent behaved correctly within a live workflow',
    'the artifact-QA verdict on a rendered artifact',
    'blocking an agent behaviour change on observed workflow behaviour'],
  forbidden_decisions = array[
    'offline model, prompt, retrieval or routing evaluation - that is the Model Evaluation Reviewer',
    'release go/no-go - that is the QA & Release Management Director',
    'brand, campaign, audience or message approval - that is the Brand & Creative Manager',
    'privacy or supplier-safety approval - that is the Marketplace Content & Privacy Reviewer',
    'reviewing an artifact it produced, under any alias']
where role_id = 'ai_quality_reviewer';

update org_role set
  responsibilities =
    'Holds the final system and release go/no-go. Reads the evidence others produce - test results, '
    'offline evaluations, workflow behaviour, security findings - and decides whether a change '
    'ships. Produces none of that evidence itself.',
  owned_decisions = array[
    'final release go/no-go',
    'blocking a release on any gate',
    'declaring an incident release-blocking'],
  forbidden_decisions = array[
    'writing the tests whose results it rules on',
    'offline model evaluation - that is the Model Evaluation Reviewer',
    'per-artifact privacy approval - that is the Marketplace Content & Privacy Reviewer',
    'approving a release for a change it authored']
where role_id = 'quality_and_release_director';

update org_role set
  responsibilities =
    'Rules on KNOWLEDGE RECORDS: validity, source quality, contradiction against what the company '
    'already holds, and freshness against the review date. Validates the record, not the agent that '
    'used it and not the workflow it was used in.',
  owned_decisions = array[
    'whether a knowledge record is valid, sourced and current',
    'quarantining a record that contradicts a better-sourced one',
    'decaying confidence past a review date'],
  forbidden_decisions = array[
    'agent behaviour inside a workflow - that is the AI Quality Assurance Reviewer',
    'legal or policy compliance - that is the Compliance & Privacy Officer',
    'authoring the knowledge record it validates',
    'release go/no-go']
where role_id = 'knowledge_validator';

update org_role set
  responsibilities =
    'Decides questions of LEGAL AND POLICY COMPLIANCE: PDPL and data protection, regulatory '
    'obligation, retention, consent, and whether a proposed action is permitted at all. Decides '
    'whether something MAY be done; not whether a particular artifact did it correctly.',
  owned_decisions = array[
    'whether an action is legally and policy-compliant',
    'data-protection and retention decisions',
    'blocking an action on a compliance finding'],
  forbidden_decisions = array[
    'per-artifact supplier-safe payload approval - that is the Marketplace Content & Privacy Reviewer',
    'knowledge record validity - that is the Knowledge Validator',
    'release go/no-go',
    'approving a compliance position it authored']
where role_id = 'compliance_and_privacy_officer';

-- marketplace_content_privacy_reviewer's scope was set in org_align_02 and is the sixth: the
-- ACTUAL supplier-facing payload and artefact. Nothing to restate here.

-- =============================================================================================
-- C. THE CUSTOMER-TO-QUOTATION CHAIN — every step owned, in the founder's order
-- =============================================================================================
-- rfq_handling has 0 runs, so this replaces its steps rather than versioning around them.
delete from workflow_step where workflow_key = 'rfq_handling';

insert into workflow_step (workflow_key, step_no, step, actor_role, action_class, gate) values
 ('rfq_handling',  1, 'Registration and initial guidance: the customer has an account and knows what to ask for',
                      'customer_onboarding',                  'coordinate',       'none'),
 ('rfq_handling',  2, 'Inquiry conversation and completeness: every mandatory answer present, no unresolved conflict',
                      'rfq_qualification_manager',            'qualify_inquiry',  'none'),
 ('rfq_handling',  3, 'Route candidates: resolve the inquiry to its category and primary trade',
                      'inquiry_router',                       'route_category',   'none'),
 ('rfq_handling',  4, 'Technical qualification against the matching category overlay (one of the 86, on demand)',
                      'inquiry_router',                       'qualify_inquiry',  'none'),
 ('rfq_handling',  5, 'Multi-category technical conflict: invoke the broad domain specialist for the primary trade (MEP, construction, fit-out or industrial) only when no single overlay owns the question',
                      'rfq_qualification_manager',            'coordinate',       'none'),
 ('rfq_handling',  6, 'Document processing: classify and extract what the customer attached',
                      -- there is no doc_extract executor; coordinate is the generic class the
                      -- document path already uses, and the step text carries the meaning.
                      'document_intelligence_manager',        'coordinate',       'none'),
 ('rfq_handling',  7, 'BOQ and specification analysis, where a bill of quantities or a specification was supplied',
                      'boq_analyst',                          'recommend',        'none'),
 ('rfq_handling',  8, 'Drawing and CAD analysis, where a drawing was supplied',
                      'drawing_analyst',                      'recommend',        'none'),
 ('rfq_handling',  9, 'Quality and readiness assessment: is this inquiry good enough to put in front of a supplier?',
                      'inquiry_quality_analyst',              'recommend',        'none'),
 ('rfq_handling', 10, 'Supplier-safe payload and file approval: inspect the ACTUAL payload, files and redacted drawings for customer identifiers and unapproved revisions',
                      'marketplace_content_privacy_reviewer', 'compliance_check', 'review'),
 ('rfq_handling', 11, 'Supplier eligibility, matching, idempotent assignment and one notification per selected supplier, with a recorded reason for every selection and exclusion',
                      'supplier_matching_dispatch_operator',  'match_inquiry',    'none'),
 ('rfq_handling', 12, 'Message delivery: the notification actually leaves, on the channel the supplier consented to',
                      'lifecycle_channel_operations',         'coordinate',       'none'),
 ('rfq_handling', 13, 'Receive quotations and normalise them for comparison',
                      'quote_evaluation',                     'coordinate',       'none'),
 ('rfq_handling', 14, 'Technical comparison, invoking the category overlay and a broad specialist only where the comparison needs one',
                      'quote_evaluation',                     'compare_quotes',   'none'),
 -- was 'Procurement Director'. `procurement` is a merged-away department key; the live head of
 -- Marketplace & Supplier Network is the Marketplace Director.
 ('rfq_handling', 15, 'Recommend the winning quotation to the customer',
                      'marketplace_director',                 'recommend',        'dept_head'),
 ('rfq_handling', 16, 'Keep the customer moving to a decision, and close the inquiry',
                      'rfq_success',                          'coordinate',       'none'),
 ('rfq_handling', 17, 'Collect feedback from both sides',
                      'customer_success_director',            'coordinate',       'none'),
 ('rfq_handling', 18, 'Trace what went wrong to the employee, prompt, knowledge source or rule, and correct it',
                      'process_improvement_manager',          'knowledge_acquire','none');

-- The three unresolvable actor_role values that are NOT deliberate placeholders. 'owner' and
-- 'Director' in employee_task stay: they are resolved per run against the task's own owner and its
-- department head, which is what that generic loop means. These three were simply wrong.
update workflow_step set actor_role = 'content_strategy_and_copy'   where actor_role = 'Content Strategist';
update workflow_step set actor_role = 'supplier_intelligence_analyst' where actor_role = 'Supplier & Customer Analyst';

-- Supplier journey — the founder's chain, onto the workflow that already models it.
delete from workflow_step where workflow_key = 'supplier_onboarding';
insert into workflow_step (workflow_key, step_no, step, actor_role, action_class, gate) values
 ('supplier_onboarding', 1, 'Supplier registration received',
     'supplier_onboarding_specialist', 'coordinate',            'none'),
 ('supplier_onboarding', 2, 'Verify trade licence and the documents behind it',
     'supplier_verification',          'supplier_verify',       'none'),
 ('supplier_onboarding', 3, 'Verify certifications and declared capability',
     'supplier_verification',          'capability_review',     'none'),
 ('supplier_onboarding', 4, 'Compliance screen before anything is activated',
     'compliance_and_privacy_officer', 'compliance_check',      'review'),
 ('supplier_onboarding', 5, 'Approve or reject the supplier',
     'supplier_verification',          'supplier_approve_clean','dept_head'),
 ('supplier_onboarding', 6, 'Activate, coach, and confirm the supplier can receive an inquiry',
     'supplier_onboarding_specialist', 'coordinate',            'none'),
 ('supplier_onboarding', 7, 'Check the effect on category coverage and liquidity',
     'supplier_coverage',              'recommend',             'none'),
 ('supplier_onboarding', 8, 'Watch for disengagement and act on it',
     'supplier_retention',             'nudge',                 'none'),
 ('supplier_onboarding', 9, 'Measure and learn',
     'process_improvement_manager',    'knowledge_acquire',     'none');

commit;
