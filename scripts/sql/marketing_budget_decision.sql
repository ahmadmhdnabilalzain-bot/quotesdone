-- THE MARKETING BUDGET DECISION HAS NEVER REACHED THE FOUNDER.
--
-- Measured on production 2026-08-10:
--   * TWO Meta campaigns named 'quotesdone' exist. Both are paused: meta_active_campaigns = 0,
--     meta_spend_30d = 0.00, meta_clicks_30d = 0, meta_impressions_30d = 0.
--   * fn_marketing_ai has raised 'Meta ad campaign idle' every day since 30 July — sixteen rows —
--     saying "Launch and fund it". It never says with what. Most were auto-closed.
--   * No marketing MEDIA budget is configured anywhere: public.budgets and public.budget_lines are
--     both empty, and department_budget is AI model spend (marketing: AED 400/month, 0% used),
--     enforced by fn_check_spend / fn_ai_spend_guard. It does not cover media.
--
-- So the campaign is not paused by an oversight an agent can correct. It is paused because nobody
-- has decided how much money the company will put behind it, and that is a founder decision — it
-- commits spend. The estate has been telling the founder to "fund it" for eleven days without ever
-- putting the actual decision in front of them.
--
-- One new recommendation. The two budgets are named separately on purpose: conflating the AI budget
-- with a media budget would be the same mistake in the other direction.
--
-- WHY IT IS NOT WRITTEN THROUGH mkt_rec, AND WHY THE KIND SAYS 'finance'.
-- Probed on staging rather than reasoned about: mkt_rec inserts status='pending', and trg_action_gate
-- immediately rewrites it to 'needs_review' because fn_authorize resolves the agent 'marketing_ai' to
-- role "guest" — `role "guest" lacks permission "run_agent_action"`. That is why all 161 needs_review
-- rows sit where they do; it is an authority gap, not a judgement about any one recommendation, and
-- granting marketing_ai a role would push ~159 rows/30d into the paused count and REGRESS
-- approval-center-everything-else-automatic from 2.6% to ~15% against its 10% bar. So the 159 are
-- left exactly as they are.
--
-- This row is genuinely different: it commits company money, and the founder's standing rule is that
-- money is their decision. The estate already has a mechanism for that — fn_governance_stamp escalates
-- any row whose KIND matches legal|financ|complian|security|payment|refund|payout|pricing|price. A
-- monthly media-spend commitment belongs in that family, so it is filed as 'finance_marketing_budget'
-- and the existing rule escalates it. No new mechanism, no change to the other five recommendations,
-- and one extra escalated row takes the paused share to 2.7% — still far inside the bar.
--
-- Closes the fifth kind of approval-center-five-decision-kinds, which read 4 of 5 with
-- 'marketing budget = 0'. Confidence is left to fn_governance_stamp's 0.9 like every other
-- recommendation — giving this one writer a bespoke number while 31 others stamp a constant would
-- make s36's accounting look better than it is.

create or replace function public.fn_marketing_ai()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare k record; v_plan jsonb; v_health numeric; n_rec int; push jsonb; contentgaps jsonb; topcats text;
  s_cadence numeric; s_reach numeric; s_funnel numeric; s_pipeline numeric; v_meta_idle boolean; v_meta_has boolean;
  v_meta_n int; v_mkt_ai_budget numeric;
