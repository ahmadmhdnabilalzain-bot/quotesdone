-- THE KNOWLEDGE EXAM SCORES THE BILINGUAL PATH AND HOLDS AN ARABIC FLOOR (5 Oct 2026, it_engineer; ledger 1085, stage 1).
--
-- MEASURED. The daily exam (the_knowledge_exam_is_scored_in_slices_that_fit_the_duty_tick.sql) puts every question to
-- fn_reason_retrieve, the English-only gte-small path. On 4 Oct 2026 it recorded Arabic recall@5 0.000-0.071 on every
-- seat (ceo 0, accountant 0, it_engineer 0.048, marketing 0.064, customer_support 0.068, sales_engineer 0.071) while
-- English read 0.402-0.682. think() reads fn_reason_retrieve_ml whenever fn_ml_read_space() = 'ml', so the exam scored
-- a path the seats do not use, and no Arabic floor existed at all. The local evaluation of the fused path
-- (scripts/eval/multilingual_recall_eval.mjs, 24 Sep) read Arabic 0.52-0.60.
--
-- FIX.
--   1. Every exam question carries a multilingual vector, embedding_ml, made by the production model (embed_ml
--      'query', loaded by scripts/kb/load_knowledge_eval_questions.mjs). Until every question has one, the exam scores
--      nothing and raises knowledge_recall:no_ml_vectors naming the command.
--   2. Each question is scored through fn_reason_retrieve_ml(seat, embedding_ml, embedding, 6): the same fused call
--      think() makes (multilingual vector first, gte vector second). recall@5 is computed exactly as before.
--   3. Timed on production 5 Oct 2026 (aborted block, 20 calls): 67 ms a call warm, 272 ms cold. 150 a beat would
--      overrun the tick's 8 s, so a beat now scores until 4 s have passed, then stops. 2,354 questions take about
--      40 beats, roughly ten hours of the 15-minute duty.
--   4. Each day's row records path = 'ml'. A fall is measured only against an earlier 'ml' day, never against the
--      gte rows before this file, so the switch itself is not read as a fall.
--   5. THE ARABIC FLOOR is set by the first production run of the 'ml' path: per seat, that day's Arabic recall rounded
--      DOWN to the 0.05 below it, stored in seat_knowledge_recall_floor, never lowered by this routine. Under it, or
--      0.10 down on the last 'ml' day, is a finding, exactly like English (whose 0.35 floor is unchanged).
--
-- Prevented by: scripts/checks/the_knowledge_exam_scores_the_bilingual_path.test.mjs (the exam reads the ml retriever
-- with both vectors, the floor table exists and is never lowered, and the beat is time-bound).

select '[1]'::vector <-> '[1]'::vector as loads_pgvector;

alter table public.seat_knowledge_eval_question add column if not exists embedding_ml vector(384);
alter table public.seat_knowledge_recall add column if not exists path text not null default 'gte';

create table if not exists public.seat_knowledge_recall_floor (
  seat text not null,
  lang text not null check (lang in ('en', 'ar')),
  floor numeric not null check (floor >= 0 and floor <= 1),
  set_on date not null,
  set_from numeric not null,
  primary key (seat, lang)
);
alter table public.seat_knowledge_recall_floor enable row level security;
drop policy if exists seat_knowledge_recall_floor_service_role_only on public.seat_knowledge_recall_floor;
create policy seat_knowledge_recall_floor_service_role_only on public.seat_knowledge_recall_floor as permissive for all to public using (false) with check (false);
revoke all on public.seat_knowledge_recall_floor from anon, authenticated;

create or replace function public.fn_it_engineer_knowledge_recall_exam()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_day date := (now() at time zone 'Asia/Dubai')::date; s record; q record; p public.seat_knowledge_recall;
  v_floor numeric; v_bad text; v_out jsonb := '[]'::jsonb; v_raised int := 0; v_scored int := 0; v_left int;
  v_missing int; v_t timestamptz := clock_timestamp();
