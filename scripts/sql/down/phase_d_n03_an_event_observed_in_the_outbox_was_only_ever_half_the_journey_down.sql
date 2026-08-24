-- ROLLBACK for phase_d_n03_an_event_observed_in_the_outbox_was_only_ever_half_the_journey.sql
--
-- Drops the consumer-side evidence columns on public.phase_d_event_reconciliation, their three
-- CHECK constraints and the board that reads them.
--
-- WHAT IS LOST: the 347 rows fall back to runtime_observation alone, which records that an event
-- was EMITTED and says nothing about whether anything consumed it. The emission observations
-- themselves survive — runtime_observation, emissions_observed, first/last_observed_at are older
-- columns and are not touched here.
drop function if exists public.fn_phase_d_event_evidence_state();
alter table public.phase_d_event_reconciliation
  drop constraint if exists phase_d_event_reconciliation_fail_closed_needs_reason_ck;
alter table public.phase_d_event_reconciliation
  drop constraint if exists phase_d_event_reconciliation_consumer_observation_ck;
alter table public.phase_d_event_reconciliation
  drop constraint if exists phase_d_event_reconciliation_evidence_status_ck;
alter table public.phase_d_event_reconciliation
  drop column if exists runtime_evidence_status,
  drop column if exists consumer_observation,
  drop column if exists consume_reason,
  drop column if exists downstream_ref,
  drop column if exists correlation_observed,
  drop column if exists causation_observed,
  drop column if exists dedupe_observed,
  drop column if exists trace_observed,
  drop column if exists retry_budget_observed,
  drop column if exists self_loop_reapplied;
