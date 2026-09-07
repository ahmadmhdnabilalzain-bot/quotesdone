-- Phase B — canonical business workflow registry: schema, constraints and validators.
--
-- Phase A answered who exists and who owns outcomes, and is frozen.  Phase B answers how the
-- company works from start to finish, and this file is the structure that holds the answer.
--
-- Nothing here activates anything.  No cron row, no provider route, no autonomous executor and
-- no business record is created by this file.  It defines tables, constraints and read-only
-- validation functions, and that is the whole of it.
--
-- Two constraints deserve naming up front, because they are the ones that make the registry a
-- guard rather than a document:
--
--   * phase_b_step_creator_not_reviewer refuses a step whose accountable owner is also its
--     independent reviewer.  Effective identity, not alias: both columns hold canonical role_ids
--     resolved through org_role_alias before insert, so two spellings of one employee collide.
--
--   * (fn_phase_b_owner_guard once refused an owner that did not resolve to an ACTIVE canonical
--     role. It was removed on 7 Sep 2026 with the other two -- see the note where it stood. An
--     owner that cannot act is now discovered at RUN time by fn_phase_c_resolve_actor.)
--
-- scripts/sql is append-only.  To change any of this, add a new file.

set lock_timeout = '8s';
set statement_timeout = '600s';

-- ---------------------------------------------------------------- state models

create table if not exists public.phase_b_workflow_state (
  state       text primary key,
  definition  text not null,
  terminal    boolean not null
);

create table if not exists public.phase_b_step_state (
  state       text primary key,
  definition  text not null,
  terminal    boolean not null
);

create table if not exists public.phase_b_workflow_transition (
  from_state  text not null references public.phase_b_workflow_state(state),
  to_state    text not null references public.phase_b_workflow_state(state),
  condition   text not null,
  primary key (from_state, to_state)
);

create table if not exists public.phase_b_step_transition (
  from_state  text not null references public.phase_b_step_state(state),
  to_state    text not null references public.phase_b_step_state(state),
  condition   text not null,
  primary key (from_state, to_state)
);

-- ------------------------------------------------------------- supporting registries

-- Actors that are deliberately not a standing role.  may_be_accountable is false for all of
-- them except the founder and the category overlay, and the overlay only inside its declared
-- technical-evaluation scope.
create table if not exists public.phase_b_dynamic_actor (
  actor_token         text primary key,
  actor_type          text not null,
  meaning             text not null,
  resolution_rule     text not null,
  may_be_accountable  boolean not null default false
);

create table if not exists public.phase_b_sla_policy (
  sla_policy_id  text primary key,
  name           text not null,
  workflow_scope text not null,
  target         text not null,
  classification text not null,
  breach_action  text not null
);

create table if not exists public.phase_b_business_object (
  object_id            text primary key,
  governing_workflow_id text not null,
  accountable_role_id  text not null,
  definition           text not null,
  record_policy        text not null,
  mutation_rule        text not null
);

create table if not exists public.phase_b_business_rule (
  rule_id        text primary key,
  rule_name      text not null,
  rule_text      text not null,
  workflow_scope text not null,
  rule_type      text not null
);

create table if not exists public.phase_b_gate (
  gate_id           text primary key,
  gate_name         text not null,
  workflow_scope    text not null,
  required_evidence text not null,
  pass_result       text not null,
  fail_result       text not null,
  gate_type         text not null
);

create table if not exists public.phase_b_founder_boundary (
  boundary_id         text primary key,
  boundary_name       text not null,
  definition          text not null,
  workflow_scope      text not null,
  decision_owner      text not null,
  phase_b_enforcement text not null
);

-- --------------------------------------------------------------------- workflows

create table if not exists public.phase_b_workflow (
  workflow_id                  text primary key,
  workflow_name                text not null,
  domain                       text not null,
  criticality                  text not null,
  profile                      text not null,
  primary_object               text not null references public.phase_b_business_object(object_id),
  purpose                      text not null,
  accountable_role_id          text not null,
  package_accountable_token    text not null,
  contributors                 text[] not null default '{}',
  independent_reviewer_role_id text,
  start_event                  text not null,
  required_end_state           text not null,
  founder_boundary             text not null,
  allowed_terminal_states      text not null,
  reopen_allowed               text not null,
  version                      bigint not null default 1,
  status                       text not null default 'active',
  superseded_by                text references public.phase_b_workflow(workflow_id),
  created_at                   timestamptz not null default now(),
  constraint phase_b_workflow_status_known check (status in ('active','superseded')),
  constraint phase_b_workflow_owner_not_reviewer
    check (independent_reviewer_role_id is null
           or independent_reviewer_role_id <> accountable_role_id)
);

