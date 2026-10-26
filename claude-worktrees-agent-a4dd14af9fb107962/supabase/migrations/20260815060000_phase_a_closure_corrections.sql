-- PHASE A CLOSURE CORRECTIONS — the five items the founder named on 15 Aug 2026.
--
-- ORGANIZATIONAL DESIGN ONLY. No knowledge, tools, prompts, model policy, decision traces, KPI
-- runtime, provider connection, synthetic data or certification. No model call of any kind.
--
-- One implicit transaction, as before: any assertion that raises takes the whole file with it.
-- Rehearsed in an aborted production transaction before being applied.
--
-- ROLLBACK: scripts/sql/phase_a_closure_rollback.sql

-- org_role is read by every context assembly in the company; an ALTER that waits behind a long
-- transaction blocks reads, writes and schema changes for as long as it waits.
set lock_timeout = '5s';
set statement_timeout = '60s';

-- ============================================================================================
-- PRECONDITIONS
-- ============================================================================================
do $$
declare v int;
begin
  select count(*) into v from public.org_role where status='active' and runtime_mode <> 'knowledge_overlay';
  if v <> 90 then raise exception 'PRECONDITION: expected 90 accountable roles, found %', v; end if;
  select count(*) into v from public.org_role where status='active' and runtime_mode='knowledge_overlay';
  if v <> 86 then raise exception 'PRECONDITION: expected 86 category overlays, found %', v; end if;
  if not exists (select 1 from public.org_role where role_id='product_ux_designer' and status='active'
                   and primary_department_id='product_eng' and manager_role_id='product_manager')
    then raise exception 'PRECONDITION: product_ux_designer is not where this file expects it'; end if;
  if not exists (select 1 from public.org_role where role_id='cto' and display_name='Chief Technology Officer')
    then raise exception 'PRECONDITION: cto does not carry the title this file retitles'; end if;
  if not exists (select 1 from public.org_workflow_ownership where workflow_id='W22' and accountable_role_id='product_manager')
    then raise exception 'PRECONDITION: W22 is not owned by product_manager'; end if;
end $$;

-- ============================================================================================
-- 1. PRODUCT/UX DESIGNER — the full organizational definition, and the deferral made explicit
-- ============================================================================================

-- RUNTIME DEFERRAL IS A DECLARATION ON THE ROLE, NOT A DEACTIVATED EMPLOYEE, AND THE REASON WAS
-- MEASURED RATHER THAN ASSUMED. The obvious way to express "organizationally defined but
-- runtime-disabled" was org_agents.active = false, which is the estate's existing mechanism. It is
-- the wrong one here: fn_agent_context_v3 still assembles a full context for an inactive employee
-- (checked directly — it returns no error for gov_relations_mgr, which is inactive), and
-- org_reorg_behaviour asserts that an inactive employee WITHOUT a surviving alias must not. The UX
-- designer has no alias to resolve to, so standing its employee down would have re-broken a check
-- this session already repaired once.
--
-- So the deferral is stated where it belongs: on the role, as a fact about phase, not by breaking
-- the runtime. It carries no behaviour today; the later phase that grants tools, knowledge, a KPI
-- binding and a model policy flips it. FALSE does not mean optional — it means not yet activated.
alter table public.org_role add column if not exists runtime_enabled boolean not null default true;
comment on column public.org_role.runtime_enabled is
  'Phase A: the role is organizationally defined and canonical. FALSE means it is deliberately not yet runtime-activated - no tools, no knowledge scope, no KPI binding, no model policy - and the later phase that activates it flips this. It never means the role is optional or retained to make a count.';

