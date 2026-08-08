-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706110716   name: closed_case_learning_loop
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============ CLOSED-CASE LEARNING LOOP ============
-- Resolve an inquiry category to a category-agent knowledge key ('cat:<slug>'), else null.
create or replace function public.fn_resolve_cat_agent(cat text)
returns text language plpgsql stable security definer set search_path=public,pg_temp as $$
declare k text; c text := lower(trim(coalesce(cat,'')));
begin
  if c = '' then return null; end if;
  if exists(select 1 from category_agents where slug=c and coalesce(active,true)) then return 'cat:'||c; end if;
  if exists(select 1 from agent_knowledge where agent_key='cat:'||c limit 1) then return 'cat:'||c; end if;
  select 'cat:'||slug into k from category_agents
    where coalesce(active,true) and (lower(name) like '%'||c||'%' or c like '%'||slug||'%' or lower(name)=c)
    order by length(slug) desc limit 1;
  return k;
end $$;

-- On archive (or re-archive), ingest each 'lesson' into the category agent's knowledge, deduped.
create or replace function public.trg_ingest_case_lessons() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare les text; key text; n int := 0;
begin
  if NEW.ai_summary is null or jsonb_typeof(NEW.ai_summary->'lessons') <> 'array' then return NEW; end if;
  key := coalesce(public.fn_resolve_cat_agent(NEW.category), '_global');
  for les in select jsonb_array_elements_text(NEW.ai_summary->'lessons') loop
    les := trim(les);
    if length(les) < 12 then continue; end if;
    if not exists (select 1 from agent_knowledge where agent_key=key and content=les) then
      insert into agent_knowledge(agent_key, topic, content, priority)
      values (key, 'Closed-case lesson (RFQ-'||NEW.rfq_id||')', les, 60);
      n := n + 1;
    end if;
  end loop;
  return NEW;
end $$;
drop trigger if exists ingest_case_lessons on public.rfq_archives;
create trigger ingest_case_lessons after insert or update of ai_summary on public.rfq_archives
  for each row execute function public.trg_ingest_case_lessons();

-- backfill existing archived cases
update public.rfq_archives set ai_summary = ai_summary where ai_summary is not null;  -- fires trigger

select agent_key, count(*) as lessons
from agent_knowledge where topic like 'Closed-case lesson%'
group by agent_key order by lessons desc;
