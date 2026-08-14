-- Rollback by ingestion run.
--
-- An import that only knows how to write forward cannot be undone: the rows it replaced
-- are gone. Before each upsert the importer stores the row it is about to overwrite, so a
-- run can be reversed exactly — inserted rows deleted, updated rows put back as they were.
create table if not exists knowledge_ingestion_undo (
  run_id      uuid not null references knowledge_ingestion_run(run_id) on delete cascade,
  table_name  text not null check (table_name in ('ops_knowledge','agent_training_case')),
  key         text not null,
  existed     boolean not null,
  prev_row    jsonb,
  primary key (run_id, table_name, key)
);
create index if not exists knowledge_ingestion_undo_run on knowledge_ingestion_undo (run_id);
alter table knowledge_ingestion_undo enable row level security;

create or replace function fn_knowledge_rollback(p_run uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted int := 0;
  v_restored int := 0;
  r record;
begin
  if not exists (select 1 from knowledge_ingestion_run where run_id = p_run) then
    raise exception 'unknown ingestion run %', p_run;
  end if;

  for r in select * from knowledge_ingestion_undo where run_id = p_run and table_name = 'ops_knowledge' loop
    if r.existed then
      -- put the stored row back exactly as it was
      delete from ops_knowledge where record_id = r.key;
      insert into ops_knowledge select * from jsonb_populate_record(null::ops_knowledge, r.prev_row);
      v_restored := v_restored + 1;
    else
      delete from ops_knowledge where record_id = r.key;
      v_deleted := v_deleted + 1;
    end if;
  end loop;

  for r in select * from knowledge_ingestion_undo where run_id = p_run and table_name = 'agent_training_case' loop
    if r.existed then
      delete from agent_training_case where case_id = r.key;
      insert into agent_training_case select * from jsonb_populate_record(null::agent_training_case, r.prev_row);
      v_restored := v_restored + 1;
    else
      delete from agent_training_case where case_id = r.key;
      v_deleted := v_deleted + 1;
    end if;
  end loop;

  update knowledge_ingestion_run set status = 'rolled_back' where run_id = p_run;
  delete from knowledge_ingestion_undo where run_id = p_run;
  return jsonb_build_object('run_id', p_run, 'deleted', v_deleted, 'restored', v_restored);
end $$;

revoke all on function fn_knowledge_rollback(uuid) from public;