update public.org_role set
  display_name = 'Product/UX Designer',
  primary_department_id = 'product_eng',
  manager_role_id = 'product_manager',
  runtime_mode = 'on_demand_specialist',
  necessity_status = 'REQUIRED_ON_DEMAND',
  responsibilities = 'Own the design of usable customer, supplier, admin, inquiry, onboarding, comparison, Arabic/RTL and mobile experiences.',
  necessity_reason = 'Own the design of usable customer, supplier, admin, inquiry, onboarding, comparison, Arabic/RTL and mobile experiences.',
  owned_decisions = array[
    'user journey design',
    'interaction design',
    'information architecture',
    'wireframes and prototypes',
    'usability requirements',
    'accessibility requirements',
    'Arabic/RTL UX requirements',
    'design-system specifications',
    'UX acceptance criteria'
  ]::text[],
  forbidden_decisions = array[
    'product roadmap priority',
    'engineering architecture',
    'production release approval',
    'brand campaign approval',
    'privacy approval',
    'code approval',
    'founder commercial policy'
  ]::text[],
  output_contracts = array[
    'user-flow specification',
    'wireframe/prototype',
    'interaction specification',
    'accessibility and RTL requirements',
    'UX acceptance criteria'
  ]::text[],
  activation_conditions = 'A product requirement, a usability problem, or an Arabic/RTL or accessibility gap in a customer, supplier or admin surface.',
  runtime_enabled = false,
  rationale = 'Phase A: organizationally defined in full and deliberately NOT runtime-activated. Tools, knowledge scope, KPI binding and model policy are later-phase work; runtime_enabled is false until then.',
  updated_at = now()
 where role_id = 'product_ux_designer';

-- ============================================================================================
-- THE ORGANIZATIONAL STEP REGISTER. org_workflow_ownership answers "who is accountable for this
-- workflow"; it cannot answer "who owns experience design within it". workflow_step answers that
-- for the 19 RUNTIME workflows and W22 is not one of them — it is an organizational workflow, and
-- putting it there would mean creating a runtime workflow row, which is activation.
--
-- So: the same question, at the organizational level. One accountable role per step, enforced by
-- the primary key. Seeded with W22 because that is the sequence the founder specified; the other
-- 29 organizational workflows carry owner-level accountability only, and that is stated in the
-- Phase A documents rather than left for someone to discover.
-- ============================================================================================
create table if not exists public.org_workflow_step (
  workflow_id          text not null references public.org_workflow_ownership(workflow_id) on delete cascade,
  step_no              bigint not null,   -- bigint at the linter's insistence; seven steps will not exhaust an int, but the rule is cheap to honour
  step                 text not null,
  accountable_role_id  text not null references public.org_role(role_id),
  created_at           timestamptz not null default now(),
  primary key (workflow_id, step_no)
);
comment on table public.org_workflow_step is
  'Phase A: ordered step ownership inside an ORGANIZATIONAL workflow. One accountable role per step, by primary key. Distinct from workflow_step, which sequences the 19 runtime workflows.';
alter table public.org_workflow_step enable row level security;
revoke all on public.org_workflow_step from anon, authenticated;

-- W22 — Product discovery to delivery. The chain the founder specified, in his ordering: the
-- Product Manager decides WHAT and in what order; the UX Designer owns HOW it is experienced and
-- what "usable" means for it; the Engineering Manager owns that it is delivered; the engineers
-- build; Test Automation proves the behaviour; and the release gate is held OUTSIDE the department
-- that ships.
--
-- SEVEN STEPS FOR SIX LINES, AND THE SPLIT IS DELIBERATE. He wrote "Backend/Frontend Engineers
-- implement" as one line. Two roles on one step is exactly the multiply-owned step that Phase A
-- forbids — "contributors do not become co-accountable owners" — so implementation is two steps
-- with one accountable role each. The sequence and the accountability are unchanged; only the
-- shared line is separated so that each half has a name against it.
insert into public.org_workflow_step (workflow_id, step_no, step, accountable_role_id) values
  ('W22', 1, 'Define and prioritize the requirement', 'product_manager'),
  ('W22', 2, 'Own experience design and UX acceptance criteria', 'product_ux_designer'),
  ('W22', 3, 'Own implementation delivery', 'engineering_manager'),
  ('W22', 4, 'Implement the backend', 'backend_engineer'),
  ('W22', 5, 'Implement the frontend', 'frontend_engineer'),
  ('W22', 6, 'Verify behaviour against the acceptance criteria', 'test_automation_engineer'),
  ('W22', 7, 'Release go/no-go', 'quality_and_release_director')
on conflict (workflow_id, step_no) do nothing;

