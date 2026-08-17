-- ROOT CAUSE 4, FOLLOW-UP — 3730 IS NOT A HISTORICAL EXCEPTION, AND THE REGISTER SAID SO.
--
-- rc4 recorded trace 3730 in phase_c_historical_repair as a CLASSIFICATION of kind
-- HISTORICAL_ORPHAN_TRACE. fn_kernel_historical_register_state immediately failed it, and it was
-- right, in the words of its own comment:
--
--   "A 'historical' exception that happened after the kernel took over is not historical. It is a
--    live defect wearing the wrong label, and that is worth failing on."
--
-- Trace 3730 was written at 2026-08-17 05:05:00, and the kernel cutover was 2026-08-16 23:18:23.
-- It is post-cutover. It was a live defect, it has been repaired, and calling it history was the
-- one thing in rc4 that was not true.
--
-- The register is append-only and its trigger states how a correction is made: a NEW row naming the
-- repair_id it corrects. That row is written below. The state function is taught to read the
-- protocol its own table prescribes — a corrected finding leaves the population, and only because a
-- correcting row exists and names it.
--
-- Rollback: scripts/sql/rollback/rc4b_3730_is_not_history.rollback.sql

insert into public.phase_c_historical_repair (
  entry_kind, record_kind, record_ref, classification, frozen_state, evidence, repair_action,
  retrofit_label, migration, classified_at, original_at, kernel_cutover_at, active_effect_now,
  cannot_reconstruct)
values (
  'RETROFIT', 'trace', '3730', null,
  'corrected: repair_id 83 classified trace 3730 as a historical exception, and it is not one',
  jsonb_build_object(
    'corrects_repair_id', 83,
    'why', 'Trace 3730 was created 2026-08-17 05:05:00.033303+00, AFTER the kernel cutover of '
        || '2026-08-16 23:18:23.256918+00. phase_c_historical_repair holds pre-cutover records that '
        || 'cannot be reconstructed. 3730 was a live defect of the kernel era: fn_kernel_trigger_submit '
        || 'wrote a TRACE-SYSTEM-EXECUTION trace with no execution row because no code path wrote '
        || 'one. It has been repaired, not preserved.',
    'what_actually_happened', 'The reconstructed phase_c_system_execution row for trace 3730 stands '
        || 'and is labelled a reconstruction in its own technical_scope, carrying the original '
        || 'instant in started_at and the repair instant in recorded_at. The trace itself was never '
        || 'edited, because fn_phase_c_trace_append_only refuses editing a sealed trace.',
    'found_by', 'fn_kernel_historical_register_state, immediately, on the sweep after rc4 deployed'),
  'repair_id 83 is superseded. Trace 3730 is recorded as a post-cutover defect that was repaired by '
  || 'scripts/sql/rc4_execution_and_trace_are_atomic.sql, not as a preserved historical exception.',
  'CORRECTION 17 Aug 2026', 'scripts/sql/rc4b_3730_is_not_history.sql',
  now(), null,
  (select started_at from public.phase_c_kernel_epoch order by started_at limit 1),
  false, null);

