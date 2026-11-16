-- PROBE (pure, no DDL, aborted transaction) for a_site_photo_is_queued_and_recorded_on_its_request_in_one_statement.sql.
-- Seat: sales_engineer. 15 Nov 2026. LOCAL ONLY (a Postgres 16 built from the schema mirror): its setup rows are written with
-- session_replication_role = replica, which only a superuser may set, so on a hosted database it stops at its first line.
-- With triggers off for the setup, nothing it inserts can start a match, a notice or an event; it always ends in
-- raise exception 'CHK<<json>>', so every row rolls back. Its two customers have example.invalid addresses and ZZ DEMO names.
-- Real rows of the three tables are counted and hashed before and after and must not move.
--   a  the queue takes a site_photo_check job, still takes every value it took before, and still refuses an unknown one
--   b  a photo recorded on the intake: shot kept when asked, null when not; the brief is not touched
--   c  a second photo is ADDED (both kept); the same job again adds nothing; another customer's job is refused
--   d  the asked shots are set once and never replaced; the No-photos answer is kept
--   e  the wrong customer finds no row (null, nothing written); at most 12 photos are kept
--   f  on an open request the photo goes to spec.site_photos and every other spec key stays as it was
--   g  both routines are closed to anon and authenticated; service_role may record
do $$
declare fail text := '';
  c1 uuid := gen_random_uuid(); c2 uuid := gen_random_uuid(); it uuid := gen_random_uuid(); inq uuid := gen_random_uuid();
  j1 uuid; j2 uuid; jx uuid; r jsonb; n int; w text;
  b_jobs int; b_it text; b_inq text; a_jobs int; a_it text; a_inq text;
  asked jsonb := '[{"shot":"ZZ Each indoor unit, from the front","shot_ar":"zz","from":"replacements"},{"shot":"ZZ Where the water drains","shot_ar":"zz","from":"drainage"}]';
  sig text := 'public.fn_site_photos_record(text, uuid, uuid, text, jsonb, text, jsonb, boolean)';