-- ============================================================================================
-- THE CONTRIBUTOR LISTS NAMED 38 PEOPLE WHO DO NOT EXIST — A DEFECT I INTRODUCED.
--
-- Found by fn_phase_a_organization_violations the first time it ran, inside the aborted
-- rehearsal, against fraud_analyst: an active independent reviewer with no workflow, no step,
-- nothing. It is a contributor to W17 "Refund, dispute and fraud" — recorded there as
-- 'fraud_reviewer', which is the PACKAGE's canonical id and matches no role in this database.
--
-- When the first Phase A migration wrote org_workflow_ownership it mapped accountable_role_id
-- and independent_reviewer through the crosswalk and wrote CONTRIBUTORS straight from the CSV.
-- 38 of 100 contributor entries therefore named nobody. Nothing failed, because nothing reads
-- the column yet — which is exactly how this estate's recurring defect always looks.
--
-- 33 resolve through the crosswalk. The other five are not roles at all: the package writes
-- "department heads", "category overlays" and "broad domain specialists" as CLASSES in that
-- column, and they are normalised to one plural form each rather than forced onto a role_id
-- they do not have. The check below accepts a contributor that is an active role OR one of
-- those three declared class terms, and refuses anything else.
-- ============================================================================================
update public.org_workflow_ownership set contributors = array_replace(contributors, 'account_manager', 'account_management') where 'account_manager' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'accounts_payable_specialist', 'accounts_payable') where 'accounts_payable_specialist' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'agent_prompt_engineer', 'prompt_engineer') where 'agent_prompt_engineer' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'ai_quality_assurance_reviewer', 'ai_quality_reviewer') where 'ai_quality_assurance_reviewer' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'billing_reconciliation_specialist', 'billing_operations') where 'billing_reconciliation_specialist' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'boq_specification_analyst', 'boq_analyst') where 'boq_specification_analyst' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'brand_creative_manager', 'brand_and_creative') where 'brand_creative_manager' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'business_development_manager', 'business_development') where 'business_development_manager' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'category_knowledge_curator', 'category_curator') where 'category_knowledge_curator' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'collections_revenue_assurance_specialist', 'collections_and_revenue_assurance') where 'collections_revenue_assurance_specialist' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'compliance_privacy_officer', 'compliance_and_privacy_officer') where 'compliance_privacy_officer' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'content_strategy_copy_specialist', 'content_strategy_and_copy') where 'content_strategy_copy_specialist' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'crm_revenue_operations_manager', 'crm_and_revenue_operations') where 'crm_revenue_operations_manager' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'culture_performance_manager', 'culture_and_performance_manager') where 'culture_performance_manager' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'customer_retention_specialist', 'customer_retention') where 'customer_retention_specialist' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'customer_support_specialist', 'customer_support') where 'customer_support_specialist' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'drawing_cad_analyst', 'drawing_analyst') where 'drawing_cad_analyst' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'fp_a_analyst', 'fpna_analyst') where 'fp_a_analyst' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'fraud_reviewer', 'fraud_analyst') where 'fraud_reviewer' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'it_operations_site_reliability_engineer', 'it_operations_engineer') where 'it_operations_site_reliability_engineer' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'learning_development_manager', 'learning_and_development_manager') where 'learning_development_manager' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'lifecycle_channel_operations_specialist', 'lifecycle_channel_operations') where 'lifecycle_channel_operations_specialist' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'organisation_design_lead', 'organization_designer') where 'organisation_design_lead' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'payments_billing_manager', 'payments_and_billing_manager') where 'payments_billing_manager' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'product_optimisation_engineer', 'product_optimization_engineer') where 'product_optimisation_engineer' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'qa_release_management_director', 'quality_and_release_director') where 'qa_release_management_director' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'quote_evaluation_specialist', 'quote_evaluation') where 'quote_evaluation_specialist' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'rfq_success_specialist', 'rfq_success') where 'rfq_success_specialist' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'risk_governance_manager', 'risk_and_governance_manager') where 'risk_governance_manager' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'social_media_community_manager', 'social_media_and_community') where 'social_media_community_manager' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'taxonomy_governance_manager', 'taxonomy_manager') where 'taxonomy_governance_manager' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'trust_safety_manager', 'trust_and_safety_manager') where 'trust_safety_manager' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'visual_design_specialist', 'visual_design') where 'visual_design_specialist' = any(contributors);

