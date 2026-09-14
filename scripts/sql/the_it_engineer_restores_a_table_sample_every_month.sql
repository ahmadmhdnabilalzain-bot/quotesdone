-- THE IT ENGINEER RESTORES A TABLE SAMPLE EVERY MONTH, AND CHECKS THE BACKUP CHAIN IS WHOLE.
--
-- Assigned: it_engineer (the drill, the record, the re-check). Failures go to the ceo, round the IT loop
-- (the_it_engineer_closes_every_loop_it_opens.sql); only if nothing in the company closes them does the
-- founder get ONE plain-English email (kind it_new_bug, sent by customer_support).
--
-- Founder, 14 Sep 2026, approving IT duty 19 ("add all for accountant and IT"): once a month restore one real
-- backed-up file (the private bucket 'backups' and its Dropbox copy) and one table sample into a scratch
-- area, confirm they open and match, and record the result. No model call anywhere.
--
-- THE FILE HALF IS DUTY 9's DRILL, MADE STRICTER, NOT A SECOND DRILL (the_it_engineer_takes_on_seven_more_
-- duties.sql and _shared/it_scheduled_readings.ts): each copy must OPEN, and the storage copy must hash equal
-- to the Dropbox copy.
--
-- THE TABLE HALF READS THE DAILY EXPORT #664 REVIVED (every_business_table_is_exported_every_day_again.sql,
-- supabase/functions/backup): <YYYY-MM-DD>/<table>/page_NNNN.json (a JSON array of rows, vector columns
-- stripped, demo rows excluded) and <YYYY-MM-DD>/_manifest.json, written only when the day finished.
-- public.table_export_run holds one row per Dubai day: status 'done' and the manifest once finished.
--   pick     the newest day marked done (before #664, the newest dated folder in storage, which is how the
--            pre-7-Sep exports were laid out), and a table from it_restore_drill_table that the manifest
--            lists as a FULL copy - a 'changes_since' page holds only that day's changes and restores
--            nothing on its own.
--   restore  page_0000.json into a TEMP table built LIKE the live one (the scratch area, dropped when the
--            transaction ends) with jsonb_populate_recordset, then compared row by row with live on the key,
--            over the columns the export carries (vector columns are stripped, so they are not compared).
--            It passes when rows were restored and at least one is identical to live; rows changed since
--            are counted, not failed, because the company kept working after the export.
--   age      the newest finished day must be at most restore_export_max_age_days old.
--   chain    kb_chunks is a full copy on 'full' days and only its changes on 'incremental' days, so it can be
--            restored only from the latest full day plus EVERY later day. Once table_export_run has rows,
--            there must be a full day inside 7 days and no missing or failed day after it.
-- Every run is a row of it_restore_drill_result and settles duty 'restore_table': a drill that could not
-- run is itself a failure.
--
-- CADENCE: it_duty_schedule 'restore_table', every 30 days; while a restore_table finding is open, again
-- after 20 hours so the re-check can close a fixed finding the next day. A drill that picked and never
-- recorded (the edge tick died) is a monitor finding before the next pick.

create table if not exists public.it_restore_drill_table (
  table_name  text primary key check (table_name ~ '^[a-z_][a-z0-9_]*$'),
  key_column  text not null check (key_column ~ '^[a-z_][a-z0-9_]*$'),
  note        text not null check (btrim(note) <> '')
);
comment on table public.it_restore_drill_table is
  'The tables the monthly restore drill may restore from the dated JSON exports in the backups bucket, and the key it compares on. Data, not code: the dynamic SQL in fn_it_restore_table_record only ever names a table listed here.';
alter table public.it_restore_drill_table enable row level security;
drop policy if exists it_restore_drill_table_service_role_only on public.it_restore_drill_table;
create policy it_restore_drill_table_service_role_only on public.it_restore_drill_table as permissive for all to public using (false) with check (false);
revoke all on public.it_restore_drill_table from anon, authenticated;

insert into public.it_restore_drill_table (table_name, key_column, note) values
  ('pricing_config', 'id', 'the prices every quote is computed from'),
  ('customers',      'id', 'who the customers are'),
  ('leads',          'id', 'the supplier pool'),
  ('inquiries',      'id', 'what customers asked for'),
  ('quotes',         'id', 'what suppliers offered'),
  ('transactions',   'id', 'every reveal that was paid for'),
  ('supplier_dues',  'id', 'what suppliers owe')
