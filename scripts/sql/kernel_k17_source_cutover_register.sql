-- K17 — every autonomous source given exactly one class, one adapter and one reason.
--
-- THE POPULATION, AND A COUNT THAT DOES NOT MATCH THE BRIEF.
--
-- The brief says "the 52 active autonomous sources". No definition over this estate yields 52.
-- Measured on production, 17 Aug 2026:
--
--   live AND creates business work AND not a founder command surface .... 41
--   the same, including the 2 founder command surfaces .................. 43
--   connection_state = CONNECTED_ACTIVE ................................. 49
--   CONNECTED_ACTIVE or INTENTIONALLY_RETIRED ........................... 51
--   CONNECTED_ACTIVE or CONNECTED_INACTIVE .............................. 62
--   THE POPULATION IN THIS FILE ......................................... 67
--   everything inventoried by K10 ....................................... 482
--
-- Rather than pick whichever definition rounds to 52, this file takes the STRICT SUPERSET of all
-- of them: every source carrying an adapter in any state (62), plus the 2 deliberately retired,
-- plus the 3 that are live and create business work but were never connected. 67 rows. Whatever
-- population of 52 the brief meant, it is inside this one — and the number is stated with its
-- definition rather than asserted, because an unbounded count from a bounded measurement is the
-- defect this estate has paid for more than once.
--
-- THE FOUR CLASSES, and the one rule each carries:
--
--   A NEW_WORK_REQUEST         may call fn_kernel_trigger_submit and nothing else
--   B EXISTING_WORKFLOW_SIGNAL may call fn_kernel_signal_submit and nothing else — it may NEVER
--                              start a workflow, which is why K16 exists
--   C READ_ONLY_MONITOR        may call NEITHER. It observes, it may update approved operational
--                              state, and when a threshold is crossed it raises a separate class-A
--                              request with its own dedupe key and evidence
--   D RETIRE_OR_HISTORICAL     may call neither, and is not to be revived
--
-- The class is not decoration: fn_kernel_source_cutover_state checks each row against the rule its
-- own class carries, so a source labelled C that starts writing business work fails a check rather
-- than sitting quietly under a green label.
--
-- WHAT THIS FILE DOES NOT DO. It does not activate anything. Eighteen of the 67 are switched off
-- today, and they stay switched off: "do not activate a source that was previously disabled merely
-- because an adapter exists" is the founder's instruction and it is also just correct — an adapter
-- is a door, not a decision to walk through it.
--
-- The seed is generated, never typed: scripts/phase_c/gen_k17.mjs writes BOTH
-- scripts/sql/kernel_k17_source_cutover_seed.sql and
-- docs/phase-c-kernel/ACTIVE_SOURCE_CUTOVER_MATRIX.csv from one classification file, and refuses
-- to emit if a single source in the population is unclassified or a classification names a source
-- that is not in it. The CSV and the table cannot disagree.
--
-- Rollback: scripts/sql/rollback/kernel_k17_source_cutover_register.rollback.sql

begin;

create table if not exists public.phase_c_source_cutover (
  source_component_id         text primary key,
  source_type                 text not null,
  source_class                text not null,
  current_entry_point         text not null,
  current_direct_side_effects text not null,
  target_kernel_adapter       text not null,
  target_workflow             text not null,
  target_step_or_signal       text not null,
  accountable_role            text,
  system_actor                text not null references public.phase_c_system_actor(system_actor_id),
  idempotency_key             text not null,
  trace_policy                text not null references public.phase_c_trace_policy(trace_policy_id),
  current_activation          text not null,
  cutover_action              text not null,
  rollback                    text not null,
  status                      text not null,
  classification_reason       text not null,
  evidence                    text not null,
  recorded_at                 timestamptz not null default now(),
  constraint phase_c_source_class_known check (source_class in (
    'A NEW_WORK_REQUEST','B EXISTING_WORKFLOW_SIGNAL',
    'C READ_ONLY_MONITOR','D RETIRE_OR_HISTORICAL')),
  constraint phase_c_source_activation_known check (current_activation in ('ACTIVE','DISABLED')),
  -- The class IS the constraint. A class-C or class-D row that names a kernel adapter is a
  -- contradiction, and it is refused at write time rather than reported later.
  constraint phase_c_source_adapter_matches_class check (
    case
      when source_class = 'A NEW_WORK_REQUEST'         then target_kernel_adapter = 'fn_kernel_trigger_submit'
      when source_class = 'B EXISTING_WORKFLOW_SIGNAL' then target_kernel_adapter = 'fn_kernel_signal_submit'
      else target_kernel_adapter not like 'fn_kernel%'
    end),
  constraint phase_c_source_reason_is_not_a_label check (length(btrim(classification_reason)) >= 40)
);

