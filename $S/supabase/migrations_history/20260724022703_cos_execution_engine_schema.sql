-- Chief-of-Staff EXECUTION ENGINE — schema additions (paired with the cos_execute edge function).
-- Turns the objective/task ledger from a plan into work that actually gets done, hourly, within authority.

-- attempts: bounded-retry counter so a task that keeps not-completing escalates instead of looping forever.
alter table public.org_tasks add column if not exists attempts int not null default 0;
alter table public.org_tasks add column if not exists last_run_at timestamptz;

-- Departments that lack a chat specialist (analytics, procurement) get a fallback brain key so the
-- executor can still produce their deliverable via a generic department-head persona.
alter table public.org_departments add column if not exists brain_agent text;
update public.org_departments set brain_agent = coalesce(brain_agent, lead_agent) where brain_agent is null;

-- CoS FREEZE SWITCH (founder-flippable, and auto-trippable by resilience_watch). 'true' halts all
-- autonomous task execution instantly. Documented, self-contained.
insert into public.app_secrets(key, value) values ('cos_frozen', 'false') on conflict (key) do nothing;

insert into public.org_memory(scope, kind, content, source) values
('exec','policy','The Chief of Staff runs an hourly execution loop (cos_execute) that works assigned objective tasks within each department''s delegated authority. It NEVER performs money, auth, security, destructive, or gated actions autonomously — those stay founder-gated. Flip app_secrets.cos_frozen=true to halt all autonomous execution instantly.','founder_directive')
on conflict do nothing;

-- The daily founder brief (fn_founder_brief) gains an OBJECTIVES section: active objectives, tasks
-- completed in 24h, objectives closed, and per-objective progress + steps awaiting the founder.
-- (Full function body is maintained in migration 20260724_founder_brief_objectives.sql.)