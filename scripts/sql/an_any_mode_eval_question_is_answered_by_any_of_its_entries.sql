-- AN 'ANY' EVAL QUESTION IS ANSWERED BY ANY ONE OF ITS ENTRIES, in the daily exam as in the eval. Seat: it_engineer, 27 Oct 2026.
--
-- A pack question with expected_mode 'any' (knowledge/packs/*.json, scripts/kb/verified_packs.mjs) names two or more entries,
-- each of which answers it, with a why. scripts/eval/knowledge_pack_eval.mjs scores it min(1, hits). The daily no-model exam,
-- public.fn_it_engineer_knowledge_recall_exam(), divided hits by the number of entries named, because
-- public.seat_knowledge_eval_question never carried the mode (scripts/kb/load_knowledge_eval_questions.mjs dropped it).
-- Measured on main 27 Oct 2026: 14 such questions, each scored "all required" by the exam; this PR adds 13 more
-- (market packs whose base-pack entry answers the question as asked). The two instruments now apply one rule.
--
-- The routine below is the live body (pg_get_functiondef, md5 b470cf9f5d9e47166d0585140196750d, equal line for line to
-- a_seats_own_pack_fills_half_of_every_retrieval.sql, its canonical file) with ONLY the recall expression changed.
-- CREATE OR REPLACE keeps its ACL; the revoke restates it for the one signature (no overloads: pg_proc lists one).
-- No transaction control in this file (a replaying check would commit it: a-check-that-replays-sql-can-commit-it).
-- Probe: an_any_mode_eval_question_is_answered_by_any_of_its_entries_probe.sql (raises on every path).
-- prevented by: scripts/checks/an_any_mode_eval_question_is_answered_by_any_of_its_entries.test.mjs

alter table public.seat_knowledge_eval_question add column if not exists expected_any boolean not null default false;
comment on column public.seat_knowledge_eval_question.expected_any is
  'true when the pack question says expected_mode any: any one entry of expected answers it (loaded by scripts/kb/load_knowledge_eval_questions.mjs)';

CREATE OR REPLACE FUNCTION public.fn_it_engineer_knowledge_recall_exam()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_day date := (now() at time zone 'Asia/Dubai')::date; s record; q record; p public.seat_knowledge_recall;
  v_floor numeric; v_bad text; v_out jsonb := '[]'::jsonb; v_raised int := 0; v_scored int := 0; v_left int;
  v_missing int; v_due int; v_t timestamptz := clock_timestamp();
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

  -- Nothing is scored while any question lacks its ml vector. Only a question already loaded at now() can be owed
  -- one: a question loaded later did not exist at that instant (what a replay at a past instant reads), so it is
  -- not missing anything then. Live, every question was loaded in the past, so this counts every missing question.
  select count(*), count(*) filter (where loaded_at <= now()) into v_missing, v_due
    from public.seat_knowledge_eval_question where embedding_ml is null;
  if v_missing > 0 then
    if v_due > 0 then
      perform public.fn_it_engineer_finding_upsert('knowledge_recall:no_ml_vectors',
        v_due || ' exam questions have no multilingual vector, so the bilingual path the seats read is not being examined',
        'public.seat_knowledge_eval_question.embedding_ml', 'agent_facing', v_due,
        jsonb_build_object('owner_seat', 'it_engineer', 'missing', v_due),
        '{}'::text[], array['run node scripts/kb/load_knowledge_eval_questions.mjs --ml'], 'it_engineer');
    end if;
    return jsonb_build_object('day', v_day, 'missing_ml', v_missing, 'raised', (v_due > 0)::int);
  end if;
  update public.it_engineer_finding set closed_at = now(), close_note = 'every question has its ml vector (knowledge_recall)'
   where issue_key = 'knowledge_recall:no_ml_vectors' and closed_at is null;

  if exists (select 1 from public.seat_knowledge_recall where day = v_day and path = 'ml') then
    return jsonb_build_object('day', v_day, 'done', true);
  end if;

  -- one time-bound beat: score today's unscored questions until 4 s have passed (67 ms a call warm, measured)
  for q in select * from public.seat_knowledge_eval_question eq
            where not exists (select 1 from public.seat_knowledge_recall_answer a where a.day = v_day and a.question_id = eq.id)
            order by eq.id limit 150
  loop
    exit when clock_timestamp() - v_t > interval '4 seconds';
    insert into public.seat_knowledge_recall_answer (day, question_id, seat, lang, recall)
    select v_day, q.id, q.seat, q.lang,
           -- expected_any: ANY one of the question's entries answers it (knowledge_pack_eval.mjs's own rule); else every one is needed
           (select case when q.expected_any then least(count(distinct regexp_replace(x->>'id', '@ar$', '')), 1)::numeric
                        else count(distinct regexp_replace(x->>'id', '@ar$', ''))::numeric / (select count(distinct e) from unnest(q.expected) e) end
              from jsonb_array_elements(public.fn_reason_retrieve_ml(q.seat, q.embedding_ml, case when q.lang = 'ar' then null else q.embedding end, 6, p_audience => 'internal')) with ordinality t(x, n)
             where n <= 5 and regexp_replace(x->>'id', '@ar$', '') = any(q.expected))
    on conflict do nothing;
    v_scored := v_scored + 1;
  end loop;
  select count(*) into v_left from public.seat_knowledge_eval_question eq
   where not exists (select 1 from public.seat_knowledge_recall_answer a where a.day = v_day and a.question_id = eq.id);
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
end $function$;

revoke execute on function public.fn_it_engineer_knowledge_recall_exam() from public, anon, authenticated;
