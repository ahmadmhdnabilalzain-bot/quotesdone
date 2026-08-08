-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260609154916   name: supplier_approval_workflow
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table public.leads
  add column if not exists approval_status text,             -- 'pending' | 'approved' | 'rejected'
  add column if not exists ai_review_notes text,             -- AI's plain-English review of the registration
  add column if not exists ai_review_flags jsonb,            -- structured issues the AI found
  add column if not exists ai_reviewed_at timestamptz,
  add column if not exists registration_submitted_at timestamptz;
