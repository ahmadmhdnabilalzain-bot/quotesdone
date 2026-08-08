-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260624114244   name: social_stage_bridge
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table content_drafts add column if not exists staged_at timestamptz;
insert into app_secrets(key,value,updated_at)
values ('default_post_image','https://uploads.postiz.com/x7LqW3Ok2v.png', now())
on conflict (key) do update set value=excluded.value, updated_at=now();
