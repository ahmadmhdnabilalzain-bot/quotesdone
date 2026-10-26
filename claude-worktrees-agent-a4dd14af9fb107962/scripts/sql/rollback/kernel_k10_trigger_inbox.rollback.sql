-- ============================================================================================
-- ROLLBACK — KERNEL K10, REAL AUTONOMOUS TRIGGER ADAPTERS
--
-- Removes the trigger inbox, the trigger-type registry, the source inventory, the derivation view
-- and the two functions. It touches NOTHING else: no phase_b table, no phase_c table, no cron job,
-- no edge function, no workflow run and no task. K10 created no work, so there is no work to undo.
--
-- IT DOES NOT DELETE THE LEDGER. kernel_trigger_inbox is the record of what was asked of this
-- company and what was decided, including every refusal. Dropping it would destroy the only
-- explanation of why the runs it started exist. It is RENAMED to kernel_trigger_inbox_rolled_back
-- and kept. Drop that table by hand, deliberately, if you truly want the record gone.
--
-- IT REFUSES while work started through the inbox is still in flight. You cannot un-ask a question
-- somebody is still answering: close or cancel those runs with fn_kernel_cancel first, then run
-- this file.
-- ============================================================================================

begin;

do $k10_rb$
declare
  v_open  int;
  v_runs  text;
begin
  if to_regclass('public.kernel_trigger_inbox') is null then
    raise notice 'K10 rollback: kernel_trigger_inbox does not exist; nothing to roll back.';
    return;
  end if;

  select count(*), string_agg(distinct r.run_id::text, ', ')
    into v_open, v_runs
    from public.kernel_trigger_inbox i
    join public.phase_c_workflow_run r on r.run_id = i.run_id
   where i.status in ('accepted','duplicate')
     and r.state not in ('completed','cancelled','failed','closed');

  if v_open > 0 then
    raise exception
      'K10 rollback refused: % workflow run(s) started through the trigger inbox are still open '
      '(runs %). Close or cancel them with fn_kernel_cancel first — removing the inbox would leave '
      'live work whose reason for existing is no longer recorded anywhere.', v_open, v_runs
      using errcode = '23514';
  end if;
end
$k10_rb$;

-- the guard and its function
drop trigger  if exists a00_kernel_trigger_type_routing_guard on public.kernel_trigger_type;
drop function if exists public.fn_kernel_trigger_type_routing_guard();

-- the invariant board and the derivation, before the tables they read
drop function if exists public.fn_kernel_trigger_state();
drop view     if exists public.v_kernel_trigger_source_derived;

-- the adapter
drop function if exists public.fn_kernel_trigger_submit(jsonb);

-- the inventory (no other object references it)
drop table if exists public.kernel_trigger_source;

-- THE LEDGER IS KEPT. Renamed, with its foreign keys to phase_c_workflow_run and phase_c_trace
-- intact, so the runs K10 started can still be traced back to what asked for them.
do $k10_rb_keep$
begin
  if to_regclass('public.kernel_trigger_inbox') is not null then
    -- the FK to kernel_trigger_type has to go, because that table is dropped below; the
    -- trigger_type text is preserved in the column.
    alter table public.kernel_trigger_inbox
      drop constraint if exists kernel_trigger_inbox_trigger_type_fkey;
    execute format('alter table public.kernel_trigger_inbox rename to %I',
                   'kernel_trigger_inbox_rolled_back_' || to_char(now(), 'YYYYMMDD'));
  end if;
end
$k10_rb_keep$;

drop table if exists public.kernel_trigger_type;

commit;
