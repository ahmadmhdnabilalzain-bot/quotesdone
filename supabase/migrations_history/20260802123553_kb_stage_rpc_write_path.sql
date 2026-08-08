-- WRITE PATH FOR A SCHEMA THAT IS NOT ON THE API SURFACE.
-- kb_stage is deliberately not in PostgREST's exposed schemas, so supabase-js cannot address it -
-- the first import attempt failed with "Invalid schema: kb_stage" on every request. The obvious fix
-- (expose kb_stage to the REST API) is the wrong one: it would put 115,000 unreviewed knowledge
-- records, their source lineage and every internal decision rule one policy mistake away from the
-- public API, to save writing this function once.
-- Instead the staging schema stays invisible to the API and these SECURITY DEFINER functions are the
-- only doors into it. p_target is matched against a fixed CASE - caller input never reaches a table
-- name - and the column list is the intersection of the payload's keys with the table's real
-- columns, so an unknown field is ignored rather than throwing, and a column with a default is left
-- to its default instead of being overwritten with null.

create or replace function public.kb_stage_upsert(p_target text, p_rows jsonb)
returns integer language plpgsql security definer set search_path = kb_stage, public as $$
declare
  v_schema text; v_tbl text; v_conflict text;
  v_keys text[]; v_all text; v_set text; v_sql text; v_n int;
begin
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then
    return 0;
  end if;

  case p_target
    when 'sources'          then v_schema:='kb_stage'; v_tbl:='sources';            v_conflict:='source_id';
    when 'categories'       then v_schema:='kb_stage'; v_tbl:='categories';         v_conflict:='category_slug';
    when 'subcategories'    then v_schema:='kb_stage'; v_tbl:='subcategories';      v_conflict:='category_slug,subcategory_slug';
    when 'records'          then v_schema:='kb_stage'; v_tbl:='records';            v_conflict:='record_id';
    when 'questions'        then v_schema:='kb_stage'; v_tbl:='questions';          v_conflict:='question_id';
    when 'decision_rules'   then v_schema:='kb_stage'; v_tbl:='decision_rules';     v_conflict:='rule_id';
    when 'validation_rules' then v_schema:='kb_stage'; v_tbl:='validation_rules';   v_conflict:='validation_id';
    when 'scenario_tests'   then v_schema:='kb_stage'; v_tbl:='scenario_tests';     v_conflict:='scenario_id';
    when 'knowledge_gaps'   then v_schema:='kb_stage'; v_tbl:='knowledge_gaps';     v_conflict:='';
    when 'crosswalk'        then v_schema:='kb_stage'; v_tbl:='category_crosswalk'; v_conflict:='knowledge_subcategory_slug,production_category_id,knowledge_domain_slug';
    when 'file_hashes'      then v_schema:='kb_stage'; v_tbl:='file_hashes';        v_conflict:='package_id,file_name';
    when 'op_route'         then v_schema:='public';   v_tbl:='kb_operational_route';      v_conflict:='catalog_num';
    when 'op_route_map'     then v_schema:='public';   v_tbl:='kb_operational_route_map';  v_conflict:='catalog_num,package_slug,subcategory_slug';
    when 'op_alias'         then v_schema:='public';   v_tbl:='kb_operational_alias';      v_conflict:='catalog_num,language,alias';
    when 'op_route_test'    then v_schema:='public';   v_tbl:='kb_operational_route_test'; v_conflict:='test_id';
    else raise exception 'unknown target %', p_target;
  end case;

  select array_agg(a.attname::text order by a.attnum) into v_keys
  from pg_attribute a
  where a.attrelid = format('%I.%I', v_schema, v_tbl)::regclass
    and a.attnum > 0 and not a.attisdropped
    and a.attname in (select jsonb_object_keys(p_rows->0));
  if v_keys is null then raise exception 'payload has no columns matching %.%', v_schema, v_tbl; end if;

  select string_agg(quote_ident(k), ',') into v_all from unnest(v_keys) k;
  select string_agg(format('%I = excluded.%I', k, k), ',') into v_set
  from unnest(v_keys) k
  where v_conflict = '' or k <> all (string_to_array(v_conflict, ','));

  v_sql := format('insert into %I.%I (%s) select %s from jsonb_populate_recordset(null::%I.%I, $1)',
                  v_schema, v_tbl, v_all, v_all, v_schema, v_tbl);
  if v_conflict <> '' then
    v_sql := v_sql || format(' on conflict (%s) do %s', v_conflict,
                             case when v_set is null then 'nothing' else 'update set ' || v_set end);
  end if;

  execute v_sql using p_rows;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

create or replace function public.kb_begin_run(p_package_id text, p_version text, p_sha text)
returns jsonb language plpgsql security definer set search_path = kb_stage, public as $$
declare r kb_stage.ingestion_runs;
begin
  select * into r from kb_stage.ingestion_runs
   where package_id = p_package_id and package_version = p_version
     and coalesce(package_sha256,'') = coalesce(p_sha,'');
  if found then
    return jsonb_build_object('run_id', r.id, 'reused', true, 'status', r.status);
  end if;
  insert into kb_stage.ingestion_runs (package_id, package_version, package_sha256, status)
  values (p_package_id, p_version, coalesce(p_sha,''), 'started') returning * into r;
  return jsonb_build_object('run_id', r.id, 'reused', false, 'status', r.status);
end $$;

create or replace function public.kb_finish_run(p_run_id uuid, p_status text, p_inserted bigint,
                                                p_updated bigint, p_rejected bigint, p_report jsonb)
returns void language sql security definer set search_path = kb_stage, public as $$
  update kb_stage.ingestion_runs
     set status = coalesce(p_status,'completed'), completed_at = now(),
         inserted_count = coalesce(p_inserted,0), updated_count = coalesce(p_updated,0),
         rejected_count = coalesce(p_rejected,0), report = coalesce(p_report,'{}'::jsonb)
   where id = p_run_id;
$$;

create or replace function public.kb_get_hashes(p_package_id text)
returns jsonb language sql security definer set search_path = kb_stage, public as $$
  select coalesce(jsonb_object_agg(file_name, jsonb_build_object('sha256', sha256, 'rows_seen', rows_seen)), '{}'::jsonb)
  from kb_stage.file_hashes where package_id = p_package_id;
$$;

revoke all on function public.kb_stage_upsert(text, jsonb) from public, anon, authenticated;
revoke all on function public.kb_begin_run(text, text, text) from public, anon, authenticated;
revoke all on function public.kb_finish_run(uuid, text, bigint, bigint, bigint, jsonb) from public, anon, authenticated;
revoke all on function public.kb_get_hashes(text) from public, anon, authenticated;
grant execute on function public.kb_stage_upsert(text, jsonb) to service_role;
grant execute on function public.kb_begin_run(text, text, text) to service_role;
grant execute on function public.kb_finish_run(uuid, text, bigint, bigint, bigint, jsonb) to service_role;
grant execute on function public.kb_get_hashes(text) to service_role;
