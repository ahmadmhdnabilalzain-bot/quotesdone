-- A TABLE WITH NO PRIMARY KEY IS REFUSED BY THE EXPORT REGISTRY, AND NEVER STOPS THE DAY.
--
-- Seat: it_engineer (wave 3 OPS builder, 16 Nov 2026; the follow-up the_daily_export_reaches_every_table_again.sql named).
-- WHAT HAPPENED. public.ceo_year_plan_archive was created on 11 Nov with LIKE ceo_year_plan (LIKE copies no primary key) and
-- registered exported = true. The daily export pages every table on its primary key, in name order; fn_table_export_page
-- raised "has no primary key to page on" at that table, so the 12, 13, 14 and 15 Nov exports each stopped there after six
-- attempts and about 115 tables after it in name order (customers, inquiries, leads, quotes, suppliers ...) had no database
-- export for four days (table_export_run, SELECT 16 Nov 2026). One table stopped the day for every other.
-- WHAT THIS FILE DOES:
--   1. fn_table_export_pageable(table): the relation exists, is a table and has a primary key -- the one thing the export
--      needs to page it;
--   2. the registry REFUSES a table that exists without a primary key as exported (trigger on public.table_export_registry),
--      naming the table and the fix, so the file that registers it fails at apply instead of the export failing at night;
--   3. the export SKIPS AND REPORTS one that is registered and cannot be paged anyway (dropped, renamed, or its key removed
--      later): fn_table_export_list leaves it out, so the day exports every other table and finishes; fn_table_export_unpageable
--      names each with the reason, and the daily duty it_engineer.export_unpageable keeps one finding per such table
--      (table_export:unpageable:<table>) open until it is paged again.
-- Measured 16 Nov 2026 (SELECT): no public table lacks a primary key, no exported registry row names a missing table, 436 of
-- 830 registry rows exported; so on the day this is applied the list is unchanged and no finding opens.
-- Base: fn_table_export_list is production's body (md5 f3ff8c549848b9d21eed4eab691c9607, 16 Nov 2026) plus one condition.
-- Prevented by: the trigger itself (an apply that registers such a table fails) and
--   a_table_with_no_primary_key_is_refused_by_the_export_registry_and_never_stops_the_day_probe.sql.
-- Rollback: drop trigger table_export_registry_needs_a_key on public.table_export_registry; re-apply production's
--   fn_table_export_list; delete from public.seat_duty where duty = 'it_engineer.export_unpageable'.
set local lock_timeout = '3s';

create or replace function public.fn_table_export_pageable(p_table text)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select exists (select 1 from pg_class c join pg_index i on i.indrelid = c.oid and i.indisprimary
                  where c.oid = to_regclass(format('public.%I', p_table)) and c.relkind in ('r', 'p'))
$fn$;
revoke execute on function public.fn_table_export_pageable(text) from public, anon, authenticated;

-- 2. the registry refuses it
create or replace function public.trg_table_export_registry_needs_a_key()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  -- a table not created yet is allowed (a file may register before it creates); the export skips and reports it until it exists
  if new.exported and to_regclass(format('public.%I', new.table_name)) is not null and not public.fn_table_export_pageable(new.table_name) then
    raise exception 'table_export_registry: public.% cannot be exported: it is not a table with a primary key, and the daily export pages every table on its primary key (a table made with LIKE copies none: add PRIMARY KEY, or LIKE ... INCLUDING ALL)', new.table_name
      using errcode = 'check_violation';
  end if;
  return new;
end $fn$;
revoke execute on function public.trg_table_export_registry_needs_a_key() from public, anon, authenticated;

drop trigger if exists table_export_registry_needs_a_key on public.table_export_registry;
create trigger table_export_registry_needs_a_key
  before insert or update of exported, table_name on public.table_export_registry
  for each row execute function public.trg_table_export_registry_needs_a_key();

-- 3. the export skips what it cannot page, and says so
create or replace function public.fn_table_export_list()
returns table(table_name text, subject text, change_log text)
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
  select r.table_name, r.category,
         (select 'table_export_change' from public.table_export_change_tracked x where x.table_name = r.table_name)
    from public.table_export_registry r
   where r.exported
     -- 16 Nov 2026: one table the export cannot page never stops the day for every other (fn_table_export_unpageable reports it)
     and public.fn_table_export_pageable(r.table_name)
   order by r.table_name
$function$;
revoke execute on function public.fn_table_export_list() from public, anon, authenticated;

create or replace function public.fn_table_export_unpageable()
returns table(table_name text, reason text)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select r.table_name,
         case when to_regclass(format('public.%I', r.table_name)) is null then 'registered as exported but public.' || r.table_name || ' does not exist'
              else 'public.' || r.table_name || ' is not a table with a primary key, so the export cannot page it' end
    from public.table_export_registry r
   where r.exported and not public.fn_table_export_pageable(r.table_name)
   order by r.table_name
$fn$;
revoke execute on function public.fn_table_export_unpageable() from public, anon, authenticated;

create or replace function public.fn_table_export_unpageable_settle()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare u record; v_open int := 0; v_closed int := 0;
begin
  for u in select * from public.fn_table_export_unpageable() loop
    perform public.fn_it_engineer_finding_upsert(
      'table_export:unpageable:' || u.table_name,
      'The daily export skips public.' || u.table_name || ': ' || u.reason,
      'public.table_export_registry / fn_table_export_list', 'agent_facing', 1,
      jsonb_build_object('table', u.table_name, 'reason', u.reason, 'skipped_since', now()),
      array['the rest of the day: every other registered table is still exported (fn_table_export_list skips only this one)'],
      array['give the table a primary key, or register it exported = false with the reason it is not needed'], 'it_engineer');
    v_open := v_open + 1;
  end loop;
  for u in select f.issue_key from public.it_engineer_finding f
            where f.issue_key like 'table_export:unpageable:%' and f.closed_at is null
              and not exists (select 1 from public.fn_table_export_unpageable() x where 'table_export:unpageable:' || x.table_name = f.issue_key) loop
    perform public.fn_it_engineer_finding_close(u.issue_key, 'the table is exported again: it has a primary key, or it is no longer registered as exported');
    v_closed := v_closed + 1;
  end loop;
  return jsonb_build_object('skipped', v_open, 'closed', v_closed);
end $fn$;
revoke execute on function public.fn_table_export_unpageable_settle() from public, anon, authenticated;

insert into public.seat_duty (duty, what, every, enabled, routine, owner_file, owner_seat) values
 ('it_engineer.export_unpageable', 'a table the daily export skips (no primary key, or gone) is one open finding until it is exported again', '1 day', true,
  'fn_table_export_unpageable_settle', 'scripts/sql/a_table_with_no_primary_key_is_refused_by_the_export_registry_and_never_stops_the_day.sql', 'it_engineer')
on conflict (duty) do nothing;

select case
  when not exists (select 1 from pg_trigger where tgname = 'table_export_registry_needs_a_key' and tgrelid = 'public.table_export_registry'::regclass)
    then 'PROBE FAILED: the registry has no primary-key trigger'
  when (select count(*) from public.fn_table_export_list()) + (select count(*) from public.fn_table_export_unpageable())
       <> (select count(*) from public.table_export_registry where exported)
    then 'PROBE FAILED: the export list and the skipped tables do not add up to the registry'
  else 'PROBE OK: ' || (select count(*) from public.fn_table_export_list()) || ' tables exported, '
       || (select count(*) from public.fn_table_export_unpageable()) || ' skipped and reported' end as verdict;