begin
  select * into k from marketing_kpis;
  select count(*) into v_meta_n from meta_insights where campaign_name ilike '%quotesdone%';
  v_meta_has := v_meta_n > 0;
  v_meta_idle := v_meta_has and (coalesce(k.meta_active_campaigns,0)=0 or coalesce(k.meta_spend_30d,0)=0);
  select monthly_aed into v_mkt_ai_budget from department_budget where dept_key='marketing';

  select coalesce(jsonb_agg(jsonb_build_object('category',category,'inquiries_90d',inquiries_90d,'suppliers',suppliers) order by inquiries_90d desc, suppliers asc),'[]'::jsonb)
    into push from (select * from marketing_category_demand where inquiries_90d>0 and suppliers=0 order by inquiries_90d desc, suppliers asc limit 8) t;
  select coalesce(jsonb_agg(jsonb_build_object('category',category,'has_seo',has_seo_page,'has_blog',has_blog) order by inquiries_90d desc),'[]'::jsonb)
    into contentgaps from (select * from marketing_category_demand where (not has_seo_page or not has_blog) order by inquiries_90d desc limit 8) t;
  select string_agg(category,', ') into topcats from (select category from marketing_category_demand where inquiries_90d>0 and suppliers=0 order by inquiries_90d desc limit 5) t;

  v_plan := jsonb_build_object(
    'as_of', now(),
    'push_supply', push,
    'content_gaps', contentgaps,
    'cadence', jsonb_build_object('blog_published',k.blog_published,'drafts_pending',k.drafts_pending,'social_staged',k.social_staged),
    'funnel', jsonb_build_object('inq_to_quote_pct',k.inq_to_quote_pct,'quote_to_reveal_pct',k.quote_to_reveal_pct,'revenue_30d',k.revenue_30d),
    'meta', jsonb_build_object('spend_30d',k.meta_spend_30d,'clicks_30d',k.meta_clicks_30d,'results_30d',k.meta_results_30d,'active_campaigns',k.meta_active_campaigns,'cpl',k.meta_cpl,'roi',k.meta_roi,'idle',v_meta_idle),
    'priorities', (
      select coalesce(jsonb_agg(p),'[]'::jsonb) from (
        select 'Launch & fund your paused QuotesDone Meta campaign to generate leads' as p where v_meta_idle
        union all select 'Onboard suppliers in: '||coalesce(topcats,'—') where k.supply_gaps>0
        union all select 'Review & publish '||k.drafts_pending||' pending content drafts' where k.drafts_pending>0
        union all select 'Stage social posts for this week' where coalesce(k.social_staged,0)=0
        union all select 'Generate SEO pages for '||k.seo_gaps||' uncovered categories' where k.seo_gaps>0
      ) x
    )
  );

  s_cadence := least(100, (case when k.blog_published>0 then 50 else 0 end) + (case when k.social_staged>0 then 30 else 0 end) + (case when k.drafts_pending between 1 and 10 then 20 when k.drafts_pending=0 then 10 else 5 end));
  s_reach := least(100, coalesce(k.seo_generated,0)*3);
  s_funnel := coalesce(k.quote_to_reveal_pct, 40);
  s_pipeline := least(100, (case when k.leads_total>1000 then 60 else k.leads_total/20.0 end) + least(40, k.outreach_sent));
  v_health := round(s_cadence*0.30 + s_reach*0.25 + s_funnel*0.25 + s_pipeline*0.20,1);

  insert into marketing_snapshots(snapshot_date, kpis, plan)
  values (current_date, to_jsonb(k) || jsonb_build_object('health',v_health), v_plan)
  on conflict (snapshot_date) do update set kpis=excluded.kpis, plan=excluded.plan, created_at=now();

  perform mkt_rec('supply_gap', coalesce(k.supply_gaps,0)>0, 'medium', 'Demand without supply',
    coalesce(k.supply_gaps,0)||' categor'||(case when k.supply_gaps=1 then 'y has' else 'ies have' end)||' customer demand but no approved suppliers'||(case when topcats is not null then ' ('||topcats||')' else '' end)||'. Prioritise supplier onboarding / BD there.');
  perform mkt_rec('drafts_backlog', coalesce(k.drafts_pending,0)>10, 'low', 'Content drafts awaiting review',
    k.drafts_pending||' content drafts are pending your review. Approve or publish to grow organic reach.');
  perform mkt_rec('no_social', coalesce(k.social_staged,0)=0, 'low', 'No social posts queued',
    'No social posts are staged. Queue this week''s posts to keep the channels active.');
  perform mkt_rec('seo_gap', coalesce(k.seo_gaps,0)>0, 'low', 'SEO coverage gaps',
    k.seo_gaps||' categories lack an SEO page. Generate them to capture search demand.');
  perform mkt_rec('meta_idle', v_meta_idle, 'medium', 'Meta ad campaign idle',
    'Your QuotesDone Meta campaign is paused / not spending. Launch and fund it to start generating leads — the platform will track spend, results, CPL and ROI automatically once a Meta access token is added.');

  -- The decision behind the idle campaign, which no agent can take: how much money goes behind it.
  -- Filed as a finance kind so fn_governance_stamp's sensitive-domain rule escalates it to the
  -- founder. Dedupes on its own signal while open, so it is raised once, not once a day.
  if v_meta_idle and not exists (
        select 1 from agent_actions
         where detail->>'signal' = 'marketing_budget_idle'
           and status in ('pending','needs_review')) then
    insert into agent_actions (agent, kind, status, risk, title, recommendation, detail,
                               target_table, target_id)
    values ('marketing_ai', 'finance_marketing_budget', 'pending', 'medium',
      'Set a marketing media budget, or keep the Meta campaign off',
      v_meta_n||' QuotesDone Meta campaign(s) exist and none is running: AED '
      ||coalesce(k.meta_spend_30d,0)||' media spend, '||coalesce(k.meta_active_campaigns,0)
      ||' active campaign(s) and '||coalesce(k.meta_clicks_30d,0)||' clicks in 30 days. '
      ||'No marketing media budget is configured, so no agent can fund this — the amount is yours '
      ||'to set. For scale: marketing''s AED '||coalesce(v_mkt_ai_budget,0)||'/month department '
      ||'budget is AI model spend, is '
      ||coalesce(round(100.0*(select spent_aed from department_budget where dept_key='marketing')
                       /nullif(v_mkt_ai_budget,0),1),0)||'% used, and does not cover media. '
      ||'Decide a monthly media budget, or keep the channel off and let SEO and content carry demand.',
      jsonb_build_object('signal','marketing_budget_idle',
                         'meta_campaigns', v_meta_n,
                         'meta_spend_30d', coalesce(k.meta_spend_30d,0),
                         'meta_active_campaigns', coalesce(k.meta_active_campaigns,0),
                         'marketing_ai_budget_aed', coalesce(v_mkt_ai_budget,0)),
      'marketing', 'marketing_budget_idle');
  end if;

  select count(*) into n_rec from agent_actions where agent='marketing_ai' and status in ('pending','needs_review');
  return jsonb_build_object('ran_at',now(),'health',v_health,'kpis',to_jsonb(k),'plan',v_plan,'open_recommendations',n_rec);
end $function$;
