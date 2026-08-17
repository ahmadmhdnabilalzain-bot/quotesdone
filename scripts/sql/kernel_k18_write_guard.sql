-- K18 — business work can only be written from inside the kernel, enforced by the database.
--
-- Everything before this file is a convention. K10 records which source should call which adapter;
-- K17 records which class each source belongs to; K13 records which old paths are retired. All of
-- it is true and none of it is ENFORCED: a new Edge Function with the service key, or a routine
-- somebody adds next month, can still insert straight into phase_c_workflow_run and nothing stops
-- it. §7 of the brief says so in as many words — "do not rely solely on code conventions".
--
-- WHY A GUC IS NOT ENOUGH. The obvious guard is a flag: set kernel.in_kernel = 'on' inside the
-- kernel, and refuse writes without it. fn_kernel_assert_in_kernel already does this for the
-- internal primitives. But any caller with SQL access can write
--
--   set local kernel.in_kernel = 'on';
--
-- and walk straight through. A token the untrusted caller can mint is not a token. The brief is
-- explicit: "the guard cannot be enabled by an untrusted caller".
--
-- WHAT CANNOT BE FORGED: THE CALL STACK. plpgsql exposes it —
--
--   get diagnostics v_ctx = pg_context;
--
-- and inside a trigger that returns the whole chain, caller by caller. Measured on production
-- before this file was written, from a trigger on a temp table:
--
--   PL/pgSQL function pg_temp_38.zz_trg() line 4 at GET DIAGNOSTICS
--   SQL statement "insert into zz_probe values (1)"
--   PL/pgSQL function pg_temp_38.zz_caller() line 2 at SQL statement
--   ...
--
-- The trigger can see exactly which routines are on the stack above it. There is no setting that
-- adds a frame, and no way to write SQL that claims to be running inside a function it is not
-- running inside. So the guard asks the only question that cannot be answered falsely: is a
-- routine with authority to write this table actually on the stack right now?
--
-- WHAT IS PROTECTED, and it is the founder's list:
--   phase_c_workflow_run, phase_c_workflow_step_run, phase_c_task, phase_c_handoff_run,
--   kernel_trigger_inbox, phase_c_event_outbox (the canonical domain-event outbox),
--   kernel_signal_inbox, phase_c_refund_decision (founder refund decisions).
-- Internal-review verdicts are not a separate table: fn_kernel_review_decide records them on
-- phase_c_task, which is on the list.
--
-- THE TWO DOORS, and nothing else:
--
--   1. A routine named in kernel_write_authority for that table is on the call stack.
--      The seed is the MEASURED writer set — every routine whose deployed body writes one of
--      these tables today — so installing this guard breaks nothing that already works. It is a
--      ceiling on the future, not a change to the present.
--
--   2. An explicit, audited maintenance operation:
--        set local kernel.maintenance_reason = 'why this history is being touched by hand';
--      AND current_user = the table owner. anon, authenticated and service_role cannot become
--      that role, so this door does not exist for them at all — it is for a human holding the
--      management token, and every use writes a row to kernel_maintenance_write recording the
--      reason, the table, the operation and the stack.
--
-- Anything else is refused, and the refusal carries the actual call stack, so whoever hit it can
-- see the path they took rather than guessing.
--
-- WHAT THIS DOES NOT CLAIM. A routine already on the allow-list can still be changed to do the
-- wrong thing; the guard checks WHO writes, not WHAT they write. The allow-list is deliberately
-- short and every entry names the reason it is there, so adding one is a visible act in a
-- reviewed migration rather than a silent import.
--
-- Rollback: scripts/sql/rollback/kernel_k18_write_guard.rollback.sql

begin;

-- ------------------------------------------------------------------ 1. who may write what
create table if not exists public.kernel_write_authority (
  routine_name  text not null,
  table_name    text not null,
  why           text not null,
  added_at      timestamptz not null default now(),
  primary key (routine_name, table_name),
  constraint kernel_write_authority_reason_is_not_a_label check (length(btrim(why)) >= 30)
);

comment on table public.kernel_write_authority is
  'K18. The complete list of routines permitted to write a business-work table, and why each one '
  'is on it. The guard checks the LIVE CALL STACK against this table, which is why a GUC cannot '
  'open it: a caller can set a flag, it cannot invent a stack frame. Adding a row here is the only '
  'way to grant a new writer, and it takes a migration somebody reads.';

alter table public.kernel_write_authority enable row level security;
revoke all on public.kernel_write_authority from public, anon, authenticated;
grant select on public.kernel_write_authority to service_role;

