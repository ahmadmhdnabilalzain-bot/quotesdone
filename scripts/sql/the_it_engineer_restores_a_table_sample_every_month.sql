-- THE IT ENGINEER RESTORES A TABLE SAMPLE EVERY MONTH, AND SAYS HOW OLD THE TABLE BACKUP IS.
--
-- Assigned: it_engineer (the drill, the record, the re-check). A failed table restore and a stale table
-- export go to the ceo, because no seat owns the table export (see below). Both go round the IT loop
-- (the_it_engineer_closes_every_loop_it_opens.sql); only if nothing in the company closes them does the
-- founder get ONE plain-English email (kind it_new_bug, sent by customer_support).
--
-- Founder, 14 Sep 2026, approving IT duty 19 ("add all for accountant and IT"): once a month restore one real
-- backed-up file (the private bucket 'backups' and its Dropbox copy) and one table sample into a scratch
-- area, confirm they open and match, and record the result. No model call anywhere.
--
-- THE FILE HALF IS DUTY 9's DRILL, MADE STRICTER, NOT A SECOND DRILL. Every 30 days
-- fn_it_duties_scheduled (the_it_engineer_takes_on_seven_more_duties.sql) downloads a random sample of
-- backed-up files from Dropbox and from storage and compares them with doc_backups. Duty 19 added two
-- tests to that same sample, in _shared/it_scheduled_readings.ts and the 9a check: each copy must OPEN
-- (a PDF starts %PDF- and ends %%EOF; JSON parses), and the storage copy's content hash must equal the
-- Dropbox copy's.
--
-- THE TABLE HALF IS THIS FILE. MEASURED BEFORE WRITING (14 Sep 2026, production): the 'backups' bucket
-- holds 5,477 objects (about 13 GB), and among them daily JSON exports of 20 tables under
-- <YYYY-MM-DD>/<table>/page_NNNN.json (and <table>.json before 12 Aug), from 23 Jun to 7 Sep 2026.
-- NOTHING IN THIS REPOSITORY WRITES THEM: the newest is 2026-09-07 and no function, script or workflow
-- names that path shape. Their writer went with the 7 Sep removal. So the drill also reports how old the
-- newest export is, and on the day this lands that is a finding. Every table in the drill list keys on
-- id (information_schema, the same day).
--
-- THE DRILL (resilience_ping -> fn_it_restore_table_due -> _pick -> _shared/it_restore_drill.ts -> _record):
--   page_0000.json of one table from the newest dated export is downloaded and opened, and its first
--   restore_table_sample_rows rows are restored into a TEMP table built LIKE the live one (the scratch
--   area, dropped when the transaction ends) with jsonb_populate_recordset, then compared row by row with
--   the live table on its key. It passes when rows were restored and at least one is identical to live;
--   rows changed since the export are counted, not failed, because the company kept working after it.
--   The newest export must be at most restore_export_max_age_days old.
-- Every run is a row of it_restore_drill_result and settles duty 'restore_table', because a drill that
-- could not run is itself a failure.
--
-- CADENCE: public.it_duty_schedule 'restore_table', every 30 days; while a restore_table finding is open,
-- again after 20 hours, so the IT engineer's re-check can close a fixed finding the next day. A drill that
-- picked and never recorded (the edge function died) is a monitor finding before the next pick.

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
  'One row per monthly table restore drill (IT duty 19): what was restored, whether it matched live, and the age of the newest table export. Kept, never pruned.';
alter table public.it_restore_drill_result enable row level security;
drop policy if exists it_restore_drill_result_service_role_only on public.it_restore_drill_result;
create policy it_restore_drill_result_service_role_only on public.it_restore_drill_result as permissive for all to public using (false) with check (false);
revoke all on public.it_restore_drill_result from anon, authenticated;

insert into public.it_threshold (key, value, unit, basis) values
  ('restore_export_max_age_days', 2,  'days', 'The dated table exports were written every day until 7 Sep 2026; two days without one means their writer has stopped.'),
  ('restore_table_sample_rows',   50, 'rows', 'Enough rows to show that the export restores and matches, few enough to pass through one RPC.')
on conflict (key) do update set value = excluded.value, unit = excluded.unit, basis = excluded.basis;

insert into public.it_duty_schedule (duty, every, note) values
  ('restore_table', interval '30 days', 'duty 19: one table page from the newest dated export restored into scratch and compared with live, and that export''s age')
on conflict (duty) do update set every = excluded.every, note = excluded.note;

create or replace function public.fn_it_restore_table_due()
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select ('restore_table' = any (public.fn_it_scheduled_due())
          or (exists (select 1 from public.it_engineer_finding where closed_at is null and issue_key like 'duty:restore\_table:%')
              and not exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'duty:restore_table'
                               and started_at > now() - interval '20 hours')))
     and not exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'restore_table_pick'
                      and started_at > now() - interval '6 hours')
