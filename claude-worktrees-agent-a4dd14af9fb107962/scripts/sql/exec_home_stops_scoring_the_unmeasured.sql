CREATE OR REPLACE FUNCTION public.fn_ws_exec_home()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with h as (select to_jsonb(public.fn_health_index()) j),
  gh as (
    select coalesce(
      (select 'monthly' where exists (select 1 from public.goal_period where horizon = 'monthly')),
      (select 'quarterly' where exists (select 1 from public.goal_period where horizon = 'quarterly')),
      'annual') hz
  ),
  g as (
    -- THE FOUNDER WAS BEING SHOWN 98% GOAL PROGRESS ON A DAY WITH AED 0 REVENUE AND 0 CUSTOMERS.
    --
    -- This CTE reimplemented fn_goal_attainment and got it wrong four ways:
    --   1. least(100.0, NULL) returns 100.0 in Postgres - least() ignores nulls. 115 of the 122
    --      goal_period rows carry a target and NO actual_value, so every unmeasured goal scored a
    --      perfect 100 and pulled the average UP. Measured on the same rows: 98.0 published,
    --      65.3 honest. For the current period alone: 50.0 from 2 measured of 61.
    --   2. It ignored company_goals.direction, scoring an 'at_most' goal as if it were 'at_least',
    --      so a cost goal that overshot still read as progress.
    --   3. It averaged every period_label of the horizon together - two months at once.
    --   4. count(*) was published as 'goal_count', so 122 goal_period ROWS read as 122 goals.
    --
    -- fn_goal_attainment already handles all four, and its own comment
    -- ("NOT least(100, ...): least() ignores nulls, so an unmeasured goal scored 100%") exists
    -- because this exact bug was found and fixed THERE and not HERE. One copy, not two.
    select (a.j->>'pct')::numeric        pct,
           (a.j->>'goals_total')::int    n,
           (a.j->>'goals_measured')::int measured
      from gh, lateral (select public.fn_goal_attainment(gh.hz) j) a
  ),
  bott as (
    select coalesce(jsonb_agg(jsonb_build_object(
             'department', r.owner_dept, 'resource', r.resource, 'used_pct', r.used_pct,
             'state', r.state, 'committed', r.committed, 'capacity', r.capacity, 'unit', r.unit)
           order by r.used_pct desc nulls last), '[]'::jsonb) j
      from public.v_resource_pressure r where r.state in ('HALT', 'DEGRADE')
  ),
  dept as (
    select coalesce(jsonb_agg(jsonb_build_object(
             'department', coalesce(dh.department, e->>'label', e->>'key'),
             'dept_key', e->>'key',
             'runs', (e->'runs'),
             'busy', coalesce((e->>'runs')::int, 0) > 0,
             'health', dh.score, 'status', dh.status)
           order by coalesce((e->>'runs')::int, 0) desc), '[]'::jsonb) j
      from jsonb_array_elements(public.fn_agents_board()->'departments') e
      left join public.v_department_health dh on dh.dept_key = e->>'key'
  )
  select jsonb_build_object(
    'health_index',     (select (j->>'index')::numeric from h),
    'mood',             (select j->>'band' from h),
    'health_note',      (select j->>'note' from h),
    'revenue_today',    (select coalesce(sum(coalesce(reveal_fee, app_fee, 0)), 0)
                           from public.transactions where revealed_at::date = current_date),
    'revenue_30d',      (select coalesce(sum(coalesce(reveal_fee, app_fee, 0)), 0)
                           from public.transactions where revealed_at > now() - interval '30 days'),
    'goal_progress_pct', (select pct from g),
    'goal_horizon',     (select hz from gh),
    'goal_count',       (select n from g),
    -- THE RULE THIS SESSION ADOPTED: no surface publishes a percentage without the coverage it
    -- rests on. "50%" and "50% across 2 measured goals of 61" are different facts, and only the
    -- second one is safe to act on. The reader decides what to render; it can no longer be
    -- unaware of the denominator.
    'goal_measured',    (select measured from g),
    'customers_active', (select count(*) from public.customers where coalesce(banned, false) = false),
    'suppliers_active', coalesce((public.fn_marketplace_analytics()->>'active_suppliers_30d')::int, 0),
    'employees',        (select count(*) from public.org_agents where active),
    -- COUNTED CRON JOBS AND CALLED THEM EMPLOYEES (10 Aug 2026).
    -- This was count(distinct agent) from agent_runs with NO JOIN TO org_agents, and agent_runs is
    -- the cron and job log: 111 distinct agent values over 30 days, only NINE of them employee keys.
    -- An employee works in three places and agent_runs is the one they use least: agent_memory
    -- (a recorded thought), agent_chats (a reasoning turn), agent_runs (a run). Any of the three
    -- counts, and the count is over org_agents so a cron can never be mistaken for a colleague.
    'employees_working', (select count(*) from public.org_agents o where o.active and (
                             exists (select 1 from public.agent_runs r
                                      where r.agent = o.agent_key and r.started_at > now() - interval '24 hours')
                          or exists (select 1 from public.agent_memory m
                                      where m.agent_key = o.agent_key and m.created_at > now() - interval '24 hours')
                          or exists (select 1 from public.agent_chats c
                                      where c.agent_key = o.agent_key and c.created_at > now() - interval '24 hours'))),
    'bottlenecks',      (select j from bott),
    'departments',      (select j from dept),
    'workflow_runs_24h', (select count(*) from public.workflow_run
                           where coalesce(started_at, created_at) > now() - interval '24 hours'),
    'handoffs_24h', (select count(*) from public.event_delivery
                      where delivered_at > now() - interval '24 hours'),
    'knowledge_revisions_7d', (select count(*) from public.kb_revisions
                                where created_at > now() - interval '7 days'),
    'uptime_pct_24h', (select round(100.0 * count(*) filter (where verdict = 'ALIVE')
                                    / nullif(count(*), 0), 1)
                         from public.edge_health_probe where checked_at > now() - interval '24 hours'),
    -- THE WORKING COMPANY. Added 10 Aug 2026 because seven of the nine business tiles can only be
    -- non-zero once the marketplace transacts, and meanwhile the founder was shown nothing of the
    -- 20,470 leads, 18,000+ runs and 800+ events that already exist.
    'leads_total',      (select count(*) from public.leads),
    'agent_runs_24h',   (select count(*) from public.agent_runs where started_at > now() - interval '24 hours'),
    'events_24h',       (select count(*) from public.company_event where occurred_at > now() - interval '24 hours'),
    'decisions_open',   (select count(*) from public.agent_actions where status in ('pending','needs_review')),
    'tasks_open',       (select count(*) from public.org_tasks where status not in ('done','cancelled')),
    'generated_at',     now()
  );
