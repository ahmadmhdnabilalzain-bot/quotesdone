-- AN ARABIC QUESTION IS RANKED IN THE SPACE THAT READS ARABIC (6 Oct 2026, it_engineer with sales_engineer; knowledge).
--
-- MEASURED (live, read-only, 6 Oct 2026). fn_reason_retrieve_ml over the 205 market packs + interior_fitout, every eval
-- question asked through the same call think() makes (multilingual vector + gte-small vector, k 6, first five rows):
-- Arabic mean recall@5 0.672 per (pack, seat) pair, 134 of 412 pairs at 0; English 0.993, 2 tax_advisory pairs at 0.
-- The prefixes were not the cause ('query: ' / 'passage: ' are applied on both sides; a stored vector re-embedded from
-- its row text agrees to cosine 0.998). The index was not the cause (exact cosine over the same rows ranks the same).
-- Three causes, each measured on its own:
--   1. Every '<id>@ar' pack row was embedded from an ENGLISH title over its Arabic body (verified_packs.mjs used
--      e.topic for both rows). The 205 market packs share one Arabic body template, so the trade's name, the line that
--      tells them apart, was in the language the question was not. Multilingual space alone, pack rows only: Arabic
--      0.750 -> 0.964 with an Arabic title (knowledge/packs/*.market.json topic_ar, written from each pack's label_ar).
--      The same English-titled Arabic twin was what pushed tax_advisory:uae-market-products out of the English top 5
--      (brands AND brands@ar both took a slot); with the Arabic title English reads 0.998, 0 pairs below 0.35.
--   2. Optional Arabic marks (tashkeel, superscript alef, tatweel) reached the model, so one word in two spellings
--      became different pieces: 0.959 -> 0.974 with the marks taken out on both sides (_shared/ml_embed_recipe.ts
--      mlClean). Letter folding as well (fn_ar_norm's alef / yeh / teh marbuta fold) LOWERED it to 0.934 and is not used.
--   3. The fusion gave gte-small, an English-only model, a say on Arabic questions: fused 0.891 against 0.964 for the
--      multilingual space alone, staged. think() no longer sends a gte vector for a question whose letters are mostly
--      Arabic (gteReads, the script, never a word); English keeps the fusion (0.998 fused, 0.990 alone).
-- Staged, all three together (aborted transactions, the new vectors written over the old inside each, nothing kept):
--   Arabic 0.672 -> 0.973, pairs at 0 134 -> 10; English 0.993 -> 0.998, pairs at 0 2 -> 0.
-- NOT FIXED, and said so: 10 Arabic pairs (ev_charging, industrial_pumps, it_services, office_equipment,
-- protective_packaging; each one question, both seats) still miss. Each expected row ranks 5th-18th behind a sibling
-- entry or the same entry kind of a neighbouring trade. Six more variants were measured and none clears them without
-- losing others: centring, a hub penalty, averaging the twins, a title vector, a passage-side query, and a trade-label
-- prior. It is the ceiling of the free multilingual-e5-small; the floor and the expected answers are unchanged.
--
-- THIS FILE.
--   a. The daily exam asks an Arabic question exactly as think() now does: no gte vector (fn_it_engineer_knowledge_
--      recall_exam; every other line is the body of the_knowledge_exam_names_no_table_after_its_own_record.sql).
--   b. Every multilingual vector whose row text carries a mark is deleted, so the queue (fn_ml_embed_claim, the runner
--      backfill and embed_ml's tick) re-embeds it under the new recipe: 3,162 rows on 6 Oct 2026 (sales 2,254, faq 150,
--      support 157, ceo 141, ops 9, the rest the seats' tables and case memory; kb_chunks 0). The read switch is not
--      touched: priority_complete_at is set once and fn_ml_read_space reads only it.
--   c. Every exam question whose text carries a mark loses its embedding_ml, so it is re-made under the same recipe;
--      until then the exam raises knowledge_recall:no_ml_vectors naming the command, as designed.
-- AT MERGE (the release operator): apply this file; node scripts/kb/load_verified_packs.mjs --apply (the 615 Arabic
-- titles); deploy embed_ml and every function that bundles think.ts; run the ml-embed-backfill workflow;
-- node scripts/kb/load_knowledge_eval_questions.mjs --ml.
-- CREATE OR REPLACE keeps the exam routine's grants (service_role only). No begin/commit.
-- prevented by: scripts/checks/an_arabic_question_is_ranked_in_the_space_that_reads_arabic.test.mjs

create or replace function public.fn_it_engineer_knowledge_recall_exam()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
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
           (select count(distinct regexp_replace(x->>'id', '@ar$', ''))
              from jsonb_array_elements(public.fn_reason_retrieve_ml(q.seat, q.embedding_ml, case when q.lang = 'ar' then null else q.embedding end, 6)) with ordinality t(x, n)
             where n <= 5 and regexp_replace(x->>'id', '@ar$', '') = any(q.expected))::numeric
           / (select count(distinct e) from unnest(q.expected) e)
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
end $fn$;

delete from public.knowledge_vector_ml v
 using public.v_knowledge_ml_source s
 where s.src = v.src and s.row_id = v.row_id and s.src <> 'kb_chunks'
   and coalesce(s.title, '') || coalesce(s.body, '') ~ '[\u064B-\u065F\u0670\u0640]';

update public.seat_knowledge_eval_question set embedding_ml = null
 where embedding_ml is not null and question ~ '[\u064B-\u065F\u0670\u0640]';

select case when position('case when q.lang = ''ar'' then null' in pg_get_functiondef('public.fn_it_engineer_knowledge_recall_exam()'::regprocedure)) > 0
            then 'PROBE OK' else 'PROBE FAILED: the exam still sends gte-small an Arabic question' end as verdict;
