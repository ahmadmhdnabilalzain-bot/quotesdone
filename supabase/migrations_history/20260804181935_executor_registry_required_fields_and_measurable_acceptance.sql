-- 4 Aug 2026. `05_SHARED_AUTONOMY_FOUNDATION/04_EXECUTOR_REGISTRY_SPEC.json` requires 12 fields on
-- every executor. `org_action_executor` had three of them - action_class, kind, target - plus
-- `department` and `advisory_safe`. Nine were missing, and that is why the spec's own acceptance
-- list could not be evaluated at all:
--
--   all_active_workflow_side_effects_have_executor
--   all_executors_have_idempotency_test
--   all_high_risk_executors_are_gated
--   all_reversible_executors_define_compensation
--   every_execution_writes_decision_trace
--
-- Each of those asks a question about a field that did not exist. A gate you cannot measure is not
-- a gate; it is a sentence in a document.
--
-- EVERY DEFAULT HERE IS FAIL-CLOSED, and that is deliberate. 55 executors are being back-filled by
-- a migration that cannot know their real risk, so it must not guess in the permissive direction:
--   risk_tier            -> 'high'  (must be lowered deliberately, per executor, with a reason)
--   reversible           -> false   (nothing is assumed undoable)
--   max_attempts         -> 1       (no silent retries of an unproven action)
--   idempotency_strategy -> null    (null means UNDECLARED, and v_executor_registry_gaps counts it)
-- The intended end state is that v_executor_registry_gaps returns zero rows. It currently returns
-- 55. That number is the honest size of the work, and it is now a query rather than an opinion.

alter table public.org_action_executor add column if not exists owner_os text;
alter table public.org_action_executor add column if not exists risk_tier text not null default 'high';
alter table public.org_action_executor add column if not exists reversible boolean not null default false;
alter table public.org_action_executor add column if not exists idempotency_strategy text;
alter table public.org_action_executor add column if not exists timeout_seconds integer not null default 60;
alter table public.org_action_executor add column if not exists max_attempts integer not null default 1;
alter table public.org_action_executor add column if not exists backoff text;
alter table public.org_action_executor add column if not exists required_authority text;
alter table public.org_action_executor add column if not exists compensation_action_class text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='org_action_executor_risk_tier_chk') then
    alter table public.org_action_executor
      add constraint org_action_executor_risk_tier_chk check (risk_tier in ('low','medium','high'));
  end if;
  if not exists (select 1 from pg_constraint where conname='org_action_executor_idem_chk') then
    alter table public.org_action_executor
      add constraint org_action_executor_idem_chk
      check (idempotency_strategy is null or idempotency_strategy in
             ('natural_key','request_hash','external_id','upsert_on_conflict','none_read_only'));
  end if;
end $$;

comment on column public.org_action_executor.risk_tier is
  'low|medium|high. Defaults to high: an executor whose risk nobody has classified is treated as the most dangerous thing it could be.';
comment on column public.org_action_executor.idempotency_strategy is
  'NULL means undeclared, not "none". Counted by v_executor_registry_gaps.';
comment on column public.org_action_executor.required_authority is
  'NULL means resolve from org_authority at execution time. A literal here may only TIGHTEN, never widen.';

-- ------------------------------------------------------------------ the gates, as queries
create or replace view public.v_executor_registry_gaps as
select e.action_class,
       e.department,
       e.kind,
       e.target,
       e.risk_tier,
       e.reversible,
       e.idempotency_strategy is null                                    as idempotency_undeclared,
       (e.reversible and e.compensation_action_class is null)            as reversible_without_compensation,
       (e.risk_tier = 'high' and coalesce(e.advisory_safe,false))        as high_risk_marked_advisory_safe,
       e.owner_os is null                                               as owner_os_undeclared
from public.org_action_executor e
where e.active
  and (e.idempotency_strategy is null
       or (e.reversible and e.compensation_action_class is null)
       or (e.risk_tier = 'high' and coalesce(e.advisory_safe,false))
       or e.owner_os is null);
comment on view public.v_executor_registry_gaps is
  'Executor registry spec acceptance, as a query. Target: zero rows. Added 4 Aug 2026 when the spec was found to be unmeasurable because 9 of its 12 required fields did not exist.';

-- Side effects that a workflow declares but no executor can carry out.
create or replace view public.v_workflow_side_effects_without_executor as
select w.workflow_key, s.step_no, s.action_class
from public.workflow w
join public.workflow_step s on s.workflow_key = w.workflow_key
left join public.org_action_executor e on e.action_class = s.action_class and e.active
where w.active and s.action_class is not null and e.action_class is null;
comment on view public.v_workflow_side_effects_without_executor is
  'all_active_workflow_side_effects_have_executor, as a query. Target: zero rows.';

-- Executions that never wrote a decision trace. Empty today because nothing executes; it becomes
-- the real measurement the moment cos_execute is re-enabled.
create or replace view public.v_executions_without_decision_trace as
select a.id, a.action_class, a.executor, a.correlation_id, a.status, a.created_at
from public.action_execution a
left join public.decision_trace d on d.correlation_id = a.correlation_id
where d.id is null;
comment on view public.v_executions_without_decision_trace is
  'every_execution_writes_decision_trace, as a query. Target: zero rows.';

grant select on public.v_executor_registry_gaps,
                public.v_workflow_side_effects_without_executor,
                public.v_executions_without_decision_trace to service_role;;
