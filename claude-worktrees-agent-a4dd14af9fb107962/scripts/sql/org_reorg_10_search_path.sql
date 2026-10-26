-- REORGANISING THE AGENT COMPANY — pin search_path on the routines this work added.
--
-- Supabase's `function_search_path_mutable` advisor flagged all seven. None of them is SECURITY
-- DEFINER, so the exposure is smaller than for a definer function, but a resolver that decides
-- WHICH AGENT a message is addressed to should not be resolvable against a caller-supplied schema:
-- fn_org_role_resolve reads org_role, org_role_alias and org_agent_alias by unqualified name inside
-- CTE arms, and fn_dept_scope decides which department's knowledge an employee retrieves.
--
-- ALTER FUNCTION ... SET is used rather than CREATE OR REPLACE: it changes only the setting, so the
-- bodies stay byte-identical to the ones already promoted and verified on both projects.

begin;

alter function public.fn_org_role_resolve(text)      set search_path to 'public';
alter function public.fn_org_role_agent(text)        set search_path to 'public';
alter function public.fn_role_manager_chain(text)    set search_path to 'public';
alter function public.fn_org_role_violations()       set search_path to 'public';
alter function public.fn_dept_canonical(text)        set search_path to 'public';
alter function public.fn_dept_scope(text)            set search_path to 'public';
alter function public.fn_overlay_for_category(text)  set search_path to 'public';
alter function public.trg_org_role_no_cycle()        set search_path to 'public';
alter function public.trg_org_role_touch()           set search_path to 'public';
alter function public.fn_objective_cascade()         set search_path to 'public';

commit;
