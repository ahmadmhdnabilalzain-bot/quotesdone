-- a_drawing_sheet_is_queued_once_probe.sql (sales_engineer, 17 Nov 2026)
-- A pure probe of cad_read_jobs_one_open_pages_job. Inside a block that always rolls itself back it queues a ZZ DEMO
-- 'pages_need_time' job (no customer, an @example.invalid owner, a path under drawings/zz-demo-probe/ that names no stored
-- object), then asserts:
--   1. a second OPEN pages job for the same stored drawing is refused (unique_violation);
--   2. once the first job is done, a new one for the same drawing is accepted (a later upload can be queued again);
--   3. a job of another kind (pdf_lengths_worker_died) for the same drawing is not touched by the index;
--   4. nothing it wrote survives (counted after the rollback).
-- No worker claims it: the block never commits. It answers with ONE ROW: 'PROBE OK' or 'PROBE FAILED: <why>'.
create temp table if not exists zz_probe_verdict (verdict text) on commit drop;
truncate zz_probe_verdict;
do $probe$
declare
  v_path constant text := 'drawings/zz-demo-probe/' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS') || '_ZZ DEMO set.pdf';
  v_fail text := ''; v_first uuid; v_refused boolean := false;
begin
  begin
    insert into public.cad_read_jobs (customer_id, owner_email, source_path, file_name, mime, why, boq_in)
    values (null, 'zz-probe@example.invalid', v_path, 'ZZ DEMO set.pdf', 'application/pdf', 'pages_need_time', '{"queued_pages":{}}')
    returning id into v_first;
    begin
      insert into public.cad_read_jobs (customer_id, owner_email, source_path, file_name, mime, why, boq_in)
      values (null, 'zz-probe@example.invalid', v_path, 'ZZ DEMO set.pdf', 'application/pdf', 'pages_need_time', '{"queued_pages":{}}');
    exception when unique_violation then v_refused := true;
    end;
    if not v_refused then v_fail := v_fail || 'a second open pages job was accepted; '; end if;
    insert into public.cad_read_jobs (customer_id, owner_email, source_path, file_name, mime, why)
    values (null, 'zz-probe@example.invalid', v_path, 'ZZ DEMO set.pdf', 'application/pdf', 'pdf_lengths_worker_died');
    update public.cad_read_jobs set status = 'done', finished_at = now() where id = v_first;
    begin
      insert into public.cad_read_jobs (customer_id, owner_email, source_path, file_name, mime, why, boq_in)
      values (null, 'zz-probe@example.invalid', v_path, 'ZZ DEMO set.pdf', 'application/pdf', 'pages_need_time', '{"queued_pages":{}}');
    exception when unique_violation then v_fail := v_fail || 'a new pages job after the first was done was refused; ';
    end;
    raise exception 'zz_probe_rollback' using detail = v_fail;
  exception when raise_exception then
    if sqlerrm <> 'zz_probe_rollback' then raise; end if;
    get stacked diagnostics v_fail = pg_exception_detail;
  end;
  if exists (select 1 from public.cad_read_jobs where source_path = v_path) then v_fail := v_fail || 'a probe row survived; '; end if;
  insert into zz_probe_verdict values (case when v_fail = '' then 'PROBE OK' else 'PROBE FAILED: ' || v_fail end);
end $probe$;
select verdict from zz_probe_verdict;
