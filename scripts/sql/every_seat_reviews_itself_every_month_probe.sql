-- PROBE: every seat's monthly self-review grades its exam on live retrieval, scores the senior-hire checklist, records
-- the trend, opens the seat's own improvement for what slipped, closes it when nothing slips, and runs as a seat duty.
-- Pure probe -- NO DDL. Seat: ceo. 29 Sep 2026. Pairs with every_seat_reviews_itself_every_month.sql.
--   node scripts/qsql.mjs scripts/sql/every_seat_reviews_itself_every_month_probe.sql
--
-- HOW IT STAYS HARMLESS: every write is inside an inner block that ends in a raised exception. Its exam items are
-- ZZ DEMO rows (item ids zzdemo-*, checklist lines ZZ-*); its months are 2099; it emails nobody.
-- THE ITEMS ARE REAL RETRIEVAL: zzdemo-01 carries the stored vector of one live accountant_knowledge row and a fact
-- taken from that row's first 1,200 characters, so fn_reason_retrieve must put it in the top 5 with the fact (PASS);
-- zzdemo-02 asks the same with a fact that is nowhere (FAIL: facts missing); zzdemo-03 has no vector (FAIL).

do $$
declare
  v_row record; v_feb jsonb; v_ceo jsonb; v_again jsonb; v_mar jsonb; v_wrap jsonb; v_g jsonb;
  v_rev public.seat_self_review; v_imp public.ceo_improvement; v_ceo_imp text; v_closed_status text;
  v_duties int; v_missing_routines int; v_left int;
