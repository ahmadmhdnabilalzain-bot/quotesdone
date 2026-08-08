-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260625073856   name: dedupe_it_incidents
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- 1) collapse existing duplicate IT "agent runs failed" incidents to the newest one
delete from public.agent_actions
where id in (
  select id from public.agent_actions
  where agent='it' and kind='incident' and target_table='agent_runs' and status='pending'
  order by id desc offset 1
);

-- 2) guard: skip inserting a new pending IT incident if an equivalent one is already open
create or replace function public.dedupe_it_incident() returns trigger
language plpgsql as $$
begin
  if NEW.agent='it' and NEW.kind='incident' and coalesce(NEW.status,'pending')='pending' then
    if exists (
      select 1 from public.agent_actions a
      where a.agent='it' and a.kind='incident' and a.status='pending'
        and coalesce(a.target_table,'')=coalesce(NEW.target_table,'')
    ) then
      return null; -- duplicate open incident; skip
    end if;
  end if;
  return NEW;
end $$;

drop trigger if exists trg_dedupe_it_incident on public.agent_actions;
create trigger trg_dedupe_it_incident
  before insert on public.agent_actions
  for each row execute function public.dedupe_it_incident();
