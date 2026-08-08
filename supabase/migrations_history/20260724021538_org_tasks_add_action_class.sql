-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260724021538   name: org_tasks_add_action_class
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table public.org_tasks add column if not exists action_class text;
-- clear the two test objectives whose tasks failed to persist, so we re-test cleanly
delete from public.org_tasks where objective_id in (1,2);
delete from public.org_objectives where id in (1,2);
