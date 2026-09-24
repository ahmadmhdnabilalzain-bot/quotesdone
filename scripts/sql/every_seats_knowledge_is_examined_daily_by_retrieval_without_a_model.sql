-- EVERY SEAT'S KNOWLEDGE IS EXAMINED DAILY BY RETRIEVAL, WITHOUT A MODEL.
-- Seat: it_engineer. 24 Sep 2026. Replaces the think()-asked, model-graded it_engineer.knowledge_exam (about AED 4.8/day,
-- 12 questions a day, retired by routine_work_is_code_and_the_model_answers_only_real_judgement.sql). The brief named a
-- knowledge_exam_retrieval_daily job to keep; measured 24 Sep 2026 it existed nowhere (cron.job, seat_duty,
-- resilience_step, pg_proc, repository), so retiring the model exam left no exam. This is that exam, as code.
--
-- WHAT IT MEASURES. Every verified pack under knowledge/ carries eval questions (English and Arabic) with the entry ids
-- that answer them. scripts/kb/load_knowledge_eval_questions.mjs loads them, embedded by the same free gte-small path
-- think() uses, into public.seat_knowledge_eval_question - one row per (seat that reads the pack, question, language).
-- Daily, fn_it_engineer_knowledge_recall_exam puts each question to the routine the seat calls at decision time,
-- public.fn_reason_retrieve(seat, vector, 6), and scores recall@5 = |expected entries among the first 5 rows| /
-- |expected| - exactly scripts/eval/knowledge_pack_eval.mjs (#897/#920), in SQL. Nothing matches a word; no model runs.
--
-- WHAT IT RAISES. The score per seat and day lands in public.seat_knowledge_recall. An it_engineer finding
-- (knowledge_recall:<seat>) opens when a seat's English recall@5 is under the floor 0.35 (knowledge_pack_eval.mjs FLOOR,
-- from the 23 Sep baseline; never lowered to go green) or fell 0.10 or more since its previous run; it closes when the
-- seat is back. No questions loaded at all is its own finding (knowledge_recall:no_questions), never a quiet pass.
-- Arabic is recorded, not gated (FLOOR.ar = 0: gte-small is an English model; the finding of the baseline).
--
-- The knowledge pass-rate duty (it_engineer.knowledge_pass_rate) stays enabled. The model exam's asked-but-never-
-- answered rows are stamped graded (no verdict) here, so that duty does not report them as a broken grader.
-- Pending: scripts/sql/pending/every_seats_knowledge_is_examined_daily_by_retrieval_without_a_model.txt.
-- Proved by: node --test scripts/checks/routine_work_never_goes_back_to_the_model.test.mjs

create table if not exists public.seat_knowledge_eval_question (
  id          bigserial primary key,
  seat        text not null,
  pack        text not null,
  lang        text not null check (lang in ('en', 'ar')),
  question    text not null check (btrim(question) <> ''),
  expected    text[] not null check (cardinality(expected) > 0),
  embedding   vector(384) not null,
  loaded_at   timestamptz not null default now(),
  unique (seat, pack, lang, question)
);
alter table public.seat_knowledge_eval_question enable row level security;
drop policy if exists seat_knowledge_eval_question_service_role_only on public.seat_knowledge_eval_question;
create policy seat_knowledge_eval_question_service_role_only on public.seat_knowledge_eval_question as permissive for all to public using (false) with check (false);
revoke all on public.seat_knowledge_eval_question from anon, authenticated;

create table if not exists public.seat_knowledge_recall (
  day         date not null,
  seat        text not null,
  questions   integer not null,
  recall_en   numeric,
  recall_ar   numeric,
  measured_at timestamptz not null default now(),
  primary key (day, seat)
);
alter table public.seat_knowledge_recall enable row level security;
drop policy if exists seat_knowledge_recall_service_role_only on public.seat_knowledge_recall;
create policy seat_knowledge_recall_service_role_only on public.seat_knowledge_recall as permissive for all to public using (false) with check (false);
revoke all on public.seat_knowledge_recall from anon, authenticated;

