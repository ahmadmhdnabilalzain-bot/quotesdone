-- PROBE: THE LEGACY SITE PAGES CARRY THE PUBLIC NUMBERS AND NEVER THE FOUNDER'S MOBILE.
--
-- Assigned: customer_support. 3 Nov 2026. Pure probe: no DDL, no write, never applied. Run AFTER
-- the_legacy_site_pages_carry_the_public_numbers_and_never_the_founders_mobile.sql, as ONE query through the
-- Management API. It always raises, so nothing it does survives; the verdict travels in the error text CHK<<...>>.
--
-- PROBE OK only if
--   1. no row of public.pages matches the founder's mobile (the pattern the companion files use; never spelled out);
--   2. all 18 rows are still there (the fix replaced text, it deleted nothing), the three legacy slugs among them;
--   3. each replaced spot now carries the public number: about's JSON telephone the calling number; the two backups'
--      wa.me links the WhatsApp number;
--   4. the two signed legal bodies still equal their registry copies (the update never reached trg_pages_legal_sync_a).
do $probe$
declare
  n_rows int; n_mobile int; n_legacy int; fails text := '';
begin
  select count(*) into n_rows from public.pages;
  select count(*) into n_mobile from public.pages where html ~ '(50[ .-]?931[ .-]?9355|509319355)';
  select count(*) into n_legacy from public.pages where slug in ('about', 'home_backup_predesign', 'home-ar_backup_predesign');

  if n_mobile <> 0 then
    fails := fails || ' 1:mobile_in(' || (select string_agg(slug, ',' order by slug) from public.pages
                                            where html ~ '(50[ .-]?931[ .-]?9355|509319355)') || ')'; end if;
  if n_rows <> 18 or n_legacy <> 3 then fails := fails || ' 2:rows(' || n_rows || ',' || n_legacy || ')'; end if;
  if not exists (select 1 from public.pages where slug = 'about' and html like '%"telephone":"+971567918605"%')
     or not exists (select 1 from public.pages where slug = 'home_backup_predesign' and html like '%wa.me/12183166814%'
                      and html like '%tel:+971567918605%')
     or not exists (select 1 from public.pages where slug = 'home-ar_backup_predesign' and html like '%wa.me/12183166814%') then
    fails := fails || ' 3:public_number_missing'; end if;
  if exists (select 1 from public.legal_documents d join public.pages p on p.slug = replace(d.source, 'pages:', '')
              where d.slug in ('customer-terms', 'supplier-agreement') and d.body_html is distinct from p.html) then
    fails := fails || ' 4:legal_body_drifted'; end if;

  raise exception 'CHK<<%>>', case when fails = ''
    then 'PROBE OK pages=' || n_rows || ' with_mobile=' || n_mobile || ' legacy_rows=' || n_legacy
    else 'PROBE FAILED:' || fails end;
end $probe$;
