-- =================================================================================================
-- Phase D — D11. Two hundred and seventy-three events that say CONNECTED and have never happened.
--
-- MEASURED FIRST, ON PRODUCTION:
--
--   frozen events in phase_b_event                                347
--   rows in phase_c_event_binding                                 347
--   bindings whose connection_status says CONNECTED               287
--   distinct event_ids that have EVER appeared in the outbox       14
--
-- So 273 events are labelled CONNECTED and have never been observed. `connection_status` is a claim
-- about STRUCTURE — a producer exists, a consumer role is named, an outbox writer is named — and it
-- is being read as though it said the event happens. Those are different questions and one column
-- was answering both.
--
-- §10 of the brief asks for exactly this separation: a structural status AND a runtime observation
-- status, per event, with the requirement `registry-only event reported runtime-observed = 0`.
--
-- THE STRUCTURAL COLUMN IS NOT REWRITTEN. `phase_c_event_binding` is Phase C's and its CONNECTED
-- verdict is true about what it actually measures. What is added is a second column beside it that
-- answers the question the first one was being asked, and it is derived from
-- `phase_c_event_outbox` — the only place an emission leaves a trace — so it cannot be asserted.
--
-- NOTHING IS EMITTED TO PRODUCE THIS. The reconciliation reads the outbox; it does not write to it.
-- An event fabricated to make its own row read OBSERVED would be the defect this exists to remove.
-- =================================================================================================

begin;

create table if not exists public.phase_d_event_reconciliation (
  event_id                  text primary key,
  event_name                text not null,
  workflow_id               text not null,
  factual_state_change      text not null,
  producer                  text not null,
  producer_resolves         boolean not null,
  primary_consumer_role_id  text,
  consumer_resolves         boolean not null,
  structural_status         text not null,
  runtime_observation       text not null,
  emissions_observed        bigint not null default 0,
  first_observed_at         timestamptz,
  last_observed_at          timestamptz,
  outbox_relation           text not null,
  dedupe_key                text,
  idempotency_mechanism     text not null,
  correlation_available     boolean not null,
  causation_available       boolean not null,
  trace_available           boolean not null,
  external_effect_relation  text not null,
  cancellation_behaviour    text not null,
  is_self_loop              boolean not null,
  reconciled_at             timestamptz not null default now(),
  constraint phase_d_event_reconciliation_event_fkey
    foreign key (event_id) references public.phase_b_event(event_id) on delete cascade,
  constraint phase_d_event_reconciliation_runtime_ck
    check (runtime_observation in ('OBSERVED_IN_OUTBOX','NEVER_OBSERVED')),
  constraint phase_d_event_reconciliation_factual_ck
    check (btrim(factual_state_change) <> '')
);

comment on table public.phase_d_event_reconciliation is
  'Phase D §10: 347 events with a STRUCTURAL status and a separate RUNTIME OBSERVATION status derived from phase_c_event_outbox. CONNECTED is a claim about structure; only the outbox can say an event has happened.';

insert into public.phase_d_event_reconciliation (
  event_id, event_name, workflow_id, factual_state_change, producer, producer_resolves,
  primary_consumer_role_id, consumer_resolves, structural_status, runtime_observation,
  emissions_observed, first_observed_at, last_observed_at, outbox_relation, dedupe_key,
  idempotency_mechanism, correlation_available, causation_available, trace_available,
  external_effect_relation, cancellation_behaviour, is_self_loop)