begin
  select count(*) into b_jobs from public.cad_read_jobs;
  select md5(coalesce(string_agg(id::text || coalesce(site_photos::text, '') || coalesce(brief::text, ''), '|' order by id), '')) into b_it from public.inquiry_intake;
  select md5(coalesce(string_agg(id::text || coalesce(spec::text, ''), '|' order by id), '')) into b_inq from public.inquiries;

  perform set_config('session_replication_role', 'replica', true);
  insert into public.customers (id, email, full_name) values (c1, 'zz-demo-photo-probe-1@example.invalid', 'ZZ DEMO photo probe 1'), (c2, 'zz-demo-photo-probe-2@example.invalid', 'ZZ DEMO photo probe 2');
  insert into public.inquiry_intake (id, customer_id, email, status, turns, brief) values (it, c1, 'zz-demo-photo-probe-1@example.invalid', 'needs_info', '[]', '{"details":{"zz_area":"40 m2"}}');
  insert into public.inquiries (id, customer_id, status, category, raw_input, spec) values (inq, c1, 'sent', 'hvac', 'ZZ DEMO probe request', '{"zz_area":"40 m2","zz_units":"3"}');
  perform set_config('session_replication_role', 'origin', true);

  -- a
  foreach w in array array['over_edge_ceiling', 'edge_worker_died', 'edge_reader_failed', 'pdf_lengths_worker_died', 'scan_needs_ocr'] loop
    begin
      insert into public.cad_read_jobs (customer_id, source_path, why) values (c1, 'drawings/zz-demo/' || w, w);
    exception when check_violation then fail := fail || w || ' is no longer queued; '; end;
  end loop;
  insert into public.cad_read_jobs (customer_id, source_path, why, boq_in) values (c1, 'drawings/zz-demo/p1.jpg', 'site_photo_check', '{"shot":null}') returning id into j1;
  insert into public.cad_read_jobs (customer_id, source_path, why, boq_in) values (c1, 'drawings/zz-demo/p2.jpg', 'site_photo_check', '{"shot":null}') returning id into j2;
  insert into public.cad_read_jobs (customer_id, source_path, why, boq_in) values (c2, 'drawings/zz-demo/x.jpg', 'site_photo_check', '{"shot":null}') returning id into jx;
  begin
    insert into public.cad_read_jobs (customer_id, source_path, why) values (c1, 'drawings/zz-demo/bad', 'zz_not_a_reason');
    fail := fail || 'an unknown why was queued; ';
  exception when check_violation then null; end;

  -- b
  r := public.fn_site_photos_record('inquiry_intake', it, c1, null, jsonb_build_array(jsonb_build_object('job_id', j1, 'shot', 'ZZ Each indoor unit, from the front')), 'portal', asked, false);
  if r is null or jsonb_array_length(r->'photos') <> 1 or r->'photos'->0->>'shot' <> 'ZZ Each indoor unit, from the front' or jsonb_array_length(r->'asked') <> 2
    then fail := fail || 'the first photo was not recorded with its shot: ' || coalesce(r::text, 'null') || '; '; end if;
  if (select brief from public.inquiry_intake where id = it) <> '{"details":{"zz_area":"40 m2"}}'::jsonb then fail := fail || 'the brief was touched; '; end if;

  -- c
  r := public.fn_site_photos_record('inquiry_intake', it, c1, null, jsonb_build_array(jsonb_build_object('job_id', j2, 'shot', 'ZZ a shot nobody asked')), 'portal', null, false);
  if jsonb_array_length(r->'photos') <> 2 or r->'photos'->1->>'job_id' <> j2::text or r->'photos'->1->'shot' <> 'null'::jsonb
    then fail := fail || 'the second photo was not added beside the first: ' || r::text || '; '; end if;
  r := public.fn_site_photos_record('inquiry_intake', it, c1, null, jsonb_build_array(jsonb_build_object('job_id', upper(j1::text))), 'portal', null, false);
  if jsonb_array_length(r->'photos') <> 2 then fail := fail || 'the same job was added twice; '; end if;
  r := public.fn_site_photos_record('inquiry_intake', it, c1, null, jsonb_build_array(jsonb_build_object('job_id', jx)), 'portal', null, false);
  if jsonb_array_length(r->'photos') <> 2 then fail := fail || 'another customer''s photo job was recorded; '; end if;

  -- d
  r := public.fn_site_photos_record('inquiry_intake', it, c1, null, '[]', 'portal', '[{"shot":"ZZ replaced"}]', true);
  if r->'asked'->0->>'shot' <> 'ZZ Each indoor unit, from the front' then fail := fail || 'the asked shots were replaced; '; end if;
  if r->'declined' <> 'true'::jsonb then fail := fail || 'the No-photos answer was not kept; '; end if;

  -- e
  r := public.fn_site_photos_record('inquiry_intake', it, c2, 'zz-demo-photo-probe-1@example.invalid', jsonb_build_array(jsonb_build_object('job_id', jx)), 'portal', null, false);
  if r is not null then fail := fail || 'another customer wrote on this intake; '; end if;
  insert into public.cad_read_jobs (customer_id, source_path, why) select c1, 'drawings/zz-demo/many' || g, 'site_photo_check' from generate_series(1, 14) g;
  r := public.fn_site_photos_record('inquiry_intake', it, c1, null,
         (select jsonb_agg(jsonb_build_object('job_id', id)) from public.cad_read_jobs where customer_id = c1 and source_path like 'drawings/zz-demo/many%'), 'portal', null, false);
  if jsonb_array_length(r->'photos') <> 12 then fail := fail || 'the request kept ' || jsonb_array_length(r->'photos') || ' photos, not 12; '; end if;

  -- f
  r := public.fn_site_photos_record('inquiries', inq, c1, null, jsonb_build_array(jsonb_build_object('job_id', j1)), 'whatsapp', null, false);
  if r is null or r->'photos'->0->>'via' <> 'whatsapp' then fail := fail || 'the open request did not record the WhatsApp photo: ' || coalesce(r::text, 'null') || '; '; end if;
  if (select spec - 'site_photos' from public.inquiries where id = inq) <> '{"zz_area":"40 m2","zz_units":"3"}'::jsonb then fail := fail || 'another spec key moved; '; end if;
  r := public.fn_site_photos_record('inquiries', inq, c1, null, jsonb_build_array(jsonb_build_object('job_id', j2)), 'whatsapp', null, false);
  if jsonb_array_length(r->'photos') <> 2 then fail := fail || 'a second WhatsApp photo did not stay beside the first; '; end if;

  -- g
  if has_function_privilege('anon', sig, 'execute') or has_function_privilege('authenticated', sig, 'execute') then fail := fail || 'the writer is open to a client role; '; end if;
  if has_function_privilege('anon', 'public.fn_site_photos_merged(jsonb, uuid, jsonb, text, jsonb, boolean)', 'execute')
     or has_function_privilege('authenticated', 'public.fn_site_photos_merged(jsonb, uuid, jsonb, text, jsonb, boolean)', 'execute') then fail := fail || 'the merge is open to a client role; '; end if;
  if not has_function_privilege('service_role', sig, 'execute') then fail := fail || 'service_role cannot record; '; end if;
  if not (select prosecdef from pg_proc where oid = sig::regprocedure) then fail := fail || 'the writer is not a definer; '; end if;
  if not exists (select 1 from pg_proc where oid = sig::regprocedure and proconfig @> array['search_path=public, pg_temp'])
     and not exists (select 1 from pg_proc where oid = sig::regprocedure and array_to_string(proconfig, ',') like 'search_path=%public%pg_temp%') then fail := fail || 'the writer has no pinned search_path; '; end if;

  -- clean up and count the real rows
  delete from public.cad_read_jobs where customer_id in (c1, c2);
  perform set_config('session_replication_role', 'replica', true);
  delete from public.inquiries where id = inq; delete from public.inquiry_intake where id = it; delete from public.customers where id in (c1, c2);
  perform set_config('session_replication_role', 'origin', true);
  select count(*) into a_jobs from public.cad_read_jobs;
  select md5(coalesce(string_agg(id::text || coalesce(site_photos::text, '') || coalesce(brief::text, ''), '|' order by id), '')) into a_it from public.inquiry_intake;
  select md5(coalesce(string_agg(id::text || coalesce(spec::text, ''), '|' order by id), '')) into a_inq from public.inquiries;
  if a_jobs <> b_jobs or a_it <> b_it or a_inq <> b_inq then fail := fail || 'real rows moved; '; end if;
  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when fail = '' then 'PROBE OK' else 'PROBE FAILED: ' || fail end, 'real_jobs', b_jobs, 'real_jobs_after', a_jobs);
end $$;
