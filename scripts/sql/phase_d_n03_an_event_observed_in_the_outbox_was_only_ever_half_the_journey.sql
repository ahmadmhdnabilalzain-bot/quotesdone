-- N03. "OBSERVED IN THE OUTBOX" WAS ONLY EVER HALF THE JOURNEY.
--
-- public.phase_d_event_reconciliation carried one runtime value for all 347 frozen events:
-- OBSERVED_IN_OUTBOX. What that measured is exact and narrow -- a row carrying the event id was
-- read back out of public.phase_c_event_outbox inside the transaction that wrote it. It proves the
-- PRODUCER emitted. It says nothing whatsoever about whether anything CONSUMED it, what the
-- consumption produced, or what happened when it could not.
--
-- One uniform value across 347 rows is the shape this estate has been bitten by before: a column
-- whose name promises a journey and whose content records a departure. "CONNECTED is a claim, not
-- a measurement" was written about this same registry.
--
-- The canonical consumer can be called INSIDE the same aborted transaction:
--
--     public.fn_kernel_event_consume(p_outbox_id bigint)
--       returns table(handled boolean, downstream_ref text, result jsonb, reason text)
--
-- It sets kernel.in_delivery, projects the event onto its downstream subject, and -- by explicit
-- construction, stated in its own body -- creates nothing, because fn_kernel_step_complete is the
-- single authoritative progression path and a consumer that created work would be a second creator
-- racing the first. So consumption can be OBSERVED without the live cron phase_c_outbox_deliver_1min
-- ever seeing the row, and therefore without any external effect.
--
-- These columns are what an observation of the whole journey needs and the table had nowhere to put:
--
--   runtime_evidence_status   the one final status Phase D closure requires, from a four-value
--                             vocabulary. OBSERVED_IN_OUTBOX is not one of them: it is a
--                             departure, and the four are outcomes.
--   consumer_observation      HANDLED / FAIL_CLOSED / NOT_EMITTED -- what the canonical consumer
--                             actually answered when it was called on a real emitted row.
--   consume_reason            the consumer's own stated reason when it did not handle. A refusal
--                             with no reason is indistinguishable from a crash.
--   downstream_ref            the subject the consumption resolved to -- the resulting task, state
--                             or effect the brief asks each event to name.
--   correlation_observed      \
--   causation_observed         |  read off the outbox row that was actually written, never off
--   dedupe_observed            |  the registry. A registry column saying an event is correlated
--   trace_observed            /   is the claim; the row carrying a correlation_id is the fact.
--   retry_budget_observed     max_attempts on the emitted row: whether a retry/dead-letter branch
--                             exists for this event at all.
--   self_loop_reapplied       the RUNTIME self-loop test. 54 of the 347 have emitted_by equal to
--                             primary_consumer_role_id, which is a registry property and not a
--                             loop. The question that matters is whether CONSUMING the event
--                             re-applies the producer's action, and that is answered by counting
--                             the business rows the consume call adds. Zero means the projection
--                             held.
--
-- Nothing here is a Phase A, Phase B or Phase C subject. public.phase_d_event_reconciliation is a
-- Phase D deliverable register; adding columns to it changes no frozen contract and no drift board.

ALTER TABLE public.phase_d_event_reconciliation
  ADD COLUMN IF NOT EXISTS runtime_evidence_status text,
  ADD COLUMN IF NOT EXISTS consumer_observation    text,
  ADD COLUMN IF NOT EXISTS consume_reason          text,
  ADD COLUMN IF NOT EXISTS downstream_ref          text,
  ADD COLUMN IF NOT EXISTS correlation_observed    boolean,
  ADD COLUMN IF NOT EXISTS causation_observed      boolean,
  ADD COLUMN IF NOT EXISTS dedupe_observed         boolean,
  ADD COLUMN IF NOT EXISTS trace_observed          boolean,
  ADD COLUMN IF NOT EXISTS retry_budget_observed   integer,
  ADD COLUMN IF NOT EXISTS self_loop_reapplied     integer;

-- THE VOCABULARY IS CLOSED, so a future writer cannot invent a fifth status that means "we did not
-- look". A NULL is permitted only before the first observation run.
ALTER TABLE public.phase_d_event_reconciliation
  DROP CONSTRAINT IF EXISTS phase_d_event_reconciliation_evidence_status_ck;
ALTER TABLE public.phase_d_event_reconciliation
  ADD CONSTRAINT phase_d_event_reconciliation_evidence_status_ck
  CHECK (runtime_evidence_status IS NULL OR runtime_evidence_status IN (
    'OBSERVED_SUCCESS',
    'OBSERVED_FAIL_CLOSED',
    'TERMINAL_EVENT_NO_CONSUMER_REQUIRED',
    'STRUCTURALLY_DEFERRED_WITH_FROZEN_REASON'));

ALTER TABLE public.phase_d_event_reconciliation
  DROP CONSTRAINT IF EXISTS phase_d_event_reconciliation_consumer_observation_ck;
