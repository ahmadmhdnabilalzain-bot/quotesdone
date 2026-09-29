-- THE BACKUPS ARE HELD TO A STATED RPO AND RTO, THE RESTORE DRILL IS WEEKLY, AND A CREDENTIAL PAST
-- ITS ROTATION AGE IS RAISED.
--
-- Assigned: it_engineer (backups are IT duty 9/19; rotation is IT duty 15).
--
-- WHAT WAS MEASURED, 28 Sep 2026 (production, read-only):
--   * it_restore_drill_result: 2 rows ever. #3 (14 Sep, supplier_dues, ok false) and #70 (15 Sep,
--     quotes, ok TRUE with restored 0 - the empty-page pass fixed on 23 Sep). So no drill has ever
--     restored a row and passed, and the next one is not due until ~15 Oct: it_duty_schedule runs
--     'restore_table' every 30 days.
--   * dr_restore: 0 rows. it_credential_rotation: 0 rows.
--   * No RTO or RPO was stated anywhere - not in it_threshold, not in docs/.
--   * table_export_run: a daily export, 'done', finishing ~23:12 UTC each night (26, 27, 28 Sep).
--   * internal_credential: 89 active. Oldest created 3 Aug 2026 (56 days). it_threshold
--     credential_rotate_days = 90. fn_it_credential_rotate (a_rotated_credential_stays_valid_until_
--     the_run_that_retires_it.sql) ALREADY inserts one it_credential_rotation row per rotation, from
--     the daily 'rotation' duty. The table is empty because nothing has reached 90 days - the first
--     falls due ~1 Nov 2026. Recording is therefore not rebuilt here; what was missing is anything
--     that notices when the rotation duty does NOT do its job.
--
-- WHAT THIS CHANGES:
--   1. The targets live in it_threshold (the table every IT duty already reads through
--      fn_it_threshold): backup_rpo_hours 26, backup_rto_hours 4, restore_drill_every_days 7.
--      Mirrored, with the reasoning, in docs/it/BACKUP_RPO_RTO.md.
--   2. The drill itself (resilience_ping -> fn_it_restore_table_due / _pick / _record) goes from every
--      30 days to every 7: it_duty_schedule 'restore_table'. The drill is not reimplemented.
--   3. Seat duty it_engineer.backup_objectives (daily, via fn_seat_duties_tick) measures:
--        achieved RPO = hours since the newest finished table export, and the widest gap between
--          finished exports over the last 7 days;
--        achieved RTO = seconds from the last PASSING drill's pick to its recorded result (a real
--          download + restore of one page). A drill that restored 0 rows is not a pass.
--      and raises duty:backup_objectives:<rpo|rto_unproven|rto|drill_stale> on a miss; each closes
--      itself the tick it is back inside target (fn_it_duty_settle).
--   4. Seat duty it_engineer.credential_rotation_age (daily) raises one item per active credential
--      whose age since its last rotation (or creation) exceeds credential_rotate_days + 7 days of
--      grace with no rotation open for it, and one per credential whose rotated_at is set but has no
--      it_credential_rotation row (a rotation done outside the duty is unrecorded).
--
--   5. fn_it_full_restore_compare(schema) + quarterly duty it_engineer.dr_review: a full-database restore
--      into a BRANCH scratch schema, compared per table by count and checksum (section 6). Built, never
--      run against production.
--   6. THE 14 SEP supplier_dues DRILL (#3, ok false) failed on three items, all since fixed upstream:
--      the newest export was 7 days old (limit 2), no full copy existed (last_full_day null), and the
--      page held 0 rows. Exports now finish daily (26-28 Sep measured) with a full copy, and an empty
--      page fails honestly (the_restore_drill_passes_only_on_rows_it_actually_restored.sql). What was
--      missing is a cadence that re-drills within a week; section 2 is that fix.
--
-- WHAT THIS DOES NOT CHANGE: fn_it_restore_table_overdue still backstops at 33 days (this duty raises
-- at 7 + 2). RTO here is the sample restore time, not a whole-database restore - nothing in the estate
-- has ever timed one, and dr_restore stays empty; the doc says so rather than inventing a number.
-- Third-party key rotation stays with it_expiry / fn_it_renewal_watch.
--
--   node scripts/apply_sql.mjs scripts/sql/the_backups_are_held_to_a_stated_rpo_and_rto_and_a_credential_past_its_rotation_age_is_raised.sql --apply --ddl

-- ── 1. THE TARGETS ────────────────────────────────────────────────────────────────────────────────
insert into public.it_threshold (key, value, unit, basis) values
  ('backup_rpo_hours', 26, 'hours',
   'Recovery point objective: at most 26 h of data may be lost. The table export runs daily (~23:00 UTC, ~12 min), so 24 h plus 2 h slack. docs/it/BACKUP_RPO_RTO.md'),
  ('backup_rto_hours', 4, 'hours',
   'Recovery time objective: service restored within 4 h. Measured today only as the weekly drill''s sample restore time; a drill must have passed within restore_drill_every_days + 2. docs/it/BACKUP_RPO_RTO.md'),
  ('restore_drill_every_days', 7, 'days',
   'The table restore drill runs weekly (it_duty_schedule restore_table). docs/it/BACKUP_RPO_RTO.md')
on conflict (key) do update set value = excluded.value, unit = excluded.unit, basis = excluded.basis;

-- ── 2. THE DRILL IS WEEKLY ────────────────────────────────────────────────────────────────────────
update public.it_duty_schedule
   set every = interval '7 days',
       note  = 'duty 19: WEEKLY - one table page from the newest finished export restored into scratch and compared with live; the export''s age and the kb_chunks chain'
 where duty = 'restore_table';

-- ── 3. ACHIEVED RPO / RTO AGAINST THE TARGETS ────────────────────────────────────────────────────
create or replace function public.fn_it_engineer_backup_objectives()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_rpo numeric := coalesce(public.fn_it_threshold('backup_rpo_hours'), 26);
  v_rto numeric := coalesce(public.fn_it_threshold('backup_rto_hours'), 4);
  v_every int := coalesce(public.fn_it_threshold('restore_drill_every_days'), 7)::int;
  v_newest timestamptz; v_age_h numeric; v_gap_h numeric;
  v_pass public.it_restore_drill_result; v_last public.it_restore_drill_result; v_pick timestamptz; v_rto_s numeric;
  v_items jsonb := '[]'::jsonb;
begin
  -- RPO: hours since the newest finished export, and the widest gap between finished exports in 7 days
  select max(finished_at) into v_newest from public.table_export_run where status = 'done';
  v_age_h := round((extract(epoch from now() - v_newest) / 3600)::numeric, 1);
  select round(max(extract(epoch from g) / 3600)::numeric, 1) into v_gap_h from (
    select finished_at - lag(finished_at) over (order by finished_at) g
      from public.table_export_run where status = 'done' and finished_at > now() - interval '7 days') x;
  if v_newest is null or v_age_h > v_rpo or coalesce(v_gap_h, 0) > v_rpo then
    v_items := v_items || jsonb_build_object('item', 'rpo', 'owner_seat', 'it_engineer', 'subject', 'table_backup',
      'blast', 'agent_facing', 'affected', 1,
      'title', case when v_newest is null then 'No finished table export exists, so the ' || v_rpo || ' h RPO cannot be met'
               else 'Achieved RPO ' || greatest(v_age_h, coalesce(v_gap_h, 0)) || ' h is over the ' || v_rpo || ' h target' end,
      'evidence', jsonb_build_object('newest_export_finished_at', v_newest, 'hours_since', v_age_h,
                                     'widest_gap_7d_hours', v_gap_h, 'target_hours', v_rpo));
  end if;

  -- RTO: the last drill that restored rows and passed, timed from its pick to its record
  select * into v_last from public.it_restore_drill_result order by id desc limit 1;
  select * into v_pass from public.it_restore_drill_result
   where ok and coalesce((detail->>'restored')::int, 0) > 0 order by id desc limit 1;
  if v_pass.id is not null then
    select max(started_at) into v_pick from public.agent_runs
     where agent = 'it_engineer' and counts->>'job' = 'restore_table_pick' and started_at <= v_pass.ran_at;
    v_rto_s := round(extract(epoch from v_pass.ran_at - v_pick)::numeric, 1);
  end if;
  if v_pass.id is null or v_pass.ran_at < now() - make_interval(days => v_every + 2) then
    v_items := v_items || jsonb_build_object('item', 'rto_unproven', 'owner_seat', 'it_engineer', 'subject', 'table_backup',
      'blast', 'agent_facing', 'affected', 1,
      'title', 'No restore drill has restored rows and passed in the last ' || (v_every + 2) || ' days'
               || coalesce(' (last pass ' || to_char(v_pass.ran_at at time zone 'Asia/Dubai', 'DD Mon') || ')', ' (none ever)')
               || ', so the ' || v_rto || ' h RTO is unproven',
      'evidence', jsonb_build_object('last_pass_id', v_pass.id, 'last_pass_at', v_pass.ran_at,
                                     'last_drill_id', v_last.id, 'last_drill_at', v_last.ran_at, 'last_drill_ok', v_last.ok));
  elsif v_rto_s is not null and v_rto_s > v_rto * 3600 then
    v_items := v_items || jsonb_build_object('item', 'rto', 'owner_seat', 'it_engineer', 'subject', 'table_backup',
      'blast', 'agent_facing', 'affected', 1,
      'title', 'The restore drill took ' || v_rto_s || ' s, over the ' || v_rto || ' h RTO',
      'evidence', jsonb_build_object('drill_id', v_pass.id, 'seconds', v_rto_s, 'target_hours', v_rto));
  end if;
  if v_last.id is null or v_last.ran_at < now() - make_interval(days => v_every + 2) then
    v_items := v_items || jsonb_build_object('item', 'drill_stale', 'owner_seat', 'it_engineer', 'subject', 'table_backup',
      'blast', 'agent_facing', 'affected', 1,
      'title', 'The weekly restore drill has not run for ' || coalesce(extract(day from now() - v_last.ran_at)::int || ' days', 'ever'),
      'evidence', jsonb_build_object('last_drill_at', v_last.ran_at, 'every_days', v_every,
                                     'look_at', 'resilience_ping restore_table step; fn_it_restore_table_due'));
  end if;

  return jsonb_build_object('rpo', jsonb_build_object('target_hours', v_rpo, 'hours_since_export', v_age_h, 'widest_gap_7d_hours', v_gap_h),
                            'rto', jsonb_build_object('target_hours', v_rto, 'last_pass_id', v_pass.id, 'sample_restore_seconds', v_rto_s),
                            'drill', jsonb_build_object('last_id', v_last.id, 'last_at', v_last.ran_at, 'every_days', v_every),
                            'settled', public.fn_it_duty_settle('backup_objectives', v_items));
end $fn$;
revoke execute on function public.fn_it_engineer_backup_objectives() from public, anon, authenticated;

-- ── 4. A CREDENTIAL PAST ITS ROTATION AGE, OR ROTATED WITHOUT A RECORD ───────────────────────────
create or replace function public.fn_it_engineer_credential_rotation_age()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_days int := coalesce(public.fn_it_threshold('credential_rotate_days'), 90)::int;
  v_grace int := 7; c record; v_items jsonb := '[]'::jsonb; n_over int := 0; n_unrec int := 0;
begin
  for c in
    select ic.id, ic.context, coalesce(ic.rotated_at, ic.created_at) since
      from public.internal_credential ic
     where ic.active and ic.retired_at is null
       and coalesce(ic.rotated_at, ic.created_at) < now() - make_interval(days => v_days + v_grace)
       and not exists (select 1 from public.it_credential_rotation r where r.context = ic.context and r.status in ('overlap', 'held'))
  loop
    n_over := n_over + 1;
    v_items := v_items || jsonb_build_object('item', 'overdue:' || c.context, 'owner_seat', 'it_engineer', 'subject', 'credentials',
      'blast', 'agent_facing', 'affected', 1,
      'title', 'Credential ' || c.context || ' is ' || extract(day from now() - c.since)::int || ' days since rotation; the limit is '
               || v_days || ' (+' || v_grace || ' grace) and the rotation duty has not rotated it',
      'evidence', jsonb_build_object('credential_id', c.id, 'since', c.since, 'rotate_days', v_days,
                                     'look_at', 'it_duty_schedule rotation; fn_it_credential_rotate; app_secrets cred_ key for this context'));
  end loop;
  for c in
    select ic.id, ic.context, ic.rotated_at from public.internal_credential ic
     where ic.rotated_at is not null and ic.active and ic.retired_at is null
       and not exists (select 1 from public.it_credential_rotation r where r.new_id = ic.id)
  loop
    n_unrec := n_unrec + 1;
    v_items := v_items || jsonb_build_object('item', 'unrecorded:' || c.context, 'owner_seat', 'it_engineer', 'subject', 'credentials',
      'blast', 'agent_facing', 'affected', 1,
      'title', 'Credential ' || c.context || ' shows a rotation on ' || to_char(c.rotated_at, 'YYYY-MM-DD') || ' with no it_credential_rotation record',
      'evidence', jsonb_build_object('credential_id', c.id, 'rotated_at', c.rotated_at));
  end loop;
  return jsonb_build_object('rotate_days', v_days, 'grace_days', v_grace, 'overdue', n_over, 'unrecorded', n_unrec,
                            'settled', public.fn_it_duty_settle('credential_rotation_age', v_items));
end $fn$;
revoke execute on function public.fn_it_engineer_credential_rotation_age() from public, anon, authenticated;

-- ── 5. THE TWO SEAT DUTIES ────────────────────────────────────────────────────────────────────────
insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file, enabled) values
  ('it_engineer.backup_objectives', 'it_engineer', interval '1 day', 'fn_it_engineer_backup_objectives',
   'Achieved RPO (export age, widest gap) and RTO (last passing drill) against it_threshold backup_rpo_hours / backup_rto_hours; the weekly drill ran',
   'scripts/sql/the_backups_are_held_to_a_stated_rpo_and_rto_and_a_credential_past_its_rotation_age_is_raised.sql', true),
  ('it_engineer.credential_rotation_age', 'it_engineer', interval '1 day', 'fn_it_engineer_credential_rotation_age',
   'Every active internal credential past credential_rotate_days (+7 grace) without a rotation, and every rotation with no it_credential_rotation record',
   'scripts/sql/the_backups_are_held_to_a_stated_rpo_and_rto_and_a_credential_past_its_rotation_age_is_raised.sql', true)
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what,
                                 owner_file = excluded.owner_file, enabled = excluded.enabled;

