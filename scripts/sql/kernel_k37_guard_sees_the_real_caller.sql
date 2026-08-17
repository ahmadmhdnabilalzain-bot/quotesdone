-- K37 — the write guard was reading its own identity, not the caller's.
--
-- K18's second door is meant for a human holding the management token doing audited historical
-- maintenance, and it is meant to be closed to everything else:
--
--   if v_reason is not null and current_user = v_owner then ... allow
--
-- fn_kernel_write_guard is SECURITY DEFINER, owned by postgres. Inside a SECURITY DEFINER function
-- current_user IS THE OWNER, whoever called it. So `current_user = v_owner` was not a test of the
-- caller at all — it was always true, and the door reduced to "state any reason and pass".
--
-- Proved, not reasoned about. scripts/checks/kernel_write_guard_both_directions.test.mjs runs each
-- case under `set local role`, inside an aborted transaction:
--
--   anon direct write ................ refused (permission denied for table)
--   authenticated direct write ....... refused (permission denied for table)
--   service_role direct write ........ refused by the guard, call stack in the error
--   service_role + a stated reason ... ACCEPTED — SERVICE_ROLE MANUFACTURED KERNEL CONTEXT
--
-- The last line is the defect. Any Edge Function holding the service key could write
-- phase_c_workflow_run, phase_c_task, the trigger inbox or the founder's refund ledger by adding
-- one `set local kernel.maintenance_reason = 'anything'` — which is precisely the "untrusted
-- caller able to manufacture kernel context" §4 requires to be impossible.
--
-- THE FIX: the guard becomes SECURITY INVOKER, so current_user is genuinely the caller's role.
--
-- It does not need to be a definer. Door 1 reads pg_context and pg_catalog, which every role may
-- read. Door 2 needs to write kernel_maintenance_write, and that ONE write moves into a separate
-- SECURITY DEFINER helper called only after the owner check has already passed — so the elevated
-- privilege is held by the four lines that need it instead of by the whole guard.
--
-- Why not session_user instead: under PostgREST, session_user is 'authenticator' and the role is
-- switched to service_role afterwards, so session_user would have refused correctly in production
-- but the test could not distinguish it from postgres and would have proved nothing. current_user
-- under SECURITY INVOKER is the thing that is actually true.
--
-- Nothing else in the guard changes: door 1 still matches the live call stack against
-- kernel_write_authority, and the kernel's own routines still pass because they are SECURITY
-- DEFINER owned by postgres and appear on the stack.
--
-- Rollback: scripts/sql/rollback/kernel_k37_guard_sees_the_real_caller.rollback.sql

begin;

-- The one privileged act, isolated. It is called only after the guard has established that the
-- caller IS the table owner, so it cannot be used to launder a write by anybody else.
create or replace function public.fn_kernel_record_maintenance_write(
  p_db_user text, p_session_role text, p_table text, p_op text, p_reason text, p_stack text)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $k37_audit$
begin
  insert into public.kernel_maintenance_write
    (db_user, session_role, table_name, operation, reason, call_stack)
  values (p_db_user, p_session_role, p_table, p_op, p_reason, p_stack);
end
$k37_audit$;

revoke all on function public.fn_kernel_record_maintenance_write(text, text, text, text, text, text)
  from public, anon, authenticated, service_role;

comment on function public.fn_kernel_record_maintenance_write(text, text, text, text, text, text) is
  'K37. The single privileged act the write guard needs: recording a hand-made maintenance write. '
  'It is separate so fn_kernel_write_guard can be SECURITY INVOKER and therefore see the REAL '
  'caller in current_user. Called only after the guard has established the caller is the table '
  'owner, and executable by nobody else.';

create or replace function public.fn_kernel_write_guard()
returns trigger
language plpgsql
-- SECURITY INVOKER, deliberately and load-bearing. As SECURITY DEFINER the current_user check
-- below compared the owner against itself and was always true.
security invoker
set search_path to 'public', 'pg_temp'
as $k37_guard$
declare
  v_ctx    text;
  v_reason text;
  v_owner  text;
  v_ok     boolean;
begin
  get diagnostics v_ctx = pg_context;

  -- Door 1: an authorised routine is on the stack. The stack cannot be forged.
  select exists (
    select 1 from public.kernel_write_authority a
     where a.table_name = tg_table_name
       and v_ctx ~ ('PL/pgSQL function (public\.)?' || a.routine_name || '\(')
  ) into v_ok;
  if v_ok then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  -- Door 2: an explicit, audited maintenance operation BY THE TABLE OWNER. Under SECURITY INVOKER
  -- current_user is the caller's own role — service_role stays service_role, and the comparison
  -- means what it says.
  v_reason := nullif(btrim(current_setting('kernel.maintenance_reason', true)), '');
  select tableowner into v_owner from pg_tables
   where schemaname = tg_table_schema and tablename = tg_table_name;
  if v_reason is not null and current_user = v_owner then
    perform public.fn_kernel_record_maintenance_write(
      current_user, session_user, tg_table_name, tg_op, v_reason, v_ctx);
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  raise exception
    '% on %.% is refused: no routine with write authority for this table is on the call stack.',
    tg_op, tg_table_schema, tg_table_name
    using errcode = '42501',
          detail = 'Call stack was:' || chr(10) || v_ctx,
          hint = 'Business work is created by the kernel and only by the kernel. New work goes '
              || 'through fn_kernel_trigger_submit; a signal about a run that already exists goes '
              || 'through fn_kernel_signal_submit; a step is completed with fn_kernel_step_complete. '
              || 'public.kernel_write_authority lists every routine permitted to write this table '
              || 'and why. Historical maintenance needs BOTH a stated reason — set local '
              || 'kernel.maintenance_reason — AND the table owner; stating a reason alone is not '
              || 'enough, and since K37 it never was.';
end
$k37_guard$;

revoke all on function public.fn_kernel_write_guard() from public, anon, authenticated;
-- SECURITY INVOKER means the trigger body runs as the writer, so the writing roles must be able to
-- execute it or every write fails with "permission denied for function". This grants the right to
-- be JUDGED, not the right to write: the function's only outcomes are "return the row" and "raise".
grant execute on function public.fn_kernel_write_guard() to anon, authenticated, service_role;

commit;
