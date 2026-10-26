-- Phase 1 F0.1: settings registry. Presence in this table = CEO-editable.
-- Anything NOT listed here (all API keys, secrets, tokens, internal state) is
-- implicitly non-editable and never exposed with a value. Secret-by-default.
-- Applied to project htdblwldjkcgjvmqkbeh on 2026-07-24.
CREATE TABLE IF NOT EXISTS public.os_settings_meta (
  key         text PRIMARY KEY,
  grp         text NOT NULL,
  type        text NOT NULL CHECK (type IN ('money','int','number','bool','text','textarea','html','email','phone','csv')),
  label       text NOT NULL,
  help        text,
  validation  jsonb NOT NULL DEFAULT '{}'::jsonb,
  dangerous   boolean NOT NULL DEFAULT false,
  sort        int NOT NULL DEFAULT 100
);
ALTER TABLE public.os_settings_meta ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.os_settings_meta FROM anon, authenticated;

-- Seed of ~39 editable business keys across Pricing, Limits, Flags, Kill-switches,
-- Templates and Company. See the live table / supabase/schema/full_schema.sql for the
-- authoritative current seed (kept in sync nightly).
