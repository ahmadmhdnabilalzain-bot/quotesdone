select 'group cols: ' || string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ', ' order by a.attnum) as line
  from pg_attribute a where a.attrelid = 'public.inquiry_workstream_group'::regclass and a.attnum > 0 and not a.attisdropped
union all
select 'group fks: ' || coalesce(string_agg(pg_get_constraintdef(c.oid), ' | '), '(none)')
  from pg_constraint c where c.conrelid = 'public.inquiry_workstream_group'::regclass and c.contype = 'f'
union all
select 'groups total: ' || count(*)::text from public.inquiry_workstream_group
union all
select 'groups with no matching inquiry_intake: ' || count(*)::text
  from public.inquiry_workstream_group g
 where not exists (select 1 from public.inquiry_intake i where i.id::text = g.inquiry_id::text)
union all
select 'inquiry_state_audit rows: ' || count(*)::text from public.inquiry_state_audit
union all
select 'holdout result of record rows: ' || count(*)::text from public.p2c1_holdout_result_of_record
union all
select 'result_of_record fks: ' || coalesce((select string_agg(pg_get_constraintdef(c.oid), ' | ')
   from pg_constraint c where c.conrelid = 'public.p2c1_holdout_result_of_record'::regclass and c.contype = 'f'), '(none)')
union all
select 'anything referencing result_of_record: ' || coalesce((select string_agg(c.conrelid::regclass::text, ', ')
   from pg_constraint c where c.confrelid = 'public.p2c1_holdout_result_of_record'::regclass), '(none)');
