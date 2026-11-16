-- PROBE of a_cad_drawing_left_unread_is_an_alarm_whether_or_not_anyone_is_watching.sql. Seat: sales_engineer (agent: L7_JOBS).
-- LOCAL ONLY. It always raises CHK<<...>>, so its ZZ DEMO jobs and findings roll back. It touches no real cad_read_jobs row.
do $probe$
declare v_fail text := ''; v_old uuid; v_new uuid; v_bad uuid; v_r jsonb;
begin
  insert into public.cad_read_jobs (owner_email, source_path, file_name, why, created_at)
  values ('zz.probe@example.invalid', 'zz-demo/probe/old.dwg', 'ZZ DEMO old.dwg', 'over_edge_ceiling', now() - interval '3 hours') returning id into v_old;
  insert into public.cad_read_jobs (owner_email, source_path, file_name, why, created_at)
  values ('zz.probe@example.invalid', 'zz-demo/probe/new.dwg', 'ZZ DEMO new.dwg', 'over_edge_ceiling', now() - interval '20 minutes') returning id into v_new;
  insert into public.cad_read_jobs (owner_email, source_path, file_name, why, status, attempts, error, finished_at, created_at)
  values ('zz.probe@example.invalid', 'zz-demo/probe/bad.dwg', 'ZZ DEMO bad.dwg', 'over_edge_ceiling', 'failed', 3, 'ZZ DEMO HTTP 400', now() - interval '1 day', now() - interval '2 days')
  returning id into v_bad;

  v_r := public.fn_sales_engineer_cad_read_wait();
  -- 1. a drawing unread past the reader's interval is a finding although nobody polls it
  if not exists (select 1 from public.it_engineer_finding where issue_key = 'duty:cad_read_wait:' || v_old and closed_at is null) then
    v_fail := v_fail || '1: an unread drawing of 3 h raised nothing: ' || v_r::text || '; '; end if;
  -- 2. a drawing inside the interval is not
  if exists (select 1 from public.it_engineer_finding where issue_key = 'duty:cad_read_wait:' || v_new) then
    v_fail := v_fail || '2: a drawing queued 20 minutes ago raised a finding; '; end if;
  -- 3. a drawing the reader failed is a finding
  if not exists (select 1 from public.it_engineer_finding where issue_key = 'duty:cad_read_wait:' || v_bad and closed_at is null) then
    v_fail := v_fail || '3: a failed read raised nothing; '; end if;
  -- 4. it clears when the reader finishes the job
  update public.cad_read_jobs set status = 'done', finished_at = now() where id = v_old;
  perform public.fn_sales_engineer_cad_read_wait();
  if exists (select 1 from public.it_engineer_finding where issue_key = 'duty:cad_read_wait:' || v_old and closed_at is null) then
    v_fail := v_fail || '4: a read drawing kept its finding; '; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK: an unread or failed CAD drawing is a finding without a poll, and clears when read' else 'PROBE FAILED: ' || v_fail end;
end $probe$;