select
  e.event_id,
  e.event_name,
  e.workflow_id,
  -- The factual state change the event represents is the frozen trigger prose. An event whose
  -- trigger says nothing is not an event, and the CHECK above refuses the row rather than storing
  -- a blank and counting it.
  coalesce(nullif(btrim(e.trigger), ''), '(the frozen registry states no trigger)'),
  e.emitted_by,
  -- `workflow_engine` and the other machine producers are not canonical roles and are not expected
  -- to resolve; this records which is which rather than scoring a machine producer as a defect.
  coalesce((select true from public.fn_phase_c_resolve_actor(e.emitted_by) a
             where a.kind = 'canonical'), false),
  e.primary_consumer_role_id,
  coalesce((select true from public.fn_phase_c_resolve_actor(e.primary_consumer_role_id) a
             where a.kind = 'canonical'), false),
  coalesce(b.connection_status, 'NO_PHASE_C_BINDING'),
  -- THE MEASUREMENT. Not the claim.
  case when o.n > 0 then 'OBSERVED_IN_OUTBOX' else 'NEVER_OBSERVED' end,
  coalesce(o.n, 0),
  o.first_at,
  o.last_at,
  coalesce(b.outbox_writer, 'public.phase_c_event_outbox'),
  e.dedupe_key,
  coalesce(b.dedupe_enforced, '(none declared)'),
  -- Correlation, causation and trace are columns on the outbox, so their availability is a fact
  -- about the relation and is read from the catalogue rather than declared.
  exists (select 1 from pg_attribute a where a.attrelid='public.phase_c_event_outbox'::regclass
           and a.attname='correlation_id' and a.attnum>0 and not a.attisdropped),
  exists (select 1 from pg_attribute a where a.attrelid='public.phase_c_event_outbox'::regclass
           and a.attname='causation_id' and a.attnum>0 and not a.attisdropped),
  exists (select 1 from pg_attribute a where a.attrelid='public.phase_c_event_outbox'::regclass
           and a.attname='trace_id' and a.attnum>0 and not a.attisdropped),
  -- An event is only related to an external effect if a Phase D step in its workflow declares one.
  case when exists (select 1 from public.phase_d_step_effect se
                     where se.workflow_id = e.workflow_id
                       and se.expected_effect_type = 'EXTERNAL_EFFECT_INTENT')
       then 'workflow declares an EXTERNAL_EFFECT_INTENT step; every such effect is mock and the outbox carries no provider call'
       else 'no external effect declared anywhere in this workflow' end,
  -- fn_kernel_cancel is the registered writer that cancels queued outbox rows beneath a cancelled
  -- run, so a cancellation does not leak an event. Named from kernel_write_authority, not assumed.
  coalesce((select 'queued rows cancelled by ' || w.routine_name
              from public.kernel_write_authority w
             where w.table_name = 'phase_c_event_outbox' and w.routine_name = 'fn_kernel_cancel'),
           'NO REGISTERED CANCELLATION WRITER'),
  -- An event whose producer and consumer are the same identity is a report addressed to its author.
  (e.emitted_by is not distinct from e.primary_consumer_role_id)
from public.phase_b_event e
left join public.phase_c_event_binding b on b.event_id = e.event_id
left join lateral (
  select count(*) n, min(created_at) first_at, max(created_at) last_at
    from public.phase_c_event_outbox o where o.event_id = e.event_id
) o on true
on conflict (event_id) do update set
  structural_status   = excluded.structural_status,
  runtime_observation = excluded.runtime_observation,
  emissions_observed  = excluded.emissions_observed,
  first_observed_at   = excluded.first_observed_at,
  last_observed_at    = excluded.last_observed_at,
  producer_resolves   = excluded.producer_resolves,
  consumer_resolves   = excluded.consumer_resolves,
  is_self_loop        = excluded.is_self_loop,
  reconciled_at       = now();

delete from public.phase_d_event_reconciliation r
 where not exists (select 1 from public.phase_b_event e where e.event_id = r.event_id);

-- ---- the board ----------------------------------------------------------------------------------