-- ── 6. THE QUARTERLY FULL-DATABASE RESTORE: COMPARED, NEVER RUN HERE ─────────────────────────────
-- No whole-database restore has ever been tested (dr_restore: 0 rows, no routine reads it). The restore
-- itself is a pg_restore of the nightly dump into a SCRATCH schema of a Supabase BRANCH (never
-- production - 11.3 GB measured 28 Sep); the runbook is docs/it/BACKUP_RPO_RTO.md. This routine is the
-- comparison: per public table, row count and an order-independent checksum (md5 of the sorted row
-- md5s) in public against the same table in the scratch schema. The result is one
-- it_restore_drill_result row, subject 'full_database into <schema>', which the quarterly dr_review
-- duty reads.
create or replace function public.fn_it_full_restore_compare(p_schema text, p_only text[] default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare t text; v_live bigint; v_rest bigint; c_live text; c_rest text; v_rows jsonb := '[]'::jsonb;
        n_bad int := 0; n_missing int := 0; v_start timestamptz := clock_timestamp(); v_ok boolean; v_out jsonb;
begin
  if p_schema is null or p_schema in ('public', 'auth', 'storage', 'extensions', 'vault', 'cron', 'realtime')
     or p_schema like 'pg\_%' or not exists (select 1 from pg_namespace where nspname = p_schema) then
    raise exception 'fn_it_full_restore_compare: % is not a scratch schema holding a restore', coalesce(p_schema, 'null');
  end if;
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind = 'r' and (p_only is null or c.relname = any (p_only)) order by 1 loop
    if not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                    where n.nspname = p_schema and c.relname = t and c.relkind = 'r') then
      n_missing := n_missing + 1;
      v_rows := v_rows || jsonb_build_object('table', t, 'missing', true);
      continue;
    end if;
    execute format('select count(*), md5(coalesce(string_agg(h, '''' order by h), '''')) from (select md5(x::text) h from public.%I x) s', t)
      into v_live, c_live;
    execute format('select count(*), md5(coalesce(string_agg(h, '''' order by h), '''')) from (select md5(x::text) h from %I.%I x) s', p_schema, t)
      into v_rest, c_rest;
    if v_live <> v_rest or c_live <> c_rest then
      n_bad := n_bad + 1;
      v_rows := v_rows || jsonb_build_object('table', t, 'live_rows', v_live, 'restored_rows', v_rest, 'checksum_equal', c_live = c_rest);
    end if;
  end loop;
  v_ok := n_bad = 0 and n_missing = 0;
  v_out := jsonb_build_object('schema', p_schema, 'mismatched', n_bad, 'missing', n_missing, 'differences', v_rows,
                              'compare_seconds', round(extract(epoch from clock_timestamp() - v_start)::numeric, 1));
  -- A partial comparison (p_only, used by the probe) is not a full restore and is never recorded as one.
  if p_only is null then
    insert into public.it_restore_drill_result (subject, ok, detail) values ('full_database into ' || p_schema, v_ok, v_out);
  end if;
  return v_out;