create table if not exists public.phase_b_workflow_step (
  step_id                      text primary key,
  workflow_id                  text not null references public.phase_b_workflow(workflow_id),
  step_no                      bigint not null,
  step_name                    text not null,
  step_type                    text not null,
  accountable_role_id          text not null,
  package_accountable_token    text not null,
  actor_kind                   text not null,
  contributors                 text[] not null default '{}',
  independent_reviewer_role_id text,
  entry_condition              text not null,
  required_inputs              text not null,
  required_action              text not null,
  required_output              text not null,
  acceptance_criteria          text not null,
  closure_criteria             text not null,
  failure_or_block_state       text not null,
  founder_gate                 text,
  idempotency_scope            text not null,
  repeatable                   boolean not null default false,
  is_closure_step              boolean not null default false,
  next_step_if_pass            text not null,
  next_step_if_fail            text not null,
  success_workflow_state       text not null references public.phase_b_workflow_state(state),
  failure_workflow_state       text not null references public.phase_b_workflow_state(state),
  notes                        text,
  constraint phase_b_step_no_unique unique (workflow_id, step_no),
  constraint phase_b_step_actor_kind_known
    check (actor_kind in ('canonical_role','founder','category_overlay')),
  -- effective identity: both columns hold canonical role_ids, so two spellings of one
  -- employee are the same value here and this refuses them
  constraint phase_b_step_creator_not_reviewer
    check (independent_reviewer_role_id is null
           or independent_reviewer_role_id <> accountable_role_id)
);

create index if not exists phase_b_step_workflow_idx on public.phase_b_workflow_step(workflow_id, step_no);
create index if not exists phase_b_step_owner_idx    on public.phase_b_workflow_step(accountable_role_id);

create table if not exists public.phase_b_handoff (
  handoff_id                  text primary key,
  workflow_id                 text not null references public.phase_b_workflow(workflow_id),
  from_step_id                text not null references public.phase_b_workflow_step(step_id),
  to_step_id                  text not null references public.phase_b_workflow_step(step_id),
  sending_role_id             text not null,
  receiving_role_id           text not null,
  sending_department_id       text not null,
  receiving_department_id     text not null,
  handoff_type                text not null,
  trigger                     text not null,
  required_packet             text not null,
  receiving_acceptance_criteria text not null,
  rejection_condition         text not null,
  return_owner_role_id        text not null,
  closure_condition           text not null,
  sla_policy_id               text not null references public.phase_b_sla_policy(sla_policy_id),
  constraint phase_b_handoff_edge_unique unique (from_step_id, to_step_id),
  -- a handoff whose sender is its receiver is not a handoff
  constraint phase_b_handoff_two_parties check (sending_role_id <> receiving_role_id)
);

create table if not exists public.phase_b_exception (
  exception_id            text primary key,
  exception_name          text not null,
  workflow_scope          text not null,
  detection_owner_role_id text not null,
  escalation_owner_role_id text not null,
  required_response       text not null,
  closure_condition       text not null,
  -- an exception that escalates to its own detector has no second pair of eyes
  constraint phase_b_exception_independent_escalation
    check (escalation_owner_role_id <> detection_owner_role_id)
);

create table if not exists public.phase_b_event (
  event_id             text primary key,
  event_name           text not null,
  workflow_id          text not null,
  emitted_by           text not null,
  trigger              text not null,
  primary_consumer_role_id text not null,
  payload_contract     text not null,
  dedupe_key           text not null
);

-- The crosswalk is the record of what the estate does TODAY against what it should do.
-- It is evidence, not configuration: every row carries the command that produced its verdict.
create table if not exists public.phase_b_crosswalk (
  crosswalk_id                    bigint generated always as identity primary key,
  current_artifact_type           text not null,
  current_artifact_name           text not null,
  repository_or_database_location text not null default '',
  current_trigger_or_caller       text not null default '',
  current_owner_or_actor          text not null default '',
  current_states_or_outcomes      text not null default '',
  target_workflow_id              text not null default '',
  target_step_id                  text not null default '',
  target_classification           text not null,
  duplicate_or_conflicting_path   text not null default '',
  historical_compatibility_required text not null default '',
  phase_c_wiring_action           text not null default '',
  evidence_command                text not null default '',
  evidence_result                 text not null default '',
  notes                           text not null default '',
  measured_at                     timestamptz not null default now(),
  constraint phase_b_crosswalk_classification_known check (target_classification in (
    'CANONICAL_KEEP','CANONICAL_BETTER_KEEP','CANONICAL_PARTIAL','DUPLICATE_PATH',
    'CONFLICTING_PATH','DEAD_CODE','UNOWNED','OUT_OF_SCOPE','PHASE_C_WIRING_GAP')),
  constraint phase_b_crosswalk_artifact_unique unique (current_artifact_type, current_artifact_name)
);