$function$;

-- ---------------------------------------------------------------------------------------------
-- fn_health_index: SIX DEMO FIXTURES WERE BEING COUNTED AS APPROVED SUPPLIERS.
--
-- approved_suppliers counted `claimed = true`, and all six claimed leads are the 7-8 Aug demo
-- fixtures - "ZZ DEMO - <name> (QuotesDone fixture, not a real company)" on @example.invalid
-- addresses, every one still approval_status = 'pending'. Real approved suppliers is ZERO.
--
-- The harm is not the count itself, it is what the count switches. The supplier_activity component
-- reads:
--     case when approved_suppliers = 0 and quotes_7d = 0 then null else least(100, quotes_7d*5) end
-- so six fake suppliers turned a genuine "not measured" into a measured 0.0, and that 0.0 was then
-- averaged into the company health index and named in the founder-facing note as a cause:
-- "driven by customer acquisition at 0.0 and supplier activity at 0.0".
--
-- Excluding them makes supplier_activity null again, which REMOVES it from the average, so the
-- index RISES (49.4 -> higher) on a company with no suppliers. That is the correct direction and
-- the uncomfortable one: the honest reading is "we have not measured supplier activity", not "we
-- measured it and it is zero". The index is now the mean of one fewer, more truthful, component
-- and components_present drops by one to say so.
--
-- Only this one statement changed from the previous definition.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_health_index()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  s_acq numeric; s_supp numeric; s_rfq numeric; s_qual numeric;
  s_resp numeric; s_disp numeric; s_up numeric;
  signups_7d int; quotes_7d int; approved_suppliers int;
  inq_total int; inq_done int; avg_qual numeric; avg_resp numeric;
  blocked_30d int; msgs_30d int; up_ok int; up_tot int;
  parts numeric[]; overall numeric; band text; present int;
