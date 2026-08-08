-- 1. Remove PUBLIC (and therefore anon/authenticated) EXECUTE on the
--    SECURITY DEFINER trigger guard protecting public.app_secrets.
--    Trigger functions do not require EXECUTE for the trigger to fire,
--    so this is safe: the trigger keeps working, the RPC surface disappears.
revoke execute on function public.fn_protect_app_secret() from public;
revoke execute on function public.fn_protect_app_secret() from anon;
revoke execute on function public.fn_protect_app_secret() from authenticated;

-- 2. Pin search_path on the eight functions flagged as mutable.
alter function public.fn_os_selftest() set search_path = public, pg_temp;
alter function public.fn_decision_gate() set search_path = public, pg_temp;
alter function public.fn_idea_rescore() set search_path = public, pg_temp;
alter function public.fn_secops_test(sample text) set search_path = public, pg_temp;
alter function public.fn_idea_score(p_value numeric, p_effort text, p_confidence numeric) set search_path = public, pg_temp;
alter function public.fn_seniority_rank(p text) set search_path = public, pg_temp;
alter function public.fn_budget_available(p_dept text) set search_path = public, pg_temp;
alter function public.fn_simulate_growth(p_invites_per_day integer, p_invite_accept_rate numeric, p_verification_rate numeric, p_months integer, p_target_verified integer) set search_path = public, pg_temp;