-- ------------------------------------------------------------------ 2. the audited maintenance log
create table if not exists public.kernel_maintenance_write (
  maintenance_id bigserial primary key,
  at             timestamptz not null default now(),
  db_user        text not null,
  session_role   text not null,
  table_name     text not null,
  operation      text not null,
  reason         text not null,
  call_stack     text not null
);

comment on table public.kernel_maintenance_write is
  'K18. One row per direct write to a business-work table made by hand under '
  'kernel.maintenance_reason. Historical maintenance is allowed — the brief requires a door for '
  'it — but never quietly: the reason, the role, the operation and the call stack are recorded '
  'before the write lands.';

alter table public.kernel_maintenance_write enable row level security;
revoke all on public.kernel_maintenance_write from public, anon, authenticated;
grant select on public.kernel_maintenance_write to service_role;

-- ------------------------------------------------------------------ 3. the guard
create or replace function public.fn_kernel_write_guard()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $k18_guard$
declare
  v_ctx    text;
  v_reason text;
  v_owner  text;
  v_ok     boolean;
begin
  get diagnostics v_ctx = pg_context;

  -- Door 1: an authorised routine is on the stack. The stack is read as text and matched against
  -- the allow-list, so a routine that merely EXISTS proves nothing — it has to be executing.
  select exists (
    select 1 from public.kernel_write_authority a
     where a.table_name = tg_table_name
       and v_ctx ~ ('PL/pgSQL function (public\.)?' || a.routine_name || '\(')
  ) into v_ok;
  if v_ok then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  -- Door 2: an explicit, audited maintenance operation by the table owner. A stated reason alone
  -- is not enough, and being the owner alone is not enough: both, or neither.
  v_reason := nullif(btrim(current_setting('kernel.maintenance_reason', true)), '');
  select tableowner into v_owner from pg_tables
   where schemaname = tg_table_schema and tablename = tg_table_name;
  if v_reason is not null and current_user = v_owner then
    insert into public.kernel_maintenance_write
      (db_user, session_role, table_name, operation, reason, call_stack)
    values (current_user, session_user, tg_table_name, tg_op, v_reason, v_ctx);
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
              || 'and why. If this really is historical maintenance, state it in the same '
              || 'transaction — set local kernel.maintenance_reason = ''...'' — which is recorded '
              || 'in public.kernel_maintenance_write and requires the table owner.';
end
$k18_guard$;

revoke all on function public.fn_kernel_write_guard() from public, anon, authenticated;