begin
  select count(*) into signups_7d from customers where created_at > now()-interval '7 days';
  select count(*) into quotes_7d  from quotes    where created_at > now()-interval '7 days';
  -- DEMO FIXTURES EXCLUDED. The marker is in the data, not the schema: the convention seeded on
  -- 7-8 Aug 2026 is 'ZZ DEMO ' in company_name and an @example.invalid address. Both are checked
  -- because either alone would let a half-formed fixture through.
  select count(*) into approved_suppliers from leads
     where (coalesce(approval_status,'')='approved' or claimed=true)
       and coalesce(company_name,'') not like 'ZZ DEMO%'
       and coalesce(email,'') not like '%@example.invalid';
  -- RFQ completion: real RFQs only (exclude split-parent containers and customer-cancelled),
  -- success = completed/won or closed-with-a-hire (a "closed, not hired" is NOT a completion).
  select count(*) filter (where created_at > now()-interval '90 days'
                            and coalesce(status,'')<>'split' and coalesce(category,'')<>'combined'
                            and coalesce(status,'')<>'cancelled'),
         count(*) filter (where created_at > now()-interval '90 days'
                            and coalesce(status,'')<>'split' and coalesce(category,'')<>'combined'
                            and (status in ('completed','won')
                                 or (status='closed' and coalesce(outcome,'') in ('hired','hired_elsewhere'))))
    into inq_total, inq_done from inquiries;
  select avg(nullif(quality->>'score','')::numeric) into avg_qual
    from quotes where quality is not null and created_at > now()-interval '90 days';
  select avg(nullif(rv_response_rate,0)) into avg_resp
    from leads where coalesce(rv_reveals,0) > 0;
  select count(*) filter (where coalesce(blocked,false)),
         count(*) into blocked_30d, msgs_30d
    from messages where created_at > now()-interval '30 days';
  select count(*) filter (where ok), count(*) into up_ok, up_tot
    from health_checks where created_at > now()-interval '24 hours';

  s_acq  := least(100, signups_7d * 10.0);
  s_supp := case when approved_suppliers=0 and quotes_7d=0 then null
                 else least(100, quotes_7d * 5.0) end;
  s_rfq  := case when inq_total=0 then null else round(inq_done::numeric/inq_total*100,1) end;
  s_qual := avg_qual;
  s_resp := case when avg_resp is null then null
                 when avg_resp <= 1 then round(avg_resp*100,1) else round(avg_resp,1) end;
  s_disp := case when msgs_30d=0 then null
                 else greatest(0, 100 - least(100, blocked_30d*5.0)) end;
  s_up   := case when up_tot=0 then null else round(up_ok::numeric/up_tot*100,1) end;

  parts := array_remove(array[s_acq,s_supp,s_rfq,s_qual,s_resp,s_disp,s_up], null);
  present := coalesce(array_length(parts,1),0);
  overall := case when present=0 then null else round((select avg(x) from unnest(parts) x),1) end;
  band := case when overall is null then 'no data'
               when overall >= 75 then 'healthy'
               when overall >= 50 then 'watch'
               else 'attention' end;

  return jsonb_build_object(
    'index', overall, 'band', band, 'components_present', present,
    -- A PROSE INSIGHT WITH A CAUSE AND A MAGNITUDE, not a blank.
    -- `overall` is the mean of the present components, so the ones furthest below it are
    -- arithmetically what hold the index there. "driven by" is division, not narrative.
    'note', case
      when present < 3 then 'insufficient data - pre-traction; index will firm up with volume'
      else (select 'Company health is '||overall||' of 100 ('||band||'), driven by '
              ||string_agg(w.label||' at '||w.score, ' and ' order by w.score, w.label)
              ||' - the two furthest below the '||overall||'-point average of '||present
              ||' measured components.'
              from (select v.label, v.score from (values
                      ('customer acquisition', s_acq), ('supplier activity', s_supp),
                      ('RFQ completion', s_rfq), ('quote quality', s_qual),
                      ('response time', s_resp), ('dispute health', s_disp), ('uptime', s_up)
                    ) v(label, score)
                     where v.score is not null order by v.score, v.label limit 2) w)
      end,
    'components', jsonb_build_object(
       'customer_acquisition', s_acq, 'supplier_activity', s_supp, 'rfq_completion', s_rfq,
       'quote_quality', s_qual, 'response_time', s_resp, 'dispute_health', s_disp,
       'uptime', s_up, 'revenue', null),
    'raw', jsonb_build_object(
       'signups_7d', signups_7d, 'quotes_7d', quotes_7d, 'approved_suppliers', approved_suppliers,
       'inquiries_eligible_90d', inq_total, 'completed_90d', inq_done,
       'blocked_msgs_30d', blocked_30d, 'uptime_ok', up_ok, 'uptime_checks', up_tot),
    'computed_at', now());
end $function$;
