-- VERSIONING WITHOUT A READ-BEFORE-WRITE. The importer upserts in batches of 500; making it fetch
-- the previous row first to decide whether to archive would double the round trips and open a race
-- between two concurrent packages. The database already has the OLD row in hand during an UPDATE,
-- so archiving belongs here. Only genuine content changes are archived - a rerun of an unchanged
-- package touches nothing, which is what makes the import idempotent.
create or replace function kb_stage.trg_archive_record_version() returns trigger
language plpgsql as $$
begin
  if TG_OP = 'UPDATE'
     and OLD.content_sha256 is distinct from NEW.content_sha256 then
    insert into kb_stage.record_versions (record_id, version, content_sha256, payload, ingestion_run_id)
    values (OLD.record_id, OLD.version, OLD.content_sha256, to_jsonb(OLD), OLD.ingestion_run_id);
    NEW.updated_at := now();
  elsif TG_OP = 'UPDATE' then
    -- unchanged content: keep the original updated_at so "what actually moved in this run" stays
    -- answerable from the table itself.
    NEW.updated_at := OLD.updated_at;
  end if;
  return NEW;
end $$;

drop trigger if exists archive_record_version on kb_stage.records;
create trigger archive_record_version before update on kb_stage.records
  for each row execute function kb_stage.trg_archive_record_version();

-- Rollback handle. Removes everything a run wrote and restores the archived previous version of any
-- record that run overwrote. Documented and tested rather than described.
create or replace function kb_stage.rollback_ingestion_run(p_run_id uuid)
returns jsonb language plpgsql security definer set search_path = kb_stage, public as $$
declare v_restored int := 0; v_deleted int := 0; v_children int := 0; n int;
begin
  -- 1. restore records this run overwrote, newest archived version first
  with latest as (
    select distinct on (rv.record_id) rv.*
    from kb_stage.record_versions rv
    join kb_stage.records r on r.record_id = rv.record_id
    where r.ingestion_run_id = p_run_id
    order by rv.record_id, rv.replaced_at desc
  )
  update kb_stage.records r
     set content        = latest.payload->>'content',
         title          = latest.payload->>'title',
         structured_data= coalesce(latest.payload->'structured_data','{}'::jsonb),
         version        = latest.version,
         content_sha256 = latest.content_sha256,
         validation_status = latest.payload->>'validation_status',
         ingestion_run_id  = (latest.payload->>'ingestion_run_id')::uuid
  from latest where latest.record_id = r.record_id;
  get diagnostics v_restored = row_count;

  -- 2. delete rows this run created (records created by the run have no archived predecessor)
  delete from kb_stage.questions        where ingestion_run_id = p_run_id; get diagnostics n = row_count; v_children := v_children + n;
  delete from kb_stage.decision_rules   where ingestion_run_id = p_run_id; get diagnostics n = row_count; v_children := v_children + n;
  delete from kb_stage.validation_rules where ingestion_run_id = p_run_id; get diagnostics n = row_count; v_children := v_children + n;
  delete from kb_stage.scenario_tests   where ingestion_run_id = p_run_id; get diagnostics n = row_count; v_children := v_children + n;
  delete from kb_stage.knowledge_gaps   where ingestion_run_id = p_run_id; get diagnostics n = row_count; v_children := v_children + n;

  delete from kb_stage.records r
   where r.ingestion_run_id = p_run_id
     and not exists (select 1 from kb_stage.record_versions v where v.record_id = r.record_id);
  get diagnostics v_deleted = row_count;

  delete from kb_stage.file_hashes where last_run_id = p_run_id;
  update kb_stage.ingestion_runs set status = 'rolled_back', completed_at = now() where id = p_run_id;

  return jsonb_build_object('run_id', p_run_id, 'records_restored', v_restored,
                            'records_deleted', v_deleted, 'child_rows_deleted', v_children);
end $$;

revoke all on function kb_stage.rollback_ingestion_run(uuid) from public, anon, authenticated;

comment on function kb_stage.rollback_ingestion_run(uuid) is
  'Undo one ingestion run: restores records it overwrote from record_versions, deletes records and child rows it created, clears its file hashes so a re-import re-reads every file. Service role only.';