-- ------------------------------------------------------------------ 4. the seed: measured, not guessed
--
-- Every routine below was found by scanning the DEPLOYED body of every function in public for a
-- write to the table named, comments stripped. Nothing was added from memory, and nothing that
-- writes today was left out — installing this guard changes no working path.
insert into public.kernel_write_authority (routine_name, table_name, why) values
  -- phase_c_workflow_run
  ('fn_kernel_workflow_start',        'phase_c_workflow_run',      'K2/K14. The only creator of a workflow run. Everything else on this table updates one that already exists.'),
  ('fn_kernel_step_complete',         'phase_c_workflow_run',      'K3. Moves the run state as steps close, and closes the run at its closure step.'),
  ('fn_kernel_handoff_accept',        'phase_c_workflow_run',      'K3. Moves the run out of waiting_handoff when the receiving owner accepts the packet.'),
  ('fn_kernel_cancel',                'phase_c_workflow_run',      'K4. Cancels or supersedes a run and propagates that to everything beneath it.'),
  ('fn_phase_c_workflow_start',       'phase_c_workflow_run',      'Kernel-internal primitive, registered as such in kernel_retired_path and guarded by fn_kernel_assert_in_kernel.'),
  -- phase_c_workflow_step_run
  ('fn_kernel_workflow_start',        'phase_c_workflow_step_run', 'K2/K14. Opens the entry step run of a new workflow run.'),
  ('fn_kernel_open_step',             'phase_c_workflow_step_run', 'K3. The single place a step run is opened; it refuses a second live run of the same step.'),
  ('fn_kernel_step_complete',         'phase_c_workflow_step_run', 'K3. Closes a step run and records its output hash and gate results.'),
  ('fn_kernel_cancel',                'phase_c_workflow_step_run', 'K4. Cancels the step runs beneath a cancelled run.'),
  ('fn_phase_c_step_run_trace_subject','phase_c_workflow_step_run','Trigger helper that writes the step run its own trace_id. It normalises one row, it starts nothing.'),
  -- phase_c_task
  ('fn_phase_c_task_create',          'phase_c_task',              'Kernel-internal primitive, registered as such. The only creator of a task; the kernel calls it once per step run.'),
  ('fn_phase_c_task_transition',      'phase_c_task',              'The task state machine. Every legal hop goes through it, and it refuses one the Phase C model does not declare.'),
  ('fn_phase_c_task_trace_subject',   'phase_c_task',              'Trigger helper that writes the task its own trace_id. It normalises one row, it starts nothing.'),
  ('fn_kernel_review_decide',         'phase_c_task',              'K7. Records an internal review verdict on the task of the step under review; independence is enforced there.'),
  ('fn_kernel_cancel',                'phase_c_task',              'K4. Cancels the tasks beneath a cancelled run or command.'),
  ('fn_founder_command_submit',       'phase_c_task',              'K2b. The founder command path, routed through the kernel; it is a canonical Phase C entry point, not a parallel runtime.'),
  ('fn_founder_command_clarify',      'phase_c_task',              'K9/K2c. Answering a clarification goes through the kernel; the control exists and this is its writer.'),
  ('fn_founder_command_control',      'phase_c_task',              'K9. The founder command control surface, routed through the kernel.'),
  -- phase_c_handoff_run
  ('fn_kernel_step_complete',         'phase_c_handoff_run',       'K3. Creates the handoff run from a real accepted output when a step closes. Since K14 it is the ONLY creator.'),
  ('fn_phase_c_handoff_open',         'phase_c_handoff_run',       'Kernel-internal primitive that writes the row fn_kernel_step_complete asks for.'),
  ('fn_phase_c_handoff_decide',       'phase_c_handoff_run',       'Kernel-internal primitive that records accept or reject, called only by fn_kernel_handoff_accept.'),
  ('fn_kernel_cancel',                'phase_c_handoff_run',       'K4. Cancels open handoff runs beneath a cancelled run.'),
  -- kernel_trigger_inbox
  ('fn_kernel_trigger_submit',        'kernel_trigger_inbox',      'K10. The request door. It is the only writer of the inbox, including for refusals and deferrals.'),
  -- kernel_signal_inbox
  ('fn_kernel_signal_submit',         'kernel_signal_inbox',       'K16. The signal door. It is the only writer of the signal ledger, including for refusals.'),
  -- phase_c_event_outbox
  ('fn_kernel_outbox_emit',           'phase_c_event_outbox',      'K5. Emits one factual event after the state it describes already exists.'),
  ('fn_kernel_outbox_deliver',        'phase_c_event_outbox',      'K5. The delivery worker; it marks rows delivered and may not re-enter the producer.'),
  ('fn_kernel_cancel',                'phase_c_event_outbox',      'K4. Cancels queued outbox rows beneath a cancelled command or run, so a cancellation does not leak an event.'),
  ('fn_phase_c_outbox_emit',          'phase_c_event_outbox',      'Kernel-internal primitive that writes the row fn_kernel_outbox_emit asks for.'),
  ('fn_phase_c_outbox_claim',         'phase_c_event_outbox',      'Kernel-internal primitive, registered as such; claims a batch for one worker.'),
  ('fn_phase_c_outbox_settle',        'phase_c_event_outbox',      'Registered READ_ONLY_HISTORICAL in kernel_retired_path; it settles rows the old worker claimed and writes no new ones.')
on conflict (routine_name, table_name) do update set why = excluded.why;

-- phase_c_refund_decision has NO routine writing it today — measured, not assumed. It is still
-- protected, so the first thing that tries becomes a refusal with a stack rather than a silent
-- write to the founder's refund ledger. K8 already made those rows immutable once written; this
-- closes the other end.

-- ------------------------------------------------------------------ 5. attach it
do $attach$
declare t text;
begin
  foreach t in array array[
    'phase_c_workflow_run','phase_c_workflow_step_run','phase_c_task','phase_c_handoff_run',
    'kernel_trigger_inbox','kernel_signal_inbox','phase_c_event_outbox','phase_c_refund_decision']
  loop
    -- a00_ so it runs before every other BEFORE trigger: Postgres fires them in NAME order, and a
    -- guard that runs after a normalising trigger has already let that trigger act.
    execute format('drop trigger if exists a00_kernel_write_guard on public.%I', t);
    execute format('create trigger a00_kernel_write_guard before insert or update or delete '
                || 'on public.%I for each row execute function public.fn_kernel_write_guard()', t);
  end loop;
end
$attach$;

