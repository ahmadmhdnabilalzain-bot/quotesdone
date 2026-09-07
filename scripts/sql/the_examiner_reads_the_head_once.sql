-- THE EXAMINER READS THE HEAD ONCE (7 Sep 2026). Follows an_employee_sits_its_certification_exam_from_its_own_knowledge.sql.
--
-- MEASURED: the first finance sitting produced no certification_exam_result row in twenty-five minutes.
-- fn_certification_exam_sit fetches the employee's 23,376-character head once (1.2 s) and then, for each
-- of the 40 questions, rebuilt that head's tsvector and ran word_similarity() over the whole 23 kB for
-- each of the four options — 160 trigram comparisons over a 23 kB text per question — and asked
-- kb_chunks for five rows with an ORDER BY id the planner had to satisfy after the index match
-- (754 ms against 20 ms without it, measured on the same query).
--
-- Three changes, none of which touch what the exam measures: the head's tsvector is built once per
-- sitting; the 0.02 trigram tiebreak applies only to records of 2,000 characters or less, where it can
-- actually discriminate; and the kb_chunks lookup drops its ORDER BY. The thresholds, the abstention
-- rule and the scoring formula are unchanged.
--
--   node scripts/apply_sql.mjs scripts/sql/the_examiner_reads_the_head_once.sql --apply --ddl

CREATE OR REPLACE FUNCTION public.fn_certification_exam_sit(p_agent text, p_certification text)
 RETURNS certification_exam_result
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c_min_support constant real := 0.25;   -- see the header: bounded rank, about three distinctive hits
  c_min_margin  constant real := 0.15;   -- relative: the winner must clear the runner-up by 15%
  v_dept text; v_pass numeric; v_head text; v_head_tsv tsvector;
  v_q record; v_best record; v_terms text; v_stem tsquery;
  v_chosen char(1); v_ok boolean;
  v_answers jsonb := '[]'::jsonb;
  v_areas jsonb; v_n int; v_correct int; v_score numeric;
  v_row public.certification_exam_result;
