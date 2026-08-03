-- Audit 9.2 "Post-redaction verification" — FAIL, not started.
-- drawing_redact detects identifying regions with ONE multimodal call and publishes the result.
-- There is no OCR pass, no second-model review, no image comparison and no human sampling. Two
-- consequences: the model can return regions and still miss a small logo or phone number, and a
-- page where it returns has_identity:false is uploaded UNMODIFIED while the run records 'complete'.
--
-- v11 adds an adversarial second pass over the RENDERED OUTPUT of every page before it is
-- uploaded. These columns record what that pass did, so "was this page checked?" is answerable by
-- query rather than by reading logs.

alter table public.drawing_redaction_runs
  add column if not exists pages_verified integer not null default 0,
  add column if not exists verify_failed  integer not null default 0,
  add column if not exists verify_detail  jsonb;

comment on column public.drawing_redaction_runs.pages_verified is
  'Pages that passed the post-redaction verification pass and were uploaded.';
comment on column public.drawing_redaction_runs.verify_failed is
  'Pages refused by the verification pass - identifying content still visible after redaction, or the check could not be completed. These are never uploaded.';
comment on column public.drawing_redaction_runs.verify_detail is
  'Per-page findings from the verification pass, for the pages it refused.';;
