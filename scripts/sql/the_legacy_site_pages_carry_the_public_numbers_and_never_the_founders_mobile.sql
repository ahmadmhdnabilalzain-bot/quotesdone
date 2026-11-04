-- THE LEGACY SITE PAGES CARRY THE PUBLIC NUMBERS AND NEVER THE FOUNDER'S MOBILE.
--
-- Seat: customer_support
-- Agent: customer_support (owner of website content). 3 Nov 2026. Ruling ledger 1482: the public calling number is
-- +971 56 791 8605 and WhatsApp is +1 218 316 6814; the founder's personal mobile is printed on nothing public.
-- Companion of the_live_system_gives_out_the_public_numbers_and_never_the_founders_mobile.sql and
-- the_founders_mobile_leaves_the_current_legal_texts.sql, which left three public.pages rows behind.
--
-- WHAT WAS MEASURED (production, 2 Nov 2026 21:45 UTC): 18 rows in public.pages; 3 carry the mobile, 7 times in all:
--   about                     1x  the schema.org JSON "telephone"
--   home_backup_predesign     4x  a wa.me link, its "WhatsApp +971 ..." label, a tel: link and its label
--   home-ar_backup_predesign  2x  a wa.me link and its Arabic WhatsApp label
-- NONE OF THE THREE IS SERVED. Every reader of public.pages, in the repository and in production, was listed:
--   - edge function compliance_archive reads slug legal_terms_body only;
--   - fn_company_hard_rules reads slug legal_supplier_body only; fn_company_org_directory_sync reads the slug LIST
--     (no html); triggers trg_pages_legal_sync_a (acts on the two legal slugs only) and trg_pages_dirty_a (sets
--     deploy_state.dirty, which nothing reads);
--   - RLS is on with no policy, anon and authenticated hold no SELECT; no view and no cron command names the table;
--   - the web site is built from src/ (public_site and site_assistant do not read pages).
-- So this is hygiene, not a leak being closed: a page restored, copied or quoted from these rows would have printed it.
--
-- WHAT THIS CHANGES: only those three rows, each guarded by the md5 of its html as read, so a row edited since is left
-- alone (and the verdict then says so). A WhatsApp link or label gets the WhatsApp number; a tel: link, a calling label
-- and the JSON telephone get the calling number. NO ROW IS DELETED. No legal slug is touched, so trg_pages_legal_sync_a
-- does nothing. The mobile is matched by the same pattern the companion files use and is never spelled out here.
-- No begin/commit: the applier runs the file as one transaction. Ends with a verdict row (PROBE OK or PROBE FAILED).
--   node scripts/apply_sql.mjs scripts/sql/the_legacy_site_pages_carry_the_public_numbers_and_never_the_founders_mobile.sql --apply --seat customer_support
-- Read-back: scripts/sql/the_legacy_site_pages_carry_the_public_numbers_and_never_the_founders_mobile_probe.sql

update public.pages p
   set html = regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(p.html,
                'wa\.me/\+?971[ .-]?50[ .-]?931[ .-]?9355', 'wa.me/12183166814', 'g'),
                '(WhatsApp|واتساب) \+?971[ .-]?50[ .-]?931[ .-]?9355', '\1 +1 218 316 6814', 'g'),
                'tel:\+?971[ .-]?50[ .-]?931[ .-]?9355', 'tel:+971567918605', 'g'),
                '\+?971[ .-]50[ .-]931[ .-]9355', '+971 56 791 8605', 'g'),
                '\+?971509319355', '+971567918605', 'g'),
       updated_at = now()
  from (values ('about', '4102fa046da9c65ef2564583931fe9ec'),
               ('home_backup_predesign', '64587e02ce6999200425036b77b65c5f'),
               ('home-ar_backup_predesign', '7bb4f93a7396a85d956dd4f6b48250ba')) g(slug, md5_as_read)
 where p.slug = g.slug and md5(p.html) = g.md5_as_read;

-- verdict
select case when
       (select count(*) from public.pages) = 18
   and (select count(*) from public.pages where html ~ '(50[ .-]?931[ .-]?9355|509319355)') = 0
   and (select count(*) from public.pages where slug = 'about' and html like '%"telephone":"+971567918605"%') = 1
   and (select count(*) from public.pages where slug = 'home_backup_predesign'
          and html like '%wa.me/12183166814%' and html like '%WhatsApp +1 218 316 6814%'
          and html like '%tel:+971567918605%' and html like '%+971 56 791 8605%') = 1
   and (select count(*) from public.pages where slug = 'home-ar_backup_predesign'
          and html like '%wa.me/12183166814%' and html like '%واتساب +1 218 316 6814%') = 1
  then 'PROBE OK' else 'PROBE FAILED: a pages row still carries the founder''s mobile, a public number is missing from a replaced spot, or a row count changed' end as verdict;