comment on table public.phase_c_source_cutover is
  'K17. One row per autonomous source, carrying its class (A new work / B signal on an existing '
  'run / C read-only monitor / D retired), the single kernel adapter that class is allowed to '
  'call, the workflow and trigger-or-signal vocabulary it maps to, its idempotency key shape, its '
  'trace policy, whether it is switched on TODAY, and the reason the class is what it is. '
  'Generated from scripts/phase_c/source_classification.mjs together with '
  'docs/phase-c-kernel/ACTIVE_SOURCE_CUTOVER_MATRIX.csv, so the CSV and this table cannot drift.';

alter table public.phase_c_source_cutover enable row level security;
revoke all on public.phase_c_source_cutover from public, anon, authenticated;
grant select on public.phase_c_source_cutover to service_role;

-- ------------------------------------------------------------------ the invariant board
create or replace function public.fn_kernel_source_cutover_state()
returns table (check_name text, expected text, actual text, ok boolean)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $k17_state$
with
-- The population is recomputed from the catalogue every time, never read off this table: a check
-- whose denominator is a column the same migration writes goes green by emptying itself.
pop as (
  select * from public.v_kernel_trigger_source_derived
   where connection_state in ('CONNECTED_ACTIVE','CONNECTED_INACTIVE','INTENTIONALLY_RETIRED')
      or (coalesce(is_active_now,false) and coalesce(creates_work_now,false)
          and coalesce(disposition,'') <> 'FOUNDER_COMMAND_SURFACE')
      -- ...or it is already classified. The register may GROW when a new source appears and may
      -- never silently SHED a row because a flag on it moved.
      or source_key in (select source_component_id from public.phase_c_source_cutover)
),
c as (select * from public.phase_c_source_cutover),
act as (select * from c where current_activation = 'ACTIVE')
select 'sources_in_the_population_with_no_classification'::text,
       '0 of ' || (select count(*)::text from pop),
       (select count(*)::text from pop p
         where not exists (select 1 from c where c.source_component_id = p.source_key))
         || ' of ' || (select count(*)::text from pop),
       (select count(*) = 0 from pop p
         where not exists (select 1 from c where c.source_component_id = p.source_key))
union all
-- NOT 'classified but not in the population'. That check failed the moment K17 corrected three
-- recorded_creates_work flags, because the population predicate READS that column: correcting a
-- measurement made two rows fall out of the denominator of the check that was meant to police
-- them. A check whose population is defined by a column the same migration rewrites goes green,
-- or red, by moving its own goalposts.
--
-- What is actually a defect is a register row for a source that does not exist AT ALL. A source
-- whose flags changed is not one; that is the register doing its job.
select 'classified_sources_that_are_not_in_the_k10_inventory',
       '0 of ' || (select count(*)::text from c),
       (select count(*)::text from c
         where not exists (select 1 from public.kernel_trigger_source k
                            where k.source_key = c.source_component_id))
         || ' of ' || (select count(*)::text from c),
       (select count(*) = 0 from c
         where not exists (select 1 from public.kernel_trigger_source k
                            where k.source_key = c.source_component_id))
union all
select 'class_split',
       'reported, never counted as one backlog',
       (select string_agg(source_class || ' ' || n::text, '; ' order by source_class)
          from (select source_class, count(*) n from c group by 1) d),
       true
union all
select 'active_new_work_sources_not_pointed_at_the_trigger_adapter',
       '0 of ' || (select count(*)::text from act where source_class = 'A NEW_WORK_REQUEST'),
       (select count(*)::text from act
         where source_class = 'A NEW_WORK_REQUEST' and target_kernel_adapter <> 'fn_kernel_trigger_submit')
         || ' of ' || (select count(*)::text from act where source_class = 'A NEW_WORK_REQUEST'),
       (select count(*) = 0 from act
         where source_class = 'A NEW_WORK_REQUEST' and target_kernel_adapter <> 'fn_kernel_trigger_submit')
