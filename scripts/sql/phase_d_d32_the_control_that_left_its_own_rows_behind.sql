-- =================================================================================================
-- Phase D — D32. A control that left its own rows behind.
--
-- D31's deploy control called fn_phase_d_run_injected_defects() directly and the file then
-- COMMITTED. Every other control in this chain wraps its probe in a subtransaction that raises and
-- is caught, so the writes roll back and only the counts survive. D31's did not, and it left
--
--     14 rows in public.phase_d_external_attempt, every idempotency_key prefixed zz-,
--     all stamped 2026-08-19 10:01:42 — one timestamp, which is the deploy itself
--
-- Nothing external happened: the adapter has no live mode and sends nothing. But the session's
-- standing claim is ZERO residue, and for one file that claim was false. It is recorded here rather
-- than quietly deleted, because a residue that is cleaned without being named is a residue nobody
-- learns from.
--
-- IT ALSO CORRUPTED THE MEASUREMENT, which is how it was found. Re-running the defect probe reported
-- PD-OUTBOX-001 with "attempts recorded=2" and PD-OUTBOX-002 with an empty delivered flag: the
-- business keys are deterministic, so the committed rows from the deploy collided with the fresh
-- run and two probes that had passed at deploy time now read NOT_REFUSED. A harness that leaves
-- state behind stops being able to measure itself.
--
-- Three things here:
--   1. the 14 rows are deleted, scoped to the zz- prefix and nothing else
--   2. the runner's control is wrapped so it aborts, like every other control in this chain
--   3. a residue check joins fn_phase_d_external_state(), so the next leak is caught by a board
--      rather than by someone noticing a count went odd
-- =================================================================================================

begin;

delete from public.phase_d_external_attempt where idempotency_key like 'zz-%';

create or replace function public.fn_phase_d_external_residue()
returns table(check_name text, expected text, actual text, state text, detail text)
language sql stable
set search_path to 'public', 'pg_temp'
as $r$
select 'no_external_attempt_rows_survive_a_phase_d_run',
       '0',
       (select count(*)::text from public.phase_d_external_attempt),
       case when (select count(*) from public.phase_d_external_attempt) = 0 then 'GREEN' else 'RED' end,
       'every Phase D probe runs in a transaction that aborts; a surviving attempt row means a control '
       || 'committed its own fixture, which is what D31 did and D32 cleaned up. It also corrupts the next '
       || 'measurement, because the business keys are deterministic and collide.'
$r$;

revoke all on function public.fn_phase_d_external_residue() from public, anon, authenticated;

do $ctl$
declare v_left int; v_total int; v_exec int; v_notref text;
begin
  select count(*) into v_left from public.phase_d_external_attempt;
  if v_left <> 0 then
    raise exception 'D32 control: % attempt row(s) still survive after the cleanup.', v_left;
  end if;

  -- The runner, now inside a subtransaction that aborts. The counts survive; the rows do not.
  perform set_config('app.phase_d_test_context','on', true);
  begin
    create temporary table zz_d32 on commit drop as
      select * from public.fn_phase_d_run_injected_defects();
    select count(*), count(*) filter (where status='REFUSED_AS_REQUIRED') into v_total, v_exec from zz_d32;
    select string_agg(defect_id || ': ' || coalesce(observed,''), ' | ') into v_notref
      from zz_d32 where status='NOT_REFUSED';
    raise exception 'PHASE_D_D32_CTL_ROLLBACK';
  exception when others then
    if SQLERRM <> 'PHASE_D_D32_CTL_ROLLBACK' then
      raise exception 'D32 control: the defect runner failed with: %', SQLERRM;
    end if;
  end;

  if v_total <> 75 then
    raise exception 'D32 control: the runner produced % row(s) and the catalogue holds 75.', v_total;
  end if;
  if v_notref is not null then
    raise exception 'D32 control: the machine FAILED to refuse an injected defect: %', v_notref;
  end if;

  select count(*) into v_left from public.phase_d_external_attempt;
  if v_left <> 0 then
    raise exception 'D32 control: the runner left % attempt row(s) behind. The subtransaction did not abort.', v_left;
  end if;

  if exists (select 1 from public.fn_phase_d_external_residue() where state <> 'GREEN') then
    raise exception 'D32 control: the residue check is not green.';
  end if;

  raise notice 'D32: residue cleaned, runner aborts, 75 rows with % executed and refused, 0 attempt rows left.', v_exec;
end $ctl$;

commit;
