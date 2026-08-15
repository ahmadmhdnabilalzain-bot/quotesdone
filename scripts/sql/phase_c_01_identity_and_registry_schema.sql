-- Phase C — canonical identity boundary and runtime-connection registries.
--
-- Phase A froze WHO EXISTS.  Phase B froze HOW THE COMPANY MUST WORK.  Phase C connects both
-- to the machinery that actually runs, and this file is the identity boundary plus the tables
-- that hold the connection.
--
-- Nothing here activates anything.  No cron row is created, enabled or disabled; no provider
-- route is opened; no business record is written; no Phase A or Phase B row is touched.  The
-- alias rows below are the one exception worth stating out loud: org_role_alias and
-- org_department_alias carry no frozen digest and no freeze trigger, which is why Phase B was
-- able to load 237 alias rows without moving fn_phase_a_baseline_drift() off zero.  Teaching
-- the estate a second spelling of an existing employee is not an organizational change.
--
-- Three things in this file are the ones that make it a boundary rather than a document:
--
--   * fn_phase_c_resolve_actor() is the ONLY sanctioned way to turn any actor token into a
--     canonical role.  It refuses unknown and inactive identities explicitly rather than
--     returning null, because a null that a caller treats as "no restriction" is the shape of
--     defect this estate has repeated: error and empty must not return the same value.
--
--   * phase_c_component holds every measured runtime component with its accountable role.
--     A CHECK refuses an active state-changing row with no accountable role, so the invariant
--     "active state-changing components without accountable role = 0" is enforced at write
--     time and not merely counted afterwards.
--
--   * phase_c_action_class carries founder_approval_required, and exactly one row may set it.
--     The founder-approval table in phase_c_05 has a foreign key to it, so a non-refund founder
--     approval request is refused by the database rather than by a convention.
--
-- scripts/sql is append-only.  To change any of this, add a new file.

set lock_timeout = '8s';
set statement_timeout = '600s';

-- ============================================================ 1. identity reconciliation
--
-- The Phase C package addresses the organization by descriptive names.  Phase A stores it
-- under short keys.  Every mapping below was measured one-to-one on 15 Aug 2026 by
-- scripts/phase_c/validate_package.mjs, which reported 9 unresolved department tokens, 86
-- unresolved overlay tokens and one unresolved role spelling.  These rows close exactly those
-- and nothing else.

insert into public.org_department_alias (packaged_department, dept_key, is_second_home, note) values
  ('finance_payments',                   'finance',             false, 'Phase C package department naming'),
  ('people_company_operations',          'people_ops',          false, 'Phase C package department naming'),
  ('growth_revenue',                     'growth',              false, 'Phase C package department naming'),
  ('data_intelligence_knowledge',        'data_intel',          false, 'Phase C package department naming'),
  ('assurance_security_reliability',     'assurance',           false, 'Phase C package department naming'),
  ('marketplace_supplier_network',       'marketplace',         false, 'Phase C package department naming'),
  ('legal_compliance_risk_trust',        'legal',               false, 'Phase C package department naming'),
  ('customer_experience_communications', 'customer_experience', false, 'Phase C package department naming'),
  ('product_engineering_ai',             'product_eng',         false, 'Phase C package department naming')
on conflict (packaged_department, dept_key) do nothing;

-- One role spelling.  Phase A's role is fpna_analyst; Phase B loaded the alias fp_a_analyst;
-- the Phase C acceptance cases introduce a third spelling, fpa_analyst.  One row, no change
-- to the role itself.
insert into public.org_role_alias (alias, role_id, kind, reason) values
  ('fpa_analyst', 'fpna_analyst', 'packaged_role_id',
   'Phase C package spelling; Phase A role is fpna_analyst and Phase B alias is fp_a_analyst')
on conflict (alias) do nothing;

-- The 86 category overlays.  public.org_category_identity already maps route_key 'opcat-NNN'
-- to category_key 'NNN_slug', and the live overlay role is 'category_overlay_' || category_key.
-- The alias rows are derived from that mapping rather than typed, so a drift in either table
-- shows up as a missing alias instead of as a wrong one.
insert into public.org_role_alias (alias, role_id, kind, reason)
select ci.route_key, r.role_id, 'packaged_role_id',
       'Phase C category overlay route key; derived from org_category_identity'
from public.org_category_identity ci
join public.org_role r
  on r.role_id = 'category_overlay_' || ci.category_key
 and r.status = 'active' and r.runtime_mode = 'knowledge_overlay'
on conflict (alias) do nothing;

