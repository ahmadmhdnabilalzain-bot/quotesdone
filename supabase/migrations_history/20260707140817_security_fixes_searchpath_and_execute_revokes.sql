-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260707140817   name: security_fixes_searchpath_and_execute_revokes
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Pin search_path on the 13 SECURITY DEFINER functions (function_search_path_mutable).
-- Config-only; bodies untouched. Signatures verified against live pg_proc.
alter function public.fn_os_nav()                 set search_path = public, pg_catalog;
alter function public.fn_os_record(text, text)    set search_path = public, pg_catalog;
alter function public.fn_os_search(text)          set search_path = public, pg_catalog;
alter function public.fn_ws_ai()                  set search_path = public, pg_catalog;
alter function public.fn_ws_analytics()           set search_path = public, pg_catalog;
alter function public.fn_ws_company()             set search_path = public, pg_catalog;
alter function public.fn_ws_customers()           set search_path = public, pg_catalog;
alter function public.fn_ws_documents()           set search_path = public, pg_catalog;
alter function public.fn_ws_exec()                set search_path = public, pg_catalog;
alter function public.fn_ws_knowledge()           set search_path = public, pg_catalog;
alter function public.fn_ws_marketplace()         set search_path = public, pg_catalog;
alter function public.fn_ws_operations()          set search_path = public, pg_catalog;
alter function public.fn_ws_suppliers(jsonb)      set search_path = public, pg_catalog;

-- Revoke EXECUTE from anon/authenticated/public on the same functions + action-gate
-- trigger fn. App calls them via service-role inside Edge Functions (bypasses grants).
revoke execute on function public.fn_os_nav()              from anon, authenticated, public;
revoke execute on function public.fn_os_record(text, text) from anon, authenticated, public;
revoke execute on function public.fn_os_search(text)       from anon, authenticated, public;
revoke execute on function public.fn_ws_ai()               from anon, authenticated, public;
revoke execute on function public.fn_ws_analytics()        from anon, authenticated, public;
revoke execute on function public.fn_ws_company()          from anon, authenticated, public;
revoke execute on function public.fn_ws_customers()        from anon, authenticated, public;
revoke execute on function public.fn_ws_documents()        from anon, authenticated, public;
revoke execute on function public.fn_ws_exec()             from anon, authenticated, public;
revoke execute on function public.fn_ws_knowledge()        from anon, authenticated, public;
revoke execute on function public.fn_ws_marketplace()      from anon, authenticated, public;
revoke execute on function public.fn_ws_operations()       from anon, authenticated, public;
revoke execute on function public.fn_ws_suppliers(jsonb)   from anon, authenticated, public;
revoke execute on function public.trg_action_gate()        from anon, authenticated, public;