create or replace function public.fn_phase_d_event_state()
returns table(check_name text, expected text, actual text, ok boolean)
language sql stable
set search_path to 'public', 'pg_temp'
as $fn$
  with ev as (select count(*) n from public.phase_b_event),
       rc as (select count(*) n from public.phase_d_event_reconciliation)
  select 'events_reconciled', (select n::text from ev), (select n::text from rc),
         (select n from rc) = (select n from ev)
  union all
  select 'reconciliations_with_no_frozen_event', '0',
         (select count(*)::text from public.phase_d_event_reconciliation r
           where not exists (select 1 from public.phase_b_event e where e.event_id = r.event_id)),
         not exists (select 1 from public.phase_d_event_reconciliation r
                      where not exists (select 1 from public.phase_b_event e
                                         where e.event_id = r.event_id))
  union all
  select 'events_with_no_factual_state_change', '0',
         (select count(*)::text from public.phase_d_event_reconciliation
           where factual_state_change = '(the frozen registry states no trigger)'),
         not exists (select 1 from public.phase_d_event_reconciliation
                      where factual_state_change = '(the frozen registry states no trigger)')
  union all
  select 'event_self_loops', '0',
         (select count(*)::text from public.phase_d_event_reconciliation where is_self_loop),
         not exists (select 1 from public.phase_d_event_reconciliation where is_self_loop)
  union all
  -- THE CHECK THIS FILE EXISTS FOR. A row may not say it was observed unless the outbox says so.
  select 'registry_only_events_reported_runtime_observed', '0',
         (select count(*)::text from public.phase_d_event_reconciliation
           where runtime_observation = 'OBSERVED_IN_OUTBOX' and emissions_observed = 0),
         not exists (select 1 from public.phase_d_event_reconciliation
                      where runtime_observation = 'OBSERVED_IN_OUTBOX' and emissions_observed = 0)
  union all
  select 'events_with_no_registered_cancellation_writer', '0',
         (select count(*)::text from public.phase_d_event_reconciliation
           where cancellation_behaviour = 'NO REGISTERED CANCELLATION WRITER'),
         not exists (select 1 from public.phase_d_event_reconciliation
                      where cancellation_behaviour = 'NO REGISTERED CANCELLATION WRITER')
  union all
  select 'events_with_no_dedupe_key', '0',
         (select count(*)::text from public.phase_d_event_reconciliation
           where coalesce(btrim(dedupe_key),'') = ''),
         not exists (select 1 from public.phase_d_event_reconciliation
                      where coalesce(btrim(dedupe_key),'') = '')
  union all
  -- DISCLOSED, AND THE WHOLE POINT. The gap between what the structure claims and what has happened
  -- is a number the founder can see rather than a word that hides it. It is NOT ratcheted to zero:
  -- closing it means running the business automation that is deliberately held.
  select 'events_structurally_connected_but_never_observed', 'informational — automation is held',
         (select count(*)::text from public.phase_d_event_reconciliation
           where structural_status = 'CONNECTED' and runtime_observation = 'NEVER_OBSERVED'), true
  union all
  select 'events_observed_at_runtime', 'informational',
         (select count(*)::text from public.phase_d_event_reconciliation
           where runtime_observation = 'OBSERVED_IN_OUTBOX'), true;
$fn$;

revoke all on function public.fn_phase_d_event_state() from public;
grant execute on function public.fn_phase_d_event_state() to service_role;
revoke all on public.phase_d_event_reconciliation from anon, authenticated;
grant select on public.phase_d_event_reconciliation to service_role;
alter table public.phase_d_event_reconciliation enable row level security;

-- ---- positive control, on this deployment --------------------------------------------------------

do $ctl$
declare v_n int; v_obs int; v_claim int;
begin
  select count(*) into v_n from public.phase_d_event_reconciliation;
  if v_n <> 347 then
    raise exception 'D11: % events reconciled; the frozen model holds 347', v_n;
  end if;

  select count(*) into v_obs from public.phase_d_event_reconciliation
   where runtime_observation = 'OBSERVED_IN_OUTBOX';
  select count(*) into v_claim from public.phase_d_event_reconciliation
   where structural_status = 'CONNECTED';

  -- The separation has to be real. If the observation column simply agreed with the structural one
  -- it would be the same claim under a second name, which is the defect this file was written for.
  if v_obs = v_claim then
    raise exception 'D11: runtime observation (%) equals the structural claim (%) — the second column is not measuring anything',
      v_obs, v_claim;
  end if;

  -- And it must not be measuring nothing at all: some events HAVE been emitted.
  if v_obs = 0 then
    raise exception 'D11: no event is recorded as observed, but phase_c_event_outbox holds % row(s)',
      (select count(*) from public.phase_c_event_outbox);
  end if;

  raise notice 'D11: 347 reconciled; % structurally CONNECTED, % actually observed in the outbox.',
    v_claim, v_obs;
end $ctl$;

commit;
