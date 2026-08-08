-- Same pattern as the supplier corpus: ops_kb_stage is not on the API surface, so these
-- SECURITY DEFINER functions are the only doors into it. p_target is matched against a fixed CASE,
-- so caller input never reaches a table name.
create or replace function public.ops_stage_upsert(p_target text, p_rows jsonb)
returns integer language plpgsql security definer set search_path = ops_kb_stage, public as $$
declare v_tbl text; v_conflict text; v_keys text[]; v_all text; v_set text; v_sql text; v_n int;
begin
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then return 0; end if;
  case p_target
    when 'sources'             then v_tbl:='sources';             v_conflict:='source_id';
    when 'records'             then v_tbl:='records';             v_conflict:='record_id';
    when 'departments'         then v_tbl:='departments';         v_conflict:='department_key';
    when 'roles'               then v_tbl:='roles';               v_conflict:='record_id';
    when 'sops'                then v_tbl:='sops';                v_conflict:='record_id';
    when 'decision_rules'      then v_tbl:='decision_rules';      v_conflict:='record_id';
    when 'exception_playbooks' then v_tbl:='exception_playbooks'; v_conflict:='record_id';
    when 'kpis'                then v_tbl:='kpis';                v_conflict:='record_id';
    when 'scenarios'           then v_tbl:='scenarios';           v_conflict:='record_id';
    when 'workflows'           then v_tbl:='workflows';           v_conflict:='workflow_key';
    when 'handoffs'            then v_tbl:='handoffs';            v_conflict:='record_id';
    when 'event_subscriptions' then v_tbl:='event_subscriptions'; v_conflict:='record_id';
    when 'templates'           then v_tbl:='templates';           v_conflict:='record_id';
    when 'policies'            then v_tbl:='policies';            v_conflict:='record_id';
    when 'hard_gates'          then v_tbl:='hard_gates';          v_conflict:='record_id';
    when 'live_bindings'       then v_tbl:='live_bindings';       v_conflict:='record_id';
    when 'department_crosswalk' then v_tbl:='department_crosswalk'; v_conflict:='production_dept_key,target_department_key';
    when 'mapping_decisions'   then v_tbl:='mapping_decisions';   v_conflict:='concept_type,concept_key';
    when 'ingestion_files'     then v_tbl:='ingestion_files';     v_conflict:='run_id,relative_path';
    else raise exception 'unknown ops target %', p_target;
  end case;

  select array_agg(a.attname::text order by a.attnum) into v_keys
  from pg_attribute a
  where a.attrelid = format('ops_kb_stage.%I', v_tbl)::regclass
    and a.attnum > 0 and not a.attisdropped
    and a.attname in (select jsonb_object_keys(p_rows->0));
  if v_keys is null then raise exception 'payload has no columns matching ops_kb_stage.%', v_tbl; end if;

  select string_agg(quote_ident(k), ',') into v_all from unnest(v_keys) k;
  select string_agg(format('%I = excluded.%I', k, k), ',') into v_set
  from unnest(v_keys) k where k <> all (string_to_array(v_conflict, ','));

  v_sql := format('insert into ops_kb_stage.%I (%s) select %s from jsonb_populate_recordset(null::ops_kb_stage.%I, $1) on conflict (%s) do %s',
                  v_tbl, v_all, v_all, v_tbl, v_conflict,
                  case when v_set is null then 'nothing' else 'update set ' || v_set end);
  execute v_sql using p_rows;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

create or replace function public.ops_begin_run(p_package text, p_version text, p_sha text)
returns jsonb language plpgsql security definer set search_path = ops_kb_stage, public as $$
declare r ops_kb_stage.ingestion_runs;
begin
  select * into r from ops_kb_stage.ingestion_runs
   where package_name = p_package and package_version = p_version and coalesce(package_sha256,'') = coalesce(p_sha,'');
  if found then return jsonb_build_object('run_id', r.id, 'reused', true, 'status', r.status); end if;
  insert into ops_kb_stage.ingestion_runs (package_name, package_version, package_sha256, status)
  values (p_package, p_version, coalesce(p_sha,''), 'running') returning * into r;
  return jsonb_build_object('run_id', r.id, 'reused', false, 'status', r.status);
