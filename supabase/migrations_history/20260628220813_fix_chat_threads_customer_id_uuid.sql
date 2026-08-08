-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260628220813   name: fix_chat_threads_customer_id_uuid
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table public.chat_threads alter column customer_id type uuid using null::uuid;