begin
  select a.department into v_dept from public.org_agents a where a.agent_key = p_agent and a.active;
  if v_dept is null then
    raise exception 'fn_certification_exam_sit: % is not an active employee', p_agent;
  end if;
  select rc.pass_mark_pct into v_pass from public.role_certification rc
   where rc.agent_key = p_agent and rc.certification = p_certification;
  if v_pass is null then
    raise exception 'fn_certification_exam_sit: % does not hold % in role_certification', p_agent, p_certification;
  end if;
  if not exists (select 1 from public.certification_exam_question q where q.certification = p_certification) then
    raise exception 'fn_certification_exam_sit: no question bank for %', p_certification;
  end if;

  v_head := coalesce(public.fn_agent_context(p_agent, 19500), '');
  -- 7 SEP 2026: the head is the same 23,000 characters for all 40 questions, so its search vector is
  -- built ONCE. Building it inside the loop cost a to_tsvector over 23 kB per question, and the
  -- trigram tiebreak below ran over the same 23 kB four times per question on top of it.
  v_head_tsv := to_tsvector('english', left(v_head, 900000));

  for v_q in
    select * from public.certification_exam_question q where q.certification = p_certification order by q.id
  loop
    v_terms := concat_ws(' ', v_q.question, v_q.option_a, v_q.option_b, v_q.option_c, v_q.option_d);
    v_stem  := plainto_tsquery('english', v_q.question);

    with ev as (
      select k.record_id, concat_ws(' ', k.title, k.content) as content
        from public.fn_ops_knowledge_search(v_dept, v_terms, 20) k
      union all
      select 'agent_knowledge:' || x.id, concat_ws(' ', x.topic, x.content)
        from (select ak.id, ak.topic, ak.content
                from public.agent_knowledge ak
               where ak.agent_key = p_agent
               order by ak.priority desc nulls last, ak.id
               limit 12) x
      union all
      select 'kb_chunks:' || y.id, concat_ws(' ', y.title, y.content)
        from (select c.id, c.title, c.content
                from public.kb_chunks c
               where v_stem is not null and c.fts @@ v_stem
               limit 5) y
    ), evt as (
      select ('head:' || p_agent)::text as record_id, v_head_tsv as tsv, v_head as content
      union all
      select record_id, to_tsvector('english', content), content from ev where content is not null
    ), opt(letter, txt) as (
      values ('A', v_q.option_a), ('B', v_q.option_b), ('C', v_q.option_c), ('D', v_q.option_d)
    ), oq as (
      select letter, txt, public.fn_exam_or_tsquery(txt, v_q.question) as q from opt
    ), sc as (
      select o.letter, e.record_id,
             -- normalisation 32 bounds ts_rank_cd into [0,1) as rank/(rank+1), so a 23,000-character
             -- head and a 400-character knowledge record sit on one scale and an absolute support
             -- threshold means the same thing against either.
             -- the 0.02 trigram tiebreak applies to short records only: over a 23 kB head it is both
             -- meaningless (every option matches somewhere) and the single most expensive term here.
             (ts_rank_cd(e.tsv, o.q, 32)
              + case when length(e.content) <= 2000 then 0.02 * word_similarity(o.txt, e.content) else 0 end)::real as s
        from oq o join evt e on true
       where o.q is not null
    ), per as (
      select distinct on (letter) letter, record_id, s from sc order by letter, s desc, record_id
    ), rk as (
      select letter, record_id, s, row_number() over (order by s desc, letter) as rn from per
    )
    select (select letter    from rk where rn = 1) as letter,
           (select record_id from rk where rn = 1) as record_id,
           coalesce((select s from rk where rn = 1), 0)::real as s1,
           coalesce((select s from rk where rn = 2), 0)::real as s2
      into v_best;

    if v_best.letter is null
       or v_best.s1 < c_min_support
       or (v_best.s1 - v_best.s2) < c_min_margin * v_best.s1 then
      v_chosen := null;                                  -- abstained: counts as wrong
    else
      v_chosen := v_best.letter;
    end if;
    v_ok := (v_chosen is not null and v_chosen = v_q.correct_option);

    v_answers := v_answers || jsonb_build_object(
      'question_id',     v_q.id,
      'syllabus_area',   v_q.syllabus_area,
      'chosen',          v_chosen,
      'key',             v_q.correct_option,
      'correct',         v_ok,
      'abstained',       (v_chosen is null),
      'score',           round(v_best.s1::numeric, 4),
      'margin',          round((v_best.s1 - v_best.s2)::numeric, 4),
      'evidence_record', case when v_chosen is null then null else v_best.record_id end);
  end loop;

  v_n := jsonb_array_length(v_answers);
  select count(*) filter (where (e->>'correct')::boolean) into v_correct
    from jsonb_array_elements(v_answers) e;
  v_score := round(100.0 * v_correct / greatest(v_n,1), 2);

  select coalesce(jsonb_agg(jsonb_build_object('syllabus_area', area, 'asked', asked, 'correct', ok)
                            order by (ok::numeric / asked), area), '[]'::jsonb)
    into v_areas
    from (select coalesce(e->>'syllabus_area','(unstated)') as area,
                 count(*) as asked,
                 count(*) filter (where (e->>'correct')::boolean) as ok
            from jsonb_array_elements(v_answers) e group by 1) t;

  insert into public.certification_exam_result
    (agent_key, certification, questions, correct, score_pct, pass_mark_pct, passed, weakest_areas, answers)
  values
    (p_agent, p_certification, v_n, v_correct, v_score, v_pass, v_score >= v_pass, v_areas, v_answers)
  returning * into v_row;

  return v_row;
end $function$;

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/the_examiner_reads_the_head_once.sql',
       evidence = 'the head is vectorised once per sitting; the trigram tiebreak is bounded (7 Sep 2026)'
 where schema_name = 'public' and routine_name = 'fn_certification_exam_sit';
