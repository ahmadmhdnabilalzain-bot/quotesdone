-- TWO BOARD ROWS WRITTEN WHEN THE DOOR HAD NEVER OPENED, AND TWO TABLES THAT BECAME ENFORCING.
--
-- NO TRANSACTION CONTROL. One CREATE OR REPLACE, two triggers, two revokes, one assertion block.
-- fn_phase_c_founder_auth_state is not a frozen Phase C subject (public.phase_c_frozen_subject
-- lists 25 objects and it is not among them), so no PCCR amendment is raised by this file.
--
-- ================================================================================================
-- A. TWO TABLES BECAME ENFORCING AND HAD NO TRUNCATE GUARD
-- ================================================================================================
--
-- a00_kernel_parent_delete_guard was attached to seven canonical relations on 2026-08-27. A trigger
-- that can RAISE makes its table ENFORCING, and fn_kernel_truncate_protection_state's whole point is
-- that a table whose triggers enforce a rule must not be emptiable by a statement that fires no row
-- trigger. Five of the seven already carried z00_kernel_truncate_guard. Two did not:
--
--     public.os_incidents        public.transactions
--
-- Both rows of that board went red — `2 of 95` on
-- `enforcing_tables_without_a_truncate_guard` and on `enforcing_tables_still_granting_truncate`.
-- The board was right and the omission was mine. TRUNCATE public.transactions would have taken every
-- payment the company has recorded, fired no row trigger, and left the new delete guard reporting
-- nothing at all.
--
-- ================================================================================================
-- B. "THE BIND DOOR MUST NOT BE EXECUTABLE BY authenticated" — WRITTEN BEFORE THE DESIGN CHANGED
-- ================================================================================================
--
-- `founder_bind_executable_by_anon_or_authenticated` expected 0 and read 1. It is not a regression;
-- it is the board still describing the shape PCCR-006 left behind, in which
-- fn_phase_c_founder_subject_bind was a SERVER path granted to service_role and to nobody else.
--
-- That shape was the finding of 26 Aug: the routine took the subject as an ARGUMENT, never compared
-- it to the caller's own auth.uid(), and service_role held EXECUTE — so a service_role call through
-- PostgREST carrying the founder's auth_user_id bound his subject with no founder token in
-- existence. The fix of 27 Aug requires p_subject = auth.uid(), requires the verified JWT role to be
-- `authenticated`, and moves the grant from service_role to authenticated. **The grant NARROWED.**
-- A board row that reads the new, narrower grant as the defect is measuring the wrong subject.
--
-- The row is therefore split rather than deleted, and the split is stricter than what it replaces:
--
--   founder_bind_executable_by_anon_service_role_or_public   expected 0
--       — every role that must NOT reach it, named, including service_role, which the old row did
--         not check at all. Under the old row, restoring the service_role grant — the actual hole —
--         left the board GREEN.
--   founder_bind_reachable_by_the_authenticated_session      expected 1
--       — the positive half. A revoke that closes the founder's own path would otherwise look like
--         a security improvement on every board in this estate.
--
-- ================================================================================================
-- C. "founder_auth_events_still_committed = 0" — TRUE ONLY WHILE THE DOOR HAD NEVER WORKED
-- ================================================================================================
--
-- public.phase_c_founder_auth_event held 0 rows from the day PCCR-006 created it until
-- 2026-08-27 12:03 UTC, because fn_phase_c_governance_decide was not on
-- public.kernel_write_authority and the kernel write guard refused its every mint with 42501. With
-- the table permanently empty, "any row here is a probe leftover" was a serviceable rule.
--
-- It is not one now. The two rows in that table are the first two real founder sessions this estate
-- has ever recorded: event 1611, the founder binding his own subject over HTTPS; event 1612, the
-- purpose-bound GOVERNANCE_DECISION session that carried his approval of PCCR-007 and is referenced
-- by decision 6. The table is append-only — a00_phase_c_founder_auth_event_is_server_minted refuses
-- DELETE outright — so "expected 0" is now an expectation the estate can never satisfy again, and a
-- check that can only fail is not a check.
--
-- What is worth checking is not the COUNT but whether every row could only have come from a verified
-- session. Three properties, each enforced at write time and each re-read here, because a guard and
-- a board that disagree is the shape this session spent its afternoon on:
--
--   * every event names an active, email-kind founder identity;
--   * every event names the transaction that minted it;
--   * every GOVERNANCE_DECISION event was consumed, because the session is spent before the decision
--     is written so that a failure between the two cannot leave a reusable session behind.
--
-- A fixture cannot produce a row here at all: the mint refuses any connection whose session_user is
-- not `authenticator`, and no test in this repository has one. That is stated as the reason the old
-- row is not simply retained alongside the new ones.
--
-- ================================================================================================

