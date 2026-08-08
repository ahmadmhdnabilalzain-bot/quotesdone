-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260720195446   name: blog_posts_public_read_published_only
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Published blog posts are public content: they were served publicly on the
-- website until the legacy host was removed. This restores read access for the
-- anonymous role, scoped strictly to published rows. Drafts stay private.
grant select on public.blog_posts to anon;

drop policy if exists blog_posts_public_read on public.blog_posts;
create policy blog_posts_public_read
  on public.blog_posts
  for select
  to anon
  using (published = true);
