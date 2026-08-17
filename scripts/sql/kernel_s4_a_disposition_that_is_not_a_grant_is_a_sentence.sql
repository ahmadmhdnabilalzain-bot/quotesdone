-- ============================================================================================
-- KERNEL S4 — A DISPOSITION RECORDED IN PROSE IS NOT AN ENFORCEMENT
--
-- The independent final acceptance (17 Aug 2026) drove the guard from outside instead of reading
-- it, and two doors opened that every green instrument said were shut.
--
-- FINDING 1 — SIX WRITE AUTHORITIES WITH A DISPOSITION AND NO ENFORCEMENT.
--   public.kernel_write_authority carries, for each of these six, a `why` that calls it a
--   kernel-internal primitive or a trigger helper. Two of their siblings —
--   fn_phase_c_workflow_start and fn_phase_c_task_create — say the same thing AND have the two
--   mechanisms that make it true: a row in public.kernel_retired_path, and no EXECUTE for any
--   ordinary role. These six had neither. Measured as service_role, in an aborted transaction:
--
--     fn_phase_c_workflow_start (registered, revoked)  REFUSED  42501 permission denied
--     fn_phase_c_task_create    (registered, revoked)  REFUSED  42501 permission denied
--     fn_phase_c_outbox_emit    (neither)              ACCEPTED — wrote outbox row, trace_id NULL
--     fn_phase_c_task_transition(neither)              ACCEPTED
--     fn_phase_c_handoff_open   (neither)              ACCEPTED
--     fn_phase_c_handoff_decide (neither)              ACCEPTED
--
--   The outbox row it wrote was status='pending' with next_attempt_at defaulting to now(), and
--   fn_phase_c_outbox_claim claims exactly `status in ('pending','retry_wait') and
--   next_attempt_at <= now()`. So a service_role caller — the role every edge function runs as —
--   could inject a deliverable event into the kernel's outbox with no kernel entry point and no
--   trace. fn_kernel_outbox_emit writes a trace; this primitive does not.
--
--   Callers, measured before revoking, over pg_proc.prosrc, cron.job.command, supabase/functions
--   and src/:
--     fn_phase_c_task_transition  <- fn_kernel_step_complete        (only)
--     fn_phase_c_handoff_decide   <- fn_kernel_handoff_accept       (only)
--     fn_phase_c_outbox_emit      <- nothing, anywhere
--     fn_phase_c_handoff_open     <- nothing, anywhere
--     fn_phase_c_*_trace_subject  <- attached as triggers z90_*, never called by name
--   Every caller is SECURITY DEFINER owned by postgres, so revoking EXECUTE from the ordinary
--   roles cannot break them. fn_phase_c_task_trace_subject additionally still held EXECUTE for
--   PUBLIC (`=X/postgres` in its ACL).
--
-- FINDING 2 — TRUNCATE WAS NEVER GUARDED.
--   fn_kernel_write_guard is a ROW-level trigger. TRUNCATE fires no row-level trigger, and
--   service_role held TRUNCATE on all seven protected tables. Measured, aborted:
--
--     set local role service_role; truncate public.phase_c_handoff_run;
--     -> ACCEPTED, rows went 7 -> 0
--
--   kernel_write_guard_both_directions.test.mjs proves seven cases and none of them is a TRUNCATE.
--   The grant is revoked below AND a statement-level guard is attached, because a revoke alone is
--   undone by the next `grant all`, silently — and this file exists because a disposition that
--   only one mechanism enforces is a disposition that is one edit from gone.
--
-- The maintenance door is the SAME door the row guard uses: the table owner, with
-- `set local kernel.maintenance_reason = '…'`, recorded in kernel_maintenance_write. Stating a
-- reason alone is not enough, and it never was.
--
-- READ-BACK IS THE PROOF. Re-run, after applying:
--   node scripts/checks/kernel_write_guard_both_directions.test.mjs
--   node scripts/checks/kernel_positive_controls.test.mjs
-- ============================================================================================

