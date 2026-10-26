-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260628202434   name: auto_publish_site_on_content_change
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists public.site_publish_state(
  id int primary key default 1,
  dirty boolean not null default false,
  last_change_at timestamptz,
  last_deploy_at timestamptz
);
insert into public.site_publish_state(id,dirty) values(1,false) on conflict (id) do nothing;
alter table public.site_publish_state enable row level security;
revoke all on public.site_publish_state from anon, authenticated;

create or replace function public.mark_site_dirty() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  update public.site_publish_state set dirty=true, last_change_at=now() where id=1;
  return null;
end$$;

drop trigger if exists trg_pages_dirty on public.pages;
create trigger trg_pages_dirty after insert or update or delete on public.pages for each statement execute function public.mark_site_dirty();

do $$ begin
  if to_regclass('public.blog_posts') is not null then
    execute 'drop trigger if exists trg_blog_dirty on public.blog_posts';
    execute 'create trigger trg_blog_dirty after insert or update or delete on public.blog_posts for each statement execute function public.mark_site_dirty()';
  end if;
  if to_regclass('public.seo_categories') is not null then
    execute 'drop trigger if exists trg_seo_dirty on public.seo_categories';
    execute 'create trigger trg_seo_dirty after insert or update or delete on public.seo_categories for each statement execute function public.mark_site_dirty()';
  end if;
end $$;

create or replace function public.run_site_autodeploy() returns void
language plpgsql security definer set search_path=public,pg_temp,net as $$
declare s text; d boolean; lastdep timestamptz;
begin
  select dirty, last_deploy_at into d, lastdep from public.site_publish_state where id=1;
  if not coalesce(d,false) then return; end if;
  if lastdep is not null and now()-lastdep < interval '50 seconds' then return; end if;
  select value into s from public.app_secrets where key='inbound_secret';
  if s is null then return; end if;
  update public.site_publish_state set dirty=false, last_deploy_at=now() where id=1;
  perform net.http_post(
    url := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/site_deploy',
    body := jsonb_build_object('__secret', s),
    headers := jsonb_build_object('Content-Type','application/json'),
    timeout_milliseconds := 150000
  );
end$$;

select cron.schedule('site_autodeploy','* * * * *', 'select public.run_site_autodeploy();');