begin
  if not exists (select 1 from public.seat_knowledge_eval_question) then
    perform public.fn_it_engineer_finding_upsert('knowledge_recall:no_questions',
      'The daily knowledge exam has no questions loaded, so no seat''s knowledge is being examined',
      'public.seat_knowledge_eval_question', 'agent_facing', 6, jsonb_build_object('owner_seat', 'it_engineer'),
      '{}'::text[], array['run node scripts/kb/load_knowledge_eval_questions.mjs'], 'it_engineer');
    return jsonb_build_object('day', v_day, 'questions', 0, 'raised', 1);
  end if;
  update public.it_engineer_finding set closed_at = now(), close_note = 'questions are loaded (knowledge_recall)'
   where issue_key = 'knowledge_recall:no_questions' and closed_at is null;

  select count(*) into v_missing from public.seat_knowledge_eval_question where embedding_ml is null;
  if v_missing > 0 then
    perform public.fn_it_engineer_finding_upsert('knowledge_recall:no_ml_vectors',
      v_missing || ' exam questions have no multilingual vector, so the bilingual path the seats read is not being examined',
      'public.seat_knowledge_eval_question.embedding_ml', 'agent_facing', v_missing,
      jsonb_build_object('owner_seat', 'it_engineer', 'missing', v_missing),
      '{}'::text[], array['run node scripts/kb/load_knowledge_eval_questions.mjs --ml'], 'it_engineer');
    return jsonb_build_object('day', v_day, 'missing_ml', v_missing, 'raised', 1);
  end if;
  update public.it_engineer_finding set closed_at = now(), close_note = 'every question has its ml vector (knowledge_recall)'
   where issue_key = 'knowledge_recall:no_ml_vectors' and closed_at is null;

  if exists (select 1 from public.seat_knowledge_recall where day = v_day and path = 'ml') then
    return jsonb_build_object('day', v_day, 'done', true);
  end if;

  -- one time-bound beat: score today's unscored questions until 4 s have passed (67 ms a call warm, measured)
  for q in select * from public.seat_knowledge_eval_question q
            where not exists (select 1 from public.seat_knowledge_recall_answer a where a.day = v_day and a.question_id = q.id)
            order by q.id limit 150
  loop
    exit when clock_timestamp() - v_t > interval '4 seconds';
    insert into public.seat_knowledge_recall_answer (day, question_id, seat, lang, recall)
    select v_day, q.id, q.seat, q.lang,
           (select count(distinct regexp_replace(x->>'id', '@ar$', ''))
              from jsonb_array_elements(public.fn_reason_retrieve_ml(q.seat, q.embedding_ml, q.embedding, 6)) with ordinality t(x, n)
             where n <= 5 and regexp_replace(x->>'id', '@ar$', '') = any(q.expected))::numeric
           / (select count(distinct e) from unnest(q.expected) e)
    on conflict do nothing;
    v_scored := v_scored + 1;
  end loop;
  select count(*) into v_left from public.seat_knowledge_eval_question q
   where not exists (select 1 from public.seat_knowledge_recall_answer a where a.day = v_day and a.question_id = q.id);
  if v_left > 0 then
    return jsonb_build_object('day', v_day, 'scored', v_scored, 'left', v_left);
  end if;

  for s in
    select seat, count(*) filter (where lang = 'en') as questions,
           round(avg(recall) filter (where lang = 'en'), 3) as en, round(avg(recall) filter (where lang = 'ar'), 3) as ar
      from public.seat_knowledge_recall_answer where day = v_day group by seat
  loop
    select * into p from public.seat_knowledge_recall where seat = s.seat and day < v_day and path = 'ml' order by day desc limit 1;
    insert into public.seat_knowledge_recall (day, seat, questions, recall_en, recall_ar, path)
    values (v_day, s.seat, s.questions, s.en, s.ar, 'ml')
    on conflict (day, seat) do update set questions = excluded.questions, recall_en = excluded.recall_en,
                                          recall_ar = excluded.recall_ar, path = 'ml', measured_at = now();
    -- the Arabic floor: set once, by the first 'ml' day, to the 0.05 at or below it; never lowered here
    if s.ar is not null then
      insert into public.seat_knowledge_recall_floor (seat, lang, floor, set_on, set_from)
      values (s.seat, 'ar', floor(s.ar * 20) / 20, v_day, s.ar) on conflict (seat, lang) do nothing;
    end if;
    select f.floor into v_floor from public.seat_knowledge_recall_floor f where f.seat = s.seat and f.lang = 'ar';
    v_bad := case when s.en is null or s.en < 0.35 then 'English under the floor 0.35'
                  when p.recall_en is not null and p.recall_en - s.en >= 0.10 then 'English down from ' || p.recall_en || ' on ' || p.day
                  when s.ar is null or s.ar < greatest(v_floor, 0.10) then 'Arabic under the floor ' || greatest(v_floor, 0.10)
                  when p.recall_ar is not null and p.recall_ar - s.ar >= 0.10 then 'Arabic down from ' || p.recall_ar || ' on ' || p.day end;
    if v_bad is not null then
      v_raised := v_raised + 1;
      perform public.fn_it_engineer_finding_upsert('knowledge_recall:' || s.seat,
        'The ' || s.seat || ' seat finds its own knowledge less: recall@5 EN ' || coalesce(s.en::text, 'unmeasured')
          || ', AR ' || coalesce(s.ar::text, 'unmeasured') || ' (' || v_bad || ')',
        'public.seat_knowledge_recall / public.fn_reason_retrieve_ml', 'agent_facing', s.questions::int,
        jsonb_build_object('seat', s.seat, 'owner_seat', 'it_engineer', 'recall_en', s.en, 'recall_ar', s.ar,
                           'floor_ar', v_floor, 'previous', to_jsonb(p)),
        '{}'::text[], array['which pack''s questions stopped finding their entries, and whether rows lost their vectors'], 'it_engineer');
    else
      update public.it_engineer_finding set closed_at = now(), close_note = 'recall back within bounds (knowledge_recall)'
       where issue_key = 'knowledge_recall:' || s.seat and closed_at is null;
    end if;
    v_out := v_out || jsonb_build_object('seat', s.seat, 'questions', s.questions, 'recall_en', s.en, 'recall_ar', s.ar,
                                         'floor_ar', v_floor, 'raised', v_bad is not null);
  end loop;
  delete from public.seat_knowledge_recall_answer where day < v_day - 7;
  return jsonb_build_object('day', v_day, 'path', 'ml', 'seats', v_out, 'raised', v_raised);
