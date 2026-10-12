CREATE OR REPLACE FUNCTION public.fn_table_export_change_tracking(p_apply boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_min bigint := coalesce(public.fn_it_threshold('export_incremental_min_bytes'), 67108864)::bigint;
  v_added text[] := '{}'; v_removed text[] := '{}'; v_refreshed text[] := '{}'; v_reasons jsonb := '{}'::jsonb;
  r record; v_pk text; v_npk integer; v_bytes bigint; v_proj text; v_have text; v_want boolean;
begin
  for r in select x.table_name as t from public.fn_table_export_list() x
            where x.table_name <> 'table_export_change'
  loop
    if to_regclass(format('public.%I', r.t)) is null then continue; end if;
    v_bytes := pg_total_relation_size(format('public.%I', r.t)::regclass);
    select count(*), min(a.attname::text) into v_npk, v_pk
      from pg_index i
      cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
      join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum
     where i.indrelid = format('public.%I', r.t)::regclass and i.indisprimary;

    if v_bytes >= v_min and coalesce(v_npk, 0) <> 1 then
      -- Named out loud rather than silently left full: this table is big and CANNOT report changes.
      v_reasons := v_reasons || jsonb_build_object(r.t,
        format('%s bytes, at or over the threshold, but its primary key has %s columns, so it stays a full copy every day',
               v_bytes, coalesce(v_npk, 0)));
    end if;

    -- The exported projection, as the update trigger compares it. A column added to a tracked table
    -- later changes this string, and the branch below rebuilds the triggers with the new list -- a
    -- stale list would make a change to the new column invisible.
    select coalesce(string_agg(quote_ident(a.attname), ',' order by a.attnum), '') into v_proj
      from pg_attribute a
     where a.attrelid = format('public.%I', r.t)::regclass and a.attnum > 0 and not a.attisdropped
       and format_type(a.atttypid, a.atttypmod) not like 'vector%';
    select x.projection into v_have from public.table_export_change_tracked x where x.table_name = r.t;
    v_want := v_bytes >= v_min and coalesce(v_npk, 0) = 1;

    if v_want and (v_have is null or v_have is distinct from v_proj) then
      if p_apply then
        execute format('drop trigger if exists %I on public.%I', 'z90_' || r.t || '_export_change_ins', r.t);
        execute format('create trigger %I after insert on public.%I referencing new table as new_rows
                        for each statement execute function public.trg_table_export_change(%L, %L)',
                       'z90_' || r.t || '_export_change_ins', r.t, v_pk, v_proj);
        execute format('drop trigger if exists %I on public.%I', 'z90_' || r.t || '_export_change_upd', r.t);
        execute format('create trigger %I after update on public.%I referencing old table as old_rows new table as new_rows
                        for each statement execute function public.trg_table_export_change(%L, %L)',
                       'z90_' || r.t || '_export_change_upd', r.t, v_pk, v_proj);
        execute format('drop trigger if exists %I on public.%I', 'z90_' || r.t || '_export_change_del', r.t);
        execute format('create trigger %I after delete on public.%I referencing old table as old_rows
                        for each statement execute function public.trg_table_export_change(%L, %L)',
                       'z90_' || r.t || '_export_change_del', r.t, v_pk, v_proj);
        execute format('drop trigger if exists %I on public.%I', 'z90_' || r.t || '_export_change_trunc', r.t);
        execute format('create trigger %I after truncate on public.%I
                        for each statement execute function public.trg_table_export_change(%L, %L)',
                       'z90_' || r.t || '_export_change_trunc', r.t, v_pk, v_proj);
        insert into public.table_export_change_tracked (table_name, pk_column, projection, bytes_at_registration)
        values (r.t, v_pk, v_proj, v_bytes)
        on conflict (table_name) do update set pk_column = excluded.pk_column, projection = excluded.projection,
                                               bytes_at_registration = excluded.bytes_at_registration;
      end if;
      if v_have is null then v_added := v_added || r.t; else v_refreshed := v_refreshed || r.t; end if;
    elsif not v_want and v_have is not null then
      if p_apply then
        execute format('drop trigger if exists %I on public.%I', 'z90_' || r.t || '_export_change_ins', r.t);
        execute format('drop trigger if exists %I on public.%I', 'z90_' || r.t || '_export_change_upd', r.t);
        execute format('drop trigger if exists %I on public.%I', 'z90_' || r.t || '_export_change_del', r.t);
        execute format('drop trigger if exists %I on public.%I', 'z90_' || r.t || '_export_change_trunc', r.t);
        delete from public.table_export_change_tracked x where x.table_name = r.t;
        delete from public.table_export_change c where c.table_name = r.t;
      end if;
      v_removed := v_removed || r.t;
    end if;
  end loop;
  return jsonb_build_object('threshold_bytes', v_min, 'added', to_jsonb(v_added), 'removed', to_jsonb(v_removed),
                            'triggers_refreshed', to_jsonb(v_refreshed),
                            'stays_full_and_why', v_reasons, 'applied', p_apply,
                            'tracked', (select coalesce(jsonb_object_agg(x.table_name, x.pk_column), '{}'::jsonb)
                                          from public.table_export_change_tracked x));
end $function$


CREATE OR REPLACE FUNCTION public.fn_table_export_demo_ids()
 RETURNS TABLE(dc text[], dl text[], di text[], dq text[])
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  select coalesce(array_agg(c.id::text), '{}') into dc from public.customers c
   where coalesce(c.is_demo, false) or coalesce(c.email, '') ~* 'example\.invalid' or coalesce(c.full_name, '') ~* 'zz[_ -]?demo';
  select coalesce(array_agg(l.id::text), '{}') into dl from public.leads l
   where coalesce(l.is_demo, false) or coalesce(l.email, '') ~* 'example\.invalid' or coalesce(l.company_name, '') ~* 'zz[_ -]?demo';
  select coalesce(array_agg(i.id::text), '{}') into di from public.inquiries i where i.customer_id::text = any(dc);
  select coalesce(array_agg(q.id::text), '{}') into dq from public.quotes q
   where q.supplier_id::text = any(dl) or q.inquiry_id::text = any(di);
  return next;
end $function$


CREATE OR REPLACE FUNCTION public.fn_table_export_due()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_local timestamp := now() at time zone 'Asia/Dubai';
  v_stamp date := (now() at time zone 'Asia/Dubai')::date;
  v_run public.table_export_run;
  v_kind text; v_since timestamptz; v_full_at timestamptz;
  v_resume jsonb;
begin
  if v_local::time < time '03:00' then
    return jsonb_build_object('due', false, 'stamp', v_stamp, 'reason', 'before 03:00 Asia/Dubai');
  end if;
  select * into v_run from public.table_export_run r where r.stamp = v_stamp for update;
  if not found then
    perform public.fn_table_export_change_tracking(true);
    select r.started_at - interval '6 hours' into v_since
      from public.table_export_run r where r.status = 'done' and r.stamp < v_stamp order by r.stamp desc limit 1;
    select max(r.started_at) into v_full_at
      from public.table_export_run r where r.status = 'done' and r.kind = 'full' and r.stamp < v_stamp;
    v_kind := case when extract(isodow from v_local) = 5 or v_since is null
                     or not exists (select 1 from public.table_export_run r
                                     where r.status = 'done' and r.kind = 'full' and r.stamp >= v_stamp - 7 and r.stamp < v_stamp)
                     -- a table that became change-tracked after the last full copy has no base yet
                     or exists (select 1 from public.table_export_change_tracked x
                                 where v_full_at is null or x.tracking_since > v_full_at)
                   then 'full' else 'incremental' end;
    if v_kind = 'full' then v_since := null; end if;
    insert into public.table_export_run (stamp, kind, since) values (v_stamp, v_kind, v_since) on conflict (stamp) do nothing;
    if not found then return jsonb_build_object('due', false, 'stamp', v_stamp, 'reason', 'claimed concurrently'); end if;
    return jsonb_build_object('due', true, 'stamp', v_stamp, 'attempt', 1, 'resume', null, 'kind', v_kind, 'since', v_since);
  end if;
  if v_run.status = 'done' then
    return jsonb_build_object('due', false, 'stamp', v_stamp, 'status', 'done', 'kind', v_run.kind);
  end if;
  if v_run.heartbeat_at > now() - interval '10 minutes' then
    return jsonb_build_object('due', false, 'stamp', v_stamp, 'status', v_run.status, 'reason', 'in progress or waiting to retry');
  end if;
  if v_run.attempts >= 6 then
    return jsonb_build_object('due', false, 'stamp', v_stamp, 'status', v_run.status, 'attempts', v_run.attempts, 'reason', 'gave up after 6 attempts');
  end if;
  v_resume := case
    when v_run.status = 'running' then v_run.state
    when v_run.status = 'failed' and jsonb_typeof(v_run.state->'queue') = 'array'
         and jsonb_array_length(v_run.state->'queue') > 0
         and (v_run.state->'errors') ? (v_run.state->'queue'->0->>'t') then v_run.state
  end;
  update public.table_export_run r
     set attempts = r.attempts + case when r.status = 'failed' then 1 else 0 end,
         status = 'running', heartbeat_at = now(),
         state = v_resume
   where r.stamp = v_stamp;
  return jsonb_build_object('due', true, 'stamp', v_stamp,
    'attempt', v_run.attempts + case when v_run.status = 'failed' then 1 else 0 end,
    'resume', v_resume,
    'kind', v_run.kind, 'since', v_run.since);
end $function$


CREATE OR REPLACE FUNCTION public.fn_table_export_filter(p_table text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_rel regclass := to_regclass(format('public.%I', p_table));
  v_where text;
begin
  if v_rel is null then raise exception 'fn_table_export_filter: public.% does not exist', p_table; end if;
  select format('(to_jsonb(t) - %L::text[])::text !~* %L', public.fn_table_export_stripped(p_table), 'zz[_ -]?demo|example\.invalid')
         || coalesce(string_agg(case a.attname
              when 'is_demo'     then ' and not coalesce(t.is_demo, false)'
              when 'customer_id' then ' and not coalesce(t.customer_id::text = any($1), false)'
              when 'supplier_id' then ' and not coalesce(t.supplier_id::text = any($2), false)'
              when 'lead_id'     then ' and not coalesce(t.lead_id::text = any($2), false)'
              when 'inquiry_id'  then ' and not coalesce(t.inquiry_id::text = any($3), false)'
              when 'quote_id'    then ' and not coalesce(t.quote_id::text = any($4), false)' end, ''), '')
    into v_where
    from pg_attribute a
   where a.attrelid = v_rel and a.attnum > 0 and not a.attisdropped
     and a.attname in ('is_demo', 'customer_id', 'supplier_id', 'lead_id', 'inquiry_id', 'quote_id');
  return v_where;
end $function$


CREATE OR REPLACE FUNCTION public.fn_table_export_finish(p_stamp date, p_manifest jsonb, p_error text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_day text := to_char(p_stamp, 'YYYY-MM-DD');
  v_bad text; v_queued integer; v_pruned integer := 0; v_run public.table_export_run;
begin
  select * into v_run from public.table_export_run r where r.stamp = p_stamp;
  if not found then return jsonb_build_object('ok', false, 'stamp', p_stamp, 'error', 'no table_export_run row for this day'); end if;
  if p_error is null then
    select string_agg(x.table_name, ', ') into v_bad
      from public.fn_table_export_list() x
     where coalesce((p_manifest->'tables'->x.table_name->>'pages')::int, -1)
           <> (select count(*) from storage.objects o
                where o.bucket_id = 'backups' and o.name like v_day || '/' || x.table_name || '/page\_%.json');
    if v_bad is not null then p_error := 'pages in storage disagree with the manifest for: ' || v_bad; end if;
    if p_error is null and not exists (select 1 from storage.objects o where o.bucket_id = 'backups' and o.name = v_day || '/_manifest.json') then
      p_error := 'the manifest is not in storage';
    end if;
  end if;

  if p_error is not null then
    update public.table_export_run r set status = 'failed', error = left(p_error, 2000), heartbeat_at = now()
     where r.stamp = p_stamp;
    return jsonb_build_object('ok', false, 'stamp', p_stamp, 'error', left(p_error, 500));
  end if;

  update public.table_export_run r set status = 'done', finished_at = now(), heartbeat_at = now(), manifest = p_manifest, error = null
   where r.stamp = p_stamp;
  -- a full copy holds every row, so changes logged well before it started are no longer needed
  if v_run.kind = 'full' then
    delete from public.table_export_change cl where cl.changed_at < v_run.started_at - interval '1 day';
    get diagnostics v_pruned = row_count;
  end if;
  v_queued := public.fn_enqueue_doc_backups();
  return jsonb_build_object('ok', true, 'stamp', p_stamp, 'kind', v_run.kind, 'queued_for_dropbox', v_queued, 'change_log_pruned', v_pruned);
end $function$


CREATE OR REPLACE FUNCTION public.fn_table_export_list()
 RETURNS TABLE(table_name text, subject text, change_log text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select r.table_name, r.category,
         (select 'table_export_change' from public.table_export_change_tracked x where x.table_name = r.table_name)
    from public.table_export_registry r
   where r.exported
   order by r.table_name
$function$


CREATE OR REPLACE FUNCTION public.fn_table_export_page(p_table text, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 1000, p_since timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_rel regclass; v_cols text; v_keyvals text; v_after text := 'true'; v_where text; v_log text; v_pk text; v_pktype text;
  v_strip text[]; v_lim integer := greatest(1, least(coalesce(p_limit, 1000), 1000));
  v_rows jsonb; v_n integer; v_last jsonb;
  v_dc text[]; v_dl text[]; v_di text[]; v_dq text[];   -- $1..$4, the positions fn_table_export_filter names
begin
  select x.change_log into v_log from public.fn_table_export_list() x where x.table_name = p_table;
  if not found then raise exception 'fn_table_export_page: % is not in fn_table_export_list()', p_table; end if;
  v_rel := to_regclass(format('public.%I', p_table));
  if v_rel is null then raise exception 'fn_table_export_page: public.% does not exist', p_table; end if;

  select string_agg(format('t.%I', a.attname), ', ' order by k.ord),
         string_agg(format('(($5->>%s)::%s)', k.ord - 1, format_type(a.atttypid, a.atttypmod)), ', ' order by k.ord),
         min(a.attname::text), min(format_type(a.atttypid, a.atttypmod))
    into v_cols, v_keyvals, v_pk, v_pktype
    from pg_index i
    cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
    join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum
   where i.indrelid = v_rel and i.indisprimary;
  if v_cols is null then raise exception 'fn_table_export_page: public.% has no primary key to page on', p_table; end if;
  if p_after is not null then v_after := format('(%s) > (%s)', v_cols, v_keyvals); end if;

  v_strip := public.fn_table_export_stripped(p_table);
  v_where := public.fn_table_export_filter(p_table);
  select d.dc, d.dl, d.di, d.dq into v_dc, v_dl, v_di, v_dq from public.fn_table_export_demo_ids() d;
  if p_since is not null and v_log is not null then
    -- THE CAST GOES ON THE LOG, NEVER ON THE TABLE. Measured 18 Sep 2026: with `t.id::text in (...)`
    -- this statement outlived the management API gateway (524) on kb_chunks -- casting the primary key
    -- makes the index on it unusable and turns an incremental page into a sequential scan of 2.69 M
    -- rows over 9 GB, every page, every night. row_key was written from this very column, so casting it
    -- back is exact.
    v_where := v_where || format(
      ' and t.%I in (select cl.row_key::%s from public.table_export_change cl
                      where cl.table_name = %L and cl.changed_at >= $7 and not cl.deleted)',
      v_pk, v_pktype, p_table);
  end if;

  execute format(
    'select coalesce(jsonb_agg(y.j order by y.ord), ''[]''::jsonb), count(*)::int, (array_agg(y.k order by y.ord desc))[1]
       from (select row_number() over () as ord, x.k, x.j
               from (select jsonb_build_array(%1$s) as k, to_jsonb(t) - $6 as j
                       from public.%2$I t where %3$s and %4$s order by %1$s limit %5$s) x) y',
    v_cols, p_table, v_after, v_where, v_lim)
    into v_rows, v_n, v_last
    using v_dc, v_dl, v_di, v_dq, p_after, v_strip, p_since;

  return jsonb_build_object('table', p_table, 'rows', v_rows, 'n', v_n, 'last', v_last, 'done', v_n < v_lim,
                            'mode', case when p_since is not null and v_log is not null then 'changes_since' else 'full' end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_table_export_replay(p_table text, p_base jsonb, p_increments jsonb DEFAULT '[]'::jsonb, p_changes jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_pk text; v_pktype text; v_npk integer; v_strip text[]; v_where text; v_proj text;
  v_dc text[]; v_dl text[]; v_di text[]; v_dq text[];   -- $1..$4, the positions fn_table_export_filter names
  v_lo text; v_hi text; v_inc jsonb; v_n integer;
  n_base integer := 0; n_upserted integer := 0; n_deleted integer := 0; n_rebuilt integer := 0;
  n_match integer := 0; n_changed integer := 0; n_gone integer := 0; n_lost integer := 0;
  v_lost_keys jsonb;
begin
  if to_regclass(format('public.%I', p_table)) is null then
    raise exception 'fn_table_export_replay: public.% does not exist', p_table;
  end if;
  if not exists (select 1 from public.fn_table_export_list() x where x.table_name = p_table) then
    raise exception 'fn_table_export_replay: % is not in fn_table_export_list()', p_table;
  end if;
  select count(*), min(a.attname::text), min(format_type(a.atttypid, a.atttypmod))
    into v_npk, v_pk, v_pktype
    from pg_index i
    cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
    join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum
   where i.indrelid = format('public.%I', p_table)::regclass and i.indisprimary;
  if coalesce(v_npk, 0) <> 1 then
    raise exception 'fn_table_export_replay: public.% has a %-column primary key; only a single-column key is rebuilt', p_table, coalesce(v_npk, 0);
  end if;
  v_strip := public.fn_table_export_stripped(p_table);
  v_where := public.fn_table_export_filter(p_table);
  select d.dc, d.dl, d.di, d.dq into v_dc, v_dl, v_di, v_dq from public.fn_table_export_demo_ids() d;
  -- The exported projection, named column by column, for the same reason the trigger names it: a
  -- to_jsonb() of the whole row would serialise a 768-dimension embedding on both sides of every
  -- comparison only to subtract it again.
  select coalesce(string_agg(quote_ident(a.attname), ',' order by a.attnum), '') into v_proj
    from pg_attribute a
   where a.attrelid = format('public.%I', p_table)::regclass and a.attnum > 0 and not a.attisdropped
     and format_type(a.atttypid, a.atttypmod) not like 'vector%';

  execute format('create temp table it_replay_scratch (like public.%I) on commit drop', p_table);
  execute format('insert into it_replay_scratch select * from jsonb_populate_recordset(null::public.%I, $1)', p_table)
    using coalesce(p_base, '[]'::jsonb);
  get diagnostics n_base = row_count;
  if n_base = 0 then
    execute 'drop table it_replay_scratch';
    return jsonb_build_object('table', p_table, 'rebuilt', 0, 'lost_rows', -1,
                              'error', 'the base page carried no rows, so there is nothing to rebuild from');
  end if;
  -- The window is the base page's own key range, IN THE KEY'S OWN TYPE. Comparing keys as text would
  -- sort bigint 10 before 9 and silently rebuild the wrong window.
  execute format('select min(s.%1$I)::text, max(s.%1$I)::text from it_replay_scratch s', v_pk) into v_lo, v_hi;

  -- every later day, in order: its rows replace the keys they carry (an update is that row again), and
  -- anything it carries outside the base page's window is dropped, so the comparison stays bounded.
  for v_inc in select value from jsonb_array_elements(coalesce(p_increments, '[]'::jsonb)) loop
    execute format('delete from it_replay_scratch s where s.%1$I in
                      (select (r->>%2$L)::%3$s from jsonb_array_elements($1) r)', v_pk, v_pk, v_pktype)
      using coalesce(v_inc, '[]'::jsonb);
    execute format('insert into it_replay_scratch select * from jsonb_populate_recordset(null::public.%I, $1)', p_table)
      using coalesce(v_inc, '[]'::jsonb);
    get diagnostics v_n = row_count;
    n_upserted := n_upserted + v_n;
    execute format('delete from it_replay_scratch s where s.%1$I < ($1)::%2$s or s.%1$I > ($2)::%2$s', v_pk, v_pktype)
      using v_lo, v_hi;
  end loop;

  -- then the deletions the change log recorded, newest wins: a key whose LAST entry is a delete is gone.
  -- A row_key that does not parse as the key's own type is skipped (21 Sep 2026): the TRUNCATE branch of
  -- trg_table_export_change writes a sentence there with deleted = true, and on bigint kb_chunks the cast
  -- raised 22P02 and failed the whole replay. Measured before the fix. The truncate itself forced the
  -- next export day FULL, so skipping its marker loses nothing.
  execute format(
    'delete from it_replay_scratch s where s.%1$I in (
       select d.row_key::%2$s from (
         select distinct on (c->>''row_key'') c->>''row_key'' as row_key, (c->>''deleted'')::boolean as deleted
           from jsonb_array_elements($1) c
          where c->>''table_name'' = $2
          order by c->>''row_key'', (c->>''changed_at'') desc) d
        where d.deleted and pg_input_is_valid(d.row_key, %2$L))', v_pk, v_pktype)
    using coalesce(p_changes, '[]'::jsonb), p_table;
  get diagnostics n_deleted = row_count;
  execute 'select count(*) from it_replay_scratch' into n_rebuilt;

  -- compared with live over the columns the export carries (the vector columns are stripped at export)
  execute format(
    'select count(*) filter (where l.%1$I is not null and not ((%3$s) is distinct from (%4$s))),
            count(*) filter (where l.%1$I is not null and ((%3$s) is distinct from (%4$s))),
            count(*) filter (where l.%1$I is null)
       from it_replay_scratch s left join public.%2$I l on l.%1$I = s.%1$I',
    v_pk, p_table, 'l.' || replace(v_proj, ',', ', l.'), 's.' || replace(v_proj, ',', ', s.'))
    into n_match, n_changed, n_gone;

  -- THE ONE THAT FAILS THE DRILL: live rows inside the window that the rebuild does not hold and that
  -- no change-log entry names either. A row created after the last export IS named (its insert is
  -- logged), so this counts only rows the backup genuinely cannot give back. The demo rule is the
  -- export's own (fn_table_export_filter), or every demo row would read as a row the rebuild lost.
-- The excuse is the LATEST log entry, not any entry. Review finding, 18 Sep 2026: "any entry names it"
-- also excused a key whose last entry is a DELETE and which is nonetheless live today -- exactly the
-- shape a trigger-bypassing write leaves (session_replication_role=replica, ALTER TABLE ... DISABLE
-- TRIGGER, a raw restore, the truncate-and-reload path). That row is in no backup file and no log entry
-- claims it is, so it must count as lost.
  execute format(
    'create temp table it_replay_lost on commit drop as
       with latest as (
         select distinct on (c->>''row_key'') c->>''row_key'' as row_key, (c->>''deleted'')::boolean as deleted
           from jsonb_array_elements($7) c
          where c->>''table_name'' = $8
          order by c->>''row_key'', (c->>''changed_at'') desc)
       select t.%1$I::text as key
         from public.%2$I t
        where %3$s
          and t.%1$I >= ($5)::%4$s and t.%1$I <= ($6)::%4$s
          and not exists (select 1 from it_replay_scratch s where s.%1$I = t.%1$I)
          and not exists (select 1 from latest l where l.row_key = t.%1$I::text and not l.deleted)',
    v_pk, p_table, v_where, v_pktype)
    using v_dc, v_dl, v_di, v_dq, v_lo, v_hi, coalesce(p_changes, '[]'::jsonb), p_table;
  -- EXECUTE, not static SQL: a plpgsql plan cached against a temp table created in this call would
  -- point at a dead OID on the next one.
  execute 'select count(*)::int from it_replay_lost' into n_lost;
  execute 'select coalesce(jsonb_agg(k.key), ''[]''::jsonb) from (select key from it_replay_lost order by key limit 10) k'
    into v_lost_keys;
  execute 'drop table it_replay_lost';

  execute 'drop table it_replay_scratch';
  return jsonb_build_object('table', p_table, 'key_column', v_pk, 'key_lo', v_lo, 'key_hi', v_hi,
    'base_rows', n_base, 'increment_rows', n_upserted, 'deletes_applied', n_deleted, 'rebuilt', n_rebuilt,
    'identical_to_live', n_match, 'changed_since_export', n_changed, 'gone_from_live', n_gone,
    'lost_rows', n_lost, 'lost_keys_first_10', v_lost_keys, 'not_compared', to_jsonb(v_strip));
end $function$


CREATE OR REPLACE FUNCTION public.fn_table_export_save(p_stamp date, p_state jsonb)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  update public.table_export_run r set state = p_state, heartbeat_at = now()
   where r.stamp = p_stamp and r.status = 'running'
  returning true;
$function$


CREATE OR REPLACE FUNCTION public.fn_table_export_stripped(p_table text)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(array_agg(a.attname::text), '{}')
    from pg_attribute a
   where a.attrelid = to_regclass(format('public.%I', p_table)) and a.attnum > 0 and not a.attisdropped
     and format_type(a.atttypid, a.atttypmod) like 'vector%';
$function$


CREATE OR REPLACE FUNCTION public.fn_target_baseline(p_contract_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c record;
  v_val numeric;
  v_state text;
  v_note text;
begin
  select * into c from public.target_contract where id = p_contract_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'No such contract.');
  end if;

  if coalesce(btrim(c.measure_sql), '') = '' then
    v_state := 'not_instrumented';
    v_note  := 'NO INSTRUMENT EXISTS. The contract names an authoritative source but carries no measure. '
            || 'This needs an instrument built before it needs a number, and that is not a SQL task.';
    v_val   := null;
  else
    begin
      execute c.measure_sql into v_val;
      if v_val is null then
        v_state := 'unknown';
        v_note  := 'The measure ran and returned NULL. That is an unknown, not a zero.';
      else
        v_state := 'measured';
        v_note  := 'Measured live from the contract''s own measure_sql.';
      end if;
    exception when others then
      -- An error is never a zero. This is the distinction the estate got wrong once already.
      v_state := 'unknown';
      v_val   := null;
      v_note  := 'The measure FAILED and the baseline is therefore unknown, not zero. Error: '
              || left(sqlerrm, 200);
    end;
  end if;

  update public.target_contract
     set baseline_value = v_val,
         baseline_state = v_state,
         baseline_at    = now(),
         baseline_note  = v_note
   where id = p_contract_id;

  return jsonb_build_object(
    'ok', true,
    'contract_id', p_contract_id,
    'baseline_value', v_val,
    'baseline_state', v_state,
    'baseline_at', now(),
    'note', v_note
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_target_feasibility(p_contract_id bigint, p_record boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c            record;
  d            record;
  v_days       int;
  v_remaining  numeric;
  v_cum_rate   numeric := 1.0;
  v_down_rate  numeric := 1.0;
  v_up_rate    numeric := 1.0;
  v_total_lag  int := 0;
  v_measured   int := 0;
  v_assumed    int := 0;
  v_stages     int := 0;
  v_top        numeric;
  v_top_down   numeric;
  v_top_up     numeric;
  v_binding    text := null;
  v_binding_why text := null;
  v_cap_limit  numeric;
  v_cost       numeric := 0;
  v_headroom   numeric;
  v_verdict    text;
  v_reason     text;
  v_changes    text[] := '{}';
  v_run_rate   numeric;
  v_required   numeric;
  v_eta        date;
  v_chain      jsonb := '[]'::jsonb;
  -- Stages that declare NO capacity ceiling. Treating an undeclared capacity as an infinite one is
  -- how this function first blessed 16,129 invitations in 30 days from a list of 19,896 addresses on
  -- a domain already bouncing at 10%. Silence about a ceiling is not evidence of headroom.
  v_undeclared text[] := '{}';
  -- THE SAFETY ENVELOPE. A channel's safe throughput is a property of the channel, not of how badly
  -- we want the target. Budget and internal capacity are negotiable; sender reputation is not, because
  -- losing it costs every sign-in code and receipt that shares the domain. So this overrides.
  v_chan       jsonb;
  v_chan_block text := null;
  v_chan_why   text := null;
  v_chan_safe  numeric;
begin
  select * into c from public.target_contract where id = p_contract_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'No such contract.');
  end if;

  v_days := greatest(0, (c.deadline - (now() at time zone c.timezone)::date));

  -- Remaining outcome. For an incremental target the baseline does not subtract.
  if c.desired_basis = 'incremental' then
    v_remaining := c.desired_value;
  else
    v_remaining := c.desired_value - coalesce(c.baseline_value, 0);
  end if;

  -- Walk the chain. cum_rate is the product of every stage's conversion, so the top of funnel
  -- required is remaining / cum_rate.
  for d in
    select * from public.target_driver where contract_id = p_contract_id order by stage_order
  loop
    v_stages := v_stages + 1;
    v_cum_rate := v_cum_rate * d.rate;

    -- Downside and upside bracket an assumed rate by half and double, bounded at 1. A measured rate
    -- is bracketed far more tightly, because we actually know it.
    if d.rate_source = 'measured' then
      v_measured := v_measured + 1;
      v_down_rate := v_down_rate * greatest(d.rate * 0.75, 0.0001);
      v_up_rate   := v_up_rate   * least(d.rate * 1.25, 1.0);
    else
      v_assumed := v_assumed + 1;
      v_down_rate := v_down_rate * greatest(d.rate * 0.5, 0.0001);
      v_up_rate   := v_up_rate   * least(d.rate * 2.0, 1.0);
    end if;

    v_total_lag := v_total_lag + d.lag_days;

    v_chain := v_chain || jsonb_build_object(
      'stage', d.stage_key,
      'label', d.stage_label,
      'rate', d.rate,
      'rate_source', d.rate_source,
      'lag_days', d.lag_days,
      'capacity_per_day', d.capacity_per_day,
      'unit_cost', d.unit_cost
    );
  end loop;

  -- No chain means no model. Say so rather than inventing one.
  if v_stages = 0 then
    v_verdict := 'CANNOT_ASSESS';
    v_reason  := 'No driver model exists for this contract. Without a causal chain there is no way to '
              || 'say what volume of activity produces the outcome, and any number would be invented.';
    v_changes := array['Build the driver model: name each stage from controllable activity to outcome, with its rate and whether that rate was measured or assumed.'];
  elsif c.baseline_state <> 'measured' then
    v_verdict := 'CANNOT_ASSESS';
    v_reason  := 'The baseline is ' || c.baseline_state || '. A gap cannot be computed from an unknown '
              || 'starting point, and treating it as zero is the error this column exists to prevent.';
    v_changes := array['Instrument the baseline, or record explicitly that it is a measured zero.'];
  end if;

  v_top      := case when v_cum_rate  > 0 then v_remaining / v_cum_rate  else null end;
  v_top_down := case when v_down_rate > 0 then v_remaining / v_down_rate else null end;
  v_top_up   := case when v_up_rate   > 0 then v_remaining / v_up_rate   else null end;

  -- Cost: sum the unit cost of every stage against the volume that stage must carry.
  declare
    v_vol numeric := v_top;
  begin
    for d in select * from public.target_driver where contract_id = p_contract_id order by stage_order loop
      if d.unit_cost is not null and v_vol is not null then
        v_cost := v_cost + (v_vol * d.unit_cost);
      end if;
      if v_vol is not null then v_vol := v_vol * d.rate; end if;
    end loop;
  end;

  -- Capacity: the first stage whose per-day ceiling cannot carry its required volume in the time left
  -- is the binding constraint. Lag is subtracted, because a stage that takes 7 days to convert does
  -- not get all 30 days of runway.
  declare
    v_vol numeric := v_top;
    v_usable_days int;
  begin
    for d in select * from public.target_driver where contract_id = p_contract_id order by stage_order loop
      v_usable_days := greatest(1, v_days - v_total_lag);
      if d.capacity_per_day is not null and v_vol is not null then
        v_cap_limit := d.capacity_per_day * v_usable_days;
        if v_vol > v_cap_limit and v_binding is null then
          v_binding := d.stage_key;
          v_binding_why := format(
            'Stage %s must carry %s units but its ceiling is %s per day over %s usable days, which is %s.',
            d.stage_key, round(v_vol, 1), d.capacity_per_day, v_usable_days, round(v_cap_limit, 1));
        end if;
      elsif d.capacity_per_day is null and d.channel_key is null then
        v_undeclared := array_append(v_undeclared,
          format('%s (must carry %s over %s usable days)', d.stage_key, round(coalesce(v_vol,0),0), v_usable_days));
      end if;

      -- The channel check. A stage that names a channel is capped by that channel's policy no matter
      -- what the budget or the internal capacity allows.
      if d.channel_key is not null and v_vol is not null then
        v_chan := public.fn_channel_safe_volume(d.channel_key, v_vol, v_usable_days);
        if coalesce((v_chan->>'ok')::boolean, false) = false and v_chan_block is null then
          v_chan_block := d.stage_key;
          v_chan_safe  := (v_chan->>'safe_max')::numeric;
          v_chan_why   := v_chan->>'reason';
        end if;
      end if;
      if v_vol is not null then v_vol := v_vol * d.rate; end if;
    end loop;
  end;

  v_headroom := case when c.budget_amount is null then null else c.budget_amount - v_cost end;

  -- Run rate so far, and the pace required from here.
  v_run_rate := case when c.baseline_at is not null and c.activated_at is not null
                       and c.baseline_at > c.activated_at
                     then coalesce(c.baseline_value,0) / greatest(1, extract(day from c.baseline_at - c.activated_at))
                     else null end;
  v_required := case when v_days > 0 then v_remaining / v_days else null end;
  v_eta := case when v_run_rate is not null and v_run_rate > 0
                then (now() at time zone c.timezone)::date + ceil(v_remaining / v_run_rate)::int
                else null end;

  -- The verdict, if the two hard refusals above did not already set it.
  if v_verdict is null then
    -- THE SAFETY ENVELOPE IS CHECKED FIRST, because it is the only constraint that cannot be bought
    -- out of. A cheaper plan, a longer deadline or more staff do not restore a blacklisted domain.
    if v_chan_block is not null then
      v_verdict := 'NOT_ACHIEVABLE';
      v_reason  := 'The channel that carries this plan cannot carry it safely. ' || v_chan_why;
      v_changes := array_append(v_changes, format(
        'Cap stage %s at %s, which is what the channel can safely carry, and make up the difference on '
        || 'another channel or renegotiate the target. Raising the volume is not an option here: budget '
        || 'and capacity are negotiable, sender reputation is not.',
        v_chan_block, round(coalesce(v_chan_safe,0),0)));
      v_changes := array_append(v_changes,
        'Open a separate outreach domain and warm it, so cold volume never shares a reputation with sign-in codes and receipts.');
    elsif v_binding is not null then
      v_verdict := 'NOT_ACHIEVABLE';
      v_reason  := 'A capacity ceiling binds before the deadline. ' || v_binding_why;
      v_changes := array_append(v_changes, format('Raise capacity at stage %s, extend the deadline, or reduce the desired value.', v_binding));
    elsif c.budget_amount is not null and v_cost > c.budget_amount then
      v_verdict := 'NOT_ACHIEVABLE';
      v_reason  := format('The plan costs %s against a budget of %s, so it cannot be funded as designed.',
                          round(v_cost,2), c.budget_amount);
      v_changes := array_append(v_changes, format('Raise the budget to %s, improve a conversion rate, or reduce the desired value.', round(v_cost,2)));
    elsif array_length(v_undeclared, 1) > 0 then
      -- An undeclared ceiling is not headroom. Say the volume out loud and make someone declare it.
      v_verdict := 'AT_RISK';
      v_reason  := format('The arithmetic is fundable, but %s stage(s) declare no capacity ceiling: %s. '
                       || 'An undeclared ceiling is an unchecked assumption, not evidence of headroom, and it is '
                       || 'exactly how a plan that looks affordable turns out to be physically impossible.',
                          array_length(v_undeclared,1), array_to_string(v_undeclared, '; '));
      v_changes := array_append(v_changes,
        format('Declare a real capacity_per_day for: %s. If the true ceiling cannot carry the volume, the target changes, not the ceiling.',
               array_to_string(v_undeclared, ', ')));
    elsif v_measured = 0 then
      v_verdict := 'AT_RISK';
      v_reason  := format('The chain is arithmetically fundable and within capacity, but every one of its %s '
                       || 'rates is assumed rather than measured here. The plan is a hypothesis, not a forecast.', v_stages);
      v_changes := array_append(v_changes, 'Measure at least the first conversion rate on a small controlled batch before scaling.');
    elsif v_assumed > v_measured then
      v_verdict := 'AT_RISK';
      v_reason  := format('%s of %s rates are assumed rather than measured, so the downside case (%s at top of funnel) '
                       || 'is far from the base case (%s).', v_assumed, v_stages, round(coalesce(v_top_down,0),0), round(coalesce(v_top,0),0));
      v_changes := array_append(v_changes, 'Convert the largest assumed rate into a measured one before committing the full budget.');
    else
      v_verdict := 'ACHIEVABLE';
      v_reason  := format('Requires %s at the top of the funnel over %s days, within capacity and budget, '
                       || 'on %s measured rates of %s.', round(coalesce(v_top,0),0), v_days, v_measured, v_stages);
    end if;
  end if;

  if p_record then
    insert into public.target_verdict (
      contract_id, remaining_outcome, days_remaining, current_run_rate, required_run_rate,
      expected_completion, scenario_downside, scenario_base, scenario_upside,
      binding_stage, binding_reason, required_top_of_funnel, projected_cost, budget_headroom,
      verdict, verdict_reason, what_must_change, measured_rate_count, assumed_rate_count
    ) values (
      p_contract_id, v_remaining, v_days, v_run_rate, v_required,
      v_eta, v_top_down, v_top, v_top_up,
      v_binding, v_binding_why, v_top, nullif(v_cost,0), v_headroom,
      v_verdict, v_reason, v_changes, v_measured, v_assumed
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'contract', c.contract_key,
    'version', c.version,
    'objective', c.objective,
    'baseline', jsonb_build_object('value', c.baseline_value, 'state', c.baseline_state, 'at', c.baseline_at),
    'remaining_outcome', v_remaining,
    'days_remaining', v_days,
    'total_lag_days', v_total_lag,
    'required_run_rate_per_day', round(coalesce(v_required,0), 2),
    'chain', v_chain,
    'cumulative_rate', v_cum_rate,
    'required_top_of_funnel', jsonb_build_object(
       'downside', round(coalesce(v_top_down,0),0),
       'base',     round(coalesce(v_top,0),0),
       'upside',   round(coalesce(v_top_up,0),0)),
    'projected_cost', round(v_cost, 2),
    'budget_amount', c.budget_amount,
    'budget_headroom', round(coalesce(v_headroom,0), 2),
    'binding_stage', v_binding,
    'binding_reason', v_binding_why,
    'channel_blocked_stage', v_chan_block,
    'channel_safe_max', v_chan_safe,
    'channel_reason', v_chan_why,
    'rates_measured', v_measured,
    'rates_assumed', v_assumed,
    'verdict', v_verdict,
    'verdict_reason', v_reason,
    'what_must_change', to_jsonb(v_changes)
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_task_approve(p_dry_run boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  r            record;
  v_auth       jsonb;
  v_granted    text;
  v_ceiling    text;
  v_tier       text;
  v_final      text;
  v_why        text;
  v_reason     text;
  v_decision   text;
  v_authreason text;
  v_rep_key    text;
  v_rep_tier   text;
  v_promoted   int := 0;
  v_held       int := 0;
  v_lane       int := 0;
  v_sample     jsonb := '[]'::jsonb;
  -- Mirrors AUTONOMOUS_CEILING in supabase/functions/dept_plan/index.ts byte for byte.
  c_ceiling constant text[] := array['content_draft','knowledge_fill','recommend','invite',
                                     'analysis','research','seo','monitor','reconcile','outreach_draft'];
begin
  for r in
    select id, dept_key, action_class, tier, coalesce(needs_founder,false) needs_founder,
           coalesce(decided_by,'(unattributed)') decided_by, title, assigned_agent
      from org_tasks
     where status = 'proposed'
     order by id
  loop
    v_auth       := fn_dept_authority(r.dept_key, r.action_class);
    v_authreason := coalesce(v_auth->>'reason', 'no reason given');
    v_granted    := coalesce(nullif(v_auth->>'tier',''), 'gated');
    if v_granted not in ('advisory','gated','supervised','autonomous') then v_granted := 'gated'; end if;

    -- WHO WILL DO IT, AND HOW HAS THEIR WORK BEEN GRADED. The assignee when one exists, else the
    -- proposer; an employee on reputation probation does not get its task waved through.
    v_rep_key := coalesce(r.assigned_agent, nullif(r.decided_by, '(unattributed)'));
    select p.tier into v_rep_tier from public.agent_reputation p where p.agent_key = v_rep_key;

    v_ceiling := case when r.action_class = any(c_ceiling) then 'autonomous' else 'gated' end;
    v_tier    := case when fn_authority_rank(v_granted) > fn_authority_rank(v_ceiling)
                      then v_ceiling else v_granted end;
    v_final   := case when r.needs_founder and fn_authority_rank(v_tier) > fn_authority_rank('gated')
                      then 'gated' else v_tier end;
    if v_rep_tier = 'probation' and v_final <> 'gated' then v_final := 'gated'; end if;

    -- Name the ACTUAL cause. Four different things produce a hold and they need different fixes:
    -- a hard gate is permanent, a missing org_authority row is a configuration gap someone should
    -- close, a ceiling clamp is a deliberate refusal to widen autonomy from a file, and a probation
    -- tier is the employee's own record.
    if v_final <> 'gated' then
      v_decision := 'approve';
      v_reason := 'Approved by the authority model: ' || r.dept_key || '/' || r.action_class
        || ' resolves to tier "' || v_final || '" (' || v_authreason || '); '
        || coalesce(v_rep_key, 'nobody') || ' holds reputation tier '
        || coalesce(v_rep_tier, 'unmeasured') || '. '
        || 'No founder gate applies — decision_policy.founder_review_gates covers refunds outside '
        || 'policy, money moves above the limit, published marketing, legal action, strategy '
        || 'changes, partnerships and executive security incidents only.';
    else
      v_decision := 'hold';
      if v_rep_tier = 'probation' then
        v_why := coalesce(v_rep_key, 'the proposer') || ' is on reputation probation, and a task '
              || 'of theirs is reviewed before it runs';
      elsif v_granted = 'gated' then
        v_why := 'the authority model itself grants no more than "gated" — ' || v_authreason;
      elsif fn_authority_rank(v_granted) > fn_authority_rank(v_ceiling) then
        v_why := 'org_authority grants "' || v_granted || '" but "' || r.action_class
              || '" sits outside AUTONOMOUS_CEILING, so it is clamped to "gated". Widening that set '
              || 'is a change to this routine''s AUTONOMOUS_CEILING constant, not an edit to the task';
      else
        v_why := 'the task was written with needs_founder=true by ' || r.decided_by
              || ', and needs_founder can only tighten';
      end if;
      v_reason := 'Held for review: ' || r.dept_key || '/' || r.action_class || ' — ' || v_why || '.';
    end if;

    if not p_dry_run then
      -- Idempotent on the DECISION, not on the run. An hourly sweep must not restate the same
      -- verdict 24 times a day; it must speak the moment a verdict CHANGES.
      insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent,
                                stage, decision, reason, confidence)
      select 'org_task', r.id::text, r.dept_key, r.decided_by, 'approval_path',
             'approval', v_decision, v_reason, 1.0
      where not exists (
        select 1 from review_chain rc
         where rc.subject_type = 'org_task' and rc.subject_id = r.id::text
           and rc.stage = 'approval' and rc.decision = v_decision);

      if v_decision = 'hold' and not r.needs_founder then
        -- A HOLD HAS AN OWNER (5 Sep 2026). A gated proposal used to stay 'proposed' with nobody named,
        -- and the OS showed it to the founder as his decision. His standing rule: nothing reaches him
        -- except a Stripe refund — and the only class that may carry needs_founder is refund_decision
        -- (a00_org_tasks_founder_routing_refund_only). So a hold enters the org_task lane at tier
        -- 'gated': the department determines it from company knowledge, the accountable colleague
        -- reviews it, and the lane invokes no executor above low/advisory_safe/reversible at that tier.
        -- The review_chain 'hold' verdict above stays on record; the row also says why it was held.
        update org_tasks
           set status = 'assigned', tier = 'gated', needs_founder = false,
               decided_by = 'approval_path', updated_at = now(),
               result = coalesce(result, '{}'::jsonb) || jsonb_build_object(
                 'held', jsonb_build_object('at', now(), 'by', 'fn_task_approve', 'reason', v_reason,
                   'owner_basis', 'a hold is reviewed by the department in the org_task lane at tier gated, never by the founder'))
         where id = r.id;
        v_lane := v_lane + 1;
      end if;

      if v_decision = 'approve' then
        -- Write the RESOLVED tier, exactly as dept_plan does. Leaving the stale tier behind is the
        -- same "permission in the payload" defect audit 7.3 fixed in fn_event_dispatch, and
        -- cos_execute reads t.tier for its advisory_safe and review_pending decisions.
        update org_tasks
           set status = 'assigned', tier = v_final, needs_founder = false,
               decided_by = 'approval_path', updated_at = now()
         where id = r.id;
      end if;
    end if;

    if v_decision = 'approve' then v_promoted := v_promoted + 1; else v_held := v_held + 1; end if;
    if jsonb_array_length(v_sample) < 12 then
      v_sample := v_sample || jsonb_build_array(jsonb_build_object(
        'task', r.id, 'dept', r.dept_key, 'class', r.action_class,
        'granted', v_granted, 'final', v_final, 'decision', v_decision,
        'reputation', jsonb_build_object('agent', v_rep_key, 'tier', v_rep_tier)));
    end if;
  end loop;

  return jsonb_build_object(
    'dry_run', p_dry_run,
    'considered', v_promoted + v_held,
    'approved', v_promoted,
    -- 'held' counts every hold verdict; of those, only a needs_founder (refund) row stays 'proposed'.
    'held', v_held,
    'held_into_lane', v_lane,
    'held_for_founder', v_held - v_lane,
    'sample', v_sample);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_task_is_demand(p_action_class text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce((select d.on_revenue_path from public.action_class_demand d where d.action_class = p_action_class), false)
$function$


CREATE OR REPLACE FUNCTION public.fn_task_lesson(p_task_id bigint, p_outcome text, p_review jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  t record; v_id bigint; v_kind text; v_conf numeric; v_detail text; v_what text;
  v_verdict text; v_result text; v_basis text;
begin
  select o.id, o.dept_key, o.title, o.action_class, o.tier, o.result, o.status from org_tasks o
    into t where o.id = p_task_id;
  if t.id is null then return null; end if;

  -- What the review actually found, in the review's own words. Violations first because a failure
  -- is the lesson; dissents next; otherwise the approval and who gave it.
  select string_agg(distinct (v->>'rule') || ' (' || (v->>'severity') || '): ' || coalesce(v->>'why',''), ' | ')
    into v_detail from jsonb_array_elements(coalesce(p_review->'violations','[]'::jsonb)) v;

  if v_detail is null or v_detail = '' then
    select string_agg((d->>'by') || ' ' || (d->>'stance') || ': ' || left(coalesce(d->>'reasoning',''), 300), ' | ')
      into v_detail from jsonb_array_elements(coalesce(p_review->'dissents','[]'::jsonb)) d;
  end if;

  if p_outcome = 'event_closed' then
    -- xos-10. The Knowledge OS captures what a DISPATCHED EVENT produced, GRADED against the row.
    select c.decision into v_verdict
      from review_chain c
     where c.subject_type = 'org_task' and c.subject_id = t.id::text
       and c.stage in ('published','cos_review','dept_review') and c.decision is not null
     order by c.created_at desc, c.id desc
     limit 1;

    v_result := coalesce(nullif(t.result->>'summary',''), '');
    v_kind   := 'lesson';

    if coalesce(v_verdict,'') in ('reject','request_revision','hold_for_human','escalate')
       or coalesce(t.result->'executed'->>'error','') <> ''
       or v_result ~* '^\s*executor error'
       or coalesce(t.status,'') not in ('done','closed') then
      v_kind  := 'lesson_learned';
      v_conf  := 0.85;   -- a failure is the most useful thing this loop can record
      v_what  := 'worse';
      v_basis := case when coalesce(v_verdict,'') <> '' then 'the review verdict "' || v_verdict || '"'
                      else 'the outcome the task itself recorded' end;
    elsif v_result = '' then
      v_conf  := 0.4;    -- below the 0.6 retrieval floor: nothing was recorded, so there is nothing to serve
      v_what  := 'no_change';
      v_basis := 'the absence of any recorded result';
    else
      v_conf  := 0.6;    -- the floor fn_agent_institutional_memory serves from
      v_what  := 'success';
      v_basis := case when coalesce(v_verdict,'') <> '' then 'the review verdict "' || v_verdict || '"'
                      else 'the result the task recorded on closing' end;
    end if;

    v_detail := 'Raised by ' || coalesce(p_review->>'event_type','a company event')
             || ' on the bus and closed by ' || t.dept_key || '. Result: '
             -- org_tasks.result is JSONB, not text: the OS writes {at, mode, brain, summary} and
             -- the summary is the part that is a lesson. `nullif(t.result,'')` casts '' to jsonb
             -- at CALL time — it survived a staging apply that had no closed tasks to iterate and
             -- failed on production's 58. ->> returns text and never has to cast.
             || left(coalesce(nullif(v_result,''), 'closed with no recorded result'), 600)
             || '. Correlation ' || coalesce(p_review->>'correlation_id','unknown')
             || '. Graded ' || v_what || ' on ' || v_basis || '.';
  elsif p_outcome = 'published' and (v_detail is null or v_detail = '') then
    v_kind   := 'lesson';
    v_conf   := 0.5;   -- recorded for the audit trail; below fn_agent_institutional_memory's 0.6 floor
    v_detail := 'Cleared the quality standard for a department deliverable on the first pass and was '
             || 'approved by ' || coalesce(p_review->>'reviewer','the department head') || ' and the Chief of Staff.';
    v_what   := 'success';
  elsif p_outcome = 'published' then
    v_kind   := 'lesson_learned';
    v_conf   := 0.85;  -- shipped OVER a recorded objection: the most useful thing to remember
    v_detail := 'Approved and published despite a recorded objection. ' || v_detail;
    v_what   := 'success_over_dissent';
  else
    v_kind   := 'lesson_learned';
    v_conf   := 0.85;
    v_detail := 'Returned by review (' || p_outcome || '). ' || coalesce(v_detail, 'see review_chain');
    v_what   := 'worse';
  end if;

  insert into institutional_memory
    (kind, subject_type, subject_id, headline, detail, outcome, learned_by, confidence,
     evidence_ref, visible_to, occurred_at)
  values (v_kind, 'org_task', t.id::text,
          left(t.dept_key || ': ' || coalesce(t.title,'(untitled task)'), 200),
          left(v_detail, 2000), v_what, t.dept_key, v_conf,
          case when p_outcome = 'event_closed'
               then 'event_delivery:org_task:' || t.id
               else 'review_chain:org_task:' || t.id end,
          array[t.dept_key], now())
  returning id into v_id;

  return v_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_task_ownership_record(p_task_id bigint, p_dept text, p_author text, p_resp text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_os text; v_agent text; v_resp text := p_resp;
begin
  if v_resp is not null then
    select r.os_key into v_os from os_responsibility r where r.responsibility = v_resp order by r.os_key limit 1;
    if v_os is null then v_resp := null; end if;
  end if;
  if v_os is null then
    select d.os_key into v_os from os_department d where d.dept_key = p_dept order by d.os_key limit 1;
  end if;
  select o.owner_agent into v_agent from operating_system o
   where o.os_key = v_os and o.active
     and exists (select 1 from org_agents a where a.agent_key = o.owner_agent and a.active);
  if v_agent is not null and v_agent is distinct from p_author then   -- an owner who authored it is already accountable; a self-review row is refused by the chain guard
    insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent,
                              stage, decision, reason, confidence)
    select 'org_task', p_task_id::text, p_dept, p_author, v_agent, 'ownership', 'owned',
           'os_responsibility routes this work to the ' || v_os || ' OS'
             || case when v_resp is null
                     then ', taken from the owning OS of the ' || p_dept || ' department because '
                          || 'the CEO seat reasoned that no declared responsibility is what the task is'
                     else ', which is the declared owner of the responsibility "' || v_resp || '" (reasoned by the CEO seat)'
                end
             || '. Accountable to the company for it: ' || v_agent || '.', 1.0
     where not exists (select 1 from review_chain rc
                        where rc.subject_type = 'org_task' and rc.subject_id = p_task_id::text
                          and rc.stage = 'ownership');
  end if;
  return jsonb_build_object('owned_by_os', v_os, 'owner_agent', v_agent, 'owns_responsibility', v_resp);
end $function$


CREATE OR REPLACE FUNCTION public.fn_task_review(p_task_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  t             record;
  v_text        text;
  v_deliverable text;
  v_author      text;
  v_chain       jsonb;
  v_outcome     text;
  v_rule        record;
  v_ch          jsonb;
  v_dept        text;
  v_blocked     boolean := false;
  v_blocker     text;
  v_dissents    jsonb := '[]'::jsonb;
  v_involved    jsonb := '[]'::jsonb;
  v_rules_hit   int := 0;
  v_own_resp    text;
  v_own_os      text;
  v_own_agent   text;
  v_own jsonb; v_resp_key text; v_resp_choice text; v_rule_key text; v_rule_choice text; v_held bigint;
  v_block_wait boolean := false;
  v_awaiting jsonb := '[]'::jsonb;   -- meaning questions filed with the CEO seat (23 Sep 2026)
begin
  select o.id, o.dept_key, o.title, o.detail, o.action_class, o.result, o.tier, o.assigned_agent
    into t from org_tasks o where o.id = p_task_id;
  if t.id is null then
    return jsonb_build_object('error', 'no such task', 'task_id', p_task_id);
  end if;

  v_deliverable := coalesce(t.result->>'deliverable', '');
  if v_deliverable = '' then
    return jsonb_build_object('task_id', p_task_id, 'outcome', 'no_deliverable',
      'reason', 'The task carries no deliverable to review.');
  end if;

  -- WHO ACTUALLY WROTE IT (4 Sep 2026). This was `coalesce(d.brain_agent, d.lead_agent, dept_key)` —
  -- the department head, whoever performed the work. fn_pick_reviewer then correctly refuses to let a
  -- head approve its own output, and for the Office of the CEO there is nobody above the ceo, so every
  -- exec task escalated on an authorship nobody claimed. The row records its worker; read it.
  select coalesce(nullif(t.result->>'employee',''), nullif(t.assigned_agent,''),
                  d.brain_agent, d.lead_agent, t.dept_key)
    into v_author
    from org_departments d where d.dept_key = t.dept_key;
  if v_author is null then
    v_author := coalesce(nullif(t.result->>'employee',''), nullif(t.assigned_agent,''), t.dept_key);
  end if;

  -- STAGE 1+2: department head, then Chief of Staff. This is fn_review_submit unchanged — the
  -- reviewer is resolved live through delegation_rule and seniority, so a head who is unavailable
  -- delegates rather than silently approving.
  v_chain   := fn_review_submit('org_task', p_task_id::text, t.dept_key, v_author, v_deliverable);
  v_outcome := v_chain->>'outcome';

  -- STAGE 3: the challenge. Deterministic, so it runs on every task rather than being rationed.
  v_text := coalesce(t.title,'') || ' ' || coalesce(t.detail,'') || ' ' || coalesce(t.action_class,'');

  -- STAGE 0 OF THE RECORD, WRITTEN HERE: WHO OWNS THIS PROCESS.
  -- ROUTED, NOT REASONED (24 Sep 2026, it_engineer). model_policy task_class 'workflow_routing' is tier none:
  -- ownership follows the structure (the task's department and its operating system, via
  -- fn_task_ownership_record with no named responsibility), never a model and never a word. An answer the
  -- CEO seat already reasoned under the old path (ceo.task_responsibility) is still honoured by its key;
  -- no new question is filed. Was 5 think() calls / 24h (inventory 24 Sep 2026).
  v_resp_key := 'task_resp:' || p_task_id || ':' || md5(v_text);
  v_resp_choice := coalesce(public.fn_reason_route_answer(v_resp_key), 'none');
  v_own := public.fn_task_ownership_record(p_task_id, t.dept_key, v_author, nullif(v_resp_choice, 'none'));
  v_own_os := v_own->>'owned_by_os'; v_own_agent := v_own->>'owner_agent'; v_own_resp := v_own->>'owns_responsibility';
  for v_rule in
    select c.* from collaboration_rule c where c.owner_dept = t.dept_key
  loop
    -- WHETHER THE RULE'S SITUATION IS THIS TASK, REASONED (23 Sep 2026). Two shared long words decided it
    -- before. Measured 23 Sep 2026: collaboration_rule holds 0 rows, so this loop runs for nobody today.
    -- A rule reasoned to apply AFTER this review ran is recorded, with its challenges, by its apply routine;
    -- a BLOCKING one still waiting holds publication (v_block_wait below).
    v_rule_key := 'task_rule:' || p_task_id || ':' || v_rule.id || ':' || md5(v_text);
    v_rule_choice := public.fn_reason_route_answer(v_rule_key);
    if v_rule_choice is null then
      v_held := public.fn_reason_route_ask('ceo', 'ceo.task_collaboration_rule', v_text,
        jsonb_build_array(jsonb_build_object('id', 'applies', 'meaning', 'the task is the situation this rule governs: ' || v_rule.situation),
                          jsonb_build_object('id', 'does_not_apply', 'meaning', 'the task is not that situation')),
        jsonb_build_object('task_id', p_task_id, 'rule_id', v_rule.id, 'dept_key', t.dept_key, 'author', v_author), v_rule_key);
      v_awaiting := v_awaiting || jsonb_build_object('surface', 'ceo.task_collaboration_rule', 'rule_id', v_rule.id, 'held_id', v_held);
      if v_rule.blocking then v_block_wait := true; end if;
      continue;
    end if;
    if v_rule_choice <> 'applies' then continue; end if;
    v_rules_hit := v_rules_hit + 1;

    -- Who the rule says must take part, recorded as its own reviewable stage so that "this needed
    -- legal and legal never saw it" is answerable after the fact.
    v_involved := v_involved || jsonb_build_object(
      'situation', v_rule.situation, 'must_involve', to_jsonb(v_rule.must_involve),
      'must_review', to_jsonb(v_rule.must_review), 'blocking', v_rule.blocking);

    insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent,
                              stage, decision, reason, confidence)
    values ('org_task', p_task_id::text, t.dept_key, v_author,
            coalesce((v_rule.must_review)[1], 'exec'), 'collaboration',
            case when v_rule.blocking then 'required' else 'advisory' end,
            'collaboration_rule #' || v_rule.id || ' applies ("' || v_rule.situation || '"): '
              || 'involve ' || coalesce(array_to_string(v_rule.must_involve, ', '), '(none)')
              || '; review by ' || coalesce(array_to_string(v_rule.must_review, ', '), '(none)')
              || '; may be challenged by ' || coalesce(array_to_string(v_rule.may_challenge, ', '), '(none)')
              || '. Why this rule exists: ' || v_rule.reason, 1.0);

    -- Each department the rule permits to challenge actually challenges.
    foreach v_dept in array coalesce(v_rule.may_challenge, array[]::text[]) loop
      v_ch := fn_challenge(v_text, t.dept_key, v_dept);
      if (v_ch->>'stance') <> 'support' then
        v_dissents := v_dissents || jsonb_build_object(
          'by', v_dept, 'stance', v_ch->>'stance', 'confidence', v_ch->>'confidence',
          'reasoning', v_ch->>'reasoning', 'blocking', v_rule.blocking);

        insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent,
                                  stage, decision, reason, violated_rule, confidence)
        values ('org_task', p_task_id::text, t.dept_key, v_author, v_dept, 'challenge',
                case when v_rule.blocking and (v_ch->>'stance') = 'recommend_against'
                     then 'reject' else 'dissent' end,
                upper(v_ch->>'stance') || ' from ' || v_dept || ': ' || coalesce(v_ch->>'reasoning','')
                  || case when v_ch->'alternatives' <> '[]'::jsonb
                          then ' Alternative offered: ' || (v_ch->'alternatives'->>0) else '' end,
                v_ch->>'conflicts_with', (v_ch->>'confidence')::numeric);

        -- THE FOUNDER'S RULE, 6 Aug 2026: the blocking flag decides whether a rejection stops the
        -- work or is recorded against it. The reason is written either way.
        if v_rule.blocking and (v_ch->>'stance') = 'recommend_against' then
          v_blocked := true;
          v_blocker := v_dept || ' — ' || left(coalesce(v_ch->>'reasoning',''), 200);
        end if;
      end if;
    end loop;
  end loop;

  -- A BLOCKING rule whose situation is still being reasoned holds publication: the task rests until the
  -- answer (fn_reason_apply_ceo__task_collaboration_rule) records the rule and its challenges.
  if v_block_wait and not v_blocked and v_outcome in ('published', 'approve') then
    v_outcome := 'awaiting_reasoning';
  end if;

  if v_blocked and v_outcome in ('published', 'approve') then
    v_outcome := 'request_revision';
    insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent,
                              stage, decision, reason, confidence)
    values ('org_task', p_task_id::text, t.dept_key, v_author, 'brief', 'cos_review',
            'request_revision',
            'Returned for revision by the Chief of Staff: a BLOCKING collaboration rule was '
            || 'challenged and the challenge recommended against it. ' || v_blocker, 1.0);
  end if;

  -- "Every completed task should generate learning." Written here, by the reviewer, at the moment
  -- the verdict is known — the review already establishes what was wrong, so the lesson costs
  -- nothing. Never let recording the lesson fail the review itself.
  begin
    perform fn_task_lesson(p_task_id, v_outcome,
      jsonb_build_object('violations', coalesce(v_chain->'violations','[]'::jsonb),
                         'dissents',   v_dissents,
                         'reviewer',   v_chain->>'reviewer'));
  exception when others then null;
  end;

  return jsonb_build_object(
    'task_id',        p_task_id,
    'outcome',        v_outcome,
    'stopped_at',     v_chain->>'stopped_at',
    'author',         v_author,
    'reviewer',       v_chain->>'reviewer',
    'delegated_from', v_chain->>'delegated_from',
    'violations',     coalesce(v_chain->'violations', '[]'::jsonb),
    'unenforceable',  coalesce(v_chain->'unenforceable', '[]'::jsonb),
    'rules_applied',  v_rules_hit,
    'collaboration',  v_involved,
    'dissents',       v_dissents,
    'owned_by_os',    v_own_os,
    'owner_agent',    v_own_agent,
    'owns_responsibility', v_own_resp,
    'blocked',        v_blocked,
    'awaiting_reasoning', v_awaiting);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_taxonomy_trades_active()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('code', code, 'label', label) order by sort, code), '[]'::jsonb)
    from public.taxonomy_trade where active;
$function$


CREATE OR REPLACE FUNCTION public.fn_taxonomy_trades_for(p_slugs text[])
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- Each name resolves to itself (normalised) and to the taxonomy code(s) of the same trade. Never to a
  -- neighbour. A retired taxonomy code is dropped, so it never gates a match.
  select coalesce(array_agg(distinct x.code order by x.code), '{}'::text[])
    from (
      select public.fn_trade_code(s) as code
        from unnest(coalesce(p_slugs, '{}'::text[])) s
      union
      select unnest(m.trade_codes)
        from unnest(coalesce(p_slugs, '{}'::text[])) s
        join public.intake_trade_taxonomy m on public.fn_trade_code(m.intake_slug) = public.fn_trade_code(s)
    ) x
   where x.code is not null
     and not exists (select 1 from public.taxonomy_trade t where t.code = x.code and not t.active);
$function$


CREATE OR REPLACE FUNCTION public.fn_text_did_not_survive_reply(p_lang text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case when lower(coalesce(p_lang, 'en')) = 'ar' then
      'وصلتني رسالتكم وقد تحوّلت حروفها إلى علامات استفهام، فتعذّرت عليّ قراءة سؤالكم. '
      || 'لا خطأ في سؤالكم، وإنما لم يصل النص سليمًا عبر الاتصال. يُرجى إعادة إرسال الرسالة. '
      || 'وإن تكرر ذلك، يمكنكم الاتصال أو المراسلة عبر واتساب:' || E'\n'
      || E'‎' || '+971 50 931 9355' || E'\n'
      || '(من الاثنين إلى الجمعة، من 9 صباحًا حتى 6 مساءً بتوقيت الإمارات)' || E'\n'
      || 'أو البريد الإلكتروني:' || E'\n' || 'management@quotesdone.com'
    else
      'Your message reached me with its characters replaced by question marks, so I cannot read '
      || 'what you asked. Nothing is wrong with your question — it did not survive the connection. '
      || 'Please send it again. If it keeps happening, call or WhatsApp +971 50 931 9355 '
      || '(Mon-Fri, 9am-6pm GST) or email management@quotesdone.com.'
  end;
$function$


CREATE OR REPLACE FUNCTION public.fn_text_lost_its_script(p_text text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(
       p_text !~ '[^\x00-\x7F]'
   and (
         (    (select count(*) from regexp_matches(p_text, '[?][?]+', 'g')) >= 2
          and length(regexp_replace(p_text, '[^?]', '', 'g'))::numeric
                >= 0.30 * greatest(length(regexp_replace(p_text, '\s', '', 'g')), 1))
      or (select count(*) from regexp_matches(p_text, '[?]{4,}', 'g')) >= 3
      or p_text ~ '[?]{8,}'
       ),
  false);
$function$


CREATE OR REPLACE FUNCTION public.fn_trade_code(p_name text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select nullif(btrim(regexp_replace(lower(btrim(coalesce(p_name, ''))), '[^[:alnum:]]+', '_', 'g'), '_'), '');
$function$


CREATE OR REPLACE FUNCTION public.fn_trade_label(p_code text, p_lang text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce((select case when p_lang = 'ar' then coalesce(t.label_ar, t.label) else t.label end
                     from public.taxonomy_trade t where t.code = lower(btrim(p_code))),
                  nullif(initcap(replace(btrim(coalesce(p_code, '')), '_', ' ')), ''))
$function$


CREATE OR REPLACE FUNCTION public.fn_trade_licence_key(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select nullif(regexp_replace(upper(coalesce(p, '')), '[^[:alnum:]]+', '', 'g'), '')
$function$


CREATE OR REPLACE FUNCTION public.fn_trade_proposal_decide(p_id bigint, p_decision text, p_code text DEFAULT NULL::text, p_label_en text DEFAULT NULL::text, p_label_ar text DEFAULT NULL::text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.taxonomy_trade_proposal; v_label text;
begin
  select * into r from public.taxonomy_trade_proposal where id = p_id for update;
  if r.id is null then raise exception 'fn_trade_proposal_decide: no proposal %', p_id; end if;
  if r.status not in ('pending', 'map_offered') then
    raise exception 'fn_trade_proposal_decide: proposal % is already %', p_id, r.status;
  end if;

  if p_decision = 'add' then
    -- Under the SUPPLIER'S code, never another: suppliers who confirmed this trade already hold it
    -- in supplier_capabilities.trades, and a different code would silently unmatch them.
    -- Siblings (other suppliers' PENDING proposals of the same code) are locked in id order first, so
    -- two concurrent 'add' decisions on one code queue instead of deadlocking.
    perform 1 from public.taxonomy_trade_proposal where code = r.code and status = 'pending' order by id for update;
    v_label := coalesce(nullif(btrim(p_label_en), ''), nullif(r.label_en, ''), r.label_ar);
    insert into public.taxonomy_trade (code, label, label_ar, aliases, sort, active)
    values (r.code, v_label, coalesce(nullif(btrim(p_label_ar), ''), r.label_ar),
            array_remove(array[lower(nullif(btrim(coalesce(p_label_en, r.label_en)), ''))], null), 900, true)
    on conflict (code) do nothing;
    update public.taxonomy_trade_proposal
       set status = 'added', mapped_to = null, decided_at = now(), decided_by = 'sales_engineer', note = coalesce(p_note, note)
     where id = r.id;
    -- Other suppliers' PENDING rows of the same code are now in the list too; they are marked as a
    -- consequence, with a system note naming the decision, never with this decision's note. A
    -- map_offered row is a separate decision for that supplier and is left alone.
    update public.taxonomy_trade_proposal
       set status = 'added', decided_at = now(), decided_by = 'sales_engineer',
           note = 'auto: code added to taxonomy_trade by proposal #' || r.id
     where code = r.code and status = 'pending' and id <> r.id;
  elsif p_decision = 'offer_map' then
    if not exists (select 1 from public.taxonomy_trade where code = p_code and active) then
      raise exception 'fn_trade_proposal_decide: % is not an active trade', p_code;
    end if;
    update public.taxonomy_trade_proposal
       set status = 'map_offered', mapped_to = p_code, decided_at = now(), decided_by = 'sales_engineer', note = coalesce(p_note, note)
     where id = r.id;
  elsif p_decision = 'reject' then
    update public.taxonomy_trade_proposal
       set status = 'rejected', mapped_to = null, decided_at = now(), decided_by = 'sales_engineer', note = coalesce(p_note, note)
     where id = r.id;
  else
    raise exception 'fn_trade_proposal_decide: decision must be add, offer_map or reject, not %', p_decision;
  end if;
  return (select to_jsonb(x) from public.taxonomy_trade_proposal x where x.id = r.id);
end $function$


CREATE OR REPLACE FUNCTION public.fn_trade_spec_checklist(p_category text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('topic_id', c.topic_id, 'topic', c.topic, 'specs', c.specs) order by c.trade_code, c.topic_id), '[]'::jsonb)
    from public.trade_spec_checklist c
   where c.trade_code = p_category
      or c.trade_code = any(coalesce(public.fn_taxonomy_trades_for(array[p_category]), '{}'::text[]))
$function$


CREATE OR REPLACE FUNCTION public.fn_transaction_attach_invoice(p_transaction_id uuid, p_invoice jsonb, p_doc_path text DEFAULT NULL::text, p_doc_name text DEFAULT NULL::text, p_doc_content_type text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_inv_id   text := nullif(btrim(coalesce(p_invoice->>'id','')), '');
  v_pdf      text := nullif(btrim(coalesce(p_invoice->>'invoice_pdf','')), '');
  v_hosted   text := nullif(btrim(coalesce(p_invoice->>'hosted_invoice_url','')), '');
  v_path     text := nullif(btrim(coalesce(p_doc_path,'')), '');
  v_existing public.transactions%rowtype;
  v_rows     integer;
begin
  if p_transaction_id is null then
    return jsonb_build_object('ok', false, 'reason', 'no transaction id');
  end if;
  if v_inv_id is null then
    return jsonb_build_object('ok', false, 'reason', 'the invoice object carries no id');
  end if;
  -- A Stripe Invoice id is in_...; anything else is not the object this column names, and a column
  -- the accountant reconciles against Stripe must not hold something Stripe cannot resolve.
  if v_inv_id !~ '^in_[A-Za-z0-9_]+$' then
    return jsonb_build_object('ok', false, 'reason', 'not a stripe invoice id',
                              'given', left(v_inv_id, 60));
  end if;

  -- Both links are opened as evidence by the founder and the CEO. A spoofed payload may not aim
  -- them anywhere but Stripe. Same pattern fn_refund_attach_receipt uses, and it refuses lookalikes
  -- such as stripe.com.evil.example because the host must END at stripe.com before the first slash.
  if v_pdf is not null and v_pdf !~ '^https://[a-z0-9.-]*\.?stripe\.com/' then
    return jsonb_build_object('ok', false, 'reason', 'invoice_pdf is not a stripe.com url',
                              'given', left(v_pdf, 120));
  end if;
  if v_hosted is not null and v_hosted !~ '^https://[a-z0-9.-]*\.?stripe\.com/' then
    return jsonb_build_object('ok', false, 'reason', 'hosted_invoice_url is not a stripe.com url',
                              'given', left(v_hosted, 120));
  end if;

  -- The stored object is named by its PREFIX, not by a free path. A caller that could name any path
  -- in finance-docs could make this row point at another record's document.
  if v_path is not null and v_path !~ '^invoices/' then
    return jsonb_build_object('ok', false, 'reason', 'a stored invoice must live under invoices/ in finance-docs',
                              'given', left(v_path, 120));
  end if;

  select * into v_existing from public.transactions where id = p_transaction_id;
  if not found then
    return jsonb_build_object('ok', false,
             'reason', format('no transaction %s', p_transaction_id));
  end if;

  -- WRITE-ONCE ON IDENTITY. The first invoice a sale was billed under is the one it stays billed
  -- under; a second, different invoice id is a fact about a different sale and is refused rather
  -- than allowed to overwrite the reference the books were reconciled against.
  if coalesce(v_existing.stripe_invoice_id, '') <> '' and v_existing.stripe_invoice_id <> v_inv_id then
    return jsonb_build_object('ok', false, 'reason', 'this transaction is already billed under another invoice',
                              'existing', v_existing.stripe_invoice_id, 'given', v_inv_id);
  end if;

  -- The FILE may arrive after the REFERENCE -- Stripe finalises the PDF moments after the session
  -- completes -- so the document columns fill in on a later call without disturbing what is set.
  update public.transactions t set
    stripe_invoice_id         = v_inv_id,
    stripe_invoice_number     = coalesce(nullif(btrim(coalesce(p_invoice->>'number','')),''), t.stripe_invoice_number),
    stripe_invoice_status     = coalesce(nullif(btrim(coalesce(p_invoice->>'status','')),''), t.stripe_invoice_status),
    stripe_invoice_total_fils = coalesce((p_invoice->>'total')::bigint, t.stripe_invoice_total_fils),
    stripe_invoice_currency   = coalesce(upper(nullif(btrim(coalesce(p_invoice->>'currency','')),'')), t.stripe_invoice_currency),
    stripe_invoice_pdf_url    = coalesce(v_pdf, t.stripe_invoice_pdf_url),
    stripe_invoice_hosted_url = coalesce(v_hosted, t.stripe_invoice_hosted_url),
    doc_path                  = coalesce(t.doc_path, v_path),
    doc_name                  = coalesce(t.doc_name, nullif(btrim(coalesce(p_doc_name,'')),'')),
    doc_content_type          = coalesce(t.doc_content_type, nullif(btrim(coalesce(p_doc_content_type,'')),'')),
    doc_kind                  = case when t.doc_path is null and v_path is not null then 'stripe_invoice'
                                     else t.doc_kind end
  where t.id = p_transaction_id;
  get diagnostics v_rows = row_count;

  return jsonb_build_object(
    'ok', v_rows > 0,
    'transaction_id', p_transaction_id,
    'invoice_id', v_inv_id,
    'stored', v_path is not null or coalesce(v_existing.doc_path,'') <> '',
    'state', (select document_state from public.v_revenue_documents where id = p_transaction_id));
end
$function$


CREATE OR REPLACE FUNCTION public.fn_transaction_refund_outcome_follows_through()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.refund_status in ('succeeded', 'refunded') and NEW.refund_amount_aed is not null
     and (OLD.refund_status is distinct from NEW.refund_status or OLD.refund_amount_aed is distinct from NEW.refund_amount_aed) then
    begin
      perform public.fn_accountant_refund_settled(NEW.id);
    exception when others then
      insert into public.ceo_task (title, detail)
      values (left('Refund on reveal ' || left(NEW.id::text, 8) || ' settled but its follow-through failed', 200),
              'fn_accountant_refund_settled raised: ' || sqlerrm || '. The refund itself is recorded; the supplier charge, the customer''s message or the re-verification did not complete.');
    end;
  elsif NEW.refund_status = 'failed' and OLD.refund_status is distinct from 'failed' then
    perform public.fn_ceo_refund_verify(NEW.id);
  elsif NEW.refund_status = 'rejected' and OLD.refund_status is distinct from 'rejected' then
    perform public.fn_seat_handoff('accountant', 'sales_engineer', 'refund.declined', 'transactions', NEW.id::text,
      jsonb_build_object('transaction_id', NEW.id, 'customer_id', NEW.customer_id, 'inquiry_id', NEW.inquiry_id,
                         'quote_id', NEW.quote_id, 'note', NEW.refund_note));
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.fn_twilio_error_in_plain_words(p_code text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case nullif(btrim(coalesce(p_code, '')), '')
    when '63016' then 'outside the 24-hour window: the recipient has not messaged us in the last 24 hours, so WhatsApp accepts only an approved template, not free text'
    when '63024' then 'not a usable WhatsApp account: the number is not on WhatsApp, has not accepted WhatsApp''s terms, or runs an outdated app'
    when '63003' then 'the number could not be found on WhatsApp: wrong, inactive or not registered'
    when '63032' then 'WhatsApp will not deliver to this user because of a WhatsApp restriction on the recipient'
    when '63033' then 'the recipient has opted out of receiving these messages'
    when '63049' then 'Meta chose not to deliver it (its per-user limit on marketing messages)'
    when '63050' then 'the recipient has opted out of marketing messages on WhatsApp'
    when '63013' then 'WhatsApp refused it as a policy violation'
    when '63018' then 'our WhatsApp sender hit its rate limit, so the message was not delivered'
    when '63027' then 'the template does not exist at Meta in this language'
    when '63028' then 'the template was sent with the wrong number of variables'
    when '63040' then 'Meta rejected the template'
    when '63041' then 'Meta paused the template (low quality)'
    when '63042' then 'Meta disabled the template'
    when '63051' then 'Meta has locked our WhatsApp sender or account'
    when '63112' then 'Meta has disabled the WhatsApp Business Account behind our sender'
    when '30003' then 'the phone is unreachable (switched off or out of coverage)'
    when '30005' then 'the number does not exist or is not assigned to anyone'
    when '30006' then 'the number is a landline or cannot receive SMS'
    when '30007' then 'the carrier filtered it as unwanted'
    when '30008' then 'the carrier reported an unknown delivery error'
    else case when p_code is null or btrim(p_code) = '' then null
              else 'Twilio error ' || btrim(p_code) || ' (twilio.com/docs/api/errors/' || btrim(p_code) || ')' end
  end
$function$


CREATE OR REPLACE FUNCTION public.fn_twilio_status_arrived(p_sid text, p_status text, p_error_code text DEFAULT NULL::text, p_source text DEFAULT 'callback'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  n public.notifications; v_status text := lower(btrim(coalesce(p_status, ''))); v_code text := nullif(btrim(coalesce(p_error_code, '')), '');
  v_final_fail boolean;
begin
  if coalesce(btrim(p_sid), '') = '' then return jsonb_build_object('matched', false, 'applied', false, 'reason', 'no MessageSid'); end if;
  if public.fn_twilio_status_rank(v_status) = 0 then
    return jsonb_build_object('matched', null, 'applied', false, 'reason', 'not a status this estate records: ' || left(v_status, 40));
  end if;
  select * into n from public.notifications
   where provider_message_id = btrim(p_sid) and channel in ('whatsapp', 'sms')
   order by id limit 1 for update;
  if n.id is null then return jsonb_build_object('matched', false, 'applied', false); end if;
  if public.fn_twilio_status_rank(v_status) <= public.fn_twilio_status_rank(n.provider_status) then
    return jsonb_build_object('matched', true, 'applied', false, 'notification_id', n.id, 'kept', n.provider_status, 'ignored', v_status);
  end if;
  v_final_fail := v_status in ('failed', 'undelivered');
  update public.notifications
     set provider_status = v_status, provider_status_at = now(),
         provider_error_code = coalesce(v_code, provider_error_code),
         status = case when v_final_fail and status = 'sent' then 'failed' else status end,
         last_error = case when v_final_fail
                           then left('Twilio reported ' || v_status || coalesce(' (error ' || v_code || ')', '') || ': '
                                     || coalesce(public.fn_twilio_error_in_plain_words(v_code), 'no error code was given'), 500)
                           else last_error end
   where id = n.id;
  return jsonb_build_object('matched', true, 'applied', true, 'notification_id', n.id, 'from', n.provider_status, 'to', v_status,
                            'failed', v_final_fail, 'error_code', v_code, 'source', left(coalesce(p_source, ''), 20));
end $function$


CREATE OR REPLACE FUNCTION public.fn_twilio_status_poll_claim(p_limit integer DEFAULT 20)
 RETURNS TABLE(notification_id bigint, sid text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  return query
  update public.notifications u set provider_status_checked_at = now()
   where u.id in (select c.id from public.notifications c
                   where c.channel in ('whatsapp', 'sms') and coalesce(btrim(c.provider_message_id), '') <> ''
                     and c.sent_at < now() - interval '30 minutes'
                     and public.fn_twilio_status_rank(c.provider_status) < 4
                     and coalesce(c.provider_status, '') <> 'unreadable'
                     and (c.provider_status_checked_at is null or c.provider_status_checked_at < now() - interval '30 minutes')
                   order by coalesce(c.provider_status_checked_at, c.sent_at)
                   limit least(greatest(coalesce(p_limit, 20), 1), 50)
                   for update skip locked)
  returning u.id, u.provider_message_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_twilio_status_poll_failed(p_notification_id bigint, p_http integer DEFAULT NULL::integer, p_code text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c_give_up constant int := 5;   -- 5 x 30 minutes: 2.5 hours of trying before we stop asking.
  n public.notifications; v_fails int; v_gave_up boolean;
begin
  select * into n from public.notifications where id = p_notification_id for update;
  if n.id is null then return jsonb_build_object('matched', false); end if;
  if public.fn_twilio_status_rank(n.provider_status) >= 4 then
    return jsonb_build_object('matched', true, 'applied', false, 'reason', 'already final: ' || n.provider_status);
  end if;
  v_fails := coalesce(n.provider_poll_failures, 0) + 1;
  v_gave_up := v_fails >= c_give_up;
  update public.notifications
     set provider_poll_failures = v_fails,
         provider_status = case when v_gave_up then 'unreadable' else provider_status end,
         provider_status_at = case when v_gave_up then now() else provider_status_at end,
         provider_error_code = coalesce(nullif(btrim(coalesce(p_code, '')), ''), provider_error_code),
         last_error = left('Twilio could not be read for this message: '
                           || coalesce('HTTP ' || p_http::text, 'no HTTP response')
                           || coalesce(', Twilio code ' || nullif(btrim(coalesce(p_code, '')), ''), '')
                           || ' (attempt ' || v_fails || ' of ' || c_give_up || ')'
                           || case when v_gave_up then ' — given up: the delivery of this message is unknown.' else '' end, 500)
   where id = n.id;
  return jsonb_build_object('matched', true, 'applied', true, 'failures', v_fails, 'gave_up', v_gave_up,
                            'give_up_after', c_give_up, 'http', p_http, 'code', nullif(btrim(coalesce(p_code, '')), ''));
end $function$


CREATE OR REPLACE FUNCTION public.fn_twilio_status_rank(p_status text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case lower(coalesce(p_status, ''))
    when 'accepted' then 1 when 'scheduled' then 1 when 'queued' then 1
    when 'sending' then 2 when 'sent' then 3
    when 'delivered' then 4 when 'undelivered' then 4 when 'failed' then 4
    when 'read' then 5 else 0 end
$function$


CREATE OR REPLACE FUNCTION public.fn_twin(p_kind text, p_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare res jsonb;
begin
  if p_kind='customer' then
    select jsonb_build_object('kind','customer','id',c.id,'name',c.full_name,'email',c.email,
      'industry',c.industry,
      'rfqs',(select count(*) from inquiries where customer_id=c.id),
      'deals',(select count(*) from transactions where customer_id=c.id),
      'spend_aed',(select coalesce(sum(reveal_fee),0) from transactions where customer_id=c.id and coalesce(fee_status,'')='paid'),
      'categories',(select coalesce(jsonb_agg(distinct category),'[]') from inquiries where customer_id=c.id),
      -- BUYING PATTERNS (§2) — categories ORDERED BY how often the customer actually buys them,
      -- with the count beside each. `categories` above is a set and a set is not a pattern.
      'preferred_categories',(select coalesce(jsonb_agg(jsonb_build_object('category',k.category,'rfqs',k.n) order by k.n desc),'[]')
         from (select category, count(*) n from inquiries where customer_id=c.id and category is not null
               group by category order by count(*) desc limit 8) k),
      'projects_active',(select count(*) from projects
         where customer_id=c.id and coalesce(status,'') not in ('closed','cancelled','completed','done')),
      'projects_total',(select count(*) from projects where customer_id=c.id),
      -- PREFERRED SUPPLIERS (§2) — the suppliers this customer has actually paid to reveal. A
      -- preference the customer demonstrated, not one they were asked to declare.
      'preferred_suppliers',(select count(distinct supplier_id) from transactions
         where customer_id=c.id and coalesce(fee_status,'')='paid' and supplier_id is not null),
      -- (No approval_chain key since 14 Sep 2026: the Approvals tab and the organisation/policy
      -- tables it read were removed — a company buys exactly like an individual. See
      -- a_company_buys_like_an_individual_so_the_approval_chain_is_dropped.sql.)
      'last_active',(select max(created_at) from inquiries where customer_id=c.id),
      -- AI UNDERSTANDING (§2) — the share of eight profile facts held, and ONLY once the customer
      -- has raised a request. Before that there is no buying behaviour to understand, and a tally of
      -- sign-up fields is not understanding (see the header of this file).
      'understanding_pct',(case when exists (select 1 from inquiries where customer_id=c.id) then
         (select round(100.0 * (
             (c.full_name is not null and c.full_name <> '')::int
           + (c.phone is not null and c.phone <> '')::int
           + coalesce(c.email_verified,false)::int
           + (c.tos_accepted_at is not null)::int
           + (c.locale is not null)::int
           + (c.industry is not null and c.industry <> '')::int
           + 1
           + (exists (select 1 from customer_preference cp where cp.customer_id=c.id))::int
         ) / 8.0)) end),
      'banned',c.banned) into res from customers c where c.id::text=p_id;

  elsif p_kind='rfq' then
    select jsonb_build_object('kind','rfq','id',i.id,'category',i.category,'emirate',i.emirate,'status',i.status,
      'completeness',i.completeness,'ready',i.rfq_ready,'budget',i.budget,
      'quotes',(select count(*) from quotes where inquiry_id=i.id),
      'avg_quote_quality',(select round(avg(nullif(quality->>'score','')::numeric),1) from quotes where inquiry_id=i.id),
      'matched_suppliers',(select count(*) from inquiry_matches where inquiry_id=i.id),
      'created',i.created_at,'completed',i.completed_at,'outcome',i.outcome) into res from inquiries i where i.id::text=p_id;

  elsif p_kind='category' then
    res := jsonb_build_object('kind','category','category',p_id,
      'demand_rfqs',(select count(*) from inquiries where category=p_id),
      -- The supplier's trade as REASONED from its own record (lead_trade_class, 23 Sep 2026), never a substring of
      -- the free-text categories column (which holds company names as often as trades, measured 23 Sep 2026).
      'approved_suppliers',(select count(*) from leads l join lead_trade_class c on c.lead_id = l.id
         where coalesce(l.approval_status,'')='approved' and c.trade_code = lower(btrim(p_id))),
      'supplier_pool_total',(select count(*) from lead_trade_class c where c.trade_code = lower(btrim(p_id))),
      'supplier_pool_unclassified',(select count(*) from leads l where not exists (select 1 from lead_trade_class c where c.lead_id = l.id)),
      'avg_quote_quality',(select round(avg(nullif(q.quality->>'score','')::numeric),1) from quotes q join inquiries i on i.id=q.inquiry_id where i.category=p_id),
      'agent',public.fn_resolve_cat_agent(p_id));

  elsif p_kind='company' then
    res := jsonb_build_object('kind','company','name','QuotesDone',
      'health',public.fn_health_index(),
      'suppliers_total',(select count(*) from leads),'suppliers_approved',(select count(*) from leads where coalesce(approval_status,'')='approved'),
      'customers',(select count(*) from customers),'rfqs',(select count(*) from inquiries),'quotes',(select count(*) from quotes),
      'revenue_paid_aed',(select coalesce(sum(reveal_fee),0) from transactions where coalesce(fee_status,'')='paid'),
      'eval',public.fn_eval_snapshot(30));
  else
    res := jsonb_build_object('error','kind must be customer|rfq|category|company');
  end if;
  return coalesce(res, jsonb_build_object('error','not found','kind',p_kind,'id',p_id));
end $function$


CREATE OR REPLACE FUNCTION public.fn_ui_label(p_domain text, p_key text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select coalesce(
           (select l.label from public.ui_label l
             where l.domain = p_domain and l.key = p_key),
           -- No row: humanise rather than blank. 'supplier_risk_complaints' -> 'Supplier Risk
           -- Complaints'. Worse than a written label, better than showing the founder a key, and
           -- v_ui_label_missing reports that it happened.
           nullif(initcap(replace(coalesce(p_key, ''), '_', ' ')), ''),
           'Unlabelled');
$function$


CREATE OR REPLACE FUNCTION public.fn_unfinished_signup_purge(p_apply boolean DEFAULT false, p_limit integer DEFAULT 20, p_only_email text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c record; v_id bigint; v_n int; v_out jsonb := '[]'::jsonb; v_cnt jsonb; v_auth uuid; v_email text; v_keep boolean;
  n_done int := 0; n_held int := 0;
begin
  -- ── customers ──
  for c in
    select cu.id, lower(cu.email) email, cu.phone,
           least(cu.created_at, coalesce((select min(u.created_at) from auth.users u where lower(u.email) = lower(cu.email)), cu.created_at)) started,
           array_remove(array[case when not coalesce(cu.email_verified, false) then 'email' end,
                               case when not coalesce(cu.phone_verified, false) then 'mobile' end,
                               case when cu.tos_accepted_at is null then 'terms' end,
                               case when cu.tos_ip is null then 'terms_ip' end], null) missing,
           public.fn_signup_customer_held(cu.id) busy
      from public.customers cu
     where (p_only_email is null and not coalesce(cu.is_demo, false)) or lower(cu.email) = lower(p_only_email)
  loop
    continue when cardinality(c.missing) = 0;                       -- complete: never touched
    continue when c.started > now() - interval '30 minutes';        -- still inside its 30 minutes
    if c.busy then n_held := n_held + 1; v_out := v_out || jsonb_build_object('kind', 'customer', 'held', 'has a request, a sale, an upload, a draft, a signature or a conversation', 'missing', c.missing); continue; end if;
    exit when n_done >= greatest(1, least(coalesce(p_limit, 20), 200));
    if not p_apply then
      n_done := n_done + 1; v_out := v_out || jsonb_build_object('kind', 'customer', 'missing', c.missing, 'started', c.started); continue;
    end if;
    insert into public.signup_purge (kind, subject_ref, started_at, missing)
    values ('customer', encode(sha256(convert_to(coalesce(c.email, c.id::text), 'UTF8')), 'hex'), c.started, c.missing) returning id into v_id;
    -- the partial uploads: what storage still holds for this sign-up (removed through the storage API)
    insert into public.signup_purge_object (purge_id, bucket, path)
    select v_id, x.bucket, x.path from (
      select 'signed-terms' bucket, cu.signed_terms_path path from public.customers cu where cu.id = c.id and cu.signed_terms_path is not null
      union select o.bucket_id, o.name from storage.objects o where o.bucket_id = 'drawing-files' and o.name like 'drawings/' || c.id || '/%'
      union select d.bucket, d.path from public.doc_backups d where d.entity = 'customer' and d.entity_id = c.id::text and d.bucket is not null and d.path is not null
    ) x where x.path is not null on conflict do nothing;
    -- the backups: Dropbox copies and records go too (dropbox_backup deletes the listed copies)
    v_cnt := public.fn_signup_purge_backups(v_id, 'customer', c.id::text);
    v_keep := public.fn_signup_email_kept_elsewhere(c.email, 'customer');
    if not v_keep then
      -- by e-mail only (the mobile was never verified), and only when no other account of this e-mail stays
      delete from public.notifications n where lower(n.to_email) = c.email;
      get diagnostics v_n = row_count; v_cnt := v_cnt || jsonb_build_object('outbox', v_n);
      delete from public.email_verifications e where lower(e.email) = c.email;
      get diagnostics v_n = row_count; v_cnt := v_cnt || jsonb_build_object('email_otp', v_n);
      delete from public.phone_verifications p where lower(p.email) = c.email;
      get diagnostics v_n = row_count; v_cnt := v_cnt || jsonb_build_object('phone_otp', v_n);
    else
      v_cnt := v_cnt || jsonb_build_object('outbox', 0, 'email_otp', 0, 'phone_otp', 0, 'login', 'kept: another account of this e-mail is complete or held');
    end if;
    delete from public.inquiry_intake ii where ii.customer_id = c.id or lower(ii.email) = c.email;
    delete from public.drawing_redaction_runs r where r.customer_id = c.id or lower(r.owner_email) = c.email;
    delete from public.customer_preference p where p.customer_id = c.id;
    delete from public.customer_layout l where l.customer_id = c.id;
    delete from public.company_event e where e.entity_type = 'customer' and e.entity_id = c.id::text;
    delete from public.customers cu where cu.id = c.id;               -- customer_phone_otps and company_review_ask cascade
    -- the login is kept while another account of this e-mail is complete or held
    if not v_keep then
      delete from auth.users u where lower(u.email) = c.email;        -- sessions, identities and refresh tokens cascade
      get diagnostics v_n = row_count;
    else v_n := 0; end if;
    v_cnt := v_cnt || jsonb_build_object('auth_users', v_n);
    update public.signup_purge set counts = v_cnt || jsonb_build_object('objects', (select count(*) from public.signup_purge_object where purge_id = v_id)) where id = v_id;
    n_done := n_done + 1; v_out := v_out || jsonb_build_object('kind', 'customer', 'purge_id', v_id, 'missing', c.missing, 'counts', v_cnt);
  end loop;

  -- ── suppliers (a claimed company whose owner's sign-up is unfinished) ──
  for c in
    select l.id, lower(l.claimed_by) email, l.source,
           (l.invited_at is not null or l.invite_status is not null or coalesce(l.source, '') <> 'self_registered') invited,
           least(coalesce(l.portal_updated_at, l.created_at, now()), coalesce((select min(u.created_at) from auth.users u where lower(u.email) = lower(l.claimed_by)), now())) started,
           array_remove(array[case when not coalesce(l.owner_email_verified, false) then 'email' end,
                               case when not coalesce(l.owner_phone_verified, false) then 'mobile' end,
                               case when l.accepted_terms_at is null then 'terms' end,
                               case when l.accepted_terms_ip is null then 'terms_ip' end], null) missing,
           public.fn_signup_supplier_held(l.id) busy
      from public.leads l
     where l.claimed_by is not null
       and ((p_only_email is null and not coalesce(l.is_demo, false)) or lower(l.claimed_by) = lower(p_only_email))
  loop
    continue when cardinality(c.missing) = 0;
    continue when c.started > now() - interval '30 minutes';
    if c.busy then n_held := n_held + 1; v_out := v_out || jsonb_build_object('kind', 'supplier', 'held', 'has a quote, a sale, a match, an upload, a signature or a conversation', 'missing', c.missing); continue; end if;
    exit when n_done >= greatest(1, least(coalesce(p_limit, 20), 200));
    if not p_apply then
      n_done := n_done + 1; v_out := v_out || jsonb_build_object('kind', case when c.invited then 'supplier_invited_lead' else 'supplier_self_registered' end, 'missing', c.missing, 'started', c.started); continue;
    end if;
    insert into public.signup_purge (kind, subject_ref, started_at, missing)
    values (case when c.invited then 'supplier_invited_lead' else 'supplier_self_registered' end,
            encode(sha256(convert_to(coalesce(c.email, c.id::text), 'UTF8')), 'hex'), c.started, c.missing) returning id into v_id;
    v_email := c.email;
    v_keep := public.fn_signup_email_kept_elsewhere(v_email, 'supplier', c.id);
    v_cnt := '{}'::jsonb;
    if not v_keep then
      delete from public.email_verifications e where lower(e.email) = v_email;
      delete from public.phone_verifications p where lower(p.email) = v_email;
      -- an invited lead's mail is the campaign's (its invitation and follow-ups): never deleted; a self-registered
      -- company's mail to this address is the sign-up's own
      if not c.invited then
        delete from public.notifications n where lower(n.to_email) = v_email;
        get diagnostics v_n = row_count; v_cnt := jsonb_build_object('outbox', v_n);
      else v_cnt := jsonb_build_object('outbox', 0, 'outbox_kept', 'campaign mail of an invited lead'); end if;
    else
      v_cnt := jsonb_build_object('outbox', 0, 'login', 'kept: another account of this e-mail is complete or held');
    end if;
    if c.invited then
      -- campaign data stays: the lead goes back to the pool, unclaimed, with nothing of the sign-up on it
      update public.leads l set claimed = false, claimed_by = null, owner_email_verified = false, owner_phone_verified = false,
             owner_dob = null, accepted_terms_at = null, accepted_terms_version = null, accepted_terms_ip = null,
             accepted_terms_sha256 = null, accepted_terms_user_agent = null, signed_terms_path = null, portal_updated_at = now()
       where l.id = c.id;
      v_cnt := v_cnt || jsonb_build_object('lead', 'returned to the invited pool');
      -- what the sign-up uploaded or produced goes, as for any unfinished sign-up (policy 1.6 "deleted in full")
      insert into public.signup_purge_object (purge_id, bucket, path)
      select v_id, o.bucket_id, o.name from storage.objects o where o.bucket_id = 'supplier-docs' and split_part(o.name, '/', 2) = c.id::text
      on conflict do nothing;
      v_cnt := v_cnt || public.fn_signup_purge_backups(v_id, 'supplier', c.id::text);
      update public.leads l set license_doc_path = null, egr_doc_path = null, insurance_doc_path = null, vat_doc_path = null,
             iso_doc_path = null, manufacturer_auth_doc_path = null, company_profile_doc_path = null, catalog_doc_paths = null
       where l.id = c.id;
    else
      insert into public.signup_purge_object (purge_id, bucket, path)
      select v_id, d.bucket, d.path from public.doc_backups d
       where d.entity = 'supplier' and d.entity_id = c.id::text and d.bucket is not null and d.path is not null
      union select v_id, o.bucket_id, o.name from storage.objects o where o.bucket_id = 'supplier-docs' and split_part(o.name, '/', 2) = c.id::text
      on conflict do nothing;
      v_cnt := v_cnt || public.fn_signup_purge_backups(v_id, 'supplier', c.id::text);
      begin
        delete from public.leads l where l.id = c.id;
        v_cnt := v_cnt || jsonb_build_object('lead', 'removed');
      exception when foreign_key_violation then
        -- something else already points at the company: it is unclaimed instead, and the purge says so
        update public.leads l set claimed = false, claimed_by = null, owner_email_verified = false, owner_phone_verified = false,
               owner_dob = null, accepted_terms_at = null, accepted_terms_version = null, accepted_terms_ip = null,
               accepted_terms_sha256 = null, accepted_terms_user_agent = null, signed_terms_path = null, portal_updated_at = now()
         where l.id = c.id;
        v_cnt := v_cnt || jsonb_build_object('lead', 'unclaimed (still referenced: ' || left(sqlerrm, 120) || ')');
      end;
    end if;
    if not v_keep then
      delete from auth.users u where lower(u.email) = v_email;
      get diagnostics v_n = row_count;
    else v_n := 0; end if;
    v_cnt := v_cnt || jsonb_build_object('auth_users', v_n);
    update public.signup_purge set counts = v_cnt where id = v_id;
    n_done := n_done + 1; v_out := v_out || jsonb_build_object('kind', 'supplier', 'purge_id', v_id, 'missing', c.missing, 'counts', v_cnt);
  end loop;

  -- the customer register is rebuilt from the table when a customer row went (audit 12 Oct: it listed 7 for 6)
  if p_apply and p_only_email is null and exists (select 1 from jsonb_array_elements(v_out) i where i->>'kind' = 'customer' and i ? 'purge_id') then
    begin
      perform net.http_post('https://' || public.qd_project_ref() || '.supabase.co/functions/v1/compliance_archive',
        jsonb_build_object('__secret', (select value from public.app_secrets where key = 'cred_db_internal'), 'action', 'register'),
        '{}'::jsonb, '{"Content-Type":"application/json"}'::jsonb, 60000);
    exception when others then null;    -- the register is rebuilt again at the next registration
    end;
  end if;
  if p_apply and n_done > 0 and p_only_email is null then
    -- counts only: no name, no e-mail, no file (the coordinator, 12 Oct 2026)
    insert into public.agent_actions (agent, kind, status, risk, title, detail, decided_at, decided_by)
    values ('it_engineer', 'signup_purge', 'done', 'low', 'Unfinished sign-ups removed (founder ruling 1181)',
            jsonb_build_object('removed', n_done, 'held', n_held,
              'customers', (select count(*) from jsonb_array_elements(v_out) i where i->>'kind' = 'customer' and i ? 'purge_id'),
              'suppliers', (select count(*) from jsonb_array_elements(v_out) i where i->>'kind' = 'supplier' and i ? 'purge_id')),
            now(), 'it_engineer');
  end if;
  return jsonb_build_object('apply', p_apply, 'removed', n_done, 'held', n_held, 'items', v_out);
end $function$


CREATE OR REPLACE FUNCTION public.fn_usd_to_aed()
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$ select 3.672450::numeric $function$


CREATE OR REPLACE FUNCTION public.fn_vat_threshold_fraction_reached(p_turnover_aed numeric)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select max(e::numeric)
    from public.decision_policy d, jsonb_array_elements_text(d.value) e
   where d.key = 'vat_threshold_report_fractions'
     and coalesce(p_turnover_aed, 0) >= e::numeric * (select num_value from public.gl_settings where key = 'vat_registration_threshold_aed');
$function$


CREATE OR REPLACE FUNCTION public.fn_vat_threshold_position(p_turnover_aed numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_thr numeric; v_frac numeric; v_band text;
begin
  select num_value into v_thr  from public.gl_settings where key = 'vat_registration_threshold_aed';
  select num_value into v_frac from public.gl_settings where key = 'vat_threshold_warn_fraction';
  if v_thr is null then
    raise exception 'gl_settings.vat_registration_threshold_aed is missing; refusing to decide a tax obligation against a threshold nobody set';
  end if;

  v_band := case
    when p_turnover_aed >= v_thr                       then 'crossed'
    when p_turnover_aed >= v_thr * coalesce(v_frac,0.8) then 'approaching'
    else 'below' end;

  return jsonb_build_object(
    'band', v_band,
    'turnover_aed', round(coalesce(p_turnover_aed,0), 2),
    'threshold_aed', v_thr,
    'headroom_aed', round(v_thr - coalesce(p_turnover_aed,0), 2),
    'pct_of_threshold', round(coalesce(p_turnover_aed,0) / v_thr * 100, 1),
    'obligation', case v_band
      when 'crossed'     then 'Taxable supplies in the preceding 12 months have passed the mandatory registration threshold. Registration is required.'
      when 'approaching' then 'Not yet required. Close enough that registration should be prepared rather than discovered.'
      else 'No registration obligation on the preceding-12-months test.' end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_vercel_snapshot_filed(p_path text, p_summary jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_day text;
begin
  if coalesce(p_path, '') !~ '^engineering/vercel/\d{4}-\d{2}-\d{2}\.json$' then
    raise exception 'fn_vercel_snapshot_filed: the snapshot lives at engineering/vercel/<YYYY-MM-DD>.json (got %)', p_path;
  end if;
  v_day := substring(p_path from '(\d{4}-\d{2}-\d{2})');
  insert into public.doc_backups (entity, entity_id, doc_type, bucket, path, file_name, dropbox_path, source, dedupe_key)
  values ('company', 'vercel:' || v_day, 'Vercel configuration', 'backups', p_path, v_day || ' vercel-project.json',
          '/QuotesDone Backup/Company/Vercel/' || left(v_day, 7) || '/' || v_day || ' vercel-project.json', 'storage', 'VERCEL:' || v_day)
  on conflict do nothing;
  insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
  values ('it_engineer', case when coalesce(jsonb_array_length(p_summary->'no_recoverable_source'), 0) > 0 then 'warn' else 'ok' end,
          jsonb_build_object('job', 'vercel_snapshot') || coalesce(p_summary, '{}'::jsonb),
          left('Vercel configuration backed up (' || p_path || '): ' || coalesce(p_summary->>'domains', '?') || ' domains, '
               || coalesce(p_summary->>'env_names', '?') || ' env var names; needed but not in Vercel: '
               || coalesce(p_summary->>'missing_in_vercel', '[]') || '; no recoverable source: ' || coalesce(p_summary->>'no_recoverable_source', '[]') || '.', 500),
          now(), now());
  return jsonb_build_object('filed', p_path);
end $function$


CREATE OR REPLACE FUNCTION public.fn_verified_mobile(p_role text, p_customer uuid DEFAULT NULL::uuid, p_lead bigint DEFAULT NULL::bigint, p_email text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case
    when p_role = 'customer' then (select c.phone from public.customers c
                                    where coalesce(c.phone_verified, false) and nullif(btrim(c.phone), '') is not null
                                      and (c.id = p_customer or (p_customer is null and p_email is not null and lower(c.email) = lower(btrim(p_email))))
                                    limit 1)
    when p_role = 'supplier' then (select l.phone from public.leads l
                                    where coalesce(l.owner_phone_verified, false) and nullif(btrim(l.phone), '') is not null
                                      and (l.id = p_lead or (p_lead is null and p_email is not null and (lower(l.claimed_by) = lower(btrim(p_email)))))
                                    order by l.id limit 1)
  end
$function$


CREATE OR REPLACE FUNCTION public.fn_wa_answer(p_from text, p_body text, p_intent text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_body     text := lower(btrim(coalesce(p_body, '')));
  v_intent   public.wa_reply_intent;
  v_reply    text;
  v_lead     record;
  v_lead_id  bigint;
  v_ident_k  text := 'unknown';
  v_ident_id text := null;
  v_id       bigint;
  v_missing  text;
  v_cfg      record;
  v_log      bigint;
begin
  if v_body = '' then
    return jsonb_build_object('ok', false, 'reason', 'Empty message.');
  end if;

  select standard_reveal_rate, supplier_free_count, supplier_reg_fee into v_cfg
    from public.pricing_config order by id limit 1;

  -- WHO IS ASKING. Identity gates every 'own_records' answer, so one supplier can never be told
  -- another supplier's business by sending a lucky message.
  v_lead_id := public.fn_wa_lead_id(p_from);
  if v_lead_id is not null then
    select * into v_lead from public.leads where id = v_lead_id;
    v_ident_k := 'lead'; v_ident_id := v_lead_id::text;
  end if;

  -- THE INTENT, AS REASONED. Read by key from the active rows; the body is not read for meaning.
  select * into v_intent from public.wa_reply_intent where active and intent_key = p_intent;

  -- NOTHING TO ANSWER FROM. An honest refusal that names what it would need. Never a guess.
  if not found then
    v_reply := public.fn_wa_unmatched_reply();
    insert into public.wa_answer_log (from_phone, body, identity_kind, identity_id, matched, reply, refusal_reason)
    values (p_from, p_body, v_ident_k, v_ident_id, false, v_reply,
            case when p_intent is null
                 then 'Not reasoned yet (the model hold). The meaning waits in customer_support''s queue and is answered on WhatsApp when it is reasoned.'
                 when p_intent = 'none' then 'Reasoned: no intent row fits. This row is the backlog: a real question with no resolver.'
                 else 'Reasoned as ' || p_intent || ': answered outside the intent table (size statement, trade list), not backlog.' end)
    returning id into v_log;
    return jsonb_build_object('ok', true, 'matched', false, 'reply', v_reply, 'log_id', v_log,
                              'intent_decided_by', case when p_intent is null then 'held: not yet reasoned' else 'reasoning' end);
  end if;

  -- IDENTITY REQUIRED BUT UNKNOWN.
  if v_intent.requires_identity and v_lead_id is null then
    v_reply := 'I do not recognise this number yet, so I cannot look up your records. Reply with the '
            || 'email address you registered with, or REGISTER to start a new registration.';
    insert into public.wa_answer_log (from_phone, body, identity_kind, identity_id, intent_key, matched, reply, refusal_reason)
    values (p_from, p_body, v_ident_k, v_ident_id, v_intent.intent_key, true, v_reply,
            'Intent reasoned but the sender is not a known party.')
    returning id into v_log;
    return jsonb_build_object('ok', true, 'matched', true, 'intent', v_intent.intent_key, 'reply', v_reply, 'log_id', v_log);
  end if;

  v_reply := v_intent.answer_template;

  -- COMPANY SLOTS, the same for everyone.
  v_reply := replace(v_reply, '{{reveal_rate}}', coalesce(round(v_cfg.standard_reveal_rate * 100, 1)::text || '%', '3%'));
  v_reply := replace(v_reply, '{{free_count}}',  coalesce(v_cfg.supplier_free_count::text, '1000'));
  v_reply := replace(v_reply, '{{reg_fee}}',     coalesce(round(v_cfg.supplier_reg_fee)::text, '1000'));

  -- THE APPROVED PUBLIC CONTACT, read from the settings that say publication in their names -- never from
  -- founder_mobile. Absent, the slot ADMITS it rather than rendering an empty string.
  v_reply := replace(v_reply, '{{founder_public_phone}}',
    coalesce((select value from public.app_secrets where key = 'founder_public_phone'),
             '(no approved public contact is configured yet)'));
  v_reply := replace(v_reply, '{{founder_public_name}}',
    coalesce((select value from public.app_secrets where key = 'founder_public_name'),
             'the owner'));

  -- OWN-RECORD SLOTS, read from this sender's row only.
  if v_lead_id is not null then
    v_reply := replace(v_reply, '{{company_name}}', coalesce(v_lead.company_name, 'your company'));
    v_reply := replace(v_reply, '{{reg_status}}',   coalesce(v_lead.registration_status, 'not started'));
    v_reply := replace(v_reply, '{{approval_status}}', coalesce(v_lead.approval_status, 'not yet reviewed'));

    -- The founder's mandatory six, not the ten the scoring view happens to list.
    select string_agg(m, ', ') into v_missing from (
      select 'a UAE mobile number' as m where coalesce(btrim(v_lead.phone_e164), '') = ''
      union all select 'an email address' where coalesce(btrim(v_lead.email), '') = ''
      union all select 'your trade licence' where coalesce(btrim(v_lead.license_doc_path), '') = ''
      union all select 'your company profile' where coalesce(btrim(v_lead.company_profile_doc_path), '') = ''
      union all select 'a signed copy of our terms' where coalesce(btrim(v_lead.signed_terms_path), '') = ''
    ) x;
    v_reply := replace(v_reply, '{{missing_list}}', coalesce(v_missing, 'nothing, your file is complete'));
    v_reply := replace(v_reply, '{{missing_line}}',
      case when v_missing is null then 'Your file is complete.'
           else 'We still need: ' || v_missing || '.' end);

    v_reply := replace(v_reply, '{{quote_count}}', '0');
    v_reply := replace(v_reply, '{{quote_detail}}',
      'No quotes yet. Once a buyer posts a request in your category you will be invited to quote.');
    v_reply := replace(v_reply, '{{awarded_count}}', '0');
    v_reply := replace(v_reply, '{{awarded_detail}}',
      'No jobs awarded yet. You will get a message here the moment one is.');
  end if;

  -- BY-ID LOOKUP. A number in the body is resolved against the real records, and returned ONLY to a
  -- party who appears on that record. The digits are FORMAT: the first run of two or more.
  if v_intent.scope = 'by_id' then
    v_id := nullif((regexp_match(v_body, '([0-9]{2,})'))[1], '')::bigint;
    if v_id is null then
      v_reply := 'Send me the number and I will look it up. For example: quote 1234, or job 5678.';
    else
      v_reply := replace(v_reply, '{{id_answer}}',
        'I could not find a record numbered ' || v_id || ' that you are a party to. Check the number, '
        || 'or reply HUMAN and the team will look into it.');
    end if;
  end if;

  insert into public.wa_answer_log (from_phone, body, identity_kind, identity_id, intent_key, matched, reply)
  values (p_from, p_body, v_ident_k, v_ident_id, v_intent.intent_key, true, v_reply)
  returning id into v_log;

  return jsonb_build_object(
    'ok', true, 'matched', true, 'intent', v_intent.intent_key,
    'identity_kind', v_ident_k, 'identity_id', v_ident_id,
    'reply', v_reply, 'log_id', v_log, 'answered_by', 'deterministic', 'intent_decided_by', 'reasoning'
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_wa_attach_document(p_phone text, p_storage_path text, p_caption text DEFAULT NULL::text, p_media_kind text DEFAULT NULL::text, p_turn_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_lead   bigint;
  v_cap    text := lower(coalesce(p_caption, '') || ' ' || coalesce(p_storage_path, ''));
  v_kind   text := 'unknown';
  v_by     text := 'caption';
  v_conf   text := 'low';
  v_intake bigint;
  v_before jsonb;
  v_after  jsonb;
  v_reply  text;
begin
  v_lead := public.fn_wa_lead_id(p_phone);

  -- Classify from the caption and the filename. Deliberately conservative: an unrecognised document
  -- is recorded as unknown and waits, rather than being filed as a trade licence on a guess.
  if v_cap ~ '(trade|licence|license|رخصة|رخصه)' then
    v_kind := 'licence'; v_conf := 'high';
  elsif v_cap ~ '(profile|company profile|brochure|ملف|بروفايل)' then
    v_kind := 'profile'; v_conf := 'high';
  elsif v_cap ~ '(terms|t&c|agreement|signed|شروط|اتفاقية)' then
    v_kind := 'signed_terms'; v_conf := 'high';
  end if;

  if v_lead is not null then
    v_before := public.fn_supplier_mandatory_check(v_lead);
  end if;

  insert into public.wa_document_intake
    (phone_e164, lead_id, turn_id, storage_path, media_kind, caption,
     classified_as, classified_by, confidence, attached, attach_note)
  values (regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g'), v_lead, p_turn_id,
          p_storage_path, p_media_kind, p_caption, v_kind, v_by, v_conf, false, null)
  returning id into v_intake;

  -- Attach ONLY when we know whose file it is and what it is. Anything else waits for a person.
  if v_lead is null then
    v_reply := 'Thank you. I could not match this number to a registered company yet, so I have kept '
            || 'your file and someone will match it to your account. If you reply with the email '
            || 'address you registered with, I can do it straight away.';
    update public.wa_document_intake set attach_note = 'No lead matches this number.' where id = v_intake;

  elsif v_kind = 'unknown' then
    v_reply := 'Thank you, I have saved that to your file. I could not tell which document it is, so '
            || 'to file it correctly please tell me: is it your trade licence, your company profile, '
            || 'or the signed terms?';
    update public.wa_document_intake set attach_note = 'Received but unclassified; asked the sender.' where id = v_intake;

  else
    if v_kind = 'licence' then
      update public.leads set license_doc_path = p_storage_path where id = v_lead;
    elsif v_kind = 'profile' then
      update public.leads set company_profile_doc_path = p_storage_path where id = v_lead;
    elsif v_kind = 'signed_terms' then
      update public.leads set signed_terms_path = p_storage_path where id = v_lead;
    end if;

    update public.wa_document_intake
       set attached = true,
           attach_note = format('Attached as %s to lead %s.', v_kind, v_lead)
     where id = v_intake;

    v_after := public.fn_supplier_mandatory_check(v_lead);

    -- Tell them what changed and what is left. This is the difference between a receipt and a service.
    if coalesce((v_after->>'complete')::boolean, false) then
      v_reply := 'Got it, that is your ' || replace(v_kind,'_',' ') || ' saved. Your file is now '
              || 'complete and it goes to our team for verification. I will message you here when it '
              || 'is approved.';
    else
      v_reply := 'Got it, that is your ' || replace(v_kind,'_',' ') || ' saved. Still needed: '
              || (select string_agg(value #>> '{}', ', ') from jsonb_array_elements(v_after->'missing'))
              || '. You can send them here the same way.';
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'intake_id', v_intake,
    'lead_id', v_lead,
    'classified_as', v_kind,
    'confidence', v_conf,
    'attached', (v_lead is not null and v_kind <> 'unknown'),
    'mandatory_before', v_before,
    'mandatory_after', v_after,
    'reply', v_reply
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_wa_context(p_audience text, p_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_e164 text; v_email text; v_lead record; v_cust record;
        v_dc uuid[]; v_dl bigint[]; v_di uuid[]; v_refunds jsonb;
begin
  -- ONE IDENTIFIER, TWO SHAPES. wa_from arrives as 'whatsapp:+9715...'; a browser session arrives
  -- as an email address. An '@' is the discriminator: nothing that is a phone number contains one,
  -- and an address stripped of non-digits is meaningless, which is how a mis-shaped identifier used
  -- to fall through to "known: false" instead of an answer.
  v_email := nullif(lower(btrim(coalesce(p_phone, ''))), '');
  if v_email is not null and position('@' in v_email) = 0 then v_email := null; end if;
  v_e164 := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  if v_e164 = '' and v_email is null then return jsonb_build_object('scope','none'); end if;

  -- ---------------------------------------------------------------- FOUNDER: the company itself
  if p_audience = 'founder' then
    -- DEMO: left out of every business figure below.
    select coalesce(array_agg(id), '{}') into v_dc from customers where is_demo;
    select coalesce(array_agg(id), '{}') into v_dl from leads where is_demo;
    select coalesce(array_agg(id), '{}') into v_di from inquiries where public.fn_inquiry_is_demo(id);

    -- REFUNDS ARE THE CEO'S, NOT HIS. The old decision-queue reader (dropped 9 Sep) listed refunds as
    -- waiting on him; since 14 Sep the CEO decides every refund and the founder only receives the CEO's summary
    -- when a review loop escalates. This is what the CEO holds, stated as information.
    with open_r as (
      select r.id, r.requested_at, r.amount_fils, r.reason_code, rv.cycle, rv.outcome
        from refunds r
        left join lateral (select x.cycle, x.outcome from refund_ceo_review x where x.refund_id = r.id order by x.cycle desc limit 1) rv on true
       where r.status = 'requested'
         and (r.customer_id = any (v_dc)) is not true and (r.supplier_lead_id = any (v_dl)) is not true and (r.inquiry_id = any (v_di)) is not true)
    select jsonb_build_object(
      'who_decides', 'ceo',
      'note', 'Every refund is decided by the CEO. You receive his short summary only when a review loop escalates (three cycles or a missed deadline). Nothing here waits on you.',
      'open', (select count(*) from open_r),
      'escalated', (select count(*) from open_r where outcome = 'escalated'),
      'items', coalesce((select jsonb_agg(jsonb_build_object('refund_id', z.id, 'requested_at', z.requested_at,
                          'amount_aed', round(z.amount_fils / 100.0, 2), 'reason', z.reason_code,
                          'review_cycle', z.cycle, 'review_outcome', z.outcome) order by z.requested_at)
                           from (select * from open_r order by requested_at limit 12) z), '[]'::jsonb))
      into v_refunds;

    return jsonb_build_object(
      'scope','company',
      'suppliers', jsonb_build_object(
        'leads_total',      (select count(*) from leads where (id = any (v_dl)) is not true),
        'claimed',          (select count(*) from leads where coalesce(claimed,false) and (id = any (v_dl)) is not true),
        'claimed_real',     (select count(*) from leads where coalesce(claimed,false) and (id = any (v_dl)) is not true
                              and not (coalesce(company_name,'') ilike 'ZZ DEMO%' or coalesce(email,'') ilike '%@example.invalid')),
        'approved',         (select count(*) from leads where approval_status = 'approved' and (id = any (v_dl)) is not true),
        'licence_verified', (select count(*) from leads where coalesce(verified,false) and (id = any (v_dl)) is not true),
        'with_email',       (select count(*) from leads where coalesce(btrim(email),'') <> '' and (id = any (v_dl)) is not true)),
      'invites', jsonb_build_object(
        'enabled',      (select value from app_secrets where key='invite_enabled'),
        'daily_cap',    (select value from app_secrets where key='invite_daily_cap'),
        'sent_today',   (select count(*) from leads where invited_at >= date_trunc('day', now() at time zone 'utc') and (id = any (v_dl)) is not true),
        'sent_7d',      (select count(*) from leads where invited_at > now() - interval '7 days' and (id = any (v_dl)) is not true),
        'bounced_7d',   (select count(*) from leads where invite_status='bounced' and invited_at > now() - interval '7 days' and (id = any (v_dl)) is not true),
        'uncontacted',  (select count(*) from leads where invited_at is null and coalesce(btrim(email),'') <> '' and (id = any (v_dl)) is not true)),
      'demand', jsonb_build_object(
        'customers',        (select count(*) from customers where (id = any (v_dc)) is not true),
        'inquiries_total',  (select count(*) from inquiries where (id = any (v_di)) is not true),
        'inquiries_7d',     (select count(*) from inquiries where created_at > now() - interval '7 days' and (id = any (v_di)) is not true),
        'quotes_total',     (select count(*) from quotes where (inquiry_id = any (v_di)) is not true and (supplier_id = any (v_dl)) is not true),
        'quotes_7d',        (select count(*) from quotes where created_at > now() - interval '7 days'
                               and (inquiry_id = any (v_di)) is not true and (supplier_id = any (v_dl)) is not true)),
      'money', jsonb_build_object(
        'transactions',      (select count(*) from transactions where (customer_id = any (v_dc)) is not true
                                and (supplier_id = any (v_dl)) is not true and (inquiry_id = any (v_di)) is not true),
        'revealed',          (select count(*) from transactions where revealed_at is not null and (customer_id = any (v_dc)) is not true
                                and (supplier_id = any (v_dl)) is not true and (inquiry_id = any (v_di)) is not true),
        'ai_spend_today_aed',(select round(coalesce(sum(cost_aed),0)::numeric,2) from ai_cost_log where occurred_at >= current_date),
        'ai_spend_month_aed',(select round(coalesce(sum(cost_aed),0)::numeric,2) from ai_cost_log where occurred_at >= date_trunc('month', now()))),
      'health', jsonb_build_object(
        'agent_runs_failed_24h', (select count(*) from agent_runs where status in ('error','failed') and started_at > now() - interval '24 hours'),
        'actions_pending',       (select count(*) from agent_actions where status in ('pending','needs_review')),
        'escalations_open',      (select count(*) from agent_actions where coalesce(escalated,false) and status in ('pending','needs_review'))),
      'refunds_with_the_ceo', v_refunds);
  end if;

  -- ---------------------------------------------------------------- SUPPLIER: only their own row
  if p_audience = 'supplier' then
    select * into v_lead from leads l
     where (v_e164 <> '' and l.id = (select o.lead_id from public.fn_whatsapp_owner(p_phone) o where o.party_kind = 'supplier'))
        or (v_email is not null and (lower(coalesce(l.claimed_by,'')) = v_email or lower(coalesce(l.email,'')) = v_email))
     order by coalesce(l.claimed,false) desc, l.id limit 1;
    if not found then return jsonb_build_object('scope','supplier','known', false); end if;

    return jsonb_build_object(
      'scope','supplier', 'known', true,
      'company', v_lead.company_name,
      'account', jsonb_build_object('email', v_lead.claimed_by, 'phone', coalesce(v_lead.phone_e164, v_lead.phone)),
      'profile', jsonb_build_object(
        'claimed',          coalesce(v_lead.claimed,false),
        'approval_status',  coalesce(v_lead.approval_status,'not submitted'),
        'verified',         coalesce(v_lead.verified,false),
        'email_verified',   coalesce(v_lead.owner_email_verified,false),
        'phone_verified',   coalesce(v_lead.owner_phone_verified,false),
        'trade_licence_no', v_lead.trade_license_no,
        'licence_authority',v_lead.license_authority,
        'licence_expiry',   v_lead.license_expiry,
        'licence_on_file',  (v_lead.license_doc_path is not null),
        'blocked_because',  v_lead.licence_gate_reason),
      'work', jsonb_build_object(
        'inquiries_received',  (select count(*) from inquiry_matches m where m.supplier_id = v_lead.id),
        'inquiries_quoted',    (select count(distinct q.inquiry_id) from quotes q where q.supplier_id = v_lead.id),
        'inquiries_missed',    (select count(*) from inquiry_matches m where m.supplier_id = v_lead.id
                                  and not exists (select 1 from quotes q where q.inquiry_id = m.inquiry_id and q.supplier_id = v_lead.id)),
        'quotes_submitted',    (select count(*) from quotes q where q.supplier_id = v_lead.id),
        'last_quote',          (select jsonb_build_object('amount_aed', q.quote_amount, 'status', q.status, 'when', q.created_at)
                                  from quotes q where q.supplier_id = v_lead.id order by q.created_at desc limit 1),
        'jobs_won',            (select count(*) from quotes q where q.supplier_id = v_lead.id and q.status = 'accepted')));
  end if;

  -- ---------------------------------------------------------------- CUSTOMER: only their own rows
  if p_audience = 'customer' then
    select * into v_cust from customers c
     where (v_e164 <> '' and c.id = (select o.customer_id from public.fn_whatsapp_owner(p_phone) o where o.party_kind = 'customer'))
        or (v_email is not null and lower(coalesce(c.email,'')) = v_email)
     limit 1;
    if not found then return jsonb_build_object('scope','customer','known', false); end if;

    return jsonb_build_object(
      'scope','customer', 'known', true,
      'name', v_cust.full_name,
      -- WHAT WE HOLD FOR THEM. "what is my email registered" was one of the four questions the
      -- assistant could not answer, and the answer was one column away the whole time.
      'account', jsonb_build_object(
        'email', v_cust.email, 'phone', v_cust.phone,
        'language', v_cust.locale, 'industry', v_cust.industry,
        'customer_since', v_cust.created_at),
      'profile', jsonb_build_object(
        'phone_verified', coalesce(v_cust.phone_verified,false),
        'email_verified', coalesce(v_cust.email_verified,false),
        'terms_signed',   (v_cust.signed_terms_url is not null),
        -- create_inquiry's own gate, stated as the fact it is, so the assistant answers "can I post
        -- a request" with the truth rather than an encouragement.
        'can_post_request', (coalesce(v_cust.phone_verified,false) and coalesce(v_cust.email_verified,false)
                             and v_cust.signed_terms_url is not null)),
      'inquiries', coalesce((
        select jsonb_agg(x order by x->>'created_at' desc) from (
          select jsonb_build_object(
            'id', i.id, 'category', i.category, 'emirate', i.emirate, 'status', i.status,
            'created_at', i.created_at,
            'suppliers_received', (select count(*) from inquiry_matches m where m.inquiry_id = i.id),
            'quotes_received',    (select count(*) from quotes q where q.inquiry_id = i.id and q.status='submitted'),
            -- PRE-REVEAL: a band and a count, never the individual quotes and never a supplier name.
            'revealed', exists (select 1 from transactions t where t.inquiry_id = i.id and t.revealed_at is not null),
            'price_band', case
              when exists (select 1 from transactions t where t.inquiry_id = i.id and t.revealed_at is not null)
                then (select jsonb_build_object('low', min(q.quote_amount), 'high', max(q.quote_amount), 'average', round(avg(q.quote_amount)::numeric,0))
                        from quotes q where q.inquiry_id = i.id and q.status='submitted')
              else (select case when count(*) = 0 then null
                                else jsonb_build_object('average_rounded_to_nearest_1000',
                                        round(avg(q.quote_amount)::numeric / 1000) * 1000, 'note',
                                        'rounded band only - the exact quotes and the supplier names unlock when you reveal')
                           end from quotes q where q.inquiry_id = i.id and q.status='submitted') end) as x
          from inquiries i where i.customer_id = v_cust.id order by i.created_at desc limit 10) z), '[]'::jsonb));
  end if;

  return jsonb_build_object('scope','unknown');
end $function$


CREATE OR REPLACE FUNCTION public.fn_wa_fact_pack(p_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_lead_id bigint;
  l         record;
  c         record;
  v_cfg     record;
  v_conv    record;
  v_hist    jsonb := '[]'::jsonb;
  v_mand    jsonb;
  v_digits  text;
  -- Built before the return, NOT inside a CASE. Postgres evaluates a record field reference even in
  -- an unreached CASE branch, so with an unknown sender 'record l is not assigned yet' aborts the
  -- whole function. An unknown caller is the most common case, so that bug would have fired first.
  v_ident   jsonb;
  v_found_c boolean := false;
  v_conv_j  jsonb;
begin
  v_digits := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
  select standard_reveal_rate, supplier_free_count, supplier_reg_fee, category_open_min_suppliers,
         refund_window_working_days, chase_after_working_days
    into v_cfg from public.pricing_config order by id limit 1;

  v_lead_id := public.fn_wa_lead_id(p_phone);
  if v_lead_id is not null then
    select * into l from public.leads where id = v_lead_id;
    v_mand  := public.fn_supplier_mandatory_check(v_lead_id);
    v_ident := jsonb_build_object(
      'kind','supplier','id',v_lead_id,'company',l.company_name,
      'approval_status', coalesce(l.approval_status,'not reviewed'),
      'registration_status', coalesce(l.registration_status,'not started'),
      'mandatory', v_mand);
  else
    select * into c from public.customers
      where regexp_replace(coalesce(phone,''), '[^0-9]', '', 'g') = v_digits limit 1;
    v_found_c := found;
    if v_found_c then
      v_mand  := public.fn_customer_mandatory_check(c.id);
      v_ident := jsonb_build_object(
        'kind','customer','id',c.id::text,'name',c.full_name,
        'email_verified', c.email_verified, 'phone_verified', c.phone_verified,
        'mandatory', v_mand);
    else
      v_ident := jsonb_build_object('kind','unknown',
        'note','This number matches no lead and no customer. Do not discuss anyone''s records.');
    end if;
  end if;

  v_conv_j := jsonb_build_object('state','new');
  select * into v_conv from public.wa_conversation where phone_e164 = v_digits;
  if found then
    v_conv_j := jsonb_build_object(
      'state', v_conv.thread_state, 'topic', v_conv.topic, 'language', v_conv.language,
      'messages_so_far', v_conv.message_count,
      'window_open', (v_conv.window_expires_at is not null and v_conv.window_expires_at > now()));
    select coalesce(jsonb_agg(jsonb_build_object('at', t.at, 'dir', t.direction,
             'text', coalesce(t.transcript, t.body)) order by t.at), '[]'::jsonb)
      into v_hist
      from (select * from public.wa_turn where conversation_id = v_conv.id order by at desc limit 12) t;
  end if;

  return jsonb_build_object(
    -- WHO. Identity is a fact, never an inference. An unknown sender stays unknown.
    'identity', v_ident,

    -- WHAT IS TRUE ABOUT THE COMPANY. Read live, never remembered.
    'company', jsonb_build_object(
      'reveal_rate_pct', round(coalesce(v_cfg.standard_reveal_rate,0.03) * 100, 1),
      'supplier_free_count', v_cfg.supplier_free_count,
      'supplier_reg_fee_aed', v_cfg.supplier_reg_fee,
      'category_opens_at_suppliers', v_cfg.category_open_min_suppliers,
      'refund_window_working_days', v_cfg.refund_window_working_days,
      'supplier_chase_after_working_days', v_cfg.chase_after_working_days,
      'founder_contact', (coalesce((select value from public.app_secrets where key = 'founder_public_phone'),
                   '(no approved public contact is configured — tell the CEO)')),
      'supplier_mandatory', jsonb_build_array('company name','UAE mobile','email','trade licence','company profile','signed terms'),
      'customer_mandatory', jsonb_build_array('name','mobile','email','signed terms')),

    -- THE THREAD.
    'conversation', v_conv_j,
    'history', v_hist,

    -- WHAT IS NOT KNOWN. Stating this is what stops a model filling the gap with something plausible.
    'unknown', jsonb_build_array(
      'There are no live requests, quotes or comparison reports in the system yet, so no job status can be given for any id.',
      'No category is open yet, so no supplier can currently be matched to a buyer request.',
      'Pricing beyond the reveal rate and registration fee is not set and must not be invented.'),

    -- WHAT MAY NOT BE SAID OR DONE. A boundary, not a suggestion.
    'must_not', jsonb_build_array(
      'Never state a fact that is not in this pack. If it is not here, say you will check and pass it to the team.',
      'Never quote a price, discount, delivery date or timescale that is not in this pack.',
      'Never reveal any other party''s identity, contact details or quote. Anonymity is the product.',
      'Never promise approval, a job, or a refund. Refunds are the founder''s decision alone.',
      'Never ask for a password, a card number or an OTP code.'),

    'generated_at', now()
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_wa_fanout()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_dest text; v_opt text;
begin
  -- only fan out plain email rows; never recurse on whatsapp rows
  if coalesce(new.channel, 'email') <> 'email' or new.to_email is null or coalesce(new.to_role, '') not in ('customer', 'supplier') then return new; end if;
  v_dest := public.fn_whatsapp_destination(new.to_role, null, new.lead_id, new.to_email);
  if v_dest is null then
    if new.to_role = 'customer' then
      select c.whatsapp_opt into v_opt from public.customers c where lower(c.email) = lower(new.to_email) limit 1;
    else
      select l.whatsapp_opt into v_opt from public.leads l where l.id = new.lead_id or (new.lead_id is null and lower(l.claimed_by) = lower(new.to_email)) order by l.id limit 1;
    end if;
    -- 'none' is recorded (a03 marks the twin skipped with the reason); unanswered makes no twin.
    if v_opt is distinct from 'none' then return new; end if;
  end if;
  insert into public.notifications (type, to_email, to_role, to_phone, lead_id, inquiry_id, quote_id, subject, body, channel, status)
  values (new.type, new.to_email, new.to_role, v_dest, new.lead_id, new.inquiry_id, new.quote_id, new.subject, new.body, 'whatsapp', 'queued');
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_wa_founder_alert_fallback(p_notification_id bigint, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  n public.notifications%rowtype;
  v_phone text; v_email text; v_kind text; v_twin integer; v_new bigint; v_outcome text; v_claim bigint;
begin
  select * into n from public.notifications where id = p_notification_id;
  if not found then return jsonb_build_object('ok', false, 'outcome', 'no_such_row'); end if;
  if coalesce(n.channel, 'email') <> 'whatsapp' then
    return jsonb_build_object('ok', false, 'outcome', 'not_whatsapp');
  end if;

  -- Same test as a10_notifications_founder_mail_policy, so one cannot admit what the other refuses.
  select regexp_replace(coalesce(value, ''), '[^0-9]', '', 'g') into v_phone
    from public.app_secrets where key = 'admin_mfa_phone';
  if not (coalesce(n.to_role, '') in ('founder', 'admin', 'owner')
          or (n.to_phone is not null and coalesce(v_phone, '') <> ''
              and regexp_replace(n.to_phone, '[^0-9]', '', 'g') = v_phone)) then
    return jsonb_build_object('ok', false, 'outcome', 'not_founder');
  end if;

  v_kind := coalesce(nullif(btrim(n.kind), ''), nullif(btrim(n.type), ''), 'unregistered');

  -- 1. CLAIM THE ROW BEFORE DOING ANYTHING ELSE. send_whatsapp runs every 15 minutes and a run can
  --    overlap its predecessor; without a claim two callers could both pass the twin check and both
  --    queue a fallback email, so the founder would get the same alert twice. The UPDATE takes the
  --    row lock and only one caller gets an id back. The outcome is not known yet, so last_error is
  --    written provisionally here and finished below — a row can never be left saying 'pending'
  --    because both writes are in the same transaction as the caller's rpc.
  update public.notifications
     set status = 'skipped',
         last_error = left('not delivered by WhatsApp: ' || coalesce(p_reason, 'unspecified')
                           || ' | founder fallback: in progress', 500)
   where id = n.id and status in ('queued', 'held')
   returning id into v_claim;
  if v_claim is null then
    -- another run already retired this row, or it was delivered in the meantime. Do NOT email again.
    return jsonb_build_object('ok', false, 'outcome', 'already_handled', 'notification_id', n.id);
  end if;

  -- 2. Did the email twin already carry this alert? fn_notify_founder inserts the email row and the
  --    WhatsApp row in the same call, so the twin shares created_at to the microsecond; ten minutes
  --    is a generous window that still cannot reach the next tick's alert, and the subject match
  --    pins it to THIS event rather than to any alert of the same kind.
  --    ponytail: the correlation is (kind, ±10 minutes, subject containment) because the two rows
  --    share no id today — fn_notify_founder writes the email subject as '[Attention] ' || event and
  --    the WhatsApp subject as the bare event, so one contains the other. Two alerts of the SAME
  --    kind inside ten minutes where one subject contains the other would mis-correlate. Give both
  --    rows a shared correlation id in fn_notify_founder if that ever becomes possible; the ceiling
  --    here is a one-hour-per-problem deduped IT digest, so it cannot happen with today's writers.
  --    The window is bounded by created_at, which notifications_status_idx covers.
  select count(*) into v_twin
    from public.notifications e
   where e.channel = 'email'
     and coalesce(e.to_role, '') in ('founder', 'admin', 'owner')
     and coalesce(nullif(btrim(e.kind), ''), nullif(btrim(e.type), ''), 'unregistered') = v_kind
     and e.status in ('queued', 'sent')
     and e.created_at between n.created_at - interval '10 minutes' and n.created_at + interval '10 minutes'
     and position(coalesce(n.subject, '~none~') in coalesce(e.subject, '')) > 0;

  if v_twin > 0 then
    v_outcome := 'email_twin_already_sent';
  else
    select coalesce(nullif(split_part(coalesce(value, ''), ',', 1), ''), 'management@quotesdone.com')
      into v_email from public.app_secrets where key = 'admin_emails';
    v_email := coalesce(v_email, 'management@quotesdone.com');

    -- The kind travels with the fallback on purpose. Queue it as 'founder_alert' with the row's own
    -- kind and a10 admits it exactly when founder_mail_policy says that kind is his to read.
    insert into public.notifications (type, kind, to_email, to_role, subject, body, status, channel)
    values ('founder_alert', v_kind, v_email, 'founder',
            '[Attention] ' || coalesce(n.subject, 'QuotesDone alert'), n.body, 'queued', 'email')
    returning id into v_new;

    if v_new is null then
      -- a10 returned NULL: founder_mail_policy says this kind is not his to read, so the alert was
      -- routed to its owning seat instead. That is a decision, not a delivery — record it where the
      -- OS can see it rather than let the WhatsApp row disappear claiming an email went.
      v_outcome := 'blocked_by_founder_mail_policy';
      insert into public.founder_alerts (level, event, detail, channel)
      values ('high', 'whatsapp_fallback:blocked_by_policy',
              left('notification ' || n.id || ' (kind ' || v_kind || ') could not be sent by WhatsApp ('
                   || coalesce(p_reason, 'unspecified') || ') and founder_mail_policy does not allow '
                   || 'that kind by email either: ' || coalesce(n.subject, ''), 1000), 'os');
    else
      v_outcome := 'emailed';
    end if;
  end if;

  -- 4. Finish the record the claim in step 1 opened. The row is already out of the queue; this only
  --    replaces 'in progress' with what actually happened, so the row explains itself for ever.
  update public.notifications
     set last_error = left('not delivered by WhatsApp: ' || coalesce(p_reason, 'unspecified')
                           || ' | founder fallback: ' || v_outcome, 500)
   where id = n.id;

  return jsonb_build_object('ok', true, 'outcome', v_outcome, 'kind', v_kind,
                            'email_notification_id', v_new, 'notification_id', n.id);
end $function$


CREATE OR REPLACE FUNCTION public.fn_wa_human_hold(p_phone text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce((select thread_state = 'handed_to_human' from public.wa_conversation
                    where phone_e164 = regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g')), false)
$function$


CREATE OR REPLACE FUNCTION public.fn_wa_human_request(p_phone text, p_hold boolean, p_event text, p_detail text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_digits text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'); v_h bigint; v_ok boolean := true; v_err text;
  v_founder boolean;
begin
  if length(v_digits) < 9 then return jsonb_build_object('ok', false, 'reason', 'no usable number'); end if;
  -- A. The founder trying "Talk to a person" from his own number is not a person waiting (handoff 58191, 22 Sep).
  v_founder := coalesce(public.fn_identify_contact(v_digits) ->> 'audience', '') = 'founder';
  if p_hold and not v_founder then
    insert into public.wa_conversation (phone_e164, party_kind, message_count, thread_state, handed_to)
    values (v_digits, 'unknown', 0, 'handed_to_human', 'customer_support')
    on conflict (phone_e164) do update set thread_state = 'handed_to_human', handed_to = 'customer_support', last_seen_at = now();
  end if;
  select id into v_h from public.agent_actions
   where kind = 'handoff' and status = 'pending' and detail ->> 'type' = 'support.human_requested' and detail ->> 'phone_digits' = v_digits
   order by id desc limit 1;
  if v_h is null and not v_founder then
    v_h := public.fn_seat_handoff('customer_support', 'customer_support', 'support.human_requested', 'wa_conversation',
      v_digits || ':' || to_char(now() at time zone 'UTC', 'YYYYMMDDHH24MISS'),
      jsonb_build_object('phone_digits', v_digits, 'held', p_hold, 'event', p_event,
                         'waiting_for', 'a person to answer +' || v_digits || ' on WhatsApp'));
  end if;
  begin
    perform public.fn_notify_founder(p_event => p_event, p_detail => p_detail, p_level => 'high', p_kind => 'whatsapp_human_request',
                                     p_dedupe_key => 'wa_human:' || v_digits || ':' || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD'),
                                     p_owner_agent => 'customer_support');
  exception when others then v_ok := false; v_err := left(sqlerrm, 300);
  end;
  return jsonb_build_object('ok', true, 'handoff_id', v_h, 'held', p_hold, 'founder_own_number', v_founder, 'notified', v_ok, 'notify_error', v_err);
end $function$


CREATE OR REPLACE FUNCTION public.fn_wa_human_request_close(p_phone text, p_by text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_digits text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'); r record; n int := 0;
begin
  -- The founder may type 050..., 50... or 971...: the last nine digits name the number.
  update public.wa_conversation set thread_state = 'open', handed_to = null
   where right(phone_e164, 9) = right(v_digits, 9) and thread_state = 'handed_to_human';
  for r in select id from public.agent_actions
            where kind = 'handoff' and status = 'pending' and detail ->> 'type' = 'support.human_requested'
              and right(detail ->> 'phone_digits', 9) = right(v_digits, 9) loop
    perform public.fn_seat_handoff_complete(r.id, jsonb_build_object('closed_by', coalesce(p_by, 'founder'), 'note', p_note, 'closed_at', now()));
    n := n + 1;
  end loop;
  return jsonb_build_object('closed', n);
end $function$


CREATE OR REPLACE FUNCTION public.fn_wa_human_request_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_conv public.wa_conversation; v_ref text; v_secret text; v_req bigint; v_body text; v_lang text; n int := 0; v_sent int := 0;
  v_held boolean; v_window interval; v_rep jsonb; rep public.support_ceo_report; n_esc int := 0; n_closed int := 0;
begin
  select value into v_ref from public.app_secrets where key = 'project_ref';
  select value into v_secret from public.app_secrets where key = 'cred_fn_resilience_ping';
  for r in select a.* from public.agent_actions a
            where a.kind = 'handoff' and a.status = 'pending' and a.detail ->> 'type' = 'support.human_requested'
              and a.created_at < now() - interval '23 hours' and not (a.detail ? 'followed_up_at')
            order by a.id limit 20 loop
    n := n + 1; v_req := null;
    v_held := coalesce(r.detail ->> 'held', 'true') = 'true';
    update public.wa_conversation set thread_state = 'open', handed_to = null
     where phone_e164 = r.detail ->> 'phone_digits' and thread_state = 'handed_to_human'
    returning * into v_conv;
    if v_conv.id is null then select * into v_conv from public.wa_conversation where phone_e164 = r.detail ->> 'phone_digits'; end if;
    v_lang := case when coalesce(v_conv.language, '') = 'ar' then 'ar' else 'en' end;
    v_body := case when v_lang = 'ar'
      then 'نعتذر عن تأخر ردنا عليكم. لم يتمكن أحد أعضاء الفريق من التواصل معكم بعد، وقد أبلغناه مجددًا بطلبكم. وإلى حين ذلك عادت إليكم خدمة الردود الفورية في هذه المحادثة، فتفضلوا بإرسال كلمة «قائمة» لعرض الخيارات أو كتابة استفساركم.' || E'\n\nفريق خدمة العملاء في QuotesDone'
      else 'We are sorry you have not heard from us yet. A member of the team has not been able to reach you, and we have reminded them of your request. Meanwhile, instant answers are back on in this chat: reply MENU for the options or type your question.' || E'\n\nQuotesDone Customer Support' end;
    if v_held and v_conv.window_expires_at > now() and v_ref is not null and v_secret is not null then
      select net.http_post(
        url := 'https://' || v_ref || '.supabase.co/functions/v1/send_whatsapp',
        headers := jsonb_build_object('Content-Type', 'application/json'),
        body := jsonb_build_object('__secret', v_secret, 'to', '+' || (r.detail ->> 'phone_digits'), 'body', v_body),
        timeout_milliseconds := 15000) into v_req;
      v_sent := v_sent + 1;
    end if;
    begin
      perform public.fn_notify_founder(p_event => 'WhatsApp: +' || (r.detail ->> 'phone_digits') || ' has waited 23 hours for a person',
        p_detail => 'Nobody closed the request from +' || (r.detail ->> 'phone_digits') || ' (' || coalesce(r.detail ->> 'event', 'Talk to a person') || ').'
        || case when v_req is not null then ' They were sent a polite follow-up and automatic replies are back on.'
                else ' Their WhatsApp window has closed, so no follow-up could be sent; call them or email them.' end
        || E'\nReply now: https://wa.me/' || (r.detail ->> 'phone_digits')
        || E'\nWhen handled, send DONE +' || (r.detail ->> 'phone_digits') || ' to the QuotesDone WhatsApp number.',
        p_level => 'high', p_kind => 'whatsapp_human_request', p_dedupe_key => 'wa_human_followup:' || r.id,
        p_owner_agent => 'customer_support');
    exception when others then null;   -- the follow-up is recorded below either way
    end;
    update public.agent_actions
       set detail = detail || jsonb_build_object('followed_up_at', now(), 'followup_request_id', v_req,
                                                 'followup_skipped', case when v_req is not null then null
                                                                           when not v_held then 'not held: the automatic replies were never paused'
                                                                           else 'the 24-hour WhatsApp window had closed' end)
     where id = r.id;
  end loop;
  -- B. 24 h, the reply clock (seat_handoff_kind.reply_within): customer_support reports it to the CEO, once.
  select reply_within into v_window from public.seat_handoff_kind
   where type = 'support.human_requested' and from_seat = 'customer_support' and to_seat = 'customer_support';
  v_window := coalesce(v_window, interval '24 hours');
  for r in select a.* from public.agent_actions a
            where a.kind = 'handoff' and a.status = 'pending' and a.detail ->> 'type' = 'support.human_requested'
              and a.created_at < now() - v_window and not (a.detail ? 'escalated_report_id')
            order by a.id limit 20 loop
    v_rep := public.fn_support_report_to_ceo('wa_human:' || r.id, 'serious',
      'A WhatsApp contact asked for a person and nobody answered within ' || v_window || ' (handoff ' || r.id || ')',
      jsonb_build_object('handoff_id', r.id, 'phone_digits', r.detail ->> 'phone_digits', 'asked_at', r.created_at,
                         'event', r.detail ->> 'event', 'followed_up_at', r.detail ->> 'followed_up_at',
                         'followup_request_id', r.detail ->> 'followup_request_id', 'followup_skipped', r.detail ->> 'followup_skipped'),
      jsonb_build_array('customer_support alerted the founder at ' || to_char(r.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai',
                        coalesce('customer_support followed up with the contact at ' || (r.detail ->> 'followed_up_at'),
                                 'customer_support has not yet followed up with the contact')),
      'Decide who answers this contact today (call, email or WhatsApp from the company number) and record it. The request stays open until the contact was followed up and this report is completed.',
      p_review_in => interval '4 hours', p_source_agent => 'customer_support');
    if coalesce((v_rep ->> 'ok')::boolean, false) then
      update public.agent_actions
         set detail = detail || jsonb_build_object('escalated_report_id', (v_rep ->> 'report_id')::bigint, 'escalated_at', now())
       where id = r.id;
      n_esc := n_esc + 1;
    end if;
  end loop;

  -- The loop closes when the contact was followed up AND the CEO's report is completed; the verdict names both.
  for r in select a.* from public.agent_actions a
            where a.kind = 'handoff' and a.status = 'pending' and a.detail ->> 'type' = 'support.human_requested'
              and a.detail ? 'followed_up_at' and a.detail ? 'escalated_report_id'
            order by a.id limit 20 loop
    select * into rep from public.support_ceo_report where id = (r.detail ->> 'escalated_report_id')::bigint;
    continue when rep.id is null or rep.status <> 'completed';
    perform set_config('qd.handoff_closer', 'customer_support', true);
    perform public.fn_seat_handoff_complete(r.id, coalesce(r.evidence, '{}'::jsonb) || jsonb_build_object(
      'verified_by', 'customer_support', 'verified_at', now(),
      'verdict', 'followed up ' || (r.detail ->> 'followed_up_at')
                 || coalesce(' (' || (r.detail ->> 'followup_skipped') || ')', '')
                 || '; the CEO decided (report ' || rep.id || '): ' || left(coalesce(rep.completion_note, rep.acceptance_receipt, 'completed'), 400)));
    perform set_config('qd.handoff_closer', '', true);
    n_closed := n_closed + 1;
  end loop;
  return jsonb_build_object('ok', true, 'due', n, 'followups_queued', v_sent, 'escalated', n_esc, 'closed', n_closed);
end $function$


CREATE OR REPLACE FUNCTION public.fn_wa_lead_id(p_phone text)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- 14 Sep 2026 (#322): only a supplier's CONFIRMED WhatsApp number (fn_whatsapp_owner). fn_wa_answer
  -- and fn_wa_fact_pack identify suppliers through this function.
  select o.lead_id from public.fn_whatsapp_owner(p_phone) o where o.party_kind = 'supplier';
$function$


CREATE OR REPLACE FUNCTION public.fn_wa_menu_context(p_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id json; v_aud text; v_cust uuid; v_lead bigint; v_name text; v_company text; v_reqs jsonb := '[]'::jsonb;
begin
  v_id  := public.fn_identify_contact(p_phone);
  v_aud := coalesce(v_id ->> 'audience', 'unknown');
  if v_aud = 'founder' then
    select nullif(btrim(value), '') into v_name from public.app_secrets where key = 'founder_name';
  elsif v_aud in ('customer', 'supplier') then
    -- fn_identify_contact already confirmed the number; this reads the same owner row for its ids.
    select o.customer_id, o.lead_id into v_cust, v_lead from public.fn_whatsapp_owner(p_phone) o limit 1;
    if v_aud = 'supplier' then
      select nullif(btrim(contact_name), ''), nullif(btrim(company_name), '') into v_name, v_company
        from public.leads where id = v_lead;
    else
      select nullif(btrim(full_name), '') into v_name from public.customers where id = v_cust;
    end if;
  end if;
  -- A greeting never carries an address (22 Sep: "Good day management@quotesdone.com").
  if v_name ~ '@' then v_name := null; end if;
  if v_company ~ '@' then v_company := null; end if;
  if v_aud = 'customer' and v_cust is not null then
    select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'rfq_no', i.rfq_no, 'status', i.status, 'created_at', i.created_at)
                              order by i.created_at desc), '[]'::jsonb)
      into v_reqs
      from (select id, rfq_no, status, created_at from public.inquiries
             where customer_id = v_cust and completed_at is null
               and coalesce(status, '') not in ('closed', 'cancelled', 'completed', 'lost')
             order by created_at desc limit 5) i;
  end if;
  return jsonb_build_object('audience', v_aud, 'name', coalesce(v_name, v_company), 'company', v_company,
                            'approved', coalesce((v_id ->> 'approved')::boolean, false), 'requests', v_reqs);
end $function$


CREATE OR REPLACE FUNCTION public.fn_wa_model_brief()
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
  select
     'You are the QuotesDone WhatsApp agent, talking to UAE suppliers and buyers. '

  || 'ABSOLUTE RULE ON FACTS: every detail about any customer, supplier, quote, job or price comes '
  || 'from fact_pack and from nowhere else. You know nothing about this company or these people '
  || 'except what fact_pack contains, and you must never fill such a gap from memory or from what '
  || 'seems likely. '

  || 'THE OWNER''S NUMBER IS ' || (coalesce((select value from public.app_secrets where key = 'founder_public_phone'),
                   '(no approved public contact is configured — tell the CEO)')) || ' AND THERE ARE EXACTLY TWO REASONS TO GIVE IT. One: the '
  || 'sender asked to speak to a person, an agent or a human, or asked who owns or runs QuotesDone. '
  || 'Two: the message is a complaint, a dispute or an accusation, which needs a person whether they '
  || 'asked or not. In both cases give it plainly and without making them ask twice, because the '
  || 'owner is the only person in this company and an escalation that does not reach him reaches '
  || 'nobody. Give it for NOTHING ELSE: not for an off-topic question, not for small talk, not '
  || 'because you could not answer. '

  || 'ABSOLUTE RULE ON SUBJECT: if the message is not about QuotesDone, reply with EXACTLY this '
  || 'sentence and nothing else: "' || public.fn_wa_off_topic_reply() || '" '
  || 'Translate it into the sender''s language if they did not write in English, but do not reword '
  || 'it, do not add to it, do not apologise around it, and do not answer the question first. Never '
  || 'state a fact about the outside world as if you had checked it: you cannot see the weather, a '
  || 'score, a rate or the time. '

  || 'BUT PHRASING IS NOT SUBJECT. A QuotesDone question asked in unusual words is still a QuotesDone '
  || 'question. "any update on my file bro" is a registration-status question and must be understood '
  || 'and answered from the record. Judge what the message is ABOUT, never how it is worded. '

  || 'WHEN IT IS ABOUT US BUT THE PACK LACKS THE FACT: say you will check and that someone will come '
  || 'back to them. That gap is ours. '

  || 'The sender may write in any language: understand them and reply in their own. Follow the '
  || 'conversation history. Honour every entry in must_not. Match the courtesy you are given; a '
  || 'greeting gets a greeting, not a menu. Be brief, plain and useful, the way a competent person '
  || 'on a phone would be.'
$function$


CREATE OR REPLACE FUNCTION public.fn_wa_off_topic_reply()
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
  select 'I am here to assist you with QuotesDone inquiries only. Please let me know how I can help you.'
$function$


CREATE OR REPLACE FUNCTION public.fn_wa_problem_report(p_phone text, p_text text, p_lang text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  alphabet constant text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';   -- 32 symbols, no 0/O/1/I (as fn_complaint_open)
  v_digits text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  v_days int := greatest(1, public.fn_seat_clock_policy('support_case_append_days', 7)::int);
  v_sla numeric := public.fn_seat_clock_policy('support_first_reply_sla_hours', 24);
  v_lang text := case when p_lang = 'ar' then 'ar' else 'en' end;
  v_kind text; v_cust uuid; v_lead bigint; v_party text; v_ref text; v_id bigint; v_inq text; v_bytes bytea;
  v_case public.support_case; v_report jsonb; i int; attempt int := 0;
begin
  if coalesce(btrim(p_text), '') = '' then raise exception 'fn_wa_problem_report: empty report'; end if;
  select o.party_kind, o.customer_id, o.lead_id into v_kind, v_cust, v_lead from public.fn_whatsapp_owner(p_phone) o limit 1;
  v_party  := coalesce(v_cust::text, v_lead::text, '+' || v_digits);
  v_report := jsonb_build_object('at', now(), 'text', left(btrim(p_text), 4000));

  -- The request the report names, when it is one of this customer's own.
  if v_cust is not null then
    select i.rfq_no::text into v_inq from public.inquiries i
     where i.customer_id = v_cust and i.rfq_no is not null and p_text ~ ('(^|[^0-9])' || i.rfq_no::text || '([^0-9]|$)')
     order by i.created_at desc limit 1;
  end if;

  -- An open case from this number or this account in the last v_days days takes the report.
  select c.* into v_case from public.support_case c
   where c.state <> 'closed' and c.opened_at > now() - make_interval(days => v_days)
     and c.party_id in (v_party, '+' || v_digits)
   order by c.opened_at desc limit 1;
  if found then
    update public.support_case set last_activity_at = now(), inquiry_ref = coalesce(inquiry_ref, v_inq)
     where case_id = v_case.case_id;
    update public.agent_actions
       set detail = jsonb_set(detail, '{reports}', coalesce(detail -> 'reports', '[]'::jsonb) || v_report)
     where kind = 'handoff' and target_id = 'support.case_open:' || v_case.case_id;
    return jsonb_build_object('case_ref', v_case.case_ref, 'case_id', v_case.case_id, 'appended', true,
                              'sla_hours', v_sla, 'party_kind', v_case.party_kind);
  end if;

  loop
    attempt := attempt + 1;
    v_bytes := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');
    v_ref := 'QD-S-';
    for i in 0..5 loop v_ref := v_ref || substr(alphabet, (get_byte(v_bytes, i) % 32) + 1, 1); end loop;
    begin
      insert into public.support_case (case_ref, party_kind, party_id, inquiry_ref, subject, state, identity_verified, verified_how, owner_role_id)
      values (v_ref, coalesce(v_kind, 'unknown'), v_party, v_inq,
              'WhatsApp problem report (' || v_lang || '): ' || left(btrim(p_text), 4000),
              'open', v_kind is not null, case when v_kind is not null then 'confirmed WhatsApp number' end, 'customer_support')
      returning case_id into v_id;
      exit;
    exception when unique_violation then
      if attempt >= 5 then raise; end if;
    end;
  end loop;

  perform public.fn_seat_handoff('customer_support', 'customer_support', 'support.case_open', 'support_case', v_id::text,
    jsonb_build_object('case_ref', v_ref, 'phone_digits', v_digits, 'lang', v_lang, 'party_kind', coalesce(v_kind, 'unknown'),
                       'inquiry_ref', v_inq, 'reports', jsonb_build_array(v_report), 'sla_hours', v_sla,
                       'waiting_for', 'the first reply to case ' || v_ref || ' (reporter +' || v_digits || ')'));
  return jsonb_build_object('case_ref', v_ref, 'case_id', v_id, 'appended', false, 'sla_hours', v_sla,
                            'party_kind', coalesce(v_kind, 'unknown'), 'inquiry_ref', v_inq);
end $function$


CREATE OR REPLACE FUNCTION public.fn_wa_record_turn(p_phone text, p_direction text, p_body text DEFAULT NULL::text, p_media_url text DEFAULT NULL::text, p_media_kind text DEFAULT NULL::text, p_transcript text DEFAULT NULL::text, p_intent text DEFAULT NULL::text, p_answered_by text DEFAULT NULL::text, p_fact_pack jsonb DEFAULT NULL::jsonb, p_model text DEFAULT NULL::text, p_cost_aed numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_digits text := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
  v_conv   record;
  v_lead   bigint;
  v_cust   uuid;
  v_kind   text := 'unknown';
  v_pid    text;
  v_turn   bigint;
  v_dir    text;
begin
  -- THE DIRECTION IS NORMALISED HERE, WHERE THE CALLER'S VOCABULARY MEETS THE COLUMN'S.
  -- Every branch below compares p_direction to 'in', and wa_turn's CHECK allows only 'in' and
  -- 'out'. A caller writing 'INBOUND' -- the obvious word, and the one the edge function reached
  -- for -- hit the CHECK and the whole turn was lost. Worse would have been no CHECK: the row
  -- would have been stored and the 24-hour service window would never have opened, so the agent
  -- would have gone quiet a day later for a reason nothing recorded.
  v_dir := case lower(btrim(coalesce(p_direction, '')))
             when 'in' then 'in' when 'inbound' then 'in' when 'incoming' then 'in'
             when 'out' then 'out' when 'outbound' then 'out' when 'outgoing' then 'out'
             else null end;
  if v_dir is null then
    return jsonb_build_object('ok', false, 'reason',
      format('direction %L is neither inbound nor outbound; nothing was recorded', p_direction));
  end if;
  if v_digits = '' then
    return jsonb_build_object('ok', false, 'reason', 'No usable phone number on the message.');
  end if;

  v_lead := public.fn_wa_lead_id(p_phone);
  if v_lead is not null then
    v_kind := 'lead'; v_pid := v_lead::text;
  else
    select id into v_cust from public.customers
     where regexp_replace(coalesce(phone,''), '[^0-9]', '', 'g') = v_digits limit 1;
    if v_cust is not null then v_kind := 'customer'; v_pid := v_cust::text; end if;
  end if;

  insert into public.wa_conversation (phone_e164, party_kind, party_id, message_count,
                                      window_opened_at, window_expires_at)
  values (v_digits, v_kind, v_pid, 0,
          case when v_dir = 'in' then now() else null end,
          case when v_dir = 'in' then now() + interval '24 hours' else null end)
  on conflict (phone_e164) do update set
      last_seen_at   = now(),
      party_kind     = coalesce(excluded.party_kind, wa_conversation.party_kind),
      party_id       = coalesce(excluded.party_id,   wa_conversation.party_id),
      -- An INBOUND message opens or re-opens the 24-hour service window. An outbound one never does,
      -- which is the whole point of the rule: we cannot extend our own permission to keep talking.
      window_opened_at  = case when v_dir = 'in' then now() else wa_conversation.window_opened_at end,
      window_expires_at = case when v_dir = 'in' then now() + interval '24 hours'
                               else wa_conversation.window_expires_at end
  returning * into v_conv;

  update public.wa_conversation
     set message_count = message_count + 1,
         last_intent   = coalesce(p_intent, last_intent)
   where id = v_conv.id
  returning * into v_conv;

  insert into public.wa_turn (conversation_id, direction, body, media_url, media_kind, transcript,
                              transcript_source, intent_key, answered_by, fact_pack, model_id, cost_aed)
  values (v_conv.id, v_dir, p_body, p_media_url, p_media_kind, p_transcript,
          case when p_transcript is not null then 'model' else 'none' end,
          p_intent, p_answered_by, p_fact_pack, p_model, p_cost_aed)
  returning id into v_turn;

  return jsonb_build_object(
    'ok', true, 'conversation_id', v_conv.id, 'turn_id', v_turn,
    'party_kind', v_conv.party_kind, 'party_id', v_conv.party_id,
    'message_count', v_conv.message_count,
    'window_expires_at', v_conv.window_expires_at,
    'window_open', (v_conv.window_expires_at is not null and v_conv.window_expires_at > now())
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_wa_route(p_phone text, p_body text, p_has_audio boolean DEFAULT false, p_needs_person boolean DEFAULT NULL::boolean, p_intent text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_digits text := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
  v_det    jsonb;
  v_pack   jsonb;
  v_conv   record;
  v_needs  boolean;
  v_why    text;
  v_held   boolean;
  v_latin  boolean;
  v_trouble boolean;
  v_asked  boolean;
  v_person boolean;
  v_reason text;
  v_chain  jsonb;
  v_intent text;
  v_reply  text;
begin
  select coalesce((select value = 'true' from public.app_secrets where key = 'paid_inference_enabled'), false)
    into v_held;
  v_held := not v_held;

  v_det  := public.fn_wa_answer(p_phone, coalesce(p_body, '(voice note)'), p_intent);
  v_pack := public.fn_wa_fact_pack(p_phone);
  v_intent := v_det->>'intent';
  v_reply  := v_det->>'reply';
  select * into v_conv from public.wa_conversation where phone_e164 = v_digits;

  -- Script detection picks the reply language; it is a format test, not a reading of meaning.
  v_latin := coalesce(p_body, '') ~ '^[\s\x20-\x7E]*$';

  -- The two ways a message needs a person. The second is REASONED (think() in wa_inbound): a complaint,
  -- a dispute, a refund demand, an accusation or a legal threat, however it is worded. Null = not yet
  -- reasoned (the hold): nobody is escalated on a guess; the message waits in customer_support's queue.
  v_asked   := coalesce(v_intent = 'contact_human', false);
  v_trouble := coalesce(p_needs_person, false);

  -- One decision now, not two. Needing a person and getting his number are the same thing here.
  v_person := v_asked or v_trouble;
  v_reason := case
    when v_asked   then 'They asked for a person, or asked who runs the company.'
    when v_trouble then 'This is a complaint, a dispute or an accusation. It needs a person whether '
                     || 'they asked for one or not, and the founder is the only person there is.'
    when p_needs_person is null then 'Whether this needs a person has not been reasoned yet (the model hold); '
                     || 'it is waiting in customer_support''s queue and nobody was escalated on a guess.'
    else 'Nobody asked for a person and nothing here needs one. A number given out by a machine '
      || 'cannot be taken back.' end;

  -- A complaint gets the number appended, because the escalation and the contact are the same act.
  if v_trouble and not v_asked then
    v_reply := v_reply || ' If you would rather speak to someone directly, call or message '
            || '+971 50 931 9355, which is answered by the owner.';
  end if;

  v_needs := false; v_why := 'A deterministic answer matched and the message is simple, so this turn costs nothing.';
  if p_has_audio then
    v_needs := true; v_why := 'The message is a voice note and must be transcribed before it can be answered.';
  elsif not v_latin then
    v_needs := true; v_why := 'The message is not in Latin script and the fixed answers exist only in English.';
  elsif v_intent in ('small_talk','off_topic','greeting','contact_human') then
    v_needs := false;
    v_why := format('Matched %s, which is answered completely without a model.', v_intent);
  elsif coalesce((v_det->>'matched')::boolean, false) = false then
    v_needs := true; v_why := 'No fixed answer matched. Wording varies, so this is the normal case rather than an exception.';
  elsif coalesce(v_conv.message_count, 0) >= 2 then
    v_needs := true; v_why := 'This is a continuing conversation; a fixed answer would ignore what came before.';
  elsif length(coalesce(p_body,'')) > 160 then
    v_needs := true; v_why := 'The message is long enough to contain more than one question.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'rung', rung, 'model', model, 'kind', kind, 'rationale', rationale) order by rung), '[]'::jsonb)
    into v_chain
    from public.model_fallback_chain
   -- 6 Oct: a voice note has its own chain (received audio stays on Gemini, matrix v2)
   where purpose = case when p_has_audio then 'whatsapp_voice_note' else 'whatsapp_conversation' end and active;

  return jsonb_build_object(
    'ok', true,
    'needs_model', v_needs,
    'why', v_why,
    'inference_held', v_held,
    -- 6 Oct: rung 1 of the chain, never a literal, so the table is the one place a model is named
    'model', case when v_needs then (select e ->> 'model' from jsonb_array_elements(v_chain) e
                                      where e ->> 'kind' = 'model' order by (e ->> 'rung')::int limit 1) else null end,
    'fallback_chain', case when v_needs then v_chain else null end,
    'on_model_failure',
      'Try each rung in order. Record model_wanted, model_used and fell_back on llm_calls for every '
   || 'attempt, so a fallback that becomes permanent is visible rather than quietly expensive. The '
   || 'final rung is the deterministic reply and it cannot fail.',
    'model_reason', case
      when not v_needs then 'No model needed. The database answered it.'
      -- 6 Oct: matrix v2 (founder_instruction 1108)
      when p_has_audio then 'google/gemini-3.8-flash hears the voice note (received audio stays on Gemini). On failure '
        || 'the deterministic reply.'
      else 'openai/gpt-6-luna first, by the founder''s matrix v2. On failure google/gemini-3.8-flash. On failure the '
        || 'deterministic reply. Every rung gets the same fact pack and the same boundaries.' end,

    -- One decision. Handing to a person and giving the number are the same act.
    'needs_a_person', v_person,
    'person_decided_by', case when v_asked then 'intent'
                              when p_needs_person is null then 'held: not yet reasoned'
                              else 'reasoning' end,
    'founder_number', case when v_person then (coalesce((select value from public.app_secrets where key = 'founder_public_phone'),
                   '(no approved public contact is configured — tell the CEO)')) else null end,
    'person_reason', v_reason,
    'opened_by', case when v_asked then 'they asked'
                      when v_trouble then 'complaint or dispute'
                      else null end,

    'action', case
      when v_needs and v_held  then 'send_deterministic_and_log_shortfall'
      when v_needs             then 'walk_fallback_chain_with_fact_pack'
      else                          'send_deterministic' end,

    'transcription_gap', case when p_has_audio
      then 'Whether Gemini 3 Flash can take the Twilio media URL directly, or whether a speech model '
        || 'must be added to ai_model_register first, is NOT established and must be checked before '
        || 'audio is enabled.'
      else null end,

    'deterministic_reply', v_reply,
    'deterministic_intent', v_intent,
    'intent_decided_by', case when p_intent is null then 'held: not yet reasoned' else 'reasoning' end,
    'fact_pack', v_pack,
    'model_brief', public.fn_wa_model_brief()
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_wa_signature_watch()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n_rows int; n_senders int; v_last timestamptz;
begin
  if coalesce(new.meta ->> 'signature_valid', '') = 'false' then
    select count(*), count(distinct wa_from), max(created_at) into n_rows, n_senders, v_last
      from public.wa_messages
     where created_at > now() - interval '24 hours' and meta ->> 'signature_valid' = 'false';
    perform public.fn_it_engineer_finding_upsert(
      'wa_inbound:signature_refused',
      'Inbound WhatsApps are being refused at the door: ' || n_rows || ' failed X-Twilio-Signature in 24 hours, so nobody who wrote got an answer',
      'supabase/functions/wa_inbound (verifyTwilioSignature, signature.ts) and app_secrets.twilio_auth_token',
      'customer_facing', n_senders,
      jsonb_build_object('refused_24h', n_rows, 'senders_24h', n_senders, 'last_refused_at', v_last,
                         'last_reason', new.meta ->> 'signature_reason', 'urls_tried', new.meta -> 'signature_urls_tried',
                         'owner_seat', 'customer_support'),
      '{}'::text[],
      array['whether the refused request was a forgery or a genuine Twilio webhook signed over a URL or token we did not try'],
      'it_engineer.wa_signature_watch');
  elsif coalesce(new.meta ->> 'signature_valid', '') = 'true' or coalesce(new.meta ->> 'provenance_verified', '') = 'true' then
    if exists (select 1 from public.it_engineer_finding where issue_key = 'wa_inbound:signature_refused' and closed_at is null) then
      perform public.fn_it_engineer_finding_close('wa_inbound:signature_refused',
        'an inbound WhatsApp passed verification at ' || to_char(now() at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || 'Z (wa_messages ' || new.id || ')');
    end if;
  end if;
  return null;
exception when others then
  -- The watch must never cost the message row it is watching.
  raise warning 'fn_wa_signature_watch: %', sqlerrm;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_wa_sms_twin(p_notification_id bigint, p_body text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  w public.notifications%rowtype;
  v_twin bigint;
  v_mark text := 'sms failover: ' || left(coalesce(p_reason, 'WhatsApp unavailable'), 300);
begin
  select * into w from public.notifications where id = p_notification_id for update;
  if not found or w.channel <> 'whatsapp' then
    return jsonb_build_object('ok', false, 'outcome', 'not_a_whatsapp_notice');
  end if;
  if coalesce(w.to_phone, '') = '' or coalesce(btrim(p_body), '') = '' then
    return jsonb_build_object('ok', false, 'outcome', 'nothing_to_send');
  end if;
  select id into v_twin from public.notifications where failover_of = w.id;
  if v_twin is null then
    insert into public.notifications (channel, status, type, kind, to_phone, to_email, to_role, lead_id, inquiry_id,
                                      quote_id, subject, body, lang, requested_by, severity, failover_of)
    values ('sms', 'queued', w.type, w.kind, w.to_phone, w.to_email, w.to_role, w.lead_id, w.inquiry_id,
            w.quote_id, w.subject, left(p_body, 600), w.lang, w.requested_by, w.severity, w.id)
    on conflict (failover_of) where failover_of is not null do nothing
    returning id into v_twin;
    if v_twin is null then select id into v_twin from public.notifications where failover_of = w.id; end if;
  end if;
  -- A row not yet sent leaves the WhatsApp queue; a row that already failed keeps 'failed' (the truth) and
  -- carries the mark, which is also what stops send_whatsapp's failed-row scan asking again.
  update public.notifications
     set status = case when status in ('queued', 'sending') then 'skipped' else status end,
         last_error = left(case when status in ('queued', 'sending') then v_mark
                                else coalesce(last_error || '; ', '') || v_mark end, 500)
   where id = w.id and coalesce(last_error, '') not like '%sms failover:%';
  return jsonb_build_object('ok', true, 'outcome', 'sms_twin', 'sms_id', v_twin);
end $function$


CREATE OR REPLACE FUNCTION public.fn_wa_template_registry_follows_messaging_template()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_status text;
begin
  if new.channel is distinct from 'whatsapp' or new.last_checked_at is null then return new; end if;
  v_status := case when new.status in ('approved', 'rejected') then new.status
                   when new.status in ('received', 'pending', 'submitted', 'in_review', 'unsubmitted') then 'pending' end;
  if v_status is null then return new; end if;
  update public.wa_template_registry r
     set status = v_status,
         checked_at = new.last_checked_at,
         approved_on = case when v_status = 'approved' then coalesce(r.approved_on, new.last_checked_at::date) else r.approved_on end,
         source = 'wa_templates_watch: Twilio Content API said "' || new.status || '" on '
                  || to_char(new.last_checked_at at time zone 'UTC', 'DD Mon YYYY HH24:MI') || ' UTC (messaging_template ' || new.sid || ')'
   where r.template_name = new.name
     and (r.checked_at is null or r.checked_at < new.last_checked_at);
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_wa_unmatched_reply()
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
  select 'I can help with your registration, your documents, your quotes, and any job by its number. '
      || 'I am not sure about that one, so let me check and someone will come back to you.'
$function$


CREATE OR REPLACE FUNCTION public.fn_watch_failed_runs()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_stale record;
  v_stale_n int := 0;
  v_rehearsal int := 0;
  v_since    timestamptz;
  v_fail     record;
  v_alerts   int := 0;
  v_held     int := 0;
  v_real     int := 0;
  v_detail   text := '';
  v_models_answering boolean;
begin
  select coalesce(last_run_at, now() - interval '24 hours') into v_since
    from alert_watermark where watcher = 'failed_runs';
  if not found then
    insert into alert_watermark (watcher, last_run_at) values ('failed_runs', now() - interval '24 hours');
    v_since := now() - interval '24 hours';
  end if;

  -- IS A MODEL ANSWERING AT ALL? This one boolean is what separates "the AI is broken" from
  -- "the AI is switched off", and it is measured, not configured - nothing here reads a flag that
  -- someone could forget to clear. A single successful attempt in the last 24 hours is enough to
  -- put every model-unavailable error back on the failure side.
  select exists (select 1 from public.llm_attempt
                  where created_at > now() - interval '24 hours' and coalesce(ok, false))
    into v_models_answering;
  -- Rows inside a declared sandbox rehearsal window (demo_factory.withRun): counted, stated in the
  -- message if one goes out, never the reason one goes out. A rehearsal on the production database
  -- paged the founder twice on 3 Sep 2026 about the operator's own probes; this is the fix.
  select count(*) into v_rehearsal
    from agent_runs r
   where r.started_at > v_since and r.status = 'error'
     and public.fn_rehearsal_window_covers(r.started_at);

  for v_fail in
    select r.agent,
           count(*) as fails,
           max(r.started_at) as latest,
           left(coalesce(max(r.note), ''), 300) as sample_note,
           -- The signature is the agent plus the shape of the note, not the note itself: the same
           -- standing condition arrives with different numbers in it every pass ("3 step(s) are
           -- ready" one hour, "4" the next) and must still be recognised as the same condition.
           r.agent || ':' || left(regexp_replace(coalesce(max(r.note), ''), '[0-9]+', '#', 'g'), 120) as signature,
           bool_or(coalesce(r.note, '') ~* '(model returned nothing|returned no content|generation_failed|returned nothing for|model call failed|open-circuit|LLM call failed)') as model_shaped
      from agent_runs r
     where r.started_at > v_since and r.status = 'error'
       -- a row inside a DECLARED rehearsal window is counted below, not paged (3 Sep 2026)
       and not public.fn_rehearsal_window_covers(r.started_at)
     group by r.agent, left(regexp_replace(coalesce(r.note, ''), '[0-9]+', '#', 'g'), 120)
     order by count(*) desc
  loop
    -- HELD: a model did not answer, and no model has answered at all. Counted, recorded, not
    -- alerted. The moment v_models_answering flips true this branch stops being taken.
    if v_fail.model_shaped and not v_models_answering then
      v_held := v_held + v_fail.fails;
      insert into public.alert_signature (watcher, signature)
        values ('failed_runs', v_fail.signature)
        on conflict (watcher, signature) do update
          set last_seen_at = now(), seen_count = alert_signature.seen_count + 1, resolved_at = null;
      continue;
    end if;

    v_real := v_real + v_fail.fails;

    -- ONCE PER CONDITION. A signature alerted inside the last 24 hours is still recorded as seen,
    -- and does not interrupt him again.
    insert into public.alert_signature (watcher, signature)
      values ('failed_runs', v_fail.signature)
      on conflict (watcher, signature) do update
        set last_seen_at = now(), seen_count = alert_signature.seen_count + 1, resolved_at = null;

    if exists (select 1 from public.alert_signature s
                where s.watcher = 'failed_runs' and s.signature = v_fail.signature
                  and s.last_alerted_at > now() - interval '24 hours') then
      continue;
    end if;

    v_detail := v_detail || v_fail.agent || ': ' || v_fail.fails || ' failure(s). ' || v_fail.sample_note || E'\n';
    v_alerts := v_alerts + 1;
    update public.alert_signature set last_alerted_at = now()
      where watcher = 'failed_runs' and signature = v_fail.signature;
  end loop;

  -- The hold is stated once, in the same message, so it is never invisible: he should be able to
  -- see that the quiet is his own decision and not a working company.
  if v_held > 0 then
    v_detail := v_detail || E'\n' || v_held ||
      ' further run(s) could not reach a model. No model call has succeeded in 24 hours, so these ' ||
      'are counted as held by the paid-inference hold, not as failures. They will be reported as ' ||
      'failures again the moment a model answers.' || E'\n';
  end if;

  -- THE DEAD-GUARD BLIND SPOT (3 Sep 2026). A job that never fires produces no failure. v_cron_stale
  -- lists active jobs with no run of any status inside twice their schedule, measured from activation
  -- (scripts/sql/v_cron_stale_the_dead_guard_blind_spot.sql). Same ledger, same once-per-24h rule.
  for v_stale in select jobname, schedule, why from public.v_cron_stale order by jobname loop
    v_stale_n := v_stale_n + 1;
    insert into public.alert_signature (watcher, signature) values ('failed_runs', 'cron_stale:' || v_stale.jobname)
    on conflict (watcher, signature) do update set last_seen_at = now(), seen_count = alert_signature.seen_count + 1, resolved_at = null;
    if exists (select 1 from public.alert_signature s where s.watcher = 'failed_runs'
                 and s.signature = 'cron_stale:' || v_stale.jobname and s.last_alerted_at > now() - interval '24 hours') then
      continue;
    end if;
    v_detail := v_detail || 'cron ' || v_stale.jobname || ' has NOT FIRED: ' || v_stale.why || E'\n';
    v_alerts := v_alerts + 1;
    update public.alert_signature set last_alerted_at = now() where watcher = 'failed_runs' and signature = 'cron_stale:' || v_stale.jobname;
  end loop;

  -- A SIGNATURE RESOLVES ON MERIT, NOT ON THE CLOCK (5 Sep 2026). The red view carried a watcher
  -- episode for 24 h after the last sighting whatever the subject did next. kb_embed had run
  -- 'ok' 83 times after its last error and dr_drill 4 times, and both stayed red; monthly_report was
  -- listed stale every hour and paged every day because v_cron_stale read '0 7 1 * *' as daily.
  -- Two rules, both measured from the subject's own ledger:
  --   failed-run signature  -> resolved when the agent has a status='ok' run started AFTER the
  --                            watcher last saw the failure (last_seen_at). A later failure re-opens
  --                            it through the upsert above (resolved_at = null), which the red view
  --                            then treats as a NEW episode and pages again.
  --   cron_stale signature  -> resolved when the job is no longer listed by v_cron_stale on this
  --                            pass, i.e. a run of any status has been recorded since.
  update public.alert_signature s
     set resolved_at = now()
   where s.watcher = 'failed_runs' and s.resolved_at is null
     and s.signature not like 'cron_stale:%'
     and exists (select 1 from public.agent_runs ok
                  where ok.agent = split_part(s.signature, ':', 1)
                    and ok.status = 'ok' and ok.started_at > s.last_seen_at);
  update public.alert_signature s
     set resolved_at = now()
   where s.watcher = 'failed_runs' and s.resolved_at is null
     and s.signature like 'cron_stale:%'
     and not exists (select 1 from public.v_cron_stale c where 'cron_stale:' || c.jobname = s.signature);

  if v_rehearsal > 0 then
    v_detail := v_detail || E'\n' || v_rehearsal || ' further run(s) failed inside a declared sandbox rehearsal window and were not paged.' || E'\n';
  end if;

  if v_alerts > 0 then
    -- 6 SEP 2026: fn_notify_founder, not an HTTP hop to alert_founder. founder_mail_policy routes this kind
    -- (scheduled_runs_failed) to the IT operations engineer as ONE org_task per condition; it never emails him.
    perform public.fn_notify_founder(
      'Scheduled runs failed (' || v_alerts || ' new condition(s))', v_detail, 'error',
      p_kind => 'scheduled_runs_failed',
      -- Dedupe on the day, not the hour. The hour made the key change every pass, which is why
      -- a dedupe key existed for three weeks and never deduplicated anything.
      p_dedupe_key => 'failed_runs:' || to_char(now(),'YYYY-MM-DD'));
    update alert_watermark set last_alert_at = now() where watcher = 'failed_runs';
  end if;

  update alert_watermark set last_run_at = now() where watcher = 'failed_runs';
  return jsonb_build_object(
    'checked_since', v_since,
    'models_answering', v_models_answering,
    'runs_failed', v_real,
    'runs_held_by_ai_hold', v_held,
    'runs_in_declared_rehearsal', v_rehearsal,
    'crons_stale', v_stale_n,
    'new_conditions_alerted', v_alerts,
    'alerted', v_alerts > 0);
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_web_search_claim(p_query text, p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_q    text := public.fn_web_search_norm(p_query);
  v_day  date := (p_now at time zone 'Asia/Dubai')::date;
  v_used integer;
begin
  -- 1. emails: any address in the query that the company holds for a party (exact, case-folded)
  if exists (
    select 1 from regexp_matches(lower(coalesce(p_query, '')), '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}', 'g') m(e)
     where exists (select 1 from public.leads l where lower(l.email) = m.e[1])
        or exists (select 1 from public.customers c where lower(c.email) = m.e[1])) then
    return jsonb_build_object('allowed', false, 'reason', 'names_a_private_party');
  end if;
  -- 2. phones: any number in the query, as its national number, equal to one held for a party
  if exists (
    select 1 from regexp_matches(coalesce(public.fn_ar_norm(p_query), ''), '\+?[0-9][0-9 ().-]{5,}[0-9]', 'g') m(t)
     cross join lateral (select public.fn_web_search_phone(m.t[1]) n) q
     where length(q.n) >= 7 and exists (
       select 1 from public.leads l
        cross join lateral (values (l.phone), (l.phone_e164), (l.whatsapp), (l.whatsapp_phone)) x(v)
        where public.fn_web_search_phone(x.v) = q.n
       union all
       select 1 from public.customers c
        cross join lateral (values (c.phone), (c.whatsapp_phone)) x(v)
        where public.fn_web_search_phone(x.v) = q.n)) then
    return jsonb_build_object('allowed', false, 'reason', 'names_a_private_party');
  end if;
  -- 3. names: the exact held name of a party, as a whole phrase of the normalised query. A lead at a *.gov.ae
  --    domain is an authority: only its COMPANY name is exempt; its contact and signatory are people.
  if exists (
    select 1 from (
      select x.n from public.leads l
       cross join lateral (values
         (case when coalesce(l.email_domain, '') ~ '(^|\.)gov\.ae$' then null else l.company_name end),
         (l.licence_legal_name), (l.contact_name), (l.signatory_name)) x(n)
      union all select full_name from public.customers union all select full_name from public.supplier_beneficial_owner
    ) s
     where length(btrim(public.fn_web_search_norm(s.n))) >= 3
       and position(public.fn_web_search_norm(s.n) in v_q) > 0) then
    return jsonb_build_object('allowed', false, 'reason', 'names_a_private_party');
  end if;
  -- 4. the day's cap, counted atomically
  insert into public.web_search_day as d (day, used) values (v_day, 1)
  on conflict (day) do update set used = d.used + 1, updated_at = now() where d.used < d.cap
  returning used into v_used;
  if v_used is null then
    perform public.fn_web_search_degraded('daily_cap', false,
      'the daily cap of ' || (select cap from public.web_search_day where day = v_day) || ' searches is reached for ' || v_day);
    return jsonb_build_object('allowed', false, 'reason', 'daily_cap');
  end if;
  return jsonb_build_object('allowed', true, 'used', v_used);
end $function$


CREATE OR REPLACE FUNCTION public.fn_web_search_degraded(p_reason text, p_notify boolean, p_detail text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_billing boolean := p_reason = 'key_or_billing';
  v_key text := 'duty:integration:web_search:' || case when v_billing then 'billing' else 'outage' end;
begin
  perform public.fn_it_engineer_finding_upsert(
    v_key,
    'web_search (Serper): ' || coalesce(p_detail, p_reason) || '. The seats reason without the web until it answers again',
    'supabase/functions/_shared/web_search.ts', 'agent_facing', 1,
    jsonb_build_object('integration', 'web_search', 'owner_seat', 'it_engineer', 'reason', p_reason,
                       'notify', coalesce(p_notify, false) and v_billing,
                       'reconnect_url', 'https://serper.dev/'),
    '{}'::text[], '{}'::text[], 'it_engineer.web_search');
  return jsonb_build_object('raised', true, 'reason', p_reason, 'issue_key', v_key);
end $function$


CREATE OR REPLACE FUNCTION public.fn_web_search_norm(p_text text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select ' ' || btrim(regexp_replace(replace(lower(coalesce(public.fn_ar_norm(p_text), '')), '.', ''), '[^[:alnum:]]+', ' ', 'g')) || ' '
$function$


CREATE OR REPLACE FUNCTION public.fn_web_search_phone(p_text text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select nullif(regexp_replace(regexp_replace(coalesce(public.fn_ar_norm(p_text), ''), '[^0-9]', '', 'g'), '^(00971|971|0)', ''), '')
$function$


CREATE OR REPLACE FUNCTION public.fn_what_if(p_question text, p_change jsonb DEFAULT '{}'::jsonb, p_scenario text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_sup int; v_rev numeric; v_cost numeric; v_conv numeric; v_pool int;
  v_impact jsonb; v_conf numeric; v_id bigint; v_held bigint; v_req jsonb;
  v_d_rev numeric; v_d_leads numeric; v_d_profit numeric;
begin
  -- WHICH SCENARIO: the caller's key, or reasoning. Nothing is read out of the question's words.
  if p_scenario is null then
    v_req := jsonb_build_object('seat', 'ceo', 'surface', 'ceo.what_if', 'question', left(coalesce(p_question, ''), 8000),
      'context', jsonb_build_object('audience', 'internal'),
      'decision', jsonb_build_object('name', 'scenario', 'options', jsonb_build_array(
        jsonb_build_object('id', 'reveal_fee_discount', 'meaning', 'what happens if the reveal fee (the price customers pay) is lowered or discounted'),
        jsonb_build_object('id', 'ai_cost_double',      'meaning', 'what happens if the cost of AI models / LLM calls rises, e.g. doubles'),
        jsonb_build_object('id', 'supplier_invites',    'meaning', 'what happens if we invite or onboard more suppliers, or scale the supply side'),
        jsonb_build_object('id', 'market_expansion',    'meaning', 'what happens if we expand to a new market or country'),
        jsonb_build_object('id', 'unmodelled',          'meaning', 'any other question: no simulation model exists for it yet'))),
      'subject', jsonb_build_object('question', p_question, 'change', coalesce(p_change, '{}'::jsonb)),
      'dedupeKey', 'what_if:' || md5(coalesce(p_question, '') || '|' || coalesce(p_change::text, '')));
    v_held := public.fn_reason_hold('ceo', 'ceo.what_if', left(coalesce(p_question, ''), 8000), v_req, '{}'::jsonb, v_req->'subject',
                                    'sql_caller', v_req->>'dedupeKey');
    return jsonb_build_object('status', 'held', 'held_id', v_held, 'question', p_question,
      'note', 'Which scenario this question asks about is being reasoned (held question #' || v_held || '); the simulation runs when it is.');
  end if;

  select count(*) into v_sup from leads where approval_status='approved';
  select coalesce(sum(coalesce(reveal_fee,app_fee,0)),0) into v_rev from transactions where revealed_at>now()-interval '30 days';
  select coalesce(sum(cost_aed),0) into v_cost from ai_cost_log where occurred_at>now()-interval '30 days';
  select coalesce(sum(sendable),0) into v_pool from v_supply_gap;
  v_conv := 0.05;

  if p_scenario = 'reveal_fee_discount' then
    v_impact := jsonb_build_object('revenue_per_reveal','down by the discount percentage',
      'reveal_volume','unknown - no reveals have occurred, so elasticity is unmeasured',
      'net_revenue','indeterminate',
      'honest_answer','This cannot be simulated. Zero reveals have happened, so there is no price-response curve to extrapolate from. Any number would be invented.');
    v_conf := 0.15;
    v_d_rev := null; v_d_leads := null; v_d_profit := null;

  elsif p_scenario = 'ai_cost_double' then
    v_impact := jsonb_build_object('current_monthly_ai_cost_aed',round(v_cost,2),'if_doubled_aed',round(v_cost*2,2),
      'share_of_total_budget', round(100.0*v_cost*2/nullif((select sum(monthly_aed) from department_budget),0),1)||'%',
      'mitigation','Model policy already routes by task class. Prompt-cache reads are '
        ||coalesce((select round(100.0*sum(cached_in_tokens)/nullif(sum(prompt_tokens),0),1)::text
                      from ai_cost_log where occurred_at > now() - interval '30 days'),'0')
        ||'% of prompt tokens over 30 days ('
        ||coalesce((select sum(cached_in_tokens)::text from ai_cost_log
                     where occurred_at > now() - interval '30 days'),'0')
        ||' read against '
        ||coalesce((select sum(cache_write_tokens)::text from ai_cost_log
                     where occurred_at > now() - interval '30 days'),'0')
        ||' written at a 1.25x premium), so caching pays only above roughly 22% and is measured here rather than assumed.');
    v_conf := 0.8;
    v_d_rev := null; v_d_leads := null; v_d_profit := -round(v_cost,2);

  elsif p_scenario = 'supplier_invites' then
    v_impact := jsonb_build_object('sendable_pool',v_pool,'expected_approved_at_5pct',round(v_pool*v_conv),
      'target',860,'shortfall',greatest(0,860-round(v_pool*v_conv)),
      'note','Assumes a 5% invite-to-approved conversion, which is an assumption not an observation - no invite has converted yet.');
    v_conf := 0.45;
    v_d_rev := null; v_d_leads := round(v_pool*v_conv); v_d_profit := null;

  elsif p_scenario = 'market_expansion' then
    v_impact := jsonb_build_object('home_market_readiness',(select count(*) from v_supply_gap where approved>=10)||' of 86 categories at target',
      'assessment','Expanding before the home market has any onboarded supply spreads a thin pool thinner and the category knowledge is UAE-specific.');
    v_conf := 0.7;
    v_d_rev := null; v_d_leads := null; v_d_profit := null;
  else
    v_impact := jsonb_build_object('assessment','No model exists for this question yet. Add a scenario to scenario_library so it can be simulated rather than guessed.');
    v_conf := 0.2;
    v_d_rev := null; v_d_leads := null; v_d_profit := null;
  end if;

  v_impact := v_impact || jsonb_build_object(
    'projected_revenue_delta_aed', v_d_rev,
    'projected_leads_delta',       v_d_leads,
    'projected_profit_delta_aed',  v_d_profit,
    'scenario', p_scenario,
    'delta_note', 'A null delta means this scenario does not model that dimension. It does not mean the delta is zero.');

  insert into simulations (scenario, result)
  values (jsonb_build_object('question',p_question,'change',p_change,'confidence',v_conf,'scenario',p_scenario),
          v_impact || jsonb_build_object('confidence', coalesce((v_impact->>'confidence')::numeric, v_conf)))
  returning id into v_id;

  if v_conf >= 0.5 then
    insert into agent_actions(agent, kind, status, risk, title, recommendation, detail,
                              target_table, target_id, confidence, evidence)
    values ('strategy_director', 'simulation_apply', 'pending', 'medium',
            left('Act on the simulation: ' || p_question, 200),
            coalesce(v_impact->>'assessment',
                     'The simulation returned a projection; open it to see the modelled figures.')
              || ' Approving this accepts the modelled change; the projection and its basis are on '
              || 'simulation #' || v_id || '.',
            jsonb_build_object('simulation_id', v_id, 'question', p_question,
                               'change', p_change, 'projection', v_impact),
            'simulations', v_id::text, v_conf,
            jsonb_build_object('basis', 'simulation #' || v_id || ' of "' || p_question || '"',
                               'simulation_id', v_id, 'confidence', v_conf, 'projection', v_impact));
  end if;

  return jsonb_build_object('id',v_id,'question',p_question,'projection',v_impact,'confidence',v_conf,'scenario',p_scenario,
    'basis', jsonb_build_object('approved_suppliers',v_sup,'revenue_30d',v_rev,'ai_cost_30d',round(v_cost,2),'sendable_pool',v_pool));
end $function$


CREATE OR REPLACE FUNCTION public.fn_whatsapp_destination(p_role text, p_customer uuid DEFAULT NULL::uuid, p_lead bigint DEFAULT NULL::bigint, p_email text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_opt text; v_wa text; v_at timestamptz;
begin
  if p_role = 'customer' then
    select c.whatsapp_opt, c.whatsapp_phone, c.whatsapp_verified_at into v_opt, v_wa, v_at from public.customers c
     where c.id = p_customer or (p_customer is null and p_email is not null and lower(c.email) = lower(btrim(p_email))) limit 1;
  elsif p_role = 'supplier' then
    select l.whatsapp_opt, l.whatsapp_phone, l.whatsapp_verified_at into v_opt, v_wa, v_at from public.leads l
     where l.id = p_lead or (p_lead is null and p_email is not null and lower(l.claimed_by) = lower(btrim(p_email))) order by l.id limit 1;
  else
    return null;
  end if;
  if v_opt = 'other' and v_at is not null and nullif(btrim(v_wa), '') is not null then return v_wa; end if;
  if v_opt = 'same' then return public.fn_verified_mobile(p_role, p_customer, p_lead, p_email); end if;
  return null;   -- 'none', unanswered, or an 'other' number not yet verified
end $function$


CREATE OR REPLACE FUNCTION public.fn_whatsapp_owner(p_phone text, p_all boolean DEFAULT false)
 RETURNS TABLE(party_kind text, customer_id uuid, lead_id bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with t as (select right(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), 9) as tail),
  hits as (
    select 'customer'::text as party_kind, c.id as customer_id, null::bigint as lead_id
      from public.customers c, t
     where length(t.tail) = 9
       and ((c.whatsapp_opt = 'other' and c.whatsapp_verified_at is not null
             and right(regexp_replace(coalesce(c.whatsapp_phone, ''), '[^0-9]', '', 'g'), 9) = t.tail)
         or (c.whatsapp_opt = 'same' and coalesce(c.phone_verified, false)
             and right(regexp_replace(coalesce(c.phone, ''), '[^0-9]', '', 'g'), 9) = t.tail))
    union
    select 'supplier', null, l.id
      from public.leads l, t
     where length(t.tail) = 9
       -- 18 Sep 2026, founder instruction 516: a confirmed sanctions ban means the handset names
       -- nobody. WhatsApp is the one channel with no session to refuse.
       and not exists (select 1 from public.sanctions_ban b where b.lead_id = l.id)
       and ((l.whatsapp_opt = 'other' and l.whatsapp_verified_at is not null
             and right(regexp_replace(coalesce(l.whatsapp_phone, ''), '[^0-9]', '', 'g'), 9) = t.tail)
         or (l.whatsapp_opt = 'same' and coalesce(l.owner_phone_verified, false)
             and right(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 9) = t.tail)))
  -- A PHONE MAY CONFIRM, NEVER SELECT: one party or nobody.
  select h.party_kind, h.customer_id, h.lead_id from hits h where p_all or (select count(*) from hits) = 1
$function$


CREATE OR REPLACE FUNCTION public.fn_workflow_actor_resolve(p_run uuid, p_actor text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_ctx jsonb; v_owner text; v_live text; v_tid bigint;
begin
  if p_actor is null or btrim(p_actor) = '' then return null; end if;

  if lower(btrim(p_actor)) not in ('owner', 'director', 'dept_head', 'department head') then
    return public.fn_org_agent_resolve(p_actor);
  end if;

  select r.context into v_ctx from public.workflow_run r where r.id = p_run;
  if v_ctx is null then return null; end if;

  -- The owner is the assignee of the task this run was raised for. employee_task runs carry
  -- context.task_id; the guard on the cast is there because context is free-form jsonb and a
  -- non-numeric task_id would abort the whole planning statement rather than skip one step.
  if coalesce(v_ctx->>'task_id','') ~ '^[0-9]+$' then
    v_tid := (v_ctx->>'task_id')::bigint;
    select t.assigned_agent into v_owner from public.org_tasks t where t.id = v_tid;
  end if;
  if v_owner is null then v_owner := nullif(v_ctx->>'agent',''); end if;
  if v_owner is null then v_owner := public.fn_org_agent_resolve(nullif(v_ctx->>'dept_key','')); end if;

  select o.agent_key into v_live from public.org_agents o where o.agent_key = v_owner and o.active;
  if v_live is null then return null; end if;

  if lower(btrim(p_actor)) = 'owner' then return v_live; end if;

  -- 'Director' on employee_task step 10 is "department head review" - the owner's own manager,
  -- which org_agents.manager_key already models for 93 of 94 employees, acyclically.
  -- The owner's active manager is the department head. If the owner has no active manager (only the
  -- ceo, the top of the org), the owner is its own department head, so 'Director' never resolves to
  -- no employee and never stalls a run at step 10.
  return coalesce(
    (select m.agent_key
       from public.org_agents o
       join public.org_agents m on m.agent_key = o.manager_key and m.active
      where o.agent_key = v_live),
    v_live);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_workflow_run_follow_task()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_run uuid; v_run_status text;
begin
  if new.status is not distinct from old.status then return new; end if;
  if new.status not in ('done','failed','escalated','cancelled') then return new; end if;

  v_run_status := case when new.status = 'done' then 'done'
                       when new.status = 'cancelled' then 'cancelled'
                       else 'failed' end;

  for v_run in
    select r.id from public.workflow_run r
     where r.workflow_key = 'employee_task'
       and r.status = 'running'
       and (r.context->>'task_id') = new.id::text
  loop
    update public.workflow_step_run
       set status = 'skipped', finished_at = now(),
           output = coalesce(output, '{}'::jsonb) || jsonb_build_object(
             'closed_by', 'owning_org_task', 'org_task_id', new.id,
             'org_task_status', new.status,
             'used_llm', case when (new.result->>'used_llm') in ('true','false') then (new.result->>'used_llm')::boolean else null end,
             'note', case when new.status = 'cancelled'
                          then 'the owning task was cancelled; this step was never separately observed, so it is skipped rather than claimed as done'
                          else 'the owning task was performed and reviewed as one act; this step was never '
                            || 'separately observed, so it is skipped rather than claimed as done' end)
     where workflow_run_id = v_run and finished_at is null;

    update public.workflow_run
       set status      = v_run_status,
           finished_at = now(),
           updated_at  = now(),
           context     = coalesce(context,'{}'::jsonb)
                         || jsonb_build_object('closed_by','owning_org_task',
                                               'org_task_status', new.status,
                                               'used_llm', case when (new.result->>'used_llm') in ('true','false') then (new.result->>'used_llm')::boolean else null end),
           error       = case when new.status = 'done' then null
                              else jsonb_build_object('owning_org_task', new.id,
                                                      'org_task_status', new.status,
                                                      'reason', case when new.status = 'cancelled' then 'the owning org_task was cancelled' else 'the owning org_task ended ' || new.status end) end
     where id = v_run;
  end loop;
  return new;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_workflow_start(p_workflow_key text, p_trigger_event_id bigint DEFAULT NULL::bigint, p_entity_type text DEFAULT NULL::text, p_entity_id text DEFAULT NULL::text, p_context jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_run uuid; v_key text; v_corr uuid; v_first int;
begin
  if not exists (select 1 from workflow w where w.workflow_key = p_workflow_key and coalesce(w.active,true))
    then return null; end if;

  -- One run per (workflow, triggering event). Without the event there is nothing to be idempotent
  -- against, so a manual start gets its own key rather than silently colliding with the last one.
  v_key := p_workflow_key || ':' || coalesce(p_trigger_event_id::text, gen_random_uuid()::text);

  select e.correlation_id into v_corr from company_event e where e.id = p_trigger_event_id;
  -- 4 SEP 2026: a run started WITHOUT a triggering event begins its own correlation.
  -- The line above finds nothing when p_trigger_event_id is null, workflow_run.correlation_id is
  -- NOT NULL, and the insert below therefore raised 23502 on every eventless start. The line before
  -- it already anticipates exactly this case -- it mints a fresh idempotency key rather than
  -- colliding -- so the omission was in the next statement, not in the design.
  --
  -- It is the reason MASTER_PLAN 4.3's one-spine design never ran: fn_org_task_promote is the leg
  -- that lifts an org_task onto the workflow spine, it calls this with a null event because a
  -- backlog task has no event, every call raised, and the promoter's own
  -- `exception when others then null` swallowed it. Measured: 0 of 301 employee_task runs ever
  -- created carry promoted_by = fn_org_task_promote, and the raise reproduces on any backlog task.
  -- Correlation ties together work that shares a cause; a promoted task IS its own cause.
  v_corr := coalesce(v_corr, gen_random_uuid());

  insert into workflow_run (workflow_key, trigger_event_id, correlation_id, entity_type, entity_id,
                            idempotency_key, status, current_step, context, started_at)
  values (p_workflow_key, p_trigger_event_id, v_corr, p_entity_type, p_entity_id,
          v_key, 'running', 0, coalesce(p_context,'{}'::jsonb), now())
  on conflict (idempotency_key) do nothing
  returning id into v_run;

  if v_run is null then
    select id into v_run from workflow_run where idempotency_key = v_key;
    return v_run;                      -- already started; nothing to re-plan
  end if;

  -- Plan every step of the workflow up front. A run whose steps are only materialised as they are
  -- reached cannot be read as "where is this piece of work", which is the entire value of the table.
  --
  -- THE ACTOR IS RESOLVED HERE (11 Aug 2026). It used to copy workflow_step.actor_role verbatim,
  -- and actor_role is not one namespace - see the header. Resolving in the dispatcher instead
  -- would leave the stored row still addressed to nobody, which is the defect this codebase keeps
  -- reproducing. addressed_as keeps the original wording so no reassignment is silent.
  insert into workflow_step_run (workflow_run_id, step_no, actor, action_class, status,
                                 input, idempotency_key)
  select v_run, s.step_no, coalesce(x.resolved, s.actor_role), s.action_class, 'queued',
         jsonb_build_object('step', s.step, 'gate', s.gate)
           || case when x.resolved is not null and x.resolved is distinct from s.actor_role
                   then jsonb_build_object('addressed_as', s.actor_role)
                   else '{}'::jsonb end,
         v_key || '#' || s.step_no
    from workflow_step s
    cross join lateral (select public.fn_workflow_actor_resolve(v_run, s.actor_role) as resolved) x
   where s.workflow_key = p_workflow_key
   order by s.step_no
  on conflict (idempotency_key) do nothing;

  select min(step_no) into v_first from workflow_step_run where workflow_run_id = v_run;
  if v_first is null then
    -- A workflow with no steps cannot be in flight. Closing it here stops it sitting in the
    -- in-flight list forever pretending to be work.
    update workflow_run set status = 'done', finished_at = now(), updated_at = now()
     where id = v_run;
    return v_run;
  end if;

  update workflow_step_run set status = 'ready', started_at = now()
   where workflow_run_id = v_run and step_no = v_first;
  update workflow_run set current_step = v_first, updated_at = now() where id = v_run;
  return v_run;
end $function$


CREATE OR REPLACE FUNCTION public.fn_workflow_start_due(p_lookback_minutes integer DEFAULT 1440)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; n int := 0;
begin
  for r in
    select w.workflow_key, e.id, e.event_type, e.payload
      from company_event e
      join workflow w on w.trigger_event = e.event_type and coalesce(w.active,true)
     where p_lookback_minutes = 0
        or e.occurred_at > now() - make_interval(mins => p_lookback_minutes)
     order by e.id
     limit 200
  loop
    if not exists (select 1 from workflow_run x
                    where x.idempotency_key = r.workflow_key || ':' || r.id::text) then
      perform public.fn_workflow_start(r.workflow_key, r.id, 'company_event', r.id::text,
                                       coalesce(r.payload,'{}'::jsonb));
      n := n + 1;
    end if;
  end loop;
  return n;
end $function$


CREATE OR REPLACE FUNCTION public.fn_workflow_step_claim(p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_out jsonb; v_today int; v_cap int; v_demand_ready int; v_held boolean;
begin
  v_held := coalesce((public.fn_kernel_paid_provider_gate('anthropic/claude-sonnet-5')->>'allowed')::boolean, false) = false;

  update public.workflow_step_run sr
     set status = 'ready'
   where sr.status = 'running'
     and sr.finished_at is null
     and sr.started_at < now() - interval '15 minutes'
     and not exists (select 1 from public.action_execution x
                      where x.workflow_step_run_id = sr.id
                        and x.status in ('queued','running','succeeded'));

  select coalesce((value #>> '{}')::int, 6) into v_cap
    from public.decision_policy where key = 'workflow_reflection_steps_per_day';
  v_cap := coalesce(v_cap, 6);

  -- NON-DEMAND ONLY, and MODEL WORK ONLY: the ceiling exists to bound paid reasoning. A deterministic
  -- determination costs nothing and is not counted against it.
  select count(*) into v_today
    from public.workflow_step_run sr
   where sr.output->>'worked_by' = 'workflow_dispatch'
     and coalesce(sr.output->>'used_llm', 'true') <> 'false'
     and sr.finished_at >= date_trunc('day', now() at time zone 'utc') at time zone 'utc'
     and not public.fn_task_is_demand(sr.action_class);

  select count(*) into v_demand_ready
    from public.workflow_step_run sr
    join public.workflow_run r on r.id = sr.workflow_run_id
   where sr.status = 'ready'
     and sr.finished_at is null
     and r.status = 'running'
     and r.workflow_key <> 'employee_task'
     and coalesce(sr.input->>'gate','') <> 'founder'
     and public.fn_task_is_demand(sr.action_class)
     and public.fn_workflow_actor_resolve(sr.workflow_run_id, sr.actor) is not null
     and not exists (
           select 1 from public.org_action_executor e
            where e.action_class = sr.action_class and e.active and e.kind in ('edge','rpc')
              and e.risk_tier = 'low' and e.advisory_safe and e.reversible
              and not e.notifies_human
              and coalesce(e.required_authority,'') <> 'founder');

  if not v_held and v_today >= v_cap and v_demand_ready = 0 then
    return jsonb_build_object('capped', true, 'worked_today', v_today, 'cap', v_cap,
             'demand_ready', 0,
             'note', 'the daily reflection ceiling is spent and no revenue-path step is waiting; see '
                     || 'scripts/sql/the_dispatchers_ceiling_counted_revenue_work_against_reflection.sql');
  end if;

  with pick as (
    select sr.id
      from public.workflow_step_run sr
      join public.workflow_run r on r.id = sr.workflow_run_id
     where sr.status = 'ready'
       and sr.finished_at is null
       and r.status = 'running'
       -- THE ORG_TASK LANE (§4.3). An employee_task run is the promotion of one org_task into the
       -- spine; the dispatcher works it while the task is still open, and the follow trigger owns it
       -- once the task has closed or parked. A run whose task is gone is nobody's work.
       and (r.workflow_key <> 'employee_task'
            or exists (select 1 from public.org_tasks t
                        where t.id::text = r.context->>'task_id'
                          and t.status in ('assigned','in_progress')))
       and coalesce(sr.input->>'gate','') <> 'founder'
       -- the reflection ceiling is untouched: it bounds PAID reasoning, and while the model is held
       -- (v_held) nothing here can reach a paid provider. When the hold lifts the lane obeys it.
       and (public.fn_task_is_demand(sr.action_class) or v_today < v_cap or v_held)
       and public.fn_workflow_actor_resolve(sr.workflow_run_id, sr.actor) is not null
       -- parked awaiting the model: not claimed again until the hold lifts
       and not (v_held and coalesce(sr.error->>'disposition','') = 'awaiting_model')
       and (
         -- the org_task lane is always the dispatcher's: its executor (cos_execute on coordinate) was
         -- retired on 3 Sep and the sweep's low-risk predicate never accepted it
         r.workflow_key = 'employee_task'
         -- (a) no safe executor owns it: the dispatcher's row, as before
         or not exists (
             select 1 from public.org_action_executor e
              where e.action_class = sr.action_class and e.active and e.kind in ('edge','rpc')
                and e.risk_tier = 'low' and e.advisory_safe and e.reversible
                and not e.notifies_human
                and coalesce(e.required_authority,'') <> 'founder')
         -- (b) the model is held and the safe executor cannot finish it: it runs on the model, or it
         --     already left only terminal (held/cancelled/stalled) executions behind
         or (v_held and (
               exists (select 1 from public.org_action_executor e
                        where e.action_class = sr.action_class and e.active
                          and public.fn_executor_needs_model(e.target))
            -- stranded: parked held/stalled, or cancelled on a REFUSAL or a missing decision record.
            -- (A never-dispatched cancel is the sweep's to re-queue, not the dispatcher's.)
            or (exists (select 1 from public.action_execution x
                         where x.workflow_step_run_id = sr.id
                           and (x.status in ('held','stalled')
                                or (x.status = 'cancelled'
                                    and (x.response->>'invoker' = 'refused' or (x.request ? 'decision_record_id')))))
                and not exists (select 1 from public.action_execution x
                                 where x.workflow_step_run_id = sr.id
                                   and x.status in ('queued','running','succeeded')))))
       )
     -- fresh steps before retries: 24 change_deployment step-1 retries (3 attempts each before they
     -- park) must not starve a step that has never been looked at
     order by coalesce(sr.attempts, 0), sr.id
     limit greatest(least(coalesce(p_limit, 5),
                          case when v_held then coalesce(p_limit, 5)
                               else greatest(v_cap - v_today, 0) + v_demand_ready end), 1)
     for update of sr skip locked
  ), claimed as (
    update public.workflow_step_run sr
       set status = 'running', started_at = now()
      from pick
     where sr.id = pick.id
    returning sr.id, sr.workflow_run_id, sr.step_no, sr.actor, sr.action_class, sr.input, sr.attempts, sr.error
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'step_run_id',  c.id,
           'run_id',       c.workflow_run_id,
           'step_no',      c.step_no,
           'employee',     public.fn_workflow_actor_resolve(c.workflow_run_id, c.actor),
           'addressed_as', coalesce(c.input->>'addressed_as', c.actor),
           'action_class', c.action_class,
           'step',         c.input->>'step',
           'gate',         c.input->>'gate',
           'workflow_key', r.workflow_key,
           'workflow',     w.name,
           'context',      r.context,
           'attempts',     coalesce(c.attempts, 0),
           'model_held',   v_held,
           'deterministic_only', v_held,
           -- THE ORG_TASK LANE: the work is the task, not the loop step it is recorded under.
           'lane',                 case when r.workflow_key = 'employee_task' and t.id is not null then 'org_task' else 'workflow_step' end,
           'org_task_id',           t.id,
           'org_task_title',        t.title,
           'org_task_detail',       left(coalesce(t.detail, ''), 2000),
           'org_task_dept',         t.dept_key,
           'org_task_action_class', t.action_class,
           'org_task_subject',      case when t.id is null then null
                                         else public.fn_org_task_subject(t.title, t.action_class, t.dept_key) end,
           'stranded_reason', case
              when exists (select 1 from public.org_action_executor e
                            where e.action_class = c.action_class and e.active and e.kind in ('edge','rpc')
                              and e.risk_tier = 'low' and e.advisory_safe and e.reversible
                              and not e.notifies_human)
               then coalesce((select 'executor ' || coalesce(x.executor, e2.target) || ' left status=' || x.status
                                     || coalesce(' (' || (x.response->>'reason') || ')', '')
                                from public.action_execution x
                                join public.org_action_executor e2 on e2.action_class = c.action_class and e2.active
                               where x.workflow_step_run_id = c.id
                               order by x.created_at desc limit 1),
                             'executor runs on the held paid model; not queued')
              else null end,
           'prior_steps', (select coalesce(jsonb_agg(jsonb_build_object(
                                    'step_no', p.step_no,
                                    'step',    p.input->>'step',
                                    'by',      coalesce(p.output->>'employee', p.actor),
                                    'outcome', left(coalesce(p.output->>'outcome',
                                                             p.output->>'note', ''), 600))
                                  order by p.step_no), '[]'::jsonb)
                             from (select p2.* from public.workflow_step_run p2
                                    where p2.workflow_run_id = c.workflow_run_id
                                      and p2.step_no < c.step_no
                                      and p2.status = 'done'
                                      and coalesce(p2.output->>'outcome', p2.output->>'note','') <> ''
                                    order by p2.step_no desc
                                    limit 3) p)
         ) order by c.id), '[]'::jsonb)
    into v_out
    from claimed c
    join public.workflow_run r on r.id = c.workflow_run_id
    left join public.workflow w on w.workflow_key = r.workflow_key
    left join public.org_tasks t on r.workflow_key = 'employee_task'
                                and t.id::text = r.context->>'task_id';

  return v_out;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_workflow_step_deterministic_done(p_step_run_id bigint, p_output jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  sr           record;
  v_sim        numeric;
  v_floor      numeric := 0.85;
  v_terms      int;
  v_employee   text;
  v_dept       text;
  v_trace      uuid;
  v_review     bigint;
  v_superseded int := 0;
  v_res        text;
  v_out        jsonb;
  -- the record applied
  v_pb_id text; v_pb_title text; v_pb_type text; v_pb_content text; v_pb_sd jsonb;
  -- facts + rendering
  v_facts jsonb; v_bound int; v_deliv text; v_outcome text;
  -- executor
  ex record; v_has_ex boolean := false; v_needs_model boolean := false; v_exec_status text; v_exec_id uuid;
  v_exec_result jsonb; v_req_args int; v_kind text := null; v_source text := 'playbook_rendered';
  v_queued boolean := false; v_refused text; v_err text; v_target text;
  -- measurement
  v_llm int := 0; v_cost int := 0; v_used_llm boolean;
  v_disp text; v_mode text;
begin
  select s.id, s.workflow_run_id, s.step_no, s.actor, s.action_class, s.input, s.attempts, s.started_at, s.output as prev_output,
         r.workflow_key, r.context, r.correlation_id, r.trigger_event_id
    into sr
    from public.workflow_step_run s
    join public.workflow_run r on r.id = s.workflow_run_id
   where s.id = p_step_run_id and s.status = 'running' and s.finished_at is null;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'step is not held running by a dispatcher');
  end if;

  v_sim      := nullif(p_output->>'similarity', '')::numeric;
  v_terms    := nullif(p_output->>'terms_matched', '')::int;
  v_employee := coalesce(nullif(p_output->>'employee',''), sr.actor);

  -- FALSE-SUCCESS GUARDS. Nothing below runs unless the determination has substance. The floors are the
  -- applier's own (0.85 cosine AND keyword corroboration), so a caller cannot pass on cosine alone.
  if coalesce(p_output->>'playbook_record_id','') = '' then
    return jsonb_build_object('ok', false, 'reason', 'no playbook_record_id: a determination must cite the company knowledge it applied');
  end if;
  if v_sim is null or v_sim < v_floor then
    return jsonb_build_object('ok', false, 'reason', 'similarity ' || coalesce(v_sim::text,'null') || ' is below the apply floor ' || v_floor);
  end if;
  if v_terms is null or v_terms < 2 then
    return jsonb_build_object('ok', false, 'reason', 'terms_matched ' || coalesce(v_terms::text,'null') || ' is below the corroboration floor of 2 step terms');
  end if;
  select k.record_id, k.title, k.record_type, k.content, k.structured_data
    into v_pb_id, v_pb_title, v_pb_type, v_pb_content, v_pb_sd
    from public.ops_knowledge k
   where k.record_id = p_output->>'playbook_record_id' and k.runtime_eligible;
  if v_pb_id is null then
    return jsonb_build_object('ok', false, 'reason', 'playbook ' || (p_output->>'playbook_record_id') || ' is not a runtime-eligible ops_knowledge record');
  end if;
  if v_pb_type not in ('decision_playbook','decision_rule','standard_operating_procedure','exception_playbook') then
    return jsonb_build_object('ok', false, 'reason', 'record ' || v_pb_id || ' is a ' || v_pb_type || ', not an actionable kind');
  end if;

  -- THE FACTS, then the deliverable AS A FUNCTION OF THEM.
  v_facts := public.fn_workflow_step_facts(sr.id);
  v_bound := coalesce((v_facts->>'facts_bound')::int, 0);

  -- THE EXECUTOR. Read the registry row and decide from it, in words.
  select e.action_class, e.kind, e.target, e.active, e.risk_tier, e.advisory_safe, e.reversible,
         e.notifies_human, e.unattended_ok, e.required_authority, e.compensation_action_class
    into ex
    from public.org_action_executor e
   where e.action_class = sr.action_class and e.active
   order by e.kind limit 1;
  v_has_ex := found;
  if v_has_ex then v_target := ex.target; end if;
  if not v_has_ex then
    v_exec_status := 'none: no active executor is mapped to action_class ' || coalesce(sr.action_class, '(null)');
  else
    v_kind := ex.kind;
    v_needs_model := public.fn_executor_needs_model(ex.target);
    if v_needs_model then
      v_exec_status := 'held: ' || ex.target || ' is routed to a model task class by fn_task_class and the paid provider is held; not invoked';
    elsif coalesce(ex.required_authority, '') = 'founder' then
      v_exec_status := 'withheld: ' || ex.target || ' is reserved to the founder';
    elsif ex.notifies_human then
      v_exec_status := 'withheld: ' || ex.target || ' notifies a human (org_action_executor.notifies_human); the deterministic close never sends';
    elsif not (ex.risk_tier = 'low' and ex.advisory_safe and ex.reversible) then
      v_exec_status := format('withheld: %s is risk_tier=%s advisory_safe=%s reversible=%s; the close invokes low/advisory_safe/reversible only',
                              ex.target, ex.risk_tier, ex.advisory_safe, ex.reversible);
    elsif ex.kind not in ('rpc', 'edge') then
      v_exec_status := 'withheld: ' || ex.target || ' is a ' || ex.kind || ' executor and no invoker handles that kind';
    elsif exists (select 1 from public.action_execution x where x.workflow_step_run_id = sr.id and x.status in ('queued','running')) then
      return jsonb_build_object('ok', false, 'reason', 'executor ' || ex.target || ' is already queued or running for this step; the sweep settles it');
    elsif ex.kind = 'rpc' then
      select coalesce(p.pronargs - p.pronargdefaults, -1) into v_req_args
        from pg_proc p where p.proname = ex.target and p.pronamespace = 'public'::regnamespace
       order by p.pronargs limit 1;
      if v_req_args is null then
        v_exec_status := 'failed: public.' || ex.target || '() does not exist';
      elsif v_req_args > 0 then
        v_exec_status := 'withheld: public.' || ex.target || '() requires ' || v_req_args || ' argument(s) a workflow step cannot supply';
      else
        v_exec_id := gen_random_uuid();
        begin
          execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from public.%I() t', ex.target) into v_exec_result;
          insert into public.action_execution(id, correlation_id, workflow_step_run_id, action_class, executor, idempotency_key,
                                              risk_tier, reversible, request, response, status, attempts, started_at, finished_at)
          values (v_exec_id, coalesce(sr.correlation_id, gen_random_uuid()), sr.id, sr.action_class, ex.target,
                  'workflow_step:' || sr.id || ':det:' || to_char(now(), 'YYYYMMDDHH24MISSMS'),
                  ex.risk_tier, ex.reversible,
                  jsonb_build_object('workflow_step_run_id', sr.id, 'workflow_run_id', sr.workflow_run_id, 'step_no', sr.step_no,
                                     'actor', sr.actor, 'source', 'fn_workflow_step_deterministic_done', 'kind', 'rpc'),
                  jsonb_build_object('invoker', 'succeeded', 'at', now(), 'kind', 'rpc', 'inline', true,
                                     'result_rows', coalesce(jsonb_array_length(v_exec_result), 0),
                                     'result', case when pg_column_size(v_exec_result) > 20000 then to_jsonb(left(v_exec_result::text, 20000)) else v_exec_result end),
                  'succeeded', 1, now(), now());
          v_exec_status := 'ran: public.' || ex.target || '() inline, ' || coalesce(jsonb_array_length(v_exec_result), 0)
                           || ' row(s), action_execution ' || v_exec_id;
          v_source := 'executor:' || ex.target;
        exception when others then
          v_err := sqlstate || ' ' || left(sqlerrm, 400);
          -- the failure is a fact: record it and refuse the close, so the step is released with the reason
          insert into public.action_execution(id, correlation_id, workflow_step_run_id, action_class, executor, idempotency_key,
                                              risk_tier, reversible, request, response, status, attempts, started_at, finished_at)
          values (v_exec_id, coalesce(sr.correlation_id, gen_random_uuid()), sr.id, sr.action_class, ex.target,
                  'workflow_step:' || sr.id || ':det:' || to_char(now(), 'YYYYMMDDHH24MISSMS'),
                  ex.risk_tier, ex.reversible,
                  jsonb_build_object('workflow_step_run_id', sr.id, 'workflow_run_id', sr.workflow_run_id, 'step_no', sr.step_no,
                                     'actor', sr.actor, 'source', 'fn_workflow_step_deterministic_done', 'kind', 'rpc'),
                  jsonb_build_object('invoker', 'failed', 'at', now(), 'kind', 'rpc', 'inline', true, 'error', v_err),
                  'failed', 1, now(), now());
          return jsonb_build_object('ok', false, 'reason', 'executor public.' || ex.target || '() failed: ' || v_err,
                                    'action_execution_id', v_exec_id);
        end;
      end if;
    else -- edge, deterministic
      select x.response->>'reason' into v_refused
        from public.action_execution x
       where x.workflow_step_run_id = sr.id and x.response->>'invoker' = 'refused'
       order by x.created_at desc limit 1;
      if v_refused is not null then
        v_exec_status := 'withheld: the invoker refused ' || ex.target || ' for this step earlier (' || left(v_refused, 200) || '); not re-queued';
      elsif exists (select 1 from public.action_execution x
                     where x.workflow_step_run_id = sr.id and x.request->>'source' = 'fn_workflow_step_deterministic_done') then
        select 'withheld: an earlier re-queue of ' || ex.target || ' for this step ended ' || x.status into v_exec_status
          from public.action_execution x
         where x.workflow_step_run_id = sr.id and x.request->>'source' = 'fn_workflow_step_deterministic_done'
         order by x.created_at desc limit 1;
      else
        v_exec_id := gen_random_uuid();
        insert into public.action_execution(id, correlation_id, workflow_step_run_id, action_class, executor, idempotency_key,
                                            risk_tier, reversible, request, status, attempts)
        values (v_exec_id, coalesce(sr.correlation_id, gen_random_uuid()), sr.id, sr.action_class, ex.target,
                'workflow_step:' || sr.id || ':det:' || to_char(now(), 'YYYYMMDDHH24MISSMS'),
                ex.risk_tier, ex.reversible,
                jsonb_build_object('workflow_step_run_id', sr.id, 'workflow_run_id', sr.workflow_run_id, 'step_no', sr.step_no,
                                   'actor', sr.actor, 'input', coalesce(sr.input, '{}'::jsonb),
                                   'source', 'fn_workflow_step_deterministic_done', 'kind', 'edge'),
                'queued', 0);
        v_queued := true;
        v_exec_status := 'queued: ' || ex.target || ' as action_execution ' || v_exec_id || ' for the HTTP invoker; the step closes when the sweep settles it';
        v_source := 'executor:' || ex.target;
      end if;
    end if;
  end if;

  -- THE DELIVERABLE, rendered from the facts, with the executor line.
  v_deliv := public.fn_workflow_step_render(v_facts, v_pb_title, v_pb_type, v_pb_content, v_pb_sd);
  v_deliv := regexp_replace(v_deliv, E'\nAPPLIED RECORD: ',
               E'- executor: ' || coalesce(v_exec_status, '?') || E'\n\nAPPLIED RECORD: ');

  -- THE DISPOSITION, earned.
  -- 5 SEP 2026, from the skeptic that audited this routine: 'determined' used to mean "not routed
  -- to a model", and both rows that carried it had executed nothing (executor withheld). A label
  -- that reads as 'executed' must be EARNED by an execution: an action_execution this close created
  -- and which succeeded. Facts bound and rendered, but no executor ran (none mapped, withheld,
  -- queued for the HTTP invoker, refused) is 'rendered' -- true, and not the same word as done.
  v_disp := case when v_bound = 0 then 'needs_narrative'
                 when v_needs_model then 'advisory_held_model'
                 when v_exec_id is not null and exists (select 1 from public.action_execution x
                        where x.id = v_exec_id and x.status = 'succeeded') then 'determined'
                 else 'rendered' end;
  v_mode := case when v_disp = 'determined' then 'determined' else 'advisory' end;
  v_outcome := case when v_disp = 'needs_narrative'
                    then 'No fact was bound for this step (no metric, goal, event payload or prior conclusion); the record "'
                         || v_pb_title || '" applies as written and the step needs narrative from a reviewer or the model path.'
                    else coalesce(nullif(v_facts#>>'{derived,band}', '') || ' ' || coalesce(v_facts#>>'{metric,label}', '') || ': ', '')
                         || 'applied ' || v_pb_type || ' "' || v_pb_title || '" to ' || v_bound || ' bound fact(s)'
                         || case when v_facts#>>'{derived,cause}' is not null then '; cause ' || (v_facts#>>'{derived,cause}') else '' end
                         || '; executor ' || split_part(coalesce(v_exec_status, 'none'), ':', 1) end;

  -- used_llm IS A MEASUREMENT: the provider ledgers since the dispatcher claimed this step.
  select count(*) into v_llm  from public.llm_attempt a where a.fn = 'workflow_dispatch' and a.created_at >= sr.started_at;
  select count(*) into v_cost from public.ai_cost_log c where c.fn = 'workflow_dispatch' and c.occurred_at >= sr.started_at;
  v_used_llm := (v_llm + v_cost) > 0;

  select o.department into v_dept from public.org_agents o where o.agent_key = v_employee;

  -- The sealed record of what was decided, on what, by which rule, with what confidence.
  insert into public.decision_trace(
      correlation_id, causation_event_id, entity_type, entity_id, decision_type,
      proposed_by, decided_by, policy_keys, knowledge_refs, evidence_refs, alternatives,
      assumptions, risk, confidence, authority_result,
      decision, outcome_status, agent_key, department_id, task_class,
      knowledge_versions, source_freshness, tools_requested, tools_executed, tool_result_refs,
      uncertainty, escalation_decision, proposed_action, expected_outcome,
      model, provider, input_tokens, output_tokens, estimated_cost_aed, final_status, sealed_at)
  values (
      coalesce(sr.correlation_id, gen_random_uuid()), sr.trigger_event_id,
      'workflow_step_run', sr.id::text, 'deterministic_playbook_application',
      v_employee, 'fn_workflow_step_deterministic_done', array['deterministic_first']::text[],
      jsonb_build_array(jsonb_build_object('record_id', v_pb_id, 'title', v_pb_title, 'record_type', v_pb_type,
                                           'similarity', v_sim, 'terms_matched', v_terms)),
      jsonb_build_array(jsonb_build_object('workflow_run_id', sr.workflow_run_id, 'workflow_key', sr.workflow_key,
                                           'step_no', sr.step_no, 'step', sr.input->>'step',
                                           'facts', v_facts)),
      coalesce(p_output->'candidates', '[]'::jsonb),
      jsonb_build_array('the corroborated nearest actionable company record is the applicable one for this step',
                        'the facts read at close time are the facts the step is about'),
      jsonb_build_object('level', 'low', 'note', case when v_source like 'executor:%'
                                                      then 'a low-risk, advisory-safe, reversible executor was invoked; moves no money, sends nothing, approves nobody'
                                                      else 'determination only; moves no money, sends nothing, approves nobody' end),
      v_sim,
      jsonb_build_object('mode', v_mode, 'gate', coalesce(sr.input->>'gate', 'none'), 'paid_provider', 'held', 'executor', v_exec_status),
      jsonb_build_object('determination', left(v_deliv, 8000), 'outcome', v_outcome, 'disposition', v_disp,
                         'determination_source', v_source, 'basis', 'facts of the step rendered against the corroborated record; no model call'),
      'pending', v_employee, v_dept, 'workflow_step',
      '{}'::jsonb, jsonb_build_object('ops_knowledge', 'live at decision time', 'facts_read_at', v_facts->>'read_at'),
      case when v_target is not null then array[v_target] else '{}'::text[] end,
      case when v_source like 'executor:%' then array[v_target] else '{}'::text[] end,
      case when v_exec_id is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('action_execution_id', v_exec_id)) end,
      case v_disp when 'determined' then 'determined from ' || v_bound || ' bound fact(s); queued for review'
                  when 'advisory_held_model' then 'determined from ' || v_bound || ' bound fact(s), but the step''s executor needs the held model; advisory until the hold lifts'
                  else 'no fact bound: the record applies as written; narrative is needed' end,
      'review_queued', 'close the workflow step with disposition ' || v_disp,
      'the run advances; a reviewer can overturn the determination',
      'none', 'deterministic', 0, 0, 0, 'auto_done', now())
  returning id into v_trace;

  -- Never a silent pass: the determination is queued for review, with everything needed to overturn it.
  insert into public.review_queue(kind, dept_key, title, summary, payload, status)
  values ('deterministic_step', v_dept,
          left(initcap(replace(v_disp, '_', ' ')) || ': ' || sr.workflow_key || ' step ' || sr.step_no || ' — ' || coalesce(sr.input->>'step',''), 240),
          left(v_outcome, 600),
          jsonb_build_object('workflow_run_id', sr.workflow_run_id, 'step_run_id', sr.id, 'step_no', sr.step_no,
                             'employee', v_employee, 'playbook_record_id', v_pb_id,
                             'playbook_title', v_pb_title, 'similarity', v_sim, 'terms_matched', v_terms,
                             'decision_trace_id', v_trace, 'disposition', v_disp,
                             'determination_source', v_source, 'executor_status', v_exec_status,
                             'facts_bound', v_bound, 'used_llm', v_used_llm),
          'pending')
  returning id into v_review;

  -- The executor's parked/stranded attempt is superseded: fn_action_release_held must not re-run it at
  -- launch over a step that is already closed.
  update public.action_execution
     set status = 'cancelled', finished_at = coalesce(finished_at, now()),
         response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
           'superseded_at', now(), 'superseded_by', 'deterministic determination',
           'decision_trace_id', v_trace, 'prior_status', status)
   where workflow_step_run_id = sr.id and status in ('held','stalled');
  get diagnostics v_superseded = row_count;

  v_out := coalesce(p_output, '{}'::jsonb) || jsonb_build_object(
             'mode', v_mode,
             'deliverable', left(v_deliv, 20000),
             'outcome', left(v_outcome, 400),
             'disposition', v_disp,
             'determination_source', v_source,
             'executor_status', v_exec_status,
             'executor_kind', v_kind,
             'action_execution_id', v_exec_id,
             'facts_bound', v_bound,
             'facts', v_facts,
             'used_llm', v_used_llm,
             'used_llm_basis', 'measured at close: ' || v_llm || ' llm_attempt + ' || v_cost
                               || ' ai_cost_log row(s) by workflow_dispatch since the step was claimed at ' || sr.started_at,
             'decision_trace_id', v_trace,
             'review_queue_id', v_review,
             'review_status', 'pending',
             'superseded_executions', v_superseded);

  if v_queued then
    -- the step stays running with a queued execution; fn_workflow_step_sweep settles it when the
    -- executor answers, merging the response over this determination
    update public.workflow_step_run set output = v_out where id = sr.id;
    return jsonb_build_object('ok', true, 'advanced', 'awaiting executor ' || v_target, 'decision_trace_id', v_trace,
                              'review_queue_id', v_review, 'superseded_executions', v_superseded,
                              'disposition', v_disp, 'determination_source', v_source,
                              'executor_status', v_exec_status, 'action_execution_id', v_exec_id,
                              'facts_bound', v_bound, 'used_llm', v_used_llm);
  end if;

  v_res := public.fn_workflow_step_done(sr.workflow_run_id, sr.step_no, v_out, 'done');

  return jsonb_build_object('ok', true, 'advanced', v_res, 'decision_trace_id', v_trace,
                            'review_queue_id', v_review, 'superseded_executions', v_superseded,
                            'disposition', v_disp, 'determination_source', v_source,
                            'executor_status', v_exec_status, 'action_execution_id', v_exec_id,
                            'facts_bound', v_bound, 'used_llm', v_used_llm);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_workflow_step_done(p_run uuid, p_step_no integer, p_output jsonb DEFAULT '{}'::jsonb, p_status text DEFAULT 'done'::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_next int;
begin
  update workflow_step_run
     set status = p_status, output = coalesce(p_output,'{}'::jsonb), finished_at = now(),
         attempts = coalesce(attempts,0) + 1
   where workflow_run_id = p_run and step_no = p_step_no;
  if not found then return 'no such step'; end if;

  if p_status <> 'done' then
    update workflow_run set status = 'failed', finished_at = now(), updated_at = now(),
           error = jsonb_build_object('failed_step', p_step_no, 'status', p_status)
     where id = p_run;
    return 'failed at step ' || p_step_no;
  end if;

  select min(step_no) into v_next from workflow_step_run
   where workflow_run_id = p_run and step_no > p_step_no and status = 'queued';

  if v_next is null then
    update workflow_run set status = 'done', finished_at = now(), updated_at = now(),
           current_step = p_step_no
     where id = p_run;
    return 'run complete';
  end if;

  update workflow_step_run set status = 'ready', started_at = now()
   where workflow_run_id = p_run and step_no = v_next;
  update workflow_run set current_step = v_next, updated_at = now() where id = p_run;
  return 'advanced to step ' || v_next;
end $function$


CREATE OR REPLACE FUNCTION public.fn_workflow_step_facts(p_step_run_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  -- step + run
  v_step_no int; v_actor text; v_action_class text; v_input jsonb; v_started timestamptz; v_run uuid;
  v_wf text; v_ctx jsonb; v_trigger bigint; v_r_entity_type text; v_r_entity_id text;
  -- event
  v_ev_type text; v_ev_entity_type text; v_ev_entity_id text; v_ev_payload jsonb; v_ev_at timestamptz; v_ev_actor text;
  -- metric
  v_mk text; v_label text; v_owner text; v_val numeric; v_tgt numeric; v_dir text; v_state text; v_err text;
  v_taken timestamptz; v_definition text; v_in_scorecard boolean := false;
  v_hist jsonb; v_consec int := 0; v_ever_met boolean := false; v_n_snap int := 0; snap record; v_off boolean;
  v_metric jsonb := null; v_band text; v_gap numeric; v_att numeric; v_cause text; v_cause_why text;
  -- goals
  v_goals jsonb := null; v_failing jsonb := null; v_prior jsonb := '[]'::jsonb;
  v_bound int := 0; v_derived jsonb := '{}'::jsonb;
begin
  select s.step_no, s.actor, s.action_class, s.input, s.started_at, s.workflow_run_id,
         r.workflow_key, coalesce(r.context, '{}'::jsonb), r.trigger_event_id, r.entity_type, r.entity_id
    into v_step_no, v_actor, v_action_class, v_input, v_started, v_run,
         v_wf, v_ctx, v_trigger, v_r_entity_type, v_r_entity_id
    from public.workflow_step_run s
    join public.workflow_run r on r.id = s.workflow_run_id
   where s.id = p_step_run_id;
  if v_run is null then return null; end if;

  select e.event_type, e.entity_type, e.entity_id, e.payload, e.occurred_at, e.actor
    into v_ev_type, v_ev_entity_type, v_ev_entity_id, v_ev_payload, v_ev_at, v_ev_actor
    from public.company_event e where e.id = v_trigger;
  v_ev_payload := coalesce(v_ev_payload, '{}'::jsonb);

  -- THE METRIC THIS RUN IS ABOUT. Keyed by the event's entity (kpi.missed carries metric_key as
  -- entity_id), else by the context's metric_key, else by the label the emitter wrote.
  v_mk := case when v_ev_entity_type = 'metric' then v_ev_entity_id
               when v_ctx ? 'metric_key' then v_ctx->>'metric_key'
               when v_r_entity_type = 'metric' then v_r_entity_id
               else (select d.metric_key from public.metric_definition d
                      where d.label = coalesce(v_ctx->>'label', v_ev_payload->>'label') limit 1) end;
  -- the emitter's numbers are facts even when the metric is a fixture with no definition row
  v_label := coalesce(v_ctx->>'label', v_ev_payload->>'label');
  v_val   := coalesce(nullif(v_ev_payload->>'value','')::numeric, nullif(v_ctx->>'value','')::numeric);
  v_tgt   := coalesce(nullif(v_ev_payload->>'target','')::numeric, nullif(v_ctx->>'target','')::numeric);
  v_state := coalesce(v_ev_payload->>'state', v_ctx->>'state');
  v_dir   := coalesce(v_ev_payload->>'direction', v_ctx->>'direction');

  if v_mk is not null then
    select sc.label, sc.owner_dept, sc.value, sc.target, sc.direction, sc.state, sc.error, sc.taken_at, sc.definition, true
      into v_label, v_owner, v_val, v_tgt, v_dir, v_state, v_err, v_taken, v_definition, v_in_scorecard
      from public.v_bi_scorecard sc where sc.metric_key = v_mk;
    v_in_scorecard := coalesce(v_in_scorecard, false);
    if not v_in_scorecard then
      -- the scorecard select found nothing and nulled the targets: restore the emitter's numbers
      v_label := coalesce(v_ctx->>'label', v_ev_payload->>'label');
      v_val   := coalesce(nullif(v_ev_payload->>'value','')::numeric, nullif(v_ctx->>'value','')::numeric);
      v_tgt   := coalesce(nullif(v_ev_payload->>'target','')::numeric, nullif(v_ctx->>'target','')::numeric);
      v_state := coalesce(v_ev_payload->>'state', v_ctx->>'state');
      v_dir   := coalesce(v_ev_payload->>'direction', v_ctx->>'direction');
    end if;

    -- snapshot history, newest first, and the leading run of misses — the metric_lifecycle playbooks'
    -- TARGET_MIS_SET test reads ">= 3 consecutive measured periods, never met since the target was set"
    v_hist := '[]'::jsonb;
    for snap in
      select s.value, s.error, s.taken_at from public.metric_snapshot s
       where s.metric_key = v_mk order by s.taken_at desc limit 12
    loop
      v_n_snap := v_n_snap + 1;
      if v_n_snap <= 6 then
        v_hist := v_hist || jsonb_build_object('value', snap.value, 'error', snap.error, 'taken_at', snap.taken_at);
      end if;
      v_off := snap.error is null and snap.value is not null and v_tgt is not null
               and ((v_dir = 'up' and snap.value < v_tgt * 0.7) or (v_dir = 'down' and snap.value > v_tgt * 1.3));
      if v_off and v_consec = v_n_snap - 1 then v_consec := v_consec + 1; end if;
      if snap.error is null and snap.value is not null and v_tgt is not null
         and ((v_dir = 'up' and snap.value >= v_tgt) or (v_dir = 'down' and snap.value <= v_tgt)) then
        v_ever_met := true;
      end if;
    end loop;
  end if;

  if v_label is not null or v_val is not null or v_mk is not null then
    -- band by the scorecard's own rule when the scorecard did not already say
    v_band := coalesce(v_state,
                case when v_err is not null then 'ERROR'
                     when v_val is null or v_tgt is null then 'UNMEASURED'
                     when v_dir = 'up'   and v_val >= v_tgt then 'ON_TARGET'
                     when v_dir = 'down' and v_val <= v_tgt then 'ON_TARGET'
                     when v_dir = 'up'   and v_val >= v_tgt * 0.7 then 'BEHIND'
                     when v_dir = 'down' and v_val <= v_tgt * 1.3 then 'BEHIND'
                     when v_val is not null and v_tgt is not null then 'OFF_TARGET' end);
    v_gap := case when v_val is not null and v_tgt is not null then v_val - v_tgt end;
    v_att := case when v_val is null or v_tgt is null then null
                  when coalesce(v_dir,'up') = 'up' then
                       case when v_tgt > 0 then round(100 * v_val / v_tgt, 1)
                            when v_val <= 0 then 100 else null end
                  else case when v_val > 0 then least(100, round(100 * v_tgt / v_val, 1)) else 100 end end;
    -- cause class, by the "root cause" playbook's own definitions, from what is measurable here
    if v_band = 'ERROR' or v_err is not null then
      v_cause := 'INSTRUMENT'; v_cause_why := 'the latest snapshot carries an error: ' || coalesce(v_err, '(null)');
    elsif v_band = 'UNMEASURED' then
      v_cause := 'INSTRUMENT'; v_cause_why := 'value or target is null; the metric is UNMEASURED, not failing';
    elsif v_band in ('ON_TARGET', 'BEHIND') then
      v_cause := 'NONE'; v_cause_why := 'band ' || v_band || ': no miss to attribute';
    elsif v_consec >= 3 and not v_ever_met and coalesce(btrim(v_definition), '') = '' then
      v_cause := 'TARGET_MIS_SET';
      v_cause_why := v_consec || ' consecutive OFF_TARGET snapshots, never met in ' || v_n_snap
                     || ' recorded, and metric_definition.definition is empty (no documented basis)';
    else
      v_cause := 'EXECUTION';
      v_cause_why := 'default per the playbook: input existed and the instrument is sound. TARGET_MIS_SET test: '
                     || v_consec || ' consecutive OFF_TARGET snapshot(s) (needs >= 3), ever met = ' || v_ever_met
                     || ', documented basis = ' || (coalesce(btrim(v_definition), '') <> '')
                     || case when v_n_snap = 0 then '; no snapshot history for this key' else '' end;
    end if;
    v_metric := jsonb_strip_nulls(jsonb_build_object(
      'metric_key', v_mk, 'label', v_label, 'owner_dept', v_owner, 'in_scorecard', v_in_scorecard,
      'value', v_val, 'target', v_tgt, 'direction', v_dir, 'state', v_state, 'error', v_err,
      'taken_at', v_taken, 'snapshots_newest_first', v_hist, 'snapshots_read', v_n_snap,
      'consecutive_off_target', v_consec, 'ever_met', v_ever_met));
    v_bound := v_bound + (v_val is not null)::int + (v_tgt is not null)::int + (v_band is not null)::int
               + (v_n_snap > 0)::int;
    v_derived := jsonb_strip_nulls(jsonb_build_object(
      'band', v_band, 'gap', v_gap, 'attainment_pct', v_att, 'cause', v_cause, 'cause_evidence', v_cause_why,
      'direction', v_dir));
  end if;

  -- GOALS AT RISK and FAILING METRICS (goal.at_risk carries both as arrays of keys / labels)
  if jsonb_typeof(v_ctx->'goals_at_risk') = 'array' or jsonb_typeof(v_ev_payload->'goals_at_risk') = 'array' then
    select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
             'key', g.key, 'goal', g.goal, 'metric', g.metric, 'target_value', g.target_value, 'unit', g.unit,
             'direction', g.direction, 'owner_dept', g.owner_dept, 'horizon', g.horizon, 'deadline', g.deadline,
             'active', g.active,
             'latest_period', (select jsonb_build_object('period', p.period_label, 'actual', p.actual_value,
                                                         'target', p.target_value, 'status', p.status)
                                 from public.goal_period p where p.goal_key = g.key
                                order by p.updated_at desc limit 1))) order by g.key), '[]'::jsonb)
      into v_goals
      from public.company_goals g
     where g.key in (select jsonb_array_elements_text(coalesce(v_ctx->'goals_at_risk', v_ev_payload->'goals_at_risk')));
    -- a fixture goal with no company_goals row is still a named fact of the trigger
    select coalesce(v_goals, '[]'::jsonb) || coalesce(jsonb_agg(jsonb_build_object('key', k, 'in_company_goals', false)), '[]'::jsonb)
      into v_goals
      from jsonb_array_elements_text(coalesce(v_ctx->'goals_at_risk', v_ev_payload->'goals_at_risk')) k
     where not exists (select 1 from public.company_goals g where g.key = k);
    v_bound := v_bound + coalesce(jsonb_array_length(v_goals), 0);
  end if;
  if jsonb_typeof(v_ctx->'failing_metrics') = 'array' or jsonb_typeof(v_ev_payload->'failing_metrics') = 'array' then
    select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
             'label', lbl, 'metric_key', sc.metric_key, 'value', sc.value, 'target', sc.target,
             'direction', sc.direction, 'state', sc.state, 'error', sc.error, 'taken_at', sc.taken_at,
             'owner_dept', sc.owner_dept, 'in_scorecard', (sc.metric_key is not null))) order by lbl), '[]'::jsonb)
      into v_failing
      from jsonb_array_elements_text(coalesce(v_ctx->'failing_metrics', v_ev_payload->'failing_metrics')) lbl
      left join public.v_bi_scorecard sc on sc.label = lbl;
    v_bound := v_bound + coalesce(jsonb_array_length(v_failing), 0);
  end if;

  -- WHAT THIS RUN ALREADY CONCLUDED (outcome lines only, in order)
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'step_no', p.step_no, 'step', p.input->>'step', 'by', coalesce(p.output->>'employee', p.actor),
           'outcome', left(coalesce(p.output->>'outcome', p.output->>'note', ''), 600),
           'disposition', p.output->>'disposition', 'determination_source', p.output->>'determination_source',
           'executor_status', p.output->>'executor_status')) order by p.step_no), '[]'::jsonb)
    into v_prior
    from public.workflow_step_run p
   where p.workflow_run_id = v_run and p.step_no < v_step_no and p.status = 'done';
  v_bound := v_bound + (select count(*) from jsonb_array_elements(v_prior) x where coalesce(x->>'outcome','') <> '')::int;

  -- the trigger payload's own scalar facts, beyond the ones already read above
  v_bound := v_bound + (select count(*) from jsonb_each(v_ev_payload) e
                         where jsonb_typeof(e.value) in ('string','number','boolean')
                           and e.key not in ('label','value','target','state','direction'))::int;

  return jsonb_strip_nulls(jsonb_build_object(
    'step', jsonb_build_object('workflow_key', v_wf, 'step_no', v_step_no, 'step', v_input->>'step',
                               'gate', v_input->>'gate', 'actor', v_actor, 'action_class', v_action_class,
                               'claimed_at', v_started),
    'trigger', case when v_ev_type is null then null else
                 jsonb_build_object('event_id', v_trigger, 'event_type', v_ev_type, 'entity_type', v_ev_entity_type,
                                    'entity_id', v_ev_entity_id, 'actor', v_ev_actor, 'occurred_at', v_ev_at,
                                    'payload', v_ev_payload) end,
    'context', v_ctx,
    'metric', v_metric,
    'goals_at_risk', v_goals,
    'failing_metrics', v_failing,
    'prior_steps', v_prior,
    'derived', v_derived,
    'facts_bound', v_bound,
    'read_at', now()));
end
$function$


CREATE OR REPLACE FUNCTION public.fn_workflow_step_render(p_facts jsonb, p_title text, p_record_type text, p_content text, p_structured jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  f jsonb := coalesce(p_facts, '{}'::jsonb);
  d jsonb := coalesce(p_facts->'derived', '{}'::jsonb);
  m jsonb := p_facts->'metric';
  t text := '';
  sel text[]; k text; v jsonb; s text; x jsonb; n int := 0; lines text := '';
begin
  t := 'DETERMINATION — ' || coalesce(f#>>'{step,workflow_key}', '?') || ' step ' || coalesce(f#>>'{step,step_no}', '?')
       || ': ' || coalesce(f#>>'{step,step}', '') || E'\n'
       || 'Decided by ' || coalesce(f#>>'{step,actor}', '?') || ' at ' || coalesce(f->>'read_at', '') || ' from '
       || coalesce(f->>'facts_bound', '0') || ' bound fact(s); no model call.' || E'\n\n';

  t := t || E'FACTS THIS STEP DECIDED FROM\n';
  if f ? 'trigger' then
    t := t || '- trigger: ' || coalesce(f#>>'{trigger,event_type}', '?') || ' on ' || coalesce(f#>>'{trigger,entity_type}', '?')
         || ' ' || coalesce(f#>>'{trigger,entity_id}', '?') || ' at ' || coalesce(f#>>'{trigger,occurred_at}', '?')
         || ' (event ' || coalesce(f#>>'{trigger,event_id}', '?') || ') payload ' || coalesce((f#>'{trigger,payload}')::text, '{}') || E'\n';
  else
    t := t || E'- trigger: none recorded on this run\n';
  end if;
  if m is not null then
    t := t || '- metric: ' || coalesce(m->>'label', m->>'metric_key', '?')
         || case when (m->>'metric_key') is not null then ' [' || (m->>'metric_key') || ']' else '' end
         || ' value=' || coalesce(m->>'value', 'null') || ' target=' || coalesce(m->>'target', 'null')
         || ' direction=' || coalesce(m->>'direction', 'unknown') || ' state=' || coalesce(m->>'state', d->>'band', 'unknown')
         || case when (m->>'error') is not null then ' ERROR=' || (m->>'error') else '' end
         || case when (m->>'taken_at') is not null then ' taken_at=' || (m->>'taken_at') else '' end
         || ' owner=' || coalesce(m->>'owner_dept', 'unknown')
         || ' in_scorecard=' || coalesce(m->>'in_scorecard', 'false') || E'\n'
         || '- snapshots (newest first, ' || coalesce(m->>'snapshots_read', '0') || ' read): ' || coalesce((m->'snapshots_newest_first')::text, '[]')
         || '; consecutive_off_target=' || coalesce(m->>'consecutive_off_target', '0') || ' ever_met=' || coalesce(m->>'ever_met', 'false') || E'\n';
  end if;
  if jsonb_typeof(f->'goals_at_risk') = 'array' then
    for x in select * from jsonb_array_elements(f->'goals_at_risk') loop
      t := t || '- goal at risk: ' || coalesce(x->>'key', '?')
           || case when coalesce(x->>'in_company_goals', 'true') = 'false' then ' (no company_goals row)'
                   else ' "' || coalesce(x->>'goal', '') || '" target ' || coalesce(x->>'target_value', 'null') || ' ' || coalesce(x->>'unit', '')
                        || ' dir=' || coalesce(x->>'direction', '?') || ' owner=' || coalesce(x->>'owner_dept', '?')
                        || ' deadline=' || coalesce(x->>'deadline', 'none')
                        || case when x ? 'latest_period' then ' latest period ' || (x->'latest_period')::text else ' (no goal_period yet)' end end
           || E'\n';
    end loop;
  end if;
  if jsonb_typeof(f->'failing_metrics') = 'array' then
    for x in select * from jsonb_array_elements(f->'failing_metrics') loop
      t := t || '- failing metric: ' || coalesce(x->>'label', '?')
           || case when coalesce(x->>'in_scorecard', 'false') = 'true'
                   then ' [' || (x->>'metric_key') || '] value=' || coalesce(x->>'value', 'null') || ' target=' || coalesce(x->>'target', 'null')
                        || ' state=' || coalesce(x->>'state', '?') || ' owner=' || coalesce(x->>'owner_dept', '?')
                        || case when (x->>'error') is not null then ' ERROR=' || (x->>'error') else '' end
                   else ' (not on v_bi_scorecard: the emitter''s label only)' end
           || E'\n';
    end loop;
  end if;
  if jsonb_typeof(f->'prior_steps') = 'array' and jsonb_array_length(f->'prior_steps') > 0 then
    for x in select * from jsonb_array_elements(f->'prior_steps') loop
      t := t || '- prior step ' || coalesce(x->>'step_no', '?') || ' (' || coalesce(x->>'by', '?') || ', '
           || coalesce(x->>'disposition', 'no disposition') || '): ' || coalesce(x->>'outcome', '') || E'\n';
    end loop;
  else
    t := t || E'- prior steps: none concluded yet; this is the first step of the run to decide anything\n';
  end if;
  if f ? 'context' and (f->'context') <> '{}'::jsonb then
    t := t || '- run context: ' || (f->'context')::text || E'\n';
  end if;

  t := t || E'\nDETERMINED\n';
  if m is not null then
    t := t || '- variance: ' || coalesce(m->>'label', '?') || ' is ' || coalesce(d->>'band', 'unknown')
         || case when d ? 'gap' then ' — gap ' || (d->>'gap') || ' against target ' || coalesce(m->>'target', 'null')
                                   || ' (direction ' || coalesce(d->>'direction', 'unknown') || ')' else '' end
         || case when d ? 'attainment_pct' then ', attainment ' || (d->>'attainment_pct') || '%' else '' end || E'\n'
         || '- cause class: ' || coalesce(d->>'cause', 'not established') || ' — ' || coalesce(d->>'cause_evidence', '') || E'\n';
  end if;

  -- resolve keyed maps in structured_data at the facts
  sel := array_remove(array[d->>'band', d->>'cause', d->>'direction', f#>>'{trigger,event_type}', f#>>'{step,gate}',
                            lower(d->>'band'), lower(d->>'cause')], null);
  if p_structured is not null and jsonb_typeof(p_structured) = 'object' then
    for k, v in select * from jsonb_each(p_structured) loop
      if jsonb_typeof(v) = 'object' then
        foreach s in array coalesce(sel, '{}'::text[]) loop
          if v ? s then
            n := n + 1;
            lines := lines || '- ' || k || '[' || s || '] → ' || case when jsonb_typeof(v->s) = 'string' then v->>s else (v->s)::text end || E'\n';
          end if;
        end loop;
      end if;
    end loop;
  end if;
  if n > 0 then
    t := t || 'Selected from "' || coalesce(p_title, '?') || '" at the facts above (' || n || ' rule(s)):' || E'\n' || lines;
  else
    t := t || 'No keyed rule in "' || coalesce(p_title, '?') || '" resolves at these facts; the record applies as written below.' || E'\n';
  end if;

  t := t || E'\nAPPLIED RECORD: ' || coalesce(p_record_type, '?') || ' "' || coalesce(p_title, '?') || E'"\n'
       || coalesce(p_content, '');
  if p_structured is not null and p_structured <> '{}'::jsonb then
    t := t || E'\n\nSTRUCTURED DATA OF THE RECORD:\n' || jsonb_pretty(p_structured);
  end if;
  return t;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_workflow_step_sweep(p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s record; v_settled int := 0; v_q int := 0; v_key text; v_res text; v_out jsonb; v_parked int; v_noclass int;
        v_cap int; v_reflection_today int; v_throttled int; v_true_stall int; v_status text; v_note text;
        v_ineligible int; v_why text; v_held boolean;
begin
  v_held := coalesce((public.fn_kernel_paid_provider_gate('anthropic/claude-sonnet-5')->>'allowed')::boolean, false) = false;

  -- 1. SETTLE what the invoker has already finished. A determination stored on the step before its
  --    executor ran (fn_workflow_step_deterministic_done's queued-edge path) is kept under the response.
  for s in
    select x.status, x.response, x.executor, r.id sid, r.workflow_run_id, r.step_no, r.output prev_output
      from public.action_execution x
      join public.workflow_step_run r on r.id = x.workflow_step_run_id
     where x.workflow_step_run_id is not null
       and x.status in ('succeeded','failed')
       and r.finished_at is null
     order by r.id
     limit 50
  loop
    v_res := public.fn_workflow_step_done(
      s.workflow_run_id, s.step_no,
      coalesce(s.prev_output, '{}'::jsonb)
        || coalesce(s.response, '{}'::jsonb)
        || jsonb_build_object('worked_by', 'executor:' || coalesce(s.executor, '?'),
                              'executor_status', case when s.status = 'succeeded' then 'ran: ' else 'failed: ' end || coalesce(s.executor, '?'))
        || case when v_held then jsonb_build_object('used_llm', false, 'used_llm_basis', 'paid provider held (kernel K12) at settle time') else '{}'::jsonb end,
      case when s.status = 'succeeded' then 'done' else 'failed' end);
    v_settled := v_settled + 1;
  end loop;

  -- 1b. RE-QUEUE the executions the old fn_execution_sweep cancelled before the invoker ever ran them
  --     (observed=cancelled, never dispatched, no decision record, not superseded). A deterministic
  --     executor such as uptime_check or ai_health is simply run, late; a model-backed one stays for the
  --     dispatcher while the model is held. The idempotency key is the same row, so this is an UPDATE.
  for s in
    select x.id xid, r.id sid
      from public.action_execution x
      join public.workflow_step_run r on r.id = x.workflow_step_run_id
      join public.org_action_executor e on e.action_class = r.action_class and e.active
     where x.status = 'cancelled'
       and r.status = 'ready' and r.finished_at is null
       and x.response->>'invoker' is null
       and x.response->>'observed' = 'cancelled'
       and not (x.request ? 'decision_record_id')
       and not (x.response ? 'superseded_by')
       and e.kind in ('edge','rpc') and e.risk_tier = 'low' and e.advisory_safe and e.reversible
       and not e.notifies_human and coalesce(e.required_authority,'') <> 'founder'
       and not (v_held and public.fn_executor_needs_model(e.target))
     order by r.id
     limit greatest(coalesce(p_limit, 5), 1)
  loop
    update public.action_execution
       set status = 'queued', finished_at = null,
           response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
             'requeued_at', now(),
             'requeue_reason', 'cancelled by fn_execution_sweep before the invoker ran it (no decision record was ever expected); re-queued 4 Sep 2026')
     where id = s.xid;
    update public.workflow_step_run set status = 'running' where id = s.sid and status = 'ready';
    v_q := v_q + 1;
  end loop;

  -- 2. QUEUE the ready steps a registered, low-risk, reversible edge executor can run WITHOUT
  --    delivering a message to a person — and, while the model is held, without needing the model.
  for s in
    select r.id, r.workflow_run_id, r.step_no, r.actor, r.action_class, r.input,
           e.target, e.risk_tier, e.reversible
      from public.workflow_step_run r
      join public.org_action_executor e on e.action_class = r.action_class
     where r.status = 'ready' and r.finished_at is null
       and e.kind in ('edge','rpc') and e.active
       and e.risk_tier = 'low' and e.advisory_safe and e.reversible
       and not e.notifies_human
       and coalesce(e.required_authority,'') <> 'founder'
       and not (v_held and public.fn_executor_needs_model(e.target))
       and not exists (select 1 from public.action_execution x
                        where x.idempotency_key = 'workflow_step:' || r.id)
     order by r.id
     limit greatest(coalesce(p_limit, 5), 1)
  loop
    v_key := 'workflow_step:' || s.id;
    insert into public.action_execution(id, correlation_id, action_class, executor, idempotency_key,
                                        risk_tier, reversible, request, status, attempts,
                                        workflow_step_run_id)
    values (gen_random_uuid(), gen_random_uuid(), s.action_class, s.target, v_key,
            s.risk_tier, s.reversible,
            jsonb_build_object('workflow_step_run_id', s.id,
                               'workflow_run_id', s.workflow_run_id,
                               'step_no', s.step_no,
                               'actor', s.actor,
                               'input', coalesce(s.input, '{}'::jsonb),
                               'source', 'fn_workflow_step_sweep'),
            'queued', 0, s.id)
    on conflict (idempotency_key) do nothing;

    update public.workflow_step_run set status = 'running' where id = s.id and status = 'ready';
    v_q := v_q + 1;
  end loop;

  select count(*), count(*) filter (where action_class is null)
    into v_parked, v_noclass
    from public.workflow_step_run where status = 'ready' and finished_at is null;

  select coalesce((value #>> '{}')::int, 6) into v_cap
    from public.decision_policy where key = 'workflow_reflection_steps_per_day';
  v_cap := coalesce(v_cap, 6);

  select count(*) into v_reflection_today
    from public.action_execution x
   where x.workflow_step_run_id is not null
     and x.created_at >= date_trunc('day', now() at time zone 'utc') at time zone 'utc'
     and not public.fn_task_is_demand(x.action_class);

  select count(*) into v_throttled
    from public.workflow_step_run sr
    join public.workflow_run r on r.id = sr.workflow_run_id
   where sr.status = 'ready' and sr.finished_at is null
     and sr.action_class is not null
     and r.status = 'running'
     and r.workflow_key <> 'employee_task'
     and coalesce(sr.input->>'gate','') <> 'founder'
     and not public.fn_task_is_demand(sr.action_class)
     and v_reflection_today >= v_cap;

  select count(*), string_agg(distinct why, '; ') into v_ineligible, v_why from (
    select sr.id,
           case when e.action_class is null then 'no executor is mapped to ' || sr.action_class
                when e.kind not in ('edge','rpc') then sr.action_class || ' is a ' || e.kind || ' executor and no invoker handles that kind'
                when not e.active then sr.action_class || ' executor is inactive'
                when e.risk_tier <> 'low' then sr.action_class || ' is risk_tier ' || e.risk_tier
                when not e.advisory_safe then sr.action_class || ' is not advisory_safe'
                when not e.reversible then sr.action_class || ' is not reversible'
                when e.notifies_human then sr.action_class || ' notifies a human'
                when v_held and public.fn_executor_needs_model(e.target) then
                     sr.action_class || ' runs on the paid model, which is held; the dispatcher works it deterministically'
                when exists(select 1 from public.action_execution x where x.workflow_step_run_id = sr.id)
                     and not exists(select 1 from public.action_execution x
                                     where x.workflow_step_run_id = sr.id
                                       and x.status in ('queued','running','succeeded')) then
                     sr.action_class || ' has only a terminal (cancelled/failed/held) action_execution; while the model is held the dispatcher works it deterministically'
           end as why
      from public.workflow_step_run sr
      left join public.org_action_executor e on e.action_class = sr.action_class
     where sr.status = 'ready' and sr.finished_at is null and sr.action_class is not null
  ) q where why is not null;
  v_ineligible := coalesce(v_ineligible, 0);
  v_true_stall := greatest(v_parked - v_noclass - v_throttled - v_ineligible, 0);

  v_out := jsonb_build_object(
    'settled', v_settled, 'queued', v_q, 'ran_at', now(), 'model_held', v_held,
    'parked', v_parked, 'parked_without_action_class', v_noclass,
    'parked_throttled_by_reflection_ceiling', v_throttled,
    'reflection_worked_today', v_reflection_today, 'reflection_cap', v_cap,
    'parked_ineligible_by_policy', v_ineligible,
    'parked_ineligible_because', coalesce(v_why, ''),
    'parked_unexplained', v_true_stall,
    'ready_runnable', (select count(*) from public.workflow_step_run r
                         join public.org_action_executor e on e.action_class = r.action_class
                        where r.status = 'ready' and e.kind in ('edge','rpc') and e.active
                          and e.risk_tier='low' and e.advisory_safe and e.reversible
                          and not e.notifies_human),
    'ready_held_notifies_human', (select count(*) from public.workflow_step_run r
                                    join public.org_action_executor e on e.action_class = r.action_class
                                   where r.status = 'ready' and e.notifies_human),
    'never_finished', (select count(*) from public.workflow_step_run where finished_at is null));

  v_status := case when v_true_stall > 0 and v_q = 0 and v_settled = 0 then 'error' else 'ok' end;
  v_note := 'settled ' || v_settled || ', queued ' || v_q || ', parked ' || v_parked
         || ' (' || v_noclass || ' awaiting an action_class, ' || v_throttled
         || ' held by the reflection ceiling at ' || v_reflection_today || '/' || v_cap || ' today, '
         || v_ineligible || ' ineligible by policy'
         || case when v_why is null or v_why = '' then '' else ' (' || left(v_why, 300) || ')' end
         || ', ' || v_true_stall || ' unexplained)';
  if v_status = 'error' then
    v_note := 'STALLED: ' || v_true_stall || ' workflow step(s) are ready, carry an action_class, '
           || 'and are not explained by the reflection ceiling. ' || v_note;
  end if;

  insert into public.agent_runs(agent, status, counts, note, started_at, finished_at)
  values ('workflow_step_sweep', v_status, v_out, v_note, now(), now());

  if v_noclass > 0 then
    begin
      insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
      select 'exec', 'Classify the workflow steps no executor can run',
             v_noclass || ' workflow_step_run row(s) are ready with no action_class, so nothing can '
             || 'ever pick them up and their runs never complete. The gap is in the DEFINITIONS: '
             || 'employee_task, rfq_handling, payment, refund, complaint, supplier_onboarding, '
             || 'customer_registration, invoice_approval, campaign_publishing and '
             || 'supplier_suspension carry no action_class on any step. Classifying them will make '
             || 'the queued backlog FIRE, so check org_action_executor.notifies_human, risk_tier '
             || 'and reversible per class first - refund reaches Stripe and needs the founder.',
             'proposed', 'gated', false, 'incident_fix'
      where not exists (select 1 from public.org_tasks
                         where title = 'Classify the workflow steps no executor can run'
                           and status <> 'done');
    exception when others then null; end;
  end if;

  -- Stranded steps are the dispatcher's while the model is held (fn_workflow_step_claim). The dedup
  -- backlog task is raised only when the hold is NOT in force, i.e. when nothing else will take them.
  if not v_held and (select count(*) from public.workflow_step_run sr
               where sr.status='ready' and sr.finished_at is null and sr.action_class is not null
                 and exists(select 1 from public.action_execution x where x.workflow_step_run_id=sr.id)
                 and not exists(select 1 from public.action_execution x
                                 where x.workflow_step_run_id=sr.id and x.status in ('queued','running','succeeded'))) > 0 then
    begin
      insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
      select 'exec', 'Re-open workflow steps stranded by a cancelled action',
             (select count(*) from public.workflow_step_run sr
               where sr.status='ready' and sr.finished_at is null and sr.action_class is not null
                 and exists(select 1 from public.action_execution x where x.workflow_step_run_id=sr.id)
                 and not exists(select 1 from public.action_execution x
                                 where x.workflow_step_run_id=sr.id and x.status in ('queued','running','succeeded')))
             || ' workflow step(s) are ready but each has only a terminal (cancelled/failed) '
             || 'action_execution, so the sweep will not re-queue over it. Re-open them for a fresh '
             || 'attempt or drive the review-decision loop they await; a cancelled action must also settle its step.',
             'proposed', 'gated', false, 'incident_fix'
      where not exists (select 1 from public.org_tasks
                         where title = 'Re-open workflow steps stranded by a cancelled action'
                           and status <> 'done');
    exception when others then null; end;
  end if;

  return v_out;
end $function$


CREATE OR REPLACE FUNCTION public.fn_working_days_between(p_from timestamp with time zone, p_to timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d date; n int := 0; last date;
begin
  if p_from is null or p_to is null or p_to <= p_from then return 0; end if;
  d := (p_from at time zone 'Asia/Dubai')::date + 1;
  last := (p_to at time zone 'Asia/Dubai')::date;
  while d <= last loop
    if public.fn_is_working_day(d) then n := n + 1; end if;
    d := d + 1;
  end loop;
  return n;
end $function$


CREATE OR REPLACE FUNCTION public.fn_write_decision_trace(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id       uuid;
  v_agent    text := nullif(p->>'agent_key','');
  v_role     text;
  v_dept     text;
  v_mgr      text;
  v_dobj     text;
  v_corr     uuid := coalesce(nullif(p->>'correlation_id','')::uuid, gen_random_uuid());
begin
  if v_agent is null then
    raise exception 'fn_write_decision_trace: agent_key is required. A trace that cannot name who decided is not evidence.';
  end if;

  -- Identity is resolved SERVER-SIDE from the roster. A model cannot label its own trace with
  -- someone else's role, which is the whole point of separating role_id from agent_key.
  select a.department, a.manager_key, d.north_star
    into v_dept, v_mgr, v_dobj
    from org_agents a left join org_departments d on d.dept_key = a.department
   where a.agent_key = v_agent;

  v_role := coalesce(nullif(p->>'role_id',''),
                     (select i.packaged_role_id from org_role_identity i
                       where i.agent_key = v_agent order by i.packaged_role_id limit 1));

  insert into decision_trace (
    correlation_id, entity_type, entity_id, decision_type, proposed_by, decided_by,
    policy_keys, knowledge_refs, evidence_refs, alternatives, assumptions, risk,
    confidence, authority_result, decision, outcome_status,
    task_id, agent_key, role_id, department_id, manager_id, task_class,
    company_objective, department_objective, relevant_kpi,
    knowledge_versions, source_freshness, tools_requested, tools_executed, tool_result_refs,
    uncertainty, escalation_decision, proposed_action, expected_outcome, review_date,
    model, provider, input_tokens, output_tokens, estimated_cost_aed, final_status
  ) values (
    v_corr,
    coalesce(nullif(p->>'entity_type',''),'agent_task'),
    nullif(p->>'entity_id',''),
    coalesce(nullif(p->>'decision_type',''),'agent_decision'),
    v_agent,
    coalesce(nullif(p->>'decided_by',''), v_agent),
    coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p->'policy_keys','[]'::jsonb)) x), '{}'),
    coalesce(p->'knowledge_refs','[]'::jsonb),
    coalesce(p->'evidence_refs','[]'::jsonb),
    coalesce(p->'alternatives','[]'::jsonb),
    coalesce(p->'assumptions','[]'::jsonb),
    coalesce(p->'risk','{}'::jsonb),
    nullif(p->>'confidence','')::numeric,
    coalesce(p->'authority_result','{}'::jsonb),
    coalesce(p->'decision','{}'::jsonb),
    coalesce(nullif(p->>'outcome_status',''),'pending'),
    nullif(p->>'task_id',''), v_agent, v_role, v_dept, v_mgr, nullif(p->>'task_class',''),
    -- The canonical company objective, read from the row that owns it rather than restated here:
    -- company_goals.revenue_annual = "Reach AED 1,000,000 annual revenue", target 1000000 AED.
    coalesce(nullif(p->>'company_objective',''),
             (select g.goal || ' (' || g.target_value::text || ' ' || coalesce(g.unit,'') || ')'
                from company_goals g where g.key = 'revenue_annual' and g.active limit 1)),
    coalesce(nullif(p->>'department_objective',''), v_dobj),
    nullif(p->>'relevant_kpi',''),
    coalesce(p->'knowledge_versions','{}'::jsonb),
    coalesce(p->'source_freshness','{}'::jsonb),
    coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p->'tools_requested','[]'::jsonb)) x), '{}'),
    coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p->'tools_executed','[]'::jsonb)) x), '{}'),
    coalesce(p->'tool_result_refs','[]'::jsonb),
    nullif(p->>'uncertainty',''), nullif(p->>'escalation_decision',''),
    nullif(p->>'proposed_action',''), nullif(p->>'expected_outcome',''),
    nullif(p->>'review_date','')::date,
    nullif(p->>'model',''), nullif(p->>'provider',''),
    nullif(p->>'input_tokens','')::integer, nullif(p->>'output_tokens','')::integer,
    nullif(p->>'estimated_cost_aed','')::numeric, nullif(p->>'final_status','')
  ) returning id into v_id;

  return v_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_writers_without_a_seat(p_days integer DEFAULT 7)
 RETURNS TABLE(kind text, name text, runs bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select 'agent_runs_label', l.agent, count(*)
    from public.agent_runs l
   where l.started_at > now() - make_interval(days => greatest(coalesce(p_days, 7), 1))
     and not exists (select 1 from public.function_owner f where f.function_slug = regexp_replace(l.agent, '^fn:', ''))
     and not exists (select 1 from public.seat_duty d where l.agent in (d.duty, d.routine))
     and not exists (select 1 from public.writer_seat o join public.org_role r on r.role_id = o.owner_seat and r.status = 'active'
                      where o.kind = 'agent_runs_label' and o.name = l.agent)
   group by l.agent
  union all
  select 'cron_job', j.jobname, null::bigint
    from cron.job j
   where not exists (select 1 from public.writer_seat o join public.org_role r on r.role_id = o.owner_seat and r.status = 'active'
                      where o.kind = 'cron_job' and o.name = j.jobname)
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_agent_ops(p_agent text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare ca public.category_agents%rowtype; pr public.prompts%rowtype;
  runs_total int; runs_24h int; runs_7d int; ok_runs int; last_run timestamptz; last_status text;
  avg_ms numeric; kn_updated timestamptz; kn_count int; mem_count int; health text;
  v_dept text; v_cap int; v_open int; v_queue int; v_goal jsonb; v_rep public.agent_reputation%rowtype;
begin
  select * into ca from public.category_agents where slug=p_agent;
  select * into pr from public.prompts where key=p_agent;

  -- RESOLVE HERE, NOT AT THE TOP. PLACEMENT IS LOAD-BEARING (15 Aug 2026).
  --
  -- Everything below this line reads org_agents, agent_runs, agent_knowledge, agent_memory,
  -- agent_actions, decision_log, employee_kpi_history, knowledge_exam_results and skills_matrix by
  -- agent_key, and every one of those missed for an employee addressed by an alias - so the whole
  -- workspace drawer came back empty for them: no runs, no knowledge, no KPIs, no learning curve.
  --
  -- But the TWO lookups above are keyed differently. category_agents.slug and prompts.key are
  -- alias-shaped: 14 alias values are also category_agents slugs, and none of the 132 slugs equals
  -- any org_agents.agent_key. Resolving before them would blank the name, emoji and persona for
  -- exactly the employees this repairs - trading an empty drawer for an anonymous one.
  p_agent := coalesce(public.fn_org_agent_resolve(p_agent), p_agent);
  select count(*), count(*) filter (where started_at>now()-interval '24 hours'),
         count(*) filter (where started_at>now()-interval '7 days'),
         count(*) filter (where status='ok'),
         max(started_at),
         coalesce(round(avg(extract(epoch from (finished_at-started_at))*1000) filter (where finished_at is not null),0),0)
    into runs_total, runs_24h, runs_7d, ok_runs, last_run, avg_ms
    from public.agent_runs where agent=p_agent;
  select status into last_status from public.agent_runs where agent=p_agent order by started_at desc limit 1;
  select count(*), max(updated_at) into kn_count, kn_updated from public.agent_knowledge where agent_key=p_agent;
  select count(*) into mem_count from public.agent_memory where agent_key=p_agent;
  health := case
    when last_status is null then 'idle'
    when last_status in ('error','failed') then 'degraded'
    when last_run < now()-interval '3 days' then 'stale'
    else 'healthy' end;

  select a.department, a.max_open_tasks into v_dept, v_cap
    from public.org_agents a where a.agent_key = p_agent;
  select * into v_rep from public.agent_reputation where agent_key = p_agent;

  -- The employee's own open items, and the open work sitting in their department.
  select count(*) into v_queue from public.agent_actions
   where agent = p_agent and status in ('pending','held_for_review','proposed','open');
  select count(*) into v_open from public.org_tasks
   where dept_key = v_dept and coalesce(status,'') <> 'done';

  -- CURRENT GOAL, resolved down the chain until something real answers.
  select case
    when o.objective is not null then jsonb_build_object(
      'objective', o.objective, 'horizon', o.horizon, 'status', o.status,
      'goal_source', 'department_objective', 'dept', v_dept)
    when cg.goal is not null then jsonb_build_object(
      'objective', cg.goal, 'horizon', cg.horizon, 'metric', cg.metric,
      'target_value', cg.target_value, 'unit', cg.unit,
      'goal_source', 'company_goals', 'dept', v_dept)
    when d.north_star is not null then jsonb_build_object(
      'objective', d.north_star, 'horizon', 'standing',
      'goal_source', 'department_north_star', 'dept', v_dept)
    else jsonb_build_object('objective', null, 'goal_source', 'none', 'dept', v_dept)
  end into v_goal
  from (select 1) _
  left join lateral (select * from public.department_objective x
                      where x.dept_key = v_dept and x.active
                      order by x.sort nulls last, x.updated_at desc limit 1) o on true
  left join lateral (select * from public.company_goals c
                      where c.owner_dept = v_dept and c.active
                      order by c.sort nulls last limit 1) cg on true
  left join public.org_departments d on d.dept_key = v_dept;

  return jsonb_build_object(
    'identity', jsonb_build_object('key',p_agent,'name',coalesce(ca.name,pr.description,p_agent),
       'emoji',ca.emoji,'active',coalesce(ca.active,true),'persona',ca.persona,
       'department', v_dept,
       'prompt_version',pr.active_version,'prompt_desc',pr.description,'prompt_owner',pr.owner,'prompt_updated',pr.updated_at,
       'knowledge_updated',kn_updated),
    'health', jsonb_build_object('status',health,'last_run',last_run,'last_status',last_status),
    'performance', jsonb_build_object('runs_total',runs_total,'runs_24h',runs_24h,'runs_7d',runs_7d,
       'ok_rate', case when runs_total>0 then round(100.0*ok_runs/runs_total,1) else null end,
       'avg_duration_ms',avg_ms),

    -- PERFORMANCE AS A TREND, NOT A POINT (11 Aug 2026). Every number above is a single current
    -- value, so the drawer could show how this employee is doing and never whether it is getting
    -- better or worse. employee_kpi_history writes one row per KPI per UTC day with a unique index
    -- that makes a fabricated trend impossible; this is its first reader. Attainment is averaged
    -- across the employee's KPIs for the day, so the series is "how this person performed", not
    -- one arbitrary KPI of theirs. Oldest-first because that is the order a line is drawn in.
    'kpi_trend', (select coalesce(jsonb_agg(jsonb_build_object(
                        'label', to_char(t.measured_on, 'DD Mon'),
                        'v', t.attainment,
                        'kpis', t.n) order by t.measured_on), '[]'::jsonb)
                    from (select h.measured_on,
                                 round(avg(h.attainment)::numeric, 1) attainment,
                                 count(*) n
                            from public.employee_kpi_history h
                           where h.agent_key = p_agent
                             and h.measured_on > (now() at time zone 'utc')::date - 90
                           group by h.measured_on
                           order by h.measured_on desc
                           limit 30) t),

    -- ── THE SIX THAT WERE COMPUTED AND NEVER DELIVERED ─────────────────────────────────────────
    'goal', v_goal,

    'tasks', jsonb_build_object(
      'mine_open', v_queue,
      'department', v_dept,
      'department_open', v_open,
      'rows', coalesce((select jsonb_agg(jsonb_build_object(
                 'id',t.id,'title',t.title,'status',t.status,'tier',t.tier,
                 'needs_founder',t.needs_founder,'created_at',t.created_at,'last_run_at',t.last_run_at)
               order by (coalesce(t.status,'')='done'), t.created_at desc)
             from (select * from public.org_tasks where dept_key = v_dept
                    and coalesce(status,'') <> 'done' order by created_at desc limit 12) t), '[]'::jsonb)),

    'decisions', coalesce((select jsonb_agg(jsonb_build_object(
                 'id',l.id,'kind',l.kind,'decision',l.decision,'confidence',l.confidence,
                 'route_to',l.route_to,'reasons',l.reasons,'sources',l.sources,'at',l.created_at)
               order by l.created_at desc)
             from (select * from public.decision_log where actor = p_agent
                    order by created_at desc limit 10) l), '[]'::jsonb),

    'confidence', jsonb_build_object(
      'reputation_score', v_rep.score, 'tier', v_rep.tier,
      'correctness', v_rep.correctness, 'reliability', v_rep.reliability,
      'learning_speed', v_rep.learning_speed, 'computed_at', v_rep.computed_at,
      'avg_decided', (select round(avg(confidence)::numeric, 2) from public.decision_log
                       where actor = p_agent and confidence is not null),
      'decided_with_confidence', (select count(*) from public.decision_log
                                   where actor = p_agent and confidence is not null)),

    'workload', jsonb_build_object(
      'open_tasks', v_open, 'queue_depth', v_queue, 'capacity', v_cap,
      'workload_pct', case when coalesce(v_cap,0) > 0
                           then round(100.0 * (v_open + v_queue) / v_cap, 1) else null end,
      'state', case when coalesce(v_cap,0) = 0 then 'unset'
                    when (v_open + v_queue) > v_cap then 'over'
                    when (v_open + v_queue) > v_cap * 0.8 then 'tight' else 'ok' end),

    'plans', coalesce((select jsonb_agg(jsonb_build_object(
                 'objective',p.objective,'horizon',p.horizon,'status',p.status,'scope','department')
               order by p.sort nulls last)
             from public.department_objective p where p.dept_key = v_dept and p.active), '[]'::jsonb)
      || coalesce((select jsonb_agg(jsonb_build_object(
                 'objective',o.objective,'horizon',o.horizon,'measure',o.measure,'scope','operating_system')
               order by o.id)
             from public.os_objective o
             where o.active and o.os_key = (select r.os_key from public.os_responsibility r
                                             where r.responsibility = v_dept limit 1)), '[]'::jsonb),

    -- WHAT THIS EMPLOYEE IS SUPPOSED TO KNOW (13 Aug 2026). employee_knowledge holds 900 rows over
    -- 66 employees - the domains each one is expected to cover and at what depth - and had NO
    -- browser-reachable reader at all. The `knowledge` block below is a different table:
    -- agent_knowledge is what has been WRITTEN for them, this is the curriculum they are measured
    -- against. Showing only the first without the second means a drawer can look full while the
    -- employee covers one of twelve domains they are meant to hold.
    'curriculum', jsonb_build_object(
       'domains', (select count(*) from public.employee_knowledge ek where ek.agent_key = p_agent),
       'rows', coalesce((select jsonb_agg(jsonb_build_object('domain',ek.domain_key,'depth',ek.depth,'layer',ek.layer_no)
                                order by ek.layer_no nulls last, ek.domain_key)
                           from public.employee_knowledge ek where ek.agent_key = p_agent),'[]'::jsonb),
       'by_depth', coalesce((select jsonb_object_agg(d.depth, d.n)
                               from (select coalesce(ek.depth,'unspecified') depth, count(*) n
                                       from public.employee_knowledge ek where ek.agent_key = p_agent
                                      group by 1) d),'{}'::jsonb)),
    'knowledge', jsonb_build_object('count',kn_count,'updated',kn_updated,

       'topics', coalesce((select jsonb_agg(distinct topic) from public.agent_knowledge where agent_key=p_agent and topic is not null),'[]'::jsonb),
       'recent', coalesce((select jsonb_agg(jsonb_build_object('topic',topic,'priority',priority,'updated',updated_at) order by updated_at desc)
                    from (select * from public.agent_knowledge where agent_key=p_agent order by updated_at desc limit 6) x),'[]'::jsonb)),
    'memory', jsonb_build_object('count',mem_count,
       'recent', coalesce((select jsonb_agg(jsonb_build_object('kind',kind,'content',left(content,140),'importance',importance,'at',created_at) order by created_at desc)
                    from (select * from public.agent_memory where agent_key=p_agent order by created_at desc limit 6) x),'[]'::jsonb)),
    'queue', coalesce((select jsonb_agg(jsonb_build_object('id',id,'kind',kind,'title',title,'risk',risk,'status',status,'recommendation',recommendation,'created_at',created_at,
                   -- NOT HIS unless the kind's policy is 'founder' (a refund). The holder is the role that decides it.
                   'holder', public.fn_action_holder(x.kind, x.agent),
                   'yours', exists (select 1 from public.agent_action_kind_policy kp where kp.kind = x.kind and kp.policy = 'founder')) order by created_at desc)
                 from (select * from public.agent_actions where agent=p_agent and status in ('pending','held_for_review','proposed','open') order by created_at desc limit 12) x),'[]'::jsonb),
    'conversations', coalesce((select jsonb_agg(jsonb_build_object('role',role,'content',left(content,160),'at',created_at) order by created_at desc)
                 from (select * from public.agent_chats where agent_key=p_agent order by created_at desc limit 8) x),'[]'::jsonb),
    -- LEARNING PROGRESS. The employee workspace showed goal, tasks, decisions, confidence,
    -- workload, plans, knowledge, health, performance, queue, runs, memory, conversations and
    -- recommendations - everything except whether this employee is getting BETTER. The founder's
    -- operating model asks each employee to "learn from performance, failures, outcomes and new
    -- information" and to "improve its decisions and methods over time", and the drawer had no key
    -- for it, so knowledge_exam_results (576 rows over 98 employees) and skills_matrix (695 rows)
    -- were written and never read by any browser-reachable surface.
    --
    -- exam_trend is one point PER DAY, oldest first, because a curve is the only form in which
    -- "improving" is visible. A single aggregate score cannot say whether it went up.
    'learning', jsonb_build_object(
      'exam_results_total', (select count(*) from public.knowledge_exam_results where agent_key = p_agent),
      'exam_days',          (select count(distinct created_at::date) from public.knowledge_exam_results where agent_key = p_agent),
      'exam_score_pct',     (select round(100.0 * count(*) filter (where verdict = 'correct') / nullif(count(*),0), 1)
                               from public.knowledge_exam_results where agent_key = p_agent),
      'last_exam_at',       (select max(created_at) from public.knowledge_exam_results where agent_key = p_agent),
      'exam_trend', coalesce((select jsonb_agg(jsonb_build_object('day', d, 'asked', n, 'score_pct', pct) order by d)
                     from (select created_at::date d, count(*) n,
                                  round(100.0 * count(*) filter (where verdict = 'correct') / nullif(count(*),0), 1) pct
                             from public.knowledge_exam_results where agent_key = p_agent
                            group by 1 order by 1 desc limit 14) t), '[]'::jsonb),
      'knowledge_gaps_found', (select count(*) from public.knowledge_exam_results
                                where agent_key = p_agent and gap_fact is not null),
      'knowledge_gaps_filled', (select count(*) from public.knowledge_exam_results
                                 where agent_key = p_agent and filled),
      'skills', coalesce((select jsonb_agg(jsonb_build_object('skill', skill, 'rating', rating) order by skill)
                 from public.skills_matrix where agent_key = p_agent), '[]'::jsonb)),
    'recommendations', coalesce((select jsonb_agg(jsonb_build_object('title',title,'recommendation',left(recommendation,180),'risk',risk,'at',created_at) order by created_at desc)
                 from (select * from public.agent_actions where agent=p_agent and recommendation is not null order by created_at desc limit 6) x),'[]'::jsonb),
    'audit', coalesce((select jsonb_agg(jsonb_build_object('title',title,'kind',kind,'status',status,'decided_by',decided_by,'decided_at',decided_at,'at',created_at) order by created_at desc)
                 from (select * from public.agent_actions where agent=p_agent order by created_at desc limit 12) x),'[]'::jsonb),
    'recent_runs', coalesce((select jsonb_agg(jsonb_build_object('id',id,'status',status,'note',note,'started_at',started_at,'finished_at',finished_at) order by started_at desc)
                 from (select * from public.agent_runs where agent=p_agent order by started_at desc limit 8) x),'[]'::jsonb)
  );
end $function$


CREATE OR REPLACE FUNCTION public.fn_ws_agents()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare v_out jsonb;
begin
  create temp table if not exists _minds (k text primary key) on commit drop;
  insert into _minds
    select agent_key from public.org_agents where active
    union select 'cat:'||slug from public.category_agents where active
    union select slug from public.category_agents where active
    union select distinct agent_key from public.agent_knowledge where agent_key <> '_global'
  on conflict do nothing;

  with keys as (
    select distinct k from (
      select agent k from public.agent_runs where agent is not null and agent <> ''
      union select agent from public.agent_actions where agent is not null
      union select key from public.prompts where key is not null
      union select slug from public.category_agents where slug is not null
      union select agent_key from public.org_agents where active
    ) u
  ),
  -- ONE PASS PER SOURCE. Previously each of these was a subquery re-evaluated for all 356 keys.
  runs as (
    select agent k, count(*) runs_total,
           count(*) filter (where started_at > now() - interval '24 hours') runs_24h,
           max(started_at) last_run
      from public.agent_runs where agent is not null and agent <> '' group by agent
  ),
  -- The newest run's status, taken with a window rather than a per-key ORDER BY ... LIMIT 1.
  last_status as (
    select k, status from (
      select agent k, status, row_number() over (partition by agent order by started_at desc) rn
        from public.agent_runs where agent is not null and agent <> ''
    ) z where rn = 1
  ),
  acts as (
    select agent k, count(*) filter (where status in ('pending','held_for_review','proposed','open')) actions_pending
      from public.agent_actions where agent is not null group by agent
  ),
  mem as (select agent_key k, count(*) n from public.agent_memory group by agent_key),
  kn  as (select agent_key k, count(*) n from public.agent_knowledge group by agent_key)
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      -- THE WORKFORCE, and nothing else. Was a distinct count over a union of org_agents,
      -- category brains under two spellings, and every agent_key that ever had a knowledge row.
      'agents', (select count(*) from public.org_agents where active),
      -- The category brains still counted, under their own name, because they are real and useful
      -- - they are simply not employees.
      'category_brains', (select count(*) from public.category_agents where active),
      'automations', (select count(distinct ar.agent) from public.agent_runs ar
                      where ar.agent is not null and ar.agent <> ''
                        and not exists (select 1 from _minds m where m.k=ar.agent)),
      'runs_24h', (select count(*) from public.agent_runs where started_at > now()-interval '24 hours'),
      'actions_total', (select count(*) from public.agent_actions),
      'actions_pending', (select count(*) from public.agent_actions where status in ('pending','held_for_review','proposed','open')),
      'memory_items', (select count(*) from public.agent_memory),
      'knowledge_items', (select count(*) from public.agent_knowledge)
    ),
    'rows', coalesce((
      select jsonb_agg(r order by (r->>'runs_total')::int desc nulls last, r->>'name')
      from (
        select jsonb_build_object(
          'key', k.k,
          'name', coalesce(ca.name, pr.description, k.k),
          'emoji', ca.emoji,
          'kind', case when exists (select 1 from _minds m where m.k=k.k) then 'agent' else 'automation' end,
          'active', coalesce(ca.active, true),
          'prompt_version', pr.active_version,
          'runs_total', coalesce(ru.runs_total, 0),
          'runs_24h', coalesce(ru.runs_24h, 0),
          'last_run', ru.last_run,
          'last_status', ls.status,
          'actions_pending', coalesce(ac.actions_pending, 0),
          'memory', coalesce(me.n, 0),
          -- Both the bare key and its 'cat:' twin, exactly as the IN (k, 'cat:'||k) did.
          'knowledge', coalesce(kb.n, 0) + coalesce(kc.n, 0)
        ) r
        from keys k
        left join public.category_agents ca on ca.slug = k.k
        left join public.prompts pr on pr.key = k.k
        left join runs ru on ru.k = k.k
        left join last_status ls on ls.k = k.k
        left join acts ac on ac.k = k.k
        left join mem me on me.k = k.k
        left join kn kb on kb.k = k.k
        left join kn kc on kc.k = 'cat:' || k.k
      ) s), '[]'::jsonb)
  ) into v_out;

  return v_out;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ws_ai()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'agents',(select count(*) from category_agents),
      'agents_active',(select count(*) from category_agents where active is true),
      'actions_total',(select count(*) from agent_actions),
      'actions_pending',(select count(*) from agent_actions where status='pending'),
      'runs_24h',(select count(*) from agent_runs where started_at > now()-interval '24 hours'),
      'avg_confidence',(select round(avg(confidence)::numeric,2) from decision_log where confidence is not null)
    ),
    'trainer', jsonb_build_object(
      'ai_health', (select (kpis->>'ai_health')::numeric from ai_trainer_snapshots order by snapshot_date desc limit 1),
      'metrics', (select kpis from ai_trainer_snapshots order by snapshot_date desc limit 1),
      'weak_agents', coalesce((select jsonb_agg(jsonb_build_object('agent',agent,'run_success_pct',run_success_pct,'rejection_rate_pct',rejection_rate_pct,'errors',errors) order by run_success_pct nulls last)
          from ai_agent_quality where runs_30d>=20 and (coalesce(run_success_pct,100)<95 or coalesce(rejection_rate_pct,0)>20)),'[]'::jsonb),
      'proposals', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk,'reco',recommendation))
          from agent_actions where agent='ai_trainer' and status in ('pending','needs_review')),'[]'::jsonb)
    ),
    'prompt_reviews', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id, 'key', detail->>'key', 'version', (detail->>'version')::int,
        'reason', detail->>'reason',
        'active_version', (select active_version from prompts p where p.key = a.detail->>'key'),
        'active_score', (a.detail->'eval'->>'active_score'),
        'candidate_score', (a.detail->'eval'->>'candidate_score'),
        'delta', (a.detail->'eval'->>'delta'),
        'decision', a.detail->'eval'->>'decision',
        'sensitive', (a.detail->'eval'->>'sensitive'),
        'scored', (a.detail ? 'eval')
      ) order by created_at desc)
      from agent_actions a where kind='prompt_approval' and status in ('pending','needs_review')),'[]'::jsonb),
    'agents', coalesce((select jsonb_agg(jsonb_build_object('slug',ca.slug,'name',ca.name,'emoji',ca.emoji,'active',ca.active,
        'actions',(select count(*) from agent_actions a where a.agent=ca.slug),
        'pending',(select count(*) from agent_actions a where a.agent=ca.slug and a.status='pending')) order by ca.name) from category_agents ca),'[]'::jsonb),
    'kinds', coalesce((select jsonb_agg(jsonb_build_object('key',k,'count',c) order by c desc) from (
        select coalesce(nullif(kind,''),'other') k, count(*) c from agent_actions group by 1 order by 2 desc limit 12) kk),'[]'::jsonb),
    'runs', coalesce((select jsonb_agg(jsonb_build_object('id',id,'agent',agent,'status',status,'started_at',started_at,'finished_at',finished_at,'note',note)) from (select * from agent_runs order by started_at desc limit 12) r),'[]'::jsonb)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_analytics()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'marketplace', fn_marketplace_analytics(),
    'supplier_funnel', jsonb_build_object(
      'directory',(select count(*) from leads),
      'claimed',(select count(*) from leads where claimed is true),
      'registered',(select count(*) from leads where registration_paid_at is not null),
      'submitted',(select count(*) from leads where coalesce(approval_status,'') in ('submitted','under_review','pending','pending_review')),
      'approved',(select count(*) from leads where approval_status='approved')
    ),
    'top_sectors', coalesce((select jsonb_agg(jsonb_build_object('key',s,'count',c) order by c desc) from (
        select coalesce(nullif(sector,''),'other') s, count(*) c from leads group by 1 order by 2 desc limit 12) x),'[]'::jsonb),
    'top_emirates', coalesce((select jsonb_agg(jsonb_build_object('key',e,'count',c) order by c desc) from (
        select coalesce(nullif(emirate,''),'—') e, count(*) c from leads group by 1 order by 2 desc limit 8) x),'[]'::jsonb)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_company()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'legal', jsonb_build_object(
      'health', (select (kpis->>'legal_health')::numeric from legal_kpi_snapshots order by snapshot_date desc limit 1),
      'kpis', (select to_jsonb(k) from legal_kpis k),
      'missing_docs', coalesce((select jsonb_agg(jsonb_build_object('requirement',requirement,'priority',priority,'applies_to',applies_to) order by priority) from legal_checklist where not present),'[]'::jsonb),
      'flags', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk)) from agent_actions where agent='legal_ai' and status in ('pending','needs_review')),'[]'::jsonb),
      'reviews', coalesce((select jsonb_agg(jsonb_build_object('title',title,'kind',doc_kind,'risk',risk_level,'at',reviewed_at) order by reviewed_at desc) from (select * from legal_reviews order by reviewed_at desc limit 10) r),'[]'::jsonb)
    ),
    'departments', coalesce((select jsonb_agg(jsonb_build_object('agent',agent,'actions',c,'pending',pend,'last_active',la) order by c desc) from (
        select coalesce(agent,'—') agent, count(*) c,
               count(*) filter (where status='pending') pend, max(created_at) la
        from agent_actions where created_at >= public.fn_os_fresh_start_at() group by 1 order by 2 desc limit 20) d),'[]'::jsonb),
    'runs', coalesce((select jsonb_agg(jsonb_build_object('agent',agent,'status',status,'started_at',started_at,'note',note)) from (select * from agent_runs where started_at >= public.fn_os_fresh_start_at() order by started_at desc limit 12) r),'[]'::jsonb),
    'evals', coalesce((select jsonb_agg(jsonb_build_object('snapshot_at',snapshot_at,'window_days',window_days,'kpis',kpis)) from (select * from agent_evals where snapshot_at >= public.fn_os_fresh_start_at() order by snapshot_at desc limit 4) e),'[]'::jsonb)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_company_os()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(

    -- ── THE TEN OPERATING SYSTEMS ────────────────────────────────────────────────────────────
    'operating_systems', coalesce((select jsonb_agg(jsonb_build_object(
        'os_key', o.os_key, 'num', o.num, 'name', o.name, 'mission', o.mission,
        'charter', o.charter, 'mandate', o.mandate, 'owner_agent', o.owner_agent,
        'health_score', o.health_score, 'last_health_at', o.last_health_at, 'active', o.active,
        'responsibilities', (select coalesce(jsonb_agg(r.responsibility order by r.responsibility), '[]'::jsonb)
                               from public.os_responsibility r where r.os_key = o.os_key),
        'objectives', (select coalesce(jsonb_agg(jsonb_build_object(
                          'objective', j.objective, 'horizon', j.horizon, 'measure', j.measure,
                          'actual_value', j.actual_value) order by j.id), '[]'::jsonb)
                         from public.os_objective j where j.os_key = o.os_key and j.active),
        -- Only 4 of the 72 os_responsibility rows name a department; the rest name capabilities.
        -- So this reports the departments the OS demonstrably owns and the headcount inside THEM,
        -- rather than a company-wide headcount that would read as 0 for Leadership and be wrong.
        'owned_departments', (select coalesce(jsonb_agg(d.dept_key order by d.dept_key), '[]'::jsonb)
                                from public.org_departments d
                               where exists (select 1 from public.os_responsibility r2
                                              where r2.os_key = o.os_key and r2.responsibility = d.dept_key)),
        'staff_in_owned_departments', (select count(*) from public.org_agents a where a.active
                    and a.department in (select r2.responsibility from public.os_responsibility r2 where r2.os_key = o.os_key)))
      order by o.num) from public.operating_system o where o.active), '[]'::jsonb),

    -- ── THE COMPANY BRAIN, AS ONE GRAPH ──────────────────────────────────────────────────────
    'graph', jsonb_build_object(
      'node_count', (select count(*) from public.graph_nodes),
      'edge_count', (select count(*) from public.graph_edges),
      'rebuilt_at', (select max(updated_at) from public.graph_nodes),
      'node_kinds', coalesce((select jsonb_agg(jsonb_build_object('kind', k.kind, 'n', k.n) order by k.n desc)
                     from (select kind, count(*) n from public.graph_nodes group by 1) k), '[]'::jsonb),
      'edge_kinds', coalesce((select jsonb_agg(jsonb_build_object('rel', e.rel, 'src_kind', e.src_kind, 'dst_kind', e.dst_kind, 'n', e.n) order by e.n desc)
                     from (select rel, src_kind, dst_kind, count(*) n from public.graph_edges group by 1,2,3) e), '[]'::jsonb),
      'nodes', coalesce((select jsonb_agg(jsonb_build_object('kind', n.kind, 'ref_id', n.ref_id, 'label', n.label) order by n.kind, n.label)
                 from (select * from public.graph_nodes order by kind, label limit 200) n), '[]'::jsonb),
      'edges', coalesce((select jsonb_agg(jsonb_build_object('src_kind', g.src_kind, 'src_ref', g.src_ref, 'rel', g.rel, 'dst_kind', g.dst_kind, 'dst_ref', g.dst_ref) order by g.src_kind, g.rel)
                 from (select * from public.graph_edges order by src_kind, rel limit 300) g), '[]'::jsonb)),

    -- ── THE AI BOARD ─────────────────────────────────────────────────────────────────────────
    'board', jsonb_build_object(
      'advisors', coalesce((select jsonb_agg(jsonb_build_object(
          'advisor_key', b.advisor_key, 'name', b.name, 'lens', b.lens, 'asks', b.asks, 'weight', b.weight)
        order by b.advisor_key) from public.board_advisor b where coalesce(b.active, true)), '[]'::jsonb),
      'opinion_count', (select count(*) from public.board_opinion),
      'opinions', coalesce((select jsonb_agg(jsonb_build_object(
          'subject', p.subject, 'advisor_key', p.advisor_key, 'recommendation', p.recommendation,
          'rationale', left(p.rationale, 300), 'confidence', p.confidence, 'at', p.created_at)
        order by p.created_at desc)
        from (select * from public.board_opinion order by created_at desc limit 12) p), '[]'::jsonb)),

    -- ── THE INDICES: MATURITY, MARKETPLACE HEALTH, ORGANISATIONAL ENERGY ─────────────────────
    -- THE ENGINE ITSELF HAD NO SCREEN (12 Aug 2026). 238 workflow runs and the only thing any
    -- surface showed was a count tile: "Workflows run today". Which processes are in flight, where
    -- each one is parked and WHO it is waiting on were not on any screen in the company, so the
    -- engine going from 5 completed runs to 131 was invisible except in the database.
    -- waiting_on is the resolved employee, not the raw actor_role - the whole point of the
    -- resolver work is that a step now names somebody the company can actually reach.
    'workflow_state', jsonb_build_object(
      'by_status', coalesce((select jsonb_object_agg(s.status, s.n)
          from (select status, count(*) n from public.workflow_run group by 1) s), '{}'::jsonb),
      'steps_delivered', (select count(*) from public.workflow_step_run
                             where output->>'worked_by' = 'workflow_dispatch'),
      'ready_now', (select count(*) from public.workflow_step_run sr
                      join public.workflow_run r on r.id = sr.workflow_run_id
                     where sr.status = 'ready' and r.status = 'running'),
      'in_flight', coalesce((select jsonb_agg(jsonb_build_object(
            'run_id', r.id,
            'workflow', coalesce(w.name, r.workflow_key),
            'step_no', sr.step_no,
            'step', sr.input->>'step',
            'gate', nullif(sr.input->>'gate', 'none'),
            'waiting_on', public.fn_workflow_actor_resolve(r.id, sr.actor),
            'addressed_as', coalesce(sr.input->>'addressed_as', sr.actor),
            'waiting_since', sr.started_at,
            'hours_waiting', round(extract(epoch from (now() - sr.started_at))/3600.0)
          ) order by sr.started_at)
        from (select r2.id, r2.workflow_key, sr2.step_no, sr2.input, sr2.actor, sr2.started_at
                from public.workflow_run r2
                join public.workflow_step_run sr2
                  on sr2.workflow_run_id = r2.id and sr2.status = 'ready'
               where r2.status = 'running'
               order by sr2.started_at
               limit 25) q
        join public.workflow_run r on r.id = q.id
        join public.workflow_step_run sr on sr.workflow_run_id = q.id and sr.step_no = q.step_no
        left join public.workflow w on w.workflow_key = r.workflow_key), '[]'::jsonb)),

    -- WHAT THE COMPANY'S PROCESSES ACTUALLY PRODUCED (11 Aug 2026).
    -- workflow_step_run.output holds 3,700-4,700 characters of real analysis per step, written by
    -- the named employee who owns that step. Before this key, the ONLY readers of that column were
    -- the two functions that write it; this surface counted rows per day and showed none of the
    -- work. A deliverable nobody reads is the defect this estate keeps reproducing.
    -- The outcome line is surfaced, not the body: the founder wants to see what his company decided,
    -- and the full text stays one query away for anything that needs it.
    'process_work', coalesce((select jsonb_agg(jsonb_build_object(
        'at', sr.finished_at,
        'workflow', coalesce(w.name, r.workflow_key),
        'step_no', sr.step_no,
        'step', sr.input->>'step',
        'employee', coalesce(sr.output->>'employee', sr.actor),
        'outcome', left(coalesce(sr.output->>'outcome',''), 400),
        'chars', length(coalesce(sr.output->>'deliverable','')),
        'confidence', sr.output->>'self_confidence',
        'mode', sr.output->>'mode') order by sr.finished_at desc)
      from public.workflow_step_run sr
      join public.workflow_run r on r.id = sr.workflow_run_id
      left join public.workflow w on w.workflow_key = r.workflow_key
     where sr.status = 'done'
       and coalesce(sr.output->>'deliverable','') <> ''
       and sr.finished_at > now() - interval '14 days'
     limit 40), '[]'::jsonb),

    'indices', coalesce((select jsonb_agg(jsonb_build_object(
        'index_name', c.index_name, 'score', c.score, 'band', c.band,
        'measured_on', c.measured_on, 'dimensions', c.dimensions) order by c.index_name)
      from public.company_index c
      where c.measured_on = (select max(measured_on) from public.company_index c2 where c2.index_name = c.index_name)), '[]'::jsonb),
    'marketplace_health', (select jsonb_build_object('score', c.score, 'band', c.band, 'measured_on', c.measured_on, 'dimensions', c.dimensions)
        from public.company_index c where c.index_name = 'marketplace_health'
        order by c.measured_on desc, c.id desc limit 1),

    -- ── EXECUTIVE REPLAY ─────────────────────────────────────────────────────────────────────
    'replay', jsonb_build_object(
      -- THE SIX TRACKS OF THE CHOSEN DAY, in one place for the first time. The day is the newest
      -- company_snapshot day, which is the chip the Replay card is already showing, so these
      -- counts describe what the founder is looking at rather than a different day's activity.
      'tracks', (select jsonb_build_object(
          'day', dd.day,
          'decisions',     (select count(*) from public.decision_log      x where x.created_at::date = dd.day),
          'conversations', (select count(*) from public.agent_chats       x where x.created_at::date = dd.day),
          'approvals',     (select count(*) from public.agent_actions     x where coalesce(x.decided_at, x.created_at)::date = dd.day),
          'workflows',     (select count(*) from public.workflow_step_run x where coalesce(x.started_at, x.finished_at)::date = dd.day),
          'kpis',          (select count(*) from public.metric_snapshot   x where x.taken_at::date = dd.day),
          'outcomes',      (select count(*) from public.outcome_record    x where coalesce(x.observed_at, x.created_at)::date = dd.day))
        from (select coalesce(max(snapshot_on), current_date - 1) as day from public.company_snapshot) dd),
      'days_on_file', (select count(*) from public.company_snapshot),
      'newest', (select max(snapshot_on) from public.company_snapshot),
      'company_snapshot', coalesce((select jsonb_agg(jsonb_build_object('snapshot_on', s.snapshot_on, 'state', s.state) order by s.snapshot_on desc)
        from (select * from public.company_snapshot order by snapshot_on desc limit 8) s), '[]'::jsonb)),

    -- ── REPUTATION ───────────────────────────────────────────────────────────────────────────
    'reputation', jsonb_build_object(
      'graded', (select count(*) from public.agent_reputation),
      'by_tier', coalesce((select jsonb_agg(jsonb_build_object('tier', t.tier, 'n', t.n) order by t.n desc)
                   from (select coalesce(tier, 'ungraded') tier, count(*) n from public.agent_reputation group by 1) t), '[]'::jsonb),
      'rows', coalesce((select jsonb_agg(jsonb_build_object(
          'agent_key', r.agent_key, 'score', r.score, 'tier', r.tier, 'correctness', r.correctness,
          'reliability', r.reliability, 'cost_efficiency', r.cost_efficiency,
          'learning_speed', r.learning_speed, 'collaboration', r.collaboration)
        order by r.score desc nulls last)
        from (select * from public.agent_reputation order by score desc nulls last limit 20) r), '[]'::jsonb)),

    -- ── STRUCTURAL PROPOSALS AND THE LESSON LEDGER ───────────────────────────────────────────
    'evolution_proposals', coalesce((select jsonb_agg(jsonb_build_object(
        'id', e.id, 'trigger_kind', e.trigger_kind, 'subject', e.subject,
        'observation', left(e.observation, 240), 'proposal', left(e.proposal, 240),
        'change_class', e.change_class, 'status', e.status, 'decided_by', e.decided_by, 'at', e.created_at)
      order by e.created_at desc)
      from (select * from public.evolution_proposal order by created_at desc limit 12) e), '[]'::jsonb),
    -- THE FOUR STRATEGIC QUEUES, named by their own tables so the screen and the store cannot drift
    -- apart: evolution_proposal, challenge_record, opportunity and board_opinion. The spec's
    -- "strategic decisions rather than operational tasks" is exactly this set against the pending
    -- agent_actions queue the founder was being shown instead.
    'strategic_queues', jsonb_build_object(
      'evolution_proposal', (select count(*) from public.evolution_proposal where status = 'proposed'),
      'challenge_record', (select count(*) from public.challenge_record where responded_at is null),
      'opportunity', (select count(*) from public.opportunity where status = 'open'),
      'board_opinion', (select count(*) from public.board_opinion),
      'operational_pending', (select count(*) from public.agent_actions where status in ('pending','needs_review'))),
    'opportunity', coalesce((select jsonb_agg(jsonb_build_object(
        'id', o.id, 'kind', o.kind, 'title', o.title, 'detail', left(o.detail, 240),
        'value_score', o.value_score, 'effort', o.effort, 'confidence', o.confidence, 'at', o.created_at)
      order by o.value_score desc nulls last)
      from (select * from public.opportunity where status = 'open'
             order by value_score desc nulls last limit 10) o), '[]'::jsonb),

    -- The AI disagreeing with the founder, and what it offered instead. 47 challenges on file, 31
    -- carrying alternatives, and no surface has ever shown one.
    'challenge_record', coalesce((select jsonb_agg(jsonb_build_object(
        'id', h.id, 'proposal', h.proposal, 'proposed_by', h.proposed_by, 'challenged_by', h.challenged_by,
        'stance', h.stance, 'confidence', h.confidence, 'reasoning', left(h.reasoning, 320),
        'alternatives', h.alternatives, 'violates_principle', h.violates_principle,
        'violates_rank', h.violates_rank, 'founder_response', h.founder_response,
        'responded_at', h.responded_at, 'at', h.created_at)
      order by h.created_at desc)
      from (select * from public.challenge_record order by created_at desc limit 12) h), '[]'::jsonb),

    'institutional_memory', jsonb_build_object(
      'lessons', (select count(*) from public.institutional_memory),
      'rows', coalesce((select jsonb_agg(jsonb_build_object(
          'kind', m.kind, 'headline', m.headline, 'outcome', m.outcome, 'lesson', left(m.detail, 240),
          'os_key', m.os_key, 'confidence', m.confidence, 'occurred_at', m.occurred_at)
        order by m.occurred_at desc nulls last)
        from (select * from public.institutional_memory order by occurred_at desc nulls last limit 12) m), '[]'::jsonb)),

    -- ── RESILIENCE ───────────────────────────────────────────────────────────────────────────
    'resilience', jsonb_build_object(
      'critical_capability', coalesce((select jsonb_agg(jsonb_build_object(
          'capability_key', c.capability_key, 'capability', c.capability, 'owner_dept', c.owner_dept,
          'test_kind', c.test_kind, 'last_verdict', c.last_verdict, 'last_checked', c.last_checked)
        order by c.capability_key) from public.critical_capability c), '[]'::jsonb),
      'continuity_plan', coalesce((select jsonb_agg(jsonb_build_object(
          'service', p.service, 'criticality', p.criticality, 'failure_mode', p.failure_mode,
          'fallback', p.fallback, 'recovery', p.recovery, 'rto_minutes', p.rto_minutes,
          'owner_agent', p.owner_agent, 'last_tested', p.last_tested)
        order by p.criticality, p.service) from public.continuity_plan p), '[]'::jsonb)),

    -- ── THE OPERATING MANUAL ─────────────────────────────────────────────────────────────────
    'operating_manual', jsonb_build_object(
      'runbooks', (select count(*) from public.os_runbooks),
      'by_category', coalesce((select jsonb_agg(jsonb_build_object('category', k.category, 'n', k.n) order by k.n desc)
                      from (select coalesce(category, 'uncategorised') category, count(*) n from public.os_runbooks group by 1) k), '[]'::jsonb),
      'rows', coalesce((select jsonb_agg(jsonb_build_object(
          'slug', r.slug, 'title', r.title, 'category', r.category, 'when_to_use', left(r.when_to_use, 200), 'os_key', r.os_key)
        order by r.sort nulls last, r.slug)
        from (select * from public.os_runbooks order by sort nulls last, slug limit 24) r), '[]'::jsonb)),

    -- ── RESOURCE MOVEMENT, AUTONOMY, SUPPLY AND THE EVENT BUS ────────────────────────────────
    'allocation_change', coalesce((select jsonb_agg(jsonb_build_object(
        'resource', a.resource, 'subject', a.subject, 'from_value', a.from_value, 'to_value', a.to_value,
        'reason', left(a.reason, 200), 'policy', a.policy, 'reverted', a.reverted, 'at', a.created_at)
      order by a.created_at desc)
      from (select * from public.allocation_change order by created_at desc limit 12) a), '[]'::jsonb),
    'autonomy', jsonb_build_object(
      'changes', (select count(*) from public.autonomy_control_audit),
      'rows', coalesce((select jsonb_agg(jsonb_build_object(
          'object', u.object, 'op', u.op, 'direction', u.direction, 'old_value', u.old_value,
          'new_value', u.new_value, 'reason', left(u.reason, 160), 'at', u.at)
        order by u.at desc)
        from (select * from public.autonomy_control_audit order by at desc limit 10) u), '[]'::jsonb)),
    'supply_health', jsonb_build_object(
      'snapshots', (select count(*) from public.supply_health_snapshots),
      'latest_period_end', (select max(period_end) from public.supply_health_snapshots),
      'coverage_gaps', coalesce((select jsonb_agg(to_jsonb(s) order by s.period_end desc)
        from (select * from public.supply_health_snapshots order by period_end desc limit 6) s), '[]'::jsonb)),
    'invite_schedule', coalesce((select jsonb_agg(jsonb_build_object(
        'day', i.day, 'planned', i.planned, 'sent', i.sent, 'status', i.status) order by i.day desc)
      from (select * from public.invite_schedule order by day desc limit 10) i), '[]'::jsonb),
    'events', jsonb_build_object(
      'total', (select count(*) from public.company_event),
      'last_7d', (select count(*) from public.company_event where occurred_at > now() - interval '7 days'),
      'by_class', coalesce((select jsonb_agg(jsonb_build_object('event_type', c.event_type, 'n', c.n) order by c.n desc)
                   from (select event_type, count(*) n from public.company_event
                          where occurred_at > now() - interval '30 days' group by 1) c), '[]'::jsonb)),

    -- ── MODEL MIX ────────────────────────────────────────────────────────────────────────────
    'model_mix', coalesce((select jsonb_agg(jsonb_build_object(
        'model_used', m.model_used, 'calls', m.calls, 'aed', m.aed, 'latency_ms', m.latency_ms,
        'cache_hits', m.cache_hits) order by m.aed desc)
      from (select coalesce(nullif(model_used,''),'unknown') model_used, count(*) calls,
                   round(coalesce(sum(cost_aed),0),4) aed,
                   round(avg(latency_ms)) latency_ms,
                   count(*) filter (where cached) cache_hits
              from public.ai_cost_log where occurred_at > now() - interval '30 days' group by 1) m), '[]'::jsonb),

    -- ── INFORMATION FLOWING BETWEEN THE TEN SYSTEMS ─────────────────────────────────────────
    -- Derived from what was actually DELIVERED, not from what os_interface declares: the declared
    -- outputs and inputs are disjoint sets and join to zero cross-OS edges. The consumer is
    -- event_delivery.os_key; the producer is company_event.actor resolved through its department,
    -- or the actor itself when the actor IS a department. Deliveries whose actor is machinery
    -- (system, a cron, the brief) are counted as unattributed rather than assigned to a system.
    'flow', (with res as (
        select d.os_key as to_os, d.event_type, d.delivered_at,
               coalesce((select od.os_key from public.org_agents a
                          join public.os_department od on od.dept_key = a.department
                         where a.agent_key = e.actor limit 1),
                        (select od2.os_key from public.os_department od2
                          where od2.dept_key = e.actor limit 1)) as from_os
          from public.event_delivery d
          join public.company_event e on e.id = d.event_id
         where d.os_key is not null and d.delivered_at > now() - interval '7 days')
      select jsonb_build_object(
        'window_days', 7,
        'deliveries', (select count(*) from res),
        'attributed', (select count(*) from res where from_os is not null),
        'unattributed', (select count(*) from res where from_os is null),
        'unroutable', (select count(*) from public.event_delivery
                        where unroutable_reason is not null
                          and delivered_at > now() - interval '7 days'),
        'nodes', coalesce((select jsonb_agg(jsonb_build_object(
            'os_key', o.os_key, 'num', o.num, 'name', o.name,
            'received', (select count(*) from res where res.to_os = o.os_key),
            'sent', (select count(*) from res where res.from_os = o.os_key)) order by o.num)
          from public.operating_system o where o.active), '[]'::jsonb),
        'edges', coalesce((select jsonb_agg(x) from (
            select from_os, to_os, count(*) as n,
                   count(distinct event_type) as event_types,
                   max(delivered_at) as newest,
                   (array_agg(distinct event_type))[1:3] as kinds
              from res where from_os is not null
             group by from_os, to_os order by count(*) desc limit 40) x), '[]'::jsonb))),

    'generated_at', now()
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_customer_360(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare c public.customers%rowtype; j jsonb;
  ltv numeric(18,2); deal_value numeric(18,2); reveals int;
  rfqs_total int; rfqs_active int; rfqs_done int; avg_budget numeric(18,2);
  last_act timestamptz; score int; cats text; docs jsonb := '[]'::jsonb; summary text;
begin
  select * into c from public.customers where id=p_id;
  if c.id is null then return jsonb_build_object('error','customer not found'); end if;

  select coalesce(sum(reveal_fee) filter (where fee_status='paid'),0), coalesce(sum(quote_amount),0), count(*)
    into ltv, deal_value, reveals from public.transactions where customer_id=p_id;
  select count(*), count(*) filter (where status not in ('completed','cancelled','closed','lost')),
         count(*) filter (where status in ('completed','closed') or outcome='completed'),
         coalesce(round(avg(nullif(expected_value,0)),2),0)
    into rfqs_total, rfqs_active, rfqs_done, avg_budget from public.inquiries where customer_id=p_id;
  select string_agg(distinct category, ', ') into cats from public.inquiries where customer_id=p_id and category is not null;

  select greatest(coalesce(max(i.created_at), c.created_at),
                  coalesce((select max(revealed_at) from public.transactions where customer_id=p_id), c.created_at),
                  c.created_at)
    into last_act from public.inquiries i where i.customer_id=p_id;
  last_act := coalesce(last_act, c.created_at);

  score := least(100, greatest(0,
      coalesce(rfqs_total,0)*12 + coalesce(reveals,0)*25 + round(coalesce(ltv,0)/20)::int
      + (case when last_act > now() - interval '30 days' then 15 else 0 end)));

  docs := coalesce((select jsonb_agg(jsonb_build_object('type','Drawing','name',coalesce(drawing_file_name,'drawing'),'path',drawing_file_path))
                    from public.inquiries where customer_id=p_id and drawing_file_path is not null),'[]'::jsonb);
  if c.signed_terms_path is not null then docs := docs || jsonb_build_object('type','Signed terms','name','terms','path',c.signed_terms_path); end if;

  summary := c.full_name||' joined '||to_char(c.created_at,'Mon YYYY')||'. '
    ||coalesce(rfqs_total,0)||' RFQ(s)'||coalesce(' across '||cats,'')||'. '
    ||coalesce(reveals,0)||' reveal(s), AED '||to_char(coalesce(ltv,0),'FM999999990.00')||' paid to date.'
    ||(case when avg_budget>0 then ' Avg project budget AED '||to_char(avg_budget,'FM999999990') else '' end)
    ||(case when c.banned then ' [BANNED]' when not coalesce(c.email_verified,false) then ' Email unverified.' else '' end);

  j := jsonb_build_object(
    'profile', jsonb_build_object('id',c.id,'full_name',c.full_name,'email',c.email,'phone',c.phone,
       'created_at',c.created_at,'phone_verified',c.phone_verified,'email_verified',c.email_verified,
       'banned',c.banned,'banned_reason',c.banned_reason,'whatsapp',jsonb_build_object('opt',c.whatsapp_opt,'confirmed',public.fn_whatsapp_destination('customer',c.id) is not null),'tos_accepted_at',c.tos_accepted_at,
       'chat_strikes',c.chat_strikes),
    'metrics', jsonb_build_object('ltv',ltv,'total_deal_value',deal_value,'reveals',reveals,
       'rfqs_total',rfqs_total,'rfqs_active',rfqs_active,'rfqs_completed',rfqs_done,
       'avg_project_budget',avg_budget,'relationship_score',score),
    'ai_summary', summary,
    'preferences', (
       with pref as (select p.preferences pj from public.customer_preference p
                       join public.customers cc on cc.id = p.customer_id
                      where p.customer_id = p_id and cc.tos_accepted_at is not null)
       select jsonb_build_object(
         'categories', coalesce((select pj->'stated'->'categories' from pref),
                                (select pj->'inferred'->'categories' from pref),
                                coalesce((select jsonb_agg(distinct category) from public.inquiries where customer_id=p_id and category is not null),'[]'::jsonb)),
         'emirates',   coalesce((select pj->'stated'->'emirates' from pref),
                                (select pj->'inferred'->'emirates' from pref),
                                coalesce((select jsonb_agg(distinct emirate) from public.inquiries where customer_id=p_id and emirate is not null),'[]'::jsonb)),
         'scope_type', (select pj->'inferred'->>'scope_type' from pref),
         'budget_aed_avg', (select pj->'inferred'->'budget_aed_avg' from pref),
         'remembered', exists(select 1 from pref))),
    'rfqs', coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'category',i.category,'emirate',i.emirate,
       'status',i.status,'pipeline_stage',i.pipeline_stage,'budget',i.expected_value,
       'outcome',i.outcome,'created_at',i.created_at) order by i.created_at desc)
       from (select * from public.inquiries where customer_id=p_id order by created_at desc limit 15) i),'[]'::jsonb),
    'quotes', coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'amount',q.quote_amount,'status',q.status,'created_at',q.created_at) order by q.created_at desc)
       from public.quotes q join public.inquiries i on i.id=q.inquiry_id where i.customer_id=p_id),'[]'::jsonb),
    'transactions', coalesce((select jsonb_agg(jsonb_build_object('quote_amount',t.quote_amount,'reveal_fee',t.reveal_fee,'fee_status',t.fee_status,'revealed_at',t.revealed_at) order by t.revealed_at desc)
       from public.transactions t where t.customer_id=p_id),'[]'::jsonb),
    'documents', docs,
    'timeline', (select jsonb_agg(e order by e->>'at' desc) from (
        select jsonb_build_object('at',c.created_at,'event','Signed up') e
        union all select jsonb_build_object('at',i.created_at,'event','RFQ: '||coalesce(i.category,'inquiry')) from public.inquiries i where i.customer_id=p_id
        union all select jsonb_build_object('at',t.revealed_at,'event','Revealed supplier · AED '||coalesce(t.reveal_fee::text,'0')||' fee') from public.transactions t where t.customer_id=p_id and t.revealed_at is not null
      ) tl)
  );
  return j;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ws_customer_behavior()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'customers',        (select count(*) from customer_health),
    -- Averages over the real book. NULL when there is nobody to average, never 0.
    'avg_health',       (select round(avg(health)::numeric, 1)       from customer_health),
    'avg_engagement',   (select round(avg(engagement)::numeric, 1)   from customer_health),
    'avg_satisfaction', (select round(avg(satisfaction)::numeric, 1) from customer_health),
    'dormant',          (select count(*) from customer_health where coalesce(dormant, false)),
    'at_risk',          (select count(*) from customer_health where lower(coalesce(risk_tier,'')) in ('high','elevated','at_risk')),
    'with_rfqs',        (select count(*) from customer_health where coalesce(total_inq, 0) > 0),
    -- CHURN IS NOT MEASURED, AND SAYS SO RATHER THAN RETURNING A NUMBER. Every customer on this
    -- platform was created inside the last 30 days and none has completed a transaction, so there
    -- is no lapse to observe. A churn rate here would be arithmetic on an empty set.
    'churn_rate_pct',   null,
    'churn_note',       'Not measured: no customer is old enough to have lapsed and no transaction has completed, so there is nothing to compute a churn rate from.',
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
              'customer_id', c.customer_id, 'name', c.full_name, 'email', c.email,
              'health', c.health, 'engagement', c.engagement, 'satisfaction', c.satisfaction,
              'progress', c.progress, 'service', c.service, 'risk_tier', c.risk_tier,
              'dormant', c.dormant, 'total_inq', c.total_inq, 'active_inq', c.active_inq,
              'stalled_inq', c.stalled_inq, 'last_activity', c.last_activity)
            order by c.health nulls last)
            from customer_health c), '[]'::jsonb),
    'generated_at', now()
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_customers()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'total',(select count(*) from customers),
      'verified',(select count(*) from customers where phone_verified is true or email_verified is true),
      'banned',(select count(*) from customers where banned is true),
      'with_rfqs',(select count(distinct customer_id) from inquiries where customer_id is not null)
    ),
    'success', jsonb_build_object(
      'kpis', coalesce((select to_jsonb(k) from customer_kpis k),'{}'::jsonb),
      'open_escalations', (select count(*) from agent_actions where kind='customer_escalation' and status in ('pending','needs_review')),
      'attention', coalesce((select jsonb_agg(a) from (
          select jsonb_build_object('id',customer_id,'name',coalesce(full_name,email),'health',health,
            'engagement',engagement,'satisfaction',satisfaction,'progress',progress,'service',service,
            'risk_tier',risk_tier,'stalled',stalled_inq,'disputes',disputes,'dormant',dormant) a
          from customer_health where risk_tier in ('high','medium') order by health asc limit 10) t),'[]'::jsonb),
      'trend', coalesce((select jsonb_agg(jsonb_build_object('d',snapshot_date,'health',(kpis->>'avg_health')) order by snapshot_date)
          from (select snapshot_date, kpis from customer_kpi_snapshots order by snapshot_date desc limit 14) s),'[]'::jsonb)
    ),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'full_name',c.full_name,'email',c.email,'phone',c.phone,
        'phone_verified',c.phone_verified,'email_verified',c.email_verified,'banned',c.banned,'created_at',c.created_at,
        'rfqs',(select count(*) from inquiries i where i.customer_id=c.id),
        'projects',(select count(*) from projects p where p.customer_id=c.id))) from (select * from customers order by created_at desc limit 100) c),'[]'::jsonb)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_documents()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'documents',(select count(*) from documents),
      'inventory_total',(select count(*) from document_inventory),
      'dropbox_files',(select count(*) from dropbox_files where not is_folder),
      'indexed',(select count(*) from documents where indexed is true),
      -- a review a department owns is not pending for the founder (6 Sep 2026)
      'reviews_pending',(select count(*) from doc_reviews where coalesce(status,'')='pending' and owner_role is null),
      'versions',(select count(*) from doc_versions)
    ),
    'controller', jsonb_build_object(
      'health', (select (kpis->>'doc_health')::numeric from document_kpi_snapshots order by snapshot_date desc limit 1),
      'kpis', (select to_jsonb(k) from document_kpis k),
      'by_bucket', coalesce((select jsonb_agg(jsonb_build_object('bucket',bucket,'docs',c,'bytes',b,'past_retention',pr,'class',cls) order by c desc)
          from (select bucket, count(*) c, sum(bytes) b, count(*) filter (where past_retention) pr, max(retention_class) cls from document_inventory group by bucket) t),'[]'::jsonb),
      'dropbox', jsonb_build_object(
        'connected', (select (max(synced_at) is not null) from dropbox_files),
        'files', (select count(*) from dropbox_files where not is_folder),
        'folders', (select count(*) from dropbox_files where is_folder),
        'bytes', (select coalesce(sum(size),0) from dropbox_files),
        'last_sync', (select max(synced_at) from dropbox_files),
        'top_folders', coalesce((select jsonb_agg(jsonb_build_object('path',path,'items',n) order by n desc)
            from (select split_part(path,'/',2) path, count(*) n from dropbox_files where path like '/%/%' group by 1 order by 2 desc limit 8) t),'[]'::jsonb)
      ),
      'retention', coalesce((select jsonb_agg(jsonb_build_object('bucket',bucket,'class',class,'retention_days',retention_days) order by bucket) from retention_policy),'[]'::jsonb),
      'tasks', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk,'reco',recommendation)) from agent_actions where agent='document_controller' and status in ('pending','needs_review')),'[]'::jsonb)
    ),
    -- bucket + path: what os_api `file` signs so the shell can open the row (6 Sep 2026)
    'documents', coalesce((select jsonb_agg(jsonb_build_object('id',id,'file_name',file_name,'kind',kind,'ref_table',ref_table,'ref_id',ref_id,'status',status,'indexed',indexed,'created_at',created_at,'bucket',bucket,'path',path)) from (select * from documents order by created_at desc limit 40) d),'[]'::jsonb),
    -- the section is titled "Reviews pending" and carries Approve/Reject: it lists pending, unowned rows only
    'reviews', coalesce((select jsonb_agg(jsonb_build_object('id',id,'file_name',file_name,'ai_category',ai_category,'ai_summary',ai_summary,'ai_confidence',ai_confidence,'status',status,'created_at',created_at)) from (select * from doc_reviews where coalesce(status,'')='pending' and owner_role is null order by created_at desc limit 20) r),'[]'::jsonb),
    'kinds', coalesce((select jsonb_agg(jsonb_build_object('key',k,'count',c) order by c desc) from (select coalesce(nullif(kind,''),'other') k, count(*) c from documents group by 1) kk),'[]'::jsonb)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_ea()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'today_events', a->'today'->'events',
    'reminders_due', a->'today'->'reminders_due',
    'upcoming_events', a->'upcoming_events',
    'open_tasks', a->'open_tasks',
    'overdue_tasks', (a->>'overdue_tasks')::int,
    'approvals_total', (a->'approvals_to_clear'->>'total')::int,
    'approvals_high_risk', (a->'approvals_to_clear'->>'high_risk')::int,
    'approvals_top', a->'approvals_to_clear'->'top',
    'recent_meetings', a->'recent_meetings'
  )
  from (select fn_ea_agenda(7) a) x;
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_exec()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'command', fn_os_command(),
    'tasks', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'status',status,'priority',priority,'due',due_date,'entity',entity)) from (select * from crm_tasks where coalesce(status,'') not in ('done','cancelled') and created_at >= fn_os_fresh_start_at() order by created_at desc limit 8) t),'[]'::jsonb),
    'approvals', public.fn_founder_queue(6)->'waiting_on_you',
    'held', coalesce((select jsonb_agg(jsonb_build_object('id',id,'agent',agent,'title',title,'kind',kind,'kind_label',fn_ui_label('action_kind',kind),'holder',public.fn_action_holder(kind, agent),'risk',risk,'status',status,'created_at',created_at,'yours',false))
                from (select a.* from agent_actions a left join agent_action_kind_policy p on p.kind = a.kind
                       where a.status in ('pending','needs_review') and coalesce(p.policy,'') <> 'founder'
                         and a.created_at >= fn_os_fresh_start_at() order by a.created_at desc limit 6) a),'[]'::jsonb),
    'activity', coalesce((select jsonb_agg(jsonb_build_object('actor',actor,'kind',kind,'kind_label',fn_ui_label('action_kind',kind),'decision',decision,'confidence',confidence,'route_to',route_to,'created_at',created_at)) from (select * from decision_log where created_at >= fn_os_fresh_start_at() order by created_at desc limit 10) d),'[]'::jsonb),
    'notifications', coalesce((select jsonb_agg(jsonb_build_object('type',type,'type_label',fn_ui_label('notification_type',type),'subject',subject,'status',status,'created_at',created_at)) from (select * from notifications where created_at >= fn_os_fresh_start_at() order by created_at desc limit 6) n),'[]'::jsonb)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_exec_home()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with h as (select to_jsonb(public.fn_health_index()) j),
  gh as (
    select coalesce(
      (select 'monthly' where exists (select 1 from public.goal_period where horizon = 'monthly')),
      (select 'quarterly' where exists (select 1 from public.goal_period where horizon = 'quarterly')),
      'annual') hz
  ),
  g as (
    -- fn_goal_attainment handles the four ways the inline version was wrong (least() ignoring
    -- nulls, direction, period, row-count-as-goal-count). One copy, not two.
    select (a.j->>'pct')::numeric        pct,
           (a.j->>'goals_total')::int    n,
           (a.j->>'goals_measured')::int measured
      from gh, lateral (select public.fn_goal_attainment(gh.hz) j) a
  ),
  bott as (
    select coalesce(jsonb_agg(jsonb_build_object(
             'department', r.owner_dept, 'resource', r.resource, 'used_pct', r.used_pct,
             'state', r.state, 'committed', r.committed, 'capacity', r.capacity, 'unit', r.unit)
           order by r.used_pct desc nulls last), '[]'::jsonb) j
      from public.v_resource_pressure r where r.state in ('HALT', 'DEGRADE')
  ),
  dept as (
    select coalesce(jsonb_agg(jsonb_build_object(
             'department', coalesce(dh.department, e->>'label', e->>'key'),
             'dept_key', e->>'key',
             'runs', (e->'runs'),
             'busy', coalesce((e->>'runs')::int, 0) > 0,
             'health', dh.score, 'status', dh.status)
           order by coalesce((e->>'runs')::int, 0) desc), '[]'::jsonb) j
      from jsonb_array_elements(public.fn_agents_board()->'departments') e
      left join public.v_department_health dh on dh.dept_key = e->>'key'
  ),
  -- fn_founder_queue and fn_founder_refund_approvals_open were dropped earlier today with the rest
  -- of the founder-approval machinery: "all approvals are from CEO. nothing goes to me". The apply
  -- guard refused this file until these two calls came out, which is the guard doing its job -- a
  -- plpgsql body resolves its callees at RUN time, so without it this would have applied cleanly and
  -- thrown the first time the tile was rendered.
  fq as (select null::jsonb j),
  home as (select jsonb_build_object(
    'health_index',     (select (j->>'index')::numeric from h),
    'mood',             (select j->>'band' from h),
    'health_note',      (select j->>'note' from h),
    'revenue_today',    (select coalesce(sum(coalesce(reveal_fee, app_fee, 0)), 0)
                           from public.transactions where revealed_at::date = current_date),
    'revenue_30d',      (select coalesce(sum(coalesce(reveal_fee, app_fee, 0)), 0)
                           from public.transactions where revealed_at > now() - interval '30 days'),
    'goal_progress_pct', (select pct from g),
    'goal_horizon',     (select hz from gh),
    'goal_count',       (select n from g),
    'goal_measured',    (select measured from g),
    'customers_active', (select count(*) from public.customers where coalesce(banned, false) = false),
    'suppliers_active', coalesce((public.fn_marketplace_analytics()->>'active_suppliers_30d')::int, 0),
    'employees',        (select count(*) from public.org_agents where active),
    'employees_working', (select count(*) from public.org_agents o where o.active and (
                             exists (select 1 from public.agent_runs r
                                      where r.agent = o.agent_key and r.started_at > now() - interval '24 hours')
                          or exists (select 1 from public.agent_memory m
                                      where m.agent_key = o.agent_key and m.created_at > now() - interval '24 hours')
                          or exists (select 1 from public.agent_chats c
                                      where c.agent_key = o.agent_key and c.created_at > now() - interval '24 hours'))),
    'bottlenecks',      (select j from bott),
    'departments',      (select j from dept),
    'workflow_runs_24h', (select count(*) from public.workflow_run
                           where coalesce(started_at, created_at) > now() - interval '24 hours'),
    -- 9 SEP 2026 -- PHASE MACHINERY REMOVED. A 'handoffs_24h' key stood here counting
    -- the kernel handoff-run table over 24 hours. That table is deleted in this sweep, so the key is
    -- gone rather than pinned to a hard-coded zero: an absent number and a measured zero are
    -- different statements, and the OS must not be told "no handoffs" by a routine that can no
    -- longer count them. Any surface reading home.handoffs_24h now reads undefined; the founder
    -- has accepted that the website may break in the meantime and be rebuilt correctly.
    'events_delivered_24h', (select count(*) from public.event_delivery
                              where delivered_at > now() - interval '24 hours'),
    'knowledge_revisions_7d', (select count(*) from public.kb_revisions
                                where created_at > now() - interval '7 days'),
    'uptime_pct_24h', (select round(100.0 * count(*) filter (where verdict = 'ALIVE')
                                    / nullif(count(*), 0), 1)
                         from public.edge_health_probe where checked_at > now() - interval '24 hours'),
    'leads_total',      (select count(*) from public.leads),
    'agent_runs_24h',   (select count(*) from public.agent_runs where started_at > now() - interval '24 hours'),
    'events_24h',       (select count(*) from public.company_event where occurred_at > now() - interval '24 hours'),
    -- HIS decisions: refund approvals and nothing else. The 14 open agent_actions this used to
    -- count are held with their roles and reported under that name.
    -- HIS decision queue is empty by ruling, not by measurement: nothing is routed to him at all.
    'decisions_open',   0,
    'held_with_roles',  (select (j->>'held_with_roles_total')::int from fq),
    'held_with',        (select j->'held_with_roles' from fq),
    -- ONE definition of an open task: public.v_org_open_tasks (see one_definition_of_an_open_task.sql).
    'tasks_open',       (select count(*) from public.v_org_open_tasks),
    'generated_at',     now()
  ) j)
  -- THE OVERNIGHT BRIEF, AS ONE SENTENCE. Written here so the Console's "speak the overnight brief"
  -- button and the founder command channel ("status", "brief", "how are we doing") read the SAME
  -- text from the SAME figures, instead of one composing it in the browser and the other having no
  -- answer at all (6 Sep 2026: "status" came back as "clarification required").
  select h.j || jsonb_build_object('brief_text',
       'Company health ' || coalesce(h.j->>'health_index', 'unknown') || ', mood ' || coalesce(h.j->>'mood', 'unknown') || '. '
    || 'Revenue today ' || coalesce(h.j->>'revenue_today', '0') || ' dirhams, ' || coalesce(h.j->>'revenue_30d', '0') || ' over thirty days. '
    || coalesce(h.j->>'suppliers_active', '0') || ' active suppliers, ' || coalesce(h.j->>'customers_active', '0') || ' active customers. '
    || coalesce(h.j->>'employees_working', '0') || ' of ' || coalesce(h.j->>'employees', '0') || ' AI employees worked overnight. '
    || 'Goal progress ' || coalesce(h.j->>'goal_progress_pct', '0') || ' percent. '
    || coalesce(h.j->>'tasks_open', '0') || ' open tasks across every department. '
    || case when jsonb_array_length(coalesce(h.j->'bottlenecks', '[]'::jsonb)) > 0
            then jsonb_array_length(h.j->'bottlenecks')::text || ' departments are over capacity.'
            else 'No department is over capacity.' end)
  from home h;
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_finance()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  cash_total numeric(18,2); rev_total numeric(18,2); exp_total numeric(18,2);
  rev30 numeric(18,2); exp30 numeric(18,2); monthly_burn numeric(18,2); runway numeric(18,1);
  j jsonb;
begin
  select coalesce(sum(balance),0) into cash_total from public.gl_account_balances where code in ('1000','1050');
  select coalesce(sum(balance),0) into rev_total from public.gl_account_balances where type='revenue';
  select coalesce(sum(balance),0) into exp_total from public.gl_account_balances where type='expense';

  -- 30-day run-rate (posted activity)
  select
    coalesce(sum(case when ga.type='revenue' then l.credit-l.debit else 0 end),0),
    coalesce(sum(case when ga.type='expense' then l.debit-l.credit else 0 end),0)
    into rev30, exp30
  from public.gl_journal_lines l
  join public.gl_journal j2 on j2.id=l.journal_id and j2.status='posted'
  join public.gl_accounts ga on ga.code=l.account_code
  where j2.entry_date >= current_date - 30;

  monthly_burn := exp30 - rev30;                       -- net cash burn (positive = burning)
  runway := case when monthly_burn > 0 and cash_total > 0 then round(cash_total/monthly_burn,1) else null end;

  j := jsonb_build_object(
    'as_of', now(),
    'cash', jsonb_build_object(
      'total', cash_total,
      'accounts', coalesce((select jsonb_agg(jsonb_build_object('code',code,'name',name,'balance',balance) order by code)
                   from public.gl_account_balances where code in ('1000','1050','1100','1110','1150','1500','1600')),'[]'::jsonb)
    ),
    'pnl', jsonb_build_object(
      'revenue', rev_total, 'expenses', exp_total, 'net_income', rev_total-exp_total,
      'margin_pct', case when rev_total>0 then round(100.0*(rev_total-exp_total)/rev_total,1) else null end
    ),
    'run_rate', jsonb_build_object(
      'revenue_30d', rev30, 'expense_30d', exp30, 'net_30d', rev30-exp30,
      'arr_estimate', round(rev30*12,2), 'monthly_burn', monthly_burn,
      'runway_months', runway
    ),
    'monetization', jsonb_build_object(
      'reveal_fees', (select coalesce(balance,0) from public.gl_account_balances where code='4000'),
      'commissions', (select coalesce(balance,0) from public.gl_account_balances where code='4100'),
      'registration', (select coalesce(balance,0) from public.gl_account_balances where code='4200'),
      'stripe_fees', (select coalesce(balance,0) from public.gl_account_balances where code='6100')
    ),
    'revenue_breakdown', coalesce((select jsonb_agg(jsonb_build_object('code',code,'name',name,'amount',balance) order by balance desc)
        from public.gl_account_balances where type='revenue' and balance<>0),'[]'::jsonb),
    'expense_breakdown', coalesce((select jsonb_agg(jsonb_build_object('code',code,'name',name,'amount',balance) order by balance desc)
        from public.gl_account_balances where type='expense' and balance<>0),'[]'::jsonb),
    'receivables', jsonb_build_object(
      'commission_receivable', (select coalesce(balance,0) from public.gl_account_balances where code='1110'),
      'trade_receivable', (select coalesce(balance,0) from public.gl_account_balances where code='1100'),
      'overdue_commissions', (select coalesce(sum(amount_due),0) from public.supplier_dues
                              where public.fn_supplier_due_is_owed(status, paid_at) and coalesce(due_date,reveal_date) < current_date)
    ),
    'payables', jsonb_build_object(
      'ap_open', (select coalesce(sum(total-amount_paid),0) from public.ap_bills where status in ('open','partial')),
      'aging', coalesce((select jsonb_agg(to_jsonb(a)) from public.ap_aging a),'[]'::jsonb)
    ),
    'cashflow', coalesce((
      select jsonb_agg(x order by x->>'month')
      from (
        select jsonb_build_object(
          'month', to_char(date_trunc('month',j3.entry_date),'YYYY-MM'),
          'inflow', sum(l.debit), 'outflow', sum(l.credit), 'net', sum(l.debit-l.credit)
        ) x
        from public.gl_journal_lines l
        join public.gl_journal j3 on j3.id=l.journal_id and j3.status='posted'
        where l.account_code in ('1000','1050')
          and j3.entry_date >= (date_trunc('month',current_date) - interval '5 months')
        group by date_trunc('month',j3.entry_date)
      ) s
    ),'[]'::jsonb),
    'budgets', coalesce((select jsonb_agg(to_jsonb(b)) from public.budget_vs_actual_summary b),'[]'::jsonb)
  );
  j := j || jsonb_build_object('ai', jsonb_build_object(
    'kpis', (select to_jsonb(k) from public.finance_kpis k),
    'forecast', public.fn_finance_forecast(),
    'health', (select (kpis->>'health')::numeric from public.finance_kpi_snapshots order by snapshot_date desc limit 1),
    'open_alerts', (select count(*) from public.agent_actions where agent='finance_ai' and status in ('pending','needs_review')),
    'alerts', coalesce((select jsonb_agg(jsonb_build_object('signal',detail->>'signal','risk',risk,'title',title,'reco',recommendation))
        from public.agent_actions where agent='finance_ai' and status in ('pending','needs_review')),'[]'::jsonb),
    'trend', coalesce((select jsonb_agg(jsonb_build_object('d',snapshot_date,'health',(kpis->>'health'),'cash',(kpis->>'cash')) order by snapshot_date)
        from (select snapshot_date,kpis from public.finance_kpi_snapshots order by snapshot_date desc limit 14) s),'[]'::jsonb)
  ));
  return j;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ws_fraud()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'open_flags', (select count(*) from fraud_flags where coalesce(status,'open') not in ('dismissed','resolved','closed')),
      'high_severity', (select count(*) from fraud_flags where lower(coalesce(severity,'')) in ('high','critical') and coalesce(status,'open') not in ('dismissed','resolved','closed')),
      'flags_7d', (select count(*) from fraud_flags where created_at > now() - interval '7 days'),
      'banned_actors', (select (select count(*) from customers where banned) + (select count(*) from leads where banned))
    ),
    'open_flags', (select coalesce(jsonb_agg(f order by f.created desc),'[]'::jsonb) from (
        select kind, subject_type, subject_id, coalesce(severity,'—') severity, coalesce(status,'open') status,
               to_char(created_at,'YYYY-MM-DD HH24:MI') created, detail
        from fraud_flags where coalesce(status,'open') not in ('dismissed','resolved','closed')
        order by created_at desc limit 100) f),
    'banned', (select coalesce(jsonb_agg(b),'[]'::jsonb) from (
        select 'customer' kind, id::text subject_id, full_name name, banned_reason reason from customers where banned
        union all
        select 'supplier', id::text, company_name, banned_reason from leads where banned limit 100) b)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_governance()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    -- governance_kpis.open_for_review counts every open agent_action; overridden here with the
    -- founder's real number and the held count published beside it under its own name.
    'kpis', (select to_jsonb(k) from public.governance_kpis k)
            || jsonb_build_object('open_for_review', public.fn_founder_refund_approvals_open(),
                                  'held_with_roles', (public.fn_founder_queue(1)->>'held_with_roles_total')::int),
    'universal_rules', (select universal_rules from public.agent_governance where active order by version desc limit 1),
    'response_structure', (select response_structure from public.agent_governance where active order by version desc limit 1),
    'recent_escalations', (select coalesce(jsonb_agg(e),'[]'::jsonb) from (
        select id, agent, title, coalesce(escalation_reason,'—') as reason, confidence,
               public.fn_action_policies(kind, confidence) as policies,
               public.fn_owning_os(agent) as os,
               public.fn_action_holder(kind, agent) as holder,
               false as yours,
               (select d.alternatives from public.decision_log d where d.id = decision_log_id) as alternatives,
               case when decided_at is not null
        then coalesce(status,'decided') || ' by ' || coalesce(decided_by,'the system') || ' on ' || decided_at::date
        else 'held with ' || public.fn_action_holder(kind, agent) || ' since ' || created_at::date end as outcome,
               to_char(created_at,'YYYY-MM-DD') as created
        from public.agent_actions
        where escalated
          and status in ('pending','needs_review')
          and created_at >= public.fn_os_fresh_start_at()
        order by created_at desc limit 15) e),
    'agent_coverage', (select coalesce(jsonb_agg(c),'[]'::jsonb) from (
        select ca.name as agent, (ca.persona is not null) as has_persona,
               exists(select 1 from public.agent_knowledge k where k.agent_key='cat:'||ca.slug or k.agent_key=ca.slug) as has_knowledge,
               (select count(*) from public.agent_actions a where a.agent=ca.slug) as audit_items
        from public.category_agents ca where ca.active order by ca.name limit 60) c),
    'fresh_start_at', public.fn_os_fresh_start_at()
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_knowledge()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'chunks',(select coalesce(sum(chunks),0) from kb_category_stats),
      'document_chunks',(select coalesce(sum(chunks),0) from kb_category_stats where source_kind='document'),
      'categories',(select count(distinct category) from kb_category_stats),
      'category_specs',(select count(*) from catalog_supplier_categories),
      'stats_as_of',(select max(refreshed_at) from kb_category_stats)
    ),
    'curator', jsonb_build_object(
      'health', (select (kpis->>'health')::numeric from knowledge_kpi_snapshots order by snapshot_date desc limit 1),
      'coverage_pct', k.coverage_pct, 'knowledge_coverage_pct', k.knowledge_coverage_pct, 'playbook_coverage_pct', k.playbook_coverage_pct,
      'accuracy_pct', k.accuracy_pct, 'freshness_pct', k.freshness_pct, 'usage_reach_pct', k.usage_reach_pct,
      'regulations', k.regulations, 'regulations_pending', k.regulations_pending, 'standards', k.standards, 'manufacturers', k.manufacturers, 'brands', k.brands, 'materials', k.materials, 'playbooks', k.playbooks,
      'open_items', (select count(*) from agent_actions where agent='knowledge_curator' and status in ('pending','needs_review')),
      'tasks', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk,'reco',recommendation))
          from agent_actions where agent='knowledge_curator' and status in ('pending','needs_review')),'[]'::jsonb)
    ),
    'reg_library', jsonb_build_object(
      'coverage', (select to_jsonb(rc) from reg_coverage rc),
      'indexed', coalesce((select jsonb_agg(jsonb_build_object('authority',authority,'code',code_name,'domain',domain) order by authority) from reg_catalog where status='indexed'),'[]'::jsonb),
      'missing', coalesce((select jsonb_agg(jsonb_build_object('authority',authority,'code',code_name,'domain',domain,'priority',priority,'status',status) order by priority, authority) from reg_catalog where copyright='free' and status<>'indexed'),'[]'::jsonb),
      'reference_only', coalesce((select jsonb_agg(jsonb_build_object('authority',authority,'code',code_name) order by authority) from reg_catalog where copyright='copyrighted'),'[]'::jsonb)
    ),
    'regulations', coalesce((select jsonb_agg(jsonb_build_object('title',title,'status',authority||coalesce(' · '||status,''),'source_url',source_url) order by coalesce(effective_date, created_at) desc)
        from (select * from regulations order by coalesce(effective_date, created_at) desc limit 20) rg),'[]'::jsonb),
    -- 6 SEP 2026: category counts come from kb_category_stats (refreshed every 30 min), not from a
    -- GROUP BY over 2.7M rows per click.
    'categories', coalesce((select jsonb_agg(jsonb_build_object('key',cat,'count',c) order by c desc) from (
        select coalesce(nullif(regexp_replace(category,'^cat:',''),''),'general') cat, sum(chunks) c from kb_category_stats group by 1 order by 2 desc limit 16) kk),'[]'::jsonb),
    'coverage', coalesce((select jsonb_agg(jsonb_build_object('category',v.category,'label',v.label,'chunks',v.chunks,'status',v.status) order by v.chunks asc, v.num)
        from v_kb_coverage v),'[]'::jsonb),
    'coverage_kpis', jsonb_build_object(
        'gaps',(select count(*) from v_kb_coverage where status='gap'),
        'thin',(select count(*) from v_kb_coverage where status='thin'),
        'covered',(select count(*) from v_kb_coverage where status='covered'),
        'total',(select count(*) from v_kb_coverage)
    ),
    -- WHICH KNOWLEDGE WAS ACTUALLY USED, and by whom. agent_brain writes a row here on every
    -- retrieval; until now nothing read them back, so "the knowledge is being used" was an
    -- assertion rather than something the founder could check.
    'used', coalesce((select jsonb_agg(jsonb_build_object(
        'agent', u.agent, 'query', left(coalesce(u.query,''), 90),
        'category', u.category, 'at', u.created_at) order by u.created_at desc)
      from (select * from kb_usage_log order by created_at desc limit 25) u),'[]'::jsonb),
    'used_kpis', jsonb_build_object(
      'lookups_7d', (select count(*) from kb_usage_log where created_at > now() - interval '7 days'),
      'agents_7d', (select count(distinct agent) from kb_usage_log where created_at > now() - interval '7 days'),
      'categories_7d', (select count(distinct category) from kb_usage_log
                         where created_at > now() - interval '7 days' and category is not null)
    ),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'category',category,'citation',citation)) from (select * from kb_chunks order by created_at desc limit 20) c),'[]'::jsonb)
  )
  from knowledge_kpis k;
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_live_company()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(

    -- ── THE PATH: milestone by milestone, with the steps inside each ─────────────────────────
    'goal_path', coalesce((select jsonb_agg(jsonb_build_object(
        'milestone', v.label, 'year_no', v.year_no, 'statement', v.statement,
        'steps', (select coalesce(jsonb_agg(jsonb_build_object(
                     'step', g.goal, 'metric', g.metric, 'target', g.target_value,
                     'unit', g.unit, 'owner_dept', g.owner_dept,
                     'actual', (select p.actual_value from public.goal_period p
                                 where p.goal_key = g.key order by p.updated_at desc limit 1))
                   order by g.sort nulls last), '[]'::jsonb)
                   from public.company_goals g
                  where g.active and coalesce(g.horizon, 'year_' || v.year_no::text) ~* ('year_?' || v.year_no::text)))
      order by v.year_no)
      from public.vision_horizon v where v.active), '[]'::jsonb),
    'roadmap_summary', (select count(*) from public.vision_horizon where active),

    -- ── THE HANDOFF CHAIN: work passing from department to department ────────────────────────
    'handoff_chain', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'subject_type', c.subject_type, 'subject_id', c.subject_id,
        'from_dept', c.dept_key, 'hop', c.stage, 'author_agent', c.author_agent,
        'to_dept', (select g.department from public.org_agents g where g.agent_key = c.reviewer_agent limit 1),
        'reviewer_agent', c.reviewer_agent, 'decision', c.decision,
        'reason', left(coalesce(c.reason, ''), 200), 'confidence', c.confidence,
        'delegated_from', c.delegated_from, 'at', c.created_at)
      order by c.created_at desc)
      from (select * from public.review_chain order by created_at desc limit 25) c), '[]'::jsonb),
    'handoffs_total', (select count(*) from public.review_chain),
    'handoff_stages', coalesce((select jsonb_agg(jsonb_build_object('hop', s.stage, 'n', s.n) order by s.n desc)
      from (select stage, count(*) n from public.review_chain group by 1) s), '[]'::jsonb),

    -- Where an event actually landed, which is the other half of the same sequence.
    'event_delivery', coalesce((select jsonb_agg(jsonb_build_object(
        'event_type', e.event_type, 'to_dept', (select g.department from public.org_agents g where g.agent_key = e.agent_key limit 1),
        'agent_key', e.agent_key, 'os_key', e.os_key, 'delivered_at', e.delivered_at,
        'unroutable_reason', e.unroutable_reason) order by e.delivered_at desc)
      from (select * from public.event_delivery order by delivered_at desc limit 15) e), '[]'::jsonb),

    -- ── THE RISK REGISTER ────────────────────────────────────────────────────────────────────
    'risk_register', coalesce((select jsonb_agg(jsonb_build_object(
        'id', r.id, 'risk', r.risk, 'category', r.category, 'dept_key', r.dept_key,
        'probability', r.probability, 'impact', r.impact, 'owner_agent', r.owner_agent,
        'mitigation', left(coalesce(r.mitigation, ''), 240), 'status', r.status,
        'review_due', r.review_due)
      -- probability and impact are TEXT on this table, not numbers, so they cannot be multiplied
      -- into a score here. Ordered by review urgency instead, and both values travel to the screen.
      order by r.review_due nulls last, r.updated_at desc nulls last)
      from public.risk_register r where coalesce(r.status, '') <> 'closed'), '[]'::jsonb),

    -- ── INFRASTRUCTURE, the last twin class with no reader ───────────────────────────────────
    -- edge_health_probe is the thirteenth twin object class and the only one nothing the browser
    -- can reach had ever read, so the founder's twin was complete except for the machine it runs on.
    'infrastructure', jsonb_build_object(
      'probes', (select count(*) from public.edge_health_probe),
      'rows', coalesce((select jsonb_agg(to_jsonb(p) order by p.id desc)
        from (select * from public.edge_health_probe order by id desc limit 12) p), '[]'::jsonb)),

    -- ── DEPARTMENT HEALTH, for the twin ──────────────────────────────────────────────────────
    'department_health', coalesce((select jsonb_agg(jsonb_build_object(
        'dept_key', h.dept_key, 'department', h.department, 'score', h.score,
        'status', h.status, 'basis', h.basis) order by h.score nulls first)
      from public.v_department_health h), '[]'::jsonb),

    'generated_at', now()
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_marketing()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'health', (select (kpis->>'health')::numeric from marketing_snapshots order by snapshot_date desc limit 1),
    'inquiries_30d', k.inquiries_30d, 'quoted_30d', k.quoted_30d, 'revealed_30d', k.revealed_30d,
    'revenue_30d', k.revenue_30d, 'inq_to_quote_pct', k.inq_to_quote_pct, 'quote_to_reveal_pct', k.quote_to_reveal_pct,
    'blog_published', k.blog_published, 'drafts_pending', k.drafts_pending,
    'social_staged', k.social_staged, 'social_published', k.social_published,
    'seo_pages', k.seo_pages, 'seo_gaps', k.seo_gaps, 'supply_gaps', k.supply_gaps,
    'leads_total', k.leads_total, 'outreach_sent', k.outreach_sent,
    'meta', jsonb_build_object(
      'spend_30d', k.meta_spend_30d, 'clicks_30d', k.meta_clicks_30d, 'results_30d', k.meta_results_30d,
      'impressions_30d', k.meta_impressions_30d, 'active_campaigns', k.meta_active_campaigns,
      'cpl', k.meta_cpl, 'roi', k.meta_roi,
      'sync', (select case when (select value from app_secrets where key='meta_access_token') is not null then 'connected' else 'awaiting_token' end),
      'campaigns', coalesce((select jsonb_agg(jsonb_build_object('name',campaign_name,'status',effective_status,'spend',spend,'clicks',clicks,'results',results))
          from meta_insights where time_window='last_30d' and campaign_name ilike '%quotesdone%'),'[]'::jsonb)
    ),
    'priorities', coalesce((select plan->'priorities' from marketing_snapshots order by snapshot_date desc limit 1),'[]'::jsonb),
    'push_supply', coalesce((select jsonb_agg(jsonb_build_object('category',category,'inquiries_90d',inquiries_90d,'suppliers',suppliers) order by inquiries_90d desc)
        from (select * from marketing_category_demand where inquiries_90d>0 and suppliers=0 order by inquiries_90d desc limit 10) t),'[]'::jsonb),
    'recommendations', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk,'reco',recommendation))
        from agent_actions where agent='marketing_ai' and status in ('pending','needs_review')),'[]'::jsonb)
  )
  from marketing_kpis k;
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_marketplace()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'rfqs',(select count(*) from inquiries),
      'active',(select count(*) from inquiries where coalesce(status,'') not in ('completed','cancelled','closed')),
      'quotes',(select count(*) from quotes),
      'avg_value',(select round(avg(expected_value)) from inquiries where expected_value is not null),
      'hired',(select count(*) from inquiries where hired_supplier_id is not null),
      'transactions',(select count(*) from transactions)
    ),
    'kanban', coalesce((select jsonb_agg(jsonb_build_object('key',stg,'count',c) order by c desc) from (
        select coalesce(nullif(pipeline_stage,''),coalesce(nullif(status,''),'new')) stg, count(*) c from inquiries group by 1) k),'[]'::jsonb),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id',id,'category',category,'emirate',emirate,'summary',summary,
        'status',status,'pipeline_stage',pipeline_stage,'deal_owner',deal_owner,'expected_value',expected_value,
        'budget',budget,'rfq_ready',rfq_ready,'created_at',created_at) ) from (select * from inquiries order by created_at desc limit 50) i),'[]'::jsonb),
    'quotes', coalesce((select jsonb_agg(jsonb_build_object('id',id,'inquiry_id',inquiry_id,'supplier_id',supplier_id,
        'quote_amount',quote_amount,'customer_price',customer_price,'status',status,'created_at',created_at)) from (select * from quotes order by created_at desc limit 30) q),'[]'::jsonb)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_notifications()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with fq as (select public.fn_founder_queue(8) j)
  select jsonb_build_object(
    -- CRITICAL — a founder alert raised at critical/high. An open agent_action at risk 'critical'
    -- used to be added here; it belongs to its role and is listed under 'held' instead.
    'critical', jsonb_build_object(
      'tier', 'critical',
      'count', (select count(*) from public.founder_alerts
                 where lower(coalesce(level,'')) in ('critical','high')
                   and created_at > now() - interval '7 days'
                   and created_at >= public.fn_os_fresh_start_at()),
      'rows', coalesce((select jsonb_agg(jsonb_build_object('title', a.event, 'detail', left(a.detail::text, 200),
                          'level', a.level, 'at', a.created_at) order by a.created_at desc)
                from (select * from public.founder_alerts
                       where lower(coalesce(level,'')) in ('critical','high')
                         and created_at > now() - interval '7 days'
                         and created_at >= public.fn_os_fresh_start_at()
                       order by created_at desc limit 8) a), '[]'::jsonb)),

    -- IMPORTANT — waiting on the founder. That is a refund approval and nothing else.
    'important', jsonb_build_object(
      'tier', 'important',
      'count', public.fn_founder_refund_approvals_open(),
      'rows', coalesce((select jsonb_agg(jsonb_build_object('title', x->>'title', 'detail', 'from ' || (x->>'from') || ' · ' || (x->>'kind_label'),
                          'kind', x->>'kind', 'agent', x->>'from', 'at', x->>'raised', 'id', x->>'id', 'source', x->>'source'))
                from fq, jsonb_array_elements(fq.j->'waiting_on_you') x), '[]'::jsonb)),

    -- HELD — open work that belongs to a named role. Informational: he is not asked to decide it.
    'held', jsonb_build_object(
      'tier', 'held',
      'count', (select (j->>'held_with_roles_total')::int from fq),
      'rows', coalesce((select jsonb_agg(jsonb_build_object(
                          'title', 'held with ' || (x->>'holder') || ': ' || (x->>'count'),
                          'detail', (select string_agg(k, ', ') from jsonb_array_elements_text(x->'kinds') k),
                          'holder', x->>'holder', 'count', x->>'count'))
                from fq, jsonb_array_elements(fq.j->'held_with_roles') x), '[]'::jsonb)),

    -- SUGGESTED — nothing is blocked, but the company thinks the founder should look.
    'suggested', jsonb_build_object(
      'tier', 'suggested',
      'count', (select count(*) from public.opportunity where status = 'open'
                 and created_at >= public.fn_os_fresh_start_at())
             + (select count(*) from public.evolution_proposal where status = 'proposed'
                 and created_at >= public.fn_os_fresh_start_at()),
      'rows', coalesce((select jsonb_agg(jsonb_build_object('title', o.title, 'detail', left(coalesce(o.detail,''), 200),
                          'kind', o.kind, 'at', o.created_at) order by o.value_score desc nulls last)
                from (select * from public.opportunity where status = 'open'
                       and created_at >= public.fn_os_fresh_start_at()
                       order by value_score desc nulls last limit 6) o), '[]'::jsonb)),

    -- COMPLETED TODAY — closed since midnight, whoever closed it.
    'completed_today', jsonb_build_object(
      'tier', 'completed_today',
      'count', (select count(*) from public.agent_actions where decided_at::date = current_date),
      'rows', coalesce((select jsonb_agg(jsonb_build_object('title', a.title, 'status', a.status,
                          'decided_by', a.decided_by, 'at', a.decided_at) order by a.decided_at desc)
                from (select * from public.agent_actions where decided_at::date = current_date
                       order by decided_at desc limit 8) a), '[]'::jsonb)),

    'auto_cleared_24h', (select round(100.0 * count(*) filter (where coalesce(escalated, false) = false)
                                 / greatest(count(*), 1))
                           from public.agent_actions where created_at > now() - interval '24 hours'),
    'auto_handled_30d', (select round(100.0 * count(*) filter (where coalesce(escalated, false) = false)
                                 / greatest(count(*), 1))
                           from public.agent_actions where created_at > now() - interval '30 days'),
    'actions_24h', (select count(*) from public.agent_actions where created_at > now() - interval '24 hours'),
    'actions_30d', (select count(*) from public.agent_actions where created_at > now() - interval '30 days'),
    'outbound_queue', (select count(*) from public.notifications where coalesce(status,'') not in ('sent','delivered')),
    'fresh_start_at', public.fn_os_fresh_start_at(),
    'generated_at', now()
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_operations()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with fq as (select public.fn_founder_queue(30) j)
  select jsonb_build_object(
    'ops', jsonb_build_object(
      'health', (select (kpis->>'ops_health')::numeric from ops_kpi_snapshots order by snapshot_date desc limit 1),
      'kpis', (select to_jsonb(k) from ops_kpis k),
      'recommendations', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk,'reco',recommendation)) from agent_actions where agent='operations_ai' and status in ('pending','needs_review')),'[]'::jsonb)
    ),
    'security', jsonb_build_object(
      'score', (select (kpis->>'security_score')::numeric from security_kpi_snapshots order by snapshot_date desc limit 1),
      'kpis', (select to_jsonb(k) from security_kpis k),
      'incidents', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk)) from agent_actions where agent='security_ai' and status in ('pending','needs_review')),'[]'::jsonb),
      'events', coalesce((select jsonb_agg(jsonb_build_object('kind',kind,'severity',severity,'source',source,'at',created_at) order by created_at desc) from (select * from security_events where created_at >= public.fn_os_fresh_start_at() order by created_at desc limit 10) e),'[]'::jsonb)
    ),
    'kpis', jsonb_build_object(
      'approvals_pending', public.fn_founder_refund_approvals_open(),
      'held_with_roles', (select (j->>'held_with_roles_total')::int from fq),
      'high_risk',(select count(*) from agent_actions where status='pending' and coalesce(risk,'') in ('high','critical')),
      -- ONE definition of an open task (was: crm_tasks, the founder's own to-do list, which is 0).
      'tasks_open',(select count(*) from public.v_org_open_tasks),
      'decisions_24h',(select count(*) from decision_log where created_at > now()-interval '24 hours' and created_at >= public.fn_os_fresh_start_at()),
      'disputes',(select count(*) from transactions where coalesce(refund_status,'') in ('requested','pending'))
    ),
    -- HIS: the refund queue, verbatim from fn_founder_queue.
    'approvals', (select j->'waiting_on_you' from fq),
    -- NOT HIS: open agent_actions with the role that holds each. No approve/reject for him.
    'held', coalesce((select jsonb_agg(jsonb_build_object('id',id,'agent',agent,'kind',kind,
        'kind_label', public.fn_ui_label('action_kind', kind),
        'holder', public.fn_action_holder(kind, agent),
        'risk',risk,'title',title,
        'policies', public.fn_action_policies(kind, confidence),
        'recommendation',recommendation,'status',status,'target_table',target_table,'created_at',created_at,
        'os', public.fn_owning_os(agent), 'confidence', confidence, 'yours', false,
        'alternatives', (select d.alternatives from public.decision_log d where d.id = decision_log_id),
        'outcome', 'held with ' || public.fn_action_holder(kind, agent) || ' since ' || created_at::date)) from (
        select a.* from agent_actions a
          left join agent_action_kind_policy p on p.kind = a.kind
         where a.status in ('pending','needs_review') and coalesce(p.policy,'') <> 'founder'
           and a.created_at >= public.fn_os_fresh_start_at()
         order by (coalesce(a.risk,'')='critical') desc, a.created_at desc limit 30) a),'[]'::jsonb),
    'decisions', coalesce((select jsonb_agg(jsonb_build_object('id',id,'actor',actor,'kind',kind,'decision',decision,
        'confidence',confidence,'route_to',route_to,'created_at',created_at)) from (select * from decision_log where created_at >= public.fn_os_fresh_start_at() order by created_at desc limit 20) d),'[]'::jsonb),
    -- The company's open org_tasks, owned by their departments' agents (not his to close: no Done button).
    'tasks', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'status',status,'priority',priority,'due',null,
        'source', coalesce(dept_key,'—') || case when assigned_agent is not null then ' · ' || assigned_agent else '' end,
        'entity','org_task','created_at',created_at)) from (select * from public.v_org_open_tasks order by created_at desc limit 20) t),'[]'::jsonb)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_refunds()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'pending', (select count(*) from transactions where refund_status in ('requested','pending')),
      'within_window', (select count(*) from transactions where refund_status in ('requested','pending') and refund_deadline > now()),
      'resolved_30d', (select count(*) from transactions where refund_resolved_at > now() - interval '30 days')
    ),
    'pending', (select coalesce(jsonb_agg(r order by r.requested desc),'[]'::jsonb) from (
        select t.id as transaction_id, t.quote_id, t.reveal_fee, coalesce(t.refund_status,'—') refund_status, coalesce(t.refund_reason,'—') reason,
               to_char(t.refund_requested_at,'YYYY-MM-DD') requested, to_char(t.refund_deadline,'YYYY-MM-DD') deadline,
               (t.refund_deadline > now()) in_window, coalesce(c.full_name,'—') customer, coalesce(l.company_name,'—') supplier
        from transactions t left join customers c on c.id=t.customer_id left join leads l on l.id=t.supplier_id
        where t.refund_status in ('requested','pending') order by t.refund_requested_at desc limit 100) r),
    'recent_resolved', (select coalesce(jsonb_agg(r order by r.resolved desc),'[]'::jsonb) from (
        select t.id as transaction_id, t.quote_id, coalesce(t.refund_status,'—') refund_status, coalesce(t.refund_note,'—') note,
               to_char(t.refund_resolved_at,'YYYY-MM-DD') resolved
        from transactions t where t.refund_resolved_at is not null order by t.refund_resolved_at desc limit 25) r)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_reports()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', (select to_jsonb(k) from public.report_kpis k),
    -- THE LATEST EXECUTIVE MEETING, IN SEQUENCE. exec_reports.findings is the ordered transcript of
    -- what each of the ten officers said; report_registry projects only title/period/id, so until
    -- now the body reached nothing the browser could run. `contributions` keeps the array order
    -- the meeting wrote it in — that order IS the replay.
    'meeting', (select jsonb_build_object(
        'id', r.id, 'period', r.period, 'officer', r.officer, 'summary', r.summary,
        'at', to_char(r.created_at,'YYYY-MM-DD HH24:MI'),
        'contributions', coalesce(r.findings, '[]'::jsonb),
        'priorities', coalesce(r.recommendations, '[]'::jsonb),
        'challenges', (select coalesce(jsonb_agg(jsonb_build_object(
              'proposal', c.proposal, 'by', c.challenged_by, 'of', c.proposed_by,
              'stance', c.stance, 'confidence', c.confidence, 'reasoning', c.reasoning,
              'alternatives', c.alternatives) order by c.id), '[]'::jsonb)
            from public.challenge_record c
           where c.created_at between r.created_at - interval '30 minutes'
                                  and r.created_at + interval '6 hours'))
      from public.exec_reports r where r.officer='ceo' and r.created_at >= public.fn_os_fresh_start_at() order by r.created_at desc limit 1),
    'freshness', (select jsonb_build_object(
        'daily', daily_fresh, 'weekly', weekly_fresh, 'monthly', monthly_fresh, 'quarterly', quarterly_fresh,
        'department', department_fresh, 'supplier', supplier_fresh, 'customer', customer_fresh, 'ai', ai_fresh
      ) from public.report_kpis),
    'recent', (select coalesce(jsonb_agg(r), '[]'::jsonb) from (
        select id, source, report_type, title, period,
               case source when 'exec' then 'exec' when 'narrative' then 'board' else source end as src,
               to_char(created_at,'YYYY-MM-DD HH24:MI') as created
        from public.report_registry where created_at >= public.fn_os_fresh_start_at() order by created_at desc limit 25) r),
    'by_type', (select coalesce(jsonb_agg(t), '[]'::jsonb) from (
        select report_type, id, title,
               case source when 'exec' then 'exec' when 'narrative' then 'board' else source end as src,
               to_char(created_at,'YYYY-MM-DD HH24:MI') as created
        from (
          select distinct on (report_type) report_type, id, source, title, created_at
          from public.report_registry where created_at >= public.fn_os_fresh_start_at() order by report_type, created_at desc
        ) x order by report_type) t),
    -- WHO PRODUCES EACH TYPE, AND WHETHER IT IS RUNNING. A tile that shows only a last date reads
    -- as live; this says "paused" out loud when the cron behind a type is off. Keyed by report_type.
    'producers', (select coalesce(jsonb_object_agg(p.report_type, jsonb_build_object(
        'job', p.jobname, 'active', coalesce(j.active, false),
        'last_run', (select to_char(max(d.start_time),'YYYY-MM-DD HH24:MI') from cron.job_run_details d where d.jobid = j.jobid),
        'paused_reason', case when coalesce(j.active, false) then null
                              when j.jobid is null then 'no cron job named ' || p.jobname
                              else 'cron ' || p.jobname || ' is paused' end)), '{}'::jsonb)
      from (values ('daily','founder_brief_daily'), ('department','reporting_ai_daily'), ('supplier','reporting_ai_daily'),
                   ('customer','reporting_ai_daily'), ('ai','reporting_ai_daily'), ('weekly','board_report_weekly'),
                   ('monthly','monthly_report'), ('quarterly','quarterly_report'), ('finance','finance_ai_daily')) as p(report_type, jobname)
      left join cron.job j on j.jobname = p.jobname),
    'flags', (select coalesce(jsonb_agg(f), '[]'::jsonb) from (
        select title, risk, status, to_char(created_at,'YYYY-MM-DD') as created
        from public.agent_actions
        where agent='reporting_ai' and kind='report_task' and status in ('pending','needs_review')
        order by created_at desc) f)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_rfq_360(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare i public.inquiries%rowtype; j jsonb; docs jsonb := '[]'::jsonb; hired text;
begin
  select * into i from public.inquiries where id=p_id;
  if i.id is null then return jsonb_build_object('error','RFQ not found'); end if;
  if i.drawing_file_path is not null then docs := docs || jsonb_build_object('type','Drawing','name',coalesce(i.drawing_file_name,'drawing'),'path',i.drawing_file_path); end if;
  if i.drawing_redacted_paths is not null then
    docs := docs || coalesce((select jsonb_agg(jsonb_build_object('type','Drawing (redacted)','name','redacted','path',x)) from unnest(i.drawing_redacted_paths) x),'[]'::jsonb);
  end if;
  select company_name into hired from public.leads where id=i.hired_supplier_id;
  j := jsonb_build_object(
    'requirements', jsonb_build_object('category',i.category,'emirate',i.emirate,'role_needed',i.role_needed,
       'summary',i.summary,'spec',i.spec,'boq',i.boq,'boq_confidence',i.boq_confidence,'budget',i.budget,
       'scope_type',i.scope_type,'trades',i.trades,'keywords',i.keywords),
    'status', jsonb_build_object('status',i.status,'pipeline_stage',i.pipeline_stage,'deal_owner',i.deal_owner,
       'expected_value',i.expected_value,'outcome',i.outcome,'lost_reason',i.lost_reason,'completed_at',i.completed_at,
       'project_id',i.project_id,'created_at',i.created_at),
    'ai_qualification', jsonb_build_object('completeness',i.completeness,'rfq_ready',i.rfq_ready,'routing',i.routing,'brief_source',i.brief_source),
    'selected_supplier', case when i.hired_supplier_id is not null then jsonb_build_object('id',i.hired_supplier_id,'company_name',hired) else null end,
    'documents', docs,
    'matching', coalesce((select jsonb_agg(jsonb_build_object('supplier_id',m.supplier_id,'company_name',l.company_name,
       'similarity',m.similarity,'match_reason',m.match_reason,'sent_at',m.sent_at) order by m.similarity desc nulls last)
       from public.inquiry_matches m left join public.leads l on l.id=m.supplier_id where m.inquiry_id=p_id),'[]'::jsonb),
    'quotes', coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'supplier_id',q.supplier_id,'company_name',l.company_name,
       'amount',q.quote_amount,'status',q.status,'lead_time',q.lead_time,'validity',q.validity,'quality',q.quality,
       'created_at',q.created_at) order by q.quote_amount asc nulls last)
       from public.quotes q left join public.leads l on l.id=q.supplier_id where q.inquiry_id=p_id),'[]'::jsonb),
    'procurement', public.fn_procurement_analysis(p_id),
    'clarifications', coalesce((select jsonb_agg(jsonb_build_object('question',qn.question,'answer',qn.answer,
       'supplier_id',qn.supplier_id,'asked_at',qn.asked_at,'answered_at',qn.answered_at) order by qn.asked_at desc)
       from public.questions qn where qn.inquiry_id=p_id),'[]'::jsonb),
    'timeline', (select jsonb_agg(e order by e->>'at' desc) from (
        select jsonb_build_object('at',i.created_at,'event','RFQ created') e
        union all select jsonb_build_object('at',m.sent_at,'event','Matched supplier') from public.inquiry_matches m where m.inquiry_id=p_id and m.sent_at is not null
        union all select jsonb_build_object('at',q.created_at,'event','Quote received: AED '||coalesce(q.quote_amount::text,'?')) from public.quotes q where q.inquiry_id=p_id
        union all select jsonb_build_object('at',i.completed_at,'event','Completed'||coalesce(' ('||i.outcome||')','')) where i.completed_at is not null
      ) tl)
  );
  return j;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ws_strategy()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', (select to_jsonb(k) from public.strategy_kpis k),
    'risks', (select coalesce(jsonb_agg(r),'[]'::jsonb) from (
        select title, category, score, likelihood, impact, status
        from public.strategy_risks where status<>'closed' order by score desc limit 20) r),
    'recommendations', (select coalesce(jsonb_agg(x),'[]'::jsonb) from (
        select title, risk, to_char(created_at,'YYYY-MM-DD') as created
        from public.agent_actions where agent='strategy_ai' and kind='strategy_rec'
          and status in ('pending','needs_review') order by array_position(array['high','medium','low']::text[],risk)) x),
    'under_supplied', coalesce(fn_strategy_metrics()->'under_supplied','[]'::jsonb),
    'market_intel', (select coalesce(jsonb_agg(m),'[]'::jsonb) from (
        select kind, title, impact, status, coalesce(source,'—') as source
        from public.market_intel where status<>'dismissed' order by created_at desc limit 20) m),
    'recent_simulations', (select coalesce(jsonb_agg(s),'[]'::jsonb) from (
        select coalesce(nullif(scenario->>'question',''), nullif(scenario->>'title',''), nullif(scenario->>'type',''), 'Scenario #' || id) as title,
               (scenario->>'confidence')::numeric as confidence,
               to_char(created_at,'YYYY-MM-DD HH24:MI') as created
        from public.simulations order by created_at desc limit 8) s)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_supplier_360(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare l public.leads%rowtype; j jsonb; docs jsonb := '[]'::jsonb;
begin
  select * into l from public.leads where id=p_id;
  if l.id is null then return jsonb_build_object('error','supplier not found'); end if;

  -- documents from path fields
  if l.license_doc_path is not null then docs:=docs||jsonb_build_object('type','Trade licence','name',coalesce(l.license_doc_name,'licence'),'path',l.license_doc_path); end if;
  if l.egr_doc_path is not null then docs:=docs||jsonb_build_object('type','Establishment card','name',coalesce(l.egr_doc_name,'egr'),'path',l.egr_doc_path); end if;
  if l.insurance_doc_path is not null then docs:=docs||jsonb_build_object('type','Insurance','name','insurance','path',l.insurance_doc_path); end if;
  if l.vat_doc_path is not null then docs:=docs||jsonb_build_object('type','VAT certificate','name','vat','path',l.vat_doc_path); end if;
  if l.company_profile_doc_path is not null then docs:=docs||jsonb_build_object('type','Company profile','name','profile','path',l.company_profile_doc_path); end if;
  if l.signed_terms_path is not null then docs:=docs||jsonb_build_object('type','Signed terms','name','terms','path',l.signed_terms_path); end if;
  if l.catalog_doc_paths is not null then
    docs := docs || coalesce((select jsonb_agg(jsonb_build_object('type','Catalogue','name','catalogue','path',x))
                              from unnest(l.catalog_doc_paths) x),'[]'::jsonb);
  end if;

  j := jsonb_build_object(
    'profile', jsonb_build_object(
      'id', l.id, 'company_name', l.company_name, 'sector', l.sector, 'sub_type', l.sub_type,
      'emirate', l.emirate, 'city', l.city, 'phone', coalesce(l.phone_e164,l.phone), 'email', l.email,
      'website', l.website, 'contact_name', l.contact_name, 'founded_year', l.founded_year,
      'company_size', l.company_size, 'employee_count', l.employee_count, 'business_role', l.business_role,
      'lifecycle_stage', l.lifecycle_stage, 'claimed', l.claimed
    ),
    'status', jsonb_build_object(
      'approval_status', l.approval_status, 'verified', l.verified, 'verification_status', l.verification_status,
      'registration_status', l.registration_status, 'matching_blocked', l.matching_blocked,
      'matching_block_reason', l.matching_block_reason, 'banned', l.banned, 'banned_reason', l.banned_reason,
      'chat_strikes', l.chat_strikes
    ),
    'ai', jsonb_build_object(
      'capability_summary', l.capability_summary, 'capability_score', l.capability_score,
      'review_notes', l.ai_review_notes, 'review_flags', l.ai_review_flags, 'reviewed_at', l.ai_reviewed_at,
      'twin', coalesce((select to_jsonb(tw) from public.supplier_twin tw where tw.supplier_id=p_id),'{}'::jsonb)
    ),
    'compliance', jsonb_build_object(
      'trade_license_no', l.trade_license_no, 'license_authority', l.license_authority,
      'license_expiry', l.license_expiry, 'trn', l.trn, 'vat_number', l.vat_number,
      'insurance_expiry', l.insurance_expiry, 'iso_certifications', l.iso_certifications,
      'certifications', l.certifications, 'accepted_terms_at', l.accepted_terms_at,
      'registration_expires_at', l.registration_expires_at,
      'license_expiring', (l.license_expiry is not null and l.license_expiry < current_date + 30),
      'insurance_expiring', (l.insurance_expiry is not null and l.insurance_expiry < current_date + 30)
    ),
    'capabilities', jsonb_build_object(
      'brands_carried', l.brands_carried, 'machinery', l.machinery, 'engineers_count', l.engineers_count,
      'team_size', l.team_size, 'warehouse_area', l.warehouse_area, 'service_emirates', l.service_emirates,
      'manufacturer_authorizations', l.manufacturer_authorizations, 'client_references', l.client_references,
      'products', l.products, 'services', l.services,
      'detail', coalesce((select to_jsonb(c) from public.supplier_capabilities c where c.supplier_id=p_id),'{}'::jsonb)
    ),
    'performance', coalesce((select jsonb_build_object(
        'matched',pf.matched,'quoted',pf.quoted,'won',pf.won,'quote_rate',pf.quote_rate,
        'win_rate',pf.win_rate,'perf_score',pf.perf_score,'rating',pf.rating,'review_count',pf.review_count)
        from public.supplier_perf pf where pf.supplier_id=p_id),'{}'::jsonb)
      || jsonb_build_object('rv_reveals',l.rv_reveals,'rv_responded',l.rv_responded,'rv_response_rate',l.rv_response_rate,
                            'app_rating',l.app_rating,'app_reviews',l.app_reviews),
    'reputation', coalesce((select to_jsonb(rp) - 'supplier_id' - 'company_name' from public.supplier_reputation rp where rp.supplier_id=p_id),'{}'::jsonb),
    'financials', (
      select jsonb_build_object(
        'deals_count', count(*) filter (where t.id is not null),
        'deal_value_total', coalesce(sum(t.quote_amount),0),
        'reveal_fees_generated', coalesce(sum(t.reveal_fee) filter (where t.fee_status='paid'),0)
      ) from public.transactions t where t.supplier_id=p_id
    ) || (
      select jsonb_build_object(
        'commission_total', coalesce(sum(amount_due),0),
        'commission_paid', coalesce(sum(amount_due) filter (where status in ('paid','settled')),0),
        'commission_owed', coalesce(sum(amount_due) filter (where public.fn_supplier_due_is_owed(status, paid_at)),0)
      ) from public.supplier_dues where supplier_id=p_id
    ),
    'documents', docs,
    'quotes', coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'amount',q.quote_amount,'status',q.status,'created_at',q.created_at) order by q.created_at desc)
                        from (select * from public.quotes where supplier_id=p_id order by created_at desc limit 10) q),'[]'::jsonb),
    'reviews', coalesce((select jsonb_agg(jsonb_build_object('rating',r.rating,'comment',r.comment,'created_at',r.created_at) order by r.created_at desc)
                        from (select * from public.reviews where supplier_id=p_id order by created_at desc limit 8) r),'[]'::jsonb),
    'timeline', (select jsonb_agg(e order by e->>'at' desc) from (
        select jsonb_build_object('at',l.created_at,'event','Added to directory') e where l.created_at is not null
        union all select jsonb_build_object('at',l.registration_submitted_at,'event','Registration submitted') where l.registration_submitted_at is not null
        union all select jsonb_build_object('at',l.approved_at,'event','Approved'||coalesce(' by '||l.approval_decided_by,'')) where l.approved_at is not null
        union all select jsonb_build_object('at',l.accepted_terms_at,'event','Accepted terms') where l.accepted_terms_at is not null
      ) tl),
    -- WHY WE DECIDED WHAT WE DECIDED about this supplier. decision_record holds the reasoning behind
    -- past decisions and decision_trace the policies that were applied; neither reached the supplier
    -- view, so "why did we reject Supplier X?" had no answer on the screen that shows X.
    'rejection_reason', coalesce((select jsonb_agg(jsonb_build_object(
        'id', dr.id, 'problem', dr.problem, 'recommendation', dr.recommendation,
        'risks', dr.risks, 'status', dr.status, 'decided_by', dr.decided_by,
        'actual_outcome', dr.actual_outcome, 'at', dr.created_at) order by dr.created_at desc)
      from public.decision_record dr
      where coalesce(l.company_name,'') <> ''
        and (dr.problem ilike '%'||l.company_name||'%' or dr.context ilike '%'||l.company_name||'%')), '[]'::jsonb),
    'decision_trace', coalesce((select jsonb_agg(jsonb_build_object(
        'entity_id', dt.entity_id, 'policy_keys', dt.policy_keys) order by dt.entity_id)
      from public.decision_trace dt where dt.entity_id = p_id::text), '[]'::jsonb)
  );
  return j;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ws_suppliers(p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  v_q text := nullif(trim(coalesce(p->>'q','')),'');
  v_emirate text := nullif(p->>'emirate','');
  v_sector text := nullif(p->>'sector','');
  v_approval text := nullif(p->>'approval','');
  v_limit int := least(coalesce((p->>'limit')::int,50),100);
  v_offset int := greatest(coalesce((p->>'offset')::int,0),0);
  v_rows jsonb; v_total bigint;
begin
  select count(*) into v_total from leads
   where coalesce(source,'') <> 'canary'
     and (v_q is null or company_name ilike '%'||v_q||'%' or categories ilike '%'||v_q||'%')
     and (v_emirate is null or emirate=v_emirate)
     and (v_sector is null or sector=v_sector)
     and (v_approval is null or approval_status=v_approval);

  select coalesce(jsonb_agg(r),'[]'::jsonb) into v_rows from (
    select jsonb_build_object('id',id,'company_name',company_name,'sector',sector,'sub_type',sub_type,
      'emirate',emirate,'city',city,'rating',app_rating,'reviews',app_reviews,'categories',categories,
      'approval_status',approval_status,'lifecycle_stage',lifecycle_stage,'verified',verified,
      'verification_status',verification_status,'capability_score',capability_score,'invite_status',invite_status,
      'registration_status',registration_status,'license_expiry',license_expiry,'banned',banned,
      'matching_blocked',matching_blocked,'phone',phone,'website',website,'created_at',created_at) as r
    from leads
    where coalesce(source,'') <> 'canary'
      and (v_q is null or company_name ilike '%'||v_q||'%' or categories ilike '%'||v_q||'%')
      and (v_emirate is null or emirate=v_emirate)
      and (v_sector is null or sector=v_sector)
      and (v_approval is null or approval_status=v_approval)
    order by capability_score desc nulls last, app_reviews desc nulls last
    limit v_limit offset v_offset
  ) x;

  return jsonb_build_object(
    'kpis', jsonb_build_object(
      'total',(select count(*) from leads where coalesce(source,'') <> 'canary'),
      'approved',(select count(*) from leads where approval_status='approved'),
      'pending_review',(select count(*) from leads where coalesce(approval_status,'') in ('submitted','pending','under_review','pending_review')),
      'verified',(select count(*) from leads where verified is true),
      'registered',(select count(*) from leads where registration_paid_at is not null),
      'licenses_expiring',(select count(*) from leads where license_expiry is not null and license_expiry < (now()+interval '30 days')::date and license_expiry >= now()::date),
      'banned',(select count(*) from leads where banned is true),
      'matching_blocked',(select count(*) from leads where matching_blocked is true)
    ),
    'success', jsonb_build_object(
      'kpis', coalesce((select to_jsonb(k) from supplier_kpis k), '{}'::jsonb),
      'open_risk', (select count(*) from agent_actions where kind='supplier_risk' and status in ('pending','needs_review')),
      'attention', coalesce((select jsonb_agg(a) from (
          select jsonb_build_object('id',supplier_id,'company_name',company_name,'health',health,
            'quality',quality,'compliance',compliance,'response',response,'retention',retention,
            'risk_tier',risk_tier,'dormant',dormant) a
          from supplier_health where risk_tier in ('high','medium') order by health asc limit 10) t),'[]'::jsonb),
      'trend', coalesce((select jsonb_agg(jsonb_build_object('d',snapshot_date,'health',(kpis->>'avg_health')) order by snapshot_date)
          from (select snapshot_date, kpis from supplier_kpi_snapshots order by snapshot_date desc limit 14) s),'[]'::jsonb)
    ),
    'kanban', coalesce((select jsonb_agg(jsonb_build_object('key',stg,'count',c) order by c desc) from (
        select coalesce(nullif(lifecycle_stage,''),'directory') stg, count(*) c from leads where coalesce(source,'') <> 'canary' group by 1 order by 2 desc limit 8) k),'[]'::jsonb),
    'sectors', coalesce((select jsonb_agg(jsonb_build_object('key',s,'count',c) order by c desc) from (
        select coalesce(nullif(sector,''),'other') s, count(*) c from leads where coalesce(source,'') <> 'canary' group by 1 order by 2 desc limit 10) s),'[]'::jsonb),
    'emirates', coalesce((select jsonb_agg(jsonb_build_object('key',e,'count',c) order by c desc) from (
        select coalesce(nullif(emirate,''),'—') e, count(*) c from leads where coalesce(source,'') <> 'canary' group by 1 order by 2 desc limit 10) e),'[]'::jsonb),
    'total', v_total, 'limit', v_limit, 'offset', v_offset, 'rows', v_rows
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.funnel_metrics(days integer DEFAULT 30)
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with w as (select (now() - make_interval(days => days)) as since),
  ri as (select i.* from public.inquiries i, w where i.created_at >= w.since and not public.fn_inquiry_is_demo(i.id))
  select json_build_object(
    'days', days,
    'inquiries', (select count(*) from ri),
    'matched', (select count(distinct m.inquiry_id) from public.inquiry_matches m join ri i on i.id=m.inquiry_id),
    'quoted', (select count(distinct q.inquiry_id) from public.quotes q join ri i on i.id=q.inquiry_id),
    'revealed', (select count(*) from public.transactions t join ri i on i.id=t.inquiry_id where t.revealed_at is not null),
    'completed', (select count(*) from ri i where i.status='completed'),
    'cancelled', (select count(*) from ri i where i.status='cancelled'),
    'reveal_fees', (select coalesce(sum(t.reveal_fee),0) from public.transactions t join ri i on i.id=t.inquiry_id where t.revealed_at is not null)
  );
$function$


CREATE OR REPLACE FUNCTION public.is_disposable_email(p_email text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select exists (
    select 1 from app_blocked_domains d
    where d.domain = lower(split_part(p_email,'@',2))
  );
$function$


CREATE OR REPLACE FUNCTION public.kb_match(query_embedding vector, match_count integer DEFAULT 8, p_category text DEFAULT NULL::text)
 RETURNS TABLE(id bigint, category text, title text, citation text, content text, similarity double precision)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with want as (
    select nullif(regexp_replace(lower(p_category),'^cat:',''),'') as c
  ), cats as (
    select c as cat from want where c is not null
    union
    select a.maps_to from kb_category_aliases a, want w where a.category = w.c
  ), src as materialized (
    select k.id, k.category, k.title, k.citation, k.content, k.embedding_gte
    from public.kb_chunks k
    where k.embedding_gte is not null
      and ((select c from want) is null or k.category_norm in (select cat from cats))
  )
  select s.id, s.category, s.title, s.citation, s.content,
         1 - (s.embedding_gte <=> query_embedding) as similarity
  from src s
  order by s.embedding_gte <=> query_embedding
  limit match_count;
$function$


CREATE OR REPLACE FUNCTION public.kb_query(p_query text, p_category text DEFAULT NULL::text, p_limit integer DEFAULT 8)
 RETURNS TABLE(source_kind text, category text, title text, snippet text, citation text, effective_date date, rank real)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_lim int := greatest(1, least(coalesce(p_limit, 8), 25));
  v_tsq tsquery;
begin
  v_tsq := websearch_to_tsquery('english', coalesce(p_query, ''));

  -- A query of nothing, or of nothing but stop words, has no lexemes to match: websearch_to_tsquery
  -- returns an empty tsquery, which matches no row. Ranking is meaningless either way, so both land here.
  if coalesce(btrim(p_query), '') = '' or v_tsq::text = '' then
    return query
      select r.source_kind, r.category, r.title, r.snippet, r.citation, r.effective_date, r.rnk
        from (
          select c.source_kind, c.category, c.title, left(c.content, 700) as snippet, c.citation, c.effective_date,
                 0::real as rnk, c.id
            from public.kb_chunks c
           where p_category is null or c.category = p_category
           order by c.id desc
           limit v_lim
        ) r
       order by r.id desc;
    return;
  end if;

  return query
    select r.source_kind, r.category, r.title, r.snippet, r.citation, r.effective_date, r.rnk
      from (
        select c.source_kind, c.category, c.title, left(c.content, 700) as snippet, c.citation, c.effective_date,
               (ts_rank(c.fts, v_tsq)
                + case when p_category is not null and c.category = p_category then 0.4 else 0 end)::real as rnk
          from public.kb_chunks c
         where c.fts @@ v_tsq
      ) r
     order by r.rnk desc nulls last, r.effective_date desc nulls last
     limit v_lim;
end
$function$


CREATE OR REPLACE FUNCTION public.kb_sync()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n int;
begin
  delete from kb_chunks where source_kind in ('regulation','trade','material');
  insert into kb_chunks(source_kind,source_id,category,title,content,citation,effective_date)
  select 'regulation', r.id::text, cat, r.title,
    coalesce(r.summary,'') || case when jsonb_array_length(coalesce(r.key_requirements,'[]'::jsonb))>0
      then E'\nKey requirements: ' || (select string_agg(x, '; ') from jsonb_array_elements_text(r.key_requirements) x) else '' end,
    r.authority || ' — ' || r.title || coalesce(' [' || r.source_url || ']','') || coalesce(' (effective ' || r.effective_date::text || ')',''),
    r.effective_date
  from regulations r
  left join lateral unnest(case when array_length(r.categories,1) is null then array[null::text] else r.categories end) as cat on true
  where r.status = 'active' and r.approved_at is not null;
  insert into kb_chunks(source_kind,source_id,category,title,content,citation,effective_date)
  select 'trade', ak.id::text, ak.agent_key, ak.topic, ak.content,
    'QuotesDone trade knowledge: ' || coalesce(ak.agent_key,'') || ' / ' || coalesce(ak.topic,''), null
  from agent_knowledge ak;
  insert into kb_chunks(source_kind,source_id,category,title,content,citation,effective_date)
  select 'material', m.id::text, m.category, m.item,
    m.item || ' — ' || coalesce(m.properties::text,'') ||
      case when array_length(m.standards,1) is not null then E'\nStandards: ' || array_to_string(m.standards,', ') else '' end ||
      case when m.price_band is not null then E'\nPrice band: ' || m.price_band else '' end,
    'QuotesDone material library: ' || m.item, null
  from materials m;
  select count(*) into n from kb_chunks;
  return jsonb_build_object('chunks', n);
end $function$


CREATE OR REPLACE FUNCTION public.kn_task(p_sig text, p_cond boolean, p_risk text, p_title text, p_reco text, p_assumptions jsonb DEFAULT NULL::jsonb, p_impact text DEFAULT NULL::text, p_cost text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if p_cond then
    if not exists (select 1 from agent_actions where kind='knowledge_task' and detail->>'signal'=p_sig and status in ('pending','needs_review')) then
      insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id,assumptions,expected_impact,cost)
      values ('knowledge_curator','knowledge_task','pending',p_risk,p_title,p_reco,jsonb_build_object('signal',p_sig),'knowledge',p_sig,p_assumptions,p_impact,p_cost);
    end if;
  else
    update agent_actions
       set status='resolved', decided_at=now(), decided_by='knowledge_curator (auto-resolved)'
     where kind='knowledge_task' and detail->>'signal'=p_sig and status in ('pending','needs_review');
  end if;
end $function$


CREATE OR REPLACE FUNCTION public.margin_rate(amount numeric)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case
    when amount < 2000  then 0.10
    when amount < 5000  then 0.08
    when amount < 10000 then 0.06
    when amount < 20000 then 0.05
    when amount < 50000 then 0.04
    else 0.03 end
$function$


CREATE OR REPLACE FUNCTION public.mask_contacts(t text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s text := t;
begin
  if s is null or s = '' then return s; end if;
  -- emails
  s := regexp_replace(s, '[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}', '[hidden]', 'gi');
  -- explicit URLs
  s := regexp_replace(s, '(https?://|www\.)[^[:space:]]+', '[hidden]', 'gi');
  -- bare social / messenger short links (no scheme)
  s := regexp_replace(s, '(wa\.me|t\.me|bit\.ly|instagram\.com|facebook\.com|fb\.com|linkedin\.com|twitter\.com|x\.com)/[^[:space:]]*', '[hidden]', 'gi');
  -- international UAE numbers (+971 ...)
  s := regexp_replace(s, '\+?971[ \-]?[0-9][0-9 \-]{6,}[0-9]', '[hidden]', 'g');
  -- local UAE mobile  05x xxx xxxx  (9 digits starting 5, optional separators) — bounded so prices/qtys are safe
  s := regexp_replace(s, '\y0?5[0-9][ \-]?[0-9]{3}[ \-]?[0-9]{4}\y', '[hidden]', 'g');
  return s;
end;
$function$


CREATE OR REPLACE FUNCTION public.mask_contacts_jsonb(j jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r jsonb; k text; v jsonb; e jsonb;
begin
  if j is null then return j; end if;
  case jsonb_typeof(j)
    when 'string' then
      return to_jsonb(public.mask_contacts(j #>> '{}'));
    when 'object' then
      r := '{}'::jsonb;
      for k, v in select key, value from jsonb_each(j) loop
        r := r || jsonb_build_object(k, public.mask_contacts_jsonb(v));
      end loop;
      return r;
    when 'array' then
      r := '[]'::jsonb;
      for e in select value from jsonb_array_elements(j) loop
        r := r || jsonb_build_array(public.mask_contacts_jsonb(e));
      end loop;
      return r;
    else
      return j;
  end case;
end;
$function$


CREATE OR REPLACE FUNCTION public.mask_name(t text, nm text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s text := t; part text;
begin
  if s is null or s = '' or nm is null or btrim(nm) = '' then return s; end if;
  s := regexp_replace(s, '\y' || regexp_replace(btrim(nm), '([.^$*+?()\[\]{}|\\-])', '\\\1', 'g') || '\y', '[hidden]', 'gi');
  for part in select unnest(regexp_split_to_array(btrim(nm), '\s+')) loop
    if length(part) >= 3 then
      s := regexp_replace(s, '\y' || regexp_replace(part, '([.^$*+?()\[\]{}|\\-])', '\\\1', 'g') || '\y', '[hidden]', 'gi');
    end if;
  end loop;
  return s;
end;
$function$


CREATE OR REPLACE FUNCTION public.mask_project_identity(t text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s text := t;
begin
  if s is null or s = '' then return s; end if;

  -- 1. LABELLED FIELDS. A title block labels its own secrets, in every format and every CAD
  --    template: "PROJECT:", "CLIENT:", "CONSULTANT:", "LOCATION:". The label is the reliable
  --    signal — far more reliable than trying to recognise the value — so the value after it is
  --    removed to end of line. This is what makes the rule format-independent, which is the
  --    founder's own requirement ("no matter what format it is").
  s := regexp_replace(s,
    '(?in)^[[:space:]]*(project|client|employer|owner|developer|consultant|architect|engineer|'
    || 'main[[:space:]]+contractor|contractor|sub[- ]?contractor|designer|surveyor|site|location|'
    || 'address|plot|building|tower|villa|community|district|drawing[[:space:]]*(no|number)?|'
    || 'dwg[[:space:]]*(no|number)?|sheet|makani|title|prepared[[:space:]]+by|issued[[:space:]]+to|'
    || 'checked[[:space:]]+by|approved[[:space:]]+by|drawn[[:space:]]+by)[[:space:]]*[:#][^\n]*',
    '[hidden]', 'g');

  -- Same labels appearing mid-line ("... | DRAWING No: AH-2024-A-102 | REV: C"), bounded to the
  -- segment so the rest of a sentence survives.
  --
  -- THE PEOPLE LABELS ARE IN THIS LIST BECAUSE THE FIRST VERSION MISSED THEM. Run over the real
  -- drawing, everything above was correctly hidden and this line came through untouched:
  --     DATE: 12/03/2024 | DRAWN BY: R. Fernandes | APPROVED: Eng. S. Malik
  -- The line-start rule did not fire because the line starts with DATE:, and the mid-line rule did
  -- not carry "drawn by" or "approved". Two named individuals — the draughtsman and the approving
  -- engineer — survived into the supplier-facing copy. A person's name is identity as surely as the
  -- consultant firm's is, and it is the kind of thing that identifies a project to anyone in the
  -- trade. Every label that can be followed by a person or a firm now appears in BOTH rules.
  s := regexp_replace(s,
    '(?i)(project|client|employer|consultant|architect|engineer|developer|owner|contractor|'
    || 'designer|surveyor|location|address|plot|building|tower|villa|community|makani|'
    || 'drawing[[:space:]]*no|dwg[[:space:]]*no|sheet[[:space:]]*no|'
    || 'drawn[[:space:]]+by|checked[[:space:]]+by|approved[[:space:]]+by|prepared[[:space:]]+by|'
    || 'reviewed[[:space:]]+by|issued[[:space:]]+to|approved|verified[[:space:]]+by)'
    || '[[:space:]]*[:#][[:space:]]*[^|\n]{1,80}', '[hidden]', 'g');

  -- 2. IDENTIFIERS WITH A SHAPE.
  --    Makani is Dubai's 10-digit address code, written 1234-56789 or as ten digits.
  s := regexp_replace(s, '(?i)\ymakani[[:space:]]*[:#]?[[:space:]]*[0-9]{4}[[:space:]-]?[0-9]{5,6}\y', '[hidden]', 'g');
  --    Plot / parcel numbers: "Plot 234-11", "Parcel 345-6789".
  s := regexp_replace(s, '(?i)\y(plot|parcel|land)[[:space:]]*(no\.?|number|#)?[[:space:]]*[0-9]{1,6}(-[0-9]{1,6})*\y', '[hidden]', 'g');
  --    Drawing / sheet numbers: "AH-2024-A-102", "DWG-01-A-203". Two or more hyphen-joined groups
  --    with at least one letter group, so a plain measurement or a date is not caught.
  s := regexp_replace(s, '\y[A-Z]{1,4}-[A-Z0-9]{1,6}-[A-Z0-9]{1,6}(-[A-Z0-9]{1,6})*\y', '[hidden]', 'g');

  -- 3. COMPANY NAMES BY THEIR SUFFIX. A UAE entity almost always announces itself: L.L.C, LLC,
  --    FZE, FZ-LLC, DMCC, Est., Trading, Contracting, Consultants, Consulting Engineers. Capture
  --    the run of capitalised words immediately before the suffix, which is the name itself.
  s := regexp_replace(s,
    '(?i)\y([A-Z][A-Za-z&''.\-]*[[:space:]]+){1,6}'
    || '(l\.?l\.?c\.?|llc|fz[- ]?llc|fze|fzco|dmcc|est\.?|establishment|trading|general[[:space:]]+trading|'
    || 'contracting|contractors?|consultants?|consulting[[:space:]]+engineers?|engineering[[:space:]]+consultants?|'
    || 'architects?|technical[[:space:]]+services|building[[:space:]]+materials)\y',
    '[hidden]', 'g');

  return s;
end $function$


CREATE OR REPLACE FUNCTION public.mask_project_identity_jsonb(j jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if j is null then return j; end if;
  case jsonb_typeof(j)
    when 'string' then return to_jsonb(public.mask_project_identity(j #>> '{}'));
    when 'array'  then return (select coalesce(jsonb_agg(public.mask_project_identity_jsonb(e)), '[]'::jsonb)
                                 from jsonb_array_elements(j) e);
    when 'object' then return (select coalesce(jsonb_object_agg(k, public.mask_project_identity_jsonb(v)), '{}'::jsonb)
                                 from jsonb_each(j) as t(k, v));
    else return j;
  end case;
end $function$


CREATE OR REPLACE FUNCTION public.pdpl_cancel_me(p_request uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_em text := public.fn_pdpl_my_verified_email();
begin
  if v_em is null or not exists (select 1 from public.pdpl_requests where id = p_request and email = v_em) then
    return jsonb_build_object('ok', false, 'code', 'not_yours');
  end if;
  return public.fn_pdpl_cancel(p_request, 'self_service');
end $function$


CREATE OR REPLACE FUNCTION public.pdpl_confirm_me(p_request uuid, p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_em text := public.fn_pdpl_my_verified_email();
begin
  if v_em is null or not exists (select 1 from public.pdpl_requests where id = p_request and email = v_em and kind = 'delete') then
    return jsonb_build_object('ok', false, 'code', 'not_yours');
  end if;
  return public.fn_pdpl_verify(p_request, p_code, 'self_service');
end $function$


CREATE OR REPLACE FUNCTION public.pdpl_request_me(p_kind text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_em text := public.fn_pdpl_my_verified_email(); v_id uuid;
begin
  if v_em is null then
    return jsonb_build_object('ok', false, 'code', 'email_not_verified',
      'message', 'Verify your email address in your account first.', 'message_ar', 'يُرجى توثيق بريدكم الإلكتروني في حسابكم أولًا.');
  end if;
  if p_kind not in ('export', 'delete') then return jsonb_build_object('ok', false, 'code', 'bad_kind'); end if;
  -- ERASE NEEDS A SECOND VERIFIED ACTION: a code is emailed and the clock starts only at pdpl_confirm_me.
  if p_kind = 'delete' then
    return public.fn_pdpl_open(v_em, 'delete', 'self_service') || jsonb_build_object('next', 'pdpl_confirm_me(request_id, code)');
  end if;
  insert into public.pdpl_requests (kind, email, role, details, status, verified_via, verified_at, handled_by)
  values (p_kind, v_em, 'self_service', 'signed-in, email verified by code', 'received', 'session+email_verified', now(), 'self_service')
  returning id into v_id;
  return public.fn_pdpl_carry_out(v_id);
end $function$


CREATE OR REPLACE FUNCTION public.pdpl_status_me()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with me as (select public.fn_pdpl_my_verified_email() as em)
  select case when (select em from me) is null
    then jsonb_build_object('ok', false, 'code', 'email_not_verified')
    else jsonb_build_object('ok', true, 'requests', coalesce((
      select jsonb_agg(jsonb_build_object(
               'request_id', q.id, 'kind', q.kind, 'status', q.status, 'created_at', q.created_at,
               'confirm_after', q.confirm_after,
               'deferred', coalesce(q.outcome -> 'deferred', '[]'::jsonb),
               'held', q.outcome -> 'held') order by q.created_at desc)
        from public.pdpl_requests q, me
       where q.email = me.em and q.status in ('received', 'cooling_off', 'held')), '[]'::jsonb))
  end;
$function$


CREATE OR REPLACE FUNCTION public.qd_project_ref()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_ref text;
begin
  select value into v_ref from app_secrets where key = 'project_ref';
  if v_ref is null then
    select substring(command from 'https://([a-z]+)[.]supabase[.]co') into v_ref
      from cron.job where command like '%supabase.co/functions/v1/%' limit 1;
  end if;
  if v_ref is null then
    raise exception 'qd_project_ref: cannot determine the Supabase project ref. Set app_secrets.project_ref.';
  end if;
  return v_ref;
end $function$


CREATE OR REPLACE FUNCTION public.qd_sign_customer()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_secret text; v_ref text;
begin
  select value into v_secret from app_secrets where key='cred_db_internal';
  -- Resolved defensively: a trigger on the Terms-acceptance path must never refuse the signature.
  begin
    v_ref := public.qd_project_ref();
  exception when others then
    v_ref := null;
  end;
  if v_ref is not null then
    perform net.http_post(
      'https://' || v_ref || '.supabase.co/functions/v1/compliance_archive',
      jsonb_build_object('__secret', v_secret, 'action','sign','kind','customer','email', NEW.email),
      '{}'::jsonb, '{"Content-Type":"application/json"}'::jsonb, 60000);
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.qd_sign_supplier()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_secret text; v_ref text;
begin
  select value into v_secret from app_secrets where key='cred_db_internal';
  -- Resolved defensively: a trigger on the Terms-acceptance path must never refuse the signature.
  begin
    v_ref := public.qd_project_ref();
  exception when others then
    v_ref := null;
  end;
  if v_ref is not null then
    perform net.http_post(
      'https://' || v_ref || '.supabase.co/functions/v1/compliance_archive',
      jsonb_build_object('__secret', v_secret, 'action','sign','kind','supplier','email', NEW.claimed_by),
      '{}'::jsonb, '{"Content-Type":"application/json"}'::jsonb, 60000);
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.recompute_supplier_rating(p_supplier bigint)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'public'
AS $function$
  update public.leads l set
    app_rating  = (select round(avg(rating)::numeric, 2) from public.reviews r where r.supplier_id = p_supplier),
    app_reviews = (select count(*)::int from public.reviews r where r.supplier_id = p_supplier)
  where l.id = p_supplier;
$function$


CREATE OR REPLACE FUNCTION public.registered_supplier_count()
 RETURNS integer
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select coalesce(max(founding_rank), 0)::int from public.leads
$function$


CREATE OR REPLACE FUNCTION public.reveal_fee(amount numeric, at_time timestamp with time zone DEFAULT now())
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  -- 6 Sep 2026: no discount, no promo, no cap (founder). at_time is kept so callers need no change;
  -- it no longer selects a rate because there is only one rate.
  select case when amount is null or amount <= 0 then 0
              else round(amount * (select c.standard_reveal_rate from public.pricing_config c where c.id = 1), 2)
         end
$function$


CREATE OR REPLACE FUNCTION public.rl_check(p_key text, p_limit integer, p_seconds integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n int;
begin
  delete from rl_hits where at < now() - (p_seconds || ' seconds')::interval and k = p_key;
  select count(*) into n from rl_hits where k = p_key and at > now() - (p_seconds || ' seconds')::interval;
  if n >= p_limit then return false; end if;
  insert into rl_hits(k) values (p_key);
  return true;
end $function$


CREATE OR REPLACE FUNCTION public.scrub_inquiry_contacts()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare changed boolean := false; v_name text; v_spec jsonb;
begin
  new.summary_masked      := public.mask_project_identity(public.mask_contacts(new.summary));
  new.raw_input_masked    := public.mask_project_identity(public.mask_contacts(new.raw_input));
  new.budget_masked       := public.mask_project_identity(public.mask_contacts(new.budget));
  v_spec                  := public.mask_project_identity_jsonb(public.mask_contacts_jsonb(new.spec));
  -- Suppliers read English only (ledger 993): a spec value in Arabic script never reaches the supplier copy. Its
  -- English reaches them on the held note (fn_inquiry_add_missing_specs, surface sales_engineer.supplier_english).
  new.spec_masked         := case when jsonb_typeof(v_spec) = 'object'
                               then coalesce((select jsonb_object_agg(s.key, s.value) from jsonb_each(v_spec) s
                                               where s.value::text !~ '[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻾]'), '{}'::jsonb)
                               else v_spec end;
  new.boq_masked          := public.mask_project_identity_jsonb(public.mask_contacts_jsonb(new.boq));
  new.completeness_masked := public.mask_project_identity_jsonb(public.mask_contacts_jsonb(new.completeness));

  if new.customer_id is not null then
    begin
      select nullif(btrim(c.full_name), '') into v_name from public.customers c where c.id = new.customer_id;
    exception when others then v_name := null; end;
    if v_name is not null then
      new.summary_masked   := public.mask_name(new.summary_masked, v_name);
      new.raw_input_masked := public.mask_name(new.raw_input_masked, v_name);
      new.budget_masked    := public.mask_name(new.budget_masked, v_name);
    end if;
  end if;

  -- The alert is about contacts and project identity; dropping an Arabic value is not a masking event.
  changed := (new.summary_masked is distinct from new.summary)
          or (new.raw_input_masked is distinct from new.raw_input)
          or (new.budget_masked is distinct from new.budget)
          or (v_spec is distinct from new.spec)
          or (new.boq_masked is distinct from new.boq)
          or (new.completeness_masked is distinct from new.completeness);
  if changed then
    begin
      insert into public.founder_alerts(level, event, detail, channel)
      values ('warn', 'inquiry_contact_masked',
        'Masked customer contact details and/or project identity (consultant, client, building, '
        || 'location, plot, drawing numbers) in the supplier-facing copy of inquiry '
        || coalesce(new.id::text, '?') || ' from customer ' || coalesce(new.customer_id::text, '?') || '.',
        'system');
    exception when others then null; end;
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.scrub_quote_contacts()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare changed boolean := false;
begin
  if new.notes         is distinct from public.mask_contacts(new.notes)         then new.notes         := public.mask_contacts(new.notes);         changed := true; end if;
  if new.scope         is distinct from public.mask_contacts(new.scope)         then new.scope         := public.mask_contacts(new.scope);         changed := true; end if;
  if new.conditions    is distinct from public.mask_contacts(new.conditions)    then new.conditions    := public.mask_contacts(new.conditions);    changed := true; end if;
  if new.exclusions    is distinct from public.mask_contacts(new.exclusions)    then new.exclusions    := public.mask_contacts(new.exclusions);    changed := true; end if;
  if new.payment_terms is distinct from public.mask_contacts(new.payment_terms) then new.payment_terms := public.mask_contacts(new.payment_terms); changed := true; end if;
  if new.warranty      is distinct from public.mask_contacts(new.warranty)      then new.warranty      := public.mask_contacts(new.warranty);      changed := true; end if;
  if new.lead_time     is distinct from public.mask_contacts(new.lead_time)     then new.lead_time     := public.mask_contacts(new.lead_time);     changed := true; end if;
  if new.validity      is distinct from public.mask_contacts(new.validity)      then new.validity      := public.mask_contacts(new.validity);      changed := true; end if;
  if changed then
    begin
      insert into public.founder_alerts(level, event, detail, channel)
      values ('warn', 'quote_contact_masked',
              'Masked off-platform contact details in quote for inquiry '||coalesce(new.inquiry_id::text,'?')||' from supplier '||coalesce(new.supplier_id::text,'?')||'.',
              'system');
    exception when others then null; end;
  end if;
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.trg_accountant_issued_document_is_append_only()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  raise exception 'accountant_issued_document is the audit trail of what was signed in the founder''s name: rows are never changed or deleted';
end $function$


CREATE OR REPLACE FUNCTION public.trg_agent_knowledge_metadata()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare v_days int; begin
  v_days := public.fn_knowledge_review_days(NEW.agent_key, NEW.layer, NEW.topic);
  -- source_ref, confidence, owner_agent and supporting_evidence are deliberately NOT set here.
  -- They belong after trg_knowledge_provenance_stamp has had its chance to derive a real citation;
  -- setting them here is what stopped it running at all. See the header.
  if NEW.validation_status is null then NEW.validation_status := 'unvalidated'; end if;
  if TG_OP = 'INSERT' then
    if NEW.review_due  is null then NEW.review_due  := (now() + (v_days     || ' days')::interval)::date; end if;
    if NEW.valid_until is null then NEW.valid_until := (now() + (v_days * 2 || ' days')::interval)::date; end if;
  elsif NEW.content is distinct from OLD.content then
    -- a refresh that changed the content moves the review date, unless the writer set one itself
    if NEW.review_due is not distinct from OLD.review_due then
      NEW.review_due := (now() + (v_days || ' days')::interval)::date;
    end if;
    if NEW.validation_status = 'stale' and OLD.validation_status = 'stale' then NEW.validation_status := 'unvalidated'; end if;
  end if;
  return NEW;
end
$function$


CREATE OR REPLACE FUNCTION public.trg_ai_cost_attribute()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare m record;
begin
  if new.dept_key is null or new.agent_key is null then
    -- 1. the hand-maintained override, unchanged and still first.
    select * into m from ai_cost_fn_map where fn = new.fn;
    if found then
      new.dept_key  := coalesce(new.dept_key,  m.dept_key);
      new.agent_key := coalesce(new.agent_key, m.agent_key);
    end if;

    -- 2. what the ROUTER would have used. fn_ai_route attributes an un-departmented call from
    --    this exact table; until now the log did not, so the ceiling and the ledger disagreed.
    if new.dept_key is null then
      select t.dept_key into new.dept_key
        from fn_task_class t
       where t.fn = new.fn and t.active and t.dept_key is not null
       limit 1;
    end if;

    -- 3. the employee's own department, when the call names one.
    if new.dept_key is null and new.agent_key is not null then
      select a.department into new.dept_key
        from org_agents a
       where a.agent_key = new.agent_key and a.department is not null
       limit 1;
    end if;

    -- 4. the executor that owns this edge function.
    if new.dept_key is null then
      select e.department into new.dept_key
        from org_action_executor e
       where e.target = new.fn and e.department is not null
       limit 1;
    end if;
  end if;

  -- CANONICAL ON THE WAY IN. Whatever source supplied it, an absorbed key is stored as the
  -- department that absorbed it, so the ten budget rows are the only vocabulary the ledger uses.
  if new.dept_key is not null then
    new.dept_key := coalesce(public.fn_dept_canonical(new.dept_key), new.dept_key);
  end if;

  return new;
-- The swallow is deliberate and pre-existing: attribution must never cost a cost-log row. A
-- rising unattributed share is caught by the invariant test rather than by an exception here.
exception when others then return new;
end $function$


CREATE OR REPLACE FUNCTION public.trg_ai_cost_log_review_family()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_fam text; v_hit text;
begin
  if new.counterpart_model is null then
    new.counterpart_model := substring(coalesce(new.model_selected_because, '') from 'counterpart_model=([^ |]+)');
  end if;
  if coalesce(new.model_used, 'none') = 'none'
     or not exists (select 1 from public.model_policy p
                     where p.task_class = new.task_class and cardinality(coalesce(p.reviews_class, '{}')) > 0) then
    return new;
  end if;
  if new.counterpart_model is null then
    new.review_violation := 'REVIEW_WITHOUT_COUNTERPART: ' || new.task_class || ' ran on ' || new.model_used || ' naming no author model';
    return new;
  end if;
  select lower(btrim(provider)) into v_fam from public.model_registry where model_id = new.model_used;
  select string_agg(x, ',') into v_hit
    from unnest(string_to_array(new.counterpart_model, ',')) x
    join public.model_registry r on r.model_id = btrim(x)
   where lower(btrim(r.provider)) = v_fam;
  if v_hit is not null then
    new.review_violation := 'SAME_FAMILY_REVIEW: ' || new.task_class || ' ran on ' || new.model_used || ' over ' || v_hit;
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.trg_ai_cost_log_reviewer_tier()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.reviewer_tier is null then
    new.reviewer_tier := substring(coalesce(new.model_selected_because, '') from 'reviewer_tier=([a-z_]+)');
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.trg_audit_agent_run()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  insert into os_audit_log (actor, action, entity, entity_id, detail, ok, err)
  values (
    coalesce(new.agent,'unknown_agent'),
    'agent_run',
    'agent_runs',
    new.id::text,
    jsonb_strip_nulls(jsonb_build_object(
      'status',  new.status,
      'counts',  new.counts,
      'note',    left(coalesce(new.note,''), 600),
      'started', new.started_at,
      'seconds', case when new.finished_at is not null and new.started_at is not null
                      then round(extract(epoch from (new.finished_at - new.started_at))::numeric, 2)
                      else null end)),
    coalesce(new.status,'ok') <> 'error',
    case when new.status = 'error' then left(coalesce(new.note,'error'), 400) else null end
  );
  return new;
exception when others then
  return new;   -- audit must never break the work it is recording
end $function$


CREATE OR REPLACE FUNCTION public.trg_backup_refile_only_it_engineer_closes()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.kind = 'handoff' and new.detail->>'type' in ('backup.refile', 'backup.remediate')
     and new.status = 'done' and old.status is distinct from 'done'
     and coalesce(current_setting('qd.backup_closer', true), '') <> 'it_engineer' then
    raise exception 'only the it_engineer closes a backup handoff (% %), after verifying every file itself', new.detail->>'type', new.id;
  end if;
  -- An allowed close is recorded: which routine closed it and as which session user (review of #628).
  if new.kind = 'handoff' and new.detail->>'type' in ('backup.refile', 'backup.remediate')
     and new.status = 'done' and old.status is distinct from 'done' then
    new.detail := coalesce(new.detail, '{}'::jsonb) || jsonb_build_object('closed_by', jsonb_build_object(
      'seat', current_setting('qd.backup_closer', true),
      'routine', nullif(current_setting('qd.backup_closer_routine', true), ''),
      'session_user', session_user::text, 'at', now()));
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.trg_block_banned_inquiry()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_banned boolean;
begin
  select banned into v_banned from customers where id = NEW.customer_id;
  if coalesce(v_banned, false) then
    raise exception 'Your account has been paused due to repeated cancelled requests. Please contact support@quotesdone.com to restore it.';
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_case_memory_campaign()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  perform public.fn_case_from_campaign(new, case when tg_op = 'UPDATE' then old end);
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.trg_case_memory_ceo_approval()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  perform public.fn_case_from_ceo_approval(new, case when tg_op = 'UPDATE' then old end);
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.trg_case_memory_ceo_decision_log()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  perform public.fn_case_from_ceo_decision_log(new, case when tg_op = 'UPDATE' then old end);
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.trg_case_memory_complaint()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  perform public.fn_case_from_complaint(new, case when tg_op = 'UPDATE' then old end);
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.trg_case_memory_decision_record()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  perform public.fn_case_from_decision_record(new, case when tg_op = 'UPDATE' then old end);
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.trg_case_memory_expense()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  perform public.fn_case_from_expense(new, case when tg_op = 'UPDATE' then old end);
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.trg_case_memory_inquiry()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  perform public.fn_case_from_inquiry(new, case when tg_op = 'UPDATE' then old end);
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.trg_case_memory_it_finding()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  perform public.fn_case_from_it_finding(new, case when tg_op = 'UPDATE' then old end);
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.trg_case_memory_refund_case()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  perform public.fn_case_from_refund_case(new, case when tg_op = 'UPDATE' then old end);
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.trg_case_memory_social_reply()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  perform public.fn_case_from_social_reply(new, case when tg_op = 'UPDATE' then old end);
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.trg_case_memory_spec_offer()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  perform public.fn_case_from_spec_offer(new, case when tg_op = 'UPDATE' then old end);
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.trg_case_memory_support_case()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  perform public.fn_case_from_support_case(new, case when tg_op = 'UPDATE' then old end);
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.trg_category_key_asked()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  perform public.fn_category_key_ask(NEW.category);
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_ceo_approval_carries_its_reasons()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_problem text := public.fn_ceo_reasons_problem(new.rationale);
begin
  if v_problem is not null then
    raise exception using errcode = 'check_violation',
      message = 'REASONLESS_DECISION: a CEO ' || new.decision || ' of ' || new.subject_kind || ' ' || new.subject_id || ' says why: ' || v_problem;
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.trg_ceo_decision_round_append_only()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  raise exception using errcode = 'check_violation',
    message = 'ceo_decision_round ' || old.id || ' is history: a decision is followed by the next round, never edited or deleted';
end $function$


CREATE OR REPLACE FUNCTION public.trg_ceo_decision_round_follows_through()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare h record;
begin
  for h in select a.id from public.agent_actions a
            where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' = 'ceo.revise'
              and a.detail->>'item_key' = new.item_key
              and not ((a.detail->>'generation')::int = new.generation and (a.detail->>'round')::int = new.round) loop
    perform set_config('qd.handoff_closer', 'ceo', true);
    perform public.fn_seat_handoff_complete(h.id, jsonb_build_object('verified_by', 'ceo', 'next_round_id', new.id,
      'next_decision', new.decision, 'generation', new.generation, 'round', new.round));
    perform set_config('qd.handoff_closer', '', true);
  end loop;
  -- an owed decision is answered here and closed by the seat that owed it (z61), after it re-verifies
  update public.agent_actions a
     set detail = a.detail || jsonb_build_object(
           'ceo_decided', jsonb_build_object('decided_by', 'ceo', 'decision', new.decision, 'round_id', new.id,
                                             'reasons', left(new.reasons, 2000)),
           'awaiting', coalesce(a.detail->>'from', 'the originating seat') || ' re-verifies the CEO''s decision')
   where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' = 'ceo.decision_owed'
     and a.detail->>'item_key' = new.item_key;
  if new.decision in ('approved', 'replaced', 'withdrawn') then
    -- the return: the seat's handler (fn_seat_takes_the_ceo_decision) re-verifies and closes what it owed
    perform public.fn_seat_handoff('ceo', new.originator_seat, 'ceo.decision_closed', 'ceo_decision_round', new.id::text,
      jsonb_build_object('round_id', new.id, 'path', new.path, 'item_key', new.item_key, 'decision', new.decision,
                         'reasons', left(new.reasons, 3000), 'generation', new.generation, 'round', new.round,
                         'version', new.version, 'source_table', new.source_table, 'source_id', new.source_id));
  elsif new.decision = 'rejected' then
    -- the return is the ceo.revise fn_ceo_decide opened for this round; the seat re-verifies against the ledger
    perform public.fn_seat_verifies_the_ceo_decision_it_owed(new.originator_seat, new.item_key);
  end if;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.trg_ceo_decision_round_rules()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n jsonb; v_problem text;
begin
  perform pg_advisory_xact_lock(hashtext('ceo_decision_round:' || new.item_key));
  if new.originator_seat = 'ceo' or not exists (select 1 from public.org_role r where r.role_id = new.originator_seat and r.status = 'active') then
    raise exception using errcode = 'check_violation',
      message = 'CEO_DECISION: ' || coalesce(new.originator_seat, '?') || ' is not an active seat other than the CEO; the ledger holds the CEO''s decisions on a seat''s work';
  end if;
  v_problem := public.fn_ceo_reasons_problem(new.reasons);
  if v_problem is not null then
    raise exception using errcode = 'check_violation',
      message = 'REASONLESS_DECISION: every CEO decision carries its reasons (' || new.decision || ' on ' || new.item_key || '): ' || v_problem;
  end if;
  n := public.fn_ceo_decision_next(new.item_key);
  if n->>'path' is not null and n->>'path' <> new.path then
    raise exception using errcode = 'check_violation', message = 'CEO_DECISION: ' || new.item_key || ' is a ' || (n->>'path') || ' item, not ' || new.path;
  end if;
  if not (n->>'open')::boolean then
    raise exception using errcode = 'check_violation',
      message = 'ITEM_CLOSED: ' || new.item_key || ' was ' || (n->>'last_decision') || ' in round ' || (n->>'last_round') || '; a new submission is a new item';
  end if;
  new.generation := (n->>'generation')::int;
  new.round := (n->>'round')::int;
  if new.decision = 'rejected' and (n->>'rejections')::int >= 4 then
    raise exception using errcode = 'check_violation',
      message = 'ROUND_LIMIT: ' || new.item_key || ' has been sent back 4 times; the CEO now approves it, or replaces or withdraws it with reasons';
  end if;
  new.decided_by := 'ceo'; new.decided_at := now();
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.trg_ceo_experiment_carries_its_reasons()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_problem text;
begin
  if (old.status = 'proposed' and new.status <> 'proposed')
     or (new.approval is distinct from old.approval and new.approval ? 'decision'
         and new.approval->'decision' is distinct from old.approval->'decision') then
    v_problem := public.fn_ceo_reasons_problem(coalesce(new.approval->>'reasons', new.approval->>'reasoning'));
  elsif new.status in ('kept', 'killed') and old.status is distinct from new.status then
    v_problem := public.fn_ceo_reasons_problem((select v.reasoning from public.ceo_experiment_verdict v
                                                 where v.experiment_id = new.id and v.decided_at is not null
                                                 order by v.decided_at desc limit 1));
  end if;
  if v_problem is not null then
    raise exception using errcode = 'check_violation',
      message = 'REASONLESS_DECISION: the CEO''s decision on experiment ' || new.id || ' (' || old.status || ' -> ' || new.status || ') says why: ' || v_problem;
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.trg_ceo_improvement_carries_its_reasons()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_problem text;
begin
  if new.status = 'dropped' and (tg_op = 'INSERT' or old.status is distinct from 'dropped') then
    v_problem := public.fn_ceo_reasons_problem(new.done_evidence);
    if v_problem is not null then
      raise exception using errcode = 'check_violation',
        message = 'REASONLESS_DECISION: the CEO drops improvement ' || coalesce(new.id::text, '(new)') || ' only with reasons: ' || v_problem;
    end if;
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.trg_ceo_turn_carries_its_reasons()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d public.seat_deliberation; v_reasons text; v_problem text;
begin
  if new.phase <> 'compare' or new.status <> 'recorded' then return new; end if;
  select * into d from public.seat_deliberation where id = new.deliberation_id;
  if d.reviewer_seat is distinct from 'ceo' or d.kind = 'marketing.monthly_plan' then return new; end if;
  v_reasons := btrim(coalesce(case when lower(new.verdict) = 'approve' then new.agreements else new.disagreements end, ''));
  if public.fn_ceo_reasons_problem(v_reasons) is not null and coalesce(btrim(new.output->>'reasoning'), '') <> '' then
    v_reasons := btrim(v_reasons || E'\n' || (new.output->>'reasoning'));
  end if;
  v_problem := public.fn_ceo_reasons_problem(v_reasons);
  if v_problem is not null then
    raise exception using errcode = 'check_violation',
      message = 'REASONLESS_DECISION: the CEO''s ' || coalesce(new.verdict, '(no verdict)') || ' on deliberation ' || new.deliberation_id || ' says why: ' || v_problem;
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.trg_ceo_weekly_report_learning()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v jsonb; v_txt text;
begin
  if coalesce(new.body, '') like '%THE SEATS, LEARNING%' then return new; end if;
  v := public.fn_seat_learning_trend(new.week_end);
  select string_agg(format('  %-17s accuracy %s (a week earlier %s, four weeks earlier %s); %s judgements and %s outcomes this week; %s lesson(s) approved, %s pending',
           k, coalesce(round((x->>'accuracy_now')::numeric * 100) || '%', 'not yet measurable'),
           coalesce(round((x->>'accuracy_week_ago')::numeric * 100) || '%', '-'),
           coalesce(round((x->>'accuracy_4w_ago')::numeric * 100) || '%', '-'),
           x->>'judgements_week', x->>'outcomes_week', x->>'lessons_approved_week', x->>'lessons_pending'), E'\n' order by k)
    into v_txt from jsonb_each(v) t(k, x);
  new.body := coalesce(new.body, '') || E'\n\n' || 'THE SEATS, LEARNING' || E'\n' || coalesce(v_txt, '  no seat has a measured judgement yet') || E'\n' ||
              '  Accuracy is the share of judgements whose real outcome proved them right, over the trailing 30 days.';
  new.figures := coalesce(new.figures, '{}'::jsonb) || jsonb_build_object('learning', v);
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.trg_company_event_dispatch()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  begin
    -- 20, not 1. See the header: at 1 this delivered only events stamped within the last sixty
    -- seconds, which was 4% of them, and everything else fell through to the 15-minute cron.
    perform public.fn_event_dispatch(20);
  exception when others then
    insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
    values ('event_dispatch_trigger', now(), now(), 'error',
      jsonb_build_object('sqlstate', sqlstate),
      'Inline dispatch from the company_event trigger failed: '||left(sqlerrm, 300)
      ||'. The event is stored and event_dispatch_15min will deliver it on the next tick.');
  end;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.trg_decision_closes_unanswered_holds()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.revealed_at is null or NEW.inquiry_id is null then return NEW; end if;
  if TG_OP = 'UPDATE' and OLD.revealed_at is not null then return NEW; end if;
  perform public.fn_quote_holds_close_at_decision(NEW.inquiry_id);
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_declog_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin raise exception 'decision_log is append-only'; end $function$


CREATE OR REPLACE FUNCTION public.trg_department_budget_keeps_a_ceiling_per_caller()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  -- PER-DEPARTMENT, NOT "IS THE TABLE EMPTY" (corrected 23 Sep 2026 in review). The first draft
  -- fired only at count(*) <= 1, so five of the six ceilings could be deleted one at a time and the
  -- guard would say nothing: marketplace — 77% of every call the estate has ever routed — could lose
  -- its ceiling in silence as long as `it` still had a row. The table being non-empty was never the
  -- property worth protecting. The property is that EVERY DEPARTMENT A CALLER ROUTES TO still
  -- resolves to a ceiling, which is exactly the lookup fn_ai_route performs.
  if tg_op = 'TRUNCATE' then
    if exists (select 1 from model_policy where active and tier <> 'none') then
      raise exception
        'TRUNCATE on department_budget would remove every spending ceiling at once while % active '
        'model_policy row(s) still route to a model. fn_ai_route finds its degrade and halt branches '
        'by the PRESENCE of a row here, so an empty table is an estate with no ceiling at all - the '
        'state measured on 23 Sep 2026. Deactivate the policies first, or replace the rows in the '
        'same transaction (a_ceiling_exists_before_the_door_is_opened.sql shows the arithmetic).',
        (select count(*) from model_policy where active and tier <> 'none')
        using errcode = '23514';
    end if;
  elsif exists (select 1 from model_policy where active and tier <> 'none')
    and exists (select 1 from fn_task_class t
                 where t.active and t.dept_key is not null
                   and public.fn_dept_canonical(t.dept_key) = old.dept_key)
  then
    raise exception
      'deleting the "%" ceiling would leave % active fn_task_class row(s) routing to a department '
      'with no budget, so fn_ai_route could neither degrade nor halt them. Per-department on purpose: '
      '"the table is not empty" was never the property - every department a caller routes to must '
      'resolve to a ceiling. Repoint or deactivate those rows first, or replace this one in the same '
      'transaction.',
      old.dept_key,
      (select count(*) from fn_task_class t
        where t.active and t.dept_key is not null
          and public.fn_dept_canonical(t.dept_key) = old.dept_key)
      using errcode = '23514';
  end if;
  -- OLD only exists on the row-level DELETE; touching it in the statement-level TRUNCATE trigger
  -- would raise on an unassigned record, so the level is tested rather than the operation.
  if tg_level = 'ROW' then return old; end if;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.trg_doc_backups_admit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tag text := nullif(btrim(coalesce(current_setting('qd.backup_sandbox', true), '')), '');
  v_root text := '/QuotesDone Backup';
  v_kp text := '';                -- the dedupe-key prefix of the rows this one is filed beside
  v_sandbox boolean := false;
  v_id text; v_cust text; v_inq8 text; v_inq text; v_anchor text;
  v_uuid constant text := '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$';
begin
  new.dropbox_path := public.fn_dbx_path(new.dropbox_path);
  -- A rehearsal's documents are never queued: its fixtures are torn down minutes later, and a queued
  -- row could never drain (a_rehearsal_never_queues_a_backup.sql). A row a probe inserts as 'zz_demo'
  -- itself is still admitted. 7 Oct 2026: an inquiry of a demo customer is demo too.
  if new.entity is distinct from 'zz_demo' and (
       coalesce(new.dropbox_path, '') ~* 'zz[ _-]?demo' or coalesce(new.path, '') ~* 'zz[ _-]?demo'
       or (new.entity = 'supplier' and exists (select 1 from public.leads l where l.id::text = new.entity_id and l.is_demo))
       or (new.entity = 'customer' and exists (select 1 from public.customers c where c.id::text = new.entity_id and c.is_demo))
       or (new.entity = 'inquiry' and new.entity_id ~ v_uuid and exists (
             select 1 from public.inquiries i join public.customers c on c.id = i.customer_id
              where i.id = new.entity_id::uuid and c.is_demo))) then
    -- A TAGGED SANDBOX RUN (fn_backup_sandbox_enqueue sets qd.backup_sandbox for its own transaction)
    -- admits the demo documents that carry its tag, re-rooted under _sandbox/<tag>/; every other demo
    -- row is dropped exactly as before.
    if v_tag is null or v_tag !~ '^[A-Za-z0-9-]{6,40}$'
       or position(lower(v_tag) in lower(coalesce(new.dropbox_path, '') || ' ' || coalesce(new.path, ''))) = 0
       or coalesce(new.dropbox_path, '') !~ '^/QuotesDone Backup/' then
      return null;
    end if;
    v_sandbox := true;
    v_kp := 'SBX:' || v_tag || ':';
    v_root := '/QuotesDone Backup/_sandbox/' || v_tag;
    new.dropbox_path := v_root || substr(new.dropbox_path, length('/QuotesDone Backup') + 1);
    new.dedupe_key := v_kp || coalesce(new.dedupe_key, '');
  end if;

  -- ONE FOLDER PER ENTITY. The first file of a supplier, a customer or a request decides its folder
  -- (the Company Details, Customer Details and Inquiry Summary rows are queued for every entity and
  -- never re-queued); every later file is filed beside it, whatever the name, category or status reads
  -- now. Each anchor is one lookup on the unique dedupe key.
  v_id := substring(new.dropbox_path from '^' || v_root || '/Suppliers/[^/]+/[^/]* \((\d+)\)/');
  if v_id is not null then
    select substring(d.dropbox_path from '^(' || v_root || '/Suppliers/[^/]+/[^/]* \(' || v_id || '\)/)') into v_anchor
      from public.doc_backups d where d.dedupe_key = v_kp || 'S:' || v_id || ':details';
    -- 12 Oct 2026 (review): a first folder opened before the name was known reads 'Supplier (<id>)'
    -- (fn_enqueue_doc_backups writes coalesce(company_name, 'Supplier')); it never wins over the name.
    if v_anchor is not null and v_anchor !~ ('/Supplier \(' || v_id || '\)/$') then
      new.dropbox_path := v_anchor || substring(new.dropbox_path from '^' || v_root || '/Suppliers/[^/]+/[^/]* \(' || v_id || '\)/(.*)$');
    end if;
  elsif new.dropbox_path ~ ('^' || v_root || '/Customers/[^/]+/') then
    v_cust := case
      when new.entity = 'customer' then new.entity_id
      when new.entity = 'inquiry' and new.entity_id ~ v_uuid then
        (select i.customer_id::text from public.inquiries i where i.id = new.entity_id::uuid) end;
    if v_cust is not null then
      -- 12 Oct 2026 (review): the CUSTOMER folder is the NAMED one. A customer whose first file was filed
      -- before the name was saved sits in 'Customer (<id8>)' (coalesce(full_name, 'Customer')); anchoring
      -- on that put every later file there and lost the name. The first folder wins only when it carries
      -- a name; otherwise the current name does. (Files already in a 'Customer (<id8>)' folder are refiled
      -- under the name by scripts/it/dropbox_tree_repair.ts, held for the founder's OK.)
      select substring(d.dropbox_path from '^(' || v_root || '/Customers/[^/]+/)') into v_anchor
        from public.doc_backups d where d.dedupe_key = v_kp || 'C:' || v_cust || ':details';
      if v_anchor is not null and v_anchor !~ '/Customer \([0-9a-f]{8}\)/$' then
        new.dropbox_path := v_anchor || substring(new.dropbox_path from '^' || v_root || '/Customers/[^/]+/(.*)$');
      end if;
      v_inq8 := substring(new.dropbox_path from '^' || v_root || '/Customers/[^/]+/Inquiries/\d{4}-\d{2}-\d{2} ([0-9a-f]{8})[^/]*/');
      if v_inq8 is not null and v_cust ~ v_uuid then
        v_inq := case when new.entity = 'inquiry' then new.entity_id else
          (select i.id::text from public.inquiries i
            where i.customer_id = v_cust::uuid and left(i.id::text, 8) = v_inq8 order by i.created_at limit 1) end;
        v_anchor := null;
        -- the request's own subfolder (date, id, first status) comes from its first file; the customer
        -- folder above it is the one decided just above (the named one)
        select substring(d.dropbox_path from '^' || v_root || '/Customers/[^/]+/Inquiries/([^/]+)/') into v_anchor
          from public.doc_backups d where d.dedupe_key = v_kp || 'I:' || v_inq || ':summary';
        if v_anchor is not null then
          new.dropbox_path := substring(new.dropbox_path from '^(' || v_root || '/Customers/[^/]+/Inquiries/)') || v_anchor || '/'
            || substring(new.dropbox_path from '^' || v_root || '/Customers/[^/]+/Inquiries/[^/]+/(.*)$');
        end if;
      end if;
    end if;
  end if;

  if new.source = 'storage' and new.status = 'pending'
     and not exists (select 1 from storage.objects o where o.bucket_id = new.bucket and o.name = new.path) then
    new.status := 'waiting_source';
    new.error := left('waiting: storage holds no object at ' || coalesce(new.bucket, '?') || '/' || coalesce(new.path, '?'), 300);
  end if;
  if v_sandbox then
    new.entity_id := new.entity || ':' || new.entity_id;
    new.entity := 'zz_demo';
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.trg_document_landed_kicks_backup()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  begin
    perform public.fn_backup_kick('document_landed:' || tg_table_name, 'enqueue');
  exception when others then
    insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
    values ('backup_kick', 'error', jsonb_build_object('table', tg_table_name, 'stage', 'trigger'),
            left('The document-landed kick failed on ' || tg_table_name || ': ' || sqlerrm, 500), now(), now());
  end;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.trg_goal_cascade()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  -- (A) DECOMPOSE ON SET/EDIT. A measurable, active goal owned by an active department hands down its
  -- department objective immediately, instead of waiting for the weekly fn_goal_decompose cron.
  if new.active and coalesce(new.measure_sql,'') <> ''
     and exists (select 1 from org_departments d where d.dept_key = new.owner_dept and d.active) then
    if exists (select 1 from department_objective
                where dept_key = new.owner_dept and goal_key = new.key and active) then
      update department_objective
         set target_value = coalesce(target_value, new.target_value),
             unit         = coalesce(unit,         new.unit),
             measure_sql  = coalesce(measure_sql,  new.measure_sql),
             updated_at   = now()
       where dept_key = new.owner_dept and goal_key = new.key and active
         and (measure_sql is null or target_value is null or unit is null);
    else
      insert into department_objective
        (dept_key, objective, horizon, goal_key, target_value, unit, measure_sql, status, active)
      values
        (new.owner_dept, new.goal, coalesce(new.horizon,'year_1'), new.key,
         new.target_value, new.unit, new.measure_sql, 'active', true);
    end if;
  end if;

  if old.active is true and new.active is false then
    -- (1) KEPT. An objective serving a retired goal is superseded.
    update department_objective
       set status='superseded', updated_at=now()
     where goal_key = new.key and status='active';

    -- (2) The re-plan is NO LONGER a direct org_tasks insert here (K31 removed that bypass). It now
    -- runs through the kernel: goal.retired (emitted below) starts a run of the runtime workflow
    -- goal_retirement_replan (public.workflow), whose steps are accountable to
    -- corporate_performance_director. Restored as work with a run, a step, an owner and a trace.

    -- (3) goal.retired now travels. It was calling the TRIGGER function fn_emit_event() with five
    -- positional args, which raised and was swallowed, so nothing was emitted. fn_emit writes
    -- company_event, which fn_workflow_start_due reads to start the re-plan workflow.
    begin
      perform public.fn_emit('goal.retired', 'company_goals', new.key, 'ceo',
                             jsonb_build_object('goal', new.key, 'title', new.goal, 'owner_dept', new.owner_dept));
    exception when others then null; end;
  end if;
  return new;
end
$function$


CREATE OR REPLACE FUNCTION public.trg_handoff_carries_its_note()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  new.detail := coalesce(new.detail, '{}'::jsonb) || jsonb_build_object('summary',
    public.fn_handoff_summary(new.detail, new.agent, new.target_table, new.target_id,
                              new.title, new.recommendation, new.id));
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.trg_handoff_only_originator_closes()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_closer text;
begin
  if new.kind = 'handoff' and new.status = 'done' and old.status is distinct from 'done'
     and exists (select 1 from public.seat_handoff_kind k
                  where k.type = new.detail->>'type' and k.from_seat = new.detail->>'from' and k.originator_closes) then
    v_closer := coalesce(nullif(current_setting('qd.handoff_closer', true), ''),
                         nullif(current_setting('qd.backup_closer', true), ''));
    if v_closer is distinct from new.detail->>'from' then
      raise exception 'handoff % (%) is closed only by its originator %, after it re-verifies; % tried to close it',
        new.id, new.detail->>'type', new.detail->>'from', coalesce(v_closer, 'an unnamed caller');
    end if;
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.trg_health_check_agent_threshold()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_total   int;
  v_failed  int;
  v_rate    numeric;
  v_limit   numeric := coalesce(
    (select nullif(value,'')::numeric from app_secrets where key='agent_failure_rate_limit'), 0.10);
begin
  if new.check_kind is distinct from 'agent_runs' then
    return new;
  end if;

  select count(*),
         count(*) filter (where status not in ('ok','success','completed','skipped','warn'))
    into v_total, v_failed
  from agent_runs
  where started_at > now() - interval '1 hour';

  -- No runs at all in an hour is itself a failure: the company has gone quiet.
  if v_total = 0 then
    new.ok := false;
    new.detail := 'NO agent runs at all in the last hour - the company has gone silent, which is worse than a high failure rate.';
    return new;
  end if;

  v_rate := round(v_failed::numeric / v_total, 4);
  new.ok := (v_rate < v_limit);
  new.detail := v_failed || ' of ' || v_total || ' agent runs failed in the last hour ('
             || round(v_rate * 100, 2) || '%); threshold ' || round(v_limit * 100, 2) || '%'
             || case when new.ok then '' else ' - OVER THRESHOLD' end
             || '. [Recomputed by trg_health_check_agent_threshold; the raw producer sets ok=false on any single failure, which can never be true.]';
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.trg_high_stakes_campaign_approved()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.approved_at is not null and old.approved_at is null and not new.is_demo then
    perform public.fn_high_stakes_campaign_review(new.id);
  end if;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.trg_high_stakes_review()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d public.seat_deliberation;
begin
  if new.phase <> 'compare' or new.status <> 'recorded' then return null; end if;
  select * into d from public.seat_deliberation where id = new.deliberation_id and kind like 'high_stakes.%';
  if d.id is null then return null; end if;
  if new.verdict <> 'approve' and d.proceeded_at is not null then
    -- The decision already went ahead: the deciding seat gets a finding, and its judgement learns the disagreement.
    perform public.fn_it_engineer_finding_upsert('high_stakes_disagreement:' || d.id,
      'The ' || d.reviewer_seat || ' seat disagrees with a ' || substr(d.kind, 13) || ' decision that already went ahead',
      d.author_seat || ' ' || substr(d.kind, 13) || ' on ' || d.subject_table || ' ' || d.subject_id, 'agent_facing', 1,
      jsonb_build_object('owner_seat', d.author_seat, 'deliberation_id', d.id, 'verdict', new.verdict,
                         'disagreements', left(new.disagreements, 2000), 'reviewer_model', new.model, 'proceeded_at', d.proceeded_at),
      '{}', '{}', d.reviewer_seat);
    perform public.fn_outcome_record(d.subject_table, d.subject_id, 'challenge_disagreed', false,
      d.reviewer_seat || ' (' || new.model || '): ' || left(new.disagreements, 800), d.author_seat, substr(d.kind, 13), null);
  elsif new.verdict = 'approve' and d.proceeded_at is null and d.kind = 'high_stakes.pricing_change' and d.subject_table = 'ceo_review' then
    -- A pricing proposal that waited for the accountant reaches the founder now.
    perform public.fn_ceo_review_tells_founder(split_part(d.subject_id, ':', 1), split_part(d.subject_id, ':', 2)::date,
      'CEO pricing proposal (evidence-based) for the week of ' || split_part(d.subject_id, ':', 2),
      coalesce(d.proposal->>'founder_detail', '') || E'\n\nThe accountant agreed on a model of another family (seat_deliberation ' || d.id || ').',
      'founder_brief');
  elsif new.verdict = 'approve' and d.proceeded_at is null and d.kind = 'high_stakes.refund' and d.subject_table = 'refunds' then
    -- A CEO-approved refund that fn_refund_decide left at awaiting_second_seat is decided again now that the second
    -- seat agreed (review of #1064). fn_refund_decide re-reads the CEO approval and the refund's status, so a refund
    -- decided in the meantime answers not_decidable and nothing moves. A failure never undoes the review: it is recorded
    -- for the CEO, who holds every refund approval.
    declare v_by text; v_res jsonb;
    begin
      select a.decided_by into v_by from public.ceo_approval a
       where a.subject_kind = 'refund' and a.subject_id = d.subject_id and a.decision = 'approved' and a.superseded_by is null
       order by a.decision_id desc limit 1;
      if v_by is not null then
        v_res := public.fn_refund_decide(d.subject_id::bigint, true, v_by,
                   'The ' || d.reviewer_seat || ' seat agreed on another family (seat_deliberation ' || d.id || ').');
        if not coalesce((v_res->>'ok')::boolean, false) and v_res->>'error' is distinct from 'not_decidable' then
          raise exception 'fn_refund_decide answered %', v_res;
        end if;
      end if;
    exception when others then
      perform public.fn_it_engineer_finding_upsert('high_stakes_refund_rerun:' || d.id,
        'A refund the second seat agreed to could not be decided again', 'ceo refund on refunds ' || d.subject_id, 'agent_facing', 1,
        jsonb_build_object('owner_seat', 'ceo', 'deliberation_id', d.id, 'refund_id', d.subject_id, 'error', left(sqlerrm, 500)),
        '{}', '{}', 'it_engineer');
    end;
  end if;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.trg_hold_answered_resets_the_run()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if OLD.state in ('open', 'awaiting_approval') and NEW.state in ('released', 'superseded') and NEW.supplier_id is not null then
    perform public.fn_supplier_collaboration_cooperated(NEW.supplier_id, NEW.quote_id, NEW.id);
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_inbound_supplier_reply()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_box text;
begin
  v_box := lower(btrim(coalesce((select value from public.app_secrets where key = 'email_reply_supplier'), '')));
  if v_box like '%@mail.quotesdone.com' and position(v_box in lower(coalesce(new.to_email, ''))) > 0 then
    new.needs_review := true;
  end if;
  return new;
end
$function$


CREATE OR REPLACE FUNCTION public.trg_ingest_case_lessons()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare les text; key text; n int := 0;
begin
  if NEW.ai_summary is null or jsonb_typeof(NEW.ai_summary->'lessons') <> 'array' then return NEW; end if;
  key := coalesce(public.fn_resolve_cat_agent(NEW.category), '_global');
  for les in select jsonb_array_elements_text(NEW.ai_summary->'lessons') loop
    les := trim(les);
    if length(les) < 12 then continue; end if;
    if not exists (select 1 from agent_knowledge where agent_key=key and content=les) then
      insert into agent_knowledge(agent_key, topic, content, priority)
      values (key, 'Closed-case lesson (RFQ-'||NEW.rfq_id||')', les, 60);
      n := n + 1;
    end if;
  end loop;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_inquiry_answer_value_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
begin
  if tg_op = 'DELETE' then
    if coalesce(current_setting('quotesdone.p2c1_teardown', true), '') = 'approved' then
      return old;
    end if;
    raise exception 'inquiry_answer rows are never deleted (id %)', old.id
      using hint = 'Supersede the answer instead. The chain is the history.';
  end if;
  if new.value       is distinct from old.value
     or new.field_id    is distinct from old.field_id
     or new.group_id    is distinct from old.group_id
     or new.precedence  is distinct from old.precedence
     or new.source_kind is distinct from old.source_kind then
    raise exception 'inquiry_answer % is immutable; supersede it instead of editing it', old.id;
  end if;
  if old.superseded_by is not null and new.superseded_by is distinct from old.superseded_by then
    raise exception 'inquiry_answer % is already superseded by %', old.id, old.superseded_by;
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.trg_inquiry_enrich()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare dup int; v_prev_id uuid; v_sim real;
  -- REPEAT_SIMILARITY: pg_trgm similarity() of the two summaries at or above which a differently worded request from
  -- the same customer, in the same category, within 30 minutes, is flagged possible_duplicate. 0.5 = half the
  -- trigrams shared; a flag only marks the inquiry for review, it never merges or drops one.
  c_repeat_similarity constant real := 0.5;
begin
  if NEW.urgency is null and NEW.spec is not null and (NEW.spec ? 'urgency') then NEW.urgency := NEW.spec->>'urgency'; end if;
  if NEW.plausibility is null and NEW.spec is not null and (NEW.spec ? 'plausibility') then NEW.plausibility := NEW.spec->'plausibility'; end if;
  if NEW.provenance is null and NEW.spec is not null and (NEW.spec ? 'provenance') then NEW.provenance := NEW.spec->'provenance'; end if;

  -- REMEMBERED PREFERENCE. Only fills a GAP — an emirate the customer stated on this RFQ always
  -- wins. `stated` beats `inferred`, and consent is re-checked on the read as well as the write.
  if NEW.emirate is null and NEW.customer_id is not null then
    select coalesce(p.preferences->'stated'->'emirates'->>0,
                    p.preferences->'inferred'->'emirates'->>0)
      into NEW.emirate
      from customer_preference p
      join customers c on c.id = p.customer_id
     -- Consent is read from customers.tos_accepted_at, where it actually lives, not from the copy
     -- on the preference row. A stale copy would keep a withdrawn profile readable.
     where p.customer_id = NEW.customer_id and c.tos_accepted_at is not null;
  end if;

  -- A REPEAT REQUEST. The very same summary is the same request (identity). A differently worded one is flagged
  -- by trigram similarity (model_policy duplicate_detection: SQL + pg_trgm, tier none; 24 Sep 2026), no question filed.
  select count(*) into dup from inquiries i
    where i.customer_id = NEW.customer_id and i.created_at > now() - interval '30 minutes'
      and coalesce(i.category,'') = coalesce(NEW.category,'')
      and i.summary = NEW.summary;
  if dup > 0 then
    NEW.plausibility := coalesce(NEW.plausibility, '{}'::jsonb) || jsonb_build_object('possible_duplicate', true);
  elsif btrim(coalesce(NEW.summary, '')) <> '' then
    select i.id, public.similarity(i.summary, NEW.summary) into v_prev_id, v_sim from inquiries i
     where i.customer_id = NEW.customer_id and i.created_at > now() - interval '30 minutes'
       and coalesce(i.category,'') = coalesce(NEW.category,'')
       and btrim(coalesce(i.summary, '')) <> '' and i.id is distinct from NEW.id
     order by public.similarity(i.summary, NEW.summary) desc, i.created_at desc limit 1;
    if v_prev_id is not null and v_sim >= c_repeat_similarity then
      NEW.plausibility := coalesce(NEW.plausibility, '{}'::jsonb) || jsonb_build_object('possible_duplicate', true,
        'duplicate_of', v_prev_id, 'duplicate_by', 'trigram', 'similarity', round(v_sim::numeric, 3));
    end if;
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_inquiry_split_needs_the_customers_choice()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_scope text;
begin
  if tg_op = 'UPDATE' and new.parent_inquiry_id is null and old.scope_type = 'multi'
     and new.scope_type is distinct from 'multi'
     and exists (select 1 from public.inquiries c where c.parent_inquiry_id = new.id) then
    raise exception 'inquiry %: its per-trade parts exist, so the customer''s choice to split cannot be rewritten (ruling 1021)', new.id
      using errcode = 'P0001';
  end if;
  if new.parent_inquiry_id is not null
     and (tg_op = 'INSERT' or new.parent_inquiry_id is distinct from old.parent_inquiry_id) then
    select p.scope_type into v_scope from public.inquiries p where p.id = new.parent_inquiry_id;
    if v_scope is distinct from 'multi' then
      raise exception 'inquiry %: a request is split into trade packages only when the customer chose it; the parent''s recorded choice is %, not multi (ruling 1021: the default is one contractor)',
        new.parent_inquiry_id, coalesce(v_scope, 'none') using errcode = 'P0001';
    end if;
  end if;
  return new;
end
$function$


CREATE OR REPLACE FUNCTION public.trg_invite_cap_allocation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_old numeric; v_new numeric;
begin
  if new.key <> 'invite_daily_cap' then return new; end if;

  -- A non-numeric or absent value is not a reallocation; nothing is recorded rather than guessed.
  begin
    v_old := nullif(btrim(coalesce(old.value, '')), '')::numeric;
    v_new := nullif(btrim(coalesce(new.value, '')), '')::numeric;
  exception when others then
    return new;
  end;
  if v_old is null or v_new is null then return new; end if;

  -- A move to the same number moved nothing. s23-reallocation-policy-cited counts a no-op as a
  -- finding, correctly, so one is never written.
  if v_old is not distinct from v_new then return new; end if;

  insert into public.allocation_change (resource, subject, from_value, to_value, reason, policy)
  values ('supplier_onboarding_capacity', 'invite_daily_cap', v_old, v_new,
          case when v_new > v_old
               then 'Daily supplier-invite capacity raised from ' || v_old || ' to ' || v_new
                    || '. Deliverability is inside tolerance, so more onboarding capacity is released.'
               else 'Daily supplier-invite capacity reduced from ' || v_old || ' to ' || v_new
                    || '. Deliverability is outside tolerance or the campaign restarted cold, so onboarding capacity is withdrawn to '
                    || 'protect the sending domain.' end,
          'invite warm-up (app_secrets.invite_warmup): capacity follows the 48-hour bounce and complaint rates, '
          || 'growing x1.5 at most once per send day, floored at the base cap and ceilinged at the configured ceiling');
  return new;
end
$function$


CREATE OR REPLACE FUNCTION public.trg_invite_lane_since()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if lower(btrim(coalesce(new.value, ''))) = 'true'
     and (tg_op = 'INSERT' or lower(btrim(coalesce(old.value, ''))) is distinct from 'true') then
    insert into public.app_secrets (key, value) values ('invite_lane_since', now()::text)
    on conflict (key) do update set value = excluded.value, updated_at = now();
  end if;
  return new;
end
$function$


CREATE OR REPLACE FUNCTION public.trg_it_judge_routine_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_rev text; v_objects jsonb;
begin
  begin
    v_rev := substring(coalesce(new.application_name, '') from '^qd-apply ([0-9a-f]{7,40}) ');
    if v_rev is not null then
      insert into public.it_change_revision (rev) values (v_rev) on conflict (rev) do nothing;
    elsif not exists (select 1 from public.it_change_source s
                       where (s.match_on = 'session_user' and new.session_user_name ~ s.pattern)
                          or (s.match_on = 'application_name' and coalesce(new.application_name, '') ~ s.pattern)) then
      select jsonb_agg(distinct c.command_tag || ' ' || c.object_identity) into v_objects
        from public.routine_change_log c where c.txid = new.txid;
      perform public.fn_it_engineer_finding_upsert(
        'duty:unsigned_change:tx' || new.txid,
        'A routine change was made outside the reviewed path: ' || jsonb_array_length(v_objects) || ' routine(s) changed by '
          || coalesce(nullif(new.application_name, ''), 'an unnamed session') || ' as ' || new.session_user_name,
        'public.routine_change_log', 'security', 1,
        jsonb_build_object('duty', 'unsigned_change', 'owner_seat', 'ceo', 'subject', 'routine_change_log',
          'txid', new.txid, 'application_name', new.application_name, 'session_user', new.session_user_name,
          'client_addr', host(new.client_addr), 'at', new.at, 'objects', v_objects,
          'close', 'Re-apply each routine with node scripts/apply_sql.mjs from a reviewed revision, or the ceo or the founder accepts it with public.fn_it_change_accept(txid, who, why).'),
        '{}'::text[], '{}'::text[], 'it_engineer.unsigned_change');
    end if;
  exception when others then
    begin
      insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
      values ('it_engineer', 'error', now(), now(), jsonb_build_object('job', 'unsigned_change_guard', 'log_id', new.id),
              left('The unsigned-change guard could not judge routine_change_log ' || new.id || ': ' || sqlerrm, 500));
    exception when others then null;
    end;
  end;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.trg_judgement_outcome()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  n jsonb := to_jsonb(new);
  o jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) else '{}'::jsonb end;
  changed boolean;
  v_prev public.target_verdict; v_median numeric; v_seat text; v_fail boolean; v_ok boolean;
begin
  begin
    if tg_table_name = 'quotes' then
      -- A quote won or lost at reveal (sales_engineer matched it).
      if n->>'status' is distinct from o->>'status' then
        if n->>'status' in ('revealed','won','accepted') then
          perform public.fn_judgement_outcome('quotes', n->>'id', 'won: ' || (n->>'status'), true, true, 'sales_engineer', 'quote',
            concat_ws(' | ', 'quote AED ' || (n->>'quote_amount'), 'for inquiry ' || (n->>'inquiry_id'), left(n->>'scope', 300)));
        elsif n->>'status' in ('lost','rejected','not_selected','declined','expired','withdrawn') then
          perform public.fn_judgement_outcome('quotes', n->>'id', 'lost: ' || (n->>'status'), false, true, 'sales_engineer', 'quote',
            concat_ws(' | ', 'quote AED ' || (n->>'quote_amount'), 'for inquiry ' || (n->>'inquiry_id'), left(n->>'scope', 300)));
        end if;
      end if;

    elsif tg_table_name = 'inquiries' then
      if n->>'status' is distinct from o->>'status' then
        if n->>'status' in ('revealed','won','completed','closed') then
          perform public.fn_judgement_outcome('inquiries', n->>'id', 'converted: ' || (n->>'status'), true, true, 'sales_engineer', 'inquiry', null);
          -- At reveal every other quote on the inquiry lost.
          if n->>'status' = 'revealed' then
            perform public.fn_judgement_outcome('quotes', q.id::text, 'lost at reveal', false, true, 'sales_engineer', 'quote',
                      concat_ws(' | ', 'quote AED ' || q.quote_amount, 'for inquiry ' || q.inquiry_id, left(q.scope, 300)))
               from public.quotes q
              where q.inquiry_id::text = n->>'id' and coalesce(q.status, '') not in ('revealed','won','accepted');
          end if;
        elsif n->>'status' in ('expired','cancelled','canceled','abandoned','lost') then
          perform public.fn_judgement_outcome('inquiries', n->>'id', 'abandoned: ' || (n->>'status') || coalesce('; ' || (n->>'lost_reason'), ''), false, true, 'sales_engineer', 'inquiry', null);
        end if;
      end if;

    elsif tg_table_name = 'complaint_tickets' then
      if n->>'final_response_at' is not null and o->>'final_response_at' is null then
        perform public.fn_judgement_outcome('complaint_tickets', n->>'id', 'resolved: ' || left(coalesce(n->>'final_response', ''), 400), true, true, null);
      end if;

    elsif tg_table_name = 'stripe_dispute' then
      if n->>'status' is distinct from o->>'status' and n->>'status' in ('won','lost') then
        perform public.fn_judgement_outcome('stripe_dispute', n->>'id', 'dispute ' || (n->>'status') || coalesce(': ' || (n->>'outcome'), ''),
          n->>'status' = 'won', true, 'accountant', 'dispute',
          concat_ws(' | ', 'card dispute ' || coalesce(n->>'reason', 'no reason'), (n->>'currency') || ' ' || ((n->>'amount_fils')::numeric / 100)));
      end if;

    elsif tg_table_name = 'notifications' then
      changed := n->>'status' is distinct from o->>'status' or n->>'provider_status' is distinct from o->>'provider_status';
      v_fail := n->>'status' in ('failed','bounced') or n->>'provider_status' in ('undelivered','failed','bounced');
      v_ok := n->>'provider_status' in ('delivered','read');
      v_seat := case when n->>'sender' in ('ceo','customer_support','sales_engineer','accountant','it_engineer','marketing') then n->>'sender' else 'customer_support' end;
      if changed and (v_fail or v_ok) then
        -- A failure becomes a case (a lesson source); a delivery only closes its judgements.
        perform public.fn_judgement_outcome('notifications', n->>'id',
          case when v_fail then 'failed: ' || coalesce(n->>'provider_status', n->>'status') || coalesce(' ' || (n->>'provider_error_code'), '') || coalesce(' ' || left(n->>'last_error', 200), '')
               else 'delivered: ' || (n->>'provider_status') end,
          not v_fail, true, case when v_fail then v_seat end, 'message',
          concat_ws(' | ', coalesce(n->>'channel', 'email') || ' message', 'type ' || (n->>'type'), 'kind ' || (n->>'kind'), 'to ' || (n->>'to_role')));
      end if;

    elsif tg_table_name = 'supplier_response_watch' then
      if n->>'first_response_at' is not null and o->>'first_response_at' is null then
        perform public.fn_judgement_outcome('supplier_response_watch', n->>'id', 'supplier responded via ' || coalesce(n->>'response_channel', 'unknown'), true, true,
          'customer_support', 'supplier_response', 'supplier chased after a reveal; ' || jsonb_array_length(coalesce(n->'attempts', '[]'::jsonb)) || ' attempt(s)');
      elsif n->>'closed_at' is not null and o->>'closed_at' is null and n->>'first_response_at' is null then
        perform public.fn_judgement_outcome('supplier_response_watch', n->>'id', 'supplier stayed silent: ' || coalesce(n->>'close_reason', 'closed'), false, true,
          'customer_support', 'supplier_response', 'supplier chased after a reveal; ' || jsonb_array_length(coalesce(n->'attempts', '[]'::jsonb)) || ' attempt(s)');
      end if;

    elsif tg_table_name = 'target_verdict' then
      -- A forecast is judged by the next one: the earlier verdict held (hit) or changed (miss).
      select * into v_prev from public.target_verdict
       where contract_id = (n->>'contract_id')::bigint and id < (n->>'id')::bigint order by id desc limit 1;
      if v_prev.id is not null and v_prev.verdict <> 'CANNOT_ASSESS' and n->>'verdict' <> 'CANNOT_ASSESS' then
        perform public.fn_judgement_outcome('target_verdict', v_prev.id::text,
          case when v_prev.verdict = n->>'verdict' then 'forecast held: ' else 'forecast missed: ' end || v_prev.verdict || ' -> ' || (n->>'verdict'),
          v_prev.verdict = n->>'verdict', true, 'ceo', 'forecast',
          concat_ws(' | ', 'target contract ' || v_prev.contract_id || ' forecast ' || v_prev.verdict, left(v_prev.verdict_reason, 400),
                    'base scenario ' || v_prev.scenario_base, 'binding stage ' || v_prev.binding_stage));
      end if;

    elsif tg_table_name = 'marketing_post_metric' then
      -- A post's performance, judged at seven days against the seat's own median of earlier posts.
      if n->>'checkpoint' = '7d' and n->>'metric' = 'engagement_rate_by_followers' and n->>'value' is not null
         and not exists (select 1 from public.marketing_post p where p.id = (n->>'post_id')::bigint and p.is_demo) then
        select percentile_cont(0.5) within group (order by m.value) into v_median
          from public.marketing_post_metric m join public.marketing_post p on p.id = m.post_id
         where m.checkpoint = '7d' and m.metric = 'engagement_rate_by_followers' and m.value is not null
           and not p.is_demo and m.post_id <> (n->>'post_id')::bigint;
        perform public.fn_judgement_outcome('marketing_post', n->>'post_id',
          'engagement ' || (n->>'value') || ' at 7d on ' || (n->>'platform') || coalesce(' vs median ' || round(v_median, 4), ' (first measured post)'),
          case when v_median is null then null else (n->>'value')::numeric >= v_median end, true, 'marketing', 'post_performance',
          (select concat_ws(' | ', p.title, left(p.text_en, 400), 'channels ' || array_to_string(p.channels, ','), p.rationale)
             from public.marketing_post p where p.id = (n->>'post_id')::bigint));
      end if;

    elsif tg_table_name = 'expense_entries' then
      if o->>'category' is not null and n->>'category' is distinct from o->>'category' then
        perform public.fn_judgement_outcome('expense_entries', n->>'id',
          'corrected: re-classified from ' || (o->>'category') || ' to ' || coalesce(n->>'category', 'unclassified'), false, true, null);
      end if;

    elsif tg_table_name = 'it_engineer_finding' then
      if n->>'closed_at' is not null and o->>'closed_at' is null then
        perform public.fn_judgement_outcome('it_engineer_finding', n->>'issue_key', 'resolved: ' || coalesce(n->>'close_note', 'closed'), true, true, null);
      elsif n->>'closed_at' is null and o->>'closed_at' is not null then
        perform public.fn_judgement_outcome('it_engineer_finding', n->>'issue_key', 'reopened: the fix did not hold', false, true, null);
      end if;
    end if;
  exception when others then
    insert into public.seat_case_memory_miss (source_table, source_id, error)
    values (tg_table_name, coalesce(n->>'id', n->>'issue_key'), 'judgement outcome: ' || sqlerrm);
  end;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.trg_leads_keep_the_public_name()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_norm text := public.fn_supplier_name_norm(new.company_name);
begin
  if v_norm is null then
    delete from public.supplier_public_name where lead_id = new.id;
  else
    insert into public.supplier_public_name (lead_id, norm) values (new.id, v_norm)
    on conflict (lead_id) do update set norm = excluded.norm;
  end if;
  return null;
end
$function$


CREATE OR REPLACE FUNCTION public.trg_learn_customer_preference()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
begin
  -- Never let remembering a preference fail the RFQ that taught it.
  begin
    perform public.fn_customer_preference_learn(NEW.customer_id);
  exception when others then null;
  end;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_legal_documents_hash()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  NEW.content_sha256 := encode(sha256(convert_to(coalesce(NEW.body_html, ''), 'UTF8')), 'hex');
  if TG_OP = 'UPDATE' and NEW.body_html is distinct from OLD.body_html then
    -- 6 SEP 2026: a body whose only change is the version label or date it prints is the SAME
    -- version, re-hashed. The words a party accepts changing is what makes a new version.
    if public.fn_legal_body_without_labels(NEW.body_html) is distinct from public.fn_legal_body_without_labels(OLD.body_html) then
      -- a changed body is a new version unless the statement set one itself
      if NEW.version is not distinct from OLD.version then
        NEW.version := public.fn_legal_version_bump(OLD.version);
      end if;
      NEW.effective_date := current_date;
    end if;
    NEW.updated_at := now();
  elsif TG_OP = 'UPDATE' and NEW.version is distinct from OLD.version then
    NEW.updated_at := now();
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_mask_quote_contact()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  new.notes      := public.mask_contacts(new.notes);
  new.scope      := public.mask_contacts(new.scope);
  new.conditions := public.mask_contacts(new.conditions);
  new.exclusions := public.mask_contacts(new.exclusions);
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.trg_model_policy_names_a_known_route()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_m text;
begin
  if not coalesce(new.active, false) then return new; end if;
  for v_m in
    select m from unnest(array[new.model_primary, new.model_fallback]) m
     where m is not null and m not in ('none', 'none/deterministic')
  loop
    if not exists (select 1 from model_registry r where r.model_id = v_m and r.active) then
      raise exception 'model_policy.% names "%" which is not an active model_registry row. '
        'fn_ai_route would substitute a different model silently. Add the registry row (prices read '
        'live from the provider catalogue) in the same file.', new.task_class, v_m
        using errcode = '23514';
    end if;
    if not exists (select 1 from llm_route_health h where h.model_id = v_m) then
      raise exception 'model_policy.% names "%" which has no llm_route_health row, so no circuit '
        'breaker covers it and fn_llm_preflight must refuse it. Add the breaker row - carrying the '
        'same open_until as the rest of the fleet - in the same file.', new.task_class, v_m
        using errcode = '23514';
    end if;
  end loop;
  -- A FALLBACK THAT IS THE PRIMARY IS NOT A FALLBACK (added 23 Sep 2026 in review, after the first
  -- draft set knowledge_ingestion's fallback to a model that a later blanket rewrite turned into its
  -- own primary). fn_ai_route hands model_fallback back for p_escalate and for a failed primary, so
  -- an equal pair silently removes the second attempt.
  if new.model_fallback is not null and new.model_fallback = new.model_primary
     and new.model_primary not in ('none', 'none/deterministic') then
    raise exception 'model_policy.% names "%" as BOTH primary and fallback. fn_ai_route returns the '
      'fallback for an escalation and for a failed primary, so this row has no second attempt at '
      'all.', new.task_class, new.model_primary
      using errcode = '23514';
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.trg_new_bug_closes_with_learning()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare i public.it_incident;
begin
  if new.kind = 'handoff' and new.detail->>'type' = 'it.finding' and new.status = 'done' and old.status is distinct from 'done' then
    select * into i from public.it_incident where handoff_id = new.id;
    if found and (coalesce(btrim(i.cause), '') = '' or coalesce(btrim(i.fix), '') = '' or coalesce(btrim(i.regression_check), '') = ''
                  or (i.playbook_class is null and coalesce(btrim(i.not_automatable_reason), '') = '')) then
      raise exception 'handoff % was a new bug (incident %): it closes only with its cause, fix, a regression check and a playbook entry or the reason it cannot be automated (fn_it_attach_learning)',
        new.id, i.id;
    end if;
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.trg_org_role_no_cycle()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare v_cur text; v_depth int := 0;
begin
  if new.manager_role_id is null then return new; end if;
  v_cur := new.manager_role_id;
  while v_cur is not null and v_depth < 64 loop
    if v_cur = new.role_id then
      raise exception 'reporting cycle: % -> % would close a loop', new.role_id, new.manager_role_id;
    end if;
    select r.manager_role_id into v_cur from public.org_role r where r.role_id = v_cur;
    v_depth := v_depth + 1;
  end loop;
  if v_depth >= 64 then
    raise exception 'reporting chain deeper than 64 above %; refusing', new.role_id;
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.trg_org_role_touch()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$ begin new.updated_at := now(); return new; end $function$


CREATE OR REPLACE FUNCTION public.trg_otp_served_country_lifts_blocks()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n int;
begin
  delete from public.otp_blocked_prefix where prefix like new.prefix || '%' and blocked_by = 'it_engineer';
  get diagnostics n = row_count;
  if n > 0 then
    insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
    values ('it_engineer', 'ok', now(), now(), jsonb_build_object('job', 'otp_unblock', 'prefix', new.prefix, 'by', 'otp_served_country', 'lifted', n),
            new.country || ' is now a served country');
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.trg_outcome_learning()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  n jsonb := to_jsonb(new);
  v_inq uuid; v_cnt integer; v_camp public.marketing_campaign; v_leads integer; v_posts integer; v_reason text; v_ok boolean;
  q record; l record;
begin
  begin
    if tg_table_name = 'reviews' then
      -- A CUSTOMER RATING: 4-5 right, 1-2 wrong, 3 recorded without a verdict. It lands on the inquiry (the match),
      -- the rated supplier's quote on it, and the supplier.
      v_ok := case when (n->>'rating')::int >= 4 then true when (n->>'rating')::int <= 2 then false end;
      v_reason := 'rated ' || (n->>'rating') || '/5' || coalesce(': ' || left(nullif(btrim(n->>'comment'), ''), 300), '');
      if n->>'inquiry_id' is not null then
        perform public.fn_outcome_record('inquiries', n->>'inquiry_id', 'rating', v_ok, v_reason, 'sales_engineer', 'inquiry', null);
        for q in select id from public.quotes where inquiry_id::text = n->>'inquiry_id' and supplier_id::text = n->>'supplier_id' loop
          perform public.fn_outcome_record('quotes', q.id::text, 'rating', v_ok, v_reason, 'sales_engineer', 'quote', null);
        end loop;
      end if;
      if n->>'supplier_id' is not null then
        perform public.fn_outcome_record('leads', n->>'supplier_id', 'rating', v_ok, v_reason, 'sales_engineer', 'supplier', null);
      end if;

    elsif tg_table_name = 'complaint_tickets' then
      -- A COMPLAINT counts against the decision it is about, only when that decision is unambiguous.
      select count(*), min(i.id::text)::uuid into v_cnt, v_inq
        from public.inquiries i join public.customers u on u.id = i.customer_id
       where lower(u.email) = lower(n->>'email') and i.created_at > (n->>'created_at')::timestamptz - interval '90 days'
         and i.created_at <= (n->>'created_at')::timestamptz;
      if v_cnt = 1 then
        perform public.fn_outcome_record('inquiries', v_inq::text, 'complaint', false,
          'complaint ' || (n->>'ticket_no') || ': ' || left(n->>'message', 400), 'sales_engineer', 'inquiry', null);
      end if;

    elsif tg_table_name = 'email_suppressions' then
      -- A SUPPLIER WHO LEFT: his address unsubscribed. Every decision about him learns it.
      for l in select id from public.leads where lower(email) = lower(n->>'email') loop
        perform public.fn_outcome_record('leads', l.id::text, 'supplier_left', false,
          'unsubscribed (' || coalesce(n->>'reason', 'unsubscribe') || coalesce(', ' || (n->>'source'), '') || ')',
          'sales_engineer', 'supplier', 'supplier ' || l.id || ' stopped receiving our messages');
      end loop;

    elsif tg_table_name = 'marketing_first_touch' then
      -- A CAMPAIGN THAT CONVERTED: a lead's first touch was one of its posts.
      select c.* into v_camp from public.marketing_campaign c join public.marketing_post p on p.campaign_id = c.id
       where p.id = (n->>'post_id')::bigint and not p.is_demo and not c.is_demo;
      if v_camp.id is not null then
        select count(*) into v_leads from public.marketing_first_touch f join public.marketing_post p on p.id = f.post_id
         where p.campaign_id = v_camp.id;
        perform public.fn_outcome_record('marketing_campaign', v_camp.id::text, 'campaign_converted', true,
          v_leads || ' lead(s) first touched its posts, latest lead ' || (n->>'lead_id') || ' via post ' || (n->>'post_id')
          || coalesce(' (' || (n->>'utm_source') || ')', ''), 'marketing', 'campaign',
          concat_ws(' | ', v_camp.campaign_key, v_camp.theme, v_camp.title));
      end if;

    elsif tg_table_name = 'marketing_post_metric' then
      -- A CAMPAIGN THAT DID NOT CONVERT: seven days after one of its posts, still no lead from any of them.
      -- A first touch later replaces it with campaign_converted.
      if n->>'checkpoint' = '7d' and n->>'metric' = 'engagement_rate_by_followers' then
        select c.* into v_camp from public.marketing_campaign c join public.marketing_post p on p.campaign_id = c.id
         where p.id = (n->>'post_id')::bigint and not p.is_demo and not c.is_demo;
        if v_camp.id is not null and not exists (select 1 from public.marketing_first_touch f join public.marketing_post p on p.id = f.post_id
                                                  where p.campaign_id = v_camp.id) then
          select count(*) into v_posts from public.marketing_post p where p.campaign_id = v_camp.id and p.published_at is not null;
          perform public.fn_outcome_record('marketing_campaign', v_camp.id::text, 'campaign_not_converted', false,
            'no lead first touched any of its ' || v_posts || ' published post(s) seven days after post ' || (n->>'post_id'),
            'marketing', 'campaign', concat_ws(' | ', v_camp.campaign_key, v_camp.theme, v_camp.title));
        end if;
      end if;
    end if;
  exception when others then
    insert into public.seat_case_memory_miss (source_table, source_id, error)
    values (tg_table_name, coalesce(n->>'id', n->>'email', n->>'post_id'), 'outcome learning: ' || sqlerrm);
  end;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.trg_p2c1_append_only()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
begin
  if tg_op = 'DELETE'
     and coalesce(current_setting('quotesdone.p2c1_teardown', true), '') = 'approved' then
    return old;
  end if;
  raise exception '% is append-only: % is not permitted.', tg_table_name, tg_op
    using hint = 'Evidence that can be deleted is evidence nobody can rely on. Record a new row instead.';
end $function$


CREATE OR REPLACE FUNCTION public.trg_pages_dirty()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin update public.deploy_state set dirty=true where id=1; return null; end $function$


CREATE OR REPLACE FUNCTION public.trg_pages_legal_sync()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.slug = 'legal_terms_body' then
    update public.legal_documents set body_html = NEW.html, source = 'pages:legal_terms_body'
     where slug = 'customer-terms' and body_html is distinct from NEW.html;
  elsif NEW.slug = 'legal_supplier_body' then
    update public.legal_documents set body_html = NEW.html, source = 'pages:legal_supplier_body'
     where slug = 'supplier-agreement' and body_html is distinct from NEW.html;
    update public.app_secrets set value = NEW.html, updated_at = now()
     where key = 'supplier_terms_html' and value is distinct from NEW.html;
  end if;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.trg_published_text_names_no_supplier()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_text text; v_name text;
begin
  if tg_table_name = 'social_message' then   -- nested: new.direction exists only on social_message
    if new.direction is distinct from 'out' or new.author is distinct from 'seat' then
      return new;   -- what a person wrote, to us or from our inbox, is recorded as written; the seat's replies are guarded
    end if;
  end if;
  -- one IF per table: PL/pgSQL plans each statement when it runs, so a column another table lacks is never read
  if    tg_table_name = 'blog_posts'             then v_text := concat_ws(' ', new.title, new.excerpt, new.meta_desc, new.body_html);
  elsif tg_table_name = 'marketing_article'      then v_text := concat_ws(' ', new.title_en, new.title_ar, new.excerpt_en, new.excerpt_ar,
                                                                           new.meta_desc_en, new.meta_desc_ar, new.body_html_en, new.body_html_ar);
  elsif tg_table_name = 'marketing_post'         then v_text := concat_ws(' ', new.title, new.text_en, new.text_ar);
  elsif tg_table_name = 'marketing_post_variant' then v_text := concat_ws(' ', new.title, new.caption, new.body, new.first_comment, new.alt_text);
  elsif tg_table_name = 'social_message'         then v_text := new.body;
  elsif tg_table_name = 'social_reply_library'   then v_text := concat_ws(' ', new.reply_en, new.reply_ar);
  elsif tg_table_name = 'social_posts'           then v_text := new.content::text;
  end if;
  v_name := public.fn_supplier_named_in(v_text);
  if v_name is not null then
    raise exception '%: this text names the supplier "%"; marketing and AI-visibility content never names a supplier (ruling 1020)',
      tg_table_name, v_name using errcode = 'P0001';
  end if;
  return new;
end
$function$


CREATE OR REPLACE FUNCTION public.trg_quote_committed_hash()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare v_text text;
begin
  -- 5 Aug 2026. fn_fraud_scan's `copied_quote` rule groups quotes by committed_hash having more
  -- than one distinct supplier — a control for the same quotation being filed by two suppliers.
  -- It could NEVER fire: the only writer of committed_hash was quote_review_api, deleted in
  -- d79b28e (22 Jul 2026) as proven-dead, and nothing replaced it. The rule has been reading a
  -- column nothing populates ever since.
  --
  -- Hash the WORDS THE SUPPLIER WROTE, deliberately NOT quote_amount: identical amounts on one
  -- RFQ are already caught by the identical_bids rule immediately above it in fn_fraud_scan, and
  -- folding the amount in here would make copied_quote a noisy duplicate of that rule rather than
  -- an independent signal. Two suppliers filing the same PROSE is the thing worth flagging.
  v_text := btrim(lower(regexp_replace(
    coalesce(new.scope,'') || ' ' || coalesce(new.notes,'') || ' ' ||
    coalesce(new.payment_terms,'') || ' ' || coalesce(new.warranty,'') || ' ' ||
    coalesce(new.committed_items::text,''),
    '[^a-z0-9]+', ' ', 'g')));
  -- A floor, so thin and boilerplate quotes cannot collide. "supply and install as specified"
  -- legitimately repeats across honest suppliers; a real copied quotation carries far more text.
  -- Below the floor the column stays NULL and fn_fraud_scan skips it (it filters coalesce<>'').
  if length(v_text) >= 40 then
    new.committed_hash := encode(extensions.digest(v_text, 'sha256'), 'hex');
  else
    new.committed_hash := null;
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.trg_quote_expiry()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare days int := 14; m text; n int;
begin
  if NEW.expires_at is null then
    m := lower(coalesce(NEW.validity,''));
    n := nullif((regexp_match(m,'(\d+)'))[1],'')::int;
    if n is not null and n > 0 then
      if m ~ 'week' then days := n*7;
      elsif m ~ 'month' then days := n*30;
      else days := n; end if;
    end if;
    if days < 1 then days := 14; end if;
    if days > 180 then days := 180; end if;
    NEW.expires_at := coalesce(NEW.created_at, now()) + make_interval(days => days);
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_quote_items_rescore()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  update public.quotes set status = status where id::text = coalesce(NEW.quote_id, OLD.quote_id);
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.trg_quote_pdf_cache_register()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_name text;
begin
  if new.path is null or new.path = '' then return new; end if;
  -- the display name is the letter-and-language part of the stored name, without the millisecond
  -- prefix the writer uses to keep paths unique: 1789983012525_QD-8B287960-A-quotation-en.pdf
  v_name := regexp_replace(split_part(new.path, '/', array_length(string_to_array(new.path, '/'), 1)),
                           '^\d{10,}_', '');
  -- a regenerated PDF replaces the earlier registration for the same quote and language
  delete from public.documents d
   where d.ref_table = 'quotes' and d.ref_id = new.quote_id::text and d.kind = 'quote'
     and d.bucket = new.bucket and d.path <> new.path
     and d.path ~ ('-quotation-' || new.lang || '\.pdf$');
  perform public.fn_register_document(new.bucket, new.path, 'quote', 'quotes', new.quote_id::text, v_name);
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.trg_quote_quality()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare cat text; grp text; v_md5 text; v_present text[]; v_cat_status text := null;
  n int; priced int; branded int; spec_n int; laboured int;
  pts int := 0; gmiss text[] := '{}'; cmiss jsonb := '[]'::jsonb; cmand_missing int := 0;
  r record; cat_pass boolean := true;
begin
  select category into cat from public.inquiries where id = NEW.inquiry_id;

  select count(*),
    count(*) filter (where coalesce(unit_price,0)>0 and coalesce(qty,0)>0),
    count(*) filter (where coalesce(brand,'')<>'' and coalesce(model,'')<>''),
    count(*) filter (where coalesce(specification,'')<>''),
    count(*) filter (where coalesce(labour,0)>0 or coalesce(install,0)>0)
    into n, priced, branded, spec_n, laboured
    from public.quote_items where quote_id = NEW.id::text;

  if coalesce(n,0)=0 then gmiss := array_append(gmiss,'an itemised breakdown (not just a lump sum)');
  else pts:=pts+15; if priced=n then pts:=pts+20; else gmiss:=array_append(gmiss,'a unit price on every line'); end if; end if;
  if n>0 and branded=n then pts:=pts+15; else gmiss:=array_append(gmiss,'the brand/model for each item'); end if;
  if n>0 and spec_n>=greatest(1,n/2) then pts:=pts+10; else gmiss:=array_append(gmiss,'the key specifications'); end if;
  if coalesce(laboured,0)>0 then pts:=pts+10; else gmiss:=array_append(gmiss,'the labour / installation cost'); end if;
  if coalesce(btrim(NEW.warranty),'')<>'' then pts:=pts+6; else gmiss:=array_append(gmiss,'the warranty period'); end if;
  if coalesce(btrim(NEW.lead_time),'')<>'' then pts:=pts+6; else gmiss:=array_append(gmiss,'the lead / delivery time'); end if;
  if coalesce(btrim(NEW.payment_terms),'')<>'' then pts:=pts+6; else gmiss:=array_append(gmiss,'the payment terms'); end if;
  if coalesce(btrim(NEW.exclusions),'')<>'' then pts:=pts+6; else gmiss:=array_append(gmiss,'what is excluded'); end if;
  if coalesce(btrim(NEW.validity),'')<>'' then pts:=pts+6; else gmiss:=array_append(gmiss,'how long the quote is valid'); end if;

  grp := public.fn_quote_spec_group(coalesce(cat,''));
  if grp is not null and exists (select 1 from public.category_quote_specs where spec_group=grp) then
    -- A reading already reasoned for this exact text is used. Without one nothing is asked (24 Sep 2026): the
    -- category status is 'not_read' and the quote is judged on its structural score alone.
    v_md5 := md5(coalesce(public.fn_quote_aspect_text(NEW), ''));
    select a.present into v_present from public.quote_aspect_reading a
     where a.quote_id = NEW.id and a.content_md5 = v_md5 and a.status = 'reasoned';
    if found then
      v_cat_status := 'reasoned';
      for r in select * from public.category_quote_specs where spec_group=grp order by mandatory desc, aspect loop
        if not (r.aspect = any(coalesce(v_present, '{}'::text[]))) then
          cmiss := cmiss || jsonb_build_object('label', r.label, 'mandatory', r.mandatory);
          if r.mandatory then cmand_missing := cmand_missing + 1; end if;
        end if;
      end loop;
      cat_pass := (cmand_missing = 0);
    else
      v_cat_status := 'not_read';
    end if;
  end if;

  NEW.quality := jsonb_build_object(
    'score', pts, 'pass', (pts >= 70 and cat_pass), 'submittable', (pts >= 70 and cat_pass),
    'missing', to_jsonb(gmiss),
    'category', case when grp is null then null else jsonb_build_object(
        'group', grp, 'status', v_cat_status, 'content_md5', v_md5, 'pass', cat_pass,
        'mandatory_missing', case when v_cat_status = 'reasoned' then cmand_missing end,
        'missing', case when v_cat_status = 'reasoned' then cmiss end) end,
    'scored_at', now());
  NEW.submittable := (pts >= 70 and cat_pass);
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_refunds_touch()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
begin NEW.updated_at := now(); return NEW; end $function$


CREATE OR REPLACE FUNCTION public.trg_reg_gov_fn()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if TG_OP = 'INSERT' then
    NEW.approved_at := null; NEW.approved_by := null;
  elsif (coalesce(NEW.title,'') is distinct from coalesce(OLD.title,'')
      or coalesce(NEW.summary,'') is distinct from coalesce(OLD.summary,'')
      or coalesce(NEW.key_requirements::text,'') is distinct from coalesce(OLD.key_requirements::text,'')
      or coalesce(NEW.body,'') is distinct from coalesce(OLD.body,'')
      or coalesce(NEW.source_url,'') is distinct from coalesce(OLD.source_url,'')
      or coalesce(NEW.effective_date::text,'') is distinct from coalesce(OLD.effective_date::text,'')
      or coalesce(NEW.status,'') is distinct from coalesce(OLD.status,'')) then
    NEW.approved_at := null; NEW.approved_by := null;
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_reg_inquiry_doc()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.drawing_file_path is not null and (TG_OP='INSERT' or NEW.drawing_file_path is distinct from OLD.drawing_file_path) then
     perform public.fn_register_document('drawing-files', NEW.drawing_file_path, 'drawing', 'inquiries', NEW.id::text, NEW.drawing_file_name);
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_reg_lead_docs()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare p text;
begin
  if NEW.license_doc_path is not null and (TG_OP='INSERT' or NEW.license_doc_path is distinct from OLD.license_doc_path) then
     perform public.fn_register_document('supplier-docs', NEW.license_doc_path, 'licence', 'leads', NEW.id::text, NEW.license_doc_name); end if;
  if NEW.company_profile_doc_path is not null and (TG_OP='INSERT' or NEW.company_profile_doc_path is distinct from OLD.company_profile_doc_path) then
     perform public.fn_register_document('supplier-docs', NEW.company_profile_doc_path, 'profile', 'leads', NEW.id::text, null); end if;
  if NEW.egr_doc_path is not null and (TG_OP='INSERT' or NEW.egr_doc_path is distinct from OLD.egr_doc_path) then
     perform public.fn_register_document('supplier-docs', NEW.egr_doc_path, 'egr', 'leads', NEW.id::text, NEW.egr_doc_name); end if;
  if NEW.catalog_doc_paths is not null then
     foreach p in array NEW.catalog_doc_paths loop
        perform public.fn_register_document('supplier-docs', p, 'catalog', 'leads', NEW.id::text, null); end loop; end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_reg_quote_doc()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.original_file_path is not null and (TG_OP='INSERT' or NEW.original_file_path is distinct from OLD.original_file_path) then
     perform public.fn_register_document('quote-files', NEW.original_file_path, 'quote', 'quotes', NEW.id::text, NEW.original_file_name);
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_reveal_receipt()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.revealed_at is not null and (TG_OP = 'INSERT' or OLD.revealed_at is null) then
    perform public.fn_seat_handoff('accountant', 'sales_engineer', 'reveal.paid', 'transactions', NEW.id::text,
      jsonb_build_object('transaction_id', NEW.id, 'customer_id', NEW.customer_id, 'supplier_id', NEW.supplier_id,
                         'inquiry_id', NEW.inquiry_id, 'quote_id', NEW.quote_id, 'revealed_at', NEW.revealed_at));
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_reveal_window()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  -- The refund window opens refund_window_working_days after the customer paid (pricing_config, the
  -- same source stripe_confirm and stripe_webhook read), so every path agrees on the date.
  if NEW.revealed_at is not null and NEW.refund_deadline is null then
    NEW.refund_deadline := public.fn_add_working_days(NEW.revealed_at,
      coalesce((select refund_window_working_days from public.pricing_config order by id limit 1), 5));
    if NEW.refund_status is null then NEW.refund_status := 'window_open'; end if;
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_review_chain_no_self_review()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_a text; v_r text;
begin
  if new.author_agent is null or new.reviewer_agent is null then return new; end if;

  v_a := coalesce(public.fn_org_agent_resolve(new.author_agent), new.author_agent);
  v_r := coalesce(public.fn_org_agent_resolve(new.reviewer_agent), new.reviewer_agent);

  if v_a = v_r then
    raise exception
      'review_chain refuses a self-review: author "%" and reviewer "%" are the same employee (%). %',
      new.author_agent, new.reviewer_agent, v_a,
      'Call fn_pick_reviewer(dept, author) and use what it returns; if it returns no reviewer, escalate.'
      using errcode = 'check_violation';
  end if;

  -- Store both sides canonical, so every count over this table measures employees and not spelling.
  new.author_agent   := v_a;
  new.reviewer_agent := v_r;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.trg_rfq_complete()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare c jsonb;
begin
  c := public.fn_rfq_score(NEW);
  NEW.completeness := c; NEW.rfq_ready := (c->>'ready')::boolean;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_routine_repeat_request_enqueue()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare p record;
begin
  if NEW.customer_id is null or btrim(coalesce(NEW.summary, '')) = ''
     or coalesce((NEW.plausibility->>'possible_duplicate')::boolean, false) then return NEW; end if;
  select i.id, i.summary into p from public.inquiries i
   where i.customer_id = NEW.customer_id and i.id <> NEW.id
     and i.created_at > now() - interval '30 minutes'
     and coalesce(i.category, '') = coalesce(NEW.category, '')
     and btrim(coalesce(i.summary, '')) <> ''
   order by i.created_at desc limit 1;
  if p.id is not null then
    perform public.fn_routine_judgement_enqueue('repeat_request', NEW.id::text,
      jsonb_build_object('inquiry_id', NEW.id, 'earlier_id', p.id, 'earlier', left(p.summary, 2000), 'later', left(NEW.summary, 2000),
                         'category', NEW.category));
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_routine_trade_words_enqueue()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.status = 'pending' then
    perform public.fn_routine_judgement_enqueue('supplier_trade_words', NEW.id::text,
      jsonb_build_object('proposal_id', NEW.id, 'supplier_id', NEW.supplier_id,
                         'words', coalesce(NEW.label_en, '') || case when NEW.label_ar is not null then ' / ' || NEW.label_ar else '' end));
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_scenario_expected_needs_ledger()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
begin
  if new.expected is distinct from old.expected
     and coalesce(current_setting('quotesdone.expectation_change', true), '') <> 'approved' then
    raise exception 'scenario_tests.expected cannot be changed directly (scenario %)', old.scenario_id
      using hint = 'Use public.fn_scenario_expectation_change(scenario_id, new_expected, reason, work_item, changed_by).';
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.trg_screening_entry_normalise()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  new.name_norm := public.fn_screening_normalise(new.name);
  new.tokens    := public.fn_screening_tokens(new.name);
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.trg_seat_deliberation_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.author_model = 'deterministic' then
    new.author_provider := 'deterministic';   -- a decision taken by code (29 Sep 2026, instruction 1009)
  elsif tg_op = 'INSERT' or new.author_model is distinct from old.author_model then
    select lower(btrim(r.provider)) into new.author_provider from public.model_registry r where r.model_id = new.author_model;
    if new.author_provider is null then
      raise exception 'seat_deliberation: author model % is not in model_registry; its family cannot be known', new.author_model;
    end if;
  end if;
  if tg_op = 'INSERT' then
    if not exists (select 1 from public.org_agents a where a.agent_key = new.author_seat and a.active)
       or not exists (select 1 from public.org_agents a where a.agent_key = new.reviewer_seat and a.active) then
      raise exception 'seat_deliberation: % and % must both be active seats', new.author_seat, new.reviewer_seat;
    end if;
    -- A REJECTION NEVER ENDS THE CYCLE (founder_instruction 1059): the CEO's reviews run to the loop guard.
    if new.reviewer_seat = 'ceo' and new.kind <> 'marketing.monthly_plan' then new.max_rounds := 5; end if;
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.trg_seat_deliberation_turn_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  d public.seat_deliberation;
  v_prov text; v_auth_prov text; v_auth_model text; v_steel text;
begin
  if tg_op = 'UPDATE' then
    raise exception 'seat_deliberation_turn % is append-only: record a new turn instead', old.id;
  end if;
  select * into d from public.seat_deliberation where id = new.deliberation_id;

  if new.model = 'deterministic' and new.phase = 'proposal' then
    -- A DECISION TAKEN BY CODE (29 Sep 2026, instruction 1009): no model wrote it, so any family may review it.
    new.provider := 'deterministic';
  elsif new.model is not null then
    select lower(btrim(r.provider)) into v_prov from public.model_registry r where r.model_id = new.model;
    if v_prov is null then
      raise exception 'seat_deliberation_turn: model % is not in model_registry', new.model;
    end if;
    if new.provider is not null and lower(btrim(new.provider)) <> v_prov then
      raise exception 'seat_deliberation_turn: provider % does not match model_registry (% is %)', new.provider, new.model, v_prov;
    end if;
    new.provider := v_prov;
  end if;

  if new.phase = 'proposal' then
    if new.seat <> d.author_seat or new.model is null or new.status <> 'recorded' then
      raise exception 'seat_deliberation_turn: a proposal is a recorded turn by the author seat % on a named model', d.author_seat;
    end if;
    return new;
  end if;

  if new.seat <> d.reviewer_seat then
    raise exception 'seat_deliberation_turn: a % turn belongs to the reviewer seat %, not %', new.phase, d.reviewer_seat, new.seat;
  end if;
  if new.reviews_turn_id is null then
    select t.id into new.reviews_turn_id from public.seat_deliberation_turn t
     where t.deliberation_id = new.deliberation_id and t.phase = 'proposal' and t.status = 'recorded' and t.round <= new.round
     order by t.round desc, t.id desc limit 1;
  end if;
  select lower(btrim(t.provider)), t.model into v_auth_prov, v_auth_model from public.seat_deliberation_turn t
   where t.id = new.reviews_turn_id and t.deliberation_id = new.deliberation_id and t.phase = 'proposal';
  if v_auth_prov is null then
    raise exception 'seat_deliberation_turn: a % turn must review a recorded proposal of the same deliberation', new.phase;
  end if;

  if new.provider = v_auth_prov then
    raise exception using errcode = 'check_violation',
      message = 'SAME_FAMILY_REVIEW: ' || new.model || ' (' || new.provider || ') may not review a proposal written on '
                || v_auth_model || ' (' || v_auth_prov || '). founder_instruction 873: the reviewer comes from another family.';
  end if;

  if new.status = 'recorded' then
    if new.model is null or new.verdict is null then
      raise exception 'MALFORMED_REVIEW: a recorded % turn names its model and its verdict', new.phase;
    end if;
    -- A steelman is a sentence of at least six words that is not a placeholder, and the comparison's is not
    -- the blind pass's copied forward. fn_seat_deliberation_record passes a steelman only when it is a JSON string.
    v_steel := public.fn_seat_deliberation_norm(new.steelman_against);
    if coalesce(array_length(regexp_split_to_array(nullif(v_steel, ''), ' '), 1), 0) < 6
       or v_steel ~ '^(none|n a|na|nil|nothing|tbd|not applicable|no (real |strong |serious |obvious )?(counter ?case|case against|counter ?argument|objection|concern|argument|risk|downside)s?|there (is|are) (nothing|no (counter ?case|case|objection|argument|risk|downside)s?))( |$)' then
      raise exception using errcode = 'check_violation',
        message = case when new.verdict = 'approve'
                       then 'MALFORMED_REVIEW: an approval without the strongest case against the proposal is malformed and is rejected'
                       else 'MALFORMED_REVIEW: every review turn states the strongest case against the proposal' end
                  || ' (at least six words, not a placeholder)';
    end if;
    if new.phase = 'compare' and exists (select 1 from public.seat_deliberation_turn b where b.deliberation_id = new.deliberation_id
          and b.phase = 'blind' and b.status = 'recorded' and public.fn_seat_deliberation_norm(b.steelman_against) = v_steel) then
      raise exception using errcode = 'check_violation',
        message = 'MALFORMED_REVIEW: the comparison''s steelman repeats the blind one; argue against the proposal now revealed';
    end if;
    if new.phase = 'compare' then
      if not exists (select 1 from public.seat_deliberation_turn b where b.deliberation_id = new.deliberation_id
                        and b.phase = 'blind' and b.status = 'recorded' and b.round <= new.round) then
        raise exception 'BLIND_FIRST: the reviewer compares only after its own blind verdict is recorded';
      end if;
      if coalesce(btrim(new.agreements), '') = '' or coalesce(btrim(new.disagreements), '') = '' then
        raise exception 'MALFORMED_REVIEW: a comparison states its agreements and its disagreements explicitly (write "none" if there are none)';
      end if;
    end if;
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.trg_seat_playbook_learns()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  begin
    if tg_table_name = 'seat_case_memory' then
      perform public.fn_seat_playbook_build(new.seat, 'lesson recorded on case #' || new.id);
    elsif tg_table_name = 'reasoning_knowledge_candidate' then
      perform public.fn_seat_playbook_build(new.seat, 'finding #' || new.id || ' ' || new.status);
    else
      perform public.fn_seat_playbook_build_all(tg_table_name || ' changed');
    end if;
  exception when others then
    begin
      perform public.fn_it_engineer_finding_upsert(
        'monitor:seat_playbook_rebuild_failed:' || tg_table_name,
        'A seat playbook could not be rebuilt after a change to ' || tg_table_name,
        'public.trg_seat_playbook_learns', 'agent_facing', 1,
        jsonb_build_object('error', left(sqlerrm, 500), 'owner_seat', 'it_engineer',
                           'fix', 'run select public.fn_seat_playbook_build_all() and read the error'),
        '{}'::text[], array['why fn_seat_playbook_build failed'], 'trg_seat_playbook_learns');
    exception when others then null;  -- the lesson stands; the next rebuild retries
    end;
  end;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.trg_step_run_actor_is_a_real_employee()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare v_actor text;
begin
  if new.status not in ('queued', 'running', 'ok') then return new; end if;
  if new.actor is null or btrim(new.actor) = '' then
    raise exception 'workflow_step_run % cannot be % with no actor', coalesce(new.step_no::text,'?'), new.status
      using errcode = 'check_violation';
  end if;

  v_actor := coalesce(public.fn_org_agent_resolve(new.actor), public.fn_org_role_resolve(new.actor));
  if v_actor is null then
    raise exception
      'workflow_step_run step % cannot be % with actor "%": that resolves to no employee. %',
      new.step_no, new.status, new.actor,
      'employee_task uses ''owner'' and ''Director'' as registry placeholders; a RUN must bind them '
      'to the task''s own owner and its department head before the step is queued.'
      using errcode = 'check_violation';
  end if;

  new.actor := v_actor;   -- store canonical, so every later count measures employees not spelling
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.trg_supplier_brief_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin raise exception 'inquiry_supplier_brief is append-only: freeze a new version instead of editing version %', OLD.version; end $function$


CREATE OR REPLACE FUNCTION public.trg_supplier_document_subject_asked()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.ref_table = 'supplier_supporting' and coalesce(NEW.status, '') <> 'withdrawn' and btrim(coalesce(NEW.file_name, '')) <> '' then
    perform public.fn_supplier_document_subject_ask(NEW.id, NEW.file_name, NEW.kind, NEW.ref_id);
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_table_export_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_pk text := tg_argv[0];
  v_proj text := coalesce(tg_argv[1], '');
begin
  if tg_op = 'TRUNCATE' then
    update public.table_export_change_tracked x set tracking_since = clock_timestamp() where x.table_name = tg_table_name;
    insert into public.table_export_change (table_name, row_key, deleted)
    values (tg_table_name, '(truncate: no row-level record is possible; the next export day is a full copy)', true);
    return null;
  end if;
  -- A bulk purge marks its own transaction (fn_kb_purge_batch). Its deletions are recorded as id ranges
  -- in kb_purge_ledger; the export learns them by the next day being a FULL copy, as for a truncate.
  if tg_op = 'DELETE' and current_setting('qd.export_change_bulk', true) = tg_table_name then
    update public.table_export_change_tracked x set tracking_since = clock_timestamp() where x.table_name = tg_table_name;
    return null;
  end if;
  if tg_op = 'INSERT' then
    execute format(
      'insert into public.table_export_change (table_name, row_key, deleted) select %L, n.%I::text, false from new_rows n',
      tg_table_name, v_pk);
  elsif tg_op = 'DELETE' then
    execute format(
      'insert into public.table_export_change (table_name, row_key, deleted) select %L, o.%I::text, true from old_rows o',
      tg_table_name, v_pk);
  elsif v_proj = '' then
    -- no projection recorded: log every touched row rather than guess that nothing changed
    execute format(
      'insert into public.table_export_change (table_name, row_key, deleted) select %L, n.%I::text, false from new_rows n',
      tg_table_name, v_pk);
  else
    execute format(
      'insert into public.table_export_change (table_name, row_key, deleted)
         select %1$L, n.%2$I::text, false from new_rows n join old_rows o on o.%2$I = n.%2$I
          where (%3$s) is distinct from (%4$s)',
      tg_table_name, v_pk,
      'n.' || replace(v_proj, ',', ', n.'), 'o.' || replace(v_proj, ',', ', o.'));
  end if;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.trg_terms_pins_sync()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  perform public.fn_terms_pins_sync();
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.trg_undo_capture()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_actor text;
begin
  v_actor := coalesce(
    nullif(current_setting('app.actor', true), ''),
    nullif(current_setting('request.jwt.claim.email', true), ''),
    session_user);

  if tg_op = 'DELETE' then
    insert into undo_log (table_name, row_id, op, before, actor)
    values (tg_table_name, (to_jsonb(old)->>(tg_argv[0])), 'DELETE', to_jsonb(old), v_actor);
    return old;
  else
    insert into undo_log (table_name, row_id, op, before, actor)
    values (tg_table_name, (to_jsonb(old)->>(tg_argv[0])), 'UPDATE', to_jsonb(old), v_actor);
    return new;
  end if;
exception when others then
  -- never let audit failure block the company's work
  if tg_op = 'DELETE' then return old; else return new; end if;
end $function$


CREATE OR REPLACE FUNCTION public.trg_version_document()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.extracted is not null and (TG_OP='INSERT' or NEW.extracted is distinct from OLD.extracted) then
    insert into public.doc_versions(entity_type,entity_id,version,snapshot,checksum,changed_fields)
    values ('document', NEW.id::text, public._next_docver('document',NEW.id::text),
            jsonb_build_object('extracted',NEW.extracted,'kind',NEW.kind,'status',NEW.status),
            md5(coalesce(NEW.extracted::text,'')), array['extracted'])
    on conflict do nothing;
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_version_quote()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare snap jsonb; chg text[] := '{}';
begin
  snap := jsonb_build_object(
    'quote_amount',NEW.quote_amount,'customer_price',NEW.customer_price,'status',NEW.status,
    'scope',NEW.scope,'committed_items',NEW.committed_items,'quality',NEW.quality,
    'review_status',NEW.review_status,'lead_time',NEW.lead_time,'warranty',NEW.warranty,
    'payment_terms',NEW.payment_terms,'conditions',NEW.conditions,'exclusions',NEW.exclusions);
  if TG_OP='UPDATE' then
    if NEW.quote_amount   is distinct from OLD.quote_amount   then chg:=array_append(chg,'quote_amount'); end if;
    if NEW.customer_price is distinct from OLD.customer_price then chg:=array_append(chg,'customer_price'); end if;
    if NEW.status         is distinct from OLD.status         then chg:=array_append(chg,'status'); end if;
    if NEW.scope          is distinct from OLD.scope          then chg:=array_append(chg,'scope'); end if;
    if NEW.committed_items is distinct from OLD.committed_items then chg:=array_append(chg,'committed_items'); end if;
    if NEW.quality        is distinct from OLD.quality        then chg:=array_append(chg,'quality'); end if;
    if NEW.review_status  is distinct from OLD.review_status  then chg:=array_append(chg,'review_status'); end if;
    if NEW.lead_time      is distinct from OLD.lead_time      then chg:=array_append(chg,'lead_time'); end if;
    if NEW.warranty       is distinct from OLD.warranty       then chg:=array_append(chg,'warranty'); end if;
    if NEW.payment_terms  is distinct from OLD.payment_terms  then chg:=array_append(chg,'payment_terms'); end if;
    if array_length(chg,1) is null then return NEW; end if;   -- nothing meaningful changed
  end if;
  insert into public.doc_versions(entity_type,entity_id,version,snapshot,checksum,changed_fields)
  values ('quote', NEW.id::text, public._next_docver('quote',NEW.id::text), snap, md5(snap::text), chg)
  on conflict do nothing;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_version_rfq()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare snap jsonb; chg text[] := '{}';
begin
  snap := jsonb_build_object('category',NEW.category,'emirate',NEW.emirate,'summary',NEW.summary,
    'spec',NEW.spec,'budget',NEW.budget,'scope_type',NEW.scope_type,'trades',NEW.trades,
    'boq',NEW.boq,'status',NEW.status,'pipeline_stage',NEW.pipeline_stage,'outcome',NEW.outcome);
  if TG_OP='UPDATE' then
    if NEW.spec is distinct from OLD.spec then chg:=array_append(chg,'spec'); end if;
    if NEW.budget is distinct from OLD.budget then chg:=array_append(chg,'budget'); end if;
    if NEW.scope_type is distinct from OLD.scope_type then chg:=array_append(chg,'scope_type'); end if;
    if NEW.trades is distinct from OLD.trades then chg:=array_append(chg,'trades'); end if;
    if NEW.boq is distinct from OLD.boq then chg:=array_append(chg,'boq'); end if;
    if NEW.status is distinct from OLD.status then chg:=array_append(chg,'status'); end if;
    if NEW.pipeline_stage is distinct from OLD.pipeline_stage then chg:=array_append(chg,'pipeline_stage'); end if;
    if NEW.category is distinct from OLD.category then chg:=array_append(chg,'category'); end if;
    if array_length(chg,1) is null then return NEW; end if;
  end if;
  insert into public.doc_versions(entity_type,entity_id,version,snapshot,checksum,changed_fields)
  values ('rfq', NEW.id::text, public._next_docver('rfq',NEW.id::text), snap, md5(snap::text), chg)
  on conflict do nothing;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.zzz_fn_notifications_demo_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_on boolean;
begin
  select coalesce((d.value #>> '{}')::boolean, false) into v_on
    from public.decision_policy d where d.key = 'demo_rehearsal_active';
  if not coalesce(v_on, false) then return NEW; end if;

  -- On UPDATE only a move INTO a status a dispatcher drains is judged. A dispatcher marking a row
  -- sent, failed or suppressed is not a send and must not be turned back into held.
  if TG_OP = 'UPDATE' and coalesce(NEW.status, '') not in ('queued', 'pending', 'digest') then return NEW; end if;

  -- RFC 2606 reserves .invalid as permanently undeliverable. Anything else, including NULL, is
  -- treated as possibly real and held. Failing closed is the whole point of this trigger.
  if coalesce(NEW.to_email, '') ~* '@example[.]invalid$' then return NEW; end if;

  NEW.status := 'held';
  -- Deliberately does NOT contain the marker pattern: a scan of every text column for it must be
  -- able to reach zero after a teardown.
  NEW.last_error := 'HELD by zzz_notifications_demo_guard: decision_policy.demo_rehearsal_active is '
                 || 'true and the recipient is not a reserved .invalid address. Release with '
                 || 'fn_notifications_release_held() once the rehearsal is torn down.';
  return NEW;
exception when others then
  -- A DIFFERENT PREFIX ON PURPOSE (database review, 15 Sep). The release below picks rows by the
  -- deliberate stamp's prefix. When this fallback shared it, a row held because the guard itself
  -- failed, where nothing was ever judged, would have been released with the rest. A row the guard
  -- could not judge is left for a person to look at.
  NEW.status := 'held';
  NEW.last_error := 'GUARD ERROR, held by zzz_notifications_demo_guard (guard itself errored: ' || sqlerrm || ')';
  return NEW;
end $function$


