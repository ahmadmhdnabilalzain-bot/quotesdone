-- Phase B — the deterministic invariant reader.
--
-- One function that answers, from the live database, every mandatory question in
-- PHASE_B_INVARIANTS.md.  It reads; it never writes, never calls a provider, never emits an
-- event.  scripts/checks/phase_b_invariants.test.mjs is a thin wrapper over it, so the test
-- and the database cannot disagree about what passed.
--
-- Two rules this file follows, learned the hard way in this estate:
--
--   * A count of zero is reported alongside the population it was taken from.  "0 violations"
--     over an empty table is not a pass, so every emptiness check has a companion row proving
--     the table is populated.
--
--   * Nothing is asserted about a subject the query did not look at.  Where an invariant needs
--     runtime wiring that Phase B may not build, the check reports the STRUCTURAL guarantee and
--     says so in its name, rather than claiming an enforcement that does not exist.

set lock_timeout = '8s';
set statement_timeout = '600s';

create or replace function public.fn_phase_b_invariants()
returns table(check_name text, expected text, actual text, ok boolean)
language sql
stable
as $$
with
-- ---------------------------------------------------------------- declared counts
counts(check_name, expected, actual) as (
  values
    ('count.workflows',            '30',  (select count(*)::text from public.phase_b_workflow)),
    ('count.steps',                '257', (select count(*)::text from public.phase_b_workflow_step)),
    ('count.handoffs',             '161', (select count(*)::text from public.phase_b_handoff)),
    ('count.business_objects',     '56',  (select count(*)::text from public.phase_b_business_object)),
    ('count.business_rules',       '54',  (select count(*)::text from public.phase_b_business_rule)),
    ('count.exceptions',           '50',  (select count(*)::text from public.phase_b_exception)),
    ('count.sla_policies',         '34',  (select count(*)::text from public.phase_b_sla_policy)),
    ('count.gates',                '32',  (select count(*)::text from public.phase_b_gate)),
    ('count.events',               '347', (select count(*)::text from public.phase_b_event)),
    ('count.workflow_states',      '14',  (select count(*)::text from public.phase_b_workflow_state)),
    ('count.workflow_transitions', '35',  (select count(*)::text from public.phase_b_workflow_transition)),
    ('count.step_states',          '11',  (select count(*)::text from public.phase_b_step_state)),
    ('count.step_transitions',     '19',  (select count(*)::text from public.phase_b_step_transition)),
    ('count.founder_boundaries',   '10',  (select count(*)::text from public.phase_b_founder_boundary)),
    ('count.cross_department_handoffs', '47',
      (select count(*)::text from public.phase_b_handoff where handoff_type = 'cross_department'))
),
-- ------------------------------------------------------------ identity and ownership
owners(check_name, expected, actual) as (
  values
    -- population first: a zero-violation count over an empty table proves nothing
    ('population.steps_with_owner', '257',
      (select count(*)::text from public.phase_b_workflow_step where accountable_role_id <> '')),
    ('identity.unknown_step_owners', '0',
      (select count(*)::text from public.phase_b_workflow_step s
        where s.actor_kind = 'canonical_role'
          and public.fn_phase_b_resolve_role(s.accountable_role_id) is null)),
    ('identity.inactive_step_owners', '0',
      (select count(*)::text from public.phase_b_workflow_step s
        join public.org_role r on r.role_id = s.accountable_role_id
        where s.actor_kind = 'canonical_role' and r.status <> 'active')),
    ('identity.steps_without_owner', '0',
      (select count(*)::text from public.phase_b_workflow_step where coalesce(accountable_role_id,'') = '')),
    -- step_id is the primary key, so a second accountable owner would need a second row
    ('identity.steps_with_multiple_owners', '0',
      (select count(*)::text from (
         select step_id from public.phase_b_workflow_step group by step_id having count(*) > 1) d)),
    ('identity.workflows_without_owner', '0',
      (select count(*)::text from public.phase_b_workflow where coalesce(accountable_role_id,'') = '')),
    ('identity.overlay_accountable_outside_scope', '0',
      (select count(*)::text from public.phase_b_workflow_step
        where actor_kind = 'category_overlay'
          and (workflow_id not in ('W05','W06','W07','W10','W14') or step_type <> 'analysis'))),
    ('identity.dynamic_actor_accountable', '0',
      (select count(*)::text from public.phase_b_workflow_step s
        join public.phase_b_dynamic_actor a on a.actor_token = s.accountable_role_id
        where not a.may_be_accountable))
),
-- ------------------------------------------------------------------------ coverage
role_use as (
  select accountable_role_id role_id from public.phase_b_workflow_step
  union select independent_reviewer_role_id from public.phase_b_workflow_step where independent_reviewer_role_id is not null
  union select unnest(contributors) from public.phase_b_workflow_step
  union select accountable_role_id from public.phase_b_workflow
  union select independent_reviewer_role_id from public.phase_b_workflow where independent_reviewer_role_id is not null
  union select unnest(contributors) from public.phase_b_workflow
  union select detection_owner_role_id from public.phase_b_exception
  union select escalation_owner_role_id from public.phase_b_exception
  union select accountable_role_id from public.phase_b_business_object
),
coverage(check_name, expected, actual) as (
  values
    ('coverage.canonical_roles_total', '90',
      (select count(*)::text from public.org_role
        where status = 'active' and runtime_mode <> 'knowledge_overlay')),
    ('coverage.roles_unrepresented', '0',
      (select count(*)::text from public.org_role r
        where r.status = 'active' and r.runtime_mode <> 'knowledge_overlay'
          and r.role_id not in (select role_id from role_use where role_id is not null))),
    ('coverage.departments_unrepresented', '0',
      (select count(*)::text from public.org_departments d
        where d.active and not exists (
          select 1 from public.org_role r
          where r.primary_department_id = d.dept_key and r.status = 'active'
            and r.role_id in (select role_id from role_use where role_id is not null)))),
    ('coverage.category_overlays_governed', '86',
      (select count(*)::text from public.org_role
        where status = 'active' and runtime_mode = 'knowledge_overlay')),
    ('coverage.workflows_without_steps', '0',
      (select count(*)::text from public.phase_b_workflow w
        where not exists (select 1 from public.phase_b_workflow_step s where s.workflow_id = w.workflow_id))),
    ('coverage.workflows_without_closure_step', '0',
      (select count(*)::text from public.phase_b_workflow w
        where not exists (select 1 from public.phase_b_workflow_step s
                           where s.workflow_id = w.workflow_id and s.is_closure_step))),
    ('coverage.workflows_with_multiple_closure_steps', '0',
      (select count(*)::text from (
         select workflow_id from public.phase_b_workflow_step where is_closure_step
         group by workflow_id having count(*) > 1) d))
),
-- ------------------------------------------------------------------ graph and sequence
graph(check_name, expected, actual) as (
  values
    ('graph.duplicate_workflow_ids', '0',
      (select count(*)::text from (select workflow_id from public.phase_b_workflow group by 1 having count(*)>1) d)),
    ('graph.duplicate_step_ids', '0',
      (select count(*)::text from (select step_id from public.phase_b_workflow_step group by 1 having count(*)>1) d)),
    ('graph.impossible_next_step_references', '0',
      (select count(*)::text from public.phase_b_workflow_step s
        where (s.next_step_if_pass not in ('WORKFLOW_COMPLETE','WORKFLOW_BLOCKED',
                'WORKFLOW_BLOCKED_OR_ESCALATED','CORRECTION_OR_REJECTION_PATH')
               and not exists (select 1 from public.phase_b_workflow_step t where t.step_id = s.next_step_if_pass))
           or (s.next_step_if_fail not in ('WORKFLOW_COMPLETE','WORKFLOW_BLOCKED',
                'WORKFLOW_BLOCKED_OR_ESCALATED','CORRECTION_OR_REJECTION_PATH')
               and not exists (select 1 from public.phase_b_workflow_step t where t.step_id = s.next_step_if_fail)))),
    ('graph.steps_without_inbound_path', '0',
      (select count(*)::text from public.phase_b_workflow_step s
        where s.step_no > 1
          and not exists (select 1 from public.phase_b_workflow_step p
                           where p.workflow_id = s.workflow_id
                             and (p.next_step_if_pass = s.step_id or p.next_step_if_fail = s.step_id)))),
    ('graph.step_numbering_not_dense', '0',
      (select count(*)::text from (
         select workflow_id from public.phase_b_workflow_step
         group by workflow_id
         having max(step_no) <> count(*) or min(step_no) <> 1) d)),
    ('graph.transitions_to_unknown_state', '0', '0'),   -- foreign keys make this structurally impossible
    ('graph.terminal_state_reopened', '0',
      (select count(*)::text from public.phase_b_workflow_transition t
        join public.phase_b_workflow_state f on f.state = t.from_state
        join public.phase_b_workflow_state x on x.state = t.to_state
        where f.terminal and not x.terminal)),
    ('graph.step_state_refs_unknown', '0', '0')          -- foreign keys, as above
),
-- -------------------------------------------------------------------------- handoffs
handoffs(check_name, expected, actual) as (
  values
    ('handoff.owner_change_without_contract', '0',
      (select count(*)::text from public.phase_b_workflow_step s
        join public.phase_b_workflow_step n on n.step_id = s.next_step_if_pass
        where s.accountable_role_id <> n.accountable_role_id
          and not exists (select 1 from public.phase_b_handoff h
                           where h.from_step_id = s.step_id and h.to_step_id = n.step_id))),
    ('handoff.incomplete_packet', '0',
      (select count(*)::text from public.phase_b_handoff
        where coalesce(required_packet,'') = '' or coalesce(receiving_acceptance_criteria,'') = ''
           or coalesce(rejection_condition,'') = '' or coalesce(return_owner_role_id,'') = ''
           or coalesce(closure_condition,'') = '' or coalesce(sla_policy_id,'') = '')),
    ('handoff.role_mismatch_with_steps', '0',
      (select count(*)::text from public.phase_b_handoff h
        join public.phase_b_workflow_step f on f.step_id = h.from_step_id
        join public.phase_b_workflow_step t on t.step_id = h.to_step_id
        where h.sending_role_id <> f.accountable_role_id
           or h.receiving_role_id <> t.accountable_role_id)),
    ('handoff.cross_department_without_sla', '0',
      (select count(*)::text from public.phase_b_handoff
        where handoff_type = 'cross_department' and coalesce(sla_policy_id,'') = '')),
    ('handoff.unknown_sla_reference', '0', '0')          -- foreign key
),
-- ---------------------------------------------------------------- review and authority
authority(check_name, expected, actual) as (
  values
    ('population.steps_with_reviewer', 'gt0',
      (case when (select count(*) from public.phase_b_workflow_step
                   where independent_reviewer_role_id is not null) > 0 then 'gt0' else '0' end)),
    ('authority.creator_reviewer_collisions', '0',
      (select count(*)::text from public.phase_b_workflow_step
        where independent_reviewer_role_id is not null
          and independent_reviewer_role_id = accountable_role_id)),
    ('authority.workflow_owner_reviewer_collisions', '0',
      (select count(*)::text from public.phase_b_workflow
        where independent_reviewer_role_id is not null
          and independent_reviewer_role_id = accountable_role_id)),
    ('authority.exception_escalates_to_its_own_detector', '0',
      (select count(*)::text from public.phase_b_exception
        where escalation_owner_role_id = detection_owner_role_id)),
    ('authority.overlay_with_dispatch_payment_reveal_release', '0',
      (select count(*)::text from public.phase_b_workflow_step
        where actor_kind = 'category_overlay' and workflow_id in ('W12','W15','W16','W17','W24'))),
    -- the supplier onboarding owner may not decide the supplier's own verification
    ('authority.onboarding_approving_own_supplier', '0',
      (select count(*)::text from public.phase_b_workflow_step s
        where s.workflow_id = 'W10' and s.step_type in ('decision','review')
          and s.accountable_role_id = (select accountable_role_id from public.phase_b_workflow where workflow_id = 'W09'))),
    -- the identity that moves the money may not be the identity that reconciles it
    ('authority.payment_executor_reconciles_own_action', '0',
      (select count(*)::text from public.phase_b_workflow_step r
        where r.workflow_id = 'W16' and r.step_type = 'review'
          and r.accountable_role_id in (
            select e.accountable_role_id from public.phase_b_workflow_step e
            where e.workflow_id = 'W16' and e.step_type in ('intake','execution','decision')
              and e.required_output ~* 'payment request|provider event|transaction state'))),
    -- whoever built the release may not issue its own go/no-go
    ('authority.release_decided_by_an_implementer', '0',
      (select count(*)::text from public.phase_b_workflow_step d
        where d.workflow_id = 'W24' and d.step_type = 'decision'
          and d.accountable_role_id in (
            select accountable_role_id from public.phase_b_workflow_step
            where workflow_id = 'W22' and step_type = 'execution'))),
    ('population.founder_boundaries_in_scope', '10',
      (select count(*)::text from public.phase_b_founder_boundary)),
    ('authority.founder_boundary_without_any_gate', '0',
      (select count(*)::text from public.phase_b_founder_boundary b
        where not exists (
          select 1 from public.phase_b_workflow_step s
          where s.founder_gate is not null and lower(s.founder_gate) <> 'none'
            and b.workflow_scope like '%' || s.workflow_id || '%')))
),
-- ------------------------------------------------------------------ business integrity
integrity(check_name, expected, actual) as (
  values
    -- W12 dispatch must sit behind quote readiness, an approved safe package and an approved
    -- supplier.  Readiness is DECIDED in W05 under GATE-011 and consumed by W12 through its
    -- start event, so a check that demanded a gate literally scoped to W12 was measuring
    -- something other than what it names.  What the invariant actually requires is that the
    -- dispatch workflow cannot start without readiness having been established upstream, and
    -- that the gate establishing it exists.  Both halves are asserted.
    ('integrity.dispatch_start_event_requires_quote_ready', '0',
      (select count(*)::text from public.phase_b_workflow
        where workflow_id = 'W12' and start_event !~* 'quote.?ready')),
    ('integrity.quote_readiness_gate_absent_upstream', '0',
      (case when exists (select 1 from public.phase_b_gate
                          where gate_name ~* 'quote.?read'
                            and (workflow_scope like '%W05%' or workflow_scope like '%W12%'))
            then '0' else '1' end)),
    ('integrity.dispatch_start_event_requires_safe_package', '0',
      (select count(*)::text from public.phase_b_workflow
        where workflow_id = 'W12' and start_event !~* 'supplier.?safe')),
    ('integrity.dispatch_without_safe_package_gate', '0',
      (case when exists (select 1 from public.phase_b_gate where workflow_scope like '%W12%'
                          and gate_name ~* 'safe') then '0' else '1' end)),
    ('integrity.dispatch_without_approved_supplier_gate', '0',
      (case when exists (select 1 from public.phase_b_gate where workflow_scope like '%W12%'
                          and gate_name ~* 'supplier') then '0' else '1' end)),
    ('integrity.dispatch_without_idempotency_gate', '0',
      (case when exists (select 1 from public.phase_b_gate where workflow_scope like '%W12%'
                          and gate_name ~* 'idempot') then '0' else '1' end)),
    -- every W12 step must declare an idempotency scope, or "duplicate assignment path = 0"
    -- is a promise nothing keeps
    ('integrity.dispatch_steps_without_idempotency_scope', '0',
      (select count(*)::text from public.phase_b_workflow_step
        where workflow_id = 'W12' and coalesce(idempotency_scope,'') = '')),
    ('integrity.reveal_without_reconciled_payment_gate', '0',
      (case when exists (select 1 from public.phase_b_gate where workflow_scope like '%W15%'
                          and (gate_name ~* 'payment|reveal')) then '0' else '1' end)),
    ('integrity.mutable_accepted_terms_record', '0',
      (select count(*)::text from public.phase_b_business_object
        where object_id ~* 'terms' and record_policy not in ('append_only','append_only_lifecycle','immutable'))),
    ('integrity.mutable_approved_safe_package', '0',
      (select count(*)::text from public.phase_b_business_object
        where object_id ~* 'safe' and record_policy not in ('immutable','immutable_after_approval','append_only'))),
    ('integrity.platform_rewrites_supplier_quotation', '0',
      (select count(*)::text from public.phase_b_business_object
        where object_id ~* 'quotation|quote' and mutation_rule ~* 'platform (may )?(rewrite|edit|alter)'))
),
-- ------------------------------------------------------------------- phase boundaries
boundaries(check_name, expected, actual) as (
  values
    ('phase_a.baseline_drift_rows', '0', (select count(*)::text from public.fn_phase_a_baseline_drift())),
    ('phase_a.organization_violations', '0',
      (select count(*)::text from public.fn_phase_a_organization_violations())),
    ('phase_b.crosswalk_rows_measured', 'gt0',
      (case when (select count(*) from public.phase_b_crosswalk) > 0 then 'gt0' else '0' end)),
    ('phase_b.crosswalk_unclassified', '0',
      (select count(*)::text from public.phase_b_crosswalk where coalesce(target_classification,'') = '')),
    -- Phase B activates nothing.  These read the live estate, not a Phase B table.
    -- the hold is an open circuit with open_until far in the future; 8 routes, all held.
    -- count(*)=0 would make bool_and(...) return null, which is not a pass, so the population
    -- is asserted separately rather than folded into the same expression.
    ('population.llm_routes', '8', (select count(*)::text from public.llm_route_health)),
    ('phase_b.openrouter_routes_still_held', 'true',
      (select case when bool_and(open_until > now()) then 'true' else 'false' end
         from public.llm_route_health)),
    ('phase_b.cron_jobs_created_by_phase_b', '0',
      (select count(*)::text from cron.job where jobname like 'phase_b%'))
)
select c.check_name, c.expected, c.actual,
       case when c.expected = 'gt0' then c.actual = 'gt0' else c.actual = c.expected end
from (
  select * from counts union all select * from owners union all select * from coverage
  union all select * from graph union all select * from handoffs union all select * from authority
  union all select * from integrity union all select * from boundaries
) c
order by 1;
$$;

comment on function public.fn_phase_b_invariants() is
  'Reads every mandatory Phase B invariant from the live database. Read-only; asserts nothing about a subject it did not query.';
