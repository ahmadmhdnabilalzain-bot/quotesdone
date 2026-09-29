-- A KPI VIEW NEVER COUNTS A DEMO PARTY.
-- Seat: it_engineer. 28 Sep 2026. Deep audit 28 Sep, runtime/data finding 6.
--
-- MEASURED (production htdblwldjkcgjvmqkbeh, read-only, 28 Sep 2026): eight views that read leads,
-- customers, inquiries or quotes had no demo exclusion - ops_kpis, category_price_stats, crm_deal_kpis,
-- customer_kpis, legal_kpis, strategy_kpis, project_summary, marketing_kpis. At the time every inquiry
-- (3/3), quote (3/3) and transaction (1/1) belonged to a demo party, so these KPIs counted only
-- ZZ DEMO activity and presented it as the company's.
--
-- WHAT THIS CHANGES: each direct read of those tables inside the seven aggregate views now skips demo
-- rows, using the estate's existing markers and nothing new:
--   * an inquiry  -> public.fn_inquiry_is_demo(id)   (customer is_demo, qd_run provenance, demo fixture)
--   * a customer  -> customers.is_demo
--   * a supplier  -> leads.is_demo
-- Column lists, names and types are unchanged; crm_deal_kpis keeps security_invoker=on.
--
-- WHAT IT DOES NOT CHANGE, deliberately:
--   * project_summary. It is not a KPI: it is one row per project, read by project_api only for the
--     signed-in customer's own projects (project_api/index.ts). A demo customer rehearsing in the
--     sandbox must still see its own ZZ DEMO project, and a real customer can never see a demo one
--     (the rows are keyed by customer_id, and fn_demo_and_real_never_pair keeps the two apart).
--     Filtering it would break the rehearsal and exclude nothing from any company figure.
--
-- THE ROUTINES AND THE VIEW BEHIND THOSE VIEWS (added the same day, coordinator's instruction):
--   * fn_ops_metrics (ops_kpis) - its no-quote backlog and matched-not-quoted counts skip demo inquiries.
--   * funnel_metrics (marketing_kpis) - every stage of the funnel, and reveal fees, skip demo inquiries.
--   * fn_strategy_metrics (strategy_kpis) - demand and active suppliers per category skip demo inquiries
--     and demo suppliers.
--   * finance_kpis (strategy_kpis) - receivables skip a due whose transaction, supplier or customer is a
--     demo identity (fn_gl_fixture_or_orphan, the ledger's own fixture test). The GL figures (cash,
--     revenue, expense) are the books and are NOT filtered here: measured 28 Sep, 0 posted journals are
--     linked to a demo transaction, and a fixture reaching the ledger is fn_gl_fixture_or_orphan's job
--     at posting time, not a report's to hide.
--   Bodies are the live definitions of 28 Sep with only the demo test added; signatures, volatility,
--   security and search_path are unchanged, so CREATE OR REPLACE keeps each routine's ACL.
--   * fn_marketplace_analytics (read by fn_ops_metrics, fn_strategy_metrics and the exec-home boards) -
--     every inquiry, quote and match it counts skips demo inquiries, and quotes also skip demo suppliers.
--     Its readers get the same keys and types; only demo rows leave the counts.
--
-- Prevented by: scripts/checks/a_kpi_view_never_counts_a_demo_party.test.mjs (fails if any of the seven
-- views loses its demo exclusion). Verdict row at the end reads the live views back.

create or replace view public.category_price_stats as
 select i.category,
    count(qq.quote_amount) as n,
    round(percentile_cont(0.5::double precision) within group (order by (qq.quote_amount::double precision))::numeric, 0) as median,
    round(percentile_cont(0.25::double precision) within group (order by (qq.quote_amount::double precision))::numeric, 0) as p25,
    round(percentile_cont(0.75::double precision) within group (order by (qq.quote_amount::double precision))::numeric, 0) as p75,
    round(avg(qq.quote_amount), 0) as mean,
    round(coalesce(stddev_pop(qq.quote_amount), 0::numeric), 0) as sd
   from quotes qq
     join inquiries i on i.id = qq.inquiry_id
  where qq.quote_amount is not null and qq.quote_amount > 0::numeric and i.category is not null
    and not public.fn_inquiry_is_demo(i.id)
  group by i.category;

create or replace view public.crm_deal_kpis with (security_invoker = on) as
 select (( select count(*) as count
           from inquiries i
             join crm_stages s on s.key = i.pipeline_stage
          where not s.is_won and not s.is_lost and not public.fn_inquiry_is_demo(i.id)))::integer as open_deals,
    (( select count(*) as count
           from inquiries i
             join crm_stages s on s.key = i.pipeline_stage
          where s.is_won and not public.fn_inquiry_is_demo(i.id)))::integer as won_deals,
    (( select count(*) as count
           from inquiries i
             join crm_stages s on s.key = i.pipeline_stage
          where s.is_lost and not public.fn_inquiry_is_demo(i.id)))::integer as lost_deals,
    ( select round(avg(extract(epoch from coalesce(i.completed_at, now()) - i.created_at) / 86400.0), 1) as round
           from inquiries i
             join crm_stages s on s.key = i.pipeline_stage
          where s.is_won and not public.fn_inquiry_is_demo(i.id)) as avg_cycle_days,
    ( select round(coalesce(sum(i.expected_value * s.probability::numeric / 100.0), 0::numeric), 2) as round
           from inquiries i
             join crm_stages s on s.key = i.pipeline_stage
          where not s.is_won and not s.is_lost and not public.fn_inquiry_is_demo(i.id)) as weighted_forecast,
    (( select count(*) as count
           from crm_activities
          where crm_activities.done = false and crm_activities.due_at is not null and crm_activities.due_at < now()))::integer as overdue_activities;

create or replace view public.customer_kpis as
 select count(*) as customers,
    round(avg(h.health), 1) as avg_health,
    round(avg(h.satisfaction), 1) as avg_satisfaction,
    round(avg(h.avg_resp_hrs) filter (where h.avg_resp_hrs is not null), 1) as avg_response_hrs,
    round(100.0 * count(*) filter (where h.progress >= 60::numeric)::numeric / nullif(count(*), 0)::numeric, 1) as pct_progressing,
    count(*) filter (where h.disputes > 0) as open_disputes,
    count(*) filter (where h.stalled_inq > 0) as with_stalled,
    count(*) filter (where h.dormant) as dormant_count,
    count(*) filter (where h.risk_tier = 'high'::text) as risk_high,
    count(*) filter (where h.risk_tier = 'medium'::text) as risk_medium,
    count(*) filter (where h.risk_tier = 'low'::text) as risk_low
   from customer_health h
  where not exists (select 1 from customers c where c.id = h.customer_id and c.is_demo);

create or replace view public.legal_kpis as
 select ( select count(*) as count
           from legal_documents) as policies_published,
    ( select count(*) as count
           from legal_documents
          where legal_documents.updated_at < (now() - '365 days'::interval)) as policies_stale,
    ( select count(*) as count
           from legal_checklist) as required_total,
    ( select count(*) as count
           from legal_checklist
          where legal_checklist.present) as required_present,
    ( select count(*) as count
           from legal_checklist
          where not legal_checklist.present) as required_missing,
    ( select count(*) as count
           from legal_checklist
          where not legal_checklist.present and legal_checklist.priority = 1) as critical_missing,
    round(100.0 * (( select count(*) as count
           from legal_checklist
          where legal_checklist.present))::numeric / nullif(( select count(*) as count
           from legal_checklist), 0)::numeric, 1) as coverage_pct,
    ( select count(*) as count
           from customers
          where not coalesce(customers.is_demo, false)) as customers,
    round(100.0 * (( select count(*) as count
           from customers
          where customers.tos_accepted_at is not null and not coalesce(customers.is_demo, false)))::numeric / nullif(( select count(*) as count
           from customers
          where not coalesce(customers.is_demo, false)), 0)::numeric, 1) as customer_terms_acceptance_pct,
    ( select count(*) as count
           from leads
          where leads.approval_status = 'approved'::text and not coalesce(leads.is_demo, false)) as suppliers_approved,
    round(100.0 * (( select count(*) as count
           from leads
          where leads.approval_status = 'approved'::text and leads.accepted_terms_at is not null and not coalesce(leads.is_demo, false)))::numeric / nullif(( select count(*) as count
           from leads
          where leads.approval_status = 'approved'::text and not coalesce(leads.is_demo, false)), 0)::numeric, 1) as supplier_terms_acceptance_pct,
    ( select count(*) as count
           from agent_actions
          where agent_actions.kind = 'legal_flag'::text and (agent_actions.status = any (array['pending'::text, 'needs_review'::text]))) as open_legal_flags,
    ( select count(*) as count
           from legal_reviews
          where legal_reviews.risk_level = 'high'::text and legal_reviews.needs_licensed_review) as high_risk_reviews;

create or replace view public.marketing_kpis as
 with f as (
         select funnel_metrics(30) as fm
        ), mi as (
         select coalesce(sum(meta_insights.spend), 0::numeric) as meta_spend,
            coalesce(sum(meta_insights.impressions), 0::numeric) as meta_impr,
            coalesce(sum(meta_insights.clicks), 0::numeric) as meta_clicks,
            coalesce(sum(meta_insights.results), 0::numeric) as meta_results,
            count(*) filter (where meta_insights.effective_status = 'ACTIVE'::text) as meta_active
           from meta_insights
          where meta_insights.time_window = 'last_30d'::text and meta_insights.campaign_name ~~* '%quotesdone%'::text
        ), nc as (
         select count(*) as n
           from customers
          where customers.created_at >= (now() - '30 days'::interval) and not coalesce(customers.is_demo, false)
        )
 select (f.fm ->> 'inquiries'::text)::integer as inquiries_30d,
    (f.fm ->> 'matched'::text)::integer as matched_30d,
    (f.fm ->> 'quoted'::text)::integer as quoted_30d,
    (f.fm ->> 'revealed'::text)::integer as revealed_30d,
    (f.fm ->> 'reveal_fees'::text)::numeric as revenue_30d,
        case
            when ((f.fm ->> 'inquiries'::text)::integer) > 0 then round(100.0 * ((f.fm ->> 'quoted'::text)::integer)::numeric / ((f.fm ->> 'inquiries'::text)::integer)::numeric, 1)
            else null::numeric
        end as inq_to_quote_pct,
        case
            when ((f.fm ->> 'quoted'::text)::integer) > 0 then round(100.0 * ((f.fm ->> 'revealed'::text)::integer)::numeric / ((f.fm ->> 'quoted'::text)::integer)::numeric, 1)
            else null::numeric
        end as quote_to_reveal_pct,
    ( select count(*) as count from blog_posts where blog_posts.published) as blog_published,
    ( select count(*) as count from blog_posts) as blog_total,
    ( select count(*) as count
           from content_drafts
          where coalesce(content_drafts.status, ''::text) <> all (array['published'::text, 'discarded'::text])) as drafts_pending,
    ( select count(*) as count
           from social_posts
          where (coalesce(social_posts.status, ''::text) = any (array['staged'::text, 'scheduled'::text, 'draft'::text, 'pending'::text])) or social_posts.mode = 'draft'::text and (coalesce(social_posts.status, ''::text) = any (array['published'::text, 'sent'::text]))) as social_staged,
    ( select count(*) as count
           from social_posts
          where social_posts.mode = 'now'::text and (coalesce(social_posts.status, ''::text) = any (array['published'::text, 'sent'::text]))) as social_published,
    ( select count(*) as count from seo_categories) as seo_pages,
    ( select count(*) as count from seo_categories where seo_categories.generated) as seo_generated,
    ( select count(*) as count from leads where not coalesce(leads.is_demo, false)) as leads_total,
    ( select count(*) as count from outreach) as outreach_sent,
    ( select coalesce(gl_account_balances.balance, 0::numeric) as "coalesce"
           from gl_account_balances
          where gl_account_balances.code = '6200'::text) as mkt_spend,
    nc.n as new_customers_30d,
        case
            when mi.meta_spend > 0::numeric then round(mi.meta_spend / nullif(nc.n, 0)::numeric, 2)
            else null::numeric
        end as cac,
        case
            when mi.meta_spend > 0::numeric then round(((f.fm ->> 'reveal_fees'::text)::numeric) / mi.meta_spend, 2)
            when (( select coalesce(gl_account_balances.balance, 0::numeric) as "coalesce"
               from gl_account_balances
              where gl_account_balances.code = '6200'::text)) > 0::numeric then round(((f.fm ->> 'reveal_fees'::text)::numeric) / (( select coalesce(gl_account_balances.balance, 0::numeric) as "coalesce"
               from gl_account_balances
              where gl_account_balances.code = '6200'::text)), 2)
            else null::numeric
        end as roi,
    ( select count(*) as count
           from marketing_category_demand
          where marketing_category_demand.inquiries_90d > 0 and marketing_category_demand.suppliers = 0) as supply_gaps,
    ( select count(*) as count
           from marketing_category_demand
          where not marketing_category_demand.has_seo_page) as seo_gaps,
    mi.meta_spend as meta_spend_30d,
    mi.meta_impr as meta_impressions_30d,
    mi.meta_clicks as meta_clicks_30d,
    mi.meta_results as meta_results_30d,
    mi.meta_active as meta_active_campaigns,
        case
            when mi.meta_results > 0::numeric then round(mi.meta_spend / mi.meta_results, 2)
            else null::numeric
        end as meta_cpl,
        case
            when mi.meta_spend > 0::numeric then round(((f.fm ->> 'reveal_fees'::text)::numeric) / mi.meta_spend, 2)
            else null::numeric
        end as meta_roi
   from f, mi, nc;

create or replace view public.ops_kpis as
 with m as (
         select fn_ops_metrics() as j
        )
 select (j ->> 'open_rfqs_no_quotes_7d'::text)::integer as no_quote_backlog,
    (j ->> 'matched_not_quoted'::text)::integer as matched_not_quoted,
    (j ->> 'avg_first_quote_hours'::text)::numeric as avg_first_quote_hours,
    (j ->> 'response_rate_pct'::text)::numeric as response_rate_pct,
    (j ->> 'overdue_activities'::text)::integer as overdue_activities,
    ( select count(*) as count
           from agent_actions
          where agent_actions.status = any (array['pending'::text, 'needs_review'::text])) as pending_approvals,
    ( select count(*) as count
           from agent_actions
          where (agent_actions.status = any (array['pending'::text, 'needs_review'::text])) and (coalesce(agent_actions.risk, ''::text) = any (array['high'::text, 'critical'::text]))) as high_risk_pending,
    ( select count(*) as count
           from crm_tasks
          where coalesce(crm_tasks.status, ''::text) <> 'done'::text) as open_tasks,
    ( select count(*) as count
           from crm_tasks
          where coalesce(crm_tasks.status, ''::text) <> 'done'::text and crm_tasks.due_date < now()) as overdue_tasks,
    ( select count(*) as count
           from inquiries
          where inquiries.status = 'quoted'::text and not public.fn_inquiry_is_demo(inquiries.id) and not (exists ( select 1
                   from transactions t
                  where t.inquiry_id = inquiries.id and t.revealed_at is not null))) as awaiting_reveal,
    ( select count(*) as count from cron.job) as cron_jobs,
    ( select count(*) as count
           from cron.job_run_details
          where job_run_details.status <> 'succeeded'::text and job_run_details.start_time >= (now() - '24:00:00'::interval)) as cron_failures_24h,
    ( select count(*) as count
           from agent_runs
          where (agent_runs.status = any (array['error'::text, 'failed'::text])) and agent_runs.started_at >= (now() - '24:00:00'::interval)) as agent_errors_24h,
    ( select count(*) as count
           from error_events
          where error_events.created_at >= (now() - '24:00:00'::interval)) as app_errors_24h,
    ( select count(*) as count
           from agent_actions
          where (agent_actions.kind = any (array['incident'::text, 'security_incident'::text])) and (agent_actions.status = any (array['pending'::text, 'needs_review'::text]))) as open_incidents
   from m;

create or replace view public.strategy_kpis as
 with sup as (
         select q.supplier_id,
            count(*) as c
           from quotes q
          where q.created_at > (now() - '90 days'::interval) and q.supplier_id is not null
            and not public.fn_inquiry_is_demo(q.inquiry_id)
            and not exists (select 1 from leads l where l.id = q.supplier_id and l.is_demo)
          group by q.supplier_id
        ), agg as (
         select count(*) as active,
            coalesce(round(100.0 * max(sup.c)::numeric / nullif(sum(sup.c), 0::numeric), 1), 0::numeric) as top_share
           from sup
        ), fin as (
         select finance_kpis.cash,
            finance_kpis.monthly_burn,
            finance_kpis.runway_months,
            finance_kpis.revenue_30d,
            finance_kpis.margin_pct
           from finance_kpis
        ), rk as (
         select count(*) filter (where strategy_risks.status = 'open'::text) as open_risks,
            max(strategy_risks.score) as top_score,
            (array_agg(strategy_risks.title order by strategy_risks.score desc))[1] as top_title
           from strategy_risks
          where strategy_risks.status = 'open'::text
        )
 select agg.active as active_suppliers_90d,
    agg.top_share as top_supplier_share_pct,
    jsonb_array_length(coalesce(fn_strategy_metrics() -> 'under_supplied'::text, '[]'::jsonb)) as under_supplied_categories,
    fin.cash,
    fin.monthly_burn,
        case
            when fin.cash > 0::numeric and fin.monthly_burn > 0::numeric then round(fin.cash / fin.monthly_burn, 1)
            else fin.runway_months
        end as runway_months,
    fin.revenue_30d,
    fin.margin_pct,
    coalesce(rk.open_risks, 0::bigint) as open_risks,
    coalesce(rk.top_score, 0) as top_risk_score,
    rk.top_title as top_risk,
    ( select count(*) as count
           from market_intel
          where market_intel.kind = 'competitor'::text and market_intel.status <> 'dismissed'::text) as competitor_intel,
    ( select count(*) as count
           from market_intel
          where market_intel.kind = 'trend'::text and market_intel.status <> 'dismissed'::text) as market_trends,
    ( select count(*) as count
           from market_intel
          where market_intel.status = 'open'::text) as open_intel,
    ( select max(simulations.created_at) as max
           from simulations) as last_simulation_at
   from agg, fin, rk;

create or replace function public.fn_marketplace_analytics()
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public', 'pg_temp'
as $function$
declare res jsonb;
begin
  with ri as (  -- real inquiries only
    select i.* from inquiries i where not public.fn_inquiry_is_demo(i.id)
  ),
  rq as (       -- real quotes: a real inquiry and a real supplier
    select q.* from quotes q join ri on ri.id = q.inquiry_id
     where not exists (select 1 from leads l where l.id = q.supplier_id and l.is_demo)
  ),
  q_first as (  -- first quote latency per rfq
    select i.id, min(qq.created_at) as first_quote_at, i.created_at, i.category
    from ri i left join rq qq on qq.inquiry_id = i.id group by i.id, i.created_at, i.category
  ),
  spread as (  -- savings potential per rfq with >=2 quotes
    select inquiry_id, min(quote_amount) lo, max(quote_amount) hi, count(*) n
    from rq where quote_amount > 0 group by inquiry_id having count(*) >= 2
  )
  select jsonb_build_object(
    'rfqs_today',   (select count(*) from ri where created_at >= date_trunc('day', now())),
    'rfqs_7d',      (select count(*) from ri where created_at >= now() - interval '7 days'),
    'rfqs_30d',     (select count(*) from ri where created_at >= now() - interval '30 days'),
    'avg_first_quote_hours', (select round(avg(extract(epoch from (first_quote_at - created_at))/3600.0)::numeric,1) from q_first where first_quote_at is not null),
    'response_rate_pct', (
      select case when count(*)>0 then round(100.0 * count(*) filter (where exists (
        select 1 from rq q where q.inquiry_id = m.inquiry_id and q.supplier_id = m.supplier_id)) / count(*), 1) else null end
      from inquiry_matches m join ri on ri.id = m.inquiry_id),
    'avg_savings_pct', (select round(avg(case when hi>0 then 100.0*(hi-lo)/hi else 0 end)::numeric,1) from spread),
    'abandoned_rfqs', (select count(*) from ri i where i.created_at < now() - interval '7 days'
                        and coalesce(i.status,'') not in ('completed','cancelled')
                        and not exists (select 1 from rq q where q.inquiry_id = i.id)),
    'active_suppliers_30d', (select count(distinct supplier_id) from rq where created_at >= now() - interval '30 days'),
    'supplier_capacity_avg', (select round(avg(c)::numeric,1) from (select supplier_id, count(*) c from rq where created_at >= now() - interval '30 days' group by supplier_id) s),
    'competitive_categories', (
      select coalesce(jsonb_agg(x order by x.avg_quotes desc), '[]'::jsonb) from (
        select i.category, round(avg(qc.c)::numeric,2) as avg_quotes, count(*) as rfqs
        from ri i join (select inquiry_id, count(*) c from rq group by inquiry_id) qc on qc.inquiry_id=i.id
        where i.created_at >= now() - interval '90 days' and i.category is not null
        group by i.category order by avg_quotes desc limit 8) x),
    'category_growth', (
      select coalesce(jsonb_agg(g), '[]'::jsonb) from (
        select category,
          count(*) filter (where created_at >= now() - interval '30 days') as this_30d,
          count(*) filter (where created_at >= now() - interval '60 days' and created_at < now() - interval '30 days') as prev_30d
        from ri where category is not null and created_at >= now() - interval '60 days'
        group by category order by this_30d desc limit 10) g),
    'generated_at', now()
  ) into res;
  return res;
end $function$;

create or replace function public.fn_ops_metrics()
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public', 'pg_temp'
as $function$
declare res jsonb;
begin
  select jsonb_build_object(
    'open_rfqs_no_quotes_7d', (select count(*) from inquiries i where i.created_at < now()-interval '7 days'
        and coalesce(i.status,'') not in ('completed','cancelled','closed')
        and not public.fn_inquiry_is_demo(i.id)
        and not exists (select 1 from quotes q where q.inquiry_id=i.id)),
    'matched_not_quoted', (select count(*) from inquiry_matches m
        where not public.fn_inquiry_is_demo(m.inquiry_id)
          and not exists (select 1 from quotes q where q.inquiry_id=m.inquiry_id and q.supplier_id=m.supplier_id)),
    'avg_first_quote_hours', (select (fn_marketplace_analytics()->>'avg_first_quote_hours')::numeric),
    'response_rate_pct', (select (fn_marketplace_analytics()->>'response_rate_pct')::numeric),
    'pipeline_by_stage', (select coalesce(jsonb_agg(jsonb_build_object('stage',label,'deals',deals,'value',value) order by sort_order),'[]'::jsonb) from crm_pipeline_report),
    'overdue_activities', (select overdue_activities from crm_deal_kpis)
  ) into res;
  return res;
end $function$;

create or replace function public.funnel_metrics(days integer default 30)
 returns json
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  with w as (select (now() - make_interval(days => days)) as since),
  ri as (select i.* from public.inquiries i, w where i.created_at >= w.since and not public.fn_inquiry_is_demo(i.id))
  select json_build_object(
    'days', days,
    'inquiries', (select count(*) from ri),
    'matched', (select count(distinct m.inquiry_id) from public.inquiry_matches m join ri i on i.id=m.inquiry_id),
    'quoted', (select count(distinct q.inquiry_id) from public.quotes q join ri i on i.id=q.inquiry_id),
    'revealed', (select count(*) from public.transactions t join ri i on i.id=t.inquiry_id where t.revealed_at is not null),
    'completed', (select count(*) from ri i where i.status='completed'),
    'cancelled', (select count(*) from ri i where i.status='cancelled'),
    'reveal_fees', (select coalesce(sum(t.reveal_fee),0) from public.transactions t join ri i on i.id=t.inquiry_id where t.revealed_at is not null)
  );
$function$;

create or replace function public.fn_strategy_metrics()
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public', 'pg_temp'
as $function$
declare res jsonb;
begin
  with dem as (select category, count(*) rfqs from inquiries
                where created_at > now()-interval '90 days' and category is not null and not public.fn_inquiry_is_demo(id)
                group by category),
  sup as (select i.category, count(distinct q.supplier_id) sups from quotes q join inquiries i on i.id=q.inquiry_id
           where q.created_at > now()-interval '90 days' and i.category is not null
             and not public.fn_inquiry_is_demo(i.id)
             and not exists (select 1 from leads l where l.id = q.supplier_id and l.is_demo)
           group by i.category)
  select jsonb_build_object(
    'under_supplied', (select coalesce(jsonb_agg(x order by x.rfqs desc),'[]'::jsonb) from (
        select d.category, d.rfqs, coalesce(s.sups,0) as active_suppliers
        from dem d left join sup s on s.category=d.category
        where coalesce(s.sups,0) < greatest(2, d.rfqs/3) order by d.rfqs desc limit 12) x),
    'coverage', jsonb_build_object(
        'categories_total', (select count(*) from category_specs),
        'with_requirements', (select count(*) from category_specs where supplier_requirements is not null),
        'with_playbook', (select count(distinct category) from qualification_playbooks where status='active'),
        'regulation_category_tags', (select count(distinct c) from regulations r, unnest(coalesce(r.categories,'{}')) c where r.status='active')),
    'funnel', (select coalesce(fn_marketplace_analytics(),'{}'::jsonb))
  ) into res;
  return res;
end $function$;

create or replace view public.finance_kpis as
 with rr as (
         select coalesce(sum(case when ga.type = 'revenue'::text then l.credit - l.debit else 0::numeric end), 0::numeric) as rev30,
            coalesce(sum(case when ga.type = 'expense'::text then l.debit - l.credit else 0::numeric end), 0::numeric) as exp30
           from gl_journal_lines l
             join gl_journal j on j.id = l.journal_id and j.status = 'posted'::text
             join gl_accounts ga on ga.code = l.account_code
          where j.entry_date >= (current_date - 30)
        ), rd as (
         select d.* from supplier_dues d
          where coalesce(public.fn_gl_fixture_or_orphan(d.transaction_id, d.supplier_id, null::uuid), '') not like 'fixture:%'
        ), ar as (
         select coalesce(sum(rd.amount_due) filter (where fn_supplier_due_is_owed(rd.status, rd.paid_at)), 0::numeric) as ar_outstanding,
            coalesce(sum(rd.amount_due) filter (where fn_supplier_due_is_owed(rd.status, rd.paid_at) and rd.due_date_30 < current_date), 0::numeric) as ar_overdue,
            coalesce(sum(rd.amount_due) filter (where rd.status = 'paid'::text), 0::numeric) as ar_collected
           from rd
        ), ap as (
         select coalesce(sum(ap_open_bills.balance_due), 0::numeric) as ap_outstanding,
            coalesce(sum(ap_open_bills.balance_due) filter (where ap_open_bills.days_overdue > 0), 0::numeric) as ap_overdue
           from ap_open_bills
        ), bud as (
         select count(*) filter (where budget_vs_actual_summary.type = 'expense'::text and budget_vs_actual_summary.pct_of_budget > 110::numeric) as budget_overruns
           from budget_vs_actual_summary
        ), gb as (
         select coalesce(sum(b.balance) filter (where b.code = any (array['1000'::text, '1050'::text])), 0::numeric) as cash,
            coalesce(sum(b.balance) filter (where b.type = 'revenue'::text), 0::numeric) as rev,
            coalesce(sum(b.balance) filter (where b.type = 'expense'::text), 0::numeric) as exp
           from gl_account_balances b
        )
 select gb.cash,
    gb.rev as revenue_total,
    gb.exp as expense_total,
    gb.rev - gb.exp as net_income,
        case when gb.rev > 0::numeric then round(100.0 * (gb.rev - gb.exp) / gb.rev, 1) else null::numeric end as margin_pct,
    rr.rev30 as revenue_30d,
    rr.exp30 as expense_30d,
    rr.exp30 - rr.rev30 as monthly_burn,
        case when (rr.exp30 - rr.rev30) > 0::numeric and gb.cash > 0::numeric then round(gb.cash / (rr.exp30 - rr.rev30), 1) else null::numeric end as runway_months,
    ar.ar_outstanding,
    ar.ar_overdue,
    ar.ar_collected,
        case when (ar.ar_collected + ar.ar_outstanding) > 0::numeric then round(100.0 * ar.ar_collected / (ar.ar_collected + ar.ar_outstanding), 1) else null::numeric end as collection_rate,
    ap.ap_outstanding,
    ap.ap_overdue,
    bud.budget_overruns
   from rr, ar, ap, bud, gb;

-- Verdict. Structure: the eight views and three routines read back with a demo test. Behaviour: each
-- figure equals an independent count taken with the demo test, and every KPI still answers one row.
-- (On 28 Sep every inquiry was a demo one, so the real counts are 0 while the raw counts are not.)
select case when (select count(*) from pg_views
                   where schemaname = 'public'
                     and viewname in ('category_price_stats','crm_deal_kpis','customer_kpis','legal_kpis',
                                      'marketing_kpis','ops_kpis','strategy_kpis','finance_kpis')
                     and definition ~ '(fn_inquiry_is_demo|is_demo|fn_gl_fixture_or_orphan)') = 8
             and (select count(*) from pg_proc
                   where pronamespace = 'public'::regnamespace
                     and proname in ('fn_ops_metrics','funnel_metrics','fn_strategy_metrics','fn_marketplace_analytics')
                     and prosrc ~ 'fn_inquiry_is_demo') = 4
             and (public.fn_marketplace_analytics() ->> 'rfqs_30d')::int
                 = (select count(*) from public.inquiries i
                     where i.created_at >= now() - interval '30 days' and not public.fn_inquiry_is_demo(i.id))
             and (public.fn_marketplace_analytics() ->> 'active_suppliers_30d')::int
                 = (select count(distinct q.supplier_id) from public.quotes q
                     where q.created_at >= now() - interval '30 days' and not public.fn_inquiry_is_demo(q.inquiry_id)
                       and not exists (select 1 from public.leads l where l.id = q.supplier_id and l.is_demo))
             and (public.funnel_metrics(36500) ->> 'inquiries')::int
                 = (select count(*) from public.inquiries i
                     where i.created_at >= now() - interval '36500 days' and not public.fn_inquiry_is_demo(i.id))
             and (public.funnel_metrics(36500) ->> 'quoted')::int
                 = (select count(distinct q.inquiry_id) from public.quotes q
                     where not public.fn_inquiry_is_demo(q.inquiry_id))
             and (public.fn_ops_metrics() ->> 'matched_not_quoted')::int
                 = (select count(*) from public.inquiry_matches m
                     where not public.fn_inquiry_is_demo(m.inquiry_id)
                       and not exists (select 1 from public.quotes q where q.inquiry_id = m.inquiry_id and q.supplier_id = m.supplier_id))
             and (select open_deals + won_deals + lost_deals from public.crm_deal_kpis)
                 = (select count(*) from public.inquiries i join public.crm_stages s on s.key = i.pipeline_stage
                     where not public.fn_inquiry_is_demo(i.id))
             and (select count(*) from public.customer_kpis) = 1
             and (select count(*) from public.legal_kpis) = 1
             and (select count(*) from public.strategy_kpis) = 1
             and (select count(*) from public.finance_kpis) = 1
             and (select count(*) from public.ops_kpis) = 1
             and (select count(*) from public.marketing_kpis) = 1
       then 'PROBE OK' else 'PROBE FAILED: a KPI lost its demo exclusion, counts a demo row, or stopped answering' end as verdict;