-- the three class terms, one form each
update public.org_workflow_ownership set contributors = array_replace(contributors, 'broad domain specialist', 'broad domain specialists') where 'broad domain specialist' = any(contributors);
update public.org_workflow_ownership set contributors = array_replace(contributors, 'category overlay', 'category overlays') where 'category overlay' = any(contributors);

-- ============================================================================================
-- 2. THE PHASE-SPECIFIC VIOLATION CHECK
--
-- fn_org_role_violations IS NOT WEAKENED, REDEFINED OR TOUCHED. It keeps asking whether an
-- employee can WORK — tools, knowledge, a KPI binding, an active runtime agent — and it keeps
-- answering "not yet" for the Product/UX Designer. That answer is correct and it stays visible.
--
-- This is a second, narrower instrument asking a different question: is the ORGANISATION correct?
-- Two functions measuring two subjects, rather than one function bent until it returns zero.
-- ============================================================================================
create or replace function public.fn_phase_a_organization_violations()
returns table (rule text, subject text, detail text)
language sql
stable
as $fn$
  -- active canonical department
  select 'department_not_active', r.role_id, r.primary_department_id
    from public.org_role r
    left join public.org_departments d on d.dept_key = r.primary_department_id
   where r.status='active' and (d.dept_key is null or not d.active)
  union all
  -- primary manager, with the CEO/founder boundary as the single exception
  select 'no_primary_manager', r.role_id, 'manager_role_id is null'
    from public.org_role r
   where r.status='active' and r.runtime_mode <> 'knowledge_overlay'
     and r.manager_role_id is null and r.role_id <> 'ceo'
  union all
  select 'manager_not_active', r.role_id, r.manager_role_id
    from public.org_role r
   where r.status='active' and r.manager_role_id is not null
     and not exists (select 1 from public.org_role m where m.role_id=r.manager_role_id and m.status='active')
  union all
  -- role class: every active role declares which kind of thing it is
  select 'no_role_class', r.role_id, coalesce(r.runtime_mode,'(null)')
    from public.org_role r
   where r.status='active' and coalesce(r.runtime_mode,'') = ''
  union all
  -- necessity, and the reason for it
  select 'no_necessity_status', r.role_id, 'necessity_status is null'
    from public.org_role r
   where r.status='active' and coalesce(btrim(r.necessity_status),'') = ''
  union all
  -- organizational purpose
  select 'no_organizational_purpose', r.role_id, 'necessity_reason/responsibilities empty'
    from public.org_role r
   where r.status='active'
     and coalesce(length(btrim(r.necessity_reason)),0) < 10
     and coalesce(length(btrim(r.responsibilities)),0) < 10
  union all
  -- owned decisions. Overlays own category judgement rather than decisions, and say so in their
  -- necessity_reason, so the rule is scoped to accountable roles rather than relaxed for everyone.
  select 'no_owned_decisions', r.role_id, 'owned_decisions is empty'
    from public.org_role r
   where r.status='active' and r.runtime_mode <> 'knowledge_overlay'
     and coalesce(cardinality(r.owned_decisions),0) = 0
  union all
  -- forbidden decisions: a role with no stated limits has no limits
  select 'no_forbidden_decisions', r.role_id, 'forbidden_decisions is empty'
    from public.org_role r
   where r.status='active' and r.runtime_mode <> 'knowledge_overlay'
     and coalesce(cardinality(r.forbidden_decisions),0) = 0
  union all
  -- AT LEAST ONE WORKFLOW, REVIEW OR MANAGEMENT RESPONSIBILITY. This is also the rule that catches
  -- a role retained only to keep a count at 90: such a role manages nobody, owns no workflow,
  -- appears in no step and reviews nothing.
  select 'no_responsibility', r.role_id, 'owns no workflow, no step, manages nobody, reviews nothing'
    from public.org_role r
   where r.status='active' and r.runtime_mode <> 'knowledge_overlay'
     and not exists (select 1 from public.org_workflow_ownership o where o.accountable_role_id = r.role_id)
     and not exists (select 1 from public.org_workflow_step s where s.accountable_role_id = r.role_id)
     and not exists (select 1 from public.org_workflow_ownership o where o.independent_reviewer = r.role_id)
     and not exists (select 1 from public.org_role m where m.manager_role_id = r.role_id and m.status='active')
     and not exists (select 1 from public.workflow_step w where w.actor_role = r.role_id)
     and not exists (select 1 from public.employee_workflow e where e.agent_key = r.runtime_agent_key)
     -- contributing to a workflow IS a responsibility. It is not ACCOUNTABILITY, which is why
     -- contributors are still refused as owners two rules down, but a role that contributes to a
     -- workflow is doing something and is not a row kept to make a count.
     and not exists (select 1 from public.org_workflow_ownership o where r.role_id = any(o.contributors))
  union all
  -- a contributor must be an active role or one of the three declared class terms
  select 'contributor_resolves_to_nobody', o.workflow_id, c
    from public.org_workflow_ownership o, unnest(o.contributors) c
   where not exists (select 1 from public.org_role r where r.role_id = c and r.status='active')
     and c not in ('department heads', 'category overlays', 'broad domain specialists')
  union all
  -- creator/reviewer separation, at the workflow and at the role
  select 'owner_reviews_own_workflow', o.workflow_id, o.accountable_role_id
    from public.org_workflow_ownership o
   where o.independent_reviewer = o.accountable_role_id
  union all
  select 'contributor_is_owner', o.workflow_id, o.accountable_role_id
    from public.org_workflow_ownership o
   where o.accountable_role_id = any(o.contributors)
  union all
  -- founder boundary
  select 'owns_founder_reserved_decision', r.role_id, d.decision_key
    from public.org_role r, public.founder_reserved_decision d, unnest(d.match_any) m(needle)
   where r.status='active'
     and position(m.needle in lower(array_to_string(r.owned_decisions,' | '))) > 0
  union all
  -- reporting cycles, walked rather than assumed
  select 'reporting_cycle', u.root, 'chain does not terminate'
    from (
      with recursive up(root, cur, depth, path) as (
        select role_id, manager_role_id, 1, array[role_id] from public.org_role where status='active'
        union all
        select u.root, r.manager_role_id, u.depth+1, u.path || r.role_id
          from up u join public.org_role r on r.role_id = u.cur and r.status='active'
         where u.depth < 30 and not r.role_id = any(u.path))
      select distinct root from up where depth >= 30) u
  union all
  select 'self_management', r.role_id, r.manager_role_id
    from public.org_role r where r.status='active' and r.manager_role_id = r.role_id
  union all
  -- duplicate active role identity
  select 'duplicate_active_identity', x.runtime_agent_key, 'held by more than one active role'
    from (select runtime_agent_key from public.org_role
           where status='active' and runtime_agent_key is not null
           group by 1 having count(*) > 1) x
  union all
  -- unresolved historical alias, both directions
  select 'retired_role_resolves_to_nobody', r.role_id, 'no alias'
    from public.org_role r
   where r.status = 'retired'
     and not exists (select 1 from public.org_role_alias a where a.alias = r.role_id)
  union all
  select 'alias_points_at_a_dead_role', a.alias, a.role_id
    from public.org_role_alias a
    join public.org_role r on r.role_id = a.role_id
   where r.status <> 'active'
  union all
  -- overlay ownership
  select 'overlay_is_not_a_category_overlay', r.role_id, 'not category_overlay_NNN_'
    from public.org_role r
   where r.status='active' and r.runtime_mode='knowledge_overlay'
     and r.role_id !~ '^category_overlay_[0-9]{3}_'
  union all
  select 'overlay_holds_a_runtime_employee', r.role_id, r.runtime_agent_key
    from public.org_role r
   where r.status='active' and r.runtime_mode='knowledge_overlay' and r.runtime_agent_key is not null
  union all
  select 'overlay_owns_a_workflow', o.workflow_id, o.accountable_role_id
    from public.org_workflow_ownership o join public.org_role r on r.role_id = o.accountable_role_id
   where r.runtime_mode = 'knowledge_overlay'
  union all
  select 'overlay_states_no_limit', r.role_id, 'necessity_reason does not say what it cannot decide'
    from public.org_role r
   where r.status='active' and r.runtime_mode='knowledge_overlay'
     and coalesce(r.necessity_reason,'') not ilike '%cannot decide%';
