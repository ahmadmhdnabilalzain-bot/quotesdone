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
--   * figures these views take from routines - fn_ops_metrics (ops_kpis), funnel_metrics (marketing_kpis),
--     fn_strategy_metrics and finance_kpis (strategy_kpis). Those routines are their own subjects; this
--     file does not retype their bodies. Named here so it is not mistaken for covered.
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

-- Verdict: every one of the seven reads back with a demo exclusion, and each still answers a row.
select case when (select count(*) from pg_views
                   where schemaname = 'public'
                     and viewname in ('category_price_stats','crm_deal_kpis','customer_kpis','legal_kpis',
                                      'marketing_kpis','ops_kpis','strategy_kpis')
                     and definition ~ '(fn_inquiry_is_demo|is_demo)') = 7
             and (select count(*) from public.crm_deal_kpis) = 1
             and (select count(*) from public.customer_kpis) = 1
             and (select count(*) from public.legal_kpis) = 1
             and (select count(*) from public.strategy_kpis) = 1
       then 'PROBE OK' else 'PROBE FAILED: a KPI view lost its demo exclusion or stopped answering' end as verdict;