union all
select 'active_existing_run_signals_not_pointed_at_the_signal_adapter',
       '0 of ' || (select count(*)::text from act where source_class = 'B EXISTING_WORKFLOW_SIGNAL'),
       (select count(*)::text from act
         where source_class = 'B EXISTING_WORKFLOW_SIGNAL' and target_kernel_adapter <> 'fn_kernel_signal_submit')
         || ' of ' || (select count(*)::text from act where source_class = 'B EXISTING_WORKFLOW_SIGNAL'),
       (select count(*) = 0 from act
         where source_class = 'B EXISTING_WORKFLOW_SIGNAL' and target_kernel_adapter <> 'fn_kernel_signal_submit')
union all
-- The one that matters for class C, and it is measured from the CATALOGUE, not from the label.
-- A monitor that starts calling a writer fails here even though its row still says READ_ONLY.
select 'active_read_only_monitors_that_write_business_work',
       '0 of ' || (select count(*)::text from act where source_class = 'C READ_ONLY_MONITOR'),
       (select count(*)::text from act a join pop p on p.source_key = a.source_component_id
         where a.source_class = 'C READ_ONLY_MONITOR' and coalesce(p.creates_work_now,false))
         || ' of ' || (select count(*)::text from act where source_class = 'C READ_ONLY_MONITOR'),
       (select count(*) = 0 from act a join pop p on p.source_key = a.source_component_id
         where a.source_class = 'C READ_ONLY_MONITOR' and coalesce(p.creates_work_now,false))
union all
select 'retired_sources_that_are_still_live_and_writing',
       '0 of ' || (select count(*)::text from c where source_class = 'D RETIRE_OR_HISTORICAL'),
       (select count(*)::text from c join pop p on p.source_key = c.source_component_id
         where c.source_class = 'D RETIRE_OR_HISTORICAL' and coalesce(p.creates_work_now,false))
         || ' of ' || (select count(*)::text from c where source_class = 'D RETIRE_OR_HISTORICAL'),
       (select count(*) = 0 from c join pop p on p.source_key = c.source_component_id
         where c.source_class = 'D RETIRE_OR_HISTORICAL' and coalesce(p.creates_work_now,false))
union all
select 'class_A_sources_whose_trigger_type_is_not_registered',
       '0 of ' || (select count(*)::text from c where source_class = 'A NEW_WORK_REQUEST'),
       (select count(*)::text from c where source_class = 'A NEW_WORK_REQUEST'
          and not exists (select 1 from public.kernel_trigger_type t
                           where t.trigger_type = c.target_step_or_signal))
         || ' of ' || (select count(*)::text from c where source_class = 'A NEW_WORK_REQUEST'),
       (select count(*) = 0 from c where source_class = 'A NEW_WORK_REQUEST'
          and not exists (select 1 from public.kernel_trigger_type t
                           where t.trigger_type = c.target_step_or_signal))
union all
select 'class_B_sources_whose_signal_type_is_not_registered',
       '0 of ' || (select count(*)::text from c where source_class = 'B EXISTING_WORKFLOW_SIGNAL'),
       (select count(*)::text from c where source_class = 'B EXISTING_WORKFLOW_SIGNAL'
          and not exists (select 1 from public.kernel_signal_type s
                           where s.signal_type = c.target_step_or_signal))
         || ' of ' || (select count(*)::text from c where source_class = 'B EXISTING_WORKFLOW_SIGNAL'),
       (select count(*) = 0 from c where source_class = 'B EXISTING_WORKFLOW_SIGNAL'
          and not exists (select 1 from public.kernel_signal_type s
                           where s.signal_type = c.target_step_or_signal))
union all
-- Activation is not a side effect of classification. This line exists so a later increment that
-- quietly switches a disabled source on has to explain itself.
select 'sources_switched_off_today',
       'reported; an adapter existing is not a reason to activate one',
       (select count(*)::text from c where current_activation = 'DISABLED')
         || ' of ' || (select count(*)::text from c) || ' carry an adapter and stay disabled',
       true
union all
select 'routine_autonomous_work_routed_through_the_founder_or_chief_of_staff',
       '0 of ' || (select count(*)::text from act where source_class in
                    ('A NEW_WORK_REQUEST','B EXISTING_WORKFLOW_SIGNAL')),
       (select count(*)::text from act
         where source_class in ('A NEW_WORK_REQUEST','B EXISTING_WORKFLOW_SIGNAL')
           and accountable_role in ('founder','chief_of_staff'))
         || ' of ' || (select count(*)::text from act where source_class in
                        ('A NEW_WORK_REQUEST','B EXISTING_WORKFLOW_SIGNAL')),
       (select count(*) = 0 from act
         where source_class in ('A NEW_WORK_REQUEST','B EXISTING_WORKFLOW_SIGNAL')
           and accountable_role in ('founder','chief_of_staff'));
