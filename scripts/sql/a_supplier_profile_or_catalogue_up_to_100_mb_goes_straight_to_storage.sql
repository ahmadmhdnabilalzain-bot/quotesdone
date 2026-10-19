-- a_supplier_profile_or_catalogue_up_to_100_mb_goes_straight_to_storage
-- Seat: sales_engineer. 19 Oct 2026, founder-confirmed requirement: supplier profiles and catalogues up to 100 MB.
--
-- MEASURED on production 19 Oct 2026 (read only): storage.buckets 'supplier-docs' has file_size_limit 26214400 (25 MB),
-- public false, and allows pdf, jpeg/jpg, png, webp, csv, xls, xlsx, docx and pptx. Vercel caps a request body at 4.5 MB,
-- so every profile and catalogue now goes straight to storage on a signed upload URL (supplier_api upload_url,
-- _shared/supplier_docs_later.ts), and the bucket's own limit is what a direct upload meets. 3 of the 29 real UAE
-- profiles are 30-85 MB.
--
-- WHAT THIS CHANGES: the bucket's size limit only, to 100 MB (104857600 bytes). The MIME list, the privacy of the bucket
-- and its policies are unchanged. Every file that arrives this way is still gated on its stored bytes (type sniffed from
-- the bytes, malware scan) before it is read, and a refused file is removed (supplier_docs_later.gateStored). Reading
-- stays inside the edge's 256 MB: measured peaks in _shared/doc_read/types.ts LIMITS.maxPaperBytes.
-- No routine, no table, no grant. Applied at merge (release operator), never before.
update storage.buckets set file_size_limit = 104857600 where id = 'supplier-docs' and file_size_limit is distinct from 104857600;

select case when (select file_size_limit from storage.buckets where id = 'supplier-docs') = 104857600
            then 'PROBE OK' else 'PROBE FAILED: supplier-docs file_size_limit is not 100 MB' end as verdict;
