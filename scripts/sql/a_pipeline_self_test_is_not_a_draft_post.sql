-- A PIPELINE SELF-TEST IS NOT A DRAFT POST (6 Sep 2026, OS walk after PR #524).
--
-- Founder, verbatim: "any social media post prepared or designed need to have a clickable link for the social
-- media and if its still in draft it need to be clickable media." Measured in his browser: Marketing → Social
-- listed ten cards; nine designed drafts carry a clickable media asset (and six a Postiz draft link); the tenth,
-- "QuotesDone auto-posting pipeline test ✅" (social_posts.source = 'selftest', 24 Jun 2026), showed "no media
-- designed yet". It is the auto-posting pipeline's own smoke row — nothing was prepared or designed — and the
-- studio was presenting it as a draft without media.
--
-- fn_marketing_studio's social list now leaves out source = 'selftest' (the row stays in the table for the
-- pipeline that wrote it). The other four keys of the studio payload are unchanged.
--
-- Apply:  node scripts/apply_sql.mjs scripts/sql/a_pipeline_self_test_is_not_a_draft_post.sql --apply
-- Prove:  select jsonb_array_length(fn_marketing_studio()->'social')  ->  9 (was 10);
--         select count(*) from jsonb_array_elements(fn_marketing_studio()->'social') p where p->>'image_url' is null -> 0

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
    -- the pipeline's own smoke rows (source = 'selftest') are not posts anyone prepared or designed
    'social', coalesce((select jsonb_agg(jsonb_build_object(
        'id', p.id, 'image_url', p.image_url,
        'text', coalesce(p.content->>'all', p.content->>'text', left(p.content::text,400)),
        'channels', to_jsonb(p.channels), 'status', p.status, 'mode', p.mode, 'error', p.error, 'created_at', p.created_at,
        'live', (p.mode = 'now' and p.status in ('sent','published')),
        'permalinks', p.permalinks, 'permalink_missing', p.permalink_missing,
        'media_missing', p.media_missing, 'preview_url', p.preview_url
      ) order by p.created_at desc) from social_posts p where coalesce(p.source, '') <> 'selftest'),'[]'::jsonb),
    'blog', coalesce((select jsonb_agg(jsonb_build_object(
        'id', b.id, 'title', b.title, 'slug', b.slug, 'category', b.category, 'excerpt', b.excerpt,
        'published', b.published, 'published_at', b.published_at, 'body_html', left(b.body_html, 24000),
        'url', case when b.published and b.slug is not null then 'https://quotesdone.com/blog/' || b.slug end
      ) order by b.updated_at desc) from blog_posts b),'[]'::jsonb),
    'review', (select coalesce(fn_review_pending(),'[]'::jsonb))
  );
$function$;
