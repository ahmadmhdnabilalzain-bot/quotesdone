-- PROBE for a_table_with_no_primary_key_is_refused_by_the_export_registry_and_never_stops_the_day.sql (16 Nov 2026). Run after
-- the file in the same query: an aborted transaction, no DDL, ends in raise exception CHK<<...>>, so nothing commits.
-- ZZ DEMO names only; no real registry row is changed. Proves:
--   1. REFUSED: registering as exported a relation that has no primary key (a view stands in for a keyless table: same
--      fn_table_export_pageable answer, no DDL) raises, and the registry is unchanged;
--   2. SKIPPED AND REPORTED: a registered table the export cannot page (here one that does not exist) is left out of
--      fn_table_export_list, every other exported table stays in it, fn_table_export_unpageable names it with the reason,
--      and the daily duty opens ONE finding for it, closed again once it is no longer registered;
--   3. a real exported table with a key is still listed.
do $probe$
declare v_fail text := ''; v_view text; v_before int; v_list int; v_reg int; v_refused boolean := false; v jsonb;
begin
  select count(*) into v_before from public.table_export_registry;
  -- 1.
  select c.relname into v_view from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'v' order by c.relname limit 1;
  if v_view is null then v_fail := v_fail || ' no view to stand in for a keyless table;';
  else
    begin
      insert into public.table_export_registry (table_name, exported, category, reason, added_by)
      values (v_view, true, 'zz_demo', 'ZZ DEMO probe: a relation with no primary key', 'probe')
      on conflict (table_name) do update set exported = true;
    exception when check_violation then v_refused := sqlerrm like '%cannot be exported%';   -- the trigger's refusal, not another check
    end;
    if not v_refused then v_fail := v_fail || ' a relation with no primary key was registered as exported;'; end if;
  end if;
  if (select count(*) from public.table_export_registry) <> v_before then v_fail := v_fail || ' the registry changed after a refusal;'; end if;

  -- 2.
  insert into public.table_export_registry (table_name, exported, category, reason, added_by)
  values ('zz_demo_export_probe_gone', true, 'zz_demo', 'ZZ DEMO probe: registered, never created', 'probe');
  select count(*) into v_list from public.fn_table_export_list();
  select count(*) into v_reg from public.table_export_registry r where r.exported;
  if exists (select 1 from public.fn_table_export_list() x where x.table_name = 'zz_demo_export_probe_gone') then v_fail := v_fail || ' the unpageable table is still in the export list;'; end if;
  if v_list <> v_reg - (select count(*) from public.fn_table_export_unpageable()) then v_fail := v_fail || format(' list %s of %s exported rows;', v_list, v_reg); end if;
  if not exists (select 1 from public.fn_table_export_unpageable() u where u.table_name = 'zz_demo_export_probe_gone' and u.reason like '%does not exist%')
    then v_fail := v_fail || ' the skipped table is not reported with its reason;'; end if;
  v := public.fn_table_export_unpageable_settle();
  perform public.fn_table_export_unpageable_settle();   -- a second run: still one finding, not two
  if (select count(*) from public.it_engineer_finding where issue_key = 'table_export:unpageable:zz_demo_export_probe_gone' and closed_at is null) <> 1
    then v_fail := v_fail || ' not exactly one open finding for the skipped table;'; end if;
  delete from public.table_export_registry where table_name = 'zz_demo_export_probe_gone';
  perform public.fn_table_export_unpageable_settle();
  if exists (select 1 from public.it_engineer_finding where issue_key = 'table_export:unpageable:zz_demo_export_probe_gone' and closed_at is null)
    then v_fail := v_fail || ' the finding did not close once the table was no longer registered;'; end if;

  -- 3.
  if not exists (select 1 from public.fn_table_export_list() x where x.table_name = 'table_export_registry')
     and exists (select 1 from public.table_export_registry where table_name = 'table_export_registry' and exported)
    then v_fail := v_fail || ' a keyed exported table fell out of the list;'; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK refused=' || v_refused || ' listed=' || v_list || ' of ' || v_reg || ' settle=' || v::text
                                   else 'PROBE FAILED:' || v_fail end;
end $probe$;