$fn$;
comment on function public.fn_phase_a_organization_violations() is
  'Phase A ORGANIZATIONAL correctness only. It deliberately does NOT test runtime tools, imported knowledge, live KPI bindings, model policies, decision traces or provider connections - those are later-phase readiness and are reported by fn_org_role_violations() and fn_phase_a_deferred_items(). Two instruments, two subjects; fn_org_role_violations is not weakened to make this one green.';
revoke all on function public.fn_phase_a_organization_violations() from public;

-- AND THE DEFERRED WORK, NAMED RATHER THAN HIDDEN. Whatever fn_org_role_violations reports that
-- this phase is forbidden to fix is listed here with its phase label, so "0 organizational
-- violations" can never be read as "nothing outstanding".
create or replace function public.fn_phase_a_deferred_items()
returns table (status text, rule text, role_id text, detail text)
language sql
stable
as $fn$
  select 'DEFERRED_TO_LATER_PHASES', v.rule, v.role_id, v.detail
    from public.fn_org_role_violations() v
   where v.rule in ('no_kpi','no_knowledge','no_authority','no_tools','no_evaluation',
                    'runtime_agent_inactive','no_model_policy');
$fn$;
comment on function public.fn_phase_a_deferred_items() is
  'The runtime-readiness gaps Phase A is forbidden to close, labelled DEFERRED_TO_LATER_PHASES. Exists so that a zero from fn_phase_a_organization_violations() is never mistaken for nothing outstanding.';