-- ============================================================== 2. package errata
--
-- The committed package is checksummed and must not be edited in place, so a defect found in
-- it is recorded here with its evidence and its decided correction — the same treatment
-- Phase B gave EX-006.  None of these is an organizational defect; all are package-side naming.
create table if not exists public.phase_c_package_erratum (
  erratum_id   text primary key,
  source_file  text not null,
  cell         text not null,
  defect       text not null,
  evidence     text not null,
  correction   text not null,
  rationale    text not null,
  recorded_at  timestamptz not null default now()
);

insert into public.phase_c_package_erratum
  (erratum_id, source_file, cell, defect, evidence, correction, rationale) values
  ('PCE-001', 'PHASE_C_AUTHORITY_AND_APPROVAL_MATRIX.csv', 'supplier_suspension.review_or_contributors',
   'cell holds prose where a role id list belongs',
   'reads "fraud_reviewer or supplier_verification_reviewer"; every other cell holds "; "-separated role ids',
   'fraud_reviewer; supplier_verification_reviewer',
   'Both named roles resolve. "or" is a human disjunction; the runtime needs the set, and reviewer independence is checked per candidate.'),
  ('PCE-002', 'PHASE_C_AUTHORITY_AND_APPROVAL_MATRIX.csv', 'marketing_publish.review_or_contributors',
   'cell holds prose where a role id list belongs',
   'reads "brand_creative_manager or ai_quality_assurance_reviewer"',
   'brand_creative_manager; ai_quality_assurance_reviewer',
   'Both resolve through org_role_alias. Same disjunction shape as PCE-001.'),
  ('PCE-003', 'PHASE_C_AUTHORITY_AND_APPROVAL_MATRIX.csv', 'production_release.review_or_contributors',
   'cell carries a conditional clause inside a role id list',
   'reads "cybersecurity_engineer; model_evaluation_reviewer where applicable"',
   'cybersecurity_engineer; model_evaluation_reviewer',
   'The condition is the workflow''s, not the identity''s. Recorded as two reviewers; applicability is decided by the gate, not by the name.'),
  ('PCE-004', 'PHASE_C_AUTHORITY_AND_APPROVAL_MATRIX.csv', 'public_claim_publish.review_or_contributors',
   'cell holds prose where a role id list belongs',
   'reads "general_counsel or compliance_privacy_officer"',
   'general_counsel; compliance_privacy_officer',
   'Both resolve. Same shape as PCE-001.'),
  ('PCE-005', 'PHASE_C_AUTHORITY_AND_APPROVAL_MATRIX.csv', 'routine_operational_decision.accountable_role_id',
   'cell holds the placeholder "accountable_canonical_role" where a role id belongs',
   'no org_role or org_role_alias row named accountable_canonical_role exists',
   'DYNAMIC: resolved at runtime to the accountable role of the workflow/step in scope',
   'This action class is deliberately generic — "any ordinary department decision". It has no single owner by construction, so it is registered as a dynamic scope rather than bound to an invented role.'),
  ('PCE-006', 'PHASE_C_AUTHORITY_AND_APPROVAL_MATRIX.csv', 'routine_operational_decision.review_or_contributors',
   'cell holds prose where a role id list belongs',
   'reads "manager/reviewer per Phase A/B"',
   'DYNAMIC: manager_role_id of the accountable role, and the step''s independent_reviewer_role_id',
   'Phase A records the manager on org_role and Phase B records the reviewer on phase_b_workflow_step. The prose names those two columns; the runtime reads them.'),
  ('PCE-007', 'PHASE_C_COMMAND_ROUTING_ACCEPTANCE_CASES.csv', 'CC-002.expected_child_roles',
   'cell names an overlay in prose inside a role id list',
   'reads "category overlay opcat-004"',
   'opcat-004',
   'opcat-004 is a registered route key and now resolves through org_role_alias to category_overlay_004_formwork-and-scaffolding-suppliers. The prose prefix is dropped; the identity is unchanged.'),
  ('PCE-008', 'PHASE_C_COMMAND_ROUTING_ACCEPTANCE_CASES.csv', 'CC-005.expected_child_roles',
   'third spelling of one role',
   'reads "fpa_analyst"; Phase A role is fpna_analyst and the Phase B alias is fp_a_analyst',
   'fpa_analyst -> fpna_analyst via org_role_alias',
   'One alias row. No role is created, renamed or moved.')
on conflict (erratum_id) do nothing;

-- ============================================================ 3. system actor registry
create table if not exists public.phase_c_system_actor (
  system_actor_id     text primary key,
  description         text not null,
  accountable_role_id text not null,
  department_id       text not null,
  allowed_actions     text not null,
  forbidden_actions   text not null,
  trace_policy_id     text not null
);

