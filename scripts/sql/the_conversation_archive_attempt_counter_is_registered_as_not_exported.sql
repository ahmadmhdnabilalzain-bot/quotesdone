-- The conversation_archive_attempt counter (#1797, a_conversation_too_big_to_draw_is_kept_as_a_text_copy.sql) was
-- created without a table_export_registry row, so every_public_table_is_exported_every_day_or_excluded refused it once
-- the schema mirror carried the table (#1810). It counts render attempts per message still pending archive; the
-- message itself is in its own table and is exported there, so the counter is working state, not a record.
-- Seat: it_engineer.
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('conversation_archive_attempt', false, 'cache', 'Render attempts per conversation message still pending archive (from the 4th it is kept as an HTML copy); working state rebuilt by conversation_archive, the messages themselves are exported in their own tables.', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

-- verdict (reads only)
select case
  when not exists (select 1 from public.table_export_registry where table_name = 'conversation_archive_attempt' and exported = false)
    then 'PROBE FAILED: conversation_archive_attempt is not registered'
  else 'PROBE OK' end as verdict;
