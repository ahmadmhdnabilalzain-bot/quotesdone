-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727004146   name: agent_knowledge_category_topic_unique
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Prevents concurrent generators from writing the same category module twice.
-- Partial: _global legitimately holds repeated topics (per-asset text, per-case lessons).
create unique index if not exists agent_knowledge_cat_topic_uidx
  on public.agent_knowledge (agent_key, topic)
  where agent_key like 'cat:%';
