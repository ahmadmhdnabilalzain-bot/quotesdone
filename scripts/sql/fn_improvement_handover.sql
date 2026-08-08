-- COMPONENT 17 — "the improvement questions reach someone" was a FLAG FLIP, not an arrival.
--
-- Measured on production 6 Aug 2026: all 13 improvement tasks counted as "picked up" had
-- status='assigned' and decided_by='approval_path' — moved out of 'proposed' by fn_task_approve's
-- hourly sweep, which reads the department's authority tier and nothing whatsoever about the
-- question. Six questions raised on 2026-07-28 sat at 'proposed' for nine days and were then all
-- flipped at the identical timestamp 2026-08-06 03:59:06. A column changed value; nobody received
-- anything.
--
-- Nor does the question travel on its own. fn_agent_context's workload block renders
-- `order by t.id limit 6` over the department's open tasks — the SIX OLDEST — so an improvement
-- question raised into a department with a backlog is never in the prompt. Measured across all 15
-- questions raised in the last 21 days: 2 reach any employee (both in `it`, which happens to hold
-- fewer than six open tasks), 13 reach nobody at all.
--
-- This hands each question to a NAMED ACTIVE EMPLOYEE as an item in that employee's own queue.
-- agent_actions is the queue an employee actually reads: supabase/functions/agent_brain/index.ts:139
-- selects `agent_actions ... .eq('agent', key) ... limit 15` into `my_pending_items`, which is the
-- context that employee reasons over, and agent_brain is what cos_execute dispatches department work
-- to. So the row is a delivery, not another column.
--
-- WHY A SWEEP AND NOT A TRIGGER. A trigger on org_tasks would deliver instantly, but org_tasks is
-- the hottest write path in the platform and an AFTER INSERT trigger that raises would stop task
-- creation everywhere; swallowing its exceptions would then hide the very failure this check exists
-- to see (that is how ~91% of fn_task_lesson's writes came to fail silently). An hourly sweep costs
-- at most one hour of latency on a WEEKLY question, is idempotent, and self-heals — if it is ever
-- switched off, the undelivered count climbs and comp-17 goes MISSING within the window.
--
-- NOT A FEEDBACK LOOP, checked before writing it: of the six triggers on agent_actions
-- (trg_action_gate, fn_category_knowledge_promote, dedupe_it_incident, fn_governance_stamp,
-- fn_invite_week_activate, fn_page_high_agent_action), NONE inserts into org_tasks or
-- company_event — verified against pg_get_functiondef on production. The only row this insert
-- causes is trg_action_gate's decision_log entry. risk='low' so fn_page_high_agent_action does not
-- page anybody about a weekly improvement question.
create or replace function public.fn_improvement_handover(p_limit int default 200)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  r          record;
  v_to       text;
  v_sent     int := 0;
  v_unstaffed int := 0;
  v_already  int := 0;
  v_sample   jsonb := '[]'::jsonb;
begin
  for r in
    select t.id, t.dept_key, t.title, t.detail, t.status, t.created_at
      from org_tasks t
     where t.title like '% improvement: %'
       and t.created_at > now() - interval '90 days'
     order by t.id
     limit greatest(coalesce(p_limit, 200), 1)
  loop
    if exists (select 1 from agent_actions a
                where a.kind = 'improvement_question'
                  and a.target_table = 'org_tasks' and a.target_id = r.id::text) then
      v_already := v_already + 1;
      continue;
    end if;

    -- The department's own head, then its lead, then any active member. Validated ACTIVE at each
    -- step: org_departments.brain_agent still names 'onboarding' for supplier_success, a department
    -- with zero employees, so an unvalidated coalesce would address the question to a vacant desk.
    select coalesce(
             (select d.brain_agent from org_departments d where d.dept_key = r.dept_key
               and exists (select 1 from org_agents a where a.agent_key = d.brain_agent and a.active)),
             (select d.lead_agent  from org_departments d where d.dept_key = r.dept_key
               and exists (select 1 from org_agents a where a.agent_key = d.lead_agent and a.active)),
             (select a.agent_key from org_agents a
               where a.active and a.department = r.dept_key order by a.agent_key limit 1))
      into v_to;

    if v_to is null then
      v_unstaffed := v_unstaffed + 1;
      continue;
    end if;

    insert into agent_actions (agent, kind, status, risk, title, recommendation, detail,
                               target_table, target_id, escalated)
    values (v_to, 'improvement_question', 'needs_review', 'low',
            left(r.title, 200),
            coalesce(nullif(r.detail, ''), r.title)
              || E'\n\nThis is one of the five weekly improvement questions your Operating System '
              || 'raised for ' || r.dept_key || '. Answer it, or say why it does not apply.',
            jsonb_build_object('org_task_id', r.id, 'dept_key', r.dept_key,
                               'raised_at', r.created_at, 'task_status', r.status,
                               'source', 'fn_improvement_handover'),
            'org_tasks', r.id::text, false);

    v_sent := v_sent + 1;
    if jsonb_array_length(v_sample) < 10 then
      v_sample := v_sample || jsonb_build_array(jsonb_build_object('task', r.id, 'to', v_to,
                                                                   'dept', r.dept_key));
    end if;
  end loop;

  return jsonb_build_object('delivered', v_sent, 'already_delivered', v_already,
                            'no_active_employee', v_unstaffed, 'sample', v_sample);
end
$function$;
