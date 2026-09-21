-- A TRUNCATE MARKER CANNOT BREAK THE RESTORE DRILL.
--
-- Assigned: it_engineer. 21 Sep 2026. Founder-confirmed task from the coordinator.
--
-- MEASURED (production, read-only, 21 Sep 2026):
--   * trg_table_export_change's TRUNCATE branch (we_back_up_the_extra_stuff_only_unless_they_got_updated.sql)
--     writes ONE row to public.table_export_change with deleted = true and row_key set to a sentence,
--     '(truncate: no row-level record is possible; the next export day is a full copy)'.
--   * Two tables are change-tracked: kb_chunks (primary key id BIGINT) and ops_knowledge (record_id TEXT).
--   * fn_table_export_replay applies the change log's deletions with `d.row_key::<key type> ... where
--     d.deleted`. The marker IS deleted = true, so on kb_chunks that cast is '(truncate: ...)'::bigint
--     and the whole replay raises "invalid input syntax for type bigint". Proved on the unchanged
--     database before this file was written: the probe below, run read-only against the live body,
--     errored with exactly that. One truncate of kb_chunks would have broken every restore drill whose
--     chain read that day's change pages -- the drill fails on the log, not on the data.
--   * No marker exists today (0 rows like '(truncate%' in table_export_change); this is latent.
--   * The live bodies of fn_table_export_replay and fn_table_export_page are byte-identical to the
--     MANIFEST-canonical file above (pg_get_functiondef compared, 21 Sep 2026). PG 17.6.
--
-- WHAT THIS CHANGES -- fn_table_export_replay only, one predicate:
--   the deletion step now keeps only change rows whose row_key parses as the key's own type
--   (pg_input_is_valid(row_key, <key type>)). By type, not by the marker's wording, so a uuid key, a
--   reworded marker or any future non-key sentinel is skipped the same way. A skipped marker loses
--   nothing: the truncate already moved tracking_since forward, which forces the next export day FULL.
--   Everything else in the body is the live body, unchanged.
--
-- WHAT THIS DOES NOT CHANGE, AND WHY:
--   * fn_table_export_page is NOT redefined. Its IN-subquery casts `cl.row_key::<key type>` only for
--     rows that pass `not cl.deleted`; the marker is always deleted = true, and a scan applies its
--     filter before it computes its output, so the cast never sees the marker. No hazard, no change.
--   * The lost-rows step compares `row_key = key::text` (text on both sides) and never casts the log;
--     a marker there matches no key. Unchanged.
--   * The trigger and the marker's wording are unchanged: the marker is the record of why a day went FULL.
--
-- PROOF: the verdict row at the end (PROBE OK / PROBE FAILED). It replays the first 3 kb_chunks rows
--   (read through fn_table_export_page) against a change list holding the truncate marker, twice: marker
--   alone (no error, 0 deletes, 0 lost) and marker plus a real delete of the first base key (that delete
--   still applies). It writes only session temp tables that fn_table_export_replay drops itself; no real
--   row is read for writing, inserted, updated or deleted. Against the old body it raises instead.

begin;

create or replace function public.fn_table_export_replay(p_table text, p_base jsonb, p_increments jsonb default '[]'::jsonb,
                                                          p_changes jsonb default '[]'::jsonb)
returns jsonb
language plpgsql volatile security definer
set search_path to 'public', 'pg_temp'
as $fn$
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
end $fn$;
revoke execute on function public.fn_table_export_replay(text, jsonb, jsonb, jsonb) from public, anon, authenticated;

commit;

-- ── PROOF, AS A ROW ───────────────────────────────────────────────────────────────────────────────
-- Reads 3 live kb_chunks rows; writes nothing but the replay's own on-commit-drop temp tables.
with m as (
  select '(truncate: no row-level record is possible; the next export day is a full copy)'::text as marker
), b as (
  select public.fn_table_export_page('kb_chunks', null, 3)->'rows' as rows
), a as (   -- the marker alone
  select public.fn_table_export_replay('kb_chunks', b.rows, '[]'::jsonb,
           jsonb_build_array(jsonb_build_object('table_name', 'kb_chunks', 'row_key', m.marker,
                                                'deleted', true, 'changed_at', now()))) as j
    from b, m
), c as (   -- the marker plus a real delete of the first base key: deletions must still apply
  select public.fn_table_export_replay('kb_chunks', b.rows, '[]'::jsonb,
           jsonb_build_array(jsonb_build_object('table_name', 'kb_chunks', 'row_key', m.marker,
                                                'deleted', true, 'changed_at', now()),
                             jsonb_build_object('table_name', 'kb_chunks', 'row_key', b.rows->0->>'id',
                                                'deleted', true, 'changed_at', now()))) as j
    from b, m
), v as (
  select
    (select format_type(a.atttypid, a.atttypmod) from pg_index i
       join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey)
      where i.indrelid = 'public.kb_chunks'::regclass and i.indisprimary) = 'bigint'  as key_is_bigint,
    not pg_input_is_valid((select marker from m), 'bigint')                              as old_cast_would_raise,
    jsonb_array_length((select rows from b))                                             as base_rows,
    (select j from a) as ja, (select j from c) as jc,
    (select prosrc from pg_proc where oid = 'public.fn_table_export_replay(text,jsonb,jsonb,jsonb)'::regprocedure)
      like '%pg_input_is_valid%'                                                          as guard_live,
    has_function_privilege('anon', 'public.fn_table_export_replay(text,jsonb,jsonb,jsonb)', 'execute') as anon_can_run
)
select case when v.key_is_bigint and v.old_cast_would_raise and v.base_rows = 3 and v.guard_live and not v.anon_can_run
             and v.ja->>'error' is null and (v.ja->>'deletes_applied')::int = 0
             and (v.ja->>'rebuilt')::int = 3 and (v.ja->>'lost_rows')::int = 0
             and (v.jc->>'deletes_applied')::int = 1 and (v.jc->>'rebuilt')::int = 2
            then 'PROBE OK' else 'PROBE FAILED' end
       || format(': key_is_bigint=%s old_cast_would_raise=%s base_rows=%s guard_live=%s anon_can_run=%s | marker only: deletes=%s rebuilt=%s lost=%s error=%s | marker+real delete: deletes=%s rebuilt=%s',
                 v.key_is_bigint, v.old_cast_would_raise, v.base_rows, v.guard_live, v.anon_can_run,
                 v.ja->>'deletes_applied', v.ja->>'rebuilt', v.ja->>'lost_rows', coalesce(v.ja->>'error', 'none'),
                 v.jc->>'deletes_applied', v.jc->>'rebuilt') as verdict
  from v;
