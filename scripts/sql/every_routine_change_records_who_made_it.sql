-- EVERY ROUTINE CHANGE RECORDS WHO MADE IT.
--
-- Assigned: it_engineer. 14 Sep 2026.
--
-- MEASURED BEFORE WRITING (14 Sep 2026, production): three times in one afternoon a routine applied
-- from a reviewed file was rewritten minutes later by an older copy of the same file
-- (fn_customer_support_acts_on_handoff and fn_customer_support_delivery_watch at transactions
-- 9695836, 9699700 and 9702819; fn_it_engineer_alert_tick and fn_it_duties after 15:57 and 16:03
-- UTC). No CI workflow applies SQL, and every build helper reported that it applied nothing, so
-- the database itself has to say who did it. Nothing recorded the session behind a CREATE FUNCTION.
--
-- WHAT THIS ADDS: an event trigger on ddl_command_end that writes one row per routine created,
-- replaced, altered or dropped in public: who (session user, application name, client address,
-- backend pid), what (command tag, object identity), and the first 2,000 characters of the
-- statement, with anything shaped like a key, token, secret or password redacted. It never raises:
-- a failure to record must not block the change it records. Rows are kept (no pruning): this is an
-- audit trail, and the founder keeps records.
-- The log is service-role only, like every audit table here.

create table if not exists public.routine_change_log (
  id              bigint generated always as identity primary key,
  at              timestamptz not null default now(),
  txid            bigint      not null default txid_current(),
  session_user_name text      not null default session_user,
  application_name  text,
  client_addr     inet,
  backend_pid     int         not null default pg_backend_pid(),
  command_tag     text        not null,
  object_identity text        not null,
  statement_head  text
);
create index if not exists routine_change_log_object_at on public.routine_change_log (object_identity, at desc);
alter table public.routine_change_log enable row level security;
drop policy if exists routine_change_log_service_role_only on public.routine_change_log;
create policy routine_change_log_service_role_only on public.routine_change_log
  as permissive for all to public using (false) with check (false);
revoke all on public.routine_change_log from anon, authenticated;

create or replace function public.fn_record_routine_change()
returns event_trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r record;
begin
  for r in select * from pg_event_trigger_ddl_commands()
            where object_type in ('function', 'procedure') and schema_name = 'public'
  loop
      insert into public.routine_change_log (application_name, client_addr, command_tag, object_identity, statement_head)
      values (current_setting('application_name', true), inet_client_addr(), r.command_tag, r.object_identity,
              regexp_replace(regexp_replace(left(current_query(), 2000),
                '((key|secret|password|passwd|token|bearer|authorization)[a-z_]*\s*(=|:)\s*)(''[^'']*''|"[^"]*"|\S{8,})', '\1[REDACTED]', 'gi'),
                '\m((sk|rk|pk)_(live|test)_|whsec_|sbp_|eyJ)[A-Za-z0-9_\-\.]{8,}', '[REDACTED]', 'g'));
  end loop;
exception when others then null;  -- recording must never block the change it records, including a failure to read the event
end $fn$;

create or replace function public.fn_record_routine_drop()
returns event_trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r record;
begin
  for r in select * from pg_event_trigger_dropped_objects()
            where object_type in ('function', 'procedure') and schema_name = 'public'
  loop
      insert into public.routine_change_log (application_name, client_addr, command_tag, object_identity, statement_head)
      values (current_setting('application_name', true), inet_client_addr(), 'DROP FUNCTION', r.object_identity,
              regexp_replace(regexp_replace(left(current_query(), 2000),
                '((key|secret|password|passwd|token|bearer|authorization)[a-z_]*\s*(=|:)\s*)(''[^'']*''|"[^"]*"|\S{8,})', '\1[REDACTED]', 'gi'),
                '\m((sk|rk|pk)_(live|test)_|whsec_|sbp_|eyJ)[A-Za-z0-9_\-\.]{8,}', '[REDACTED]', 'g'));
  end loop;
exception when others then null;
end $fn$;

revoke execute on function public.fn_record_routine_change() from public, anon, authenticated;
revoke execute on function public.fn_record_routine_drop() from public, anon, authenticated;

drop event trigger if exists qd_record_routine_change;
create event trigger qd_record_routine_change on ddl_command_end
  when tag in ('CREATE FUNCTION', 'ALTER FUNCTION', 'CREATE PROCEDURE', 'ALTER PROCEDURE')
  execute function public.fn_record_routine_change();

drop event trigger if exists qd_record_routine_drop;
create event trigger qd_record_routine_drop on sql_drop
  execute function public.fn_record_routine_drop();

-- Both triggers must be attached and enabled, or nothing is being recorded. (An end-to-end probe,
-- a throwaway routine created and dropped, was run after the first apply and logged both rows.)
do $check$
declare n int;
begin
  if not exists (select 1 from pg_event_trigger where evtname = 'qd_record_routine_drop' and evtenabled <> 'D') then
    raise exception 'qd_record_routine_drop is not attached';
  end if;
  if not exists (select 1 from pg_event_trigger where evtname = 'qd_record_routine_change' and evtenabled <> 'D') then
    raise exception 'qd_record_routine_change is not attached';
  end if;
end $check$;