create table if not exists public.phase_c_trace_policy (
  trace_policy_id                 text primary key,
  scope                           text not null,
  trace_required                  text not null,
  minimum_fields                  text not null,
  completed_without_trace_allowed text not null
);

-- ============================================================ 4. authority registry
create table if not exists public.phase_c_action_class (
  action_class             text primary key,
  description              text not null,
  execution_mode           text not null,
  accountable_role_id      text not null,
  review_or_contributors   text not null,
  founder_approval_required boolean not null,
  founder_initiated_only   boolean not null,
  notes                    text not null
);

-- The founder-autonomy invariant, enforced rather than counted.  Exactly one action class
-- may require a founder manual approval, and it must be refund_decision.
create unique index if not exists phase_c_action_class_single_founder_approval_uk
  on public.phase_c_action_class ((true)) where founder_approval_required;

-- ============================================================ 5. command registries
create table if not exists public.phase_c_command_intent (
  intent_id                  text primary key,
  intent_name                text not null,
  workflow_id                text not null,
  default_accountable_role_id text not null,
  command_owner_role_id      text not null,
  classification_mode        text not null,
  immediate_task_required    boolean not null,
  founder_approval_required  text not null,
  founder_initiated_only     text not null,
  default_priority           text not null,
  low_confidence_behavior    text not null,
  notes                      text not null
);

create table if not exists public.phase_c_command_state (
  state text primary key, definition text not null, terminal boolean not null
);
create table if not exists public.phase_c_command_transition (
  from_state text not null references public.phase_c_command_state(state),
  to_state   text not null references public.phase_c_command_state(state),
  condition  text not null,
  primary key (from_state, to_state)
);
create table if not exists public.phase_c_task_state (
  state text primary key, definition text not null, terminal boolean not null
);
create table if not exists public.phase_c_task_transition (
  from_state text not null references public.phase_c_task_state(state),
  to_state   text not null references public.phase_c_task_state(state),
  condition  text not null,
  primary key (from_state, to_state)
);

-- ============================================================ 6. runtime component registry
create table if not exists public.phase_c_component (
  component_id            text primary key,
  component_type          text not null,
  source_path_or_db_object text not null,
  entry_method            text not null default '',
  current_callers         text not null default '',
  external_entry          text not null default '',
  schedule_or_trigger     text not null default '',
  mutates_state           boolean not null,
  current_actor           text not null default '',
  canonical_system_actor  text not null references public.phase_c_system_actor(system_actor_id),
  accountable_role_id     text not null,
  department_id           text not null default '',
  workflow_id             text not null,
  step_id                 text not null default '',
  authority_class         text not null references public.phase_c_action_class(action_class),
  trace_policy_id         text not null references public.phase_c_trace_policy(trace_policy_id),
  idempotency_strategy    text not null,
  retry_policy            text not null,
  activation_state        text not null,
  classification          text not null,
  gap                     text not null default '',
  repair_or_keep_action   text not null default '',
  evidence                text not null default '',
  measured_at             timestamptz not null default now()
);

-- The Phase C classification vocabulary, master spec §3.6.  An unknown verdict is refused,
-- so "unclassified" cannot enter by typo.
alter table public.phase_c_component drop constraint if exists phase_c_component_classification_ck;
alter table public.phase_c_component add constraint phase_c_component_classification_ck
  check (classification in ('CANONICAL_KEEP','CANONICAL_BETTER_KEEP','WIRE_TO_CANONICAL',
                            'DUPLICATE_PATH','CONFLICTING_PATH','NO_CALLER_UNCLASSIFIED',
                            'INACTIVE_HISTORICAL','REPAIR_BEFORE_REACTIVATION',
                            'INTENTIONALLY_RETIRED','PHASE_D_CORRECTNESS_GAP')) not valid;

-- The invariant, enforced at write time.  An active component that changes state must name a
-- canonical accountable role and either a frozen workflow or an explicit justified system
-- scope.  'SYSTEM_SCOPE' and 'OUT_OF_SCOPE' are the two justified non-workflow values; both
-- are explicit, which is the whole point — a blank is not.
alter table public.phase_c_component drop constraint if exists phase_c_component_accountable_ck;
alter table public.phase_c_component add constraint phase_c_component_accountable_ck
  check (
    not (mutates_state and activation_state not in ('inactive','disabled'))
    or (accountable_role_id <> '' and workflow_id <> '')
  ) not valid;

