-- THE RESTORE DRILL PASSES ONLY ON ROWS IT ACTUALLY RESTORED.
--
-- Assigned: it_engineer (IT duty 19, restore_table). Readiness audit, 23 Sep 2026: "no restore has ever been tested".
--
-- MEASURED (23 Sep 2026, production htdblwldjkcgjvmqkbeh). The monthly drill exists and runs
-- (it_duty_schedule 'restore_table', every 30 days; it_restore_drill_result holds 2 rows) and it restores a page
-- of the newest finished export into a TEMP table (on commit drop), compares it with live and settles a finding.
-- But neither run ever restored a row:
--   #3  14 Sep  supplier_dues from 2026-09-07   restored 0   ok false
--   #70 15 Sep  quotes from 2026-09-15          restored 0   ok TRUE  (rows_in_file 0, live empty that day)
-- The only "pass" in its history is a vacuous one. Two causes:
--   1. THE PICK chose a table by pg_class.reltuples, which counts demo rows the export excludes (quotes: 3 live,
--      all demo; the export manifest says rows 0) and is -1 for a table never analysed. The export's own
--      manifest carries the row count of each table (table_export_run.manifest->'tables'->t->'rows'; leads 22,265
--      on 23 Sep), so the pick now prefers a table whose export page HAS rows.
--   2. THE RECORD passed a restore of zero rows when live was empty too. An empty restore proves nothing about the
--      backups, so it is now a failure with its own reason. A pass needs rows restored AND at least one
--      identical to live (the row counts go into it_restore_drill_result.detail either way).
-- Nothing else changes: the chain rebuild, the export age, the TEMP scratch table, the settle and the
-- heartbeat are byte-for-byte the canonical bodies in we_back_up_the_extra_stuff_only_unless_they_got_updated.sql.
--
-- Prevented by: scripts/checks/the_restore_drill_passes_only_on_rows_it_actually_restored.test.mjs and the
-- verdict-row probe at the end of this file.

create or replace function public.fn_it_restore_table_pick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_newest text; v_manifest jsonb; v_tab text; v_prev timestamptz;
  v_full date; v_chain_tab text; v_chain jsonb;