revoke all on function public.fn_phase_a_deferred_items() from public;

-- ============================================================================================
-- 3. THE PRODUCT/TECHNOLOGY HEAD
--
-- The stable technical key stays `cto`: it is the runtime agent key, it is named by workflow steps,
-- KPI rows and routine literals, and renaming it would orphan every one of them for no
-- organizational gain. Only the title and the accountability it names change.
--
-- This closes a real gap rather than relabelling one. "Chief Technology Officer" names engineering
-- and says nothing about product, which left product STRATEGY ownership implicit: the Product
-- Manager owns the requirement and its priority, and nobody above them owned the product direction
-- the requirements are supposed to serve. The department is Product, Engineering & AI; its head is
-- now titled for all three.
-- ============================================================================================
update public.org_role set
  display_name = 'Chief Product & Technology Officer',
  rationale = coalesce(rationale,'') || ' Phase A retitle: the department is Product, Engineering & AI and its head is now titled for all three. Stable key cto unchanged.',
  updated_at = now()
 where role_id = 'cto';
update public.org_agents set title = 'Chief Product & Technology Officer' where agent_key = 'cto';

-- the package's canonical id resolves to the stable key, so both vocabularies reach the same role
insert into public.org_role_alias (alias, role_id, kind, reason) values
  ('chief_product_technology_officer', 'cto', 'packaged_role_id',
   'Phase A: the package canonical id for the Product, Engineering & AI head; the stable runtime key is cto.')
on conflict (alias) do update set role_id = excluded.role_id;

-- ============================================================================================
-- 4. THE UAE TAX DECISION, RECORDED AS A DECISION
--
-- Not a comment in a migration nobody re-reads: a row in decision_record, approved by the founder,
-- so the reasoning survives the session that made it. It adds no 91st role.
-- ============================================================================================
-- THE GATE ON decision_record REFUSED THIS TWICE, AND IT WAS RIGHT BOTH TIMES.
--
-- fn_decision_gate requires a COMPLETE impact analysis and at least one evidence reference before
-- any row may be 'approved': business, financial, legal and customer impact, plus evidence. The
-- first attempt supplied financial and legal only, so the trigger rewrote the status to
-- 'blocked_by_gate' and the postcondition caught it. The second attempt supplied the rest in a
-- follow-up UPDATE — and the gate's approval branch only fires when the status TRANSITIONS into
-- 'approved', which that update did not do, so the row stayed blocked.
--
-- So it is written the way the gate is designed to be satisfied: propose with the full analysis
-- attached, then approve. A founder decision recorded without its impact analysis is exactly what
-- that gate exists to refuse, and it is satisfied rather than worked around.
insert into public.decision_record
  (decided_by, dept_key, problem, context, options, recommendation, expected_outcome,
   rollback_plan, status, reversible, impact_business, impact_financial, impact_legal,
   impact_customer, impact_supplier, evidence)
