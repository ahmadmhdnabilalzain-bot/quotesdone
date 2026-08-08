-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709084410   name: fn_marketing_ai_agent
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- de-dupe helper: one open marketing recommendation per signal
create or replace function public.mkt_rec(p_sig text, p_cond boolean, p_risk text, p_title text, p_reco text)
returns void language plpgsql security definer set search_path to 'public','pg_temp' as $$
begin
  if p_cond and not exists (select 1 from agent_actions where kind='marketing_recommendation' and detail->>'signal'=p_sig and status in ('pending','needs_review')) then
    insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
    values ('marketing_ai','marketing_recommendation','pending',p_risk,p_title,p_reco,jsonb_build_object('signal',p_sig),'marketing',p_sig);
  end if;
end $$;
revoke all on function public.mkt_rec(text,boolean,text,text,text) from anon, authenticated, public;

create or replace function public.fn_marketing_ai()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare k record; v_plan jsonb; v_health numeric; n_rec int; push jsonb; contentgaps jsonb; topcats text;
  s_cadence numeric; s_reach numeric; s_funnel numeric; s_pipeline numeric;
begin
  select * into k from marketing_kpis;

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
    'priorities', (
      select coalesce(jsonb_agg(p),'[]'::jsonb) from (
        select 'Onboard suppliers in: '||coalesce(topcats,'—') as p where k.supply_gaps>0
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

  -- recommendations (kept for founder; agent never auto-publishes/posts/sends)
  perform mkt_rec('supply_gap', coalesce(k.supply_gaps,0)>0, 'medium', 'Demand without supply',
    coalesce(k.supply_gaps,0)||' categor'||(case when k.supply_gaps=1 then 'y has' else 'ies have' end)||' customer demand but no approved suppliers'||(case when topcats is not null then ' ('||topcats||')' else '' end)||'. Prioritise supplier onboarding / BD there.');
  perform mkt_rec('drafts_backlog', coalesce(k.drafts_pending,0)>10, 'low', 'Content drafts awaiting review',
    k.drafts_pending||' content drafts are pending your review. Approve or publish to grow organic reach.');
  perform mkt_rec('no_social', coalesce(k.social_staged,0)=0, 'low', 'No social posts queued',
    'No social posts are staged. Queue this week''s posts to keep the channels active.');
  perform mkt_rec('seo_gap', coalesce(k.seo_gaps,0)>0, 'low', 'SEO coverage gaps',
    k.seo_gaps||' categories lack an SEO page. Generate them to capture search demand.');

  select count(*) into n_rec from agent_actions where agent='marketing_ai' and status in ('pending','needs_review');
  return jsonb_build_object('ran_at',now(),'health',v_health,'kpis',to_jsonb(k),'plan',v_plan,'open_recommendations',n_rec);
end $fn$;
revoke all on function public.fn_marketing_ai() from anon, authenticated, public;

insert into public.category_agents(slug,name,emoji,active,persona)
values ('marketing_ai','Marketing AI','📣',true,
  'Owns growth marketing across SEO, content, social and lead generation. Tracks the demand funnel (inquiries to quotes to reveals), content output, SEO coverage, lead pipeline and marketing ROI/CAC, and scores marketing health. Produces a marketing plan (which categories to push from demand-vs-supply gaps, content and SEO gaps) and campaign report, and surfaces recommendations. Content drafts, social posts and BD invites are KEPT for the founder to approve — the agent never auto-publishes, posts, or sends cold outreach on its own.')
on conflict (slug) do update set name=excluded.name, emoji=excluded.emoji, active=excluded.active, persona=excluded.persona;

select cron.schedule('marketing_ai_daily','50 6 * * *', $$select public.fn_marketing_ai();$$);