begin
  select max(started_at) into v_prev from public.agent_runs
   where agent = 'it_engineer' and counts->>'job' = 'restore_table_pick';
  if v_prev is not null and v_prev < now() - interval '1 hour'
     and not exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'duty:restore_table'
                      and started_at >= v_prev) then
    perform public.fn_it_engineer_finding_upsert('duty:restore_heartbeat:unrecorded',
      'The table restore drill started at ' || to_char(v_prev at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai and never recorded a result',
      'resilience_ping -> _shared/it_restore_drill.ts', 'monitor', 1,
      jsonb_build_object('duty', 'restore_heartbeat', 'owner_seat', 'ceo', 'subject', 'resilience_ping', 'picked_at', v_prev),
      '{}'::text[], array['why the edge tick stopped between the pick and the record: read resilience_ping''s logs'], 'it_engineer.restore_table');
  end if;
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('it_engineer', 'ok', now(), now(), jsonb_build_object('job', 'restore_table_pick'), null);

  select r.stamp::text, r.manifest into v_newest, v_manifest
    from public.table_export_run r where r.status = 'done' and r.manifest is not null
   order by r.stamp desc limit 1;
  if v_newest is null then            -- before #664's first finished day: the pre-7-Sep layout
    select max(split_part(o.name, '/', 1)) into v_newest
      from storage.objects o where o.bucket_id = 'backups' and o.name ~ '^\d{4}-\d{2}-\d{2}/';
  end if;

  -- ── the incremental chain, when there is one ──
  select max(r.stamp) into v_full from public.table_export_run r where r.kind = 'full' and r.status = 'done';
  if v_full is not null then
    select x.table_name into v_chain_tab
      from public.table_export_change_tracked x
      join storage.objects o on o.bucket_id = 'backups'
                           and o.name = to_char(v_full, 'YYYY-MM-DD') || '/' || x.table_name || '/page_0000.json'
     order by random() limit 1;
  end if;
  if v_chain_tab is not null then
    select jsonb_build_object(
      'table', v_chain_tab,
      'full_day', to_char(v_full, 'YYYY-MM-DD'),
      'base', to_char(v_full, 'YYYY-MM-DD') || '/' || v_chain_tab || '/page_0000.json',
      'increments', coalesce((select jsonb_agg(o.name order by o.name)
                                from public.table_export_run r
                                join storage.objects o on o.bucket_id = 'backups'
                                 and o.name like r.stamp::text || '/' || v_chain_tab || '/page\_%.json'
                               where r.status = 'done' and r.stamp > v_full), '[]'::jsonb),
      'changes', coalesce((select jsonb_agg(o.name order by o.name)
                             from public.table_export_run r
                             join storage.objects o on o.bucket_id = 'backups'
                              and o.name like r.stamp::text || '/table_export_change/page\_%.json'
                            where r.status = 'done' and r.stamp > v_full), '[]'::jsonb))
      into v_chain;
  end if;

  select t.table_name into v_tab
    from public.it_restore_drill_table t
    join storage.objects o on o.bucket_id = 'backups' and o.name = v_newest || '/' || t.table_name || '/page_0000.json'
    left join pg_class pc on pc.oid = to_regclass('public.' || t.table_name)
   where v_manifest is null
      or (v_manifest->'tables' ? t.table_name
          and coalesce(v_manifest->'tables'->t.table_name->>'mode', 'full') not like 'changes_since%')
   -- 23 Sep 2026: a page the export says has rows first; reltuples counts demo rows the export excludes.
   order by coalesce((v_manifest->'tables'->t.table_name->>'rows') ~ '^[1-9][0-9]*$', false) desc,
            (coalesce(pc.reltuples, 0) > 0) desc, random() limit 1;
  return jsonb_build_object('newest_export_day', v_newest,
    'sample_rows', coalesce(public.fn_it_threshold('restore_table_sample_rows'), 50),
    'chain', v_chain,
    'table', case when v_tab is not null
                  then jsonb_build_object('table', v_tab, 'path', v_newest || '/' || v_tab || '/page_0000.json', 'day', v_newest) end);
end $fn$;
revoke execute on function public.fn_it_restore_table_pick() from public, anon, authenticated;
create or replace function public.fn_it_restore_table_record(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  t jsonb := p->'table'; v_items jsonb := '[]'::jsonb; v_key text; v_tab text := p->'table'->>'table';
  n_rest int := 0; n_match int := 0; n_changed int := 0; n_missing int := 0; v_err text; v_age int; v_max int;
  v_ok boolean; v_detail jsonb; v_out jsonb; v_drop text[]; v_full date; v_last date; v_gaps text; v_live_empty boolean;
  c jsonb := p->'chain'; v_rebuild jsonb; v_rebuild_ok boolean := true;
begin
  if jsonb_typeof(p) is distinct from 'object' then
    raise exception 'fn_it_restore_table_record takes the drill reading from _shared/it_restore_drill.ts';
  end if;

  -- ── THE AGE OF THE NEWEST FINISHED EXPORT ──
  v_max := coalesce(public.fn_it_threshold('restore_export_max_age_days'), 2)::int;
  v_age := current_date - (p->>'newest_export_day')::date;
  if v_age is null or v_age > v_max then
    v_items := v_items || jsonb_build_object('item', 'export_stale', 'owner_seat', 'ceo', 'subject', 'table_backup',
      'title', case when v_age is null then 'There is no finished table export in the backups bucket at all'
                    else 'The newest finished table backup is from ' || (p->>'newest_export_day') || ' (' || v_age || ' days old)' end,
      'blast', 'agent_facing', 'affected', 1,
      'evidence', jsonb_build_object('newest_export_day', p->>'newest_export_day', 'age_days', v_age, 'max_age_days', v_max,
        'writer', 'supabase/functions/backup, claimed by resilience_ping through fn_table_export_due'));
  end if;

  -- ── THE CHAIN: the latest full day plus every day after it ──
  if exists (select 1 from public.table_export_run) then
    select max(stamp) into v_full from public.table_export_run where kind = 'full' and status = 'done';
    select max(stamp) into v_last from public.table_export_run where status = 'done';
    if v_full is null or v_full < current_date - 7 then
      v_items := v_items || jsonb_build_object('item', 'full_copy_stale', 'owner_seat', 'ceo', 'subject', 'table_backup',
        'title', 'the change-tracked tables have no finished full copy in the last 7 days' || coalesce(' (the last is ' || v_full || ')', ''),
        'blast', 'agent_facing', 'affected', 1, 'evidence', jsonb_build_object('last_full_day', v_full));
    else
      select string_agg(d::date::text, ', ' order by d) into v_gaps
        from generate_series(v_full, v_last, interval '1 day') d
       where not exists (select 1 from public.table_export_run r where r.stamp = d::date and r.status = 'done');
      if v_gaps is not null then
        v_items := v_items || jsonb_build_object('item', 'chain_broken', 'owner_seat', 'ceo', 'subject', 'table_backup',
          'title', 'a change-tracked table restores only from the full copy of ' || v_full || ' plus every later day, and ' || v_gaps || ' did not finish',
          'blast', 'agent_facing', 'affected', 1,
          'evidence', jsonb_build_object('last_full_day', v_full, 'last_done_day', v_last, 'missing_or_failed', v_gaps));
      end if;
    end if;
  end if;

  -- ── THE REBUILD FROM BASE + INCREMENTS + DELETES ──
  if c is not null and jsonb_typeof(c) = 'object' then
    if c->>'error' is not null then
      v_rebuild := jsonb_build_object('table', c->>'table', 'error', c->>'error');
      v_rebuild_ok := false;
    else
      begin
        v_rebuild := public.fn_table_export_replay(c->>'table', coalesce(c->'base_rows', '[]'::jsonb),
                                                   coalesce(c->'increment_rows', '[]'::jsonb),
                                                   coalesce(c->'change_rows', '[]'::jsonb));
      exception when others then
        v_rebuild := jsonb_build_object('table', c->>'table', 'error', 'the rebuild failed: ' || sqlerrm);
      end;
      v_rebuild_ok := coalesce((v_rebuild->>'rebuilt')::int, 0) > 0
                  and coalesce((v_rebuild->>'lost_rows')::int, 1) = 0
                  and v_rebuild->>'error' is null;
    end if;
    v_rebuild := v_rebuild || jsonb_build_object('full_day', c->>'full_day', 'base', c->>'base',
                                                 'increment_files', c->'increments', 'change_files', c->'changes');
    if not v_rebuild_ok then
      v_items := v_items || jsonb_build_object('item', 'rebuild', 'owner_seat', 'ceo', 'subject', 'table_backup',
        'title', 'The restore drill could not rebuild ' || coalesce(c->>'table', 'a change-tracked table')
                 || ' from its full copy of ' || coalesce(c->>'full_day', '?') || ' plus the later days'
                 || coalesce(': ' || (v_rebuild->>'error'),
                      ' (' || coalesce(v_rebuild->>'lost_rows', '?') || ' live row(s) in the rebuilt key window are in no backup file)'),
        'blast', 'agent_facing', 'affected', 1, 'evidence', v_rebuild);
    end if;
  end if;

  -- ── THE SINGLE FULL PAGE RESTORED INTO SCRATCH ──
  select key_column into v_key from public.it_restore_drill_table where table_name = v_tab;
  if t is null or v_tab is null then
    v_err := 'no full-copy page_0000.json of any table in it_restore_drill_table in the newest finished export';
  elsif v_key is null then
    v_err := v_tab || ' is not in it_restore_drill_table';
  elsif t->>'error' is not null then
    v_err := t->>'error';
  else
    select coalesce(array_agg(c2.column_name::text), '{}') into v_drop
      from information_schema.columns c2
     where c2.table_schema = 'public' and c2.table_name = v_tab
       and not (coalesce(t->'rows'->0, '{}'::jsonb) ? c2.column_name);
    begin
      execute format('create temp table it_restore_scratch (like public.%I) on commit drop', v_tab);
      execute format('insert into it_restore_scratch select * from jsonb_populate_recordset(null::public.%I, $1)', v_tab)
        using coalesce(t->'rows', '[]'::jsonb);
      get diagnostics n_rest = row_count;
      execute format(
        'select count(*) filter (where l.%1$I is not null and (to_jsonb(l) - $1) = (to_jsonb(s) - $1)),
                count(*) filter (where l.%1$I is not null and (to_jsonb(l) - $1) <> (to_jsonb(s) - $1)),
                count(*) filter (where l.%1$I is null)
           from it_restore_scratch s left join public.%2$I l on l.%1$I = s.%1$I', v_key, v_tab)
        into n_match, n_changed, n_missing using v_drop;
      drop table it_restore_scratch;
    exception when others then v_err := 'restore into scratch failed: ' || sqlerrm;
    end;
  end if;
  if v_err is null and n_rest = 0 and v_key is not null then
    if coalesce((t->>'rows_in_file')::int, -1) = 0 then
      -- 23 Sep 2026: an empty page restores nothing, so it proves nothing -- a failure, not a pass.
      execute format('select not exists (select 1 from public.%I)', v_tab) into v_live_empty;
      v_err := 'the picked page of ' || v_tab || ' holds 0 rows, so nothing was restored and nothing was proved'
               || case when v_live_empty then ' (live is empty too)' else '' end;
    else
      v_err := 'the export holds ' || coalesce(t->>'rows_in_file', 'an unknown number of') || ' row(s) and none reached the restore';
    end if;
  end if;
  v_ok := v_err is null and n_rest > 0 and n_match > 0;
  v_detail := jsonb_build_object('table', v_tab, 'path', t->>'path', 'rows_in_file', t->'rows_in_file', 'restored', n_rest,
                                 'identical_to_live', n_match, 'changed_since_export', n_changed, 'gone_from_live', n_missing,
                                 'not_compared', to_jsonb(v_drop), 'error', v_err,
                                 'newest_export_day', p->>'newest_export_day', 'age_days', v_age,
                                 'last_full_day', v_full, 'chain_gaps', v_gaps, 'rebuild', v_rebuild);
  insert into public.it_restore_drill_result (subject, ok, detail)
  values (coalesce(v_tab, 'no table') || coalesce(' from ' || (t->>'path'), ''), v_ok and v_rebuild_ok and jsonb_array_length(v_items) = 0, v_detail);
  if not v_ok then
    v_items := v_items || jsonb_build_object('item', 'restore', 'owner_seat', 'ceo', 'subject', 'table_backup',
      'title', 'The monthly restore drill could not restore a table sample' || coalesce(' of ' || v_tab, '') || ': '
               || coalesce(v_err, n_rest || ' row(s) restored and none identical to live (' || n_changed || ' changed, ' || n_missing || ' gone)'),
      'blast', 'agent_facing', 'affected', 1, 'evidence', v_detail);
  end if;

  v_out := jsonb_build_object('restore_table', public.fn_it_duty_settle('restore_table', v_items), 'drill', v_detail);
  perform public.fn_it_engineer_finding_close('duty:restore_heartbeat:unrecorded', 'the table restore drill recorded a result');
  perform public.fn_it_duty_ran('restore_table', v_out);
  return v_out;
end $fn$;
revoke execute on function public.fn_it_restore_table_record(jsonb) from public, anon, authenticated;

-- PROBE (this file defines routines, so no raise and no call that writes: fn_it_restore_table_pick logs a pick
-- the next run would report as unrecorded, and fn_it_restore_table_record writes a drill result. Their behaviour
-- is proved in an aborted transaction by the test named above.)
select case
  when has_function_privilege('anon', 'public.fn_it_restore_table_pick()', 'execute')
    or has_function_privilege('anon', 'public.fn_it_restore_table_record(jsonb)', 'execute')
    then 'PROBE FAILED: anon can execute a restore drill routine'
  when not exists (select 1 from public.table_export_run r
                     join public.it_restore_drill_table t on coalesce((r.manifest->'tables'->t.table_name->>'rows')::bigint, 0) > 0
                    where r.status = 'done' and r.stamp = (select max(stamp) from public.table_export_run where status = 'done'))
    then 'PROBE FAILED: the newest finished export has no drill table with rows, so the drill would fail every month'
  else 'PROBE OK' end as verdict;
