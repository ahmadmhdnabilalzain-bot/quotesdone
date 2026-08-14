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
CREATE OR REPLACE FUNCTION public.fn_employee_kpi_trend(p_agent_key text, p_days integer DEFAULT 90)
 RETURNS TABLE(kpi text, unit text, observations bigint, first_value numeric, latest_value numeric, direction text, latest_verdict text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with h as (
    select k.kpi, h.kpi_id, h.actual_value, h.unit, h.verdict, h.measured_on,
           first_value(h.actual_value) over w_asc  as first_v,
           first_value(h.actual_value) over w_desc as latest_v,
           first_value(h.verdict)      over w_desc as latest_verdict,
           row_number()                over w_desc as rn,
           count(*)                    over (partition by h.kpi_id) as n
      from employee_kpi_history h
      join employee_kpi k on k.id = h.kpi_id
     where h.agent_key = coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key)
       and h.measured_on > (now() at time zone 'utc')::date - p_days
       and h.actual_value is not null
    window w_asc  as (partition by h.kpi_id order by h.measured_on),
           w_desc as (partition by h.kpi_id order by h.measured_on desc)
  )
  select kpi, unit, n,
         first_v, latest_v,
         case when n < 2 or first_v is null or latest_v is null then 'no trend yet'
              when latest_v = first_v then 'flat'
              when (unit = 'percent_max') = (latest_v < first_v) then 'improving'
              else 'worsening' end,
         latest_verdict
    from h where rn = 1
   order by kpi;
$function$
;

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
