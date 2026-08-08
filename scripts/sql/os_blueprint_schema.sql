-- SPEC FILE #2 — the additive schema the OS blueprint's cross-OS contract needs.
-- Every statement is idempotent; this file is safe to re-apply and is applied to BOTH projects
-- with `node scripts/apply_sql.mjs scripts/sql/os_blueprint_schema.sql --promote --ddl`.

-- ── xos-14 · correlation and causation ────────────────────────────────────────────────────────
-- ELEVEN routines and SEVEN triggers insert into company_event. Setting correlation_id inside
-- fn_emit_event would have covered the seven triggers and missed fn_emit_metric_alerts,
-- fn_emit_budget_exceeded, fn_regulation_propagate, fn_review_submit and the rest — and every
-- writer added later. A column DEFAULT is the only place that catches all of them at once, and it
-- catches the ones nobody has written yet.
--
-- current_setting(..., true) returns NULL rather than raising when the setting is unset, so an
-- event emitted outside any dispatch context still gets a fresh correlation_id and simply starts
-- its own chain. That is the correct reading: an event with no cause IS a chain root.
alter table public.company_event
  alter column correlation_id set default coalesce(
    nullif(current_setting('app.correlation_id', true), '')::uuid,
    gen_random_uuid());

alter table public.company_event
  alter column causation_id set default
    nullif(current_setting('app.causation_event_id', true), '')::bigint;

-- Backfill, and be exact about what it does and does not claim. Grouping historical events by the
-- entity they concern IS a real causal grouping — the 209 review.step rows about one review_chain
-- row genuinely belong to one chain — but it is RECONSTRUCTED, not recorded. causation_id stays
-- NULL for history on purpose: which event caused which was never written down, and inventing an
-- ordering would be the manufactured-evidence failure this brief keeps warning about.
update public.company_event
   set correlation_id = md5(entity_type || ':' || coalesce(entity_id, id::text))::uuid
 where correlation_id is null;

-- ── xos-03 / xos-05 / xos-07 · the delivery record has to carry the answer, not just the fan-out ─
-- os_key: subscriptions resolve to an agent, and the spec's unit is the Operating System.
-- unroutable_reason: 179 of 266 deliveries carried task_id NULL because the subscriber had no
--   department, and a NULL that means "no department" is indistinguishable from one that means
--   "not dispatched yet". Naming the reason is the whole fix.
-- result / closed_at: link 7 is "results returned to the originating event"; without a column for
--   the result there is nowhere for the answer to go.
alter table public.event_delivery add column if not exists os_key             text;
alter table public.event_delivery add column if not exists unroutable_reason  text;
alter table public.event_delivery add column if not exists result             text;
alter table public.event_delivery add column if not exists closed_at          timestamptz;

-- ── xos-04 · assess impact BEFORE acting ──────────────────────────────────────────────────────
-- The dispatcher wrote one fixed title/detail template at action_class='analysis' for every
-- subscriber of every event. Nothing anywhere recorded what the event MEANT to the OS receiving
-- it, which is what link 4 asks for.
create table if not exists public.event_assessment (
  id              bigserial primary key,
  event_id        bigint      not null references public.company_event(id) on delete cascade,
  os_key          text        not null references public.operating_system(os_key),
  agent_key       text,
  severity        text        not null check (severity in ('low','medium','high')),
  impact          text        not null,
  proposed_action text,
  assessed_at     timestamptz not null default now(),
  unique (event_id, os_key)
);
create index if not exists ix_event_assessment_event on public.event_assessment(event_id);

-- ── xos-08 / xos-09 · consolidation and re-prioritisation, keyed on the correlation ────────────
-- Link 8 and link 9 are per-CHAIN, not per-event: the Chief of Staff consolidates what every OS
-- did about one originating event, and that set is exactly one correlation_id.
create table if not exists public.event_rollup (
  correlation_id  uuid        primary key,
  root_event_id   bigint      references public.company_event(id) on delete set null,
  event_type      text,
  os_count        integer     not null default 0,
  tasks_total     integer     not null default 0,
  tasks_closed    integer     not null default 0,
  outcome         text,
  priority_note   text,
  consolidated_at timestamptz not null default now()
);

-- ── comp-11 · variance -> root cause ──────────────────────────────────────────────────────────
-- The 50 "KPI missed" tasks asked an agent to diagnose the cause in prose, so the diagnosis was
-- unqueryable the moment it was written.
alter table public.org_tasks add column if not exists root_cause text;

-- ── comp-07 · declared-but-never-fired interfaces ─────────────────────────────────────────────
-- Founder decision of 6 Aug 2026: emit the interfaces that are internal and could fire today; mark
-- the ones that cannot fire until real customers and suppliers exist. Production has 0 customers
-- and 0 inquiries, so `planned` is a statement of fact about traffic, not an excuse.
alter table public.os_interface add column if not exists planned boolean not null default false;
alter table public.os_interface add column if not exists planned_reason text;

-- ── xos-04 · severity is the OS's OWN declared reading of an input, not a global constant ──────
-- Link 4 says each OS assesses impact before acting. The assessment is per (event_type, os_key),
-- which is exactly what os_interface is already keyed on — so the severity belongs here rather
-- than in a CASE inside the dispatcher, where only one OS's opinion could ever be expressed.
-- Left NULL for outputs: an OS does not assess its own emissions.
alter table public.os_interface add column if not exists severity text
  check (severity in ('low','medium','high'));

update public.os_interface set severity = case
    when event_type in ('security.event','test.failed','sla.breached','budget.exceeded',
                        'health.degraded','regulation.changed')          then 'high'
    when event_type in ('kpi.missed','goal.at_risk','os.health_changed','invoice.received',
                        'outcome.graded','contract.submitted')           then 'medium'
    else 'low' end
 where direction = 'input' and severity is null;

-- ── comp-12 · short-term vs long-term memory ──────────────────────────────────────────────────
-- agent_memory's kinds are instruction/reflection/learned with no horizon, so "short-term memory
-- is distinguishable" could not be answered by the data.
alter table public.agent_memory add column if not exists horizon text
  check (horizon in ('short','long'));

-- ── comp-12 · best practices scoped to the OS that needs them ─────────────────────────────────
alter table public.os_runbooks add column if not exists os_key text
  references public.operating_system(os_key);

-- ── comp-11 · KPIs hang off OS objectives, not only goal_period ───────────────────────────────
alter table public.employee_kpi add column if not exists serves_objective bigint
  references public.os_objective(id);

-- ── comp-03 · objectives carry a computable measure ───────────────────────────────────────────
-- os_objective.measure ALREADY holds company_goals keys for the numeric ones (revenue_annual,
-- supplier_coverage_10x86). measure_sql is for the rest; the join does the work where it can.
alter table public.os_objective add column if not exists measure_sql text;
alter table public.os_objective add column if not exists actual_value numeric;
alter table public.os_objective add column if not exists measured_at timestamptz;

-- ── comp-16 · capacity per OS ─────────────────────────────────────────────────────────────────
-- resource_pool was company-wide (v_resource_pressure -> fn_company_situation), so no OS could
-- report its own capacity. os_key is DERIVED from owner_dept through the same os_department link
-- the rest of the blueprint uses rather than assigned by hand — the mapping already exists and a
-- second hand-written one would be a seventh vocabulary for the same thing.
alter table public.resource_pool add column if not exists os_key text
  references public.operating_system(os_key);

update public.resource_pool rp
   set os_key = od.os_key
  from public.os_department od
 where od.dept_key = rp.owner_dept and rp.os_key is null;
