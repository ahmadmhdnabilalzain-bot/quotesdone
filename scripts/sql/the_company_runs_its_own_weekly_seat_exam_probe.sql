-- PROBE of the_company_runs_its_own_weekly_seat_exam.sql. Seat: it_engineer (agent: L7_JOBS). 16 Nov 2026.
-- LOCAL ONLY (a Postgres 16 copy built from the mirror, with net.http_post stood in). It always raises CHK<<...>>, so every
-- row it writes rolls back. Its items are ZZ DEMO items of its own; it names no real seat_exam_item and touches no real ask.
-- Each case names what the founder asked (ledger 1084) or the alarm (1443: the company's own clock, and it says when it stops).
do $probe$
declare v_fail text := ''; r public.seat_exam_run; v_r jsonb; v_n jsonb; v_rec jsonb; v_les jsonb; v_req bigint; v_dow int;
        v_fix bigint; v_k bigint; v_items text[];
begin
  delete from public.seat_exam_run;                                  -- the probe's world: no run yet (rolled back)
  v_dow := extract(dow from (now() at time zone 'Asia/Dubai'))::int;
  insert into public.decision_policy (key, value) values ('seat_exam_weekly', '{}') on conflict (key) do nothing;
  update public.decision_policy set value = jsonb_build_object('per_seat', 3, 'week_aed_cap', 10, 'dow', v_dow, 'hour_dubai', 0,
                                                               'deadline_hours', 30, 'max_failed_posts', 3) where key = 'seat_exam_weekly';
  delete from public.seat_exam_item where item_id like 'zz-demo-%';
  insert into public.seat_exam_item (seat, item_id, checklist, q_en, expected_entry_ids, expected_facts, source_file) values
    ('accountant', 'zz-demo-a1', 'zz', 'ZZ DEMO Who bears the card fee on a reveal?', array['accountant:zz'], array['the company bears it'], 'knowledge/exams/zz.json'),
    ('accountant', 'zz-demo-a2', 'zz', 'ZZ DEMO What is the reveal fee?', array['accountant:zz'], array['3%'], 'knowledge/exams/zz.json'),
    ('accountant', 'zz-demo-a3', 'zz', 'ZZ DEMO When is VAT charged?', array['accountant:zz'], array['5%'], 'knowledge/exams/zz.json'),
    ('ceo', 'zz-demo-c1', 'zz', 'ZZ DEMO Can a seat sign a guarantee?', array['ceo:zz'], array['written authority'], 'knowledge/exams/zz.json');
  -- a3 has an open fix that was never made: it is planned first and its fix is made at its next miss
  insert into public.seat_exam_fix (seat, item_id, opened_run) values ('accountant', 'zz-demo-a3', 'zz-demo-old');

  -- 1. THE COMPANY'S OWN CLOCK: on its day and hour the duty opens the week's run and posts it to it_engineer
  v_r := public.fn_it_engineer_seat_exam_tick();
  select * into r from public.seat_exam_run where week = (v_r->>'week')::date;
  if r.id is null or r.status <> 'open' or r.request_id is null or r.posts <> 1 or v_r->>'action' <> 'posted' then
    v_fail := v_fail || '1: the run was not opened and posted: ' || v_r::text || '; '; end if;
  if (select convert_from(body, 'utf8') from net.http_request_queue where id = r.request_id) not like '%"action": "seat_exam"%' then
    v_fail := v_fail || '1: the post is not the seat_exam action; '; end if;
  select array_agg(e->>'item_id' order by o) into v_items from jsonb_array_elements(r.planned) with ordinality p(e, o) where e->>'item_id' like 'zz-demo-%';
  if v_items[1] <> 'zz-demo-a3' or not ('zz-demo-c1' = any (v_items)) then v_fail := v_fail || '1: the open fix is not asked first: ' || v_items::text || '; '; end if;
  -- one post in flight at a time
  if public.fn_it_engineer_seat_exam_tick()->>'action' <> 'waiting' then v_fail := v_fail || '1: a second post went while one was in flight; '; end if;

  -- 2. FRESH WORDINGS: next hands the earlier wordings of an item, never the expected facts' author a hint beyond them
  insert into public.seat_exam_asked (run_tag, seat, item_id, wording, answer, status, pass, graded_by, missing, asked_at)
  values ('zz-demo-old', 'accountant', 'zz-demo-a3', 'ZZ DEMO an earlier wording of a3', '', 'answered', false, 'claude', '{}', now() - interval '20 days');
  v_n := public.fn_seat_exam_next(r.id, 1);
  if v_n->'items'->0->>'item_id' <> 'zz-demo-a3' or v_n->'items'->0->'used_wordings' <> '["ZZ DEMO an earlier wording of a3"]'::jsonb then
    v_fail := v_fail || '2: next does not hand the item with its earlier wordings: ' || v_n::text || '; '; end if;

  -- 3. A MISTAKE LEADS TO AN ACTUAL FIX: a miss opens a fix, the lesson is written in the seat's own knowledge, fix_ref set
  v_rec := public.fn_seat_exam_record(r.id, 'zz-demo-a1', 'accountant', 'ZZ DEMO who carries the card charge?', 'a fee is added', 'stub',
                                      'answered', false, 'model', array['the company bears it']);
  v_fix := (v_rec->>'fix_id')::bigint;
  if v_fix is null or not (v_rec->>'lesson_needed')::boolean then v_fail := v_fail || '3: a miss opened no fix: ' || v_rec::text || '; '; end if;
  v_les := public.fn_seat_exam_fix_lesson(v_fix);
  v_k := (v_les->>'knowledge_id')::bigint;
  if not exists (select 1 from public.agent_knowledge where id = v_k and agent_key = 'accountant' and content like '%the company bears it%')
     or (select fix_ref from public.seat_exam_fix where id = v_fix) <> 'agent_knowledge:' || v_k
     or (select kind from public.seat_exam_fix where id = v_fix) <> 'knowledge_ingest' then
    v_fail := v_fail || '3: the lesson is not in the seat''s knowledge with the fix pointing at it: ' || v_les::text || '; '; end if;
  -- the open fix of a3 that was never made is made at its miss (lesson_needed), not left a record
  v_rec := public.fn_seat_exam_record(r.id, 'zz-demo-a3', 'accountant', 'ZZ DEMO VAT when?', 'never', 'stub', 'answered', false, 'code', array['5%']);
  if not (v_rec->>'lesson_needed')::boolean then v_fail := v_fail || '3: an unmade open fix was not made at its miss; '; end if;
  -- a wording outage opens no fix
  v_rec := public.fn_seat_exam_record(r.id, 'zz-demo-a2', 'accountant', '', '', null, 'no_wording', false, 'code', array['3%']);
  if (v_rec->>'fix_id') is not null or (v_rec->>'lesson_needed')::boolean then v_fail := v_fail || '3: a wording outage opened a fix; '; end if;
  -- a held answer (model hold, deadline) is not a knowledge miss: no fix, no lesson
  v_rec := public.fn_seat_exam_record(r.id, 'zz-demo-c1', 'ceo', 'ZZ DEMO may a seat guarantee?', '', null, 'held', false, 'code', array['written authority']);
  if (v_rec->>'fix_id') is not null or (v_rec->>'lesson_needed')::boolean then v_fail := v_fail || '3: a held answer opened a fix; '; end if;
  delete from public.seat_exam_asked where run_tag = r.run_tag and item_id = 'zz-demo-c1';   -- c1 stays unasked for the cases below
  -- an item asked twice in one run, or not planned, is refused
  begin perform public.fn_seat_exam_record(r.id, 'zz-demo-a1', 'accountant', 'x x x x x x x', '', null, 'answered', true, 'code', '{}');
        v_fail := v_fail || '3: an item was recorded twice in one run; '; exception when others then null; end;
  begin perform public.fn_seat_exam_record(r.id, 'not-planned', 'accountant', 'x x x x x x x', '', null, 'answered', true, 'code', '{}');
        v_fail := v_fail || '3: an unplanned item was recorded; '; exception when others then null; end;

  -- 4. A FIX THAT DID NOT HOLD IS THE IT ENGINEER'S FINDING; a pass after the fix closes it
  update public.agent_knowledge set created_at = now() - interval '1 hour' where id = v_k;
  insert into public.seat_exam_asked (run_tag, seat, item_id, wording, answer, status, pass, graded_by, missing)
  values ('zz-demo-later', 'accountant', 'zz-demo-a1', 'ZZ DEMO later wording', 'still wrong', 'answered', false, 'model', array['the company bears it']);
  -- the post came back 200: harvested, and the next tick posts again
  insert into net._http_response (id, status_code, content) values (r.request_id, 200, '{"ok":true}');
  v_r := public.fn_it_engineer_seat_exam_tick();
  if v_r->>'action' <> 'posted' then v_fail := v_fail || '4: a 200 was not harvested and posted again: ' || (v_r->>'action') || '; '; end if;
  if not exists (select 1 from public.it_engineer_finding where issue_key = 'duty:seat_exam:fix_did_not_hold:zz-demo-a1' and closed_at is null) then
    v_fail := v_fail || '4: a fix that did not hold raised no finding; '; end if;

  -- 5. THE WEEK'S AED CAP STOPS THE RUN, AND SAYS SO
  insert into public.ai_cost_log (fn, model_used, cost_aed, occurred_at) values ('knowledge_exam', 'zz-demo-stub', 10.5, now());
  if public.fn_seat_exam_next(r.id, 1)->>'stop' <> 'week_cap' then v_fail := v_fail || '5: next does not stop at the cap; '; end if;
  insert into net._http_response (id, status_code, content) select request_id, 200, '{}' from public.seat_exam_run where id = r.id;
  v_r := public.fn_it_engineer_seat_exam_tick();
  if (select status from public.seat_exam_run where id = r.id) <> 'capped' then v_fail := v_fail || '5: the run was not closed capped: ' || v_r::text || '; '; end if;
  if not exists (select 1 from public.it_engineer_finding where issue_key = 'duty:seat_exam:run:' || r.week and closed_at is null) then
    v_fail := v_fail || '5: a capped run raised no finding; '; end if;

  -- 6. THREE FAILED POSTS CLOSE THE RUN 'failed', AND A RUN NOT FINISHED IN TIME IS LATE (both findings)
  delete from public.ai_cost_log where fn = 'knowledge_exam' and cost_aed = 10.5;
  update public.seat_exam_run set status = 'open', finished_at = null, request_id = null, http_status = null where id = r.id;
  for i in 1..3 loop
    v_r := public.fn_it_engineer_seat_exam_tick();
    insert into net._http_response (id, status_code, error_msg) select request_id, 500, 'ZZ DEMO boom' from public.seat_exam_run where id = r.id;
  end loop;
  v_r := public.fn_it_engineer_seat_exam_tick();
  if (select status from public.seat_exam_run where id = r.id) <> 'failed' then
    v_fail := v_fail || '6: three failed posts did not fail the run: ' || (select row_to_json(s)::text from public.seat_exam_run s where id = r.id) || '; '; end if;
  update public.seat_exam_run set status = 'open', finished_at = null, failed_posts = 0, request_id = null, created_at = now() - interval '31 hours' where id = r.id;
  v_r := public.fn_it_engineer_seat_exam_tick();
  if not exists (select 1 from public.it_engineer_finding where issue_key = 'duty:seat_exam:late:' || r.week and closed_at is null) then
    v_fail := v_fail || '6: a late run raised no finding: ' || v_r::text || '; '; end if;

  -- 7. EVERY ITEM ASKED: the run is done and its run finding clears
  update public.seat_exam_run set created_at = now(), request_id = null, http_status = null where id = r.id;
  insert into public.seat_exam_asked (run_tag, seat, item_id, wording, answer, status, pass, graded_by, missing)
  select r.run_tag, e->>'seat', e->>'item_id', 'ZZ DEMO filled', '', 'answered', true, 'code', '{}'
    from jsonb_array_elements((select planned from public.seat_exam_run where id = r.id)) e
   where not exists (select 1 from public.seat_exam_asked a where a.run_tag = r.run_tag and a.item_id = e->>'item_id');
  v_r := public.fn_it_engineer_seat_exam_tick();
  if (select status from public.seat_exam_run where id = r.id) <> 'done' then v_fail := v_fail || '7: a fully asked run is not done: ' || v_r::text || '; '; end if;
  if exists (select 1 from public.it_engineer_finding where issue_key in ('duty:seat_exam:late:' || r.week, 'duty:seat_exam:run:' || r.week) and closed_at is null) then
    v_fail := v_fail || '7: the run''s findings did not clear when it finished; '; end if;

  -- 8. CLOSED to everyone but the service
  if has_function_privilege('anon', 'public.fn_seat_exam_record(bigint,text,text,text,text,text,text,boolean,text,text[])', 'execute')
     or has_function_privilege('authenticated', 'public.fn_it_engineer_seat_exam_tick()', 'execute')
     or has_table_privilege('anon', 'public.seat_exam_run', 'select') then v_fail := v_fail || '8: open outside the service role; '; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK: the week''s exam opens on its own clock, asks fresh wordings, fixes a miss in the seat''s knowledge, stops at its cap and raises a finding when it fails, is late or a fix does not hold'
                                    else 'PROBE FAILED: ' || v_fail end;
end $probe$;
