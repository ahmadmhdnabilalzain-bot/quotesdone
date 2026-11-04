-- The company_faq_embed_inflight table (#1812, a_company_faq_row_is_never_left_without_its_vector.sql) was created
-- without a table_export_registry row, so every_table_is_exported_or_explicitly_excluded refused it once the schema
-- mirror carried the table (#1820). It holds pg_net request ids for embeds in flight, cleared on every harvest; the
-- FAQ rows and their vectors are exported with company_faq, so this is working state, not a record. Seat: customer_support.
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('company_faq_embed_inflight', false, 'cache', 'pg_net request ids of company_faq embeds in flight, deleted on harvest or after 30 minutes; the FAQ rows and vectors are exported with company_faq.', 'customer_support')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

-- verdict (reads only)
select case
  when not exists (select 1 from public.table_export_registry where table_name = 'company_faq_embed_inflight' and exported = false)
    then 'PROBE FAILED: company_faq_embed_inflight is not registered'
  else 'PROBE OK' end as verdict;
