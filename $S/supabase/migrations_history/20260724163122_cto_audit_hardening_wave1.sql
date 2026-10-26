-- CTO AUDIT HARDENING — WAVE 1 (safe, behaviour-preserving)
-- Applied to project htdblwldjkcgjvmqkbeh (suppliers DB) on 2026-07-24 via MCP apply_migration.
-- Mirrored into the repo so git reflects the live schema.

-- (A) Finding 2/10: pin search_path on the two advisor-flagged functions (both SECURITY INVOKER).
ALTER FUNCTION public.fn_marketing_library_search(text, integer) SET search_path = public;
ALTER FUNCTION public.fn_quote_spec_group(text) SET search_path = public;

-- (B) Finding 7: Stripe event ledger (audit trail + reconciliation). Additive only.
CREATE TABLE IF NOT EXISTS public.stripe_events (
  event_id        text PRIMARY KEY,
  type            text,
  payment_status  text,
  first_seen_at   timestamptz NOT NULL DEFAULT now(),
  last_seen_at    timestamptz NOT NULL DEFAULT now(),
  delivery_count  integer     NOT NULL DEFAULT 1,
  note            text
);
ALTER TABLE public.stripe_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.stripe_events FROM anon, authenticated;

-- (C) Finding 10: index the unindexed FK on org_agents.
DO $$
DECLARE colnames text;
BEGIN
  SELECT string_agg(quote_ident(a.attname), ', ' ORDER BY k.ord)
    INTO colnames
  FROM pg_constraint con
  JOIN unnest(con.conkey) WITH ORDINALITY AS k(attnum, ord) ON true
  JOIN pg_attribute a ON a.attrelid = con.conrelid AND a.attnum = k.attnum
  WHERE con.conname = 'org_agents_department_fkey' AND con.contype = 'f';
  IF colnames IS NOT NULL THEN
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_org_agents_department ON public.org_agents (%s)', colnames);
  END IF;
END $$;

-- (D) Finding 10: add primary keys to the four PK-less tables.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.rl_hits'::regclass AND contype='p') THEN
    ALTER TABLE public.rl_hits ADD COLUMN _pk bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.content_drafts_backup_20260724'::regclass AND contype='p') THEN
    ALTER TABLE public.content_drafts_backup_20260724 ADD COLUMN _pk bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.escalations_archive_20260724'::regclass AND contype='p') THEN
    ALTER TABLE public.escalations_archive_20260724 ADD COLUMN _pk bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.org_reset_backup_20260724'::regclass AND contype='p') THEN
    ALTER TABLE public.org_reset_backup_20260724 ADD COLUMN _pk bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY;
  END IF;
END $$;
