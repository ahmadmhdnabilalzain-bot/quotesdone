-- REORGANISING THE AGENT COMPANY - 23: the sql-language half of "resolve before compare".
--
-- org_reorg_21 fixed the plpgsql routines by assigning the resolved key back to the parameter as
-- the first statement. A LANGUAGE sql body has no statements to assign in, so the parameter is
-- wrapped where it is used instead. Three routines, one comparison site each, no behaviour change
-- for a caller that already passes a canonical key because coalesce returns it unchanged.
--
-- WHY THESE THREE MATTER, and the middle one is the expensive one:
--
--   fn_routing_tier_model   selects the PAID TIER from org_agents.routing_tier. It matched
--                           agent_key exactly, so every one of the ten department heads - all of
--                           which are normally addressed by an alias or a job title - resolved to
--                           no row, returned null, and the caller could not pick the cheaper tier.
--                           A routing function that silently answers "no opinion" for the ten most
--                           senior employees is a cost defect wearing a null.
--   fn_ai_confidence_prior  feeds the confidence prior that can downgrade a call one tier. Keyed on
--                           agent_key against ai_cost_log, which is heavily alias-contaminated, so
--                           the n >= 5 and stddev > 0 guards were being starved and the prior
--                           almost never existed.
--   fn_employee_kpi_trend   KPI attribution for an employee addressed under any other name showed
--                           an empty trend - not an error, an empty result, which reads as
--                           "this employee has no measured KPIs".
--
-- Bodies are the live staging definitions with only the wrap applied, generated not retyped.

begin;

-- fn_ai_confidence_prior
CREATE OR REPLACE FUNCTION public.fn_ai_confidence_prior(p_agent_key text, p_task_class text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- A CONSTANT IS NOT A MEASUREMENT, AND THIS IS THE GUARD THAT SAYS SO.
  -- The founder's own reading of the two existing emitters: "always emit exactly 1.000, which
  -- carries no information". A model that reports the same number every time would otherwise
  -- downgrade itself to a cheaper tier on the strength of its own unvarying optimism. stddev = 0
  -- over the window means the signal has no content, so it does not route anything. n >= 5 for the
  -- same reason at the other end: one confident answer is an anecdote.
  select case
           when count(*) >= 5 and coalesce(stddev_samp(confidence), 0) > 0
           then jsonb_build_object(
                  'prior', round(percentile_cont(0.5) within group (order by confidence)::numeric, 4),
                  'n', count(*),
                  'spread', round(stddev_samp(confidence)::numeric, 4))
           else null
         end
    from public.ai_cost_log
   where agent_key = coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key)
     and task_class = p_task_class
     and confidence is not null
     and occurred_at > now() - interval '14 days';
$function$
;

-- fn_employee_kpi_trend
-- ROUTINE REMOVED 7 September 2026. public.fn_employee_kpi_trend was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- fn_routing_tier_model
CREATE OR REPLACE FUNCTION public.fn_routing_tier_model(p_agent_key text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
   where a.agent_key = coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key)
     and coalesce(a.active, true)
   limit 1;
$function$
;

commit;
