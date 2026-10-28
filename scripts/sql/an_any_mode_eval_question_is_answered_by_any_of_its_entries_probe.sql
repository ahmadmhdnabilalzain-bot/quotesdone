-- PROBE for an_any_mode_eval_question_is_answered_by_any_of_its_entries.sql. Seat: it_engineer, 27 Oct 2026.
-- It RUNS the routine (public.fn_it_engineer_knowledge_recall_exam), it does not read its text. Every path ends in
-- raise exception 'CHK<<...>>', so everything it does rolls back: it is replayed TOGETHER with its .sql in one request
-- through scripts/lib/safe_replay.mjs (replaySql), never applied, never run with autocommit statement by statement.
--
-- How: today's exam state and every real question are removed INSIDE the aborted transaction, and two fixture
-- questions are put in. Both carry the multilingual and gte-small vectors of one real verified-pack row, so that row
-- ranks first for them, and both expect that row plus an id no row has. The 'any' fixture must score 1; the all-required
-- fixture 0.5. On the routine before this change both score 0.5 (REPRODUCED). No real row is changed by the end:
-- the raise takes the deletes back with everything else.
do $probe$
declare
  c_row constant text := 'pest_control:product-distinctions';
  v_day date := (now() at time zone 'Asia/Dubai')::date;
  v_ml vector; v_gte vector; q_any bigint; q_all bigint; a_any numeric; a_all numeric; v_exam jsonb; n_real int;
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public'
                   and table_name = 'seat_knowledge_eval_question' and column_name = 'expected_any') then
    raise exception 'CHK<<NOT APPLIED: seat_knowledge_eval_question has no expected_any; replay this probe with its .sql>>';
  end if;
  select v.embedding into v_ml from public.knowledge_vector_ml v where v.src = 'sales_knowledge' and v.row_id = c_row;
  select s.embedding_gte into v_gte from public.sales_knowledge s where s.record_id = c_row and s.runtime_index_eligible;
  if v_ml is null or v_gte is null then
    raise exception 'CHK<<PROBE FAILED: % has no ml or gte vector, so the fixture cannot be ranked>>', c_row;
  end if;
  select count(*) into n_real from public.seat_knowledge_eval_question;

  delete from public.seat_knowledge_recall where day = v_day;
  delete from public.seat_knowledge_recall_answer where day = v_day;
  delete from public.seat_knowledge_eval_question;
  insert into public.seat_knowledge_eval_question (seat, pack, lang, question, expected, expected_any, embedding, embedding_ml, loaded_at)
  values ('sales_engineer', 'zz-probe.any', 'en', 'ZZ PROBE any-mode question', array[c_row, 'zz-probe:no-such-entry'], true,  v_gte, v_ml, now() - interval '1 day')
  returning id into q_any;
  insert into public.seat_knowledge_eval_question (seat, pack, lang, question, expected, expected_any, embedding, embedding_ml, loaded_at)
  values ('sales_engineer', 'zz-probe.all', 'en', 'ZZ PROBE all-required question', array[c_row, 'zz-probe:no-such-entry'], false, v_gte, v_ml, now() - interval '1 day')
  returning id into q_all;

  v_exam := public.fn_it_engineer_knowledge_recall_exam();
  select recall into a_any from public.seat_knowledge_recall_answer where day = v_day and question_id = q_any;
  select recall into a_all from public.seat_knowledge_recall_answer where day = v_day and question_id = q_all;

  if a_any = 1 and a_all = 0.5 then
    raise exception 'CHK<<PROBE OK: any-mode fixture % / all-required fixture % (real questions set aside inside the rollback: %) | exam %>>',
      a_any, a_all, n_real, left(v_exam::text, 300);
  elsif a_any = 0.5 and a_all = 0.5 then
    raise exception 'CHK<<REPRODUCED: the any-mode fixture scored % like the all-required one; the exam ignores expected_any | exam %>>',
      a_any, left(v_exam::text, 300);
  else
    raise exception 'CHK<<PROBE FAILED: any % all % (expected 1 and 0.5) | exam %>>', a_any, a_all, left(v_exam::text, 300);
  end if;
end $probe$;