-- ------------------------------------------------------------------ 6. the invariant board
create or replace function public.fn_kernel_write_guard_state()
returns table (check_name text, expected text, actual text, ok boolean)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $k18_state$
with protected(t) as (values
  ('phase_c_workflow_run'),('phase_c_workflow_step_run'),('phase_c_task'),('phase_c_handoff_run'),
  ('kernel_trigger_inbox'),('kernel_signal_inbox'),('phase_c_event_outbox'),('phase_c_refund_decision')),
attached as (
  select p.t, exists (
    select 1 from pg_trigger tg join pg_class c on c.oid = tg.tgrelid
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = p.t
      and tg.tgname = 'a00_kernel_write_guard' and not tg.tgisinternal and tg.tgenabled <> 'D') a
  from protected p
),
-- Every routine whose DEPLOYED body writes a protected table, measured from prosrc with comments
-- stripped — the same scan that produced the seed. A writer that is not on the allow-list is a
-- routine that will be refused at runtime, and it is better to see it here than in an outage.
writers as (
  select p.proname, t.t
    from protected t
    join pg_proc p on true
    join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
   where regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', ' ', 'g'), '--[^\n]*', ' ', 'g')
         ~ ('(insert\s+into|update|delete\s+from)\s+(public\.)?' || t.t || '\M')
     and p.proname <> 'fn_kernel_write_guard'
)
select 'protected_tables_without_the_guard_attached'::text,
       '0 of ' || (select count(*)::text from protected),
       (select count(*)::text from attached where not a) || ' of ' || (select count(*)::text from protected),
       (select count(*) = 0 from attached where not a)
union all
select 'routines_that_write_a_protected_table_with_no_authority',
       '0 of ' || (select count(*)::text from writers),
       (select count(*)::text from writers w
         where not exists (select 1 from public.kernel_write_authority a
                            where a.routine_name = w.proname and a.table_name = w.t))
         || ' of ' || (select count(*)::text from writers)
         || coalesce(' [' || (select string_agg(distinct w.proname || '->' || w.t, ', ')
              from writers w where not exists (select 1 from public.kernel_write_authority a
                                                where a.routine_name = w.proname and a.table_name = w.t)) || ']', ''),
       (select count(*) = 0 from writers w
         where not exists (select 1 from public.kernel_write_authority a
                            where a.routine_name = w.proname and a.table_name = w.t))
union all
select 'write_authority_granted_to_a_routine_that_does_not_exist',
       '0 of ' || (select count(*)::text from public.kernel_write_authority),
       (select count(*)::text from public.kernel_write_authority a
         where not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                            where n.nspname = 'public' and p.proname = a.routine_name))
         || ' of ' || (select count(*)::text from public.kernel_write_authority),
       (select count(*) = 0 from public.kernel_write_authority a
         where not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                            where n.nspname = 'public' and p.proname = a.routine_name))
union all
select 'ordinary_roles_holding_direct_dml_on_a_protected_table',
       '0',
       (select count(*)::text from information_schema.role_table_grants
         where table_schema = 'public' and table_name in (select t from protected)
           and grantee in ('anon','authenticated','PUBLIC')
           and privilege_type in ('INSERT','UPDATE','DELETE')),
       (select count(*) = 0 from information_schema.role_table_grants
         where table_schema = 'public' and table_name in (select t from protected)
           and grantee in ('anon','authenticated','PUBLIC')
           and privilege_type in ('INSERT','UPDATE','DELETE'))
union all
select 'maintenance_writes_recorded',
       'reported, never zero-by-hiding',
       (select count(*)::text from public.kernel_maintenance_write)
         || ' hand-made writes recorded'
         || coalesce(', most recent ' || (select max(at)::text from public.kernel_maintenance_write), ''),
       true
union all
select 'maintenance_writes_with_no_stated_reason',
       '0 of ' || (select count(*)::text from public.kernel_maintenance_write),
       (select count(*)::text from public.kernel_maintenance_write where btrim(reason) = '')
         || ' of ' || (select count(*)::text from public.kernel_maintenance_write),
       (select count(*) = 0 from public.kernel_maintenance_write where btrim(reason) = '');
$k18_state$;

revoke all on function public.fn_kernel_write_guard_state() from public, anon, authenticated;
grant execute on function public.fn_kernel_write_guard_state() to service_role;

comment on function public.fn_kernel_write_guard_state() is
  'K18 invariants. The second line re-runs the scan that produced the allow-list: any routine '
  'whose deployed body writes a protected table but holds no authority will be refused at '
  'runtime, and it is better to read that here than to find it in an outage.';

commit;