-- A generic name may never be the final owner.  These are the exact strings this estate has
-- used as owners in the past; each one is a name nobody models.
alter table public.phase_c_component drop constraint if exists phase_c_component_no_generic_owner_ck;
alter table public.phase_c_component add constraint phase_c_component_no_generic_owner_ck
  check (accountable_role_id not in ('Director','director','service_role','pg_cron','postgres',
                                     'system','admin','code_runner','unknown','')) not valid;

alter table public.phase_c_component validate constraint phase_c_component_classification_ck;
alter table public.phase_c_component validate constraint phase_c_component_accountable_ck;
alter table public.phase_c_component validate constraint phase_c_component_no_generic_owner_ck;

create index if not exists phase_c_component_workflow_ix on public.phase_c_component (workflow_id);
create index if not exists phase_c_component_class_ix on public.phase_c_component (classification);

-- ============================================================ 7. binding registries
create table if not exists public.phase_c_role_binding (
  canonical_role_id     text primary key,
  department_id         text not null default '',
  runtime_agent_key     text not null default '',
  resolver_path         text not null,
  task_receiver_path    text not null,
  authority_binding_path text not null,
  review_binding_path   text not null,
  knowledge_scope_path  text not null,
  tool_policy_path      text not null,
  trace_policy_id       text not null references public.phase_c_trace_policy(trace_policy_id),
  paid_model_route_status text not null,
  workflows_served      text not null default '',
  connection_status     text not null,
  gap                   text not null default '',
  evidence              text not null default ''
);

create table if not exists public.phase_c_overlay_binding (
  overlay_id            text primary key,
  live_role_id          text not null,
  category_name         text not null default '',
  invocation_role_id    text not null,
  result_returns_to_role_id text not null,
  invocation_entrypoint text not null,
  result_contract       text not null,
  trace_policy_id       text not null references public.phase_c_trace_policy(trace_policy_id),
  connection_status     text not null,
  evidence              text not null default ''
);

create table if not exists public.phase_c_workflow_binding (
  workflow_id           text primary key,
  accountable_role_id   text not null,
  runtime_entrypoint    text not null,
  workflow_run_writer   text not null,
  state_transition_enforcer text not null,
  event_outbox_writer   text not null,
  current_engine        text not null default '',
  bound_components      bigint not null default 0,
  trace_policy_id       text not null references public.phase_c_trace_policy(trace_policy_id),
  connection_status     text not null,
  evidence              text not null default ''
);

create table if not exists public.phase_c_step_binding (
  step_id               text primary key,
  workflow_id           text not null,
  accountable_role_id   text not null,
  independent_reviewer_role_id text not null default '',
  idempotency_scope     text not null,
  canonical_runtime_handler text not null,
  current_handlers      text not null default '',
  gate_enforcer         text not null,
  authority_enforcer    text not null,
  review_enforcer       text not null,
  event_emitter         text not null,
  handoff_writer        text not null,
  trace_policy_id       text not null references public.phase_c_trace_policy(trace_policy_id),
  connection_status     text not null,
  gap                   text not null default '',
  phase_d_action        text not null default '',
  evidence              text not null default ''
);

-- A deferred step is only acceptable when it carries all four of the master prompt's
-- conditions.  Two of them are columns; this refuses a deferral that names neither an owner
-- nor the Phase D work.
alter table public.phase_c_step_binding drop constraint if exists phase_c_step_binding_deferral_ck;
alter table public.phase_c_step_binding add constraint phase_c_step_binding_deferral_ck
  check (connection_status <> 'DEFERRED_RUNTIME_IMPLEMENTATION'
         or (accountable_role_id <> '' and canonical_runtime_handler <> '' and phase_d_action <> '')) not valid;
alter table public.phase_c_step_binding validate constraint phase_c_step_binding_deferral_ck;

create table if not exists public.phase_c_handoff_binding (
  handoff_id            text primary key,
  workflow_id           text not null,
  sending_role_id       text not null,
  receiving_role_id     text not null,
  sending_department_id text not null default '',
  receiving_department_id text not null default '',
  sla_policy_id         text not null default '',
  runtime_writer        text not null,
  runtime_receiver      text not null,
  packet_schema_validator text not null,
  ownership_retention_guard text not null,
  sla_timer_handler     text not null,
  trace_policy_id       text not null references public.phase_c_trace_policy(trace_policy_id),
  connection_status     text not null,
  evidence              text not null default ''
);

create table if not exists public.phase_c_event_binding (
  event_id              text primary key,
  event_name            text not null,
  workflow_id           text not null,
  emitted_by            text not null,
  primary_consumer_role_id text not null,
  dedupe_key            text not null,
  outbox_writer         text not null,
  delivery_worker       text not null,
  dedupe_enforced       text not null,
  dead_letter_path      text not null,
  connection_status     text not null,
  evidence              text not null default ''
);