values (
  'founder', 'finance',
  'Does QuotesDone need a standing UAE tax role, or does the Financial Controller own UAE VAT and corporate-tax coordination?',
  'A UAE Tax Overlay was created on 15 Aug 2026 outside the Phase A package and retired by Phase A. The package answers the question differently: CURRENT_TO_FINAL_ROLE_CHANGES.csv records "Expand scope | Financial Controller | UAE VAT/corporate-tax coordination".',
  jsonb_build_array(
    'Add a standing UAE tax role as a 91st role',
    'Keep a knowledge overlay outside the 86-entry category registry',
    'Financial Controller owns routine coordination and escalates anything material'),
  'No additional standing UAE tax role. The Financial Controller owns normal UAE VAT and corporate-tax coordination: invoice tax compliance, the filing calendar, supporting evidence, revenue-recognition coordination and operational reconciliation. Complex, material, disputed or current-interpretation questions escalate to authoritative current sources, to Legal/Compliance where relevant, and to an external UAE tax professional or firm. This adds no 91st role.',
  'Routine tax coordination has one accountable owner; nothing material is answered from an AI employee''s memory of tax law.',
  'Create a standing tax role if routine coordination proves to exceed the Financial Controller''s capacity, or if a filing position needs continuous in-house ownership.',
  'proposed', true,
  'The company keeps 90 canonical roles rather than 91. Routine UAE VAT and corporate-tax coordination has one accountable owner in Finance instead of a standing overlay that declared no operational owner, no invocation role and no knowledge-governance path.',
  'Avoids a standing role the company does not need; external advice is bought per matter rather than salaried. No salary line, no recruitment and no additional model spend - the Financial Controller already holds the scope.',
  'A filing position taken from an AI employee''s memory of tax law is the risk this closes. Current interpretation, disputes and material positions escalate to an external UAE tax professional and to Legal/Compliance; they are never answered from memory.',
  'None directly. Invoice tax compliance stays correct on customer-facing documents, which is the only surface a customer sees, and it is owned rather than assumed.',
  'None directly. Supplier invoicing and subscription tax treatment sit inside the same Financial Controller scope.',
  jsonb_build_array(
    jsonb_build_object('source','CURRENT_TO_FINAL_ROLE_CHANGES.csv','detail','Expand scope | Financial Controller | UAE VAT/corporate-tax coordination'),
    jsonb_build_object('source','org_role.responsibilities financial_controller','detail','UAE tax already within approved scope: VAT, corporate-tax coordination, invoice tax compliance, revenue recognition, filing calendar, supporting-document controls'),
    jsonb_build_object('source','supabase/migrations/20260815050000_phase_a_organization_closure.sql','detail','tax_overlay_uae retired and aliased to financial_controller'))
);

update public.decision_record
   set status = 'approved', approved_by = 'founder', decided_at = now()
 where decided_by='founder' and problem ilike '%UAE tax role%' and status = 'proposed';

-- and the escalation path is written on the role itself, not only in the decision row
update public.org_role set
  owned_decisions = (
    select array_agg(distinct e order by e) from unnest(
      owned_decisions || array[
        'UAE VAT and corporate-tax coordination',
        'invoice tax compliance',
        'tax filing calendar',
        'tax supporting evidence',
        'operational tax reconciliation'
      ]::text[]) e),
  forbidden_decisions = (
    select array_agg(distinct e order by e) from unnest(
      forbidden_decisions || array[
        'current UAE tax law interpretation',
        'a disputed or material filing position'
      ]::text[]) e),
  escalation_targets = (
    select array_agg(distinct e order by e) from unnest(
      escalation_targets || array['general_counsel','external UAE tax professional or firm']::text[]) e),
  rationale = coalesce(rationale,'') || ' Phase A founder decision: owns routine UAE VAT and corporate-tax coordination; complex, material, disputed or current-interpretation questions escalate to authoritative current sources, Legal/Compliance and an external UAE tax professional. No 91st role.',
  updated_at = now()
 where role_id = 'financial_controller';

