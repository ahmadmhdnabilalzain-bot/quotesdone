-- customer_spec_guide.sql - the delivery surface for the per-trade "how to specify your request" guide.
-- Seat: sales_engineer. 28 Sep 2026.
--
-- The gap: the customer inquiry form had nowhere to show a trade's specifying guide. The CONTENT is held
-- by the founder, so this file ships the empty surface only - no rows. A guide is visible to anyone only
-- once its status is 'published'; a 'draft' is invisible to anon and authenticated alike (RLS), and the
-- read routine filters on status as well so a definer-context caller cannot leak a draft either.
-- Writes are service-role only (grants revoked). No existing content table fits: marketing_article is
-- the blog, keyed by slug, with its own publishing workflow.

create table if not exists public.customer_spec_guide (
  trade       text primary key,
  body_en     text not null,
  body_ar     text not null,
  status      text not null default 'draft' check (status in ('draft', 'published')),
  updated_at  timestamptz not null default now()
);

alter table public.customer_spec_guide enable row level security;
drop policy if exists customer_spec_guide_public_reads_published on public.customer_spec_guide;
create policy customer_spec_guide_public_reads_published on public.customer_spec_guide
  as permissive for select to anon, authenticated using (status = 'published');
revoke all on public.customer_spec_guide from public, anon, authenticated;
grant select on public.customer_spec_guide to anon, authenticated;

create or replace function public.fn_customer_spec_guide(p_trade text)
returns table (trade text, body_en text, body_ar text)
language sql stable security invoker
set search_path to 'public', 'pg_temp'
as $fn$
  select g.trade, g.body_en, g.body_ar
    from public.customer_spec_guide g
   where g.trade = p_trade and g.status = 'published';
$fn$;

revoke execute on function public.fn_customer_spec_guide(text) from public;
grant execute on function public.fn_customer_spec_guide(text) to anon, authenticated;

-- Verdict-row probe (the file has DDL, so it cleans up and returns rows rather than raising):
-- a published ZZ DEMO row is returned, a draft ZZ DEMO row is not; both are removed afterwards.
insert into public.customer_spec_guide (trade, body_en, body_ar, status) values
  ('zz_demo_published', 'ZZ DEMO en', 'ZZ DEMO ar', 'published'),
  ('zz_demo_draft',     'ZZ DEMO en', 'ZZ DEMO ar', 'draft');

select case
  when (select count(*) from public.fn_customer_spec_guide('zz_demo_published')) = 1
   and (select count(*) from public.fn_customer_spec_guide('zz_demo_draft')) = 0
  then 'PROBE OK' else 'PROBE FAILED: published/draft visibility wrong' end as verdict;

delete from public.customer_spec_guide where trade in ('zz_demo_published', 'zz_demo_draft');

select case when exists (select 1 from public.customer_spec_guide where trade like 'zz\_demo\_%')
  then 'PROBE FAILED: demo rows left behind' else 'PROBE OK' end as verdict;