-- ---- A. THE TWO TRUNCATE GUARDS -----------------------------------------------------------------
drop trigger if exists z00_kernel_truncate_guard on public.os_incidents;
create trigger z00_kernel_truncate_guard before truncate on public.os_incidents
  for each statement execute function public.fn_kernel_truncate_guard();
revoke truncate on public.os_incidents from public, anon, authenticated, service_role;

drop trigger if exists z00_kernel_truncate_guard on public.transactions;
create trigger z00_kernel_truncate_guard before truncate on public.transactions
  for each statement execute function public.fn_kernel_truncate_guard();
revoke truncate on public.transactions from public, anon, authenticated, service_role;

-- ---- B + C. THE BOARD ---------------------------------------------------------------------------
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
  -- B, negative half. service_role is named here and was not named in the row this replaces, which
  -- is why restoring the actual hole used to leave the board green.
  select 'founder_bind_executable_by_anon_service_role_or_public', '0',
         (select coalesce(string_agg(distinct grantee, ' '), '0') from information_schema.routine_privileges
           where routine_schema = 'public' and routine_name = 'fn_phase_c_founder_subject_bind'
             and grantee in ('anon','service_role','PUBLIC')),
         not exists (select 1 from information_schema.routine_privileges
                      where routine_schema = 'public'
                        and routine_name = 'fn_phase_c_founder_subject_bind'
                        and grantee in ('anon','service_role','PUBLIC'))
  union all
  -- B, positive half. A revoke that closes the founder's own path is not a security improvement.
  select 'founder_bind_reachable_by_the_authenticated_session', '1',
         (select count(*)::text from information_schema.routine_privileges
           where routine_schema = 'public' and routine_name = 'fn_phase_c_founder_subject_bind'
             and grantee = 'authenticated' and privilege_type = 'EXECUTE'),
         exists (select 1 from information_schema.routine_privileges
                  where routine_schema = 'public' and routine_name = 'fn_phase_c_founder_subject_bind'
                    and grantee = 'authenticated' and privilege_type = 'EXECUTE')
  union all
  -- B, the predicate that carries the whole fix. A body without it is the 26 Aug hole, whatever the
  -- grants say.
  select 'founder_bind_compares_the_subject_to_the_caller', '1',
         (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'fn_phase_c_founder_subject_bind'
             and p.prosrc like '%pd_founder_bind_subject_is_not_the_caller%'),
         exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'fn_phase_c_founder_subject_bind'
                    and p.prosrc like '%pd_founder_bind_subject_is_not_the_caller%')
  union all
  -- C, replacing "still committed = 0". The count is reported and is not the test.
  select 'founder_auth_events_not_backed_by_a_verified_session', '0',
         (select count(*)::text from public.phase_c_founder_auth_event e
           where e.txid is null
              or not exists (select 1 from public.phase_c_founder_identity f
                              where f.identity = e.identity and f.active and f.kind = 'email')
              or (e.action_class = 'GOVERNANCE_DECISION' and e.consumed_at is null))
           || ' of ' || (select count(*)::text from public.phase_c_founder_auth_event),
         not exists (select 1 from public.phase_c_founder_auth_event e
                      where e.txid is null
                         or not exists (select 1 from public.phase_c_founder_identity f
                                         where f.identity = e.identity and f.active and f.kind = 'email')
                         or (e.action_class = 'GOVERNANCE_DECISION' and e.consumed_at is null))
  union all
  select 'founder_auth_events_recorded',
         'informational — append-only, and mintable only on the PostgREST connection',
         (select count(*)::text from public.phase_c_founder_auth_event) || ' event(s), of which '
           || (select count(*)::text from public.phase_c_founder_auth_event
                where action_class = 'GOVERNANCE_DECISION')
           || ' carry a governance decision',
         true;
$function$;

-- ---- THE ASSERTIONS ------------------------------------------------------------------------------
do $assert$
declare v_red int; v_trunc int;
begin
  select count(*) into v_red from public.fn_phase_c_founder_auth_state() where not ok;
  if v_red <> 0 then
    raise exception 'fn_phase_c_founder_auth_state is red on % row(s)', v_red;
  end if;
  select count(*) into v_red from public.fn_kernel_truncate_protection_state() where not ok;
  if v_red <> 0 then
    raise exception 'fn_kernel_truncate_protection_state is red on % row(s)', v_red;
  end if;
  select count(*) into v_trunc from pg_trigger
   where tgname = 'z00_kernel_truncate_guard'
     and tgrelid in ('public.os_incidents'::regclass, 'public.transactions'::regclass);
  if v_trunc <> 2 then
    raise exception 'the truncate guard is attached to % of the 2 newly enforcing tables', v_trunc;
  end if;
  raise notice 'OK  founder_auth_state red=0  truncate_protection red=0  new truncate guards=%', v_trunc;
end
$assert$;