$fn$;
revoke execute on function public.fn_it_restore_table_due() from public, anon, authenticated;

create or replace function public.fn_it_restore_table_pick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_newest text; v_tab record; v_prev timestamptz;
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

  select max(split_part(o.name, '/', 1)) into v_newest
    from storage.objects o where o.bucket_id = 'backups' and o.name ~ '^\d{4}-\d{2}-\d{2}/';
  select t.table_name, o.name into v_tab
    from public.it_restore_drill_table t
    join storage.objects o on o.bucket_id = 'backups' and o.name = v_newest || '/' || t.table_name || '/page_0000.json'
   order by random() limit 1;
  return jsonb_build_object('newest_export_day', v_newest,
    'sample_rows', coalesce(public.fn_it_threshold('restore_table_sample_rows'), 50),
    'table', case when v_tab.table_name is not null
                  then jsonb_build_object('table', v_tab.table_name, 'path', v_tab.name, 'day', v_newest) end);
end $fn$;
revoke execute on function public.fn_it_restore_table_pick() from public, anon, authenticated;

-- p: {newest_export_day, table:{table, path, day, rows:[...], rows_in_file, error}} from runRestoreTable.
create or replace function public.fn_it_restore_table_record(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  t jsonb := p->'table'; v_items jsonb := '[]'::jsonb; v_key text; v_tab text := p->'table'->>'table';
  n_rest int := 0; n_match int := 0; n_changed int := 0; n_missing int := 0; v_err text; v_age int; v_max int;
  v_ok boolean; v_detail jsonb; v_out jsonb;
begin
  if jsonb_typeof(p) is distinct from 'object' then
    raise exception 'fn_it_restore_table_record takes the drill reading from _shared/it_restore_drill.ts';
  end if;

  -- ── THE AGE OF THE NEWEST EXPORT ──
  v_max := coalesce(public.fn_it_threshold('restore_export_max_age_days'), 2)::int;
  v_age := current_date - (p->>'newest_export_day')::date;
  if v_age is null or v_age > v_max then
    v_items := v_items || jsonb_build_object('item', 'export_stale', 'owner_seat', 'ceo', 'subject', 'table_backup',
      'title', case when v_age is null then 'There is no dated table export in the backups bucket at all'
                    else 'The newest table backup in the backups bucket is from ' || (p->>'newest_export_day') || ' (' || v_age
                         || ' days old); nothing has written one since' end,
      'blast', 'agent_facing', 'affected', 1,
      'evidence', jsonb_build_object('newest_export_day', p->>'newest_export_day', 'age_days', v_age, 'max_age_days', v_max,
        'note', 'no function, script or workflow in the repository writes <YYYY-MM-DD>/<table>/page_NNNN.json; its writer went with the 7 Sep 2026 removal'));
  end if;

  -- ── THE RESTORE INTO SCRATCH ──
  select key_column into v_key from public.it_restore_drill_table where table_name = v_tab;
  if t is null or v_tab is null then
    v_err := 'no page_0000.json of any table in it_restore_drill_table in the newest export';
  elsif v_key is null then
    v_err := v_tab || ' is not in it_restore_drill_table';
  elsif t->>'error' is not null then
    v_err := t->>'error';
  else
    begin
      execute format('create temp table it_restore_scratch (like public.%I) on commit drop', v_tab);
      execute format('insert into it_restore_scratch select * from jsonb_populate_recordset(null::public.%I, $1)', v_tab)
        using coalesce(t->'rows', '[]'::jsonb);
      get diagnostics n_rest = row_count;
      execute format(
        'select count(*) filter (where l.%1$I is not null and to_jsonb(l) = to_jsonb(s)),
                count(*) filter (where l.%1$I is not null and to_jsonb(l) <> to_jsonb(s)),
                count(*) filter (where l.%1$I is null)
           from it_restore_scratch s left join public.%2$I l on l.%1$I = s.%1$I', v_key, v_tab)
        into n_match, n_changed, n_missing;
      drop table it_restore_scratch;
    exception when others then v_err := 'restore into scratch failed: ' || sqlerrm;
    end;
  end if;
  v_ok := v_err is null and n_rest > 0 and n_match > 0;
  v_detail := jsonb_build_object('table', v_tab, 'path', t->>'path', 'rows_in_file', t->'rows_in_file', 'restored', n_rest,
                                 'identical_to_live', n_match, 'changed_since_export', n_changed, 'gone_from_live', n_missing,
                                 'error', v_err, 'newest_export_day', p->>'newest_export_day', 'age_days', v_age);
  insert into public.it_restore_drill_result (subject, ok, detail)
  values (coalesce(v_tab, 'no table') || coalesce(' from ' || (t->>'path'), ''), v_ok and v_age is not null and v_age <= v_max, v_detail);
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