-- ============================================================================================
-- POSTCONDITIONS
-- ============================================================================================
do $$
declare v int; v_txt text;
begin
  select count(*) into v from public.org_departments where active;
  if v <> 10 then raise exception 'POST: active departments = %, expected 10', v; end if;

  select count(*) into v from public.org_role where status='active' and runtime_mode <> 'knowledge_overlay';
  if v <> 90 then raise exception 'POST: accountable roles = %, expected 90 - the UX designer must remain one of the 90', v; end if;

  select count(*) into v from public.org_role where status='active' and runtime_mode='knowledge_overlay';
  if v <> 86 then raise exception 'POST: category overlays = %, expected 86', v; end if;

  -- THE REQUIRED RESULT: zero organizational violations.
  select count(*), string_agg(distinct rule, ', ') into v, v_txt from public.fn_phase_a_organization_violations();
  if v <> 0 then raise exception 'POST: fn_phase_a_organization_violations() returned % row(s): %', v, v_txt; end if;

  -- the two rules the founder named explicitly
  select count(*) into v from public.fn_phase_a_organization_violations() where rule = 'no_responsibility';
  if v <> 0 then raise exception 'POST: % role(s) have no workflow, review or management responsibility', v; end if;

  select count(*) into v from public.org_workflow_ownership o, unnest(o.contributors) c
   where not exists (select 1 from public.org_role r where r.role_id = c and r.status='active')
     and c not in ('department heads', 'category overlays', 'broad domain specialists');
  if v <> 0 then raise exception 'POST: % contributor entr(ies) still name nobody', v; end if;

  -- the UX designer specifically: fully defined, and deliberately not runtime-enabled
  if not exists (
    select 1 from public.org_role
     where role_id='product_ux_designer' and status='active'
       and primary_department_id='product_eng' and manager_role_id='product_manager'
       and runtime_mode='on_demand_specialist'
       and cardinality(owned_decisions) = 9 and cardinality(forbidden_decisions) = 7
       and cardinality(output_contracts) = 5
       and runtime_enabled = false)
    then raise exception 'POST: product_ux_designer is not fully defined, or is not marked runtime-deferred'; end if;

  select count(*) into v from public.org_workflow_step where workflow_id='W22';
  if v <> 7 then raise exception 'POST: W22 has % step(s), expected 7', v; end if;
  if not exists (select 1 from public.org_workflow_step
                  where workflow_id='W22' and step_no=2 and accountable_role_id='product_ux_designer')
    then raise exception 'POST: the UX designer does not own experience design in W22'; end if;
  -- the release gate is held outside the department that ships
  if (select r.primary_department_id from public.org_role r
       join public.org_workflow_step s on s.accountable_role_id = r.role_id
      where s.workflow_id='W22' and s.step_no=7) <> 'assurance'
    then raise exception 'POST: the W22 release gate is not held by Independent Assurance'; end if;

  -- the retitle, and the stable key it kept
  if not exists (select 1 from public.org_role where role_id='cto' and display_name='Chief Product & Technology Officer')
    then raise exception 'POST: the product/technology head was not retitled'; end if;
  if not exists (select 1 from public.org_role_alias where alias='chief_product_technology_officer' and role_id='cto')
    then raise exception 'POST: the packaged id for the product/technology head resolves to nobody'; end if;

  -- the tax decision is recorded and adds no role
  if not exists (select 1 from public.decision_record
                  where decided_by='founder' and status='approved' and problem ilike '%UAE tax role%')
    then raise exception 'POST: the UAE tax decision was not recorded'; end if;
  if exists (select 1 from public.org_role where status='active' and runtime_mode='knowledge_overlay'
               and role_id !~ '^category_overlay_[0-9]{3}_')
    then raise exception 'POST: a non-category overlay exists again'; end if;

  raise notice 'PHASE A CLOSURE: 10 departments, 90 roles, 86 overlays, 0 organizational violations.';
end $$;
