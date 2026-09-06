-- SOCIAL POSTS ARE CLICKABLE (founder's order, 6 Sep 2026): a prepared or designed social post carries
-- a clickable link to the network once it is published, and clickable media while it is still a draft.
--
-- Measured on 6 Sep 2026 before this file: social_posts held 4 rows, all mode='draft' status='sent'
-- (sent to Postiz as DRAFTS on 24 Jun 2026 — none ever reached a network; marketing_golive is 'false'),
-- 3 with an image at uploads.postiz.com (HEAD 200) and 1 selftest row with none. Postiz's public API no
-- longer lists those June post ids, so no network permalink exists for them and none can be recovered:
-- they are disclosed as permalink_missing with that reason rather than given an invented URL.
-- The OS labelled those four "Social live" because marketing_kpis counted status='sent' alone.
--
-- Mechanism, so it stays true:
--   * permalinks     jsonb  {channel: url}   the network URLs (Postiz releaseURL per channel), filled by
--                                             postiz_publish action=sync once Postiz reports the release
--   * permalink_missing text                 why there is no permalink yet (a live row must carry one or
--                                             the other — the CHECK below refuses a live row with neither)
--   * media_missing  text                    'no media designed yet' when image_url is null (every row
--                                             must carry an image or this reason)
--   * preview_url    text                    the Postiz preview page for a draft (platform.postiz.com/p/<id>)
--   postiz_publish is now the ONE writer of the ledger row (it used to write agent_runs only, so the
--   24 Postiz drafts created through agent_act/secretary_act in Jul–Aug 2026 had no row at all).
begin;

alter table public.social_posts
  add column if not exists permalinks jsonb,
  add column if not exists permalink_missing text,
  add column if not exists media_missing text,
  add column if not exists preview_url text;

comment on column public.social_posts.permalinks is 'network URLs per channel ({"x": "https://x.com/..."}) — the Postiz releaseURL, written by postiz_publish action=sync';
comment on column public.social_posts.permalink_missing is 'the honest reason a live row has no permalink yet; a live row (mode=now, status sent/published) must carry permalinks or this';
comment on column public.social_posts.media_missing is '''no media designed yet'' when image_url is null; every row carries an image or this reason';
comment on column public.social_posts.preview_url is 'Postiz preview page of the draft (platform.postiz.com/p/<postId>?share=true)';

-- Backfill the four rows measured on 6 Sep 2026 (all sent to Postiz as drafts, none published).
update public.social_posts
   set permalink_missing = coalesce(permalink_missing,
         'sent to Postiz as a draft (type=draft) on ' || to_char(created_at, 'DD Mon YYYY') ||
         ', never published to a network; Postiz no longer lists these post ids (GET /public/v1/posts for that month returned none on 6 Sep 2026), so no network URL exists to recover')
 where mode = 'draft' and permalinks is null and permalink_missing is null;
update public.social_posts
   set media_missing = coalesce(media_missing, 'no media designed yet')
 where image_url is null;

alter table public.social_posts drop constraint if exists social_posts_clickable;
alter table public.social_posts add constraint social_posts_clickable check (
  (image_url is not null or media_missing is not null)
  and (
    not (mode = 'now' and status in ('sent', 'published'))
    or (permalinks is not null and permalinks <> '{}'::jsonb)
    or permalink_missing is not null
  )
);

-- "Social live" counts posts that went to a network (mode=now); a Postiz draft is staged, not live.
create or replace view public.marketing_kpis as
 WITH f AS (
         SELECT funnel_metrics(30) AS fm
        ), mi AS (
         SELECT COALESCE(sum(meta_insights.spend), (0)::numeric) AS meta_spend,
            COALESCE(sum(meta_insights.impressions), (0)::numeric) AS meta_impr,
            COALESCE(sum(meta_insights.clicks), (0)::numeric) AS meta_clicks,
            COALESCE(sum(meta_insights.results), (0)::numeric) AS meta_results,
            count(*) FILTER (WHERE (meta_insights.effective_status = 'ACTIVE'::text)) AS meta_active
           FROM meta_insights
          WHERE ((meta_insights.time_window = 'last_30d'::text) AND (meta_insights.campaign_name ~~* '%quotesdone%'::text))
        )
 SELECT ((f.fm ->> 'inquiries'::text))::integer AS inquiries_30d,
    ((f.fm ->> 'matched'::text))::integer AS matched_30d,
    ((f.fm ->> 'quoted'::text))::integer AS quoted_30d,
    ((f.fm ->> 'revealed'::text))::integer AS revealed_30d,
    ((f.fm ->> 'reveal_fees'::text))::numeric AS revenue_30d,
        CASE
            WHEN (((f.fm ->> 'inquiries'::text))::integer > 0) THEN round(((100.0 * (((f.fm ->> 'quoted'::text))::integer)::numeric) / (((f.fm ->> 'inquiries'::text))::integer)::numeric), 1)
            ELSE NULL::numeric
        END AS inq_to_quote_pct,
        CASE
            WHEN (((f.fm ->> 'quoted'::text))::integer > 0) THEN round(((100.0 * (((f.fm ->> 'revealed'::text))::integer)::numeric) / (((f.fm ->> 'quoted'::text))::integer)::numeric), 1)
            ELSE NULL::numeric
        END AS quote_to_reveal_pct,
    ( SELECT count(*) AS count
           FROM blog_posts
          WHERE blog_posts.published) AS blog_published,
    ( SELECT count(*) AS count
           FROM blog_posts) AS blog_total,
    ( SELECT count(*) AS count
           FROM content_drafts
          WHERE (COALESCE(content_drafts.status, ''::text) <> ALL (ARRAY['published'::text, 'discarded'::text]))) AS drafts_pending,
    ( SELECT count(*) AS count
           FROM social_posts
          WHERE (COALESCE(social_posts.status, ''::text) = ANY (ARRAY['staged'::text, 'scheduled'::text, 'draft'::text, 'pending'::text]))
             OR (social_posts.mode = 'draft'::text AND COALESCE(social_posts.status, ''::text) = ANY (ARRAY['published'::text, 'sent'::text]))) AS social_staged,
    ( SELECT count(*) AS count
           FROM social_posts
          WHERE (social_posts.mode = 'now'::text AND COALESCE(social_posts.status, ''::text) = ANY (ARRAY['published'::text, 'sent'::text]))) AS social_published,
    ( SELECT count(*) AS count
           FROM seo_categories) AS seo_pages,
    ( SELECT count(*) AS count
           FROM seo_categories
          WHERE seo_categories.generated) AS seo_generated,
    ( SELECT count(*) AS count
           FROM leads) AS leads_total,
    ( SELECT count(*) AS count
           FROM outreach) AS outreach_sent,
    ( SELECT COALESCE(gl_account_balances.balance, (0)::numeric) AS "coalesce"
           FROM gl_account_balances
          WHERE (gl_account_balances.code = '6200'::text)) AS mkt_spend,
    ( SELECT count(*) AS count
           FROM customers
          WHERE (customers.created_at >= (now() - '30 days'::interval))) AS new_customers_30d,
        CASE
            WHEN (mi.meta_spend > (0)::numeric) THEN round((mi.meta_spend / (NULLIF(( SELECT count(*) AS count
               FROM customers
              WHERE (customers.created_at >= (now() - '30 days'::interval))), 0))::numeric), 2)
            ELSE NULL::numeric
        END AS cac,
        CASE
            WHEN (mi.meta_spend > (0)::numeric) THEN round((((f.fm ->> 'reveal_fees'::text))::numeric / mi.meta_spend), 2)
            WHEN (( SELECT COALESCE(gl_account_balances.balance, (0)::numeric) AS "coalesce"
               FROM gl_account_balances
              WHERE (gl_account_balances.code = '6200'::text)) > (0)::numeric) THEN round((((f.fm ->> 'reveal_fees'::text))::numeric / ( SELECT COALESCE(gl_account_balances.balance, (0)::numeric) AS "coalesce"
               FROM gl_account_balances
              WHERE (gl_account_balances.code = '6200'::text))), 2)
            ELSE NULL::numeric
        END AS roi,
    ( SELECT count(*) AS count
           FROM marketing_category_demand
          WHERE ((marketing_category_demand.inquiries_90d > 0) AND (marketing_category_demand.suppliers = 0))) AS supply_gaps,
    ( SELECT count(*) AS count
           FROM marketing_category_demand
          WHERE (NOT marketing_category_demand.has_seo_page)) AS seo_gaps,
    mi.meta_spend AS meta_spend_30d,
    mi.meta_impr AS meta_impressions_30d,
    mi.meta_clicks AS meta_clicks_30d,
    mi.meta_results AS meta_results_30d,
    mi.meta_active AS meta_active_campaigns,
        CASE
            WHEN (mi.meta_results > (0)::numeric) THEN round((mi.meta_spend / mi.meta_results), 2)
            ELSE NULL::numeric
        END AS meta_cpl,
        CASE
            WHEN (mi.meta_spend > (0)::numeric) THEN round((((f.fm ->> 'reveal_fees'::text))::numeric / mi.meta_spend), 2)
            ELSE NULL::numeric
        END AS meta_roi
   FROM f,
    mi;

-- The Review tab's drafts say when they have no media rather than rendering a blank.
CREATE OR REPLACE FUNCTION public.fn_review_pending()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'marketing_posts', coalesce((select jsonb_agg(jsonb_build_object(
        'kind','marketing_post','ref_id',c.id,'title',c.title,'channel',c.channel,'body',c.body,'image_url',c.image_url,
        'media_missing', case when c.image_url is null then 'no media designed yet' end,
        'created_at',c.created_at)
        order by c.created_at desc)
      from content_drafts c where c.status='draft' and coalesce(c.review_status,'pending')='pending'), '[]'::jsonb),
    'refunds', coalesce((select jsonb_agg(jsonb_build_object(
        'kind','refund','ref_id',t.id,'customer_id',t.customer_id,'reason',t.refund_reason,'requested_at',t.refund_requested_at)
        order by t.refund_requested_at desc)
      from transactions t where t.refund_status='requested'), '[]'::jsonb),
    'boost_budgets', coalesce((select jsonb_agg(jsonb_build_object(
        'kind','boost_budget','ref_id',r.id,'title',r.title,'summary',r.summary,'payload',r.payload,'created_at',r.created_at)
        order by r.created_at desc)
      from review_queue r where r.kind='boost_budget' and r.status='pending'), '[]'::jsonb)
  );
$function$;

-- The Marketing page's lists carry the URLs: per-channel permalinks, the media, the Postiz preview,
-- the reasons when one is missing, and the live blog URL.
CREATE OR REPLACE FUNCTION public.fn_marketing_studio()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', (select to_jsonb(k) from marketing_kpis k limit 1),
    'trend', coalesce((select jsonb_agg(jsonb_build_object(
        'd', to_char(s.snapshot_date,'Mon DD'),
        'leads', nullif(s.kpis->>'leads_total','')::numeric,
        'blog', nullif(s.kpis->>'blog_published','')::numeric,
        'social', nullif(s.kpis->>'social_published','')::numeric,
        'seo', nullif(s.kpis->>'seo_pages','')::numeric
      ) order by s.snapshot_date) from marketing_snapshots s),'[]'::jsonb),
    'social', coalesce((select jsonb_agg(jsonb_build_object(
        'id', p.id, 'image_url', p.image_url,
        'text', coalesce(p.content->>'all', p.content->>'text', left(p.content::text,400)),
        'channels', to_jsonb(p.channels), 'status', p.status, 'mode', p.mode, 'error', p.error, 'created_at', p.created_at,
        'live', (p.mode = 'now' and p.status in ('sent','published')),
        'permalinks', p.permalinks, 'permalink_missing', p.permalink_missing,
        'media_missing', p.media_missing, 'preview_url', p.preview_url
      ) order by p.created_at desc) from social_posts p),'[]'::jsonb),
    'blog', coalesce((select jsonb_agg(jsonb_build_object(
        'id', b.id, 'title', b.title, 'slug', b.slug, 'category', b.category, 'excerpt', b.excerpt,
        'published', b.published, 'published_at', b.published_at, 'body_html', left(b.body_html, 24000),
        'url', case when b.published and b.slug is not null then 'https://quotesdone.com/blog/' || b.slug end
      ) order by b.updated_at desc) from blog_posts b),'[]'::jsonb),
    'review', (select coalesce(fn_review_pending(),'[]'::jsonb))
  );
$function$;

commit;
