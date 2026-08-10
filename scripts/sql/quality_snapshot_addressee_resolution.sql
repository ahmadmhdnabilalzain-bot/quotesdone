-- FOURTH INSTANCE of the same root cause, found by SWEEPING every agent_key/agent column in the
-- schema against org_agents rather than by guessing where to look:
--
--   agent_runs            17,111 of 19,667   NOT a defect -- `agent` there is the JOB name
--                                            (uptime, smoke, kb_embed, cos_execute), a different
--                                            vocabulary on purpose
--   ai_quality_snapshots     754 of 1,066    THE DEFECT
--   agent_expectations        29 of 36       the same defect, deliberately not forced (below)
--   agent_actions            415 of 2,377    done rows, history, left alone
--   model_policy_by_identity  80 of 120      the pack's 24 TARGET departments against the live 15
--
-- 754 ai_quality_snapshots rows score an employee under a name that is not an employee --
-- marketing_ai, knowledge_curator, security_ai, chief_of_staff, document_controller, reporting_ai,
-- operations_ai, customer_success, supplier_success, ai_trainer, strategy_ai, autogen -- 32 rows
-- each. So the Marketing Director's measured quality history EXISTS and is filed under a person who
-- does not work here, and every per-employee quality view sees an empty series.
--
-- Same fix shape as agent_actions: resolve at the write boundary through the same
-- fn_org_agent_resolve. Unlike agent_actions this backfills ALL rows rather than only live ones -- a
-- quality snapshot is a measurement ABOUT an employee and a trend needs its past. Nothing is
-- invented: only the name of the subject is corrected, and org_agent_alias holds the mapping and the
-- reason permanently, so the provenance is a row rather than a comment.
--
-- Rows whose agent is a JOB rather than a role (ai_health, backup, cost_snapshot) resolve to null
-- and are LEFT ALONE. ai_quality_snapshots legitimately scores subsystems as well as employees, and
-- forcing those onto a person would be the mirror of the defect being fixed.
--
-- agent_expectations carries the same defect on 29 of 36 rows and is DELIBERATELY NOT TOUCHED. Its
-- primary key is `agent`, so resolving chief_of_staff -> brief collides with brief's own row: 23505,
-- and the constraint is right to refuse. Two expectations for one employee is a MERGE, and which of
-- the two states what is actually expected of the Chief of Staff is a judgement, not a rename.
-- Recorded as a true finding rather than forced.
--
-- Measured after: 902 of 1,066 rows now attributed to a real employee, across 25 employees.

create or replace function public.fn_quality_snapshot_resolve_agent()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare v_key text;
begin
  if new.agent is null then return new; end if;
  if exists (select 1 from public.org_agents o where o.agent_key = new.agent and o.active) then
    return new;
  end if;
  v_key := public.fn_org_agent_resolve(new.agent);
  if v_key is not null then new.agent := v_key; end if;
  return new;
end $$;

drop trigger if exists trg_quality_snapshot_resolve_agent on public.ai_quality_snapshots;
create trigger trg_quality_snapshot_resolve_agent
  before insert on public.ai_quality_snapshots
  for each row execute function public.fn_quality_snapshot_resolve_agent();

update public.ai_quality_snapshots s
   set agent = public.fn_org_agent_resolve(s.agent)
 where public.fn_org_agent_resolve(s.agent) is not null
   and public.fn_org_agent_resolve(s.agent) <> s.agent;

revoke execute on function public.fn_quality_snapshot_resolve_agent() from public, anon, authenticated;
