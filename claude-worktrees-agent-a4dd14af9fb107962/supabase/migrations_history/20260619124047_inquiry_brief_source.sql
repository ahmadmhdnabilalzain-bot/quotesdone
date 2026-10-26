-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260619124047   name: inquiry_brief_source
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table public.inquiries
  add column if not exists brief_source text;
-- brief_source: null | 'drawing' (original shared with suppliers) | 'quotation' (original NEVER shared; only anonymized scope);
