-- =================================================================================================
-- PHASE D DOWN — reverses the additive DDL of
-- scripts/sql/phase_d_d24_a_new_enforcing_table_with_no_truncate_guard.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/: no npm script, no
-- check under scripts/checks/, no GitHub workflow, no apply_sql or --promote path. This file is a
-- hand-run rollback. A person opens it, reads the block below, accepts it, and runs it.
--
-- OBJECT DROPPED, by name (never `cascade`):
--   trigger z00_kernel_truncate_guard on public.phase_d_fixture_stage
--   (BEFORE TRUNCATE FOR EACH STATEMENT EXECUTE FUNCTION public.fn_kernel_truncate_guard())
--
-- READ THIS BEFORE RUNNING IT. d24 exists because a row trigger cannot see a TRUNCATE: every other
-- guard on public.phase_d_fixture_stage is a row trigger, so before d24 the whole enforcing table
-- could be emptied in one statement with nothing raising. Running this down re-opens that. It is a
-- rollback of a guard, not of a feature; the only good reason to run it is that d9c's table is
-- going away too, and in that case dropping the table takes the trigger anyway and this file is
-- unnecessary.
--
-- The same trigger name exists on public.phase_d_object_record (installed by d2). This file does
-- NOT touch that one — it is named per relation and only the phase_d_fixture_stage one belongs to
-- d24. The control block below asserts the d2 trigger is still in place, so a rollback that
-- silently disarmed the wrong table would fail loudly.
--
-- ROW COUNT AT RISK: none. No rows are read or written. public.phase_d_fixture_stage keeps all 25
-- rows; it just stops being protected against TRUNCATE.
--
-- NOT TOUCHED: public.fn_kernel_truncate_guard(). It is a kernel routine, shared by every table
-- that carries this guard, and is not d24's to drop.
-- =================================================================================================

begin;

do $pre$
begin
  if to_regclass('public.phase_d_fixture_stage') is null then
    raise exception 'D24 down: public.phase_d_fixture_stage does not exist. The d9c down has already run and took the trigger with it; there is nothing here to revert.';
  end if;
end $pre$;

drop trigger if exists z00_kernel_truncate_guard on public.phase_d_fixture_stage;

do $ctl$
begin
  if exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
              join pg_namespace n on n.oid = c.relnamespace
             where n.nspname = 'public' and c.relname = 'phase_d_fixture_stage'
               and t.tgname = 'z00_kernel_truncate_guard' and not t.tgisinternal) then
    raise exception 'D24 down did not take: z00_kernel_truncate_guard is still on public.phase_d_fixture_stage.';
  end if;

  -- The identically named guard on phase_d_object_record belongs to d2 and must survive this file.
  if to_regclass('public.phase_d_object_record') is not null
     and not exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
                      join pg_namespace n on n.oid = c.relnamespace
                     where n.nspname = 'public' and c.relname = 'phase_d_object_record'
                       and t.tgname = 'z00_kernel_truncate_guard' and not t.tgisinternal) then
    raise exception 'D24 down disarmed the wrong table: z00_kernel_truncate_guard is missing from public.phase_d_object_record, which belongs to d2.';
  end if;

  raise notice 'D24 down: phase_d_fixture_stage no longer carries a TRUNCATE guard. The d2 guard on phase_d_object_record is untouched.';
end $ctl$;

commit;