end $fn$;
revoke execute on function public.fn_it_full_restore_compare(text, text[]) from public, anon, authenticated;

-- The quarterly DR review: a full restore compared equal inside 92 days, and the targets exist.
create or replace function public.fn_it_engineer_dr_review()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_last public.it_restore_drill_result; v_items jsonb := '[]'::jsonb;
begin
  select * into v_last from public.it_restore_drill_result
   where subject like 'full\_database into %' and ok order by id desc limit 1;
  if v_last.id is null or v_last.ran_at < now() - interval '92 days' then
    v_items := v_items || jsonb_build_object('item', 'full_restore', 'owner_seat', 'it_engineer', 'subject', 'table_backup',
      'blast', 'agent_facing', 'affected', 1,
      'title', 'No full-database restore has compared equal in the last 92 days'
               || coalesce(' (last ' || to_char(v_last.ran_at, 'YYYY-MM-DD') || ')', ' (never)'),
      'evidence', jsonb_build_object('last_id', v_last.id, 'runbook', 'docs/it/BACKUP_RPO_RTO.md',
                                     'compare', 'select public.fn_it_full_restore_compare(''<scratch schema>'') on the branch'));
  end if;
  if (select count(*) from public.it_threshold where key in ('backup_rpo_hours', 'backup_rto_hours', 'restore_drill_every_days')) <> 3 then
    v_items := v_items || jsonb_build_object('item', 'targets', 'owner_seat', 'it_engineer', 'subject', 'table_backup', 'config', true,
      'title', 'The RPO/RTO/drill targets are missing from it_threshold');
  end if;
  return jsonb_build_object('last_full_restore', v_last.ran_at, 'settled', public.fn_it_duty_settle('dr_review', v_items));
