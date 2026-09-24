-- THE KNOWLEDGE EXAM IS SCORED IN SLICES THAT FIT THE DUTY TICK (24 Sep 2026, it_engineer).
--
-- MEASURED. fn_it_engineer_knowledge_recall_exam (every_seats_knowledge_is_examined_daily_by_retrieval_without_a_model.sql)
-- scored all 2,354 loaded questions in one call: 39.8 s, timed on production in an aborted block. It runs inside
-- fn_seat_duties_tick, which resilience_ping calls through PostgREST under the authenticator's 8 s statement_timeout.
-- The exam never had a last_ok_at, so it was the most overdue duty and went first on every tick. Each tick then
-- cancelled after about 8.3 s (resilience_step.seatDuties last_ms 8274) and rolled back every duty in it. From
-- 10:16Z no seat duty ran: the step's last_ok_at froze at 10:16:35, and customer_support.disputes went overdue.
--
-- FIX. Each call scores at most 150 of today's unscored questions (about 2.5 s at the measured 17 ms per
-- question) into seat_knowledge_recall_answer. When none is left, it aggregates per seat and raises exactly as
-- before. The duty now runs every 15 minutes. After a day is aggregated, a call is one existence check.
-- A full day takes about 16 calls, roughly four hours after Dubai midnight. Nothing about the score changes.
-- No cron job is added (founder, 7 Sep: no new scheduled jobs).

create table if not exists public.seat_knowledge_recall_answer (
  day date not null,
  question_id bigint not null,
  seat text not null,
  lang text not null,
  recall numeric not null,
  primary key (day, question_id)
);
alter table public.seat_knowledge_recall_answer enable row level security;
drop policy if exists seat_knowledge_recall_answer_service_role_only on public.seat_knowledge_recall_answer;
create policy seat_knowledge_recall_answer_service_role_only on public.seat_knowledge_recall_answer as permissive for all to public using (false) with check (false);
revoke all on public.seat_knowledge_recall_answer from anon, authenticated;

create or replace function public.fn_it_engineer_knowledge_recall_exam()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_day date := (now() at time zone 'Asia/Dubai')::date; s record; p public.seat_knowledge_recall; v_bad text; v_out jsonb := '[]'::jsonb;
  v_raised int := 0; v_scored int; v_left int;
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

  -- today already aggregated: nothing to do
  if exists (select 1 from public.seat_knowledge_recall where day = v_day) then
    return jsonb_build_object('day', v_day, 'done', true);
  end if;

  -- one slice of today's unscored questions
  insert into public.seat_knowledge_recall_answer (day, question_id, seat, lang, recall)
  select v_day, q.id, q.seat, q.lang,
         (select count(distinct regexp_replace(x->>'id', '@ar$', ''))
            from jsonb_array_elements(public.fn_reason_retrieve(q.seat, q.embedding, 6)) with ordinality t(x, n)
           where n <= 5 and regexp_replace(x->>'id', '@ar$', '') = any(q.expected))::numeric
         / (select count(distinct e) from unnest(q.expected) e)
    from (select * from public.seat_knowledge_eval_question q
           where not exists (select 1 from public.seat_knowledge_recall_answer a where a.day = v_day and a.question_id = q.id)
           order by q.id limit 150) q
  on conflict do nothing;
  get diagnostics v_scored = row_count;
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
  delete from public.seat_knowledge_recall_answer where day < v_day - 7;
  return jsonb_build_object('day', v_day, 'seats', v_out, 'raised', v_raised);
end $fn$;
revoke execute on function public.fn_it_engineer_knowledge_recall_exam() from public, anon, authenticated;
grant execute on function public.fn_it_engineer_knowledge_recall_exam() to service_role;

update public.seat_duty set every = interval '15 minutes',
       what = 'No model: every verified pack''s eval questions put to each seat''s own retriever (fn_reason_retrieve), 150 a beat until the day is scored; recall@5 per seat recorded, a fall or a score under 0.35 is a finding.',
       owner_file = 'scripts/sql/the_knowledge_exam_is_scored_in_slices_that_fit_the_duty_tick.sql'
 where duty = 'it_engineer.knowledge_recall';

-- Probe: one slice fits well inside the 8 s the tick has, and scores rows.
do $$ declare t timestamptz := clock_timestamp(); r jsonb; begin
  r := public.fn_it_engineer_knowledge_recall_exam();
  if clock_timestamp() - t > interval '6 seconds' then raise exception 'slice took %', clock_timestamp() - t; end if;
end $$;
select case when (select every from public.seat_duty where duty = 'it_engineer.knowledge_recall') = interval '15 minutes'
             and (exists (select 1 from public.seat_knowledge_recall_answer) or exists (select 1 from public.seat_knowledge_recall))
            then 'PROBE OK' else 'PROBE FAILED' end as verdict;