on conflict (table_name) do update set key_column = excluded.key_column, note = excluded.note;

create table if not exists public.it_restore_drill_result (
  id       bigserial primary key,
  ran_at   timestamptz not null default now(),
  subject  text not null,
  ok       boolean not null,
  detail   jsonb not null default '{}'::jsonb
);
comment on table public.it_restore_drill_result is
  'One row per monthly table restore drill (IT duty 19): what was restored, whether it matched live, the age of the newest finished export and whether the kb_chunks chain is whole. Kept, never pruned.';
alter table public.it_restore_drill_result enable row level security;
drop policy if exists it_restore_drill_result_service_role_only on public.it_restore_drill_result;
create policy it_restore_drill_result_service_role_only on public.it_restore_drill_result as permissive for all to public using (false) with check (false);
revoke all on public.it_restore_drill_result from anon, authenticated;

insert into public.it_threshold (key, value, unit, basis) values
  ('restore_export_max_age_days', 2,  'days', 'The table export is written every Dubai day after 03:00; two days without a finished one means it has stopped.'),
  ('restore_table_sample_rows',   50, 'rows', 'Enough rows to show that the export restores and matches, few enough to pass through one RPC.')
on conflict (key) do update set value = excluded.value, unit = excluded.unit, basis = excluded.basis;

insert into public.it_duty_schedule (duty, every, note) values
  ('restore_table', interval '30 days', 'duty 19: one table page from the newest finished export restored into scratch and compared with live; the export''s age and the kb_chunks chain')
on conflict (duty) do update set every = excluded.every, note = excluded.note;

create or replace function public.fn_it_restore_table_due()
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select ('restore_table' = any (public.fn_it_scheduled_due())
          or (exists (select 1 from public.it_engineer_finding where closed_at is null and issue_key like 'duty:restore\_table:%')
              and (not exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'duty:restore_table'
                                and started_at > now() - interval '20 hours')
                   -- a finished export newer than the one the last drill read: re-check at once, so a
                   -- stale-export finding closes the tick after the export lands, inside the loop's window
                   or exists (select 1 from public.table_export_run r
                               where r.status = 'done' and r.stamp::text > coalesce(
                                 (select d.detail->>'newest_export_day' from public.it_restore_drill_result d order by d.id desc limit 1), '')))))
     and not exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'restore_table_pick'
                      and started_at > now() - interval '6 hours')
$fn$;
revoke execute on function public.fn_it_restore_table_due() from public, anon, authenticated;

create or replace function public.fn_it_restore_table_pick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_newest text; v_manifest jsonb; v_tab text; v_prev timestamptz;
begin
  -- A previous pick with no recorded drill after it: the edge tick died between the two.
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
  select t.table_name into v_tab
    from public.it_restore_drill_table t
    join storage.objects o on o.bucket_id = 'backups' and o.name = v_newest || '/' || t.table_name || '/page_0000.json'
    left join pg_class pc on pc.oid = to_regclass('public.' || t.table_name)
   where v_manifest is null
      or (v_manifest->'tables' ? t.table_name
          and coalesce(v_manifest->'tables'->t.table_name->>'mode', 'full') not like 'changes_since%')
   -- A table with rows first: the first live drill (14 Sep 2026) drew supplier_dues, empty, and had
   -- nothing to compare.
   order by (coalesce(pc.reltuples, 0) > 0) desc, random() limit 1;
  return jsonb_build_object('newest_export_day', v_newest,
    'sample_rows', coalesce(public.fn_it_threshold('restore_table_sample_rows'), 50),
    'table', case when v_tab is not null
                  then jsonb_build_object('table', v_tab, 'path', v_newest || '/' || v_tab || '/page_0000.json', 'day', v_newest) end);
end $fn$;
revoke execute on function public.fn_it_restore_table_pick() from public, anon, authenticated;

