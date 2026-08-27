-- DOWN for phase_c_two_boards_written_when_the_door_had_never_opened.sql.
--
-- Applying this file removes the TRUNCATE guard from public.os_incidents and public.transactions —
-- so a single statement could empty every payment the company has recorded, firing no row trigger —
-- and restores two board rows that PCCR-006's own fix made false: one that reads the narrowed bind
-- grant as a defect while ignoring service_role entirely, and one that expects
-- public.phase_c_founder_auth_event to be empty, which it can never be again because the table is
-- append-only and now holds two real founder sessions. It exists because the deployment ledger
-- requires a stated reversal, not because reversing it is safe.

drop trigger if exists z00_kernel_truncate_guard on public.os_incidents;
drop trigger if exists z00_kernel_truncate_guard on public.transactions;

create or replace function public.fn_phase_c_founder_auth_state()
returns TABLE(check_name text, expected text, actual text, ok boolean)
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
  select 'enabled_founder_identities_without_an_auth_subject'::text, '0'::text,
         (select count(*)::text from public.phase_c_founder_identity
           where active and kind = 'email' and auth_user_id is null),
         not exists (select 1 from public.phase_c_founder_identity
                      where active and kind = 'email' and auth_user_id is null)
  union all
  select 'require_founder_still_resolves_a_caller_supplied_string', '0',
         (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'fn_phase_c_require_founder'
             and p.prosrc ~ 'f\.identity = lower\(btrim\(p_actor\)\)'),
         not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                      where n.nspname = 'public' and p.proname = 'fn_phase_c_require_founder'
                        and p.prosrc ~ 'f\.identity = lower\(btrim\(p_actor\)\)')
  union all
  select 'founder_bind_executable_by_anon_or_authenticated', '0',
         (select count(*)::text from information_schema.routine_privileges
           where routine_schema = 'public' and routine_name = 'fn_phase_c_founder_subject_bind'
             and grantee in ('anon','authenticated','PUBLIC')),
         not exists (select 1 from information_schema.routine_privileges
                      where routine_schema = 'public'
                        and routine_name = 'fn_phase_c_founder_subject_bind'
                        and grantee in ('anon','authenticated','PUBLIC'))
  union all
  select 'founder_auth_events_still_committed', '0',
         (select count(*)::text from public.phase_c_founder_auth_event),
         not exists (select 1 from public.phase_c_founder_auth_event);
$function$;
