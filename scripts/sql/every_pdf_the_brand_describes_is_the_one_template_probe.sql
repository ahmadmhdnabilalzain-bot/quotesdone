-- Probe for every_pdf_the_brand_describes_is_the_one_template.sql (22 Sep 2026). Pure probe, no DDL.
select case when count(*) = 2 and bool_and(value not ilike '%Helvetica%' and value not ilike '%Confidential%' and value ilike '%pdf_native%')
            then 'PROBE OK' else 'PROBE FAILED' end as verdict,
       string_agg(key, ', ' order by key) as rows_read
  from public.company_brand where key in ('type.pdf', 'imagery.documents');
