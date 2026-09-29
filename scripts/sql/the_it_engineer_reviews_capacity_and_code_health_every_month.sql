-- THE IT ENGINEER REVIEWS CAPACITY AND CODE HEALTH EVERY MONTH.
--
-- Assigned: it_engineer.
--
-- WHAT WAS MEASURED, 28 Sep 2026 (production, read-only): the database is 11.27 GB against
-- it_threshold db_disk_limit_bytes 19,327,352,832 (18 GiB) - 58%, warn ratio cap_warn_ratio 0.8.
-- Supabase storage has cap_supabase_storage_bytes 100 GiB. SECURITY DEFINER routines in public with no
-- pinned search_path: 0. No seat_duty owned a monthly review of either; the daily db_health duty
-- watches disk moment to moment, but nothing looked at the month as a whole.
--
-- WHAT THIS ADDS: two monthly it_engineer seat duties run by fn_seat_duties_tick.
--   it_engineer.capacity_review - database size and storage bytes against their caps; raises when
--     either is past cap_warn_ratio.
--   it_engineer.code_health - the three mechanical defects the apply discipline names: a SECURITY
--     DEFINER routine in public with no pinned search_path, a public table with RLS on and no policy,
--     and a seat duty that has failed 3+ times in a row. One finding per class, carrying the names.
--
-- WHAT THIS DOES NOT DO: project growth (no size history is kept to project from), or read GitHub.
--
--   node scripts/apply_sql.mjs scripts/sql/the_it_engineer_reviews_capacity_and_code_health_every_month.sql --apply --ddl

create or replace function public.fn_it_engineer_capacity_review()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_warn numeric := coalesce(public.fn_it_threshold('cap_warn_ratio'), 0.8);
  v_db bigint := pg_database_size(current_database());
  v_db_cap numeric := public.fn_it_threshold('db_disk_limit_bytes');
  v_st bigint; v_st_cap numeric := public.fn_it_threshold('cap_supabase_storage_bytes');
  v_items jsonb := '[]'::jsonb;
begin
  select coalesce(sum((metadata->>'size')::bigint), 0) into v_st from storage.objects;
  if v_db_cap is null or v_db > v_db_cap * v_warn then
    v_items := v_items || jsonb_build_object('item', 'database', 'owner_seat', 'it_engineer', 'subject', 'capacity',
      'config', v_db_cap is null,
      'title', case when v_db_cap is null then 'No database size cap is recorded (it_threshold db_disk_limit_bytes)'
               else 'The database is ' || round(v_db / 1e9, 2) || ' GB, ' || round(100.0 * v_db / v_db_cap) || '% of its cap' end,
      'evidence', jsonb_build_object('bytes', v_db, 'cap_bytes', v_db_cap, 'warn_ratio', v_warn));
  end if;
  if v_st_cap is null or v_st > v_st_cap * v_warn then
    v_items := v_items || jsonb_build_object('item', 'storage', 'owner_seat', 'it_engineer', 'subject', 'capacity',
      'config', v_st_cap is null,
      'title', case when v_st_cap is null then 'No storage cap is recorded (it_threshold cap_supabase_storage_bytes)'
               else 'Storage holds ' || round(v_st / 1e9, 2) || ' GB, ' || round(100.0 * v_st / v_st_cap) || '% of its cap' end,
      'evidence', jsonb_build_object('bytes', v_st, 'cap_bytes', v_st_cap, 'warn_ratio', v_warn));
  end if;
  return jsonb_build_object('db_bytes', v_db, 'db_cap', v_db_cap, 'storage_bytes', v_st, 'storage_cap', v_st_cap,
                            'settled', public.fn_it_duty_settle('capacity_review', v_items));
end $fn$;
revoke execute on function public.fn_it_engineer_capacity_review() from public, anon, authenticated;

create or replace function public.fn_it_engineer_code_health()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_unpinned text[]; v_nopolicy text[]; v_failing text[]; v_items jsonb := '[]'::jsonb;
begin
  select coalesce(array_agg(p.oid::regprocedure::text order by 1), '{}') into v_unpinned
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search\_path=%');
  select coalesce(array_agg(c.relname::text order by 1), '{}') into v_nopolicy
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
     and not exists (select 1 from pg_policy pol where pol.polrelid = c.oid);
  select coalesce(array_agg(duty order by duty), '{}') into v_failing
    from public.seat_duty where enabled and failures >= 3;
  if cardinality(v_unpinned) > 0 then
    v_items := v_items || jsonb_build_object('item', 'search_path', 'owner_seat', 'it_engineer', 'subject', 'code_health',
      'title', cardinality(v_unpinned) || ' SECURITY DEFINER routine(s) in public have no pinned search_path',
      'evidence', jsonb_build_object('routines', to_jsonb(v_unpinned)));
  end if;
  if cardinality(v_nopolicy) > 0 then
    v_items := v_items || jsonb_build_object('item', 'rls_no_policy', 'owner_seat', 'it_engineer', 'subject', 'code_health',
      'title', cardinality(v_nopolicy) || ' public table(s) have RLS on and no policy',
      'evidence', jsonb_build_object('tables', to_jsonb(v_nopolicy)));
  end if;
  if cardinality(v_failing) > 0 then
    v_items := v_items || jsonb_build_object('item', 'failing_duties', 'owner_seat', 'it_engineer', 'subject', 'code_health',
      'title', cardinality(v_failing) || ' seat duty(ies) have failed 3 or more times in a row',
      'evidence', jsonb_build_object('duties', to_jsonb(v_failing)));
  end if;
  return jsonb_build_object('unpinned', cardinality(v_unpinned), 'rls_no_policy', cardinality(v_nopolicy),
                            'failing_duties', cardinality(v_failing), 'settled', public.fn_it_duty_settle('code_health', v_items));
end $fn$;
revoke execute on function public.fn_it_engineer_code_health() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file, enabled) values
  ('it_engineer.capacity_review', 'it_engineer', interval '30 days', 'fn_it_engineer_capacity_review',
   'Monthly: database size and storage bytes against it_threshold db_disk_limit_bytes / cap_supabase_storage_bytes at cap_warn_ratio',
   'scripts/sql/the_it_engineer_reviews_capacity_and_code_health_every_month.sql', true),
  ('it_engineer.code_health', 'it_engineer', interval '30 days', 'fn_it_engineer_code_health',
   'Monthly: SECURITY DEFINER routines without a pinned search_path, RLS tables without a policy, seat duties failing 3+ times',
   'scripts/sql/the_it_engineer_reviews_capacity_and_code_health_every_month.sql', true)
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what,
                                 owner_file = excluded.owner_file, enabled = excluded.enabled;

-- PROBE: a verdict row, no writes.
select case
  when (select count(*) from public.seat_duty where enabled and duty in ('it_engineer.capacity_review', 'it_engineer.code_health')) <> 2
    then 'PROBE FAILED: the two monthly duties are not scheduled'
  else 'PROBE OK' end as verdict;
