-- ============================================================================================
-- ROLLBACK — KERNEL K5 (the factual outbox)
--
-- Apply AFTER kernel_k2_workflow_start.rollback.sql.
--
-- WHAT COMES OUT: the kernel's emitter, consumer, delivery worker, delivery marker and SLA
-- helper, and the kernel identity CHECK. The old path is untouched and still live —
-- fn_phase_c_outbox_deliver, fn_phase_c_outbox_claim, fn_phase_c_event_consume and
-- fn_phase_c_event_ingress were never modified, and cron job 278 still points at
-- fn_phase_c_outbox_deliver. Removing these functions restores the previous behaviour exactly.
--
-- WHAT STAYS, AND WHY — READ THIS BEFORE ASKING FOR A FULLER REVERT
--
-- 1. The six identity columns stay. They hold measurements: correlation_id, causation_id and
--    source_id were never backfilled by guessing, so every value present is one the kernel
--    actually recorded. Dropping the columns deletes that and cannot be undone.
--
-- 2. first_failure stays timestamptz NULL, and first_failure_reason stays. Reverting it to
--    `text NOT NULL default ''` would cast real timestamps back to text or to '' — destroying
--    the diagnosis the column exists to hold — and would REINSTATE the 42804 that made the
--    failure branch of fn_phase_c_outbox_deliver unable to complete. The retype is a strict
--    improvement for the OLD body too: with first_failure timestamptz and next_attempt_at
--    nullable, `coalesce(first_failure, now())` plans and `next_attempt_at = null` writes, so
--    the pre-kernel deliver can finally settle a failure instead of aborting the whole pass.
--    That is the one thing you do not want to give back.
--
-- 3. next_attempt_at stays NULLABLE for the same reason.
--
-- The status CHECK is widened back to include 'cancelled', because that is the only narrowing
-- K5 performed and a constraint is not evidence.
--
-- If the columns really must go — only when the kernel is being abandoned, not merely paused —
-- the destructive statements are at the bottom, commented out, so that removing them is a
-- deliberate act with a reader's name on it.
-- ============================================================================================

drop function if exists public.fn_kernel_outbox_deliver(integer, text);
drop function if exists public.fn_kernel_event_consume(bigint);
drop function if exists public.fn_kernel_outbox_emit(jsonb);
drop function if exists public.fn_kernel_assert_not_in_delivery(text);
drop function if exists public.fn_kernel_in_delivery();
drop function if exists public.fn_kernel_sla_due(text, timestamptz);

alter table public.phase_c_event_outbox
  drop constraint if exists phase_c_event_outbox_kernel_identity_ck;

do $st$
begin
  if exists (select 1 from pg_constraint
              where conrelid='public.phase_c_event_outbox'::regclass
                and conname='phase_c_event_outbox_status_ck') then
    alter table public.phase_c_event_outbox drop constraint phase_c_event_outbox_status_ck;
  end if;
  alter table public.phase_c_event_outbox
    add constraint phase_c_event_outbox_status_ck
    check (status in ('pending','claimed','delivered','retry_wait','dead_letter','cancelled','superseded'));
end $st$;

-- ------------------------------------------------------------------ DESTRUCTIVE, deliberately off
-- Uncommenting any of these throws away measurements. There is no second copy.
--
-- alter table public.phase_c_event_outbox
--   drop column if exists correlation_id,
--   drop column if exists causation_id,
--   drop column if exists source_id,
--   drop column if exists command_id,
--   drop column if exists workflow_run_id,
--   drop column if exists step_run_id,
--   drop column if exists first_failure_reason,
--   drop column if exists last_sqlstate,
--   drop column if exists max_attempts;
--
-- -- and this one reinstates the 42804 that made the failure branch unable to complete:
-- update public.phase_c_event_outbox set first_failure = null where first_failure is not null;
-- alter table public.phase_c_event_outbox
--   alter column first_failure type text using coalesce(first_failure::text, ''),
--   alter column first_failure set default '',
--   alter column first_failure set not null;
-- update public.phase_c_event_outbox set next_attempt_at = now() where next_attempt_at is null;
-- alter table public.phase_c_event_outbox alter column next_attempt_at set not null;