begin
  set local statement_timeout = '60s';
  begin
    select a.record_id, a.embedding_gte, substr(a.content, 1, 40) as fact into v_row
      from public.accountant_knowledge a
     where a.embedding_gte is not null and a.runtime_index_eligible and length(a.content) > 60
     order by a.record_id limit 1;
    if v_row.record_id is null then raise exception 'no embedded accountant_knowledge row to build the probe item from'; end if;

    insert into public.seat_exam_item (seat, item_id, checklist, q_en, expected_entry_ids, expected_facts, q_vec, source_file) values
      ('accountant', 'zzdemo-01', 'ZZ-01', 'ZZ DEMO question', array[v_row.record_id], array[v_row.fact], v_row.embedding_gte, 'zzdemo'),
      ('accountant', 'zzdemo-02', 'ZZ-02', 'ZZ DEMO question', array[v_row.record_id], array['ZZ DEMO fact that is nowhere'], v_row.embedding_gte, 'zzdemo'),
      ('accountant', 'zzdemo-03', 'ZZ-01', 'ZZ DEMO question', array[v_row.record_id], array[v_row.fact], null, 'zzdemo');
    -- last month: everything passed
    insert into public.seat_self_review (month, seat, items, passed, rate, checklist_lines, checklist_passed, checklist_rate, trend, passed_items, passed_lines)
    values (date '2099-01-01', 'accountant', 3, 3, 1.0, 2, 2, 1.0, 'first', array['zzdemo-01', 'zzdemo-02', 'zzdemo-03'], array['ZZ-01', 'ZZ-02']);

    v_g := public.fn_seat_exam_grade('accountant');
    v_feb := public.fn_seat_self_review(date '2099-02-01', 'accountant');
    select * into v_rev from public.seat_self_review where month = date '2099-02-01' and seat = 'accountant';
    select * into v_imp from public.ceo_improvement where id = v_rev.improvement_id;
    v_again := public.fn_seat_self_review(date '2099-02-01', 'accountant');
    v_ceo := public.fn_seat_self_review(date '2099-02-01', 'ceo');
    select status into v_ceo_imp from public.ceo_improvement where id = (v_ceo->>'improvement_id')::bigint;

    -- the seat repairs its exam: next month nothing slips and February's improvement closes
    delete from public.seat_exam_item where item_id in ('zzdemo-02', 'zzdemo-03');
    v_mar := public.fn_seat_self_review(date '2099-03-01', 'accountant');
    select status into v_closed_status from public.ceo_improvement where id = v_rev.improvement_id;

    -- the duty door of every seat exists and runs
    select count(*), count(*) filter (where not public.fn_seat_duty_routine_exists(routine)) into v_duties, v_missing_routines
      from public.seat_duty where duty like '%.self_review' and enabled
       and owner_seat in (select role_id from public.org_role where status = 'active');
    v_wrap := public.fn_marketing_self_review();
    raise exception 'qd_probe_rollback';
  exception when raise_exception then
    if sqlerrm <> 'qd_probe_rollback' then raise; end if;
  end;

  select count(*) into v_left from public.seat_exam_item where item_id like 'zzdemo-%';
  v_left := v_left + (select count(*) from public.seat_self_review where month >= date '2099-01-01')
                   + (select count(*) from public.ceo_improvement where source_kind = 'self_review' and source_ref like '%:2099-%');

  if (select count(*) from jsonb_array_elements(v_g) x where (x->>'pass')::boolean) <> 1
     or not exists (select 1 from jsonb_array_elements(v_g) x where x->>'id' = 'zzdemo-01' and (x->>'pass')::boolean)
     or not exists (select 1 from jsonb_array_elements(v_g) x where x->>'id' = 'zzdemo-02' and x->>'reason' like 'facts missing%')
     or not exists (select 1 from jsonb_array_elements(v_g) x where x->>'id' = 'zzdemo-03' and x->>'reason' like 'not embedded%') then
    raise exception 'the grader did not pass 01 and fail 02 (facts) and 03 (not embedded): %', v_g;
  end if;
  if v_rev.items <> 3 or v_rev.passed <> 1 or v_rev.checklist_lines <> 2 or v_rev.checklist_passed <> 0 or v_rev.trend <> 'down'
     or v_rev.prev_rate <> 1.0 then
    raise exception 'February scored wrong: items % passed % lines % lines passed % trend % prev %', v_rev.items, v_rev.passed,
      v_rev.checklist_lines, v_rev.checklist_passed, v_rev.trend, v_rev.prev_rate;
  end if;
  if not (array_to_string(v_rev.slipped, '|') like '%exam item zzdemo-02 passed%' and array_to_string(v_rev.slipped, '|') like '%checklist line ZZ-02 passed%'
          and array_to_string(v_rev.slipped, '|') like '%exam score fell from 100%' and array_to_string(v_rev.slipped, '|') like '%not embedded%') then
    raise exception 'February did not name every slip: %', v_rev.slipped;
  end if;
  if v_imp.id is null or v_imp.seat <> 'accountant' or v_imp.source_kind <> 'self_review' or v_imp.due_on <> date '2099-03-05'
     or v_imp.close_check is null or v_imp.handoff_id is null or v_imp.task_id is null then
    raise exception 'the seat did not open its own tracked improvement (seat, due 5 Mar, check, task, handoff): %', to_jsonb(v_imp);
  end if;
  if not coalesce((v_again->>'already')::boolean, false) then raise exception 'a second run of the month was not a no-op: %', v_again; end if;
  if v_ceo->>'trend' <> 'no_exam' or v_ceo_imp is null then raise exception 'a seat with no exam was not flagged with an improvement: %', v_ceo; end if;
  if (v_mar->>'slipped')::int <> 0 or (v_mar->>'trend') <> 'up' or (v_mar->>'closed')::int < 1 or v_closed_status <> 'done' then
    raise exception 'March did not close February''s improvement: % (status %)', v_mar, v_closed_status;
  end if;
  if v_duties <> (select count(*) from public.org_role where status = 'active') or v_missing_routines <> 0 then
    raise exception 'self-review duties: % for % active seats, % with no routine', v_duties, (select count(*) from public.org_role where status = 'active'), v_missing_routines;
  end if;
  if not coalesce((v_wrap->>'ok')::boolean, false) then raise exception 'the marketing duty door did not run: %', v_wrap; end if;
  if v_left <> 0 then raise exception 'the rollback left % row(s)', v_left; end if;

  perform set_config('qd.probe_verdict',
    format('PROBE OK grader pass/facts/not-embedded on live retrieval; Feb 1/3 items, 0/2 checklist lines, trend down, %s slips named, own improvement #%s due %s with task+handoff; rerun no-op; ceo no_exam flagged; Mar nothing slipped, trend up, Feb improvement closed; %s self_review duties, marketing door ok; left_behind=0',
           cardinality(v_rev.slipped), v_imp.id, v_imp.due_on, v_duties), true);
exception when others then
  perform set_config('qd.probe_verdict', 'PROBE FAILED ' || sqlerrm, true);
end $$;

select coalesce(current_setting('qd.probe_verdict', true), 'PROBE FAILED (the block set no verdict)') as verdict;

