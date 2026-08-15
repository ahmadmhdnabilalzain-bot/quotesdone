-- Phase B — pin search_path on the eight Phase B functions.
--
-- The Supabase security advisor flagged all eight as `function_search_path_mutable`, and for
-- three of them that is not cosmetic: fn_phase_b_owner_guard, fn_phase_b_workflow_owner_guard
-- and fn_phase_b_handoff_guard are TRIGGER functions, so they execute with the search_path of
-- whoever is doing the write. A caller who sets `search_path` to a schema of their own could
-- shadow public.org_role or public.phase_b_workflow_step with a table that answers differently,
-- and the guard would pass while checking the wrong data.
--
-- None of the eight is SECURITY DEFINER, so this is not privilege escalation — it is a guard
-- that could be made to look at the wrong table, which is the same failure mode as an
-- instrument reporting on the wrong subject.
--
-- pg_temp is last on purpose: it is where a temporary table would live, and putting it after
-- public means a temp table cannot shadow a real one.
--
-- ALTER FUNCTION ... SET does not change any body, so nothing here alters behaviour for a
-- caller with a normal search_path.

set lock_timeout = '8s';
set statement_timeout = '600s';

alter function public.fn_phase_b_resolve_role(text)                                    set search_path = public, pg_temp;
alter function public.fn_phase_b_owner_guard()                                         set search_path = public, pg_temp;
alter function public.fn_phase_b_workflow_owner_guard()                                set search_path = public, pg_temp;
alter function public.fn_phase_b_handoff_guard()                                       set search_path = public, pg_temp;
alter function public.fn_phase_b_transition_allowed(text, text)                        set search_path = public, pg_temp;
alter function public.fn_phase_b_step_transition_allowed(text, text)                   set search_path = public, pg_temp;
alter function public.fn_phase_b_closure_blockers(text, text[], bigint, bigint)        set search_path = public, pg_temp;
alter function public.fn_phase_b_invariants()                                          set search_path = public, pg_temp;

-- Verify by reading it back: all eight must now carry a proconfig entry.
do $$
declare v_unpinned bigint;
begin
  select count(*) into v_unpinned
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname like 'fn\_phase\_b\_%'
    and (p.proconfig is null or not (p.proconfig::text like '%search_path%'));
  if v_unpinned > 0 then
    raise exception 'phase_b: % function(s) still have a mutable search_path', v_unpinned;
  end if;
end $$;
