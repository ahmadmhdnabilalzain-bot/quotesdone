-- A REVIEW CARRIES UP TO FIVE PRIVATE PHOTOS (T2, seat: sales_engineer, 5 Oct 2026).
--
-- Measured before this file: storage.buckets had no photo bucket and public.reviews had no photo
-- column, so a customer could leave stars and words after a revealed job but never a photo.
--
-- 1. review-photos: a PRIVATE bucket (public = false). Images only, 5 MB each — the same limits
--    customer_api/review_photos.ts enforces before upload, stated a second time by storage itself.
--    No storage.objects policy is added: only service_role (customer_api, supplier_api) reads or
--    writes it, and every read is a 1-hour signed URL.
-- 2. reviews.photo_paths: the object paths, at most five. Paths are <transaction_id>/<random>.<ext>,
--    so neither the customer's file name nor any supplier name is stored.
-- No routine and no table is created here, so there is no grant to revoke.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('review-photos', 'review-photos', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

alter table public.reviews add column if not exists photo_paths text[] not null default '{}';

alter table public.reviews drop constraint if exists reviews_photo_paths_max_five;
alter table public.reviews add constraint reviews_photo_paths_max_five
  check (coalesce(cardinality(photo_paths), 0) <= 5);

comment on column public.reviews.photo_paths is
  'Post-job review photos (T2): object paths in the private review-photos bucket, at most 5; served only as signed URLs to the customer and the reviewed supplier.';
