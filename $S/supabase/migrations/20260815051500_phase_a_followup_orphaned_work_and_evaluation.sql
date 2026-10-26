-- PHASE A FOLLOW-UP — the two things the post-deployment sweep found, and the one it found that
-- this file deliberately does NOT fix.
--
-- 1. FIVE OPEN TASKS ADDRESSED TO A RUNTIME EMPLOYEE THE MERGE STOOD DOWN.
--
-- The merge of partnerships + government_relations left one runtime employee, and gov_relations_mgr
-- was set inactive so that no live employee would be unowned by an active canonical role. Five
-- org_tasks were still assigned to it: status 'assigned', nobody able to pick them up. Exactly the
-- defect this session repaired this morning for a closed department, reintroduced by my own
-- migration and caught by the sweep rather than by anything failing.
--
-- They move to partnerships_mgr, the surviving employee of the merged role. Status is untouched.
update public.org_tasks
   set assigned_agent = 'partnerships_mgr', updated_at = now()
 where assigned_agent = 'gov_relations_mgr'
   and status in ('assigned', 'in_progress');

-- 2. THE NEW ROLE HAD NO EVALUATION SUITE.
--
-- Which suite grades a role is organizational design — it says what "done well" means for this
-- role — so it belongs in Phase A. It routes no spend and connects nothing.
update public.org_role
   set evaluation_suite = 'eval_ux_design', updated_at = now()
 where role_id = 'product_ux_designer' and evaluation_suite is null;

-- 3. WHAT THIS FILE DOES NOT DO, AND WHY THAT IS THE DECISION RATHER THAN AN OMISSION.
--
-- fn_org_role_violations() now reports three rules against product_ux_designer: no_kpi,
-- no_knowledge, no_tools — plus no_authority. It reported ZERO before Phase A. That is a real
-- change and it is stated here rather than buried.
--
-- The tempting fix is to grant the role a KPI, a knowledge scope and a tool and take the count back
-- to zero. Three reasons not to:
--
--   a. Phase A's own scope forbids it. "Do not work on knowledge content, tools, models, prompts,
--      decision traces, runtime quality." The package repeats it in the exclusions and again in the
--      production-direct constraints. Granting them would be a Phase B change wearing a Phase A
--      commit message.
--   b. fn_org_role_violations() is a RUNTIME-READINESS check, not an organizational-design one. It
--      asks "can this employee work?". For a role that Phase A creates and Phase B activates, the
--      correct answer today is "not yet", and a check that says so is telling the truth.
--   c. There is no honest tool to grant. The tools held by comparable advisory specialists are
--      qualify_inquiry, route_category, supplier_verify, supplier_approve_clean, match_inquiry and
--      capability_enrich. Giving a UX designer the ability to approve a supplier, to satisfy a
--      count, would be a worse outcome than a red check — it is the exact shape of the silent
--      over-grant this estate has been bitten by before.
--
-- So four rules stay red against one role, deliberately, and they are recorded in
-- docs/phase-a/PHASE_A_UNRESOLVED_DECISIONS.md as the Phase B activation dependency. The role is
-- inert in the meantime: it owns no workflow, no route invokes it, no cron runs it, and with
-- model_policy null it cannot make a paid call even if something did.
--
-- Assert exactly that, so "inert" is measured and not asserted by comment.
do $$
declare v int; v_rules text;
begin
  select count(*) into v from public.org_tasks t
   where t.status in ('assigned','in_progress') and t.assigned_agent is not null
     and not exists (select 1 from public.org_agents a where a.agent_key=t.assigned_agent and a.active);
  if v <> 0 then raise exception 'FOLLOW-UP: % open task(s) are still assigned to somebody who cannot act', v; end if;

  select count(*) into v from public.org_role where role_id='product_ux_designer' and model_policy is not null;
  if v <> 0 then raise exception 'FOLLOW-UP: product_ux_designer has a model policy — Phase A must not route spend'; end if;

  select count(*) into v from public.org_workflow_ownership where accountable_role_id = 'product_ux_designer';
  if v <> 0 then raise exception 'FOLLOW-UP: product_ux_designer owns a workflow it is not yet activated for'; end if;

  select count(*) into v from public.workflow_step where actor_role = 'product_ux_designer';
  if v <> 0 then raise exception 'FOLLOW-UP: a workflow step already addresses product_ux_designer'; end if;

  -- and the remaining violations are the four expected ones, against that one role only.
  select string_agg(distinct rule, ', ' order by rule) into v_rules from public.fn_org_role_violations();
  if exists (select 1 from public.fn_org_role_violations() where role_id <> 'product_ux_designer')
    then raise exception 'FOLLOW-UP: canonical-rule violations exist outside product_ux_designer: %', v_rules; end if;
  raise notice 'PHASE A FOLLOW-UP: orphaned work reassigned; remaining violations (%) are the Phase B activation of product_ux_designer only.', v_rules;
end $$;