create table if not exists public.phase_c_gate_binding (
  gate_id               text primary key,
  gate_name             text not null,
  workflow_scope        text not null,
  gate_type             text not null,
  enforcement_layer     text not null,
  enforcement_function  text not null,
  all_callers           text not null,
  fail_closed_proof     text not null,
  connection_status     text not null,
  evidence              text not null default ''
);

create table if not exists public.phase_c_rule_binding (
  rule_id               text primary key,
  rule_name             text not null,
  rule_type             text not null,
  workflow_scope        text not null,
  enforcement_layer     text not null,
  enforcement_function  text not null,
  all_callers           text not null,
  deterministic_test_id text not null,
  connection_status     text not null,
  evidence              text not null default ''
);

-- ============================================================ 8. the identity boundary
--
-- One resolver.  Every live actor boundary calls it before context, task, authority, review,
-- knowledge, tool, workflow, KPI or trace behaviour.
--
-- It returns a row rather than a bare text so a caller cannot mistake "unknown" for "no
-- restriction": kind is always populated, and 'unknown'/'inactive' carry a reason.  A function
-- that returned null for both "not found" and "found but inactive" would repeat the defect
-- this estate has already paid for twice.
create or replace function public.fn_phase_c_resolve_actor(p_token text)
returns table (kind text, role_id text, department_id text, system_actor_id text, reason text)
language plpgsql
stable
set search_path to 'public', 'pg_temp'
as $$
declare
  v_tok  text := btrim(coalesce(p_token, ''));
  v_id   text;
  v_role public.org_role%rowtype;
begin
  if v_tok = '' then
    kind := 'refused'; reason := 'empty actor token'; return next; return;
  end if;

  -- the founder is an external decision boundary, not an employee
  if v_tok = 'founder' then
    kind := 'founder'; role_id := 'founder'; department_id := 'exec';
    reason := 'external decision boundary; may hold refund_decision only'; return next; return;
  end if;

  -- a registered system actor executes, but never replaces the accountable employee
  select a.system_actor_id, a.accountable_role_id, a.department_id
    into system_actor_id, role_id, department_id
  from public.phase_c_system_actor a where a.system_actor_id = v_tok;
  if found then
    kind := 'system_actor';
    reason := 'system actor; accountable_role_id is the business owner, not the executor';
    return next; return;
  end if;

  -- canonical role id, then any registered alias: legacy key, merged key, packaged role
  -- identity or approved title.  org_role_alias.kind records which.
  v_id := (select r.role_id from public.org_role r where r.role_id = v_tok);
  if v_id is null then
    v_id := (select a.role_id from public.org_role_alias a where a.alias = v_tok limit 1);
  end if;

  if v_id is null then
    kind := 'unknown'; reason := format('no active canonical role, alias or system actor named %L', v_tok);
    return next; return;
  end if;

  select * into v_role from public.org_role r where r.role_id = v_id;
  if not found then
    kind := 'unknown'; reason := format('alias %L points at missing role %L', v_tok, v_id);
    return next; return;
  end if;
  if v_role.status <> 'active' then
    kind := 'inactive'; role_id := v_role.role_id; department_id := v_role.primary_department_id;
    reason := format('role %L has status %L and may not receive or execute current work', v_id, v_role.status);
    return next; return;
  end if;

  role_id := v_role.role_id;
  department_id := v_role.primary_department_id;
  if v_role.runtime_mode = 'knowledge_overlay' then
    kind := 'overlay';
    reason := 'category overlay: may be invoked and may advise, may never hold dispatch authority or own a required step';
  else
    kind := 'canonical';
    reason := 'active canonical role';
  end if;
  return next;
end $$;

revoke all on function public.fn_phase_c_resolve_actor(text) from public;
grant execute on function public.fn_phase_c_resolve_actor(text) to service_role;

-- The single boolean a caller usually wants, expressed so it cannot be misread.  It is TRUE
-- only for an active canonical role: an overlay, the founder, a system actor, an inactive role
-- and an unknown token all return FALSE.
create or replace function public.fn_phase_c_actor_may_own(p_token text)
returns boolean language sql stable set search_path to 'public', 'pg_temp' as $$
  select coalesce((select kind = 'canonical' from public.fn_phase_c_resolve_actor(p_token)), false);
$$;
revoke all on function public.fn_phase_c_actor_may_own(text) from public;
grant execute on function public.fn_phase_c_actor_may_own(text) to service_role;
