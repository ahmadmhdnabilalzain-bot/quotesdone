-- ANONYMITY / REDACTION PROVENANCE (2 Aug 2026, external security review).
-- WHY: QuotesDone sells anonymity - a supplier must not learn who the buyer is until the reveal
-- fee is paid. supplier_api hands matched suppliers a SIGNED URL for every entry in
-- inquiries.drawing_redacted_paths, and it signs ANY object path in the 'drawing-files' bucket.
-- The customer's ORIGINAL, unredacted upload lives in that SAME bucket
-- (drawings/<customer_id>/<ts>_<name>, customer_api storeOriginal), while redacted pages live at
-- redacted/<uuid>/page_pN.jpg. Until now create_inquiry copied drawing.drawing_redacted_paths
-- straight out of the REQUEST BODY into that column, so a modified or buggy frontend could name
-- the original (title block: client name, address, contacts, project number) and every matched
-- supplier would receive it for free, pre-reveal.
-- This table makes redaction output server-owned: drawing_redact writes one row per run, and
-- create_inquiry may only attach paths it can find in a row belonging to the calling customer.
-- It also records pages_in/pages_out so a PARTIAL redaction can be refused instead of silently
-- shipping the pages that happened to succeed.
create table if not exists public.drawing_redaction_runs (
  id           uuid primary key default gen_random_uuid(),
  created_at   timestamptz not null default now(),
  customer_id  uuid references public.customers(id) on delete set null,
  owner_email  text,
  -- raw prefix the caller asked for. drawing_redact deliberately discards the identifying part
  -- when building storage paths; it is kept here (server-side only) so runs made by callers that
  -- do not know customers.id - attach_photos, which is authenticated as the auth user and sends
  -- refphoto/<auth-user-id>/<ts> - can still be attributed to their owner.
  caller_ref   text,
  source_path  text,
  output_paths text[] not null default '{}'::text[],
  pages_in     integer not null default 0,
  pages_out    integer not null default 0,
  skipped      integer not null default 0,
  status       text not null default 'unknown'
);
create index if not exists drawing_redaction_runs_customer_idx on public.drawing_redaction_runs (customer_id, created_at desc);
create index if not exists drawing_redaction_runs_caller_ref_idx on public.drawing_redaction_runs (caller_ref text_pattern_ops);
create index if not exists drawing_redaction_runs_outputs_idx on public.drawing_redaction_runs using gin (output_paths);
-- Service role only: this table maps buyers to object paths, which is exactly what the anonymity
-- model protects. No policies are defined, so anon/authenticated keys can read nothing.
alter table public.drawing_redaction_runs enable row level security;
revoke all on public.drawing_redaction_runs from anon, authenticated;
