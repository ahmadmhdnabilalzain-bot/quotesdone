-- AUDIT 9.1 - "Universal attachment sanitisation" - FAIL, not started.
--
-- The audit tabulated 15 inbound attachment paths. Across all of them there is ONE magic-byte
-- check (reg_fetch), no shared sanitisation module, and 14 of 15 storage buckets accept any
-- content type at all. Three of those buckets carry a "limit" of 1 GB, which is not a limit.
--
-- This migration does the layer that does not depend on any edge function being correct.
-- allowed_mime_types and file_size_limit are enforced by Storage itself, so they hold even for
-- an upload path nobody has patched yet, and even for a direct signed-URL PUT that bypasses the
-- function entirely. That makes it the right thing to do FIRST.
--
-- WHAT THIS DOES NOT DO, stated plainly so it is not mistaken for the whole fix:
-- allowed_mime_types is matched against the DECLARED Content-Type on the request. A caller who
-- says 'application/pdf' and sends a ZIP passes this check. Declared type is a courtesy, not
-- evidence. The magic-byte sniffing that turns it into evidence lives in
-- supabase/functions/_shared/attachment.ts and is applied at each inbound path. This layer
-- narrows the blast radius; it does not close 9.1 on its own.
--
-- Every list below is a superset of what the bucket already holds - verified against
-- storage.objects metadata->>'mimetype' before writing - plus the types its flow legitimately
-- needs. Nothing already stored becomes unreadable; only future uploads are constrained.

do $$
declare
  b record;
  spec jsonb := jsonb_build_object(
    -- ---- untrusted input: customers and suppliers upload here ----------------------------
    'drawing-files',   jsonb_build_object('mb', 25,  'types', jsonb_build_array('application/pdf','image/jpeg','image/jpg','image/png','image/webp')),
    'quote-files',     jsonb_build_object('mb', 25,  'types', jsonb_build_array('application/pdf','image/jpeg','image/jpg','image/png','image/webp')),
    'supplier-docs',   jsonb_build_object('mb', 25,  'types', jsonb_build_array('application/pdf','image/jpeg','image/jpg','image/png','image/webp')),
    'receipt-files',   jsonb_build_object('mb', 15,  'types', jsonb_build_array('application/pdf','image/jpeg','image/png','text/html')),
    -- ---- admin/operator input -------------------------------------------------------------
    'finance-docs',    jsonb_build_object('mb', 25,  'types', jsonb_build_array('application/pdf','image/jpeg','image/png','text/plain','text/csv','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')),
    'kb-import-assets',jsonb_build_object('mb', 50,  'types', jsonb_build_array('text/plain','text/markdown','text/csv','application/json','application/pdf')),
    -- ---- system-generated -----------------------------------------------------------------
    'agent-docs',      jsonb_build_object('mb', 25,  'types', jsonb_build_array('application/pdf','text/html','text/html; charset=utf-8','text/plain','text/markdown','application/json','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')),
    'backups',         jsonb_build_object('mb', 100, 'types', jsonb_build_array('application/json','application/pdf','application/zip','text/markdown','text/plain','text/csv','image/jpeg')),
    'compliance-docs', jsonb_build_object('mb', 25,  'types', jsonb_build_array('text/markdown','text/plain','application/pdf','text/html','text/html; charset=UTF-8','text/html; charset=utf-8')),
    'finance-reports', jsonb_build_object('mb', 25,  'types', jsonb_build_array('application/pdf','text/html','text/html; charset=utf-8','text/csv','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')),
    'signed-terms',    jsonb_build_object('mb', 25,  'types', jsonb_build_array('application/pdf','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')),
    -- ---- public buckets ---------------------------------------------------------------------
    -- 'site' and 'brand' legitimately hold text/html and are served from the Supabase domain, so
    -- write access to them is equivalent to script execution on that origin. The allow-list cannot
    -- fix that; only the deploy path's authorisation can. Recorded here as a known exposure.
    'site',            jsonb_build_object('mb', 25,  'types', jsonb_build_array('text/html','text/html; charset=utf-8','text/css','text/javascript','application/json','image/png','image/jpeg','image/svg+xml','image/x-icon')),
    'brand',           jsonb_build_object('mb', 25,  'types', jsonb_build_array('image/png','image/jpeg','image/svg+xml','image/x-icon','font/ttf','font/woff','font/woff2','text/html','text/html; charset=utf-8','text/css')),
    'social-media',    jsonb_build_object('mb', 50,  'types', jsonb_build_array('image/png','image/jpeg','image/webp','video/mp4')),
    'demo-assets',     jsonb_build_object('mb', 25,  'types', jsonb_build_array('audio/mpeg','image/png','image/jpeg','video/mp4'))
  );
  k text; v jsonb; missing text := '';
begin
  -- Refuse to run half-applied: a bucket in the spec that does not exist, or a bucket in
  -- production that the spec forgot, both mean this list has drifted from reality.
  for k in select jsonb_object_keys(spec) loop
    if not exists (select 1 from storage.buckets where id = k) then missing := missing || 'spec-only:' || k || ' '; end if;
  end loop;
  for b in select id from storage.buckets loop
    if not (spec ? b.id) then missing := missing || 'unspecified:' || b.id || ' '; end if;
  end loop;
  if missing <> '' then
    raise exception 'AUDIT 9.1 bucket spec has drifted from production: %. Fix the spec rather than leaving a bucket wide open.', missing
      using errcode = '55000';
  end if;

  for k in select jsonb_object_keys(spec) loop
    v := spec -> k;
    update storage.buckets
       set allowed_mime_types = array(select jsonb_array_elements_text(v -> 'types')),
           file_size_limit    = ((v ->> 'mb')::bigint * 1024 * 1024)
     where id = k;
  end loop;
end $$;

-- A named, queryable statement of the intent, so the next audit can check the live buckets
-- against it instead of re-deriving it from a migration body.
create or replace view public.v_storage_bucket_policy as
select b.id                                        as bucket,
       b.public,
       b.file_size_limit,
       round(b.file_size_limit / 1048576.0, 1)      as size_limit_mb,
       coalesce(array_length(b.allowed_mime_types, 1), 0) as allowed_types,
       b.allowed_mime_types,
       (b.allowed_mime_types is null)               as accepts_anything,
       (b.file_size_limit is null or b.file_size_limit > 104857600) as size_limit_ineffective,
       (select count(*) from storage.objects o where o.bucket_id = b.id) as objects
from storage.buckets b;

comment on view public.v_storage_bucket_policy is
  'AUDIT 9.1. Live enforcement state of every storage bucket. accepts_anything or size_limit_ineffective being true on any row is a regression - Storage-level limits are the only attachment control that holds when an edge function is wrong or bypassed.';

revoke all on public.v_storage_bucket_policy from public, anon, authenticated;
grant select on public.v_storage_bucket_policy to service_role;
;