CREATE OR REPLACE FUNCTION public.fn_kernel_historical_register_state()
 RETURNS TABLE(check_name text, expected text, actual text, ok boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
with r as (select * from public.phase_c_historical_repair),
-- ROOT CAUSE 4 FOLLOW-UP, 17 Aug 2026. The register is append-only and its own trigger states the
-- correction protocol: "A correction is a NEW row that names the repair_id it corrects in its
-- evidence, never an edit to the row that stated the original finding." Until now nothing here read
-- that protocol, so a corrected finding went on being counted as a live one and there was no way to
-- satisfy the register by the mechanism the register prescribes. A CLASSIFICATION that a later row
-- names as corrected is no longer in the population; the correcting row has to exist and has to
-- name it, which is stricter bookkeeping than not looking.
exc as (
  select * from r c
   where c.entry_kind = 'CLASSIFICATION'
     and not exists (select 1 from r x
                      where (x.evidence->>'corrects_repair_id')::bigint = c.repair_id))
-- ---- CURRENT state. These must be zero, and they are about today, not about history.
select 'active_historical_duplicate_work'::text,
       '0 of ' || (select count(*)::text from exc where classification = 'HISTORICAL_DUPLICATE_EFFECT'),
       (select count(*)::text from exc
         where classification = 'HISTORICAL_DUPLICATE_EFFECT' and active_effect_now)
         || ' of ' || (select count(*)::text from exc where classification = 'HISTORICAL_DUPLICATE_EFFECT'),
       (select count(*) = 0 from exc where classification = 'HISTORICAL_DUPLICATE_EFFECT' and active_effect_now)
union all
select 'queued_work_beneath_cancelled_commands',
       '0',
       (select count(*)::text from public.phase_c_task t
         join public.founder_command c on c.command_id = t.command_id
        where c.state = 'cancelled'
          and t.state not in (select state from public.phase_c_task_state where terminal)),
       (select count(*) = 0 from public.phase_c_task t
         join public.founder_command c on c.command_id = t.command_id
        where c.state = 'cancelled'
          and t.state not in (select state from public.phase_c_task_state where terminal))
union all
select 'current_terminal_objects_with_open_trace',
       '0',
       (select count(*)::text from public.phase_c_trace t
         where t.status = 'open'
           and t.created_at >= (select min(started_at) from public.phase_c_kernel_epoch)
           and exists (select 1 from public.phase_c_workflow_run w
                        where w.run_id::text = t.subject_ref and t.subject_kind = 'workflow_run'
                          and w.state in (select state from public.phase_b_workflow_state where terminal))),
       (select count(*) = 0 from public.phase_c_trace t
         where t.status = 'open'
           and t.created_at >= (select min(started_at) from public.phase_c_kernel_epoch)
           and exists (select 1 from public.phase_c_workflow_run w
                        where w.run_id::text = t.subject_ref and t.subject_kind = 'workflow_run'
                          and w.state in (select state from public.phase_b_workflow_state where terminal)))
union all
select 'current_active_orphan_traces',
       '0 — an orphan trace created AFTER the kernel epoch',
       (select count(*)::text from public.phase_c_trace t
         where t.created_at >= (select min(started_at) from public.phase_c_kernel_epoch)
           and t.subject_kind = 'task'
           and not exists (select 1 from public.phase_c_task k where k.task_id::text = t.subject_ref)),
       (select count(*) = 0 from public.phase_c_trace t
         where t.created_at >= (select min(started_at) from public.phase_c_kernel_epoch)
           and t.subject_kind = 'task'
           and not exists (select 1 from public.phase_c_task k where k.task_id::text = t.subject_ref))
union all
-- ---- PRESERVED history. Reported with an exact count, never as compliance.
select 'historical_exceptions_preserved',
       'reported exactly, and never presented as current compliance',
       (select string_agg(classification || ' ' || n::text, '; ' order by classification)
          from (select classification, count(*) n from exc group by 1) d)
         || '; retrofit entries ' || (select count(*)::text from r where entry_kind = 'RETROFIT'),
       true
union all
select 'historical_exceptions_with_no_original_timestamp',
       '0 of ' || (select count(*)::text from exc),
       (select count(*)::text from exc where original_at is null)
         || ' of ' || (select count(*)::text from exc),
       (select count(*) = 0 from exc where original_at is null)
union all
select 'historical_exceptions_with_no_reason_they_cannot_be_reconstructed',
       '0 of ' || (select count(*)::text from exc),
       (select count(*)::text from exc where coalesce(btrim(cannot_reconstruct),'') = '')
         || ' of ' || (select count(*)::text from exc),
       (select count(*) = 0 from exc where coalesce(btrim(cannot_reconstruct),'') = '')
union all
select 'historical_exceptions_dated_after_the_kernel_cutover',
       '0 of ' || (select count(*)::text from exc where original_at is not null),
       (select count(*)::text from exc where original_at is not null and original_at >= kernel_cutover_at)
         || ' of ' || (select count(*)::text from exc where original_at is not null),
       -- A "historical" exception that happened after the kernel took over is not historical. It
       -- is a live defect wearing the wrong label, and that is worth failing on.
       (select count(*) = 0 from exc where original_at is not null and original_at >= kernel_cutover_at)
union all
select 'register_is_append_only',
       'a trigger refusing UPDATE and DELETE',
       (select case when count(*) = 1 then 'present' else 'MISSING' end
          from pg_trigger tg join pg_class c on c.oid = tg.tgrelid
         where c.relname = 'phase_c_historical_repair'
           and tg.tgname = 'a00_phase_c_historical_repair_append_only'
           and not tg.tgisinternal and tg.tgenabled <> 'D'),
       (select count(*) = 1 from pg_trigger tg join pg_class c on c.oid = tg.tgrelid
         where c.relname = 'phase_c_historical_repair'
           and tg.tgname = 'a00_phase_c_historical_repair_append_only'
           and not tg.tgisinternal and tg.tgenabled <> 'D');
$function$;
