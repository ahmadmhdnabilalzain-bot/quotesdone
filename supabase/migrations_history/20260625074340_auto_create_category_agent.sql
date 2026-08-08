-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260625074340   name: auto_create_category_agent
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- When a new service category is added, automatically create its sales agent.
create or replace function public.ensure_category_agent() returns trigger
language plpgsql as $$
begin
  if not exists (select 1 from public.category_agents where slug = NEW.slug) then
    insert into public.category_agents(slug, name, active, created_at)
    values (
      NEW.slug,
      coalesce(NEW.name, initcap(replace(NEW.slug, '-', ' '))),
      true,
      now()
    );
  end if;
  return NEW;
end $$;

drop trigger if exists trg_ensure_category_agent on public.seo_categories;
create trigger trg_ensure_category_agent
  after insert on public.seo_categories
  for each row execute function public.ensure_category_agent();

-- safety backfill: make sure every existing category already has an agent
insert into public.category_agents(slug, name, active, created_at)
select s.slug, coalesce(s.name, initcap(replace(s.slug,'-',' '))), true, now()
from public.seo_categories s
where not exists (select 1 from public.category_agents c where c.slug = s.slug);
