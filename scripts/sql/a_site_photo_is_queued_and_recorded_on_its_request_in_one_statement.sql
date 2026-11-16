-- A SITE PHOTO IS QUEUED FOR ITS CHECK AND RECORDED ON ITS REQUEST IN ONE STATEMENT. 15 Nov 2026.
-- Seat: sales_engineer. Founder ledger 1704 ("For stuff that requires a site visit. The sales engineer should ask for photos. It
-- will make it easier for suppliers to quote.") and ruling 1683 (anonymity is the core: a supplier sees only the checked copy).
-- Follows the independent review of branch sales_engineer-a-site-visit-job-asks-for-photos (bf8b9ea45), items 1, 2 and 4.
--
-- 1. THE QUEUE REFUSED EVERY PHOTO (review item 1, BLOCKER). public.cad_read_jobs.why is held by cad_read_jobs_why_check
--    (a_scanned_drawing_is_queued_for_ocr_redaction.sql), read on production 15 Nov 2026 as the five values
--    over_edge_ceiling, edge_worker_died, edge_reader_failed, pdf_lengths_worker_died, scan_needs_ocr. The photo check's job
--    (why 'site_photo_check', scripts/cad_read_worker.ts sitePhoto) was refused, so customer_api site_photo answered 500
--    photo_not_queued every time and WhatsApp kept every photo back. The check is re-created with every value it held plus
--    site_photo_check.
-- 2. A PHOTO SENT AFTER THE LAST CHAT TURN NEVER REACHED THE REQUEST (review item 2). The record lived inside
--    inquiry_intake.brief, which only the next chat turn wrote. It now has its own column, inquiry_intake.site_photos
--    ({asked, photos, declined}, _shared/site_photos.ts), written by the upload itself. The chat turn writes brief whole
--    (inquiry_intake/handle.ts), so a record kept inside brief would be overwritten by any turn that read it earlier.
-- 3. READ-MODIFY-WRITE LOST PHOTOS (review item 4). WhatsApp read brief/spec, added the photo in the function and wrote the
--    whole object back: two photos sent together kept one, and a chat turn saved in between was overwritten.
--    fn_site_photos_record adds photos in ONE UPDATE whose new value is computed from the row as it is when the row lock is
--    taken (READ COMMITTED re-evaluates the SET expression on the newest row version). So two photos at once both stay, and
--    no other key of the spec is touched. Each photo must be a site_photo_check job of the row's own customer. Photos are
--    kept by job id, so a retry never adds one twice. At most 12 photos are kept per request, and a shot is kept only when
--    it is one of the asked shots (else null).
--
-- Writers: customer_api site_photo (the intake), wa_inbound/customer_files.ts (the intake or the open request),
-- inquiry_intake/handle.ts (the ask, the No-photos answer and any photos sent with a turn). Readers: inquiry_intake/handle.ts
-- (never ask twice), customer_api create_inquiry (copied to inquiries.spec.site_photos), supplier_api/site_photos_door.ts.
-- No policy change: inquiry_intake and inquiries keep their RLS and grants; both routines are closed to every client role.
-- Rehearsed LOCALLY (Postgres 16 from the mirror) with a_site_photo_is_queued_and_recorded_on_its_request_in_one_statement_probe.sql.
-- Pending until applied: scripts/sql/pending/a_site_photo_is_queued_and_recorded_on_its_request_in_one_statement.txt.

set local lock_timeout = '3s';

-- 1. The queue takes the photo check. Every value the check held before stays, in its order.
alter table public.cad_read_jobs drop constraint if exists cad_read_jobs_why_check;
alter table public.cad_read_jobs add constraint cad_read_jobs_why_check
  check (why = any (array['over_edge_ceiling', 'edge_worker_died', 'edge_reader_failed', 'pdf_lengths_worker_died', 'scan_needs_ocr', 'site_photo_check']));

-- 2. The intake's own record of the photo ask and the photos (null = nothing asked, nothing sent).
alter table public.inquiry_intake add column if not exists site_photos jsonb;
comment on column public.inquiry_intake.site_photos is
  'The site photo ask and the photos of this request: {asked:[{shot,shot_ar,from,trade,topic_id}], photos:[{shot,job_id,via}], declined?}. Written only by fn_site_photos_record (one statement); copied to inquiries.spec.site_photos by create_inquiry. A supplier sees only the copies the check released (supplier_api/site_photos_door.ts).';

-- 3a. The record with these photos added (pure apart from the ownership read; no write). Owned by the definer below.
create or replace function public.fn_site_photos_merged(p_prev jsonb, p_customer_id uuid, p_photos jsonb, p_via text, p_asked jsonb, p_declined boolean)
returns jsonb
language sql
stable
set search_path to 'public', 'pg_temp'
as $fn$
  with prev as (
    select case when jsonb_typeof(p_prev) = 'object' then p_prev else '{}'::jsonb end as r
  ), asked as (
    select case
             when jsonb_typeof(prev.r->'asked') = 'array' and jsonb_array_length(prev.r->'asked') > 0 then prev.r->'asked'
             when jsonb_typeof(p_asked) = 'array' then coalesce((select jsonb_agg(e order by k) from jsonb_array_elements(p_asked) with ordinality x(e, k)
                                                                  where k <= 6 and jsonb_typeof(e) = 'object' and coalesce(e->>'shot', '') <> ''), '[]'::jsonb)
             else '[]'::jsonb end as a
      from prev
  ), old as (
    select case when jsonb_typeof(prev.r->'photos') = 'array' then prev.r->'photos' else '[]'::jsonb end as p from prev
  ), incoming as (
    select distinct on (lower(e->>'job_id')) lower(e->>'job_id') as job_id, nullif(btrim(e->>'shot'), '') as shot, k
      from jsonb_array_elements(case when jsonb_typeof(p_photos) = 'array' then p_photos else '[]'::jsonb end) with ordinality x(e, k)
     where jsonb_typeof(e) = 'object' and coalesce(e->>'job_id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     order by lower(e->>'job_id'), k
  ), fresh as (
    -- only a photo check job of THIS customer, and only one not already on the record
    select i.job_id, i.shot, i.k
      from incoming i
      join public.cad_read_jobs j on j.id = i.job_id::uuid and j.customer_id = p_customer_id and j.why = 'site_photo_check'
     where not exists (select 1 from old, jsonb_array_elements(old.p) o where lower(o->>'job_id') = i.job_id)
  ), added as (
    select coalesce(jsonb_agg(jsonb_build_object(
             'shot', case when exists (select 1 from asked, jsonb_array_elements(asked.a) s where s->>'shot' = f.shot) then f.shot end,
             'job_id', f.job_id,
             'via', case when p_via = 'whatsapp' then 'whatsapp' else 'portal' end) order by f.k), '[]'::jsonb) as n
      from fresh f
  )
  select jsonb_build_object(
           'asked', asked.a,
           'photos', coalesce((select jsonb_agg(e order by k) from jsonb_array_elements(old.p || added.n) with ordinality y(e, k) where k <= 12), '[]'::jsonb))
         || case when prev.r->'declined' = 'true'::jsonb or coalesce(p_declined, false) then '{"declined": true}'::jsonb else '{}'::jsonb end
    from prev, asked, old, added;
$fn$;
revoke execute on function public.fn_site_photos_merged(jsonb, uuid, jsonb, text, jsonb, boolean) from public, anon, authenticated;

-- 3b. The one writer. p_table is 'inquiry_intake' (the column) or 'inquiries' (spec.site_photos, jsonb_set: no other spec key
--     is touched). The row must be the customer's (an intake started before sign-in is matched by its e-mail). Returns the
--     record as stored, or null when no row of this customer was found.
create or replace function public.fn_site_photos_record(p_table text, p_id uuid, p_customer_id uuid, p_email text, p_photos jsonb,
                                                        p_via text default 'portal', p_asked jsonb default null, p_declined boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v jsonb;
begin
  if p_id is null or p_customer_id is null then return null; end if;
  if p_table = 'inquiry_intake' then
    update public.inquiry_intake t
       set site_photos = public.fn_site_photos_merged(t.site_photos, p_customer_id, p_photos, p_via, p_asked, p_declined)
     where t.id = p_id
       and (t.customer_id = p_customer_id or (t.customer_id is null and coalesce(p_email, '') <> '' and lower(t.email) = lower(p_email)))
    returning t.site_photos into v;
  elsif p_table = 'inquiries' then
    update public.inquiries t
       set spec = jsonb_set(case when jsonb_typeof(t.spec) = 'object' then t.spec else '{}'::jsonb end, '{site_photos}',
                            public.fn_site_photos_merged(t.spec->'site_photos', p_customer_id, p_photos, p_via, p_asked, p_declined))
     where t.id = p_id and t.customer_id = p_customer_id
    returning t.spec->'site_photos' into v;
  end if;
  return v;
end
$fn$;
revoke execute on function public.fn_site_photos_record(text, uuid, uuid, text, jsonb, text, jsonb, boolean) from public, anon, authenticated;
grant execute on function public.fn_site_photos_record(text, uuid, uuid, text, jsonb, text, jsonb, boolean) to service_role;

-- Restated so this file alone leaves both tables closed (their owning files' RLS, policies and revokes are unchanged).
alter table public.inquiry_intake enable row level security;
alter table public.cad_read_jobs enable row level security;
