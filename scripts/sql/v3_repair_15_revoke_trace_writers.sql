-- V3 REMEDIATION — closing a hole this remediation opened.
--
-- An audit of every function created by this work found two of my own left EXECUTE to PUBLIC:
--
--   fn_agent_action_trace_row(agent_actions)   SECURITY DEFINER, and it WRITES decision_trace
--   fn_agent_action_trace_ins()                SECURITY DEFINER trigger function
--
-- proacl on both read '=X/postgres,postgres=X/postgres,service_role=X/postgres' - the leading
-- '=X/' is PUBLIC. v3_repair_02_decision_trace.sql revoked the functions it declared with an
-- explicit grant block and simply missed these two, which are the ones the triggers call.
--
-- fn_agent_action_trace_row is the material one. It is SECURITY DEFINER, so it runs as the owner,
-- and its whole job is to insert a decision_trace row with a caller-supplied agent_actions record.
-- Executable by PUBLIC, it is a way for anon or authenticated to FORGE AUDIT EVIDENCE - traces
-- naming any agent, any role, any confidence. The decision trace is the thing this remediation
-- exists to make trustworthy; a forgeable trace is worse than no trace, because it reads as
-- evidence.
--
-- Neither needs PUBLIC. Both are reached from triggers, which execute as the definer regardless of
-- who holds EXECUTE on the function.

begin;

revoke all on function public.fn_agent_action_trace_row(public.agent_actions) from public;
grant execute on function public.fn_agent_action_trace_row(public.agent_actions) to service_role;

revoke all on function public.fn_agent_action_trace_ins() from public;
grant execute on function public.fn_agent_action_trace_ins() to service_role;

commit;