end $fn$;
revoke execute on function public.fn_it_engineer_dr_review() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file, enabled) values
  ('it_engineer.dr_review', 'it_engineer', interval '90 days', 'fn_it_engineer_dr_review',
   'Quarterly DR review: a full-database restore into a branch scratch schema compared equal (fn_it_full_restore_compare) inside 92 days; the RPO/RTO targets are recorded',
   'scripts/sql/the_backups_are_held_to_a_stated_rpo_and_rto_and_a_credential_past_its_rotation_age_is_raised.sql', true)
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what,
                                 owner_file = excluded.owner_file, enabled = excluded.enabled;

-- PROBE: a verdict row, no writes.
select case
  when (select count(*) from public.it_threshold where key in ('backup_rpo_hours', 'backup_rto_hours', 'restore_drill_every_days')) <> 3
    then 'PROBE FAILED: the RPO/RTO/drill targets are not in it_threshold'
  when (select every from public.it_duty_schedule where duty = 'restore_table') > interval '7 days'
    then 'PROBE FAILED: the restore drill is not weekly'
  when (select count(*) from public.seat_duty where enabled and duty in ('it_engineer.backup_objectives', 'it_engineer.credential_rotation_age', 'it_engineer.dr_review')) <> 3
    then 'PROBE FAILED: the three seat duties are not scheduled'
  else 'PROBE OK' end as verdict;