-- Errata against the committed package.  The package is checksummed and must not be edited in
-- place, so a defect found in it is recorded here with the evidence that found it.
create table if not exists public.phase_b_package_erratum (
  erratum_id   bigint generated always as identity primary key,
  package_file text not null,
  record_id    text not null,
  defect       text not null,
  evidence     text not null,
  correction   jsonb not null,
  rationale    text not null,
  recorded_at  timestamptz not null default now(),
  constraint phase_b_erratum_unique unique (package_file, record_id)
);

-- ------------------------------------------------------------- identity resolution

-- Resolve a token to an ACTIVE canonical role, or null.  Aliases are input compatibility only:
-- a merged-away or retired role resolves to null here and is refused by the owner guard.
create or replace function public.fn_phase_b_resolve_role(p_token text)
returns text
language sql
stable
as $$
  select r.role_id
  from public.org_role r
  where r.status = 'active'
    and r.runtime_mode <> 'knowledge_overlay'
    and r.role_id = coalesce(
      (select role_id from public.org_role where role_id = p_token and status = 'active'),
      (select a.role_id from public.org_role_alias a where a.alias = p_token limit 1)
    )
  limit 1;
$$;

-- THE THREE OWNER/HANDOFF GUARDS WERE REMOVED ON 7 SEPTEMBER 2026.
--
-- fn_phase_b_owner_guard, fn_phase_b_workflow_owner_guard and fn_phase_b_handoff_guard, with their
-- a10_ triggers, refused any change to step ownership, workflow ownership and handoff
-- accountability unless a Phase B change reason was set in the same transaction. Founder ruling
-- that day: "phase A to D where steps to make sure the structure was fine. their freezes or implied
-- limits should be removed totally. i dont want any limits in the workflow". Those are exactly the
-- edits the live organisation needs -- roles have been merged and parked since this register was
-- written -- so they are gone, in
-- scripts/sql/the_last_phase_b_guards_come_off_because_the_founder_removed_every_limit.sql.
--
-- Do not reinstate them. An owner that cannot act is discovered at RUN time, by
-- fn_phase_c_resolve_actor, which is where it actually matters.


-- Only declared transitions.  A transition table with a foreign key already refuses an unknown
-- state; this refuses an undeclared PAIR, which is the thing the state model actually promises.
create or replace function public.fn_phase_b_transition_allowed(p_from text, p_to text)
returns boolean
language sql
stable
as $$
  select exists (select 1 from public.phase_b_workflow_transition
                  where from_state = p_from and to_state = p_to);
$$;

create or replace function public.fn_phase_b_step_transition_allowed(p_from text, p_to text)
returns boolean
language sql
stable
as $$
  select exists (select 1 from public.phase_b_step_transition
                  where from_state = p_from and to_state = p_to);
$$;

-- Closure is refused while anything mandatory is open.  Pure over its arguments so it is
-- testable now; Phase C supplies the run's real step list, blockers and handoffs.
create or replace function public.fn_phase_b_closure_blockers(
  p_workflow_id     text,
  p_completed_steps text[],
  p_open_blockers   bigint,
  p_open_handoffs   bigint
) returns setof text
language plpgsql
stable
as $$
declare v_missing text;
begin
  if p_open_blockers > 0 then
    return next format('%s unresolved blocker(s)', p_open_blockers);
  end if;
  if p_open_handoffs > 0 then
    return next format('%s handoff(s) not accepted', p_open_handoffs);
  end if;
  for v_missing in
    select s.step_id from public.phase_b_workflow_step s
    where s.workflow_id = p_workflow_id
      and s.step_id <> all (coalesce(p_completed_steps, '{}'::text[]))
  loop
    return next format('mandatory step %s not completed', v_missing);
  end loop;
  return;
end $$;

-- No SECURITY DEFINER function is created here, so there is no PUBLIC EXECUTE grant to revoke.
-- The registry is readable structure, not an authority escalation.

comment on table public.phase_b_workflow is
  'Phase B canonical business workflow registry. Structure only: defining a workflow here does not activate it.';
comment on table public.phase_b_crosswalk is
  'What the estate does today versus the canonical workflow, with the command that measured each verdict.';
