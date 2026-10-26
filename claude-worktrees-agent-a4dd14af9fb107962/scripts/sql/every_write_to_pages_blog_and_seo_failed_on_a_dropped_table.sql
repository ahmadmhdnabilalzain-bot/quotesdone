-- EVERY WRITE TO pages, blog_posts AND seo_categories FAILED ON A DROPPED TABLE.
--
-- Subject: the stale "site dirty" trigger function public.mark_site_dirty() and its three triggers.
-- Owner seat: ceo. Found 14 Sep 2026 while applying
-- the_signed_legal_registry_follows_the_14_september_texts.sql, which updates two rows of public.pages.
--
-- MEASURED ON PRODUCTION, 14 Sep 2026: the apply failed with
--   42P01: relation "public.site_publish_state" does not exist
--   QUERY: update public.site_publish_state set dirty=true, last_change_at=now() where id=1
-- raised from public.mark_site_dirty(). to_regclass('public.site_publish_state') is null, and no
-- file in scripts/sql ever created or dropped it (grep: 0 files) -- the table went out of production
-- without the repository, and the function that writes it stayed behind. pg_trigger shows it bound
-- by three statement triggers: trg_pages_dirty on public.pages, trg_blog_dirty on public.blog_posts
-- and trg_seo_dirty on public.seo_categories. So every INSERT/UPDATE/DELETE on those three tables
-- has thrown since the table went away -- the signed legal bodies in public.pages could not be
-- re-signed, and no blog post or SEO category could be edited in the database.
--
-- WHY DROPPING LOSES NOTHING: the only thing the function did was mark a row in a table that no
-- longer exists; nothing can read a flag in a missing table. public.pages keeps its current dirty
-- marker, trg_pages_dirty_a -> public.trg_pages_dirty(), which does not touch site_publish_state
-- (measured). The same shape as trg_pricing_facts on 9 Sep (DROPPED.txt): a trigger whose body
-- called a dropped thing made every write to its table throw.
--
-- WHAT THIS DOES NOT CHANGE: trg_pages_dirty_a and trg_pages_legal_sync_a on public.pages stay; no
-- table, no data, no other routine.

drop trigger if exists trg_pages_dirty on public.pages;
drop trigger if exists trg_blog_dirty on public.blog_posts;
drop trigger if exists trg_seo_dirty on public.seo_categories;
drop function if exists public.mark_site_dirty();

do $chk$
begin
  if to_regprocedure('public.mark_site_dirty()') is not null then
    raise exception 'mark_site_dirty() still exists';
  end if;
  if exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
              where not t.tgisinternal and t.tgname in ('trg_pages_dirty','trg_blog_dirty','trg_seo_dirty')) then
    raise exception 'a stale dirty trigger is still bound';
  end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.pages'::regclass and tgname = 'trg_pages_dirty_a') then
    raise exception 'the current pages dirty trigger trg_pages_dirty_a is missing';
  end if;
  raise notice 'mark_site_dirty() and its three triggers are gone; trg_pages_dirty_a remains';
end
$chk$;
