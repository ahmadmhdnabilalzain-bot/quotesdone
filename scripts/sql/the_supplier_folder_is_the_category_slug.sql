-- the_supplier_folder_is_the_category_slug.sql
--
-- Assigned: sales_engineer (owns the Dropbox tree). Founder audit of 12 Oct 2026 against DROPBOX_ARCHIVE_SPEC.md.
--
-- ── the supplier folder is the primary category's SLUG (the founder's spec, 9 Sep 2026) ──
-- Audit 12 Oct: the live Suppliers/ tree mixed v1 slug folders ('interior-design'), category NAMES ('Interior
-- fit-out') and two catch-alls ('Uncategorized' and 'Other'). The spec: "the folder is the primary category's slug
-- ... 86 possible subfolders", and one honest folder for a supplier with no category: 'uncategorized'. Every
-- supplier folder in Dropbox today belongs to a test or deleted company (0 registered real suppliers), so the
-- change moves no real company; those folders go to _archive with the repair (#1284).
create or replace function public.fn_dbx_category(p_lead_id bigint)
 returns text
 language sql
 stable
 set search_path to 'public', 'pg_catalog'
as $function$
  select public.fn_dbx_safe(coalesce(
    (select c.slug from public.lead_category lc
       join public.catalog_supplier_categories c on c.slug = lc.slug
      where lc.lead_id = p_lead_id and lc.is_primary
      order by lc.score desc nulls last limit 1),
    (select c.slug from public.lead_category lc
       join public.catalog_supplier_categories c on c.slug = lc.slug
      where lc.lead_id = p_lead_id
      order by lc.score desc nulls last limit 1),
    (select c.slug from public.leads l
       join public.catalog_supplier_categories c
         on c.slug = btrim(split_part(coalesce(l.categories,''),',',1))
         or lower(c.name) = lower(btrim(split_part(coalesce(l.categories,''),',',1)))
         or c.slug = btrim(coalesce(l.sector,''))
      where l.id = p_lead_id limit 1),
    'uncategorized'));
$function$;


select case when public.fn_dbx_category(-1) = 'uncategorized'
             and not exists (select 1 from public.fn_dbx_category(-1) x where x <> lower(x))
            then 'PROBE OK' else 'PROBE FAILED: ' || public.fn_dbx_category(-1) end as verdict;