end $fn$;
revoke execute on function public.fn_it_engineer_knowledge_recall_exam() from public, anon, authenticated;
grant execute on function public.fn_it_engineer_knowledge_recall_exam() to service_role;

-- Today's answers were scored on the gte path: drop them so today is scored again on the ml path.
delete from public.seat_knowledge_recall_answer where day = (now() at time zone 'Asia/Dubai')::date
   and not exists (select 1 from public.seat_knowledge_recall r
                    where r.day = (now() at time zone 'Asia/Dubai')::date and r.path = 'ml');

update public.seat_duty set
       what = 'No model: every verified pack''s eval questions, English and Arabic, put to the bilingual retriever the seats read (fn_reason_retrieve_ml), a 4-second beat at a time until the day is scored; recall@5 per seat recorded; English under 0.35, Arabic under the floor set by its first run, or a 0.10 fall is a finding.',
       owner_file = 'scripts/sql/the_knowledge_exam_scores_the_bilingual_path_and_holds_an_arabic_floor.sql'
 where duty = 'it_engineer.knowledge_recall';

-- Probe (nothing kept): the routine runs inside a block that is rolled back, and one fused call is short enough that a
-- beat (it starts no call after 4 s) ends inside the tick's 8 s: the worst beat is 4 s plus one call, so a call must
-- stay under 1.5 s. Measured 5 Oct 2026: 67 ms warm; 286 ms with the gte vector standing in for the ml one.
create temporary table if not exists qd_probe_exam_ms (ms numeric) on commit drop;
do $$ declare t timestamptz := clock_timestamp(); v_ms numeric; begin
  begin
    perform public.fn_it_engineer_knowledge_recall_exam();
    v_ms := extract(epoch from clock_timestamp() - t) * 1000;
    raise exception 'qd_probe_rollback';
  exception when others then
    if sqlerrm <> 'qd_probe_rollback' then raise; end if;
  end;
  -- at apply no question has its ml vector yet, so the routine returns at no_ml_vectors; time real fused calls too:
  -- 20 questions, their gte vector standing in for the ml one (same dimension)
  t := clock_timestamp();
  perform public.fn_reason_retrieve_ml(q.seat, q.embedding, q.embedding, 6)
     from (select * from public.seat_knowledge_eval_question order by id limit 20) q;
  v_ms := extract(epoch from clock_timestamp() - t) * 1000 / 20;   -- ms per fused call
  insert into qd_probe_exam_ms values (v_ms);
end $$;
select case when (select count(*) from information_schema.columns
                   where table_name = 'seat_knowledge_eval_question' and column_name = 'embedding_ml') = 1
             and exists (select 1 from pg_class where relname = 'seat_knowledge_recall_floor')
             and (select ms from qd_probe_exam_ms) < 1500
            then 'PROBE OK' else 'PROBE FAILED: one fused call takes ' || coalesce((select ms from qd_probe_exam_ms)::text, '?') || ' ms' end as verdict;
