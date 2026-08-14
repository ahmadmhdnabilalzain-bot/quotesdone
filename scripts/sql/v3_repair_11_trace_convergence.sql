-- V3 REMEDIATION — STAGE 3 (continued): ONE TRACE SHAPE, NOT THREE
--
-- Measured immediately after the first live agent_brain turn on staging (14 Aug 2026): four
-- decision_trace rows existed and only ONE of them was complete.
--
--   decision_type='agent_brain_turn'  agent_key=cfo   role_id=finance-director  sealed  <- new writer
--   decision_type='handoff'           agent_key=NULL  role_id=NULL              unsealed
--   decision_type='handoff'           agent_key=NULL  role_id=NULL              unsealed
--   decision_type='route_category'    agent_key=NULL  role_id=NULL              unsealed
--
-- The three incomplete rows come from the ORIGINAL fn_agent_action_trace(), the UPDATE-trigger
-- function that predates this remediation. It writes a trace with no identity on it, so
-- fn_management_decision_review cannot answer "what did this ROLE decide" for any of them — which
-- is the whole reason the trace exists.
--
-- Rather than leave two writers drifting apart (this repo has already lost a day to two files
-- defining one routine), the old trigger function is repointed at the shared row builder that the
-- INSERT path already uses. One body, both paths, same shape.

begin;

create or replace function public.fn_agent_action_trace()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- Delegates to the shared builder so the UPDATE path and the INSERT path cannot produce
  -- different trace shapes. fn_agent_action_trace_row resolves role, department and manager from
  -- the roster and pulls the knowledge actually retrieved near the decision.
  perform public.fn_agent_action_trace_row(new);
  return new;
end $$;

-- Backfill identity onto the traces already written by the old body. This does not invent
-- anything: agent_key is recovered from the agent_actions row the trace points at, and role,
-- department and manager come from the roster. Rows whose source action no longer exists are left
-- alone and stay visible in v_decision_trace_incomplete.
update decision_trace t
   set agent_key     = a.agent,
       role_id       = (select i.packaged_role_id from org_role_identity i
                         where i.agent_key = a.agent order by i.packaged_role_id limit 1),
       department_id = g.department,
       manager_id    = g.manager_key,
       final_status  = coalesce(t.final_status, a.status),
       escalation_decision = coalesce(t.escalation_decision,
                                      case when a.escalated then 'escalated' else 'within_authority' end)
  from agent_actions a
  left join org_agents g on g.agent_key = a.agent
 where t.agent_key is null
   and t.sealed_at is null
   and t.entity_id = a.id::text;

commit;
