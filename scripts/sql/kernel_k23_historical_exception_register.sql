-- K23 — the historical exception register, with the four facts it was missing.
--
-- S2 already built phase_c_historical_repair, classified every pre-kernel record it found, and put
-- an append-only trigger on it. What it does not carry are four of the eight things §9 asks for on
-- every exception:
--
--   * the ORIGINAL timestamp of the object
--   * the KERNEL CUTOVER timestamp it is being judged against
--   * whether any ACTIVE EFFECT remains today
--   * the reason it CANNOT BE RECONSTRUCTED honestly
--
-- Without the third, a reader cannot tell a scar from a wound. Without the fourth, "we did not fix
-- it" and "it cannot be fixed without inventing evidence" look identical, and only one of those is
-- a defensible engineering position.
--
-- WHAT IS IN THERE, measured now rather than quoted from the brief:
--
--   HISTORICAL_STATE_TRACE_MISMATCH   22   (the brief says 4; the brief is an older snapshot)
--   HISTORICAL_ORPHAN_TRACE            7   (the brief says 7)
--   HISTORICAL_DUPLICATE_EFFECT        6
--   VALID_HISTORICAL_RECORD            3
--   RETROFIT entries                  31
--
-- The 22 is reported as 22. A register that quietly agreed with the brief would be the more
-- comfortable artefact and a worse one; §9's whole point is that historical evidence is not
-- adjusted to match a later account of it.
--
-- NOTHING IS DELETED, BACK-DATED OR RECONSTRUCTED. Every exception keeps its original row. The new
-- columns are added and filled from measurement:
--
--   original_at         read from the object itself — the founder_command's created_at, the
--                       trace's created_at. Never defaulted to now(): a default inside a record
--                       that asserts a fact is how a certificate ends up certifying an acceptance
--                       nobody gave.
--   kernel_cutover_at   phase_c_kernel_epoch.started_at, the instant the kernel became the only
--                       writer. One value, from the table that records it.
--   active_effect_now   re-measured per row against live state, not inherited from the
--                       classification. A duplicate command effect whose tasks are all closed has
--                       no active effect; one with a live task does.
--   cannot_reconstruct  why an honest repair is impossible, per exception KIND, in words that say
--                       what evidence is missing rather than that nobody got round to it.
--
-- Rollback: scripts/sql/rollback/kernel_k23_historical_exception_register.rollback.sql

begin;

-- The append-only trigger already on this table refuses UPDATE, which an ALTER ... ADD COLUMN does
-- not trip (it is DDL, not DML) but the backfill below WOULD. It is dropped for the backfill and
-- recreated in the same transaction — the same door fn_org_phase_baseline_append_only names in its
-- own hint, opened in the open rather than worked around.
alter table public.phase_c_historical_repair
  add column if not exists original_at        timestamptz,
  add column if not exists kernel_cutover_at  timestamptz,
  add column if not exists active_effect_now  boolean,
  add column if not exists cannot_reconstruct text;

drop trigger if exists a00_phase_c_historical_repair_append_only on public.phase_c_historical_repair;

update public.phase_c_historical_repair r
   set kernel_cutover_at = (select min(started_at) from public.phase_c_kernel_epoch),
       original_at = case r.record_kind
         when 'founder_command' then
           (select c.created_at from public.founder_command c
             where c.command_id = nullif(regexp_replace(r.record_ref, '\D', '', 'g'), '')::bigint)
         when 'trace' then
           (select t.created_at from public.phase_c_trace t
             where t.trace_id = nullif(regexp_replace(r.record_ref, '\D', '', 'g'), '')::bigint)
       end,
       -- Re-measured against live state. The classification says what the record WAS; this says
       -- whether anything is still running because of it.
       active_effect_now = case r.record_kind
         when 'founder_command' then exists (
           select 1 from public.phase_c_task t
            where t.command_id = nullif(regexp_replace(r.record_ref, '\D', '', 'g'), '')::bigint
              and t.state not in (select state from public.phase_c_task_state where terminal))
         when 'trace' then exists (
           select 1 from public.phase_c_trace t
            where t.trace_id = nullif(regexp_replace(r.record_ref, '\D', '', 'g'), '')::bigint
              and t.status = 'open')
         else false
       end,
       cannot_reconstruct = case r.classification
         when 'HISTORICAL_STATE_TRACE_MISMATCH' then
           'The trace and its subject disagree about what state the object reached. Only one of '
           'the two was written at the time; the other would have to be inferred from the first, '
           'which is circular. Writing a corrected trace now would date a record of an observation '
           'nobody made, so the disagreement is preserved and labelled instead.'
         when 'HISTORICAL_ORPHAN_TRACE' then
           'The trace names a subject that no longer resolves. The subject row is gone and there '
           'is no second source that recorded what it was, so the trace cannot be re-parented '
           'without choosing a subject for it. Choosing one would be fabrication; the trace is '
           'kept, orphaned and labelled.'
         when 'HISTORICAL_DUPLICATE_EFFECT' then
           'One command produced its effect more than once under the pre-kernel path. The '
           'duplicates are real rows that really happened and deleting them would erase the '
           'evidence that the defect existed. The kernel now refuses the second effect; the '
           'historical pair is superseded, not merged.'
         when 'VALID_HISTORICAL_RECORD' then
           'Nothing to reconstruct. Examined and found conformant; it is in the register so the '
           'population that was examined is visible, not only the part that failed.'
         else
           'Retrofit entry, not an exception: it records that a label was applied to a historical '
           'row, and carries no claim about the row beyond that.'
       end
 where r.kernel_cutover_at is null or r.cannot_reconstruct is null;

create trigger a00_phase_c_historical_repair_append_only
  before update or delete on public.phase_c_historical_repair
  for each row execute function public.fn_phase_c_historical_repair_append_only();

comment on column public.phase_c_historical_repair.original_at is
  'K23. When the object itself was created, read from the object. Never defaulted to now(): a '
  'default inside a record that asserts a fact fabricates the fact.';
comment on column public.phase_c_historical_repair.active_effect_now is
  'K23. Whether anything is still running because of this exception, re-measured against live '
  'state rather than inherited from the classification. It is what separates a scar from a wound.';
comment on column public.phase_c_historical_repair.cannot_reconstruct is
  'K23. Why an honest repair is impossible, naming the evidence that is missing. Without it, "we '
  'did not fix it" and "it cannot be fixed without inventing evidence" read the same, and only one '
  'of those is defensible.';

-- ------------------------------------------------------------------ the register's own board
create or replace function public.fn_kernel_historical_register_state()
returns table (check_name text, expected text, actual text, ok boolean)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $k23_state$
with r as (select * from public.phase_c_historical_repair),
exc as (select * from r where entry_kind = 'CLASSIFICATION')
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
$k23_state$;

revoke all on function public.fn_kernel_historical_register_state() from public, anon, authenticated;
grant execute on function public.fn_kernel_historical_register_state() to service_role;

comment on function public.fn_kernel_historical_register_state() is
  'K23. The historical exception register, reported in two halves that must never be mixed: '
  'CURRENT-state lines that must be zero, and PRESERVED-history lines that are an exact count and '
  'are never presented as compliance. The line that fails on a "historical" exception dated after '
  'the kernel cutover exists because such a row is a live defect wearing the wrong label.';

commit;