-- ponytail: every question every day (~2,200 retrievals at the 23 Sep pack count); sample per seat if the duty outgrows its run.
create or replace function public.fn_it_engineer_knowledge_recall_exam()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_day date := (now() at time zone 'Asia/Dubai')::date; s record; p public.seat_knowledge_recall; v_bad text; v_out jsonb := '[]'::jsonb; v_raised int := 0;
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

  for s in
    with scored as (
      select q.seat, q.lang,
             (select count(distinct regexp_replace(x->>'id', '@ar$', ''))
                from jsonb_array_elements(public.fn_reason_retrieve(q.seat, q.embedding, 6)) with ordinality t(x, n)
               where n <= 5 and regexp_replace(x->>'id', '@ar$', '') = any(q.expected))::numeric
             / (select count(distinct e) from unnest(q.expected) e) as recall
        from public.seat_knowledge_eval_question q)
    select seat, count(*) filter (where lang = 'en') as questions,
           round(avg(recall) filter (where lang = 'en'), 3) as en, round(avg(recall) filter (where lang = 'ar'), 3) as ar
      from scored group by seat
  loop
    select * into p from public.seat_knowledge_recall where seat = s.seat and day < v_day order by day desc limit 1;
    insert into public.seat_knowledge_recall (day, seat, questions, recall_en, recall_ar) values (v_day, s.seat, s.questions, s.en, s.ar)
    on conflict (day, seat) do update set questions = excluded.questions, recall_en = excluded.recall_en,
                                          recall_ar = excluded.recall_ar, measured_at = now();
    v_bad := case when s.en is null or s.en < 0.35 then 'under the floor 0.35'
                  when p.recall_en is not null and p.recall_en - s.en >= 0.10 then 'down from ' || p.recall_en || ' on ' || p.day end;
    if v_bad is not null then
      v_raised := v_raised + 1;
      perform public.fn_it_engineer_finding_upsert('knowledge_recall:' || s.seat,
        'The ' || s.seat || ' seat finds its own knowledge less: English recall@5 ' || coalesce(s.en::text, 'unmeasured') || ' (' || v_bad || ')',
        'public.seat_knowledge_recall / public.fn_reason_retrieve', 'agent_facing', s.questions::int,
        jsonb_build_object('seat', s.seat, 'owner_seat', 'it_engineer', 'recall_en', s.en, 'recall_ar', s.ar, 'previous', to_jsonb(p)),
        '{}'::text[], array['which pack''s questions stopped finding their entries, and whether rows lost their vectors'], 'it_engineer');
    else
      update public.it_engineer_finding set closed_at = now(), close_note = 'recall back within bounds (knowledge_recall)'
       where issue_key = 'knowledge_recall:' || s.seat and closed_at is null;
    end if;
    v_out := v_out || jsonb_build_object('seat', s.seat, 'questions', s.questions, 'recall_en', s.en, 'recall_ar', s.ar, 'raised', v_bad is not null);
  end loop;
  return jsonb_build_object('day', v_day, 'seats', v_out, 'raised', v_raised);
end $fn$;
revoke execute on function public.fn_it_engineer_knowledge_recall_exam() from public, anon, authenticated;
grant execute on function public.fn_it_engineer_knowledge_recall_exam() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('it_engineer.knowledge_recall', 'it_engineer', interval '1 day', 'fn_it_engineer_knowledge_recall_exam',
   'Daily, no model: every verified pack''s eval questions put to each seat''s own retriever (fn_reason_retrieve); recall@5 per seat recorded, a fall or a score under 0.35 is a finding.',
   'scripts/sql/every_seats_knowledge_is_examined_daily_by_retrieval_without_a_model.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

-- The retired model exam's unanswered rows: stamped, so the pass-rate duty does not read them as an ungradable exam.
update public.seat_knowledge_exam set graded_at = now(), grade_reason = 'retired unanswered: the model exam ended 24 Sep 2026'
 where graded_at is null;

select case when to_regclass('public.seat_knowledge_recall') is not null
             and (select enabled from public.seat_duty where duty = 'it_engineer.knowledge_recall')
             and (select enabled from public.seat_duty where duty = 'it_engineer.knowledge_pass_rate')
             and position('fn_reason_hold' in pg_get_functiondef('public.fn_it_engineer_knowledge_recall_exam()'::regprocedure)) = 0
            then 'PROBE OK' else 'PROBE FAILED' end as verdict;