-- p: {newest_export_day, table:{table, path, day, rows:[...], rows_in_file, error}} from runRestoreTable.
create or replace function public.fn_it_restore_table_record(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  t jsonb := p->'table'; v_items jsonb := '[]'::jsonb; v_key text; v_tab text := p->'table'->>'table';
  n_rest int := 0; n_match int := 0; n_changed int := 0; n_missing int := 0; v_err text; v_age int; v_max int;
  v_ok boolean; v_detail jsonb; v_out jsonb; v_drop text[]; v_full date; v_last date; v_gaps text; v_live_empty boolean;
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

  -- ── THE kb_chunks CHAIN: the latest full day plus every day after it ──
  if exists (select 1 from public.table_export_run) then
    select max(stamp) into v_full from public.table_export_run where kind = 'full' and status = 'done';
    select max(stamp) into v_last from public.table_export_run where status = 'done';
    if v_full is null or v_full < current_date - 7 then
      v_items := v_items || jsonb_build_object('item', 'full_copy_stale', 'owner_seat', 'ceo', 'subject', 'table_backup',
        'title', 'kb_chunks has no finished full copy in the last 7 days' || coalesce(' (the last is ' || v_full || ')', ''),
        'blast', 'agent_facing', 'affected', 1, 'evidence', jsonb_build_object('last_full_day', v_full));
    else
      select string_agg(d::date::text, ', ' order by d) into v_gaps
        from generate_series(v_full, v_last, interval '1 day') d
       where not exists (select 1 from public.table_export_run r where r.stamp = d::date and r.status = 'done');
      if v_gaps is not null then
        v_items := v_items || jsonb_build_object('item', 'chain_broken', 'owner_seat', 'ceo', 'subject', 'table_backup',
          'title', 'kb_chunks restores only from the full copy of ' || v_full || ' plus every later day, and ' || v_gaps || ' did not finish',
          'blast', 'agent_facing', 'affected', 1,
          'evidence', jsonb_build_object('last_full_day', v_full, 'last_done_day', v_last, 'missing_or_failed', v_gaps));
      end if;
    end if;
  end if;

  -- ── THE RESTORE INTO SCRATCH ──
  select key_column into v_key from public.it_restore_drill_table where table_name = v_tab;
  if t is null or v_tab is null then
    v_err := 'no full-copy page_0000.json of any table in it_restore_drill_table in the newest finished export';
  elsif v_key is null then
    v_err := v_tab || ' is not in it_restore_drill_table';
  elsif t->>'error' is not null then
    v_err := t->>'error';
  else
    -- Only the columns the export carries are compared: vector columns are stripped at export.
    select coalesce(array_agg(c.column_name::text), '{}') into v_drop
      from information_schema.columns c
     where c.table_schema = 'public' and c.table_name = v_tab
       and not (coalesce(t->'rows'->0, '{}'::jsonb) ? c.column_name);
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
  -- An empty restore passes only when the EXPORT says the table was empty (rows_in_file is the whole
  -- file's count, taken before the sample) AND the table is empty live. Review of e820d64: judged on the
  -- live table alone, an export that lost its rows would pass as soon as the table was emptied too.
  if v_err is null and n_rest = 0 and v_key is not null then
    if coalesce((t->>'rows_in_file')::int, -1) = 0 then
      execute format('select not exists (select 1 from public.%I)', v_tab) into v_live_empty;
    else
      v_err := 'the export holds ' || coalesce(t->>'rows_in_file', 'an unknown number of') || ' row(s) and none reached the restore';
    end if;
  end if;
  v_ok := v_err is null and ((n_rest > 0 and n_match > 0) or coalesce(v_live_empty, false));
  v_detail := jsonb_build_object('table', v_tab, 'path', t->>'path', 'rows_in_file', t->'rows_in_file', 'restored', n_rest,
                                 'identical_to_live', n_match, 'changed_since_export', n_changed, 'gone_from_live', n_missing,
                                 'not_compared', to_jsonb(v_drop), 'error', v_err,
                                 'newest_export_day', p->>'newest_export_day', 'age_days', v_age,
                                 'last_full_day', v_full, 'chain_gaps', v_gaps);
  insert into public.it_restore_drill_result (subject, ok, detail)
  values (coalesce(v_tab, 'no table') || coalesce(' from ' || (t->>'path'), ''), v_ok and jsonb_array_length(v_items) = 0, v_detail);
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