ALTER TABLE public.phase_d_event_reconciliation
  ADD CONSTRAINT phase_d_event_reconciliation_consumer_observation_ck
  CHECK (consumer_observation IS NULL OR consumer_observation IN (
    'HANDLED', 'FAIL_CLOSED', 'NOT_EMITTED'));

-- A FAIL_CLOSED WITH NO STATED REASON IS NOT A MEASUREMENT. The table refuses to hold one.
ALTER TABLE public.phase_d_event_reconciliation
  DROP CONSTRAINT IF EXISTS phase_d_event_reconciliation_fail_closed_needs_reason_ck;
ALTER TABLE public.phase_d_event_reconciliation
  ADD CONSTRAINT phase_d_event_reconciliation_fail_closed_needs_reason_ck
  CHECK (consumer_observation IS DISTINCT FROM 'FAIL_CLOSED'
         OR coalesce(btrim(consume_reason),'') <> '');

-- ---------------------------------------------------------------------------------------------
-- THE BOARD. A number nobody can read is not evidence, and a board that reads its own writer's
-- column is not a check. Every row below is derived from the observation columns above, so a run
-- that did not happen shows as a red count rather than as an absent row.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_phase_d_event_evidence_state()
 RETURNS TABLE(check_name text, numerator bigint, denominator bigint, ok boolean, detail text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'pg_temp'
AS $function$
  with r as (select * from public.phase_d_event_reconciliation)
  select 'events_carrying_a_final_evidence_status',
         count(*) filter (where runtime_evidence_status is not null), count(*),
         count(*) filter (where runtime_evidence_status is not null) = count(*),
         'Phase D closure may not leave an event as merely CONNECTED or NEVER_OBSERVED'
    from r
  union all
  select 'events_runtime_observed_or_proven_terminal_or_deferred',
         count(*) filter (where runtime_evidence_status in (
           'OBSERVED_SUCCESS','OBSERVED_FAIL_CLOSED',
           'TERMINAL_EVENT_NO_CONSUMER_REQUIRED','STRUCTURALLY_DEFERRED_WITH_FROZEN_REASON')),
         count(*),
         count(*) filter (where runtime_evidence_status in (
           'OBSERVED_SUCCESS','OBSERVED_FAIL_CLOSED',
           'TERMINAL_EVENT_NO_CONSUMER_REQUIRED','STRUCTURALLY_DEFERRED_WITH_FROZEN_REASON')) = count(*),
         'every event ends on one of the four permitted statuses'
    from r
  union all
  select 'fail_closed_events_stating_no_reason',
         count(*) filter (where consumer_observation = 'FAIL_CLOSED'
                            and coalesce(btrim(consume_reason),'') = ''), count(*),
         count(*) filter (where consumer_observation = 'FAIL_CLOSED'
                            and coalesce(btrim(consume_reason),'') = '') = 0,
         'a refusal with no stated reason is indistinguishable from a crash'
    from r
  union all
  select 'events_whose_consumption_reapplied_the_producer_action',
         coalesce(sum(case when coalesce(self_loop_reapplied,0) > 0 then 1 else 0 end),0), count(*),
         coalesce(sum(case when coalesce(self_loop_reapplied,0) > 0 then 1 else 0 end),0) = 0,
         'measured at runtime by counting the business rows the consume call added, not by comparing two registry columns'
    from r
  union all
  select 'observed_events_carrying_no_correlation_id',
         count(*) filter (where consumer_observation in ('HANDLED','FAIL_CLOSED')
                            and correlation_observed is not true),
         count(*) filter (where consumer_observation in ('HANDLED','FAIL_CLOSED')),
         count(*) filter (where consumer_observation in ('HANDLED','FAIL_CLOSED')
                            and correlation_observed is not true) = 0,
         'read off the emitted outbox row, not off the registry'
    from r
  union all
  select 'observed_events_carrying_no_trace',
         count(*) filter (where consumer_observation in ('HANDLED','FAIL_CLOSED')
                            and trace_observed is not true),
         count(*) filter (where consumer_observation in ('HANDLED','FAIL_CLOSED')),
         count(*) filter (where consumer_observation in ('HANDLED','FAIL_CLOSED')
                            and trace_observed is not true) = 0,
         'an emission with no trace cannot be reconciled after the fact'
    from r
  union all
  select 'observed_events_with_no_retry_budget',
         count(*) filter (where consumer_observation in ('HANDLED','FAIL_CLOSED')
                            and coalesce(retry_budget_observed,0) < 1),
         count(*) filter (where consumer_observation in ('HANDLED','FAIL_CLOSED')),
         count(*) filter (where consumer_observation in ('HANDLED','FAIL_CLOSED')
                            and coalesce(retry_budget_observed,0) < 1) = 0,
         'max_attempts on the emitted row: a retry/dead-letter branch that does not exist cannot be reached'
    from r;
$function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_event_evidence_state() FROM PUBLIC;
