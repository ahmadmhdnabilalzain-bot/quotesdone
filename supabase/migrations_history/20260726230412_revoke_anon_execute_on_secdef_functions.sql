-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260726230412   name: revoke_anon_execute_on_secdef_functions
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- SECURITY FIX. Four SECURITY DEFINER functions created earlier today were executable
-- by anon and authenticated, which is wrong for all of them:
--   fn_review_submit    - anon could inject rows into review_chain and company_event,
--                         corrupting the approval audit trail
--   fn_watch_failed_runs- anon could trigger founder alerts and outbound HTTP using the
--                         internal secret held server-side
--   fn_watch_health     - same
--   fn_select_model     - leaks internal model policy and department budget posture
-- These are internal/service functions. Only service_role and postgres should execute them.
revoke execute on function public.fn_review_submit(text, text, text, text, text) from anon, authenticated, public;
revoke execute on function public.fn_watch_failed_runs() from anon, authenticated, public;
revoke execute on function public.fn_watch_health() from anon, authenticated, public;
revoke execute on function public.fn_select_model(text, text, numeric) from anon, authenticated, public;

grant execute on function public.fn_review_submit(text, text, text, text, text) to service_role;
grant execute on function public.fn_watch_failed_runs() to service_role;
grant execute on function public.fn_watch_health() to service_role;
grant execute on function public.fn_select_model(text, text, numeric) to service_role;
