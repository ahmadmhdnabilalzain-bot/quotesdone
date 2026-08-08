-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260726130146   name: fn_marketing_studio
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_marketing_studio()
returns jsonb language sql stable security definer set search_path to 'public','pg_catalog' as $$
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
        'channels', to_jsonb(p.channels), 'status', p.status, 'mode', p.mode, 'error', p.error, 'created_at', p.created_at
      ) order by p.created_at desc) from social_posts p),'[]'::jsonb),
    'blog', coalesce((select jsonb_agg(jsonb_build_object(
        'id', b.id, 'title', b.title, 'slug', b.slug, 'category', b.category, 'excerpt', b.excerpt,
        'published', b.published, 'published_at', b.published_at, 'body_html', left(b.body_html, 24000)
      ) order by b.updated_at desc) from blog_posts b),'[]'::jsonb),
    'review', (select coalesce(fn_review_pending(),'[]'::jsonb))
  );
$$;

create or replace function public.fn_marketing_blog_publish(p_id uuid, p_published boolean, p_by text)
returns jsonb language plpgsql security definer set search_path to 'public','pg_catalog' as $$
declare r public.blog_posts%rowtype;
begin
  update public.blog_posts set published = p_published,
    published_at = case when p_published and published_at is null then now() else published_at end,
    updated_at = now()
  where id = p_id returning * into r;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  begin insert into public.os_audit_log(actor, action, entity, entity_id, detail)
    values (coalesce(nullif(btrim(p_by),''),'operator'), case when p_published then 'blog_publish' else 'blog_unpublish' end, 'blog_posts', p_id::text, jsonb_build_object('title', r.title));
  exception when others then null; end;
  return jsonb_build_object('ok', true, 'published', r.published);
end $$;