$k17_state$;

revoke all on function public.fn_kernel_source_cutover_state() from public, anon, authenticated;
grant execute on function public.fn_kernel_source_cutover_state() to service_role;

comment on function public.fn_kernel_source_cutover_state() is
  'K17 invariants. The population is recomputed from the live catalogue on every call, never read '
  'off phase_c_source_cutover: a check whose denominator is a column its own migration writes goes '
  'green by emptying itself. The class-C line is measured from creates_work_now, so a monitor that '
  'starts writing business work fails even though its row still says READ_ONLY.';

-- One more signal type, owed by the classification: edge:supplier_ack is a step event inside an
-- open W14 run (SLA-SUPPLIER-ACK, 4 hours), which K10 recorded and which has no vocabulary yet.
insert into public.kernel_signal_type
  (signal_type, disposition, workflow_id, meaning, system_actor_id, activation_state)
values
  ('supplier.acknowledgement', 'ATTACH_ONLY', null,
   'A supplier has confirmed they contacted the customer, from the one-click link in the nudge '
   'email. It stops the nudges and satisfies SLA-SUPPLIER-ACK on a run that already exists. '
   'ATTACH_ONLY and not COMPLETE_STEP: acknowledging contact is not the same as finishing the '
   'step, and completing a step on the strength of a click would close work nobody did.',
   'system.webhook_receiver', 'inactive')
on conflict (signal_type) do update set
  disposition = excluded.disposition, meaning = excluded.meaning;

-- ------------------------------------------------------------------ a recorded flag corrected
--
-- The class-C check above failed on its first rehearsal: 3 of 14 active read-only monitors were
-- recorded as creating business work. That is the check doing its job, so the claim was measured
-- rather than the check softened.
--
-- For a cron job or a database trigger, creates_work_now is derived live from pg_proc — it cannot
-- be wrong. For an EDGE FUNCTION there is no catalogue to read, so K10 fell back to
-- recorded_creates_work, a boolean a human set. These three were set true. What they actually
-- write, read out of the deployed source on 17 Aug 2026:
--
--   edge:claim_lookup    agent_runs (its own execution log). Nothing else. It reads leads by
--                        claim_token and returns.
--   edge:resend_webhook  agent_runs (own log); email_suppressions (upsert); leads.invite_status
--                        = 'bounced'; error_events (telemetry).
--   edge:unsubscribe     email_suppressions (delete + upsert). Nothing else.
--
-- Not one of them writes phase_c_workflow_run, phase_c_workflow_step_run, phase_c_task,
-- phase_c_handoff_run, phase_c_event_outbox, org_tasks or agent_actions. They write their own
-- execution log, a suppression list and a delivery status — operational state that other
-- workflows read, which is exactly what class C is for. The recorded flag was wrong; the
-- classification is right.
--
-- The correction is recorded as a correction, with its evidence, and it is deliberately narrow:
-- three named sources, each with the tables it writes spelled out, so a later reader can check the
-- claim instead of trusting it. Nothing else in the inventory is touched.
--
-- This still rests on reading source rather than on a guard. The guard is the next increment: once
-- kernel-context enforcement sits on the business-work tables, a class-C source cannot write one
-- whatever anybody records about it, and this check stops depending on a boolean at all.
update public.kernel_trigger_source
   set recorded_creates_work = false,
       evidence = evidence || ' | K17 2026-08-17: recorded_creates_work corrected true -> false. '
                || 'Deployed source writes only: '
                || case source_key
                     when 'edge:claim_lookup'   then 'agent_runs (own execution log).'
                     when 'edge:resend_webhook' then 'agent_runs (own log), email_suppressions, leads.invite_status, error_events.'
                     when 'edge:unsubscribe'    then 'email_suppressions.'
                   end
                || ' No workflow run, step run, task, handoff or outbox row. Class C READ_ONLY_MONITOR.'
 where source_key in ('edge:claim_lookup','edge:resend_webhook','edge:unsubscribe')
   and recorded_creates_work is true;

commit;
