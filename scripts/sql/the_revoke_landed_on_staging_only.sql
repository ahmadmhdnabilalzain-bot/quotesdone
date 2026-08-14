-- THE REVOKE LANDED ON STAGING ONLY
--
-- scripts/sql/a_staffing_check_is_not_a_rehearsal.sql was applied with `--promote` and NOT
-- `--promote --ddl`. Promote carries the routine DEFINITION and not the GRANTS, so the two
-- `revoke all ... from public, anon, authenticated` lines at the foot of that file executed on
-- staging and never on production. A newly CREATEd SECURITY DEFINER function is granted EXECUTE to
-- PUBLIC, so both functions were left callable by anon on production.
--
-- project_parity caught it within minutes: anon-executable SECURITY DEFINER prod 58 / staging 56,
-- DRIFT +2 prod-only. That check earning its keep is the only reason this was a five-minute defect
-- rather than a standing hole.
--
-- fn_scenario_rehearse_all() WRITES — it updates scenario_library.last_run/last_result and inserts
-- into agent_runs — so an anonymous caller could have rewritten the resilience record. This is the
-- known trap and I walked into it: use --promote --ddl whenever a file contains anything that is
-- not a routine body.

revoke all on function public.fn_scenario_rehearse(text) from public, anon, authenticated;
revoke all on function public.fn_scenario_rehearse_all() from public, anon, authenticated;
