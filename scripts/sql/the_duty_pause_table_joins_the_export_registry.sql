-- THE DUTY PAUSE TABLE JOINS THE EXPORT REGISTRY (30 Sep 2026; seat: it_engineer, release operator).
--
-- #1139 created public.duty_pause and added it to the daily export by redefining fn_table_export_list().
-- #1137 then replaced that list with public.table_export_registry, seeded from the list as it stood before
-- #1139 merged, so duty_pause is live, unexported and in no registry row (read back 30 Sep 2026: 313 exported,
-- duty_pause absent). This is the registry row #1137's header asks every table-creating PR to carry.

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('duty_pause', true, 'company', 'which duties are paused, by whom and why (one row = one paused duty; #1139)', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

select case when exists (select 1 from public.fn_table_export_list() t where t::text like '%duty_pause%')
            then 'PROBE OK duty_pause exported, ' || (select count(*) from public.table_export_registry where exported) || ' exported'
            else 'PROBE FAILED: duty_pause is not in fn_table_export_list()' end as verdict;
