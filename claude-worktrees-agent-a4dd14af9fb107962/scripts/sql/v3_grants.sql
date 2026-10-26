-- The grants for the V3 routines, applied to BOTH projects.
--
-- apply_sql --promote carries the routine DEFINITION and nothing else, so the `revoke all
-- … from public` lines in the files that created these twelve functions ran on staging and
-- never on production. project_parity caught it: twelve SECURITY DEFINER functions were
-- anon-executable on production and revoked on staging.
--
-- Revoking from PUBLIC rather than from anon: a grant held through PUBLIC makes
-- `revoke … from anon` a silent no-op.
revoke all on function fn_propose_lesson(text, text, text, jsonb, numeric, date) from public;
revoke all on function fn_validate_lesson(bigint, text, text, text) from public;
revoke all on function fn_supersede_lesson(bigint, bigint, text) from public;
revoke all on function fn_assign_training(text, text, text, integer) from public;
revoke all on function fn_open_remediation(text, text, text, jsonb) from public;
revoke all on function fn_remediation_step(bigint, numeric, numeric) from public;
revoke all on function fn_agent_autonomy_blocked(text) from public;
revoke all on function fn_knowledge_freshness_sweep() from public;
revoke all on function fn_category_checklist(text, text, text) from public;
revoke all on function fn_category_quote_ready(text, jsonb, text) from public;
revoke all on function fn_role_readiness_recompute() from public;
revoke all on function fn_category_readiness_recompute() from public;

-- The service role still needs the four an edge function actually calls.
grant execute on function fn_propose_lesson(text, text, text, jsonb, numeric, date) to service_role;
grant execute on function fn_validate_lesson(bigint, text, text, text) to service_role;
grant execute on function fn_assign_training(text, text, text, integer) to service_role;
grant execute on function fn_open_remediation(text, text, text, jsonb) to service_role;
grant execute on function fn_remediation_step(bigint, numeric, numeric) to service_role;
grant execute on function fn_agent_autonomy_blocked(text) to service_role;
grant execute on function fn_category_checklist(text, text, text) to service_role;
grant execute on function fn_category_quote_ready(text, jsonb, text) to service_role;
