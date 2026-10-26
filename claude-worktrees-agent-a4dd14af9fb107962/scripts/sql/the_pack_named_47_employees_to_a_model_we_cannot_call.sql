-- THE 96 model_policy_by_identity ROWS, RESOLVED - AND THE BRIEF'S PLAN WOULD HAVE BROKEN ROUTING.
--
-- Decision carried in from the session brief: "the policy moves onto org_agents as a routing_tier
-- seeded from the pack's four-role taxonomy, sequenced after 1-4." §1-4 are done, so this is it.
-- Re-measured first, and TWO things had changed since that decision was written.
--
-- 1. THE 24 current_agent ROWS ARE ALREADY WIRED. fn_ai_route reads model_policy_by_identity today
--    - an earlier session added the branch, complete with a note that its first version was
--    unreachable. So the question is only about the 96 target_employee rows.
--
-- 2. THE PACK NAMES MODELS THIS COMPANY CANNOT CALL. This is the finding that changes the plan.
--    Measured against model_registry where active and approved:
--
--      pack model                        in model_registry?   named by
--      deepseek/deepseek-v4-flash        NO                   47 of 96 rows
--      google/gemini-3.5-flash-lite      NO
--      google/gemini-3.6-flash           NO
--      qwen/qwen3.7-flash                NO
--      anthropic/claude-sonnet-5:batch   NO
--      qwen/qwen3.7-plus                 yes (small, 0.32)
--      anthropic/claude-sonnet-5         yes (large, 2.00)
--
--    Five of the pack's seven models do not exist in this company's registry. Honouring the rows
--    as written would have pointed 47 employees at deepseek-v4-flash, and fn_ai_route would have
--    silently substituted a different model on every one of those calls while the config claimed
--    otherwise. That is a decorative setting - the exact defect this codebase keeps producing.
--
-- SO THE TIER IS STORED, NOT THE MODEL. org_agents.routing_tier carries the pack's four-role
-- taxonomy, which is the durable part of its judgement, and fn_ai_route resolves tier -> registry
-- tier -> cheapest active approved model AT CALL TIME. When the fleet changes, routing follows it.
-- Nothing has to be rewritten, and no model ID is stored anywhere it can go stale.
--
-- WHAT IT COSTS, measured rather than assumed. The generic fallback today is general_drafting =
-- ~anthropic/claude-haiku-latest, medium, 1.00 USD/Mtok in. Against that:
--
--   operations_specialist -> small  (gemini-3.1-flash-lite 0.25)   4x CHEAPER
--   analyst_controller    -> medium (haiku 1.00)                   unchanged
--   director              -> medium (haiku 1.00)                   unchanged
--   reviewer_auditor      -> large  (claude-sonnet-5 2.00)         2x DEARER, DELIBERATELY
--
-- The reviewer upgrade is not an oversight. All 24 Reviewer/Auditor rows in the pack name
-- sonnet-5 and all 24 carry authority 'advisory', and a reviewer running on the cheap model is the
-- "green check that means nothing" defect expressed in model choice. Specialists outnumber
-- reviewers heavily in this org, so the net direction is down.
--
-- SCOPE, STATED. This only fires where routing would otherwise fall to the GENERIC default - an
-- unmapped calling function, or a task_class with no policy. Any task_class with a real policy
-- still wins, exactly as the pack's own rows say: "Role default only; task_class routing overrides
-- it." No existing well-routed call changes model.

alter table public.org_agents
  add column if not exists routing_tier text;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'org_agents_routing_tier_check') then
    alter table public.org_agents add constraint org_agents_routing_tier_check
      check (routing_tier is null or routing_tier in
             ('director','analyst_controller','operations_specialist','reviewer_auditor'));
  end if;
end $$;

comment on column public.org_agents.routing_tier is
  'The pack v2026.07.31 four-role taxonomy (Director / Analyst-Controller / Operations Specialist / Reviewer-Auditor), applied to a real employee. fn_ai_route resolves it to a registry tier and then to the cheapest active approved model AT CALL TIME - the TIER is stored, never a model id, so routing follows the fleet instead of going stale. Added 11 Aug 2026 after measuring that 5 of the 7 models named by model_policy_by_identity are absent from model_registry.';

-- SEEDED BY RULE, title first and seniority second. Reviewer/auditor is tested FIRST because a
-- Quality Assurance Manager is a reviewer before it is a manager, and getting that backwards would
-- put the company's checkers on the cheap model.
update public.org_agents set routing_tier = case
    when title ~* 'review|audit|quality|assurance|compliance|risk|governance|guardrail|validator|moderation|verification|fraud|trust'
      then 'reviewer_auditor'
    when seniority in ('executive','chief','director','lead')
      or title ~* 'director|head of|chief|officer|^ceo|^cto|^cfo|counsel'
      then 'director'
    when title ~* 'analyst|controller|engineer|architect|scientist|strategist|designer|forecast'
      or seniority = 'senior'
      then 'analyst_controller'
    when seniority = 'manager'
      then 'director'
    else 'operations_specialist' end
 where active and routing_tier is null;

-- ---------------------------------------------------------------------------------------------
-- THE RESOLVER. Its own function so the mapping is testable without invoking the whole router,
-- and so fn_ai_route gains eight lines rather than a new block of logic.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_routing_tier_model(p_agent_key text)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  select case when a.routing_tier is null then null else jsonb_build_object(
      'routing_tier', a.routing_tier,
      'registry_tier', t.rt,
      'model', (select r.model_id from model_registry r
                 where r.active and r.approved and r.tier = t.rt
                 order by r.in_per_mtok_usd limit 1)) end
    from org_agents a
    cross join lateral (select case a.routing_tier
                                 when 'reviewer_auditor'      then 'large'
                                 when 'operations_specialist' then 'small'
                                 else 'medium' end as rt) t
   where a.agent_key = p_agent_key and coalesce(a.active, true)
   limit 1;
$function$;

revoke all on function public.fn_routing_tier_model(text) from public;
revoke all on function public.fn_routing_tier_model(text) from anon;