-- ---------------------------------------------------------------- FINDING 1: the six dispositions
insert into public.kernel_retired_path (path_name, disposition, replacement, evidence) values
  ('fn_phase_c_outbox_emit', 'KERNEL_INTERNAL_PRIMITIVE', 'fn_kernel_outbox_emit',
   'The outbox row-writer. Measured 17 Aug 2026: ZERO callers in pg_proc, cron.job, '
   || 'supabase/functions or src — and still EXECUTE-able by service_role, which wrote a '
   || 'deliverable pending row with trace_id NULL from outside the kernel. fn_kernel_outbox_emit '
   || 'is the entry point and it writes the trace; this one never did.'),
  ('fn_phase_c_handoff_open', 'KERNEL_INTERNAL_PRIMITIVE', 'fn_kernel_step_complete',
   'The handoff row-writer fn_kernel_step_complete asks for. Measured 17 Aug 2026: zero callers '
   || 'anywhere, and EXECUTE-able by service_role. Registered and revoked so the statement in '
   || 'kernel_write_authority.why is enforced rather than asserted.'),
  ('fn_phase_c_handoff_decide', 'KERNEL_INTERNAL_PRIMITIVE', 'fn_kernel_handoff_accept',
   'Records accept or reject. Sole caller at measurement: fn_kernel_handoff_accept, which is '
   || 'SECURITY DEFINER and owned by postgres, so the revoke below cannot reach it.'),
  ('fn_phase_c_task_transition', 'KERNEL_INTERNAL_PRIMITIVE', 'fn_kernel_step_complete',
   'The task state machine. Sole caller at measurement: fn_kernel_step_complete. It refuses a hop '
   || 'the Phase C model does not declare, but it does not ask who is calling, so the door has to '
   || 'be shut by the grant.'),
  ('fn_phase_c_step_run_trace_subject', 'KERNEL_INTERNAL_PRIMITIVE', 'trigger z90_phase_c_step_run_trace_subject',
   'Trigger helper that writes the step run its own trace_id. Reached by the trigger mechanism, '
   || 'never by name; EXECUTE for an ordinary role grants nothing it needs and is removed.'),
  ('fn_phase_c_task_trace_subject', 'KERNEL_INTERNAL_PRIMITIVE', 'trigger z90_phase_c_task_trace_subject',
   'Trigger helper that writes the task its own trace_id. It additionally still held EXECUTE for '
   || 'PUBLIC, which no trigger function has any use for.')
on conflict (path_name) do update
   set disposition = excluded.disposition,
       replacement = excluded.replacement,
       evidence    = excluded.evidence;

revoke all on function public.fn_phase_c_outbox_emit(text, text, jsonb, text)
  from public, anon, authenticated, service_role;
revoke all on function public.fn_phase_c_handoff_open(bigint, text, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.fn_phase_c_handoff_decide(bigint, text, text, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.fn_phase_c_task_transition(bigint, text, text, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.fn_phase_c_step_run_trace_subject()
  from public, anon, authenticated, service_role;
revoke all on function public.fn_phase_c_task_trace_subject()
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------- FINDING 2: TRUNCATE
create or replace function public.fn_kernel_truncate_guard()
returns trigger language plpgsql security invoker set search_path to 'public', 'pg_temp' as $s4trunc$
declare
  v_ctx    text;
  v_reason text;
  v_owner  text;
begin
  get diagnostics v_ctx = pg_context;

  -- There is no Door 1 here on purpose. No kernel routine truncates a protected table; a TRUNCATE
  -- is always maintenance, so the only door is the audited one the row guard already uses.
  v_reason := nullif(btrim(current_setting('kernel.maintenance_reason', true)), '');
  select tableowner into v_owner from pg_tables
   where schemaname = tg_table_schema and tablename = tg_table_name;
  if v_reason is not null and current_user = v_owner then
    perform public.fn_kernel_record_maintenance_write(
      current_user, session_user, tg_table_name, 'TRUNCATE', v_reason, v_ctx);
    return null;
  end if;

  raise exception
    'TRUNCATE on %.% is refused: a truncate is not a kernel write and fires no row-level guard.',
    tg_table_schema, tg_table_name
    using errcode = '42501',
          detail = 'Call stack was:' || chr(10) || v_ctx,
          hint = 'TRUNCATE removes every row without firing fn_kernel_write_guard, so it is '
              || 'refused outright. Historical maintenance needs BOTH a stated reason — set local '
              || 'kernel.maintenance_reason — AND the table owner, exactly as it does for an '
              || 'ordinary write, and it is recorded in kernel_maintenance_write either way.';
end
$s4trunc$;
revoke all on function public.fn_kernel_truncate_guard() from public;
grant execute on function public.fn_kernel_truncate_guard() to service_role;
comment on function public.fn_kernel_truncate_guard() is
  'Statement-level BEFORE TRUNCATE guard for the protected kernel tables. The row guard cannot see '
  'a TRUNCATE; measured 17 Aug 2026, service_role truncated phase_c_handoff_run 7 -> 0 with every '
  'instrument green. Same audited maintenance door as fn_kernel_write_guard, no equivalent of its '
  'Door 1: no kernel routine truncates.';

do $s4attach$
declare t text;
begin
  foreach t in array array['phase_c_workflow_run','phase_c_workflow_step_run','phase_c_task',
                           'phase_c_handoff_run','phase_c_event_outbox','phase_c_trace',
                           'founder_command'] loop
    execute format('revoke truncate on public.%I from public, anon, authenticated, service_role', t);
    execute format('drop trigger if exists z00_kernel_truncate_guard on public.%I', t);
    execute format('create trigger z00_kernel_truncate_guard before truncate on public.%I '
                || 'for each statement execute function public.fn_kernel_truncate_guard()', t);
  end loop;
end
$s4attach$;