end $$;

create or replace function public.ops_finish_run(p_run_id uuid, p_status text, p_ins bigint,
                                                 p_upd bigint, p_skip bigint, p_rej bigint, p_detail jsonb)
returns void language sql security definer set search_path = ops_kb_stage, public as $$
  update ops_kb_stage.ingestion_runs
     set status = coalesce(p_status,'completed'), completed_at = now(),
         inserted_count = coalesce(p_ins,0), updated_count = coalesce(p_upd,0),
         skipped_count = coalesce(p_skip,0), rejected_count = coalesce(p_rej,0),
         detail = coalesce(p_detail,'{}'::jsonb)
   where id = p_run_id;
$$;

create or replace function public.ops_get_files(p_run_id uuid)
returns jsonb language sql security definer set search_path = ops_kb_stage, public as $$
  select coalesce(jsonb_object_agg(relative_path, jsonb_build_object('sha256', sha256, 'status', status)), '{}'::jsonb)
  from ops_kb_stage.ingestion_files where run_id = p_run_id;
$$;

-- Rollback by ingestion run. Same contract as the supplier corpus: restore what the run overwrote,
-- delete what it created, and never silently drop a prior version.
create or replace function public.ops_rollback_run(p_run_id uuid)
returns jsonb language plpgsql security definer set search_path = ops_kb_stage, public as $$
declare v_restored int := 0; v_deleted int := 0;
begin
  with latest as (
    select distinct on (rv.record_id) rv.*
    from ops_kb_stage.record_versions rv
    join ops_kb_stage.records r on r.record_id = rv.record_id
    where r.ingestion_run_id = p_run_id
    order by rv.record_id, rv.replaced_at desc
  )
  update ops_kb_stage.records r
     set content = latest.payload->>'content', title = latest.payload->>'title',
         structured_data = coalesce(latest.payload->'structured_data','{}'::jsonb),
         version = latest.version, content_sha256 = latest.content_sha256,
         validation_status = latest.payload->>'validation_status',
         implementation_status = latest.payload->>'implementation_status',
         ingestion_run_id = (latest.payload->>'ingestion_run_id')::uuid
  from latest where latest.record_id = r.record_id;
  get diagnostics v_restored = row_count;

  -- child projections cascade from records
  delete from ops_kb_stage.records r
   where r.ingestion_run_id = p_run_id
     and not exists (select 1 from ops_kb_stage.record_versions v where v.record_id = r.record_id);
  get diagnostics v_deleted = row_count;

  delete from ops_kb_stage.ingestion_files where run_id = p_run_id;
  update ops_kb_stage.ingestion_runs set status = 'rolled_back', completed_at = now() where id = p_run_id;
  return jsonb_build_object('run_id', p_run_id, 'records_restored', v_restored, 'records_deleted', v_deleted);
end $$;

revoke all on function public.ops_stage_upsert(text,jsonb) from public, anon, authenticated;
revoke all on function public.ops_begin_run(text,text,text) from public, anon, authenticated;
revoke all on function public.ops_finish_run(uuid,text,bigint,bigint,bigint,bigint,jsonb) from public, anon, authenticated;
revoke all on function public.ops_get_files(uuid) from public, anon, authenticated;
revoke all on function public.ops_rollback_run(uuid) from public, anon, authenticated;
grant execute on function public.ops_stage_upsert(text,jsonb) to service_role;
grant execute on function public.ops_begin_run(text,text,text) to service_role;
grant execute on function public.ops_finish_run(uuid,text,bigint,bigint,bigint,bigint,jsonb) to service_role;
grant execute on function public.ops_get_files(uuid) to service_role;
grant execute on function public.ops_rollback_run(uuid) to service_role;
