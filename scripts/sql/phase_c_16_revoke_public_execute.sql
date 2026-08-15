-- Phase C — revoke PUBLIC execute on the twelve routines that still carry it.
--
-- Every SECURITY DEFINER routine Phase C created was revoked from PUBLIC in the migration that
-- created it. These twelve are the ones that were not: eleven trigger functions and one read-only
-- helper, all SECURITY INVOKER with a pinned search_path, so they run with the caller's own
-- privileges and RLS applies to them.
--
-- The Supabase linter agrees they are not a finding: of 743 advisories, the 41 that name a Phase C
-- object are all INFO `rls_enabled_no_policy` — RLS on with no policy, which is deny-by-default and
-- the correct posture for an internal runtime table. Zero WARN-level advisories name anything
-- Phase C created.
--
-- They are revoked anyway. A trigger function reachable as an RPC is a surface with no use: calling
-- fn_phase_c_task_state_guard() outside a trigger context raises, and calling
-- fn_phase_c_no_new_founder_approval_path() outside one raises by design. Nothing needs to reach
-- them and something might one day try, and the cost of closing that is one file.
--
-- `revoke ... from anon` is a SILENT NO-OP when the grant is held through PUBLIC, which is how it
-- is actually held here. So the revoke below names PUBLIC, and the grants that follow name the
-- roles that genuinely need it.
--
-- scripts/sql is append-only.  To change any of this, add a new file.

set lock_timeout = '8s';
set statement_timeout = '600s';

do $revoke$
declare r record; n bigint := 0;
begin
  for r in
    select p.oid::regprocedure::text as sig
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
    where ns.nspname = 'public'
      and (p.proname like 'fn\_phase\_c\_%' or p.proname like 'fn\_founder\_command%')
      and has_function_privilege('public', p.oid, 'execute')
  loop
    execute format('revoke all on function %s from public', r.sig);
    execute format('grant execute on function %s to service_role', r.sig);
    n := n + 1;
  end loop;
  raise notice 'Phase C: revoked PUBLIC execute on % routine(s)', n;
end $revoke$;
