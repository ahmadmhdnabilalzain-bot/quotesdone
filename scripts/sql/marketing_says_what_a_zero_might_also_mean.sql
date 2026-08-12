-- Marketing says what a zero might also mean — 12 Aug 2026
--
-- Eighth and last in the s36 sequence for the SQL wrappers. Five mkt_rec rules plus the direct
-- finance_marketing_budget insert, all now carrying assumptions, expected impact and cost.
--
-- The meta_idle assumption is the one that earns its place: zero spend and zero active campaigns is
-- read as "the campaign is paused", and it reads identically when no Meta access token is configured
-- and the platform simply cannot see the campaign. The recommendation's own last sentence already
-- admits the token may be missing; the assumption now says so where the reasoning lives.
--
-- Every KPI, the plan payload, the health weights, the dedupe guard on the budget escalation and the
-- return shape are unchanged.

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
    coalesce(k.supply_gaps,0)||' categor'||(case when k.supply_gaps=1 then 'y has' else 'ies have' end)||' customer demand but no approved suppliers'||(case when topcats is not null then ' ('||topcats||')' else '' end)||'. Prioritise supplier onboarding / BD there.',
    jsonb_build_array(
      '"No approved suppliers" counts APPROVED ones. A supplier who registered and is waiting in the approval queue, or one approved whose capability enrichment never ran, is invisible to this count and to the matcher alike — so this can be an onboarding backlog wearing the costume of a market gap.',
      'The demand is real demand. inquiries_90d counts RFQs raised, including any the same buyer raised more than once.',
      'The category label on an RFQ matches the one suppliers are indexed under. Two vocabularies drifting apart produces this alert with supply sitting behind it.'),
    'These are the categories where a buyer asked and nobody could answer'||(case when topcats is not null then ' ('||topcats||')' else '' end)||'. Onboarding there converts demand that already exists, which is cheaper than creating new demand.',
    'No spend to invite from the 20,470 existing leads. Cost is founder attention and the invite ramp, gated on invite_enabled.');

  perform mkt_rec('drafts_backlog', coalesce(k.drafts_pending,0)>10, 'low', 'Content drafts awaiting review',
    k.drafts_pending||' content drafts are pending your review. Approve or publish to grow organic reach.',
    jsonb_build_array(
      'The drafts are worth publishing. They were generated, not commissioned, so a backlog can mean the generator is productive rather than that there is value waiting.',
      'Ten is a chosen threshold. Nothing degrades at eleven.',
      'Pending means unread. A draft deliberately parked as not-good-enough sits here identically to one nobody has opened.'),
    'Published content is the only demand channel here that costs no media money. '||k.drafts_pending||' drafts reviewed is '||k.drafts_pending||' more chances to be found by a buyer searching for a trade.',
    'No spend — generation already happened and its model cost is sunk. Review is founder time; publishing something wrong costs reputation.');

  perform mkt_rec('no_social', coalesce(k.social_staged,0)=0, 'low', 'No social posts queued',
    'No social posts are staged. Queue this week''s posts to keep the channels active.',
    jsonb_build_array(
      'Staged posts are a proxy for activity, and only a proxy: this counts what is queued in the platform, so posting directly to a channel by hand leaves this at zero.',
      'The channels are worth keeping active for a marketplace with one confirmed supplier and no customers yet — cadence for its own sake is a cost, not a strategy.'),
    'Modest and indirect. Keeping a channel warm matters when demand starts arriving; it does not create demand on its own.',
    'No spend. Staging time. The honest ceiling is that at this stage supply onboarding is worth more than posting cadence, and this rule cannot weigh the two.');

  perform mkt_rec('seo_gap', coalesce(k.seo_gaps,0)>0, 'low', 'SEO coverage gaps',
    k.seo_gaps||' categories lack an SEO page. Generate them to capture search demand.',
    jsonb_build_array(
      'A page existing is being counted, not a page ranking. Generating '||coalesce(k.seo_gaps,0)||' pages moves this counter to zero whether or not a single one is ever found in search.',
      'There is search demand in these categories to capture. Nothing in this rule reads a search volume — it reads which categories have a page.',
      'A generated page is good enough to rank. Thin pages across many categories can do a domain more harm than a few strong ones.'),
    'SEO is the compounding demand channel: a page that ranks keeps working with no further spend. The realistic impact is months away, not this week.',
    'Model spend per page, one-off. The real risk is publishing '||coalesce(k.seo_gaps,0)||' thin pages at once to clear a counter.');

  perform mkt_rec('meta_idle', v_meta_idle, 'medium', 'Meta ad campaign idle',
    'Your QuotesDone Meta campaign is paused / not spending. Launch and fund it to start generating leads — the platform will track spend, results, CPL and ROI automatically once a Meta access token is added.',
    jsonb_build_array(
      'Zero spend and zero active campaigns means the campaign is PAUSED. It reads exactly the same when no Meta access token is configured and the platform simply cannot see a campaign that is running — the recommendation''s own last sentence admits the token may be missing.',
      'The '||v_meta_n||' campaign(s) matched by name are QuotesDone''s; the match is `campaign_name ilike ''%quotesdone%''`.',
      'Paid acquisition is the right channel to restart. With one confirmed supplier, leads arriving faster than supply can serve them is a worse outcome than no leads.'),
    'Paid media is the fastest demand lever available, and the only one on this board that works in days rather than months. It is also the only one that needs money.',
    'Real money, and the amount is the founder''s to set — no agent can fund it. The escalation raised alongside this asks for exactly that figure.');

  -- The decision behind the idle campaign, which no agent can take: how much money goes behind it.
  -- Filed as a finance kind so fn_governance_stamp's sensitive-domain rule escalates it to the
  -- founder. Dedupes on its own signal while open, so it is raised once, not once a day.
  if v_meta_idle and not exists (
        select 1 from agent_actions
         where detail->>'signal' = 'marketing_budget_idle'
           and status in ('pending','needs_review')) then
    insert into agent_actions (agent, kind, status, risk, title, recommendation, detail,
                               target_table, target_id, assumptions, expected_impact, cost)
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
      'marketing', 'marketing_budget_idle',
      jsonb_build_array(
        'The reported AED '||coalesce(k.meta_spend_30d,0)||' spend and '||coalesce(k.meta_active_campaigns,0)||' active campaign(s) are the truth. Without a Meta access token the platform sees nothing and reports zero, which is indistinguishable from a campaign that is genuinely off.',
        'Spending on ads is worth doing at all right now. There is one confirmed supplier: leads arriving faster than supply can serve them damages the platform more than an empty channel does.',
        'Keeping the channel off is a legitimate answer, not a deferral — the recommendation offers it as an equal option deliberately.'),
      'This is the decision, not the alert: a figure here turns paid acquisition on, and no figure keeps it off. Either answer closes it; only silence leaves the company without a demand plan.',
      'Real money, monthly, at whatever level you set — the department''s AED '||coalesce(v_mkt_ai_budget,0)||'/month is AI model spend and does not cover media. No agent can spend it, which is why this is escalated rather than executed.');
  end if;

  select count(*) into n_rec from agent_actions where agent='marketing_ai' and status in ('pending','needs_review');
  return jsonb_build_object('ran_at',now(),'health',v_health,'kpis',to_jsonb(k),'plan',v_plan,'open_recommendations',n_rec);
end $function$;
